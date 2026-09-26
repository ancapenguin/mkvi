/// `ROADMAP.md` Faz 2, the unchecked item, measured:
///
/// > **Vurgu dolu düğme, yükseltilmiş yüzeyde `borderStrong` kenarı alacak.** Bu
/// > bir token kuralı değil, arayüz kuralı: token testi bunu ölçemez, vurgu dolu
/// > her düğme `bg`/`surface` üzerinde durmalı, `surfaceRaised`/`surfaceSoft`
/// > üzerinde ise kenarı olmalı.
///
/// `design/test/contrast_test.dart` already proves the half that is a token rule:
/// `borderStrong` clears 3:1 on all five surfaces. This file proves the half that
/// is not — that the *button* takes the edge, and only on the surfaces that need
/// it.
///
/// ## How the assertion avoids becoming a colour snapshot
///
/// Nothing here compares a button against a hex value written into the test. The
/// test reads the role the panel says it is standing on
/// ([MkviPanelVariant.surfaceRole]), reads that role's colour out of the palette
/// the widget is about to be painted with ([mkviStyleOf]), and reads the button's
/// resolved [BorderSide]. So a token change moves all three numbers together and
/// the test keeps meaning the same thing; what it cannot survive is the widget
/// ignoring the rule, because then the two sides stop being related at all.
///
/// The second half of the file is the negative control the ROADMAP asks for: the
/// theme's own `filledButtonTheme` has **no** `side` at all, so an edge that
/// appears on a raised panel can only have come from this layer. Without that
/// assertion, "the filled button has a border" would pass just as well on a theme
/// that gave every button one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/widget_samples.dart';

/// The [BorderSide] a filled button would actually paint, the way the framework
/// resolves it.
///
/// `ButtonStyleButton` merges the widget's own style **over** the theme's
/// ([FilledButtonThemeData.style]) — that is the only reason an edge added here
/// does not throw away the resolver's fill, height, padding and shape — so the
/// test has to perform the same merge to see the edge the user would see.
BorderSide resolvedFilledSide(WidgetTester tester, String label) {
  final FilledButton button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, label),
  );
  final ButtonStyle? themed = Theme.of(
    tester.element(find.byType(FilledButton).first),
  ).filledButtonTheme.style;
  final ButtonStyle effective = (themed ?? const ButtonStyle()).merge(
    button.style ?? const ButtonStyle(),
  );
  return effective.side?.resolve(<WidgetState>{}) ?? BorderSide.none;
}

/// The same, for an action with no fill.
BorderSide resolvedOutlinedSide(WidgetTester tester, String label) {
  final OutlinedButton button = tester.widget<OutlinedButton>(
    find.widgetWithText(OutlinedButton, label),
  );
  final ButtonStyle? themed = Theme.of(
    tester.element(find.byType(OutlinedButton).first),
  ).outlinedButtonTheme.style;
  final ButtonStyle effective = (themed ?? const ButtonStyle()).merge(
    button.style ?? const ButtonStyle(),
  );
  return effective.side?.resolve(<WidgetState>{}) ?? BorderSide.none;
}

void main() {
  group('the panel is one of the three surface roles, at a token radius', () {
    testWidgets('a raised panel paints surfaceRaised and the md radius', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(mkviPanelSample(MkviPanelVariant.raised)),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final DecoratedBox surface = tester.widget<DecoratedBox>(
        find.byKey(MkviPanelKeys.surface),
      );
      final BoxDecoration decoration = surface.decoration as BoxDecoration;

      expect(decoration.color, style.role('surfaceRaised'));
      expect(decoration.borderRadius, style.shape('md').borderRadius);
      expect(
        decoration.border,
        isNull,
        reason: 'a raised panel is not born with an edge',
      );
    });

    testWidgets('a soft panel paints surfaceSoft, and a flat one paints nothing', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;

      await pumpMkvi(
        tester,
        MkviStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: mkviSample(mkviPanelSample(MkviPanelVariant.soft)),
        ),
      );
      expect(
        (tester.widget<DecoratedBox>(find.byKey(MkviPanelKeys.surface))
                .decoration
                as BoxDecoration)
            .color,
        style.role('surfaceSoft'),
      );

      await pumpMkvi(
        tester,
        MkviStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: mkviSample(mkviPanelSample(MkviPanelVariant.flat)),
        ),
      );
      final BoxDecoration flat =
          tester.widget<DecoratedBox>(find.byKey(MkviPanelKeys.surface))
                  .decoration
              as BoxDecoration;
      expect(
        flat.color,
        isNull,
        reason: 'a flat panel has no fill of its own',
      );
      expect(
        MkviPanelVariant.flat.surfaceRole,
        'bg',
        reason: 'and the surface it stands on is the window background',
      );
      expect(
        (flat.border! as Border).top.color,
        style.role('borderStrong'),
        reason: 'which is why a flat panel is born with an edge',
      );
    });

    testWidgets('the padding is the space step the caller asked for, resolved', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviPanel.raised(
            paddingStep: '6',
            child: Text(SampleTr.keyValue2),
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Padding padding = tester.widget<Padding>(
        find.descendant(
          of: find.byKey(MkviPanelKeys.surface),
          matching: find.byType(Padding),
        ),
      );
      expect(
        padding.padding,
        EdgeInsets.all(style.gap('6')),
        reason: 'a padding step is a token name, so density is already in it',
      );
      expect(
        padding.padding,
        isNot(EdgeInsets.all(6)),
        reason: 'and it is not the number typed next to the name',
      );
    });
  });

  group('ROADMAP Faz 2: a filled action takes the strong edge only off the page', () {
    testWidgets('the same filled action is edged on a raised panel and bare on the page', (
      WidgetTester tester,
    ) async {
      // The expectation, written out, and NOT read back out of the function
      // under test: a test whose branch condition is the code it is testing
      // passes in both directions. Disabling `mkviFilledActionNeedsEdge` turns
      // this test red on the `expect` below, and that is the proof it is a gate
      // and not a restatement.
      const Map<MkviPanelVariant, bool> roadmapSays = <MkviPanelVariant, bool>{
        MkviPanelVariant.raised: true,
        MkviPanelVariant.soft: true,
        MkviPanelVariant.flat: false,
      };

      late AppearanceStyle style;

      for (final MkviPanelVariant variant in MkviPanelVariant.values) {
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(mkviPanelSample(variant)),
          ),
        );

        final String role = variant.surfaceRole;
        expect(
          mkviFilledActionNeedsEdge(role),
          roadmapSays[variant],
          reason:
              'ROADMAP Faz 2: a filled action on $role takes the strong edge: '
              '${roadmapSays[variant]}',
        );

        final BorderSide side = resolvedFilledSide(
          tester,
          SampleTr.primaryAction,
        );

        if (roadmapSays[variant]!) {
          expect(
            side.color,
            style.role('borderStrong'),
            reason:
                'a filled action on $role has no other boundary than its fill',
          );
          expect(
            side.width,
            style.borderWidth,
            reason: 'and the edge is the token border width, not a screen\'s px',
          );
          expectTokenContrast(
            style,
            'borderStrong',
            role,
            minimum: 3,
          );
        } else {
          expect(
            side.width,
            0.0,
            reason:
                'a filled action on $role sits on the page itself, where the '
                'rule says it takes no edge',
          );
        }

        // The premise of the whole rule, asserted so the branch above cannot
        // pass for the wrong reason: a raised surface really is a different
        // colour from the page behind it.
        if (variant.paintsFill) {
          expect(
            style.role(role),
            isNot(style.role('bg')),
            reason: '$role is not the window background',
          );
        }
      }
    });

    testWidgets('the theme itself edges nothing, so the edge on a panel was decided here', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(mkviPanelSample(MkviPanelVariant.raised)),
      );

      final ButtonStyle? themed = Theme.of(
        tester.element(find.byType(FilledButton).first),
      ).filledButtonTheme.style;

      expect(
        themed,
        isNotNull,
        reason: 'the resolver does build a filled button theme',
      );
      expect(
        themed!.side?.resolve(<WidgetState>{}),
        isNull,
        reason:
            'no edge anywhere in the theme: a filled button has no border '
            'until a surface asks for one, which is the whole rule',
      );
      expect(
        resolvedFilledSide(tester, SampleTr.primaryAction).color,
        mkviStyleOf(tester).role('borderStrong'),
      );
    });

    testWidgets('a filled action in a section header on the page takes no edge', (
      WidgetTester tester,
    ) async {
      // The same button, the same palette, the other half of the sentence: not
      // "filled always has a border", but "filled has a border off the page".
      await pumpMkvi(tester, mkviSample(mkviSectionSample()));

      final AppearanceStyle style = mkviStyleOf(tester);
      expect(
        resolvedFilledSide(tester, SampleTr.primaryAction).width,
        0.0,
        reason: 'a section header is page-level, so its role is bg',
      );
      expect(style.role('bg'), isNot(style.role('surfaceRaised')));
    });

    testWidgets('an action with no fill is outlined, and its label is a surface role', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(mkviPanelSample(MkviPanelVariant.raised)),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final BorderSide side = resolvedOutlinedSide(
        tester,
        SampleTr.secondaryAction,
      );
      expect(
        side.color,
        style.role('borderStrong'),
        reason: 'an outlined action is nothing but an edge, and the edge is '
            'the strong one the resolver gave the theme',
      );
      expect(side.width, style.borderWidth);

      // The label of an action with no fill stands on a *surface*, so it is a
      // surface role and not the on-accent role the theme hands every button.
      final OutlinedButton button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, SampleTr.secondaryAction),
      );
      final Color? label = button.style?.foregroundColor?.resolve(
        <WidgetState>{},
      );
      expect(label, style.role('text'));
      expectTokenContrast(style, 'text', 'surfaceRaised', minimum: 7);
    });

    testWidgets('the rule is the one that is certainly wrong, not the two cases ROADMAP names', (
      WidgetTester tester,
    ) async {
      // `bg` and `surface` are the page: no edge.
      expect(mkviFilledActionNeedsEdge('bg'), isFalse);
      expect(mkviFilledActionNeedsEdge('surface'), isFalse);
      // The two the ROADMAP names: an edge.
      expect(mkviFilledActionNeedsEdge('surfaceRaised'), isTrue);
      expect(mkviFilledActionNeedsEdge('surfaceSoft'), isTrue);
      // And a role nobody wrote a rule for, on the safe side of the decision.
      expect(mkviFilledActionNeedsEdge('surfaceOverlay'), isTrue);
      expect(mkviFilledActionNeedsEdge(MkviErrorState.surfaceRole), isTrue);
    });
  });

  group('the header strip is a strip, and it is optional', () {
    testWidgets('a panel with no title, subtitle or action has no header at all', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(const MkviPanel.raised(child: Text(SampleTr.keyValue2))),
      );

      expect(find.byKey(MkviPanelKeys.header), findsNothing);
      expect(find.byKey(MkviPanelKeys.body), findsOneWidget);
      expect(
        tester.getSize(find.byKey(MkviPanelKeys.body)).height,
        greaterThan(0),
        reason: 'and the body is still there',
      );
    });

    testWidgets('the header sits above the body, with the gap step between them', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(mkviPanelSample(MkviPanelVariant.raised)),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Rect header = tester.getRect(find.byKey(MkviPanelKeys.header));
      final Rect body = tester.getRect(find.byKey(MkviPanelKeys.body));
      final Rect surface = tester.getRect(find.byKey(MkviPanelKeys.surface));

      expect(header.height, greaterThan(0));
      expect(
        body.top - header.bottom,
        closeTo(style.gap('3'), 0.01),
        reason: 'one space step, resolved',
      );
      expect(
        surface.left,
        lessThan(header.left),
        reason: 'and the whole strip is inside the panel\'s padding',
      );
      expect(
        style.gap('3'),
        greaterThan(0),
        reason: 'the header gap is not a zero step',
      );
    });

    testWidgets('both actions are in the strip and neither is off the panel', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(mkviPanelSample(MkviPanelVariant.raised)),
      );

      final Rect surface = tester.getRect(find.byKey(MkviPanelKeys.surface));
      final Finder filled = find.widgetWithText(
        FilledButton,
        SampleTr.primaryAction,
      );
      final Finder outlined = find.widgetWithText(
        OutlinedButton,
        SampleTr.secondaryAction,
      );
      expect(filled, findsOneWidget);
      expect(outlined, findsOneWidget);

      for (final Finder button in <Finder>[filled, outlined]) {
        final Rect rect = tester.getRect(button);
        expect(
          surface.contains(rect.topLeft),
          isTrue,
          reason: 'the action starts inside the panel',
        );
        expect(
          surface.contains(rect.bottomRight),
          isTrue,
          reason: 'the action ends inside the panel',
        );
        expect(
          rect.top,
          lessThan(surface.bottom),
          reason: 'and it is in the header, not below the body',
        );
        expect(
          tester.getSize(button).height,
          greaterThanOrEqualTo(mkviStyleOf(tester).control('md').height),
          reason: 'and it is at least the md control height',
        );
      }
    });

    testWidgets('a disabled action keeps its place and does nothing', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          MkviPanel.raised(
            title: SampleTr.panelTitle,
            actions: <MkviPanelAction>[
              MkviPanelAction(
                label: SampleTr.secondaryAction,
                onPressed: null,
              ),
            ],
          ),
        ),
      );

      final OutlinedButton button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, SampleTr.secondaryAction),
      );
      expect(button.onPressed, isNull);
      expect(
        find.byKey(MkviPanelKeys.header),
        findsOneWidget,
        reason: 'a disabled action is still an action and still takes its place',
      );
    });
  });

  group('every panel survives the whole matrix', () {
    testWidgets('no panel overflows in any of the 16 theme/accent pairs or the 6 scale/density pairs', (
      WidgetTester tester,
    ) async {
      final List<AppearanceSettings> matrix = <AppearanceSettings>[
        ...mkviAppearanceMatrix(),
        ...mkviScaleMatrix(),
      ];
      for (final AppearanceSettings settings in matrix) {
        for (final MkviPanelVariant variant in MkviPanelVariant.values) {
          await pumpMkvi(
            tester,
            mkviSample(mkviPanelSample(variant)),
            settings: settings,
          );
          expectNoOverflow(tester);
        }
      }
    });

    testWidgets('the panel keeps its edge rule at the largest type and at every density', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;

      for (final DensityPreference density in DensityPreference.values) {
        for (final MkviPanelVariant variant in MkviPanelVariant.values) {
          await pumpMkvi(
            tester,
            MkviStyleProbe(
              onStyle: (AppearanceStyle value) => style = value,
              child: mkviSample(mkviPanelSample(variant)),
            ),
            settings: AppearanceSettings(
              fontScale: AppearanceSettings.maxFontScale,
              density: density,
            ),
          );
          final BorderSide side = resolvedFilledSide(
            tester,
            SampleTr.primaryAction,
          );
          if (mkviFilledActionNeedsEdge(variant.surfaceRole)) {
            expect(side.color, style.role('borderStrong'));
            expect(side.width, style.borderWidth);
          } else {
            expect(side.width, 0.0);
          }
          expectNoOverflow(tester);
        }
      }
    });
  });
}
