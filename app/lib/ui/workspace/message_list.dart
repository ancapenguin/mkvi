/// The conversation: one row per thing `ChatTimeline.rows` says to draw.
///
/// ## Why this file draws a list and not a message array
///
/// `App.tsx` held `useState<ChatMessage[]>([])` and appended to it, so the
/// surface had no idea which lines belonged to one bubble, where a day changed,
/// or which of its own lines had not left the machine. All three are already
/// decided in `lib/chat`: [ChatTimeline.rows] emits a [DaySeparatorRow] once
/// per midnight crossing and a `startsGroup`/`endsGroup` pair per line, and
/// `MessageDelivery` is the queue's own state rather than anything the UI
/// tracks. So the only decisions left here are visual, and they are the ones a
/// widget can get wrong on its own:
///
/// * **the newest line is at the bottom and the list opens on it** — the list is
///   `reverse`d and its items are handed over newest-first, so no scroll
///   controller, no post-frame jump and no "the message I just sent is off the
///   bottom of the screen";
/// * **a line that has not gone out stays on screen** — a refusal from the
///   channel is a *state* of the line, not a reason to remove it, and the row
///   offers "Yeniden dene" and "Sil" instead;
/// * **the timestamp rides the end of a bubble group**, which is what
///   `endsGroup` is for, and the time comes from the type scale rather than a
///   12 px literal that ignores the user's font size.
///
/// ## The two row classes are not called `MessageRow`
///
/// `lib/chat/timeline_row.dart` owns `MessageRow` — a *derived description* of
/// one line, carrying the message and its group flags. A widget in this package
/// named `MessageRow` would be a second meaning for one name in the same
/// feature, and every import site would need a prefix. So the widgets are
/// `WorkspaceMessageRow` and `WorkspaceDaySeparator`, and the one place they
/// meet (`MessageList.build`) is the switch that makes the two vocabularies
/// line up.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'workspace_strings.dart';

/// The keys the list's parts answer to.
abstract final class MessageListKeys {
  /// The list's own box — present whether it is showing lines or the empty
  /// state, so a layout test can measure the region that a notice shrinks.
  static const Key list = Key('mkvi.workspace.list');

  /// The scrolling viewport. Absent when the conversation is empty.
  static const Key viewport = Key('mkvi.workspace.list.viewport');

  /// One line, as one box.
  static Key row(String id) => Key('mkvi.workspace.row.$id');

  /// The bubble inside a row.
  static Key bubble(String id) => Key('mkvi.workspace.bubble.$id');

  /// The body text of a row.
  static Key body(String id) => Key('mkvi.workspace.body.$id');

  /// The timestamp of a row, on the rows that end a bubble group.
  static Key time(String id) => Key('mkvi.workspace.time.$id');

  /// The delivery word of an outgoing row.
  static Key status(String id) => Key('mkvi.workspace.status.$id');

  /// The Turkish reason a line did not go out.
  static Key reason(String id) => Key('mkvi.workspace.reason.$id');

  /// The retry action on a line that did not go out.
  static Key retry(String id) => Key('mkvi.workspace.retry.$id');

  /// The discard action on a line that did not go out.
  static Key discard(String id) => Key('mkvi.workspace.discard.$id');

  /// A day boundary, keyed by its local midnight, which is the value the
  /// separator is derived from.
  static Key daySeparator(DateTime day) =>
      Key('mkvi.workspace.day.${day.millisecondsSinceEpoch}');
}

/// The Turkish word for one delivery state.
///
/// [MessageDelivery.read] reuses [ChatMessages.readReceipt] rather than spelling
/// "Okundu" again: the receipt is the chat layer's word, the TypeScript original
/// appended it to the meta line itself (`ChatCallWorkspace.tsx:572`), and two
/// copies of one Turkish word in two files is how a Turkish/English split starts.
String workspaceDeliveryLabel(MessageDelivery delivery) => switch (delivery) {
  MessageDelivery.sending => WorkspaceTr.deliverySending.tr,
  MessageDelivery.sent => WorkspaceTr.deliverySent.tr,
  MessageDelivery.read => ChatMessages.readReceipt,
  MessageDelivery.failed => WorkspaceTr.deliveryFailed.tr,
};

/// The conversation, as the rows the surface draws.
class MessageList extends StatelessWidget {
  /// Creates the list.
  const MessageList({
    super.key,
    required this.timeline,
    this.now,
    this.failureReasons = const <String, String>{},
    this.onRetry,
    this.onDiscard,
  });

  /// The window of lines to draw, day separators and group flags included.
  final ChatTimeline timeline;

  /// "Now", for [ChatMessages.dayLabel]'s "Bugün" / "Dün" decision.
  ///
  /// A parameter rather than a `DateTime.now()` inside `build`, because a
  /// value type that captured the clock would have to be rebuilt every midnight
  /// and because a test cannot assert a label that depends on when the suite
  /// ran. `null` reads the wall clock, which is what production wants.
  final DateTime? now;

  /// Why a line is still queued, by line id — [QueuedMessage.reason] lifted out
  /// of the snapshot. The timeline carries the *state*; the reason lives in the
  /// queue, and a row that says "Gönderilemedi" without saying why is the
  /// half-answer the user cannot act on.
  final Map<String, String> failureReasons;

  /// Retries the queue, i.e. [ChatController.retryQueued].
  final VoidCallback? onRetry;

  /// Drops one queued line, i.e. [ChatController.discardQueued].
  final ValueChanged<String>? onDiscard;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final DateTime clock = now ?? DateTime.now();
    // `rows` is derived on every read, so it is read once: a rebuild that asked
    // for it twice would walk the whole conversation twice for one frame.
    final List<TimelineRow> rows = timeline.rows.toList(growable: false);
    final bool empty = rows.isEmpty;
    return Semantics(
      container: true,
      label: ChatMessages.messageLogLabel,
      child: SizedBox(
        key: MessageListKeys.list,
        width: double.infinity,
        child: empty
            ? Center(
                child: MkviEmptyState(
                  title: ChatMessages.emptyChatTitle,
                  description: ChatMessages.emptyChatBody,
                  icon: Icons.forum_outlined,
                  surfaceRole: 'bg',
                ),
              )
            : _viewport(style, rows, clock),
      ),
    );
  }

  Widget _viewport(
    AppearanceStyle style,
    List<TimelineRow> rows,
    DateTime clock,
  ) {
    return ListView.builder(
      key: MessageListKeys.viewport,
      // The newest line is the last one, and `reverse` puts item 0 at the
      // bottom, so the items are handed over newest-first and the list opens
      // showing the newest line. The visual order is still oldest-first from
      // the top, which is what a reader expects going up into the history.
      reverse: true,
      padding: EdgeInsets.symmetric(vertical: style.gap('2')),
      itemCount: rows.length,
      itemBuilder: (BuildContext context, int index) {
        // Reversed for [reverse] only; `index` is the position in the array the
        // builder is handed, not a position on screen.
        final TimelineRow row = rows[rows.length - 1 - index];
        return switch (row) {
          DaySeparatorRow(:final DateTime day) => WorkspaceDaySeparator(
            key: MessageListKeys.daySeparator(day),
            day: day,
            now: clock,
          ),
          MessageRow(
            :final TimelineMessage message,
            :final bool startsGroup,
            :final bool endsGroup,
          ) => WorkspaceMessageRow(
            message: message,
            startsGroup: startsGroup,
            endsGroup: endsGroup,
            failureReason: failureReasons[message.id],
            onRetry: onRetry,
            onDiscard: onDiscard,
          ),
        };
      },
    );
  }
}

/// One day boundary: the Turkish label from [ChatMessages.dayLabel], between two
/// hairlines so it reads as a break rather than as a message.
class WorkspaceDaySeparator extends StatelessWidget {
  /// Creates a separator for [day].
  const WorkspaceDaySeparator({
    super.key,
    required this.day,
    required this.now,
  });

  /// Local midnight of the day the following lines belong to.
  final DateTime day;

  /// "Now", so the label can be "Bugün" or "Dün" instead of a date.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: style.gap('3')),
      child: Row(
        children: <Widget>[
          const Expanded(child: MkviDivider()),
          SizedBox(width: style.gap('3')),
          Text(
            ChatMessages.dayLabel(day: day, now: now),
            style: style
                .styleOf('2xs')
                .copyWith(color: style.role('textMuted')),
          ),
          SizedBox(width: style.gap('3')),
          const Expanded(child: MkviDivider()),
        ],
      ),
    );
  }
}

/// One line of the conversation, as a bubble with its meta line and — when it
/// has not gone out — the two actions that resolve that.
class WorkspaceMessageRow extends StatelessWidget {
  /// Creates a row for [message].
  const WorkspaceMessageRow({
    super.key,
    required this.message,
    required this.startsGroup,
    required this.endsGroup,
    this.failureReason,
    this.onRetry,
    this.onDiscard,
  });

  /// The line to draw.
  final TimelineMessage message;

  /// Whether this line draws its own top corner and the gap above it.
  final bool startsGroup;

  /// Whether this line draws its own bottom corner and the timestamp.
  final bool endsGroup;

  /// The Turkish reason it did not go out, or `null`.
  final String? failureReason;

  /// Retries the queue. Offered only on a line that is still queued.
  final VoidCallback? onRetry;

  /// Drops this line, i.e. `discardQueued(message.id)`.
  final ValueChanged<String>? onDiscard;

  /// The role this bubble is filled with: the note this device made, and the
  /// line the peer sent, must be told apart at a glance.
  String get fillRole =>
      message.direction == MessageDirection.outgoing ? 'accentSoft' : 'surfaceRaised';

  /// Whether this line is still waiting for the channel.
  bool get isPending => message.isPending;

  /// Whether this line failed, which is the only state that offers the actions.
  bool get isFailed => message.delivery == MessageDelivery.failed;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Padding(
      key: MessageListKeys.row(message.id),
      padding: EdgeInsetsDirectional.only(
        top: startsGroup ? style.gap('3') : style.gap('1'),
        // The insets are what make the direction readable before the colours
        // are: an outgoing line hugs the right, an incoming line hugs the left.
        start: message.direction == MessageDirection.outgoing
            ? style.gap('10')
            : 0.0,
        end: message.direction == MessageDirection.outgoing
            ? 0.0
            : style.gap('10'),
      ),
      child: Row(
        mainAxisAlignment: message.direction == MessageDirection.outgoing
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: <Widget>[
          // `Flexible`, so a 32 KB line wraps inside the row instead of
          // overflowing it: the cap is [PeerProtocol.maxMessageBytes] and a
          // composer is allowed to write one.
          Flexible(child: _bubble(style)),
        ],
      ),
    );
  }

  Widget _bubble(AppearanceStyle style) {
    final double radius = style.radius('lg');
    final bool failed = isFailed;
    return DecoratedBox(
      key: MessageListKeys.bubble(message.id),
      decoration: BoxDecoration(
        color: style.role(fillRole),
        // The group flags, used as radii: a line that continues a bubble keeps
        // the joined corners square, and no `dart:math` is needed to work out
        // which corners those are.
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(startsGroup ? radius : 0),
          topRight: Radius.circular(startsGroup ? radius : 0),
          bottomLeft: Radius.circular(endsGroup ? radius : 0),
          bottomRight: Radius.circular(endsGroup ? radius : 0),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: style.gap('3'),
          vertical: style.gap('2'),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              message.body,
              key: MessageListKeys.body(message.id),
              style: style.styleOf('md').copyWith(color: style.role('text')),
            ),
            if (failed && failureReason != null) ...<Widget>[
              SizedBox(height: style.gap('1')),
              Text(
                failureReason!,
                key: MessageListKeys.reason(message.id),
                style: style
                    .styleOf('2xs')
                    .copyWith(color: style.role('danger')),
              ),
            ],
            // The timestamp rides the end of a bubble, which is the whole
            // reason `ChatTimeline.rows` computes `endsGroup`.
            if (endsGroup) ...<Widget>[
              SizedBox(height: style.gap('1')),
              _meta(style),
            ],
            if (failed && (onRetry != null || onDiscard != null))
              ...<Widget>[
                SizedBox(height: style.gap('2')),
                _actions(style),
              ],
          ],
        ),
      ),
    );
  }

  /// The time, and — for a line this device wrote — what happened to it.
  Widget _meta(AppearanceStyle style) {
    final bool outgoing = message.direction == MessageDirection.outgoing;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          ChatMessages.messageTime(message.sentAt),
          key: MessageListKeys.time(message.id),
          style: style.styleOf('2xs').copyWith(color: style.role('textMuted')),
        ),
        if (outgoing) ...<Widget>[
          SizedBox(width: style.gap('2')),
          Text(
            workspaceDeliveryLabel(message.delivery),
            key: MessageListKeys.status(message.id),
            style: style.styleOf('2xs').copyWith(
              color: isFailed ? style.role('danger') : style.role('textMuted'),
            ),
          ),
        ],
      ],
    );
  }

  /// "Yeniden dene" and "Sil", and nothing else.
  ///
  /// A line that failed is the one line in this app the user can do something
  /// *about*, so it is the one line with two buttons on it. Both are asked for
  /// by the caller and both are drawn at the token hit target rather than at the
  /// 34 dp `md` control the theme's buttons measure.
  Widget _actions(AppearanceStyle style) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: style.gap('2'),
      runSpacing: style.gap('2'),
      children: <Widget>[
        if (onRetry != null)
          _action(
            style,
            key: MessageListKeys.retry(message.id),
            label: ChatMessages.retry,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
            filled: true,
          ),
        if (onDiscard != null)
          _action(
            style,
            key: MessageListKeys.discard(message.id),
            label: WorkspaceTr.discard.tr,
            icon: Icons.delete_outline_rounded,
            onPressed: () => onDiscard!(message.id),
            filled: false,
            // "Sil" out of context is a button that could delete anything. The
            // tooltip is what a screen reader reads as the control's purpose,
            // and this is the one place a word that short needed a sentence
            // behind it.
            tooltip: WorkspaceTr.discardLabel.tr,
          ),
      ],
    );
  }

  Widget _action(
    AppearanceStyle style, {
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
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
      // The bubble's own role, so the filled retry takes the `borderStrong`
      // edge `mkviFilledActionNeedsEdge` demands on anything that is not
      // `bg` or `surface`.
      surfaceRole: fillRole,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: style.hitTargetMin,
        minHeight: style.hitTargetMin,
      ),
      child: tooltip == null ? button : Tooltip(message: tooltip, child: button),
    );
  }
}
