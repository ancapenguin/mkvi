/// The workspace screen: the two halves of `ROADMAP.md` Faz 6 in one window.
///
/// ```text
/// ┌──────────────────────────────────────────┐
/// │ WorkspaceHeader                          │  two names + the status strip
/// ├──────────────────────────────────────────┤
/// │ TransferList            (bounded)        │  when there is a transfer
/// │ MessageList             (Expanded)       │  ← this is what shrinks
/// │ WorkspaceHistory                         │
/// │ NoticeHost              (in flow)        │  zero tall, or the notice
/// │ MessageComposer                          │  can never be covered
/// └──────────────────────────────────────────┘
/// ```
///
/// ## The placement of [NoticeHost] is the fix for defect 8
///
/// The reported bug was not a colour and not a string: it was
/// `position: fixed; z-index: 100; bottom: 18px; right: 18px` in
/// `src/App.css:168-172`, which put the toast **on top of the send button** on
/// two machines that reported they could no longer type anything. `NoticeHost`
/// is an in-flow `Column` child, so it cannot overlap anything — but only if it
/// is *placed* in the flow, and the only place it can be placed without
/// covering the composer is between the list and the composer. That is what
/// this widget does, and `test/ui/workspace/workspace_screen_test.dart` measures
/// the two rects and fails if they ever touch, plus the list's own bottom edge
/// before and after a notice arrives.
///
/// Putting the lane anywhere else restores the bug without any widget being able
/// to detect it, so the placement is written here as well as tested.
///
/// ## Nothing polls
///
/// The conversation comes from [ChatController.states] and the transfers from
/// [TransferCoordinator.changes]; both are broadcast streams this screen
/// subscribes to in `initState` and releases in `dispose`. There is no timer, no
/// `AnimatedBuilder` clock and no repeated read, so `pumpAndSettle` in the test
/// harness returns and every `expectNoOverflow` after it means something.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/session/names.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/notice/notice.dart';

import 'message_composer.dart';
import 'message_list.dart';
import 'transfer_list.dart';
import 'workspace_header.dart';
import 'workspace_history.dart';
import 'workspace_strings.dart';

/// The keys the screen's own regions answer to.
abstract final class WorkspaceScreenKeys {
  /// The screen's column, as one box.
  static const Key screen = Key('mkvi.workspace.screen');

  /// The column that holds the conversation, the lane and the composer — i.e.
  /// the part of the tree the defect-8 measurement is about.
  static const Key conversation = Key('mkvi.workspace.screen.conversation');

  /// The "forget this device" confirmation dialog.
  static const Key forgetConfirm = Key('mkvi.workspace.screen.forget.dialog');

  /// Its "go ahead" button. Distinct from the dialog key because a test has to
  /// press the button, not merely observe the dialog.
  static const Key forgetConfirmButton = Key(
    'mkvi.workspace.screen.forget.confirm',
  );

  /// Its "never mind" button.
  static const Key forgetCancel = Key('mkvi.workspace.screen.forget.cancel');
}

/// The notice layer's palette, out of the resolved style.
///
/// The one bridge in the app between `design/tokens.json` and
/// [NoticePalette], and it lives here because the workspace is the first screen
/// that renders a notice. Every field names the role it comes from, so a colour
/// cannot be invented on the way: `app/lib/` still contains no colour literal
/// and no other screen has to write this function.
NoticePalette workspaceNoticePalette(AppearanceStyle style) => NoticePalette(
  surface: style.role('surfaceOverlay'),
  onSurface: style.role('text'),
  muted: style.role('textMuted'),
  border: style.role('border'),
  accent: style.role('accent'),
  success: style.role('success'),
  warning: style.role('warning'),
  danger: style.role('danger'),
  focusRing: style.role('focusRing'),
  shadow: style.role('shadow3'),
);

/// The notice layer's measurements, out of the resolved style.
///
/// Every default [NoticeMetrics] declares is a density-1.0 number, so a screen
/// that passes none of them would draw a notice whose type does not follow the
/// user's font size — which is the defect `ROADMAP.md` kusur 4 is about. The
/// two fields left at their defaults are the notice's maximum width and its
/// shadow blur: neither is typography, and both are caps rather than sizes.
NoticeMetrics workspaceNoticeMetrics(AppearanceStyle style) => NoticeMetrics(
  bodyFontSize: style.typeStep('sm').size,
  bodyLineHeight: style.typeStep('sm').lineHeight,
  closeTarget: style.hitTargetMin,
  closeIconSize: style.control('md').iconSize,
  focusRingWidth: style.focusRingWidth,
  severityIconSize: style.control('md').iconSize,
  stripeWidth: style.gap('1'),
  stripeGap: style.gap('3'),
  contentGap: style.gap('2'),
  paddingX: style.gap('3'),
  paddingY: style.gap('3'),
  laneGapX: style.gap('4'),
  laneGapY: style.gap('2'),
  cornerRadius: style.radius('lg'),
  statusIconSize: style.control('sm').iconSize,
  statusDotSize: style.gap('2'),
  borderWidth: style.borderWidth,
);

/// The chat and file-transfer workspace.
///
/// Everything it renders comes from the two layers below it, and it holds no
/// state of its own except the one thing neither layer can own: whether a page
/// of history is on its way, and which settled transfer rows the user has
/// cleared.
class WorkspaceScreen extends StatefulWidget {
  /// Creates the screen.
  const WorkspaceScreen({
    super.key,
    required this.controller,
    required this.notice,
    required this.peer,
    this.transfers,
    this.onForgetPeer,
    this.onRemoveAlias,
    this.now,
    this.transferMaxRows = 2,
  });

  /// The conversation, the queue and the history handoff.
  final ChatController controller;

  /// The notice and status channels. The screen writes **only** to the notice
  /// channel, and only to say that a send was refused — a connection state goes
  /// through `setStatus`, which has no path to a notice.
  final NoticeController notice;

  /// Who the peer is, already resolved. Two names, two slots, and the screen
  /// never compares them.
  final PeerNameView peer;

  /// The transfers, or `null` for a screen that is only a conversation.
  final TransferCoordinator? transfers;

  /// Forgets the pairing. `null` hides the action.
  final VoidCallback? onForgetPeer;

  /// Removes this device's note about the peer. `null` hides the action.
  final VoidCallback? onRemoveAlias;

  /// "Now", for the day separator's "Bugün" / "Dün" decision. `null` reads the
  /// wall clock.
  final DateTime? now;

  /// How many transfer rows the box is tall enough for.
  final int transferMaxRows;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  ChatSnapshot? _snapshot;
  List<TransferView> _transfers = const <TransferView>[];

  /// Transfer rows the user has cleared. A view decision: a settled row has
  /// nothing left to do, and [TransferCoordinator] keeps its own bound as the
  /// only thing that may *forget* a transfer. A cleared row cannot come back,
  /// because a transfer id is minted once.
  final Set<String> _cleared = <String>{};

  bool _loadingHistory = false;
  StreamSubscription<ChatSnapshot>? _chat;
  StreamSubscription<TransferView>? _transfersChanged;

  @override
  void initState() {
    super.initState();
    // Seeded from the controller's own getters rather than left null, so the
    // first frame is a conversation and not an empty state that a frame later
    // contradicts.
    _snapshot = ChatSnapshot(
      timeline: widget.controller.timeline,
      queue: widget.controller.queue,
      channelOpen: widget.controller.isChannelOpen,
    );
    _transfers = widget.transfers?.views ?? const <TransferView>[];
    _chat = widget.controller.states.listen(_onChatState);
    final TransferCoordinator? transfers = widget.transfers;
    if (transfers != null) {
      _transfersChanged = transfers.changes.listen(_onTransferChanged);
    }
  }

  @override
  void dispose() {
    unawaited(_chat?.cancel());
    unawaited(_transfersChanged?.cancel());
    super.dispose();
  }

  /// Asks before forgetting, because forgetting cannot be undone.
  ///
  /// [WorkspaceScreen.onForgetPeer] deletes the peer's key from this device.
  /// After that the two devices are strangers again and the user has to walk
  /// through pairing once more — with the *other* machine, on a keyboard, while
  /// both are on screen. That is a large enough cost that a single mis-tap on a
  /// small button is not an acceptable way to pay it.
  ///
  /// The confirmation therefore lives **here** and not in the shell: the shell
  /// would have to be right about it, and the shell is the piece with no tests
  /// behind it. Two buttons, and the destructive one visually the odd one out.
  Future<void> _confirmForgetPeer() async {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: WorkspaceScreenKeys.forgetConfirm,
        title: Text(WorkspaceTr.forgetTitle.tr),
        content: Text(WorkspaceTr.forgetBody.tr),
        actions: <Widget>[
          TextButton(
            key: WorkspaceScreenKeys.forgetCancel,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(WorkspaceTr.forgetCancel.tr),
          ),
          FilledButton(
            key: WorkspaceScreenKeys.forgetConfirmButton,
            style: FilledButton.styleFrom(
              backgroundColor: style.role('dangerFill'),
              foregroundColor: style.role('textOnAccent'),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(WorkspaceTr.forgetConfirm.tr),
          ),
        ],
      ),
    );
    if (confirmed ?? false) widget.onForgetPeer?.call();
  }

  void _onChatState(ChatSnapshot snapshot) {
    if (mounted) setState(() => _snapshot = snapshot);
  }

  void _onTransferChanged(TransferView _) {
    // The whole visible list is re-read rather than patched: the coordinator
    // owns the order and the bound, and a screen that kept its own copy of the
    // list would be a second source of truth for both.
    if (!mounted) return;
    setState(() => _transfers = widget.transfers?.views ?? const <TransferView>[]);
  }

  /// The rows the list shows: everything the coordinator holds that the user has
  /// not cleared.
  List<TransferView> get _visibleTransfers => _transfers
      .where((TransferView view) => !_cleared.contains(view.id))
      .toList(growable: false);

  /// Why each queued line is still queued, by id.
  Map<String, String> get _failureReasons {
    final List<QueuedMessage> queue = _snapshot?.queue ?? const <QueuedMessage>[];
    return <String, String>{
      for (final QueuedMessage entry in queue)
        if (entry.reason != null) entry.id: entry.reason!,
    };
  }

  // -----------------------------------------------------------------------
  // Actions
  // -----------------------------------------------------------------------

  /// Writes the line down, or says why it was not written.
  ///
  /// A closed channel is **not** a refusal: `ChatController.send` holds the line
  /// in its queue in that case, which is the whole point of the queue and the
  /// reason the composer's field is never disabled by the peer's state. A
  /// refusal is a line that was never written — blank, over the byte cap, or
  /// the queue at its bound — and each of those has a Turkish sentence, which
  /// goes to the notice lane as a warning while the composer's text stays where
  /// it was typed.
  bool _send(String body) {
    final SendResult result = widget.controller.send(body);
    if (result is SendRefused) {
      widget.notice.showText(result.reason, kind: NoticeKind.warning);
      return false;
    }
    return true;
  }

  Future<void> _loadOlder() async {
    if (_loadingHistory) return;
    setState(() => _loadingHistory = true);
    try {
      final String? before = widget.controller.lastStorageFailure;
      await widget.controller.loadOlderHistory();
      // A read that fails is not the same answer as a read that found nothing:
      // the store is unreachable, and `ChatController` reports that as a
      // Turkish string of its own rather than as a page. Showing it is the whole
      // difference between "there is nothing older" and "we could not look", and
      // the one before it — a failure from an earlier read — is left alone.
      final String? failure = widget.controller.lastStorageFailure;
      if (failure != null && failure != before) {
        widget.notice.showText(failure, kind: NoticeKind.warning);
      }
    } finally {
      // `finally`, not the happy path: a read that throws still has to take the
      // button out of its loading state, or the control is stuck for ever and
      // the second press does nothing.
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _accept(String id) => unawaited(widget.transfers!.accept(id));

  void _decline(String id) => widget.transfers!.decline(id);

  void _cancel(String id) => widget.transfers!.cancel(id);

  void _clearRow(String id) => setState(() => _cleared.add(id));

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final ChatSnapshot snapshot =
        _snapshot ??
        ChatSnapshot(
          timeline: widget.controller.timeline,
          queue: widget.controller.queue,
          channelOpen: widget.controller.isChannelOpen,
        );
    final List<TransferView> transfers = _visibleTransfers;
    final NoticePalette palette = workspaceNoticePalette(style);
    final NoticeMetrics metrics = workspaceNoticeMetrics(style);

    return Semantics(
      container: true,
      label: WorkspaceTr.workspace.tr,
      child: Material(
        // Transparent, and here so that every control below has the `Material`
        // ancestor its ink needs. The fill is the window background, which is
        // the `bg` role every control in the conversation is measured against.
        type: MaterialType.transparency,
        child: ColoredBox(
          color: style.role('bg'),
          child: Column(
            key: WorkspaceScreenKeys.screen,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              WorkspaceHeader(
                peer: widget.peer,
                notice: widget.notice,
                palette: palette,
                metrics: metrics,
                onRemoveAlias: widget.onRemoveAlias,
                // The header cannot ask, so it fires and the screen asks. See
                // [_confirmForgetPeer] for why the confirmation is here and not
                // in the shell.
                onForgetPeer: widget.onForgetPeer == null
                    ? null
                    : _confirmForgetPeer,
              ),
              Expanded(
                child: Column(
                  key: WorkspaceScreenKeys.conversation,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (transfers.isNotEmpty)
                      // `Flexible`, and not a fixed-height child: the file lane
                      // and the conversation share whatever the window has left
                      // after the header, the history, the notice lane and the
                      // composer. A lane that demanded its two rows before the
                      // conversation had any would push the conversation off the
                      // bottom of a 400x720 window, which is a vertical overflow
                      // — the defect class this whole directory is measured
                      // against. The lane's own cap still applies inside the
                      // share it is given.
                      Flexible(
                        flex: 1,
                        child: TransferList(
                          transfers: transfers,
                          onAccept: _accept,
                          onDecline: _decline,
                          onCancel: _cancel,
                          onDismiss: _clearRow,
                          maxRows: widget.transferMaxRows,
                        ),
                      ),
                    // The only expanded child, so it is the only thing a notice
                    // can take space from — and the larger share of what is left,
                    // because a conversation is the reason the window is open.
                    Expanded(
                      flex: 2,
                      child: MessageList(
                        timeline: snapshot.timeline,
                        now: widget.now,
                        failureReasons: _failureReasons,
                        // Both are always offered and the row decides whether
                        // to draw them: only a line that failed gets the two
                        // buttons, and `retryQueued` against a closed channel
                        // is a flush that moves nothing rather than an error.
                        onRetry: widget.controller.retryQueued,
                        onDiscard: widget.controller.discardQueued,
                      ),
                    ),
                    WorkspaceHistory(
                      hasMore: widget.controller.hasOlderHistory,
                      loading: _loadingHistory,
                      onLoadMore: _loadOlder,
                      lineCount: snapshot.timeline.length,
                    ),
                    // In flow, between the list and the composer, with nothing
                    // expanded around it. This line is defect 8's fix.
                    NoticeHost(
                      controller: widget.notice,
                      palette: palette,
                      metrics: metrics,
                    ),
                    MessageComposer(
                      onSend: _send,
                      channelOpen: snapshot.channelOpen,
                      queuedCount: snapshot.queue.length,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
