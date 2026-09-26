/// Every Turkish string the call state machine can produce.
///
/// `PeerProtocol` already owns the two strings that also travel as a `reason` on
/// the wire — [PeerProtocol.defaultCallDeclineReason] and
/// [PeerProtocol.busyCallReason] — and those are *reused* here rather than
/// repeated, so a change in one place cannot leave the other stale. This file owns
/// the strings that exist only in the call state machine.
///
/// These strings are a compatibility surface, not decoration. Every `reason` here
/// is put on the wire by one peer and rendered as text by the *other* one, and the
/// button labels are what a person reads while deciding whether to accept a call.
/// A Turkish string rewritten "to sound better" therefore breaks two things at
/// once: a peer's decline reason, and a translated UI. Each entry below says what
/// it is *for*, so the next reader can tell a deliberate wording from a typo.
library;

import 'package:mkvi/core/protocol/control_message.dart';

/// The call layer's own user-facing text. Turkish, like every other user-facing
/// string in the port.
final class CallMessages {
  const CallMessages._();

  /// Refused by [CallMachine.startOutgoing] while a call is already live.
  static const String callInProgress = 'Başka bir arama zaten etkin.';

  /// Refused by [CallMachine.accept] when no incoming call is ringing. Local only:
  /// no frame carries it, because the peer is already gone.
  static const String incomingCallNotFound = 'Gelen arama bulunamadı.';

  /// The caller's 45 s offer timeout elapsed. Shown to the caller only; the peer
  /// receives a `call-end` instead, and has nothing to render.
  static const String offerTimeout = 'Arama yanıtı için zaman aşımı oluştu.';

  /// The callee-side ring timeout, and the whole point of that timer existing.
  ///
  /// A timer on the caller alone is not enough: without one on the callee, a
  /// ringing dialog can sit on screen forever with both buttons disabled, and the
  /// only thing that ever clears it is the user. This string is the `reason` that
  /// goes into the `call-decline` the ring timeout sends, so the caller can tell
  /// "she said no" from "she never heard it" — the two need different reactions
  /// and one generic decline reason would collapse them.
  static const String ringTimeoutReason = 'Cevap verilmedi.';

  /// The peer ended a call that had already connected.
  static const String remoteCallEnded = 'Karşı taraf aramayı sonlandırdı.';

  /// The peer cancelled a call that had *not* connected yet. Deliberately a
  /// different string from [remoteCallEnded]: the call never became a
  /// conversation, so "sonlandırdı" (ended) would be a lie.
  static const String remoteCallCancelled = 'Karşı taraf aramayı bitirdi.';

  /// This device hung up, after the call had connected.
  static const String callEndedLocally = 'Arama sonlandırıldı.';

  /// The local user gave up on an invitation nobody answered, and the callee's
  /// dialog is still waiting. This is *not* [callEndedLocally]: the call never
  /// connected, and saying it was "ended" hides that the user is the one who
  /// walked away from a ringing screen.
  static const String callCancelledLocally = 'Arama iptal edildi.';

  /// Sent as the decline `reason` when the callee's media cannot start, so the
  /// caller learns that the refusal was technical rather than personal.
  static const String mediaUnavailable = 'Medya başlatılamadı.';

  /// Fallback when starting the call throws.
  static const String startFailed = 'Arama başlatılamadı.';

  /// Fallback when accepting throws.
  static const String acceptFailed = 'Arama kabul edilemedi.';

  /// Fallback when declining throws.
  static const String declineFailed = 'Arama reddedilemedi.';

  /// Refusal of the mid-call video upgrade while the call is not connected.
  static const String notConnected = 'Arama bağlı değil.';

  /// Refusal of a second mid-call video upgrade.
  static const String alreadyVideo = 'Arama zaten görüntülü.';

  /// Refusal of [CallMachine.reset] while a call is still live.
  static const String callStillRunning = 'Arama hâlâ sürüyor.';

  /// The promise the answer dialog makes before the user accepts.
  ///
  /// Kept literally true: no `PublishMedia` action exists before
  /// [CallMachine.accept] has emitted one. It is a claim about the wire, not
  /// about the UI, and `test/call/call_incoming_test.dart` is what keeps it
  /// honest.
  static const String mediaPromise =
      'Kabul edene kadar kamera ve mikrofonundan hiçbir şey gönderilmez.';

  /// The eyebrow above the answer dialog title, which names the call's mode.
  static String incomingEyebrow(CallMode mode) =>
      'Gelen ${mode == CallMode.video ? 'görüntülü' : 'sesli'} arama';

  /// The answer dialog title. Shows the caller's name, so it is the one string
  /// here that is a function of peer state rather than of local state.
  static String peerIsCalling(String peerName) => '$peerName arıyor';

  /// The accept button while the camera is being opened — the window in which
  /// the promise of [mediaPromise] is being kept.
  static const String preparing = 'Hazırlanıyor…';

  /// The answer dialog's decline button.
  static const String declineLabel = 'Reddet';

  /// The answer dialog's accept button.
  static const String acceptLabel = 'Kabul et';

  /// The empty call stage caption while an invitation is unanswered.
  static const String waitingForAnswer = 'Yanıt bekleniyor…';

  /// The empty call stage caption when a call is live but nothing is being sent.
  static const String noActiveVideo = 'Aktif görüntü yok';
}
