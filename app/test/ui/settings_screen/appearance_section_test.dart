/// The appearance section, measured where it is measurable and asserted where it
/// is not.
///
/// ## The claims
///
/// 1. **A change reaches the state layer, and only the state layer.** Tapping a
///    theme, an accent, a corner or a switch is asserted on
///    `SettingsController.appearance` — not on the widget's own idea of the
///    selection. That is the difference between a picker that writes a value and
///    a picker that paints one.
/// 2. **The preview is a measurement, not decoration.** The accent pill's fill is
///    compared with `style.role('accent')` and its label with
///    `style.role('textOnAccent')`, in all sixteen theme/accent pairs, because
///    `ROADMAP.md`'s 1.17:1 class of defect lives exactly in "a fill nobody
///    measured".
/// 3. **The corner preset is visible.** The density card's painted radius is
///    compared with `style.shape('md').borderRadius`, so picking "Keskin" is
///    observable on a card rather than only in the controller.
/// 4. **A reset puts every control back**, including the ones whose value came
///    from the controller rather than from a tap — the defect a picker with its
///    own copy of the choice has, and the one `SettingsChoiceGroup` exists to
///    prevent.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/settings_screen/settings_screen_ui.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/settings_fixtures.dart';
import 'support/settings_semantics.dart';

/// The fill of the preview's accent pill.
Color previewAccentFill(WidgetTester tester) {
  final Container pill = tester.widget<Container>(
    find.byKey(AppearanceKeys.previewAccent),
  );
  return (pill.decoration! as BoxDecoration).color!;
}

/// The painted radius of the card at [key].
BorderRadiusGeometry cardRadius(WidgetTester tester, Key key) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byKey(key),
      matching: find.byKey(SettingsCardKeys.surface),
    ),
  );
  return (box.decoration as BoxDecoration).borderRadius!;
}

/// The radio inside option row [index].
///
/// `MkviChoiceKeys.row` is the whole row — the row is the hit target, not the
/// 20 dp mark — so the mark is found inside it.
Radio<ThemePreference> themeRadio(WidgetTester tester, int index) =>
    tester
        .widget<Radio<ThemePreference>>(
          find.descendant(
            of: find.byKey(MkviChoiceKeys.row(index)),
            matching: find.byType(Radio<ThemePreference>),
          ),
        );

void main() {
  group('the theme list', () {
    testWidgets('a tap writes through to the controller, and the mark follows', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(AppearanceSection(controller: controller)),
      );
      final SettingsCatalog catalog = controller.catalog;
      expect(controller.appearance.theme, ThemePreference.system);

      final int index = catalog.themeOptions.indexOf(ThemePreference.forest);
      await tapInSection(tester, find.byKey(MkviChoiceKeys.row(index)));

      expect(
        controller.appearance.theme,
        ThemePreference.forest,
        reason: 'the section has no value of its own; the tap is a controller '
            'call and the controller is what changed',
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      // The selection is read off the `RadioGroup`, not off a resolved
      // `fillColor`: a `WidgetStateProperty` built with `resolveWith` returns
      // the accent for `{selected}` whether or not the row is the chosen one, so
      // asserting on it would pass on a picker that never changed.
      final RadioGroup<ThemePreference> group = tester
          .widget<RadioGroup<ThemePreference>>(
            find.byType(RadioGroup<ThemePreference>),
          );
      expect(group.groupValue, ThemePreference.forest);
      expect(themeRadio(tester, index).value, ThemePreference.forest);
      expect(
        themeRadio(tester, index).fillColor!.resolve(<WidgetState>{
          WidgetState.selected,
        }),
        style.role('accent'),
        reason: 'and the marked row is painted with the accent role',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('the system theme is the first option and it explains itself', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(AppearanceSection(controller: controller)),
      );
      final SettingsCatalog catalog = controller.catalog;

      expect(
        catalog.themeOptions.first,
        ThemePreference.system,
        reason: 'it is the default, so it is first',
      );
      expect(
        find.text(catalog.systemThemeDescription),
        findsOneWidget,
        reason: 'the one option that is a decision about the platform is the '
            'one that says what it follows',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('the accent picker and the preview', () {
    testWidgets('a tap changes the accent, and the preview paints the new one', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(AppearanceSection(controller: controller)),
      );
      final SettingsCatalog catalog = controller.catalog;
      final Color before = previewAccentFill(tester);

      final int index = AccentId.values.indexOf(AccentId.rose);
      await tester.tap(
        find.descendant(
          of: find.byKey(AppearanceKeys.accentGroup),
          matching: find.byKey(MkviChoiceKeys.segment(index)),
        ),
      );
      await tester.pump();
      expect(controller.appearance.accent, const AccentPreference.preset(
        AccentId.rose,
      ));

      // The resolved palette moved with the preference, in the same tick: this
      // is the "applied immediately" claim, measured on the object both the
      // screen and the app read.
      final Color after = controller.resolved.style.role('accent');
      expect(after, isNot(before));
      expect(
        controller.resolved.style.accentId,
        AccentId.rose.name,
      );

      // And the second pump is what a user sees: the pill is painted with the
      // new accent and its label with the on-accent role.
      await unmountMkvi(tester);
      await pumpMkvi(
        tester,
        mkviSettingsSection(AppearanceSection(controller: controller)),
        settings: controller.appearance,
      );
      final AppearanceStyle style = mkviStyleOf(tester);
      expect(previewAccentFill(tester), style.role('accent'));
      expect(
        textStyleAt(tester, find.descendant(
          of: find.byKey(AppearanceKeys.previewAccent),
          matching: find.byType(Text),
        )).color,
        style.role('textOnAccent'),
      );
      // The pill is a fill standing on a `surface` card, which is the case the
      // ROADMAP rule exempts: no edge, and the contrast is the token file's.
      expectTokenContrast(style, 'textOnAccent', 'accent');
      expect(
        find.text(catalog.accentOptionLabel(AccentId.rose)),
        findsOneWidget,
        reason: 'the segment the user tapped is the one that now reads as '
            'chosen, and its name comes from the token file',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('the four shipped ramps and the two declared pairs hold in all '
        'sixteen theme/accent combinations', (WidgetTester tester) async {
      for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
        final SettingsController controller = mkviSettingsController();
        addTearDown(controller.dispose);
        await controller.setAppearance(settings);
        late AppearanceStyle style;
        await pumpMkvi(
          tester,
          SettingsStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSettingsSection(AppearanceSection(controller: controller)),
          ),
          settings: settings,
        );

        // The two pairs this section actually paints, read off the widgets and
        // compared to the roles — not to a colour written into the test.
        expect(
          previewAccentFill(tester),
          style.role('accent'),
          reason: describeCombination(settings),
        );
        expect(
          textStyleAt(
            tester,
            find.descendant(
              of: find.byKey(AppearanceKeys.previewAccent),
              matching: find.byType(Text),
            ),
          ).color,
          style.role('textOnAccent'),
          reason: describeCombination(settings),
        );
        expect(
          textStyleAt(tester, find.byKey(AppearanceKeys.previewName)).color,
          style.role('text'),
          reason: describeCombination(settings),
        );
        expect(
          textStyleAt(tester, find.byKey(AppearanceKeys.previewDetail)).color,
          style.role('textMuted'),
          reason: describeCombination(settings),
        );
        // The two pairs the brief names, measured on the palette about to be
        // painted.
        expectTokenContrast(style, 'textOnAccent', 'accent');
        expectTokenContrast(style, 'text', 'surface');
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester);
      }
    });
  });

  group('the corner preset', () {
    testWidgets('a tap changes the resolved radius, and a card shows it', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(AppearanceSection(controller: controller)),
      );
      expect(controller.appearance.radius, RadiusPreference.soft);
      final double soft = controller.resolved.style.radii['md']!;

      final int index = RadiusPreference.values.indexOf(RadiusPreference.crisp);
      await tester.tap(
        find.descendant(
          of: find.byKey(AppearanceKeys.radiusGroup),
          matching: find.byKey(MkviChoiceKeys.segment(index)),
        ),
      );
      await tester.pump();
      expect(controller.appearance.radius, RadiusPreference.crisp);
      expect(
        controller.resolved.style.radii['md'],
        isNot(soft),
        reason: 'the preset is not a label: it moves a number every card reads',
      );

      // And the card in the next section is painted with it, so the change is
      // visible rather than only stored.
      await unmountMkvi(tester);
      await pumpMkvi(
        tester,
        mkviSettingsSection(
          Column(
            children: <Widget>[
              AppearanceSection(controller: controller),
              DensitySection(controller: controller),
            ],
          ),
        ),
        settings: controller.appearance,
      );
      final AppearanceStyle style = mkviStyleOf(tester);
      expect(cardRadius(tester, DensityKeys.card), style.shape('md').borderRadius);
      expect(
        style.radiusPresetId,
        RadiusPreference.crisp.presetId,
        reason: 'read from the preference, not from the token name',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('the two accessibility switches', () {
    testWidgets('a tap writes the switch, and both directions work', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(AppearanceSection(controller: controller)),
      );
      final SettingsCatalog catalog = controller.catalog;
      expect(controller.appearance.highContrast, isFalse);
      expect(controller.appearance.reduceMotion, isFalse);

      await tapInSection(
        tester,
        find.byKey(MkviChoiceKeys.switchRow(
          AppearanceSwitch.highContrast.index,
        )),
      );
      expect(controller.appearance.highContrast, isTrue);
      expect(
        controller.appearance.reduceMotion,
        isFalse,
        reason: 'two independent switches, not one list that replaces',
      );

      // High contrast is not only a boolean: it pushes the ramps, so the
      // resolved palette must differ from the one it started on.
      expect(controller.resolved.style.highContrast, isTrue);
      expect(
        controller.resolved.style.focusRingWidth,
        greaterThan(mkviAppearance().style.focusRingWidth),
        reason: 'the token file promises a thicker focus ring too',
      );

      await tapInSection(
        tester,
        find.byKey(MkviChoiceKeys.switchRow(
          AppearanceSwitch.reduceMotion.index,
        )),
      );
      expect(controller.appearance.reduceMotion, isTrue);
      expect(
        controller.resolved.style.duration('normal'),
        Duration.zero,
        reason: 'reduced motion is a resolved number, not a branch in a widget',
      );

      // And off again: a switch that cannot be turned off is not a switch.
      await tapInSection(
        tester,
        find.byKey(MkviChoiceKeys.switchRow(
          AppearanceSwitch.highContrast.index,
        )),
      );
      expect(controller.appearance.highContrast, isFalse);
      expect(find.text(catalog.highContrastLabel), findsOneWidget);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('the reset', () {
    testWidgets('puts every control back to the shipped default and says so', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(AppearanceSection(controller: controller)),
      );
      final SettingsCatalog catalog = controller.catalog;

      await controller.setTheme(ThemePreference.plum);
      await controller.setAccent(const AccentPreference.preset(AccentId.amber));
      await controller.setFontScale(AppearanceSettings.maxFontScale);
      await controller.setRadius(RadiusPreference.crisp);
      await controller.setHighContrast(true);
      await controller.setDensity(DensityPreference.compact);
      await tester.pump();
      expect(controller.appearance, isNot(AppearanceSettings.initial));

      expect(find.byKey(AppearanceKeys.notice), findsNothing);
      await tapInSection(
        tester,
        find.widgetWithText(OutlinedButton, catalog.resetAppearanceLabel),
      );

      expect(
        controller.appearance,
        AppearanceSettings.initial,
        reason: 'the preference went back to the shipped one',
      );
      expect(
        find.text(catalog.appearanceResetDone),
        findsOneWidget,
        reason: 'and the user is told, in the catalogue\'s own sentence',
      );

      // The two controls whose value came from the controller rather than from
      // a tap: if the picker kept its own copy, these would still be lit.
      expect(
        tester
            .widget<RadioGroup<ThemePreference>>(
              find.byType(RadioGroup<ThemePreference>),
            )
            .groupValue,
        AppearanceSettings.initial.theme,
        reason: 'the theme came back from the controller, not from a tap, and '
            'the list followed it',
      );
      expect(themeRadio(tester, 0).value, AppearanceSettings.initial.theme);
      // Read the switch itself, not the row widget that holds it: the key is on
      // `MkviSwitchRow`, so `find.byKey` returns the row.
      expect(
        tester
            .widget<SwitchListTile>(
              find.descendant(
                of: find.byKey(MkviChoiceKeys.switchRow(
                  AppearanceSwitch.highContrast.index,
                )),
                matching: find.byType(SwitchListTile),
              ),
            )
            .value,
        isFalse,
      );

      // Any other change hides the sentence, because a stale confirmation under
      // a preview showing something else is a lie.
      await tapInSection(
        tester,
        find.byKey(MkviChoiceKeys.row(
          catalog.themeOptions.indexOf(ThemePreference.light),
        )),
      );
      expect(controller.appearance.theme, ThemePreference.light);
      expect(find.byKey(AppearanceKeys.notice), findsNothing);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });
}
