/// The header: who the peer is, which of the two names is which, and what the
/// connection is doing.
///
/// ## The two names
///
/// `src/App.tsx:119` was
///
/// ```ts
/// const peerName = peerAlias || peerAnnouncedName || defaultPeerName;
/// ```
///
/// so a note typed on *this* device outranked the name the peer published about
/// itself, and the announced name disappeared the moment a note existed. Worse,
/// `src/ChatCallWorkspace.tsx:490` computed
/// `aliasIsSet = Boolean(peerAnnouncedName && peerAnnouncedName !== peerName)`
/// and gated **both** the announced-name line and the "remove note" button on
/// it, so typing the peer's own name as a note made both disappear — the one
/// case where the peer is most likely to want to change it again.
///
/// This widget asks [PeerNameView] and never compares the two names itself:
///
/// * the headline is always [PeerNameView.displayName], which is the
///   announcement or the placeholder and is never the note;
/// * [PeerNameView.hasAlias] puts a **second** line under it, saying whose note
///   it is ([WorkspaceTr]'s `workspaceAliasLine`);
/// * [PeerNameView.showsAnnouncedName] — true whenever a note exists and the
///   announced name is known, *including when the two are equal* — puts the
///   "Kendi seçtiği ad: …" line back;
/// * [PeerNameView.canRemoveAlias] is the only thing that decides whether the
///   remove button is on screen.
///
/// ## The connection state is not a toast
///
/// The strip is [NoticeStatusBar], which reads the persistent status channel and
/// has no timer, no close button and no path to the notice lane. The reported
/// bug ("reconnecting" arriving as a toast that could not be dismissed) is
/// structurally impossible here: [NoticeController.setStatus] has no branch that
/// builds a notice.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/session/names.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/notice/notice.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'workspace_strings.dart';

/// The keys the header's parts answer to, so a test measures the part it means.
abstract final class WorkspaceHeaderKeys {
  /// The decorated surface: the two names and the status strip.
  static const Key header = Key('mkvi.workspace.header');

  /// The peer's own name — the headline. Never the local note.
  static const Key name = Key('mkvi.workspace.header.name');

  /// The line that says this device's note about the peer.
  static const Key aliasLine = Key('mkvi.workspace.header.alias');

  /// The line that says what the peer calls *itself*.
  static const Key announcedLine = Key('mkvi.workspace.header.announced');

  /// The initials well.
  static const Key avatar = Key('mkvi.workspace.header.avatar');

  /// The remove-the-note action. Absent when there is no note.
  static const Key removeAlias = Key('mkvi.workspace.header.removeAlias');

  /// The forget-this-device action.
  static const Key forgetPeer = Key('mkvi.workspace.header.forget');

  /// The row that holds the header's actions, so a test can measure them as a
  /// strip rather than finding the first `Wrap` in the tree.
  static const Key actions = Key('mkvi.workspace.header.actions');

  /// The row that holds the status strip and the actions. Separate from
  /// [actions] because a test that wants the connection state asks for this.
  static const Key meta = Key('mkvi.workspace.header.meta');
}

/// The top strip of the workspace: two names, a status strip, two actions.
///
/// Nothing here writes to the notice channel. [notice] is read by
/// [NoticeStatusBar] and that is the whole of this widget's use of it.
class WorkspaceHeader extends StatelessWidget {
  /// Creates the header.
  const WorkspaceHeader({
    super.key,
    required this.peer,
    required this.notice,
    required this.palette,
    this.metrics = const NoticeMetrics(),
    this.onRemoveAlias,
    this.onForgetPeer,
  });

  /// Who the peer is, already resolved. The UI never recomputes a name.
  final PeerNameView peer;

  /// The status channel. Listened to, never written to.
  final NoticeController notice;

  /// Every colour the strip draws with, resolved from the design tokens by the
  /// screen that builds this.
  final NoticePalette palette;

  /// The strip's measurements.
  final NoticeMetrics metrics;

  /// Removes this device's note. `null` hides the action, and a note with no
  /// action is a question the user cannot answer.
  final VoidCallback? onRemoveAlias;

  /// Forgets the pairing. `null` hides the action.
  final VoidCallback? onForgetPeer;

  /// The role this header paints, and the role its actions are given.
  ///
  /// A filled action on `surface` takes no `borderStrong` edge, by
  /// [mkviFilledActionNeedsEdge]'s rule — the same decision `MkviPanel` makes
  /// for a raised panel, made once and named.
  static const String surfaceRole = 'surface';

  /// The actions this header offers, in reading order, each with the key a test
  /// measures it by.
  ///
  /// The remove action is asked for by [PeerNameView.canRemoveAlias] and by the
  /// callback: a button that exists with nothing to do is the 0.1.x close
  /// button's other half.
  List<({Key key, MkviPanelAction action, String? tooltip})> _actions() {
    return <({Key key, MkviPanelAction action, String? tooltip})>[
      if (peer.canRemoveAlias && onRemoveAlias != null)
        (
          key: WorkspaceHeaderKeys.removeAlias,
          action: MkviPanelAction(
            label: peer.removeAliasLabel,
            onPressed: onRemoveAlias,
            icon: Icons.person_off_outlined,
          ),
          // No tooltip: [PeerNameView.removeAliasLabel] is already the whole
          // sentence, and a tooltip that says something *different* from the
          // label is worse than no tooltip at all. `peer.aliasButtonLabel` is
          // the session layer's word for the editor that *sets* a note, which is
          // not this button.
          tooltip: null,
        ),
      if (onForgetPeer != null)
        (
          key: WorkspaceHeaderKeys.forgetPeer,
          action: MkviPanelAction(
            label: WorkspaceTr.forgetDevice.tr,
            // The header fires; the SCREEN asks. Forgetting deletes the peer's
            // key and cannot be undone, so the confirmation cannot live in a
            // stateless header and must not be the shell's job either.
            onPressed: onForgetPeer,
            icon: Icons.link_off_rounded,
          ),
          // The one control on this screen that cannot be undone, so its
          // tooltip says what it costs. A screen reader reads the label, the
          // hint and the tooltip of a control, and this is the sentence that
          // turns "Bu cihazı unut" from a button into a decision.
          tooltip: WorkspaceTr.forgetDeviceLabel.tr,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final List<({Key key, MkviPanelAction action, String? tooltip})> actions =
        _actions();
    return Semantics(
      container: true,
      label: WorkspaceTr.headerRegion.tr,
      child: DecoratedBox(
        key: WorkspaceHeaderKeys.header,
        decoration: BoxDecoration(
          color: style.role('surface'),
          borderRadius: style.shape('lg').borderRadius,
          border: Border.all(
            color: style.role('borderStrong'),
            width: style.borderWidth,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(style.gap('4')),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _avatar(style),
                  SizedBox(width: style.gap('3')),
                  // `Expanded`, and nothing else in this row: the status strip
                  // and the actions each take a row of their own below, because
                  // three things side by side leave the *names* — the two things
                  // this header exists to keep apart — about 180 dp in a
                  // 400 dp window, and a name that wraps to three lines is a
                  // header that pushes the conversation off the screen.
                  Expanded(child: _names(style)),
                ],
              ),
              SizedBox(height: style.gap('3')),
              // The status strip and the actions share a row, and the row wraps:
              // at 400 dp the two Turkish labels do not fit beside each other
              // and become two lines rather than a horizontal scrollbar.
              Wrap(
                key: WorkspaceHeaderKeys.meta,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: style.gap('3'),
                runSpacing: style.gap('2'),
                children: <Widget>[
                  NoticeStatusBar(
                    controller: notice,
                    palette: palette,
                    metrics: metrics,
                  ),
                  if (actions.isNotEmpty)
                    Wrap(
                      key: WorkspaceHeaderKeys.actions,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: style.gap('2'),
                      runSpacing: style.gap('2'),
                      children: <Widget>[
                        for (final ({
                          Key key,
                          MkviPanelAction action,
                          String? tooltip,
                        }) entry in actions)
                          // The token file promises 44 dp of pointer target and
                          // the resolver's button themes set `minimumSize` to
                          // the 34 dp `md` control, so the promise is made here,
                          // once, rather than by a test that quietly measures
                          // the control instead of the target. The key is on this
                          // box, so what a test measures is the target and not
                          // the button inside it.
                          ConstrainedBox(
                            key: entry.key,
                            constraints: BoxConstraints(
                              minWidth: style.hitTargetMin,
                              minHeight: style.hitTargetMin,
                            ),
                            child: _button(entry, style),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The button itself, with the action's tooltip when it has one.
  Widget _button(
    ({Key key, MkviPanelAction action, String? tooltip}) entry,
    AppearanceStyle style,
  ) {
    final Widget button = MkviActionButton(
      action: entry.action,
      surfaceRole: surfaceRole,
    );
    return entry.tooltip == null
        ? button
        : Tooltip(message: entry.tooltip!, child: button);
  }

  /// The initials well: two letters off [PeerNameView.avatarInitials], which is
  /// `toLocaleUpperCase("tr-TR")` of the *primary* name in the original.
  Widget _avatar(AppearanceStyle style) {
    return Container(
      key: WorkspaceHeaderKeys.avatar,
      width: style.control('lg').height,
      height: style.control('lg').height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: style.role('accentSoft'),
        shape: BoxShape.circle,
      ),
      child: Text(
        peer.avatarInitials,
        style: style
            .styleOf('md')
            .copyWith(color: style.role('text'), fontWeight: FontWeight.w600),
      ),
    );
  }

  /// The two names, in two lines, and never one line with the other in it.
  Widget _names(AppearanceStyle style) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          peer.displayName,
          key: WorkspaceHeaderKeys.name,
          style: style.styleOf('lg').copyWith(color: style.role('text')),
        ),
        if (peer.hasAlias) ...<Widget>[
          SizedBox(height: style.gap('1')),
          Text(
            workspaceAliasLine(peer.alias),
            key: WorkspaceHeaderKeys.aliasLine,
            style: style.styleOf('sm').copyWith(color: style.role('textMuted')),
          ),
        ],
        // `showsAnnouncedName`, not `alias != announcedName`. That difference
        // is defect 7: the equality test made this line vanish for a note that
        // happens to be spelled like the peer's own name.
        if (peer.showsAnnouncedName) ...<Widget>[
          SizedBox(height: style.gap('1')),
          Text(
            peer.announcedNameLabel,
            key: WorkspaceHeaderKeys.announcedLine,
            style: style.styleOf('sm').copyWith(color: style.role('textMuted')),
          ),
        ],
      ],
    );
  }
}
