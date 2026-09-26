import 'dart:async';

import 'display_source.dart';
import 'media_device.dart';
import 'media_fault.dart';

/// A sleep, injected so a watchdog's whole schedule runs in microseconds.
///
/// A function typedef rather than an interface because there is nothing to
/// configure and nothing to record beyond the requested durations — which is
/// exactly what `test/media` records.
typedef MediaDelay = Future<void> Function(Duration duration);

/// The production sleep.
Future<void> defaultMediaDelay(Duration duration) =>
    Future<void>.delayed(duration);

/// Every injected dependency of the media layer, as one value.
///
/// One bundle rather than four constructor parameters, so the seam is a single
/// thing a test can build and a single thing production supplies. A
/// `MediaController` that takes its capture, its senders and its stats as
/// separate arguments can be constructed with the test double for one of them
/// and the real device for another; this cannot.
final class MediaSeams {
  const MediaSeams({
    required this.capture,
    required this.senders,
    required this.stats,
    this.delay = defaultMediaDelay,
    this.diagnostics,
  });

  final MediaCapture capture;

  final MediaSenderRegistry senders;

  final MediaStatsProbe stats;

  /// The watchdog's sleep. Injected so a whole share schedule runs in
  /// microseconds; see [ScreenShareWatchdog] for why the budget is counted rather
  /// than timed.
  final MediaDelay delay;

  /// Where the platform's English text goes. Never a UI.
  ///
  /// Null in tests that do not assert on it, and the right default in production:
  /// dropping the raw text is safe, showing it is not.
  final MediaDiagnostics? diagnostics;
}

/// One captured local track, seen from outside the plugin.
///
/// `MediaStreamTrack` is an abstract class from `webrtc_interface`, so a fake is
/// legal Dart — but implementing it means implementing `getConstraints` and
/// `applyConstraints` as `UnimplementedError` throws, and a test that has to know
/// which of the plugin's members are pure is a test that will start lying. This
/// interface is the four operations MKVI actually performs.
abstract interface class MediaTrackHandle {
  String get id;

  /// `'audio'` or `'video'`.
  String get kind;

  String get label;

  /// Mutes the content without detaching the track.
  ///
  /// Distinct from detaching: a muted track still encodes silence and still
  /// keeps the sender's `framesEncoded` moving, which is what a muted
  /// microphone must do. Muting by `replaceTrack(null)` would make the peer see a
  /// broken track instead of a quiet one.
  bool get enabled;

  set enabled(bool value);

  /// Releases the underlying capture. Idempotent, and the only thing in this
  /// layer that can turn a camera light off.
  Future<void> stop();
}

/// One pre-negotiated sender, seen from outside the plugin.
abstract interface class MediaSenderHandle {
  /// The id the peer connection's stats reports this sender under. Used to match
  /// an `outbound-rtp` stats entry back to a sender.
  String get id;

  /// The `audio`, `camera` or `screen` slot this sender belongs to.
  String get slot;

  MediaTrackHandle? get track;

  /// Attaches [track], or detaches when it is `null`.
  ///
  /// A `null` argument is the whole mid-call attach/detach mechanism and is not
  /// a mistake to be defended against: `RTCRtpSender.replaceTrack(MediaStreamTrack?)`
  /// declares the parameter nullable precisely for this.
  Future<void> replaceTrack(MediaTrackHandle? track);
}

/// The three senders created once per connection.
///
/// Named, not indexed, because the *reason* there are three is that the screen
/// sender must never stand in for the camera one: both video sources can be live
/// at once and each needs its own stable sender. An index would let that be
/// re-broken by an off-by-one, and the failure would be a screen share silently
/// shown as the other person's face.
final class MediaSenderSet {
  const MediaSenderSet({
    required this.audio,
    required this.camera,
    required this.screen,
  });

  final MediaSenderHandle audio;

  final MediaSenderHandle camera;

  final MediaSenderHandle screen;
}

/// Where the three transceivers come from.
abstract interface class MediaSenderRegistry {
  /// Creates the audio, camera and screen transceivers as `sendrecv`, in that
  /// order, and returns their senders. Called exactly once per connection.
  ///
  /// This is the only negotiation this layer ever causes, and the reason is
  /// arithmetic rather than taste. A transceiver has to exist before the first
  /// offer, because adding one mid-call is a renegotiation, and recovering from
  /// a collision mid-call needs SDP `rollback` — which is an unverified upstream
  /// capability (flutter_webrtc issue #625, open since 2021). A layer that
  /// renegotiated would therefore depend on something nobody has proven works.
  ///
  /// Pre-creating all three at connection time removes the glare window on the
  /// media side entirely: there is nothing left to add later, so turning the
  /// camera on, starting a screen share and stopping either of them are all
  /// `replaceTrack` calls that need no offer at all. `MediaController`'s
  /// negotiation counter is the measurable form of that promise — it is 1 after
  /// `open()` and stays 1 for the life of the call.
  Future<MediaSenderSet> open();

  /// Releases the registry's own resources.
  ///
  /// Never stops tracks. The controller owns the track ledger, so a caller
  /// cannot stop a track twice and a half-stopped call cannot be papered over.
  Future<void> close();

  /// Fires when the connection wants a new offer.
  ///
  /// [MediaController] subscribes and then never acts on it, which is the point:
  /// it turns "we promise attach and detach never renegotiate" from a claim in a
  /// comment into a number a test can read.
  Stream<void> get renegotiationNeeded;
}

/// Reads one number off the connection: how many frames this sender has encoded.
///
/// ## The only signal that exists for upstream issue #2137
///
/// `getDisplayMedia` resolves successfully with a track that will never produce
/// a frame when the shared window is not foreground, because the plugin
/// discards the return value of `Start()` and reports success anyway:
/// ```cpp
/// desktop_capturer->Start(uint32_t(fps));
/// result->Success(EncodableValue(params));
/// ```
/// (`flutter_webrtc/common/cpp/src/flutter_screen_capture.cc:373-375`). No
/// callback, no future, no exception, no `readyState` change. The only
/// observable that ever moves is `outbound-rtp.framesEncoded` in the RTP stats,
/// so that is what the watchdog reads.
///
/// `0` is a legitimate answer for a whole second or two after attach, which is
/// why [ScreenShareWatchdog] treats it as "not yet" and not as "broken".
abstract interface class MediaStatsProbe {
  /// `outbound-rtp.framesEncoded` for the sender with [senderId].
  ///
  /// Returns `0` when the entry is absent, which is indistinguishable from "the
  /// encoder has not started" and is handled the same way.
  Future<int> framesEncoded(String senderId);
}

/// What to ask the OS for, in MKVI's own vocabulary.
final class MediaCaptureRequest {
  const MediaCaptureRequest({
    this.audio = false,
    this.video = false,
    this.microphoneDeviceId,
    this.cameraDeviceId,
  });

  final bool audio;

  final bool video;

  /// Only ever a value the controller has already found in
  /// [MediaDeviceSnapshot]. See [MediaDeviceSnapshot.byId] for why.
  final String? microphoneDeviceId;

  final String? cameraDeviceId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaCaptureRequest &&
          other.audio == audio &&
          other.video == video &&
          other.microphoneDeviceId == microphoneDeviceId &&
          other.cameraDeviceId == cameraDeviceId;

  @override
  int get hashCode =>
      Object.hash(audio, video, microphoneDeviceId, cameraDeviceId);

  @override
  String toString() =>
      'MediaCaptureRequest(audio: $audio, video: $video, '
      'mic: $microphoneDeviceId, cam: $cameraDeviceId)';
}

/// The tracks one `getUserMedia` produced.
final class CapturedMedia {
  const CapturedMedia(this.tracks);

  final List<MediaTrackHandle> tracks;

  /// The microphone track, or `null` when none came back.
  ///
  /// A `null` here with [MediaCaptureRequest.audio] requested is a real,
  /// observable failure and not an edge case — see [MediaController.startCall].
  MediaTrackHandle? get firstAudio {
    for (final MediaTrackHandle track in tracks) {
      if (track.kind == 'audio') return track;
    }
    return null;
  }

  /// The camera track, or `null` when none came back.
  MediaTrackHandle? get firstVideo {
    for (final MediaTrackHandle track in tracks) {
      if (track.kind == 'video') return track;
    }
    return null;
  }
}

/// The whole capture surface, injected.
abstract interface class MediaCapture {
  Future<CapturedMedia> getUserMedia(MediaCaptureRequest request);

  /// Starts display capture of [source].
  ///
  /// There is no [sourceId]-less overload because there is no native picker to
  /// resolve one: the caller enumerates with [displaySources] and chooses.
  Future<CapturedMedia> getDisplayMedia(DisplaySource source);

  Future<MediaDeviceSnapshot> enumerateDevices();

  /// Re-points the *existing* microphone capture at [deviceId].
  ///
  /// Re-pointing rather than re-capturing is not a shortcut, it is the only
  /// correct option: the native handler validates the id against the recording
  /// device list and fails loudly
  /// (`common/cpp/src/flutter_media_stream.cc:504-527`), whereas a fresh
  /// `getUserMedia` with an unknown audio `deviceId` succeeds with the previous
  /// microphone still selected.
  Future<void> selectAudioInput(String deviceId);

  /// Every shareable screen and window, in the plugin's own order.
  Future<List<DisplaySource>> displaySources();

  /// Fires on every OS device add/remove notification, carrying nothing.
  ///
  /// Fires more than once per physical change and says nothing about which
  /// device; the controller re-enumerates and diffs.
  Stream<void> get deviceChanges;
}
