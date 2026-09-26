/// The transfer list: five states, a bounded box, and a saved file's path that
/// does not get painted.
///
/// ## The three defects this file is measured against
///
/// 1. **A full Windows path grew the list.** `ROADMAP.md` kusur 8 records the
///    notice carrying a saved path as the reason the toast grew down over the
///    message list, and the transfer row had the same problem one screen over:
///    `TransferView.detail` is the destination on a completed receive, and a
///    destination is 200-odd characters of unbroken text with no break
///    opportunity. So the row **never paints the path** — it says
///    [WorkspaceTr.saved] and stops, and the row's two text lines are capped with
///    an ellipsis. `TransferView.detail` keeps the path as a *value*, for a
///    caller that needs it; it is not a thing the list shows.
/// 2. **The list was unbounded.** `App.tsx` had
///    `useState<transfers>([])` and only ever appended, so a session that sent a
///    few hundred files showed a list nobody could scroll. The list here is
///    capped at [TransferList.maxRows] rows tall, each row's share of the height
///    derived from the type scale, the bar and the hit target, and the rest
///    scrolls inside the box instead of pushing the conversation off the screen.
/// 3. **The close button was 34 px.** `src/App.css:190` set
///    `width: 34px; height: 34px` on it, and the whole `font` shorthand in the
///    same rule was invalid CSS, so the glyph rendered unstyled. Every control
///    in this file is drawn at `AppearanceStyle.hitTargetMin` and carries a
///    Turkish word, not a bare ✕.
///
/// ## Five states, and the actions each one offers
///
/// `TransferPhase` is closed and [TransferView.stateLabel] already spells it in
/// Turkish, so the badge is [TransferView.stateLabel] rather than a second
/// mapping. The actions are asked for per phase: an announced incoming offer is
/// the only state with two, an answer is never silent, and a settled row can be
/// dismissed without cancelling anything — which is what
/// [TransferPhase.isTerminal] means.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/core/protocol/file_transfer.dart' show TransferDirection;
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'workspace_strings.dart';

/// The keys the transfer list's parts answer to.
abstract final class TransferListKeys {
  /// The list's own box. Absent when there is nothing to show.
  static const Key list = Key('mkvi.workspace.transfers');

  /// One transfer, as one box.
  static Key row(String id) => Key('mkvi.workspace.transfer.$id');

  /// The row's headline: the direction and the file's name.
  static Key heading(String id) => Key('mkvi.workspace.transfer.heading.$id');

  /// The state badge.
  static Key state(String id) => Key('mkvi.workspace.transfer.state.$id');

  /// The detail line — never a saved path.
  static Key detail(String id) => Key('mkvi.workspace.transfer.detail.$id');

  /// The progress bar, on the states that have one.
  static Key progress(String id) => Key('mkvi.workspace.transfer.progress.$id');

  /// Accept an announced offer.
  static Key accept(String id) => Key('mkvi.workspace.transfer.accept.$id');

  /// Decline an announced offer.
  static Key decline(String id) => Key('mkvi.workspace.transfer.decline.$id');

  /// Stop a transfer from this side.
  static Key cancel(String id) => Key('mkvi.workspace.transfer.cancel.$id');

  /// Clear a settled row.
  static Key dismiss(String id) => Key('mkvi.workspace.transfer.dismiss.$id');
}

/// The Turkish line a row shows under its heading.
///
/// A completed receive's [TransferView.detail] is the destination the sink
/// chose, and the answer here is [WorkspaceTr.saved] — the file's name is
/// already the headline, so the row still says which file finished and nothing
/// says where. Every other phase's detail is a reason the peer or this device
/// chose, or the `transferred / total` pair, both of which are bounded.
String transferDetailLine(TransferView view) => switch (view.phase) {
  TransferPhase.done => WorkspaceTr.saved.tr,
  TransferPhase.failed || TransferPhase.cancelled => view.detailLabel,
  TransferPhase.offered || TransferPhase.active => view.detailLabel,
};

/// How tall one row may be, derived from the type scale rather than written down.
///
/// The terms are the ones a row is actually built from: the headline's line, the
/// capped two-line detail, the bar, the row's own padding, and the hit target an
/// action occupies. A test measures the list against this, so a token change
/// moves both sides of the assertion together.
double transferRowBudget(AppearanceStyle style) {
  final ResolvedTypeStep headline = style.typeStep('sm');
  final ResolvedTypeStep detail = style.typeStep('2xs');
  final double text =
      (headline.size * headline.lineHeight) +
      (detail.size * detail.lineHeight * 2);
  return text + style.gap('4') + (style.gap('3') * 2) + style.hitTargetMin;
}

/// The badge tone for one phase, from the four the token file declares pairs for.
MkviBadgeTone transferToneFor(TransferPhase phase) => switch (phase) {
  TransferPhase.offered => MkviBadgeTone.accent,
  TransferPhase.active => MkviBadgeTone.accent,
  TransferPhase.done => MkviBadgeTone.success,
  TransferPhase.failed => MkviBadgeTone.danger,
  TransferPhase.cancelled => MkviBadgeTone.warning,
};

/// The transfers, oldest first, in a box that cannot grow without bound.
class TransferList extends StatelessWidget {
  /// Creates the list.
  const TransferList({
    super.key,
    required this.transfers,
    this.onAccept,
    this.onDecline,
    this.onCancel,
    this.onDismiss,
    this.maxRows = 2,
  });

  /// The rows to show, oldest first — [TransferCoordinator.views].
  final List<TransferView> transfers;

  /// Accepts an announced offer: [TransferCoordinator.accept].
  final ValueChanged<String>? onAccept;

  /// Declines an announced offer: [TransferCoordinator.decline].
  final ValueChanged<String>? onDecline;

  /// Stops a transfer from this side: [TransferCoordinator.cancel].
  final ValueChanged<String>? onCancel;

  /// Clears a settled row without touching the transfer.
  final ValueChanged<String>? onDismiss;

  /// How many rows the box is tall enough for. The rest scrolls inside it.
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) return const SizedBox.shrink();
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Semantics(
      container: true,
      label: ChatMessages.transferListLabel,
      child: ConstrainedBox(
        // The cap, in the row's own terms. It is a cap and not a height: a
        // short list takes what it needs, and a long one scrolls.
        constraints: BoxConstraints(
          maxHeight: transferRowBudget(style) * maxRows,
        ),
        child: ListView.builder(
          key: TransferListKeys.list,
          shrinkWrap: true,
          padding: EdgeInsets.symmetric(
            horizontal: style.gap('4'),
            vertical: style.gap('2'),
          ),
          itemCount: transfers.length,
          itemBuilder: (BuildContext context, int index) {
            final TransferView view = transfers[index];
            return WorkspaceTransferRow(
              key: TransferListKeys.row(view.id),
              view: view,
              onAccept: onAccept,
              onDecline: onDecline,
              onCancel: onCancel,
              onDismiss: onDismiss,
            );
          },
        ),
      ),
    );
  }
}

/// One transfer, as a box: what it is, how far it has got, and what can be done
/// about it right now.
class WorkspaceTransferRow extends StatelessWidget {
  /// Creates a row for [view].
  const WorkspaceTransferRow({
    super.key,
    required this.view,
    this.onAccept,
    this.onDecline,
    this.onCancel,
    this.onDismiss,
  });

  /// What to show. Every word on this row is one of [TransferView]'s getters.
  final TransferView view;

  /// Accepts the offer.
  final ValueChanged<String>? onAccept;

  /// Declines the offer.
  final ValueChanged<String>? onDecline;

  /// Stops the transfer.
  final ValueChanged<String>? onCancel;

  /// Clears the row.
  final ValueChanged<String>? onDismiss;

  /// Whether this state has a bar: an announced offer and a moving transfer do,
  /// a settled one does not. A bar at 100% under "Tamamlandı" is noise.
  bool get showsProgress =>
      view.phase == TransferPhase.offered || view.phase == TransferPhase.active;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final List<Widget> actions = _actions(style);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: style.gap('2')),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            view.heading,
            key: TransferListKeys.heading(view.id),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.styleOf('sm').copyWith(color: style.role('text')),
          ),
          SizedBox(height: style.gap('2')),
          if (showsProgress) ...<Widget>[
            MkviLinearProgress(
              key: TransferListKeys.progress(view.id),
              // `TransferView.ratio` is already clamped to 0..1 and only ever
              // written by [TransferCoordinator]'s one clamping helper, so the
              // bar cannot walk backwards here.
              value: view.ratio,
              label: view.progressLabel,
            ),
            SizedBox(height: style.gap('2')),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MkviBadge(
                key: TransferListKeys.state(view.id),
                label: view.stateLabel,
                tone: transferToneFor(view.phase),
              ),
              SizedBox(width: style.gap('2')),
              Expanded(
                child: Text(
                  transferDetailLine(view),
                  key: TransferListKeys.detail(view.id),
                  // Two lines and an ellipsis, whatever the text is. This is
                  // the bound that replaces the one the toast did not have.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: style
                      .styleOf('2xs')
                      .copyWith(color: style.role('textMuted')),
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...<Widget>[
            SizedBox(height: style.gap('2')),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: style.gap('2'),
              runSpacing: style.gap('2'),
              children: actions,
            ),
          ],
        ],
      ),
    );
  }

  /// The actions this state offers, and nothing else.
  ///
  /// An incoming offer is the only state with two answers, because it is the
  /// only state where the user is the one being asked. A settled row is only
  /// dismissible — cancelling a finished transfer would tell the peer its file
  /// was cancelled, which is the `cancelFile` bug.
  List<Widget> _actions(AppearanceStyle style) {
    Widget? accept() => onAccept == null
        ? null
        : _action(
            style,
            key: TransferListKeys.accept(view.id),
            label: WorkspaceTr.acceptTransfer.tr,
            icon: Icons.download_rounded,
            onPressed: () => onAccept!(view.id),
            filled: true,
          );
    Widget? decline() => onDecline == null
        ? null
        : _action(
            style,
            key: TransferListKeys.decline(view.id),
            label: WorkspaceTr.declineTransfer.tr,
            icon: Icons.close_rounded,
            onPressed: () => onDecline!(view.id),
            filled: false,
          );
    Widget? cancel() => onCancel == null
        ? null
        : _action(
            style,
            key: TransferListKeys.cancel(view.id),
            label: WorkspaceTr.cancelTransfer.tr,
            icon: Icons.stop_circle_outlined,
            onPressed: () => onCancel!(view.id),
            filled: false,
          );
    Widget? dismiss() => onDismiss == null
        ? null
        : _action(
            style,
            key: TransferListKeys.dismiss(view.id),
            label: WorkspaceTr.dismissTransfer.tr,
            icon: Icons.close_rounded,
            onPressed: () => onDismiss!(view.id),
            filled: false,
            // The one action whose purpose is not obvious from its word alone:
            // "Kapat" on a row means "this row has nothing left to do", and the
            // file's name belongs in the spoken name of that control.
            tooltip: view.dismissLabel,
          );
    return switch (view.phase) {
      TransferPhase.offered
          when view.direction == TransferDirection.receive => <Widget>[
        if (accept() != null) accept()!,
        if (decline() != null) decline()!,
      ],
      // An outgoing offer has no local decision, but it can be withdrawn.
      TransferPhase.offered || TransferPhase.active => <Widget>[
        if (cancel() != null) cancel()!,
      ],
      TransferPhase.done || TransferPhase.failed || TransferPhase.cancelled =>
        <Widget>[if (dismiss() != null) dismiss()!],
    };
  }

  Widget _action(
    AppearanceStyle style, {
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required bool filled,
    String? tooltip,
  }) {
    final Widget button = MkviActionButton(
      key: key,
      action: MkviPanelAction(
        label: label,
        onPressed: onPressed,
        icon: icon,
        filled: filled,
      ),
      // The list stands on the window background, so a filled action here takes
      // no `borderStrong` edge.
      surfaceRole: 'bg',
    );
    return ConstrainedBox(
      // 44 dp, not the theme button's 34: this is the control the reported
      // defect made unhittable.
      constraints: BoxConstraints(
        minWidth: style.hitTargetMin,
        minHeight: style.hitTargetMin,
      ),
      child: tooltip == null ? button : Tooltip(message: tooltip, child: button),
    );
  }
}

