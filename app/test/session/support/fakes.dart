/// Hand-driven fakes for every seam `lib/session` exposes.
///
/// Nothing here opens a socket, touches a keyring, writes a file or waits on a
/// real clock. The signaling socket itself is borrowed from the signaling
/// suite's own fake (`test/signaling/support/fake_socket.dart`), so the
/// repository has exactly one [SignalingSocket] fake.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/session/identity.dart';
import 'package:mkvi/session/local_settings.dart';
import 'package:mkvi/session/peer_store.dart';
import 'package:mkvi/session/reconnect_driver.dart';
import 'package:mkvi/signaling/rendezvous_client.dart';
import 'package:mkvi/signaling/signal_payload.dart';

import '../../signaling/support/fake_socket.dart';

/// A 43 character base64 key the Worker would accept, so an envelope built
/// from it passes `isSignalPayload` instead of being rejected as malformed.
const String fakePeerPublicKey = 'ocBf7Y0Cr+t0WkRwS+uhapiSLxEz2KP9SSileaNDrxc';

/// A second valid key, for the initiator comparison and for peer isolation.
const String fakeOtherPublicKey = 'Kw8mQd1pZbY7tVnRc3JfXhA5sLgE2uTiO0yWqBnMlDk';

/// An 86 character signature. The SHAPE is what matters; the verification in
/// these tests is a fake too.
const String fakeSignature =
    '9NvX15EZy28o5rdpfPx6lC2gXrSnAS1+VuGE5R1zaJoHhRjOPd8iOzjsuWQ5mEca9npAQJc0N9DiFzQfswxFXg';

/// A 43 character base64url id, for a discovery id or a session.
String fakeOpaqueId(String tag) => tag.padRight(43, 'x');

/// Mints a DIFFERENT session id every call, so a replayed identity frame from a
/// dead socket cannot verify against a live epoch.
SessionIdFactory countingSessionIds() {
  int next = 0;
  return () => fakeOpaqueId('S${(next++).toString().padLeft(2, '0')}');
}

// ---------------------------------------------------------------------------
// Local settings
// ---------------------------------------------------------------------------

/// An in-memory [LocalSettings].
final class FakeSettings implements LocalSettings {
  final Map<String, String> values = <String, String>{};
  final List<String> removed = <String>[];

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String value) => values[key] = value;

  @override
  void remove(String key) {
    removed.add(key);
    values.remove(key);
  }

  /// The whole store as one string, for a "nothing leaked in here" assertion.
  String get serialized => values.entries
      .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
      .join('&');
}

// ---------------------------------------------------------------------------
// Peer store
// ---------------------------------------------------------------------------

/// An in-memory [PeerStore] whose every read answer can be scripted.
final class FakePeerStore implements PeerStore {
  FakePeerStore({
    this.answer,
    List<PeerReadResult> script = const <PeerReadResult>[],
    this.throwOnRead,
    this.throwOnWrite,
  }) : script = <PeerReadResult>[...script];

  /// The answer used once [script] is empty.
  PeerReadResult? answer;

  /// Consumed before [answer], so a test can make a read fail and then succeed.
  final List<PeerReadResult> script;

  Object? throwOnRead;
  Object? throwOnWrite;

  final List<KnownPeer> writes = <KnownPeer>[];
  int reads = 0;

  @override
  Future<PeerReadResult> readPeer() async {
    reads += 1;
    final Object? failure = throwOnRead;
    if (failure != null) throw failure;
    if (script.isNotEmpty) return script.removeAt(0);
    return answer ?? const PeerAbsent();
  }

  @override
  Future<void> writePeer(KnownPeer peer) async {
    final Object? failure = throwOnWrite;
    if (failure != null) throw failure;
    writes.add(peer);
  }
}

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------

/// A [DeviceIdentityLoader] whose first [failuresBeforeSuccess] reads throw.
final class FakeIdentityLoader implements DeviceIdentityLoader {
  FakeIdentityLoader({
    this.publicKey = fakeOtherPublicKey,
    this.failuresBeforeSuccess = 0,
  });

  final String publicKey;
  int failuresBeforeSuccess;

  int calls = 0;

  /// Every transcript handed to `sign`, in order. The reconnect transcript is a
  /// wire contract, so tests assert on these strings directly.
  final List<String> signedTranscripts = <String>[];

  @override
  Future<DeviceIdentity> load() async {
    calls += 1;
    if (calls <= failuresBeforeSuccess) {
      throw StateError('Cihaz kasası kilitli.');
    }
    return DeviceIdentity(publicKey: publicKey, sign: sign);
  }

  Future<String> sign(String transcript) async {
    signedTranscripts.add(transcript);
    return fakeSignature;
  }
}

/// A [PairingVerifier] that records what it was asked and answers as told.
final class FakePairVerifier {
  FakePairVerifier({this.accept = true, this.throwOnVerify = false});

  bool accept;
  bool throwOnVerify;

  final List<({String publicKey, String transcript, String signature})> calls =
      <({String publicKey, String transcript, String signature})>[];

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
    if (throwOnVerify) throw StateError('Doğrulama çöktü.');
    return accept;
  }
}

/// A [PairScopedDeviceIdFactory] that records what it was given, so a test can
/// pin `mkvi/peer-device/v1/…` without hashing anything.
final class FakeDeviceIdFactory {
  final List<({String discoveryId, String publicKey})> calls =
      <({String discoveryId, String publicKey})>[];

  Future<String> call(String discoveryId, String publicKey) async {
    calls.add((discoveryId: discoveryId, publicKey: publicKey));
    return fakeOpaqueId('D${discoveryId.length}');
  }
}

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

/// A [PeerTransportBinding] that records what it was asked to do.
final class RecordingTransport implements PeerTransportBinding {
  final List<ReconnectEpoch> opened = <ReconnectEpoch>[];
  final List<SignalPayload> signals = <SignalPayload>[];

  /// One entry per `closeChannel` call, holding how many channels were open at
  /// that moment. A stale epoch that tore down a live successor shows up as a
  /// count that does not line up with the epochs opened.
  final List<int> closes = <int>[];

  /// How many of the next `openChannel` calls will throw.
  int openFailures = 0;

  @override
  Future<void> openChannel(ReconnectEpoch epoch) async {
    if (openFailures > 0) {
      openFailures -= 1;
      throw StateError('Medya başlatılamadı.');
    }
    opened.add(epoch);
  }

  @override
  void handleSignal(SignalPayload signal) => signals.add(signal);

  @override
  Future<void> closeChannel() async => closes.add(opened.length);
}

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------

/// A [Delay] that records what it was asked to wait for and returns at once.
///
/// The whole backoff schedule is then exercised in microseconds, and the
/// recording is what the "exactly the expected sequence" assertion reads.
final class RecordingDelay {
  final List<Duration> requested = <Duration>[];

  /// When this index is reached, the sleep parks until [release] is called, so
  /// a test can stop the loop at a chosen point in the schedule.
  int holdAt = -1;

  final Completer<void> _held = Completer<void>();

  void release() {
    if (!_held.isCompleted) _held.complete();
  }

  Future<void> call(Duration duration) async {
    requested.add(duration);
    if (holdAt >= 0 && requested.length - 1 == holdAt) {
      await _held.future;
    }
    await Future<void>.delayed(Duration.zero);
  }
}

/// Yields to the event loop until [reached] is true, then fails loudly rather
/// than hanging when the loop never arrives.
///
/// Every fake in this file completes through a real `Future`, so a test has to
/// let the loop run; this is the explicit "let it run".
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

/// Feeds a [FakeSocket] the identity frame a real peer would send.
///
/// [session] defaults to a valid 43 character id; pass [legacy] for a v1 peer,
/// which sends no `session` key at all.
void announceIdentity(
  FakeSocket socket, {
  String publicKey = fakePeerPublicKey,
  String signature = fakeSignature,
  String? session,
  bool legacy = false,
}) {
  final Map<String, Object?> payload = <String, Object?>{
    'kind': 'identity',
    'publicKey': publicKey,
    'signature': signature,
    'session': legacy ? null : (session ?? fakeOpaqueId('S00')),
  };
  if (legacy) payload.remove('session');
  socket.emitJson(<String, Object?>{'type': 'relay', 'payload': payload});
}

// ---------------------------------------------------------------------------
// The whole loop, wired to fakes
// ---------------------------------------------------------------------------

/// A driver with every seam faked, plus the handles a test pokes at.
final class DriverHarness {
  DriverHarness({
    String endpoint = 'https://signal.example',
    String peerPublicKey = fakePeerPublicKey,
  }) {
    driver = ReconnectDriver(
      identityLoader: identity,
      rendezvousClientFactory: newClient,
      verifyPairing: verifyPairing.call,
      transport: transport,
      pairScopedDeviceId: deviceId.call,
      sessionIdFactory: sessionIds,
      delay: delay.call,
    );
    context = ReconnectContext(
      endpoint: endpoint,
      discoveryId: fakeOpaqueId('room'),
      peerPublicKey: peerPublicKey,
    );
    events = <ReconnectEvent>[];
    subscription = driver.events.listen(events.add);
  }

  final FakeIdentityLoader identity = FakeIdentityLoader();
  final FakePairVerifier verifyPairing = FakePairVerifier();
  final FakeDeviceIdFactory deviceId = FakeDeviceIdFactory();
  final RecordingTransport transport = RecordingTransport();
  final RecordingDelay delay = RecordingDelay();
  final RecordingSocketFactory sockets = RecordingSocketFactory();
  final SessionIdFactory sessionIds = countingSessionIds();

  late final ReconnectDriver driver;
  late final ReconnectContext context;
  late final StreamSubscription<ReconnectEvent> subscription;
  late final List<ReconnectEvent> events;

  RendezvousClient newClient() => RendezvousClient(socketFactory: sockets.call);

  /// The socket of the current attempt.
  FakeSocket get socket => sockets.last;

  /// The socket of attempt [index], counting from the first socket created.
  FakeSocket socketAt(int index) => sockets.sockets[index];

  List<T> of<T extends ReconnectEvent>() =>
      events.whereType<T>().toList(growable: false);

  Future<void> dispose() async {
    await subscription.cancel();
    await driver.dispose();
  }
}
