// A 1:1 port of `src/services/display-name.test.ts` (8 tests).
//
// These cover `safeDisplayName` and the `profile` branch of `parseControl`,
// which the 27-test transport suite only touched indirectly. The invisible code
// points are spelled as `String.fromCharCode` so that no zero-width or bidi
// character is ever stored literally in this source file.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/control_parser.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/peer_protocol_exception.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';

String repeat(String unit, int count) =>
    List<String>.filled(count, unit).join();

String encode(Map<String, Object?> value) => jsonEncode(value);

final Matcher throwsProtocolException = throwsA(isA<PeerProtocolException>());

/// U+200B ZERO WIDTH SPACE.
final String zeroWidthSpace = String.fromCharCode(0x200b);

/// U+202E RIGHT-TO-LEFT OVERRIDE, the classic header-spoofing character.
final String rightToLeftOverride = String.fromCharCode(0x202e);

/// U+FEFF ZERO WIDTH NO-BREAK SPACE, i.e. the BOM.
final String byteOrderMark = String.fromCharCode(0xfeff);

void main() {
  final String id = repeat('a', 32);

  group('safeDisplayName', () {
    test(
      'keeps an ordinary Turkish name intact',
      () {
        expect(safeDisplayName('Ayşe Gül'), 'Ayşe Gül');
      },
      // src/services/display-name.test.ts:9
    );

    test(
      'collapses whitespace and trims',
      () {
        expect(safeDisplayName('  ali   veli \n'), 'ali veli');
      },
      // src/services/display-name.test.ts:13
    );

    // The name is rendered verbatim in the header, so the peer must not be able
    // to inject line breaks, zero-width padding or bidi overrides into the layout.
    test(
      'strips control, zero-width and bidi characters',
      () {
        expect(safeDisplayName('a${String.fromCharCode(0x00)}b'), 'a b');
        expect(safeDisplayName('a${zeroWidthSpace}b'), 'a b');
        expect(safeDisplayName('a${rightToLeftOverride}b'), 'a b');
        expect(safeDisplayName('${byteOrderMark}ad'), 'ad');
      },
      // src/services/display-name.test.ts:19
    );

    test(
      'truncates to the protocol limit',
      () {
        expect(
          safeDisplayName(repeat('n', 200)),
          hasLength(PeerProtocol.maxDisplayNameLength),
        );
      },
      // src/services/display-name.test.ts:26
    );

    test(
      'returns an empty string when nothing usable remains',
      () {
        expect(safeDisplayName('   $zeroWidthSpace '), '');
      },
      // src/services/display-name.test.ts:30
    );
  });

  group('parseControl profile messages', () {
    test(
      'accepts a self-announced display name',
      () {
        expect(
          parseControl(
            encode(<String, Object?>{
              'type': 'profile',
              'id': id,
              'name': 'Kuzen',
            }),
          ),
          ProfileMessage(id: id, name: 'Kuzen'),
        );
      },
      // src/services/display-name.test.ts:36
    );

    test(
      'sanitises the announced name rather than trusting it',
      () {
        expect(
          parseControl(
            encode(<String, Object?>{
              'type': 'profile',
              'id': id,
              'name': '  kö${rightToLeftOverride}tü  ',
            }),
          ),
          ProfileMessage(id: id, name: 'kö tü'),
        );
      },
      // src/services/display-name.test.ts:40
    );

    test(
      'rejects a profile whose name is missing or empties out',
      () {
        expect(
          () => parseControl(
            encode(<String, Object?>{'type': 'profile', 'id': id}),
          ),
          throwsProtocolException,
        );
        expect(
          () => parseControl(
            encode(<String, Object?>{
              'type': 'profile',
              'id': id,
              'name': '   ',
            }),
          ),
          throwsProtocolException,
        );
        expect(
          () => parseControl(
            encode(<String, Object?>{'type': 'profile', 'id': id, 'name': 7}),
          ),
          throwsProtocolException,
        );
      },
      // src/services/display-name.test.ts:44
    );
  });
}
