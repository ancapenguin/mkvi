/// The call-start ladder: the rungs, and the one that was removed.
///
/// **No hardware.** Every `getUserMedia` answer is scripted in `FakeCapture`, so
/// these tests exercise the Dart ladder only — the rungs the controller asks for,
/// what it does with what comes back, and what it tells the user.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/media/media.dart';

import 'support/media_fakes.dart';

void main() {
  group('a video call the camera cannot serve', () {
    // Pins ChatCallWorkspace.tsx:317 — the third rung `{audio: true, video: false}`
    // and its warning "Kamera bulunamadı; arama yalnızca sesli başlayacak." A user
    // who pressed the video button got a silent audio call and one line of text
    // that said so. This is the port's answer: report, do not downgrade.
    test('reports instead of degrading to audio', () async {
      // No camera and no microphone enumerated, and the OS hands back nothing for
      // either rung. Note that nothing *throws* here: a missing device resolves
      // with an empty track list
      // (`common/cpp/src/flutter_media_stream.cc:382-393`), so the ladder has to
      // read what it got rather than rely on a `catch`.
      final MediaHarness harness = MediaHarness(
        devices: const MediaDeviceSnapshot(),
      );
      addTearDown(harness.dispose);
      await harness.open();
      harness.capture.script.addAll(<Object?>[
        CapturedMedia(const <MediaTrackHandle>[]),
        CapturedMedia(const <MediaTrackHandle>[]),
      ]);

      final MediaCallStarted result = await harness.controller.startCall(
        video: true,
      );

      expect(result, isA<MediaCallFailed>());
      final MediaCallFailed failed = result as MediaCallFailed;
      expect(failed.fault.kind, MediaFaultKind.deviceNotFound);
      expect(failed.message, MediaTexts.cameraNotFound);

      // The claim being pinned: the ladder asked for a camera twice and stopped.
      // A third request for `{audio: true, video: false}` is the deleted rung.
      expect(harness.capture.requests, <Matcher>[
        isA<MediaCaptureRequest>()
            .having((MediaCaptureRequest r) => r.audio, 'audio', isTrue)
            .having((MediaCaptureRequest r) => r.video, 'video', isTrue),
        isA<MediaCaptureRequest>()
            .having((MediaCaptureRequest r) => r.audio, 'audio', isFalse)
            .having((MediaCaptureRequest r) => r.video, 'video', isTrue),
      ]);
      expect(
        harness.capture.requests.any(
          (MediaCaptureRequest r) => r.audio && !r.video,
        ),
        isFalse,
        reason: 'the microphone-only rung must not exist',
      );
    });

    test('publishes nothing at all when it reports', () async {
      final MediaHarness harness = MediaHarness(
        devices: const MediaDeviceSnapshot(),
      );
      addTearDown(harness.dispose);
      await harness.open();
      harness.capture.script.addAll(<Object?>[
        CapturedMedia(const <MediaTrackHandle>[]),
        CapturedMedia(const <MediaTrackHandle>[]),
      ]);

      await harness.controller.startCall(video: true);

      expect(harness.registry.audio.calls, isEmpty);
      expect(harness.registry.camera.calls, isEmpty);
      expect(harness.controller.state.hasMedia, isFalse);
      expect(harness.controller.state.notice, isNull);
    });

    test('a thrown error on the camera rung is reported too', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      harness.capture.script.addAll(<Object?>[
        'Unable to getUserMedia: NotReadableError: Could not start video source',
        'Unable to getUserMedia: TrackStartError',
      ]);

      final MediaCallFailed failed =
          await harness.controller.startCall(video: true) as MediaCallFailed;

      expect(failed.fault.kind, MediaFaultKind.deviceNotReadable);
      expect(failed.message, MediaTexts.cameraNotReadable);
    });
  });

  group('a microphone that will not open during a video call', () {
    // Rung 2 of the ladder, and the one degradation that is still allowed
    // because its effect is visible: the video the user asked for is still going
    // out. Pins ChatCallWorkspace.tsx:316, warning text byte-identical.
    test('degrades to video-only and says so', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      // Rung 1 asks for both; the plugin raises the raw Dart `String` it really
      // raises (`mediadevices_impl.dart:48-50`).
      harness.capture.script.add('Unable to getUserMedia: No available device');
      // Rung 2 asks for the camera alone, and it works.
      final FakeTrack camera = FakeTrack(
        kind: 'video',
        label: defaultCameraLabel,
      );
      harness.capture.script.add(CapturedMedia(<MediaTrackHandle>[camera]));

      final MediaCallStarted result = await harness.controller.startCall(
        video: true,
      );

      expect(result, isA<MediaCallLive>());
      final MediaCallLive live = result as MediaCallLive;
      expect(live.video, isTrue, reason: 'the camera the user asked for is on');
      expect(live.audio, isFalse);
      expect(live.notice, MediaTexts.microphoneMissingInVideoCall);

      // Said so in the state as well, so a UI that only renders the notice box
      // still shows it.
      expect(harness.controller.state.notice, live.notice);
      expect(harness.controller.state.cameraLive, isTrue);
      expect(harness.controller.state.microphoneLive, isFalse);
      // And the video really is on the camera sender.
      expect(harness.registry.camera.calls, <MediaTrackHandle?>[camera]);
      expect(harness.registry.audio.calls, isEmpty);
    });

    test('a mic-only failure is not confused with a camera failure', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      harness.capture.script.addAll(<Object?>[
        'Unable to getUserMedia: No specified device found',
        CapturedMedia(<MediaTrackHandle>[
          FakeTrack(kind: 'video', label: defaultCameraLabel),
        ]),
      ]);

      final MediaCallLive live =
          await harness.controller.startCall(video: true) as MediaCallLive;

      expect(live.notice, isNotNull);
      expect(live.notice, isNot(contains('video')));
    });
  });

  group('a permission refusal', () {
    // ChatCallWorkspace.tsx:330-331 named one sentence for a combined refusal.
    // A combined `getUserMedia({audio: true, video: true})` cannot say which
    // device the OS refused, so the call-level failure uses the combined advice.
    test('is reported with the combined Turkish sentence', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      harness.capture.script.addAll(<Object?>[
        'Unable to getUserMedia: Permission denied',
        'Unable to getUserMedia: Permission denied',
      ]);

      final MediaCallFailed failed =
          await harness.controller.startCall(video: true) as MediaCallFailed;

      expect(failed.fault.kind, MediaFaultKind.permissionDenied);
      expect(failed.message, MediaTexts.callPermissionDenied);
      expect(failed.message, contains("MKVI'ye"));
    });

    test('is reported on the microphone alone for an audio call', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      harness.capture.script.add('Unable to getUserMedia: Permission denied');

      final MediaCallFailed failed =
          await harness.controller.startCall(video: false) as MediaCallFailed;

      expect(failed.fault, isA<MediaFault>());
      expect(failed.fault.kind, MediaFaultKind.permissionDenied);
      expect(failed.fault.source, MediaSourceKind.microphone);
      expect(failed.fault.message, MediaTexts.microphonePermissionDenied);
    });
  });

  group('a device the OS simply does not have', () {
    // `GetUserVideo` returns early with no track and no error
    // (`common/cpp/src/flutter_media_stream.cc:382-393`) and `GetUserMedia` then
    // reports success with an empty `videoTracks` array (`:62-77`). The ladder has
    // to *inspect* what came back, because nothing throws.
    test('a resolved getUserMedia with no camera track is a failure', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      final FakeTrack mic = FakeTrack(kind: 'audio', label: defaultMicLabel);
      harness.capture.script.addAll(<Object?>[
        // Rung 1: the microphone opened, the camera produced nothing. The OS
        // reported success.
        CapturedMedia(<MediaTrackHandle>[mic]),
        // Rung 2: the camera alone, and it also produces nothing.
        CapturedMedia(const <MediaTrackHandle>[]),
      ]);

      final MediaCallStarted result = await harness.controller.startCall(
        video: true,
      );

      expect(result, isA<MediaCallFailed>());
      // The microphone the OS did hand back must not be left running, which is
      // exactly the leak a "resolve is a success" assumption produces.
      expect(mic.stopCount, greaterThanOrEqualTo(1));
      expect(harness.controller.state.hasMedia, isFalse);
    });

    test(
      'an enumerated-but-silent camera is "not readable", not "not found"',
      () async {
        // A camera that is plugged in and produces nothing is a different sentence
        // with a different fix than a camera that is not there.
        final MediaHarness harness = MediaHarness();
        addTearDown(harness.dispose);
        await harness.open();

        harness.capture.script.addAll(<Object?>[
          CapturedMedia(<MediaTrackHandle>[
            FakeTrack(kind: 'audio', label: defaultMicLabel),
          ]),
          CapturedMedia(const <MediaTrackHandle>[]),
        ]);

        final MediaCallFailed failed =
            await harness.controller.startCall(video: true) as MediaCallFailed;

        expect(failed.fault.kind, MediaFaultKind.deviceNotReadable);
        expect(failed.message, MediaTexts.cameraNotReadable);
      },
    );

    test('nothing enumerated at all is "not found"', () async {
      final MediaHarness harness = MediaHarness(
        devices: const MediaDeviceSnapshot(),
      );
      addTearDown(harness.dispose);
      await harness.open();

      harness.capture.script.addAll(<Object?>[
        CapturedMedia(const <MediaTrackHandle>[]),
        CapturedMedia(const <MediaTrackHandle>[]),
      ]);

      final MediaCallFailed failed =
          await harness.controller.startCall(video: true) as MediaCallFailed;

      expect(failed.fault.kind, MediaFaultKind.deviceNotFound);
      expect(failed.message, MediaTexts.cameraNotFound);
    });
  });

  group('a stale device id', () {
    // The native layer accepts an unknown id and keeps the previous device
    // (`common/cpp/src/flutter_media_stream.cc:219-228`, `:267-269`), so the
    // controller refuses it before it gets there.
    test('is refused rather than silently substituted', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      final MediaCallFailed failed =
          await harness.controller.startCall(
                video: true,
                cameraDeviceId: 'cam-that-was-unplugged',
              )
              as MediaCallFailed;

      expect(failed.fault.kind, MediaFaultKind.deviceNotFound);
      expect(
        harness.capture.requests,
        isEmpty,
        reason: 'nothing may be asked of the OS for a device it does not have',
      );
    });

    test('a known id is passed through to the constraint', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      final MediaCallLive live =
          await harness.controller.startCall(
                video: true,
                cameraDeviceId: 'cam-1',
                microphoneDeviceId: 'mic-1',
              )
              as MediaCallLive;

      expect(live.video, isTrue);
      expect(harness.capture.requests.single.cameraDeviceId, 'cam-1');
      expect(harness.capture.requests.single.microphoneDeviceId, 'mic-1');
      // The device ids it reports are the ones it proved against the device list.
      expect(harness.controller.state.cameraDeviceId, 'cam-1');
      expect(harness.controller.state.microphoneDeviceId, 'mic-1');
    });
  });

  group('a call that works', () {
    test('publishes both senders with one replaceTrack each', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      final MediaCallLive live =
          await harness.controller.startCall(video: true) as MediaCallLive;

      expect(live.audio, isTrue);
      expect(live.video, isTrue);
      expect(live.notice, isNull);
      expect(harness.registry.audio.calls.length, 1);
      expect(harness.registry.camera.calls.length, 1);
      expect(harness.registry.screen.calls, isEmpty);
      expect(harness.controller.state.hasMedia, isTrue);
      expect(harness.controller.state.fault, isNull);
    });

    test('a voice call opens the audio sender only', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      final MediaCallLive live =
          await harness.controller.startCall(video: false) as MediaCallLive;

      expect(live.audio, isTrue);
      expect(live.video, isFalse);
      expect(harness.registry.camera.calls, isEmpty);
      expect(harness.capture.requests.single.video, isFalse);
    });

    test('nothing is captured before open()', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);

      final MediaCallFailed failed =
          await harness.controller.startCall(video: true) as MediaCallFailed;

      expect(failed.fault.kind, MediaFaultKind.unavailable);
      expect(failed.message, MediaTexts.connectionNotReady);
      expect(harness.capture.requests, isEmpty);
    });
  });

  group('the transceivers', () {
    // peer-transport.ts:76-80. Order and identity are the contract: the screen
    // sender must never stand in for the camera one.
    test('are created once, in order, and renegotiate exactly once', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);

      await harness.open();

      expect(harness.registry.openCount, 1);
      expect(harness.registry.slots, <String>['audio', 'camera', 'screen']);
      expect(harness.controller.negotiationCount, 1);

      // A second open is a no-op, so the transceivers cannot be made twice.
      await harness.controller.open();
      expect(harness.registry.openCount, 1);
      expect(harness.registry.slots.length, 3);
      expect(harness.controller.negotiationCount, 1);
    });

    test('a failure to create them is reported, not thrown', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      harness.registry.failOpen = 'addTransceiver refused';

      final MediaFailed failed = await harness.controller.open() as MediaFailed;

      expect(failed.fault.kind, MediaFaultKind.unavailable);
      expect(failed.message, MediaTexts.connectionNotReady);
      expect(harness.controller.state.fault, failed.fault);
    });
  });
}
