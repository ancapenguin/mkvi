/// The code this device shows, measured rather than eyeballed.
///
/// ## What is under test
///
/// A code block can look perfect and be wrong: the string on screen can be a
/// length the Worker will not route, a copy control can be a button that copies
/// nothing, and a regenerate control can leave "copied" under a code that was
/// never copied. So every test here asserts one of four measurable things:
///
/// * the CHARACTER IN BOX N, read off the widget, compared to
///   [pairingCodeLength], [pairingCodePattern] and [pairingCodeAlphabet] — the
///   wire's own functions, never a re-implementation of them;
/// * the code that reached the clipboard, read off the recording seam **and** off
///   `SystemChannels.platform`, so the production default is measured too;
/// * a NUMBER: a box's size, a hit target, a token role;
/// * a Turkish sentence, compared against the catalogue entry that produced it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/signaling/pairing_code.dart';
import 'package:mkvi/ui/pairing/pairing.dart';

import '../../support/mkvi_test_app.dart';
import 'support/pairing_fixtures.dart';

/// A code the alphabet accepts, so the assertions about a *named* string are not
/// assertions about thirteen characters the test has to read back.
const String knownCode = 'ABCDEFGHJKLMN';

void main() {
  group('the code is the wire\'s own code', () {
    testWidgets('thirteen boxes, the wire length, and the Worker\'s pattern', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, const PairingCodeView());

      // The blocks are there, one per character, and no more.
      for (int index = 0; index < pairingCodeLength; index += 1) {
        expect(
          find.byKey(PairingCodeKeys.characterBox(index)),
          findsOneWidget,
          reason: 'box $index is missing, so the code is not $pairingCodeLength '
              'characters long',
        );
      }
      expect(
        find.byKey(PairingCodeKeys.characterBox(pairingCodeLength)),
        findsNothing,
        reason: 'a fourteenth box means the generated code is longer than the '
            'wire accepts',
      );

      // And the characters themselves, joined, are a code the Worker would route.
      final String drawn = String.fromCharCodes(<int>[
        for (int index = 0; index < pairingCodeLength; index += 1)
          textIn(tester, find.byKey(PairingCodeKeys.character(index))).runes.first,
      ]);
      expect(drawn.length, pairingCodeLength);
      expect(pairingCodePattern.hasMatch(drawn), isTrue, reason: drawn);
      expect(isAcceptedPairingCode(drawn), isTrue, reason: drawn);
      for (final int rune in drawn.runes) {
        expect(
          pairingCodeAlphabet.contains(String.fromCharCode(rune)),
          isTrue,
          reason: 'the code contains a symbol outside the alphabet: $drawn',
        );
      }
      expectNoOverflow(tester);
    });

    testWidgets('a seeded code is drawn character for character', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, const PairingCodeView(initialCode: knownCode));

      for (int index = 0; index < knownCode.length; index += 1) {
        expect(
          textIn(tester, find.byKey(PairingCodeKeys.character(index))),
          knownCode[index],
          reason: 'box $index draws the wrong character',
        );
      }
      expect(
        textIn(tester, find.byKey(PairingCodeKeys.sendNote)),
        PairingTr.sendCodeNote.tr,
      );
      expect(
        textIn(tester, find.byKey(PairingCodeKeys.sendNote)),
        'Bu kodu karşı tarafa gönder. Karşı taraf kendi cihazında bu kodu girsin.',
      );
      expectNoOverflow(tester);
    });

    testWidgets('a new code replaces the old one and clears what was reported', (
      WidgetTester tester,
    ) async {
      final List<String> written = <String>[];
      await pumpMkvi(
        tester,
        PairingCodeView(
          initialCode: knownCode,
          copyToClipboard: recordingClipboard(written: written),
        ),
      );

      await tester.tap(find.byKey(PairingCodeKeys.copy));
      await tester.pumpAndSettle();
      expect(textIn(tester, find.byKey(PairingCodeKeys.status)), PairingTr.copiedNote.tr);

      await tester.tap(find.byKey(PairingCodeKeys.regenerate));
      await tester.pumpAndSettle();

      final String next = textIn(
        tester,
        find.byKey(PairingCodeKeys.character(0)),
      );
      expect(next, isNot('A'), reason: 'the regenerate control did not mint a new code');
      expect(
        find.byKey(PairingCodeKeys.status),
        findsNothing,
        reason: '"Kod panoya kopyalandı" under a code that was never copied is a '
            'sentence about the wrong code',
      );
      // The new code is still a code, and the caption counts its own length.
      final String drawn = String.fromCharCodes(<int>[
        for (int index = 0; index < pairingCodeLength; index += 1)
          textIn(tester, find.byKey(PairingCodeKeys.character(index))).runes.first,
      ]);
      expect(pairingCodePattern.hasMatch(drawn), isTrue, reason: drawn);
      expectNoOverflow(tester);
    });
  });

  group('the copy really copies', () {
    testWidgets('the control hands the drawn code to the clipboard', (
      WidgetTester tester,
    ) async {
      final List<String> written = <String>[];
      await pumpMkvi(
        tester,
        PairingCodeView(
          initialCode: knownCode,
          copyToClipboard: recordingClipboard(written: written),
        ),
      );

      await tester.tap(find.byKey(PairingCodeKeys.copy));
      await tester.pumpAndSettle();

      expect(written, <String>[knownCode]);
      expectNoOverflow(tester);
    });

    test('the default seam is the real Clipboard.setData', () async {
      // The seam a test can see proves the button called *something*. Only the
      // platform channel proves the production default copies to the clipboard
      // rather than to a field of its own.
      final List<MethodCall> calls = interceptClipboard();

      expect(await copyPairingCodeToClipboard(knownCode), isTrue);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'Clipboard.setData');
      expect(calls.single.arguments, <String, Object?>{'text': knownCode});
    });

    test('a clipboard the platform refuses is reported, not thrown', () async {
      // A refused clipboard is recoverable: the code is on screen in thirteen
      // boxes. A button that takes the screen down with it is worse than a
      // button that does nothing.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            throw PlatformException(code: 'unavailable');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      expect(await copyPairingCodeToClipboard(knownCode), isFalse);
    });

    testWidgets('the copy line is Turkish, and says which way it went', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        PairingCodeView(
          initialCode: knownCode,
          copyToClipboard: recordingClipboard(result: true),
        ),
      );
      await tester.tap(find.byKey(PairingCodeKeys.copy));
      await tester.pumpAndSettle();
      final AppearanceStyle style = mkviStyleOf(tester);

      expect(
        textIn(tester, find.byKey(PairingCodeKeys.status)),
        'Kod panoya kopyalandı.',
      );
      expect(
        styleIn(tester, find.byKey(PairingCodeKeys.status)).color,
        style.role('success'),
      );
      expectNoOverflow(tester);

      await unmountMkvi(tester);
      await pumpMkvi(
        tester,
        PairingCodeView(
          initialCode: knownCode,
          copyToClipboard: recordingClipboard(result: false),
        ),
      );
      await tester.tap(find.byKey(PairingCodeKeys.copy));
      await tester.pumpAndSettle();
      final AppearanceStyle after = mkviStyleOf(tester);

      expect(
        textIn(tester, find.byKey(PairingCodeKeys.status)),
        'Kod kopyalanamadı; yukarıdaki kutudan elle yazabilirsin.',
      );
      expect(
        styleIn(tester, find.byKey(PairingCodeKeys.status)).color,
        after.role('danger'),
        reason: 'a failed copy and a successful one must not look the same',
      );
      expectNoOverflow(tester);
    });
  });

  group('one announcement, not thirteen', () {
    testWidgets('the cells are excluded and the code is named once', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, const PairingCodeView(initialCode: knownCode));

      final Semantics node = tester.widget<Semantics>(
        find.byKey(PairingCodeKeys.announcement),
      );
      expect(node.properties.label, contains(knownCode));
      expect(
        find.descendant(
          of: find.byKey(PairingCodeKeys.announcement),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
        reason: 'thirteen separate letters is what a screen reader reads when '
            'the cells are not excluded',
      );
      expectNoOverflow(tester);
    });
  });

  group('the geometry, measured', () {
    testWidgets('a box is one md control, square', (WidgetTester tester) async {
      await pumpMkvi(tester, const PairingCodeView(initialCode: knownCode));
      final ResolvedControl md = mkviStyleOf(tester).control('md');

      expect(
        tester.getSize(find.byKey(PairingCodeKeys.characterBox(0))).height,
        md.height,
      );
      expect(
        tester.getSize(find.byKey(PairingCodeKeys.characterBox(0))).width,
        md.height,
        reason: 'and square, so a row of them reads as a row',
      );
      expect(md.height, lessThan(mkviStyleOf(tester).hitTargetMin));
      expectNoOverflow(tester);
    });

    testWidgets('the cell is the token fill on the token edge', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, const PairingCodeView(initialCode: knownCode));
      final AppearanceStyle style = mkviStyleOf(tester);
      final BoxDecoration decoration = decorationIn(
        tester,
        find.byKey(PairingCodeKeys.characterBox(0)),
      );

      // The same box a filled cell of `MkviCodeField` has, so the screen that
      // shows a code and the screen that types one agree about what a code is.
      expect(decoration.color, style.role('accentSoft'));
      expect(decoration.border!.top.color, style.role('borderStrong'));
      expect(decoration.border!.top.width, style.borderWidth);
      expect(
        styleIn(tester, find.byKey(PairingCodeKeys.character(0))).color,
        style.role('text'),
      );
      expectNoOverflow(tester);
    });

    testWidgets('both controls are hit targets', (WidgetTester tester) async {
      await pumpMkvi(tester, const PairingCodeView(initialCode: knownCode));
      final AppearanceStyle style = mkviStyleOf(tester);

      for (final Finder control in pairingControls(tester)) {
        expectHitTarget(tester, control, style: style);
      }
      expectNoOverflow(tester);
    });

    testWidgets('the controls are hit targets at every scale and density', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviScaleMatrix()) {
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          const PairingCodeView(initialCode: knownCode),
          settings: settings,
        );
        final AppearanceStyle style = mkviStyleOf(tester);
        for (final Finder control in pairingControls(tester)) {
          expectHitTarget(tester, control, style: style);
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
            const PairingCodeView(initialCode: knownCode),
            settings: settings,
            size: size,
          );
          expectNoOverflow(tester);
          final AppearanceStyle style = mkviStyleOf(tester);
          // The four pairs this block actually paints.
          expectTokenContrast(style, 'text', 'accentSoft', minimum: 6.0);
          expectTokenContrast(style, 'text', 'surfaceSoft');
          expectTokenContrast(style, 'textMuted', 'surfaceSoft');
          expectTokenContrast(style, 'success', 'surfaceSoft');
          expectTokenContrast(style, 'danger', 'surfaceSoft');
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
            const PairingCodeView(initialCode: knownCode),
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

    testWidgets('every control carries a readable Turkish name', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, const PairingCodeView(initialCode: knownCode));
      await expectPairingControlsLabelled(tester);
      expectNoOverflow(tester);
    });

    testWidgets('a generated code is thirteen cells wide in the narrow window', (
      WidgetTester tester,
    ) async {
      // 13 x 44 dp of cell plus the gaps is 466 dp at the cozy density, and
      // `mkviWindowSizes` includes a 400 dp window. Scrolling is how a narrow
      // window becomes a narrower code block; clipping a cell the user has to
      // read is how it becomes a bug.
      await pumpMkvi(
        tester,
        const PairingCodeView(),
        size: mkviPhoneWindowSize,
      );
      expectNoOverflow(tester);
      expect(
        find.byKey(PairingCodeKeys.characterBox(pairingCodeLength - 1)),
        findsOneWidget,
        reason: 'all thirteen cells are built; the row scrolls, it is not cut',
      );
      expect(
        tester.getSize(find.byKey(PairingCodeKeys.characters)).height,
        greaterThanOrEqualTo(mkviStyleOf(tester).control('md').height),
      );
    });
  });

  group('the vocabulary', () {
    test('every entry has Turkish text and every refusal two sentences', () {
      for (final MapEntry<PairingTr, String> entry
          in pairingTrCatalogue.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: '${entry.key} has no wording, so it would render as nothing',
        );
      }
      for (final PairingRefusal refusal in PairingRefusal.values) {
        expect(refusal.messageTr.trim(), isNotEmpty, reason: '$refusal');
        expect(refusal.recoveryTr.trim(), isNotEmpty, reason: '$refusal');
      }
      expect(PairingRefusal.unreachable.isWorthRetrying, isTrue);
      expect(PairingRefusal.expired.isWorthRetrying, isFalse);
      expect(
        PairingRefusal.verificationFailed.isWorthRetrying,
        isFalse,
        reason: 'a code that failed verification must never be offered again',
      );
    });
  });
}
