/// The one object the UI holds: the current [SetupState], the peer's names, and
/// the reconnect loop that backs them.
///
/// Everything a component-tree of mutable widget state would have held lives
/// here as a value, and every write goes through a method whose guard is
/// testable. The two production defects are pinned by the shape of this class:
///
/// * Pairing is reachable from [openPairing] and from nowhere else. There is no
///   `knownPeer == null` test anywhere in the app, because there is no nullable
///   peer in the state machine - a peer that exists and cannot be read is
///   [SetupBroken], and [SetupBroken.showsPairingScreen] is false.
/// * The alias is in [peerNames].alias and in no other slot. [names] is the
///   only way to get a name, so the annotation can never displace the
///   announced name in the primary slot, can never be written into
///   [KnownPeer.announcedName] and can never reach a [SignalPayload].
library;

import 'dart:async';

import 'package:mkvi/signaling/signal_payload.dart';

import 'identity.dart';
import 'local_settings.dart';
import 'names.dart';
import 'peer_store.dart';
import 'reconnect_driver.dart';
import 'session_bootstrap.dart';
import 'setup_state.dart';

/// The composition root for startup, the reconnect loop and naming.
///
/// Pure Dart on purpose: no `package:flutter` import anywhere in this library,
/// so all of it runs under `flutter test` with no widget, no binding and no
/// platform channel. The UI listens to [states] and calls the methods.
final class SessionController {
  SessionController({
    required PeerStore peerStore,
    required LocalSettings settings,
    required DeviceIdentityLoader identityLoader,
    required RendezvousClientFactory rendezvousClientFactory,
    required PairingVerifier verifyPairing,
    required PeerTransportBinding transport,
    required PairScopedDeviceIdFactory pairScopedDeviceId,
    SessionIdFactory sessionIdFactory = defaultSessionIdFactory,
    Delay delay = waitForReconnectDelay,
  }) : _bootstrap = SessionBootstrap(peerStore),
       _peerStore = peerStore,
       _aliases = PeerAliasStore(settings),
       _selfName = SelfName(settings),
       _settings = settings,
       _driver = ReconnectDriver(
         identityLoader: identityLoader,
         rendezvousClientFactory: rendezvousClientFactory,
         verifyPairing: verifyPairing,
         transport: transport,
         pairScopedDeviceId: pairScopedDeviceId,
         sessionIdFactory: sessionIdFactory,
         delay: delay,
       );

  final SessionBootstrap _bootstrap;
  final PeerStore _peerStore;
  final PeerAliasStore _aliases;
  final SelfName _selfName;
  final LocalSettings _settings;
  final ReconnectDriver _driver;

  final StreamController<SetupState> _states =
      StreamController<SetupState>.broadcast();

  SetupState _state = const SetupState.restoring();
  KnownPeer? _peer;
  String _announcedName = '';
  String _alias = '';
  String _selfNameValue = '';
  String _endpoint = '';
  bool _disposed = false;

  /// The current startup state, as a value rather than a fourth rendering
  /// branch.
  SetupState get state => _state;

  /// The state stream. A UI rebuilds from this and never from a null check.
  Stream<SetupState> get states => _states.stream;

  /// The stored peer, or null when there is none. A null here means "never
  /// paired or explicitly replaced", NEVER "could not be read" - that is
  /// [SetupBroken], and conflating the two is what produced the white screen.
  KnownPeer? get peer => _peer;

  /// Everything the UI shows about the peer, already resolved. There is no
  /// other source of a peer name.
  PeerNameView get names =>
      PeerNameView(announcedName: _announcedName, alias: _alias);

  /// This device's own name, sanitised.
  String get selfName => _selfNameValue;

  /// The signaling endpoint, from the local settings or the production default.
  String get endpoint => _endpoint;

  /// The loop, for a diagnostics line and for tests.
  ReconnectDriver get driver => _driver;

  // -----------------------------------------------------------------------
  // Startup
  // -----------------------------------------------------------------------

  /// Reads the stored peer and settles into a state.
  ///
  /// Emits [SetupState.restoring] first, so a slow keyring shows a spinner and
  /// never a pairing screen, and then exactly one of [SetupState.firstRun],
  /// [SetupState.reconnecting] or [SetupState.broken]. Starting the loop is the
  /// last thing it does and only when there is a peer to reconnect to.
  Future<void> bootstrap() async {
    _selfNameValue = _selfName.read();
    _endpoint = readEndpoint(_settings);
    _transition(const SetupState.restoring());
    await _restore();
  }

  /// The `broken` screen's primary action. Reads again; a store that was locked
  /// a second ago is usually readable now.
  Future<void> retry() async {
    if (!_state.canRetry) return;
    _transition(const SetupState.restoring());
    await _restore();
  }

  Future<void> _restore() async {
    final BootstrapOutcome outcome = await _bootstrap.restore();
    if (_disposed) return;
    _applyOutcome(outcome);
    if (outcome.peer != null) unawaited(_startLoop());
  }

  void _applyOutcome(BootstrapOutcome outcome) {
    final KnownPeer? peer = outcome.peer;
    if (peer == null) {
      _peer = null;
      _announcedName = '';
      _alias = '';
      _transition(outcome.state);
      return;
    }
    _adopt(peer);
    _transition(outcome.state);
  }

  /// Takes a stored peer as the current one, reading its annotation.
  ///
  /// The one-time migration of the unscoped legacy key happens here and only
  /// for the peer that was actually restored, which is what keeps a note about
  /// one person from being shown for the next: [PeerAliasStore.read] is a pure
  /// function of one public key and has no legacy fallback.
  void _adopt(KnownPeer peer) {
    _peer = peer;
    _announcedName = peer.announcedName;
    _alias = _aliases.migrateLegacyAlias(peer.publicKey);
  }

  // -----------------------------------------------------------------------
  // Pairing
  // -----------------------------------------------------------------------

  /// The pairing screen, on purpose. The ONLY producer of
  /// [SetupState.needsPairing] in the whole application.
  Future<void> openPairing() async {
    if (_state.showsPairingScreen) return;
    // The state changes FIRST. `_startLoop` bails out on a pairing screen, and
    // a restore that is still in flight can therefore never start a loop behind
    // the pairing screen. That is what a separate "the user asked for pairing"
    // flag used to be for, and here it is enforced by the state itself instead
    // of by a caller remembering to set a second flag.
    _transition(const SetupState.needsPairing());
    await _driver.stop();
  }

  /// Backs out of a user-initiated pairing and returns to the saved pair. The
  /// "← Sohbete dön" button.
  Future<void> cancelPairing() async {
    if (_state is! SetupNeedsPairing) return;
    final KnownPeer? peer = _peer;
    if (peer == null) {
      _transition(const SetupState.firstRun());
      return;
    }
    _adopt(peer);
    _transition(const SetupState.reconnecting());
    unawaited(_startLoop());
  }

  /// Adopts a peer that a finished pairing produced.
  ///
  /// [freshAnnouncedName] is whatever the data channel has delivered, and it is
  /// very often still null: the peer's `profile` frame can arrive after pairing
  /// completes. Substituting the placeholder for a missing name here would
  /// replace a name the user had been looking at for months with `"Kişi"`.
  Future<bool> completePairing({
    required String publicKey,
    required String discoveryId,
    String? freshAnnouncedName,
    int? pairedAtMs,
  }) async {
    final String? previous = _peer != null && _peer!.publicKey == publicKey
        ? _peer!.announcedName
        : null;
    final KnownPeer stored = KnownPeer.forPairing(
      publicKey: publicKey,
      discoveryId: discoveryId,
      pairedAtMs: pairedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      freshAnnouncedName: freshAnnouncedName,
      previousAnnouncedName: previous,
    );
    try {
      await _peerStore.writePeer(stored);
    } on Object {
      // Nothing is adopted before the write succeeds, so a failed write cannot
      // leave the app showing a peer that is not on disk — which would survive
      // the restart and then be gone.
      return false;
    }
    if (_disposed) return true;
    _adopt(stored);
    _transition(const SetupState.reconnecting());
    unawaited(_startLoop());
    return true;
  }

  /// Forgets the saved pair. The next bootstrap is a first run, and the pairing
  /// screen is then legitimate.
  Future<bool> forgetPeer() async {
    final KnownPeer? peer = _peer;
    if (peer == null) return false;
    await _driver.stop();
    _peer = null;
    _announcedName = '';
    _alias = '';
    _transition(const SetupState.firstRun());
    return true;
  }

  // -----------------------------------------------------------------------
  // Channel
  // -----------------------------------------------------------------------

  /// Announces that the data channel opened or closed.
  ///
  /// It can only ever move between [SetupState.connected] and
  /// [SetupState.reconnecting], and only while a peer is stored and no pairing is
  /// in progress - a channel report during pairing or during a broken read
  /// cannot open the workspace.
  void reportChannelOpen(bool open) {
    if (_disposed || _peer == null || _state.showsPairingScreen) return;
    _transition(
      open ? const SetupState.connected() : const SetupState.reconnecting(),
    );
  }

  // -----------------------------------------------------------------------
  // Names
  // -----------------------------------------------------------------------

  /// The peer announced a name for itself over the data channel. Persisted, and
  /// it never touches the local annotation — the two are separate slots.
  ///
  /// The store write is best effort and is never allowed to fail the update: a
  /// name that arrived over an open channel is true whether or not it reached
  /// the disk, and the next run would learn it from the peer again.
  Future<void> applyAnnouncedName(String name) async {
    final String clean = sanitizeSelfName(name);
    if (clean.isEmpty) return;
    final KnownPeer? peer = _peer;
    _announcedName = clean;
    if (peer == null || peer.announcedName == clean) return;
    final KnownPeer updated = peer.copyWith(announcedName: clean);
    _peer = updated;
    try {
      await _peerStore.writePeer(updated);
    } on Object {
      // The in-memory name stands; a failed write only costs a re-announce.
    }
  }

  /// Sets this device's local note about the peer, scoped by public key.
  ///
  /// This never touches [names].displayName and never writes into the stored
  /// record. An empty value removes the note.
  void setPeerAlias(String raw) {
    final KnownPeer? peer = _peer;
    if (peer == null) return;
    _aliases.write(peer.publicKey, raw);
    _alias = _aliases.read(peer.publicKey);
  }

  /// The annotation for exactly [publicKey]. The UI layer must not read a
  /// peer's note by any other route, which is how one peer's note used to end
  /// up on another's screen.
  String aliasFor(String publicKey) => _aliases.read(publicKey);

  /// Sets this device's own name. Sanitised on write AND on read.
  void setSelfName(String raw) {
    _selfName.write(raw);
    _selfNameValue = _selfName.read();
  }

  // -----------------------------------------------------------------------
  // Connection settings
  // -----------------------------------------------------------------------

  /// Saves the endpoint and the ICE text together. A blank endpoint is refused
  /// rather than stored.
  bool saveConnectionSettings({
    required String endpoint,
    required String iceText,
  }) {
    final bool saved = saveEndpointAndIce(
      _settings,
      endpoint: endpoint,
      iceText: iceText,
    );
    if (saved) _endpoint = readEndpoint(_settings);
    return saved;
  }

  Future<void> restartDiscovery() async {
    final KnownPeer? peer = _peer;
    if (peer == null || _state.showsPairingScreen) return;
    // Changing either the endpoint or the ICE text must produce a NEW session
    // id rather than reuse the sockets of the old candidates.
    await _startLoop();
  }

  // -----------------------------------------------------------------------
  // Plumbing
  // -----------------------------------------------------------------------

  Future<void> _startLoop() async {
    if (_disposed) return;
    final KnownPeer? peer = _peer;
    // No peer, or a pairing screen: nothing to reconnect to. The pairing-screen
    // guard is what makes [openPairing] authoritative even against a restore
    // that was already in flight when the user pressed it.
    if (peer == null || _state.showsPairingScreen) return;
    _transition(const SetupState.reconnecting());
    await _driver.start(
      ReconnectContext(
        endpoint: _endpoint,
        discoveryId: peer.discoveryId,
        peerPublicKey: peer.publicKey,
      ),
    );
  }

  void _transition(SetupState next) {
    if (_disposed || _state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _driver.dispose();
    await _states.close();
  }
}

/// Every payload the session layer can originate.
///
/// A closed set, so a test can prove the annotation is in none of them. None
/// carries a name: the announced name travels on the data channel, and the
/// signaling server sees a public key, a signature and a session id.
Iterable<SignalPayload> sessionOutboundPayloads({
  required String publicKey,
  required String signature,
  required String session,
  required String sdp,
  required IceCandidate candidate,
}) => <SignalPayload>[
  IdentitySignal(publicKey: publicKey, signature: signature, session: session),
  OfferSignal(sdp),
  AnswerSignal(sdp),
  IceSignal(candidate),
];
