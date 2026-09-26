/// The raised surface a screen lays its content out in — and the one place the
/// `ROADMAP.md` Faz 2 rule about a filled action standing on a raised surface
/// is implemented, because that rule is an interface rule and not a token rule.
///
/// ## Why this is here and not in the theme
///
/// `AppearanceResolver` builds a complete `ThemeData`: the filled, outlined and
/// text buttons, the input borders, the focus ring, the text theme, all fifteen
/// colour roles of the `ColorScheme` and every slot of the text theme. Material's
/// own widget is used for all of that and this layer rebuilds none of it. What
/// Material cannot know is **what a button is standing on**: `side` is a
/// property of the button, and the token file measures `borderStrong` against
/// every surface without being able to say which controls must carry one.
///
/// So the decision is made once, here, from the surface role the caller passes
/// in ([MkviActionButton.surfaceRole]), and a screen cannot get it wrong by
/// forgetting:
///
/// ```dart
/// MkviPanel.raised(actions: <MkviPanelAction>[
///   MkviPanelAction(label: 'Kaydet', onPressed: save, filled: true),
/// ])
///
/// MkviPanel.flat(actions: <MkviPanelAction>[
///   MkviPanelAction(label: 'Kaydet', onPressed: save, filled: true),
/// ])
/// ```
///
/// The first takes the `borderStrong` edge, the second does not, and
/// `test/ui/widgets/surfaces_test.dart` measures both against the palette they
/// are about to be painted with — by reading the role the panel paints, not by
/// comparing a hard-coded colour.
///
/// ## What a panel is not
///
/// It is not a card, a dialog or a scaffold. It is the raised rectangle the rest
/// of the primitives are arranged in: a [MkviPanelVariant.surfaceRole], a token
/// radius, an optional [MkviPanel.bordered] edge, optional padding steps and an
/// optional title/action strip. Everything inside it is another primitive.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

/// The keys the parts of a panel answer to, so a test measures the part it
/// means rather than the first `Padding` it finds.
abstract final class MkviPanelKeys {
  /// The decorated surface: the box the eye sees.
  static const Key surface = Key('mkvi.panel.surface');

  /// The title/subtitle/action strip. Absent when the panel has none.
  static const Key header = Key('mkvi.panel.header');

  /// The caller's content, wrapped so it has a rect of its own.
  static const Key body = Key('mkvi.panel.body');
}

/// Which surface a [MkviPanel] paints — and, for a filled action inside one,
/// whether it takes the strong edge.
enum MkviPanelVariant {
  /// `surfaceRaised`: a panel that sits above the page.
  raised('surfaceRaised'),

  /// `surfaceSoft`: a well. The same fill the input fields use, so a form and
  /// the field inside it do not disagree about what an inset looks like.
  soft('surfaceSoft'),

  /// No fill. The window background shows through, so the panel is a structure
  /// rather than a surface.
  ///
  /// The role is still `bg` rather than nothing, because it is the surface a
  /// control inside it is measured against, and `bg` is the surface the window
  /// is.
  flat('bg');

  const MkviPanelVariant(this.surfaceRole);

  /// The role this variant stands on.
  ///
  /// For [raised] and [soft] it is also the fill: there is no second answer.
  final String surfaceRole;

  /// Whether this variant paints a fill of its own.
  bool get paintsFill => this != MkviPanelVariant.flat;

  /// Whether a filled action standing on this variant takes the strong edge.
  bool get givesFilledActionsAnEdge =>
      mkviFilledActionNeedsEdge(surfaceRole);
}

/// `ROADMAP.md` Faz 2, implemented rather than ticked:
///
/// > Vurgu dolu düğme, yükseltilmiş yüzeyde `borderStrong` kenarı alacak. Bu bir
/// > token kuralı değil, arayüz kuralı.
///
/// The token test cannot measure it: `design/test/contrast_test.dart` proves
/// that `borderStrong` clears 3:1 on all five surfaces, and that says nothing
/// about which controls must carry the edge. The rule is about the *pairing* of
/// a solid accent fill with the surface behind it — a filled button is a shape
/// with no outline, and on a surface that is not the page's own background the
/// shape stops being findable.
///
/// So it is written as the one thing that is certainly wrong rather than as the
/// list of the two things `ROADMAP.md` happens to name: **the edge goes on
/// unless the fill stands directly on `bg` or `surface`.** The two named cases
/// come out the same either way — `surfaceRaised` and `surfaceSoft` take the
/// edge, `bg` does not — and a role nobody thought of (`surfaceOverlay` under a
/// dialog, `dangerFill` under [MkviErrorState]) is on the safe side of the
/// decision instead of the unsafe one.
bool mkviFilledActionNeedsEdge(String surfaceRole) =>
    surfaceRole != 'bg' && surfaceRole != 'surface';

/// One action in a panel's title strip.
///
/// A value, not a widget: the panel owns the layout, the surface role and the
/// edge rule, and the caller owns the wording and the callback. The label is
/// Turkish because the screen that builds this is Turkish — this layer ships no
/// string of its own, so a panel cannot be built with no wording at all.
@immutable
final class MkviPanelAction {
  /// Creates an action.
  const MkviPanelAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
  });

  /// What the button says. Turkish, from the screen.
  final String label;

  /// What it does. `null` disables the action rather than hiding it, so a
  /// disabled action still occupies its place in the strip.
  final VoidCallback? onPressed;

  /// The leading glyph. `null` for a text-only action.
  final IconData? icon;

  /// Whether this is the panel's primary action.
  ///
  /// A filled action is the one that takes (or does not take) the strong edge
  /// of [MkviPanelVariant.givesFilledActionsAnEdge].
  final bool filled;

  /// Whether the action can be pressed.
  bool get enabled => onPressed != null;

  @override
  String toString() =>
      'MkviPanelAction(${filled ? 'filled' : 'outlined'}, "$label", '
      '${enabled ? 'enabled' : 'disabled'})';
}

/// The one button in the app that knows what it is standing on.
///
/// Material's [FilledButton] and [OutlinedButton] do the work — the metrics,
/// the ink, the hover, the press and the disabled states all come from the
/// `ThemeData` the resolver built — and this widget adds the two things the
/// theme cannot know:
///
/// 1. **the edge of a filled action**, from [mkviFilledActionNeedsEdge];
/// 2. **the label colour of an action that has no fill**, which is a function
///    of the surface it stands on and not of the accent it is themed with.
///
/// On (2): the theme hands `textOnAccent` to every button, which is right for a
/// filled one — it is an on-FILL role and the fill is `accent`, a pair the token
/// file measures at 4.5:1. It is wrong for an action with no fill, because that
/// label stands on [surfaceRole], and in the light theme `textOnAccent` is white
/// on a near-white `surface`: 1.00:1. The role the token file declares on all
/// five surfaces is `text` (7:1, and `textSubtle` at 4.5:1 when disabled), so
/// that is what an unfilled action uses here. The resolver is not this layer's
/// to change; `test/ui/widgets/surfaces_test.dart` measures both roles against
/// the surface the button is standing on, so the day the theme agrees the
/// assertion says so.
class MkviActionButton extends StatelessWidget {
  /// Creates the action button for [action], standing on [surfaceRole].
  const MkviActionButton({
    super.key,
    required this.action,
    required this.surfaceRole,
  });

  /// What to press.
  final MkviPanelAction action;

  /// The role of the surface this button is painted on. One of the 29 token
  /// role names; `MkviPanelVariant.surfaceRole` and
  /// `MkviSectionHeader.surfaceRole` are the two this layer supplies.
  final String surfaceRole;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    if (action.filled) return _filled(style);
    return _outlined(style);
  }

  Widget _filled(AppearanceStyle style) {
    return FilledButton(
      onPressed: action.onPressed,
      // Only the edge is overridden: `ButtonStyleButton` merges this over the
      // theme's `filledButtonTheme`, so the fill, the height, the padding, the
      // shape and the label style are still the resolver's.
      style: ButtonStyle(
        side: WidgetStatePropertyAll<BorderSide>(
          mkviFilledActionNeedsEdge(surfaceRole)
              ? BorderSide(
                  color: style.role('borderStrong'),
                  width: style.borderWidth,
                )
              : BorderSide.none,
        ),
      ),
      child: _label(style),
    );
  }

  Widget _outlined(AppearanceStyle style) {
    return OutlinedButton(
      onPressed: action.onPressed,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.disabled)
              ? style.role('textSubtle')
              : style.role('text'),
        ),
      ),
      child: _label(style),
    );
  }

  Widget _label(AppearanceStyle style) {
    // `md` is the control every button in this design is built from: the
    // resolver's button themes measure `controls.md` and nothing else.
    final ResolvedControl control = style.control('md');
    final Color colour = action.filled
        ? style.role('textOnAccent')
        : style.role('text');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (action.icon != null) ...<Widget>[
          Icon(action.icon, size: control.iconSize, color: colour),
          SizedBox(width: control.gap),
        ],
        // Flexible, so a long Turkish label wraps inside a narrow panel instead
        // of overflowing it: 0.1.x clipped its own labels in narrow windows.
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

/// A rectangle of one of the three surface roles, with an optional title strip.
///
/// Three named constructors rather than a variant field a caller can forget to
/// set: [MkviPanel.raised] is a panel above the page, [MkviPanel.soft] is a
/// well, and [MkviPanel.flat] is a structure with no fill — and only the last
/// one is born with an edge, because a flat panel with neither a fill nor an
/// edge is not a panel, it is a guess.
///
/// The header is optional and self-effacing: no title, no subtitle and no
/// actions means no header row at all, so a panel that is only a well costs
/// nothing vertically.
class MkviPanel extends StatelessWidget {
  /// Creates a panel on the `surfaceRaised` surface.
  const MkviPanel.raised({
    super.key,
    this.title,
    this.subtitle,
    this.actions = const <MkviPanelAction>[],
    this.bordered = false,
    this.paddingStep = '4',
    this.headerGapStep = '3',
    this.radiusStep = 'md',
    this.child,
  }) : variant = MkviPanelVariant.raised;

  /// Creates a panel on the `surfaceSoft` well.
  const MkviPanel.soft({
    super.key,
    this.title,
    this.subtitle,
    this.actions = const <MkviPanelAction>[],
    this.bordered = false,
    this.paddingStep = '4',
    this.headerGapStep = '3',
    this.radiusStep = 'md',
    this.child,
  }) : variant = MkviPanelVariant.soft;

  /// Creates a panel with no fill of its own, on the window background.
  ///
  /// Born with an edge, because that is the only thing a fill-less rectangle
  /// can be seen by. Pass `bordered: false` to turn even that off.
  const MkviPanel.flat({
    super.key,
    this.title,
    this.subtitle,
    this.actions = const <MkviPanelAction>[],
    this.bordered = true,
    this.paddingStep = '4',
    this.headerGapStep = '3',
    this.radiusStep = 'md',
    this.child,
  }) : variant = MkviPanelVariant.flat;

  /// Which surface this panel is on. Fixed by the constructor, so a panel's
  /// edge rule can never disagree with its fill.
  final MkviPanelVariant variant;

  /// The content.
  final Widget? child;

  /// The title. Optional: a panel with no title and no actions has no header.
  final String? title;

  /// One line under the title, in `textMuted`.
  final String? subtitle;

  /// The actions, in the order they should be read.
  final List<MkviPanelAction> actions;

  /// Whether the panel takes the `borderStrong` edge.
  final bool bordered;

  /// The padding between the panel's edge and its content, as a
  /// `design/tokens.json` `space.steps` name: `'0'`..`'10'`, `'4'` by default.
  ///
  /// A step name rather than a number, because a number here would be a
  /// literal that ignores the user's density — which is the defect
  /// `AppearanceStyle` exists to make impossible. An unknown name throws
  /// rather than falling back to a default.
  final String paddingStep;

  /// The gap between the header strip and the body, same naming.
  final String headerGapStep;

  /// The corner radius, as a `radius.steps` name: `'none'`, `'xs'`, `'sm'`,
  /// `'md'`, `'lg'`, `'xl'`, `'pill'`.
  final String radiusStep;

  /// Whether this panel has a header row at all.
  bool get hasHeader => title != null || subtitle != null || actions.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Material(
      // Transparent: the panel paints itself below, and this exists so the
      // actions inside it have a `Material` ancestor for their ink.
      type: MaterialType.transparency,
      child: DecoratedBox(
        key: MkviPanelKeys.surface,
        decoration: BoxDecoration(
          color: variant.paintsFill ? style.role(variant.surfaceRole) : null,
          borderRadius: style.shape(radiusStep).borderRadius,
          border: bordered
              ? Border.all(
                  color: style.role('borderStrong'),
                  width: style.borderWidth,
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.all(style.gap(paddingStep)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (hasHeader) _header(style),
              if (hasHeader && child != null)
                SizedBox(height: style.gap(headerGapStep)),
              if (child != null) KeyedSubtree(key: MkviPanelKeys.body, child: child!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppearanceStyle style) {
    return Row(
      key: MkviPanelKeys.header,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // Expanded, so a long title gives way instead of pushing the actions
        // out of the panel.
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title != null)
                Text(
                  title!,
                  style: style.styleOf('lg').copyWith(color: style.role('text')),
                ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: style
                      .styleOf('sm')
                      .copyWith(color: style.role('textMuted')),
                ),
            ],
          ),
        ),
        if (actions.isNotEmpty)
          Flexible(
            child: Wrap(
              // A wrap, not a row: two Turkish action labels in a 280 dp column
              // must become two lines, not an overflow stripe.
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: style.gap('2'),
              runSpacing: style.gap('2'),
              children: <Widget>[
                for (final MkviPanelAction action in actions)
                  MkviActionButton(
                    action: action,
                    surfaceRole: variant.surfaceRole,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
