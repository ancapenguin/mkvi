// A 1:1 port of `src/services/peer-transport.test.ts` (27 tests).
//
// The test names are the English names of the vitest suite, inside the same
// groups, so the two files can be diffed by eye. Every Turkish string in the
// expectations is the string the TypeScript source itself raises.
//
// The trailing comment of each `test` is the line of the original it came from.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/control_parser.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/peer_protocol_exception.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';
import 'package:mkvi/core/protocol/transfer_id.dart';

/// `"a".repeat(32)`, which JavaScript has and Dart does not.
String repeat(String unit, int count) =>
    List<String>.filled(count, unit).join();

/// The JSON the TypeScript tests built with `JSON.stringify(value)`.
String encode(Map<String, Object?> value) => jsonEncode(value);

/// Dart has no built-in UUID generator, so the canonical v4 shape is written out
/// by hand. Only the dashes matter to the parser.
const String uuid = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

/// The fixture of "strips path separators and control characters":
/// `rapor` + NUL + U+001F + `.pdf`, spelled as code points so that no invisible
/// control character is ever stored in this source file.
final String nameWithControlCharacters = String.fromCharCodes(<int>[
  0x72,
  0x61,
  0x70,
  0x6f,
  0x72,
  0x00,
  0x1f,
  0x2e,
  0x70,
  0x64,
  0x66,
]);

/// The matcher the TypeScript suite expressed as `expect(...).toThrow()`.
final Matcher throwsProtocolException = throwsA(isA<PeerProtocolException>());

/// The matcher the TypeScript suite expressed as `.toThrow(/çok büyük/)`.
final Matcher throwsMessageTooLarge = throwsA(
  isA<PeerProtocolException>().having(
    (PeerProtocolException e) => e.message,
    'message',
    contains('çok büyük'),
  ),
);

void main() {
  // The 32 character lowercase hex id every fixture uses.
  final String id = repeat('a', 32);
  final String discovery = repeat('A', 43);

  group('randomTransferId', () {
    // Chat frames once used crypto.randomUUID(), whose dashes made the receiving
    // parseControl throw "Geçersiz kontrol mesajı." and silently drop every message.
    test(
      'produces ids that parseControl accepts on every control type',
      () {
        for (int attempt = 0; attempt < 50; attempt += 1) {
          final String generated = randomTransferId();
          expect(generated, matches(PeerProtocol.transferIdPattern));
          expect(
            parseControl(
              encode(<String, Object?>{
                'type': 'chat',
                'id': generated,
                'text': 'merhaba',
                'sentAt': 1,
              }),
            ).id,
            generated,
          );
          expect(
            parseControl(
              encode(<String, Object?>{
                'type': 'call-offer',
                'id': generated,
                'mode': 'video',
              }),
            ).id,
            generated,
          );
          expect(
            parseControl(
              encode(<String, Object?>{'type': 'call-end', 'id': generated}),
            ).id,
            generated,
          );
        }
      },
      // src/services/peer-transport.test.ts:12
    );

    test(
      'rejects a UUID, the shape that caused the dropped-message bug',
      () {
        expect(
          () => parseControl(
            encode(<String, Object?>{
              'type': 'chat',
              'id': uuid,
              'text': 'x',
              'sentAt': 1,
            }),
          ),
          throwsProtocolException,
        );
      },
      // src/services/peer-transport.test.ts:22
    );
  });

  group('parseControl', () {
    test(
      'accepts a well-formed chat frame',
      () {
        expect(
          parseControl(
            encode(<String, Object?>{
              'type': 'chat',
              'id': id,
              'text': 'merhaba',
              'sentAt': 1700000000000,
            }),
          ),
          ChatMessage(id: id, text: 'merhaba', sentAt: 1700000000000),
        );
      },
      // src/services/peer-transport.test.ts:28
    );

    test(
      'rejects frames whose id is not a 32-character hex transfer id',
      () {
        for (final String bad in <String>[
          '',
          'kısa',
          repeat('A', 32),
          repeat('a', 31),
          repeat('a', 33),
          id.toUpperCase(),
        ]) {
          expect(
            () => parseControl(
              encode(<String, Object?>{
                'type': 'chat',
                'id': bad,
                'text': 'x',
                'sentAt': 1,
              }),
            ),
            throwsProtocolException,
            reason: 'id "$bad" must be rejected',
          );
        }
      },
      // src/services/peer-transport.test.ts:33
    );

    test(
      'rejects non-object and malformed payloads',
      () {
        for (final String raw in <String>[
          'null',
          '42',
          '"metin"',
          '[]',
          '{}',
          'değil-json',
        ]) {
          expect(
            () => parseControl(raw),
            throwsProtocolException,
            reason: 'payload "$raw" must be rejected',
          );
        }
      },
      // src/services/peer-transport.test.ts:39
    );

    test(
      'rejects an empty chat body and one larger than the message limit',
      () {
        expect(
          () => parseControl(
            encode(<String, Object?>{
              'type': 'chat',
              'id': id,
              'text': '',
              'sentAt': 1,
            }),
          ),
          throwsProtocolException,
        );
        final String oversized = repeat('a', PeerProtocol.maxMessageBytes + 1);
        expect(
          () => parseControl(
            encode(<String, Object?>{
              'type': 'chat',
              'id': id,
              'text': oversized,
              'sentAt': 1,
            }),
          ),
          throwsProtocolException,
        );
      },
      // src/services/peer-transport.test.ts:45
    );

    test(
      'rejects a chat frame whose multi-byte body exceeds the limit in bytes, not characters',
      () {
        // "ş" is two UTF-8 bytes, so this is under the character count but over the byte budget.
        final String body = repeat('ş', PeerProtocol.maxMessageBytes ~/ 2 + 1);
        expect(body.length, lessThan(PeerProtocol.maxMessageBytes));
        expect(
          () => parseControl(
            encode(<String, Object?>{
              'type': 'chat',
              'id': id,
              'text': body,
              'sentAt': 1,
            }),
          ),
          throwsProtocolException,
        );
      },
      // src/services/peer-transport.test.ts:51
    );

    test(
      'rejects a chat frame with a non-numeric timestamp',
      () {
        expect(
          () => parseControl(
            encode(<String, Object?>{
              'type': 'chat',
              'id': id,
              'text': 'x',
              'sentAt': 'dün',
            }),
          ),
          throwsProtocolException,
        );
      },
      // src/services/peer-transport.test.ts:58
    );

    test(
      'sanitizes the name and mime of an accepted file offer',
      () {
        final PeerControlMessage parsed = parseControl(
          encode(<String, Object?>{
            'type': 'file-offer',
            'id': id,
            'name': '../../etc/passwd',
            'mime': 'not a mime',
            'size': 10,
          }),
        );
        expect(
          parsed,
          FileOfferMessage(
            id: id,
            name: '.._.._etc_passwd',
            mime: 'application/octet-stream',
            size: 10,
          ),
        );
      },
      // src/services/peer-transport.test.ts:62
    );

    test(
      'rejects file offers with an out-of-range or non-integer size',
      () {
        // `Number.NaN` in the original. Dart's `jsonEncode` refuses to write a
        // non-finite number at all (it throws instead of emitting `NaN`), and
        // JavaScript's `JSON.stringify(NaN)` writes the four bytes `null`, so
        // `null` is the faithful wire form of the same rejected frame. The
        // `1e400` spelling that really does put an Infinity on the wire is
        // covered in dart_semantics_test.dart.
        for (final Object? size in <Object?>[
          0,
          -1,
          1.5,
          PeerProtocol.maxFileBytes + 1,
          null,
          '10',
        ]) {
          expect(
            () => parseControl(
              encode(<String, Object?>{
                'type': 'file-offer',
                'id': id,
                'name': 'a.bin',
                'mime': 'text/plain',
                'size': size,
              }),
            ),
            throwsProtocolException,
            reason: 'size $size must be rejected',
          );
        }
      },
      // src/services/peer-transport.test.ts:69
    );

    test(
      'accepts a file offer sitting exactly on the size limit',
      () {
        final PeerControlMessage parsed = parseControl(
          encode(<String, Object?>{
            'type': 'file-offer',
            'id': id,
            'name': 'a.bin',
            'mime': 'text/plain',
            'size': PeerProtocol.maxFileBytes,
          }),
        );
        expect(parsed.kind, ControlMessageType.fileOffer);
        expect((parsed as FileOfferMessage).size, PeerProtocol.maxFileBytes);
      },
      // src/services/peer-transport.test.ts:75
    );

    test(
      'passes through the id-only control frames',
      () {
        for (final String type in <String>[
          'file-accept',
          'file-complete',
          'call-accept',
          'call-end',
        ]) {
          final PeerControlMessage parsed = parseControl(
            encode(<String, Object?>{'type': type, 'id': id}),
          );
          expect(parsed, isA<IdOnlyMessage>());
          expect(parsed.type, type);
          expect(parsed.id, id);
        }
      },
      // src/services/peer-transport.test.ts:80
    );

    test(
      'accepts audio and video call offers',
      () {
        for (final String mode in <String>['audio', 'video']) {
          expect(
            parseControl(
              encode(<String, Object?>{
                'type': 'call-offer',
                'id': id,
                'mode': mode,
              }),
            ),
            CallOfferMessage(id: id, mode: CallMode.values.byName(mode)),
          );
        }
      },
      // src/services/peer-transport.test.ts:86
    );

    test(
      'rejects a call offer with an unknown or missing mode',
      () {
        for (final Object? mode in <Object?>[null, 'screen', '', 1]) {
          expect(
            () => parseControl(
              encode(<String, Object?>{
                'type': 'call-offer',
                'id': id,
                'mode': mode,
              }),
            ),
            throwsProtocolException,
            reason: 'mode $mode must be rejected',
          );
        }
      },
      // src/services/peer-transport.test.ts:92
    );

    test(
      'accepts and sanitizes an optional call decline reason',
      () {
        final PeerControlMessage withoutReason = parseControl(
          encode(<String, Object?>{'type': 'call-decline', 'id': id}),
        );
        expect(withoutReason, CallDeclineMessage(id: id));
        expect((withoutReason as CallDeclineMessage).reason, isNull);
        final PeerControlMessage withReason = parseControl(
          encode(<String, Object?>{
            'type': 'call-decline',
            'id': id,
            'reason': '  meşgul\n${repeat('u', 400)}',
          }),
        );
        expect(
          (withReason as CallDeclineMessage).reason,
          'meşgul ${repeat('u', 249)}',
        );
      },
      // src/services/peer-transport.test.ts:98
    );

    test(
      'accepts pair-confirmed with an absent or well-formed discovery capability',
      () {
        final PeerControlMessage absent = parseControl(
          encode(<String, Object?>{'type': 'pair-confirmed', 'id': id}),
        );
        expect((absent as PairConfirmedMessage).discovery, isNull);
        expect(absent.toJson().containsKey('discovery'), isFalse);
        final PeerControlMessage present = parseControl(
          encode(<String, Object?>{
            'type': 'pair-confirmed',
            'id': id,
            'discovery': discovery,
          }),
        );
        expect((present as PairConfirmedMessage).discovery, discovery);
      },
      // src/services/peer-transport.test.ts:104
    );

    test(
      'rejects a pair-confirmed discovery capability of the wrong shape',
      () {
        for (final Object? candidate in <Object?>[
          repeat('A', 42),
          repeat('A', 44),
          '${repeat('A', 42)}+',
          '',
          5,
        ]) {
          expect(
            () => parseControl(
              encode(<String, Object?>{
                'type': 'pair-confirmed',
                'id': id,
                'discovery': candidate,
              }),
            ),
            throwsProtocolException,
            reason: 'discovery "$candidate" must be rejected',
          );
        }
      },
      // src/services/peer-transport.test.ts:110
    );

    test(
      'truncates a decline reason to 256 characters',
      () {
        final PeerControlMessage parsed = parseControl(
          encode(<String, Object?>{
            'type': 'file-decline',
            'id': id,
            'reason': repeat('u', 400),
          }),
        );
        expect(
          parsed,
          FileDeclineMessage(
            id: id,
            reason: repeat('u', PeerProtocol.maxReasonLength),
          ),
        );
      },
      // src/services/peer-transport.test.ts:116
    );

    test(
      'allows cancel and decline without a reason',
      () {
        for (final String type in <String>['file-decline', 'file-cancel']) {
          final PeerControlMessage parsed = parseControl(
            encode(<String, Object?>{'type': type, 'id': id}),
          );
          expect(parsed.id, id);
          final String? reason = switch (parsed) {
            FileDeclineMessage(:final String? reason) => reason,
            FileCancelMessage(:final String? reason) => reason,
            _ => fail('$type did not parse into a decline or cancel'),
          };
          expect(reason, isNull);
          expect(
            parsed.toJson().containsKey('reason'),
            isFalse,
            reason: 'an absent reason is not written at all',
          );
        }
      },
      // src/services/peer-transport.test.ts:121
    );

    test(
      'rejects unknown frame types',
      () {
        expect(
          () =>
              parseControl(encode(<String, Object?>{'type': 'eval', 'id': id})),
          throwsProtocolException,
        );
      },
      // src/services/peer-transport.test.ts:127
    );

    test(
      'rejects a control frame larger than the message limit before parsing it',
      () {
        expect(
          () => parseControl(
            '{"padding":"${repeat('a', PeerProtocol.maxMessageBytes)}"}',
          ),
          throwsMessageTooLarge,
        );
      },
      // src/services/peer-transport.test.ts:131
    );
  });

  group('safeName', () {
    test(
      'strips path separators and control characters',
      () {
        expect(safeName('a/b\\c:d*e?f"g<h>i|j'), 'a_b_c_d_e_f_g_h_i_j');
        expect(safeName(nameWithControlCharacters), 'rapor__.pdf');
      },
      // src/services/peer-transport.test.ts:137
    );

    test(
      'keeps Turkish characters intact',
      () {
        expect(safeName('ödev şşğ.txt'), 'ödev şşğ.txt');
      },
      // src/services/peer-transport.test.ts:142
    );

    test(
      'truncates to 160 characters',
      () {
        expect(
          safeName(repeat('n', 400)),
          hasLength(PeerProtocol.maxFileNameLength),
        );
      },
      // src/services/peer-transport.test.ts:146
    );

    test(
      'falls back to a placeholder when nothing usable remains',
      () {
        expect(safeName('   '), 'dosya');
        expect(safeName('/'), '_');
      },
      // src/services/peer-transport.test.ts:150
    );
  });

  group('safeMime', () {
    test(
      'accepts conventional media types',
      () {
        for (final String mime in <String>[
          'text/plain',
          'image/png',
          'application/vnd.api+json',
        ]) {
          expect(safeMime(mime), mime);
        }
      },
      // src/services/peer-transport.test.ts:157
    );

    test(
      'falls back to a byte stream for anything malformed',
      () {
        for (final String mime in <String>[
          '',
          'text',
          'text/',
          '/plain',
          'text/plain; charset=utf-8',
          '<script>',
        ]) {
          expect(safeMime(mime), 'application/octet-stream');
        }
      },
      // src/services/peer-transport.test.ts:163
    );
  });
}
