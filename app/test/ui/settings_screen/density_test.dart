/// The density, measured on the rows it moves rather than on the label.
///
/// `density` was honoured in 8 call sites out of ~40 in 0.1.x, because it was a
/// value nobody was obliged to read. The state layer fixed the cause — one
/// resolved `space` map — but a picker that only says "Sıkışık" or "Rahat" asks
/// the user to take the word for it, and a test that only asserts
/// `controller.appearance.density` cannot tell a density that changed from a
/// density that is only stored.
///
/// So the claim here is a **gap**: the three sample rows under the picker are
/// separated by `style.gap('2')`, and this file measures that distance at
/// `compact` and at `comfortable` and fails if the two are equal. A section that
/// stopped scaling its rows goes red; a section that stored the preference
/// correctly and drew nothing differently stays green — which is the defect.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/settings_screen/settings_screen_ui.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/settings_fixtures.dart';
import 'support/settings_semantics.dart';

/// The vertical distance between sample row [index] and the one after it.
double gapBetweenRows(WidgetTester tester, int index) =>
    tester.getRect(find.byKey(DensityKeys.row(index + 1))).top -
    tester.getRect(find.byKey(DensityKeys.row(index))).bottom;

void main() {
  group('the picker', () {
    testWidgets('offers one segment per preference, named by the catalogue', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(DensitySection(controller: controller)),
      );
      final SettingsCatalog catalog = controller.catalog;

      // Two, not three: the token file declares `compact`, `cozy` and `roomy`
      // and `DensityPreference` has two values, so the screen can only offer
      // two. Asserted here so the gap is a fact and not a habit.
      expect(DensityPreference.values, hasLength(2));
      expect(
        DensityPreference.values.map(
          (DensityPreference density) => density.densityId,
        ),
        <String>['compact', 'cozy'],
        reason: 'the ids are the token file\'s, read through the enum',
      );

      for (int index = 0; index < DensityPreference.values.length; index += 1) {
        expect(
          find.descendant(
            of: find.byKey(DensityKeys.card),
            matching: find.byKey(MkviChoiceKeys.segment(index)),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            catalog.densityOptionLabel(DensityPreference.values[index]),
          ),
          findsOneWidget,
        );
      }
      expect(find.text(catalog.densityDescription), findsOneWidget);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('a tap writes the preference and the resolved density with it', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(DensitySection(controller: controller)),
      );
      final SettingsCatalog catalog = controller.catalog;
      expect(controller.appearance.density, DensityPreference.comfortable);

      await tapInSection(
        tester,
        find.descendant(
          of: find.byKey(DensityKeys.card),
          matching: find.byKey(
            MkviChoiceKeys.segment(
              DensityPreference.values.indexOf(DensityPreference.compact),
            ),
          ),
        ),
      );

      expect(controller.appearance.density, DensityPreference.compact);
      expect(
        controller.resolved.style.density,
        lessThan(mkviAppearance().style.density),
        reason: 'the resolved number every widget reads moved, not the label',
      );
      expect(find.text(catalog.densityCompactLabel), findsOneWidget);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('the sample rows', () {
    testWidgets('are separated by the resolved gap, and the two densities differ', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);

      final Map<DensityPreference, double> gapByDensity =
          <DensityPreference, double>{};
      final Map<DensityPreference, double> expectedByDensity =
          <DensityPreference, double>{};

      for (final DensityPreference density in DensityPreference.values) {
        await controller.setDensity(density);
        late AppearanceStyle style;
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          SettingsStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSettingsSection(DensitySection(controller: controller)),
          ),
          settings: controller.appearance,
        );

        final double step = style.gap('2');
        expectedByDensity[density] = step;
        for (int index = 0; index < 2; index += 1) {
          expect(
            gapBetweenRows(tester, index),
            closeTo(step, 0.01),
            reason: 'the rows are one $density space step apart, measured as a '
                'rectangle gap',
          );
        }
        gapByDensity[density] = gapBetweenRows(tester, 0);
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester);
      }

      expect(
        gapByDensity[DensityPreference.compact]!,
        lessThan(gapByDensity[DensityPreference.comfortable]!),
        reason: 'and the two are not the same number: a density that is only '
            'stored is not a density',
      );
      expect(
        expectedByDensity[DensityPreference.compact]!,
        lessThan(expectedByDensity[DensityPreference.comfortable]!),
      );
    });

    testWidgets('hold at both type ends and in all sixteen theme/accent pairs', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);

      for (final AppearanceSettings settings in <AppearanceSettings>[
        ...mkviAppearanceMatrix(),
        ...mkviScaleMatrix(),
      ]) {
        await controller.setAppearance(settings);
        late AppearanceStyle style;
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          SettingsStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSettingsSection(DensitySection(controller: controller)),
          ),
          settings: controller.appearance,
        );

        expect(
          gapBetweenRows(tester, 0),
          closeTo(style.gap('2'), 0.01),
          reason: describeCombination(settings),
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester);
      }
    });
  });
}
