/// The type scale, measured at both ends of the slider's range.
///
/// `ROADMAP.md` Faz 2:
///
/// > **Ölçek/yoğunluk her yerde** (0.1.x'te `fontScale` ilk ekranlarda etkisizdi).
///
/// This file is the measurement that claim is supposed to pass, and it is
/// written to go **red** if the screen stops honouring the user's scale:
///
/// * after `controller.setFontScale(1.25)` the resolved style's `fontScale` is
///   `1.25` **and** the sample text's `fontSize` is exactly
///   `style.typeStep('lg').size` — a token multiplied by the user's number, not
///   a literal. A screen that painted a hard-coded size would fail here while
///   every other test on it stayed green;
/// * the same two numbers at `0.9` are *smaller*, so the test says "the change
///   moved the text" and not merely "the text has a size";
/// * the slider's own labels are not elided at either end, measured with a
///   [TextPainter] against the laid-out box: a clipped label and a fitted one
///   have the same widget, so only the two numbers tell them apart;
/// * neither end overflows in a 320 dp column, in any of the sixteen
///   theme/accent pairs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/settings_screen/settings_screen_ui.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/settings_fixtures.dart';
import 'support/settings_semantics.dart';

/// The `fontSize` the sample at [key] is painted with.
double sampleFontSize(WidgetTester tester, Key key) =>
    textStyleAt(tester, find.byKey(key)).fontSize!;

void main() {
  group('the slider', () {
    testWidgets('offers exactly the range and the step the preference owns', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(TypeScaleSection(controller: controller)),
      );
      final SettingsCatalog catalog = controller.catalog;
      final Slider slider = tester.widget<Slider>(
        find.byKey(MkviChoiceKeys.slider),
      );

      expect(slider.min, AppearanceSettings.minFontScale);
      expect(slider.max, AppearanceSettings.maxFontScale);
      expect(slider.value, AppearanceSettings.defaultFontScale);
      // 0.9 to 1.25 in steps of 0.05 is seven intervals — eight stops, seven
      // gaps — and `divisions` counts the gaps. `divisions` is what makes the
      // value snap: without it a slider hands back 0.0833 and the codec then has
      // to report the stored value as corrected on the next read.
      expect(slider.divisions, 7);
      expect(
        slider.divisions,
        ((AppearanceSettings.maxFontScale - AppearanceSettings.minFontScale) /
                AppearanceSettings.fontScaleStep)
            .round(),
        reason: 'the stops are the preference\'s, not a number in this test',
      );
      expect(
        slider.semanticFormatterCallback!(AppearanceSettings.maxFontScale),
        catalog.fontScaleMaximumLabel,
      );
      expect(
        find.text(catalog.fontScaleMinimumLabel),
        findsOneWidget,
        reason: 'both ends are named, so the user knows what the slider spans',
      );
      expect(find.text(catalog.fontScaleMaximumLabel), findsOneWidget);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('a change reaches the type, immediately', () {
    /// The two sample sizes, the style's own scale, and the slider's value.
    ({double small, double large, double scale, double value}) measureType(
      WidgetTester tester,
      SettingsController controller,
    ) {
      final AppearanceStyle style = mkviStyleOf(tester);
      return (
        small: sampleFontSize(tester, TypeScaleKeys.sampleSmall),
        large: sampleFontSize(tester, TypeScaleKeys.sampleLarge),
        scale: style.fontScale,
        value: tester.widget<Slider>(find.byKey(MkviChoiceKeys.slider)).value,
      );
    }

    testWidgets('setFontScale(1.25) reaches the resolved style and the sample', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(TypeScaleSection(controller: controller)),
      );

      final ({double small, double large, double scale, double value}) before =
          measureType(tester, controller);

      // The one call the settings screen makes. No pump in between, no re-read:
      // the preference is normalised and re-resolved inside it.
      await controller.setFontScale(AppearanceSettings.maxFontScale);
      expect(controller.resolved.style.fontScale, 1.25);

      // The theme the tree is painted with comes from the same controller, so
      // the second pump is what the app would show after the change.
      await unmountMkvi(tester);
      await pumpMkvi(
        tester,
        mkviSettingsSection(TypeScaleSection(controller: controller)),
        settings: controller.appearance,
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      expect(
        style.fontScale,
        1.25,
        reason: 'the resolved style carries the user\'s number',
      );
      expect(
        sampleFontSize(tester, TypeScaleKeys.sampleSmall),
        style.typeStep('sm').size,
        reason: 'and the small sample is painted at the resolved sm step, so '
            'the sample IS the measurement of the scale',
      );
      expect(
        sampleFontSize(tester, TypeScaleKeys.sampleLarge),
        style.typeStep('lg').size,
      );
      expect(
        tester.widget<Slider>(find.byKey(MkviChoiceKeys.slider)).value,
        1.25,
        reason: 'and the slider itself moved to where the user put it',
      );
      // Direction, not just equality: 1.25 is bigger than 1.0.
      expect(measureType(tester, controller).large, greaterThan(before.large));
      expect(measureType(tester, controller).small, greaterThan(before.small));
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('the scale is quantised, so a stored value is always on a step', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      // 1.23 is not on the 0.05 grid; the layer snaps it rather than storing a
      // number the codec would have to report as corrected on the next read.
      await controller.setFontScale(1.23);
      expect(controller.appearance.fontScale, 1.25);
      expect(AppearanceSettings.isFontScaleNormalised(1.25), isTrue);

      // And an out-of-range value is clamped rather than stored.
      await controller.setFontScale(9);
      expect(controller.appearance.fontScale, AppearanceSettings.maxFontScale);
      await controller.setFontScale(0.1);
      expect(controller.appearance.fontScale, AppearanceSettings.minFontScale);

      await unmountMkvi(tester);
      await pumpMkvi(
        tester,
        mkviSettingsSection(TypeScaleSection(controller: controller)),
        settings: controller.appearance,
      );
      final AppearanceStyle style = mkviStyleOf(tester);
      expect(style.fontScale, AppearanceSettings.minFontScale);
      expect(
        sampleFontSize(tester, TypeScaleKeys.sampleLarge),
        style.typeStep('lg').size,
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('both ends of the range', () {
    testWidgets('the sample lines get smaller at the minimum and bigger at the '
        'maximum, and the slider follows', (WidgetTester tester) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);

      final Map<double, double> largeByScale = <double, double>{};
      for (final double scale in <double>[
        AppearanceSettings.minFontScale,
        AppearanceSettings.defaultFontScale,
        AppearanceSettings.maxFontScale,
      ]) {
        await controller.setFontScale(scale);
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          mkviSettingsSection(TypeScaleSection(controller: controller)),
          settings: controller.appearance,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester);
        largeByScale[scale] = sampleFontSize(
          tester,
          TypeScaleKeys.sampleLarge,
        );
        expect(
          tester.widget<Slider>(find.byKey(MkviChoiceKeys.slider)).value,
          scale,
          reason: 'at $scale the thumb is at $scale',
        );
      }

      expect(largeByScale.keys, hasLength(3));
      expect(
        largeByScale[AppearanceSettings.minFontScale]!,
        lessThan(largeByScale[AppearanceSettings.defaultFontScale]!),
      );
      expect(
        largeByScale[AppearanceSettings.defaultFontScale]!,
        lessThan(largeByScale[AppearanceSettings.maxFontScale]!),
      );
    });

    testWidgets('the slider labels are not elided at either end', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      final SettingsCatalog catalog = controller.catalog;

      for (final double scale in <double>[
        AppearanceSettings.minFontScale,
        AppearanceSettings.maxFontScale,
      ]) {
        await controller.setFontScale(scale);
        late AppearanceStyle style;
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          SettingsStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSettingsSection(TypeScaleSection(controller: controller)),
          ),
          settings: controller.appearance,
        );

        // The value's own label and the slider's end label can be the same
        // string — at 0.9 the value IS "%90" — so each is found by the ROLE it
        // is painted in, not by its text alone. The role is read from the style
        // rather than written into the test, so a token change moves all three
        // numbers together.
        final List<(String, Color)> labels = <(String, Color)>[
          (catalog.fontScaleMinimumLabel, style.role('textMuted')),
          (catalog.fontScaleMaximumLabel, style.role('textMuted')),
          (catalog.fontScaleValue(scale), style.role('accent')),
        ];

        for (final (String label, Color colour) in labels) {
          final Finder finder = find.byWidgetPredicate(
            (Widget widget) =>
                widget is Text &&
                widget.data == label &&
                widget.style?.color == colour,
            description: 'the "$label" label in $colour',
          );
          expect(
            finder,
            findsOneWidget,
            reason: '"$label" at scale $scale, in the role it should be in',
          );
          final Text text = tester.widget<Text>(finder);
          final double laidOut = tester.getSize(finder).width;
          final double needed = intrinsicLineWidth(
            label,
            text.style ?? const TextStyle(),
          );
          expect(
            laidOut,
            closeTo(needed, 0.5),
            reason:
                '"$label" needs $needed px and was given $laidOut px at scale '
                '$scale: a label that is cut is not a label',
          );
        }
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester);
      }
    });

    testWidgets('neither end overflows, in any of the sixteen pairs', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      final SettingsCatalog catalog = controller.catalog;

      for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
        for (final double scale in <double>[
          AppearanceSettings.minFontScale,
          AppearanceSettings.maxFontScale,
        ]) {
          await controller.setAppearance(
            settings.copyWith(fontScale: scale),
          );
          await unmountMkvi(tester);
          await pumpMkvi(
            tester,
            mkviSettingsSection(TypeScaleSection(controller: controller)),
            settings: controller.appearance,
          );
          expect(
            // The percent is written with the catalogue's own function and
            // found on the slider's `label`, not by `find.text`: at either end
            // the value and the end label are the same string ("%90" is both),
            // and a test that matched by text alone would be counting two
            // labels as one.
            tester.widget<Slider>(find.byKey(MkviChoiceKeys.slider)).label,
            catalog.fontScaleValue(scale),
            reason: describeCombination(settings),
          );
          expectNoOverflow(tester);
          await expectEveryControlIsLabelled(tester);
        }
      }
    });
  });
}
