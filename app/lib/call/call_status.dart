import 'package:mkvi/core/protocol/control_message.dart';

/// Which side of the call this device is on.
///
/// TS: the transport is the same object on both ends and distinguishes the sides
/// by *which* field holds the id — `pendingCalls` for the caller,
/// `incomingCalls` for the callee. The Dart port has one session, so the side is
/// a value in it and every guard can read it instead of guessing.
enum CallSide { caller, callee }

/// The six call states the old UI rendered.
///
/// TS: `export type CallStatus` in `src/components/ChatCallWorkspace.tsx:15`, and
/// [label] is the `statusLabels` entry of the same file. The set is *not* the
/// transport's: the transport has no states at all, it has three maps
/// (`pendingCalls`, `incomingCalls`, `activeCallId`) and lets `App.tsx` guess the
/// rest. Collapsing them into one enum is what makes "the callee cannot accept
/// a call that already ended" a compile-time-checkable condition instead of an
/// `if` over a `Set<string>` of magic strings.
enum CallStatus {
  /// No call, or a call the user has already been shown the end of.
  idle('Arama yok'),

  /// The invitation is on the wire and nobody has answered it yet.
  ///
  /// TS: `requestCall` is pending, i.e. `pendingCalls.size > 0`.
  outgoing('Yanıt bekleniyor'),

  /// A `call-offer` arrived and the user has not answered it yet.
  ///
  /// TS: `incomingCalls.size > 0`. This state exists *only* in 0.1.4+; the
  /// released 0.1.4 build auto-accepted, so there was no such window at all.
  incoming('Gelen arama'),

  /// Both sides accepted and the media is being published.
  connecting('Bağlanıyor'),

  /// Media is flowing.
  connected('Güvenli bağlantı'),

  /// The call finished, for any reason. [CallMachine.reset] returns to [idle].
  ended('Arama sona erdi');

  const CallStatus(this.label);

  /// TS: `statusLabels[callStatus]`, `ChatCallWorkspace.tsx:202-209`.
  final String label;

  /// Whether a call is in progress, i.e. whether [CallMachine.startOutgoing] and
  /// [CallMachine.accept] must be refused.
  ///
  /// TS: `if (this.activeCallId || this.pendingCalls.size || this.incomingCalls.size)`
  /// in `requestCall`, and the `!["idle", "ended"].includes(callStatusRef.current)`
  /// test in `App.tsx:390`.
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
  /// real conversation rather than an unanswered invitation.
  ///
  /// TS: `if (!["idle", "incoming", "ended"].includes(callStatusRef.current)`
  /// in `App.tsx:399` — the same test, spelled as one question.
  bool get isSettled =>
      this == CallStatus.connecting || this == CallStatus.connected;
}

/// Convenience: whether [mode] is a mode that publishes a camera track.
///
/// The Dart transport has three `sendrecv` transceivers from the moment the
/// connection is built — audio, camera, screen — so a mode is a *permission*, not
/// a negotiation. TS: `this.audioTransceiver` / `this.cameraTransceiver` in
/// `src/services/peer-transport.ts:78-80`, added once and never re-added.
bool modeWantsVideo(CallMode mode) => mode == CallMode.video;
