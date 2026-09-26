/// The hairlines and the empty space.
///
/// There is one test in this file that is really a measurement, and it is the
/// one about the colour: MKVI has exactly **one** divider colour, `border`, and
/// the token file validates it against all five surfaces at 3:1 — the old
/// build's dividers measured 1.6–2.3:1. So a screen cannot ask for a second,
/// subtler line: there is nothing to ask for, and the assertion below says so in
/// every palette rather than in one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/widget_samples.dart';

/// The painted top edge of a horizontal divider, which is how Material's own
/// `Divider` draws one: a border inside a box that is exactly one border width
/// tall.
BorderSide hairlineOf(WidgetTester tester) {
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(MkviDivider),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (box.decoration as BoxDecoration).border!.top;
}

/// The painted line of a vertical divider, which is a coloured box.
Color verticalHairlineOf(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.descendant(
        of: find.byType(MkviVerticalDivider),
        matching: find.byType(ColoredBox),
      ),
    )
    .color;

void main() {
  group('a hairline is one border width of the one divider colour', () {
    testWidgets('the horizontal divider is one border width tall and spans the column', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MkviDivider(),
              Text(SampleTr.keyValue2),
            ],
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Rect divider = tester.getRect(find.byType(MkviDivider));

      expect(hairlineOf(tester).color, style.role('border'));
      expect(hairlineOf(tester).width, style.borderWidth);
      expect(
        divider.height,
        closeTo(style.borderWidth, 0.001),
        reason:
            'a border width is a physical promise and never follows the density',
      );
      expect(
        divider.width,
        closeTo(
          tester.getRect(find.text(SampleTr.keyValue2)).width,
          0.01,
        ),
        reason: 'a divider spans whatever it divides',
      );
    });

    testWidgets('the border role clears 3:1 on all five surfaces, in every palette', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviAppearanceMatrix()) {
        late AppearanceStyle style;
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(const MkviDivider()),
          ),
          settings: settings,
        );
        for (final String surface in <String>[
          'bg',
          'surface',
          'surfaceRaised',
          'surfaceSoft',
          'surfaceOverlay',
        ]) {
          expect(
            style.contrast('border', surface),
            greaterThanOrEqualTo(3),
            reason:
                'theme ${style.themeId}, accent ${style.accentId}, border on '
                '$surface',
          );
        }
      }
    });

    testWidgets('the vertical divider is one border wide and fills the height it is given', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, mkviSample(mkviDividerSample()));

      final AppearanceStyle style = mkviStyleOf(tester);
      final Rect divider = tester.getRect(find.byType(MkviVerticalDivider));

      expect(verticalHairlineOf(tester), style.role('border'));
      expect(divider.width, closeTo(style.borderWidth, 0.001));
      expect(
        divider.height,
        greaterThan(divider.width),
        reason: 'a vertical rule is taller than it is thick',
      );
      // It takes exactly the height of the row it divides: the `stretch` in
      // the sample is the contract the divider's own doc states.
      expect(
        divider.height,
        closeTo(tester.getSize(find.byType(Row).first).height, 0.01),
      );
    });

    testWidgets('a vertical divider in a loosely bounded row is still visible', (
      WidgetTester tester,
    ) async {
      // No `stretch`, no `IntrinsicHeight`: the case the `minHeight` below the
      // divider exists for. A rule that silently measures zero is worse than
      // one that measures a hairline.
      await pumpMkvi(
        tester,
        mkviSample(
          const Row(
            children: <Widget>[
              Text(SampleTr.keyLabel2),
              MkviVerticalDivider(),
              Expanded(child: Text(SampleTr.keyValue2)),
            ],
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Rect divider = tester.getRect(find.byType(MkviVerticalDivider));
      expect(divider.width, closeTo(style.borderWidth, 0.001));
      expect(
        divider.height,
        greaterThanOrEqualTo(style.borderWidth),
        reason: 'never zero',
      );
    });
  });

  group('the indents and the gaps are space steps, resolved', () {
    testWidgets('a horizontal indent moves the line by the step it names', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(const MkviDivider(startIndentStep: '6', endIndentStep: '2')),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Rect outer = tester.getRect(
        find.ancestor(
          of: find.descendant(
            of: find.byType(MkviDivider),
            matching: find.byType(DecoratedBox),
          ),
          matching: find.byType(Padding),
        ),
      );
      final Rect line = tester.getRect(
        find.descendant(
          of: find.byType(MkviDivider),
          matching: find.byType(DecoratedBox),
        ),
      );

      expect(
        line.left - outer.left,
        closeTo(style.gap('6'), 0.01),
        reason: 'the start indent is the step it names',
      );
      expect(
        outer.right - line.right,
        closeTo(style.gap('2'), 0.01),
        reason: 'and the end indent is a different one',
      );
    });

    testWidgets('a gap is exactly its step on its own axis', (
      WidgetTester tester,
    ) async {
      for (final String step in <String>['0', '3', '8']) {
        late AppearanceStyle style;
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(MkviGap(step)),
          ),
        );
        expect(
          tester.getSize(find.byType(MkviGap)).height,
          closeTo(style.gap(step), 0.001),
          reason: 'a vertical gap of step $step is gap($step) tall',
        );

        // A `Row` of `min`, so the gap is measured on its own terms: a Column
        // with `stretch` would hand it the column's width and the assertion
        // would be about the sample instead of the gap.
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[MkviGap(step, axis: Axis.horizontal)],
              ),
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(MkviGap)).width,
          closeTo(style.gap(step), 0.001),
          reason: 'and the same step is wide on the other axis',
        );
      }
    });

    testWidgets('a zero step really is zero space', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, mkviSample(const MkviGap('0')));

      final AppearanceStyle style = mkviStyleOf(tester);
      expect(style.gap('0'), 0);
      expect(tester.getSize(find.byType(MkviGap)).height, 0);
    });
  });

  group('every divider survives the whole matrix', () {
    testWidgets('no divider or gap overflows in any of the 16 theme/accent pairs or the 6 scale/density pairs', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in <AppearanceSettings>[
        ...mkviAppearanceMatrix(),
        ...mkviScaleMatrix(),
      ]) {
        for (final Widget sample in <Widget>[
          mkviDividerSample(),
          mkviKeyValueSample(),
        ]) {
          await pumpMkvi(tester, mkviSample(sample), settings: settings);
          expectNoOverflow(tester);
        }
      }
    });

    testWidgets('the hairline is the token file\'s border width at every density', (
      WidgetTester tester,
    ) async {
      expect(
        mkviTokenFixture.tokens.borderWidth,
        1,
        reason: 'the one physical promise: a border width, in logical pixels',
      );
      for (final DensityPreference density in DensityPreference.values) {
        late AppearanceStyle style;
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(const MkviDivider()),
          ),
          settings: AppearanceSettings(density: density),
        );
        expect(
          tester.getRect(find.byType(MkviDivider)).height,
          closeTo(style.borderWidth, 0.001),
          reason: 'density ${density.densityId} must not fatten a border',
        );
        expect(
          style.borderWidth,
          mkviTokenFixture.tokens.borderWidth,
          reason: 'and the resolved style still carries the file\'s own number',
        );
      }
    });
  });
}
