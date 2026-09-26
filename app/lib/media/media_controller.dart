import 'dart:async';

import 'display_source.dart';
import 'media_device.dart';
import 'media_fault.dart';
import 'media_result.dart';
import 'media_seam.dart';
import 'media_state.dart';
import 'media_texts.dart';
import 'screen_share_watchdog.dart';

/// Owns the three pre-negotiated senders and every local track the process owns.
///
/// ## What it is for
///
/// A camera API plus a set of senders, with nothing in between holding a track,
/// has three live failure modes, and each is answered by a decision in this file
/// rather than by a comment:
///
/// 1. **A camera left on after the call.** Stopping streams from wherever the
///    call happens to end means a decline, a ring timeout or a failed publish can
///    each take a different path and any of them can miss. Here there is one
///    ledger ([_owned]) and one drain ([stop]), and every track the controller ever
///    creates goes into it before anything can fail.
/// 2. **A requested video call silently became audio-only.** A capture ladder
///    whose last rung is `{audio: true, video: false}` downgrades the user's
///    request, and if the only warning is buried in a box that also carries every
///    other error, the downgrade is invisible. See [startCall].
/// 3. **An English exception in a Turkish UI.** See [classifyMediaFault].
///
/// ## The one rule about negotiation
///
/// Attach and detach are `replaceTrack`, and nothing else. The three transceivers
/// exist from [open] and no media method adds, removes or reconfigures one, so no
/// media method can ever produce an offer — which is what lets the call machine
/// emit a mid-call `upgradeToVideo` with **no** accompanying `SendFrame`, and which
/// is also why upstream issue #625 (SDP `rollback` unverified) does not reach this
/// layer: the glare window that would need a rollback does not exist on the media
/// side. [negotiationCount] exists so that promise is a number.
final class MediaController {
  /// Creates a controller. Nothing is captured and no device is opened until
  /// [open], and then [startCall].
  MediaController({
    required MediaSeams seams,
    Duration firstFrameTimeout = const Duration(seconds: 4),
    Duration firstFramePollInterval = const Duration(milliseconds: 500),
  }) : _seams = seams,
       _watchdog = ScreenShareWatchdog(
         seams: seams,
         firstFrameTimeout: firstFrameTimeout,
         pollInterval: firstFramePollInterval,
       ) {
    _watchdogSubscription = _watchdog.phases.listen(_onScreenPhase);
  }

  final MediaSeams _seams;
  final ScreenShareWatchdog _watchdog;

  late final StreamSubscription<ScreenSharePhase> _watchdogSubscription;

  /// Every track this controller created and has not yet stopped.
  ///
  /// A track is added the instant the OS hands it over and removed the instant it
  /// is stopped, so the list is exactly "the cameras and microphones that are still
  /// on". A track the controller does not know about is a track it can never switch
  /// off, which is the leak the old build had.
  final List<MediaTrackHandle> _owned = <MediaTrackHandle>[];

  MediaTrackHandle? _audioTrack;
  MediaTrackHandle? _cameraTrack;
  MediaTrackHandle? _screenTrack;

  MediaSenderSet? _senders;
  MediaDeviceSnapshot _devices = const MediaDeviceSnapshot();
  MediaState _state = const MediaState();

  final StreamController<MediaState> _states =
      StreamController<MediaState>.broadcast(sync: true);
  final StreamController<MediaDevicesChanged> _deviceEvents =
      StreamController<MediaDevicesChanged>.broadcast(sync: true);
  final StreamController<int> _negotiationEvents =
      StreamController<int>.broadcast(sync: true);

  StreamSubscription<void>? _deviceSubscription;
  StreamSubscription<void>? _negotiationSubscription;

  /// Serialises every public operation, so an `enableCamera` still awaiting the OS
  /// cannot be resurrected by a `stop` that overtook it.
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;
  int _negotiationCount = 0;

  // ---------------------------------------------------------------------------
  // Reading the controller
  // ---------------------------------------------------------------------------

  /// The whole state, as an immutable value.
  MediaState get state => _state;

  /// The state, whenever it changes.
  Stream<MediaState> get states => _states.stream;

  /// A real device-set change: something plugged in, or something was unplugged.
  ///
  /// Fires **once per change**, not once per OS notification — see
  /// [MediaDevicesChanged] for why the plugin's own event cannot be used directly.
  Stream<MediaDevicesChanged> get deviceChanges => _deviceEvents.stream;

  /// How many times the connection has asked for a new offer since [open].
  ///
  /// 1 after [open], and 1 forever after. Every mid-call attach, detach, mute,
  /// camera switch and screen share leaves it alone; that is the whole design, and
  /// this is where a test reads it.
  int get negotiationCount => _negotiationCount;

  /// The same number, as it changes.
  Stream<int> get negotiations => _negotiationEvents.stream;

  /// The watchdog, exposed so a debug surface can show its own view.
  ScreenShareWatchdog get watchdog => _watchdog;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Creates the audio, camera and screen transceivers and starts listening for
  /// device changes. Called once, by whoever owns the peer connection, at the
  /// moment the connection is built.
  ///
  /// This is the only point at which a renegotiation is expected, because it is the
  /// only point at which a transceiver is created.
  Future<MediaOutcome> open() => _serialized(() async {
    if (_disposed) return MediaFailed(_unavailable(MediaSourceKind.camera));
    if (_senders != null) return const MediaSucceeded();
    // Listeners go on **before** the transceivers are created. Creating a
    // transceiver is what raises the renegotiation, so a listener attached after
    // the fact can miss the one event this layer ever causes — and a
    // [negotiationCount] that under-counts is worse than none, because it looks
    // like evidence.
    _negotiationSubscription = _seams.senders.renegotiationNeeded.listen((_) {
      _negotiationCount += 1;
      if (_negotiationEvents.hasListener) {
        _negotiationEvents.add(_negotiationCount);
      }
    });
    _deviceSubscription = _seams.capture.deviceChanges.listen(
      // Queued, not just `unawait`ed. The OS fires several notifications for one
      // physical change, and three of them running concurrently would each diff
      // against the *same* stale list and each publish a line — which is exactly the
      // "kamera çıkarıldı" shown three times that [deviceChanges] promises not to
      // do. Serialised, the second and third run against an already-updated list,
      // find no difference, and are dropped.
      (_) => unawaited(_serialized(_handleDeviceChange)),
      onError: (Object error) => _seams.diagnostics?.call(
        MediaFault(MediaFaultKind.unavailable, MediaSourceKind.camera),
        error,
      ),
    );
    try {
      _senders = await _seams.senders.open();
    } catch (error) {
      final MediaFault fault = _unavailable(MediaSourceKind.camera);
      _fail(fault, error);
      return MediaFailed(fault);
    }
    await _refreshDevices();
    _succeed();
    return const MediaSucceeded();
  });

  /// Releases the senders' own resources. Does **not** stop tracks; call [stop]
  /// first, or [dispose], which does both.
  Future<void> close() => _seams.senders.close();

  /// The call ended. Detaches all three senders and stops every track this
  /// controller created.
  ///
  /// Returns the resulting state rather than throwing, because a cleanup path that
  /// can fail is a cleanup path that leaks: a `replaceTrack` that throws here must
  /// not stop the other two senders, or the tracks, from being released. Failures
  /// are collected, reported through [MediaState.fault], and the drain continues.
  Future<MediaState> stop() => _serialized(() async {
    _watchdog.disarm();
    final List<Object> failures = <Object>[];

    final MediaSenderSet? senders = _senders;
    if (senders != null) {
      for (final MediaSenderHandle sender in <MediaSenderHandle>[
        senders.audio,
        senders.camera,
        senders.screen,
      ]) {
        try {
          await sender.replaceTrack(null);
        } catch (error) {
          failures.add(error);
        }
      }
    }

    // Drain the ledger even if every detach above failed. This is the line the old
    // build did not have: it stopped streams in a React effect keyed on
    // `callStatus === "ended"`, so a decline or a failed publish left the camera
    // on, and `close()` only ran on unmount.
    final List<MediaTrackHandle> owned = List<MediaTrackHandle>.of(_owned);
    _owned.clear();
    _audioTrack = null;
    _cameraTrack = null;
    _screenTrack = null;
    for (final MediaTrackHandle track in owned) {
      failures.addAll(await _stopQuietly(track));
    }

    // The device list is deliberately **not** cleared here. It describes the
    // machine, not the call, and the unplug check reads the *state* ids — which
    // [MediaState] below resets. Forgetting the list would make the next OS
    // notification report every camera as newly plugged in.
    if (failures.isEmpty) {
      _emit(const MediaState());
    } else {
      final MediaFault fault = MediaFault(
        MediaFaultKind.unavailable,
        MediaSourceKind.camera,
      );
      _seams.diagnostics?.call(fault, failures.first);
      _emit(MediaState(fault: fault));
    }
    return _state;
  });

  /// [stop], then closes the senders and every stream. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _watchdogSubscription.cancel();
    await _deviceSubscription?.cancel();
    await _negotiationSubscription?.cancel();
    _deviceSubscription = null;
    _negotiationSubscription = null;
    await _watchdog.dispose();
    await close();
    await _states.close();
    await _deviceEvents.close();
    await _negotiationEvents.close();
  }

  // ---------------------------------------------------------------------------
  // Starting a call
  // ---------------------------------------------------------------------------

  /// Captures and publishes what the call needs, or reports why it cannot.
  ///
  /// `video: true` means the user pressed the video button, and that request is
  /// honoured or **reported** — never quietly downgraded. The ladder has exactly
  /// two rungs:
  ///
  /// | rung | request | outcome |
  /// |---|---|---|
  /// | 1 | microphone + camera | the call, as asked for |
  /// | 2 | camera only | video-only, with [MediaTexts.microphoneMissingInVideoCall] |
  /// | — | ~~microphone only~~ | **removed** |
  ///
  /// A third rung — fall back to `{audio: true, video: false}` and report success
  /// — is what a silent audio call looks like from the peer's side, with the
  /// reason buried in a warning line. A user who asked for video and got that has
  /// been told nothing. So when both rungs fail the call **fails**, with a
  /// Turkish reason.
  ///
  /// The degradation that *is* permitted is the one whose effect the user can still
  /// see: a video call whose microphone is missing continues as a video call and
  /// says so.
  ///
  /// [cameraDeviceId] and [microphoneDeviceId] are honoured only after being found
  /// in the current device list; an id the OS does not have is a reported
  /// `deviceNotFound` rather than a silent fall back to a different device.
  Future<MediaCallStarted> startCall({
    required bool video,
    String? cameraDeviceId,
    String? microphoneDeviceId,
  }) => _serialized(() async {
    if (_disposed) return MediaCallFailed(_unavailable(MediaSourceKind.camera));
    final MediaSenderSet? senders = _senders;
    if (senders == null) {
      return MediaCallFailed(_unavailable(MediaSourceKind.camera));
    }

    await _refreshDevices();
    // Validate before asking for anything: a stale id must not reach the native
    // layer, where an unmatched audio deviceId keeps the *previous* microphone
    // while reporting the requested one.
    final MediaFault? cameraFault = video
        ? _validate(cameraDeviceId, MediaSourceKind.camera)
        : null;
    if (cameraFault != null) {
      _fail(cameraFault, null);
      return MediaCallFailed(cameraFault);
    }
    // A microphone id that is gone is not fatal for a video call: rung 2 is exactly
    // that case and produces the notice. It is fatal for an audio call, where the
    // microphone is the whole request.
    final MediaFault? micFault = _validate(
      microphoneDeviceId,
      MediaSourceKind.microphone,
    );
    if (micFault != null && !video) {
      _fail(micFault, null);
      return MediaCallFailed(micFault);
    }

    if (!video) {
      final _Attempt attempt = await _attempt(
        MediaCaptureRequest(
          audio: true,
          microphoneDeviceId: micFault == null ? microphoneDeviceId : null,
        ),
        requiredSource: MediaSourceKind.microphone,
      );
      final MediaFault? fault = attempt.fault;
      if (fault != null) return MediaCallFailed(fault);
      final MediaFault? attachFault = await _attachAudio(attempt.audioTrack);
      if (attachFault != null) return MediaCallFailed(attachFault);
      _emit(
        _state.copyWith(
          microphoneLive: true,
          microphoneDeviceId: attempt.microphoneDeviceId,
          clearCameraDeviceId: true,
        ),
      );
      _succeed();
      return const MediaCallLive(audio: true, video: false);
    }

    // Rung 1: both devices, as asked for.
    final _Attempt full = await _attempt(
      MediaCaptureRequest(
        audio: true,
        video: true,
        microphoneDeviceId: micFault == null ? microphoneDeviceId : null,
        cameraDeviceId: cameraDeviceId,
      ),
      requiredSource: MediaSourceKind.camera,
    );
    if (full.ok) {
      final MediaFault? audioAttach = await _attachAudio(full.audioTrack);
      if (audioAttach != null) return MediaCallFailed(audioAttach);
      final MediaFault? cameraAttach = await _attachCamera(full.cameraTrack);
      if (cameraAttach != null) {
        // The camera could not be published: put the microphone back where it was
        // rather than leave a half-started call on the wire.
        await _attachAudio(null);
        return MediaCallFailed(cameraAttach);
      }
      _emit(
        _state.copyWith(
          microphoneLive: true,
          cameraLive: true,
          microphoneDeviceId: full.microphoneDeviceId,
          cameraDeviceId: full.cameraDeviceId,
        ),
      );
      _succeed();
      return const MediaCallLive(audio: true, video: true);
    }

    // Rung 2: camera only. The one permitted degradation, and it announces itself.
    // Rung 1 has already released whatever it captured, so nothing is running while
    // this is attempted.
    final _Attempt videoOnly = await _attempt(
      MediaCaptureRequest(video: true, cameraDeviceId: cameraDeviceId),
      requiredSource: MediaSourceKind.camera,
    );
    if (videoOnly.ok) {
      final MediaFault? cameraAttach = await _attachCamera(
        videoOnly.cameraTrack,
      );
      if (cameraAttach != null) return MediaCallFailed(cameraAttach);
      _emit(
        _state.copyWith(
          cameraLive: true,
          microphoneLive: false,
          cameraDeviceId: videoOnly.cameraDeviceId,
          clearMicrophoneDeviceId: true,
        ),
      );
      _succeed(notice: MediaTexts.microphoneMissingInVideoCall);
      return const MediaCallLive(
        audio: false,
        video: true,
        notice: MediaTexts.microphoneMissingInVideoCall,
      );
    }

    // Both rungs failed. Report; do not fall back to audio. A permission refusal is
    // preferred when either attempt hit one, because a combined
    // `getUserMedia({audio: true, video: true})` cannot say *which* device was
    // refused and "allow the app" is the only advice that can be right.
    final MediaFault fullFault =
        full.fault ??
        MediaFault(MediaFaultKind.unknown, MediaSourceKind.camera);
    final MediaFault reported =
        fullFault.kind == MediaFaultKind.permissionDenied ||
            videoOnly.fault?.kind == MediaFaultKind.permissionDenied
        ? MediaFault(MediaFaultKind.permissionDenied, MediaSourceKind.camera)
        : videoOnly.fault ?? fullFault;
    _fail(reported, null);
    return MediaCallFailed(reported);
  });

  // ---------------------------------------------------------------------------
  // Camera, mid-call
  // ---------------------------------------------------------------------------

  /// Attaches a camera to the camera sender with `replaceTrack`.
  ///
  /// Works during a voice call, which is the point: the camera transceiver was
  /// negotiated as `sendrecv` at [open], so turning the camera on mid-call is one
  /// `replaceTrack` and no offer. That is also why the call machine's
  /// `upgradeToVideo` can promise a frameless upgrade: adding a transceiver here
  /// would be a renegotiation, and renegotiating is the thing this layer is built
  /// to avoid.
  Future<MediaOutcome> enableCamera({
    String? deviceId,
  }) => _serialized(() async {
    if (_disposed) return MediaFailed(_unavailable(MediaSourceKind.camera));
    if (_senders == null) {
      return MediaFailed(_unavailable(MediaSourceKind.camera));
    }

    await _refreshDevices();
    final MediaFault? invalid = _validate(deviceId, MediaSourceKind.camera);
    if (invalid != null) {
      _fail(invalid, null);
      return MediaFailed(invalid);
    }

    final _Attempt attempt = await _attempt(
      MediaCaptureRequest(video: true, cameraDeviceId: deviceId),
      requiredSource: MediaSourceKind.camera,
    );
    final MediaFault? fault = attempt.fault;
    if (fault != null) return MediaFailed(fault);

    final MediaFault? attachFault = await _attachCamera(attempt.cameraTrack);
    if (attachFault != null) return MediaFailed(attachFault);
    _emit(
      _state.copyWith(cameraLive: true, cameraDeviceId: attempt.cameraDeviceId),
    );
    _succeed();
    return const MediaSucceeded();
  });

  /// Detaches the camera with `replaceTrack(null)` and stops its track.
  ///
  /// Not a mute: the track is stopped, so the camera light goes out. A muted camera
  /// would keep encoding black frames forever, and a detach whose `replaceTrack`
  /// then rejects leaves a camera that is neither sending nor stopped — lit, and
  /// streaming nothing, with no way for the user to tell.
  Future<MediaOutcome> disableCamera() => _serialized(() async {
    if (_disposed) return MediaFailed(_unavailable(MediaSourceKind.camera));
    if (_senders == null) {
      return MediaFailed(_unavailable(MediaSourceKind.camera));
    }
    if (_cameraTrack == null) return const MediaSucceeded();

    final MediaFault? attachFault = await _attachCamera(null);
    if (attachFault != null) return MediaFailed(attachFault);
    _emit(_state.copyWith(cameraLive: false, clearCameraDeviceId: true));
    _succeed();
    return const MediaSucceeded();
  });

  /// Publishes a different camera without renegotiating.
  ///
  /// **This does not use `Helper.switchCamera`, which cannot work on Windows.** Two
  /// independent reasons, both in the plugin's own source:
  ///
  /// * `Helper.switchCamera` ignores its `deviceId` off the web branch and sends
  ///   only `{'trackId': track.id}` to the platform
  ///   (`flutter_webrtc/lib/src/helper.dart:65-70`), so on Windows it switches to
  ///   whatever the native side considers next, not to the device that was asked
  ///   for;
  /// * the handler that receives it answers `result->NotImplemented()`
  ///   (`flutter_webrtc/common/cpp/src/flutter_media_stream.cc:630-634`), so the
  ///   call fails outright.
  ///
  /// So the port does what the web branch does: capture the requested device and
  /// `replaceTrack` it. That costs one capture restart, which the hardware would
  /// have done anyway.
  Future<MediaOutcome> switchCamera(String deviceId) => _serialized(() async {
    if (_disposed) return MediaFailed(_unavailable(MediaSourceKind.camera));
    if (_senders == null) {
      return MediaFailed(_unavailable(MediaSourceKind.camera));
    }

    await _refreshDevices();
    final MediaFault? invalid = _validate(deviceId, MediaSourceKind.camera);
    if (invalid != null) {
      _fail(invalid, null);
      return MediaFailed(invalid);
    }

    final _Attempt attempt = await _attempt(
      MediaCaptureRequest(video: true, cameraDeviceId: deviceId),
      requiredSource: MediaSourceKind.camera,
    );
    final MediaFault? fault = attempt.fault;
    if (fault != null) return MediaFailed(fault);

    final MediaFault? attachFault = await _attachCamera(attempt.cameraTrack);
    if (attachFault != null) return MediaFailed(attachFault);
    _emit(
      _state.copyWith(cameraLive: true, cameraDeviceId: attempt.cameraDeviceId),
    );
    _succeed();
    return const MediaSucceeded();
  });

  // ---------------------------------------------------------------------------
  // Microphone, mid-call
  // ---------------------------------------------------------------------------

  /// Re-points the existing microphone capture at [deviceId].
  ///
  /// Goes through `Helper.selectAudioInput`, which reaches
  /// `FlutterMediaStream::SelectAudioInput`
  /// (`common/cpp/src/flutter_media_stream.cc:504-527`). That is the one device
  /// switch on Windows that is validated: it walks the recording device list and
  /// fails with `Not found device id: …` when the id is not there.
  ///
  /// Re-capturing the microphone instead would be the *wrong* thing to do, for a
  /// reason worth stating: `getUserMedia` with an unknown audio `deviceId` matches
  /// nothing (`common/cpp/src/flutter_media_stream.cc:219-228`), never calls
  /// `SetRecordingDevice`, and returns a track that keeps the previous microphone
  /// while reporting the *requested* id in its settings (`:267-269`). A switch that
  /// appears to work and does not is worse than one that refuses.
  Future<MediaOutcome> switchMicrophone(
    String deviceId,
  ) => _serialized(() async {
    if (_disposed) return MediaFailed(_unavailable(MediaSourceKind.microphone));
    if (_senders == null) {
      return MediaFailed(_unavailable(MediaSourceKind.microphone));
    }

    await _refreshDevices();
    final MediaFault? invalid = _validate(deviceId, MediaSourceKind.microphone);
    if (invalid != null) {
      _fail(invalid, null);
      return MediaFailed(invalid);
    }
    try {
      await _seams.capture.selectAudioInput(deviceId);
    } catch (error) {
      // `catch (Object)`, never `on PlatformException`: the plugin raises raw
      // Dart `String`s from its capture paths
      // (`flutter_webrtc/lib/src/native/mediadevices_impl.dart:48-50`).
      final MediaFault fault = classifyMediaFault(
        error,
        source: MediaSourceKind.microphone,
      );
      _fail(fault, error);
      return MediaFailed(fault);
    }
    _emit(
      _state.copyWith(
        microphoneLive: _audioTrack != null,
        microphoneDeviceId: deviceId,
      ),
    );
    _succeed();
    return const MediaSucceeded();
  });

  /// Mutes or unmutes the published microphone **without detaching it**.
  ///
  /// `track.enabled = false` keeps the sender alive and encoding silence, so the
  /// peer sees a quiet microphone rather than a broken track. That is the whole
  /// reason muting is not `replaceTrack(null)`: detaching the microphone would
  /// renegotiate it away, and a renegotiation mid-call is exactly what this layer
  /// refuses to do.
  Future<MediaOutcome> muteMicrophone({required bool muted}) =>
      _serialized(() async {
        if (_disposed) {
          return MediaFailed(_unavailable(MediaSourceKind.microphone));
        }
        if (_senders == null) {
          return MediaFailed(_unavailable(MediaSourceKind.microphone));
        }
        final MediaTrackHandle? track = _audioTrack;
        if (track == null) return const MediaSucceeded();
        try {
          track.enabled = !muted;
        } catch (error) {
          final MediaFault fault = MediaFault(
            MediaFaultKind.unavailable,
            MediaSourceKind.microphone,
          );
          _fail(fault, error);
          return MediaFailed(fault);
        }
        _succeed();
        return const MediaSucceeded();
      });

  // ---------------------------------------------------------------------------
  // Screen share
  // ---------------------------------------------------------------------------

  /// Every screen and window this machine can share.
  ///
  /// **There is no native display picker on Windows** in this plugin, so this list
  /// *is* the picker: a caller has to present it and pass the chosen id to
  /// [startScreenShare]. See [DisplaySource] for the whole story.
  ///
  /// A failure returns an empty list and sets [MediaState.fault]; there is no other
  /// channel for it.
  Future<List<DisplaySource>> availableDisplaySources() async {
    if (_disposed) return const <DisplaySource>[];
    try {
      return await _seams.capture.displaySources();
    } catch (error) {
      final MediaFault fault = classifyMediaFault(
        error,
        source: MediaSourceKind.screen,
      );
      _fail(fault, error);
      return const <DisplaySource>[];
    }
  }

  /// Starts sharing a screen or window, mid-call, with the first-frame watchdog
  /// armed.
  ///
  /// [sourceId] must be one of [availableDisplaySources]; when it is `null` the
  /// first entry is used and [MediaScreenShareStarted.source] says which, so a
  /// caller can always show the user what is actually being shared.
  ///
  /// Starting a share while one is already running replaces it: the previous target
  /// is detached and stopped first, which is what a user picking "a different
  /// window" wants, and what keeps the ledger to one screen track.
  ///
  /// ## What comes back
  ///
  /// [MediaScreenShareStarted] means the capture *started*, which is the strongest
  /// claim this can make, because upstream issue #2137 is exactly the case where it
  /// started and will never deliver a frame. [MediaState.screenShare] says whether
  /// frames followed, and it is already [ScreenSharePhase.waitingForFirstFrame] by
  /// the time this method returns.
  Future<MediaScreenShare> startScreenShare({
    String? sourceId,
  }) => _serialized(() async {
    if (_disposed) {
      return MediaScreenShareFailed(_unavailable(MediaSourceKind.screen));
    }
    if (_senders == null) {
      return MediaScreenShareFailed(_unavailable(MediaSourceKind.screen));
    }

    final List<DisplaySource> sources = await availableDisplaySources();
    if (sources.isEmpty) {
      final MediaFault fault = MediaFault(
        MediaFaultKind.deviceNotFound,
        MediaSourceKind.screen,
      );
      _watchdog.fail();
      _fail(fault, null);
      return MediaScreenShareFailed(fault);
    }
    final DisplaySource? source = _pick(sources, sourceId);
    if (source == null) {
      final MediaFault fault = MediaFault(
        MediaFaultKind.deviceNotFound,
        MediaSourceKind.screen,
      );
      _watchdog.fail();
      _fail(fault, null);
      return MediaScreenShareFailed(fault);
    }

    // Replace any share already running, so the ledger never holds two.
    if (_screenTrack != null) await _attachScreen(null);

    CapturedMedia captured;
    try {
      captured = await _seams.capture.getDisplayMedia(source);
    } catch (error) {
      final MediaFault fault = classifyMediaFault(
        error,
        source: MediaSourceKind.screen,
      );
      _watchdog.fail();
      _fail(fault, error);
      return MediaScreenShareFailed(fault);
    }

    // Registered before inspection, exactly as in `_attempt`: anything the OS
    // handed over is now ours to stop.
    _owned.addAll(captured.tracks);
    final MediaTrackHandle? video = captured.firstVideo;
    if (video == null) {
      await _releaseCaptured(captured);
      final MediaFault fault = MediaFault(
        MediaFaultKind.deviceNotFound,
        MediaSourceKind.screen,
      );
      _watchdog.fail();
      _fail(fault, null);
      return MediaScreenShareFailed(fault);
    }

    final MediaFault? attachFault = await _attachScreen(video);
    if (attachFault != null) {
      _watchdog.fail();
      _fail(attachFault, null);
      return MediaScreenShareFailed(attachFault);
    }

    // Armed before this method returns, so "waiting for the first frame" is on
    // screen while the user is still looking at the call rather than seconds
    // later. This is the whole of the #2137 workaround.
    _watchdog.arm(_senders!.screen.id);
    _emit(
      _state.copyWith(
        screenShare: ScreenSharePhase.waitingForFirstFrame,
        screenSourceId: source.id,
        screenSourceName: source.name,
      ),
    );
    _succeed();
    return MediaScreenShareStarted(source.name);
  });

  /// Detaches the screen sender with `replaceTrack(null)`, stops the screen track,
  /// and disarms the watchdog.
  ///
  /// Idempotent: stopping a share that is not running succeeds without touching the
  /// sender, so a double tap is not an error.
  Future<MediaOutcome> stopScreenShare() => _serialized(() async {
    if (_disposed) return MediaFailed(_unavailable(MediaSourceKind.screen));
    if (_senders == null) {
      return MediaFailed(_unavailable(MediaSourceKind.screen));
    }
    if (_screenTrack == null) {
      if (_state.screenShare != ScreenSharePhase.idle) {
        _watchdog.disarm();
        _emit(_state.copyWith(screenShare: ScreenSharePhase.idle));
      }
      _succeed();
      return const MediaSucceeded();
    }
    _watchdog.disarm();
    final MediaFault? attachFault = await _attachScreen(null);
    if (attachFault != null) return MediaFailed(attachFault);
    _emit(
      _state.copyWith(
        screenShare: ScreenSharePhase.idle,
        clearScreenSourceId: true,
        clearScreenSourceName: true,
      ),
    );
    _succeed();
    return const MediaSucceeded();
  });

  // ---------------------------------------------------------------------------
  // Capturing
  // ---------------------------------------------------------------------------

  /// One rung of the ladder: ask the OS, verify what came back, and give
  /// everything up again on any failure.
  ///
  /// ## The check that is not in the browser original
  ///
  /// A missing device does **not** throw on this plugin. `GetUserVideo` returns
  /// early, with no track and no error, when the video device module reports no
  /// devices or refuses to create a capturer:
  ///
  /// ```cpp
  /// if (nb_video_devices == 0)
  ///   return;
  /// if (!video_capturer.get())
  ///   return;
  /// ```
  /// (`flutter_webrtc/common/cpp/src/flutter_media_stream.cc:382-393`).
  ///
  /// `GetUserMedia` then reports success with an empty `videoTracks` array
  /// (`:62-77`). In a browser the same situation throws `NotFoundError` and the
  /// ladder's `catch` moves on; here it resolves, so a ladder that only caught
  /// would see rung 1 "succeed" with no camera and publish nothing at all. That is
  /// indistinguishable, from the caller's side, from a camera that was never asked
  /// for — and it is the shape of the bug that made the old camera look alive
  /// locally while sending nothing.
  ///
  /// So the returned stream is **inspected**, and a requested-but-absent track
  /// becomes a real fault. Which kind it is comes from the device list: nothing
  /// enumerated is "plug something in", something enumerated is "it is there and
  /// broken", and those are different sentences with different fixes.
  Future<_Attempt> _attempt(
    MediaCaptureRequest request, {
    required MediaSourceKind requiredSource,
  }) async {
    CapturedMedia captured;
    try {
      captured = await _seams.capture.getUserMedia(request);
    } catch (error) {
      // `catch (Object)`, never `on PlatformException`: the plugin throws a raw
      // Dart `String` from both `getUserMedia` and `getDisplayMedia`
      // (`flutter_webrtc/lib/src/native/mediadevices_impl.dart:48-50`, `:93-95`).
      final MediaFault fault = classifyMediaFault(
        error,
        source: requiredSource,
      );
      _fail(fault, error);
      return _Attempt.failed(fault);
    }

    _owned.addAll(captured.tracks);

    // Video first: a video call is about the camera, and a first rung that lost the
    // camera is exactly the case the ladder has to reason about.
    if (request.video && captured.firstVideo == null) {
      final MediaFault fault = _absent(MediaSourceKind.camera);
      await _releaseCaptured(captured);
      _fail(fault, null);
      return _Attempt.failed(fault);
    }
    if (request.audio && captured.firstAudio == null) {
      final MediaFault fault = _absent(MediaSourceKind.microphone);
      await _releaseCaptured(captured);
      _fail(fault, null);
      return _Attempt.failed(fault);
    }
    return _Attempt.ok(captured, _devices);
  }

  // ---------------------------------------------------------------------------
  // Attaching and detaching — the only things that touch a sender
  // ---------------------------------------------------------------------------

  Future<MediaFault?> _attachAudio(MediaTrackHandle? track) async {
    final MediaFault? fault = await _attach(
      _senders!.audio,
      track,
      () => _audioTrack,
    );
    if (fault == null) _audioTrack = track;
    return fault;
  }

  Future<MediaFault?> _attachCamera(MediaTrackHandle? track) async {
    final MediaFault? fault = await _attach(
      _senders!.camera,
      track,
      () => _cameraTrack,
    );
    if (fault == null) _cameraTrack = track;
    return fault;
  }

  Future<MediaFault?> _attachScreen(MediaTrackHandle? track) async {
    final MediaFault? fault = await _attach(
      _senders!.screen,
      track,
      () => _screenTrack,
    );
    if (fault == null) _screenTrack = track;
    return fault;
  }

  /// `replaceTrack` on one sender, with a real rollback.
  ///
  /// The previous track is stopped **only after** the new one is in place, so a
  /// failed publish leaves the call exactly as it was. When either sender's
  /// `replaceTrack` rejects, the other is restored too: a screen share that
  /// started and a camera that did not would leave the call in a state the user
  /// never asked for. A `null` [next] is the ordinary detach.
  Future<MediaFault?> _attach(
    MediaSenderHandle sender,
    MediaTrackHandle? next,
    MediaTrackHandle? Function() current,
  ) async {
    final MediaTrackHandle? previous = current();
    if (identical(previous, next)) return null;
    try {
      await sender.replaceTrack(next);
    } catch (error) {
      final MediaFault fault = MediaFault(
        MediaFaultKind.unavailable,
        _slotSource(sender.slot),
      );
      _seams.diagnostics?.call(fault, error);
      try {
        await sender.replaceTrack(previous);
      } catch (restoreError) {
        _seams.diagnostics?.call(fault, restoreError);
      }
      // Whatever the sender may have taken must not be left running.
      if (next != null && !identical(next, previous)) {
        await _stopQuietly(next);
      }
      return fault;
    }
    if (previous != null && !identical(previous, next)) {
      await _stopQuietly(previous);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Device changes
  // ---------------------------------------------------------------------------

  /// Re-enumerates, publishes a real difference, and releases anything that left.
  ///
  /// The plugin's own `ondevicechange` cannot be used directly: it carries no
  /// payload, and on Windows it is raised by the *audio* device module alone
  /// (`common/cpp/src/flutter_webrtc_base.cc:88-92`) — so a camera unplug can
  /// arrive with no camera news, and one unplug can arrive as several
  /// notifications. Re-enumerating and diffing fixes both, and is the reason a
  /// "kamera çıkarıldı" line appears once.
  Future<void> _handleDeviceChange() async {
    if (_disposed || _senders == null) return;
    final MediaDeviceSnapshot before = _devices;
    final MediaDeviceSnapshot? after = await _refreshDevices();
    if (after == null || _disposed) return;

    final MediaDevicesChanged change = MediaDevicesChanged(
      removedMicrophones: before.difference(after).microphones,
      removedCameras: before.difference(after).cameras,
      addedMicrophones: after.addedComparedTo(before).microphones,
      addedCameras: after.addedComparedTo(before).cameras,
    );
    // No real difference: an OS notification with nothing behind it. Dropped, so the
    // UI cannot show the same line twice for one unplug.
    if (change.isEmpty) return;
    if (_deviceEvents.hasListener) _deviceEvents.add(change);

    // A device this process was publishing has left. Detach it rather than leave a
    // dead track on the wire: a peer otherwise sees a permanently silent or frozen
    // participant with no reason given.
    String? notice;
    if (change.lostCamera(_state.cameraDeviceId)) {
      notice = MediaTexts.cameraUnplugged;
      await _attachCamera(null);
    }
    if (change.lostMicrophone(_state.microphoneDeviceId)) {
      notice = MediaTexts.microphoneUnplugged;
      await _attachMicrophoneForLost();
    }
    _emit(
      _state.copyWith(
        cameraLive: _cameraTrack != null,
        microphoneLive: _audioTrack != null,
        clearCameraDeviceId: _cameraTrack == null,
        clearMicrophoneDeviceId: _audioTrack == null,
        clearFault: true,
        clearNotice: notice == null,
        notice: notice,
      ),
    );
  }

  /// Releases a microphone that has been unplugged.
  Future<void> _attachMicrophoneForLost() async {
    if (_senders != null) {
      await _attach(_senders!.audio, null, () => _audioTrack);
    }
    _audioTrack = null;
  }

  /// Re-reads the device list, keeping the old one when the read fails.
  ///
  /// A failed enumeration is not evidence that devices disappeared, and reporting
  /// it as such would show "kamera çıkarıldı" for a camera that is still plugged in.
  /// Returns the new snapshot, or `null` when nothing could be read.
  Future<MediaDeviceSnapshot?> _refreshDevices() async {
    try {
      _devices = await _seams.capture.enumerateDevices();
    } catch (error) {
      _seams.diagnostics?.call(
        MediaFault(MediaFaultKind.unknown, MediaSourceKind.camera),
        error,
      );
      return null;
    }
    return _devices;
  }

  // ---------------------------------------------------------------------------
  // Ledger
  // ---------------------------------------------------------------------------

  /// Stops every track in [captured] and forgets them.
  Future<void> _releaseCaptured(CapturedMedia captured) async {
    for (final MediaTrackHandle track in captured.tracks) {
      _owned.removeWhere((MediaTrackHandle held) => identical(held, track));
      await _stopQuietly(track);
    }
  }

  /// Stops one track and forgets it. Returns whatever went wrong, so a caller in a
  /// cleanup path can carry on.
  ///
  /// Never throws. A `stop()` that could throw would be a `stop()` that could skip
  /// the next track, which is the leak.
  Future<List<Object>> _stopQuietly(MediaTrackHandle track) async {
    _owned.removeWhere((MediaTrackHandle held) => identical(held, track));
    try {
      await track.stop();
      return const <Object>[];
    } catch (error) {
      return <Object>[error];
    }
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  /// The chosen target, or `null` when the requested id is not in the list.
  ///
  /// An unknown id is a failure rather than a fall back to the first entry: with no
  /// native picker, silently sharing a different window than the one the user
  /// chose is the worst possible answer.
  static DisplaySource? _pick(List<DisplaySource> sources, String? sourceId) {
    for (final DisplaySource candidate in sources) {
      if (sourceId == null || candidate.id == sourceId) return candidate;
    }
    return null;
  }

  /// A `deviceNotFound` for an id the OS does not have, or `null` when it does.
  ///
  /// Not left to the native layer on purpose; see [MediaDeviceSnapshot.byId]. An
  /// unmatched id there is accepted and silently keeps the previous device.
  MediaFault? _validate(String? deviceId, MediaSourceKind source) {
    if (deviceId == null) return null;
    if (_devices.byId(deviceId) != null) return null;
    return MediaFault(MediaFaultKind.deviceNotFound, source);
  }

  /// The fault for a track that was requested and did not come back.
  MediaFault _absent(MediaSourceKind source) {
    final List<MediaDevice> present = switch (source) {
      MediaSourceKind.camera => _devices.cameras,
      MediaSourceKind.microphone => _devices.microphones,
      // No enumeration exists for share targets, so "no track" is "no target".
      MediaSourceKind.screen => const <MediaDevice>[],
    };
    return MediaFault(
      present.isEmpty
          ? MediaFaultKind.deviceNotFound
          : MediaFaultKind.deviceNotReadable,
      source,
    );
  }

  static MediaSourceKind _slotSource(String slot) => switch (slot) {
    'audio' => MediaSourceKind.microphone,
    'screen' => MediaSourceKind.screen,
    _ => MediaSourceKind.camera,
  };

  /// The one "the media layer itself is not usable" fault, whether because
  /// [open] has not run or because [dispose] has. One name for one sentence, so a
  /// caller cannot invent a second one.
  static MediaFault _unavailable(MediaSourceKind source) =>
      MediaFault(MediaFaultKind.unavailable, source);

  void _onScreenPhase(ScreenSharePhase phase) {
    if (_disposed) return;
    _emit(
      _state.copyWith(
        screenShare: phase,
        clearScreenSourceId:
            phase == ScreenSharePhase.idle || phase == ScreenSharePhase.failed,
        clearScreenSourceName:
            phase == ScreenSharePhase.idle || phase == ScreenSharePhase.failed,
      ),
    );
  }

  void _emit(MediaState next) {
    if (next == _state) return;
    _state = next;
    if (_states.hasListener) _states.add(next);
  }

  /// Records a failure: Turkish text in the state, raw text to the log only.
  void _fail(MediaFault fault, Object? raw) {
    if (raw != null) _seams.diagnostics?.call(fault, raw);
    _emit(_state.copyWith(fault: fault));
  }

  /// Clears any standing failure and sets an optional notice.
  void _succeed({String? notice}) {
    _emit(
      _state.copyWith(
        clearFault: true,
        clearNotice: notice == null,
        notice: notice,
      ),
    );
  }

  /// Runs [work] with nothing else running.
  Future<T> _serialized<T>(Future<T> Function() work) {
    final Completer<T> completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await work());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}

/// One rung of the ladder's result.
///
/// Holds the tracks it captured *and* the device ids it can prove them to be. The
/// proof is the point: the plugin puts the track's own fresh UUID in both `id` and
/// `label` (`common/cpp/src/flutter_media_stream.cc:408-410`), so the only thing a
/// track can be matched back to hardware with is the device manager's friendly
/// name, and an ambiguous name proves nothing. Guessing an id from a label would be
/// a lie that the unplug check would then act on.
final class _Attempt {
  _Attempt.failed(this.fault)
    : audioTrack = null,
      cameraTrack = null,
      microphoneDeviceId = null,
      cameraDeviceId = null;

  _Attempt.ok(CapturedMedia captured, MediaDeviceSnapshot devices)
    : fault = null,
      audioTrack = captured.firstAudio,
      cameraTrack = captured.firstVideo,
      microphoneDeviceId = _deviceIdOf(captured.firstAudio, devices),
      cameraDeviceId = _deviceIdOf(captured.firstVideo, devices);

  final MediaTrackHandle? audioTrack;

  final MediaTrackHandle? cameraTrack;

  final String? microphoneDeviceId;

  final String? cameraDeviceId;

  final MediaFault? fault;

  bool get ok => fault == null;

  static String? _deviceIdOf(
    MediaTrackHandle? track,
    MediaDeviceSnapshot devices,
  ) {
    final String label = track?.label ?? '';
    if (label.isEmpty) return null;
    return devices.idForLabel(label);
  }
}
