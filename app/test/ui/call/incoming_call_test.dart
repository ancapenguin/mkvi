/// The answer screen, which is `ROADMAP.md`'s reported defect 3: "Cevap ekranı
/// yok, arama direkt açılıyor."
///
/// Four claims are measured here, and each one is the screen half of a claim the
/// state machine already owns:
///
/// | claim | the machine's half (`test/call/call_incoming_test.dart`) | this file |
/// |---|---|---|
/// | a callee cannot be connected without answering | `accept()` is the only door | no [CallStage] is built while `incoming`, and the status is still `incoming` after any amount of ticking |
/// | a double tap sends one frame | `accept` is idempotent | two taps, one `call-accept` on the wire |
/// | the ring timeout closes the screen | the machine sends `call-decline` | the answer screen is gone, and it was still there at 44 s |
/// | the frame precedes the media | `accept → [SendFrame, PublishMedia]` | the screen's own executor puts the frame out first |
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/call/call.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/accessibility_floor.dart';
import 'support/call_screen_fixture.dart';

/// Every test in this file ends with this, and so must every test in
/// `test/ui/call`.
///
/// The two assertions are the harness's floor: [expectNoOverflow] catches the
/// defect class 0.1.x shipped in every screen, and [expectEveryControlLabelled]
/// catches the other one — the 17 WCAG violations `ROADMAP.md` counts. Putting
/// them in one function means no test can forget the second while remembering
/// the first.
Future<void> expectScreenSound(WidgetTester tester) async {
  expectNoOverflow(tester);
  // `expectEveryControlIsLabelled` and `expectEveryControlIsNamed`, and not the
  // harness's `expectEveryControlLabelled`: it disposes its `SemanticsHandle` in
  // an `addTearDown` that runs *after* the framework's end-of-test check, so
  // every caller fails on the handle instead of on the claim, and it reads an
  // owner that has no tree at all. Both measured in `call_controls_test.dart`
  // and written up in `support/accessibility_floor.dart`.
  await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
  expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
}

void main() {
  group('DEFECT 3, the answer screen exists and the call does not open', () {
    testWidgets('an incoming call shows the answer screen and no stage', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring(CallMode.video);
      late CallUiHost seen;
      await fixture.pump(tester, onStyle: (CallUiHost host) => seen = host);

      expect(fixture.call.machine.status, CallStatus.incoming);
      expect(find.byKey(IncomingCallKeys.screen), findsOneWidget);
      expect(
        find.byKey(CallStageKeys.surface),
        findsNothing,
        reason:
            'the stage is the call; a call that has not been answered has no '
            'stage. 0.1.4 opened the call by itself and this is the line that '
            'says it does not any more.',
      );
      expect(find.byKey(CallControlKeys.microphone), findsNothing);
      expect(find.byType(CallControls), findsNothing);
      expect(seen.snapshot.showsAnswerScreen, isTrue);
      expect(seen.snapshot.showsStage, isFalse);
      await expectScreenSound(tester);
    });

    testWidgets('the Turkish wording is the call layer\'s, not a second copy', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring(CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      expect(
        find.text(CallMessages.incomingEyebrow(CallMode.video)),
        findsOneWidget,
      );
      expect(
        find.text(CallMessages.peerIsCalling(CallScreenFixture.peerName)),
        findsOneWidget,
      );
      expect(find.text(CallMessages.mediaPromise), findsOneWidget);
      expect(find.text(CallMessages.acceptLabel), findsOneWidget);
      expect(find.text(CallMessages.declineLabel), findsOneWidget);
      expect(
        CallUiReused.accept,
        CallMessages.acceptLabel,
        reason: 'the catalogue reuses the machine\'s wording rather than retyping it',
      );
      expect(CallUiReused.eyebrow(CallMode.audio), 'Gelen sesli arama');
      await expectScreenSound(tester);
    });

    testWidgets('the status never becomes connected on its own, whatever the '
        'screen does', (WidgetTester tester) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring();
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      // Forty-four one-second ticks, pumping the tree every time: the countdown
      // is live, the widget rebuilds, and nothing presses anything.
      for (int second = 1; second < 45; second += 1) {
        await tester.pump(const Duration(seconds: 1));
        expect(
          fixture.call.machine.status,
          CallStatus.incoming,
          reason: 'at second $second the call is still waiting for the user',
        );
      }

      expect(fixture.call.machine.status, CallStatus.incoming);
      expect(
        fixture.call.sent,
        isEmpty,
        reason: 'a single frame before the user accepts is the reported defect',
      );
      expect(
        find.byKey(CallStageKeys.surface),
        findsNothing,
        reason: 'and the stage is still not on screen after 44 seconds',
      );
      await expectScreenSound(tester);
    });
  });

  group('a double tap sends one frame', () {
    testWidgets('pressing "Kabul et" twice puts one call-accept on the wire', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      fixture.ring();
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      // Two presses with no pump between them, so the second lands on the *same*
      // button: a rebuild in between would be a different test.
      await tester.tap(find.byKey(IncomingCallKeys.accept));
      await tester.tap(find.byKey(IncomingCallKeys.accept));
      await tester.pumpAndSettle();

      expect(
        fixture.call.sent.whereType<CallAcceptMessage>(),
        hasLength(1),
        reason: 'the machine is idempotent, and so is the screen',
      );
      expect(fixture.framesOf<CallAcceptMessage>(), hasLength(1));
      expect(fixture.call.machine.status, CallStatus.connected);
      await expectScreenSound(tester);
    });

    testWidgets('accepting publishes media only after the frame is out', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);

      expect(
        fixture.host.operations,
        <String>['frame:call-accept', 'media:publish'],
        reason:
            'the ordering contract ROADMAP.md Faz 5 models as data, measured '
            'through the screen\'s own executor rather than off the machine',
      );
      expect(fixture.call.sent, <Matcher>[isA<CallAcceptMessage>()]);
      expect(
        fixture.host.operations.indexOf('frame:call-accept'),
        lessThan(fixture.host.operations.indexOf('media:publish')),
        reason: 'the peer is told before the camera is opened',
      );
      await expectScreenSound(tester);
    });
  });

  group('the 45 second ring timeout', () {
    testWidgets('at 44 s the answer screen is still up and says so', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring();
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      fixture.advance(const Duration(seconds: 44));
      await tester.pump();

      expect(find.byKey(IncomingCallKeys.screen), findsOneWidget);
      expect(find.text(CallUiTr.remainingSeconds(1)), findsOneWidget);
      expect(fixture.call.machine.isRingTimerArmed, isTrue);
      expect(fixture.call.sent, isEmpty, reason: 'nothing has been decided yet');
      await expectScreenSound(tester);
    });

    testWidgets('the countdown starts at the machine\'s own 45 s', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring();
      late CallUiHost seen;
      await fixture.pump(tester, onStyle: (CallUiHost host) => seen = host);

      expect(
        seen.remainingRingSeconds,
        CallMachine.callRingTimeout.inSeconds,
        reason:
            'one 45 in the application, and it belongs to the machine; a second '
            'copy written into the widget is how the two timeouts stop meaning '
            'what they say',
      );
      expect(find.text(CallUiTr.remainingSeconds(45)), findsOneWidget);
      expect(seen.machine.ringTimeout, CallMachine.callRingTimeout);
      await expectScreenSound(tester);
    });

    testWidgets('at 45 s the screen is gone and call-declined is on the wire', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      final String id = fixture.ring();
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      fixture.advance(const Duration(seconds: 45));
      await tester.pump();

      expect(
        find.byKey(IncomingCallKeys.screen),
        findsNothing,
        reason:
            '0.1.x had no callee timer at all, so a ringing dialog stayed on '
            'screen for ever with both buttons there and neither working',
      );
      expect(find.byKey(CallScreenKeys.empty), findsOneWidget);
      expect(
        fixture.call.sent,
        <Matcher>[
          isA<CallDeclineMessage>()
              .having((CallDeclineMessage m) => m.id, 'id', id)
              .having(
                (CallDeclineMessage m) => m.reason,
                'reason',
                CallMessages.ringTimeoutReason,
              ),
        ],
      );
      expect(fixture.call.machine.status, CallStatus.ended);
      expect(fixture.call.machine.isRinging, isFalse);
      await expectScreenSound(tester);
    });
  });

  group('declining', () {
    testWidgets('"Reddet" sends one call-decline and closes the screen', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      final String id = fixture.ring();
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      await tester.tap(find.byKey(IncomingCallKeys.decline));
      await tester.pumpAndSettle();

      expect(
        fixture.call.sent.whereType<CallDeclineMessage>(),
        hasLength(1),
        reason: 'a double tap on "Reddet" is also possible, and also idempotent',
      );
      expect(fixture.host.operations, <String>['frame:call-decline']);
      expect(
        fixture.framesOf<CallDeclineMessage>().single.id,
        id,
      );
      expect(find.byKey(CallStageKeys.surface), findsNothing);
      await expectScreenSound(tester);
    });
  });

  group('the two buttons keep their promises', () {
    testWidgets('both are at least the token hit target on the short side', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring();
      late AppearanceStyle seen;
      await fixture.pump(tester, onStyle: (CallUiHost _) {});
      seen = mkviStyleOf(tester);

      expectHitTarget(tester, find.byKey(IncomingCallKeys.accept), style: seen);
      expectHitTarget(tester, find.byKey(IncomingCallKeys.decline), style: seen);
      expect(
        seen.hitTargetMin,
        44,
        reason: 'control.hitTargetMin in design/tokens.json, never scaled',
      );
      await expectScreenSound(tester);
    });

    testWidgets('both are still at the target at the largest type and density', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring();
      late AppearanceStyle seen;
      await fixture.pump(
        tester,
        settings: AppearanceSettings(
          fontScale: AppearanceSettings.maxFontScale,
          density: DensityPreference.values.last,
        ),
        onStyle: (CallUiHost _) {},
      );
      seen = mkviStyleOf(tester);

      expect(seen.fontScale, greaterThan(1));
      expectHitTarget(tester, find.byKey(IncomingCallKeys.accept), style: seen);
      expectHitTarget(tester, find.byKey(IncomingCallKeys.decline), style: seen);
      await expectScreenSound(tester);
    });

    testWidgets('the answer screen is a card, not a bare column', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      fixture.ring();
      late AppearanceStyle seen;
      await fixture.pump(tester, onStyle: (CallUiHost _) {});
      seen = mkviStyleOf(tester);

      final RenderBox surface = tester.renderObject<RenderBox>(
        find.byKey(IncomingCallKeys.screen),
      );
      expect(surface.size.width, closeTo(mkviWindowSize.width, 0.01));

      // The panel is capped, so a 1280 dp window does not produce a 1280 dp
      // card — the cap is twelve `lg` control heights, not a pixel.
      final double panelWidth = tester
          .getSize(find.byType(MkviPanel).first)
          .width;
      expect(
        panelWidth + 2 * seen.gap('8'),
        closeTo(seen.control('lg').height * 12, 0.01),
        reason:
            'a token-derived cap, and it follows the density; the gutter around '
            'it is gap(\'8\')',
      );
      expect(panelWidth, lessThan(mkviWindowSize.width));
      await expectScreenSound(tester);
    });
  });

  group('the answer screen survives the matrix', () {
    testWidgets('no overflow in any theme/accent combination at any window', (
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

    testWidgets('no overflow at both ends of the type slider and both densities', (
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
          matrix: mkviScaleMatrix(),
          size: window,
          each: (AppearanceSettings settings, CallUiHost _) {
            expectHitTarget(tester, find.byKey(IncomingCallKeys.accept));
            expectHitTarget(tester, find.byKey(IncomingCallKeys.decline));
          },
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });

    testWidgets('no overflow with either accessibility switch on', (
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
