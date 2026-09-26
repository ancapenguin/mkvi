/// The call screen as a whole: which of the three things it draws, for which
/// state, and what it says in each.
///
/// The answer screen has its own file. This one is about the **routing**, and
/// routing is where a screen silently goes wrong: a stage left on screen behind
/// a dialog, a control bar that is live before the call is, a decline rendered in
/// the same red box as a broken microphone. Each state is measured by what is on
/// screen and by the Turkish sentence under the stage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/media/media.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/call/call.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/fakes/fakes.dart';
import '../../support/mkvi_test_app.dart';
import 'support/accessibility_floor.dart';
import 'support/call_screen_fixture.dart';

Future<void> expectScreenSound(WidgetTester tester) async {
  expectNoOverflow(tester);
  await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
  expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
}

void main() {
  group('which of the three things is on screen', () {
    testWidgets('an idle machine draws nothing at all', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      expect(fixture.call.machine.status, CallStatus.idle);
      expect(find.byKey(CallScreenKeys.empty), findsOneWidget);
      expect(find.byKey(CallStageKeys.surface), findsNothing);
      expect(find.byType(CallControls), findsNothing);
      expect(find.byKey(IncomingCallKeys.screen), findsNothing);
      await expectScreenSound(tester);
    });

    testWidgets('an ended call draws nothing either', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      fixture.ring();
      await fixture.accept(tester);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});
      expect(fixture.call.machine.status, CallStatus.connected);

      fixture.host.end();
      await tester.pumpAndSettle();

      expect(fixture.call.machine.status, CallStatus.ended);
      expect(find.byKey(CallScreenKeys.empty), findsOneWidget);
      expect(find.byKey(CallStageKeys.surface), findsNothing);
      await expectScreenSound(tester);
    });

    testWidgets('an incoming call draws the answer screen, never the stage', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring(CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      expect(find.byKey(IncomingCallKeys.screen), findsOneWidget);
      expect(find.byKey(CallStageKeys.surface), findsNothing);
      expect(find.byType(CallControls), findsNothing);
      await expectScreenSound(tester);
    });

    testWidgets('an answered call draws the stage and the controls', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      expect(find.byKey(CallStageKeys.surface), findsOneWidget);
      expect(find.byType(CallControls), findsOneWidget);
      expect(find.byKey(IncomingCallKeys.screen), findsNothing);
      for (final Key key in <Key>[
        CallControlKeys.microphone,
        CallControlKeys.camera,
        CallControlKeys.screenShare,
        CallControlKeys.devices,
        CallControlKeys.hangUp,
      ]) {
        expectHitTarget(tester, find.byKey(key));
      }
      await expectScreenSound(tester);
    });
  });

  group('what the stage says, per state', () {
    testWidgets('an unanswered outgoing call says it is waiting', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.dial(CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      expect(find.text(CallMessages.waitingForAnswer), findsOneWidget);
      expect(
        find.byType(MkviErrorState),
        findsNothing,
        reason:
            'waiting is a *state*, and it is the stage caption the call layer '
            'already owns — not a red box',
      );
      await expectScreenSound(tester);
    });

    testWidgets('an accepted call that is still publishing says so', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      fixture.ring(CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      // Synchronously, with no pump in between: `accept` puts the machine in
      // `connecting` and the media step is a queued future, so this is the one
      // instant at which the state is observable. A pump would run the microtask
      // and the state would be gone — which is itself the point, and is why
      // [CallScreen.captionFor] is public.
      fixture.host.accept();
      expect(fixture.call.machine.status, CallStatus.connecting);
      expect(
        CallScreen.captionFor(fixture.host.snapshot),
        CallUiTr.connectingCaption,
        reason: 'the stage names the state it is in rather than showing nothing',
      );

      await tester.pumpAndSettle();
      expect(
        fixture.call.machine.status,
        CallStatus.connected,
        reason: 'and the media layer, not the button, is what claims it',
      );
      await expectScreenSound(tester);
    });

    testWidgets('a connected audio call with no camera says there is none', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.audio);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      expect(fixture.media!.controller.state.cameraLive, isFalse);
      expect(find.text(CallMessages.noActiveVideo), findsOneWidget);
      expect(
        find.byKey(LocalPipKeys.box),
        findsNothing,
        reason:
            'no second camera means no floating box: an empty picture the user '
            'would ask about is worse than no picture',
      );
      await expectScreenSound(tester);
    });

    testWidgets('a running share is described by its phase, not by a caption', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      fixture.media!.stats.declare(screenSenderId, 0);
      await fixture.host.toggleScreenShare(sourceId: 'screen-0');
      await tester.pumpAndSettle();
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      expect(
        fixture.media!.controller.state.screenShare,
        ScreenSharePhase.stalled,
      );
      expect(
        find.descendant(
          of: find.byKey(CallStageKeys.mainTile),
          matching: find.byKey(VideoTileKeys.caption),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(
          find.descendant(
            of: find.byKey(CallStageKeys.mainTile),
            matching: find.byKey(VideoTileKeys.caption),
          ),
        ).data,
        MediaTexts.screenShareStalled,
        reason: 'the stage caption follows the phase, whatever the phase is',
      );
      expect(
        find.text(MediaTexts.screenShareWaitingForFirstFrame),
        findsNothing,
        reason: 'the phase has moved on, and the caption follows the phase',
      );
      await expectScreenSound(tester);
    });

    testWidgets('a share waiting for its first frame says exactly that', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      fixture.media!.stats.declare(screenSenderId, 1);
      await fixture.host.toggleScreenShare(sourceId: 'window-3');
      // Read the phase before the watchdog's first poll can finish, which is the
      // only instant at which "waiting for the first frame" is on screen.
      await fixture.host.media!.startScreenShare(sourceId: 'window-3');
      await tester.pump();

      final List<ScreenSharePhase> trail = fixture.media!.phases;
      expect(trail, contains(ScreenSharePhase.waitingForFirstFrame));
      expect(
        MediaTexts.screenShareWaitingForFirstFrame,
        'İlk kare bekleniyor…',
        reason:
            '0.1.x sat on a black rectangle with no state at all; this is the '
            'sentence that replaces it',
      );
      await expectScreenSound(tester);
    });
  });

  group('the notice line, and what it is not', () {
    testWidgets('a decline is a result, shown as a sentence and not as a fault', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      final String id = fixture.ring();
      await fixture.accept(tester);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});
      expect(fixture.call.machine.status, CallStatus.connected);

      // The peer hangs up from a call that had connected, which
      // `CallMachine.onRemoteEnd` records as `CallEndedByRemote` — and which
      // 0.1.x had no outcome for at all: it came back as a rejected promise and
      // landed in the media error box.
      fixture.call.machine.onRemoteEnd(callId: id);
      fixture.host.sync();
      await tester.pump();

      expect(fixture.call.machine.status, CallStatus.ended);
      expect(
        find.byType(MkviErrorState),
        findsNothing,
        reason:
            'a person who said no, and a person who could not open a camera, '
            'are different events and `call_outcome.dart` exists so they stay '
            'different. A red box for the first one is the bug it was written '
            'for.',
      );
      expect(find.byKey(CallScreenKeys.empty), findsOneWidget);
      expect(fixture.call.machine.outcome, isA<CallEndedByRemote>());
      expect(
        fixture.call.machine.outcome!.notice,
        CallMessages.remoteCallEnded,
        reason: 'and the notice is the Turkish sentence the call layer owns',
      );
      await expectScreenSound(tester);
    });

    testWidgets('a capture failure declines with the media layer\'s own reason', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      fixture.ring(CallMode.video);
      // The diagnostics sink refuses an unarranged call, and a capture failure
      // is *supposed* to send one: the raw platform text goes to the log and
      // nowhere near the state.
      fixture.media!.diagnostics.log.arrange('call');
      // No camera at all: rung 1 and rung 2 both fail, and the call *fails*
      // rather than silently becoming an audio call.
      fixture.media!.capture.getUserMediaScript.add('NotReadableError: nope');
      fixture.media!.capture.getUserMediaScript.add('NotReadableError: nope');

      await fixture.accept(tester);

      expect(fixture.call.machine.status, CallStatus.ended);
      expect(fixture.call.machine.outcome, isA<CallFailed>());
      expect(
        fixture.media!.rawDiagnostics,
        isNotEmpty,
        reason: 'the platform\'s own English text reached the log',
      );
      expect(
        fixture.call.sent.whereType<CallDeclineMessage>(),
        hasLength(1),
        reason:
            'a callee that cannot open its camera declines with the reason, '
            'which is what `App.tsx:583-587` did by hand',
      );
      expect(
        (fixture.call.sent.whereType<CallDeclineMessage>().single).reason,
        isNot(contains('NotReadableError')),
        reason: 'and never the platform\'s own text',
      );
      expect(
        fixture.media!.orphanedTracks,
        isEmpty,
        reason: 'and nothing it tried to capture is left running',
      );
      await expectScreenSound(tester);
    });
  });

  group('the screen never reaches connected on its own', () {
    testWidgets('media is the only door, and it is the media layer\'s answer', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      fixture.ring(CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      expect(fixture.call.machine.status, CallStatus.incoming);

      fixture.host.accept();
      expect(
        fixture.call.machine.status,
        CallStatus.connecting,
        reason:
            'accepting alone does not claim a connection — and no `pump` may '
            'run before this line, because one pump is enough to let the queued '
            'media step finish and take the state away',
      );
      await tester.pump();
      expect(find.byKey(CallStageKeys.surface), findsOneWidget);

      await tester.pumpAndSettle();
      expect(fixture.call.machine.status, CallStatus.connected);
      expect(
        fixture.call.sent.whereType<CallAcceptMessage>(),
        hasLength(1),
        reason: 'and the whole exchange is one frame on the wire',
      );
      await expectScreenSound(tester);
    });
  });

  group('the device picker is opt-in and lives below the stage', () {
    testWidgets('it is absent by default and present when asked for', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});
      expect(find.byType(CallDevicePicker), findsNothing);

      await fixture.pump(
        tester,
        showDevicePicker: true,
        onStyle: (CallUiHost _) {},
      );
      expect(find.byType(CallDevicePicker), findsOneWidget);
      expect(find.byKey(CallStageKeys.surface), findsOneWidget);
      expect(
        tester.getRect(find.byType(CallDevicePicker)).top,
        greaterThanOrEqualTo(tester.getRect(find.byKey(CallStageKeys.surface)).bottom),
        reason: 'the picker is in flow below the stage, never over it',
      );
      await expectScreenSound(tester);
    });
  });

  group('the whole screen survives the matrix', () {
    testWidgets('a ringing call: no overflow in any theme/accent at any window', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring();
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => CallScreen(
            host: fixture.host,
            peerName: CallScreenFixture.peerName,
          ),
          matrix: mkviAppearanceMatrix(),
          size: window,
          each: (AppearanceSettings settings, CallUiHost _) {
            expect(
              find.byKey(IncomingCallKeys.screen),
              findsOneWidget,
              reason: '${describeCombination(settings)} at ${window.width}dp',
            );
          },
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });

    testWidgets('a connected call: no overflow in any theme/accent at any window', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => CallScreen(
            host: fixture.host,
            peerName: CallScreenFixture.peerName,
            showDevicePicker: true,
          ),
          matrix: mkviAppearanceMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });

    testWidgets('a connected call: no overflow at both ends of the type slider', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => CallScreen(
            host: fixture.host,
            peerName: CallScreenFixture.peerName,
          ),
          matrix: mkviScaleMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });

    testWidgets('a connected call: no overflow with either accessibility switch', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => CallScreen(
            host: fixture.host,
            peerName: CallScreenFixture.peerName,
          ),
          matrix: mkviAccessibilityMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });
  });
}
