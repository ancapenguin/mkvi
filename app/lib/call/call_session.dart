import 'package:mkvi/core/protocol/control_message.dart';

import 'call_status.dart';

/// One call, as an immutable value.
///
/// The call used to *be* three collections — one for the caller, one for the
/// callee, one for the accepted call — which is why "which side am I?" could
/// only be answered by asking which collection holds the id, and why the
/// caller's 45 s timeout and the callee's ring timeout could not share one code
/// path. One value with a [CallSide] is what lets both timers be the same shape
/// and still mean different things.
///
/// Every field is `final`; the machine replaces the whole value on each
/// transition, so a session can be handed to the UI and stay valid for as long as
/// the UI likes.
final class CallSession {
  const CallSession({
    required this.id,
    required this.mode,
    required this.side,
    required this.status,
    required this.startedAt,
    this.offeredAt,
    this.acceptedAt,
    this.upgradedAt,
    this.connectedAt,
    this.endedAt,
  });

  /// A bare 32 character lowercase hex id, the same shape the control parser
  /// requires for every frame.
  final String id;

  /// The media the call was *started* with.
  ///
  /// Mutated in place — to [CallMode.video] — by the mid-call upgrade, which is
  /// why it is not final on the wire: the peer is never told, and does not need
  /// to be, because the camera transceiver was negotiated as `sendrecv` when the
  /// connection was built.
  final CallMode mode;

  final CallSide side;

  /// Always equal to `CallMachine.status` for as long as the session exists.
  final CallStatus status;

  /// When the session was created: the moment the caller sent its offer, or the
  /// moment the `call-offer` arrived for the callee. It is read from the injected
  /// clock, never from a real timer, so a test can place it exactly.
  final DateTime startedAt;

  /// When the `call-offer` went on the wire. Equal to [startedAt] for the caller
  /// (the offer is the first thing `startOutgoing` does) and [startedAt] for the
  /// callee too, since the offer is the frame that created the session. Kept as a
  /// separate field because it is the instant both timeouts are measured from.
  final DateTime? offeredAt;

  /// When the invitation was accepted: `onRemoteAccept` for the caller, `accept`
  /// for the callee.
  final DateTime? acceptedAt;

  /// When [mode] became [CallMode.video] mid-call. `null` for a call that was
  /// started as a video call or never upgraded.
  final DateTime? upgradedAt;

  /// When the media was published and the call became [CallStatus.connected].
  final DateTime? connectedAt;

  /// When the call reached [CallStatus.ended]. `null` while it is live.
  final DateTime? endedAt;

  /// How long the invitation rang, measured to the moment it was accepted.
  ///
  /// `null` if it was never accepted, which for the callee means the answer
  /// screen was closed or the ring timeout fired, and for the caller means the
  /// offer timed out or was declined.
  Duration? get ringingDuration => acceptedAt?.difference(startedAt);

  /// How long the call lived, measured to the end. `0` while it is live.
  Duration get totalDuration =>
      (endedAt ?? connectedAt ?? acceptedAt ?? startedAt).difference(startedAt);

  /// Whether [mode] currently publishes a camera track.
  bool get hasVideo => mode == CallMode.video;

  /// Whether the call reached both sides' accept.
  bool get isSettled => status.isSettled;

  CallSession copyWith({
    CallMode? mode,
    CallStatus? status,
    DateTime? acceptedAt,
    DateTime? upgradedAt,
    DateTime? connectedAt,
    DateTime? endedAt,
  }) => CallSession(
    id: id,
    mode: mode ?? this.mode,
    side: side,
    status: status ?? this.status,
    startedAt: startedAt,
    offeredAt: offeredAt,
    acceptedAt: acceptedAt ?? this.acceptedAt,
    upgradedAt: upgradedAt ?? this.upgradedAt,
    connectedAt: connectedAt ?? this.connectedAt,
    endedAt: endedAt ?? this.endedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallSession &&
          other.id == id &&
          other.mode == mode &&
          other.side == side &&
          other.status == status &&
          other.startedAt == startedAt &&
          other.offeredAt == offeredAt &&
          other.acceptedAt == acceptedAt &&
          other.upgradedAt == upgradedAt &&
          other.connectedAt == connectedAt &&
          other.endedAt == endedAt;

  @override
  int get hashCode => Object.hash(
    id,
    mode,
    side,
    status,
    startedAt,
    offeredAt,
    acceptedAt,
    upgradedAt,
    connectedAt,
    endedAt,
  );

  @override
  String toString() =>
      'CallSession($id ${side.name} ${mode.wireName} ${status.name} '
      'started=$startedAt ended=$endedAt)';
}
