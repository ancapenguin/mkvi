/// The reconnect loop, ported from the `useEffect` at `src/App.tsx:207-320`.
///
/// The shape is the original's: an identity, a pair-scoped device id, a FRESH
/// session id per epoch, a signature over `mkvi/discover/v2/…`, a socket, an
/// announcement, and a backoff that resets on success. What changed is that the
/// three ways the original could stop reconnecting forever are gone, and each
/// one is structural rather than a guard someone has to remember:
///
/// 1. **A transient identity failure ended the loop.** `src/App.tsx:217-222`
///    caught the failure, set a notice and `return`ed out of the enclosing
///    async IIFE. The effect's dependencies could then never change again, so
///    the app sat on "reconnecting" until the user restarted it. Here the
///    identity read is INSIDE the loop and a throw is an attempt outcome.
/// 2. **A stale epoch's teardown clobbered a newer epoch's state.** The
///    `finally` at `src/App.tsx:290-303` wrote `setConnected(false)` and
///    `setReconnecting(true)` without checking whether that epoch had been
///    cancelled, so an epoch unwinding after its successor had started left the
///    UI pinned on "reconnecting" with a live channel behind it. Here every
///    write is behind [_isCurrent].
/// 3. **An invalid endpoint threw a raw `TypeError` out of `connect()`.**
///    `src/services/rendezvous.ts` built its URL with `new URL(path, endpoint)`
///    OUTSIDE the promise, so `.catch()` on the returned promise never ran at
///    all. Here the URL builder rejects, the driver classifies it, and the loop
///    backs off and tries again.
///
/// One further difference is forced by the Dart port and is not optional:
/// `IoSignalingSocket.close()` cancels its stream subscription before closing
/// (`app/lib/signaling/rendezvous_client.dart:156-163`), so a socket the client
/// closes itself never reports `onClose`. The TypeScript `client.close()` did
/// reach `onDisconnect`, so the driver ends its own epoch explicitly wherever
/// the original relied on that.
library;

import 'dart:async';

import 'package:mkvi/signaling/rendezvous_client.dart';
import 'package:mkvi/signaling/signal_payload.dart';

import 'identity.dart';
import 'peer_store.dart' show maskCapability;
import 'reconnect_schedule.dart';

/// Waits for [duration]. The only production implementation, and the seam a
/// test replaces so the whole schedule can be exercised in microseconds.
typedef Delay = Future<void> Function(Duration duration);

/// Waits on the real clock.
Future<void> waitForReconnectDelay(Duration duration) =>
    Future<void>.delayed(duration);

/// Creates a fresh signaling client. TS: `new RendezvousClient()` inside the
/// loop at `src/App.tsx:227`. One client per epoch, never reused.
typedef RendezvousClientFactory = RendezvousClient Function();

/// What the driver reconnects TO. Immutable, so a later endpoint edit is a new
/// context and a new epoch rather than a mutation under a running loop.
final class ReconnectContext {
  const ReconnectContext({
    required this.endpoint,
    required this.discoveryId,
    required this.peerPublicKey,
  });

  final String endpoint;
  final String discoveryId;
  final String peerPublicKey;

  @override
  String toString() =>
      'ReconnectContext(${maskCapability(discoveryId)}, ${maskCapability(peerPublicKey)})';
}

/// Hides a bearer capability in a log line.
///
/// `src/App.tsx` had no equivalent, which is how a discovery id ended up inside
/// a user-facing notice more than once. The implementation lives in
/// `peer_store.dart` with the other capability and is imported here, so the two
/// layers cannot drift on what a log line is allowed to show.

/// Why one attempt ended without a channel.
///
/// Every case here is retryable. A loop that can decide to give up is a loop
/// that can strand the UI, and the user's only remedy for a stranded UI is to
/// restart the app, which is the bug this file exists to remove.
sealed class ReconnectFailure {
  const ReconnectFailure();

  /// Turkish, and the exact text a notice should carry.
  String get message;

  /// Always true. Kept as a method rather than a field so a future case that is
  /// genuinely terminal has to be argued for instead of defaulting.
  bool get isRetryable => true;
}

/// The endpoint is not usable: not an absolute http, https, ws or wss URL with
/// a host. TS: a raw `TypeError: Invalid URL` escaping `connect()`.
final class ReconnectEndpointUnusable extends ReconnectFailure {
  const ReconnectEndpointUnusable();

  @override
  String get message => signalingConnectError;
}

/// This device's key could not be read, or could not sign with. TS:
/// `src/App.tsx:221` and the `.catch` at `src/App.tsx:277`.
final class ReconnectIdentityUnavailable extends ReconnectFailure {
  const ReconnectIdentityUnavailable();

  @override
  String get message => 'Cihaz kimliği açılamadı.';
}

/// The peer's signature did not verify, or the peer is not the one this device
/// paired with. TS: `src/App.tsx:256-260`.
final class ReconnectPeerUnverified extends ReconnectFailure {
  const ReconnectPeerUnverified();

  @override
  String get message => 'Bilinen cihaz kimliği doğrulanamadı.';
}

/// The socket could not be opened, or the transport refused to start. TS: the
/// `catch` at `src/App.tsx:288-289`, whose detail was interpolated as
/// `Yeniden bağlanılıyor: ${error.message}`.
final class ReconnectConnectFailed extends ReconnectFailure {
  const ReconnectConnectFailed([this.detail]);

  /// The underlying error's own text, or null when there is none worth showing.
  final String? detail;

  @override
  String get message => switch (detail) {
    final String text when text.isNotEmpty => 'Yeniden bağlanılıyor: $text',
    _ => 'Otomatik bağlantı kurulamadı.',
  };
}

/// One signaling epoch, and the only way to put a payload on its socket.
///
/// The epoch is the unit of cancellation. [isCurrent] is a closure over the
/// driver's epoch counter, which is what lets a transport that captured an epoch
/// days ago discover that the epoch is dead instead of relaying into a socket
/// that no longer exists.
final class ReconnectEpoch {
  ReconnectEpoch._({
    required this.epoch,
    required this.attempt,
    required this.session,
    required this.deviceId,
    required this.publicKey,
    required this.signature,
    required this.isInitiator,
    required this.currentEpochCheck,
    required this.relayToSocket,
  });

  /// The driver's epoch counter. Increases on every [ReconnectDriver.start]; a
  /// [ReconnectDriver.stop] retires the current epoch without minting a new
  /// number, which is what lets its teardown still be a teardown.
  final int epoch;

  /// 1-based attempt within this epoch.
  final int attempt;

  /// A FRESH 32-byte base64url id per epoch. TS: `createRendezvousId()` inside
  /// the loop at `src/App.tsx:229`. Reusing it across epochs would let a
  /// replayed identity frame from a dead socket verify against a live one.
  final String session;

  /// The pair-scoped device handle, stable for this (discovery, public key)
  /// pair across epochs. The Durable Object uses it to enforce the two-device
  /// limit, so it must NOT be per-epoch.
  final String deviceId;

  /// This device's public key.
  final String publicKey;

  /// The signature over `mkvi/discover/v2/<discoveryId>/<session>`.
  final String signature;

  /// Whether this side offers. Derived from the two public keys, so both devices
  /// agree without exchanging a role.
  final bool isInitiator;

  /// Whether this epoch is still the driver's current one. A closure over the
  /// driver's epoch counter, so an epoch that captured a transport days ago
  /// still learns that it is dead instead of relaying into a socket that no
  /// longer exists.
  final bool Function() currentEpochCheck;

  /// Puts a payload on this epoch's socket.
  final void Function(SignalPayload) relayToSocket;

  /// The identity envelope announced on this epoch.
  ///
  /// The only payload the session layer ever originates. It carries a key, a
  /// signature and a session, and NOT a name: a name goes over the data
  /// channel, never through the signaling server.
  IdentitySignal get identity => IdentitySignal(
    publicKey: publicKey,
    signature: signature,
    session: session,
  );

  /// Whether this epoch is still the driver's current one.
  bool get isCurrent => currentEpochCheck();

  /// Sends [signal] to the peer, and reports whether it went out.
  ///
  /// Returns false instead of throwing when the socket is already gone, which
  /// is what the TypeScript `announce` did (`src/App.tsx:239-242`): the next
  /// socket announces anyway, so a throw here would only turn a lost announce
  /// into a dead loop.
  bool relay(SignalPayload signal) {
    if (!isCurrent) return false;
    try {
      relayToSocket(signal);
      return true;
    } on SignalingException {
      return false;
    }
  }
}

/// What the transport layer must supply. It owns the WebRTC peer connection,
/// which is not in this library and is not testable here, so the loop only ever
/// asks it to open, feed and close.
abstract class PeerTransportBinding {
  /// Called once per epoch, after the remote identity has verified.
  Future<void> openChannel(ReconnectEpoch epoch);

  /// Every relayed payload the driver did not consume, including the ones that
  /// arrived BEFORE verification and were queued (TS: `src/App.tsx:280`).
  void handleSignal(SignalPayload signal);

  /// Called when an epoch ends, and only for the CURRENT epoch. An active call
  /// cannot survive it.
  Future<void> closeChannel();
}

/// What the loop reports. A stream, not a callback, so a UI can attach late and
/// a slow listener cannot stall the loop.
sealed class ReconnectEvent {
  const ReconnectEvent();
}

/// A socket is being opened. The epoch is minted before `connectKnown`, so a UI
/// can show the session id in a diagnostics line.
final class ReconnectAttemptStarted extends ReconnectEvent {
  const ReconnectAttemptStarted(this.epoch);

  final ReconnectEpoch epoch;
}

/// The remote identity verified and is the peer this device paired with.
final class ReconnectPeerVerified extends ReconnectEvent {
  const ReconnectPeerVerified(this.epoch, this.peerPublicKey);

  final ReconnectEpoch epoch;
  final String peerPublicKey;
}

/// The remote identity was rejected, or the transport refused to start. The
/// epoch is over; the loop backs off and opens the next one.
final class ReconnectAttemptRejected extends ReconnectEvent {
  const ReconnectAttemptRejected(this.failure);

  final ReconnectFailure failure;
}

/// The next attempt will begin after [delay]. Emitted on every retry, including
/// the ones the user is not told about.
final class ReconnectRetryScheduled extends ReconnectEvent {
  const ReconnectRetryScheduled({required this.attempt, required this.delay});

  final int attempt;
  final Duration delay;
}

/// An attempt failed and the failure is bad enough to tell the user about, which
/// is the `delay >= 2_800` test at `src/App.tsx:289`.
final class ReconnectAttemptFailed extends ReconnectEvent {
  const ReconnectAttemptFailed({
    required this.attempt,
    required this.failure,
    required this.retryIn,
  });

  final int attempt;
  final ReconnectFailure failure;
  final Duration retryIn;
}

/// The CURRENT epoch has been torn down. Emitted exactly once per epoch, and
/// never for a superseded epoch - which is the assertion that pins the
/// `finally`-clobber defect.
final class ReconnectEpochClosed extends ReconnectEvent {
  const ReconnectEpochClosed(this.epoch);

  final ReconnectEpoch epoch;
}

/// The driver: one loop, one current epoch, one teardown path.
final class ReconnectDriver {
  ReconnectDriver({
    required this.identityLoader,
    required this.rendezvousClientFactory,
    required this.verifyPairing,
    required this.transport,
    required this.pairScopedDeviceId,
    this.sessionIdFactory = defaultSessionIdFactory,
    this.delay = waitForReconnectDelay,
  });

  final DeviceIdentityLoader identityLoader;
  final RendezvousClientFactory rendezvousClientFactory;
  final PairingVerifier verifyPairing;
  final PeerTransportBinding transport;
  final PairScopedDeviceIdFactory pairScopedDeviceId;
  final SessionIdFactory sessionIdFactory;
  final Delay delay;

  final StreamController<ReconnectEvent> _events =
      StreamController<ReconnectEvent>.broadcast();

  /// Starts at 0; the first epoch is 1. Tests assert on these numbers.
  int _epoch = 0;
  bool _stopped = false;
  RendezvousClient? _client;
  void Function()? _endEpoch;
  Completer<void>? _sleepGate;
  Future<void> _running = Future<void>.value();
  Future<void> _chain = Future<void>.value();
  bool _disposed = false;

  /// The loop's report. Broadcast, so the UI may attach after the first attempt.
  Stream<ReconnectEvent> get events => _events.stream;

  /// How many epochs have been started. [stop] does NOT count: it retires the
  /// current epoch instead of handing out a new number.
  int get epochCount => _epoch;

  /// Whether the loop has been stopped and not started again.
  bool get isStopped => _stopped;

  /// Whether [epoch] is still the one whose writes are allowed.
  bool isCurrentEpoch(int epoch) => _isCurrent(epoch);

  /// Cancels the running loop, if any, and starts a new epoch for [context].
  ///
  /// Serialised against [stop] and against other [start] calls, so an epoch
  /// number is never handed out twice.
  Future<void> start(ReconnectContext context) =>
      _serialise(() => _start(context));

  /// Cancels the running loop. A pending backoff is woken immediately, so
  /// stopping during a 12 second sleep does not wait out the sleep.
  Future<void> stop() => _serialise(_stop);

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _events.close();
  }

  // -----------------------------------------------------------------------
  // Epoch lifecycle
  // -----------------------------------------------------------------------

  Future<void> _start(ReconnectContext context) async {
    // Retire everything BEFORE doing anything else. A loop suspended inside an
    // identity read, inside `connectKnown` or inside a backoff sleep must
    // already know it is stale the moment it wakes up, and it is deliberately
    // NOT awaited: every write it makes is guarded, so letting it unwind beside
    // its successor is both safe and the thing being tested.
    _epoch += 1;
    _stopped = false;
    _wakeAndClose();
    final int epoch = _epoch;
    _running = _run(epoch, context);
    // The loop runs until the next `start` or `stop`. It is NOT awaited here,
    // and it must not be: the serialisation chain below schedules `start` and
    // `stop` against each other, and a `start` that waited for its own loop
    // would make `stop` unreachable for the whole life of the connection.
    //
    // The loop cannot reject - every failure inside it is a value - but the
    // guard is here so a future edit cannot turn an unhandled async error into
    // a crash of the isolate that hosts the UI.
    unawaited(_running.then((_) {}, onError: (Object _) {}));
  }

  Future<void> _stop() async {
    final Future<void> running = _running;
    _stopped = true;
    _wakeAndClose();
    await running;
  }

  /// Wakes a sleeping loop and closes the socket of the epoch being retired.
  void _wakeAndClose() {
    _sleepGate?.complete();
    _sleepGate = null;
    final RendezvousClient? client = _client;
    _client = null;
    // The Dart socket does not report a close for a socket the client closed
    // itself, and a socket that has not finished its handshake reports nothing
    // at all, so the epoch is ended here rather than waiting for `onClose`.
    _endEpoch?.call();
    _endEpoch = null;
    client?.close();
  }

  /// Whether the LOOP of [epoch] may keep running. A `stop` ends it, and so does
  /// a newer epoch.
  bool _isCurrent(int epoch) => epoch == _epoch && !_stopped;

  /// Whether a NEWER epoch has taken over from [epoch].
  ///
  /// Distinct from [_isCurrent] on purpose, and the distinction is the whole of
  /// the `finally`-clobber fix. A teardown under an explicit [stop] MUST still
  /// close the channel and report the close; a teardown under a successor MUST
  /// NOT, because the transport is already holding the successor's channel and
  /// the UI is already live behind it. "Is this still current?" cannot tell
  /// those two apart, because `stop` retires the epoch without handing out a new
  /// number.
  bool _superseded(int epoch) => epoch != _epoch;

  void _emit(ReconnectEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  // -----------------------------------------------------------------------
  // The loop
  // -----------------------------------------------------------------------

  Future<void> _run(int epoch, ReconnectContext context) async {
    int failures = 0;
    while (_isCurrent(epoch)) {
      _AttemptOutcome outcome;
      try {
        outcome = await _attempt(epoch, context, failures + 1);
      } on Object catch (error) {
        // The attempt body classifies every failure it knows about. Anything
        // that still escapes is treated as a connect failure rather than
        // allowed to end the loop, because a driver that can die leaves the UI
        // stuck on "reconnecting" with no way out.
        if (!_isCurrent(epoch)) return;
        outcome = _AttemptOutcome.failed(_classify(error));
      }
      if (!_isCurrent(epoch)) return;
      // TS: `delay = 700` at `src/App.tsx:285` runs as soon as a socket opens and
      // BEFORE the sleep at `src/App.tsx:305`, so an epoch that reached a socket
      // always sleeps the first 700 ms and the schedule only grows again for a
      // failure that never reached one. The reset belongs HERE, not after the
      // sleep, or a second successful reconnect would sleep 1260 ms.
      if (outcome.reachedSocket) failures = 0;
      if (!await _waitBeforeRetry(epoch, failures, outcome.failure)) return;
      failures += 1;
    }
  }

  /// Sleeps for the backoff of [failures] consecutive failures, reporting it if
  /// it is long enough to be worth a notice. Returns false when the loop must
  /// stop instead of retrying.
  Future<bool> _waitBeforeRetry(
    int epoch,
    int failures,
    ReconnectFailure? failure,
  ) async {
    final Duration wait = reconnectBackoffDelay(failures);
    final int attempt = failures + 1;
    if (failure != null && shouldReportReconnectFailure(failures)) {
      _emit(
        ReconnectAttemptFailed(
          attempt: attempt,
          failure: failure,
          retryIn: wait,
        ),
      );
    }
    _emit(ReconnectRetryScheduled(attempt: attempt, delay: wait));

    final Completer<void> gate = Completer<void>();
    _sleepGate = gate;
    // The sleep is raced against the cancellation gate rather than awaited on
    // its own, so a new epoch can begin without waiting out a 12 second backoff.
    final bool cancelled = await Future.any<bool>(<Future<bool>>[
      gate.future.then((_) => true),
      delay(wait).then((_) => false, onError: (Object _) => false),
    ]);
    if (identical(_sleepGate, gate)) _sleepGate = null;
    return !cancelled && _isCurrent(epoch);
  }

  // -----------------------------------------------------------------------
  // One attempt
  // -----------------------------------------------------------------------

  /// TS: the body of the `while (!cancelled)` loop at `src/App.tsx:226-307`.
  Future<_AttemptOutcome> _attempt(
    int epoch,
    ReconnectContext context,
    int attempt,
  ) async {
    // -- the endpoint, before anything is dialled. ----------------------
    // `buildSignalingUrl` is the Dart client's fix for the
    // `new URL(path, endpoint)` the TypeScript client built OUTSIDE its promise:
    // that threw a bare `TypeError: Invalid URL` which the `.catch()` on the
    // returned promise could not see, so a typo in the address left the app
    // waiting forever with an unhandled error in the console. Validating here
    // turns the same input into a reported, retryable state and dials nothing.
    try {
      buildSignalingUrl(context.endpoint, peerPath, <String, String>{
        'pair': context.discoveryId,
        'device': context.peerPublicKey,
      });
    } on SignalingException {
      return _stale(epoch, const ReconnectEndpointUnusable());
    }

    // -- identity. TS: src/App.tsx:217-222 ------------------------------
    // The original `return`ed out of the whole IIFE on a failure. Here it is a
    // value, the loop backs off, and the next attempt reads the key again: a
    // keyring that was still unlocking three seconds ago is not broken.
    final DeviceIdentity identity;
    try {
      identity = await identityLoader.load();
    } on Object {
      return _stale(epoch, const ReconnectIdentityUnavailable());
    }
    if (!_isCurrent(epoch)) return _AttemptOutcome.abandoned();

    // -- pair-scoped device id. TS: src/App.tsx:224 ----------------------
    final String deviceId;
    try {
      deviceId = await pairScopedDeviceId(
        context.discoveryId,
        identity.publicKey,
      );
    } on Object {
      return _stale(epoch, const ReconnectIdentityUnavailable());
    }
    if (!_isCurrent(epoch)) return _AttemptOutcome.abandoned();

    // -- fresh session id and its signature. TS: src/App.tsx:229-231 ------
    final String session = sessionIdFactory();
    final String signature;
    try {
      signature = await identity.sign(
        discoveryTranscript(context.discoveryId, session),
      );
    } on Object {
      return _stale(epoch, const ReconnectIdentityUnavailable());
    }
    if (!_isCurrent(epoch)) return _AttemptOutcome.abandoned();

    final ReconnectEpoch re = ReconnectEpoch._(
      epoch: epoch,
      attempt: attempt,
      session: session,
      deviceId: deviceId,
      publicKey: identity.publicKey,
      signature: signature,
      isInitiator: isInitiator(
        ownPublicKey: identity.publicKey,
        peerPublicKey: context.peerPublicKey,
      ),
      currentEpochCheck: () => _isCurrent(epoch),
      relayToSocket: _relay,
    );

    final RendezvousClient client = rendezvousClientFactory();
    _client = client;
    final _PeerSeen seen = _PeerSeen();
    final Completer<void> disconnected = Completer<void>();
    final Completer<void> retired = Completer<void>();
    Future<void> verification = Future<void>.value();

    /// Ends the epoch from the INSIDE: the socket dropped, or the peer was
    /// refused, or the teardown is running.
    void endEpoch() {
      if (!disconnected.isCompleted) disconnected.complete();
    }

    /// Ends the epoch from the OUTSIDE: [_invalidate] is retiring it.
    ///
    /// The Dart socket does not report a close for a socket the client closed
    /// itself, and a socket that has not finished its handshake never reports
    /// anything at all, so a `connectKnown` that is still waiting can only be
    /// unwound by something outside it. Without this the loop would sit inside
    /// a connect for a socket that is already closed, and [stop] would wait for
    /// it.
    void retireEpoch() {
      endEpoch();
      if (!retired.isCompleted) retired.complete();
    }

    _endEpoch = retireEpoch;

    void onSignal(SignalPayload signal) {
      if (signal is IdentitySignal) {
        // Serialised, exactly as `src/App.tsx:248` chained its promises: two
        // identity frames must not race into two transports. `_verify` never
        // throws, so the chain never breaks.
        verification = verification.then(
          (_) => _verify(epoch, context, re, client, retireEpoch, signal, seen),
        );
        return;
      }
      if (seen.verified) {
        transport.handleSignal(signal);
        return;
      }
      // Anything that arrives before the peer is verified is queued, not
      // dropped: an offer that beats the identity frame is normal.
      seen.deferred.add(signal);
    }

    _emit(ReconnectAttemptStarted(re));

    try {
      // -- connect. TS: src/App.tsx:246-284 ----------------------------
      // Raced against the retirement of this epoch, so a socket that never
      // completes its handshake cannot pin the loop. The loser of the race is
      // left with a handler attached by `Future.any`, so its error is consumed
      // rather than reported as unhandled.
      await Future.any<Object?>(<Future<Object?>>[
        client.connectKnown(
          context.endpoint,
          context.discoveryId,
          re.deviceId,
          onSignal: onSignal,
          onPresence: (int online) {
            // TS: `if (online > 1) announce();` at `src/App.tsx:283`.
            if (online > 1) re.relay(re.identity);
          },
          onDisconnect: (SignalingCloseEvent _) => endEpoch(),
        ),
        retired.future.then((_) => throw const _EpochRetired()),
      ]);
      if (!_isCurrent(epoch)) {
        client.close();
        return _AttemptOutcome.abandoned();
      }
      // TS: `announce();` at `src/App.tsx:286`.
      re.relay(re.identity);
      await disconnected.future;
    } on _EpochRetired {
      client.close();
      return _AttemptOutcome.abandoned();
    } on Object catch (error) {
      // The endpoint was already validated above, so anything arriving here is a
      // transport failure with a Turkish message of its own, not a raw
      // `TypeError` from inside the client.
      return _stale(epoch, _classify(error));
    } finally {
      await _teardown(epoch, re, client, retireEpoch);
    }
    if (!_isCurrent(epoch)) return _AttemptOutcome.abandoned();
    return _AttemptOutcome.reached();
  }

  /// TS: the `finally` at `src/App.tsx:290-303`, with the clobber fixed.
  ///
  /// The socket is always closed - that is housekeeping, not state. Closing the
  /// CHANNEL and reporting the epoch as closed is state, and it happens only if
  /// no NEWER epoch has taken over, so a superseded epoch cannot tear down a
  /// channel its successor has already opened and cannot emit a close that pins
  /// the UI on "reconnecting" with a live channel behind it. An explicit [stop]
  /// is not a successor and does close.
  Future<void> _teardown(
    int epoch,
    ReconnectEpoch re,
    RendezvousClient client,
    void Function() retireEpoch,
  ) async {
    retireEpoch();
    client.close();
    if (identical(_client, client)) _client = null;
    if (identical(_endEpoch, retireEpoch)) _endEpoch = null;
    if (_superseded(epoch)) return;
    await transport.closeChannel();
    _emit(ReconnectEpochClosed(re));
  }

  /// TS: the identity branch of the signal handler, `src/App.tsx:247-277`.
  Future<void> _verify(
    int epoch,
    ReconnectContext context,
    ReconnectEpoch re,
    RendezvousClient client,
    void Function() endEpoch,
    IdentitySignal signal,
    _PeerSeen seen,
  ) async {
    // A repeated announcement of the SAME session is a keepalive, not a new
    // peer: re-verifying it would replace a live transport on every presence
    // message. TS: `src/App.tsx:250`.
    final String incoming = signal.session ?? 'legacy';
    if (seen.verified && seen.remoteSession == incoming) return;

    bool valid;
    try {
      valid = await verifyPairing(
        signal.publicKey,
        remoteDiscoveryTranscript(context.discoveryId, signal.session),
        signal.signature,
      );
    } on Object {
      valid = false;
    }
    // TS: `if (cancelled || epochClosed) return;` at `src/App.tsx:255`.
    if (!_isCurrent(epoch)) return;

    if (!valid || signal.publicKey != context.peerPublicKey) {
      // TS: `src/App.tsx:256-260`. The socket is closed, which retires the
      // epoch, which retries with a new session id.
      _emit(const ReconnectAttemptRejected(ReconnectPeerUnverified()));
      endEpoch();
      client.close();
      return;
    }

    seen.verified = true;
    seen.remoteSession = incoming;
    _emit(ReconnectPeerVerified(re, signal.publicKey));
    try {
      await transport.openChannel(re);
    } on Object {
      _emit(const ReconnectAttemptRejected(ReconnectConnectFailed()));
      endEpoch();
      client.close();
      return;
    }
    if (!_isCurrent(epoch)) return;
    // Re-announce so the far side sees this device under the NEW session id.
    // TS: `announce();` at `src/App.tsx:274`.
    re.relay(re.identity);
    // TS: `while (deferred.length) await transport.handleSignal(deferred.shift()!)`
    // at `src/App.tsx:275`.
    while (seen.deferred.isNotEmpty) {
      transport.handleSignal(seen.deferred.removeAt(0));
    }
  }

  void _relay(SignalPayload signal) {
    _client?.relay(signal);
  }

  _AttemptOutcome _stale(int epoch, ReconnectFailure failure) =>
      _isCurrent(epoch)
      ? _AttemptOutcome.failed(failure)
      : _AttemptOutcome.abandoned();

  // -----------------------------------------------------------------------
  // Failure classification
  // -----------------------------------------------------------------------

  /// Maps whatever escaped a call into a reported, retryable state.
  ///
  /// A [SignalingException] from `connectKnown` means the socket itself could
  /// not be brought up - a refused connection, a DNS failure, a TLS failure.
  /// The endpoint's own shape was already checked at the top of the attempt, so
  /// by the time a `SignalingException` arrives it is a transport problem and
  /// its Turkish text is the detail to show, exactly as `src/App.tsx:289`
  /// interpolated `error.message` into `Yeniden bağlanılıyor: …`.
  static ReconnectFailure _classify(Object error) {
    if (error is SignalingException) {
      return ReconnectConnectFailed(error.message);
    }
    return ReconnectConnectFailed(error.toString());
  }

  // -----------------------------------------------------------------------
  // Serialisation
  // -----------------------------------------------------------------------

  Future<void> _serialise(Future<void> Function() action) {
    final Completer<void> done = Completer<void>();
    _chain = _chain.then((_) async {
      try {
        await action();
        done.complete();
      } on Object catch (error, stack) {
        done.completeError(error, stack);
      }
    });
    return done.future;
  }
}

/// What one epoch has learned about the peer so far.
final class _PeerSeen {
  bool verified = false;
  String remoteSession = '';
  final List<SignalPayload> deferred = <SignalPayload>[];
}

/// Unwinds an attempt whose epoch was retired while the socket was still
/// connecting. Never escapes [_attempt]; it exists so a pending
/// `connectKnown` can be abandoned without waiting for a socket that will
/// never open.
final class _EpochRetired implements Exception {
  const _EpochRetired();
}

/// The outcome of one attempt.
final class _AttemptOutcome {
  const _AttemptOutcome.reached() : failure = null, reachedSocket = true;

  const _AttemptOutcome.failed(this.failure) : reachedSocket = false;

  const _AttemptOutcome.abandoned() : failure = null, reachedSocket = false;

  /// TS: `await client.connectKnown(...)` - did an epoch get to a socket?
  final bool reachedSocket;

  final ReconnectFailure? failure;
}
