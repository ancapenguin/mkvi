import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import 'display_source.dart';
import 'media_device.dart';
import 'media_seam.dart';

/// The production [MediaCapture], [MediaSenderRegistry] and [MediaStatsProbe],
/// over `flutter_webrtc` 1.6.2+hotfix.3.
///
/// This is the **only** file in `lib/media` that imports the plugin. Everything
/// else talks to the interfaces in `media_seam.dart`, which is what lets
/// `test/media` exercise the whole ladder, the watchdog and the track ledger with
/// no camera, no microphone, no peer connection and no second machine.
///
/// ## Constraints, and the `dynamic` rule
///
/// The plugin's capture API is `getUserMedia(Map<String, dynamic>)`. This adapter
/// builds `Map<String, Object?>` instead and passes it straight through: `Object?`
/// and `dynamic` are both top types, so the two are mutually assignable, and the
/// values that cross the method channel are read back on the C++ side as
/// `EncodableValue`, never as a Dart `dynamic`. Nothing else in `lib/media`
/// mentions `dynamic` at all, and [MediaStatsProbe] reads the one genuinely
/// `Map<dynamic, dynamic>` in the plugin (`StatsReport.values`) through an
/// `Object?` local.
///
/// ## Upstream defects this file is shaped around
///
/// * **#2137** — `getDisplayMedia` can resolve with a track that never produces a
///   frame, because `RTCDesktopCapturer::Start`'s return value is discarded and
///   success is reported regardless
///   (`common/cpp/src/flutter_screen_capture.cc:373-375`). There is no signal in
///   the plugin's API to read, which is why the watchdog is driven from
///   [MediaStatsProbe]. What this adapter *can* do is never treat a resolved
///   `getDisplayMedia` as "live", and it does.
/// * **#2205** — HDR displays are captured with wrong colours, because the DXGI
///   desktop capturer clips to 8-bit BGRA and there is no Windows Graphics
///   Capture backend. **Not worked around here and not worked around anywhere in
///   this port.** There is no correct answer available from Dart: the user sees
///   washed-out video on an HDR display and no MKVI code can change that. Claiming
///   otherwise would be the only dishonest thing in the layer.
/// * **#625** — SDP `rollback` is unverified upstream. Nothing here needs it,
///   because the three transceivers are created once by [open] and no media method
///   adds or removes one. See [MediaSenderRegistry.open].
/// * `Helper.switchCamera` is unusable on Windows: it drops its `deviceId` off the
///   web branch and sends only `{'trackId': …}`
///   (`flutter_webrtc/lib/src/helper.dart:65-70`), and the handler that receives
///   it answers `NotImplemented()`
///   (`common/cpp/src/flutter_media_stream.cc:630-634`). `MediaController
///   .switchCamera` re-captures instead; documented at the call site.
/// * `getUserMedia` and `getDisplayMedia` throw a **raw Dart `String`**, not a
///   `PlatformException`
///   (`flutter_webrtc/lib/src/native/mediadevices_impl.dart:48-50` and `:93-95`).
///   Nothing here catches; `MediaController` classifies with `catch (Object)`.
///
/// ## One plugin behaviour this adapter refuses to hide
///
/// A missing device does not throw. `GetUserVideo` returns early, with no track and
/// no error, when the video device module reports no devices or refuses to create
/// a capturer (`common/cpp/src/flutter_media_stream.cc:382-393`), and
/// `GetUserMedia` then reports success with an empty `videoTracks` array (`:62-77`).
/// So [getUserMedia] returns whatever it was handed, tracks and all, and
/// `MediaController` is the one that decides a requested-but-absent track is a
/// failure. Turning that into an exception here would put the one judgement that
/// matters in the one file that cannot be tested without hardware.
final class WebRtcMediaBackend
    implements MediaCapture, MediaSenderRegistry, MediaStatsProbe {
  WebRtcMediaBackend({required webrtc.RTCPeerConnection connection})
    : _peerConnection = connection;

  final webrtc.RTCPeerConnection _peerConnection;

  /// Every sender this backend handed out, by id, so [framesEncoded] can find the
  /// `outbound-rtp` stats entry that belongs to it.
  final Map<String, webrtc.RTCRtpSender> _sendersById =
      <String, webrtc.RTCRtpSender>{};

  final StreamController<void> _renegotiations =
      StreamController<void>.broadcast(sync: true);
  final StreamController<void> _deviceChanges =
      StreamController<void>.broadcast(sync: true);

  bool _listening = false;
  bool _closed = false;

  // ---------------------------------------------------------------------------
  // MediaSenderRegistry
  // ---------------------------------------------------------------------------

  /// Creates the audio, camera and screen transceivers, in that order.
  ///
  /// The order and the `sendrecv` direction are the port of
  /// `peer-transport.ts:78-80`, and they are load-bearing:
  ///
  /// ```dart
  /// this.audioTransceiver = this.pc.addTransceiver("audio", { direction: "sendrecv" });
  /// this.cameraTransceiver = this.pc.addTransceiver("video", { direction: "sendrecv" });
  /// this.screenTransceiver = this.pc.addTransceiver("video", { direction: "sendrecv" });
  /// ```
  ///
  /// "Keep stable, dedicated senders. In particular the screen sender must not
  /// replace the camera sender, because both video sources may be live at once."
  /// Two `video` transceivers with nothing attached are an answer carrying two
  /// empty `m=` sections, and neither side renegotiates again — which is what makes
  /// turning the camera on during a voice call a `replaceTrack`.
  ///
  /// Creating a transceiver raises `onRenegotiationNeeded` — the plugin's spelling,
  /// and not `onNegotiationNeeded` — which is expected exactly once, here.
  /// `MediaController` counts it and does nothing else.
  @override
  Future<MediaSenderSet> open() async {
    _startListening();

    final webrtc.RTCRtpTransceiver audio = await _peerConnection.addTransceiver(
      kind: webrtc.RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: webrtc.RTCRtpTransceiverInit(
        direction: webrtc.TransceiverDirection.SendRecv,
      ),
    );
    final webrtc.RTCRtpTransceiver camera = await _peerConnection
        .addTransceiver(
          kind: webrtc.RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: webrtc.RTCRtpTransceiverInit(
            direction: webrtc.TransceiverDirection.SendRecv,
          ),
        );
    final webrtc.RTCRtpTransceiver screen = await _peerConnection
        .addTransceiver(
          kind: webrtc.RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: webrtc.RTCRtpTransceiverInit(
            direction: webrtc.TransceiverDirection.SendRecv,
          ),
        );

    return MediaSenderSet(
      audio: _wrap(audio.sender, 'audio'),
      camera: _wrap(camera.sender, 'camera'),
      screen: _wrap(screen.sender, 'screen'),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sendersById.clear();
    webrtc.navigator.mediaDevices.ondevicechange = null;
    _peerConnection.onRenegotiationNeeded = null;
    await _renegotiations.close();
    await _deviceChanges.close();
  }

  @override
  Stream<void> get renegotiationNeeded => _renegotiations.stream;

  void _startListening() {
    if (_listening) return;
    _listening = true;
    _peerConnection.onRenegotiationNeeded = () {
      if (!_renegotiations.isClosed) _renegotiations.add(null);
    };
    // The plugin's own device notification. On Windows it is raised by the *audio*
    // device module alone (`common/cpp/src/flutter_webrtc_base.cc:88-92`) and can
    // fire several times for one change, so it is treated as "something moved, go
    // and look" and never as the change itself.
    webrtc.navigator.mediaDevices.ondevicechange = (Object? _) {
      if (!_deviceChanges.isClosed) _deviceChanges.add(null);
    };
  }

  // ---------------------------------------------------------------------------
  // MediaCapture
  // ---------------------------------------------------------------------------

  @override
  Future<CapturedMedia> getUserMedia(MediaCaptureRequest request) async {
    // `Map<String, Object?>` where the plugin asks for `Map<String, dynamic>`;
    // see the class doc for why that is not a `dynamic` in disguise.
    final Map<String, Object?> constraints = <String, Object?>{
      'audio': _deviceConstraint(request.microphoneDeviceId),
      'video': _deviceConstraint(request.cameraDeviceId),
    };
    final webrtc.MediaStream stream = await webrtc.navigator.mediaDevices
        .getUserMedia(constraints);
    return _wrapStream(stream);
  }

  @override
  Future<CapturedMedia> getDisplayMedia(DisplaySource source) async {
    final Map<String, Object?> constraints = <String, Object?>{
      // Display audio would need a second output loopback the plugin does not
      // expose, and the TypeScript original asked for `audio: false` too
      // (`peer-transport.ts:167`).
      'audio': false,
      'video': <String, Object?>{
        // The shape `FlutterScreenCapture::GetDisplayMedia` reads:
        // `video.deviceId.exact` and `video.mandatory.frameRate`
        // (`common/cpp/src/flutter_screen_capture.cc:186-205`). A wrong shape here
        // is the `Bad Arguments` / `source not found!` error at `:331-334`.
        'deviceId': <String, Object?>{'exact': source.id},
        'mandatory': <String, Object?>{'frameRate': 30},
      },
    };
    final webrtc.MediaStream stream = await webrtc.navigator.mediaDevices
        .getDisplayMedia(constraints);
    return _wrapStream(stream);
  }

  @override
  Future<MediaDeviceSnapshot> enumerateDevices() async {
    final List<webrtc.MediaDeviceInfo> devices = await webrtc
        .navigator
        .mediaDevices
        .enumerateDevices();
    final List<MediaDevice> microphones = <MediaDevice>[];
    final List<MediaDevice> cameras = <MediaDevice>[];
    for (final webrtc.MediaDeviceInfo device in devices) {
      final MediaDeviceKind? kind = switch (device.kind) {
        'audioinput' => MediaDeviceKind.microphone,
        'videoinput' => MediaDeviceKind.camera,
        // `audiooutput` is not a capture input, and MKVI has no output picker:
        // playback belongs to the peer connection's own audio track.
        _ => null,
      };
      if (kind == null) continue;
      final MediaDevice value = MediaDevice(
        id: device.deviceId,
        label: device.label,
        kind: kind,
      );
      if (kind == MediaDeviceKind.microphone) {
        microphones.add(value);
      } else {
        cameras.add(value);
      }
    }
    return MediaDeviceSnapshot(
      microphones: List<MediaDevice>.unmodifiable(microphones),
      cameras: List<MediaDevice>.unmodifiable(cameras),
    );
  }

  @override
  Future<void> selectAudioInput(String deviceId) =>
      // The one validated device switch on Windows: it walks the recording device
      // list and fails with `Not found device id: …`
      // (`common/cpp/src/flutter_media_stream.cc:504-527`). It also raises a real
      // `PlatformException`, because `Helper.selectAudioInput` calls
      // `WebRTC.invokeMethod` directly rather than through the wrapper that
      // flattens failures into a `String`.
      webrtc.Helper.selectAudioInput(deviceId);

  @override
  Future<List<DisplaySource>> displaySources() async {
    final List<webrtc.DesktopCapturerSource> sources = await webrtc
        .desktopCapturer
        .getSources(
          types: <webrtc.SourceType>[
            webrtc.SourceType.Screen,
            webrtc.SourceType.Window,
          ],
        );
    return List<DisplaySource>.unmodifiable(
      sources.map(
        (webrtc.DesktopCapturerSource source) => DisplaySource(
          id: source.id,
          name: source.name,
          kind: switch (source.type) {
            webrtc.SourceType.Screen => DisplaySourceKind.screen,
            webrtc.SourceType.Window => DisplaySourceKind.window,
          },
        ),
      ),
    );
  }

  @override
  Stream<void> get deviceChanges => _deviceChanges.stream;

  // ---------------------------------------------------------------------------
  // MediaStatsProbe
  // ---------------------------------------------------------------------------

  /// The only signal that exists for upstream issue #2137.
  ///
  /// Reads `outbound-rtp.framesEncoded` for one sender. A resolved `getDisplayMedia`
  /// whose window is in the background leaves this at zero forever while the
  /// plugin reports no error of any kind, so this number is the only difference
  /// between a working share and a dead one.
  @override
  Future<int> framesEncoded(String senderId) async {
    final webrtc.RTCRtpSender? sender = _sendersById[senderId];
    if (sender == null) return 0;
    final List<webrtc.StatsReport> reports = await sender.getStats();
    for (final webrtc.StatsReport report in reports) {
      if (report.type != 'outbound-rtp') continue;
      // `StatsReport.values` is `Map<dynamic, dynamic>` because the platform
      // channel is. Read through an `Object?` so no `dynamic` enters this layer;
      // anything that is not a number is "no frames yet".
      final Object? encoded = report.values['framesEncoded'];
      if (encoded is num) return encoded.toInt();
    }
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Adapters
  // ---------------------------------------------------------------------------

  MediaSenderHandle _wrap(webrtc.RTCRtpSender sender, String slot) {
    _sendersById[sender.senderId] = sender;
    return _SenderAdapter(sender, slot);
  }

  CapturedMedia _wrapStream(webrtc.MediaStream stream) => CapturedMedia(
    List<MediaTrackHandle>.unmodifiable(
      stream.getTracks().map((webrtc.MediaStreamTrack t) => _WebrtcTrack(t)),
    ),
  );

  /// `true` when the OS should use its default device, a constraint map when the
  /// caller named one.
  ///
  /// Only ever called with an id `MediaController` has already found in
  /// `enumerateDevices`; see `MediaDeviceSnapshot.byId` for what happens if a
  /// caller skips that check.
  static Object? _deviceConstraint(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) return true;
    return <String, Object?>{'deviceId': deviceId};
  }
}

/// One of the three senders, with the plugin's `RTCRtpSender` behind it.
final class _SenderAdapter implements MediaSenderHandle {
  _SenderAdapter(this._sender, this.slot);

  final webrtc.RTCRtpSender _sender;

  @override
  final String slot;

  @override
  String get id => _sender.senderId;

  @override
  MediaTrackHandle? get track {
    final webrtc.MediaStreamTrack? native = _sender.track;
    return native == null ? null : _WebrtcTrack(native);
  }

  /// The only write path to a sender in `lib/media`.
  ///
  /// A `null` [track] is a detach, which `RTCRtpSender.replaceTrack` declares
  /// nullable precisely for this, and which is how the camera is turned off
  /// mid-call without renegotiating.
  @override
  Future<void> replaceTrack(MediaTrackHandle? track) async {
    final webrtc.MediaStreamTrack? native = track is _WebrtcTrack
        ? track.native
        : null;
    if (track != null && native == null) {
      // Raised as a raw `String` on purpose: it is the same shape the plugin
      // raises from `getUserMedia` when a device cannot be opened, so a caller
      // that classifies one and not the other is the bug this layer exists to
      // prevent.
      throw 'A track from another source reached the WebRTC sender';
    }
    await _sender.replaceTrack(native);
  }
}

/// One plugin track behind the four operations `lib/media` performs.
final class _WebrtcTrack implements MediaTrackHandle {
  _WebrtcTrack(this.native);

  final webrtc.MediaStreamTrack native;

  @override
  String get id => native.id ?? '';

  @override
  String get kind => native.kind ?? '';

  @override
  String get label => native.label ?? '';

  @override
  bool get enabled => native.enabled;

  @override
  set enabled(bool value) => native.enabled = value;

  @override
  Future<void> stop() => native.stop();

  @override
  String toString() => 'WebrtcTrack($id, $kind)';
}
