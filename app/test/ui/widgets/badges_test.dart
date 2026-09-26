/// The badge: four meanings, four token pairs, and one edge that is
/// deliberately not the strong one.
///
/// The interesting assertion here is a negative one. The token file validates
/// `danger` as a *text* colour on all five surfaces, and a badge whose fill is
/// `dangerFill` looks like it wants a `danger` label — a red pill with red text,
/// which measures **1.34:1** in the light theme and 1.75:1 in midnight. So the
/// danger tone is the one tone whose label is not the role of the same name, and
/// this file measures both the right pair and the wrong one so that a future
/// "simplification" of the enum fails here instead of on a screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/widget_samples.dart';

/// The minimum the token file declares for each tone's label, read off its
/// `contrast` list: 6:1 on the three soft fills, 4.5:1 on `dangerFill`.
double declaredMinimumFor(MkviBadgeTone tone) =>
    tone == MkviBadgeTone.danger ? 4.5 : 6.0;

/// The badge's own [Container], so the test reads the box and not the widget
/// that builds it.
Container badgeContainer(WidgetTester tester, MkviBadgeTone tone) {
  return tester.widget<Container>(
    find.descendant(
      of: find.byWidgetPredicate(
        (Widget widget) => widget is MkviBadge && widget.tone == tone,
      ),
      matching: find.byType(Container),
    ),
  );
}

void main() {
  group('each tone is one declared pair, and nothing else', () {
    testWidgets('the four tones paint the four pairs the token file validates', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;

      for (final MkviBadgeTone tone in MkviBadgeTone.values) {
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(MkviBadge(label: SampleTr.badgeLabel, tone: tone)),
          ),
        );

        final Container container = badgeContainer(tester, tone);
        final BoxDecoration decoration = container.decoration! as BoxDecoration;
        final Text label = tester.widget<Text>(
          find.text(SampleTr.badgeLabel),
        );

        expect(
          decoration.color,
          style.role(tone.surfaceRole),
          reason: '$tone is filled with ${tone.surfaceRole}',
        );
        expect(
          label.style?.color,
          style.role(tone.labelRole),
          reason: '$tone is labelled with ${tone.labelRole}',
        );
        expect(
          style.contrast(tone.labelRole, tone.surfaceRole),
          greaterThanOrEqualTo(declaredMinimumFor(tone)),
          reason:
              'the pair the badge claims is the pair the token file declares, '
              'in ${style.themeId}/${style.accentId}',
        );
      }
    });

    testWidgets('the danger tone is the one whose label is not the role of the same name', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviBadge(
            label: SampleTr.badgeLabel,
            tone: MkviBadgeTone.danger,
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      expect(MkviBadgeTone.danger.surfaceRole, 'dangerFill');
      expect(
        MkviBadgeTone.danger.labelRole,
        'textOnAccent',
        reason: 'the fill\'s own declared pair, not the text role',
      );
      expect(
        style.contrast('danger', 'dangerFill'),
        lessThan(4.5),
        reason:
            'a danger label on a danger pill is a red on red: this is the '
            'measurement that decides the label role, so it is asserted',
      );
      expectTokenContrast(
        style,
        'textOnAccent',
        MkviBadgeTone.danger.surfaceRole,
        minimum: 4.5,
      );
    });

    testWidgets('the edge is border, and never borderStrong', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;

      for (final MkviBadgeTone tone in MkviBadgeTone.values) {
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(MkviBadge(label: SampleTr.badgeLabel, tone: tone)),
          ),
        );

        final BoxDecoration decoration =
            badgeContainer(tester, tone).decoration! as BoxDecoration;
        final Border border = decoration.border! as Border;
        expect(
          border.top.color,
          style.role('border'),
          reason: 'a label\'s edge is the divider edge',
        );
        expect(border.top.width, style.borderWidth);
        expect(
          border.top.color,
          isNot(style.role('borderStrong')),
          reason:
              'borderStrong belongs to a filled control whose only boundary '
              'would be its fill; spending it on every badge would flatten the '
              'one place it carries meaning',
        );

        // The edge's job is to separate the pill from the surface it stands on,
        // and that is the pair the token file declares.
        for (final String surface in <String>[
          'bg',
          'surface',
          'surfaceRaised',
          'surfaceSoft',
          'surfaceOverlay',
        ]) {
          expectTokenContrast(style, 'border', surface, minimum: 3);
        }
      }
    });
  });

  group('a badge is a label, sized like one', () {
    testWidgets('the pill is the pill radius with a two step horizontal padding', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(const MkviBadge(label: SampleTr.badgeLabel)),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Container container = badgeContainer(
        tester,
        MkviBadgeTone.accent,
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;

      expect(decoration.borderRadius, style.shape('pill').borderRadius);
      expect(
        container.padding,
        EdgeInsets.symmetric(
          horizontal: style.gap('2'),
          vertical: style.gap('1'),
        ),
        reason: 'a pill, not a lozenge: the vertical step is one below',
      );
    });

    testWidgets('the label is 2xs by default and xs when the badge is not dense', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;

      await pumpMkvi(
        tester,
        MkviStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: mkviSample(const MkviBadge(label: SampleTr.badgeLabel)),
        ),
      );
      expect(
        tester.widget<Text>(find.text(SampleTr.badgeLabel)).style?.fontSize,
        style.typeStep('2xs').size,
      );

      await pumpMkvi(
        tester,
        MkviStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: mkviSample(
            const MkviBadge(label: SampleTr.badgeLabel, dense: false),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text(SampleTr.badgeLabel)).style?.fontSize,
        style.typeStep('xs').size,
      );
    });

    testWidgets('a badge with a glyph pairs an sm icon with a 2xs label', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviBadge(
            label: SampleTr.badgeLabel,
            tone: MkviBadgeTone.success,
            icon: Icons.lock_outline_rounded,
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Icon icon = tester.widget<Icon>(
        find.byIcon(Icons.lock_outline_rounded),
      );
      expect(icon.size, style.control('sm').iconSize);
      expect(
        icon.color,
        style.role(MkviBadgeTone.success.labelRole),
        reason: 'the glyph is the same colour as the label, always',
      );
      expect(
        tester.getRect(find.byIcon(Icons.lock_outline_rounded)).width,
        lessThan(tester.getSize(find.byType(MkviBadge)).height),
        reason: 'and it is smaller than the pill it sits in',
      );
    });

    testWidgets('a badge is a label, so it is not a pointer target', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(const MkviBadge(label: SampleTr.badgeLabel)),
      );

      expect(find.byType(InkResponse), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
      expect(
        tester.getSize(find.byType(MkviBadge)).height,
        lessThan(mkviStyleOf(tester).hitTargetMin),
        reason:
            'a badge is not a control and promises no target; if the user has '
            'to act on it, an action goes next to it',
      );
    });
  });

  group('every badge survives the whole matrix', () {
    testWidgets('no badge overflows in any of the 16 theme/accent pairs or the 6 scale/density pairs', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in <AppearanceSettings>[
        ...mkviAppearanceMatrix(),
        ...mkviScaleMatrix(),
      ]) {
        await pumpMkvi(
          tester,
          mkviSample(mkviBadgeSample()),
          settings: settings,
        );
        expectNoOverflow(tester);
      }
    });

    testWidgets('the label of every tone clears its declared minimum at the largest type', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in <AppearanceSettings>[
        AppearanceSettings(fontScale: AppearanceSettings.maxFontScale),
        AppearanceSettings(
          fontScale: AppearanceSettings.maxFontScale,
          theme: ThemePreference.light,
          highContrast: true,
        ),
      ]) {
        late AppearanceStyle style;
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(mkviBadgeSample()),
          ),
          settings: settings,
        );
        for (final MkviBadgeTone tone in MkviBadgeTone.values) {
          expect(
            style.contrast(tone.labelRole, tone.surfaceRole),
            greaterThanOrEqualTo(declaredMinimumFor(tone)),
            reason:
                '$tone at fontScale ${style.fontScale}, highContrast '
                '${style.highContrast}',
          );
        }
        expectNoOverflow(tester);
      }
    });
  });
}
