/// The small box that shows this device's own camera while the main stage shows
/// the peer's — and, when the peer's camera has not arrived, the other way round.
///
/// ## Why the size is a multiple of a control height
///
/// 0.1.x pinned the peer's video to a literal 126 px and drew the local preview
/// as whatever the CSS said. A literal cannot follow the user's density, and
/// `ROADMAP.md` already records the cost of that pattern: `density` was honoured
/// in 8 call sites out of ~40 because it was a value nobody was obliged to read.
///
/// So the box is **four `sm` controls tall**, and nothing else:
///
/// ```dart
/// double pipSide(AppearanceStyle style) => style.control('sm').height * 4;
/// ```
///
/// Four is a proportion, not a metric: it says "the small picture is four
/// button-heights across", which is a shape the design system can scale with
/// density and a type scale can never argue with. `pipSide` is public and
/// side-effect free so a test can compare a measured rect against the same
/// function the widget used — and the *proportionality* assertion (the same
/// multiple in `compact` and in `roomy`) is the one that would catch a literal
/// sneaking back in.
///
/// ## Why the corner is a parameter and not a drag
///
/// The original offered a draggable picture-in-picture. A drag is three things
/// this layer cannot own honestly — a gesture arena decision, a saved position
/// per window, and a hit target that moves — and none of them is what the
/// reported defect was. The defect was that the main stage was **pinned** to the
/// local camera, and a corner is enough to stop the two pictures fighting for the
/// same rectangle. The position is therefore a [LocalPipCorner], which is a value
/// a test can measure with `tester.getRect` and a shell can change.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

import 'call_strings.dart';
import 'video_tile.dart';

/// Which corner the small picture sits in.
enum LocalPipCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  /// The [Alignment] this corner means, which is also how a test reads it.
  Alignment get alignment => switch (this) {
    LocalPipCorner.topLeft => Alignment.topLeft,
    LocalPipCorner.topRight => Alignment.topRight,
    LocalPipCorner.bottomLeft => Alignment.bottomLeft,
    LocalPipCorner.bottomRight => Alignment.bottomRight,
  };
}

/// The keys the parts of the small picture answer to.
abstract final class LocalPipKeys {
  /// The whole small picture, position and size. What a test measures for both.
  static const Key box = Key('mkvi.call.pip.box');
}

/// The small picture.
///
/// [widthFraction] is how much of the stage's width it takes, so it shrinks with
/// the stage instead of overflowing a narrow window. It is a fraction rather
/// than a length for the same reason the height is a multiple: a number here
/// would be the 126 px all over again.
class LocalPip extends StatelessWidget {
  /// Creates the small picture.
  const LocalPip({
    super.key,
    required this.label,
    this.caption,
    this.corner = LocalPipCorner.topRight,
    this.widthFraction = _defaultWidthFraction,
    this.insetStep = '0',
    this.icon = Icons.person_outline_rounded,
  });

  /// One of these five-eighths-ish defaults to; overridable for a wide stage.
  static const double _defaultWidthFraction = 0.26;

  /// Whose camera this is, in Turkish.
  final String label;

  /// The line under [label], when there is one.
  final String? caption;

  /// Which corner.
  final LocalPipCorner corner;

  /// How much of the stage's width the box takes, as a fraction in `0 < f < 1`.
  final double widthFraction;

  /// The space between the box and the edges of whatever holds it, as a
  /// `space.steps` name.
  ///
  /// `'0'` by default, because the stage that holds this picture already has a
  /// gutter of its own (`gap('3')`) and a second one would double it: measured
  /// at 24 dp where 12 dp was meant. Standalone, pass a step.
  final String insetStep;

  /// The glyph shown while no frame is arriving.
  final IconData icon;

  /// The short side of the small picture, in logical pixels.
  ///
  /// Public, pure and token-derived: the widget calls it, and so does the test
  /// that measures the rect. Four `sm` control heights, which is 112 dp at the
  /// default density and 98 dp at `compact`.
  static double sideOf(AppearanceStyle style) =>
      style.control('sm').height * _smHeightsAcross;

  /// How many `sm` control heights the small picture is across.
  static const int _smHeightsAcross = 4;

  /// The width the small picture is given, in [available] pixels.
  ///
  /// A fraction of the stage, capped at [sideOf] — and the cap has to be applied
  /// *after* the fraction, not before. A `ConstrainedBox` above a
  /// `FractionallySizedBox` measures the fraction of the **cap**, so at a 1280 dp
  /// stage the picture came out 29 dp wide: a quarter of 112, which is not a
  /// quarter of anything the user can see.
  double widthFor(double available, AppearanceStyle style) {
    final double fraction = available * widthFraction;
    final double cap = sideOf(style);
    return fraction < cap ? fraction : cap;
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Align(
      alignment: corner.alignment,
      child: Padding(
        padding: EdgeInsets.all(style.gap(insetStep)),
        // `LayoutBuilder` rather than a fraction widget, because the fraction has
        // to be taken of the *stage's* width and then capped. See [widthFor].
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SizedBox(
              // The key is on the picture itself and not on the `Align` around
              // it, so `tester.getRect` measures the small box and not the whole
              // stage.
              key: LocalPipKeys.box,
              width: widthFor(constraints.maxWidth, style),
              child: Semantics(
                // The box is not a control, so this is a *label* and not a
                // button: `expectHitTarget` on it would be measuring a promise
                // this widget does not make. The name is what a screen reader
                // needs, because "a small box" is not a thing it can see.
                label: '$label. ${CallUiTr.pipLabel}',
                child: ExcludeSemantics(
                  child: VideoTile(
                    label: label,
                    caption: caption,
                    icon: icon,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
