/// Hand-driven fakes for every seam `lib/media` exposes.
///
/// Nothing here opens a device, a socket or a clock. A test drives a whole call —
/// including the ladder, the track ledger and the first-frame watchdog — by
/// scripting what the OS would have done.
///
/// **No test in `app/test/media` exercises a real camera, a real microphone, a real
/// peer connection or a real display capture.** Hardware was not available to the
/// author of these tests. What is exercised is the Dart layer: the ladder, the
/// `replaceTrack` discipline, the ledger, the watchdog's schedule, the classifier
/// and the device-change diff.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/media/media.dart';

/// A [MediaTrackHandle] that remembers whether it was stopped.
///
/// [stopCount] rather than a bool, because "stopped exactly once" is a stronger
/// and more useful claim than "stopped": a double `stop()` is what turns one leak
/// into a platform error in the middle of the next call.
final class FakeTrack implements MediaTrackHandle {
  FakeTrack({
    required this.kind,
    this.label = '',
    this.id = '',
    this.stopError,
    this.failOnEnable = false,
  });

  @override
  final String id;

  @override
  final String kind;

  @override
  String label;

  int stopCount = 0;

  /// Thrown by [stop] when set, to prove the drain continues past a failure.
  final Object? stopError;

  /// Thrown by the [enabled] setter when true, to prove a mute failure is reported
  /// rather than thrown.
  bool failOnEnable;

  bool _enabled = true;

  /// True while the OS is holding this track, which is the thing the old build
  /// leaked. The literal mirror of a camera light.
  bool get isLive => stopCount == 0;

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    if (failOnEnable) throw 'set enabled refused';
    _enabled = value;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    final Object? failure = stopError;
    if (failure != null) throw failure;
  }

  @override
  String toString() => 'FakeTrack($kind, ${label.isEmpty ? id : label})';
}

/// A [MediaSenderHandle] that records every `replaceTrack`, and can be told to
/// refuse.
///
/// The refusal is the interesting part: when either `replaceTrack` rejects, the
/// other sender is restored and the new camera is stopped rather than left
/// half-attached. Both are pinned here.
final class FakeSender implements MediaSenderHandle {
  FakeSender({required this.slot, this.id = ''});

  @override
  final String slot;

  @override
  final String id;

  MediaTrackHandle? _track;

  /// One entry per `replaceTrack`, with `null` for a detach. The whole
  /// "mid-call attach is `replaceTrack` and nothing else" claim is this list.
  final List<MediaTrackHandle?> calls = <MediaTrackHandle?>[];

  /// When set, the next `replaceTrack` throws this and then clears itself.
  Object? failNextReplace;

  /// When set, every `replaceTrack` throws this. Used to prove [MediaController.stop]
  /// still stops the tracks when no sender can be detached.
  Object? failAllReplaces;

  @override
  MediaTrackHandle? get track => _track;

  @override
  Future<void> replaceTrack(MediaTrackHandle? track) async {
    calls.add(track);
    final Object? failure = failAllReplaces ?? failNextReplace;
    if (failNextReplace != null) failNextReplace = null;
    if (failure != null) throw failure;
    _track = track;
  }

  /// The `replaceTrack` calls that were a detach, i.e. `replaceTrack(null)`.
  List<MediaTrackHandle?> get detaches =>
      calls.where((MediaTrackHandle? t) => t == null).toList(growable: false);

  @override
  String toString() => 'FakeSender($slot, $id)';
}

/// A [MediaSenderRegistry] that hands out [FakeSender]s and counts the
/// negotiations the connection asked for.
final class FakeRegistry implements MediaSenderRegistry {
  FakeRegistry();

  final FakeSender audio = FakeSender(slot: 'audio', id: 'sender-audio');
  final FakeSender camera = FakeSender(slot: 'camera', id: 'sender-camera');
  final FakeSender screen = FakeSender(slot: 'screen', id: 'sender-screen');

  int openCount = 0;
  int closeCount = 0;

  /// Every renegotiation the *connection* asked for, in order.
  final List<void> negotiations = <void>[];

  final StreamController<void> _renegotiations =
      StreamController<void>.broadcast(sync: true);

  /// Every transceiver slot created, in order: audio, camera, screen, all
  /// `sendrecv`.
  final List<String> slots = <String>[];

  /// When set, [open] throws this.
  Object? failOpen;

  @override
  Future<MediaSenderSet> open() async {
    openCount += 1;
    final Object? failure = failOpen;
    if (failure != null) throw failure;
    slots.addAll(<String>['audio', 'camera', 'screen']);
    // Creating the transceivers is what raises the one and only renegotiation, so
    // the fake raises it here exactly as a peer connection would. Nothing in
    // `lib/media` raises another.
    requestNegotiation();
    return MediaSenderSet(audio: audio, camera: camera, screen: screen);
  }

  @override
  Future<void> close() async => closeCount += 1;

  @override
  Stream<void> get renegotiationNeeded => _renegotiations.stream;

  /// Raises a renegotiation request, as the connection would.
  void requestNegotiation() {
    if (_renegotiations.isClosed) return;
    negotiations.add(null);
    _renegotiations.add(null);
  }

  Future<void> dispose() => _renegotiations.close();
}

/// A [MediaStatsProbe] a test can drive one poll at a time.
///
/// This is the seam upstream issue #2137 forces into existence: a display track
/// that never encodes a frame, which the plugin reports as a *success*.
final class FakeStats implements MediaStatsProbe {
  FakeStats();

  /// What [framesEncoded] answers. Replaced per test.
  int frames = 0;

  /// Every sender id the watchdog asked about, in order.
  final List<String> asked = <String>[];

  /// When set, [framesEncoded] throws this instead of answering.
  Object? failWith;

  @override
  Future<int> framesEncoded(String senderId) async {
    asked.add(senderId);
    final Object? failure = failWith;
    if (failure != null) throw failure;
    return frames;
  }
}

/// A [MediaDelay] that records what it was asked to wait and returns at once.
///
/// The whole watchdog schedule then runs in microseconds and the recording is what
/// the "polled every 500 ms until the 4 s budget" assertion reads.
final class FakeDelay {
  final List<Duration> requested = <Duration>[];

  Future<void> call(Duration duration) async {
    requested.add(duration);
    await Future<void>.delayed(Duration.zero);
  }
}

/// What the OS would have done on the next `getUserMedia`.
final class FakeCapture implements MediaCapture {
  FakeCapture();

  final List<MediaCaptureRequest> requests = <MediaCaptureRequest>[];

  /// One answer per `getUserMedia`, consumed in order. A `null` entry means "throw
  /// this instead", which is how the raw-`String` case is exercised.
  final List<Object?> script = <Object?>[];

  /// The answer once [script] is empty. `null` with no script means "the OS handed
  /// back exactly what was asked for".
  Object? answer;

  MediaDeviceSnapshot devices = const MediaDeviceSnapshot();

  /// The sources [displaySources] reports.
  List<DisplaySource> sources = const <DisplaySource>[];

  /// Thrown by [displaySources] when set.
  Object? failDisplaySources;

  /// Thrown by [enumerateDevices] when set.
  Object? failEnumerate;

  /// Thrown by [selectAudioInput] when set.
  Object? failSelectAudioInput;

  final List<String> selectedInputs = <String>[];

  /// Thrown by [getDisplayMedia] when set. Takes priority over [displayScript].
  Object? failDisplayMedia;

  /// One answer per `getDisplayMedia`, consumed in order.
  final List<Object?> displayScript = <Object?>[];

  final List<DisplaySource> shared = <DisplaySource>[];

  /// Every track handed out, in order. The ledger assertion reads this.
  final List<FakeTrack> created = <FakeTrack>[];

  int deviceListings = 0;

  final StreamController<void> _deviceChanges =
      StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get deviceChanges => _deviceChanges.stream;

  /// Announces a device change, as the OS would. Carries nothing, can be fired any
  /// number of times for one physical change — which is the point.
  void announceDeviceChange() {
    if (_deviceChanges.isClosed) return;
    _deviceChanges.add(null);
  }

  @override
  Future<MediaDeviceSnapshot> enumerateDevices() async {
    deviceListings += 1;
    final Object? failure = failEnumerate;
    if (failure != null) throw failure;
    return devices;
  }

  @override
  Future<CapturedMedia> getUserMedia(MediaCaptureRequest request) async {
    requests.add(request);
    final Object? scripted = script.isEmpty ? answer : script.removeAt(0);
    if (scripted is CapturedMedia) return scripted;
    if (scripted != null) throw scripted;
    // "The OS did what it was asked": one track per requested device, carrying the
    // device manager's friendly name in `label` — which is exactly and only what
    // the plugin puts there
    // (`common/cpp/src/flutter_media_stream.cc:408-410`), and what the controller
    // has to match a track back to hardware with.
    final List<FakeTrack> tracks = <FakeTrack>[];
    if (request.audio) {
      tracks.add(
        FakeTrack(
          kind: 'audio',
          label: _labelFor(request.microphoneDeviceId) ?? defaultMicLabel,
        ),
      );
    }
    if (request.video) {
      tracks.add(
        FakeTrack(
          kind: 'video',
          label: _labelFor(request.cameraDeviceId) ?? defaultCameraLabel,
        ),
      );
    }
    created.addAll(tracks);
    return CapturedMedia(List<MediaTrackHandle>.unmodifiable(tracks));
  }

  /// The friendly name of an enumerated device, or `null` when the OS has no such
  /// id. Mirrors `enumerateDevices`, so a fake track's label is a name a
  /// `MediaDeviceSnapshot` can actually be asked about.
  String? _labelFor(String? deviceId) {
    if (deviceId == null) return null;
    return devices.byId(deviceId)?.label;
  }

  @override
  Future<CapturedMedia> getDisplayMedia(DisplaySource source) async {
    final Object? failure = failDisplayMedia;
    if (failure != null) throw failure;
    if (displayScript.isNotEmpty) {
      final Object? scripted = displayScript.removeAt(0);
      if (scripted is CapturedMedia) {
        created.addAll(scripted.tracks.whereType<FakeTrack>());
        shared.add(source);
        return scripted;
      }
      if (scripted != null) throw scripted;
    }
    final FakeTrack track = FakeTrack(kind: 'video', label: source.name);
    created.add(track);
    shared.add(source);
    return CapturedMedia(<MediaTrackHandle>[track]);
  }

  @override
  Future<List<DisplaySource>> displaySources() async {
    final Object? failure = failDisplaySources;
    if (failure != null) throw failure;
    return sources;
  }

  @override
  Future<void> selectAudioInput(String deviceId) async {
    final Object? failure = failSelectAudioInput;
    if (failure != null) throw failure;
    selectedInputs.add(deviceId);
  }

  Future<void> dispose() => _deviceChanges.close();

  /// Every track the OS handed out that is still live. The literal "is the camera
  /// light still on" assertion.
  List<FakeTrack> get liveTracks =>
      created.where((FakeTrack track) => track.isLive).toList(growable: false);
}

// The labels the plugin actually reports: `common/cpp/src/flutter_media_stream.cc`
// puts the friendly name in a track's `label`, never a device id. The fakes keep
// that honest so `_Attempt` can only report an id it actually proved.
const String defaultMicLabel = 'Mikrofon (Realtek Audio)';
const String defaultCameraLabel = 'Kamera (Integrated Webcam)';

/// A `MediaDevice` with the labels a Windows device manager would show.
MediaDevice fakeCamera({
  String id = 'cam-1',
  String label = defaultCameraLabel,
}) => MediaDevice(id: id, label: label, kind: MediaDeviceKind.camera);

MediaDevice fakeMicrophone({
  String id = 'mic-1',
  String label = defaultMicLabel,
}) => MediaDevice(id: id, label: label, kind: MediaDeviceKind.microphone);

/// A snapshot with one camera and one microphone, ids `cam-1` / `mic-1`.
MediaDeviceSnapshot fakeDeviceList({List<MediaDevice>? cameras}) =>
    MediaDeviceSnapshot(
      microphones: <MediaDevice>[fakeMicrophone()],
      cameras: cameras ?? <MediaDevice>[fakeCamera()],
    );

/// A shareable screen, as `DesktopCapturer.getSources` would report it.
DisplaySource fakeScreen({
  String id = 'screen-0',
  String name = 'Tüm Ekranlar',
}) => DisplaySource(id: id, name: name, kind: DisplaySourceKind.screen);

/// A shareable window.
DisplaySource fakeWindow({
  String id = 'window-3',
  String name = 'Not Defteri',
}) => DisplaySource(id: id, name: name, kind: DisplaySourceKind.window);

/// Everything wired to fakes, plus the handles a test pokes at.
///
/// Mirrors the shape of `test/session/support/fakes.dart`'s `DriverHarness`, for
/// the same reason: a test that has to assemble five doubles before it can say
/// anything is a test that will test the wrong thing.
final class MediaHarness {
  MediaHarness({
    MediaDeviceSnapshot? devices,
    List<DisplaySource>? sources,
    int? framesEncoded,
    Duration firstFrameTimeout = const Duration(milliseconds: 4),
    Duration firstFramePollInterval = const Duration(milliseconds: 1),
  }) : capture = FakeCapture(),
       registry = FakeRegistry(),
       stats = FakeStats(),
       delay = FakeDelay() {
    capture.devices = devices ?? fakeDeviceList();
    capture.sources = sources ?? <DisplaySource>[fakeScreen()];
    if (framesEncoded != null) stats.frames = framesEncoded;
    controller = MediaController(
      seams: MediaSeams(
        capture: capture,
        senders: registry,
        stats: stats,
        delay: delay.call,
        diagnostics: record,
      ),
      firstFrameTimeout: firstFrameTimeout,
      firstFramePollInterval: firstFramePollInterval,
    );
    states = controller.states.listen(stateEmissions.add);
    deviceChanges = controller.deviceChanges.listen(deviceEmissions.add);
  }
  final FakeCapture capture;
  final FakeRegistry registry;
  final FakeStats stats;
  final FakeDelay delay;

  late final MediaController controller;

  late final StreamSubscription<MediaState> states;
  late final StreamSubscription<MediaDevicesChanged> deviceChanges;

  final List<MediaState> stateEmissions = <MediaState>[];
  final List<MediaDevicesChanged> deviceEmissions = <MediaDevicesChanged>[];

  /// Every `(fault, raw)` pair the controller sent to the diagnostics sink. The
  /// raw half is how a test proves the platform's English text reached the log and
  /// not the state.
  final List<(MediaFault, Object)> rawDiagnostics = <(MediaFault, Object)>[];

  final List<ScreenSharePhase> phaseTrail = <ScreenSharePhase>[];

  void record(MediaFault fault, Object raw) => rawDiagnostics.add((fault, raw));

  /// Opens the controller and starts recording screen-share phases.
  Future<void> open() async {
    controller.watchdog.phases.listen(phaseTrail.add);
    await controller.open();
  }

  /// Every phase a share went through, in order.
  List<ScreenSharePhase> get phases => phaseTrail;

  /// Every track the OS handed back, whether or not the controller kept it.
  List<FakeTrack> get createdTracks => capture.created;

  /// The tracks currently published on a sender.
  List<FakeTrack> get attachedTracks {
    final List<FakeTrack> attached = <FakeTrack>[];
    for (final FakeSender sender in <FakeSender>[
      registry.audio,
      registry.camera,
      registry.screen,
    ]) {
      final MediaTrackHandle? track = sender.track;
      if (track is FakeTrack) attached.add(track);
    }
    return List<FakeTrack>.unmodifiable(attached);
  }

  /// **The leak detector.** Tracks the OS is still holding that nobody is
  /// publishing — a camera light that is on for a call that has ended, a screen
  /// capture of a window the user closed.
  ///
  /// Not the same as "a track that is still running": the microphone of a live call
  /// is *supposed* to be running. What must never be true is a live track with no
  /// sender behind it, which is the state the Tauri build could reach from three
  /// different effects and a failed `replaceTrack`.
  List<FakeTrack> get orphanedTracks {
    final List<FakeTrack> attached = attachedTracks;
    return List<FakeTrack>.unmodifiable(
      capture.created
          .where(
            (FakeTrack track) =>
                track.isLive &&
                !attached.any((FakeTrack live) => identical(live, track)),
          )
          .toList(growable: false),
    );
  }

  /// Every track the OS handed back that has not been stopped, attached or not.
  List<FakeTrack> get liveTracks => capture.liveTracks;

  Future<void> dispose() async {
    await states.cancel();
    await deviceChanges.cancel();
    await controller.dispose();
    await capture.dispose();
    await registry.dispose();
  }
}

/// Yields to the event loop until [reached] is true, then fails loudly rather than
/// hanging when the loop never arrives.
///
/// The watchdog polls through a real `Future`, so a test has to let the loop run.
Future<void> pumpUntil(
  bool Function() reached, {
  String reason = 'the expected point',
  int turns = 500,
}) async {
  for (int turn = 0; turn < turns; turn += 1) {
    if (reached()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(reached(), isTrue, reason: 'the loop never reached $reason');
}
