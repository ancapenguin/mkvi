// The protocol constants are the one thing a port must not duplicate, so this
// file pins them to the TypeScript originals and pins the arithmetic and the
// hand-written patterns to the constants beside them.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';

void main() {
  group('limits match src/domain/peer-transport.ts', () {
    test('keeps the exported byte and length limits', () {
      expect(
        PeerProtocol.maxMessageBytes,
        32 * 1024,
        reason: 'MAX_MESSAGE_BYTES',
      );
      expect(
        PeerProtocol.maxFileBytes,
        512 * 1024 * 1024,
        reason: 'MAX_FILE_BYTES',
      );
      expect(
        PeerProtocol.maxDisplayNameLength,
        40,
        reason: 'MAX_DISPLAY_NAME_LENGTH',
      );
      expect(
        PeerProtocol.fileChunkBytes,
        16 * 1024,
        reason: 'FILE_CHUNK_BYTES',
      );
      expect(
        PeerProtocol.fileFlushBytes,
        4 * 1024 * 1024,
        reason: 'FILE_FLUSH_BYTES',
      );
    });

    test('keeps the private constants of src/services/peer-transport.ts', () {
      expect(PeerProtocol.fileFrameTag, 1, reason: 'FILE_FRAME');
      expect(PeerProtocol.transferIdBytes, 16, reason: 'FILE_ID_BYTES');
      expect(
        PeerProtocol.fileFrameHeaderBytes,
        1 + PeerProtocol.transferIdBytes,
        reason: 'FILE_HEADER_BYTES',
      );
      expect(
        PeerProtocol.maxConcurrentReceives,
        2,
        reason: 'MAX_CONCURRENT_RECEIVES',
      );
      expect(
        PeerProtocol.maxSafeInteger,
        9007199254740991,
        reason: 'Number.MAX_SAFE_INTEGER',
      );
    });

    test('keeps the inline slice limits of the sanitiser', () {
      expect(PeerProtocol.maxReasonLength, 256);
      expect(PeerProtocol.maxFileNameLength, 160);
      expect(PeerProtocol.maxMimeLength, 128);
      expect(PeerProtocol.defaultFileName, 'dosya');
      expect(PeerProtocol.defaultMimeType, 'application/octet-stream');
    });

    test('keeps the pairing code parameters', () {
      expect(
        PeerProtocol.pairingCodeAlphabet,
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
      );
      expect(PeerProtocol.pairingCodeAlphabet, hasLength(32));
      expect(PeerProtocol.pairingCodeLength, 13);
      expect(PeerProtocol.pairingCodeMaxLength, 16);
      expect(PeerProtocol.pairingCodeBits, 65);
      expect(PeerProtocol.capabilityLength, 43);
    });
  });

  group('the hand-written patterns agree with the constants', () {
    // text_sanitizer.dart spells its patterns out as literals so they read like
    // the TypeScript regular expressions. These assertions are what stop a
    // constant from being changed without the pattern following.
    test(
      'transferIdPattern matches exactly transferIdLength lowercase hex characters',
      () {
        expect(PeerProtocol.transferIdPattern.pattern, r'^[a-f0-9]{32}$');
        expect(
          PeerProtocol.transferIdPattern.hasMatch(
            'a' * PeerProtocol.transferIdLength,
          ),
          isTrue,
        );
        expect(
          PeerProtocol.transferIdPattern.hasMatch(
            'a' * (PeerProtocol.transferIdLength - 1),
          ),
          isFalse,
        );
        expect(
          PeerProtocol.transferIdPattern.hasMatch(
            'a' * (PeerProtocol.transferIdLength + 1),
          ),
          isFalse,
        );
        expect(
          PeerProtocol.transferIdPattern.hasMatch(
            'A' * PeerProtocol.transferIdLength,
          ),
          isFalse,
        );
        expect(
          PeerProtocol.transferIdPattern.hasMatch(
            '${'a' * PeerProtocol.transferIdLength}\n',
          ),
          isFalse,
        );
      },
    );

    test(
      'capabilityPattern matches exactly capabilityLength base64url characters',
      () {
        expect(PeerProtocol.capabilityPattern.pattern, r'^[A-Za-z0-9_-]{43}$');
        expect(
          PeerProtocol.capabilityPattern.hasMatch(
            'A' * PeerProtocol.capabilityLength,
          ),
          isTrue,
        );
        expect(
          PeerProtocol.capabilityPattern.hasMatch(
            'A' * (PeerProtocol.capabilityLength - 1),
          ),
          isFalse,
        );
        expect(
          PeerProtocol.capabilityPattern.hasMatch(
            '${'A' * (PeerProtocol.capabilityLength - 1)}+',
          ),
          isFalse,
        );
      },
    );

    test('the pairing alphabet is exactly the ranges the normaliser keeps', () {
      // A-H, J-N, P-Z and 2-9, which is what /[^A-HJ-NP-Z2-9]/ accepts.
      for (int unit = 0x41; unit <= 0x5a; unit += 1) {
        final bool kept = unit != 0x49 && unit != 0x4f;
        expect(
          PeerProtocol.pairingCodeAlphabet.contains(String.fromCharCode(unit)),
          kept,
          reason: 'letter ${String.fromCharCode(unit)}',
        );
      }
      for (int unit = 0x30; unit <= 0x39; unit += 1) {
        expect(
          PeerProtocol.pairingCodeAlphabet.contains(String.fromCharCode(unit)),
          unit >= 0x32,
          reason: 'digit $unit',
        );
      }
    });
  });

  group('byte budget is measured in UTF-8 bytes', () {
    test('agrees with the hand-computed UTF-8 length of every sample', () {
      // utf8ByteLength is the gate for the 32 KB cap, so these hand-computed
      // expectations are what pin it to a byte count rather than a character
      // count. The samples are built from code points so that no combining mark
      // is ever stored literally in this file.
      final Map<String, int> expectedBytes = <String, int>{
        '': 0,
        'a': 1,
        String.fromCharCode(0x015f): 2, // s with cedilla
        String.fromCharCode(0x011f): 2, // g with breve
        String.fromCharCode(0x20ac): 3, // euro sign
        String.fromCharCodes(<int>[0xd83d, 0xde00]):
            4, // grinning face, a surrogate pair
        String.fromCharCodes(<int>[
          0xd6,
          0x6d,
          0x65,
          0x72,
          0x20,
          0x15e,
          0x61,
          0x68,
          0x69,
          0x6e,
        ]): 12, // Omer Sahin
        String.fromCharCodes(<int>[0x00e1, 0x0302, 0x0303]):
            6, // a plus two combining marks
        String.fromCharCodes(<int>[0x0645, 0x0631, 0x062d, 0x0628, 0x0627]):
            10, // five Arabic letters
      };
      expectedBytes.forEach((String sample, int bytes) {
        expect(
          utf8ByteLength(sample),
          bytes,
          reason: 'byte length of "$sample"',
        );
      });
      // A combining sequence is one character but several bytes, which is the
      // whole reason the cap is a byte budget.
      expect(String.fromCharCodes(<int>[0x00e1, 0x0302]).runes.length, 2);
      expect(utf8ByteLength(String.fromCharCodes(<int>[0x00e1, 0x0302])), 4);
    });
  });
}
