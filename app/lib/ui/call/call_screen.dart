/// The call screen: the one widget that reads the state machine, and the host
/// that turns its transitions into media and frames.
///
/// ## The two halves, and why they are in one file
///
/// `CallMachine` is not a `ChangeNotifier` — `ROADMAP.md` takes no state-management
/// library and the port's own header says so — so something has to subscribe to
/// it, and something has to own the `MediaController`. [CallUiHost] is that
/// something, and it is here rather than in a file of its own because it is the
/// *only* thing that knows how the two of them fit together: a screen is a
/// function of the snapshot, and the snapshot is a function of the machine and
/// the media controller.
///
/// ## The four things this layer promises
///
/// 1. **The answer screen is the only way in.** [CallUiHost.accept] is a thin
///    pass-through to [CallMachine.accept], the screen renders
///    [IncomingCallScreen] while the status is [CallStatus.incoming] and renders
///    no stage at all in that state, and nothing here reaches
///    [CallMachine.onMediaReady] except as a *reaction* to the media layer having
///    finished. `connected` is therefore unreachable from a button.
/// 2. **The ring timeout closes the screen.** [CallUiHost.remainingRingSeconds] is
///    derived from `CallSession.startedAt` and `CallMachine.ringTimeout`, and the
///    *status* — not a local flag — decides whether the answer screen is up. When
///    the timeout fires the status is `ended` and the screen is gone.
/// 3. **The frame precedes the media.** [CallUiHost.onTransition] walks
///    `CallTransition.actions` **in order** and only ever queues a media step
///    *behind* a frame, so `accept → [SendFrame, PublishMedia]` is the order the
///    outside world observes. [CallUiHost.operations] is the log a test reads,
///    because "the actions are in that order in a list" is not the same claim as
///    "the camera opened after the peer was told".
/// 4. **The stage has a subject and the subject changes.**
///    [CallUiHost.remoteCameraLive] is the only input to [CallStageFocus], which is
///    how `ROADMAP.md`'s reported defect 5 — a stage pinned to the local camera
///    with the peer in a fixed 126 px box — stops being a layout and becomes a
///    decision.
///
/// ## The one seam a caller has to know about
///
/// [CallMachine.onTransition] is a constructor argument, so in production the host
/// *is* the machine's listener:
///
/// ```dart
/// CallMachine(startTimer: asyncCallTimerStarter, onTransition: host.onTransition)
/// ```
///
/// and a test that already has a machine — `FakeCallHarness` builds one with its
/// own listener — hands the same machine to the host, which then runs the
/// transitions its own buttons produce. Both paths go through
/// [_executeTransition], which runs each transition exactly **once** however it
/// arrives; that identity guard is the whole reason the two paths can coexist.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/media/media.dart';
import 'package:mkvi/settings/settings.dart';

import 'call_controls.dart';
import 'call_device_picker.dart';
import 'call_stage.dart';
import 'call_strings.dart';
import 'incoming_call_screen.dart';
import 'local_pip.dart';

/// The keys the call screen answers to.
abstract final class CallScreenKeys {
  /// The screen as a whole.
  static const Key screen = Key('mkvi.call.screen');

  /// What is drawn when the machine holds no live call: nothing at all, and this
  /// is the key that says so. A test asserts the stage is absent from it.
  static const Key empty = Key('mkvi.call.screen.empty');
}

/// What the device picker shows, for the two lists the media controller does not
/// publish itself.
///
/// [MediaController.availableDisplaySources] *is* public, so the share-target list
/// is read from the controller. The camera and microphone lists are not: the
/// controller keeps its snapshot private, and this layer may not add a getter to
/// it. So the inventory is **injected** — which has the second benefit that a
/// picker can be laid out and measured with no capture backend at all.
@immutable
final class CallDeviceInventory {
  /// Creates an inventory.
  const CallDeviceInventory({
    this.cameras = const <MediaDevice>[],
    this.microphones = const <MediaDevice>[],
  });

  /// What the OS enumerates for `videoinput`, in its own order.
  final List<MediaDevice> cameras;

  /// What the OS enumerates for `audioinput`, in its own order.
  final List<MediaDevice> microphones;

  /// A copy with different lists, for a shell that re-enumerates.
  CallDeviceInventory copyWith({
    List<MediaDevice>? cameras,
    List<MediaDevice>? microphones,
  }) => CallDeviceInventory(
    cameras: cameras ?? this.cameras,
    microphones: microphones ?? this.microphones,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallDeviceInventory &&
          listEquals(other.cameras, cameras) &&
          listEquals(other.microphones, microphones);

  @override
  int get hashCode => Object.hash(Object.hashAll(cameras), Object.hashAll(microphones));

  @override
  String toString() =>
      'CallDeviceInventory(${cameras.length} camera, '
      '${microphones.length} microphone)';
}

/// The snapshot a call screen renders from.
///
/// Computed, never cached: [CallUiHost.snapshot] reads the machine and the media
/// controller every time it is asked, so a screen can never paint a value the
/// controller has already released — the failure `MediaState`'s own header warns
/// about when a widget is handed a camera flag directly.
@immutable
final class CallUiSnapshot {
  /// Creates a snapshot.
  const CallUiSnapshot({
    required this.status,
    required this.remainingRingSeconds,
    this.session,
    this.media = const MediaState(),
    this.notice,
    this.focus = CallStageFocus.local,
    this.microphoneMuted = false,
  });

  /// The machine's status.
  final CallStatus status;

  /// The held call, or `null`.
  final CallSession? session;

  /// Everything the media controller knows.
  final MediaState media;

  /// How long the answer screen has left, in whole seconds. `0` unless the status
  /// is [CallStatus.incoming].
  final int remainingRingSeconds;

  /// The Turkish line to show, from the last outcome or the last refusal.
  final String? notice;

  /// Whose camera the main stage is showing.
  final CallStageFocus focus;

  /// Whether the published microphone track is muted.
  final bool microphoneMuted;

  /// Whether the answer screen is the thing to draw. The *only* condition, so
  /// there is no second opinion anywhere in this layer.
  bool get showsAnswerScreen => status == CallStatus.incoming;

  /// Whether the stage and the control bar are the thing to draw.
  bool get showsStage => status.isLive && !showsAnswerScreen;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallUiSnapshot &&
          other.status == status &&
          other.session == session &&
          other.media == media &&
          other.remainingRingSeconds == remainingRingSeconds &&
          other.notice == notice &&
          other.focus == focus &&
          other.microphoneMuted == microphoneMuted;

  @override
  int get hashCode => Object.hash(
    status,
    session,
    media,
    remainingRingSeconds,
    notice,
    focus,
    microphoneMuted,
  );

  @override
  String toString() =>
      'CallUiSnapshot(${status.name}, left: ${remainingRingSeconds}s, '
      'focus: ${focus.name}, media: $media)';
}

/// How often the answer screen asks for a fresh countdown while it is on screen.
///
/// A **clock**, not an animation, which is why it is not read from
/// `AppearanceStyle.duration(...)`: `motion.durations` are transition lengths that
/// reduced-motion replaces with `instant`, and a countdown that reduced motion
/// turned into no countdown at all would read `Kalan süre: 45 sn` for ever. So it
/// is one named constant and the only one of its kind in this package.
///
/// It is the *screen's* clock, not the host's, on purpose: the host is not a
/// widget and has no `dispose`-on-unmount of its own, so a timer it owned would
/// outlive the answer screen and every widget test that pumped it would fail on
/// "a Timer is still pending". The screen is unmounted by the framework, and an
/// `IncomingCallScreen` that is not on screen has nothing to count down.
const Duration callCountdownTick = Duration(seconds: 1);

/// Puts one control frame on the wire. Injected because this layer has no
/// transport.
typedef CallUiFrameSender = void Function(PeerControlMessage frame);

/// Owns the call state machine for a screen, and the media controller beside it.
///
/// ## The mute flag is the host's, and here is why
///
/// [MediaState.microphoneLive] answers "is a track attached". The control bar
/// needs to answer "am I listening to myself", which is a different question:
/// [MediaController.muteMicrophone] sets `track.enabled = false` and changes **no**
/// state field, because a muted track is deliberately still attached. So the host
/// keeps the flag, puts it back when a mute fails, and resets it when the call
/// ends — rather than the media layer growing a field that would then have to be
/// kept true across `stop()`.
final class CallUiHost extends ChangeNotifier {
  /// Creates a host over [machine].
  ///
  /// [now] is required and has no default: the countdown is a clock read, and a
  /// host that guessed one would put a second, invisible copy of the 45 s timeout
  /// into the application. [media] is optional so a screen can be laid out and
  /// measured with no capture backend at all.
  CallUiHost({
    required this.machine,
    required this.now,
    this.media,
    this.sendFrame,
    this.countdownTick = callCountdownTick,
    this.inventory = const CallDeviceInventory(),
  }) {
    final MediaController? media = this.media;
    if (media != null) {
      _mediaStates = media.states.listen((MediaState _) => sync());
      _mediaDevices = media.deviceChanges.listen(
        (MediaDevicesChanged _) => sync(),
      );
    }
  }

  /// The media controller, when the screen has one.
  final MediaController? media;

  /// Where a control frame goes. `null` in a test that counts [operations] and
  /// does not care about the wire.
  final CallUiFrameSender? sendFrame;

  /// The countdown's period, handed to the answer screen. See
  /// [callCountdownTick] for why the screen owns the timer.
  final Duration countdownTick;

  /// The two device lists the picker draws. See [CallDeviceInventory].
  CallDeviceInventory inventory;

  /// Every share target the OS reported, from
  /// [MediaController.availableDisplaySources].
  List<DisplaySource> displaySources = <DisplaySource>[];

  /// Whether the peer's camera is publishing.
  ///
  /// Not a machine fact: [CallMachine] owns this device's side of a call and has
  /// no opinion about the peer's tracks. The transport sets this when a remote
  /// track starts or stops, and it is the only input to [CallStageFocus].
  bool remoteCameraLive = false;

  /// The machine this host drives. Public so a shell can read `missedCalls` and
  /// `outcome` without a second reference.
  final CallMachine machine;

  /// The clock the countdown is measured on. Required, and read on every
  /// snapshot, so the 45 s that is shown is the same 45 s the machine fires.
  ///
  /// Public so a shell can hand the *machine's own* clock to the host and know
  /// that it did; there is no other place in this package that reads a clock.
  final DateTime Function() now;

  /// Every outside-world step the host has taken, in order.
  ///
  /// `'frame:call-accept'`, `'media:publish'`, `'media:release'`. This is the
  /// ordering contract as data, which is what `ROADMAP.md` Faz 5 asks for, and it
  /// is readable without a second machine.
  final List<String> operations = <String>[];

  StreamSubscription<MediaState>? _mediaStates;
  StreamSubscription<MediaDevicesChanged>? _mediaDevices;

  /// Serialises the media steps, so a release can never overtake a publish.
  Future<void> _queue = Future<void>.value();

  /// The transition most recently executed, so a transition handed over twice —
  /// once by the machine's own listener and once by a button — runs once.
  CallTransition? _executed;

  /// The snapshot last announced to listeners.
  CallUiSnapshot _announced = const CallUiSnapshot(
    status: CallStatus.idle,
    remainingRingSeconds: 0,
  );

  String? _notice;
  bool _microphoneMuted = false;

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  /// What a screen should draw, computed from the machine and the media
  /// controller as they are right now.
  CallUiSnapshot get snapshot => CallUiSnapshot(
    status: machine.status,
    session: machine.session,
    media: media?.state ?? const MediaState(),
    remainingRingSeconds: remainingRingSeconds,
    notice: _notice,
    focus: remoteCameraLive ? CallStageFocus.remote : CallStageFocus.local,
    microphoneMuted: _microphoneMuted,
  );

  /// Whole seconds left before the callee's ring timeout fires.
  ///
  /// `0` unless a call is ringing. Derived from [CallSession.startedAt] and the
  /// machine's own `ringTimeout`, so there is exactly one 45 in this application
  /// and it belongs to the machine.
  int get remainingRingSeconds {
    if (!machine.isRinging) return 0;
    final CallSession? session = machine.session;
    if (session == null) return 0;
    final Duration left = machine.ringTimeout - now().difference(session.startedAt);
    if (left.isNegative) return 0;
    return left.inSeconds;
  }

  /// Whether the microphone is published and not muted — what the control bar
  /// shows as "on".
  bool get microphoneAudible =>
      (media?.state.microphoneLive ?? false) && !_microphoneMuted;

  /// Republishes the snapshot when it has changed.
  ///
  /// **The one thing a caller has to remember.** Every button in this package goes
  /// through a method here, and those already call it — so a *screen* never has
  /// to. What a screen's *owner* has to is call it after something that did not
  /// come from a button: the ring timeout firing, a `call-decline` arriving, a
  /// device being unplugged. In production the machine's `onTransition` is
  /// [onTransition] and does it automatically; a test holding a machine with its
  /// own listener calls it once after moving the clock.
  void sync() {
    final CallUiSnapshot next = snapshot;
    if (next == _announced) return;
    _announced = next;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Answering
  // ---------------------------------------------------------------------------

  /// Answers the ringing screen.
  ///
  /// The only path this package offers towards [CallStatus.connected], and it is a
  /// pass-through: [CallMachine.accept] owns the guard that refuses an id which is
  /// no longer on screen, and the host does not second-guess it.
  CallTransition accept() => _run(machine.accept());

  /// Declines the ringing screen. Idempotent, because the machine is.
  CallTransition decline() => _run(machine.decline());

  /// Ends whatever call is held. Idempotent.
  CallTransition end() => _run(machine.end());

  // ---------------------------------------------------------------------------
  // Mid-call media
  // ---------------------------------------------------------------------------

  /// Mutes or unmutes the published microphone.
  Future<void> toggleMicrophone() async {
    final MediaController? media = this.media;
    if (media == null) return;
    final bool wanted = !_microphoneMuted;
    final MediaOutcome outcome = await media.muteMicrophone(muted: wanted);
    // A mute that failed is reported by the controller as a `MediaState.fault`;
    // the flag follows the sender rather than the press.
    if (outcome is! MediaFailed) _microphoneMuted = wanted;
    sync();
  }

  /// Turns the camera on or off.
  ///
  /// This is the button `ROADMAP.md`'s reported defect 6 is about — "sesliyken
  /// kamera açılamıyor" — and the reason it works during an audio call is
  /// structural rather than lucky: the camera transceiver was negotiated as
  /// `sendrecv` when the connection was built, so this is one `replaceTrack` and
  /// no offer.
  Future<void> toggleCamera() async {
    final MediaController? media = this.media;
    if (media == null) return;
    if (media.state.cameraLive) {
      await media.disableCamera();
    } else {
      await media.enableCamera(deviceId: media.state.cameraDeviceId);
    }
    sync();
  }

  /// Starts or stops the screen share.
  ///
  /// [sourceId] is the target the user picked; `null` means "the first one the OS
  /// offers", which is what the picker omits when nothing is selected. A share
  /// that starts and never delivers a frame is [ScreenSharePhase.stalled] and says
  /// so on the stage — see [ScreenShareWatchdog] for why nothing upstream can.
  Future<void> toggleScreenShare({String? sourceId}) async {
    final MediaController? media = this.media;
    if (media == null) return;
    if (media.state.screenShare.isAttached) {
      await media.stopScreenShare();
    } else {
      await media.startScreenShare(sourceId: sourceId);
    }
    sync();
  }

  /// Republishes a different camera. The controller **refuses** an id the OS does
  /// not have rather than silently keeping the old one, because a switch that
  /// appears to work and does not is worse than one that refuses.
  Future<void> selectCamera(String deviceId) async {
    await media?.switchCamera(deviceId);
    sync();
  }

  /// Re-points the microphone.
  Future<void> selectMicrophone(String deviceId) async {
    await media?.switchMicrophone(deviceId);
    sync();
  }

  /// Reads the share-target list, which is the one list the media controller
  /// publishes itself.
  Future<void> refreshDisplaySources() async {
    final MediaController? media = this.media;
    if (media == null) return;
    displaySources = await media.availableDisplaySources();
    sync();
  }

  // ---------------------------------------------------------------------------
  // Transition handling
  // ---------------------------------------------------------------------------

  /// The machine's `onTransition` in production: `onTransition: host.onTransition`.
  ///
  /// Safe to pass to a machine the host also drives, because
  /// [_executeTransition] runs each transition exactly once.
  void onTransition(CallTransition transition) => _executeTransition(transition);

  CallTransition _run(CallTransition transition) {
    _executeTransition(transition);
    return transition;
  }

  /// Runs one transition's actions, in the order the machine listed them.
  void _executeTransition(CallTransition transition) {
    if (identical(_executed, transition)) return;
    _executed = transition;
    for (final CallAction action in transition.actions) {
      if (action is SendFrame) {
        // Synchronous and first: the decision reaches the peer before anything is
        // captured, which is the whole of reported defect 4.
        operations.add('frame:${action.message.type}');
        sendFrame?.call(action.message);
      } else if (action is PublishMedia) {
        // Queued, never awaited inline. The queue is what makes "the frame went
        // out first" true even though the media step is asynchronous.
        operations.add('media:publish');
        _enqueue(() => _publishMedia(action));
      } else if (action is ReleaseMedia) {
        operations.add('media:release');
        _enqueue(_releaseMedia);
      }
    }
    final CallOutcome? outcome = transition.outcome;
    if (outcome != null && outcome.notice.isNotEmpty) {
      _notice = outcome.notice;
    } else if (transition.refusal != null) {
      _notice = transition.refusal!.message;
    }
    if (transition.status == CallStatus.ended) _microphoneMuted = false;
    sync();
  }

  Future<void> _publishMedia(PublishMedia request) async {
    final MediaController? media = this.media;
    if (media == null) return;
    final MediaCallStarted started = await media.startCall(
      video: request.video,
      cameraDeviceId: media.state.cameraDeviceId,
      microphoneDeviceId: media.state.microphoneDeviceId,
    );
    // The only two calls this package makes into the machine that are not
    // decisions, and both are *reactions*: `connected` may not be claimed before
    // `replaceTrack` has finished, and a capture that failed declines the call
    // with the reason the media layer gave.
    if (started is MediaCallLive) {
      _run(machine.onMediaReady());
    } else if (started is MediaCallFailed) {
      _run(machine.fail(started.message));
    }
  }

  Future<void> _releaseMedia() async {
    await media?.stop();
  }

  void _enqueue(Future<void> Function() work) {
    _queue = _queue.then((_) => work());
  }

  @override
  void dispose() {
    unawaited(_mediaStates?.cancel());
    unawaited(_mediaDevices?.cancel());
    _mediaStates = null;
    _mediaDevices = null;
    super.dispose();
  }
}

/// The screen a shell mounts: [IncomingCallScreen] or the stage and the control
/// bar, and nothing else.
class CallScreen extends StatefulWidget {
  /// Creates the call screen.
  const CallScreen({
    super.key,
    required this.host,
    required this.peerName,
    this.pipCorner = LocalPipCorner.topRight,
    this.showDevicePicker = false,
  });

  /// The host. The screen holds no call state of its own.
  final CallUiHost host;

  /// Who the other side is, in the name the app knows them by.
  final String peerName;

  /// Which corner the small picture is in.
  final LocalPipCorner pipCorner;

  /// Whether the device picker is open below the stage.
  final bool showDevicePicker;

  /// The one line the stage shows for [snap].
  ///
  /// Every branch is a string the call or media layer already owns, and each one
  /// names a *state* rather than reporting an event — a screen that is still
  /// connecting says so, instead of the empty stage
  /// `ChatCallWorkspace.tsx:541` showed and `CallMessages.waitingForAnswer` was
  /// written to replace.
  ///
  /// Static and public so a test can name the sentence for a state the machine
  /// passes through too quickly to hold on screen: [CallStatus.connecting] lasts
  /// exactly as long as the media step takes, which against a fake is one
  /// microtask, and a caption nobody can catch is a caption nobody has tested.
  static String captionFor(CallUiSnapshot snap) {
    if (snap.status == CallStatus.outgoing) return CallUiReused.waitingForAnswer;
    if (snap.status == CallStatus.connecting) {
      return CallUiTr.connectingCaption;
    }
    // A share is described by the phase label, which is the only thing that can
    // say "the first frame has not arrived yet" — the whole of upstream #2137.
    if (snap.media.screenShare.isAttached) {
      return snap.media.screenShare.label;
    }
    if (!snap.media.cameraLive && snap.focus == CallStageFocus.local) {
      return CallUiReused.noActiveVideo;
    }
    return snap.focus == CallStageFocus.remote
        ? CallUiTr.remoteVideoLabel
        : CallUiTr.localVideoLabel;
  }

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallUiHost get _host => widget.host;

  @override
  void initState() {
    super.initState();
    _host.addListener(_onHostChanged);
  }

  @override
  void didUpdateWidget(CallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, _host)) {
      oldWidget.host.removeListener(_onHostChanged);
      _host.addListener(_onHostChanged);
    }
  }

  @override
  void dispose() {
    _host.removeListener(_onHostChanged);
    super.dispose();
  }

  void _onHostChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Read straight from the host on every build rather than from a field
    // refreshed in `initState`: a screen that caches the status is a screen that
    // can paint a call as open one frame after it ended.
    final CallUiSnapshot snap = _host.snapshot;
    final Widget body;
    if (snap.showsAnswerScreen) {
      // The answer screen, and *only* the answer screen. No `CallStage` is built
      // on this branch, which is what makes "the call has not opened" a
      // structural fact rather than a flag somebody has to keep in step.
      body = IncomingCallScreen(
        peerName: widget.peerName,
        mode: snap.session?.mode ?? CallMode.audio,
        remainingSeconds: snap.remainingRingSeconds,
        countdownTick: _host.countdownTick,
        // The screen has no clock of its own — the ring timeout and its deadline
        // are the machine's — so it asks for a fresh read once per tick and the
        // host answers from the machine's own clock.
        onRefresh: _host.sync,
        onAccept: _host.accept,
        onDecline: _host.decline,
      );
    } else if (snap.showsStage) {
      body = _live(context, snap);
    } else {
      body = const SizedBox.shrink(key: CallScreenKeys.empty);
    }
    return KeyedSubtree(key: CallScreenKeys.screen, child: body);
  }

  /// The stage, the notice line and the control bar, for every live status that
  /// is not an answer screen.
  Widget _live(BuildContext context, CallUiSnapshot snap) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final MediaState media = snap.media;

    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: CallStage(
            caption: CallScreen.captionFor(snap),
            focus: snap.focus,
            // No small picture when there is only one camera to show: an empty
            // second box is a box the user will ask about.
            showPip: media.cameraLive || snap.focus == CallStageFocus.remote,
            pipCorner: widget.pipCorner,
            pipCaption: media.screenShare.isAttached
                ? media.screenShare.label
                : null,
          ),
        ),
        if (snap.notice != null) ...<Widget>[
          SizedBox(height: style.gap('2')),
          Text(
            snap.notice!,
            textAlign: TextAlign.center,
            style: style.styleOf('sm').copyWith(color: style.role('textMuted')),
          ),
        ],
        SizedBox(height: style.gap('4')),
        CallControls(
          microphoneLive: media.microphoneLive,
          microphoneMuted: snap.microphoneMuted,
          cameraLive: media.cameraLive,
          screenShareAttached: media.screenShare.isAttached,
          // An outgoing call nobody has answered has nothing to toggle: the
          // controls are disabled rather than absent, so the bar does not change
          // shape when the peer finally picks up.
          microphoneEnabled: snap.status.isSettled,
          cameraEnabled: snap.status.isSettled,
          screenShareEnabled: snap.status.isSettled,
          onToggleMicrophone: _host.toggleMicrophone,
          onToggleCamera: _host.toggleCamera,
          onToggleScreenShare: () => _host.toggleScreenShare(
            sourceId: _host.displaySources.isEmpty
                ? null
                : _host.displaySources.first.id,
          ),
          onOpenDevices: _host.refreshDisplaySources,
          onHangUp: _host.end,
        ),
        if (widget.showDevicePicker) ...<Widget>[
          SizedBox(height: style.gap('4')),
          CallDevicePicker(
            cameras: _host.inventory.cameras,
            microphones: _host.inventory.microphones,
            displaySources: _host.displaySources,
            cameraDeviceId: media.cameraDeviceId,
            microphoneDeviceId: media.microphoneDeviceId,
            displaySourceId: media.screenSourceId,
            onSelectCamera: _host.selectCamera,
            onSelectMicrophone: _host.selectMicrophone,
            onStartShare: (String id) => _host.toggleScreenShare(sourceId: id),
          ),
        ],
      ],
    );
  }
}
