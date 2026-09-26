/// The one action button this screen uses, and the reason it is not
/// `MkviActionButton`.
///
/// ## What the token file promises, and what the theme declares
///
/// `control.hitTargetMin` is **44**, and the token file says it is a *physical*
/// promise: never multiplied by the density, the type scale or anything else.
/// The resolved `ThemeData` declares the opposite for every button —
///
/// ```dart
/// minimumSize: WidgetStatePropertyAll<Size>(Size(0, controls.md.height))
/// ```
///
/// and `controls.md.height` is **34** at density 1.0 (38.25 at `roomy`). Measured
/// on this branch, the resolved `filledButtonTheme.style.minimumSize` resolves to
/// `Size(0, 34)`.
///
/// So the promise is met today — by luck. `ThemeData.materialTapTargetSize` is
/// `MaterialTapTargetSize.padded`, whose minimum is a hard-coded **48** inside
/// Material, and `ButtonStyleButton` takes the larger of the two: the rendered
/// box measures 48 x 48 for both this widget and the widgets layer's. A number
/// the design system does not own is what is keeping the app's buttons above its
/// own token, and it disappears the moment a screen sets
/// `materialTapTargetSize: shrinkWrap`, or a future Flutter changes the 48.
///
/// `expectHitTarget` measures the **render box**, so it passes at 48 and would
/// keep passing through a `shrinkWrap` change right up to the frame where the
/// buttons are 34. Declaring the token in the button's own `minimumSize` makes
/// the promise a property of this widget rather than of a Material default, and
/// `pairing_enter_test.dart` measures all three numbers: the token, the theme's
/// declaration and the rendered box.
///
/// ## What is copied from `MkviActionButton`, and why it cannot be reused
///
/// Both interface rules the widgets layer documents in `README.md` are honoured
/// here, because a second button implementation that forgets one of them is
/// exactly the "two sources of truth for one control" the redesign ends:
///
/// 1. **the edge of a filled action** comes from [mkviFilledActionNeedsEdge] and
///    the caller's surface role, so a filled button on a `surfaceRaised` panel
///    takes the `borderStrong` edge and the same button on the page does not;
/// 2. **the label of an action with no fill is a surface role, not an on-fill
///    role** — `text` when it is enabled and `textSubtle` when it is disabled,
///    because `textOnAccent` measures 1.12:1 on a light `surface`.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

/// One action on the pairing screen: what it says and what it does.
///
/// A value and not a widget, so a caller hands the screen a list of them and the
/// screen decides the order. [onPressed] is `null` for a disabled action rather
/// than a flag, which is also what makes the action *locked* in a test: a
/// disabled Material button has a `null` handler, and that is the thing to
/// assert.
@immutable
final class PairingAction {
  /// Creates an action.
  const PairingAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
    this.buttonKey,
  });

  /// What the button says. Turkish, from [PairingTr].
  final String label;

  /// What it does, or `null` to lock it.
  final VoidCallback? onPressed;

  /// The leading glyph, or `null` for a text-only action.
  final IconData? icon;

  /// Whether this is the screen's primary action.
  final bool filled;

  /// The key the button answers to, so a test can press it and measure it.
  ///
  /// On the value rather than on the widget the caller builds: a caller that
  /// puts a list of these in a [PairingActionRow] cannot otherwise reach the
  /// individual buttons, and a control no test can address is a control nobody
  /// measured.
  final Key? buttonKey;

  /// Whether the action can be pressed.
  bool get enabled => onPressed != null;

  @override
  String toString() =>
      'PairingAction(${filled ? 'filled' : 'outlined'}, "$label", '
      '${enabled ? 'enabled' : 'locked'})';
}

/// A [PairingAction] as a button, at the hit target the token file promises.
class PairingActionButton extends StatelessWidget {
  /// Creates the button for [action], standing on [surfaceRole].
  const PairingActionButton({
    super.key,
    required this.action,
    required this.surfaceRole,
  });

  /// What to press.
  final PairingAction action;

  /// The token role of the surface this button is painted on — one of the 29 in
  /// `design/tokens.json`. `MkviPanelVariant.surfaceRole` and
  /// `MkviSectionHeader.surfaceRole` are the two the widgets layer supplies, and
  /// both are the right answer here.
  final String surfaceRole;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    // A zero *width* is "no minimum width", the same wording the resolver uses;
    // the height is the real promise and it comes from the token file.
    final double target = _targetHeight(style);
    final ButtonStyle base = ButtonStyle(
      minimumSize: WidgetStatePropertyAll<Size>(Size(0, target)),
    );    if (action.filled) {
      return FilledButton(
        onPressed: action.onPressed,
        style: base.copyWith(
          // Only the edge is overridden; the fill, the padding, the shape and
          // the label style are still the resolver's.
          side: WidgetStatePropertyAll<BorderSide>(
            mkviFilledActionNeedsEdge(surfaceRole)
                ? BorderSide(
                    color: style.role('borderStrong'),
                    width: style.borderWidth,
                  )
                : BorderSide.none,
          ),
        ),
        child: _label(style, style.role('textOnAccent')),
      );
    }
    return OutlinedButton(
      onPressed: action.onPressed,
      style: base.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.disabled)
              ? style.role('textSubtle')
              : style.role('text'),
        ),
      ),
      child: _label(style, style.role('text')),
    );
  }

  /// The button's own height: the `md` control, raised to the hit target.
  ///
  /// The `max` is not defensive noise — it is the rule the code field already
  /// states: a control height is never below the target at any density the app
  /// ships, so the two are separate numbers, and if a future density ever raised
  /// `md.height` past 44 the taller control wins.
  static double _targetHeight(AppearanceStyle style) {
    final double control = style.control('md').height;
    return control < style.hitTargetMin ? style.hitTargetMin : control;
  }

  Widget _label(AppearanceStyle style, Color colour) {
    final ResolvedControl md = style.control('md');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (action.icon != null) ...<Widget>[
          Icon(action.icon, size: md.iconSize, color: colour),
          SizedBox(width: md.gap),
        ],
        // Flexible, so a Turkish label wraps inside a narrow panel instead of
        // overflowing it — the other half of the 0.1.x clipped-label defect.
        Flexible(
          child: Text(
            action.label,
            style: style.styleOf('sm').copyWith(color: colour),
          ),
        ),
      ],
    );
  }
}

/// A row of [PairingAction]s that wraps instead of overflowing.
///
/// `Wrap` rather than `Row`, for the reason `MkviPanel`'s action strip gives:
/// two Turkish labels in a 320 dp column must become two lines, not an overflow
/// stripe. The surface role travels with every action, so the edge rule is a
/// property of where the row stands rather than of which button is in it.
class PairingActionRow extends StatelessWidget {
  /// Creates a wrapping action row.
  const PairingActionRow({
    super.key,
    required this.actions,
    required this.surfaceRole,
    this.alignment = WrapAlignment.start,
  });

  /// The actions, in the order they should be read.
  final List<PairingAction> actions;

  /// The token role of the surface the row stands on.
  final String surfaceRole;

  /// How the row is aligned when it has more than one line.
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Wrap(
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: style.gap('2'),
      runSpacing: style.gap('2'),
      children: <Widget>[
        for (final PairingAction action in actions)
          PairingActionButton(
            key: action.buttonKey,
            action: action,
            surfaceRole: surfaceRole,
          ),
      ],
    );
  }
}
