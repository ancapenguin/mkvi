/// The reconnect loop, including the three defects of the TypeScript original.
///
/// 1. `src/App.tsx:217-222` caught a failed identity read, set a notice and
///    `return`ed out of the enclosing async IIFE. The effect's dependencies
///    could then never change again, so the app sat on "reconnecting" until the
///    user restarted it.
/// 2. The `finally` at `src/App.tsx:290-303` wrote `setConnected(false)` and
///    `setReconnecting(true)` with no check for whether that epoch had been
///    cancelled, so an epoch unwinding after its successor had started could
///    pin the UI on "reconnecting" with a live channel behind it.
/// 3. `src/services/rendezvous.ts` built its URL with `new URL(path, endpoint)`
///    OUTSIDE the promise, so an invalid endpoint escaped `connect()` as a raw
///    `TypeError: Invalid URL` and the `.catch()` on the returned promise never
///    ran at all.
///
/// Nothing here opens a socket or waits on a clock: the socket is
/// `test/signaling/support/fake_socket.dart` and the delay is
/// [RecordingDelay], which records the requested duration and returns at once.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/session/identity.dart';
import 'package:mkvi/session/reconnect_driver.dart';
import 'package:mkvi/session/reconnect_schedule.dart';
import 'package:mkvi/signaling/rendezvous_client.dart';
import 'package:mkvi/signaling/signal_payload.dart';

import '../signaling/support/fake_socket.dart';
import 'support/fakes.dart';

void main() {
  group('the material an epoch is built from', () {
    test(
      'signs mkvi/discover/v2/<discoveryId>/<session>, and a fresh session each attempt',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );

        expect(
          harness.identity.signedTranscripts.single,
          'mkvi/discover/v2/${harness.context.discoveryId}/${fakeOpaqueId('S00')}',
        );
        expect(harness.sockets.urls.single.host, 'signal.example');
        expect(
          harness.sockets.urls.single.queryParameters['pair'],
          harness.context.discoveryId,
        );

        // The socket drops, the loop retries, and the SECOND epoch must not reuse
        // the first session id: a replayed identity frame from a dead socket would
        // otherwise verify against a live one.
        harness.socket.emitClose(code: 1006);
        await pumpUntil(
          () => harness.sockets.sockets.length > 1,
          reason: 'the second socket',
        );

        expect(harness.identity.signedTranscripts, hasLength(2));
        expect(
          harness.identity.signedTranscripts[1],
          'mkvi/discover/v2/${harness.context.discoveryId}/${fakeOpaqueId('S01')}',
        );
        expect(
          harness.identity.signedTranscripts[1],
          isNot(harness.identity.signedTranscripts[0]),
        );
      },
    );

    test(
      'verifies a remote identity against the v2 transcript when it carries a session',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        harness.socket.emitOpen();
        announceIdentity(harness.socket, session: fakeOpaqueId('S00'));
        await pumpUntil(
          () => harness.transport.opened.isNotEmpty,
          reason: 'the peer to verify',
        );

        expect(
          harness.verifyPairing.calls.single.transcript,
          'mkvi/discover/v2/${harness.context.discoveryId}/${fakeOpaqueId('S00')}',
        );
      },
    );

    test(
      'verifies a session-less remote identity against the v1 transcript, as App.tsx:253 did',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        harness.socket.emitOpen();
        // A 0.1.x peer sends no session at all.
        announceIdentity(harness.socket, legacy: true);
        await pumpUntil(
          () => harness.transport.opened.isNotEmpty,
          reason: 'the peer to verify',
        );

        expect(
          harness.verifyPairing.calls.single.transcript,
          'mkvi/discover/v1/${harness.context.discoveryId}',
        );
      },
    );

    test(
      'the initiator is decided by the two public keys, and both sides agree',
      () {
        // TS: `identity.publicKey < knownPeer.public_key` at `src/App.tsx:223`.
        expect(
          isInitiator(
            ownPublicKey: fakeOtherPublicKey,
            peerPublicKey: fakePeerPublicKey,
          ),
          isTrue,
        );
        expect(
          isInitiator(
            ownPublicKey: fakePeerPublicKey,
            peerPublicKey: fakeOtherPublicKey,
          ),
          isFalse,
        );
        // Whichever side is smaller offers, so the roles can never both be false
        // or both be true.
        expect(
          isInitiator(
            ownPublicKey: fakeOtherPublicKey,
            peerPublicKey: fakePeerPublicKey,
          ),
          isNot(
            isInitiator(
              ownPublicKey: fakePeerPublicKey,
              peerPublicKey: fakeOtherPublicKey,
            ),
          ),
        );
      },
    );

    test(
      'a queued offer is replayed once the peer verifies, not dropped',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        harness.socket.emitOpen();

        // An offer that beats the identity frame. TS: `deferred.push(signal)` at
        // `src/App.tsx:280`.
        harness.socket.emitJson(<String, Object?>{
          'type': 'relay',
          'payload': <String, Object?>{'kind': 'offer', 'sdp': 'v=0'},
        });
        expect(
          harness.transport.signals,
          isEmpty,
          reason: 'nothing may be handled before verification',
        );

        announceIdentity(harness.socket);
        await pumpUntil(
          () => harness.transport.signals.isNotEmpty,
          reason: 'the queued offer to be replayed',
        );
        expect(harness.transport.signals.single, isA<OfferSignal>());
      },
    );
  });

  group('DEFECT 1, a transient identity failure ended the loop forever', () {
    test('a failing identity read is retried, and the loop survives it', () async {
      final DriverHarness harness = DriverHarness();
      addTearDown(harness.dispose);
      // The keyring was still unlocking for the first two attempts. TS caught
      // this, showed a notice, and RETURNED out of the whole IIFE.
      harness.identity.failuresBeforeSuccess = 2;

      unawaited(harness.driver.start(harness.context));
      await pumpUntil(
        () => harness.sockets.sockets.isNotEmpty,
        reason: 'a socket after the identity read finally succeeded',
      );

      expect(harness.identity.calls, 3, reason: 'two failures, then a success');
      expect(
        harness.sockets.sockets,
        hasLength(1),
        reason:
            'three attempts, but only the one that could read the key dialled anything',
      );
      expect(harness.delay.requested, const <Duration>[
        // The two failed attempts, then the epoch that reached a socket and is
        // now waiting for the peer.
        Duration(milliseconds: 700),
        Duration(milliseconds: 1260),
      ]);
    });

    test(
      'an identity read that never succeeds still retries forever, with backoff',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);
        harness.identity.failuresBeforeSuccess = 1000;

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.delay.requested.length >= 6,
          reason: 'six backoff sleeps',
        );

        expect(harness.identity.calls, greaterThanOrEqualTo(6));
        expect(
          harness.sockets.sockets,
          isEmpty,
          reason: 'nothing is dialled while the key is unreadable',
        );
        expect(harness.delay.requested.take(6), <Duration>[
          reconnectBackoffDelay(0),
          reconnectBackoffDelay(1),
          reconnectBackoffDelay(2),
          reconnectBackoffDelay(3),
          reconnectBackoffDelay(4),
          reconnectBackoffDelay(5),
        ]);
      },
    );
    test(
      'the identity failure is reported to the user from the fourth attempt',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);
        harness.identity.failuresBeforeSuccess = 1000;

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.of<ReconnectAttemptFailed>().isNotEmpty,
          reason: 'a reported failure',
        );

        final ReconnectAttemptFailed event = harness
            .of<ReconnectAttemptFailed>()
            .first;
        expect(event.failure, isA<ReconnectIdentityUnavailable>());
        expect(
          event.failure.message,
          'Cihaz kimliği açılamadı.',
          reason: 'TS: src/App.tsx:221',
        );
        expect(event.failure.isRetryable, isTrue);
        expect(event.attempt, 4, reason: 'the 2.8 s gate of src/App.tsx:289');
      },
    );
  });

  group('DEFECT 2, a stale epoch teardown clobbered a live epoch', () {
    test(
      "a superseded epoch's teardown touches nothing its successor owns",
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        // Epoch 1: a socket, a verified peer, a live channel.
        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        final FakeSocket first = harness.socket;
        first.emitOpen();
        announceIdentity(first);
        await pumpUntil(
          () => harness.transport.opened.length == 1,
          reason: 'epoch 1 to open a channel',
        );

        // Epoch 2: an endpoint edit, an ICE change, anything. The new epoch
        // invalidates the old one BEFORE anything is awaited.
        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.length == 2,
          reason: 'the second socket',
        );
        await pumpUntil(() => harness.driver.epochCount == 2);

        // Epoch 1 is now unwinding. It must NOT have closed a channel, because the
        // only channel the transport holds is epoch 2's.
        expect(
          harness.transport.closes,
          isEmpty,
          reason: 'a stale epoch must not closeChannel()',
        );
        expect(
          harness.of<ReconnectEpochClosed>(),
          isEmpty,
          reason: 'and must not report itself closed',
        );

        // Epoch 2 opens its own channel.
        final FakeSocket second = harness.socket;
        second.emitOpen();
        announceIdentity(second);
        await pumpUntil(
          () => harness.transport.opened.length == 2,
          reason: 'epoch 2 to open a channel',
        );

        // Epoch 1's socket finally reports a close, long after it was retired. This
        // is the event the TypeScript `finally` turned into `setConnected(false)`
        // and `setReconnecting(true)` on a UI that was already live.
        first.emitClose(code: 1006);
        first.emitError(StateError('gecikmeli hata'));
        await pumpUntil(() => harness.sockets.sockets.length >= 2);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          harness.transport.closes,
          isEmpty,
          reason: 'a late close from a retired epoch must change nothing',
        );
        expect(
          harness.transport.opened,
          hasLength(2),
          reason: 'the live epoch keeps its channel',
        );

        // Only stopping the live epoch reports a close, and it reports one.
        await harness.driver.stop();
        expect(
          harness.transport.closes,
          <int>[2],
          reason: 'exactly one close, for the epoch that was current',
        );
        expect(harness.of<ReconnectEpochClosed>(), hasLength(1));
      },
    );

    test(
      'a retired epoch cannot relay into the socket of its successor',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        final ReconnectEpoch first = harness
            .of<ReconnectAttemptStarted>()
            .single
            .epoch;
        expect(first.isCurrent, isTrue);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.driver.epochCount == 2,
          reason: 'the second epoch',
        );

        expect(first.isCurrent, isFalse, reason: 'an epoch knows it is dead');
        expect(
          first.relay(first.identity),
          isFalse,
          reason: 'and it refuses to put a byte on the wire',
        );
        expect(
          harness.socket.sent,
          isEmpty,
          reason: 'the successor socket has not been dialled yet either',
        );
      },
    );

    test('stop wakes a pending backoff instead of waiting it out', () async {
      final DriverHarness harness = DriverHarness();
      addTearDown(harness.dispose);
      // Park the loop inside the FIRST sleep, which the schedule would otherwise
      // hold for 700 ms of real time.
      harness.delay.holdAt = 0;
      harness.identity.failuresBeforeSuccess = 1;

      unawaited(harness.driver.start(harness.context));
      await pumpUntil(
        () => harness.delay.requested.length == 1,
        reason: 'the first sleep to begin',
      );

      final Future<void> stopping = harness.driver.stop();
      // The cancellation gate, not the sleep, is what unblocks the loop.
      await stopping.timeout(const Duration(seconds: 5));
      expect(harness.driver.isStopped, isTrue);
      expect(
        harness.driver.epochCount,
        1,
        reason: 'stop retires the epoch; it does not start a new one',
      );
    });
  });

  group('DEFECT 3, an invalid endpoint threw a raw TypeError out of connect()', () {
    test('an unusable endpoint is a reported, retryable state', () async {
      for (final String endpoint in <String>[
        '',
        'not-a-url',
        'signal.example',
        'https://',
        '://x',
      ]) {
        final DriverHarness harness = DriverHarness(endpoint: endpoint);
        addTearDown(harness.dispose);

        // The TypeScript client would have thrown `TypeError: Invalid URL` from
        // inside `connect()` before the promise existed, and this `await` would
        // have rethrown it out of `start()`.
        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.delay.requested.length >= 4,
          reason: 'four retries for endpoint "$endpoint"',
        );

        expect(
          harness.sockets.sockets,
          isEmpty,
          reason: 'endpoint "$endpoint" must not be dialled',
        );
        expect(
          harness.of<ReconnectAttemptFailed>().map(
            (ReconnectAttemptFailed e) => e.failure,
          ),
          everyElement(isA<ReconnectEndpointUnusable>()),
          reason: 'endpoint "$endpoint"',
        );
        expect(
          harness.of<ReconnectAttemptFailed>().first.failure.message,
          signalingConnectError,
          reason: 'endpoint "$endpoint"',
        );
        // And the loop is still alive, with the schedule it should be on.
        expect(
          harness.driver.epochCount,
          1,
          reason: 'the loop must not have ended',
        );
        expect(harness.delay.requested, <Duration>[
          reconnectBackoffDelay(0),
          reconnectBackoffDelay(1),
          reconnectBackoffDelay(2),
          reconnectBackoffDelay(3),
        ], reason: 'endpoint "$endpoint"');
      }
    });

    test('a socket that refuses to open is retryable too', () async {
      final DriverHarness harness = DriverHarness();
      addTearDown(harness.dispose);

      unawaited(harness.driver.start(harness.context));
      // Every attempt is refused. The user is only told from the fourth, which
      // is the `delay >= 2_800` gate of `src/App.tsx:289`.
      for (int attempt = 0; attempt < 4; attempt += 1) {
        await pumpUntil(
          () => harness.sockets.sockets.length > attempt,
          reason: 'socket ${attempt + 1}',
        );
        harness.socket.emitError(StateError('bağlantı reddedildi'));
      }
      await pumpUntil(
        () => harness.of<ReconnectAttemptFailed>().isNotEmpty,
        reason: 'a reported failure',
      );

      expect(
        harness.of<ReconnectAttemptFailed>().first.failure,
        isA<ReconnectConnectFailed>(),
      );
      expect(
        harness.of<ReconnectAttemptFailed>().first.failure.message,
        'Yeniden bağlanılıyor: $signalingConnectError',
        reason:
            'TS: src/App.tsx:289 interpolated the error into a reconnecting notice',
      );
      expect(
        harness.driver.isStopped,
        isFalse,
        reason: 'the loop is still running',
      );
      expect(harness.sockets.sockets, hasLength(4));
    });
  });

  group('a peer that does not verify', () {
    test(
      'a bad signature retires the epoch and retries with a new session',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);
        harness.verifyPairing.accept = false;

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        final FakeSocket first = harness.socket;
        harness.socket.emitOpen();
        announceIdentity(first);
        await pumpUntil(
          () => harness.sockets.sockets.length > 1,
          reason: 'the epoch to be retired',
        );

        expect(
          harness.transport.opened,
          isEmpty,
          reason: 'no channel may be opened for an unverified peer',
        );
        expect(
          harness.of<ReconnectAttemptRejected>().map(
            (ReconnectAttemptRejected e) => e.failure,
          ),
          everyElement(isA<ReconnectPeerUnverified>()),
        );
        expect(
          harness.of<ReconnectAttemptRejected>().first.failure.message,
          'Bilinen cihaz kimliği doğrulanamadı.',
          reason: 'TS: src/App.tsx:257',
        );
        expect(
          first.closeCalls,
          isNotEmpty,
          reason: 'TS: src/App.tsx:258 closed the socket',
        );
        expect(
          harness.of<ReconnectAttemptStarted>().last.epoch.session,
          isNot(fakeOpaqueId('S00')),
        );
      },
    );

    test(
      'a peer that is not the one this device paired with is refused',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        harness.socket.emitOpen();
        // A perfectly valid signature from a device this install never paired with.
        announceIdentity(harness.socket, publicKey: fakeOtherPublicKey);
        await pumpUntil(
          () => harness.of<ReconnectAttemptRejected>().isNotEmpty,
          reason: 'the stranger to be refused',
        );

        expect(harness.transport.opened, isEmpty);
        expect(
          harness.of<ReconnectAttemptRejected>().single.failure,
          isA<ReconnectPeerUnverified>(),
        );
      },
    );

    test(
      'a verifier that throws is treated as a refusal, not as a crash',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);
        harness.verifyPairing.throwOnVerify = true;

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        harness.socket.emitOpen();
        announceIdentity(harness.socket);
        await pumpUntil(
          () => harness.of<ReconnectAttemptRejected>().isNotEmpty,
          reason: 'the failure to be classified',
        );

        expect(
          harness.of<ReconnectAttemptRejected>().single.failure,
          isA<ReconnectPeerUnverified>(),
        );
        expect(
          harness.driver.epochCount,
          1,
          reason: 'the loop is still the same epoch',
        );
      },
    );

    test(
      'a transport that refuses to start retires the epoch and retries',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);
        harness.transport.openFailures = 1;

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        harness.socket.emitOpen();
        announceIdentity(harness.socket);
        await pumpUntil(
          () => harness.sockets.sockets.length > 1,
          reason: 'the epoch to be retired',
        );

        expect(harness.transport.opened, isEmpty);
        expect(
          harness.of<ReconnectAttemptRejected>().single.failure,
          isA<ReconnectConnectFailed>(),
        );
      },
    );
  });

  group('the epoch that a transport holds', () {
    test('carries the material the UI and the transport need', () async {
      final DriverHarness harness = DriverHarness();
      addTearDown(harness.dispose);

      unawaited(harness.driver.start(harness.context));
      await pumpUntil(
        () => harness.sockets.sockets.isNotEmpty,
        reason: 'the first socket',
      );
      final ReconnectEpoch epoch = harness
          .of<ReconnectAttemptStarted>()
          .single
          .epoch;

      expect(epoch.epoch, 1);
      expect(epoch.attempt, 1);
      expect(epoch.publicKey, fakeOtherPublicKey);
      expect(
        epoch.deviceId,
        fakeOpaqueId('D43'),
        reason: 'pair-scoped, and stable across epochs',
      );
      expect(epoch.identity.session, epoch.session);
      expect(epoch.identity.publicKey, epoch.publicKey);
      expect(epoch.identity.signature, fakeSignature);
      expect(
        epoch.isInitiator,
        isTrue,
        reason: 'fakeOtherPublicKey sorts before fakePeerPublicKey',
      );

      // The URL carries the pair capability and the pair-scoped device handle.
      final Uri url = harness.sockets.urls.single;
      expect(url.queryParameters['pair'], harness.context.discoveryId);
      expect(url.queryParameters['device'], epoch.deviceId);
    });

    test(
      'an announce is refused once the socket is gone, and does not throw',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        final ReconnectEpoch epoch = harness
            .of<ReconnectAttemptStarted>()
            .single
            .epoch;

        // The socket has not opened, so `relay` would throw inside the client. TS
        // swallowed that at `src/App.tsx:239-242`; so does this.
        expect(epoch.relay(epoch.identity), isFalse);
      },
    );

    test(
      'an announce on a live socket goes out as an identity envelope',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        harness.socket.emitOpen();
        final ReconnectEpoch epoch = harness
            .of<ReconnectAttemptStarted>()
            .single
            .epoch;

        expect(epoch.relay(epoch.identity), isTrue);
        expect(harness.socket.sent.last, isNotEmpty);
        expect(harness.socket.sent.last, contains('"kind":"identity"'));
        expect(harness.socket.sent.last, contains(epoch.session));
      },
    );
  });

  group('a dropped channel', () {
    test('resets the backoff, as App.tsx:285 did', () async {
      final DriverHarness harness = DriverHarness();
      addTearDown(harness.dispose);

      // Three failures with a dead endpoint's shape is not available here, so
      // build the streak by closing sockets: each close is a reached socket, so
      // the schedule resets each time. What is being pinned is that the reset
      // happens and the loop keeps running.
      unawaited(harness.driver.start(harness.context));
      for (int drop = 0; drop < 3; drop += 1) {
        await pumpUntil(
          () => harness.sockets.sockets.length > drop,
          reason: 'socket ${drop + 1}',
        );
        harness.socket.emitOpen();
        harness.socket.emitClose(code: 1006);
      }
      await pumpUntil(
        () => harness.delay.requested.length == 3,
        reason: 'three retries',
      );

      expect(
        harness.delay.requested,
        const <Duration>[
          Duration(milliseconds: 700),
          Duration(milliseconds: 700),
          Duration(milliseconds: 700),
        ],
        reason:
            'a socket that opened resets the streak, so every sleep is the first one',
      );
    });

    test(
      'a presence message re-announces the identity, as App.tsx:283 did',
      () async {
        final DriverHarness harness = DriverHarness();
        addTearDown(harness.dispose);

        unawaited(harness.driver.start(harness.context));
        await pumpUntil(
          () => harness.sockets.sockets.isNotEmpty,
          reason: 'the first socket',
        );
        harness.socket.emitOpen();
        await pumpUntil(
          () => harness.socket.sent.isNotEmpty,
          reason: 'the first announce',
        );

        final int before = harness.socket.sent.length;
        harness.socket.emitJson(<String, Object?>{
          'type': 'presence',
          'peers': 2,
        });
        await pumpUntil(
          () => harness.socket.sent.length > before,
          reason: 'a re-announce',
        );
        expect(harness.socket.sent.length, before + 1);

        // A room of one is this device alone; there is nobody to announce to.
        final int after = harness.socket.sent.length;
        harness.socket.emitJson(<String, Object?>{
          'type': 'presence',
          'peers': 1,
        });
        await Future<void>.delayed(Duration.zero);
        expect(harness.socket.sent.length, after);
      },
    );
  });
}
