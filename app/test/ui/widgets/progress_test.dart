/// The two progress shapes, and the property that keeps the test-suite runnable:
///
/// **a widget in this layer never starts a clock of its own.**
///
/// A self-looping `AnimationController` schedules a frame forever, so
/// `pumpAndSettle` — which every test in this app is pumped with, and which
/// `expectNoOverflow` runs straight after — could never return for a screen that
/// contained one. The first test in the second group is therefore not a
/// cosmetic assertion: it is the reason this file has no `Ticker`, and the
/// reason the sweep is a number the caller passes in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/widget_samples.dart';

/// The bar under test, as Material's own widget, which is where the theme
/// hands every progress its metrics.
LinearProgressIndicator barOf(WidgetTester tester, [int index = 0]) =>
    tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    ).elementAt(index);

void main() {
  group('a bar is the fill and the track, both from the palette', () {
    testWidgets('a determinate bar is asked for its fraction and nothing else', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviLinearProgress(
            value: SampleTr.progressValue,
            label: SampleTr.progressLabel,
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final LinearProgressIndicator bar = barOf(tester);

      expect(bar.value, SampleTr.progressValue);
      expect(bar.value, isNotNull);
      expect(bar.color, style.role('accent'));
      expect(bar.backgroundColor, style.role('border'));
      expect(bar.minHeight, style.gap('4'));
      expect(bar.borderRadius, style.shape('pill').borderRadius);
      expect(bar.semanticsLabel, SampleTr.progressLabel);

      final Size size = tester.getSize(find.byType(MkviLinearProgress));
      expect(size.height, closeTo(style.gap('4'), 0.01));
      expect(size.width, greaterThan(0));
    });

    testWidgets('an indeterminate bar is drawn at the phase, not by a loop of its own', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviLinearProgress(phase: SampleTr.progressPhase),
        ),
      );

      final LinearProgressIndicator bar = barOf(tester);
      expect(
        bar.value,
        SampleTr.progressPhase,
        reason: 'the fill is at the phase the caller swept it to',
      );
      expect(
        bar.value,
        isNotNull,
        reason:
            'a null value would hand the sweep to Material, which repeats an '
            'AnimationController forever and can never settle',
      );
    });

    testWidgets('the track is the border role, which the token file declares on every surface', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(const MkviLinearProgress(value: SampleTr.progressValue)),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      expect(barOf(tester).backgroundColor, style.role('border'));
      for (final String surface in <String>[
        'bg',
        'surface',
        'surfaceRaised',
        'surfaceSoft',
        'surfaceOverlay',
      ]) {
        // 0.1.x's progress track measured 1.24:1. This is the assertion that
        // says the track is a role the palette was measured with.
        expectTokenContrast(style, 'border', surface, minimum: 3);
      }
    });
  });

  group('the sweep is the caller\'s clock, and the tokens say how long it is', () {
    testWidgets('a bar with no controller of its own settles, so the harness pump is enough', (
      WidgetTester tester,
    ) async {
      // The assertion is the absence of a timeout plus an idle frame:
      // `pumpMkvi` settles, and every other test in this directory is pumped
      // the same way.
      await pumpMkvi(tester, mkviSample(mkviProgressSample()));
      expect(find.byType(MkviLinearProgress), findsNWidgets(2));
      expect(find.byType(MkviCircularProgress), findsNWidgets(2));
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'and nothing in here is still asking for a frame',
      );
      expectNoOverflow(tester);
    });

    test('the sweep is style.duration(slow) on style.motionEasing', () {
      final AppearanceStyle style = mkviAppearance().style;
      final MkviProgressMotion motion = MkviProgressMotion.of(style);
      expect(motion.duration, style.duration('slow'));
      expect(motion.curve, style.motionEasing);
      expect(motion.isAnimated, isTrue);
      expect(motion, MkviProgressMotion.of(mkviAppearance().style));
    });

    testWidgets('reduced motion hands the caller an instant sweep and says so', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        MkviStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: mkviSample(
            const MkviLinearProgress(phase: SampleTr.progressPhase),
          ),
        ),
        settings: AppearanceSettings(reduceMotion: true),
      );

      final MkviProgressMotion motion = MkviProgressMotion.of(style);
      expect(
        motion.duration,
        style.duration('instant'),
        reason: 'the token file replaces every duration, not just this one',
      );
      expect(motion.duration, Duration.zero);
      expect(
        motion.isAnimated,
        isFalse,
        reason:
            'so a caller must paint the phase it has: a controller on a zero '
            'period divides by zero, and that is a crash',
      );
      expect(
        barOf(tester).value,
        SampleTr.progressPhase,
        reason: 'and the bar still shows where the sweep would have been',
      );
    });
  });

  group('a ring is the same two roles, drawn as an arc', () {
    testWidgets('a determinate ring is the fraction, with no rotation at all', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviCircularProgress(value: SampleTr.progressValue),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final CircularProgressIndicator ring = tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          );

      expect(ring.value, SampleTr.progressValue);
      expect(
        ring.strokeWidth,
        style.focusRingWidth,
        reason:
            'the token file declares no progress stroke, and its one "a visible '
            'line" width is the one that widens under high contrast',
      );
      expect(ring.color, style.role('accent'));
      expect(ring.backgroundColor, style.role('border'));
      expect(
        tester.getSize(find.byType(MkviCircularProgress)).height,
        closeTo(style.control('lg').height, 0.01),
      );
      expect(
        find.byType(RotationTransition),
        findsNothing,
        reason: 'a determinate ring has nothing to rotate',
      );
    });

    testWidgets('an indeterminate ring is a fixed arc rotated to the phase', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviCircularProgress(phase: SampleTr.ringQuarterTurn),
        ),
      );

      final CircularProgressIndicator ring = tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          );
      final RotationTransition rotation = tester.widget<RotationTransition>(
        find.byType(RotationTransition),
      );

      expect(
        ring.value,
        MkviCircularProgress.indeterminateSweep,
        reason: 'a partial arc: a full ring would read as "complete"',
      );
      expect(rotation.turns.value, SampleTr.ringQuarterTurn);

      // A quarter turn is a quarter turn: the matrix the ring is painted
      // through is a real rotation, not a decoration.
      final Transform transform = tester.widget<Transform>(
        find.descendant(
          of: find.byType(RotationTransition),
          matching: find.byType(Transform),
        ),
      );
      expect(
        transform.transform.storage[0],
        closeTo(0, 1e-9),
        reason: 'cos of a quarter turn is zero',
      );
      expect(transform.transform.storage[1], closeTo(1, 1e-9));
    });

    testWidgets('the ring is an sm, md or lg control square', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;

      for (final String size in <String>['sm', 'md', 'lg']) {
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(
              MkviCircularProgress(value: SampleTr.progressValue, controlSize: size),
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(MkviCircularProgress)).height,
          closeTo(style.control(size).height, 0.01),
          reason: 'a $size ring is a $size control square',
        );
      }
    });
  });

  group('every progress survives the whole matrix', () {
    testWidgets('no progress overflows in any of the 16 theme/accent pairs or the 6 scale/density pairs', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in <AppearanceSettings>[
        ...mkviAppearanceMatrix(),
        ...mkviScaleMatrix(),
      ]) {
        await pumpMkvi(
          tester,
          mkviSample(mkviProgressSample()),
          settings: settings,
        );
        expectNoOverflow(tester);
      }
    });

    testWidgets('the bar is a hairline that follows the density, at every density', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;
      final List<double> heights = <double>[];

      for (final DensityPreference density in DensityPreference.values) {
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(
              const MkviLinearProgress(value: SampleTr.progressValue),
            ),
          ),
          settings: AppearanceSettings(density: density),
        );
        expect(barOf(tester).minHeight, style.gap('4'));
        heights.add(tester.getSize(find.byType(MkviLinearProgress)).height);
      }
      expect(
        heights.first,
        isNot(heights.last),
        reason: 'the density preference has to move the bar, or it is ignored',
      );
    });
  });
}
