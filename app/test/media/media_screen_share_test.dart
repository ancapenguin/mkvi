/// Screen share: the dedicated sender, and the first-frame watchdog.
///
/// **No hardware and no display.** `FakeStats` is the seam upstream issue #2137
/// forces into existence: a display track the plugin reports as a *success* and
/// which never encodes a single frame. `FakeCapture` hands it over on demand. What
/// is under test is the watchdog's schedule and the state the UI would render, not
/// DXGI.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/media/media.dart';

import 'support/media_fakes.dart';

void main() {
  group('the screen sender', () {
    // "The screen sender must not replace the camera sender, because both video
    // sources may be live at once."
    test('a share attaches to the screen sender, not the camera one', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: true);
      final int cameraCalls = harness.registry.camera.calls.length;

      final MediaScreenShareStarted started =
          await harness.controller.startScreenShare()
              as MediaScreenShareStarted;

      expect(started.source, fakeScreen().name);
      expect(harness.registry.screen.calls.length, 1);
      expect(harness.registry.screen.calls.single, isNotNull);
      // The camera is untouched: both video sources are live at once, which is the
      // whole reason there are two transceivers.
      expect(harness.registry.camera.calls.length, cameraCalls);
      expect(harness.controller.state.cameraLive, isTrue);
      expect(harness.orphanedTracks, isEmpty);
    });

    test(
      'the sources are enumerated, because there is no native picker',
      () async {
        final MediaHarness harness = MediaHarness(
          sources: <DisplaySource>[fakeScreen(), fakeWindow()],
        );
        addTearDown(harness.dispose);
        await harness.open();

        final List<DisplaySource> sources = await harness.controller
            .availableDisplaySources();

        expect(sources.map((DisplaySource s) => s.id), <String>[
          'screen-0',
          'window-3',
        ]);
        expect(sources.first.kind, DisplaySourceKind.screen);
        expect(sources.last.kind, DisplaySourceKind.window);
      },
    );

    test('a chosen source id is honoured', () async {
      final MediaHarness harness = MediaHarness(
        sources: <DisplaySource>[fakeScreen(), fakeWindow()],
      );
      addTearDown(harness.dispose);
      await harness.open();

      final MediaScreenShareStarted started =
          await harness.controller.startScreenShare(sourceId: 'window-3')
              as MediaScreenShareStarted;

      expect(started.source, 'Not Defteri');
      expect(harness.capture.shared.single.id, 'window-3');
    });

    test(
      'an unknown source id fails rather than sharing something else',
      () async {
        final MediaHarness harness = MediaHarness(
          sources: <DisplaySource>[fakeScreen(), fakeWindow()],
        );
        addTearDown(harness.dispose);
        await harness.open();

        final MediaScreenShareFailed failed =
            await harness.controller.startScreenShare(sourceId: 'window-99')
                as MediaScreenShareFailed;

        expect(failed.fault.kind, MediaFaultKind.deviceNotFound);
        expect(failed.message, MediaTexts.screenNotFound);
        expect(
          harness.capture.shared,
          isEmpty,
          reason:
              'sharing a window the user did not choose is the worst answer',
        );
        expect(harness.controller.state.screenShare, ScreenSharePhase.failed);
      },
    );

    test('an empty source list fails with the Turkish line', () async {
      final MediaHarness harness = MediaHarness(
        sources: const <DisplaySource>[],
      );
      addTearDown(harness.dispose);
      await harness.open();

      final MediaScreenShareFailed failed =
          await harness.controller.startScreenShare() as MediaScreenShareFailed;

      expect(failed.fault.kind, MediaFaultKind.deviceNotFound);
      expect(failed.message, MediaTexts.screenNotFound);
      expect(harness.registry.screen.calls, isEmpty);
    });

    test('a failed source enumeration is reported on the state', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      harness.capture.failDisplaySources = 'getDesktopSources refused';

      final List<DisplaySource> sources = await harness.controller
          .availableDisplaySources();

      expect(sources, isEmpty);
      expect(harness.controller.state.fault, isNotNull);
      expect(harness.controller.state.fault!.message, MediaTexts.screenUnknown);
    });

    test('starting a second share replaces the first', () async {
      final MediaHarness harness = MediaHarness(
        sources: <DisplaySource>[fakeScreen(), fakeWindow()],
      );
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startScreenShare();
      final FakeTrack first = harness.createdTracks.last;

      await harness.controller.startScreenShare(sourceId: 'window-3');

      expect(first.stopCount, 1);
      expect(harness.orphanedTracks, isEmpty);
      expect(harness.controller.state.screenSourceId, 'window-3');
    });
  });

  group('the first-frame watchdog (upstream #2137)', () {
    test('a share that encodes a frame goes live', () async {
      final MediaHarness harness = MediaHarness(framesEncoded: 12);
      addTearDown(harness.dispose);
      await harness.open();

      await harness.controller.startScreenShare();
      await pumpUntil(
        () => harness.controller.state.screenShare == ScreenSharePhase.live,
        reason: 'the share to go live',
      );

      expect(harness.controller.state.screenShare, ScreenSharePhase.live);
      expect(harness.controller.state.screenShare.label, isNotEmpty);
      // The first read happens immediately: a track that was already encoding
      // must not wait out a poll interval.
      expect(harness.stats.asked.single, 'sender-screen');
    });

    test('a share that never encodes a frame trips the watchdog', () async {
      // The exact shape of #2137: `getDisplayMedia` resolves, the track is attached,
      // and `desktop_capturer->Start()`'s return value was discarded so nobody is
      // told anything (`common/cpp/src/flutter_screen_capture.cc:373-375`).
      final MediaHarness harness = MediaHarness(framesEncoded: 0);
      addTearDown(harness.dispose);
      await harness.open();

      final MediaScreenShareStarted started =
          await harness.controller.startScreenShare()
              as MediaScreenShareStarted;

      // The API still says "started", because that is all it can say.
      expect(started.source, isNotEmpty);
      // And the state says "waiting", immediately, before any stat was read — which
      // is the whole workaround.
      expect(
        harness.controller.state.screenShare,
        ScreenSharePhase.waitingForFirstFrame,
      );
      expect(
        harness.controller.state.screenShare.label,
        MediaTexts.screenShareWaitingForFirstFrame,
      );

      await pumpUntil(
        () => harness.controller.state.screenShare == ScreenSharePhase.stalled,
        reason: 'the watchdog to give up',
      );

      expect(harness.controller.state.screenShare, ScreenSharePhase.stalled);
      expect(
        harness.controller.state.screenShare.label,
        MediaTexts.screenShareStalled,
      );
      // The Turkish label names the remedy, because the defect has one: the shared
      // window has to be in the foreground.
      expect(
        harness.controller.state.screenShare.label,
        contains('öne getirip'),
      );
      // Polled on the screen sender only, and on a real schedule.
      expect(harness.stats.asked, everyElement('sender-screen'));
      expect(
        harness.stats.asked.length,
        harness.controller.watchdog.pollBudget,
        reason:
            'one read per poll, and the budget is the timeout over the interval',
      );
      expect(
        harness.delay.requested,
        everyElement(const Duration(milliseconds: 1)),
      );
    });

    test('the waiting state is the first thing published', () async {
      final MediaHarness harness = MediaHarness(framesEncoded: 0);
      addTearDown(harness.dispose);
      await harness.open();

      await harness.controller.startScreenShare();

      expect(
        harness.phases.take(2),
        <ScreenSharePhase>[
          ScreenSharePhase.starting,
          ScreenSharePhase.waitingForFirstFrame,
        ],
        reason: 'the phase must be visible before the first stat is read',
      );
    });

    test('a late first frame is still caught', () async {
      final MediaHarness harness = MediaHarness(
        framesEncoded: 0,
        firstFrameTimeout: const Duration(milliseconds: 20),
        firstFramePollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(harness.dispose);
      await harness.open();

      await harness.controller.startScreenShare();
      // Let a few polls go by, then the frame arrives.
      harness.stats.frames = 3;
      await pumpUntil(
        () => harness.controller.state.screenShare == ScreenSharePhase.live,
        reason: 'the late frame to be noticed',
      );

      expect(harness.controller.state.screenShare, ScreenSharePhase.live);
    });

    test('a stats read that throws does not fail a working share', () async {
      final MediaHarness harness = MediaHarness(framesEncoded: 5);
      addTearDown(harness.dispose);
      await harness.open();
      harness.stats.failWith = 'getStats refused';

      await harness.controller.startScreenShare();
      await pumpUntil(
        () => harness.controller.state.screenShare == ScreenSharePhase.stalled,
        reason: 'the budget to run out',
      );

      // A failed read is not evidence of a frame, and not evidence of a broken one
      // either: the share ends as "stalled", which is the honest answer, and the
      // raw error went to diagnostics rather than to the user.
      expect(harness.controller.state.screenShare, ScreenSharePhase.stalled);
      expect(harness.rawDiagnostics, isNotEmpty);
      expect(
        harness.controller.state.fault,
        isNull,
        reason: 'the phase carries the message; the fault box stays clear',
      );
    });

    test('a share that is stopped mid-watch publishes nothing stale', () async {
      final MediaHarness harness = MediaHarness(framesEncoded: 0);
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startScreenShare();
      expect(
        harness.controller.state.screenShare,
        ScreenSharePhase.waitingForFirstFrame,
      );

      await harness.controller.stopScreenShare();
      final int readsAtStop = harness.stats.asked.length;
      // Let the loop that was in flight try to carry on.
      for (int turn = 0; turn < 40; turn += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(harness.controller.state.screenShare, ScreenSharePhase.idle);
      expect(harness.phases.last, ScreenSharePhase.idle);
      expect(
        harness.phases,
        isNot(contains(ScreenSharePhase.stalled)),
        reason: 'a share that was stopped cannot stall afterwards',
      );
      expect(
        harness.stats.asked.length,
        readsAtStop,
        reason: 'the in-flight loop noticed the disarm and stopped asking',
      );
    });
  });

  group('stopping a share', () {
    test('detaches with replaceTrack(null) and stops the track', () async {
      final MediaHarness harness = MediaHarness(framesEncoded: 7);
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startScreenShare();
      final FakeTrack screen = harness.createdTracks.last;

      final MediaSucceeded outcome =
          await harness.controller.stopScreenShare() as MediaSucceeded;

      expect(outcome.notice, isNull);
      expect(harness.registry.screen.calls.last, isNull);
      expect(screen.stopCount, 1);
      expect(harness.controller.state.screenShare, ScreenSharePhase.idle);
      expect(harness.controller.state.screenSourceId, isNull);
      expect(harness.orphanedTracks, isEmpty);
    });

    test('is a no-op when nothing is being shared', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();

      final MediaSucceeded outcome =
          await harness.controller.stopScreenShare() as MediaSucceeded;

      expect(outcome.notice, isNull);
      expect(harness.registry.screen.calls, isEmpty);
    });

    test('a stalled share is still stopped', () async {
      final MediaHarness harness = MediaHarness(framesEncoded: 0);
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startScreenShare();
      final FakeTrack screen = harness.createdTracks.last;
      await pumpUntil(
        () => harness.controller.state.screenShare == ScreenSharePhase.stalled,
        reason: 'the watchdog to give up',
      );

      await harness.controller.stopScreenShare();

      expect(screen.stopCount, 1);
      expect(harness.orphanedTracks, isEmpty);
    });
  });

  group('failures before the first frame', () {
    test('a vanished target is a cancellation, not an error box', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      // The plugin's own answer when the cached source list went stale between the
      // enumeration and the capture
      // (`common/cpp/src/flutter_screen_capture.cc:331-334`): the window the user
      // picked has been closed. Also `source not found` is a needle of the "no
      // device" row, which is why the dismissal check runs *before* the table.
      harness.capture.failDisplayMedia =
          'Unable to getDisplayMedia: Bad Arguments: source not found!';

      final MediaScreenShareFailed failed =
          await harness.controller.startScreenShare() as MediaScreenShareFailed;

      expect(failed.cancelled, isTrue);
      expect(failed.fault.kind, MediaFaultKind.cancelled);
      expect(failed.message, MediaTexts.screenCancelled);
      expect(harness.controller.state.screenShare, ScreenSharePhase.failed);
    });

    test("a Windows NotAllowedError is a real refusal, not a dismissal", () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      // In a browser `NotAllowedError` from `getDisplayMedia` is a closed picker. On
      // Windows there is no native picker to close — the application builds the
      // list — so MF/DXGI refusing is a genuine permission problem and must not be
      // swallowed.
      harness.capture.failDisplayMedia =
          'Unable to getDisplayMedia: NotAllowedError: Permission denied by system';

      final MediaScreenShareFailed failed =
          await harness.controller.startScreenShare() as MediaScreenShareFailed;

      expect(failed.cancelled, isFalse);
      expect(failed.fault.kind, MediaFaultKind.permissionDenied);
      expect(failed.message, MediaTexts.screenPermissionDenied);
    });

    test('a display capture that yields no track is reported', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      harness.capture.displayScript.add(
        CapturedMedia(const <MediaTrackHandle>[]),
      );

      final MediaScreenShareFailed failed =
          await harness.controller.startScreenShare() as MediaScreenShareFailed;

      expect(failed.fault.kind, MediaFaultKind.deviceNotFound);
      expect(harness.registry.screen.calls, isEmpty);
      expect(harness.orphanedTracks, isEmpty);
    });

    test('a publish that fails stops the track it just opened', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      harness.registry.screen.failNextReplace = 'sender is closed';

      final MediaScreenShareFailed failed =
          await harness.controller.startScreenShare() as MediaScreenShareFailed;

      expect(failed.fault.kind, MediaFaultKind.unavailable);
      expect(harness.orphanedTracks, isEmpty);
      expect(harness.controller.state.screenShare, ScreenSharePhase.failed);
    });

    test('an unclassified error still lands on a Turkish line', () async {
      final MediaHarness harness = MediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      harness.capture.failDisplayMedia =
          'Unable to getDisplayMedia: 0xdeadbeef';

      final MediaScreenShareFailed failed =
          await harness.controller.startScreenShare() as MediaScreenShareFailed;

      expect(failed.fault.kind, MediaFaultKind.unknown);
      expect(failed.message, MediaTexts.screenUnknown);
      expect(failed.message, isNot(contains('0xdeadbeef')));
    });
  });
}
