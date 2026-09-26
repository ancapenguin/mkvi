import 'call_messages.dart';

/// Why a *user-triggered* step was refused, with the Turkish line the UI shows.
///
/// A refusal is not an exception. An earlier shape of this code signalled every
/// refusal by throwing, and the UI caught one kind of throw and rendered its
/// message in a single red box — which is how "Arama reddedildi." ended up
/// rendered in the same place as a missing microphone. Refusing quietly and
/// naming the reason keeps the two apart.
///
/// A refusal never changes state. The one exception is
/// [callInProgress] on an incoming offer, which is answered with a `call-decline`
/// on the wire: the peer is owed a decision, and `Meşgul.` is that decision.
/// Every other refusal is silent.
enum CallRefusal {
  /// Another call is live, so a new invitation was refused.
  callInProgress(CallMessages.callInProgress),

  /// The answer screen is gone: the call ended, the ring timeout fired, or the id
  /// belongs to a call this machine is not holding.
  ///
  /// This is the refusal that closes the race where the caller's 45 s offer
  /// timeout lands while the callee is still opening its camera.
  incomingCallNotFound(CallMessages.incomingCallNotFound),

  /// The mid-call video upgrade was asked for while the call was not connected.
  notConnected(CallMessages.notConnected),

  /// The mid-call video upgrade was asked for on a call that is already video.
  alreadyVideo(CallMessages.alreadyVideo),

  /// The UI asked to go back to idle while a call is still live.
  callStillRunning(CallMessages.callStillRunning);

  const CallRefusal(this.message);

  /// The Turkish text. Byte-identical to any literal the wire or a peer's UI may
  /// already be showing for the same refusal.
  final String message;
}
