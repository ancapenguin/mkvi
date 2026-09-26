/// One row of the transfer list, as a value.
///
/// Everything the row shows — the headline, the percentage, the state word, the
/// two accessibility labels and the byte pair — is a getter here, so the Turkish
/// text lives in `ChatMessages` and the surface has nothing to spell.
///
/// ## The three states became five
///
/// Three states — active, done, failed — cannot say what happened to a transfer
/// the user cancelled, so a cancel has to render as `failed` with a Turkish
/// reason in the detail line: the same red row as a real failure. `offered` is
/// added for the same reason in the other direction: a transfer the peer
/// announced and the user has not answered yet is neither active nor failed, and
/// rendering it as an active 0% row is how "Alınıyor: 0%" comes to mean both
/// "waiting for you" and "stalled".
library;

import 'package:mkvi/core/protocol/file_transfer.dart';

import 'chat_messages.dart';

/// Where a transfer is, in the order the states are reached.
///
/// `cancelled` and `failed` are both terminal and both dismissible; the surface
/// offers a close button for any state except [active] and [offered] — a live
/// transfer must be cancelled rather than merely hidden, and an unanswered offer
/// must not be dismissible, because closing it would leave the peer waiting for
/// a decision that can no longer be given.
enum TransferPhase {
  /// The peer announced it; nobody has accepted or declined yet.
  offered,

  /// Accepted and moving.
  active,

  /// Every declared byte arrived, or every byte of ours was handed over.
  done,

  /// It ended badly: declined, over the cap, short of its declared size, or the
  /// storage layer refused.
  failed,

  /// Somebody stopped it on purpose, from either side.
  cancelled;

  /// Whether the row can be dismissed without cancelling anything.
  bool get isTerminal => this != active && this != offered;
}

/// A transfer, as the list shows it.
final class TransferView {
  const TransferView({
    required this.id,
    required this.name,
    required this.direction,
    required this.phase,
    required this.transferred,
    required this.total,
    required this.detail,
  });

  final String id;

  /// The sanitised name, from `safeName`, so it can be shown verbatim.
  final String name;

  final TransferDirection direction;
  final TransferPhase phase;

  /// Bytes this device can prove moved: bytes the sink reported written, or
  /// bytes the source reported read. Never a number the peer asserted.
  final int transferred;

  final int total;

  /// The saved path when [phase] is [TransferPhase.done], the Turkish reason
  /// when it failed or was cancelled, `null` while it is still moving.
  final String? detail;

  /// The progress fraction, clamped into `0.0`..`1.0`.
  ///
  /// Clamping is not decoration: [total] can be 0 before an offer is announced
  /// and a sink that stored fewer bytes than declared would otherwise render a
  /// bar past its end or a negative one.
  double get ratio {
    if (total <= 0) return 0;
    final double raw = transferred / total;
    if (raw.isNaN || raw < 0) return 0;
    return raw > 1 ? 1 : raw;
  }

  /// `0`..`100`.
  int get percent => (ratio * 100).round();

  /// The row headline, naming the direction and the file.
  String get heading => ChatMessages.transferHeading(direction, name);

  /// The state word, or a live percentage while the transfer is still moving.
  String get stateLabel => switch (phase) {
    TransferPhase.offered => ChatMessages.awaitingDecision,
    TransferPhase.active => '%$percent',
    TransferPhase.done => ChatMessages.completed,
    TransferPhase.failed => ChatMessages.failed,
    TransferPhase.cancelled => ChatMessages.cancelled,
  };

  /// The `aria-label` of the close button.
  String get dismissLabel => ChatMessages.dismissTransferLabel(name);

  /// The `aria-label` of the progress bar.
  String get progressLabel => ChatMessages.transferProgressLabel(name);

  /// The reason or saved path when there is one, otherwise the `transferred /
  /// total` pair. A moving transfer has no reason, so it falls back to numbers.
  String get detailLabel => detail ?? ChatMessages.bytePair(transferred, total);

  TransferView copyWith({
    String? name,
    TransferPhase? phase,
    int? transferred,
    int? total,
    String? detail,
    bool clearDetail = false,
  }) => TransferView(
    id: id,
    name: name ?? this.name,
    direction: direction,
    phase: phase ?? this.phase,
    transferred: transferred ?? this.transferred,
    total: total ?? this.total,
    detail: clearDetail ? null : (detail ?? this.detail),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferView &&
          other.id == id &&
          other.name == name &&
          other.direction == direction &&
          other.phase == phase &&
          other.transferred == transferred &&
          other.total == total &&
          other.detail == detail;

  @override
  int get hashCode =>
      Object.hash(id, name, direction, phase, transferred, total, detail);

  @override
  String toString() =>
      'TransferView($id ${direction.name} ${phase.name} $transferred/$total)';
}
