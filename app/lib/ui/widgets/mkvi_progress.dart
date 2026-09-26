/// The two progress shapes, and the one thing about them that is not obvious:
/// **this layer does not run the loop.**
///
/// ## Why there is no `AnimationController` in here
///
/// A self-looping indeterminate indicator can never satisfy `pumpAndSettle`,
/// which is how every widget test in this app is pumped (`pumpMkvi`, in
/// `test/support/mkvi_test_app.dart`). An `AnimationController` with
/// `repeat()` schedules a frame forever, so a screen with an indeterminate bar
/// in it would make every test that contains that screen fail with a
/// pump-and-settle timeout — and the harness's own `expectNoOverflow`, the thing
/// that catches the 0.1.x overflows, runs straight after that pump.
///
/// So the sweep belongs to the caller, exactly as the clock belongs to the caller
/// of `NoticeController` in `lib/ui/notice/`. The caller passes a [phase] and
/// this layer draws it; [MkviProgressMotion] is the single value the caller's own
/// controller is built from, so the sweep is `style.duration('slow')` on
/// `style.motionEasing` and not whatever a screen had to hand:
///
/// ```dart
/// final MkviProgressMotion motion = MkviProgressMotion.of(context);
/// _controller = AnimationController(vsync: this, duration: motion.duration)
///   ..repeat();
/// ...
/// MkviLinearProgress(phase: _controller.value, motion: motion),
/// ```
///
/// ## Reduced motion needs no branch here either
///
/// `motion.reducedMotionNote` in the token file says every duration becomes
/// `instant` when the user asked for that, and `AppearanceResolver` does exactly
/// that, so [MkviProgressMotion.of] hands the caller `Duration.zero` and there
/// is nothing left to decide. A caller that builds a controller on a zero period
/// has a bug the token file cannot fix for it, which is why the note on
/// [MkviProgressMotion.isAnimated] says what to do instead: draw the phase as it
/// is. A bar frozen at a partial fill is the standard "this is indeterminate, do
/// not wait for it" picture, and it is the same picture with the movement
/// removed.
///
/// ## The two roles
///
/// The fill is `accent` and the track is `border`. The track is the interesting
/// one: 0.1.x's progress track measured **1.24:1**, and `border` is the role the
/// token file now declares at 3:1 against all five surfaces, so the track is
/// never a role the file forgot about. The stroke of the circle is
/// `control.focusRingWidth` — the token file's one "a visible line" width, which
/// is also the one that widens under high contrast — because it declares no
/// progress stroke and Material's own 4 dp default is a number the design system
/// does not own.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

/// The timing one sweep of an indeterminate bar is driven with.
///
/// Built from the tokens, once, by [MkviProgressMotion.of]: `style.duration`
/// for `'slow'` and `style.motionEasing`. With reduced motion the resolver has
/// already replaced every duration with `instant`, so this object says so
/// instead of a second code path having to.
@immutable
final class MkviProgressMotion {
  /// Creates a motion contract. Prefer [MkviProgressMotion.of].
  const MkviProgressMotion({required this.duration, required this.curve});

  /// The sweep contract of the palette [style] is about to paint.
  factory MkviProgressMotion.of(AppearanceStyle style) => MkviProgressMotion(
    duration: style.duration('slow'),
    curve: style.motionEasing,
  );

  /// `style.duration('slow')`, or `instant` under reduced motion.
  final Duration duration;

  /// `style.motionEasing`.
  final Cubic curve;

  /// Whether a sweep is possible at all.
  ///
  /// `false` means the user asked for reduced motion and the resolver answered
  /// with `instant`. A caller must then paint the [phase] it has and start no
  /// controller: an `AnimationController` on a zero period divides by zero, and
  /// that is a crash, not a still picture.
  bool get isAnimated => duration > Duration.zero;

  @override
  bool operator ==(Object other) =>
      other is MkviProgressMotion &&
      other.duration == duration &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(duration, curve);

  @override
  String toString() => 'MkviProgressMotion($duration)';
}

/// How far along the bar is.
///
/// One value for both cases, and the distinction is only *where the number comes
/// from*: a determinate bar is told `0.4` by a transfer, an indeterminate one is
/// handed `0.4` by a sweep. Nothing else about them differs, and a widget that
/// took two parameters for it would have two places to get the picture wrong.
class MkviLinearProgress extends StatelessWidget {
  /// Creates a bar.
  ///
  /// [value] between 0 and 1 draws that fraction. `null` draws the
  /// indeterminate segment at [phase], which is 0..1 and wraps.
  const MkviLinearProgress({
    super.key,
    this.value,
    this.phase = 0.0,
    this.heightStep = '4',
    this.label,
    this.motion,
  }) : assert(
         value == null || (value >= 0.0 && value <= 1.0),
         'a determinate progress is a fraction of the track, not a percentage',
       ),
       assert(
         phase >= 0.0 && phase <= 1.0,
         'phase is a position along the track; wrap it yourself if you repeat',
       );

  /// The fraction to draw, or `null` for the indeterminate segment.
  final double? value;

  /// Where the indeterminate fill sits, 0..1. A caller that repeats a sweep
  /// wraps it itself: the value is a position, not a clock.
  final double phase;

  /// The bar's thickness, as a `space.steps` name. A progress bar is a
  /// hairline; `'4'` is 4 dp at the cozy density and follows the user's density
  /// like every other gap.
  final String heightStep;

  /// The accessible name. Turkish, from the screen: "Dosya aktarılıyor".
  final String? label;

  /// The sweep contract, for a caller that draws a segment. Unused by the bar
  /// itself — it is carried so a screen does not have to hold two objects that
  /// must agree.
  final MkviProgressMotion? motion;

  /// Whether this bar knows how much is left.
  bool get isDeterminate => value != null;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return LinearProgressIndicator(
      // Never null: Material's own indeterminate runs a repeating controller,
      // which is the thing this file's library doc is about.
      value: value ?? phase,
      minHeight: style.gap(heightStep),
      color: style.role('accent'),
      backgroundColor: style.role('border'),
      borderRadius: style.shape('pill').borderRadius,
      // The M3 gap between the fill and the track is a Material default this
      // design system does not own, so it is pinned to the zero step.
      trackGap: style.gap('0'),
      // Material derives the "40" of a determinate bar itself, from `value`.
      semanticsLabel: label,
    );
  }
}

/// A progress drawn as a ring, for a place with no horizontal room to spare.
///
/// Determinate: the arc is the fraction. Indeterminate: the arc is
/// [MkviCircularProgress.indeterminateSweep] long and the whole ring is rotated
/// to [phase] — which is a rotation, so a test reads the turns the ring was
/// asked for rather than a rectangle, since a square ring's bounding box is the
/// same at every quarter turn.
class MkviCircularProgress extends StatelessWidget {
  /// Creates a ring.
  const MkviCircularProgress({
    super.key,
    this.value,
    this.phase = 0.0,
    this.controlSize = 'lg',
    this.label,
    this.motion,
  }) : assert(
         value == null || (value >= 0.0 && value <= 1.0),
         'a determinate progress is a fraction of the ring, not a percentage',
       ),
       assert(
         phase >= 0.0 && phase <= 1.0,
         'phase is a position along the ring; wrap it yourself if you repeat',
       );

  /// The fraction to draw, or `null` for the indeterminate arc.
  final double? value;

  /// Where the indeterminate arc points, 0..1 turns. A caller that repeats a
  /// sweep wraps it itself: the value is a position, not a clock.
  final double phase;

  /// The control size the ring is measured from: `'sm'`, `'md'` or `'lg'`. The
  /// ring's diameter is that control's height, so it grows with the density
  /// preference the same way every other control does.
  final String controlSize;

  /// The accessible name. Turkish, from the screen.
  final String? label;

  /// The sweep contract, for a caller that drives the rotation. Unused by the
  /// ring itself.
  final MkviProgressMotion? motion;

  /// How much of the ring an indeterminate sweep shows.
  ///
  /// A third, so the leading edge and the trailing edge are both visible at
  /// every phase and the ring never reads as "two thirds done". It is a
  /// proportion rather than a token because the token file declares no arc
  /// geometry; the ring's *thickness* and *size* are both tokens.
  static const double indeterminateSweep = 0.35;

  /// Whether this ring knows how much is left.
  bool get isDeterminate => value != null;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final Widget ring = CircularProgressIndicator(
      // Never null, for the same reason the linear bar's is not.
      value: value ?? indeterminateSweep,
      strokeWidth: style.focusRingWidth,
      color: style.role('accent'),
      backgroundColor: style.role('border'),
      semanticsLabel: label,
    );
    return SizedBox.square(
      dimension: style.control(controlSize).height,
      // `RotationTransition` takes turns directly, so the rotation is expressed
      // in the unit the caller thinks in. `Transform.rotate` in this Flutter
      // takes radians, and converting would mean `dart:math` in a layer that is
      // not allowed to have it.
      child: value != null
          ? ring
          : RotationTransition(
              turns: AlwaysStoppedAnimation<double>(phase),
              child: ring,
            ),
    );
  }
}
