/// The two shapes every settings page and every long list is built from: a
/// heading with a description and an optional action, and a label/value row.
///
/// Both exist because the old UI had neither as a *thing*. `App.tsx` wrote a
/// `<div>` with a `fontSize: 13` label and a second `<div>` with the value, in
/// eleven places, and each of those eleven places picked its own colour, its own
/// gap and its own truncation — which is why one of them showed a timestamp at
/// 4.47:1 and another clipped a long Windows path. A primitive that owns the
/// label's colour (`textMuted`, the role the token file declares on all five
/// surfaces at 4.5:1) and hands the value `text` cannot be wrong in one place
/// and right in another.
///
/// A section header also passes its own surface role down to its actions, which
/// is how the `borderStrong`-on-a-raised-surface rule reaches a button that is
/// not inside a panel: a header is page-level, so its role is `bg` and a filled
/// action under it correctly takes no edge.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

import 'mkvi_panel.dart';

/// The keys the parts of a section answer to.
abstract final class MkviSectionKeys {
  /// The heading row, so a test can measure the strip as one box.
  static const Key header = Key('mkvi.section.header');

  /// The label of a [MkviKeyValueRow].
  static const Key label = Key('mkvi.section.label');

  /// The value of a [MkviKeyValueRow].
  static const Key value = Key('mkvi.section.value');
}

/// A heading, a sentence under it, and whatever the section offers on the right.
///
/// The heading is `lg` in `text` and the description is `sm` in `textMuted` —
/// two roles the token file declares against `bg`, `surface`, `surfaceRaised`,
/// `surfaceSoft` and `surfaceOverlay` alike, so a section header reads the same
/// on any of them and the matrix test in
/// `test/ui/widgets/states_test.dart` measures all five.
///
/// [trailing] is for the things that are not buttons — a badge, a switch, a
/// count. A button belongs in [actions], so the edge rule applies to it.
class MkviSectionHeader extends StatelessWidget {
  /// Creates a section heading.
  const MkviSectionHeader({
    super.key,
    required this.title,
    this.description,
    this.actions = const <MkviPanelAction>[],
    this.trailing,
    this.surfaceRole = 'bg',
    this.gapStep = '2',
  });

  /// The heading, in `lg`.
  final String title;

  /// One or more sentences in `sm`/`textMuted`. Optional.
  final String? description;

  /// The buttons this section offers, built through the same edge rule a panel
  /// uses. The first one is not treated as more important than the rest: a
  /// section offers actions, it does not have a primary one.
  final List<MkviPanelAction> actions;

  /// Anything that is not a button. A badge, a switch, a counter.
  final Widget? trailing;

  /// The role of the surface this header is painted on, passed straight to the
  /// actions. A header inside a [MkviPanel.raised] must say
  /// `'surfaceRaised'`, or a filled action under it will lose the edge it needs.
  final String surfaceRole;

  /// The gap between the heading block and the actions, as a `space.steps`
  /// name.
  final String gapStep;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Padding(
      key: MkviSectionKeys.header,
      padding: EdgeInsets.symmetric(vertical: style.gap(gapStep)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: style.styleOf('lg').copyWith(color: style.role('text')),
                ),
                if (description != null)
                  Text(
                    description!,
                    style: style
                        .styleOf('sm')
                        .copyWith(color: style.role('textMuted')),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty || trailing != null)
            SizedBox(width: style.gap('3')),
          if (actions.isNotEmpty)
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: style.gap('2'),
                runSpacing: style.gap('2'),
                children: <Widget>[
                  for (final MkviPanelAction action in actions)
                    MkviActionButton(action: action, surfaceRole: surfaceRole),
                ],
              ),
            ),
          if (trailing != null) ?trailing,
        ],
      ),
    );
  }
}

/// A label and its value on one line: the label muted, the value not.
///
/// A label in `textMuted` and a value in `text` is not a taste decision. It is
/// the only pair the token file declares on all five surfaces — 4.5:1 and 7:1 —
/// so a key/value row can be dropped into any panel in the app without a second
/// look at whether it can be read.
///
/// The value is trailing-aligned and shrinkable, and the label is the flexible
/// one: the values in this app are hashes, paths and version strings, and a
/// fingerprint that wraps into a column of hex is a row that no longer reads as
/// a row.
class MkviKeyValueRow extends StatelessWidget {
  /// Creates a label/value row.
  const MkviKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.gapStep = '3',
    this.dense = false,
  });

  /// What the value is. Turkish, from the screen.
  final String label;

  /// The value itself.
  final String value;

  /// The gap between the two, as a `space.steps` name.
  final String gapStep;

  /// Whether the row uses the two smallest type steps instead of `sm`.
  ///
  /// For a table of a dozen rows where the type is a reference rather than
  /// prose. The colours do not change: `textMuted` and `text` are the same
  /// pair at any size, and a size is not a licence to use `textSubtle`.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final String labelStep = dense ? '2xs' : 'sm';
    final String valueStep = dense ? 'xs' : 'sm';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: style.gap('2')),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              key: MkviSectionKeys.label,
              style: style
                  .styleOf(labelStep)
                  .copyWith(color: style.role('textMuted')),
            ),
          ),
          SizedBox(width: style.gap(gapStep)),
          Flexible(
            child: Text(
              value,
              key: MkviSectionKeys.value,
              textAlign: TextAlign.end,
              style: style.styleOf(valueStep).copyWith(color: style.role('text')),
            ),
          ),
        ],
      ),
    );
  }
}
