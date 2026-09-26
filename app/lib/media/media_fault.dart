import 'package:flutter/services.dart' show PlatformException;

import 'media_texts.dart';

/// Which device the failure is about.
///
/// The classifier needs this because the plugin raises the *same* exception name
/// for two completely different situations depending on the call site:
/// `NotAllowedError` from `getUserMedia` means the OS refused a permission
/// prompt, while `NotAllowedError` from `getDisplayMedia` means the user closed
/// the source list. The TypeScript original got this right by accident only —
/// `toggleScreenShare` (`ChatCallWorkspace.tsx:440`) special-cased
/// `NotAllowedError` — and the Dart port makes the context an explicit argument
/// so it cannot be forgotten at a new call site.
enum MediaSourceKind { microphone, camera, screen }

/// What went wrong, in the vocabulary the plugin and the OS actually produce.
enum MediaFaultKind {
  /// The OS refused the capture permission, or the user refused the prompt.
  permissionDenied,

  /// No such device: nothing enumerated, or the requested id is not in the list.
  deviceNotFound,

  /// Another process holds the device exclusively (`SHARING_VIOLATION`, WASAPI
  /// device-in-use, a browser `NotReadableError` raised for a locked camera).
  deviceBusy,

  /// The device opened and then produced no media, or was invalidated mid-capture.
  deviceNotReadable,

  /// No capture backend on this platform or build.
  unsupported,

  /// The media layer itself is not usable yet (`open()` has not run) or no longer
  /// (`dispose()` has run). Not a device problem, so it reads differently.
  unavailable,

  /// The user dismissed a picker instead of choosing from it.
  cancelled,

  /// Anything the classifier could not place. Never a passthrough of the raw text.
  unknown,
}

/// A media failure, as the UI is meant to receive it.
///
/// Two fields and nothing else. There is deliberately **no** field carrying the
/// platform's own text: a value that is never stored cannot be rendered by
/// accident, and the old build's `setMediaError(error.message)`
/// (`ChatCallWorkspace.tsx:352`) is what put `NotReadableError: Could not start
/// video source` in front of a Turkish user. The raw text goes to the
/// `MediaDiagnostics` sink the app wires to its log, not here.
final class MediaFault {
  const MediaFault(this.kind, this.source);

  final MediaFaultKind kind;

  final MediaSourceKind source;

  /// The user-facing line, always Turkish, always a constant from
  /// [MediaTexts]. Total: every `(kind, source)` pair is spelled out in [text],
  /// which is asserted to have exactly one entry per pair.
  String get message => text[(kind, source)] ?? MediaTexts.genericFailure;

  /// The whole table, keyed by the pair. Deliberately total rather than
  /// `switch`-ed so a test can assert that no pair is missing — the bug this
  /// table exists to prevent is a pair that quietly fell through to English.
  static const Map<(MediaFaultKind, MediaSourceKind), String>
  text = <(MediaFaultKind, MediaSourceKind), String>{
    (MediaFaultKind.permissionDenied, MediaSourceKind.microphone):
        MediaTexts.microphonePermissionDenied,
    (MediaFaultKind.permissionDenied, MediaSourceKind.camera):
        MediaTexts.cameraPermissionDenied,
    (MediaFaultKind.permissionDenied, MediaSourceKind.screen):
        MediaTexts.screenPermissionDenied,
    (MediaFaultKind.deviceNotFound, MediaSourceKind.microphone):
        MediaTexts.microphoneNotFound,
    (MediaFaultKind.deviceNotFound, MediaSourceKind.camera):
        MediaTexts.cameraNotFound,
    (MediaFaultKind.deviceNotFound, MediaSourceKind.screen):
        MediaTexts.screenNotFound,
    (MediaFaultKind.deviceBusy, MediaSourceKind.microphone):
        MediaTexts.microphoneBusy,
    (MediaFaultKind.deviceBusy, MediaSourceKind.camera): MediaTexts.cameraBusy,
    (MediaFaultKind.deviceBusy, MediaSourceKind.screen): MediaTexts.screenBusy,
    (MediaFaultKind.deviceNotReadable, MediaSourceKind.microphone):
        MediaTexts.microphoneNotReadable,
    (MediaFaultKind.deviceNotReadable, MediaSourceKind.camera):
        MediaTexts.cameraNotReadable,
    (MediaFaultKind.deviceNotReadable, MediaSourceKind.screen):
        MediaTexts.screenNotReadable,
    (MediaFaultKind.unsupported, MediaSourceKind.microphone):
        MediaTexts.microphoneUnsupported,
    (MediaFaultKind.unsupported, MediaSourceKind.camera):
        MediaTexts.cameraUnsupported,
    (MediaFaultKind.unsupported, MediaSourceKind.screen):
        MediaTexts.screenUnsupported,
    // The connection is one thing; which device was being asked for only
    // changes the noun in the unavailable sentences.
    (MediaFaultKind.unavailable, MediaSourceKind.microphone):
        MediaTexts.connectionNotReady,
    (MediaFaultKind.unavailable, MediaSourceKind.camera):
        MediaTexts.connectionNotReady,
    (MediaFaultKind.unavailable, MediaSourceKind.screen):
        MediaTexts.connectionNotReady,
    // A picker can only be dismissed where there is a picker. The other two
    // pairs cannot occur, and are spelled out anyway so the table stays
    // total and the test can insist on it.
    (MediaFaultKind.cancelled, MediaSourceKind.microphone):
        MediaTexts.microphoneUnknown,
    (MediaFaultKind.cancelled, MediaSourceKind.camera):
        MediaTexts.cameraUnknown,
    (MediaFaultKind.cancelled, MediaSourceKind.screen):
        MediaTexts.screenCancelled,
    (MediaFaultKind.unknown, MediaSourceKind.microphone):
        MediaTexts.microphoneUnknown,
    (MediaFaultKind.unknown, MediaSourceKind.camera): MediaTexts.cameraUnknown,
    (MediaFaultKind.unknown, MediaSourceKind.screen): MediaTexts.screenUnknown,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaFault && other.kind == kind && other.source == source;

  @override
  int get hashCode => Object.hash(kind, source);

  @override
  String toString() => 'MediaFault(${kind.name}, ${source.name})';
}

/// Where the platform's own English text goes.
///
/// Injected rather than logged inline so `lib/media` depends on no logging
/// package and so a test can assert that the raw text reached the sink and,
/// separately, that it reached nowhere near a [MediaFault].
typedef MediaDiagnostics = void Function(MediaFault fault, Object raw);

/// The classification table, in the order it is consulted.
///
/// Order matters and is asserted by a test: `deviceBusy` has to be tested
/// before `deviceNotReadable`, because a locked camera surfaces on Windows as
/// `NotReadableError` (libwebrtc maps a `SHARING_VIOLATION` capture start
/// failure onto the spec's "in use" name) and the *fix* the user needs is
/// "close the other app", not "restart the driver".
const List<(MediaFaultKind, List<String>)>
_mediaFaultTable = <(MediaFaultKind, List<String>)>[
  // -- device busy, first: see the note above about NotReadableError -----------
  (
    MediaFaultKind.deviceBusy,
    <String>[
      'sharing violation',
      'share violation',
      '0x80070020',
      'device in use',
      'device is in use',
      'already in use',
      'in use by another',
      'audclnt_e_',
      'devicebusyerror',
      'device is busy',
      'cannot start capture', // libwebrtc: a locked camera reaches us like this
      'used by another process',
      'another application',
      'başka bir uygulama',
    ],
  ),
  // -- permission denied -----------------------------------------------------
  (
    MediaFaultKind.permissionDenied,
    <String>[
      'notallowederror',
      'permissionerror',
      'mediadevicepermissionerror',
      'permission denied',
      'permissiondenied',
      'mediastreampermissionerror',
      'access is denied',
      'access denied',
      'eacces',
      '0x80070005',
      'denied',
      'not supported for security reasons',
      'securityerror',
      'notauthorizederror',
      'privilege',
      'izin verilmedi',
      'not permitted',
    ],
  ),
  // -- no device -------------------------------------------------------------
  (
    MediaFaultKind.deviceNotFound,
    <String>[
      'notfounderror',
      'devicesnotfounderror',
      'no specified device',
      'no available device',
      'no available capture device',
      'no device',
      'no capture device',
      'not found device id',
      'not found device',
      'device not found',
      'mf_e_notfound',
      '0x80070002',
      'source not found',
      'create desktopcapturer failed',
      'bulunamad',
    ],
  ),
  // -- opened but no media ---------------------------------------------------
  (
    MediaFaultKind.deviceNotReadable,
    <String>[
      'notreadableerror',
      'trackstart',
      'track start',
      'not readable',
      'unable to read',
      'could not start',
      'device has been removed',
      'device is not available',
      'device has been disabled',
      'device_not_available',
      'device_not_initialized',
      'mf_e_notinitialized',
      'mf_e_shutdown',
      '0x88890004',
      '0x8889000c',
      'videocapturemodule',
      'audiocapturemodule',
      'capture device',
      'gelmedi',
    ],
  ),
  // -- no backend at all -----------------------------------------------------
  (
    MediaFaultKind.unsupported,
    <String>[
      'missingpluginexception',
      'nosuchmethoderror',
      'unimplementederror',
      'notimplemented',
      'unimplemented',
      'not supported on this platform',
      'unsupported',
      'desteklenmiyor',
      'notavailable',
    ],
  ),
];

/// Classifies whatever `flutter_webrtc` or the OS threw into a Turkish [MediaFault].
///
/// ## Why `catch (Object error)` and not `on PlatformException`
///
/// `MediaDeviceNative.getUserMedia` and `getDisplayMedia` both end with
/// ```dart
/// } on PlatformException catch (e) {
///   throw 'Unable to getUserMedia: ${e.message}';
/// }
/// ```
/// (`flutter_webrtc/lib/src/native/mediadevices_impl.dart:48-50` and `:93-95`).
/// That is a raw Dart `String`, so `on PlatformException` does not catch it and a
/// caller that only handles `PlatformException` sees the error escape as a
/// string. Every entry point in `MediaController` therefore does
/// `catch (Object error)` and hands whatever arrived to this function, which
/// handles a `String`, a `PlatformException` (real `PlatformException`s *do*
/// arrive from `Helper.selectAudioInput`, which calls `WebRTC.invokeMethod`
/// directly), any other `Object`, and a web `DOMException`-shaped object whose
/// name is reachable through `toString()`.
///
/// [source] is required because the same exception name means different things
/// per call site; see [MediaSourceKind].
MediaFault classifyMediaFault(Object error, {required MediaSourceKind source}) {
  final String haystack = _flatten(error);

  // Checked before the table, not inside it. A dismissed picker and a stale
  // source id both mention the source list, and `source not found` is also a
  // needle of the "no device" row — so a share that never started for a
  // user-adjacent reason would be reported as "no display found", which is a lie
  // about something they did on purpose. See [_isPickerDismissal].
  if (source == MediaSourceKind.screen && _isPickerDismissal(haystack)) {
    return MediaFault(MediaFaultKind.cancelled, source);
  }

  // The permission row is consulted before the "no device" row on purpose. A
  // refused permission and an absent camera produce the same failure out of a
  // single combined `getUserMedia({audio: true, video: true})`, and "allow the
  // app" is the only fix that can help when both are in play.
  for (final (MediaFaultKind kind, List<String> needles) in _mediaFaultTable) {
    if (needles.any(haystack.contains)) {
      return MediaFault(kind, source);
    }
  }

  return MediaFault(MediaFaultKind.unknown, source);
}

/// Whether the text is the "picker was closed" shape rather than a refusal.
///
/// Only meaningful for a display capture. `AbortError` is the spec's name for
/// it, and `source not found` is what the plugin's Windows handler raises
/// (`common/cpp/src/flutter_screen_capture.cc:332`) when the cached source list
/// went stale between the enumeration and the capture — which is the user
/// having picked a window that has since been closed, so the same message.
/// Whether the text is the "the share was not started, and it was not the OS
/// refusing" shape.
///
/// Only meaningful for a display capture, and the two needles are the only two
/// ways that happens **on Windows**:
///
/// * `AbortError` — the spec's name for a dismissed picker
///   (`DOMException` from `getDisplayMedia`). A build with a native picker (web,
///   Android) reaches this; a Windows build does not, because there is no native
///   picker to dismiss — the application builds the list itself.
/// * `source not found!` — the plugin's own answer when the cached source list went
///   stale between the enumeration and the capture
///   (`common/cpp/src/flutter_screen_capture.cc:331-334`). The window the user
///   picked has been closed, which is user-adjacent and should not open a red
///   error box.
///
/// A `NotAllowedError` on the screen path is deliberately **not** here. In a browser
/// it is a dismissed picker, but on Windows there is no picker to dismiss, so it is
/// a real refusal by MF/DXGI and is reported as one. Getting this backwards would
/// silently swallow every genuine screen-capture permission problem.
bool _isPickerDismissal(String haystack) =>
    haystack.contains('aborterror') ||
    haystack.contains('cancelled') ||
    haystack.contains('canceled') ||
    haystack.contains('source not found');

/// Reduces anything throwable to one lowercase haystack.
///
/// Four shapes, because the plugin produces four: a raw `String`, a
/// `PlatformException` (whose `code` carries the plugin's own vocabulary and
/// whose `message` carries libwebrtc's), any other `Object` (whose `toString` is
/// the only text there is), and a web `DOMException` whose `name` is the whole
/// classification. Nothing here is ever shown to a user.
String _flatten(Object error) {
  final StringBuffer buffer = StringBuffer();
  if (error is PlatformException) {
    buffer.write(error.code);
    buffer.write(' ');
    buffer.write(error.message ?? '');
  } else {
    buffer.write(error.toString());
  }
  return buffer.toString().toLowerCase();
}
