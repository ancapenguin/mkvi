/// The harness is infrastructure, so the harness is tested.
///
/// Every other widget test in `test/ui/` trusts these functions: if
/// [pumpMkvi] silently installed no `AppearanceStyle`, or sized the surface to
/// a phone, or `expectTokenContrast` compared the wrong pair, every assertion
/// built on top of it would pass while proving nothing - which is the exact
/// shape of failure `ROADMAP.md` records for 0.1.x ("the suite is green and the
/// feature is broken").
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';

import 'mkvi_test_app.dart';

void main() {
  testWidgets('pumpMkvi installs a real AppearanceStyle, not a default one', (
    WidgetTester tester,
  ) async {
    AppearanceStyle? seen;
    await pumpMkvi(
      tester,
      Builder(
        builder: (BuildContext context) {
          seen = AppearanceStyle.of(context);
          return const SizedBox.shrink();
        },
      ),
      settings: AppearanceSettings(
        theme: ThemePreference.forest,
        fontScale: 1.25,
        density: DensityPreference.compact,
      ),
    );

    expect(seen, isNotNull);
    expect(seen!.themeId, 'forest');
    expect(seen!.fontScale, 1.25);
    expect(mkviStyleOf(tester).themeId, 'forest');
    expect(mkviStyleOf(tester).density, isNot(1.0));
  });

  testWidgets('mkviStyleOf fails loudly when the tree has no style at all', (
    WidgetTester tester,
  ) async {
    // A bare MaterialApp is exactly what a test must not write, and the harness
    // has to say so instead of quietly returning a default.
    await tester.pumpWidget(
      const MaterialApp(home: SizedBox.shrink()),
    );
    expect(() => mkviStyleOf(tester), throwsA(isA<StateError>()));
  });

  testWidgets('pumpMkvi lays the tree out at the desktop window, not a phone', (
    WidgetTester tester,
  ) async {
    await pumpMkvi(
      tester,
      const SizedBox.expand(key: Key('fill')),
    );
    expect(tester.getSize(find.byKey(const Key('fill'))), mkviWindowSize);
  });

  testWidgets('a narrow window is available for the layouts that must fit', (
    WidgetTester tester,
  ) async {
    await pumpMkvi(
      tester,
      const SizedBox.expand(key: Key('fill')),
      size: mkviNarrowWindowSize,
    );
    expect(tester.getSize(find.byKey(const Key('fill'))), mkviNarrowWindowSize);
  });

  test('the appearance matrix is every theme against every accent', () {
    final List<AppearanceSettings> matrix = mkviAppearanceMatrix().toList();
    expect(matrix.length, ThemePreference.values.where((ThemePreference t) => t.isExplicit).length * AccentId.values.length);
    for (final ThemePreference theme in <ThemePreference>[
      ThemePreference.midnight,
      ThemePreference.light,
      ThemePreference.forest,
      ThemePreference.plum,
    ]) {
      for (final AccentId accent in AccentId.values) {
        expect(
          matrix.any(
            (AppearanceSettings s) => s.theme == theme && s.accent.presetId == accent,
          ),
          isTrue,
          reason: 'matrix is missing ${theme.name}/${accent.name}',
        );
      }
    }
  });

  test('the scale matrix covers both ends of the slider and both densities', () {
    final List<AppearanceSettings> matrix = mkviScaleMatrix().toList();
    expect(
      matrix.map((AppearanceSettings s) => s.fontScale).toSet(),
      <double>{0.9, 1.0, 1.25},
    );
    expect(
      matrix.map((AppearanceSettings s) => s.density).toSet(),
      DensityPreference.values.toSet(),
    );
  });

  test('every matrix combination resolves, and every one of them paints', () {
    // 4 themes x 4 accents must all produce a usable style; the old build had a
    // video placeholder at 1.17:1 that only existed in one of them, and nothing
    // noticed because nothing resolved all of them.
    for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
      final ResolvedAppearance resolved = mkviAppearance(settings: settings);
      expect(
        resolved.style.roles.length,
        mkviTokenFixture.tokens.roleNames.length,
        reason: '${settings.theme.name}/${settings.accent.accentId} lost a role',
      );
      expect(resolved.report.issues, isEmpty, reason: '$settings');
    }
  });

  testWidgets(
    'unmountMkvi is what lets a matrix be walked inside one test',
    (WidgetTester tester) async {
      // Without it this is the failure two agents hit independently:
      //   "A Theme was inherited but an unrelated ancestor of the widget that
      //    requested the inheritance is introducing a new Theme"
      // which arrives as a framework crash, not as an assertion about the
      // widget under test.
      for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          Text('${settings.theme.name}/${settings.accent.accentId}'),
          settings: settings,
        );
        expect(mkviStyleOf(tester).themeId, settings.theme.themeId);
      }
      expectNoOverflow(tester);
    },
  );

  testWidgets('pumpMkviMatrix walks the whole grid in one test', (
    WidgetTester tester,
  ) async {
    final List<String> seen = <String>[];
    await pumpMkviMatrix(
      tester,
      (AppearanceSettings settings) => Text(describeCombination(settings)),
      matrix: mkviAppearanceMatrix(),
      each: (AppearanceSettings settings) => seen.add(settings.theme.name),
    );
    expect(seen, hasLength(16));
    expectNoOverflow(tester);
  });

  testWidgets('a bare Text is not rendered in Flutter error style', (
    WidgetTester tester,
  ) async {
    // The trap this harness exists to remove: with no ambient
    // DefaultTextStyle a bare `Text` comes out red and double-underlined, so a
    // test that measures geometry around one measures the error style.
    await pumpMkvi(tester, const Text('merhaba'));
    final TextStyle? style = tester.widget<Text>(find.text('merhaba')).style;
    expect(
      style?.color,
      isNot(const Color(0xFFFF0000)),
      reason: 'the text is inheriting Flutter error styling, not the theme',
    );
  });

  test('the accessibility matrix covers both switches both ways', () {
    final List<AppearanceSettings> matrix = mkviAccessibilityMatrix().toList();
    expect(matrix, hasLength(4));
    expect(
      matrix.map((AppearanceSettings s) => s.highContrast).toSet(),
      <bool>{false, true},
    );
    expect(
      matrix.map((AppearanceSettings s) => s.reduceMotion).toSet(),
      <bool>{false, true},
    );
  });

  test('every window size the harness offers is at least a phone', () {
    for (final Size size in mkviWindowSizes) {
      expect(size.width, greaterThanOrEqualTo(400));
      expect(size.height, greaterThanOrEqualTo(600));
    }
  });

  testWidgets('readControlLabels reports what a screen reader would say', (
    WidgetTester tester,
  ) async {
    await pumpMkvi(
      tester,
      Column(
        children: <Widget>[
          ElevatedButton(onPressed: () {}, child: const Text('Gönder')),
          const TextField(decoration: InputDecoration(labelText: 'Adınız')),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.close),
            tooltip: 'Kapat',
          ),
        ],
      ),
    );
    final List<ControlReading> readings = await readControlLabels(tester);
    expect(readings, isNotEmpty, reason: 'no operable control was found at all');

    // One reading per control, not per wrapper widget. A Material button is an
    // `ElevatedButton` over an `InkWell` over a `GestureDetector`; a reader that
    // walked widgets would report one control three times.
    expect(
      readings.where((ControlReading r) => r.spoken.contains('Gönder')),
      hasLength(1),
      reason: 'the send button was counted more than once: $readings',
    );

    // A `TextField` names itself on a DESCENDANT node, so a reader that reads
    // only the role-bearing node calls every field in the app unlabelled. That
    // false negative is worse than no check at all: it would train the next
    // agent to wrap already-named controls in redundant `Semantics`.
    expect(
      readings.any((ControlReading r) => r.spoken.contains('Adınız')),
      isTrue,
      reason: 'metin alanının adı yok: $readings',
    );
    expect(
      readings.any((ControlReading r) => r.spoken.contains('Kapat')),
      isTrue,
      reason: 'ikon düğmesinin tooltip\'i yok: $readings',
    );
    await expectEveryControlLabelled(tester);
  });

  testWidgets('expectEveryControlLabelled goes red on a nameless control', (
    WidgetTester tester,
  ) async {
    await pumpMkvi(
      tester,
      const Column(
        children: <Widget>[
          // Deliberately nameless. A control the screen reader cannot name is
          // not a control, and this is the assertion that says so.
          ElevatedButton(onPressed: _noop, child: SizedBox.shrink()),
        ],
      ),
    );
    // The reason this test exists: until 2026-09-26 the helper put its failure
    // text INTO the `spoken` value, so `spoken` was never empty and the
    // assertion could not fail — it reported 22 named controls and then
    // accepted a nameless one.
    await expectLater(
      () => expectEveryControlLabelled(tester),
      throwsA(
        isA<TestFailure>().having(
          (TestFailure f) => f.message,
          'mesaj',
          allOf(contains('okunacak bir adı yok'), contains('düğme')),
        ),
      ),
    );
  });

  test('expectTokenContrast fails on a pair that does not clear the bar', () {
    final AppearanceStyle style = mkviAppearance().style;
    expect(
      () => expectTokenContrast(style, 'text', 'text'),
      throwsA(isA<TestFailure>()),
    );
    expect(
      () => expectTokenContrast(style, 'text', 'surface'),
      returnsNormally,
    );
  });

  test('the type and space step names are the ones the token file declares', () {
    final tokens = mkviTokenFixture.tokens;
    expect(tokens.typeScale.keys.toSet(), mkviTypeSteps.toSet());
    expect(tokens.spaceSteps.keys.toSet(), mkviSpaceSteps.toSet());
  });
}

/// A button that does nothing, for a test about the button's NAME.
void _noop() {}
