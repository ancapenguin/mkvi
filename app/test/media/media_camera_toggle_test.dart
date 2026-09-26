/// Mid-call camera work: attach, detach, switch, mute.
///
/// **No hardware.** Every `getUserMedia` answer is scripted; every `replaceTrack` is
/// recorded by `FakeSender`. What is under test is the `replaceTrack`-only
/// discipline and the track ledger, not the capture backend.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/media/media.dart';

import 'support/media_fakes.dart';

void main() {
  group('turning the camera on during a voice call', () {
    // The pre-negotiated `sendrecv` camera transceiver
    // (`peer-transport.ts:78-80`) is what makes this possible without an offer.
    // The call machine's `upgradeToVideo` has promised a frameless upgrade, and
    // this is the Dart side of that promise.
    test('attaches with one replaceTrack and no renegotiation', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);

      final int afterOpen = harness.controller.negotiationCount;
      final int offersBefore = harness.registry.negotiations.length;
      expect(afterOpen, 1, reason: 'open() is the one negotiation');

      final MediaSucceeded outcome =
          await harness.controller.enableCamera() as MediaSucceeded;

      expect(outcome.notice, isNull);
      expect(harness.controller.state.cameraLive, isTrue);
      // The camera sender was written exactly once, with a real track.
      expect(harness.registry.camera.calls.length, 1);
      expect(harness.registry.camera.calls.single, isNotNull);
      // Nothing else was touched, and in particular no offer was produced: the
      // call machine must emit this upgrade with no `SendFrame` beside it.
      expect(
        harness.registry.audio.calls.length,
        1,
        reason: 'the microphone was published by startCall and not again',
      );
      expect(harness.registry.screen.calls, isEmpty);
      expect(harness.controller.negotiationCount, afterOpen);
      expect(harness.registry.negotiations.length, offersBefore);
      expect(
        harness.phaseTrail,
        isEmpty,
        reason: 'no screen share was started, so no watchdog ran',
      );
    });

    test('a second enable does not re-open the camera', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);
      await harness.controller.enableCamera();
      final FakeTrack first = harness.createdTracks.last;

      // The OS is asked for a second camera, and the first one is stopped only
      // after the new track is in place, so a failure here would leave the old one
      // running. A *successful* re-enable is a fresh capture, which is correct:
      // `Helper.switchCamera` cannot be used on Windows, so re-capturing is the
      // only way to honour a device id.
      await harness.controller.enableCamera();

      expect(harness.registry.camera.calls.length, 2);
      expect(first.stopCount, 1, reason: 'the replaced track is stopped');
      expect(harness.orphanedTracks, isEmpty);
    });
  });

  group('turning the camera off', () {
    // ChatCallWorkspace.tsx:397-421 removed the track from the stream and stopped
    // it, then published. When the publish failed the camera was already stopped
    // and the call was left with no camera and no error; when it succeeded the
    // track was stopped but nothing guaranteed it on every path. `replaceTrack(null)`
    // plus a stop in the same step, with a rollback if the detach fails, is the
    // port's answer.
    test('detaches with replaceTrack(null) and stops the track', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      final FakeTrack camera = harness.createdTracks.firstWhere(
        (FakeTrack track) => track.kind == 'video',
      );

      final MediaSucceeded outcome =
          await harness.controller.disableCamera() as MediaSucceeded;

      expect(outcome.notice, isNull);
      expect(harness.registry.camera.calls.last, isNull);
      expect(harness.registry.camera.detaches.length, 1);
      expect(camera.stopCount, 1);
      expect(harness.controller.state.cameraLive, isFalse);
      expect(harness.controller.state.cameraDeviceId, isNull);
      expect(harness.orphanedTracks, isEmpty);
    });

    test('leaves the microphone alone', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      final int audioCalls = harness.registry.audio.calls.length;

      await harness.controller.disableCamera();

      expect(harness.registry.audio.calls.length, audioCalls);
      expect(harness.controller.state.microphoneLive, isTrue);
    });

    test('is a no-op when there is no camera', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);

      final MediaSucceeded outcome =
          await harness.controller.disableCamera() as MediaSucceeded;

      expect(outcome.notice, isNull);
      expect(
        harness.registry.camera.calls,
        isEmpty,
        reason: 'nothing to detach, so nothing is written',
      );
    });

    test('a failed detach is reported and the camera is still stopped', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      final FakeTrack camera = harness.createdTracks.firstWhere(
        (FakeTrack track) => track.kind == 'video',
      );
      harness.registry.camera.failNextReplace = 'sender is closed';

      final MediaFailed failed =
          await harness.controller.disableCamera() as MediaFailed;

      expect(failed.fault.kind, MediaFaultKind.unavailable);
      // The rollback restored the previous track, so the rollback's own stop is
      // skipped and the track is still held — the state says so, rather than
      // claiming a camera that is still on is off.
      expect(harness.controller.state.cameraLive, isTrue);
      expect(
        harness.registry.camera.calls.last,
        isNotNull,
        reason: 'the previous track was put back',
      );
      expect(
        camera.stopCount,
        0,
        reason: 'a track that is still attached must not be stopped',
      );
      expect(
        harness.orphanedTracks,
        isEmpty,
        reason:
            'and nothing is orphaned by the failed detach, because the '
            'rollback put the old track back',
      );
    });
  });

  group('switching the camera', () {
    // `Helper.switchCamera` drops its `deviceId` off the web branch
    // (`flutter_webrtc/lib/src/helper.dart:65-70`) and its handler answers
    // `NotImplemented()` (`common/cpp/src/flutter_media_stream.cc:630-634`), so on
    // Windows it cannot honour a device id at all. The port re-captures.
    test('re-captures the named device and replaces the track', () async {
      final MediaHarness harness = MediaHarness(
        devices: fakeDeviceList(
          cameras: <MediaDevice>[
            fakeCamera(),
            fakeCamera(id: 'cam-2', label: 'Kamera (USB Webcam)'),
          ],
        ),
      );
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      final FakeTrack first = harness.createdTracks.firstWhere(
        (FakeTrack track) => track.kind == 'video',
      );

      final MediaSucceeded outcome =
          await harness.controller.switchCamera('cam-2') as MediaSucceeded;

      expect(outcome.notice, isNull);
      expect(harness.capture.requests.last.cameraDeviceId, 'cam-2');
      expect(harness.registry.camera.calls.last, isNotNull);
      expect(harness.controller.state.cameraDeviceId, 'cam-2');
      expect(first.stopCount, 1);
      expect(harness.orphanedTracks, isEmpty);
    });

    test(
      'a failed re-capture keeps the old camera and stops the new attempt',
      () async {
        final MediaHarness harness = MediaHarness(
          devices: fakeDeviceList(
            cameras: <MediaDevice>[
              fakeCamera(),
              fakeCamera(id: 'cam-2', label: 'Kamera (USB Webcam)'),
            ],
          ),
        );
        addTearDown(harness.dispose);
        await harness.open();
        await harness.controller.startCall(video: true);
        final FakeTrack first = harness.createdTracks.firstWhere(
          (FakeTrack track) => track.kind == 'video',
        );
        harness.capture.script.add(
          'Unable to getUserMedia: Device is already in use',
        );

        final MediaFailed failed =
            await harness.controller.switchCamera('cam-2') as MediaFailed;

        expect(failed.fault.kind, MediaFaultKind.deviceBusy);
        expect(failed.message, MediaTexts.cameraBusy);
        expect(harness.controller.state.cameraDeviceId, 'cam-1');
        expect(first.isLive, isTrue, reason: 'the working camera is still on');
      },
    );

    test('an unknown device id is refused before the OS is asked', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      final int before = harness.capture.requests.length;

      final MediaFailed failed =
          await harness.controller.switchCamera('cam-9') as MediaFailed;

      expect(failed.fault.kind, MediaFaultKind.deviceNotFound);
      expect(harness.capture.requests.length, before);
    });
  });

  group('switching the microphone', () {
    // `selectAudioInput` is the one validated device switch on Windows: it walks
    // the recording device list and fails with `Not found device id: …`
    // (`common/cpp/src/flutter_media_stream.cc:504-527`). Re-capturing with a
    // deviceId would silently keep the previous microphone instead.
    test('goes through selectAudioInput, not a re-capture', () async {
      final MediaHarness harness = MediaHarness(
        devices: MediaDeviceSnapshot(
          microphones: <MediaDevice>[
            fakeMicrophone(),
            fakeMicrophone(id: 'mic-2', label: 'Mikrofon (USB Kulaklık)'),
          ],
          cameras: <MediaDevice>[fakeCamera()],
        ),
      );
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);
      final int capturesBefore = harness.capture.requests.length;

      final MediaSucceeded outcome =
          await harness.controller.switchMicrophone('mic-2') as MediaSucceeded;

      expect(outcome.notice, isNull);
      expect(harness.capture.selectedInputs, <String>['mic-2']);
      expect(
        harness.capture.requests.length,
        capturesBefore,
        reason: 'a microphone switch must not re-capture',
      );
      expect(harness.controller.state.microphoneDeviceId, 'mic-2');
      expect(harness.controller.negotiationCount, 1);
    });

    test('a native refusal is reported in Turkish', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      harness.capture.failSelectAudioInput =
          'Unable to selectAudioInput: Not found device id: mic-9';

      final MediaFailed failed =
          await harness.controller.switchMicrophone('mic-1') as MediaFailed;

      expect(failed.fault.kind, MediaFaultKind.deviceNotFound);
      expect(failed.message, MediaTexts.microphoneNotFound);
    });
  });

  group('muting', () {
    // ChatCallWorkspace.tsx:390 got this right: `track.enabled = false` keeps the
    // sender and its silence, where detaching would show the peer a broken track.
    test('disables the track without detaching it', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);
      final FakeTrack mic = harness.createdTracks.firstWhere(
        (FakeTrack track) => track.kind == 'audio',
      );
      final int attachCalls = harness.registry.audio.calls.length;

      await harness.controller.muteMicrophone(muted: true);

      expect(mic.enabled, isFalse);
      expect(
        harness.registry.audio.calls.length,
        attachCalls,
        reason: 'a mute is not a detach',
      );
      expect(mic.stopCount, 0, reason: 'and not a stop');
      expect(harness.controller.state.microphoneLive, isTrue);
    });

    test('unmutes again', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);
      final FakeTrack mic = harness.createdTracks.firstWhere(
        (FakeTrack track) => track.kind == 'audio',
      );

      await harness.controller.muteMicrophone(muted: true);
      await harness.controller.muteMicrophone(muted: false);

      expect(mic.enabled, isTrue);
    });

    test('a refused mute is reported, not thrown', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);
      for (final FakeTrack track in harness.createdTracks) {
        track.failOnEnable = true;
      }

      final MediaFailed failed =
          await harness.controller.muteMicrophone(muted: true) as MediaFailed;

      expect(failed.fault.kind, MediaFaultKind.unavailable);
      expect(failed.message, MediaTexts.connectionNotReady);
    });
  });

  group('the track ledger', () {
    test(
      'a camera that cannot be published is stopped, not left running',
      () async {
        final MediaHarness harness = MediaHarness();
        addTearDown(harness.dispose);
        await harness.open();
        final FakeTrack camera = FakeTrack(
          kind: 'video',
          label: defaultCameraLabel,
        );
        harness.capture.script.add(CapturedMedia(<MediaTrackHandle>[camera]));
        harness.registry.camera.failNextReplace = 'sender is closed';

        final MediaFailed failed =
            await harness.controller.enableCamera() as MediaFailed;

        expect(failed.fault.kind, MediaFaultKind.unavailable);
        // The track the OS just opened must not survive a failed publish. The old
        // build's half-finished `toggleCamera` is exactly this leak.
        expect(camera.stopCount, 1);
        expect(harness.orphanedTracks, isEmpty);
        expect(harness.controller.state.cameraLive, isFalse);
      },
    );

    test(
      'a video call whose camera sender refuses leaves nothing running',
      () async {
        final MediaHarness harness = MediaHarness();
        addTearDown(harness.dispose);
        await harness.open();
        harness.registry.camera.failNextReplace = 'sender is closed';

        final MediaCallFailed failed =
            await harness.controller.startCall(video: true) as MediaCallFailed;

        expect(failed.fault.kind, MediaFaultKind.unavailable);
        expect(
          harness.orphanedTracks,
          isEmpty,
          reason: 'the microphone was rolled back and stopped too',
        );
        expect(harness.controller.state.hasMedia, isFalse);
      },
    );
  });
}
