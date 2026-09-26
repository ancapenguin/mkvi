/// Every user-facing string the call screen owns, in Turkish, in one place.
///
/// ## Why the answer screen's words are NOT here
///
/// The answer screen's eyebrow, its title, its two button labels and the promise
/// it makes to the user already exist, in [CallMessages], and they exist there for
/// a reason worth repeating: the TypeScript original wrote them inline in
/// `ChatCallWorkspace.tsx:182-187` and the same two sentences were re-typed in
/// three other places, so "Kabul et" existed in four spellings. Re-typing them here
/// would restart that. So this file **reuses** them — see [CallUiReused] — and
/// owns only what the screen layer actually introduces: the countdown, the
/// control bar's accessible names, the device picker's sections and the two
/// video-tile labels.
///
/// That reuse is the same rule [CallMessages] follows against
/// `PeerProtocol.defaultCallDeclineReason`: a Turkish string with two sources of
/// truth is a string that will be "fixed" in one place and left stale in the
/// other.
///
/// ## Why these are `static const` and not an enum
///
/// An enum member's field cannot be read in a constant expression, and this
/// layer's controls take their defaults as `const` constructor arguments. So the
/// catalogue is a `final class` of `static const String` — the same shape
/// [CallMessages] and `MediaTexts` use — which keeps every string usable as a
/// default, in a `const` object, with no second copy of the text.
library;

import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';

/// The whole Turkish vocabulary of the call screen.
final class CallUiTr {
  const CallUiTr._();

  // ---------------------------------------------------------------------------
  // The answer screen
  // ---------------------------------------------------------------------------

  /// The accessible description of the countdown line.
  ///
  /// A screen reader reads the visible "Kalan süre: 44 sn" as text; this is what
  /// tells it *that the number is a deadline*, which the number alone does not.
  static const String countdownHint =
      'Kalan süre, cevap ekranı kapanana kadar';

  /// The remaining-seconds line, as Turkish text.
  ///
  /// [seconds] must already be clamped to zero by the host, so this cannot print
  /// a negative. The unit is spelled out rather than abbreviated because a bare
  /// "44" on a screen whose only other number is a call duration reads as an id.
  static String remainingSeconds(int seconds) => 'Kalan süre: $seconds sn';

  // ---------------------------------------------------------------------------
  // The control bar
  //
  // Every control is an icon button, and an icon button with no `tooltip` is the
  // 17-WCAG-violation shape `ROADMAP.md` names. The name is therefore part of the
  // catalogue and not something a call site invents, and the wording is
  // deliberately about the *action* — "Kamerayı kapat", not "Kamera" — because the
  // one question a user has about an icon button is what pressing it will do.
  // ---------------------------------------------------------------------------

  /// The microphone button while the published track is audible.
  static const String microphoneMute = 'Mikrofonu kapat';

  /// The microphone button while the published track is muted.
  static const String microphoneUnmute = 'Mikrofonu aç';

  /// The camera button while the camera is publishing.
  static const String cameraStop = 'Kamerayı kapat';

  /// The camera button while the camera is off.
  static const String cameraStart = 'Kamerayı aç';

  /// The screen-share button while nothing is being shared.
  static const String screenShareStart = 'Ekran paylaşımını başlat';

  /// The screen-share button while a share is attached.
  static const String screenShareStop = 'Ekran paylaşımını durdur';

  /// The button that opens the device picker.
  static const String devicesOpen = 'Cihaz seç';

  /// The button that ends the call.
  static const String hangUp = 'Aramayı kapat';

  /// The hang-up button's hint, which says what it does to the other side.
  static const String hangUpHint = 'Karşı tarafın araması da sonlanır.';

  // ---------------------------------------------------------------------------
  // The device picker
  // ---------------------------------------------------------------------------

  /// The camera section's heading.
  static const String cameraSection = 'Kamera';

  /// The microphone section's heading.
  static const String microphoneSection = 'Mikrofon';

  /// The share-target section's heading.
  static const String displaySection = 'Paylaşılacak ekran ya da pencere';

  /// What the camera section says when the OS lists no camera.
  static const String noCameras = 'Bu cihazda kamera bulunamadı.';

  /// What the microphone section says when the OS lists no microphone.
  static const String noMicrophones = 'Bu cihazda mikrofon bulunamadı.';

  /// What the display section says when there is nothing to share.
  static const String noDisplaySources =
      'Paylaşılacak ekran ya da pencere bulunamadı.';

  /// The description of a share target that is a whole screen.
  static const String displayScreenKind = 'Ekran';

  /// The description of a share target that is a single window.
  static const String displayWindowKind = 'Pencere';

  // ---------------------------------------------------------------------------
  // The stage
  // ---------------------------------------------------------------------------

  /// The main tile's label while it shows the other side.
  static const String remoteVideoLabel = 'Karşı taraf';

  /// The main tile's label while it shows this device's own camera.
  static const String localVideoLabel = 'Sen';

  /// The small tile's accessible name, which says *whose* it is and that it is the
  /// small one — a screen reader user has no "small box" to see.
  static const String pipLabel = 'Kendi küçük görüntün';

  /// The main tile's caption while the call is being set up.
  static const String connectingCaption = 'Bağlanıyor…';

  // ---------------------------------------------------------------------------
  // The derived wordings
  //
  // Functions rather than a format string, because a value with a hole in it is
  // the same problem `MkviSliderRow.valueLabel` avoids: a second, unscaled copy
  // of a unit can grow inside the format.
  // ---------------------------------------------------------------------------

  /// The microphone button's name for [muted].
  static String microphoneAction({required bool muted}) =>
      muted ? microphoneUnmute : microphoneMute;

  /// The camera button's job, from the one field the media layer does keep.
  ///
  /// [MediaState.cameraLive] is the whole truth here: the layer stops the track on
  /// disable rather than muting it, so the flag really is the camera.
  static String cameraAction({required bool live}) =>
      live ? cameraStop : cameraStart;

  /// The screen-share button's job, from `ScreenSharePhase.isAttached`.
  ///
  /// Read off `isAttached` rather than `live` on purpose: a share that started and
  /// has not produced its first frame is *running*, and a button offering to
  /// "start" a share which is already capturing is the old black-rectangle bug
  /// with a different caption.
  static String screenShareAction({required bool attached}) =>
      attached ? screenShareStop : screenShareStart;

  /// Every fixed entry, keyed by its own name, for tests and a debug overlay.
  ///
  /// A second list of *names* and not a second list of texts: every value below is
  /// the same constant the widgets use, so a change to one changes the catalogue
  /// with it.
  static const Map<String, String> catalogue = <String, String>{
    'countdownHint': countdownHint,
    'microphoneMute': microphoneMute,
    'microphoneUnmute': microphoneUnmute,
    'cameraStop': cameraStop,
    'cameraStart': cameraStart,
    'screenShareStart': screenShareStart,
    'screenShareStop': screenShareStop,
    'devicesOpen': devicesOpen,
    'hangUp': hangUp,
    'hangUpHint': hangUpHint,
    'cameraSection': cameraSection,
    'microphoneSection': microphoneSection,
    'displaySection': displaySection,
    'noCameras': noCameras,
    'noMicrophones': noMicrophones,
    'noDisplaySources': noDisplaySources,
    'displayScreenKind': displayScreenKind,
    'displayWindowKind': displayWindowKind,
    'remoteVideoLabel': remoteVideoLabel,
    'localVideoLabel': localVideoLabel,
    'pipLabel': pipLabel,
    'connectingCaption': connectingCaption,
  };
}

/// The words the answer screen reuses from the call layer rather than retyping.
///
/// A test asserts that these are the *same* values, so a second spelling cannot
/// appear here without a test noticing.
abstract final class CallUiReused {
  const CallUiReused._();

  /// The eyebrow above the answer screen's title.
  static String eyebrow(CallMode mode) => CallMessages.incomingEyebrow(mode);

  /// The answer screen's title.
  static String title(String peerName) => CallMessages.peerIsCalling(peerName);

  /// The sentence that makes the answer screen's promise about media.
  static const String promise = CallMessages.mediaPromise;

  /// The accept button's label.
  static const String accept = CallMessages.acceptLabel;

  /// The decline button's label.
  static const String decline = CallMessages.declineLabel;

  /// The stage's caption while nobody has answered the call yet.
  static const String waitingForAnswer = CallMessages.waitingForAnswer;

  /// The stage's caption when there is genuinely no video to show.
  static const String noActiveVideo = CallMessages.noActiveVideo;
}
