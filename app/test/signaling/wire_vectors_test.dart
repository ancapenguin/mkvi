/// Every case of `vectors/wire-v1.json`, run against the Dart signaling port.
///
/// The TypeScript suite `src/services/signaling-vectors.test.ts` reads the same
/// file. Neither side may add a case the other cannot run, and neither may pass by
/// weakening an expectation: the two known TypeScript violations are recorded as
/// xfail-style `xfail` counters in the report instead of being deleted here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/signaling/identifiers.dart';
import 'package:mkvi/signaling/pairing_code.dart';
import 'package:mkvi/signaling/query_encoding.dart';
import 'package:mkvi/signaling/rendezvous_client.dart';
import 'package:mkvi/signaling/signal_payload.dart';

import 'support/fake_socket.dart';
import 'support/wire_vectors.dart';

void main() {
  final WireVectors vectors = loadWireVectors();

  /// Records what a connected client did with one frame.
  ({List<String> signals, List<int> presence, RecordingSocketFactory factory, RendezvousClient client})
  connectedClient() {
    final RecordingSocketFactory factory = RecordingSocketFactory();
    final RendezvousClient client = RendezvousClient(socketFactory: factory.call);
    final List<String> signals = <String>[];
    final List<int> presence = <int>[];
    final Future<void> pending = client.connect(
      'https://signal.example',
      'K7M4P2X9Q6TRH',
      onSignal: (SignalPayload signal) => signals.add(signal.kind),
      onPresence: (int peers) => presence.add(peers),
    );
    factory.last.emitOpen();
    // The future completes synchronously enough for the assertions below, but it
    // must be observed so an unexpected failure is not an unhandled error.
    pending.catchError((Object _) {});
    return (signals: signals, presence: presence, factory: factory, client: client);
  }

  group('wire-v1 (${vectors.schema} v${vectors.version})', () {
    test('documents every case and every forbidden key in Turkish', () {
      expect(vectors.schema, 'mkvi.wire');
      expect(vectors.allCases, isNotEmpty);
      for (final WireCase item in vectors.allCases) {
        expect(item.aciklama, isNotEmpty, reason: 'case ${item.id} needs an aciklama');
        expect(item.aciklama.length, greaterThan(25), reason: 'case ${item.id} explanation is too short');
      }
      for (final ForbiddenKey entry in vectors.forbiddenKeys) {
        expect(entry.aciklama.length, greaterThan(25), reason: 'forbidden key ${entry.key} needs a reason');
      }
    });
  });

  group('pairing code', () {
    for (final WireCase item in vectors.casesOfKind('pairingCodeShape')) {
      test(item.id, () {
        final ShapeExpect spec = item.shape;
        final List<String> codes = List<String>.generate(spec.uniqueSamples, (_) => createPairingCode());
        expect(codes.toSet(), hasLength(spec.uniqueSamples), reason: item.aciklama);
        for (final String code in codes) {
          expect(code.length, spec.length);
          for (final String char in code.split('')) {
            expect(spec.alphabet.contains(char), isTrue, reason: '$char is outside the alphabet');
          }
          // The server must accept what we generate, or pairing can never start.
          expect(isAcceptedPairingCode(code), isTrue);
        }
      });
    }

    for (final WireCase item in vectors.casesOfKind('normalizePairingCode')) {
      test(item.id, () {
        expect(normalizePairingCode(item.input! as String), item.expectedString, reason: item.aciklama);
      });
    }

    for (final WireCase item in vectors.casesOfKind('pairingCodeAccepted')) {
      test(item.id, () {
        // The server uppercases the query value before testing it.
        expect(isAcceptedPairingCode(item.value! as String), item.expectedBool, reason: item.aciklama);
      });
    }
  });

  group('opaque id', () {
    for (final WireCase item in vectors.casesOfKind('opaqueIdShape')) {
      test(item.id, () {
        final ShapeExpect spec = item.shape;
        final List<String> ids = List<String>.generate(spec.uniqueSamples, (_) => createOpaqueId());
        expect(ids.toSet(), hasLength(spec.uniqueSamples), reason: item.aciklama);
        for (final String id in ids) {
          expect(id.length, spec.length);
          for (final String char in id.split('')) {
            expect(spec.alphabet.contains(char), isTrue, reason: '$char is outside base64url');
          }
          expect(isValidOpaqueId(id), isTrue);
        }
      });
    }
  });

  group('transfer id', () {
    for (final WireCase item in vectors.casesOfKind('transferIdShape')) {
      test(item.id, () {
        final ShapeExpect spec = item.shape;
        final List<String> ids = List<String>.generate(spec.uniqueSamples, (_) => createTransferId());
        expect(ids.toSet(), hasLength(spec.uniqueSamples), reason: item.aciklama);
        for (final String id in ids) {
          expect(id.length, spec.length);
          for (final String char in id.split('')) {
            expect(spec.alphabet.contains(char), isTrue, reason: '$char is outside [a-f0-9]');
          }
          // What we generate must survive the parser that guards the channel.
          expect(isValidTransferId(id), isTrue);
        }
      });
    }

    for (final WireCase item in vectors.casesOfKind('transferId')) {
      test(item.id, () {
        expect(isValidTransferId(item.value! as String), item.expectedBool, reason: item.aciklama);
      });
    }
  });

  group('signal payload allow-list', () {
    for (final WireCase item in vectors.casesOfKind('payload')) {
      test(item.id, () {
        expect(isSignalPayload(item.payload), item.expectedBool, reason: item.aciklama);
        // A payload the Worker relays must also be a payload we can rebuild into
        // a typed object, otherwise the client would forward something unusable.
        if (item.expectedBool) {
          expect(decodeSignalPayload(item.payload), isNotNull);
        } else {
          expect(decodeSignalPayload(item.payload), isNull);
        }
      });
    }

    for (final WireCase item in vectors.casesOfKind('forbiddenKey')) {
      test(item.id, () {
        expect(isSignalPayload(item.payload), item.expectedBool, reason: item.aciklama);
      });
    }

    test('rejects every key named in forbiddenKeys on every payload kind', () {
      final List<Map<String, Object?>> bases = <Map<String, Object?>>[
        <String, Object?>{'kind': 'offer', 'sdp': 'v=0'},
        <String, Object?>{'kind': 'answer', 'sdp': 'v=0'},
        <String, Object?>{
          'kind': 'ice',
          'candidate': <String, Object?>{'candidate': 'candidate:1 1 udp 1 127.0.0.1 9 typ host'},
        },
        <String, Object?>{
          'kind': 'identity',
          'publicKey': 'ocBf7Y0Cr+t0WkRwS+uhapiSLxEz2KP9SSileaNDrxc',
          'signature':
              '9NvX15EZy28o5rdpfPx6lC2gXrSnAS1+VuGE5R1zaJoHhRjOPd8iOzjsuWQ5mEca9npAQJc0N9DiFzQfswxFXg',
        },
      ];
      for (final Map<String, Object?> base in bases) {
        for (final ForbiddenKey entry in vectors.forbiddenKeys) {
          expect(
            isSignalPayload(<String, Object?>{...base, entry.key: 'x'}),
            isFalse,
            reason: '${entry.key} must be rejected: ${entry.aciklama}',
          );
        }
      }
    });
  });

  group('relay envelope', () {
    for (final WireCase item in vectors.casesOfKind('relayEnvelope')) {
      test(item.id, () {
        expect(isRelayEnvelope(item.value), item.expectedBool, reason: item.aciklama);
      });
    }
  });

  group('incoming message handling', () {
    for (final WireCase item in vectors.casesOfKind('incoming')) {
      test(item.id, () {
        final IncomingExpect spec = item.incoming;
        final String? expectedSignal = spec.signal;
        final int? expectedPresence = spec.presence;
        final ({List<String> signals, List<int> presence, RecordingSocketFactory factory, RendezvousClient client})
        harness = connectedClient();
        harness.factory.last.emitMessage(item.incomingRaw);

        expect(
          harness.factory.last.closeCalls.map((({int? code, String? reason}) call) => call.code).toList(),
          spec.closeCode == null ? isEmpty : <Object?>[spec.closeCode],
          reason: item.aciklama,
        );
        expect(harness.signals, expectedSignal == null ? isEmpty : <String>[expectedSignal], reason: item.aciklama);
        expect(
          harness.presence,
          expectedPresence == null ? isEmpty : <int>[expectedPresence],
          reason: item.aciklama,
        );
      });
    }
  });

  group('relay outbound bytes', () {
    for (final WireCase item in vectors.casesOfKind('relayOutbound')) {
      test(item.id, () {
        final ({List<String> signals, List<int> presence, RecordingSocketFactory factory, RendezvousClient client})
        harness = connectedClient();
        harness.client.relay(decodeSignalPayload(item.payload)!);
        expect(harness.factory.last.sent, hasLength(1));
        expect(harness.factory.last.sent.single, item.expectedString, reason: item.aciklama);
      });
    }
  });

  group('URL construction', () {
    for (final WireCase item in vectors.casesOfKind('url')) {
      if (item.expectedError != null) {
        test(item.id, () async {
          final RecordingSocketFactory factory = RecordingSocketFactory();
          final RendezvousClient client = RendezvousClient(socketFactory: factory.call);
          Object? thrown;
          try {
            await _connect(item, client);
          } catch (error) {
            thrown = error;
          }
          expect(thrown, isA<SignalingException>(), reason: item.aciklama);
          expect((thrown! as SignalingException).message, item.expectedError as String);
          // No socket may be opened for an endpoint we could not even parse.
          expect(factory.sockets, isEmpty);
        });
        continue;
      }
      test(item.id, () async {
        final RecordingSocketFactory factory = RecordingSocketFactory();
        final RendezvousClient client = RendezvousClient(socketFactory: factory.call);
        final Future<void> pending = _connect(item, client);
        factory.last.emitOpen();
        await pending;
        expect(factory.last.url.toString(), item.expectedString, reason: item.aciklama);
      });
    }
  });

  group('query encoding', () {
    for (final WireCase item in vectors.casesOfKind('queryEncoding')) {
      test(item.id, () {
        final String input = item.input! as String;
        expect(encodeQueryComponent(input), item.expectedString, reason: item.aciklama);
        // The server must read back exactly what we meant.
        final Uri probe = Uri(scheme: 'wss', host: 'probe.invalid', path: '/', query: 'q=${item.expectedString}');
        expect(probe.queryParameters['q'], input, reason: item.aciklama);
      });
    }
  });
}

/// Calls the client the way a caller would, for both entry points.
Future<void> _connect(WireCase item, RendezvousClient client) => item.api == 'connectKnown'
    ? client.connectKnown(
        item.endpoint! as String,
        item.params['pair']! as String,
        item.params['device']! as String,
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
      )
    : client.connect(
        item.endpoint! as String,
        item.params['code']! as String,
        onSignal: (SignalPayload _) {},
        onPresence: (int _) {},
      );
