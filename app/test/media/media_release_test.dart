/// Releasing the media: the leak the Tauri build had.
///
/// A camera that stayed on after the call. `ChatCallWorkspace.tsx` stopped streams
/// from three different `useEffect`s, one of which was keyed on
/// `callStatus === "ended"` — so a decline, a ring timeout, a failed publish or a
/// screen-share failure all left the camera running, and `stopStream` on unmount was
/// the only other exit.
///
/// **No hardware.** The leak being pinned is that a `FakeTrack` the OS handed over
/// is still running with no sender behind it, which is what a live camera is.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/media/media.dart';

import 'support/media_fakes.dart';

void main() {
  group('the call ends', () {
    test('every track it created is stopped', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      await harness.controller.startScreenShare();

      expect(harness.createdTracks.length, 3);
      expect(harness.orphanedTracks, isEmpty);

      final MediaState after = await harness.controller.stop();

      for (final FakeTrack track in harness.createdTracks) {
        expect(
          track.stopCount,
          1,
          reason: '${track.kind} was stopped exactly once',
        );
      }
      expect(harness.liveTracks, isEmpty, reason: 'the OS holds nothing');
      expect(harness.orphanedTracks, isEmpty);
      expect(after.hasMedia, isFalse);
      expect(after.screenShare, ScreenSharePhase.idle);
    });

    test('all three senders are detached', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      await harness.controller.startScreenShare();

      await harness.controller.stop();

      // One detach each, and a detach is `replaceTrack(null)` — never a new track
      // and never a transceiver.
      expect(harness.registry.audio.detaches.length, 1);
      expect(harness.registry.camera.detaches.length, 1);
      expect(harness.registry.screen.detaches.length, 1);
      expect(harness.controller.negotiationCount, 1);
    });

    test('a screen-share failure does not stop the rest of the drain', () async {
      // The compound case the old build lost: a share fails partway, and then the
      // call ends. Every track the OS ever handed out must still be stopped.
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      harness.registry.screen.failNextReplace = 'sender is closed';

      final MediaScreenShareFailed failed =
          await harness.controller.startScreenShare() as MediaScreenShareFailed;
      expect(failed.fault.kind, MediaFaultKind.unavailable);

      // The failed share's own track was stopped at failure time, and the call's
      // camera and microphone are still running.
      expect(harness.createdTracks.length, 3);
      expect(
        harness.orphanedTracks,
        isEmpty,
        reason: 'the failed share cleaned up after itself',
      );

      final MediaState after = await harness.controller.stop();

      for (final FakeTrack track in harness.createdTracks) {
        expect(track.stopCount, 1, reason: '${track.kind} was stopped');
      }
      expect(harness.liveTracks, isEmpty);
      expect(after.hasMedia, isFalse);
    });

    test('a screen capture that yields no track leaves nothing behind', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);
      // A display capture that returns an audio-only stream: the plugin does not
      // raise, it just hands back nothing to attach.
      final FakeTrack stray = FakeTrack(kind: 'audio', label: 'Sistem sesi');
      harness.capture.displayScript.add(
        CapturedMedia(<MediaTrackHandle>[stray]),
      );

      final MediaScreenShareFailed failed =
          await harness.controller.startScreenShare() as MediaScreenShareFailed;

      expect(failed.fault.kind, MediaFaultKind.deviceNotFound);
      expect(
        stray.stopCount,
        1,
        reason: 'a track the OS handed over is stopped even when unused',
      );
      expect(harness.orphanedTracks, isEmpty);
    });

    test('a detach that throws does not skip the tracks', () async {
      // The path that makes a cleanup function a leak: one sender refusing must not
      // prevent the other two from being detached, nor the tracks from being
      // stopped. The TypeScript build rethrew from `stopCall`
      // (`peer-transport.ts:221-222`) after stopping, which is better, but its stop
      // itself ran in a React effect keyed on one status value.
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      await harness.controller.startScreenShare();
      harness.registry
        ..audio.failAllReplaces = 'sender is closed'
        ..camera.failAllReplaces = 'sender is closed'
        ..screen.failAllReplaces = 'sender is closed';

      final MediaState after = await harness.controller.stop();

      for (final FakeTrack track in harness.createdTracks) {
        expect(track.stopCount, 1, reason: '${track.kind} was stopped anyway');
      }
      expect(harness.liveTracks, isEmpty);
      // The failure is reported rather than thrown out of a cleanup path.
      expect(after.fault, isNotNull);
      expect(after.hasMedia, isFalse);
      expect(harness.rawDiagnostics, isNotEmpty);
    });

    test('a track whose stop throws does not skip the next one', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      // Both tracks refuse to stop, in the order the ledger holds them.
      final FakeTrack mic = FakeTrack(
        kind: 'audio',
        label: defaultMicLabel,
        stopError: 'the device driver is gone',
      );
      final FakeTrack camera = FakeTrack(
        kind: 'video',
        label: defaultCameraLabel,
        stopError: 'the device driver is gone',
      );
      harness.capture.script.add(
        CapturedMedia(<MediaTrackHandle>[mic, camera]),
      );
      await harness.controller.startCall(video: true);

      final MediaState after = await harness.controller.stop();

      expect(mic.stopCount, 1);
      expect(
        camera.stopCount,
        1,
        reason: 'a failure did not skip the next track',
      );
      expect(after.hasMedia, isFalse);
      expect(after.fault, isNotNull);
    });
  });

  group('dispose', () {
    test('stops everything and closes the senders', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(() async {});
      await harness.open();
      await harness.controller.startCall(video: true);
      await harness.controller.startScreenShare();

      await harness.controller.dispose();

      for (final FakeTrack track in harness.createdTracks) {
        expect(track.stopCount, 1, reason: '${track.kind} was stopped');
      }
      expect(harness.liveTracks, isEmpty);
      expect(harness.registry.closeCount, 1);
    });

    test('is idempotent and does not stop a track twice', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(() async {});
      await harness.open();
      await harness.controller.startCall(video: true);
      final FakeTrack mic = harness.createdTracks.firstWhere(
        (FakeTrack track) => track.kind == 'audio',
      );

      await harness.controller.dispose();
      await harness.controller.dispose();

      expect(mic.stopCount, 1);
    });

    test('nothing works afterwards, and it is reported in Turkish', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(() async {});
      await harness.open();
      await harness.controller.startCall(video: true);
      await harness.controller.dispose();

      final MediaFailed camera =
          await harness.controller.enableCamera() as MediaFailed;
      final MediaCallFailed call =
          await harness.controller.startCall(video: true) as MediaCallFailed;
      final MediaFailed share =
          await harness.controller.stopScreenShare() as MediaFailed;

      expect(camera.message, MediaTexts.connectionNotReady);
      expect(call.message, MediaTexts.connectionNotReady);
      expect(share.message, MediaTexts.connectionNotReady);
      expect(await harness.controller.availableDisplaySources(), isEmpty);
    });
  });

  group('a track the controller never saw', () {
    // The invariant in one line: the OS holds nothing this process did not ask for.
    test('holds after a whole call, a share, and a hang-up', () async {
      final MediaHarness harness = MediaHarness(framesEncoded: 4);
      addTearDown(harness.dispose);
      await harness.open();

      await harness.controller.startCall(video: true);
      await harness.controller.startScreenShare();
      await pumpUntil(
        () => harness.controller.state.screenShare == ScreenSharePhase.live,
        reason: 'the share to go live',
      );
      await harness.controller.disableCamera();
      await harness.controller.enableCamera();
      await harness.controller.stopScreenShare();
      await harness.controller.startScreenShare();
      await harness.controller.stop();

      expect(harness.orphanedTracks, isEmpty);
      expect(harness.liveTracks, isEmpty);
      // Nine tracks in total: two from the call, one camera from the toggle, two
      // screen tracks from the two shares, and the originals that were replaced.
      expect(harness.createdTracks.length, greaterThanOrEqualTo(5));
      for (final FakeTrack track in harness.createdTracks) {
        expect(track.stopCount, 1, reason: 'stopped once, never twice');
      }
    });
  });
}
