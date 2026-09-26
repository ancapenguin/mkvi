/// The pairing screen, and the white pairing screen's second half.
///
/// ## What is under test
///
/// The claim this file exists for is a *negative* one, and it is measured rather
/// than asserted in prose: **for every [SetupState] whose `showsPairingScreen` is
/// false, this screen builds one zero-size box and no pairing content at all.**
///
/// `src/App.tsx:545` gated the pairing screen on `knownPeer === null`, and a
/// rejected `loadKnownPeer()` left that field null, so a corrupt store, a lost
/// keyring entry and a plain first run all rendered the same screen — and a user
/// who had been paired for months woke up being asked to pair again with no way
/// back. `lib/session/setup_state.dart` closed the cause; the table below is the
/// measurement that it stayed closed.
///
/// The other claims are the two the brief names: the code really is the wire's
/// own code and really is copyable, and the peer's two names are drawn in two
/// labelled slots rather than ranked against each other.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/session/session.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/pairing/pairing.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/fakes/fakes.dart';
import '../../support/mkvi_test_app.dart';
import 'support/pairing_fixtures.dart';

/// A code the alphabet accepts.
const String goodCode = 'ABCDEFGHJKLMN';

/// Every [SetupState] the session layer can be in, and how to reach it with a
/// real [SessionController] and no production seam.
enum Reach {
  /// The state before `bootstrap` settles: the store is being read.
  restoring,

  /// `seedAbsent()` — never paired on this device.
  firstRun,

  /// `seedPaired()` — a peer exists and the channel is not up.
  reconnecting,

  /// `seedPaired()` plus an open channel.
  connected,

  /// `seedUnreadable()` — a peer was paired and cannot be read.
  broken,

  /// `seedPaired()` plus the explicit "pair a new device" press.
  needsPairing,
}

void main() {
  group('the white pairing screen', () {
    testWidgets('every state that may not show pairing builds one zero box', (
      WidgetTester tester,
    ) async {
      for (final Reach reach in Reach.values) {
        final ScriptedPairingExchange exchange = ScriptedPairingExchange(
          scriptedAccepted(),
        );
        final FakeSessionHarness harness = await pumpReached(
          tester,
          reach,
          exchange: exchange.call,
        );
        final SetupState state = harness.controller.state;

        if (state.showsPairingScreen) {
          expect(
            find.byKey(PairingScreenKeys.hidden),
            findsNothing,
            reason: '$reach shows pairing, so the screen must build a body',
          );
          expect(find.byKey(PairingScreenKeys.body), findsOneWidget);
        } else {
          // The whole claim, as a widget: a bare box with nothing in it.
          expect(
            find.byKey(PairingScreenKeys.hidden),
            findsOneWidget,
            reason: '$reach is $state and must not build the pairing screen',
          );
          final SizedBox hidden = tester.widget<SizedBox>(
            find.byKey(PairingScreenKeys.hidden),
          );
          expect(hidden.child, isNull, reason: '$reach builds a box with no content');
          expect(
            find.byType(Text),
            findsNothing,
            reason: '$reach puts not one word on screen — that is what the white '
                'pairing screen was',
          );
          // And as an absence, three ways.
          expect(
            find.byType(PairingCodeView),
            findsNothing,
            reason: '$reach must not offer a code to send',
          );
          expect(
            find.byType(PairingEnter),
            findsNothing,
            reason: '$reach must not offer a code to type',
          );
          expect(
            find.byKey(MkviCodeKeys.field),
            findsNothing,
            reason: '$reach must not mount the code field at all',
          );
          expect(
            find.widgetWithText(OutlinedButton, PairingTr.cancelLabel.tr),
            findsNothing,
            reason: '$reach must not offer a way out of a screen it is not on',
          );
        }
        expectNoOverflow(tester);
        // A screen that shows NOTHING has nothing to label, and a label check
        // here would measure the empty box - which passes trivially. The claim
        // is the box, and `hidden.child == null` above already makes it.
        await unmountMkvi(tester);
      }
    });

    testWidgets('a first run mints a code AND offers to read one', (
      WidgetTester tester,
    ) async {
      final FakeSessionHarness harness = await pumpReached(
        tester,
        Reach.firstRun,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
      );

      expect(find.byKey(PairingScreenKeys.codeBlock), findsOneWidget);
      expect(find.byType(PairingCodeView), findsOneWidget);
      expect(harness.controller.state, isA<SetupFirstRun>());

      // BOTH halves, on a first run. This used to assert the field was absent,
      // because the screen forced a role on the two devices: one shows a code,
      // the other types it, and which one you were depended on who ran setup
      // first. There is no good answer to that question, so the screen no
      // longer asks it. Either device can do either half, in either order.
      expect(
        find.byKey(PairingScreenKeys.enterBlock),
        findsOneWidget,
        reason: 'a first run must also be able to read the other device`s code',
      );
      expect(find.byKey(MkviCodeKeys.field), findsOneWidget);

      // No way back: there is nothing stored to go back to, and a control that
      // goes nowhere is how a dead button ships.
      expect(
        find.widgetWithText(OutlinedButton, PairingTr.cancelLabel.tr),
        findsNothing,
      );
      // The headline is the session layer's own Turkish, not the screen's.
      expect(
        textIn(
          tester,
          find.descendant(
            of: find.byKey(PairingScreenKeys.heading),
            matching: find.byType(Text),
          ).first,
        ),
        'İlk bağlantını kur',
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('pairing a new device shows the field and the peer it replaces', (
      WidgetTester tester,
    ) async {
      await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
        alias: 'Eşim',
      );

      expect(find.byKey(PairingScreenKeys.enterBlock), findsOneWidget);
      expect(find.byKey(MkviCodeKeys.field), findsOneWidget);
      expect(find.byKey(PairingScreenKeys.peerBlock), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, PairingTr.cancelLabel.tr),
        findsOneWidget,
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });
  });

  group('the peer has two names, in two slots', () {
    testWidgets('the announced name and the local note are separate rows', (
      WidgetTester tester,
    ) async {
      final FakeSessionHarness harness = await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
        alias: 'Eşim',
      );

      final PeerNameView names = harness.controller.names;
      expect(names.announcedName, 'Ada');
      expect(names.alias, 'Eşim');
      expect(rowValue(tester, PairingScreenKeys.announcedRow), 'Ada');
      expect(rowValue(tester, PairingScreenKeys.aliasRow), 'Eşim');
      expect(
        rowValue(tester, PairingScreenKeys.announcedRow),
        names.displayName,
        reason: 'the primary slot is the announced name, never the note — this '
            'is the `src/App.tsx:119` expression',
      );
      expect(
        rowValue(tester, PairingScreenKeys.announcedRow),
        isNot(names.alias),
      );
      expect(
        textIn(tester, find.byKey(PairingScreenKeys.announcedLine)),
        'Kendi seçtiği ad: Ada',
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('a note equal to the announced name still gets both rows', (
      WidgetTester tester,
    ) async {
      // The case `src/ChatCallWorkspace.tsx:490` could not render: the note is
      // typed as the peer's own name, and the two lines used to disappear.
      final FakeSessionHarness harness = await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
        alias: 'Ada',
      );

      final PeerNameView names = harness.controller.names;
      expect(names.alias, names.announcedName);
      expect(names.showsAnnouncedName, isTrue);
      expect(rowValue(tester, PairingScreenKeys.announcedRow), 'Ada');
      expect(rowValue(tester, PairingScreenKeys.aliasRow), 'Ada');
      expect(
        find.byKey(PairingScreenKeys.announcedLine),
        findsOneWidget,
        reason: 'this is the case in which the peer is MOST likely to want to '
            'change their name, so the line must be here',
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('with no note there is one name and no second line', (
      WidgetTester tester,
    ) async {
      final FakeSessionHarness harness = await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
      );

      expect(harness.controller.names.hasAlias, isFalse);
      expect(rowValue(tester, PairingScreenKeys.announcedRow), 'Ada');
      expect(find.byKey(PairingScreenKeys.aliasRow), findsNothing);
      expect(
        find.byKey(PairingScreenKeys.announcedLine),
        findsNothing,
        reason: 'there is nothing to tell apart, so there is nothing to say',
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('pairing a new device from a broken read names nobody', (
      WidgetTester tester,
    ) async {
      // The documented last resort: `SetupBroken` is the one state that offers
      // "pair a new device", and it is reachable with no stored peer — which is
      // exactly why the peer block must be ABSENT rather than showing the
      // placeholder "Kişi" as though a person called it were paired here.
      final FakeSessionHarness harness = FakeSessionHarness()..seedUnreadable();
      await harness.bootstrap();
      expect(harness.controller.state, isA<SetupBroken>());
      expect(harness.controller.peer, isNull);
      await harness.controller.openPairing();
      expect(harness.controller.state, isA<SetupNeedsPairing>());
      expect(harness.controller.peer, isNull);

      await pumpMkvi(
        tester,
        PairingScreen(
          controller: harness.controller,
          exchange: ScriptedPairingExchange(scriptedAccepted()).call,
        ),
      );

      expect(find.byKey(PairingScreenKeys.enterBlock), findsOneWidget);
      expect(find.byKey(PairingScreenKeys.peerBlock), findsNothing);
      expect(
        find.text(KnownPeer.defaultAnnouncedName),
        findsNothing,
        reason: 'the placeholder is not a person and must not stand in for one',
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });
  });

  group('leaving, only after being asked', () {
    testWidgets('dismissing the confirmation stays on the pairing screen', (
      WidgetTester tester,
    ) async {
      final FakeSessionHarness harness = await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
      );

      await tester.tap(
        find.widgetWithText(OutlinedButton, PairingTr.cancelLabel.tr),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PairingScreenKeys.cancelDialog), findsOneWidget);
      expect(find.text(PairingTr.cancelTitle.tr), findsOneWidget);
      expect(find.text(PairingTr.cancelMessage.tr), findsOneWidget);
      expectNoOverflow(tester);

      await tester.tap(find.byKey(PairingScreenKeys.cancelDismiss));
      await tester.pumpAndSettle();

      expect(harness.controller.state, isA<SetupNeedsPairing>());
      expect(find.byKey(PairingScreenKeys.body), findsOneWidget);
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('confirming returns to the saved pair, and the screen goes', (
      WidgetTester tester,
    ) async {
      final FakeSessionHarness harness = await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
      );

      await tester.tap(
        find.widgetWithText(OutlinedButton, PairingTr.cancelLabel.tr),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PairingScreenKeys.cancelConfirm));
      await tester.pumpAndSettle();

      expect(harness.controller.state, isA<SetupReconnecting>());
      expect(
        find.byKey(PairingScreenKeys.hidden),
        findsOneWidget,
        reason: 'and a saved pair owns the main screen, so pairing is not on it',
      );
      expect(
        find.byType(Text),
        findsNothing,
        reason: 'a saved peer owns the screen even while it is offline, so the '
            'pairing wording has to leave with it',
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('both of the confirmation\'s controls are hit targets', (
      WidgetTester tester,
    ) async {
      await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
      );
      await tester.tap(
        find.widgetWithText(OutlinedButton, PairingTr.cancelLabel.tr),
      );
      await tester.pumpAndSettle();
      final AppearanceStyle style = mkviStyleOf(tester);

      expectHitTarget(tester, find.byKey(PairingScreenKeys.cancelConfirm), style: style);
      expectHitTarget(tester, find.byKey(PairingScreenKeys.cancelDismiss), style: style);
      expect(
        tester.getSize(find.byKey(PairingScreenKeys.cancelDismiss)).height,
        greaterThanOrEqualTo(style.hitTargetMin),
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });
  });

  group('the exchange, and what it says when it says no', () {
    testWidgets('a code in flight shows the progress, with the code still there', (
      WidgetTester tester,
    ) async {
      final Completer<PairingOutcome> gate = Completer<PairingOutcome>();
      final ScriptedPairingExchange exchange = ScriptedPairingExchange(
        scriptedAccepted(),
      );
      final FakeSessionHarness harness = await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: (String code) {
          exchange.calls += 1;
          exchange.codes.add(code);
          return gate.future;
        },
      );

      await tester.enterText(find.byKey(MkviCodeKeys.field), goodCode);
      await tester.pump();
      await tester.tap(find.byKey(PairingEnterKeys.submit));
      await tester.pump();

      expect(exchange.codes, <String>[goodCode]);
      expect(find.byKey(PairingScreenKeys.progress), findsOneWidget);
      expect(find.text(PairingTr.progressTitle.tr), findsOneWidget);
      expect(
        find.text(PairingTr.progressNote.tr),
        findsOneWidget,
        reason: 'a progress surface that does not say what it is waiting for is '
            'a spinner',
      );
      expect(
        buttonEnabled(tester, find.byKey(PairingEnterKeys.submit)),
        isFalse,
        reason: 'a single-use code must not be sent twice while one is in flight',
      );
      expect(
        harness.controller.state,
        isA<SetupNeedsPairing>(),
        reason: 'the state has not moved: the exchange has not finished',
      );
      expectNoOverflow(tester);

      // And a second press while it is in flight is ignored, not queued.
      await tester.tap(find.byKey(PairingEnterKeys.submit), warnIfMissed: false);
      await tester.pump();
      expect(exchange.calls, 1);

      gate.complete(const PairingOutcome.refused(PairingRefusal.cancelled));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('a transport failure is offered again with the same code', (
      WidgetTester tester,
    ) async {
      final ScriptedPairingExchange exchange = ScriptedPairingExchange(
        const PairingOutcome.refused(PairingRefusal.unreachable),
      );
      await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: exchange.call,
      );

      await tester.enterText(find.byKey(MkviCodeKeys.field), goodCode);
      await tester.pump();
      await tester.tap(find.byKey(PairingEnterKeys.submit));
      await tester.pumpAndSettle();

      expect(find.byKey(PairingScreenKeys.failure), findsOneWidget);
      expect(
        textIn(tester, find.byKey(MkviStateKeys.reason)),
        'Eşleşme sunucusuna ulaşılamadı.',
      );
      expect(
        textIn(tester, find.byKey(MkviStateKeys.message)),
        'Bağlantını kontrol edip aynı kodla yeniden dene.',
      );
      expect(find.byKey(PairingScreenKeys.retry), findsOneWidget);
      expect(
        buttonEnabled(tester, find.byKey(PairingEnterKeys.submit)),
        isTrue,
        reason: 'the field still holds the code, so the control is live again',
      );
      expectNoOverflow(tester);

      // Scroll it into view FIRST. Measured: with both halves now on one
      // screen, the retry row sits below the entry block, and a window of
      // 1280x800 puts it off-screen — `tap` then lands on empty space and the
      // button is never pressed. The test failed with "one code sent, expected
      // two" and no complaint from `flutter test`, because tapping empty space
      // is not an error. `ensureVisible` + a pump is what makes the tap land.
      await tester.ensureVisible(find.byKey(PairingScreenKeys.retry));
      await tester.pump();
      await tester.tap(find.byKey(PairingScreenKeys.retry));
      // `_submit` is async: it sets `exchanging`, awaits the exchange on a
      // microtask, then sets the outcome. Two pumps run the microtask and the
      // `setState` after it. `pumpAndSettle` is not usable here — the progress
      // widget the screen shows while exchanging keeps scheduling frames.
      await tester.pump();
      await tester.pump();

      // The retry resends the code the user TYPED, not the one this device
      // minted. Both halves now live on one screen, so `MkviCodeKeys.field`
      // belongs to the entry block; the minting block shows cells and has no
      // input of its own.
      expect(exchange.codes, <String>[goodCode, goodCode]);
      expect(
        exchange.distinctCodes,
        hasLength(1),
        reason: 'the retry must resend the same code, not mint a new one',
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('a spent code is never offered again', (
      WidgetTester tester,
    ) async {
      await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(
          const PairingOutcome.refused(PairingRefusal.expired),
        ).call,
      );

      await tester.enterText(find.byKey(MkviCodeKeys.field), goodCode);
      await tester.pump();
      await tester.tap(find.byKey(PairingEnterKeys.submit));
      await tester.pumpAndSettle();

      expect(
        textIn(tester, find.byKey(MkviStateKeys.reason)),
        'Eşleştirme kodu artık geçerli değil.',
      );
      expect(
        find.byKey(PairingScreenKeys.retry),
        findsNothing,
        reason: 'a code the room has thrown away must not be sent again; the '
            'recovery sentence says a new one is needed',
      );
      expect(
        textIn(tester, find.byKey(MkviStateKeys.message)),
        'Yeni bir kod üret ve karşı tarafa yeniden gönder.',
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('a completed pairing takes the screen away', (
      WidgetTester tester,
    ) async {
      // The production wiring shape: the exchange calls `completePairing`, and
      // the controller is the thing that leaves the pairing state. A screen that
      // hid itself on a "success" boolean instead would stay up with a dead
      // control and a code that is already spent.
      FakeSessionHarness? reached;
      final FakeSessionHarness harness = await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: (String code) async {
          final bool written = await reached!.controller.completePairing(
            publicKey: fakePeerPublicKey,
            discoveryId: fakeOpaqueId('room'),
          );
          return written
              ? scriptedAccepted()
              : const PairingOutcome.refused(PairingRefusal.recordNotWritten);
        },
      );
      reached = harness;

      await tester.enterText(find.byKey(MkviCodeKeys.field), goodCode);
      await tester.pump();
      await tester.tap(find.byKey(PairingEnterKeys.submit));
      await tester.pumpAndSettle();

      expect(harness.controller.state, isA<SetupReconnecting>());
      expect(find.byKey(PairingScreenKeys.hidden), findsOneWidget);
      expect(harness.peerStore.writes, hasLength(1));
      expect(
        find.byKey(PairingScreenKeys.failure),
        findsNothing,
        reason: 'a write that succeeded has nothing to apologise for',
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });
  });

  group('the geometry, measured', () {
    testWidgets('every control on the screen is a hit target', (
      WidgetTester tester,
    ) async {
      await pumpReached(
        tester,
        Reach.firstRun,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      for (final Finder control in pairingControls(tester)) {
        expectHitTarget(tester, control, style: style);
      }
      expectNoOverflow(tester);
      await unmountMkvi(tester);

      await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
      );
      final AppearanceStyle after = mkviStyleOf(tester);
      for (final Finder control in pairingControls(tester)) {
        expectHitTarget(tester, control, style: after);
      }
      expectHitTarget(
        tester,
        find.widgetWithText(OutlinedButton, PairingTr.cancelLabel.tr),
        style: after,
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('the two names are two rows, and the row is a row', (
      WidgetTester tester,
    ) async {
      await pumpReached(
        tester,
        Reach.needsPairing,
        exchange: ScriptedPairingExchange(scriptedAccepted()).call,
        alias: 'Eşim',
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      final Size announced = tester.getSize(
        find.byKey(PairingScreenKeys.announcedRow),
      );
      final Size alias = tester.getSize(find.byKey(PairingScreenKeys.aliasRow));
      expect(announced.height, alias.height);
      expect(announced.width, greaterThan(0));
      expect(alias.width, greaterThan(0));
      expect(
        find.byKey(PairingScreenKeys.announcedRow),
        findsOneWidget,
        reason: 'and the value sits on the raised well, not on the page',
      );
      expect(
        decorationOf(
          tester,
          find.descendant(
            of: find.byKey(PairingScreenKeys.peerBlock),
            matching: find.byKey(MkviPanelKeys.surface),
          ),
        ).color,
        style.role('surfaceSoft'),
      );
      expectNoOverflow(tester);
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });
  });

  group('the matrix ROADMAP.md Faz 2 asks for', () {
    testWidgets('it paints in every theme and accent, in every window', (
      WidgetTester tester,
    ) async {
      final ScriptedPairingExchange exchange = ScriptedPairingExchange(
        scriptedAccepted(),
      );
      for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
        for (final Size size in mkviWindowSizes) {
          final FakeSessionHarness harness = await pumpReached(
            tester,
            Reach.firstRun,
            exchange: exchange.call,
            settings: settings,
            size: size,
          );
          expectNoOverflow(tester);
          final AppearanceStyle style = mkviStyleOf(tester);
          // The pairs this screen paints: the heading on `bg`, the code cells on
          // `accentSoft`, the muted sentences on the raised panel.
          expectTokenContrast(style, 'text', 'bg');
          expectTokenContrast(style, 'textMuted', 'bg');
          expectTokenContrast(style, 'text', 'surfaceRaised');
          expectTokenContrast(style, 'textMuted', 'surfaceRaised');
          expectTokenContrast(style, 'text', 'accentSoft', minimum: 6.0);
          expect(harness.controller.state.showsPairingScreen, isTrue);
          // The label check runs HERE, inside the loop, while this pump is
          // still on screen. Placed after the loop it measured an empty tree —
          // `unmountMkvi` at the end of the last iteration had already torn
          // everything down, and an empty tree passes every label assertion.
          // That is the false negative this whole helper exists to prevent.
          await expectEveryControlLabelled(tester);
          await unmountMkvi(tester);
        }
      }
    });

    testWidgets('the field side paints in every theme and window too', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
        for (final Size size in mkviWindowSizes) {
          await pumpReached(
            tester,
            Reach.needsPairing,
            exchange: ScriptedPairingExchange(scriptedAccepted()).call,
            settings: settings,
            size: size,
          );
          expectNoOverflow(tester);
          await unmountMkvi(tester);
        }
      }
    });

    testWidgets('it survives both accessibility switches, everywhere', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviAccessibilityMatrix()) {
        for (final Size size in mkviWindowSizes) {
          for (final Reach reach in <Reach>[
            Reach.firstRun,
            Reach.needsPairing,
          ]) {
            await pumpReached(
              tester,
              reach,
              exchange: ScriptedPairingExchange(scriptedAccepted()).call,
              settings: settings,
              size: size,
            );
            expectNoOverflow(tester);
            final AppearanceStyle style = mkviStyleOf(tester);
            for (final Finder control in pairingControls(tester)) {
              expectHitTarget(tester, control, style: style);
            }
            await unmountMkvi(tester);
          }
        }
      }
      await expectLabelledOnAFreshTree(tester);
    });

    testWidgets('every scale and density, on both sides of the screen', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviScaleMatrix()) {
        for (final Reach reach in <Reach>[Reach.firstRun, Reach.needsPairing]) {
          await pumpReached(
            tester,
            reach,
            exchange: ScriptedPairingExchange(scriptedAccepted()).call,
            settings: settings,
          );
          expectNoOverflow(tester);
          await unmountMkvi(tester);
        }
      }
    });
  });
}

/// Reaches [reach] on a real [SessionController] and pumps the screen on it.
///
/// ## The harness is deliberately NOT disposed
///
/// `FakeSessionHarness.dispose()` awaits `ReconnectDriver.stop()`, and
/// `ScriptedDelay`, the `Delay` seam the driver is built with, ends with
/// `await Future<void>.delayed(Duration.zero)`. A `testWidgets` body runs on the
/// fake clock, which only advances inside `tester.pump()`, so **a
/// `Future.delayed` awaited directly in a test body never completes.** Measured
/// on this branch:
///
/// ```text
/// p1  await Future<void>.value()                -> p2
/// p2  await Future<void>.delayed(Duration.zero)  -> never returns
/// ```
///
/// Awaiting `harness.dispose()` in a teardown therefore hangs for the full
/// ten-minute timeout with every assertion green, which is the least useful
/// failure there is.
///
/// So the harness is dropped rather than torn down, and the reconnect loop a
/// paired bootstrap starts is left running: it is a fake seam over a fake
/// socket, inside a test-local binding, and nothing global survives it. That is
/// also why [Reach.reconnecting] and [Reach.connected] appear in exactly one test
/// (a leaked loop re-arms a zero-delay timer, and a matrix loop would pay for it
/// sixteen times). [Reach.needsPairing] is unaffected: `openPairing` stops the
/// loop itself, and its state transition happens before that await.
/// `openPairing` already stops the loop for [Reach.needsPairing].
Future<FakeSessionHarness> pumpReached(
  WidgetTester tester,
  Reach reach, {
  required PairingExchange exchange,
  String? alias,
  AppearanceSettings settings = AppearanceSettings.initial,
  Size size = mkviWindowSize,
}) async {
  final FakeSessionHarness harness = FakeSessionHarness();
  switch (reach) {
    case Reach.restoring:
      // Nothing: `SessionController._state` starts at `restoring`, and the point
      // is that the screen is already up while the store is still being read.
      break;
    case Reach.firstRun:
      harness.seedAbsent();
      await harness.bootstrap();
    case Reach.reconnecting:
      harness.seedPaired();
      await harness.bootstrap();
    case Reach.connected:
      harness.seedPaired();
      await harness.bootstrap();
      harness.controller.reportChannelOpen(true);
    case Reach.broken:
      harness.seedUnreadable();
      await harness.bootstrap();
    case Reach.needsPairing:
      harness.seedPaired();
      await harness.bootstrap();
      await harness.controller.openPairing();
  }
  // The alias is set BEFORE the first pump, and that is a property of the screen
  // rather than tidiness: `PairingScreen` rebuilds from `SessionController.states`
  // and reads `controller.names` at build time, and `setPeerAlias` publishes no
  // state. A rename made while this screen is up is therefore not reflected until
  // the state moves, and the only place the alias is written from is the
  // workspace, which is not this screen.
  if (alias != null) harness.controller.setPeerAlias(alias);
  await pumpMkvi(
    tester,
    PairingScreen(controller: harness.controller, exchange: exchange),
    settings: settings,
    size: size,
  );
  return harness;
}

/// The value of the [MkviKeyValueRow] keyed [key].
String rowValue(WidgetTester tester, Key key) => textIn(
  tester,
  find.descendant(
    of: find.byKey(key),
    matching: find.byKey(MkviSectionKeys.value),
  ),
);

/// Pumps a real screen and asserts the accessibility floor on it.
///
/// A matrix loop ends with `unmountMkvi`, so an accessibility assertion after one
/// walks an **empty** semantics tree and passes without ever reading a control.
/// The harness now measures correctly on its own, so this is a plain assertion
/// — but it is kept, and kept calling `expectEveryControlLabelled` from
/// `test/support/mkvi_test_app.dart`, because that is the assertion that can
/// fail. A local copy of the walk would be one more thing that silently returns
/// an empty list the day the test binding changes.
Future<void> expectLabelledOnAFreshTree(WidgetTester tester) async {
  await pumpReached(
    tester,
    Reach.needsPairing,
    exchange: ScriptedPairingExchange(scriptedAccepted()).call,
  );
  // Not empty first: a label assertion over an empty tree is satisfied by an
  // empty list, so the assertion below it has to be shown to have something to
  // say. This line is what makes the one after it mean something.
  expect(
    await readControlLabels(tester),
    isNotEmpty,
    reason: 'nothing was found to label, so labelling proves nothing',
  );
  await expectEveryControlLabelled(tester);
  expectNoOverflow(tester);
}
