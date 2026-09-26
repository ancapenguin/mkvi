/// Every Turkish string the call state machine can produce.
///
/// `PeerProtocol` already owns the two strings that also travel as a `reason` on
/// the wire — [PeerProtocol.defaultCallDeclineReason] and
/// [PeerProtocol.busyCallReason] — and those are *reused* here rather than
/// repeated, so a change in one place cannot leave the other stale. This file owns
/// the strings that exist only in the call state machine.
///
/// Every entry carries the `file:line` it was ported from, because a Turkish
/// string with no source is a string that will be "fixed" by someone who does not
/// know the peer that already displays it.
library;

import 'package:mkvi/core/protocol/control_message.dart';

/// The call layer's own user-facing text. Turkish, like every other user-facing
/// string in the port.
final class CallMessages {
  const CallMessages._();

  /// TS: the rejection of `requestCall` when a call is already live,
  /// `src/services/peer-transport.ts:105`.
  static const String callInProgress = 'Başka bir arama zaten etkin.';

  /// TS: the throw of `acceptCall` for an id the transport does not hold,
  /// `src/services/peer-transport.ts:123`.
  static const String incomingCallNotFound = 'Gelen arama bulunamadı.';

  /// TS: the caller's 45 s offer timeout rejection,
  /// `src/services/peer-transport.ts:112`.
  static const String offerTimeout = 'Arama yanıtı için zaman aşımı oluştu.';

  /// Not in 0.1.x, and the point of the callee-side ring timeout.
  ///
  /// 0.1.4 had a 45 s timer on the *caller* (`CALL_OFFER_TIMEOUT_MS`) and nothing
  /// at all on the callee, so `incomingCalls` was only ever cleared by
  /// accept/decline/stop/close and a ringing dialog could sit on screen forever
  /// with both buttons disabled. This is the `reason` that goes into the
  /// `call-decline` the ring timeout sends.
  static const String ringTimeoutReason = 'Cevap verilmedi.';

  /// TS: the rejection `receiveControl` produces for a `call-end`,
  /// `src/services/peer-transport.ts:440`.
  static const String remoteCallEnded = 'Karşı taraf aramayı sonlandırdı.';

  /// TS: the notice `App.tsx:404` showed for `remote-call-ended`.
  static const String remoteCallCancelled = 'Karşı taraf aramayı bitirdi.';

  /// TS: the rejection `stopCall` hands to every pending call,
  /// `src/services/peer-transport.ts:208`.
  static const String callEndedLocally = 'Arama sonlandırıldı.';

  /// The local user gave up on an invitation nobody answered. No TypeScript
  /// counterpart: 0.1.x rejected the pending call with
  /// [callEndedLocally] and let the dialog sit there.
  static const String callCancelledLocally = 'Arama iptal edildi.';

  /// TS: the decline `App.tsx:584` sends when the callee's media cannot start.
  static const String mediaUnavailable = 'Medya başlatılamadı.';

  /// TS: `ChatCallWorkspace.tsx:352`, the fallback when `onStartCall` throws.
  static const String startFailed = 'Arama başlatılamadı.';

  /// TS: `ChatCallWorkspace.tsx:368`, the fallback when accepting throws.
  static const String acceptFailed = 'Arama kabul edilemedi.';

  /// TS: `ChatCallWorkspace.tsx:376`, the fallback when declining throws.
  static const String declineFailed = 'Arama reddedilemedi.';

  /// Refusal of the mid-call video upgrade while the call is not connected.
  static const String notConnected = 'Arama bağlı değil.';

  /// Refusal of a second mid-call video upgrade.
  static const String alreadyVideo = 'Arama zaten görüntülü.';

  /// Refusal of [CallMachine.reset] while a call is still live.
  static const String callStillRunning = 'Arama hâlâ sürüyor.';

  /// TS: the promise the answer dialog makes, `ChatCallWorkspace.tsx:184`.
  ///
  /// The port keeps it literally true: no `PublishMedia` action exists before
  /// `CallMachine.accept` has emitted one.
  static const String mediaPromise =
      'Kabul edene kadar kamera ve mikrofonundan hiçbir şey gönderilmez.';

  /// TS: the eyebrow above the answer dialog title, `ChatCallWorkspace.tsx:182`.
  static String incomingEyebrow(CallMode mode) =>
      'Gelen ${mode == CallMode.video ? 'görüntülü' : 'sesli'} arama';

  /// TS: the answer dialog title, `ChatCallWorkspace.tsx:183`.
  static String peerIsCalling(String peerName) => '$peerName arıyor';

  /// TS: the accept button while the camera is being opened,
  /// `ChatCallWorkspace.tsx:187`.
  static const String preparing = 'Hazırlanıyor…';

  /// TS: the answer dialog's decline button, `ChatCallWorkspace.tsx:186`.
  static const String declineLabel = 'Reddet';

  /// TS: the answer dialog's accept button, `ChatCallWorkspace.tsx:187`.
  static const String acceptLabel = 'Kabul et';

  /// TS: the empty call stage caption, `ChatCallWorkspace.tsx:541`.
  static const String waitingForAnswer = 'Yanıt bekleniyor…';

  /// TS: the empty call stage caption, `ChatCallWorkspace.tsx:541`.
  static const String noActiveVideo = 'Aktif görüntü yok';
}
