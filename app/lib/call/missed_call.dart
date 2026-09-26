import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';

import 'call_messages.dart';

/// Why a call finished without becoming a conversation, or — for
/// [endedNormally] — that it did and then finished.
///
/// The point of the enum is that these stay distinguishable. Three different
/// endings — a decline, a timeout and a cancellation — once reached the screen
/// through one indistinguishable "error" notice (or through nothing at all), and a
/// history that cannot say which one happened is not a history.
enum MissedCallReason {
  /// The callee answered the answer screen with "Reddet", or the callee's media
  /// could not start and it had to decline instead.
  declined,

  /// Nobody answered within 45 s. On the caller side that is the offer timer; on
  /// the callee side the ring timer.
  timedOut,

  /// The call was hung up — by the local user or by the peer — while the
  /// invitation was still unanswered.
  cancelled,

  /// The call connected and then ended normally.
  endedNormally;

  /// The Turkish one-liner the UI shows next to a record.
  String get label => switch (this) {
    // Reused rather than repeated: this is the same text `declineCall` defaults
    // to and the same text the receiver falls back to.
    MissedCallReason.declined => PeerProtocol.defaultCallDeclineReason,
    MissedCallReason.timedOut => CallMessages.ringTimeoutReason,
    MissedCallReason.cancelled => 'Karşı taraf aramayı iptal etti.',
    MissedCallReason.endedNormally => 'Arama sona erdi.',
  };
}

/// One finished call, kept so the UI can show it after the call stage is gone.
///
/// Small, immutable and deliberately free of any `MediaStream` or transport
/// handle: a missed call outlives the WebRTC connection, so anything it held would
/// either leak or be meaningless by the time the list is rendered.
final class MissedCall {
  const MissedCall({
    required this.id,
    required this.mode,
    required this.at,
    required this.reason,
    this.detail,
  });

  /// The call id. The same 32 character hex the control frames carry, so a record
  /// can be de-duplicated against a frame that arrives late.
  final String id;

  /// The mode the call was in when it finished — the *current* mode, so an
  /// audio call upgraded to video is recorded as video.
  final CallMode mode;

  /// When the call finished.
  final DateTime at;

  final MissedCallReason reason;

  /// The peer's own words, when there were any: the `reason` of a `call-decline`,
  /// already run through [PeerProtocol.maxReasonLength] and control-character
  /// scrubbing by the wire parser.
  final String? detail;

  /// The Turkish line the UI shows. The peer's words win when there are any.
  String get label =>
      detail != null && detail!.isNotEmpty ? detail! : reason.label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MissedCall &&
          other.id == id &&
          other.mode == mode &&
          other.at == at &&
          other.reason == reason &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(id, mode, at, reason, detail);

  @override
  String toString() =>
      'MissedCall($id ${mode.wireName} ${reason.name} at=$at '
      'detail=$detail)';
}
