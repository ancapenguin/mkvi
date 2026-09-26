/// The choice controls, and the catalogue that feeds them.
///
/// Three claims are measured here rather than asserted in prose:
///
/// * the COLOURS, read off the widgets themselves and compared to the token
///   roles - because `ThemeData` fills the switch but not the radio, the slider
///   or a segmented control, and Material's defaults for those three are
///   computed from `ColorScheme` rather than from `tokens.json`;
/// * the ROADMAP's surface rule - an accent fill on `surface` takes no edge and
///   the same fill on `surfaceRaised` takes a `borderStrong` one - measured as a
///   `BorderSide` on the box, in both directions, because a rule that is only
///   ever tested in one direction is a rule that can be dropped;
/// * the FEEDBACK, counted: a tap that changes nothing publishes nothing, and a
///   tap that changes something publishes exactly once, with the selection
///   before and after.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/widget_fixtures.dart';

void main() {
  group('the radio row', () {
    testWidgets('the selected mark is the accent fill and the other one is not', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviOptionRow<TestDensity>(
            value: TestDensity.compact,
            groupValue: TestDensity.compact,
            onChanged: (TestDensity? _) {},
            label: testDensityTr(TestDensity.compact),
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);
      final Radio<TestDensity> radio = tester.widget<Radio<TestDensity>>(
        find.byType(Radio<TestDensity>),
      );

      expect(
        radio.fillColor!.resolve(<WidgetState>{WidgetState.selected}),
        style.role('accent'),
      );
      expect(radio.fillColor!.resolve(<WidgetState>{}), style.role('surfaceRaised'));
      expect(radio.side!.color, style.role('borderStrong'));
      expect(radio.side!.width, style.borderWidth);
      expect(radio.backgroundColor!.resolve(<WidgetState>{}), style.role('surface'));
    });

    testWidgets('the whole row is the target, and tapping it chooses', (
      WidgetTester tester,
    ) async {
      TestDensity? chosen;
      await pumpMkvi(
        tester,
        InputHost(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final TestDensity density in TestDensity.values)
                MkviOptionRow<TestDensity>(
                  key: MkviChoiceKeys.row(density.index),
                  value: density,
                  groupValue: TestDensity.cozy,
                  onChanged: (TestDensity? value) => chosen = value,
                  label: testDensityTr(density),
                ),
            ],
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      for (final TestDensity density in TestDensity.values) {
        expectHitTarget(
          tester,
          find.byKey(MkviChoiceKeys.row(density.index)),
          style: style,
        );
      }

      // The tap lands on the row, not on the mark: a mark is 20 dp and the
      // promise is 44.
      await tester.tap(find.byKey(MkviChoiceKeys.row(2)));
      await tester.pump();
      expect(chosen, TestDensity.roomy);
    });

    testWidgets('rows inside one group are one group, not one group each', (
      WidgetTester tester,
    ) async {
      final MkviChoiceCatalog<TestDensity> catalog = testDensityCatalog(
        selection: <TestDensity>{TestDensity.cozy},
      );
      addTearDown(catalog.dispose);
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviChoiceGroup<TestDensity>(catalog: catalog),
        ),
      );

      expect(find.byType(RadioGroup<TestDensity>), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<TestDensity>>(
              find.byType(RadioGroup<TestDensity>),
            )
            .groupValue,
        TestDensity.cozy,
      );

      await tester.tap(find.byKey(MkviChoiceKeys.row(2)));
      await tester.pump();

      expect(catalog.value, TestDensity.roomy);
      expect(
        catalog.selection,
        <TestDensity>{TestDensity.roomy},
        reason: 'a single choice replaces, it does not accumulate',
      );
    });
  });

  group('the segmented row, and the ROADMAP surface rule', () {
    testWidgets('the selected segment is textOnAccent on the accent', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviSegmentedRow<TestDensity>(
            values: TestDensity.values,
            selected: TestDensity.compact,
            labelFor: testDensityTr,
            onChanged: (TestDensity _) {},
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      Text textIn0(int index) => tester.widget<Text>(
        find.descendant(
          of: find.byKey(MkviChoiceKeys.segment(index)),
          matching: find.byType(Text),
        ),
      );

      expect(textIn0(0).style!.color, style.role('textOnAccent'));
      expect(
        (tester
                .widget<Container>(find.byKey(MkviChoiceKeys.segment(0)))
                .decoration
            as BoxDecoration)
            .color,
        style.role('accent'),
      );
      expect(textIn0(1).style!.color, style.role('text'));
      expect(
        (tester
                .widget<Container>(find.byKey(MkviChoiceKeys.segment(1)))
                .decoration
            as BoxDecoration)
            .color,
        style.role('surface'),
        reason: 'an unselected segment is the surface it rests on, not a fill',
      );

      // The two pairs the control actually paints, measured in the palette.
      expectTokenContrast(style, 'textOnAccent', 'accent');
      expectTokenContrast(style, 'text', 'surface');
      for (final TestDensity density in TestDensity.values) {
        expectHitTarget(
          tester,
          find.byKey(MkviChoiceKeys.segment(density.index)),
          style: style,
        );
      }
    });

    testWidgets('on a plain surface the accent fill takes no edge at all', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        InputHost(
          surfaceRole: 'surface',
          child: MkviSegmentedRow<TestDensity>(
            values: TestDensity.values,
            selected: TestDensity.cozy,
            labelFor: testDensityTr,
            onChanged: (TestDensity _) {},
            resting: MkviRestingSurface.surface,
          ),
        ),
      );

      expect(
        (tester
                .widget<Container>(find.byKey(MkviChoiceKeys.segmentedBorder))
                .decoration
            as BoxDecoration?)
            ?.border,
        isNull,
        reason:
            'ROADMAP: on bg/surface an accent-filled button needs no edge, and '
            'an edge here would be a line the design never asked for',
      );
    });

    testWidgets('on a raised surface the same fill takes a borderStrong edge', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        InputHost(
          surfaceRole: 'surfaceRaised',
          child: MkviSegmentedRow<TestDensity>(
            values: TestDensity.values,
            selected: TestDensity.cozy,
            labelFor: testDensityTr,
            onChanged: (TestDensity _) {},
            resting: MkviRestingSurface.raised,
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);
      final BoxDecoration decoration = tester
          .widget<Container>(find.byKey(MkviChoiceKeys.segmentedBorder))
          .decoration! as BoxDecoration;

      expect(
        decoration.border!.top.color,
        style.role('borderStrong'),
        reason:
            'ROADMAP: on surfaceRaised/surfaceSoft an accent-filled button '
            'needs an edge, or the fill is a smudge the eye has to find',
      );
      expect(decoration.border!.top.width, style.borderWidth);
      expect(
        tester.widget<Container>(find.byKey(MkviChoiceKeys.segmentedBorder)).padding,
        EdgeInsets.all(style.borderWidth),
        reason: 'the edge is inside the padding, so the segments do not move',
      );
    });
  });

  group('the slider row', () {
    testWidgets('it snaps to the token step, and never leaves the range', (
      WidgetTester tester,
    ) async {
      double? moved;
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviSliderRow(
            label: 'Yazı tipi boyutu',
            value: AppearanceSettings.defaultFontScale,
            min: AppearanceSettings.minFontScale,
            max: AppearanceSettings.maxFontScale,
            step: AppearanceSettings.fontScaleStep,
            valueLabel: testFontScaleTr,
            minLabel: testFontScaleTr(AppearanceSettings.minFontScale),
            maxLabel: testFontScaleTr(AppearanceSettings.maxFontScale),
            onChanged: (double value) => moved = value,
          ),
        ),
      );
      final Slider slider = tester.widget<Slider>(
        find.byKey(MkviChoiceKeys.slider),
      );

      // 0.9 to 1.25 in 0.05 steps is seven stops, and a value off a stop is a
      // setting the codec would have to report as corrected.
      expect(slider.divisions, 7);
      expect(slider.min, AppearanceSettings.minFontScale);
      expect(slider.max, AppearanceSettings.maxFontScale);
      expect(slider.semanticFormatterCallback!(1.1), '%110');
      expect(slider.label, '%100');

      await tester.drag(find.byKey(MkviChoiceKeys.slider), const Offset(600, 0));
      await tester.pump();
      expect(
        moved,
        AppearanceSettings.maxFontScale,
        reason: 'dragged to the end is the token maximum, not 1.9',
      );
      expect(
        testFontScaleTr(moved!),
        '%125',
        reason: 'and the label the settings screen shows is that number',
      );
    });

    testWidgets('the track, the thumb and the target are token roles', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviSliderRow(
            label: 'Yazı tipi boyutu',
            value: 1.0,
            min: 0.9,
            max: 1.25,
            step: 0.05,
            valueLabel: testFontScaleTr,
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);
      final SliderTheme theme = tester.widget<SliderTheme>(
        find.byType(SliderTheme),
      );

      expect(theme.data.activeTrackColor, style.role('accent'));
      expect(theme.data.thumbColor, style.role('accent'));
      expect(theme.data.inactiveTrackColor, style.role('border'));
      expectHitTarget(
        tester,
        find.byKey(MkviChoiceKeys.sliderTarget),
        style: style,
      );
    });
  });

  group('the switch row', () {
    testWidgets('its track is the accent when it is on, and it is a target', (
      WidgetTester tester,
    ) async {
      bool? turned;
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviSwitchRow(
            key: MkviChoiceKeys.switchRow(0),
            value: true,
            onChanged: (bool value) => turned = value,
            label: 'Yüksek karşıtlık',
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);
      final SwitchListTile tile = tester.widget<SwitchListTile>(
        find.descendant(
          of: find.byKey(MkviChoiceKeys.switchRow(0)),
          matching: find.byType(SwitchListTile),
        ),
      );

      expect(tile.trackColor!.resolve(<WidgetState>{WidgetState.selected}), style.role('accent'));
      expect(
        tile.trackColor!.resolve(<WidgetState>{}),
        style.role('border'),
      );
      expect(
        tile.thumbColor!.resolve(<WidgetState>{WidgetState.selected}),
        style.role('textOnAccent'),
      );
      expectHitTarget(tester, find.byKey(MkviChoiceKeys.switchRow(0)), style: style);
      expectTokenContrast(style, 'textOnAccent', 'accent');

      await tester.tap(find.byKey(MkviChoiceKeys.switchRow(0)));
      await tester.pump();
      expect(turned, isFalse);
    });
  });

  group('the catalogue is the only place a selection lives', () {
    test('it refuses a value that is not one of its options', () {
      // Two options, so the third is a value this catalogue genuinely does not
      // have - the shape of a screen that offers a subset.
      final MkviChoiceCatalog<TestDensity> catalog = MkviChoiceCatalog<TestDensity>(
        label: 'Yoğunluk',
        options: <MkviChoiceOption<TestDensity>>[
          for (final TestDensity density in <TestDensity>[
            TestDensity.compact,
            TestDensity.cozy,
          ])
            MkviChoiceOption<TestDensity>(
              value: density,
              label: testDensityTr(density),
            ),
        ],
      );
      addTearDown(catalog.dispose);
      expect(catalog.options.length, 2);
      expect(
        () => catalog.labelOf(TestDensity.compact),
        returnsNormally,
      );
      expect(
        () => catalog.select(TestDensity.roomy),
        throwsA(isA<StateError>()),
        reason: 'a value the catalogue does not have must fail at the tap',
      );
      expect(
        () => catalog.labelOf(TestDensity.roomy),
        throwsA(isA<StateError>()),
        reason: 'and a label lookup must fail rather than return an empty string',
      );
    });

    test('it refuses an initial selection it does not have an option for', () {
      expect(
        () => MkviChoiceCatalog<TestDensity>(
          label: 'Yoğunluk',
          selection: <TestDensity>{TestDensity.roomy},
          options: <MkviChoiceOption<TestDensity>>[
            MkviChoiceOption<TestDensity>(
              value: TestDensity.compact,
              label: testDensityTr(TestDensity.compact),
            ),
          ],
        ),
        throwsA(isA<StateError>()),
        reason: 'a stored value with no option is a crash, not an empty list',
      );
    });

    test('a selection that did not change publishes nothing', () {
      int published = 0;
      final MkviChoiceCatalog<TestDensity> catalog = testDensityCatalog(
        selection: <TestDensity>{TestDensity.cozy},
        onDidChange: (Set<TestDensity> _, Set<TestDensity> _) => published += 1,
      );
      addTearDown(catalog.dispose);

      catalog.select(TestDensity.cozy);
      expect(published, 0);
      expect(catalog.selection, <TestDensity>{TestDensity.cozy});

      catalog.select(TestDensity.roomy);
      expect(published, 1);
      expect(catalog.selection, <TestDensity>{TestDensity.roomy});
    });

    test('a multiple-choice catalogue accumulates, and can go back to empty', () {
      final MkviChoiceCatalog<TestDensity> catalog = testDensityCatalog(
        multiple: true,
      );
      addTearDown(catalog.dispose);

      catalog.select(TestDensity.compact);
      catalog.select(TestDensity.roomy);
      expect(catalog.selection, <TestDensity>{
        TestDensity.compact,
        TestDensity.roomy,
      });
      expect(catalog.value, isNull, reason: 'two of three is not one value');

      catalog.select(TestDensity.compact);
      catalog.select(TestDensity.roomy);
      expect(catalog.selection, isEmpty);
    });

    test('a screen that owns the value drives the same feedback path', () {
      final List<String> seen = <String>[];
      final MkviChoiceCatalog<TestDensity> catalog = testDensityCatalog(
        onDidChange: (Set<TestDensity> previous, Set<TestDensity> next) =>
            seen.add('${previous.length}->${next.length}'),
      );
      addTearDown(catalog.dispose);

      catalog.didChange(
        <TestDensity>{TestDensity.cozy},
        <TestDensity>{TestDensity.compact},
      );
      expect(seen, <String>['1->1']);
      expect(catalog.value, TestDensity.compact);

      // The same call with the same set publishes nothing at all.
      catalog.didChange(
        <TestDensity>{TestDensity.compact},
        <TestDensity>{TestDensity.compact},
      );
      expect(seen.length, 1);
    });
  });

  group('the group draws the catalogue and nothing else', () {
    testWidgets('every label on screen came from the catalogue', (
      WidgetTester tester,
    ) async {
      final MkviChoiceCatalog<TestDensity> catalog = testDensityCatalog(
        selection: <TestDensity>{TestDensity.cozy},
      );
      addTearDown(catalog.dispose);
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviChoiceGroup<TestDensity>(catalog: catalog),
        ),
      );

      expect(find.text(catalog.label), findsOneWidget);
      for (final MkviChoiceOption<TestDensity> option in catalog.options) {
        expect(find.text(option.label), findsOneWidget);
        expect(find.text(option.description!), findsOneWidget);
      }
      expect(
        find.text('Yoğunluk'),
        findsOneWidget,
        reason: 'a segment or a row with an English label would be a new one',
      );
    });

    testWidgets('a switch list is refused for a single-choice catalogue', (
      WidgetTester tester,
    ) async {
      final MkviChoiceCatalog<TestDensity> single = testDensityCatalog();
      addTearDown(single.dispose);
      expect(
        () => MkviChoiceGroup<TestDensity>(
          catalog: single,
          layout: MkviChoiceLayout.switches,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'a switch cannot say "none of these"',
      );
    });

    testWidgets('a segmented group draws the catalogue in segments', (
      WidgetTester tester,
    ) async {
      TestDensity? chosen;
      final MkviChoiceCatalog<TestDensity> catalog = testDensityCatalog(
        selection: <TestDensity>{TestDensity.compact},
      );
      addTearDown(catalog.dispose);
      await pumpMkvi(
        tester,
        InputHost(
          surfaceRole: 'surfaceRaised',
          child: MkviChoiceGroup<TestDensity>(
            catalog: catalog,
            layout: MkviChoiceLayout.segmented,
            resting: MkviRestingSurface.raised,
            onChanged: (TestDensity value) => chosen = value,
          ),
        ),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      expect(
        (tester
                .widget<Container>(find.byKey(MkviChoiceKeys.segmentedBorder))
                .decoration
            as BoxDecoration)
            .border!
            .top
            .color,
        style.role('borderStrong'),
      );
      await tester.tap(find.byKey(MkviChoiceKeys.segment(1)));
      await tester.pump();
      expect(chosen, TestDensity.cozy);
      expect(catalog.value, TestDensity.cozy);
    });

    testWidgets('a switch group toggles one entry at a time', (
      WidgetTester tester,
    ) async {
      final MkviChoiceCatalog<TestDensity> catalog = testDensityCatalog(
        multiple: true,
        selection: <TestDensity>{TestDensity.compact},
      );
      addTearDown(catalog.dispose);
      await pumpMkvi(
        tester,
        InputHost(
          child: MkviChoiceGroup<TestDensity>(
            catalog: catalog,
            layout: MkviChoiceLayout.switches,
          ),
        ),
      );

      await tester.tap(find.byKey(MkviChoiceKeys.switchRow(2)));
      await tester.pump();
      expect(catalog.selection, <TestDensity>{
        TestDensity.compact,
        TestDensity.roomy,
      });
      await tester.tap(find.byKey(MkviChoiceKeys.switchRow(0)));
      await tester.pump();
      expect(catalog.selection, <TestDensity>{TestDensity.roomy});
    });
  });

  group('the matrix ROADMAP.md Faz 2 asks for', () {
    testWidgets('every layout paints in every theme and accent', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
        for (final MkviChoiceLayout layout in MkviChoiceLayout.values) {
          await unmountMkvi(tester);
          final MkviChoiceCatalog<TestDensity> catalog = testDensityCatalog(
            multiple: layout == MkviChoiceLayout.switches,
            selection: <TestDensity>{TestDensity.compact},
          );
          addTearDown(catalog.dispose);
          await pumpMkvi(
            tester,
            InputHost(
              surfaceRole: 'surfaceRaised',
              child: MkviChoiceGroup<TestDensity>(catalog: catalog, layout: layout),
            ),
            settings: settings,
          );
          expectNoOverflow(tester);
          final AppearanceStyle style = mkviStyleOf(tester);
          expectTokenContrast(style, 'text', 'surface');
          expectTokenContrast(style, 'textMuted', 'surface');
          expectTokenContrast(style, 'textOnAccent', 'accent');
        }
      }
    });

    testWidgets('every layout paints at every scale and density', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviScaleMatrix()) {
        for (final MkviChoiceLayout layout in MkviChoiceLayout.values) {
          await unmountMkvi(tester);
          final MkviChoiceCatalog<TestDensity> catalog = testDensityCatalog(
            multiple: layout == MkviChoiceLayout.switches,
            selection: <TestDensity>{TestDensity.compact},
          );
          addTearDown(catalog.dispose);
          await pumpMkvi(
            tester,
            InputHost(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  MkviChoiceGroup<TestDensity>(catalog: catalog, layout: layout),
                  MkviSliderRow(
                    label: 'Yazı tipi boyutu',
                    value: 1.0,
                    min: AppearanceSettings.minFontScale,
                    max: AppearanceSettings.maxFontScale,
                    step: AppearanceSettings.fontScaleStep,
                    valueLabel: testFontScaleTr,
                  ),
                ],
              ),
            ),
            settings: settings,
          );
          expectNoOverflow(tester);
        }
      }
    });
  });
}

