/// Device changes: "kamera çıkarıldı", reported once.
///
/// The plugin's own `ondevicechange` cannot be used directly. It carries no payload
/// — the spec's comment on `MediaDevices.ondevicechange` is "There is no information
/// about the change included in the event object" — and on Windows it is raised by
/// the **audio** device module alone
/// (`flutter_webrtc/common/cpp/src/flutter_webrtc_base.cc:88-92`), so one unplug can
/// arrive as several notifications and a camera unplug can arrive with no camera
/// news at all.
///
/// **No hardware.** `FakeCapture.announceDeviceChange()` is the OS notification and
/// `FakeCapture.devices` is what the OS would then report. What is under test is the
/// re-enumerate-and-diff, not WASAPI's device watcher.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/media/media.dart';

import 'support/media_fakes.dart';

void main() {
  group('a camera that is unplugged mid-call', () {
    test('is reported exactly once, however many notifications arrive', () async {
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
      expect(harness.controller.state.cameraDeviceId, 'cam-1');
      final FakeTrack camera = harness.createdTracks.firstWhere(
        (FakeTrack track) => track.kind == 'video',
      );

      // The camera that is publishing is now gone from the OS's list.
      harness.capture.devices = fakeDeviceList(
        cameras: <MediaDevice>[
          fakeCamera(id: 'cam-2', label: 'Kamera (USB Webcam)'),
        ],
      );
      // Three notifications for one physical change, which is the normal shape of
      // the Windows event.
      harness.capture.announceDeviceChange();
      harness.capture.announceDeviceChange();
      harness.capture.announceDeviceChange();
      await pumpUntil(
        () => harness.deviceEmissions.isNotEmpty,
        reason: 'the unplug to be reported',
      );
      for (int turn = 0; turn < 20; turn += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        harness.deviceEmissions.length,
        1,
        reason: 'one change, one line — not one per OS notification',
      );
      final MediaDevicesChanged change = harness.deviceEmissions.single;
      expect(change.removedCameras.map((MediaDevice d) => d.id), <String>[
        'cam-1',
      ]);
      expect(change.addedCameras, isEmpty);
      expect(change.isEmpty, isFalse);

      // The dead track is detached and stopped: a peer otherwise sees a frozen
      // participant with no reason given.
      expect(harness.registry.camera.calls.last, isNull);
      expect(camera.stopCount, 1);
      expect(harness.controller.state.cameraLive, isFalse);
      expect(harness.orphanedTracks, isEmpty);
    });

    test('the notice is Turkish and stands on its own', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);

      harness.capture.devices = MediaDeviceSnapshot(
        microphones: <MediaDevice>[fakeMicrophone()],
      );
      harness.capture.announceDeviceChange();
      await pumpUntil(
        () => harness.controller.state.notice != null,
        reason: 'the notice to appear',
      );

      expect(harness.controller.state.notice, MediaTexts.cameraUnplugged);
      // A notice is not an error box.
      expect(harness.controller.state.fault, isNull);
    });

    test('an unrelated notification is dropped', () async {
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

      // The OS says something moved and then reports the same list. Nothing
      // actually changed, so there is nothing to say.
      harness.capture.announceDeviceChange();
      await pumpUntil(
        () => harness.capture.deviceListings > 1,
        reason: 'the controller to re-enumerate',
      );
      for (int turn = 0; turn < 20; turn += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(harness.deviceEmissions, isEmpty);
      expect(harness.controller.state.notice, isNull);
      expect(harness.controller.state.cameraLive, isTrue);
    });

    test('a notification before open() is ignored', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);

      harness.capture.announceDeviceChange();
      for (int turn = 0; turn < 20; turn += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(harness.deviceEmissions, isEmpty);
      expect(
        harness.capture.deviceListings,
        0,
        reason: 'nothing is listening yet, so nothing is enumerated',
      );
    });
  });

  group('a device that is plugged in', () {
    test('is reported as an addition', () async {
      final MediaHarness harness = MediaHarness(
        devices: MediaDeviceSnapshot(
          microphones: <MediaDevice>[fakeMicrophone()],
        ),
      );
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);

      harness.capture.devices = fakeDeviceList();
      harness.capture.announceDeviceChange();
      await pumpUntil(
        () => harness.deviceEmissions.isNotEmpty,
        reason: 'the addition to be reported',
      );

      final MediaDevicesChanged change = harness.deviceEmissions.single;
      expect(change.addedCameras.map((MediaDevice d) => d.id), <String>[
        'cam-1',
      ]);
      expect(change.removedCameras, isEmpty);
      // An addition is not a notice: nothing the user was doing broke.
      expect(harness.controller.state.notice, isNull);
    });
  });

  group('a microphone that is unplugged mid-call', () {
    test('is detached and said so', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);
      final FakeTrack mic = harness.createdTracks.firstWhere(
        (FakeTrack track) => track.kind == 'audio',
      );

      harness.capture.devices = MediaDeviceSnapshot(
        cameras: <MediaDevice>[fakeCamera()],
      );
      harness.capture.announceDeviceChange();
      await pumpUntil(
        () => harness.controller.state.notice != null,
        reason: 'the notice to appear',
      );

      expect(harness.controller.state.notice, MediaTexts.microphoneUnplugged);
      expect(harness.registry.audio.calls.last, isNull);
      expect(mic.stopCount, 1);
      expect(harness.controller.state.microphoneLive, isFalse);
      expect(harness.orphanedTracks, isEmpty);
    });
  });

  group('a camera that is not the published one', () {
    test('being unplugged changes nothing about the call', () async {
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
      final FakeTrack camera = harness.createdTracks.firstWhere(
        (FakeTrack track) => track.kind == 'video',
      );

      harness.capture.devices = MediaDeviceSnapshot(
        microphones: <MediaDevice>[fakeMicrophone()],
        cameras: <MediaDevice>[fakeCamera()],
      );
      harness.capture.announceDeviceChange();
      await pumpUntil(
        () => harness.deviceEmissions.isNotEmpty,
        reason: 'the change to be reported',
      );

      // The change is reported — a device did go — but cam-1 is still published, so
      // the call is untouched and the notice box stays clear.
      expect(harness.deviceEmissions.single.removedCameras.single.id, 'cam-2');
      expect(harness.controller.state.cameraLive, isTrue);
      expect(harness.controller.state.notice, isNull);
      expect(camera.stopCount, 0);
    });
  });

  group('a failed enumeration', () {
    // A failed read is not evidence that a device disappeared. Reporting it as one
    // would put "kamera çıkarıldı" in front of a user whose camera is still
    // plugged in.
    test('is not reported as a device disappearing', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      harness.capture.failEnumerate = 'getSources refused';

      harness.capture.announceDeviceChange();
      await pumpUntil(
        () => harness.rawDiagnostics.isNotEmpty,
        reason: 'the failure to be recorded',
      );
      for (int turn = 0; turn < 20; turn += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(harness.deviceEmissions, isEmpty);
      expect(harness.controller.state.notice, isNull);
      expect(harness.controller.state.cameraLive, isTrue);
      expect(harness.orphanedTracks, isEmpty);
    });
  });

  group('MediaDevicesChanged', () {
    test('an empty change knows it is empty', () {
      expect(const MediaDevicesChanged().isEmpty, isTrue);
      expect(
        MediaDevicesChanged(
          removedCameras: <MediaDevice>[fakeCamera()],
        ).isEmpty,
        isFalse,
      );
    });

    test('matches on ids, not labels', () {
      // A renamed device is the same device. The OS does not have names, it has
      // connections, and a label change must not read as an unplug.
      const MediaDevice before = MediaDevice(
        id: 'cam-1',
        label: 'Kamera (eski ad)',
        kind: MediaDeviceKind.camera,
      );
      const MediaDevice after = MediaDevice(
        id: 'cam-1',
        label: 'Kamera (yeni ad)',
        kind: MediaDeviceKind.camera,
      );
      final MediaDeviceSnapshot older = MediaDeviceSnapshot(
        cameras: <MediaDevice>[before],
      );
      final MediaDeviceSnapshot newer = MediaDeviceSnapshot(
        cameras: <MediaDevice>[after],
      );

      expect(older.difference(newer).cameras, isEmpty);
      expect(newer.addedComparedTo(older).cameras, isEmpty);
      expect(newer.idForLabel('Kamera (yeni ad)'), 'cam-1');
    });

    test('an ambiguous label proves nothing and says so', () {
      // Two devices can genuinely share a device manager name. Picking one would be
      // a coin flip, and the unplug check would later act on it.
      const MediaDeviceSnapshot twins = MediaDeviceSnapshot(
        cameras: <MediaDevice>[
          MediaDevice(
            id: 'cam-1',
            label: 'Kamera',
            kind: MediaDeviceKind.camera,
          ),
          MediaDevice(
            id: 'cam-2',
            label: 'Kamera',
            kind: MediaDeviceKind.camera,
          ),
        ],
      );

      expect(twins.idForLabel('Kamera'), isNull);
      expect(twins.idForLabel('Yok'), isNull);
    });
  });
}
