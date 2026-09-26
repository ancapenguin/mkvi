/// The settings screen as a page: its sections, its banner, its labels, and the
/// two interface rules `ROADMAP.md` asks a screen to keep.
///
/// ## What is measured here, and why each one is a measurement
///
/// * **Overflow, in the whole matrix at three window sizes.** 0.1.x shipped an
///   overflow in every one of its screens and none of them was caught, because
///   the tests were written at one width. 16 theme/accent pairs + 6
///   scale/density pairs + 4 accessibility pairs, at 1280x800, 720x640 and
///   400x720, in a 320 dp column — the width at which a `Row` can actually run
///   out of room.
/// * **Every label comes from `SettingsCatalog`.** A theme name typed into this
///   screen would drift from `design/tokens.json` silently; asserting the
///   catalogue's own strings appear on screen makes the drift a red test.
/// * **The filled-action edge rule, in both directions.** An accent fill on
///   `surface` takes no `borderStrong` edge and the same fill on `surfaceRaised`
///   takes one. The screen ships both cases, so both are measured here rather
///   than only in the widget layer's own test.
/// * **Hit targets.** 0.1.x's close button was 34 px; every control on this
///   screen is measured against `control.hitTargetMin` from the token file.
/// * **A corrected store is reported, a clean one is not.** Absence is not
///   corruption, so a fresh install must not be greeted with a warning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/settings_screen/settings_screen_ui.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/settings_fixtures.dart';
import 'support/settings_semantics.dart';

void main() {
  group('the page', () {
    testWidgets('is every section, in the order a user meets them', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(tester, mkviSettingsPage(controller));

      for (final Key section in <Key>[
        AppearanceKeys.themeGroup,
        AppearanceKeys.accentGroup,
        AppearanceKeys.previewCard,
        TypeScaleKeys.card,
        DensityKeys.card,
        ConnectionKeys.card,
        IdentityKeys.card,
        AboutKeys.card,
      ]) {
        expect(find.byKey(section), findsOneWidget, reason: '$section');
      }
      // The order is the claim, so measure it rather than trust the source.
      final List<Offset> tops = <Offset>[
        for (final Key section in <Key>[
          AppearanceKeys.themeGroup,
          AppearanceKeys.accentGroup,
          TypeScaleKeys.card,
          DensityKeys.card,
          ConnectionKeys.card,
          IdentityKeys.card,
          AboutKeys.card,
        ])
          tester.getTopLeft(find.byKey(section)),
      ];
      for (int index = 1; index < tops.length; index += 1) {
        expect(
          tops[index].dy,
          greaterThan(tops[index - 1].dy),
          reason: 'section $index is not below section ${index - 1}',
        );
      }

      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('paints every label from the catalogue, not from the screen', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(tester, mkviSettingsPage(controller));
      final SettingsCatalog catalog = controller.catalog;

      for (final String label in <String>[
        catalog.appearanceSection,
        catalog.themeLabel,
        catalog.systemThemeLabel,
        catalog.accentLabel,
        catalog.radiusLabel,
        catalog.accessibilitySection,
        catalog.highContrastLabel,
        catalog.reduceMotionLabel,
        catalog.fontScaleLabel,
        catalog.fontScaleMinimumLabel,
        catalog.fontScaleMaximumLabel,
        catalog.densityLabel,
        catalog.connectionSection,
        catalog.endpointLabel,
        catalog.iceServersLabel,
        catalog.saveLabel,
        catalog.selfNameLabel,
        catalog.resetAppearanceLabel,
        // The four theme names and the four accent names come from
        // `design/tokens.json` through the catalogue, so a renamed theme or a
        // renamed accent fails here instead of drifting on screen.
        for (final ThemePreference theme in ThemePreference.values)
          catalog.themeOptionLabel(theme),
        for (final AccentId accent in AccentId.values)
          catalog.accentOptionLabel(accent),
        for (final RadiusPreference radius in RadiusPreference.values)
          catalog.radiusOptionLabel(radius),
        for (final DensityPreference density in DensityPreference.values)
          catalog.densityOptionLabel(density),
      ]) {
        expect(find.text(label), findsWidgets, reason: '"$label" is not on screen');
      }

      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('says nothing about a store nobody has written', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      controller.load();
      await pumpMkvi(tester, mkviSettingsPage(controller));

      expect(
        find.byKey(SettingsScreenKeys.repairedBanner),
        findsNothing,
        reason: 'absence is not corruption: a first launch must not be warned '
            'about a document nobody wrote',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('reports a stored value it had to correct, in Turkish', (
      WidgetTester tester,
    ) async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SettingsKeys.appearance:
            '{"${SettingsCodec.versionKey}":${SettingsCodec.version},'
                '"${SettingsCodec.themeKey}":"bilinmeyen-tema"}',
      });
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);
      controller.load();

      expect(controller.report.hasIssues, isTrue);
      await pumpMkvi(tester, mkviSettingsPage(controller));

      expect(find.byKey(SettingsScreenKeys.repairedBanner), findsOneWidget);
      expect(
        find.text(controller.catalog.repairedBannerTitle),
        findsOneWidget,
      );
      // The reason is the layer's own sentence, verbatim: a screen that
      // reworded it would be two vocabularies for one problem.
      expect(find.text(controller.report.summaryTr), findsOneWidget);
      expect(
        find.text(SettingsUiTr.repairedBannerRecovery.tr),
        findsOneWidget,
        reason: 'a correction the user cannot act on is only half reported',
      );

      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('the filled-action edge rule, in both directions', () {
    /// The colour of the box [MkviSegmentedRow] draws its edge on, or null.
    Color? segmentedEdgeColour(WidgetTester tester, Finder group) {
      final Container box = tester.widget<Container>(
        find.descendant(
          of: group,
          matching: find.byKey(MkviChoiceKeys.segmentedBorder),
        ),
      );
      final BoxDecoration decoration = box.decoration! as BoxDecoration;
      final BoxBorder? border = decoration.border;
      if (border == null) return null;
      return border.top.color;
    }

    testWidgets('the density picker stands on surface, so its fill takes no edge', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        SettingsStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: mkviSettingsSection(DensitySection(controller: controller)),
        ),
      );

      final Finder group = find.byType(SettingsChoiceGroup<DensityPreference>);
      expect(
        segmentedEdgeColour(tester, group),
        isNull,
        reason: 'ROADMAP Faz 2: an accent fill on `surface` takes no edge, '
            'and this picker is shipped on a `surface` card',
      );
      // And the positive control: the rule is not "never any edge".
      expect(mkviFilledActionNeedsEdge('surface'), isFalse);
      expect(mkviFilledActionNeedsEdge('surfaceRaised'), isTrue);
      expect(MkviRestingSurface.surface.needsBorder, isFalse);
      expect(MkviRestingSurface.raised.needsBorder, isTrue);
      expect(style.role('surface'), isNot(style.role('surfaceRaised')));
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('the accent picker stands on the raised panel, so its fill takes one', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        SettingsStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: mkviSettingsPage(controller),
        ),
      );

      for (final Key group in <Key>[
        AppearanceKeys.accentGroup,
        AppearanceKeys.radiusGroup,
      ]) {
        expect(
          segmentedEdgeColour(tester, find.byKey(group)),
          style.role('borderStrong'),
          reason: 'an accent fill on `surfaceRaised` must carry '
              '`borderStrong`, measured as the role and not as a colour',
        );
      }
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('the same picker takes the edge on a raised card and none on a soft one', (
      WidgetTester tester,
    ) async {
      // The other half of the sentence in one test: the section is told which
      // surface it stands on, and the edge follows. "Filled always has a
      // border" and "filled never has a border" both fail here.
      for (final MkviRestingSurface resting in <MkviRestingSurface>[
        MkviRestingSurface.surface,
        MkviRestingSurface.raised,
      ]) {
        final SettingsController controller = mkviSettingsController();
        addTearDown(controller.dispose);
        late AppearanceStyle style;
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          SettingsStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSettingsSection(
              AppearanceSection(controller: controller, resting: resting),
            ),
          ),
        );
        final Finder group = find.byKey(AppearanceKeys.accentGroup);
        expect(
          segmentedEdgeColour(tester, group),
          resting.needsBorder ? style.role('borderStrong') : null,
          reason: 'on ${resting.roleName} the edge is '
              '${resting.needsBorder ? 'required' : 'forbidden'}',
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester);
      }
    });
  });

  group('the about card', () {
    testWidgets('shows the version and says it cannot check for an update', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(tester, mkviSettingsPage(controller));

      expect(
        find.text(mkviTestAppVersion),
        findsOneWidget,
        reason: 'the version is a required argument, so a build cannot show '
            'this card without saying what it is',
      );
      expect(find.text(SettingsUiTr.versionLabel.tr), findsOneWidget);
      expect(find.text(SettingsUiTr.updateStatusLabel.tr), findsOneWidget);
      expect(
        find.text(SettingsUiTr.updateStatusUnknown.tr),
        findsOneWidget,
        reason: 'no update client is wired, and "Güncel" would be a claim '
            'nobody measured',
      );
      expect(
        find.widgetWithText(OutlinedButton, SettingsUiTr.checkUpdateLabel.tr),
        findsNothing,
        reason: 'a control that cannot do anything is not a control',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('offers the check, and shows the host\'s own status, once a host '
        'provides both', (WidgetTester tester) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      int checks = 0;
      await pumpMkvi(
        tester,
        mkviSettingsPage(
          controller,
          onCheckUpdate: () => checks += 1,
          updateStatusTr: 'Güncelleme denetlendi: sürüm 0.2.0 güncel.',
        ),
      );

      expect(
        find.text('Güncelleme denetlendi: sürüm 0.2.0 güncel.'),
        findsOneWidget,
        reason: 'the wording of a check stays with the thing being checked',
      );
      expect(
        find.text(SettingsUiTr.updateStatusUnknown.tr),
        findsNothing,
      );
      final Finder action = find.widgetWithText(
        OutlinedButton,
        SettingsUiTr.checkUpdateLabel.tr,
      );
      expect(action, findsOneWidget);
      expectHitTarget(tester, action);
      await tapInSection(tester, action);
      expect(checks, 1, reason: 'one press, one check');
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('the accessibility floor', () {
    testWidgets('every operable control is found, and every one has a name', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(tester, mkviSettingsPage(controller));
      final SettingsCatalog catalog = controller.catalog;

      final List<SettingsControlReading> readings = await readSettingsControlLabels(
        tester,
      );

      // The assertion is only worth anything if the walk found the controls, so
      // the count and the kinds are measured rather than assumed.
      expect(
        readings,
        hasLength(greaterThan(15)),
        reason: 'the whole page is operable, so a walk that found a handful of '
            'nodes measured nothing: $readings',
      );
      final Map<String, int> byKind = <String, int>{};
      for (final SettingsControlReading reading in readings) {
        byKind[reading.type] = (byKind[reading.type] ?? 0) + 1;
      }
      // The kinds this page has, counted: a walk that found the buttons and
      // none of the fields is a walk that stopped early. A switch row is
      // reported as the row — the outermost operable node — so it counts as
      // `denetlenebilir öğe`, not as the `Switch` inside it.
      expect(
        byKind.keys,
        containsAll(<String>[
          'düğme',
          'kaydırıcı',
          'metin alanı',
          'denetlenebilir öğe',
        ]),
        reason: 'a button, the type slider, the three fields and the option '
            'and switch rows: $byKind',
      );
      expect(
        byKind['metin alanı'],
        3,
        reason: 'the endpoint, the ICE servers and the self name: $byKind',
      );
      expect(byKind['kaydırıcı'], 1, reason: 'the type scale, once: $byKind');

      expect(
        readings.where((SettingsControlReading r) => !r.named),
        isEmpty,
        reason: 'a control the user cannot hear is not a control: $readings',
      );

      // And the names are the app's own Turkish, not a placeholder: every
      // control on the page is named after a label this screen or the
      // catalogue put there.
      final Set<String> spoken = <String>{
        for (final SettingsControlReading reading in readings) reading.spoken,
      };
      for (final String label in <String>[
        catalog.fontScaleLabel,
        catalog.endpointLabel,
        catalog.iceServersLabel,
        catalog.selfNameLabel,
        catalog.resetAppearanceLabel,
        catalog.saveLabel,
        catalog.highContrastLabel,
        catalog.reduceMotionLabel,
        catalog.accentOptionLabel(AccentId.blue),
        catalog.densityOptionLabel(DensityPreference.comfortable),
        SettingsUiTr.identitySaveLabel.tr,
        // `checkUpdateLabel` is deliberately absent: this page is pumped with no
        // update client, so there is no such control, and the about group below
        // is where that button is measured.
      ]) {
        expect(
          spoken.any((String value) => value.contains(label)),
          isTrue,
          reason: 'nothing on screen is named "$label": $spoken',
        );
      }

      expectNoOverflow(tester);
    });
  });

  group('every control is big enough to press', () {
    testWidgets('buttons, rows, segments and the slider all clear the token target', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(tester, mkviSettingsPage(controller));
      final AppearanceStyle style = mkviStyleOf(tester);

      final List<Finder> targets = <Finder>[
        // Every button, named by which one it is rather than by a type: the
        // reset is an outlined action and the two saves are filled, and the
        // screen decides which — so the test asks for the label.
        find.widgetWithText(
          OutlinedButton,
          controller.catalog.resetAppearanceLabel,
        ),
        find.widgetWithText(FilledButton, controller.catalog.saveLabel),
        find.widgetWithText(FilledButton, SettingsUiTr.identitySaveLabel.tr),
        // The theme rows, in the catalogue's order (which puts `Sistem` first
        // because it is the default).
        for (final ThemePreference theme in controller.catalog.themeOptions)
          find.byKey(MkviChoiceKeys.row(
            controller.catalog.themeOptions.indexOf(theme),
          )),
        // The segments. Every segmented control reuses the same static keys, so
        // each one is scoped to the section that owns it.
        for (int index = 0; index < AccentId.values.length; index += 1)
          find.descendant(
            of: find.byKey(AppearanceKeys.accentGroup),
            matching: find.byKey(MkviChoiceKeys.segment(index)),
          ),
        for (int index = 0; index < RadiusPreference.values.length; index += 1)
          find.descendant(
            of: find.byKey(AppearanceKeys.radiusGroup),
            matching: find.byKey(MkviChoiceKeys.segment(index)),
          ),
        for (int index = 0; index < DensityPreference.values.length; index += 1)
          find.descendant(
            of: find.byKey(DensityKeys.card),
            matching: find.byKey(MkviChoiceKeys.segment(index)),
          ),
        // The two accessibility switches.
        for (int index = 0; index < AppearanceSwitch.values.length; index += 1)
          find.byKey(MkviChoiceKeys.switchRow(index)),
        // The slider's target, not the slider's own box: the target is what the
        // token file promises and the slider's box is only 34 dp tall.
        find.byKey(MkviChoiceKeys.sliderTarget),
      ];

      expect(targets, isNotEmpty);
      for (final Finder target in targets) {
        expect(
          target,
          findsOneWidget,
          reason: 'no control at $target, so nothing was measured',
        );
        expectHitTarget(tester, target, style: style);
      }

      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('the whole matrix overflows nowhere', () {
    testWidgets('16 theme/accent pairs, 6 scale/density pairs and 4 accessibility '
        'pairs, at three window sizes', (WidgetTester tester) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);

      final List<AppearanceSettings> matrix = <AppearanceSettings>[
        ...mkviAppearanceMatrix(),
        ...mkviScaleMatrix(),
        ...mkviAccessibilityMatrix(),
      ];
      // The harness's own counts, asserted so a widening of the matrix is
      // visible here: `mkviScaleMatrix` is six, not nine, because
      // `DensityPreference` has two values where the token file has three
      // densities. See `density_section.dart`.
      expect(mkviAppearanceMatrix(), hasLength(16));
      expect(mkviScaleMatrix(), hasLength(6));
      expect(mkviAccessibilityMatrix(), hasLength(4));
      expect(mkviWindowSizes, hasLength(3));

      for (final Size size in mkviWindowSizes) {
        await pumpSettingsMatrix(
          tester,
          controller,
          matrix: matrix,
          size: size,
          each: (AppearanceSettings settings, AppearanceStyle style) {
            expectNoOverflow(tester);
            // The two pairs this screen actually paints, measured in every
            // combination rather than assumed: the accent fill with the
            // on-accent role, and body text on the card the sample sits on.
            expectTokenContrast(style, 'textOnAccent', 'accent');
            expectTokenContrast(style, 'text', 'surface');
          },
        );
      }
    });
  });
}
