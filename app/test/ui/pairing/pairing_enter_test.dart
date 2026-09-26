/// The code entry, measured rather than eyeballed.
///
/// ## What is under test
///
/// A pairing entry can look finished and send nothing: the control can be enabled
/// with a code the Worker would answer with a bare `400`, it can be pressed with
/// nine characters typed, and it can be pressed twice for a code that is
/// single-use. So the claims here are:
///
/// * the value **after** the widget's own formatter, compared against
///   `normalizePairingCode` and `isAcceptedPairingCode` — the two functions the
///   wire is pinned to, never a re-implementation;
/// * the control's `onPressed`, which is the only thing "locked" means;
/// * a Turkish sentence, compared against the catalogue entry that produced it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/signaling/pairing_code.dart';
import 'package:mkvi/ui/pairing/pairing.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/pairing_fixtures.dart';

/// A code the alphabet accepts, thirteen characters, no `I`, `O`, `0` or `1`.
const String goodCode = 'ABCDEFGHJKLMN';

void main() {
  group('the gate, as a function', () {
    test('an accepted code has no reason; every other one does', () {
      expect(pairingCodeProblem(goodCode).accepted, isTrue);
      expect(pairingCodeProblem(goodCode).reason, isNull);
      expect(pairingCodeProblem(goodCode.toLowerCase()).accepted, isTrue);
      expect(pairingCodeProblem('abcd-efgh ijklmn').accepted, isTrue);

      expect(pairingCodeProblem('').reason, PairingTr.emptyCode.tr);
      expect(
        pairingCodeProblem('ABCD').reason,
        PairingTr.tooShort.format(pairingCodeLength - 4),
      );
      expect(pairingCodeProblem('ABCD').reason, 'Kod eksik: 9 karakter daha gerekiyor.');
      expect(
        pairingCodeProblem('I O 0 1').reason,
        PairingTr.emptyCode.tr,
        reason: 'the four ambiguous characters are dropped at the source, so a '
            'string made only of them normalises to nothing at all',
      );
    });

    test('the rejected sentence is a guard, and nothing reaches it today', () {
      // `normalizePairingCode` drops everything outside the alphabet and
      // truncates at [pairingCodeMaxLength], so every value it can produce is
      // over the alphabet and 0..16 long — and `isAcceptedPairingCode` accepts
      // every one of those at 13..16. `PairingTr.invalidCode` is therefore
      // unreachable from this gate. It is kept because a change to
      // `lib/signaling/pairing_code.dart` that let a rejected value through must
      // not leave the screen with no sentence, and this test is what says so
      // instead of leaving a string no user can ever read.
      for (final String candidate in <String>[
        '',
        'I',
        'O',
        '0',
        '1',
        '1010',
        'ioIO01',
        'ıI',
        '????',
        '—',
      ]) {
        expect(
          pairingCodeProblem(candidate).reason,
          PairingTr.emptyCode.tr,
          reason: 'candidate "$candidate"',
        );
      }
      expect(
        pairingTrCatalogue[PairingTr.invalidCode],
        'Bu kod geçersiz.',
      );
    });

    test('the reason agrees with the wire, character for character', () {
      // `pairingCodeProblem` is a gate the button and the sentence share; if it
      // ever disagrees with `isAcceptedPairingCode` the two would tell the user
      // opposite things about the same value.
      for (final String candidate in <String>[
        '',
        'A',
        'ABCD',
        'ABCDEFGHJKLM',
        goodCode,
        'ABCDEFGHJKLMNO',
        '1010',
        'ioIO01',
        'abcdefghjklmn',
        'ABC DEFG-HJKLMN',
      ]) {
        final String clean = normalizePairingCode(candidate);
        expect(
          pairingCodeProblem(candidate).accepted,
          isAcceptedPairingCode(clean),
          reason: 'candidate "$candidate" normalises to "$clean"',
        );
      }
    });
  });

  group('a code goes out only when the wire would take it', () {
    testWidgets('a complete code unlocks the control and is sent normalised', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      final List<String> sent = <String>[];

      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(
            controller: controller,
            onSubmit: sent.add,
          ),
        ),
      );

      // Empty: locked. The claim is about the handler, not the ripple.
      expect(buttonEnabled(tester, find.byKey(PairingEnterKeys.submit)), isFalse);

      // Messy input, exactly what a paste out of a chat window looks like.
      await tester.enterText(find.byKey(MkviCodeKeys.field), 'abcd efgh-jklmn');
      await tester.pumpAndSettle();

      expect(controller.text, goodCode);
      expect(
        normalizePairingCode(controller.text),
        controller.text,
        reason: 'the formatter already did this; the gate must not redo it',
      );
      expect(buttonEnabled(tester, find.byKey(PairingEnterKeys.submit)), isTrue);

      await tester.tap(find.byKey(PairingEnterKeys.submit));
      await tester.pumpAndSettle();

      expect(sent, <String>[goodCode]);
      expectNoOverflow(tester);
    });

    testWidgets('a code the alphabet cannot use never unlocks the control', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      final List<String> sent = <String>[];

      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(controller: controller, onSubmit: sent.add),
        ),
      );

      await tester.enterText(find.byKey(MkviCodeKeys.field), 'a1i0oB');
      await tester.pumpAndSettle();

      expect(controller.text, 'AB');
      expect(isAcceptedPairingCode(controller.text), isFalse);
      expect(buttonEnabled(tester, find.byKey(PairingEnterKeys.submit)), isFalse);
      expect(sent, isEmpty);
      expectNoOverflow(tester);
    });
  });

  group('a wrong code says why, in Turkish, and goes nowhere', () {
    testWidgets('the keyboard submit of a short code is refused, with the count', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      final List<String> sent = <String>[];

      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(controller: controller, onSubmit: sent.add),
        ),
      );

      await tester.enterText(find.byKey(MkviCodeKeys.field), 'ABCD');
      // The submit in the SAME turn as the edit, for the reason
      // `code_field_test.dart` gives: a formatter that changes the value makes
      // `EditableText` restart its input connection on the next frame, and the
      // client a test can address is the one the connection had at that moment.
      // A pump in between loses the action entirely.
      // The control cannot be pressed, so the keyboard's own submit is the only
      // way to reach the gate — and it has to reach the same gate.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(sent, isEmpty, reason: 'an unfinished code must not be sent');
      expect(textIn(tester, find.byKey(PairingEnterKeys.error)), 'Kod eksik: 9 karakter daha gerekiyor.');
      expect(
        textIn(tester, find.byKey(PairingEnterKeys.error)),
        PairingTr.tooShort.format(9),
      );
      expect(
        buttonEnabled(tester, find.byKey(PairingEnterKeys.submit)),
        isFalse,
        reason: 'the sentence and the control must agree',
      );
      expectNoOverflow(tester);
    });

    testWidgets('input of nothing the alphabet accepts is the field\'s own line', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(controller: controller, onSubmit: (_) {}),
        ),
      );

      await tester.enterText(find.byKey(MkviCodeKeys.field), '1010');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(
        textIn(tester, find.byKey(MkviCodeKeys.error)),
        'Kodda kullanılamayan karakterler var; yalnızca A-Z (I ve O hariç) ve '
        '2-9 rakamları olur.',
      );
      expect(
        textIn(tester, find.byKey(MkviCodeKeys.error)),
        MkviCodeTr.unusableCharacters.tr,
      );
      expect(
        find.byKey(PairingEnterKeys.error),
        findsNothing,
        reason: 'this block owns the sentence about a refused send; the field '
            'owns the one about a value it is still being edited on',
      );
      expectNoOverflow(tester);
    });

    testWidgets('the standing complaint is dropped by the next keystroke', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);

      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(controller: controller, onSubmit: (_) {}),
        ),
      );

      await tester.enterText(find.byKey(MkviCodeKeys.field), 'ABCD');
      // Same turn, no pump in between: see the note above.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(PairingEnterKeys.error), findsOneWidget);

      await tester.enterText(find.byKey(MkviCodeKeys.field), 'ABCDEFGHJKLMN');
      await tester.pumpAndSettle();

      expect(
        find.byKey(PairingEnterKeys.error),
        findsNothing,
        reason: '"Kod eksik: 9 karakter" under a complete code is a sentence '
            'about a value that no longer exists',
      );
      expectNoOverflow(tester);
    });
  });

  group('while an exchange is in flight', () {
    testWidgets('the control is locked and says what it is doing', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController(
        text: goodCode,
      );
      addTearDown(controller.dispose);
      final List<String> sent = <String>[];

      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(
            controller: controller,
            busy: true,
            onSubmit: sent.add,
          ),
        ),
      );

      expect(buttonEnabled(tester, find.byKey(PairingEnterKeys.submit)), isFalse);
      expect(
        textIn(
          tester,
          find.descendant(
            of: find.byKey(PairingEnterKeys.submit),
            matching: find.byType(Text),
          ),
        ),
        'Kod gönderiliyor…',
      );
      expect(
        find.descendant(
          of: find.byKey(PairingEnterKeys.submit),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
      // The code is still on screen while it is in flight: a user who has to
      // retype a code because the screen cleared it has lost the thread.
      expect(controller.text, goodCode);
      expectNoOverflow(tester);
    });
  });

  group('the button, measured', () {
    testWidgets('it is a hit target, and a filled one on a raised surface', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(
            controller: TextEditingController(text: goodCode),
            onSubmit: (_) {},
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);
      final FilledButton button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(PairingEnterKeys.submit),
          matching: find.byType(FilledButton),
        ),
      );

      expectHitTarget(tester, find.byKey(PairingEnterKeys.submit), style: style);
      expect(
        tester.getSize(find.byKey(PairingEnterKeys.submit)).height,
        greaterThanOrEqualTo(style.hitTargetMin),
      );

      // The three numbers, measured: the token, what the theme declares, and
      // what the button itself declares.
      expect(style.hitTargetMin, 44);
      expect(style.control('md').height, 34);
      final Size? themed = Theme.of(
        tester.element(find.byType(FilledButton)),
      ).filledButtonTheme.style?.minimumSize?.resolve(<WidgetState>{});
      expect(
        themed?.height,
        style.control('md').height,
        reason: "the resolved theme declares controls.md.height, which is below "
            'control.hitTargetMin — see pairing_action.dart',
      );
      expect(
        style.control('md').height,
        lessThan(style.hitTargetMin),
      );
      expect(
        button.style?.minimumSize?.resolve(<WidgetState>{})?.height,
        style.hitTargetMin,
        reason: "the promise has to be in the control's own style, not in a "
            "Material default this directory does not own",
      );
      expect(
        Theme.of(
          tester.element(find.byType(FilledButton)),
        ).materialTapTargetSize,
        MaterialTapTargetSize.padded,
        reason: 'and the reason the rendered box clears the token today anyway: '
            'Material pads every button to a hard-coded 48',
      );
      expectNoOverflow(tester);
    });

    testWidgets('a filled action on a raised panel takes the strong edge', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(
            controller: TextEditingController(text: goodCode),
            onSubmit: (_) {},
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      // The ROADMAP Faz 2 interface rule, measured rather than quoted: the
      // button stands on `surfaceRaised`, so it takes the `borderStrong` edge.
      final ButtonStyle resolved = _filledStyleOf(
        tester,
        find.byKey(PairingEnterKeys.submit),
      );
      final BorderSide? side = resolved.side?.resolve(<WidgetState>{});
      expect(side, isNotNull);
      expect(side!.color, style.role('borderStrong'));
      expect(side.width, style.borderWidth);
      expect(
        mkviFilledActionNeedsEdge('surfaceRaised'),
        isTrue,
        reason: 'and the rule that produced it is the one in the widgets layer',
      );
      expect(mkviFilledActionNeedsEdge('bg'), isFalse);
      expectNoOverflow(tester);
    });

    testWidgets('a locked control\'s label is the declared surface role', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(
            controller: TextEditingController(),
            onSubmit: (_) {},
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      expect(buttonEnabled(tester, find.byKey(PairingEnterKeys.submit)), isFalse);
      expect(
        styleIn(
          tester,
          find.descendant(
            of: find.byKey(PairingEnterKeys.submit),
            matching: find.byType(Text),
          ),
        ).color,
        style.role('textOnAccent'),
        reason: 'a filled action on `accent` is an on-FILL role; the widgets '
            'layer measures the unfilled case instead, and this one is filled',
      );
      expectTokenContrast(style, 'textOnAccent', 'accent');
      expectNoOverflow(tester);
    });

    testWidgets('every control is a hit target at every scale and density', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviScaleMatrix()) {
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          PairingHost(
            child: PairingEnter(
              controller: TextEditingController(text: goodCode),
              onSubmit: (_) {},
            ),
          ),
          settings: settings,
        );
        final AppearanceStyle style = mkviStyleOf(tester);
        for (final Finder control in pairingControls(tester)) {
          expectHitTarget(tester, control, style: style);
        }
        for (final int index in <int>[0, 6, pairingCodeLength - 1]) {
          expectHitTarget(
            tester,
            find.byKey(MkviCodeKeys.cell(index)),
            style: style,
          );
        }
        expectNoOverflow(tester);
      }
    });
  });

  group('the matrix ROADMAP.md Faz 2 asks for', () {
    testWidgets('it paints in every theme and accent, in every window', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
        for (final Size size in mkviWindowSizes) {
          await unmountMkvi(tester);
          await pumpMkvi(
            tester,
            PairingHost(
              child: PairingEnter(
                controller: TextEditingController(text: goodCode),
                onSubmit: (_) {},
              ),
            ),
            settings: settings,
            size: size,
          );
          expectNoOverflow(tester);
          final AppearanceStyle style = mkviStyleOf(tester);
          // The pairs this block paints: the send control's label on `accent`,
          // the two sentences on the raised panel.
          expectTokenContrast(style, 'textOnAccent', 'accent');
          expectTokenContrast(style, 'text', 'surfaceRaised');
          expectTokenContrast(style, 'textMuted', 'surfaceRaised');
          expectTokenContrast(style, 'danger', 'surfaceRaised');
        }
      }
    });

    testWidgets('it survives both accessibility switches, everywhere', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviAccessibilityMatrix()) {
        for (final Size size in mkviWindowSizes) {
          await unmountMkvi(tester);
          await pumpMkvi(
            tester,
            PairingHost(
              child: PairingEnter(
                controller: TextEditingController(text: goodCode),
                onSubmit: (_) {},
              ),
            ),
            settings: settings,
            size: size,
          );
          expectNoOverflow(tester);
          final AppearanceStyle style = mkviStyleOf(tester);
          for (final Finder control in pairingControls(tester)) {
            expectHitTarget(tester, control, style: style);
          }
        }
      }
    });

    testWidgets('every control this screen announces is named in Turkish', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(
            controller: TextEditingController(text: goodCode),
            onSubmit: (_) {},
          ),
        ),
      );

      // The visible Turkish label is in the tree…
      expect(
        textIn(tester, find.byKey(MkviCodeKeys.label)),
        'Eşleştirme kodu',
      );
      expect(
        textIn(tester, find.byKey(MkviCodeKeys.label)),
        MkviCodeTr.fieldLabel.tr,
      );
      // …and the readings name each control once, in Turkish.
      final List<PairingReading> readings = await pairingControlReadings(tester);
      expect(readings, isNotEmpty, reason: 'no operable control was found at all');
      // The send button, matched by ROLE rather than by text. Matching on
      // 'Eşleş' used to find exactly one control, and stopped the moment the
      // field was named "Eşleştirme kodu" — a test that counts a control by a
      // word it shares with another control is a test that will be "fixed" by
      // renaming something.
      expect(
        readings.where(
          (PairingReading r) => r.kind == 'düğme' && r.spoken.contains('Eşleş'),
        ),
        hasLength(1),
        reason: 'the send control is counted once, not once per wrapper: $readings',
      );
      // The field is the second control, and it carries the label. It used to
      // be absent: `Opacity(opacity: 0)` dropped the subtree from the tree
      // entirely. Now it is here and named, so the claim covers two controls
      // rather than one.
      expect(
        readings
            .where((PairingReading r) => r.kind == 'metin alanı')
            .single
            .spoken,
        MkviCodeTr.fieldLabel.tr,
        reason: 'the field is reachable and named: $readings',
      );
      expect(
        await unlabelledControls(tester),
        isEmpty,
        reason: 'this screen declares no exemption: $readings',
      );
      expectNoOverflow(tester);
    });

    testWidgets('the code field IS in the semantics tree, and named', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        PairingHost(
          child: PairingEnter(
            controller: TextEditingController(text: goodCode),
            onSubmit: (_) {},
          ),
        ),
      );
      final List<PairingReading> readings = await pairingControlReadings(tester);

      // HISTORY, kept because the shape of this bug is worth remembering.
      //
      // The field was a `TextField` under `Opacity(opacity: 0)`, and Flutter
      // drops the semantics of everything under an `Opacity` at 0 —
      // `alwaysIncludeSemantics` defaults to false. So the pairing code entry
      // was not *unlabelled*; it was **absent**, and a screen-reader user could
      // not reach the one control this screen exists for. The screen published
      // exactly one operable node: its send button.
      //
      // Fixed 2026-09-26 in `mkvi_code_field.dart` with two changes: the
      // `Opacity` got `alwaysIncludeSemantics: true` so the subtree is in the
      // tree, and a `Semantics` wrapper names the field — because the name on
      // the thirteen cells is a SIBLING subtree, not an ancestor, so a reader
      // looking upward from the field reads nothing.
      //
      // This test asserted the opposite on purpose, to turn red the moment the
      // fix landed. The claims below are the positive ones.
      expect(
        readings.where((PairingReading r) => r.kind == 'metin alanı'),
        hasLength(1),
        reason: 'the code field is reachable and is exactly one text field; '
            'if it is gone, the `Opacity` lost `alwaysIncludeSemantics`. '
            'The readings were $readings',
      );
      expect(
        readings
            .where((PairingReading r) => r.kind == 'metin alanı')
            .single
            .spoken,
        MkviCodeTr.fieldLabel.tr,
        reason: 'a reachable field is not enough, it also has to be named: '
            '$readings',
      );
      expect(
        readings,
        hasLength(2),
        reason: 'the field and the send button, and nothing else: $readings',
      );
      expectNoOverflow(tester);
    });
  });
}

/// The [ButtonStyle] a rendered [FilledButton] resolved, read off the widget.
ButtonStyle _filledStyleOf(WidgetTester tester, Finder finder) {
  final FilledButton button = tester.widget<FilledButton>(
    find.descendant(of: finder, matching: find.byType(FilledButton)),
  );
  return button.style ?? const ButtonStyle();
}
