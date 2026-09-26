/// Fakes for every seam `lib/session` exposes, plus the signaling socket the
/// reconnect loop dials.
///
/// Layer notes are in `fakes/README.md`. Three things are worth repeating here
/// because they are the ones a test gets wrong when it writes its own doubles:
///
/// * [FakePeerStore.readPeer] has **no default answer**. An unarranged read
///   raises. The old fake answered `PeerAbsent()`, and `PeerAbsent` is the one
///   read result that may lead to the pairing screen - so an unarranged read
///   quietly put the app on the white pairing screen's only legal path. That is
///   the exact defect `peer_store.dart` was written to remove, and a fake that
///   reintroduces it makes any bootstrap test pass for the wrong reason.
/// * [FakeDeviceIdentityLoader.calls] is a first-class counter, because
///   `ROADMAP.md` Faz 4's "a second identity is minted silently" claim is
///   measured with it and nothing else measures it.
/// * [FakeLocalSettings.read] is total by default (an unwritten key is `null`,
///   which is a real answer) and strict on request, so the
///   `mkvi.peerAlias.<publicKey>` scoping can be pinned key by key.
library;

import 'dart:async';
import 'dart:convert';

import 'package:mkvi/session/identity.dart';
import 'package:mkvi/session/local_settings.dart';
import 'package:mkvi/session/peer_store.dart';
import 'package:mkvi/session/reconnect_driver.dart';
import 'package:mkvi/signaling/rendezvous_client.dart';
import 'package:mkvi/signaling/signal_payload.dart';

import 'script_log.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The peer's public key: 43 base64url characters, the shape the Worker's
/// `^[A-Za-z0-9_-]{43}$` accepts, so an envelope built from it is not rejected
/// as malformed before the fake ever sees it.
const String fakePeerPublicKey = 'ocBf7Y0Cr+t0WkRwS+uhapiSLxEz2KP9SSileaNDrxc';

/// This device's own key. Chosen *below* [fakePeerPublicKey] so
/// `isInitiator(own, peer)` is true and the role does not have to be computed
/// by every test that cares.
const String fakeLocalPublicKey = 'Kw8mQd1pZbY7tVnRc3JfXhA5sLgE2uTiO0yWqBnMlDk';

/// An 86 character signature. The shape is what matters; the verification is
/// [FakePairingVerifier]'s.
const String fakeSignature =
    '9NvX15EZy28o5rdpfPx6lC2gXrSnAS1+VuGE5R1zaJoHhRjOPd8iOzjsuWQ5mEca9npAQJc0N9DiFzQfswxFXg';

/// A 43 character opaque id, for a discovery capability or a session id.
String fakeOpaqueId(String tag) => tag.padRight(43, 'x').substring(0, 43);

/// Mints a **different** session id on every call, so a replayed identity frame
/// from a dead socket cannot verify against a live epoch.
SessionIdFactory countingSessionIds({String prefix = 'S'}) {
  int next = 0;
  return () => fakeOpaqueId('$prefix${(next++).toString().padLeft(2, '0')}');
}

/// A paired peer a test can seed the store with.
KnownPeer fakeKnownPeer({
  String publicKey = fakePeerPublicKey,
  String discoveryId = 'room',
  String announcedName = 'Ada',
  int pairedAtMs = 1730000000000,
}) => KnownPeer(
  publicKey: publicKey,
  discoveryId: fakeOpaqueId(discoveryId),
  announcedName: announcedName,
  pairedAtMs: pairedAtMs,
);

// ---------------------------------------------------------------------------
// Local settings
// ---------------------------------------------------------------------------

/// An in-memory [LocalSettings] that records every call.
///
/// [strictReads] turns a read of a key the test never declared into a refusal.
/// Off by default because an unwritten key really is absent, and
/// `PeerAliasStore` reads two keys on a fresh install that no test wrote.
final class FakeLocalSettings implements LocalSettings {
  FakeLocalSettings({
    Map<String, String> seed = const <String, String>{},
    this.strictReads = false,
  }) {
    values.addAll(seed);
    _declared.addAll(seed.keys);
    log
      ..define('read', 'returns the stored value, or null when never written')
      ..define('write', 'stores the value under the key')
      ..define('remove', 'deletes the key and remembers that it did');
  }

  final ScriptLog log = ScriptLog('FakeLocalSettings');

  /// When true, a read of a key that was never written or declared raises.
  final bool strictReads;

  final Map<String, String> values = <String, String>{};
  final List<String> removed = <String>[];
  final Set<String> _declared = <String>{};

  /// Declares [key] as readable without giving it a value. For
  /// [strictReads]: the key exists in production and is simply empty here.
  void declare(String key) => _declared.add(key);

  /// How many reads happened. `PeerAliasStore.migrateLegacyAlias` reads two
  /// keys; a test that wants to prove it read the legacy key and did not read a
  /// *different* peer's scoped key reads this.
  int get reads => log.countOf('read');

  @override
  String? read(String key) {
    if (strictReads && !_declared.contains(key)) {
      // Recorded under its own member so the refusal shows which key was the
      // surprise, and so a passing test never mentions it.
      log.record(
        'read:$key',
        detail: key,
        hint: 'strictReads is on, so declare the key first',
      );
      return null;
    }
    log.record('read', detail: key);
    return values[key];
  }

  @override
  void write(String key, String value) {
    log.record('write', detail: '$key=$value');
    values[key] = value;
    _declared.add(key);
  }

  @override
  void remove(String key) {
    log.record('remove', detail: key);
    removed.add(key);
    values.remove(key);
    _declared.add(key);
  }

  /// The whole store as one string, for a "nothing secret leaked in here"
  /// assertion. The peer record and the private key must never appear in it.
  String get serialized => values.entries
      .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
      .join('&');
}

// ---------------------------------------------------------------------------
// Peer store
// ---------------------------------------------------------------------------

/// An in-memory [PeerStore] whose read answers are all explicit.
///
/// There is no fallback answer. A test that wants "never paired" says
/// [FakePeerStore.absent]; a test that wants "paired but locked" says
/// [FakePeerStore.unreadable]; and a test that arranges neither gets
/// [UnscriptedCallError] rather than a plausible lie.
final class FakePeerStore implements PeerStore {
  FakePeerStore({
    this.readAnswer,
    List<PeerReadResult> readScript = const <PeerReadResult>[],
    this.readThrows,
    this.writeThrows,
  }) : readScript = <PeerReadResult>[...readScript] {
    log
      ..define(
        'readPeer',
        'answers the arranged read result, or throws when the store does',
      )
      ..define('writePeer', 'encrypts and stores the record, replacing the last')
      ..define('committedLength', 'the bytes the store currently holds');
  }

  /// Never paired. The one read result that may lead to the pairing screen.
  factory FakePeerStore.absent() => FakePeerStore(
    readAnswer: const PeerAbsent(),
  );

  /// Paired, and readable.
  factory FakePeerStore.paired([KnownPeer? peer]) =>
      FakePeerStore(readAnswer: PeerFound(peer ?? fakeKnownPeer()));

  /// Paired, and not readable. [failure] must be given: which kind of unreadable
  /// is the whole point of the three-way read result.
  factory FakePeerStore.unreadable([
    PeerReadFailure failure = const PeerDecryptFailed(),
  ]) => FakePeerStore(readAnswer: PeerUnreadable(failure));

  final ScriptLog log = ScriptLog('FakePeerStore');

  /// The answer used once [readScript] is empty.
  PeerReadResult? readAnswer;

  /// Consumed before [readAnswer], so a read can fail and then succeed.
  final List<PeerReadResult> readScript;

  /// Thrown by `readPeer`. The "the bridge is not there at all" case.
  Object? readThrows;

  /// Thrown by `writePeer`. The "the record could not be written" case.
  Object? writeThrows;

  /// Every record that reached the store, in write order.
  final List<KnownPeer> writes = <KnownPeer>[];

  /// The record the store currently holds, or null.
  KnownPeer? stored;

  int reads = 0;
  int writeCount = 0;

  @override
  Future<PeerReadResult> readPeer() async {
    reads += 1;
    log.record('readPeer');
    final Object? failure = readThrows;
    if (failure != null) throw failure;
    if (readScript.isNotEmpty) return readScript.removeAt(0);
    final PeerReadResult? answer = readAnswer;
    if (answer == null) {
      throw UnscriptedCallError(
        seam: 'FakePeerStore',
        member: 'readPeer',
        detail: 'no read answer arranged',
        arranged: log.arrangedMembers,
        hint: 'use FakePeerStore.absent() / .paired() / .unreadable()',
      );
    }
    if (answer is PeerFound) stored = answer.peer;
    return answer;
  }

  @override
  Future<void> writePeer(KnownPeer peer) async {
    writeCount += 1;
    log.record('writePeer', detail: peer.publicKey);
    final Object? failure = writeThrows;
    if (failure != null) throw failure;
    writes.add(peer);
    stored = peer;
    readAnswer = PeerFound(peer);
  }

  /// The JSON the Rust bridge would have encrypted. "A local alias must never
  /// appear in the serialized record" is an assertion against this.
  String? get storedJson => stored?.encode();
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/// A [DeviceIdentityLoader] with a call counter and a transcript log.
///
/// [calls] is the counter `ROADMAP.md` Faz 4 asks for. A bootstrap that mints a
/// second identity is a defect with no other observable, and the loop's own
/// attempts make this counter move legitimately, so a test reads it before and
/// after rather than asserting an absolute.
final class FakeDeviceIdentityLoader implements DeviceIdentityLoader {
  FakeDeviceIdentityLoader({
    this.publicKey = fakeLocalPublicKey,
    this.failuresBeforeSuccess = 0,
    this.signature = fakeSignature,
  }) {
    log
      ..define('load', 'returns the identity, or throws while failures remain')
      ..define('sign', 'returns the scripted signature and logs the transcript');
  }

  final ScriptLog log = ScriptLog('FakeDeviceIdentityLoader');

  final String publicKey;
  final String signature;

  /// How many of the first [calls] throw. The "the keyring was still unlocking"
  /// case, which the TypeScript original turned into a permanently stopped
  /// loop.
  int failuresBeforeSuccess;

  /// How many times the loop asked for an identity. The Faz 4 counter.
  int calls = 0;

  /// Every transcript handed to `sign`, in order. `mkvi/discover/v2/...` is a
  /// wire contract, so tests assert on the string itself.
  final List<String> signedTranscripts = <String>[];

  /// The identity this loader hands out, without going through [calls].
  DeviceIdentity get identity =>
      DeviceIdentity(publicKey: publicKey, sign: _sign);

  @override
  Future<DeviceIdentity> load() async {
    calls += 1;
    log.record('load');
    if (calls <= failuresBeforeSuccess) {
      throw StateError('Cihaz kasası kilitli.');
    }
    return identity;
  }

  Future<String> _sign(String transcript) async {
    log.record('sign', detail: transcript);
    signedTranscripts.add(transcript);
    return signature;
  }
}

/// A [PairingVerifier] that records what it was asked and answers as told.
///
/// [accept] is nullable on purpose: `null` means "not arranged", and a verify
/// with no answer raises rather than returning `true` (which would open a
/// channel) or `false` (which would make every test look like it was testing
/// rejection).
final class FakePairingVerifier {
  FakePairingVerifier({this.accept}) {
    log.define('call', 'answers with the arranged accept/reject verdict');
  }

  final ScriptLog log = ScriptLog('FakePairingVerifier');

  /// The verdict, or null when no test has arranged one.
  bool? accept;

  /// When set, `call` throws instead of answering. The verifier bridge is not
  /// there at all.
  Object? throwOnVerify;

  /// Every verification, in order.
  final List<({String publicKey, String transcript, String signature})> calls =
      <({String publicKey, String transcript, String signature})>[];

  /// Arranges the verdict. The readable form of setting [accept].
  void verify({required bool accept}) => this.accept = accept;

  /// The transcript of the [index]th verification.
  String transcriptAt(int index) => calls[index].transcript;

  Future<bool> call(
    String publicKey,
    String transcript,
    String signature,
  ) async {
    calls.add((
      publicKey: publicKey,
      transcript: transcript,
      signature: signature,
    ));
    log.record('call', detail: transcript);
    final Object? failure = throwOnVerify;
    if (failure != null) throw failure;
    final bool? verdict = accept;
    if (verdict == null) {
      throw UnscriptedCallError(
        seam: 'FakePairingVerifier',
        member: 'call',
        detail: transcript,
        arranged: log.arrangedMembers,
        hint: 'call verify(accept: true/false) first',
      );
    }
    return verdict;
  }
}

/// A [PairScopedDeviceIdFactory] that records what it was given, so
/// `mkvi/peer-device/v1/...` can be pinned without hashing anything.
final class FakePairScopedDeviceIdFactory {
  FakePairScopedDeviceIdFactory() {
    log.define('call', 'returns a deterministic id built from the pair');
  }

  final ScriptLog log = ScriptLog('FakePairScopedDeviceIdFactory');

  final List<({String discoveryId, String publicKey})> calls =
      <({String discoveryId, String publicKey})>[];

  /// How many ids were minted. The device handle must be stable across epochs
  /// but *fresh* per pair, so a test asserts two epochs share one id and two
  /// pairs do not.
  int get minted => calls.length;

  Future<String> call(String discoveryId, String publicKey) async {
    calls.add((discoveryId: discoveryId, publicKey: publicKey));
    log.record('call', detail: publicKey);
    // Derived from BOTH halves of the pair, because the device handle is scoped
    // to the pair: two peers in the same room must not get the same handle, and
    // the same peer across epochs must get the same one.
    return fakeOpaqueId(
      'D${discoveryId.length.toString().padLeft(2, '0')}'
      '${publicKey.length.toString().padLeft(2, '0')}'
      '${_tagFor(publicKey)}',
    );
  }

  /// A one character digest of the public key, so a test can read at a glance
  /// whether two calls asked for the same device.
  static String _tagFor(String publicKey) {
    int hash = 0;
    for (final int unit in publicKey.codeUnits) {
      hash = (hash * 31 + unit) & 0x3f;
    }
    return hash.toRadixString(16);
  }
}

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

/// A [PeerTransportBinding] that records what it was asked to do.
final class FakePeerTransport implements PeerTransportBinding {
  FakePeerTransport() {
    log
      ..define('openChannel', 'records the epoch, or throws while failures remain')
      ..define('handleSignal', 'records the payload in order')
      ..define('closeChannel', 'records how many channels were open at that moment');
  }

  final ScriptLog log = ScriptLog('FakePeerTransport');

  /// Every epoch whose channel was opened, in order.
  final List<ReconnectEpoch> opened = <ReconnectEpoch>[];

  /// Every payload the loop handed over, in order. The identity frame is
  /// consumed by the loop itself, so a payload here is a frame the data channel
  /// was supposed to see.
  final List<SignalPayload> signals = <SignalPayload>[];

  /// One entry per `closeChannel`, holding how many channels were open at that
  /// moment. A stale epoch tearing down a live successor shows up here as a
  /// count that does not line up with [opened].
  final List<int> closes = <int>[];

  /// How many of the next `openChannel` calls throw. The "the transport refused
  /// to start" attempt outcome.
  int openFailures = 0;

  @override
  Future<void> openChannel(ReconnectEpoch epoch) async {
    log.record('openChannel', detail: epoch.epoch);
    if (openFailures > 0) {
      openFailures -= 1;
      throw StateError('Medya başlatılamadı.');
    }
    opened.add(epoch);
  }

  @override
  void handleSignal(SignalPayload signal) {
    log.record('handleSignal', detail: signal.runtimeType.toString());
    signals.add(signal);
  }

  @override
  Future<void> closeChannel() async {
    log.record('closeChannel', detail: opened.length);
    closes.add(opened.length);
  }
}

// ---------------------------------------------------------------------------
// Signaling socket
// ---------------------------------------------------------------------------

/// A [SignalingSocket] whose every event is fired by the test.
///
/// Deliberately reimplemented rather than imported from
/// `test/signaling/support/fake_socket.dart`: that file belongs to the
/// signaling suite, and a shared library that reaches into another suite's
/// `support/` directory is how two suites end up disagreeing about what a fake
/// does. The behaviour is identical; the [ScriptLog] is the addition.
final class ScriptedSignalingSocket implements SignalingSocket {
  ScriptedSignalingSocket(this.url) : log = ScriptLog('ScriptedSignalingSocket') {
    log
      ..define('readyState', 'poll')
      ..define('send', 'appends the frame to the record')
      ..define('close', 'records the arguments and marks the socket closed');
  }

  /// Every call this socket received, in order. The record is the contract: a
  /// test asserts on it instead of on the socket's internal state.
  final ScriptLog log;

  /// The URL the client asked for, already built and encoded. The query is where
  /// the pair capability and the device handle travel, so a test asserts on this
  /// rather than on a string it built itself.
  final Uri url;

  int _readyState = SignalingSocket.connecting;

  @override
  int get readyState {
    log.poll('readyState');
    return _readyState;
  }

  @override
  void Function()? onOpen;

  @override
  void Function(String data)? onMessage;

  @override
  void Function(SignalingCloseEvent event)? onClose;

  @override
  void Function(Object error)? onError;

  /// Every frame the client sent, in order.
  final List<String> sent = <String>[];

  /// Every `close()` call, in order, with the arguments the client chose.
  final List<({int? code, String? reason})> closeCalls =
      <({int? code, String? reason})>[];

  /// Completes the handshake.
  void emitOpen() {
    _readyState = SignalingSocket.open;
    onOpen?.call();
  }

  /// Delivers one text frame.
  void emitMessage(String data) => onMessage?.call(data);

  /// Delivers one frame built from a JSON value, so a test can write the
  /// envelope it means.
  void emitJson(Object? value) => emitMessage(jsonEncode(value));

  /// Reports a transport error.
  void emitError([Object? error]) =>
      onError?.call(error ?? StateError('Sinyal hatası.'));

  /// Reports a close. [code] 1006 is the reserved "abnormal closure", which is
  /// what a dropped connection looks like.
  void emitClose({int code = 1006, String reason = ''}) {
    _readyState = SignalingSocket.closed;
    onClose?.call(SignalingCloseEvent(code, reason));
  }

  @override
  void send(String data) {
    log.record('send', detail: data);
    sent.add(data);
  }

  @override
  void close([int? code, String? reason]) {
    log.record('close', detail: reason ?? '');
    closeCalls.add((code: code, reason: reason));
    _readyState = SignalingSocket.closed;
  }
}

/// A [SignalingSocketFactory] that records every URL and hands out
/// [ScriptedSignalingSocket]s, one per epoch.
final class ScriptedSignalingSocketFactory {
  ScriptedSignalingSocketFactory() {
    log.define('call', 'creates a socket for the URL and records both');
  }

  final ScriptLog log = ScriptLog('ScriptedSignalingSocketFactory');

  final List<Uri> urls = <Uri>[];
  final List<ScriptedSignalingSocket> sockets = <ScriptedSignalingSocket>[];

  SignalingSocket call(Uri url) {
    log.record('call', detail: url.toString());
    urls.add(url);
    final ScriptedSignalingSocket socket = ScriptedSignalingSocket(url);
    sockets.add(socket);
    return socket;
  }

  /// The socket of the current attempt.
  ScriptedSignalingSocket get last => sockets.last;

  /// The socket of attempt [index], counting from the first one created.
  ScriptedSignalingSocket socketAt(int index) => sockets[index];
}

/// Feeds a socket the identity frame a real peer would send.
///
/// [legacy] omits the `session` key entirely, which is what 0.1.0 - 0.1.3 sent
/// and what forces the `mkvi/discover/v1/...` transcript on the other side.
void announceIdentity(
  ScriptedSignalingSocket socket, {
  String publicKey = fakePeerPublicKey,
  String signature = fakeSignature,
  String? session,
  bool legacy = false,
}) {
  final Map<String, Object?> payload = <String, Object?>{
    'kind': 'identity',
    'publicKey': publicKey,
    'signature': signature,
  };
  if (!legacy) payload['session'] = session ?? fakeOpaqueId('S00');
  socket.emitJson(<String, Object?>{'type': 'relay', 'payload': payload});
}

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------

/// A [Delay] that records what it was asked to wait for and returns at once.
///
/// The whole backoff schedule then runs in microseconds, and [requested] is what
/// the "exactly this sequence of delays" assertion reads.
final class ScriptedDelay {
  ScriptedDelay() {
    log.define('call', 'records the duration, returns at once, holds when told');
  }

  final ScriptLog log = ScriptLog('ScriptedDelay');

  /// Every duration the loop asked for, in order.
  final List<Duration> requested = <Duration>[];

  /// The index at which the sleep parks until [release] is called, or -1. The
  /// way to stop the loop at a chosen point in the schedule.
  int holdAt = -1;

  final Completer<void> _held = Completer<void>();

  /// Lets a held sleep finish.
  void release() {
    if (!_held.isCompleted) _held.complete();
  }

  Future<void> call(Duration duration) async {
    log.record('call', detail: duration);
    requested.add(duration);
    if (holdAt >= 0 && requested.length - 1 == holdAt) {
      await _held.future;
    }
    await Future<void>.delayed(Duration.zero);
  }
}

/// A [RendezvousClientFactory] that hands out clients over one socket factory.
typedef ScriptedClientFactory = RendezvousClient Function();

/// A [ReconnectContext] a test can point the loop at.
ReconnectContext fakeReconnectContext({
  String endpoint = 'https://signal.example',
  String discoveryId = 'room',
  String peerPublicKey = fakePeerPublicKey,
}) => ReconnectContext(
  endpoint: endpoint,
  discoveryId: fakeOpaqueId(discoveryId),
  peerPublicKey: peerPublicKey,
);
