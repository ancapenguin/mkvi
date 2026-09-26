/// How a call finished, as a value the UI can branch on.
///
/// The four live bugs include one that is *entirely* about this file: 0.1.4
/// declared `call-declined` in `PeerTransportEvent`, the transport emitted it, and
/// **no branch anywhere consumed it** — the caller only learned about a decline
/// through the rejection of the `requestCall` promise, which `App.tsx` turned into
/// a media error. So a decline, a timeout and a transport failure all arrived as
/// "an error happened".
///
/// [CallDeclined] exists to make that impossible to write by accident: a decline
/// is a *result*, not an exception, it is its own type, and it is not
/// [CallFailed].
library;

import 'call_messages.dart';

/// The sealed set of ways a call attempt can end.
///
/// Sealed so that a `switch` over it is exhaustive: adding a fifth way to end a
/// call becomes a compile error in every consumer instead of a silently
/// unhandled case.
sealed class CallOutcome {
  const CallOutcome();

  /// The call id this outcome belongs to.
  String get id;

  /// When the outcome was decided.
  DateTime get at;

  /// The Turkish line the UI shows as a notice.
  String get notice;
}

/// The peer accepted the invitation. Not an ending: the call goes on to
/// [CallStatus.connecting] and then [CallStatus.connected].
///
/// TS: the `resolve(id)` of the `requestCall` promise, `peer-transport.ts:430`.
final class CallAccepted extends CallOutcome {
  const CallAccepted({required this.id, required this.at});

  @override
  final String id;

  @override
  final DateTime at;

  @override
  String get notice => '';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallAccepted && other.id == id && other.at == at;

  @override
  int get hashCode => Object.hash(id, at);

  @override
  String toString() => 'CallAccepted($id at=$at)';
}

/// The peer sent `call-decline`.
///
/// **Not** a failure: the person on the other end pressed "Reddet". TS: the
/// `call-decline` case of `receiveControl`, `peer-transport.ts:433-438`, whose
/// `emit({ type: "call-declined", ... })` no consumer handled.
final class CallDeclined extends CallOutcome {
  const CallDeclined({
    required this.id,
    required this.at,
    required this.reason,
  });

  @override
  final String id;

  @override
  final DateTime at;

  /// The peer's reason, or [PeerProtocol.defaultCallDeclineReason] when the frame
  /// carried none — the same fallback `receiveControl` uses.
  final String reason;

  @override
  String get notice => reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallDeclined &&
          other.id == id &&
          other.at == at &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(id, at, reason);

  @override
  String toString() => 'CallDeclined($id at=$at "$reason")';
}

/// Nobody answered within the timeout.
///
/// [offeredByUs] is the only thing that distinguishes the caller's 45 s
/// `CALL_OFFER_TIMEOUT_MS` from the callee's 45 s ring timeout, and it is exactly
/// the distinction 0.1.x could not draw because it had only one of the two.
final class CallTimedOut extends CallOutcome {
  const CallTimedOut({
    required this.id,
    required this.at,
    required this.waited,
    required this.offeredByUs,
  });

  @override
  final String id;

  @override
  final DateTime at;

  /// How long was waited. Always the relevant 45 s, never a real elapsed time.
  final Duration waited;

  /// `true` on the caller (nobody accepted our `call-offer`), `false` on the
  /// callee (nobody answered the ringing screen).
  final bool offeredByUs;

  @override
  String get notice =>
      offeredByUs ? CallMessages.offerTimeout : CallMessages.ringTimeoutReason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallTimedOut &&
          other.id == id &&
          other.at == at &&
          other.waited == waited &&
          other.offeredByUs == offeredByUs;

  @override
  int get hashCode => Object.hash(id, at, waited, offeredByUs);

  @override
  String toString() =>
      'CallTimedOut($id at=$at waited=${waited.inSeconds}s '
      'offeredByUs=$offeredByUs)';
}

/// The peer hung up while the invitation was still unanswered.
///
/// TS: the `call-end` case of `receiveControl` reaching a call that had not
/// connected, `peer-transport.ts:439-445`.
final class CallCancelledByRemote extends CallOutcome {
  const CallCancelledByRemote({required this.id, required this.at});

  @override
  final String id;

  @override
  final DateTime at;

  @override
  String get notice => CallMessages.remoteCallCancelled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallCancelledByRemote && other.id == id && other.at == at;

  @override
  int get hashCode => Object.hash(id, at);

  @override
  String toString() => 'CallCancelledByRemote($id at=$at)';
}

/// The peer hung up from a connected call.
final class CallEndedByRemote extends CallOutcome {
  const CallEndedByRemote({required this.id, required this.at});

  @override
  final String id;

  @override
  final DateTime at;

  @override
  String get notice => CallMessages.remoteCallEnded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallEndedByRemote && other.id == id && other.at == at;

  @override
  int get hashCode => Object.hash(id, at);

  @override
  String toString() => 'CallEndedByRemote($id at=$at)';
}

/// We hung up, from any state. [reason] is the Turkish line for the notice:
/// [CallMessages.callEndedLocally] for a hangup, or the decline text when the
/// answer screen was dismissed.
final class CallEndedLocally extends CallOutcome {
  const CallEndedLocally({
    required this.id,
    required this.at,
    required this.reason,
  });

  @override
  final String id;

  @override
  final DateTime at;

  final String reason;

  @override
  String get notice => reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallEndedLocally &&
          other.id == id &&
          other.at == at &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(id, at, reason);

  @override
  String toString() => 'CallEndedLocally($id at=$at "$reason")';
}

/// The call could not be made: the capture failed, the transport refused to send,
/// the channel closed mid-call.
///
/// This is the bucket 0.1.4 put *everything* into, which is why a decline looked
/// like a broken microphone. A decline is [CallDeclined]; only a genuine failure
/// is this.
final class CallFailed extends CallOutcome {
  const CallFailed({required this.id, required this.at, required this.reason});

  @override
  final String id;

  @override
  final DateTime at;

  /// Turkish, because it is shown verbatim.
  final String reason;

  @override
  String get notice => reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallFailed &&
          other.id == id &&
          other.at == at &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(id, at, reason);

  @override
  String toString() => 'CallFailed($id at=$at "$reason")';
}
