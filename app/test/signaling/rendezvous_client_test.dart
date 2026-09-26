/// Client lifecycle tests, including the four the TypeScript suite does not have.
///
/// Everything here runs without a server: the client is constructed with a
/// [RecordingSocketFactory], and the fake socket is opened, fed and closed by
/// hand. That is the whole point of the `SignalingSocketFactory` seam, and it is
/// what makes the awkward orderings testable - a frame arriving before `onopen`,
/// a socket that opens after the connect future already failed, a second close
/// event on a socket the client has already forgotten.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/signaling/rendezvous_client.dart';
import 'package:mkvi/signaling/signal_payload.dart';

import 'support/fake_socket.dart';

void main() {
  const String endpoint = 'https://signal.example';
  const String code = 'K7M4P2X9Q6TRH';

  /// A client plus the factory that produced its socket.
  ({RendezvousClient client, RecordingSocketFactory factory}) build() {
    final RecordingSocketFactory factory = RecordingSocketFactory();
    return (client: RendezvousClient(socketFactory: factory.call), factory: factory);
  }

  group('the four cases the TypeScript suite lacks', () {
    test('reconnect after a close delivers onDisconnect exactly once', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) first = build();
      final List<SignalingCloseEvent> disconnects = <SignalingCloseEvent>[];

      Future<void> join(RendezvousClient client, RecordingSocketFactory factory) async {
        final Future<void> pending = client.connect(
          endpoint,
          code,
          onSignal: (SignalPayload _) {},
          onPresence: (int _) {},
          onDisconnect: disconnects.add,
        );
        factory.last.emitOpen();
        await pending;
      }

      await join(first.client, first.factory);
      first.factory.last.emitClose(code: 1006, reason: 'ağ koptu');
      expect(disconnects.map((SignalingCloseEvent event) => event.code), <int>[1006]);

      // Reconnecting after the drop is the documented recovery: the Durable
      // Object has no mailbox, so the caller must re-announce itself.
      final ({RendezvousClient client, RecordingSocketFactory factory}) second = build();
      await join(second.client, second.factory);
      // The old socket must not report again when its event arrives late.
      first.factory.last.emitClose(code: 1006, reason: 'ikinci kez');
      expect(disconnects, hasLength(1), reason: 'a second disconnect would be a double report');
      expect(second.factory.urls, hasLength(1));

      second.factory.last.emitClose(code: 1001, reason: 'odadan ayrıldı');
      expect(disconnects.map((SignalingCloseEvent event) => event.code), <int>[1006, 1001]);
    });

    test('a message arriving before onopen does not resolve the connect future twice', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final List<int> presence = <int>[];
      var resolutions = 0;
      var rejections = 0;

      final Future<void> pending = harness.client
          .connect(endpoint, code, onSignal: (SignalPayload _) {}, onPresence: presence.add)
          .then((_) => resolutions++, onError: (Object _) => rejections++);

      // The Durable Object sends `room` the moment the socket is accepted, which
      // can be before the client observes its own open event.
      harness.factory.last.emitMessage('{"type":"room","peers":1}');
      expect(presence, <int>[1], reason: 'presence must still be delivered before open');
      expect(resolutions, 0, reason: 'a message must not settle the connect future');
      expect(rejections, 0);

      harness.factory.last.emitOpen();
      await pending;
      harness.factory.last.emitOpen();
      await Future<void>.delayed(Duration.zero);
      expect(resolutions, 1);
      expect(rejections, 0);
    });

    test('a close code other than 1003 still reports a disconnect', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final List<SignalingCloseEvent> disconnects = <SignalingCloseEvent>[];
      final Future<void> pending = harness.client.connect(
        endpoint,
        code,
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
        onDisconnect: disconnects.add,
      );
      harness.factory.last.emitOpen();
      await pending;

      // 1000 normal, 1001 going away, 4000 "superseded connection" from the
      // Worker, 1006 no close frame at all. None of them is 1003, and every one
      // of them is a disconnect the caller has to hear about.
      for (final ({int code, String reason}) sample in <({int code, String reason})>[
        (code: 1000, reason: 'normal'),
        (code: 1001, reason: 'going away'),
        (code: 4000, reason: 'Superseded connection'),
        (code: 1006, reason: ''),
        (code: 4001, reason: 'Peer discovery expired'),
      ]) {
        final ({RendezvousClient client, RecordingSocketFactory factory}) next = build();
        final List<SignalingCloseEvent> seen = <SignalingCloseEvent>[];
        final Future<void> open = next.client.connect(
          endpoint,
          code,
          onSignal: (SignalPayload _) {},
          onPresence: (int _) {},
          onDisconnect: seen.add,
        );
        next.factory.last.emitOpen();
        await open;
        next.factory.last.emitClose(code: sample.code, reason: sample.reason);
        expect(seen, hasLength(1), reason: 'close code ${sample.code} must report a disconnect');
        expect(seen.single.code, sample.code);
        expect(seen.single.reason, sample.reason);
      }
    });

    test('the endpoint is encoded correctly when it already has a path or a query', () async {
      for (final ({String endpoint, String expected}) sample in <({String endpoint, String expected})>[
        (
          endpoint: 'https://signal.example/a/b?x=1&y=2',
          expected: 'wss://signal.example/v1/rendezvous?code=$code',
        ),
        (
          endpoint: 'https://signal.example/base?token=a%2Bb',
          expected: 'wss://signal.example/v1/rendezvous?code=$code',
        ),
        (
          endpoint: 'https://signal.example:8787/a/b?x=1',
          expected: 'wss://signal.example:8787/v1/rendezvous?code=$code',
        ),
        (
          endpoint: 'HTTPS://Signal.Example/Path',
          expected: 'wss://signal.example/v1/rendezvous?code=$code',
        ),
        // The path is fixed, so the endpoint's own query is dropped rather than
        // merged: a stale `code=` in the endpoint must not survive next to ours.
        (
          endpoint: 'https://signal.example/?code=OLD',
          expected: 'wss://signal.example/v1/rendezvous?code=$code',
        ),
      ]) {
        final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
        final Future<void> pending = harness.client.connect(
          sample.endpoint,
          code,
          onSignal: (SignalPayload _) {},
          onPresence: (int _) {},
        );
        harness.factory.last.emitOpen();
        await pending;
        expect(harness.factory.last.url.toString(), sample.expected, reason: sample.endpoint);
        // The code must survive a full decode on the server side.
        expect(harness.factory.last.url.queryParameters['code'], code);
      }
    });
  });

  group('Dart-only behaviour the TypeScript client gets wrong', () {
    test('an invalid endpoint rejects with the Turkish error, never a FormatException', () async {
      for (final String bad in <String>['', 'not-a-url', 'signal.example', 'https://', 'https://:99/x', '://x']) {
        final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
        Object? thrown;
        try {
          await harness.client.connect(bad, code, onSignal: (SignalPayload _) {}, onPresence: (int _) {});
        } catch (error) {
          thrown = error;
        }
        expect(thrown, isA<SignalingException>(), reason: 'endpoint "$bad"');
        expect((thrown! as SignalingException).message, signalingConnectError);
        expect(thrown.toString(), signalingConnectError);
        // Nothing may be dialled for an endpoint we could not even parse.
        expect(harness.factory.sockets, isEmpty, reason: 'endpoint "$bad"');
      }
    });

    test('a wss endpoint keeps TLS instead of being downgraded to plaintext', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final Future<void> pending = harness.client.connect(
        'wss://signal.example',
        code,
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
      );
      harness.factory.last.emitOpen();
      await pending;
      expect(harness.factory.last.url.toString(), 'wss://signal.example/v1/rendezvous?code=$code');
    });

    test('a ws endpoint is never silently upgraded', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final Future<void> pending = harness.client.connect(
        'ws://127.0.0.1:8787',
        code,
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
      );
      harness.factory.last.emitOpen();
      await pending;
      expect(harness.factory.last.url.toString(), 'ws://127.0.0.1:8787/v1/rendezvous?code=$code');
    });

    test('a relay envelope the Worker would refuse is malformed, not forwarded', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final List<SignalPayload> signals = <SignalPayload>[];
      final Future<void> pending = harness.client.connect(
        endpoint,
        code,
        onSignal: signals.add,
        onPresence: (int _) {},
      );
      harness.factory.last.emitOpen();
      await pending;

      // A `chat` payload is what turns the Worker into a content tunnel. The
      // Worker would drop the sender with close(1008); the client refuses to
      // hand such a thing to the application at all.
      harness.factory.last.emitMessage('{"type":"relay","payload":{"kind":"chat","text":"mesaj"}}');
      expect(signals, isEmpty);
      expect(harness.factory.last.closeCalls.single.code, closeCodeInvalidMessage);

      // And a relay with no payload at all is malformed too.
      final ({RendezvousClient client, RecordingSocketFactory factory}) second = build();
      final Future<void> open = second.client.connect(
        endpoint,
        code,
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
      );
      second.factory.last.emitOpen();
      await open;
      second.factory.last.emitMessage('{"type":"relay"}');
      expect(second.factory.last.closeCalls.single.code, closeCodeInvalidMessage);
    });
  });

  group('lifecycle', () {
    test('an error before the socket opens rejects with the Turkish error', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final List<int> disconnects = <int>[];
      final Future<void> pending = harness.client.connect(
        endpoint,
        code,
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
        onDisconnect: (SignalingCloseEvent event) => disconnects.add(event.code),
      );
      harness.factory.last.emitError();
      await expectLater(pending, throwsA(isA<SignalingException>()));
      // The connection never opened, so there is no disconnect to report: the
      // user sees one error, not two.
      expect(disconnects, isEmpty);
    });

    test('a close before the socket opens rejects with the Turkish error', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final List<int> disconnects = <int>[];
      final Future<void> pending = harness.client
          .connect(
            endpoint,
            code,
            onSignal: (SignalPayload _) {},
            onPresence: (int _) {},
            onDisconnect: (SignalingCloseEvent event) => disconnects.add(event.code),
          )
          .catchError((Object error) {
        expect((error as SignalingException).message, signalingConnectError);
      });
      harness.factory.last.emitClose(code: 1006);
      await pending;
      expect(disconnects, isEmpty);
    });

    test('a socket that opens after the future settled is closed again', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final Future<void> pending = harness.client.connect(
        endpoint,
        code,
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
      );
      harness.factory.last.emitError();
      harness.factory.last.emitOpen();
      expect(harness.factory.last.closeCalls, hasLength(1));
      await expectLater(pending, throwsA(isA<SignalingException>()));
    });

    test('refuses to relay on a socket that is not open', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) closed = build();
      expect(
        () => closed.client.relay(const OfferSignal('v=0')),
        throwsA(isA<SignalingException>().having((SignalingException e) => e.message, 'message', signalingNotOpenError)),
      );

      final ({RendezvousClient client, RecordingSocketFactory factory}) connecting = build();
      connecting.client.connect(endpoint, code, onSignal: (SignalPayload _) {}, onPresence: (int _) {});
      expect(connecting.factory.last.readyState, SignalingSocket.connecting);
      expect(
        () => connecting.client.relay(const OfferSignal('v=0')),
        throwsA(isA<SignalingException>()),
      );
    });

    test('sends a relay envelope and closes on request', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final Future<void> pending = harness.client.connect(
        endpoint,
        code,
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
      );
      harness.factory.last.emitOpen();
      await pending;

      harness.client.relay(const AnswerSignal('v=0\r\n'));
      harness.client.relay(const IceSignal(IceCandidate(candidate: 'candidate:1 1 udp 1 127.0.0.1 9 typ host')));
      expect(harness.factory.last.sent, <String>[
        '{"type":"relay","payload":{"kind":"answer","sdp":"v=0\\r\\n"}}',
        '{"type":"relay","payload":{"kind":"ice","candidate":{"candidate":"candidate:1 1 udp 1 127.0.0.1 9 typ host"}}}',
      ]);

      harness.client.close();
      expect(harness.factory.last.closeCalls, hasLength(1));
    });

    test('ignores an unknown message type instead of crashing', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final List<SignalPayload> signals = <SignalPayload>[];
      final List<int> presence = <int>[];
      final Future<void> pending = harness.client.connect(
        endpoint,
        code,
        onSignal: signals.add,
        onPresence: presence.add,
      );
      harness.factory.last.emitOpen();
      await pending;

      harness.factory.last.emitMessage('{"type":"heartbeat"}');
      harness.factory.last.emitMessage('{"type":42}');
      expect(signals, isEmpty);
      expect(presence, isEmpty);
      expect(harness.factory.last.closeCalls, isEmpty);
    });

    test('delivers identity signals with and without a session', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final List<IdentitySignal> identities = <IdentitySignal>[];
      final Future<void> pending = harness.client.connect(
        endpoint,
        code,
        onSignal: (SignalPayload signal) {
          if (signal is IdentitySignal) identities.add(signal);
        },
        onPresence: (int _) {},
      );
      harness.factory.last.emitOpen();
      await pending;

      const String publicKey = 'ocBf7Y0Cr+t0WkRwS+uhapiSLxEz2KP9SSileaNDrxc';
      const String signature =
          '9NvX15EZy28o5rdpfPx6lC2gXrSnAS1+VuGE5R1zaJoHhRjOPd8iOzjsuWQ5mEca9npAQJc0N9DiFzQfswxFXg';
      harness.factory.last
        ..emitMessage('{"type":"relay","payload":{"kind":"identity","publicKey":"$publicKey","signature":"$signature"}}')
        ..emitMessage(
          '{"type":"relay","payload":{"kind":"identity","publicKey":"$publicKey","signature":"$signature",'
          '"session":"n_Q5sLUmI0XDbM6PDpIlnqt7jzphr2-R0zHsMNyV8zQ"}}',
        );

      expect(identities, hasLength(2));
      expect(identities.first.session, isNull, reason: 'a legacy identity has no session');
      expect(identities.last.session, 'n_Q5sLUmI0XDbM6PDpIlnqt7jzphr2-R0zHsMNyV8zQ');
      expect(harness.factory.last.closeCalls, isEmpty);
    });

    test('percent-encodes standard base64 opaque ids in the peer URL', () async {
      final ({RendezvousClient client, RecordingSocketFactory factory}) harness = build();
      final Future<void> pending = harness.client.connectKnown(
        endpoint,
        'hrzwNhe8y7yIt6c/++iyTHaXHzZ2mto1xRd/0YmNhn4',
        'hrzwNhe8y7yIt6c_--iyTHaXHzZ2mto1xRd_0YmNhn4',
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
      );
      harness.factory.last.emitOpen();
      await pending;

      // A raw `+` would be read back as a space by the server and the id would
      // arrive corrupted: this is the second half of the "93% of pairings died"
      // bug, in the query string instead of the JSON body.
      expect(
        harness.factory.last.url.toString(),
        'wss://signal.example/v1/peer?pair=hrzwNhe8y7yIt6c%2F%2B%2BiyTHaXHzZ2mto1xRd%2F0YmNhn4'
        '&device=hrzwNhe8y7yIt6c_--iyTHaXHzZ2mto1xRd_0YmNhn4',
      );
      expect(harness.factory.last.url.queryParameters['pair'], 'hrzwNhe8y7yIt6c/++iyTHaXHzZ2mto1xRd/0YmNhn4');
    });
  });
}
