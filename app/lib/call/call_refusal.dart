import 'call_messages.dart';

/// Why a *user-triggered* step was refused, with the Turkish line the UI shows.
///
/// A refusal is not an exception. The old build threw or rejected — 0.1.4's
/// `requestCall` returned a rejected promise and `App.tsx` showed its message as
/// a media error, which is how "Arama reddedildi." ended up rendered in the same
/// red box as a missing microphone. Refusing quietly and naming the reason keeps
/// the two apart.
///
/// A refusal never changes state. The one exception is
/// [callInProgress] on an incoming offer, which is answered with a `call-decline`
/// on the wire: the peer is owed a decision, and `Meşgul.` is that decision.
/// Every other refusal is silent.
enum CallRefusal {
  /// Another call is live, so a new invitation was refused. TS: the
  /// `requestCall` rejection at `peer-transport.ts:105`.
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

  /// The Turkish text. Byte-identical to the `new Error(...)` literal the
  /// TypeScript original used where one existed.
  final String message;
}
