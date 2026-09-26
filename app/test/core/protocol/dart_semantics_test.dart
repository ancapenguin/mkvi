// Cases the TypeScript suite could not have: places where Dart and JavaScript
// genuinely disagree, and therefore where a naive transliteration would either
// crash or quietly accept more than the Tauri build does.
//
// Every test here is an addition. Nothing in this file replaces a ported test.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/control_parser.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/peer_protocol_exception.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';

String repeat(String unit, int count) =>
    List<String>.filled(count, unit).join();

String encode(Map<String, Object?> value) => jsonEncode(value);

/// The matcher the TypeScript suite expressed as `expect(...).toThrow()`.
final Matcher throwsProtocolException = throwsA(isA<PeerProtocolException>());

final Matcher throwsMessageTooLarge = throwsA(
  isA<PeerProtocolException>().having(
    (PeerProtocolException e) => e.message,
    'message',
    contains('çok büyük'),
  ),
);

/// "I" followed by COMBINING DOT ABOVE: two code points, one grapheme, one
/// letter. The Turkish dotted capital I in decomposed form.
final String decomposedDottedCapitalI = String.fromCharCodes(<int>[
  0x49,
  0x0307,
]);

/// A lone high surrogate, which a well-formed UTF-8 decoder can never produce
/// and a peer can therefore only send by lying about its encoding.
final String loneSurrogate = String.fromCharCode(0xD800);

/// U+1F600 GRINNING FACE as a surrogate pair, i.e. what a real emoji is.
final String grinningFace = String.fromCharCodes(<int>[0xd83d, 0xde00]);

void main() {
  final String id = repeat('a', 32);
  final String discovery = repeat('A', 43);

  group('grapheme safety', () {
    // Required addition: the cap must not cut a combining sequence in half.
    test(
      'does not split a combining sequence when a display name is truncated at the boundary',
      () {
        // 39 plain characters, then a two-code-point letter, then one more: 42 code
        // points in total. A naive `slice(0, 40)` keeps the "I" and drops the
        // combining dot, which renders as a bare I instead of an İ.
        final String name =
            '${repeat('a', 39)}$decomposedDottedCapitalI'
            '${'b'}';
        expect(name.runes.length, 42);
        expect(
          name.length,
          42,
          reason: 'no surrogate pair, so code units and code points agree here',
        );

        final String cut = safeDisplayName(name);
        expect(
          cut,
          repeat('a', 39),
          reason: 'the dangling I is dropped with its mark',
        );
        expect(
          cut.runes.length,
          lessThanOrEqualTo(PeerProtocol.maxDisplayNameLength),
        );
        expect(
          cut.codeUnitAt(cut.length - 1),
          0x61,
          reason: 'ends on a whole character',
        );

        // A name that is exactly at the cap is untouched.
        expect(safeDisplayName(repeat('a', 40)), repeat('a', 40));
        expect(safeDisplayName(repeat('a', 41)), repeat('a', 40));
      },
    );

    test('leaves a precomposed Turkish name alone', () {
      // U+015F is one code point, so the grapheme guard must not shorten it.
      final String name = repeat('ş', 41);
      expect(safeDisplayName(name), repeat('ş', 40));
      expect(safeDisplayName('Ömer Şahin'), 'Ömer Şahin');
    });

    test(
      'does not cut a surrogate pair when an emoji lands on the boundary',
      () {
        // 39 plain characters then an emoji: 40 code points but 41 UTF-16 code
        // units, so the original's `.slice(0, 40)` would keep the high surrogate
        // and drop the low one, producing a lone surrogate and a broken emoji.
        final String name = repeat('a', 39) + grinningFace;
        expect(name.length, 41, reason: 'the emoji is two UTF-16 code units');
        expect(name.runes.length, 40, reason: 'but only one code point');

        final String cut = safeDisplayName(name);
        expect(
          cut,
          '${repeat('a', 39)}$grinningFace',
          reason: 'the whole emoji, never half of it',
        );
        expect(cut.length, 41, reason: 'both code units of the emoji survived');
        expect(
          cut.runes.every((int r) => r < 0xd800 || r > 0xdfff),
          isTrue,
          reason: 'no unpaired surrogate survives',
        );
      },
    );

    test('turns a zero-width joiner into a space before it could ever dangle', () {
      // U+200D is inside the zero-width range that safeDisplayName collapses to a
      // space, so it can never reach the truncation step and can never be left
      // dangling at the cap. A joined emoji therefore degrades to its two halves
      // with a space between them, which is a legal single-code-point cut.
      final String family = String.fromCharCodes(<int>[
        0x1f468,
        0x200d,
        0x1f469,
      ]);
      final String man = String.fromCharCode(0x1f468);
      final String woman = String.fromCharCode(0x1f469);
      expect(safeDisplayName(family), '$man $woman');
      expect(safeDisplayName('a$family'), 'a$man $woman');
      // Whatever the cap does here, it cannot leave a lone high surrogate.
      final String cut = safeDisplayName(repeat('a', 39) + family);
      expect(cut.runes.every((int r) => r < 0xd800 || r > 0xdfff), isTrue);
    });
  });

  group('invalid code points', () {
    // Required addition: an unpaired surrogate must not crash the sanitiser or
    // the size budget.
    test('does not crash on a lone surrogate or an invalid code point', () {
      expect(() => safeDisplayName('Merhaba$loneSurrogate'), returnsNormally);
      // The port maps it to a space, which the surrounding trim then removes.
      // The TypeScript original keeps it; see the deviation note in the report.
      expect(safeDisplayName('Merhaba$loneSurrogate'), 'Merhaba');
      expect(safeDisplayName(loneSurrogate), '');

      expect(() => safeName('a$loneSurrogate${'b'}'), returnsNormally);
      // safeName mirrors the original character class, which does not list
      // surrogates, so the lone surrogate is preserved here rather than replaced.
      expect(safeName('a$loneSurrogate${'b'}'), 'a$loneSurrogate${'b'}');

      expect(safeMime('text$loneSurrogate/plain'), 'application/octet-stream');
      expect(() => safeMime('text$loneSurrogate/plain'), returnsNormally);

      // Measuring the byte budget must not throw either. utf8.encode replaces the
      // unpaired surrogate with the three bytes of U+FFFD.
      expect(utf8ByteLength('x$loneSurrogate'), 4);
      expect(utf8ByteLength(loneSurrogate), 3);

      // A *valid* surrogate pair is an ordinary character and must survive.
      expect(safeDisplayName('a${grinningFace}b'), 'a${grinningFace}b');
      expect(utf8ByteLength(grinningFace), 4);
      expect(
        parseControl(
          encode(<String, Object?>{
            'type': 'chat',
            'id': id,
            'text': grinningFace,
            'sentAt': 1,
          }),
        ),
        isA<ChatMessage>(),
      );
    });

    test('measures the control budget in UTF-8 bytes for a multi-byte body', () {
      // The mirror image of the ported "multi-byte body" test, pinned to the
      // exact boundary: a body that fills the remaining byte budget is accepted
      // and one two-byte character more is not.
      final int overhead = utf8
          .encode(
            encode(<String, Object?>{
              'type': 'chat',
              'id': id,
              'text': '',
              'sentAt': 1,
            }),
          )
          .length;
      final int bodyByteBudget = PeerProtocol.maxMessageBytes - overhead;
      expect(
        bodyByteBudget.isEven,
        isTrue,
        reason: 'so the boundary is reachable with a two-byte character',
      );

      final String justFits = repeat('ş', bodyByteBudget ~/ 2);
      expect(utf8ByteLength(justFits), bodyByteBudget);
      final PeerControlMessage accepted = parseControl(
        encode(<String, Object?>{
          'type': 'chat',
          'id': id,
          'text': justFits,
          'sentAt': 1,
        }),
      );
      expect((accepted as ChatMessage).text, justFits);

      final String oneByteTooMuch = repeat('ş', bodyByteBudget ~/ 2 + 1);
      expect(utf8ByteLength(oneByteTooMuch), bodyByteBudget + 2);
      expect(
        () => parseControl(
          encode(<String, Object?>{
            'type': 'chat',
            'id': id,
            'text': oneByteTooMuch,
            'sentAt': 1,
          }),
        ),
        throwsProtocolException,
      );
    });
  });

  group('duplicate JSON keys', () {
    // Required addition: `JSON.parse` keeps the last member of a duplicated key
    // and so does `jsonDecode`, so the port has to agree rather than reject or
    // pick the first.
    test('keeps the last of a duplicate JSON key, like JSON.parse', () {
      expect(
        parseControl(
          '{"type":"chat","type":"chat","id":"$id","text":"x","sentAt":1}',
        ),
        isA<ChatMessage>(),
      );
      // The dangerous shape: a legitimate type followed by an injected one.
      expect(
        () => parseControl(
          '{"type":"chat","type":"eval","id":"$id","text":"x","sentAt":1}',
        ),
        throwsProtocolException,
      );
      // Reversed, last-wins resolves to the legitimate one.
      expect(
        parseControl(
          '{"type":"eval","type":"chat","id":"$id","text":"x","sentAt":1}',
        ),
        isA<ChatMessage>(),
      );
      // The id is validated after the merge, so a duplicated id cannot smuggle a
      // bad one in front of a good one.
      expect(
        () => parseControl('{"type":"call-end","id":"$id","id":"olmayan"}'),
        throwsProtocolException,
      );
      // A duplicated field is merged the same way.
      expect(
        () => parseControl(
          '{"type":"call-offer","id":"$id","mode":"video","mode":"screen"}',
        ),
        throwsProtocolException,
      );
      expect(
        parseControl(
          '{"type":"call-offer","id":"$id","mode":"screen","mode":"video"}',
        ),
        CallOfferMessage(id: id, mode: CallMode.video),
      );
    });
  });

  group('integer overflow', () {
    // Required addition: a declared file size that does not fit a 64-bit integer
    // must be rejected, not clamped and not crash.
    test('rejects a declared file size that overflows a 64-bit integer', () {
      const String twoTo63 =
          '9223372036854775808'; // 2^63, one past the largest int
      const String twoTo53 =
          '9007199254740992'; // 2^53, the first inexact integer in JavaScript
      const String twoTo53Minus1 =
          '9007199254740991'; // Number.MAX_SAFE_INTEGER

      String offer(String size) =>
          '{"type":"file-offer","id":"$id","name":"a.bin","mime":"text/plain","size":$size}';

      // `jsonDecode` cannot hold 2^63 as an int and falls back to a double, so
      // the safe-integer bound has to catch it. Note that `double.toInt()`
      // *clamps* to 2^63-1 rather than throwing, which is exactly why the bound
      // is checked before the conversion.
      expect(asJavaScriptSafeInteger(9223372036854775808.0), isNull);
      expect(() => parseControl(offer(twoTo63)), throwsProtocolException);

      expect(asJavaScriptSafeInteger(9007199254740992), isNull);
      expect(() => parseControl(offer(twoTo53)), throwsProtocolException);

      // 2^53-1 is a safe integer, but it is far above the 512 MB protocol cap.
      expect(asJavaScriptSafeInteger(9007199254740991), 9007199254740991);
      expect(() => parseControl(offer(twoTo53Minus1)), throwsProtocolException);

      // A syntactically valid JSON number that decodes to Infinity in both
      // languages; JavaScript's `JSON.stringify(NaN)` writes `null`, so `1e400`
      // is the spelling that actually puts a non-finite value on the wire.
      expect(() => parseControl(offer('1e400')), throwsProtocolException);
      expect(() => parseControl(offer('-1e400')), throwsProtocolException);

      // The cap itself still works, so the bound did not swallow the range check.
      expect(
        (parseControl(offer('${PeerProtocol.maxFileBytes}'))
                as FileOfferMessage)
            .size,
        PeerProtocol.maxFileBytes,
      );
      expect((parseControl(offer('1')) as FileOfferMessage).size, 1);
    });

    test(
      'treats a JSON number written with a decimal point as an integer, like Number.isSafeInteger',
      () {
        // `JSON.parse("1.0")` is 1 in JavaScript and `Number.isSafeInteger(1)` is
        // true, so the original accepts this frame. A Dart port that required an
        // `int` here would reject a frame the Tauri build accepts.
        final PeerControlMessage parsed = parseControl(
          '{"type":"file-offer","id":"$id","name":"a.bin","mime":"text/plain","size":1.0}',
        );
        expect((parsed as FileOfferMessage).size, 1);
        expect(asJavaScriptSafeInteger(1.0), 1);
        expect(asJavaScriptSafeInteger(1.5), isNull);
        expect(asJavaScriptSafeInteger(double.nan), isNull);
        expect(asJavaScriptSafeInteger(double.infinity), isNull);
        expect(asJavaScriptSafeInteger('10'), isNull);
        expect(asJavaScriptSafeInteger(null), isNull);
        expect(asJavaScriptSafeInteger(true), isNull);
      },
    );
  });

  group('absent versus explicit null', () {
    // Not in the TypeScript suite, but `null` and "key not present" are the same
    // value in Dart and different values in JavaScript, so the port has to
    // distinguish them explicitly to stay compatible.
    test(
      'rejects an explicit null where the original expects an absent key',
      () {
        expect(
          () => parseControl(
            '{"type":"pair-confirmed","id":"$id","discovery":null}',
          ),
          throwsProtocolException,
        );
        expect(
          () =>
              parseControl('{"type":"call-decline","id":"$id","reason":null}'),
          throwsProtocolException,
        );
        expect(
          () =>
              parseControl('{"type":"file-decline","id":"$id","reason":null}'),
          throwsProtocolException,
        );
        expect(
          () => parseControl('{"type":"file-cancel","id":"$id","reason":null}'),
          throwsProtocolException,
        );

        // The absent form is accepted, and is not written back out.
        expect(
          (parseControl('{"type":"pair-confirmed","id":"$id"}')
                  as PairConfirmedMessage)
              .discovery,
          isNull,
        );
        expect(
          (parseControl('{"type":"call-decline","id":"$id"}')
                  as CallDeclineMessage)
              .reason,
          isNull,
        );
      },
    );
  });

  group('wire round trip', () {
    // Not in the TypeScript suite, but the port adds an encoder, so every one of
    // the twelve variants has to survive encode-then-parse unchanged.
    test('round-trips every control type through encode and parse', () {
      final List<PeerControlMessage> messages = <PeerControlMessage>[
        ChatMessage(id: id, text: 'merhaba', sentAt: 1),
        ChatMessage(id: id, text: 'şğü', sentAt: 1700000000000),
        FileOfferMessage(id: id, name: 'a.bin', mime: 'text/plain', size: 10),
        FileAcceptMessage(id: id),
        FileDeclineMessage(id: id, reason: 'Alıcı dosyayı kabul etmedi.'),
        FileDeclineMessage(id: id),
        FileCompleteMessage(id: id),
        FileCancelMessage(id: id, reason: 'Aktarım iptal edildi.'),
        FileCancelMessage(id: id),
        CallOfferMessage(id: id, mode: CallMode.audio),
        CallOfferMessage(id: id, mode: CallMode.video),
        CallAcceptMessage(id: id),
        CallDeclineMessage(id: id, reason: 'Meşgul.'),
        CallDeclineMessage(id: id),
        CallEndMessage(id: id),
        PairConfirmedMessage(id: id, discovery: discovery),
        PairConfirmedMessage(id: id),
        ProfileMessage(id: id, name: 'Ayşe'),
      ];
      expect(messages, hasLength(18));

      for (final PeerControlMessage message in messages) {
        expect(
          parseControl(encodeControl(message)),
          message,
          reason: 'a ${message.type} frame must survive the round trip',
        );
      }
    });

    test('writes exactly the JSON the TypeScript object literals produced', () {
      expect(
        encodeControl(ChatMessage(id: id, text: 'x', sentAt: 1)),
        '{"type":"chat","id":"$id","text":"x","sentAt":1}',
      );
      expect(
        encodeControl(
          FileOfferMessage(id: id, name: 'a.bin', mime: 'text/plain', size: 10),
        ),
        '{"type":"file-offer","id":"$id","name":"a.bin","mime":"text/plain","size":10}',
      );
      expect(
        encodeControl(CallOfferMessage(id: id, mode: CallMode.video)),
        '{"type":"call-offer","id":"$id","mode":"video"}',
      );
      expect(
        encodeControl(CallEndMessage(id: id)),
        '{"type":"call-end","id":"$id"}',
      );
      // An absent optional field is omitted, exactly as `JSON.stringify` omits
      // `undefined`; it is not written as null.
      expect(
        encodeControl(FileDeclineMessage(id: id)),
        '{"type":"file-decline","id":"$id"}',
      );
      expect(
        encodeControl(PairConfirmedMessage(id: id)),
        '{"type":"pair-confirmed","id":"$id"}',
      );
      expect(
        encodeControl(CallDeclineMessage(id: id)),
        '{"type":"call-decline","id":"$id"}',
      );
    });
  });

  group('byte oriented entry point', () {
    test('parses a control frame handed over as bytes', () {
      final Uint8List bytes = Uint8List.fromList(
        utf8.encode(encodeControl(ChatMessage(id: id, text: 'ş', sentAt: 1))),
      );
      expect(
        parseControlBytes(bytes),
        ChatMessage(id: id, text: 'ş', sentAt: 1),
      );

      // The size guard runs before any decoding, so a huge frame costs nothing.
      expect(
        () => parseControlBytes(Uint8List(PeerProtocol.maxMessageBytes + 1)),
        throwsMessageTooLarge,
      );

      // Strict UTF-8: a frame that is not valid UTF-8 is rejected, not repaired.
      expect(
        () => parseControlBytes(<int>[0xff, 0xfe, 0xfd]),
        throwsProtocolException,
      );
      // A CESU-8 encoding of a surrogate half is invalid UTF-8 as well.
      expect(
        () => parseControlBytes(<int>[0xed, 0xa0, 0x80]),
        throwsProtocolException,
      );
      // Valid UTF-8 that is not a frame is still a rejected frame.
      expect(
        () => parseControlBytes(utf8.encode('ç')),
        throwsProtocolException,
      );
    });
  });

  group('reason sanitising is deliberately asymmetric', () {
    // Not in the TypeScript suite, and the port deliberately diverges here.
    // src/services/peer-transport.ts:546 slices a file-decline/file-cancel reason
    // raw while :547 runs a call-decline reason through safeReason. A file
    // decline is rendered in a transfer row, so 0.1.x puts raw newlines, tabs
    // and leading spaces into the interface. This port scrubs all three.
    test('scrubs a file decline reason too, unlike 0.1.x', () {
      final String bidi = String.fromCharCode(0x202e);
      // Two whitespace runs, two control characters and an over-long tail.
      final String noisy = '  Meşgul\n\t$bidi  ${repeat('x', 400)}';

      final CallDeclineMessage call =
          parseControl(
                '{"type":"call-decline","id":"$id","reason":${jsonEncode(noisy)}}',
              )
              as CallDeclineMessage;
      // safeReason replaces U+0000-U+001F and U+007F with a space, collapses the
      // runs, trims, then slices to 256.
      expect(call.reason, safeReason(noisy));
      expect(call.reason, hasLength(PeerProtocol.maxReasonLength));
      expect(call.reason, startsWith('Meşgul $bidi '));
      expect(call.reason, isNot(contains('\n')));
      expect(call.reason, isNot(contains('\t')));

      final FileDeclineMessage file =
          parseControl(
                '{"type":"file-decline","id":"$id","reason":${jsonEncode(noisy)}}',
              )
              as FileDeclineMessage;
      // Same treatment as the call decline: identical output, and the 256 code
      // point cap still applies.
      expect(file.reason, safeReason(noisy));
      expect(file.reason, call.reason);
      expect(file.reason, hasLength(PeerProtocol.maxReasonLength));
      expect(file.reason, isNot(contains('\n')));
      expect(file.reason, isNot(contains('\t')));
      expect(file.reason, isNot(startsWith(' ')));

      // Neither branch strips a bidi override: only `safeDisplayName` does, and
      // the reason is rendered as plain text, not as a label.
      expect(safeReason(bidi), bidi);
      expect(safeDisplayName(bidi), '');
    });
  });

  group('ECMAScript whitespace set', () {
    // Not in the TypeScript suite, but `dart:core`'s `String.trim` uses a
    // different whitespace definition than JavaScript's, so the port implements
    // the ECMAScript set itself. This pins every member of that set.
    test('treats every ECMAScript whitespace as a single space', () {
      const List<int> ecmaWhitespace = <int>[
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, // tab, LF, VT, FF, CR
        0x20, // space
        0xa0, // no-break space
        0x1680, // ogham space mark
        0x2000,
        0x2001,
        0x2002,
        0x2003,
        0x2004,
        0x2005,
        0x2006,
        0x2007,
        0x2008,
        0x2009,
        0x200a, // en quad .. hair space
        0x2028, 0x2029, // line and paragraph separator
        0x202f, // narrow no-break space
        0x205f, // medium mathematical space
        0x3000, // ideographic space
        0xfeff, // BOM
      ];
      for (final int code in ecmaWhitespace) {
        final String space = String.fromCharCode(code);
        final String label =
            'U+${code.toRadixString(16).toUpperCase().padLeft(4, '0')}';
        expect(
          safeDisplayName('a${space}b'),
          'a b',
          reason: '$label between two letters',
        );
        expect(
          safeDisplayName('${space}a$space'),
          'a',
          reason: '$label is trimmed',
        );
        expect(
          safeReason('a${space}b'),
          'a b',
          reason: '$label in a decline reason',
        );
        expect(
          safeReason('a$space'),
          'a',
          reason: '$label is trimmed from a reason',
        );
      }
      // A run of several collapses to one, as the original's `/\s+/g` does.
      expect(safeDisplayName('a${' ' * 5}b'), 'a b');
    });

    test('keeps U+0085, which dart:core trims but ECMAScript does not', () {
      // NEL is Unicode White_Space but not an ECMAScript `\s`. JavaScript keeps
      // it inside a display name; the port keeps it too.
      final String nel = String.fromCharCode(0x85);
      expect(safeDisplayName('a${nel}b'), 'a${nel}b');
    });
  });

  group('media type anchoring', () {
    // Not in the TypeScript suite. The original validated with a regular
    // expression whose `^`/`$` do not match around a trailing newline, and the
    // port replaced the expression with a scanner; this pins the two together.
    test('does not accept a media type with anything around it', () {
      for (final String candidate in <String>[
        'text/plain\n',
        '\ntext/plain',
        'text/plain\r',
        ' text/plain',
        'text/plain ',
        'text/plain; charset=utf-8',
        'text//plain',
        'te xt/plain',
        'text/pl ain',
        'TÉXT/plain',
      ]) {
        expect(
          safeMime(candidate),
          'application/octet-stream',
          reason: 'safeMime must reject "$candidate"',
        );
      }
      // A very long but well-formed type is validated first and then cut.
      final String long1 = 'application/${repeat('x', 200)}';
      expect(safeMime(long1), hasLength(PeerProtocol.maxMimeLength));
    });
  });
}
