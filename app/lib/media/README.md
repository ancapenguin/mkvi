# `lib/media` — capture, publish, and the first-frame watchdog

One controller, `MediaController`, owns the three pre-negotiated senders and every
local track. It is the only thing that touches `flutter_webrtc`, and only through
the interfaces in `media_seam.dart`, so `test/media` runs the whole call ladder with
no camera, no microphone, no peer connection and no second machine.

The Tauri build had none of this. `ChatCallWorkspace.tsx` called
`navigator.mediaDevices` itself, `App.tsx` called the senders itself, and nothing in
between owned a track.

## The order the owner of a connection must run things in

| step | what happens |
|---|---|
| peer connection built | `open()` — the three `sendrecv` transceivers, and the one and only renegotiation |
| peer accepts a call | `startCall(video:)` — the ladder; a video request either gets a camera or is **reported** |
| camera button mid-call | `enableCamera()` / `disableCamera()` — `replaceTrack` only |
| share button mid-call | `startScreenShare()` / `stopScreenShare()` — `replaceTrack` only, watchdog armed |
| device picker, microphone | `switchMicrophone()` — `selectAudioInput`, validated natively |
| device picker, camera | `switchCamera()` — re-capture and `replaceTrack`; `Helper.switchCamera` cannot work on Windows |
| a device is unplugged | the `deviceChanges` stream, once per real change |
| call ended | `stop()` — detach all three senders and stop every track created |
| connection closed | `dispose()` |

No public method throws. Every outcome is a value: `MediaSucceeded` / `MediaFailed`,
`MediaCallLive` / `MediaCallFailed`, `MediaScreenShareStarted` /
`MediaScreenShareFailed`. A capture failure is a normal answer, not an exception,
because every one of them ends in the same Turkish media-error box and a caller who
has to remember a `try` around each one will forget one.

## The ladder, and the rung that was deleted

`ChatCallWorkspace.tsx:313-318` had three rungs. The third was
`{audio: true, video: false}` and its only sign was the warning "Kamera bulunamadı;
arama yalnızca sesli başlayacak." A user who pressed the video button got a silent
audio call and one line of text, in a box that also carries every other error.

| rung | request | outcome |
|---|---|---|
| 1 | microphone + camera | the call, as asked for |
| 2 | camera only | video-only, with `MediaTexts.microphoneMissingInVideoCall` |
| — | ~~microphone only~~ | **removed** |

When both rungs fail the call **fails**, with a Turkish reason. The degradation that
survives is the one whose effect the user can still see: a video call whose
microphone is missing continues as a video call and says so.

## Two things the browser got for free

**A missing device does not throw here.** `GetUserVideo` returns early, with no track
and no error, when the video device module reports no devices or refuses to create a
capturer (`flutter_webrtc/common/cpp/src/flutter_media_stream.cc:382-393`), and
`GetUserMedia` then reports success with an empty `videoTracks` array (`:62-77`). A
ladder that only caught would see rung 1 "succeed" with no camera and publish nothing
— indistinguishable, from the caller's side, from a camera that was never asked for.
So `MediaController._attempt` **inspects** what came back, and a requested-but-absent
track becomes a real fault.

**A track carries no device id.** The plugin puts the track's own fresh UUID in both
`id` and `label` (`:408-410`). The only thing a track can be matched back to hardware
with is the device manager's friendly name, so `MediaDeviceSnapshot.idForLabel` does
that, and answers `null` for an ambiguous name rather than picking one. The id *is*
validated before it reaches the native layer, because an unmatched `deviceId` there is
accepted and silently keeps the previous device (`:219-228`, `:267-269`).

## Upstream defects, and where each is handled

| issue | what it is | handled in |
|---|---|---|
| **#2137** | `getDisplayMedia` resolves with a track that never produces a frame when the shared window is not foreground. Root cause: `RTCDesktopCapturer::Start`'s return value is discarded and success reported anyway (`common/cpp/src/flutter_screen_capture.cc:373-375`) | `screen_share_watchdog.dart`; the phase becomes `waitingForFirstFrame` the instant the track is attached, and becomes `stalled` if `outbound-rtp.framesEncoded` never moves |
| **#2205** | HDR displays capture with wrong colours; the DXGI capturer clips to 8-bit BGRA and there is no WGC backend | **not solved, and not solvable from Dart.** Documented in `webrtc_media_backend.dart`; nothing in this layer pretends otherwise |
| **#625** | SDP `rollback` is unverified upstream, and `peer-transport.ts:322` relies on it | designed around: the three transceivers exist from `open()`, so no media operation can produce an offer and the glare window a rollback would need does not exist on the media side. `MediaController.negotiationCount` is 1 after `open()` and 1 forever after |
| — | `getUserMedia` / `getDisplayMedia` throw a **raw Dart `String`**, not a `PlatformException` (`lib/src/native/mediadevices_impl.dart:48-50`, `:93-95`) | `media_fault.dart`; every call site is `catch (Object error)`. `on PlatformException` would not catch it |
| — | `Helper.switchCamera` drops its `deviceId` off the web branch (`lib/src/helper.dart:65-70`) and its handler answers `NotImplemented()` (`common/cpp/src/flutter_media_stream.cc:630-634`) | `MediaController.switchCamera` re-captures and `replaceTrack`s |
| — | `ondevicechange` carries no payload and on Windows is raised by the **audio** device module alone (`common/cpp/src/flutter_webrtc_base.cc:88-92`) | `MediaController` re-enumerates and diffs, serialised, so one physical change is one line |
| — | an English exception message in a Turkish UI (`setMediaError(error.message)` at `ChatCallWorkspace.tsx:352`, `:368`, `:376`, `:419`, `:441`) | `MediaFault` has **no** field for the platform's own text. A value that is never stored cannot be rendered by accident; the raw text goes to the injected `MediaDiagnostics` sink |

## The track ledger

`_owned` holds every track the controller created and has not yet stopped. A track is
added the instant the OS hands it over — before anything can fail — and removed the
instant it is stopped. A track the controller does not know about is a track it can
never switch off, which is the leak the old build had: `stopStream` ran from three
`useEffect`s in `ChatCallWorkspace.tsx`, one of them keyed on
`callStatus === "ended"`, so a decline, a ring timeout or a failed publish left the
camera live.

`stop()` drains the ledger **even when every `replaceTrack` throws**, and a track
whose `stop()` throws does not skip the next one. `test/media`'s `orphanedTracks` is
the assertion: a live track with no sender behind it.

## Turkish

Every user-facing string is a constant in `media_texts.dart`. Nothing in `lib/media`
builds a message by interpolation, and `media_fault.dart`'s table is total — one entry
per `(MediaFaultKind, MediaSourceKind)` pair, asserted by a test — so a pair cannot
quietly fall through to English. Comments are English; strings the user sees are
Turkish.

## Tests

`test/media` needs no hardware and exercises no hardware. `test/media/support/media_fakes.dart`
fakes every seam, and the suites drive the ladder, the `replaceTrack` discipline, the
ledger, the watchdog's poll schedule, the classifier and the device-change diff from
scripted OS answers.
