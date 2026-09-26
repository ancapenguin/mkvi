/// One line of the conversation, as this device sees it.
///
/// Named `TimelineMessage` and not `ChatMessage` on purpose: the protocol
/// package already owns `ChatMessage` for the `chat` control frame, and a layer
/// that has two types of the same name is a layer where the wire shape and the
/// rendered shape get confused. The one that travels is
/// `package:mkvi/core/protocol/control_message.dart`'s; the one that is
/// displayed is this.
library;

import 'package:mkvi/core/protocol/control_message.dart';

/// Which device wrote a line. Two devices, so this doubles as the grouping key:
/// consecutive lines from the same [MessageDirection] belong to one bubble.
enum MessageDirection { incoming, outgoing }

/// How far a line has got on its way to the peer.
///
/// The optimistic echo in `ChatController.send` creates a line that already
/// exists in the timeline but has not left the machine; [sending] is that state,
/// [failed] is what it becomes when the channel refuses it, and it stays
/// [failed] — in the queue, not lost — until a retry succeeds.
enum MessageDelivery { sending, sent, read, failed }

/// An immutable, ordered conversation line.
///
/// [id] is the transfer id the two devices agree on: the sender mints it with
/// `randomTransferId()` and puts it in the `chat` frame, and the receiver reads
/// it out of the same frame. That is what lets the optimistic echo and the
/// message that eventually comes back be the same entry rather than a duplicate,
/// and it is why [id] is a bare 32 character hex string.
final class TimelineMessage {
  const TimelineMessage({
    required this.id,
    required this.body,
    required this.sentAt,
    required this.direction,
    required this.delivery,
  });

  /// Builds the timeline line for an incoming `chat` frame.
  ///
  /// A received line is [MessageDelivery.sent] on arrival: it is on the disk of
  /// this device and on its way to the other screen, which is the only sense in
  /// which a received message has a delivery state at all.
  factory TimelineMessage.fromFrame(ChatMessage frame) => TimelineMessage(
    id: frame.id,
    body: frame.text,
    sentAt: DateTime.fromMillisecondsSinceEpoch(frame.sentAt),
    direction: MessageDirection.incoming,
    delivery: MessageDelivery.sent,
  );

  /// Bare 32 character lowercase hex, from `randomTransferId()` or a parsed
  /// frame. Stable for the life of the line, which is the whole point.
  final String id;

  final String body;

  /// Local wall-clock time. Ordering uses the instant; day separators use the
  /// local calendar day, because "Dün" means a local day, not a UTC one.
  final DateTime sentAt;

  final MessageDirection direction;

  final MessageDelivery delivery;

  /// Whether this line still has to be handed to the peer.
  bool get isPending =>
      delivery == MessageDelivery.sending || delivery == MessageDelivery.failed;

  TimelineMessage copyWith({
    String? body,
    DateTime? sentAt,
    MessageDirection? direction,
    MessageDelivery? delivery,
  }) => TimelineMessage(
    id: id,
    body: body ?? this.body,
    sentAt: sentAt ?? this.sentAt,
    direction: direction ?? this.direction,
    delivery: delivery ?? this.delivery,
  );

  /// The total order of the timeline: instant first, then id.
  ///
  /// The id tiebreak is not cosmetic. Two devices send with their own clocks, so
  /// a peer whose clock lags produces a line whose `sentAt` is *earlier* than one
  /// already on screen; without a tiebreak a `<=` comparison would let that line
  /// land on either side of its equal-timestamped neighbour depending on arrival
  /// order, and the timeline would visibly reshuffle when the user scrolled back.
  static int compare(TimelineMessage a, TimelineMessage b) {
    final int byInstant = a.sentAt.compareTo(b.sentAt);
    if (byInstant != 0) return byInstant;
    return a.id.compareTo(b.id);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineMessage &&
          other.id == id &&
          other.body == body &&
          other.sentAt == sentAt &&
          other.direction == direction &&
          other.delivery == delivery;

  @override
  int get hashCode => Object.hash(id, body, sentAt, direction, delivery);

  @override
  String toString() =>
      'TimelineMessage($id ${direction.name} ${delivery.name} @$sentAt)';
}
