/// The two hairlines and the empty space, all three read from one role.
///
/// MKVI has exactly one divider colour. The token file validates `border`
/// against all five surfaces at 3:1 — the old build's dividers measured
/// 1.6–2.3:1 and the fix is in the palette, not in a per-screen choice — so
/// there is nothing to configure here and no second, subtler line to reach for
/// when a screen "needs" one. A second divider colour is the 1.6:1 defect with a
/// nicer name.
///
/// `dividerTheme` in the resolved `ThemeData` already carries the same role and
/// the same thickness, so Material's own `Divider` would also be correct. These
/// exist for two reasons that `Divider` does not answer: the indents are
/// **space steps** (so they follow the density preference) rather than pixels,
/// and a vertical one is a widget rather than a `Row` with a `SizedBox` in it,
/// which is where a 0 px mistake hides.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

/// A hairline between two rows, in the one divider colour.
///
/// Exactly `control.borderWidth` tall — one logical pixel at every density,
/// because the token file says a border width is a physical promise and not a
/// style. The indents are `space.steps` names for the same reason the panel's
/// padding is: `'0'`..`'10'`, and an unknown name throws rather than quietly
/// indenting by nothing.
class MkviDivider extends StatelessWidget {
  /// Creates a horizontal hairline.
  const MkviDivider({super.key, this.startIndentStep, this.endIndentStep});

  /// Where the hairline starts, as a `space.steps` name. `null` is flush.
  final String? startIndentStep;

  /// Where the hairline ends, as a `space.steps` name. `null` is flush.
  final String? endIndentStep;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: startIndentStep == null ? 0.0 : style.gap(startIndentStep!),
        end: endIndentStep == null ? 0.0 : style.gap(endIndentStep!),
      ),
      // A `Border(top:)` rather than a coloured box, exactly as Material's own
      // `Divider` does it, and for the same reason: the width of a hairline
      // comes from the parent, and a `double.infinity` here would throw
      // "forces an infinite width" in the one context a caller might get wrong
      // (a `Row` without an `Expanded`). Tight width — a `Column` with
      // `stretch`, which is what a settings list is — gives a full-width line.
      child: SizedBox(
        height: style.borderWidth,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: style.role('border'), width: style.borderWidth),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hairline between two columns.
///
/// Its parent has to bound the height, and the usual way is a `Row` with
/// `CrossAxisAlignment.stretch` or an `IntrinsicHeight`; a vertical hairline in
/// a loosely-bounded row has no height to fill. The `minHeight` below keeps it
/// from disappearing *completely* in that case: a divider that silently measures
/// zero is worse than one that measures a hairline.
class MkviVerticalDivider extends StatelessWidget {
  /// Creates a vertical hairline.
  const MkviVerticalDivider({super.key, this.startIndentStep, this.endIndentStep});

  /// Where the hairline starts, as a `space.steps` name. `null` is flush.
  final String? startIndentStep;

  /// Where the hairline ends, as a `space.steps` name. `null` is flush.
  final String? endIndentStep;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: startIndentStep == null ? 0.0 : style.gap(startIndentStep!),
        end: endIndentStep == null ? 0.0 : style.gap(endIndentStep!),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: style.borderWidth),
        child: SizedBox(
          // No `double.infinity` height: a vertical rule takes the height it is
          // given, and `minHeight` is what keeps it from measuring zero when
          // the caller forgets to bound it.
          width: style.borderWidth,
          child: ColoredBox(color: style.role('border')),
        ),
      ),
    );
  }
}

/// Empty space, named.
///
/// The alternative is `SizedBox(height: style.gap('4'))` at every call site,
/// which is correct and unreadable: a column of thirty gaps reads as thirty
/// numbers. A step name reads as the space it is, and the name is what a
/// reviewer can check against the token file.
class MkviGap extends StatelessWidget {
  /// Creates a gap along the main axis of its parent.
  const MkviGap(this.step, {super.key, this.axis = Axis.vertical});

  /// The step, `'0'`..`'10'` from `design/tokens.json` `space.steps`.
  final String step;

  /// Which way the space goes.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final double size = AppearanceStyle.of(context).gap(step);
    return axis == Axis.vertical
        ? SizedBox(height: size)
        : SizedBox(width: size);
  }
}
