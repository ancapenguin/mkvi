/// The two states a screen shows when it has nothing to show, and when what it
/// has to show is a failure.
///
/// ## Why the reason is a constructor argument
///
/// The white pairing screen in 0.1.x was not a rendering bug, and the reason it
/// stayed white is the reason this file exists: `App.tsx` had four returns and
/// the pairing screen was the fallback one, reached whenever `knownPeer ===
/// null`. A first run, a corrupt store and a transient IPC failure all left that
/// field null, so two of the three showed the first-run screen, and a user who
/// had been paired for months woke up to a screen asking them to pair again.
///
/// The Dart half of that fix is `SetupState` — one case per thing that can be
/// true, and one method (`showsPairingScreen`) that decides whether pairing may
/// be built at all. This file is the other half: what the user is shown instead.
/// [MkviErrorState] takes the reason and the recovery as **required**
/// arguments, so a screen cannot build an error state that says *something went
/// wrong* and drops the cause:
///
/// ```dart
/// MkviErrorState(
///   title: state.title,          // 'Kayıtlı eş açılamadı'
///   reason: failure.message,      // SetupBroken.failure.message
///   message: failure.recovery,    // what the user can do about it
///   actions: <MkviPanelAction>[
///     MkviPanelAction(label: 'Tekrar dene', onPressed: retry, filled: true),
///     MkviPanelAction(label: 'Yeni cihaz eşle', onPressed: pair),
///   ],
/// )
/// ```
///
/// There is no overload that leaves the reason out, and the reason is rendered
/// in full: no `maxLines`, no ellipsis, no flexible box that swallows it. A 300
/// character Windows path or a keyring diagnostic is longer than the block, and
/// the block grows.
///
/// ## Why the error surface is `dangerFill` and not `surface`
///
/// Because "this failed" and "this is empty" must not look the same at a glance,
/// and a surface that merely *tints* is not a signal anybody reads. So the error
/// block paints the token file's `dangerFill` — a fill, one of the five the file
/// validates `textOnAccent` on at 4.5:1 — with a `danger` edge, and every glyph
/// and every string in it is `textOnAccent`, because that is the only role
/// declared on `dangerFill`. Hierarchy inside the block comes from the type step,
/// never from a second colour and never from opacity: the token file forbids
/// expressing hierarchy with opacity, which is where 0.1.x's 4.47:1 timestamp
/// came from.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

import 'mkvi_panel.dart';

/// The keys the parts of a state answer to.
abstract final class MkviStateKeys {
  /// The decorated error block: the `dangerFill` surface and its `danger` edge.
  static const Key errorSurface = Key('mkvi.state.error.surface');

  /// The error's cause. One widget, so a test can ask for the whole string.
  static const Key reason = Key('mkvi.state.error.reason');

  /// The error's recovery: what the user can do about it.
  static const Key message = Key('mkvi.state.error.message');

  /// The empty state's glyph well.
  static const Key emptyGlyph = Key('mkvi.state.empty.glyph');
}

/// [blocks] with a gap between each pair and none at either end.
///
/// A trailing gap inside a `Column(mainAxisSize: MainAxisSize.min)` is dead
/// space the caller paid for and cannot use, so the gap is inserted *between*
/// the blocks and never after the last one.
List<Widget> _separated(List<Widget> blocks, double gap) => <Widget>[
  for (int i = 0; i < blocks.length; i++) ...<Widget>[
    if (i > 0) SizedBox(height: gap),
    blocks[i],
  ],
];

/// Nothing to show, and nothing wrong: a glyph, a headline, a sentence.
///
/// [title] is required, so an empty state cannot be built with no wording — the
/// same rule `SetupState` follows by giving every case a `title`. A screen that
/// has nothing to list says *what* is empty, in Turkish, and this widget
/// supplies the layout and the two roles the token file declares on every
/// surface: `text` at 7:1 for the headline, `textMuted` at 4.5:1 for the
/// sentence.
///
/// The block is centred horizontally and takes only the height it needs. Where
/// it sits in the window is the screen's decision, because a list that is empty
/// because it is still loading and a search that found nothing belong in
/// different places.
class MkviEmptyState extends StatelessWidget {
  /// Creates an empty state.
  const MkviEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.actions = const <MkviPanelAction>[],
    this.surfaceRole = 'bg',
    this.gapStep = '3',
  });

  /// The headline. Turkish, and never absent: a required argument is a
  /// compile-time promise that somebody wrote it down.
  final String title;

  /// The sentence under it. Optional; a heading on its own is a valid state.
  final String? description;

  /// The glyph. Optional — a one-line state does not need a well.
  final IconData? icon;

  /// What the user can do about it. Nothing here is filled by default: an empty
  /// state is not a failure and should not shout.
  final List<MkviPanelAction> actions;

  /// The role of the surface this state is painted on, passed to the actions so
  /// the edge rule follows the surface rather than the widget.
  final String surfaceRole;

  /// The gap between the blocks, as a `space.steps` name.
  final String gapStep;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final double gap = style.gap(gapStep);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: _separated(<Widget>[
        if (icon != null) _glyphWell(style),
        Text(
          title,
          textAlign: TextAlign.center,
          style: style.styleOf('lg').copyWith(color: style.role('text')),
        ),
        if (description != null)
          Text(
            description!,
            textAlign: TextAlign.center,
            style: style
                .styleOf('sm')
                .copyWith(color: style.role('textMuted')),
          ),
        if (actions.isNotEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: style.gap('2'),
            runSpacing: style.gap('2'),
            children: <Widget>[
              for (final MkviPanelAction action in actions)
                MkviActionButton(action: action, surfaceRole: surfaceRole),
            ],
          ),
      ], gap),
    );
  }

  Widget _glyphWell(AppearanceStyle style) {
    // `surfaceSoft` with `textMuted` in it: both are declared on every surface,
    // so the well is the same object in all sixteen theme/accent combinations
    // and its edge never has to be reasoned about per screen.
    return Container(
      key: MkviStateKeys.emptyGlyph,
      width: style.control('lg').height,
      height: style.control('lg').height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.role('surfaceSoft'),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: style.control('lg').iconSize,
        color: style.role('textMuted'),
      ),
    );
  }
}

/// The block that says what failed, and what to do about it.
///
/// [reason] and [message] are both required and both rendered in full. There is
/// no `summary`-and-`details` collapse, no `maxLines` and no `TextOverflow`:
/// a diagnostic the user cannot read is a diagnostic support will be asked
/// about again.
///
/// The block is a `dangerFill` surface with a `danger` edge, and every string in
/// it is `textOnAccent` — the pair the token file declares on `dangerFill` at
/// 4.5:1. Its actions are given the `dangerFill` role, so a filled action on it
/// takes the strong edge by the same rule as a filled action on a raised panel
/// (see [mkviFilledActionNeedsEdge]).
class MkviErrorState extends StatelessWidget {
  /// Creates an error block.
  const MkviErrorState({
    super.key,
    required this.reason,
    required this.message,
    this.title,
    this.icon = Icons.error_outline_rounded,
    this.actions = const <MkviPanelAction>[],
    this.paddingStep = '4',
    this.gapStep = '3',
    this.radiusStep = 'lg',
  });

  /// What went wrong. Never dropped, never truncated.
  final String reason;

  /// What the user can do about it, in Turkish, as an instruction rather than
  /// as an apology.
  final String message;

  /// The headline, when the state has one. Optional: a one-line failure with a
  /// long diagnostic does not need a title above it.
  final String? title;

  /// The glyph. There is only one meaning here, so it has a default.
  final IconData? icon;

  /// What can be done about it. `SetupBroken` has two: retry, and pair a new
  /// device as the documented last resort.
  final List<MkviPanelAction> actions;

  /// The padding between the edge and the text, as a `space.steps` name.
  final String paddingStep;

  /// The gap between the blocks, as a `space.steps` name.
  final String gapStep;

  /// The corner radius, as a `radius.steps` name.
  final String radiusStep;

  /// The role this block paints, which is also the role its actions are given.
  static const String surfaceRole = 'dangerFill';

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final Color onFill = style.role('textOnAccent');
    final List<Widget> blocks = <Widget>[
      if (title != null)
        Text(
          title!,
          style: style.styleOf('lg').copyWith(color: onFill),
        ),
      // With no title the reason *is* the headline, so it takes the headline
      // step. Either way it is the same colour: a second, dimmer colour on
      // `dangerFill` is not a declared pair, and an undeclared pair is how the
      // 4.47:1 timestamp happened.
      Text(
        reason,
        key: MkviStateKeys.reason,
        style: style
            .styleOf(title == null ? 'lg' : 'md')
            .copyWith(color: onFill),
      ),
      Text(
        message,
        key: MkviStateKeys.message,
        style: style.styleOf('sm').copyWith(color: onFill),
      ),
      if (actions.isNotEmpty)
        Wrap(
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: style.gap('2'),
          runSpacing: style.gap('2'),
          children: <Widget>[
            for (final MkviPanelAction action in actions)
              MkviActionButton(action: action, surfaceRole: surfaceRole),
          ],
        ),
    ];

    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        key: MkviStateKeys.errorSurface,
        decoration: BoxDecoration(
          color: style.role(surfaceRole),
          borderRadius: style.shape(radiusStep).borderRadius,
          border: Border.all(
            color: style.role('danger'),
            width: style.borderWidth,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(style.gap(paddingStep)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: style.control('lg').iconSize, color: onFill),
                SizedBox(width: style.gap('3')),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _separated(blocks, style.gap(gapStep)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
