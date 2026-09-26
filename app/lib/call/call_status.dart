import 'package:mkvi/core/protocol/control_message.dart';

/// Which side of the call this device is on.
///
/// The side is a *value* in the one session rather than an accident of which
/// container happens to hold the call id, so every guard can read it explicitly
/// instead of inferring it.
enum CallSide { caller, callee }

/// The six states a call can be in, with the label the UI shows for each.
///
/// The set is deliberately the UI's, not the transport's: the transport has no
/// states at all, it has separate pending/incoming/active collections and leaves
/// the status to be guessed. Collapsing them into one enum is what makes "the
/// callee cannot accept a call that already ended" a compile-time-checkable
/// condition instead of an `if` over a set of magic strings.
enum CallStatus {
  /// No call, or a call the user has already been shown the end of.
  idle('Arama yok'),

  /// The invitation is on the wire and nobody has answered it yet.
  outgoing('Yanıt bekleniyor'),

  /// A `call-offer` arrived and the user has not answered it yet.
  ///
  /// This state is a promise: nothing is on the wire and no capture is running
  /// until the user accepts, which is why the callee's ring timer is the only
  /// thing standing between this state and an answer dialog that never closes.
  incoming('Gelen arama'),

  /// Both sides accepted and the media is being published.
  connecting('Bağlanıyor'),

  /// Media is flowing.
  connected('Güvenli bağlantı'),

  /// The call finished, for any reason. [CallMachine.reset] returns to [idle].
  ended('Arama sona erdi');

  const CallStatus(this.label);

  /// The Turkish label the UI renders for this state.
  final String label;

  /// Whether a call is in progress, i.e. whether [CallMachine.startOutgoing] and
  /// [CallMachine.accept] must be refused.
  ///
  /// One predicate, asked as one question. Every entry point consults it, so
  /// "busy" cannot mean three slightly different things in three places.
  bool get isLive =>
      this == CallStatus.outgoing ||
      this == CallStatus.incoming ||
      this == CallStatus.connecting ||
      this == CallStatus.connected;

  /// Whether an answered-or-not invitation is still waiting for the user.
  ///
  /// This is the single guard that makes the two timers unambiguous: the offer
  /// timer only means something in [outgoing] and the ring timer only in
  /// [incoming].
  bool get isRinging => this == CallStatus.incoming;

  /// Whether the call got past both sides' accept, i.e. whether it counts as a
  /// real conversation rather than an unanswered invitation. One question, asked
  /// once, so "was this a real call?" cannot be answered three different ways.
  bool get isSettled =>
      this == CallStatus.connecting || this == CallStatus.connected;
}

/// Convenience: whether [mode] is a mode that publishes a camera track.
///
/// The transport has three `sendrecv` transceivers from the moment the connection
/// is built — audio, camera, screen — so a mode is a *permission*, not a
/// negotiation, and this is only the permission check.
bool modeWantsVideo(CallMode mode) => mode == CallMode.video;
