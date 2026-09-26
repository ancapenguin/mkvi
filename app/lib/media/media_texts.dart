/// Every Turkish string `lib/media` can put in front of a user, in one place.
///
/// `lib/core/protocol/peer_protocol.dart` keeps the wire strings together for the
/// same reason this file exists. The Tauri build had no single owner for the media
/// error box: `ChatCallWorkspace.tsx` wrote its own wording inline, `App.tsx`
/// invented a second one, and the loudest of the three was
/// `setMediaError(error instanceof Error ? error.message : ...)`
/// (`ChatCallWorkspace.tsx:352`, `:368`, `:376`, `:419`, `:441`) — which put a raw
/// English WebView `DOMException` message straight into a Turkish UI.
///
/// A string that only exists at a call site is a string that can be an English
/// exception message. Nothing in `lib/media` builds a message by interpolation;
/// the classifier picks a constant out of this file and the raw platform text
/// goes to the injected diagnostics sink instead.
library;

/// The whole Turkish vocabulary of the media layer.
final class MediaTexts {
  const MediaTexts._();

  // ---------------------------------------------------------------------------
  // Camera capture failures
  //
  // Keyed in `MediaFault.text` by `(MediaFaultKind, MediaSourceKind)`. The
  // wording is deliberately per-source: "Kamera bulunamadı" and "Mikrofon
  // bulunamadı" send the user to a different cable.
  // ---------------------------------------------------------------------------

  /// TS: `captureMedia`'s combined `NotAllowedError` sentence, used when a call
  /// asked for both devices and permission was refused. Byte-identical.
  static const String callPermissionDenied =
      "Kamera veya mikrofon izni verilmedi. Windows ayarlarından MKVI'ye izin ver.";

  /// The standalone permission refusal for the camera alone.
  static const String cameraPermissionDenied =
      "Kamera erişimine izin verilmedi. Windows ayarlarından MKVI'ye izin ver.";

  /// The camera is absent, disabled, or claimed by the OS as unusable.
  static const String cameraNotFound =
      "Kamera bulunamadı. Cihaz bağlı değil ya da başka bir uygulama kullanıyor olabilir.";

  /// Another process holds the camera exclusively.
  static const String cameraBusy =
      "Kamera başka bir uygulama tarafından kullanılıyor. O uygulamayı kapat ve yeniden dene.";

  /// The camera opened and then produced nothing.
  static const String cameraNotReadable =
      "Kamera açıldı ama görüntü gelmedi. Sürücüyü yeniden başlatıp tekrar dene.";

  /// No capture backend at all on this build.
  static const String cameraUnsupported =
      'Bu cihazda kamera erişimi desteklenmiyor.';

  /// The fallback for a camera failure the classifier could not place.
  static const String cameraUnknown =
      'Kamera açılamadı. Cihaz bağlıysa ve başka bir uygulama kullanmıyorsa tekrar dene.';

  // ---------------------------------------------------------------------------
  // Microphone capture failures
  // ---------------------------------------------------------------------------

  /// The standalone permission refusal for the microphone alone.
  static const String microphonePermissionDenied =
      "Mikrofon erişimine izin verilmedi. Windows ayarlarından MKVI'ye izin ver.";

  static const String microphoneNotFound =
      'Mikrofon bulunamadı. Cihaz bağlı değil ya da başka bir uygulama kullanıyor olabilir.';

  static const String microphoneBusy =
      'Mikrofon başka bir uygulama tarafından kullanılıyor. O uygulamayı kapat ve yeniden dene.';

  static const String microphoneNotReadable =
      'Mikrofon açıldı ama ses gelmedi. Cihaz seçimini değiştirip tekrar dene.';

  static const String microphoneUnsupported =
      'Bu cihazda mikrofon erişimi desteklenmiyor.';

  static const String microphoneUnknown =
      'Mikrofon açılamadı. Cihaz bağlıysa ve başka bir uygulama kullanmıyorsa tekrar dene.';

  // ---------------------------------------------------------------------------
  // Screen share failures
  // ---------------------------------------------------------------------------

  static const String screenPermissionDenied =
      'Ekran paylaşımına izin verilmedi.';

  /// The share never started for a reason the user caused: the picker was closed,
  /// or the window they picked had already gone.
  ///
  /// Not an error: the TypeScript original suppressed the same case
  /// (`ChatCallWorkspace.tsx:440` skips `NotAllowedError`), because closing a
  /// picker is not something to apologise for. On Windows there is no native picker
  /// to close — the application builds the list itself — so the reachable case is
  /// the stale-source one, and the wording covers both.
  static const String screenCancelled =
      'Ekran paylaşımı iptal edildi ya da paylaşılan pencere kapandı.';

  static const String screenNotFound =
      'Paylaşılacak ekran ya da pencere bulunamadı.';

  static const String screenBusy =
      'Seçilen pencere başka bir uygulama tarafından kullanılıyor.';

  static const String screenNotReadable =
      'Ekran paylaşımı başladı ama görüntü gelmedi.';

  static const String screenUnsupported =
      'Bu cihazda ekran paylaşımı desteklenmiyor.';

  static const String screenUnknown = 'Ekran paylaşımı başlatılamadı.';

  // ---------------------------------------------------------------------------
  // Faults about the connection rather than about a device
  // ---------------------------------------------------------------------------

  /// A media method was called before the transceivers existed.
  static const String connectionNotReady =
      'Medya bağlantısı henüz hazır değil.';

  /// A media method was called after `dispose`.
  static const String connectionClosed = 'Medya bağlantısı kapatıldı.';

  /// The last-resort text. A user should never see this, which is exactly why
  /// it exists.
  static const String genericFailure = 'Kamera ve mikrofon açılamadı.';

  // ---------------------------------------------------------------------------
  // Notices — a working call that is not what the user asked for, or a device
  // that left while the call was live
  // ---------------------------------------------------------------------------

  /// TS: the second rung's `warning` at `ChatCallWorkspace.tsx:316`.
  /// Byte-identical. This is the ONE degradation the ladder is still allowed to
  /// perform silently-but-announced, because the video the user asked for is
  /// still on the wire.
  static const String microphoneMissingInVideoCall =
      'Mikrofon bulunamadı; yalnızca görüntü gönderilecek.';

  /// The active camera disappeared from the device list.
  static const String cameraUnplugged =
      'Kamera çıkarıldı. Kamera görüntüsü gönderilmiyor.';

  /// The active microphone disappeared from the device list.
  static const String microphoneUnplugged =
      'Mikrofon çıkarıldı. Mikrofon sesi gönderilmiyor.';

  // ---------------------------------------------------------------------------
  // Screen share phase labels
  //
  // Every one of these is a state the user can be *in*, not an error. The
  // `waitingForFirstFrame` label is the whole point of the watchdog: see
  // `ScreenSharePhase` for why upstream cannot tell us.
  // ---------------------------------------------------------------------------

  static const String screenShareIdle = 'Ekran paylaşımı kapalı.';

  static const String screenShareStarting = 'Ekran paylaşımı başlatılıyor…';

  /// Shown from the instant the track is attached, because upstream never says
  /// anything at all: `getDisplayMedia` resolves with a track that may never
  /// produce a frame (upstream #2137). The old build sat on a black rectangle
  /// with no state at all.
  static const String screenShareWaitingForFirstFrame = 'İlk kare bekleniyor…';

  static const String screenShareLive = 'Ekran paylaşımı sürüyor.';

  /// The watchdog gave up waiting. The remedy is named because the upstream
  /// defect has one: the target window has to be foreground.
  static const String screenShareStalled =
      'Ekran paylaşımı başladı ama ilk kare gelmedi. '
      'Paylaşmak istediğin pencereyi öne getirip yeniden dene.';

  static const String screenShareFailed = 'Ekran paylaşımı başlatılamadı.';
}
