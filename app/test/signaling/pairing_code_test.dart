/// Port of `src/domain/signaling.test.ts` (3 tests), plus the Dart-only extras
/// the TypeScript suite has no way to express.
///
/// 1:1 mapping, same order:
///
/// | TypeScript                                  | Dart                                       |
/// |---------------------------------------------|--------------------------------------------|
/// | creates 65-bit, unambiguous codes           | creates 65-bit, unambiguous codes          |
/// | normalizes pasted codes ... ambiguous chars | normalizes pasted codes without accepting  |
/// |                                             |   ambiguous characters                    |
/// | keeps legacy identities compatible ...      | keeps a legacy identity compatible while  |
/// |                                             |   allowing a reconnect session            |
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/signaling/identifiers.dart';
import 'package:mkvi/signaling/pairing_code.dart';
import 'package:mkvi/signaling/query_encoding.dart';
import 'package:mkvi/signaling/signal_payload.dart';

void main() {
  final RegExp generatedCode = RegExp(r'^[A-Z2-9]{13}$');
  final RegExp reconnectSession = RegExp(r'^[A-Za-z0-9_-]{43}$');

  group('pairing code', () {
    test('creates 65-bit, unambiguous codes', () {
      final Set<String> codes = <String>{for (int index = 0; index < 128; index++) createPairingCode()};
      expect(codes, hasLength(128));
      for (final String code in codes) {
        expect(generatedCode.hasMatch(code), isTrue, reason: '$code does not match $generatedCode');
      }
    });

    test('normalizes pasted codes without accepting ambiguous characters', () {
      expect(normalizePairingCode('ab-2 c9 i0o!Z'), 'AB2C9Z');
      expect(normalizePairingCode('A' * 40), hasLength(16));
    });

    test('keeps a legacy identity compatible while allowing a reconnect session', () {
      final IdentitySignal legacy = const IdentitySignal(publicKey: 'key', signature: 'signature');
      final IdentitySignal reconnect = IdentitySignal(
        publicKey: legacy.publicKey,
        signature: legacy.signature,
        session: '${'a' * 41}-_',
      );

      // A legacy identity must not grow a null `session` key: an explicit null
      // is what the Worker rejects, and old clients never sent the key at all.
      expect(legacy.toJson().containsKey('session'), isFalse);
      expect(legacy.toJson(), <String, Object?>{'kind': 'identity', 'publicKey': 'key', 'signature': 'signature'});
      expect(reconnect.session, isNotNull);
      expect(reconnectSession.hasMatch(reconnect.session!), isTrue);
      expect(reconnect.toJson().keys.toList(), <String>['kind', 'publicKey', 'signature', 'session']);
    });
  });

  group('Dart-only extras', () {
    test('produces the same code for the same random source', () {
      // The TypeScript version cannot be pinned this way: it reads
      // `crypto.getRandomValues`, so its output is only shape-checked.
      expect(createPairingCode(random: Random(7)), createPairingCode(random: Random(7)));
      expect(createTransferId(random: Random(7)), createTransferId(random: Random(7)));
    });

    test('never emits a symbol outside the alphabet, even at the range edges', () {
      // 32 divides 256, so every symbol is reachable and none is unreachable.
      expect(pairingCodeAlphabet.length, 32);
      for (int seed = 0; seed < 64; seed++) {
        final String code = createPairingCode(random: Random(seed));
        expect(code, hasLength(pairingCodeLength));
        for (final String symbol in code.split('')) {
          expect(pairingCodeAlphabet.contains(symbol), isTrue, reason: '$symbol escaped the alphabet');
        }
      }
    });

    test('drops the Turkish dotted and dotless I from a pasted code', () {
      // Both upper-case to I, which the alphabet omits. Matching the TypeScript
      // here matters: a locale-sensitive upper-case would keep them and the
      // server would answer 400.
      expect(normalizePairingCode('ıİiI'), isEmpty);
      expect(normalizePairingCode('K7M4P2X9Q6TRı'), 'K7M4P2X9Q6TR');
    });

    test('upper-cases with the ECMAScript special-casing rules', () {
      // JavaScript's `toUpperCase` applies the full Unicode SpecialCasing table
      // and Dart's applies only the simple one, so a code containing `ß` or a
      // Latin ligature would silently contribute ASCII letters in one language
      // and nothing in the other. This pins the port to the JavaScript answer,
      // which is what the frozen 0.1.x build and the Worker both do.
      expect(normalizePairingCode('ß'), 'S'); // upper-cases to "Ss"
      expect(normalizePairingCode('ﬁ'), 'F'); // U+FB01 expands to "FI"
      expect(normalizePairingCode('ŉ'), 'N'); // U+0149 expands to "'N"
      // An ordinary lowercase letter survives; only I and O are excluded.
      expect(normalizePairingCode('l'), 'L');
      // Every expansion is capped after filtering, not before.
      expect(
        normalizePairingCode(List<String>.filled(17, 'ß').join()),
        hasLength(pairingCodeMaxLength),
      );
    });

    test('generates opaque ids the Worker will route', () {
      for (int seed = 0; seed < 64; seed++) {
        final String id = createOpaqueId(random: Random(seed));
        expect(id, hasLength(43));
        expect(isValidOpaqueId(id), isTrue, reason: '$id is not a valid opaque id');
        // base64url only: the id also travels in a URL query.
        expect(id.contains('+'), isFalse);
        expect(id.contains('/'), isFalse);
        expect(id.contains('='), isFalse);
      }
    });

    test('rejects the hyphenated uuid the transport used to emit', () {
      // The exact production failure: `crypto.randomUUID()` produced 36
      // characters with dashes, `parseControl` rejected it, and not one message
      // ever arrived. `createTransferId` is the fix.
      const String uuid = '9f2c1b7e-4a55-4d3c-8b21-6e0f7a9c1d34';
      expect(isValidTransferId(uuid), isFalse);
      expect(isValidTransferId(uuid.replaceAll('-', '')), isTrue);
    });

    test('encodes a query component exactly as the server decodes it', () {
      expect(encodeQueryComponent('+'), '%2B');
      expect(encodeQueryComponent('/'), '%2F');
      expect(encodeQueryComponent('a b'), 'a+b');
      expect(encodeQueryComponent('hrzwNhe8y7yIt6c_--iyTHaXHzZ2mto1xRd_0YmNhn4'),
          'hrzwNhe8y7yIt6c_--iyTHaXHzZ2mto1xRd_0YmNhn4');
    });

    test('writes an identity envelope with session last and omitted when absent', () {
      const String key = 'ocBf7Y0Cr+t0WkRwS+uhapiSLxEz2KP9SSileaNDrxc';
      const String signature =
          '9NvX15EZy28o5rdpfPx6lC2gXrSnAS1+VuGE5R1zaJoHhRjOPd8iOzjsuWQ5mEca9npAQJc0N9DiFzQfswxFXg';
      expect(SignalingEnvelope(const IdentitySignal(publicKey: key, signature: signature)).encode(),
          '{"type":"relay","payload":{"kind":"identity","publicKey":"$key","signature":"$signature"}}');
      expect(
        SignalingEnvelope(IdentitySignal(publicKey: key, signature: signature, session: 'n_Q5sLUmI0XDbM6PDpIlnqt7jzphr2-R0zHsMNyV8zQ'))
            .encode(),
        '{"type":"relay","payload":{"kind":"identity","publicKey":"$key","signature":"$signature",'
        '"session":"n_Q5sLUmI0XDbM6PDpIlnqt7jzphr2-R0zHsMNyV8zQ"}}',
      );
    });

    test('omits absent ICE fields instead of writing nulls', () {
      const IceSignal signal = IceSignal(IceCandidate(candidate: 'candidate:1 1 udp 1 127.0.0.1 9 typ host'));
      // A null `sdpMid` is what a real browser sends while gathering, and the
      // Worker accepts it; writing it back out is unnecessary noise on the wire.
      expect(signal.toJson()['candidate'], isA<Map<Object?, Object?>>());
      expect((signal.toJson()['candidate']! as Map<Object?, Object?>).containsKey('sdpMid'), isFalse);
      expect(SignalingEnvelope(signal).encode(),
          '{"type":"relay","payload":{"kind":"ice","candidate":{"candidate":"candidate:1 1 udp 1 127.0.0.1 9 typ host"}}}');
    });
  });
}
