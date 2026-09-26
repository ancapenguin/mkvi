/// The local conversation log, behind an interface.
///
/// The Rust core owns the encrypted SQLite file; it does not exist yet, so
/// nothing in this layer touches `dart:io` or calls a bridge. What the layer
/// *does* fix is the contract, because the old contract is what let the UI lose
/// history:
///
/// * `App.tsx` read the newest page with `listLocalHistory()` and then called
///   `.reverse()` on the whole result. The order of the conversation therefore
///   depended on the store returning a newest-first array, which is not
///   something the type said. Here every page is **oldest-first** and the
///   reversal is a property of the type, not of an array method someone has to
///   remember.
/// * There was no "is there anything older?" answer, so a scroll-to-top could
///   not know when to stop. [HistoryPage.hasMore] is that answer, and it is the
///   only thing that can ever set `ChatTimeline.exhausted`.
///
/// Nothing in this file is unbounded: [HistoryStore.retentionLimit] bounds what a
/// production implementation is expected to keep, and every page is bounded by
/// the caller's `limit`.
library;

import 'timeline_message.dart';

/// One stored line.
///
/// Separate from the rendered `TimelineMessage` on purpose: the disk shape has
/// to survive a redesign of the surface, and the surface has to survive a schema
/// migration. The two share an id, which is the join.
final class StoredMessage {
  const StoredMessage({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.direction,
    required this.delivery,
  });

  final String id;
  final String body;
  final DateTime sentAt;
  final MessageDirection direction;

  /// The delivery state as it was when the line was written, so a line persisted
  /// while it was still pending is not resurrected as sent.
  final MessageDelivery delivery;

  /// The two `sender_device_id` values the encrypted history table stores.
  String get senderDeviceId =>
      direction == MessageDirection.outgoing ? 'local' : 'peer';

  /// The persisted `sent_at_ms`.
  int get sentAtMs => sentAt.millisecondsSinceEpoch;

  /// The rendered line for this stored line.
  TimelineMessage toTimeline() => TimelineMessage(
    id: id,
    body: body,
    sentAt: sentAt,
    direction: direction,
    delivery: delivery,
  );

  /// The stored form of a rendered line.
  factory StoredMessage.fromTimeline(TimelineMessage message) => StoredMessage(
    id: message.id,
    body: message.body,
    sentAt: message.sentAt,
    direction: message.direction,
    delivery: message.delivery,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredMessage &&
          other.id == id &&
          other.body == body &&
          other.sentAt == sentAt &&
          other.direction == direction &&
          other.delivery == delivery;

  @override
  int get hashCode => Object.hash(id, body, sentAt, direction, delivery);

  @override
  String toString() => 'StoredMessage($id, $senderDeviceId, $sentAtMs)';
}

/// One page of the log, **oldest line first**.
///
/// The order is part of the contract, not a convention. It is the whole reason
/// `ChatController` can concatenate two pages without reversing either.
final class HistoryPage {
  HistoryPage({required List<StoredMessage> messages, required this.hasMore})
    : messages = List<StoredMessage>.unmodifiable(messages);

  /// An empty page that says there is nothing older.
  static final HistoryPage none = HistoryPage(
    messages: const <StoredMessage>[],
    hasMore: false,
  );

  /// The lines, oldest first.
  final List<StoredMessage> messages;

  /// Whether anything exists strictly before the first line of this page.
  final bool hasMore;

  int get length => messages.length;

  bool get isEmpty => messages.isEmpty;

  @override
  String toString() => 'HistoryPage(${messages.length}, hasMore: $hasMore)';
}

/// The local conversation log.
///
/// Implementations must return each page **oldest-first** and must treat
/// [HistoryPage.hasMore] as an answer they are allowed to compute from a count
/// rather than from a sentinel row.
abstract interface class HistoryStore {
  /// The newest [limit] lines of [conversationId], oldest-first.
  Future<HistoryPage> loadNewest({
    required String conversationId,
    required int limit,
  });

  /// The [limit] lines immediately before the line at ([beforeMs], [beforeId]),
  /// oldest-first.
  ///
  /// A caller that pages has already read the newest page and passes the oldest
  /// line it holds; a caller that has not passes the newest page's oldest line
  /// too, and an implementation must then answer identically to [loadNewest].
  Future<HistoryPage> loadOlder({
    required String conversationId,
    required int beforeMs,
    required String beforeId,
    required int limit,
  });

  /// Appends one line. Appending an id that is already stored must be a no-op,
  /// not an error and not a second row: a retried send and a re-read of the
  /// timeline both land here.
  Future<void> append({
    required String conversationId,
    required StoredMessage message,
  });

  /// Trims [conversationId] to its newest [keep] lines.
  ///
  /// The layer is bounded in memory; the log on disk has to be bounded too, or
  /// "in-memory window" only moves the problem to the next run.
  Future<void> trimTo({required String conversationId, required int keep});

  /// How many lines a production implementation keeps per conversation.
  ///
  /// A default, not a command: an implementation may keep fewer but must not
  /// keep more, and [trimTo] is how it is told to.
  static const int retentionLimit = 5000;
}
