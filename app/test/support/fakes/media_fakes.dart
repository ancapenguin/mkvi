/// Fakes for every seam `lib/media` exposes: tracks, senders, the sender
/// registry, the stats probe and the capture surface.
///
/// **No test in this directory exercises a real camera, a real microphone, a
/// real peer connection or a real display capture.** What is exercised is the
/// Dart layer: the ladder, the `replaceTrack` discipline, the ledger, the
/// watchdog's schedule, the classifier and the device-change diff.
///
/// The one thing scripted here that a convenient double would get wrong is
/// [ScriptedStatsProbe]: a poll for a sender nobody declared **raises**. The
/// watchdog's entire reason to exist is upstream issue #2137 - a display track
/// that reports success and never encodes a frame - and a probe that answers
/// `0` for every id makes "the watchdog noticed" indistinguishable from "the
/// watchdog was reading a sender that does not exist". Declaring the senders up
/// front is one line and it is what makes the watchdog's assertion real.
library;

import 'dart:async';

import 'package:mkvi/media/media.dart';

import 'script_log.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The labels the plugin actually reports. `flutter_media_stream.cc:408-410`
/// puts the device manager's friendly name in a track's `label`, never a device
/// id, so these are what a controller can match a track back to hardware with.
const String defaultMicLabel = 'Mikrofon (Realtek Audio)';
const String defaultCameraLabel = 'Kamera (Integrated Webcam)';

/// A `MediaDevice` with the label a Windows device manager would show.
MediaDevice fakeCamera({String id = 'cam-1', String label = defaultCameraLabel}) =>
    MediaDevice(id: id, label: label, kind: MediaDeviceKind.camera);

/// A microphone, likewise.
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

/// A shareable screen, as `DesktopCapturer.getSources` reports it.
DisplaySource fakeScreen({String id = 'screen-0', String name = 'Tüm Ekranlar'}) =>
    DisplaySource(id: id, name: name, kind: DisplaySourceKind.screen);

/// A shareable window.
DisplaySource fakeWindow({String id = 'window-3', String name = 'Not Defteri'}) =>
    DisplaySource(id: id, name: name, kind: DisplaySourceKind.window);

/// What a typical desktop offers: one screen, one window.
List<DisplaySource> fakeDisplaySources() => <DisplaySource>[
  fakeScreen(),
  fakeWindow(),
];

/// The sender ids the registry hands out. A stats probe has to be told about
/// these before anything may poll them.
const String audioSenderId = 'sender-audio';
const String cameraSenderId = 'sender-camera';
const String screenSenderId = 'sender-screen';

// ---------------------------------------------------------------------------
// Tracks
// ---------------------------------------------------------------------------

/// A [MediaTrackHandle] that remembers whether it was stopped.
///
/// [stopCount] rather than a bool, because "stopped exactly once" is a stronger
/// and more useful claim than "stopped": a double `stop()` is what turns one
/// leak into a platform error in the middle of the next call.
final class ScriptedTrack implements MediaTrackHandle {
  ScriptedTrack({
    this.kind = 'video',
    this.label = '',
    this.id = '',
    this.stopError,
    this.failOnEnable = false,
  }) {
    log
      ..define('stop', 'counts the stop, or throws when asked to')
      ..define('enabled', 'poll or mute without detaching');
  }

  final ScriptLog log = ScriptLog('ScriptedTrack');

  @override
  final String id;

  @override
  final String kind;

  @override
  String label;

  int stopCount = 0;

  /// Thrown by `stop` when set, to prove the drain continues past a failure.
  final Object? stopError;

  /// Thrown by the `enabled` setter when true, to prove a mute failure is
  /// reported rather than thrown.
  bool failOnEnable = false;

  bool _enabled = true;

  /// True while the OS is holding this track, which is the thing the old build
  /// leaked. The literal mirror of a camera light.
  bool get isLive => stopCount == 0;

  @override
  bool get enabled {
    log.poll('enabled');
    return _enabled;
  }

  @override
  set enabled(bool value) {
    log.record('enabled', detail: value);
    if (failOnEnable) throw 'enabled refused';
    _enabled = value;
  }

  @override
  Future<void> stop() async {
    log.record('stop');
    stopCount += 1;
    final Object? failure = stopError;
    if (failure != null) throw failure;
  }

  @override
  String toString() => 'ScriptedTrack($kind, ${label.isEmpty ? id : label})';
}

// ---------------------------------------------------------------------------
// Senders
// ---------------------------------------------------------------------------

/// A [MediaSenderHandle] that records every `replaceTrack` and can be told to
/// refuse.
///
/// The refusal is what the TypeScript build could not survive: the transport
/// restores both senders when either `replaceTrack` rejects, and the workspace
/// stops the new camera when the publish fails. Both are pinned by [calls] and
/// [failAllReplaces].
final class ScriptedSender implements MediaSenderHandle {
  ScriptedSender({required this.slot, this.id = ''}) {
    log.define('replaceTrack', 'records the track, or throws when asked to');
  }

  final ScriptLog log = ScriptLog('ScriptedSender');

  @override
  final String slot;

  @override
  final String id;

  MediaTrackHandle? _track;

  /// One entry per `replaceTrack`, `null` for a detach. The whole "a mid-call
  /// attach is `replaceTrack` and nothing else" claim is this list.
  final List<MediaTrackHandle?> calls = <MediaTrackHandle?>[];

  /// Thrown by the next `replaceTrack`, then cleared.
  Object? failNextReplace;

  /// Thrown by every `replaceTrack`. Used to prove `MediaController.stop` still
  /// stops the tracks when no sender can be detached.
  Object? failAllReplaces;

  @override
  MediaTrackHandle? get track {
    log.poll('track');
    return _track;
  }

  @override
  Future<void> replaceTrack(MediaTrackHandle? track) async {
    calls.add(track);
    log.record('replaceTrack', detail: track?.toString() ?? 'detach');
    final Object? failure = failAllReplaces ?? failNextReplace;
    if (failNextReplace != null) failNextReplace = null;
    if (failure != null) throw failure;
    _track = track;
  }

  /// The `replaceTrack` calls that were a detach.
  List<MediaTrackHandle?> get detaches =>
      calls.where((MediaTrackHandle? t) => t == null).toList(growable: false);

  @override
  String toString() => 'ScriptedSender($slot, $id)';
}

/// A [MediaSenderRegistry] that hands out [ScriptedSender]s and counts the
/// negotiations the connection asked for.
final class ScriptedSenderRegistry implements MediaSenderRegistry {
  ScriptedSenderRegistry() {
    log
      ..define('open', 'creates the three transceivers and raises one negotiation')
      ..define('close', 'releases the registry')
      ..define('renegotiationNeeded', 'poll')
      ..define('requestNegotiation', 'raises a renegotiation, as the connection does');
  }

  final ScriptLog log = ScriptLog('ScriptedSenderRegistry');

  final ScriptedSender audio = ScriptedSender(
    slot: 'audio',
    id: audioSenderId,
  );
  final ScriptedSender camera = ScriptedSender(
    slot: 'camera',
    id: cameraSenderId,
  );
  final ScriptedSender screen = ScriptedSender(
    slot: 'screen',
    id: screenSenderId,
  );

  /// Every sender this registry owns, in creation order.
  List<ScriptedSender> get all => <ScriptedSender>[audio, camera, screen];

  int openCount = 0;
  int closeCount = 0;

  /// Every renegotiation the *connection* asked for, in order.
  final List<void> negotiations = <void>[];

  /// Every transceiver slot created, in order. The port of
  /// `peer-transport.ts:78-80`: audio, camera, screen, all `sendrecv`.
  final List<String> slots = <String>[];

  /// Thrown by `open` when set. The connection could not be built.
  Object? failOpen;

  final StreamController<void> _renegotiations =
      StreamController<void>.broadcast(sync: true);

  @override
  Future<MediaSenderSet> open() async {
    log.record('open');
    final Object? failure = failOpen;
    if (failure != null) throw failure;
    openCount += 1;
    slots.addAll(<String>['audio', 'camera', 'screen']);
    // Creating the transceivers is what raises the one and only renegotiation,
    // so the fake raises it here exactly as a peer connection would. Nothing in
    // `lib/media` raises another.
    requestNegotiation();
    return MediaSenderSet(audio: audio, camera: camera, screen: screen);
  }

  @override
  Future<void> close() async {
    log.record('close');
    closeCount += 1;
  }

  @override
  Stream<void> get renegotiationNeeded {
    log.poll('renegotiationNeeded');
    return _renegotiations.stream;
  }

  /// Raises a renegotiation request, as the connection would.
  void requestNegotiation() {
    if (_renegotiations.isClosed) return;
    log.record('requestNegotiation');
    negotiations.add(null);
    _renegotiations.add(null);
  }

  Future<void> dispose() => _renegotiations.close();
}

// ---------------------------------------------------------------------------
// Stats
// ---------------------------------------------------------------------------

/// A [MediaStatsProbe] a test drives one poll at a time, with a per-sender
/// tally.
///
/// [frameTally] is the whole point of this class. A blank probe answers `0` for
/// every id, and `0` is a legitimate answer for a second or two after attach -
/// so a blank probe cannot tell "the watchdog is watching a sender that is
/// working" from "the watchdog is watching a sender that does not exist" and
/// cannot tell either from "the encoder never started", which is the one case
/// that matters. Declare the senders, then move the number.
final class ScriptedStatsProbe implements MediaStatsProbe {
  ScriptedStatsProbe({Map<String, int> frameTally = const <String, int>{}}) {
    this.frameTally.addAll(frameTally);
    log.define('framesEncoded', 'answers the tally for a declared sender');
  }

  final ScriptLog log = ScriptLog('ScriptedStatsProbe');

  /// Sender id to the number of frames it has encoded.
  ///
  /// A sender id that is not in this map and not covered by [defaultFrames]
  /// raises: the watchdog asked about something the test never declared.
  final Map<String, int> frameTally = <String, int>{};

  /// The answer for any sender not named in [frameTally]. Null and no entry
  /// means "refuse".
  int? defaultFrames;

  /// Every sender id that was asked about, in order.
  final List<String> asked = <String>[];

  /// How many polls each sender received.
  Map<String, int> get pollCounts {
    final Map<String, int> counts = <String, int>{};
    for (final String id in asked) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts;
  }

  /// Thrown by the next poll, once. The stats call itself failed, which the
  /// watchdog has to survive rather than treat as "no frames".
  Object? failNextPoll;

  /// Sets the tally for [senderId] and declares it.
  void declare(String senderId, int frames) => frameTally[senderId] = frames;

  /// Moves a sender's frame count by [by]. A negative number models the counter
  /// going backwards, which a reconnect does.
  void bump(String senderId, int by) {
    frameTally[senderId] = (frameTally[senderId] ?? 0) + by;
  }

  /// Declares the three senders a default registry hands out, all at [frames].
  void declareDefaultSenders(int frames) {
    declare(audioSenderId, frames);
    declare(cameraSenderId, frames);
    declare(screenSenderId, frames);
  }

  @override
  Future<int> framesEncoded(String senderId) async {
    asked.add(senderId);
    final Object? failure = failNextPoll;
    if (failure != null) {
      failNextPoll = null;
      log.record('framesEncoded', detail: senderId);
      throw failure;
    }
    final int? frames = frameTally[senderId] ?? defaultFrames;
    if (frames == null) {
      throw UnscriptedCallError(
        seam: 'ScriptedStatsProbe',
        member: 'framesEncoded',
        detail: senderId,
        arranged: log.arrangedMembers,
        hint:
            'declare(senderId, frames) or set defaultFrames - an answer of 0 '
            'for an undeclared sender is indistinguishable from a dead encoder',
      );
    }
    log.record('framesEncoded', detail: senderId);
    return frames;
  }
}

// ---------------------------------------------------------------------------
// Capture
// ---------------------------------------------------------------------------

/// A [MediaCapture] that answers with scripted results and can fail the way the
/// plugin does - including by throwing a raw `String`, which
/// `common/cpp/src/flutter_media_stream.cc` really does.
final class ScriptedCapture implements MediaCapture {
  ScriptedCapture({
    this.requireScript = false,
    MediaDeviceSnapshot? devices,
    List<DisplaySource>? sources,
  }) {
    if (devices != null) this.devices = devices;
    if (sources != null) this.sources = sources;
    log
      ..define('enumerateDevices', 'returns the declared snapshot')
      ..define('displaySources', 'returns the declared sources')
      ..define('selectAudioInput', 'records the re-point')
      ..define('deviceChanges', 'poll')
      ..define(
        'getDisplayMedia',
        'returns one video track labelled with the source name',
      );
    if (!requireScript) {
      log.define(
        'getUserMedia',
        'hands back one track per requested device, labelled with the '
            "device manager's friendly name",
      );
    }
  }

  final ScriptLog log = ScriptLog('ScriptedCapture');

  /// When true, a `getUserMedia` with nothing scripted raises. Off by default
  /// because "the OS did exactly what it was asked" is a real and useful
  /// default; on when a test wants the OS's cooperation to be an explicit claim.
  final bool requireScript;

  /// Every request the controller made, in order.
  final List<MediaCaptureRequest> requests = <MediaCaptureRequest>[];

  /// One answer per `getUserMedia`, consumed in order. An entry that is a
  /// [CapturedMedia] is returned; anything else is thrown, which is how the
  /// raw-`String` case is exercised.
  final List<Object?> getUserMediaScript = <Object?>[];

  /// The answer once the script is empty.
  Object? getUserMediaAnswer;

  /// One answer per `getDisplayMedia`, consumed in order, with the same rule.
  final List<Object?> displayScript = <Object?>[];

  /// What the OS reports when asked what it has.
  MediaDeviceSnapshot devices = const MediaDeviceSnapshot();

  /// The sources `displaySources` reports. A test reads
  /// `harness.availableDisplaySources` and picks one of them.
  List<DisplaySource> sources = const <DisplaySource>[];

  /// Thrown by `displaySources` when set.
  Object? failDisplaySources;

  /// Thrown by `enumerateDevices` when set.
  Object? failEnumerate;

  /// Thrown by `selectAudioInput` when set. The native handler validates the id
  /// against the recording device list and fails loudly, which is why a fresh
  /// `getUserMedia` with an unknown id is not a workaround.
  Object? failSelectAudioInput;

  /// Every id `selectAudioInput` was pointed at, in order.
  final List<String> selectedInputs = <String>[];

  /// Thrown by `getDisplayMedia` when set. Takes priority over [displayScript].
  Object? failDisplayMedia;

  /// Every source that was shared, in order.
  final List<DisplaySource> shared = <DisplaySource>[];

  /// Every track the OS handed out, in order. The ledger assertion reads this.
  final List<ScriptedTrack> created = <ScriptedTrack>[];

  int deviceListings = 0;

  final StreamController<void> _deviceChanges =
      StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get deviceChanges {
    log.poll('deviceChanges');
    return _deviceChanges.stream;
  }

  /// Announces a device change, as the OS would. Carries nothing and can fire any
  /// number of times for one physical change - which is the point.
  void announceDeviceChange() {
    if (_deviceChanges.isClosed) return;
    log.record('announceDeviceChange');
    _deviceChanges.add(null);
  }

  @override
  Future<MediaDeviceSnapshot> enumerateDevices() async {
    deviceListings += 1;
    log.record('enumerateDevices');
    final Object? failure = failEnumerate;
    if (failure != null) throw failure;
    return devices;
  }

  @override
  Future<CapturedMedia> getUserMedia(MediaCaptureRequest request) async {
    requests.add(request);
    if (getUserMediaScript.isEmpty && getUserMediaAnswer == null) {
      if (requireScript) {
        log.record('getUserMedia', detail: request);
        throw UnscriptedCallError(
          seam: 'ScriptedCapture',
          member: 'getUserMedia',
          detail: request,
          arranged: log.arrangedMembers,
          hint: 'requireScript is on, so add a scripted answer',
        );
      }
    }
    final Object? scripted = getUserMediaScript.isEmpty
        ? getUserMediaAnswer
        : getUserMediaScript.removeAt(0);
    log.record('getUserMedia', detail: request);
    if (scripted is CapturedMedia) {
      created.addAll(scripted.tracks.whereType<ScriptedTrack>());
      return scripted;
    }
    if (scripted != null) throw scripted;
    // "The OS did what it was asked": one track per requested device, carrying
    // the device manager's friendly name in `label`, which is exactly and only
    // what the plugin puts there.
    final List<ScriptedTrack> tracks = <ScriptedTrack>[];
    if (request.audio) {
      tracks.add(
        ScriptedTrack(
          kind: 'audio',
          label: _labelFor(request.microphoneDeviceId) ?? defaultMicLabel,
        ),
      );
    }
    if (request.video) {
      tracks.add(
        ScriptedTrack(
          kind: 'video',
          label: _labelFor(request.cameraDeviceId) ?? defaultCameraLabel,
        ),
      );
    }
    created.addAll(tracks);
    return CapturedMedia(List<MediaTrackHandle>.unmodifiable(tracks));
  }

  /// The friendly name of an enumerated device, or null when the OS has no such
  /// id. Mirrors `enumerateDevices`, so a fake track's label is a name a
  /// [MediaDeviceSnapshot] can actually be asked about.
  String? _labelFor(String? deviceId) {
    if (deviceId == null) return null;
    return devices.byId(deviceId)?.label;
  }

  @override
  Future<CapturedMedia> getDisplayMedia(DisplaySource source) async {
    log.record('getDisplayMedia', detail: source.id);
    final Object? failure = failDisplayMedia;
    if (failure != null) throw failure;
    if (displayScript.isNotEmpty) {
      final Object? scripted = displayScript.removeAt(0);
      if (scripted is CapturedMedia) {
        created.addAll(scripted.tracks.whereType<ScriptedTrack>());
        shared.add(source);
        return scripted;
      }
      if (scripted != null) throw scripted;
    }
    final ScriptedTrack track = ScriptedTrack(kind: 'video', label: source.name);
    created.add(track);
    shared.add(source);
    return CapturedMedia(<MediaTrackHandle>[track]);
  }

  @override
  Future<List<DisplaySource>> displaySources() async {
    log.record('displaySources');
    final Object? failure = failDisplaySources;
    if (failure != null) throw failure;
    return sources;
  }

  @override
  Future<void> selectAudioInput(String deviceId) async {
    log.record('selectAudioInput', detail: deviceId);
    final Object? failure = failSelectAudioInput;
    if (failure != null) throw failure;
    selectedInputs.add(deviceId);
  }

  Future<void> dispose() => _deviceChanges.close();

  /// Every track the OS handed out that is still live. The literal "is the
  /// camera light still on" assertion.
  List<ScriptedTrack> get liveTracks =>
      created.where((ScriptedTrack t) => t.isLive).toList(growable: false);
}

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------

/// A [MediaDelay] that records what it was asked to wait for and returns at
/// once.
///
/// The whole watchdog schedule then runs in microseconds and [requested] is what
/// the "polled every 500 ms until the 4 s budget" assertion reads.
final class ScriptedMediaDelay {
  ScriptedMediaDelay() {
    log.define('call', 'records the duration and returns at once');
  }

  final ScriptLog log = ScriptLog('ScriptedMediaDelay');

  /// Every duration the watchdog asked for, in order.
  final List<Duration> requested = <Duration>[];

  Future<void> call(Duration duration) async {
    log.record('call', detail: duration);
    requested.add(duration);
    await Future<void>.delayed(Duration.zero);
  }
}

/// One `(fault, raw)` pair a controller sent to its diagnostics sink.
///
/// The raw half is how a test proves the platform's English text reached the log
/// and not the state.
typedef RecordedMediaDiagnostic = (MediaFault fault, Object raw);

/// A [MediaDiagnostics] sink that records rather than prints.
final class RecordingMediaDiagnostics {
  final ScriptLog log = ScriptLog('RecordingMediaDiagnostics');

  final List<RecordedMediaDiagnostic> entries = <RecordedMediaDiagnostic>[];

  void call(MediaFault fault, Object raw) {
    log.record('call', detail: fault.runtimeType.toString());
    entries.add((fault, raw));
  }

  /// The faults only, in order.
  List<MediaFault> get faults => entries
      .map((RecordedMediaDiagnostic e) => e.$1)
      .toList(growable: false);
}
