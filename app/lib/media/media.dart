/// The media layer: capture, publish, and the first-frame watchdog.
///
/// One controller, [MediaController], owns the three pre-negotiated senders and
/// every local track. It is the only thing that talks to `flutter_webrtc`, and
/// only through the interfaces in `media_seam.dart`, so `test/media` runs the
/// whole call ladder with no hardware.
///
/// The TypeScript original had none of this: `ChatCallWorkspace.tsx` called
/// `navigator.mediaDevices` itself, `App.tsx` called the senders itself, and
/// nothing in between owned a track. [MediaController] is that missing middle.
///
/// ## The order the owner of a connection must run things in
///
/// | step | what happens |
/// |---|---|
/// | peer connection built | `MediaController.open()` — the three `sendrecv` transceivers, and the one and only renegotiation |
/// | peer accepts a call | `startCall(video:)` — the ladder; a video request either gets a camera or is **reported** |
/// | camera button mid-call | `enableCamera()` / `disableCamera()` — `replaceTrack` only |
/// | share button mid-call | `startScreenShare()` / `stopScreenShare()` — `replaceTrack` only, watchdog armed |
/// | device picker | `switchMicrophone()` — `selectAudioInput`, validated natively |
/// | camera picker | `switchCamera()` — re-capture and `replaceTrack`, because `Helper.switchCamera` cannot work on Windows |
/// | a device is unplugged | the [MediaController.deviceChanges] stream, once per real change |
/// | call ended | `stop()` — detach all three senders and stop every track created |
/// | connection closed | `dispose()` |
///
/// `stop()` and `dispose()` are the answer to the leak the old build had: a
/// camera left on after a call. There is one track ledger, and every track the
/// controller creates goes into it before anything can fail.
///
/// ## Upstream defects, and where they are handled
///
/// | issue | what it is | handled in |
/// |---|---|---|
/// | #2137 | `getDisplayMedia` resolves with a track that never produces a frame when the window is not foreground | `screen_share_watchdog.dart`, armed from `MediaController.startScreenShare` |
/// | #2205 | HDR displays capture with wrong colours; no WGC backend | **not solved, not solvable from Dart** — see `webrtc_media_backend.dart` |
/// | #625 | SDP `rollback` unverified upstream | designed around: the three transceivers exist from `open()`, so no media operation can produce an offer |
/// | — | `getUserMedia`/`getDisplayMedia` throw a raw Dart `String`, not a `PlatformException` | `media_fault.dart`, `catch (Object)` at every call site |
/// | — | a missing device resolves with **no** track and no error | `MediaController._attempt` inspects what came back |
/// | — | `Helper.switchCamera` ignores `deviceId` and its handler is `NotImplemented()` on Windows | `MediaController.switchCamera` re-captures |
library;

export 'display_source.dart';
export 'media_controller.dart';
export 'media_device.dart';
export 'media_fault.dart';
export 'media_result.dart';
export 'media_seam.dart';
export 'media_state.dart';
export 'media_texts.dart';
export 'screen_share_watchdog.dart';
export 'webrtc_media_backend.dart';
