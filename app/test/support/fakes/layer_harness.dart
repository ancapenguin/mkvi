/// One ready-made wiring per layer, so a test spends its lines on the assertion
/// and not on assembling five doubles.
///
/// Each harness owns the fakes of its layer **as public fields** and exposes the
/// real controller as well. A test reads `harness.identity.calls` rather than
/// reaching into a closure, and a test that wants a seam the harness did not
/// script can change the field - the harness never hides a collaborator.
library;

import 'dart:async';

import 'package:mkvi/call/call.dart';
import 'package:mkvi/chat/chat_controller.dart';
import 'package:mkvi/chat/history_store.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/media/media.dart';
import 'package:mkvi/session/session.dart';
import 'package:mkvi/signaling/rendezvous_client.dart';
import 'package:mkvi/signaling/signal_payload.dart';
import 'package:mkvi/update/update.dart';

import 'call_fakes.dart';
import 'chat_fakes.dart';
import 'media_fakes.dart';
import 'script_log.dart';
import 'session_fakes.dart';
import 'update_fakes.dart';

// ---------------------------------------------------------------------------
// Call
// ---------------------------------------------------------------------------

/// A [CallMachine] on a controlled clock, with the transitions recorded.
///
/// `advance` moves the clock and fires everything that comes due, so "the ring
/// timer is 45 s and the offer timer is 45 s and they are different timers" is a
/// timing assertion rather than a comment.
final class FakeCallHarness {
  FakeCallHarness({DateTime? startAt}) {
    machine = CallMachine(
      startTimer: clock.start,
      now: clock.call,
      idFactory: ids.call,
      onTransition: transitions.add,
    );
  }

  /// The clock and the timer registry. One value, so a deadline is a real
  /// instant.
  final FakeCallClock clock = FakeCallClock();

  /// The id factory the machine draws from.
  final FakeCallIds ids = FakeCallIds();

  /// Every transition the machine reported, in order. A refused or stale step is
  /// not here, which is what makes "the UI was not woken" assertable.
  final List<CallTransition> transitions = <CallTransition>[];

  late final CallMachine machine;

  /// Moves the clock forward and fires everything that comes due.
  void advance(Duration by) => clock.advance(by);

  /// The timers still waiting to fire.
  List<ArmedCallTimer> get liveTimers => clock.armed;

  /// The single live timer, or a loud failure. A test that means "the ring
  /// timer" must not silently get the offer timer.
  ArmedCallTimer get onlyLiveTimer => clock.only;

  /// Every frame the machine asked to be sent, in order.
  List<PeerControlMessage> get sent => <PeerControlMessage>[
    for (final CallTransition transition in transitions) ...transition.frames,
  ];

  /// Puts the machine in the callee seat, as the transport does when a parsed
  /// `call-offer` arrives on the data channel.
  CallTransition ring(String id, [CallMode mode = CallMode.audio]) =>
      machine.onIncomingOffer(CallOfferMessage(id: id, mode: mode));

  /// Puts the machine in the caller seat.
  CallTransition dial(CallMode mode, {String? id}) =>
      machine.startOutgoing(mode, id: id);

  /// The id the machine generated for the outgoing call, or null.
  String? get dialedId => machine.session?.id;

  /// Accepts a ringing invitation.
  CallTransition accept() => machine.accept();

  /// Ends the held call.
  CallTransition end({bool notifyPeer = true}) =>
      machine.end(notifyPeer: notifyPeer);

  /// A callee that has answered and published its media.
  CallTransition answerAndConnect(
    String id, [
    CallMode mode = CallMode.audio,
  ]) {
    ring(id, mode);
    machine.accept();
    return machine.onMediaReady();
  }

  /// A caller whose invitation the peer accepted and whose media is published.
  CallTransition acceptedAndConnected(
    String id, [
    CallMode mode = CallMode.audio,
  ]) {
    dial(mode, id: id);
    machine.onRemoteAccept(callId: id);
    return machine.onMediaReady();
  }

  /// The frames of one transition, in the order the machine listed them.
  static List<PeerControlMessage> framesOf(CallTransition transition) =>
      transition.frames.toList(growable: false);

  /// The action kinds of one transition, in order. Cheaper to read in a failure
  /// message than the actions themselves.
  static List<String> shapeOf(CallTransition transition) => <String>[
    for (final CallAction action in transition.actions)
      action.runtimeType.toString(),
  ];

  void dispose() => machine.dispose();
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

/// A [ChatController] with a scripted channel, an in-memory log and a sink.
final class FakeChatHarness {
  FakeChatHarness({
    bool channelOpen = true,
    List<StoredMessage> history = const <StoredMessage>[],
    String directory = '/tmp/mkvi',
  }) {
    channel = ScriptedChatChannel(isOpen: channelOpen);
    store = ScriptedHistoryStore(seed: history);
    files = ScriptedFileSink(directory: directory);
    controller = ChatController(
      channel: channel,
      store: store,
      idFactory: ids.call,
    );
    subscription = controller.states.listen(snapshots.add);
    // The controller keeps its own view of the channel; starting it in step with
    // the seam is what makes `isChannelOpen` mean something on the first line.
    controller.reportChannelOpen(channelOpen);
  }

  late final ScriptedChatChannel channel;
  late final ScriptedHistoryStore store;
  late final ScriptedFileSink files;
  final CountingChatIds ids = CountingChatIds();

  late final ChatController controller;
  late final StreamSubscription<ChatSnapshot> subscription;

  /// Every snapshot the controller emitted, in order.
  final List<ChatSnapshot> snapshots = <ChatSnapshot>[];

  /// Sends one line and returns what the controller said.
  SendResult send(String body) => controller.send(body);

  /// Takes one `chat` frame off the wire, as the transport would.
  bool receive(ChatMessage frame) => controller.receive(frame);

  /// Reports that the data channel opened or closed, as the reconnect loop does.
  ///
  /// Both sides move together on purpose: the controller keeps its own
  /// `_channelOpen` and the seam keeps its own `isOpen`, and a flush is only
  /// attempted when *both* are true. A harness that moved one without the other
  /// would silently test a controller that believes the channel is up while the
  /// fake is not.
  void reportChannelOpen(bool open) {
    channel.isOpen = open;
    controller.reportChannelOpen(open);
  }

  /// Opens the channel and flushes the queue.
  void openChannel() => reportChannelOpen(true);

  /// Closes the channel. The queue survives; the delivery state does not change.
  void closeChannel() => reportChannelOpen(false);

  Future<void> dispose() async {
    await subscription.cancel();
    await controller.dispose();
  }
}

/// Mints deterministic, **distinct**, well-formed message ids.
///
/// `randomTransferId()` is the production seam and is exercised by the protocol
/// suite; here a test needs to *name* the id it is about to look up.
///
/// The ids are 32 lowercase hex characters, the only shape `parseControl`
/// accepts, so a frame the controller produces is a frame the peer can read. The
/// last eight characters are a counter, so two lines in one conversation can
/// never collide - a shared id is exactly what makes a controller drop a line.
final class CountingChatIds {
  CountingChatIds({this.head = 'aaaaaaaaaaaaaaaa'});

  /// The leading 24 characters every id shares, so a test can read at a glance
  /// that an id came from this factory.
  final String head;

  int calls = 0;

  String call() {
    calls += 1;
    return head + calls.toRadixString(16).padLeft(8, '0');
  }

  /// A one-off factory for exactly [n] ids, for a test that names the id it
  /// expects rather than reading it back.
  static String Function() sequence(int n) {
    int next = 0;
    return () =>
        'aaaaaaaaaaaaaaaa${(next++).toRadixString(16).padLeft(8, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Media
// ---------------------------------------------------------------------------

/// A [MediaController] with every media seam faked, plus the leak detector.
final class FakeMediaHarness {
  FakeMediaHarness({
    MediaDeviceSnapshot? devices,
    List<DisplaySource>? sources,
    int? framesEncoded,
    Duration firstFrameTimeout = const Duration(milliseconds: 4),
    Duration firstFramePollInterval = const Duration(milliseconds: 1),
  }) {
    capture = ScriptedCapture(
      devices: devices ?? fakeDeviceList(),
      sources: sources ?? fakeDisplaySources(),
    );
    registry = ScriptedSenderRegistry();
    stats = ScriptedStatsProbe();
    // The three senders a default registry hands out, declared up front: a poll
    // for an undeclared sender raises rather than answering 0, which is the one
    // answer that would make the watchdog's assertion vacuous.
    stats.declareDefaultSenders(framesEncoded ?? 0);
    delay = ScriptedMediaDelay();
    diagnostics = RecordingMediaDiagnostics();
    controller = MediaController(
      seams: MediaSeams(
        capture: capture,
        senders: registry,
        stats: stats,
        delay: delay.call,
        diagnostics: diagnostics.call,
      ),
      firstFrameTimeout: firstFrameTimeout,
      firstFramePollInterval: firstFramePollInterval,
    );
    states = controller.states.listen(stateEmissions.add);
    deviceChanges = controller.deviceChanges.listen(deviceEmissions.add);
  }

  late final ScriptedCapture capture;
  late final ScriptedSenderRegistry registry;
  late final ScriptedStatsProbe stats;
  late final ScriptedMediaDelay delay;
  late final RecordingMediaDiagnostics diagnostics;

  late final MediaController controller;

  late final StreamSubscription<MediaState> states;
  late final StreamSubscription<MediaDevicesChanged> deviceChanges;

  final List<MediaState> stateEmissions = <MediaState>[];
  final List<MediaDevicesChanged> deviceEmissions = <MediaDevicesChanged>[];

  final List<ScreenSharePhase> phaseTrail = <ScreenSharePhase>[];

  /// Every `(fault, raw)` pair the controller sent to the diagnostics sink.
  List<RecordedMediaDiagnostic> get rawDiagnostics => diagnostics.entries;

  /// Opens the controller and starts recording screen-share phases.
  Future<void> open() async {
    controller.watchdog.phases.listen(phaseTrail.add);
    await controller.open();
  }

  /// The sources the OS would offer, as the controller sees them.
  Future<List<DisplaySource>> availableDisplaySources() =>
      controller.availableDisplaySources();

  /// Every phase a share went through, in order.
  List<ScreenSharePhase> get phases => phaseTrail;

  /// Every track the OS handed back, whether or not the controller kept it.
  List<ScriptedTrack> get createdTracks => capture.created;

  /// The tracks currently published on a sender.
  List<ScriptedTrack> get attachedTracks {
    final List<ScriptedTrack> attached = <ScriptedTrack>[];
    for (final ScriptedSender sender in registry.all) {
      final MediaTrackHandle? track = sender.track;
      if (track is ScriptedTrack) attached.add(track);
    }
    return List<ScriptedTrack>.unmodifiable(attached);
  }

  /// **The leak detector.** Tracks the OS is still holding that nobody is
  /// publishing - a camera light on for a call that has ended, a screen capture
  /// of a window the user closed.
  ///
  /// Not the same as "a track that is still running": the microphone of a live
  /// call is *supposed* to be running. What must never be true is a live track
  /// with no sender behind it.
  List<ScriptedTrack> get orphanedTracks {
    final List<ScriptedTrack> attached = attachedTracks;
    return List<ScriptedTrack>.unmodifiable(
      capture.created
          .where(
            (ScriptedTrack track) =>
                track.isLive &&
                !attached.any((ScriptedTrack live) => identical(live, track)),
          )
          .toList(growable: false),
    );
  }

  /// Every track the OS handed back that has not been stopped, attached or not.
  List<ScriptedTrack> get liveTracks => capture.liveTracks;

  Future<void> dispose() async {
    await states.cancel();
    await deviceChanges.cancel();
    await controller.dispose();
    await capture.dispose();
    await registry.dispose();
  }
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// A [SessionController] with every session seam faked, and the counters
/// `ROADMAP.md` Faz 4 asks for.
final class FakeSessionHarness {
  FakeSessionHarness({
    String? endpoint,
    String peerPublicKey = fakePeerPublicKey,
    String localPublicKey = fakeLocalPublicKey,
    Map<String, String> settings = const <String, String>{},
  }) {
    identity = FakeDeviceIdentityLoader(publicKey: localPublicKey);
    peerStore = FakePeerStore();
    verifier = FakePairingVerifier(accept: true);
    deviceIds = FakePairScopedDeviceIdFactory();
    transport = FakePeerTransport();
    // The endpoint travels through the local settings, which is where
    // `readEndpoint` reads it from. Seeding the map instead of assigning a field
    // is what makes a test that asserts on the socket URL actually see it.
    localSettings = FakeLocalSettings(
      seed: <String, String>{
        if (endpoint case final String seeded) SettingsKeys.rendezvousEndpoint: seeded,
        ...settings,
      },
    );
    controller = SessionController(
      peerStore: peerStore,
      settings: localSettings,
      identityLoader: identity,
      rendezvousClientFactory: newClient,
      verifyPairing: verifier.call,
      transport: transport,
      pairScopedDeviceId: deviceIds.call,
      sessionIdFactory: sessionIds,
      delay: delay.call,
    );
    subscription = controller.states.listen(stateEmissions.add);
    signalEndpoint = endpoint ?? defaultRendezvousEndpoint;
    peerKey = peerPublicKey;
  }

  late final FakeLocalSettings localSettings;
  late final FakePeerStore peerStore;
  late final FakeDeviceIdentityLoader identity;
  late final FakePairingVerifier verifier;
  late final FakePairScopedDeviceIdFactory deviceIds;
  late final FakePeerTransport transport;
  late final ScriptedDelay delay = ScriptedDelay();
  late final ScriptedSignalingSocketFactory sockets =
      ScriptedSignalingSocketFactory();

  /// A fresh session id on every call, so a replayed identity frame from a dead
  /// socket cannot verify against a live epoch.
  final SessionIdFactory sessionIds = countingSessionIds();

  late final SessionController controller;
  late final StreamSubscription<SetupState> subscription;

  final List<SetupState> stateEmissions = <SetupState>[];

  /// How many times [bootstrap] was called. A second bootstrap is a second
  /// identity read, and a second identity read is the Faz 4 defect.
  int bootstrapCalls = 0;

  /// The signaling endpoint the controller reads. Defaults to the production
  /// one, because that is what a device with an unwritten store uses; pass
  /// [endpoint] to `FakeSessionHarness` to seed `SettingsKeys.rendezvousEndpoint`
  /// and have the socket URL follow.
  late final String signalEndpoint;

  /// The peer's public key the controller was wired with.
  late final String peerKey;

  /// A client over this harness's socket factory. One per epoch, never reused.
  RendezvousClient newClient() => RendezvousClient(socketFactory: sockets.call);

  // -- seeding ---------------------------------------------------------------

  /// Never paired on this device. The only state that may show pairing.
  void seedAbsent() => peerStore.readAnswer = const PeerAbsent();

  /// Paired, and readable.
  void seedPaired([KnownPeer? peer]) =>
      peerStore.readAnswer = PeerFound(peer ?? fakeKnownPeer());

  /// Paired, and not readable. The `broken` state, never the pairing screen.
  void seedUnreadable([PeerReadFailure failure = const PeerDecryptFailed()]) =>
      peerStore.readAnswer = PeerUnreadable(failure);

  /// The store itself is unreachable, which is a throw rather than a value.
  void seedUnavailable() =>
      peerStore.readThrows = StateError('Güvenli depo erişilemiyor.');

  // -- driving ---------------------------------------------------------------

  /// Reads the store and settles into a state, counting the call.
  ///
  /// The counter is the point: `identity.calls` alone cannot distinguish "one
  /// bootstrap" from "three", because the reconnect loop reads the identity on
  /// every attempt. [identityCallsAtBootstrap] records the other half.
  Future<void> bootstrap() async {
    bootstrapCalls += 1;
    identityCallsAtBootstrap.add(identity.calls);
    await controller.bootstrap();
  }

  /// The number of `identity.calls` before each [bootstrap]. The difference
  /// between two entries is how many identities one bootstrap minted.
  final List<int> identityCallsAtBootstrap = <int>[];

  /// The socket of the current attempt.
  ScriptedSignalingSocket get socket => sockets.last;

  /// The socket of attempt [index], counting from the first one created.
  ScriptedSignalingSocket socketAt(int index) => sockets.socketAt(index);

  /// Sends the peer identity frame to [socket], then lets the loop run.
  Future<void> verifyPeer({
    ScriptedSignalingSocket? target,
    String publicKey = fakePeerPublicKey,
    bool legacy = false,
  }) async {
    announceIdentity(
      target ?? socket,
      publicKey: publicKey,
      legacy: legacy,
    );
    await settle();
  }

  /// Every reconnect event, in order.
  List<T> eventsOf<T extends ReconnectEvent>() {
    final List<T> found = <T>[];
    for (final ReconnectEvent event in driverEvents) {
      if (event is T) found.add(event);
    }
    return found;
  }

  final List<ReconnectEvent> driverEvents = <ReconnectEvent>[];
  StreamSubscription<ReconnectEvent>? _driverSubscription;

  /// Starts recording the reconnect loop's events. Call it after the controller
  /// exists; [bootstrap] does it on the first call.
  void watchDriver() {
    _driverSubscription ??= controller.driver.events.listen(driverEvents.add);
  }

  Future<void> dispose() async {
    await _driverSubscription?.cancel();
    await subscription.cancel();
    await controller.dispose();
  }
}

// ---------------------------------------------------------------------------
// Update
// ---------------------------------------------------------------------------

/// An [UpdateClient] with every update seam faked, and the scenarios the layer's
/// refusals are named after.
final class FakeUpdateHarness {
  FakeUpdateHarness({
    String feedUrl = fakeLiveFeedUrl,
    String publicKey = fakePrehashedKey,
    String version = fakeCurrentVersion,
    List<int>? pinnedManifest,
    int artifactMaxBytes = 1024 * 1024,
    int manifestMaxBytes = 16 * 1024,
    Duration minCheckInterval = Duration.zero,
  }) {
    // The verifier reads the bytes the file store actually holds, which is what
    // makes it a whole-content comparison rather than a flag.
    files = ScriptedUpdateFileStore();
    verifier = ScriptedSignatureVerifier(files: files);
    config = UpdateConfig(
      currentVersion: version,
      feedUrl: Uri.parse(feedUrl),
      publicKeyB64: publicKey,
      pinnedManifest: pinnedManifest,
      artifactMaxBytes: artifactMaxBytes,
      manifestMaxBytes: manifestMaxBytes,
      minCheckInterval: minCheckInterval,
    );
    fetcher = ScriptedHttpFetcher();
    installer = ScriptedInstallerLauncher();
    clock = ScriptedUpdateClock();
    // The one good default, written down: a prehashed key and a started
    // installer. Every refusal scenario below changes exactly one of them, so a
    // failure names which seam moved.
    verifier.keyState = const ReleaseKeyPrehashed();
    installer.outcome = const InstallStarted();
    client = UpdateClient(
      config: config,
      fetcher: fetcher,
      verifier: verifier,
      installer: installer,
      files: files,
      clock: clock,
    );
    subscription = client.events.listen(events.add);
  }

  late final ScriptedHttpFetcher fetcher;
  late final ScriptedUpdateFileStore files;
  late final ScriptedSignatureVerifier verifier;
  late final ScriptedInstallerLauncher installer;
  late final ScriptedUpdateClock clock;

  late final UpdateConfig config;
  late final UpdateClient client;
  late final StreamSubscription<UpdateEvent> subscription;

  final List<UpdateEvent> events = <UpdateEvent>[];

  /// The bytes the release key is pretending to have signed.
  List<int> get artifact => fakeSignedArtifact();

  /// Lets the broadcast event stream deliver everything a test has already
  /// caused. A stream listener runs in a later turn than the `add`, so a report
  /// returned from `check()` can arrive before the last event has landed.
  Future<void> settleEvents() => settle();

  // -- scenarios -------------------------------------------------------------

  /// A feed offering a newer version, and a download of [bytes].
  ///
  /// The signed digest is recomputed **only** when [bytes] is left out. A test
  /// that passes different bytes is testing a rejection, and re-signing them
  /// here would quietly turn that test into a pass.
  void offerUpdate({List<int>? feed, List<int>? bytes, int declaredLength = -1}) {
    final List<int> payload = bytes ?? artifact;
    fetcher.feed = FeedReadOk(body: feed ?? fakeFeedJson(), declaredLength: null);
    final int declared = declaredLength < 0 ? payload.length : declaredLength;
    fetcher.downloadEvents = fakeArtifactEvents(payload, declaredLength: declared);
    if (bytes == null) verifier.signedDigest = fakeDigest64(payload);
  }

  /// The endpoint answers 404 - the failure this product shipped with, because
  /// the URL in `src-tauri/tauri.conf.json:43` names a repository that does not
  /// exist. A transport failure, not a malformed manifest.
  void feedNotFound() =>
      fetcher.feed = const FeedReadFailed('http 404');

  /// The feed read never completed. Not the same as a 404, and the client says
  /// so differently.
  void feedUnreachable([String detail = 'bağlantı yok']) =>
      fetcher.feed = FeedReadFailed(detail);

  /// The configured key is the retired "Ed" form, so every signature it can
  /// produce is refused. Reported before a user ever sees an update fail.
  void useLegacyKey() {
    verifier.keyState = const ReleaseKeyLegacy();
  }

  /// The key is not a minisign block at all.
  void useUnreadableKey() {
    verifier.keyState = const ReleaseKeyUnreadable();
  }

  /// The verifier bridge is not wired, so nothing was checked and everything is
  /// refused.
  void useUnavailableVerifier() {
    verifier.keyState = const ReleaseKeyUnavailable();
  }

  /// The bytes on disk are not the ones that were signed.
  void rejectSignature() => verifier.scripted =
      const ArtifactSignatureRejected();

  /// The installer refused to start, or the process died.
  void refuseInstall([String detail = 'dosya yok']) =>
      installer.outcome = InstallRefused(detail);

  /// A download that ends without ever saying it finished is a failed
  /// transfer. Treating the end of a stream as success is how a truncated
  /// installer gets to be an installer.
  ///
  ///
  /// Arranges the **download** side only, so call it after
  /// [offerFromCheck] - otherwise the offer re-arranges an honest download and
  /// the mismatch never happens.
  void sizeMismatch() {
    fetcher.downloadEvents = fakeArtifactEvents(
      artifact,
      declaredLength: artifact.length + 1,
    );
  }

  /// The download ends without ever saying it finished.
  ///
  /// Arranges the **download** side only; call it after [offerFromCheck].
  void truncateDownload() {
    fetcher.downloadEvents = <DownloadEvent>[
      const DownloadAnnounced(4096),
      const DownloadChunk(<int>[1, 2, 3]),
    ];
  }

  // -- assertions ------------------------------------------------------------

  /// Runs `check` and hands back the offer it found, failing loudly if there was
  /// none.
  Future<UpdateOffer> offerFromCheck() async {
    offerUpdate();
    final UpdateReport report = await client.check();
    if (report is! UpdateOffered) {
      throw StateError('check() did not offer an update: $report');
    }
    return report.offer;
  }

  /// The refusal a report carries, failing loudly if it is not a refusal.
  UpdateFailure failureOf(UpdateReport report) {
    if (report is! UpdateRefused) {
      throw StateError('the report is not a refusal: $report');
    }
    return report.failure;
  }

  List<T> eventsOf<T extends UpdateEvent>() =>
      events.whereType<T>().toList(growable: false);

  /// The store operation log, which is the ordering contract.
  List<String> get storeOperations => files.operations;

  Future<void> dispose() async {
    await subscription.cancel();
    await client.dispose();
  }
}

/// The signal payloads a session layer can originate, for a test that proves a
/// name is in none of them.
List<SignalPayload> outboundSignals() => sessionOutboundPayloads(
  publicKey: fakeLocalPublicKey,
  signature: fakeSignature,
  session: fakeOpaqueId('S'),
  sdp: 'v=0',
  candidate: const IceCandidate(candidate: 'a=x', sdpMid: '0'),
).toList(growable: false);
