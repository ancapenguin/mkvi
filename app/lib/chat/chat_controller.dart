/// The one object the chat surface holds: the conversation, the queue of lines
/// that have not reached the peer, and the handoff to the local log.
///
/// ## The defect this exists for
///
/// A send used to be guarded by the peer being online, in two places at once: the
/// composer disabled its field while the channel was down, and the send path threw
/// if no channel existed. Both guards were aimed at the same failure, and both
/// made the same failure worse — a message written during a reconnect, which is
/// exactly when a user most wants to write one, could not be composed at all. And
/// if the channel dropped between the field being enabled and the keypress
/// landing, the text was simply gone: no queue, no optimistic echo, no retry, one
/// throw and the line was never written down.
///
/// This class inverts that. [send] never fails because the channel is down; it
/// writes the line down first, marks it [MessageDelivery.sending] and holds it.
/// The channel is an output, not a precondition.
library;

import 'dart:async';

import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';
import 'package:mkvi/core/protocol/transfer_id.dart';

import 'chat_channel.dart';
import 'chat_messages.dart';
import 'chat_timeline.dart';
import 'history_store.dart';
import 'timeline_message.dart';

/// A line that has not reached the peer yet, and the reason it has not.
final class QueuedMessage {
  const QueuedMessage({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.delivery,
    required this.reason,
  });

  final String id;
  final String body;
  final DateTime sentAt;
  final MessageDelivery delivery;

  /// Why it is still queued, in Turkish. `null` until an attempt has failed.
  final String? reason;

  QueuedMessage copyWith({MessageDelivery? delivery, String? reason}) =>
      QueuedMessage(
        id: id,
        body: body,
        sentAt: sentAt,
        delivery: delivery ?? this.delivery,
        reason: reason ?? this.reason,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueuedMessage &&
          other.id == id &&
          other.body == body &&
          other.sentAt == sentAt &&
          other.delivery == delivery &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(id, body, sentAt, delivery, reason);

  @override
  String toString() => 'QueuedMessage($id, ${delivery.name}, $reason)';
}

/// The outcome of one [ChatController.send] call.
sealed class SendResult {
  const SendResult();
}

/// The line is in the conversation. [delivered] says whether it is already on
/// the wire or still queued for when the channel returns.
final class MessageQueued extends SendResult {
  const MessageQueued(this.id, {required this.delivered});

  final String id;
  final bool delivered;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageQueued && other.id == id && other.delivered == delivered;

  @override
  int get hashCode => Object.hash(id, delivered);

  @override
  String toString() => 'MessageQueued($id, delivered: $delivered)';
}

/// The line was not written, and [reason] says why.
final class SendRefused extends SendResult {
  const SendRefused(this.reason);

  final String reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SendRefused && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'SendRefused($reason)';
}

/// Everything the surface rebuilds from, as one value.
final class ChatSnapshot {
  ChatSnapshot({
    required this.timeline,
    required List<QueuedMessage> queue,
    required this.channelOpen,
  }) : queue = List<QueuedMessage>.unmodifiable(queue);

  final ChatTimeline timeline;

  /// Oldest first: the order the lines were composed in, which is also the order
  /// they go out in.
  final List<QueuedMessage> queue;

  final bool channelOpen;

  @override
  String toString() =>
      'ChatSnapshot(${timeline.length} lines, ${queue.length} queued, '
      'channel: $channelOpen)';
}

/// Owns the conversation, the in-flight queue and the history handoff.
final class ChatController {
  /// [channel] and [store] are written as initialising formals of the private
  /// fields, so each dependency is bound in exactly one place.
  ChatController({
    required this._channel,
    required this._store,
    String Function()? idFactory,
    this._conversationId = defaultConversationId,
    int window = ChatTimeline.defaultWindow,
    this._maxQueued = defaultMaxQueued,
    this._historyPageSize = defaultHistoryPageSize,
  }) : _window = window,
       _idFactory = idFactory ?? randomTransferId,
       _timeline = ChatTimeline.empty(window: window) {
    // The queue must be able to fit inside the window. If it could not, a burst
    // of offline sends would guarantee that the window evicts a line the user
    // still has to see — a pending line that fell off the oldest end would stay
    // in the queue and still go out, but the surface would have no way to show it
    // or to offer "Yeniden dene". Refusing the misconfiguration is the only way
    // to keep "never loses a pending line" true by construction.
    if (_maxQueued > _window) {
      throw ArgumentError.value(
        _maxQueued,
        'maxQueued',
        'must not exceed window ($_window): a queued line has to stay visible',
      );
    }
    if (_maxQueued < 1) {
      throw ArgumentError.value(_maxQueued, 'maxQueued', 'must be at least 1');
    }
    if (_historyPageSize < 1) {
      throw ArgumentError.value(
        _historyPageSize,
        'historyPageSize',
        'must be at least 1',
      );
    }
  }

  /// The conversation every message belongs to.
  ///
  /// MKVI is a two-person app, so there is exactly one. The column is still named
  /// rather than assumed, so the day a group chat exists does not need a
  /// migration of the stored history.
  static const String defaultConversationId = 'default';

  /// How many lines may be held while the channel is down.
  ///
  /// Not unbounded on purpose. A queue that grows forever is a memory leak with
  /// a progress bar; a bound that *refuses* the newest line with a Turkish
  /// reason keeps the older ones, which is the only way to satisfy "must not lose
  /// a message that failed to send" and "must not grow unboundedly" at once.
  static const int defaultMaxQueued = 200;

  /// How many lines one history page asks for.
  static const int defaultHistoryPageSize = 50;

  final ChatChannelBinding _channel;
  final HistoryStore _store;
  final String _conversationId;
  final int _window;
  final int _maxQueued;
  final int _historyPageSize;
  final String Function() _idFactory;

  ChatTimeline _timeline;
  final List<QueuedMessage> _queue = <QueuedMessage>[];
  final Set<String> _queuedIds = <String>{};
  bool _channelOpen = false;
  bool _flushing = false;
  bool _disposed = false;
  String? _lastStorageFailure;

  final StreamController<ChatSnapshot> _states =
      StreamController<ChatSnapshot>.broadcast();

  /// The conversation, oldest first. Unmodifiable.
  ChatTimeline get timeline => _timeline;

  /// Lines that have not reached the peer, oldest first. Unmodifiable.
  List<QueuedMessage> get queue => List<QueuedMessage>.unmodifiable(_queue);

  int get queuedCount => _queue.length;

  bool get hasQueuedMessages => _queue.isNotEmpty;

  /// Whether the queue is holding lines purely because the channel is down. The
  /// composer's placeholder and the "Yeniden dene" button read from this.
  bool get isHoldingForReconnect => !_channelOpen && _queue.isNotEmpty;

  bool get isChannelOpen => _channelOpen;

  /// Whether the history may still have an older page.
  bool get hasOlderHistory => !_timeline.exhausted;

  /// The conversation id lines are stored under.
  String get conversationId => _conversationId;

  /// The most recent storage failure, in Turkish, or `null`.
  ///
  /// The history is best effort on purpose: a line that is on screen must not
  /// disappear because a disk write failed, so a failure is reported and not
  /// thrown. TS did the same with `setNotice`, but it had no way to *not* notice
  /// — the red banner replaced whatever was on screen.
  String? get lastStorageFailure => _lastStorageFailure;

  /// The rebuild stream. A surface listens to this; it never polls the queue.
  Stream<ChatSnapshot> get states => _states.stream;

  // -----------------------------------------------------------------------
  // Sending
  // -----------------------------------------------------------------------

  /// Writes a line down, then tries to send it.
  ///
  /// The order is the whole point: the line is in [timeline] and in the queue
  /// *before* the channel is touched, so a channel that is down, a channel that
  /// refuses, or a transport that misbehaves cannot lose the text. A refusal
  /// happens only for a line that was never written — blank, over the byte cap,
  /// or the queue at its bound — and each says so in Turkish.
  SendResult send(String body) {
    if (_disposed) return const SendRefused(ChatMessages.sendFailed);
    final String clean = body.trim();
    if (clean.isEmpty) return const SendRefused(ChatMessages.emptyMessage);
    // The cap is measured in UTF-8 bytes because that is what the parser
    // enforces on the way in; a `String.length` check would be a different,
    // looser limit and would let this side build a frame `parseControl` refuses.
    if (utf8ByteLength(clean) > PeerProtocol.maxMessageBytes) {
      return SendRefused(ChatMessages.messageTooLarge());
    }
    if (_queue.length >= _maxQueued) {
      return const SendRefused(ChatMessages.queueFull);
    }

    final String id = _idFactory();
    final TimelineMessage line = TimelineMessage(
      id: id,
      body: clean,
      sentAt: DateTime.now(),
      direction: MessageDirection.outgoing,
      delivery: MessageDelivery.sending,
    );
    _queue.add(
      QueuedMessage(
        id: id,
        body: clean,
        sentAt: line.sentAt,
        delivery: MessageDelivery.sending,
        reason: null,
      ),
    );
    _queuedIds.add(id);
    _timeline = _timeline.add(line, isPinned: _isPinned);
    _flush();
    // Emitted here rather than from `_flush`, so a send into a closed channel —
    // the case that matters most, and the one a channel-gated composer could not
    // represent — still rebuilds the surface. `_flush` emitting would have made
    // this emit nothing.
    _emit();
    return MessageQueued(id, delivered: !_isPinned(line));
  }

  /// Retries every queued line, oldest first.
  ///
  /// Called automatically when the channel reports it is open again; exposed so
  /// a "Yeniden dene" button can drive it while the channel stays up.
  void retryQueued() {
    _flush();
    _emit();
  }

  /// Drops one queued line, for an explicit user discard.
  ///
  /// The *only* way a pending line leaves the queue without having been sent.
  /// There is deliberately no size-based eviction: an eviction is a silent loss
  /// with a worse disguise, which is why the bound refuses the newest line
  /// instead of dropping the oldest.
  bool discardQueued(String id) {
    final int index = _queue.indexWhere((QueuedMessage m) => m.id == id);
    if (index < 0) return false;
    _queue.removeAt(index);
    _queuedIds.remove(id);
    _timeline = _timeline.remove(id);
    _emit();
    return true;
  }

  // -----------------------------------------------------------------------
  // Receiving
  // -----------------------------------------------------------------------

  /// Takes one `chat` frame off the wire.
  ///
  /// Returns `false` when the line is already held, which is the reply for a
  /// frame the peer repeated: the id is the dedupe key, and appending blindly
  /// meant a data channel that redelivered showed the same line twice.
  bool receive(ChatMessage frame) {
    if (_disposed || _timeline.contains(frame.id)) return false;
    final TimelineMessage line = TimelineMessage.fromFrame(frame);
    _timeline = _timeline.add(line, isPinned: _isPinned);
    _persist(line);
    _emit();
    return true;
  }

  /// Marks outgoing lines as read. Incoming lines are ignored: a line the peer
  /// wrote has no read receipt of ours to carry.
  void markRead(Iterable<String> ids) {
    final Set<String> wanted = ids.toSet();
    if (wanted.isEmpty) return;
    ChatTimeline next = _timeline;
    for (final String id in wanted) {
      next = next.update(
        id,
        (TimelineMessage m) => m.direction == MessageDirection.outgoing
            ? m.copyWith(delivery: MessageDelivery.read)
            : m,
      );
    }
    if (identical(next, _timeline)) return;
    _timeline = next;
    _emit();
  }

  /// Marks every outgoing line as read.
  void markAllRead() => markRead(
    _timeline.messages
        .where(
          (TimelineMessage m) =>
              m.direction == MessageDirection.outgoing &&
              m.delivery != MessageDelivery.read,
        )
        .map((TimelineMessage m) => m.id),
  );

  // -----------------------------------------------------------------------
  // Channel
  // -----------------------------------------------------------------------

  /// The reconnect loop reports that the data channel opened or closed.
  ///
  /// A close changes nothing but [isChannelOpen]: the queue, the conversation
  /// and the delivery state of every line survive it, which is the property that
  /// makes a queued message worth having. An open flushes.
  void reportChannelOpen(bool open) {
    if (_disposed) return;
    _channelOpen = open;
    if (open) _flush();
    _emit();
  }
  // -----------------------------------------------------------------------
  // History handoff
  // -----------------------------------------------------------------------

  /// Reads the newest page into an empty conversation.
  ///
  /// Refuses to run on a conversation that already holds lines: this is the
  /// "pairing was just confirmed" handoff, and running it later would splice
  /// stored copies underneath live lines that carry fresher delivery states.
  /// TS ran the read on every `pairingConfirmed`, and `setMessages(stored…)`
  /// *replaced* the whole array — so a pairing re-confirmation mid-conversation
  /// threw away every unsent line on screen.
  Future<bool> loadInitialHistory() async {
    if (_disposed || _timeline.isNotEmpty) return false;
    final HistoryPage page = await _readNewestPage();
    if (_disposed) return false;
    _timeline = ChatTimeline.fromMessages(
      page.messages.map((StoredMessage m) => m.toTimeline()),
      window: _window,
      exhausted: !page.hasMore,
    );
    _emit();
    return true;
  }

  /// Reads the page before the oldest line held.
  ///
  /// Returns `false` once the history is exhausted, which is what stops a
  /// scroll-to-top from paging forever. Overlapping pages are harmless: the
  /// timeline merges by id and keeps whatever it already holds.
  Future<bool> loadOlderHistory() async {
    if (_disposed || _timeline.exhausted) return false;
    final List<TimelineMessage> held = _timeline.messageList;
    final TimelineMessage? oldest = held.isEmpty ? null : held.first;
    final HistoryPage page = oldest == null
        ? await _readNewestPage()
        : await _readOlderPage(oldest);
    if (_disposed) return false;
    _timeline = _timeline.prepend(
      page.messages.map((StoredMessage m) => m.toTimeline()),
      hasMore: page.hasMore,
      isPinned: _isPinned,
    );
    _emit();
    return true;
  }

  Future<HistoryPage> _readNewestPage() async {
    try {
      return await _store.loadNewest(
        conversationId: _conversationId,
        limit: _historyPageSize,
      );
    } on Object {
      _lastStorageFailure = ChatMessages.historyUnavailable;
      return HistoryPage.none;
    }
  }

  Future<HistoryPage> _readOlderPage(TimelineMessage oldest) async {
    try {
      return await _store.loadOlder(
        conversationId: _conversationId,
        beforeMs: oldest.sentAt.millisecondsSinceEpoch,
        beforeId: oldest.id,
        limit: _historyPageSize,
      );
    } on Object {
      _lastStorageFailure = ChatMessages.historyUnavailable;
      return HistoryPage.none;
    }
  }

  // -----------------------------------------------------------------------
  // Plumbing
  // -----------------------------------------------------------------------

  /// Hands queued lines to the channel, oldest first, stopping at the first
  /// refusal.
  ///
  /// Stopping is deliberate. A conversation is ordered, so a queue that flushed
  /// line 3 while line 2 was still held would deliver the peer's replies in an
  /// order neither device agreed on — the one defect a retry loop introduces on
  /// its own.
  void _flush() {
    if (_disposed || _flushing || !_channel.isOpen) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final QueuedMessage head = _queue.first;
        final SendOutcome outcome = _channel.send(
          ChatMessage(
            id: head.id,
            text: head.body,
            sentAt: head.sentAt.millisecondsSinceEpoch,
          ),
        );
        if (outcome is ChannelUnavailable) {
          _markFailed(head.id, outcome.reason);
          break;
        }
        _settle(head.id);
      }
    } finally {
      _flushing = false;
    }
  }

  /// Moves a line to [MessageDelivery.sent], takes it out of the queue and
  /// writes it to the log.
  void _settle(String id) {
    final int index = _queue.indexWhere((QueuedMessage m) => m.id == id);
    if (index < 0) return;
    final QueuedMessage entry = _queue.removeAt(index);
    _queuedIds.remove(id);
    final TimelineMessage? line = _timeline.messageById(id);
    final TimelineMessage settled = (line ?? _asTimeline(entry)).copyWith(
      delivery: MessageDelivery.sent,
    );
    _timeline = _timeline.replace(settled);
    _persist(settled);
  }

  /// Moves a line to [MessageDelivery.failed] and **keeps it queued**.
  ///
  /// Returns whether anything changed, so a flush that retries a line which is
  /// already failed for the same reason does not emit a redundant rebuild.
  bool _markFailed(String id, String reason) {
    final int index = _queue.indexWhere((QueuedMessage m) => m.id == id);
    if (index < 0) return false;
    final QueuedMessage failed = _queue[index].copyWith(
      delivery: MessageDelivery.failed,
      reason: reason,
    );
    if (failed == _queue[index]) return false;
    _queue[index] = failed;
    _timeline = _timeline.update(
      id,
      (TimelineMessage m) => m.copyWith(delivery: MessageDelivery.failed),
    );
    return true;
  }

  /// Whether the window must not evict this line yet.
  bool _isPinned(TimelineMessage message) => _queuedIds.contains(message.id);

  static TimelineMessage _asTimeline(QueuedMessage entry) => TimelineMessage(
    id: entry.id,
    body: entry.body,
    sentAt: entry.sentAt,
    direction: MessageDirection.outgoing,
    delivery: entry.delivery,
  );

  void _persist(TimelineMessage message) {
    unawaited(
      _writeHistory(
        StoredMessage.fromTimeline(
          message.copyWith(delivery: MessageDelivery.sent),
        ),
      ),
    );
  }

  Future<void> _writeHistory(StoredMessage message) async {
    try {
      await _store.append(conversationId: _conversationId, message: message);
      _lastStorageFailure = null;
    } on Object {
      // Deliberately swallowed. The line is already on screen; losing the disk
      // copy costs a message on the next run, while throwing here would take the
      // whole composer down for a write that may well succeed on retry.
      _lastStorageFailure = ChatMessages.messageNotStored;
    }
  }

  void _emit() {
    if (_disposed || _states.isClosed) return;
    _states.add(
      ChatSnapshot(
        timeline: _timeline,
        queue: _queue,
        channelOpen: _channelOpen,
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    _queuedIds.clear();
    await _states.close();
  }
}
