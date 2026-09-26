/// The small pill a row carries when the thing it is about has a state: paired,
/// waiting, expired, 3 files.
///
/// A label needs a background that means something, and a background that means
/// something needs a *pair*, not just a colour. The token file declares exactly
/// the pairs this widget uses and nothing else:
///
/// | tone | surface | label | declared at |
/// |---|---|---|---|
/// | [MkviBadgeTone.accent] | `accentSoft` | `text` | 6:1 |
/// | [MkviBadgeTone.success] | `successSoft` | `text` | 6:1 |
/// | [MkviBadgeTone.warning] | `warningSoft` | `text` | 6:1 |
/// | [MkviBadgeTone.danger] | `dangerFill` | `textOnAccent` | 4.5:1 |
///
/// The last row is the interesting one. `danger` is the role the file validates
/// as *text* on every surface, so a red label on a red pill would be that role
/// doing the wrong job: `danger` on `dangerFill` measures **1.34:1** in the light
/// theme and 1.75:1 in midnight. `dangerFill` is a *fill*, and the fill's own
/// declared pair is `textOnAccent` at **4.83:1** — so a danger badge is a red
/// pill with the light on-colour in it, and a test measures that in all sixteen
/// theme/accent combinations instead of assuming red-on-red is fine.
///
/// ## The edge is `border`, not `borderStrong`
///
/// A badge is a label, and a label's edge separates it from the surface it
/// stands on — the same job `divider` does, one step weaker. That is the pair
/// the token file declares: `border` at 3:1 against `bg`, `surface`,
/// `surfaceRaised`, `surfaceSoft` and `surfaceOverlay` alike. It is deliberately
/// *not* a claim about the pill's own fill, where `border` measures about 1.1:1
/// and draws nothing; a hairline around a fill is decoration pretending to be
/// structure.
///
/// `borderStrong` is reserved for the thing the `ROADMAP.md` Faz 2 rule is
/// about: a *filled* button, whose only boundary would otherwise be the shape of
/// its own fill. Spending `borderStrong` on every badge in a list would flatten
/// the one place it carries meaning.
///
/// A badge is **not** a control: it has no hit target, no focus and no
/// callback. `expectHitTarget` on a badge would be measuring the wrong promise.
/// If the user has to *act* on what the badge says, put an action next to it —
/// which is what [MkviPanelAction] is for.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

/// The four meanings a badge can carry, and the token pair each one is painted
/// in.
enum MkviBadgeTone {
  /// Neutral, "this is the app speaking". `accentSoft` with `text` on it.
  accent('accentSoft', 'text'),

  /// It worked. `successSoft` with `text` on it.
  success('successSoft', 'text'),

  /// It needs attention but nothing is lost. `warningSoft` with `text` on it.
  warning('warningSoft', 'text'),

  /// It failed or it is unsafe. `dangerFill` with `textOnAccent` on it.
  danger('dangerFill', 'textOnAccent');

  const MkviBadgeTone(this.surfaceRole, this.labelRole);

  /// The role the pill is filled with.
  final String surfaceRole;

  /// The role the text is drawn in — the one the token file declares *on*
  /// [surfaceRole], which is why the danger tone's label is not `danger`.
  final String labelRole;
}

/// One small state label.
///
/// Sized in `2xs` by default: a badge is read, not read at, and a `sm` badge on
/// a list row competes with the row's own value. `dense: false` gives `xs` for
/// the one badge on a screen that has to be noticed from across a room — a
/// device's connection state, say.
class MkviBadge extends StatelessWidget {
  /// Creates a badge.
  const MkviBadge({
    super.key,
    required this.label,
    this.tone = MkviBadgeTone.accent,
    this.icon,
    this.dense = true,
    this.paddingStep = '2',
  });

  /// What the badge says. Turkish, one or two words.
  final String label;

  /// Which meaning this badge carries.
  final MkviBadgeTone tone;

  /// The leading glyph. Optional.
  final IconData? icon;

  /// Whether the badge uses the two smallest type steps, which is the default.
  /// `false` steps up to `xs`.
  final bool dense;

  /// The horizontal padding, as a `space.steps` name. The vertical padding is
  /// one step below it, so the pill is not a lozenge.
  final String paddingStep;

  /// The type step the label is set in.
  String get typeStep => dense ? '2xs' : 'xs';

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final Color labelColour = style.role(tone.labelRole);
    return Container(
      decoration: BoxDecoration(
        color: style.role(tone.surfaceRole),
        borderRadius: style.shape('pill').borderRadius,
        border: Border.all(color: style.role('border'), width: style.borderWidth),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: style.gap(paddingStep),
        vertical: style.gap('1'),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              // `sm`: a glyph in a `2xs` label is unreadable, and the token
              // file is explicit that icon sizes never follow density.
              size: style.control('sm').iconSize,
              color: labelColour,
            ),
            SizedBox(width: style.gap('1')),
          ],
          Text(label, style: style.styleOf(typeStep).copyWith(color: labelColour)),
        ],
      ),
    );
  }
}
