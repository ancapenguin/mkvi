/// How a call finished, as a value the UI can branch on.
///
/// A decline, a timeout and a transport failure are three different facts, and a
/// caller needs to react to each differently: one is a person saying no, one is
/// silence, one is something breaking. This hierarchy exists to make collapsing
/// them into "an error happened" impossible to write by accident — [CallDeclined]
/// is a *result*, its own type, and is not [CallFailed].
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
/// **Not** a failure: the person on the other end pressed "Reddet", and the UI
/// must not present that as a broken microphone.
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
  /// carried none. The wire parser has already scrubbed and capped whatever
  /// arrived, so this needs no further checking.
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
/// [CallMachine.callOfferTimeout] from the callee's 45 s
/// [CallMachine.callRingTimeout], and both are 45 s on purpose. Without it the two
/// would be one outcome with two different notices, and a caller could not tell
/// from its history whether *it* was left waiting or *the other side* was.
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

/// The peer hung up while the invitation was still unanswered. Distinct from
/// [CallEndedByRemote] because nothing was ever said on this call.
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
/// This is the bucket for genuine breakage only. A decline is [CallDeclined] and
/// a silence is [CallTimedOut]; neither of those is a failure, and routing them
/// through here is exactly what makes a "Reddet" look like a broken microphone.
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
