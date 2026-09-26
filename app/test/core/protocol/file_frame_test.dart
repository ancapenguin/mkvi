// The binary file frame, byte for byte, plus the protocol half of an incoming
// transfer.
//
// The frame header size, the chunk size and the concurrency cap are the three
// numbers a file transfer is most likely to get wrong, and all three are
// invisible at runtime: a wrong header size does not throw, it silently
// misattributes bytes to the wrong transfer. So they are pinned here rather than
// trusted.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/control_parser.dart';
import 'package:mkvi/core/protocol/file_frame.dart';
import 'package:mkvi/core/protocol/file_transfer.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/peer_protocol_exception.dart';
import 'package:mkvi/core/protocol/transfer_id.dart';

String repeat(String unit, int count) =>
    List<String>.filled(count, unit).join();

final Matcher throwsProtocolException = throwsA(isA<PeerProtocolException>());

Matcher throwsWithMessage(String message) => throwsA(
  isA<PeerProtocolException>().having(
    (PeerProtocolException e) => e.message,
    'message',
    message,
  ),
);

/// A frame exactly as `streamFile` builds it: tag, raw id bytes, payload.
Uint8List buildFrame(String id, List<int> payload) {
  final Uint8List frame = Uint8List(
    PeerProtocol.fileFrameHeaderBytes + payload.length,
  );
  frame[0] = PeerProtocol.fileFrameTag;
  frame.setRange(1, PeerProtocol.fileFrameHeaderBytes, transferIdToBytes(id));
  frame.setRange(PeerProtocol.fileFrameHeaderBytes, frame.length, payload);
  return frame;
}

FileOfferMessage offer({
  required String id,
  required int size,
  String name = 'a.bin',
}) {
  final PeerControlMessage parsed = parseControl(
    '{"type":"file-offer","id":"$id","name":"$name","mime":"text/plain","size":$size}',
  );
  return parsed as FileOfferMessage;
}

void main() {
  final String id = repeat('a', 32);

  group('transfer id', () {
    test('is 32 lowercase hex characters drawn from 16 random bytes', () {
      for (int attempt = 0; attempt < 64; attempt += 1) {
        final String generated = randomTransferId();
        expect(generated, hasLength(PeerProtocol.transferIdLength));
        expect(generated, matches(PeerProtocol.transferIdPattern));
        expect(isTransferId(generated), isTrue);
        expect(
          generated.codeUnits.every((int unit) => unit >= 0x30 && unit <= 0x66),
          isTrue,
        );
      }
    });

    test('survives the byte round trip through a frame header', () {
      // Known vectors: the id is hex, so the byte layout is directly checkable.
      expect(transferIdToBytes(repeat('0', 32)), Uint8List(16));
      expect(
        transferIdToBytes(repeat('f', 32)),
        Uint8List.fromList(List<int>.filled(16, 0xff)),
      );
      expect(
        transferIdToBytes('0123456789abcdef0123456789abcdef'),
        Uint8List.fromList(<int>[
          0x01,
          0x23,
          0x45,
          0x67,
          0x89,
          0xab,
          0xcd,
          0xef,
          0x01,
          0x23,
          0x45,
          0x67,
          0x89,
          0xab,
          0xcd,
          0xef,
        ]),
      );
      for (final String sample in <String>[
        randomTransferId(),
        randomTransferId(),
        repeat('0', 32),
        repeat('f', 32),
      ]) {
        expect(transferIdFromBytes(transferIdToBytes(sample)), sample);
        expect(
          transferIdFromBytes(transferIdToBytes(sample)),
          matches(PeerProtocol.transferIdPattern),
        );
      }
    });
  });

  group('file frame layout', () {
    test('is a one byte tag, sixteen raw id bytes and the payload', () {
      final Uint8List payload = Uint8List.fromList(<int>[
        0xde,
        0xad,
        0xbe,
        0xef,
      ]);
      final FileFrame frame = FileFrame(id: id, payload: payload);
      final Uint8List bytes = frame.toBytes();

      expect(PeerProtocol.fileFrameHeaderBytes, 17);
      expect(PeerProtocol.fileFrameTag, 1);
      expect(PeerProtocol.transferIdBytes, 16);
      expect(bytes.length, 17 + payload.length);
      expect(bytes[0], 1, reason: 'FILE_FRAME tag');
      expect(
        bytes.sublist(1, 17),
        transferIdToBytes(id),
        reason: 'the id travels as raw bytes, not as hex text',
      );
      expect(bytes.sublist(17), payload);
      // The frame carries no length prefix: the length is however many bytes
      // arrived past the header.
      expect(
        bytes.length - PeerProtocol.fileFrameHeaderBytes,
        frame.payloadLength,
      );
    });

    test('round-trips through decode', () {
      final Uint8List payload = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      final FileFrame decoded = FileFrame.decode(buildFrame(id, payload));
      expect(decoded.id, id);
      expect(decoded.payload, payload);
      expect(decoded.payloadLength, 5);
    });

    test('carries a full 16 KB chunk', () {
      final Uint8List payload = Uint8List(PeerProtocol.fileChunkBytes);
      for (int i = 0; i < payload.length; i += 1) {
        payload[i] = i & 0xff;
      }
      expect(PeerProtocol.fileChunkBytes, 16 * 1024);
      final FileFrame decoded = FileFrame.decode(buildFrame(id, payload));
      expect(decoded.payloadLength, PeerProtocol.fileChunkBytes);
      expect(decoded.payload.first, 0);
      expect(decoded.payload.last, 0xff);
    });

    test('rejects a frame that is not a frame', () {
      // `bytes.byteLength <= FILE_HEADER_BYTES` throws before the tag is even
      // looked at, so a header with no payload is rejected.
      expect(
        () => FileFrame.decode(Uint8List(17)),
        throwsWithMessage(PeerProtocol.invalidFrame),
      );
      expect(
        () => FileFrame.decode(Uint8List(16)),
        throwsWithMessage(PeerProtocol.invalidFrame),
      );
      expect(
        () => FileFrame.decode(<int>[]),
        throwsWithMessage(PeerProtocol.invalidFrame),
      );
      // Right length, wrong tag.
      final Uint8List wrongTag = buildFrame(id, <int>[1]);
      wrongTag[0] = 2;
      expect(
        () => FileFrame.decode(wrongTag),
        throwsWithMessage(PeerProtocol.invalidFrame),
      );
      // A control frame arriving on the binary path is not a file frame either.
      expect(
        () => FileFrame.decode(Uint8List.fromList(<int>[0x7b, 0x7d, 0x0a])),
        throwsWithMessage(PeerProtocol.invalidFrame),
      );
    });

    test('refuses to build a frame that could never be decoded', () {
      expect(
        () => FileFrame(id: id, payload: Uint8List(0)).toBytes(),
        throwsArgumentError,
      );
    });
  });

  group('incoming transfer admission', () {
    test('admits an announced file', () {
      final PeerFileReceiver receiver = PeerFileReceiver();
      final FileOfferAdmission admission = receiver.offer(
        offer(id: id, size: 10),
      );
      expect(admission, isA<FileOfferAccepted>());
      expect(
        (admission as FileOfferAccepted).file,
        IncomingFile(id: id, name: 'a.bin', mime: 'text/plain', size: 10),
      );
      expect(receiver.pendingCount, 1);
      expect(receiver.contains(id), isTrue);
      expect(receiver.isAccepted(id), isFalse);
    });

    test(
      'refuses a third pending transfer with the Turkish auto-decline reason',
      () {
        final PeerFileReceiver receiver = PeerFileReceiver();
        expect(PeerProtocol.maxConcurrentReceives, 2);
        final String second = repeat('b', 32);
        final String third = repeat('c', 32);

        expect(
          receiver.offer(offer(id: id, size: 10)),
          isA<FileOfferAccepted>(),
        );
        expect(
          receiver.offer(offer(id: second, size: 10)),
          isA<FileOfferAccepted>(),
        );

        final FileOfferAdmission refused = receiver.offer(
          offer(id: third, size: 10),
        );
        expect(refused, isA<FileOfferRefused>());
        expect((refused as FileOfferRefused).id, third);
        expect(refused.reason, 'Çok fazla bekleyen aktarım var.');
        expect(
          receiver.pendingCount,
          2,
          reason: 'a refused offer is not stored',
        );
        expect(receiver.contains(third), isFalse);

        // Freeing a slot lets the next offer in.
        expect(receiver.drop(second), isTrue);
        expect(
          receiver.offer(offer(id: third, size: 10)),
          isA<FileOfferAccepted>(),
        );
      },
    );

    test(
      'refuses a re-announced id instead of resetting the live transfer',
      () {
        // A re-announced id must NOT replace the live transfer. Doing so resets
        // `received` to 0 and `accepted` to false mid-transfer, and — because it
        // overwrites rather than adds — never trips the capacity guard. A peer
        // could then reset the progress the user is watching, forever, while
        // still occupying exactly one slot. This port refuses the repeat.
        final PeerFileReceiver receiver = PeerFileReceiver();
        receiver.offer(offer(id: id, size: 10));
        receiver.accept(id);
        receiver.addFrame(buildFrame(id, <int>[1, 2, 3]));
        expect(receiver.receivedBytesOf(id), 3);

        final FileOfferAdmission repeat = receiver.offer(offer(id: id, size: 10));
        expect(repeat, isA<FileOfferRefused>());
        expect(
          (repeat as FileOfferRefused).reason,
          PeerProtocol.transferAlreadyReceiving,
        );
        // The transfer the user already accepted is untouched.
        expect(receiver.receivedBytesOf(id), 3);
        expect(receiver.isAccepted(id), isTrue);
        expect(receiver.pendingCount, 1);
      },
    );

    test('refuses a re-announced id once the receiver is at capacity', () {
      // The capacity guard runs *before* the map write, exactly as in the
      // original, so the quirk above is only reachable below
      // MAX_CONCURRENT_RECEIVES. At capacity even a repeat is auto-declined and
      // the first announcement survives.
      final PeerFileReceiver receiver = PeerFileReceiver();
      receiver.offer(offer(id: id, size: 10));
      receiver.offer(offer(id: repeat('b', 32), size: 10));
      final FileOfferAdmission refused = receiver.offer(
        offer(id: id, size: 20),
      );
      expect(refused, isA<FileOfferRefused>());
      expect(
        (refused as FileOfferRefused).reason,
        'Çok fazla bekleyen aktarım var.',
      );
      expect(
        receiver.offerOf(id)!.size,
        10,
        reason: 'the first announcement survives',
      );
    });

    test('rejects accepting a transfer that was never announced', () {
      final PeerFileReceiver receiver = PeerFileReceiver();
      expect(
        () => receiver.accept(id),
        throwsWithMessage('Dosya teklifi bulunamadı.'),
      );
      // Accepting twice is a no-op, not an error.
      receiver.offer(offer(id: id, size: 10));
      receiver.accept(id);
      expect(() => receiver.accept(id), returnsNormally);
    });
  });

  group('incoming frame accounting', () {
    late PeerFileReceiver receiver;

    setUp(() {
      receiver = PeerFileReceiver();
      receiver.offer(offer(id: id, size: 10));
    });

    test(
      'refuses a frame for a transfer that is announced but not accepted',
      () {
        expect(
          () => receiver.addFrame(buildFrame(id, <int>[1])),
          throwsWithMessage('İzin verilmeyen dosya verisi alındı.'),
        );
      },
    );

    test('refuses a frame for a transfer nobody announced', () {
      receiver.accept(id);
      expect(
        () => receiver.addFrame(buildFrame(repeat('b', 32), <int>[1])),
        throwsWithMessage('İzin verilmeyen dosya verisi alındı.'),
      );
    });

    test(
      'refuses a frame that would push the transfer past its declared size',
      () {
        receiver.accept(id);
        expect(
          () => receiver.addFrame(
            buildFrame(id, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
          ),
          throwsWithMessage('Dosya beklenen boyutu aşıyor.'),
        );
        // The refusal does not count the bytes.
        expect(receiver.receivedBytesOf(id), 0);
        // Exactly the declared size is fine.
        receiver.addFrame(buildFrame(id, List<int>.filled(6, 1)));
        expect(
          receiver.addFrame(buildFrame(id, List<int>.filled(4, 2))),
          isA<TransferProgress>(),
        );
        expect(receiver.receivedBytesOf(id), 10);
        expect(receiver.isComplete(id), isTrue);
        // One byte more is not.
        expect(
          () => receiver.addFrame(buildFrame(id, <int>[1])),
          throwsWithMessage('Dosya beklenen boyutu aşıyor.'),
        );
      },
    );

    test('reports progress with the name that travels on every tick', () {
      receiver.accept(id);
      final TransferProgress first = receiver.addFrame(
        buildFrame(id, List<int>.filled(4, 7)),
      );
      expect(
        first,
        TransferProgress(
          id: id,
          name: 'a.bin',
          direction: TransferDirection.receive,
          transferred: 4,
          total: 10,
        ),
      );
      expect(first.id, id);
      expect(first.name, 'a.bin');
      expect(first.direction, TransferDirection.receive);
      expect(first.transferred, 4);
      expect(first.total, 10);
      expect(receiver.isComplete(id), isFalse);

      final TransferProgress second = receiver.addFrame(
        buildFrame(id, List<int>.filled(6, 7)),
      );
      expect(second.transferred, 10);
      expect(receiver.isComplete(id), isTrue);
    });

    test(
      'keeps a Turkish file name intact through the offer and the progress tick',
      () {
        final PeerFileReceiver turkish = PeerFileReceiver();
        final String turkishId = repeat('9', 32);
        turkish.offer(offer(id: turkishId, size: 4, name: 'ödev şşğ.txt'));
        turkish.accept(turkishId);
        expect(
          turkish.addFrame(buildFrame(turkishId, List<int>.filled(4, 1))).name,
          'ödev şşğ.txt',
        );
      },
    );

    test('forgets a dropped transfer and refuses its later frames', () {
      receiver.accept(id);
      receiver.addFrame(buildFrame(id, <int>[1, 2]));
      expect(receiver.drop(id), isTrue);
      expect(
        receiver.drop(id),
        isFalse,
        reason: 'dropping twice is not an error',
      );
      expect(receiver.pendingCount, 0);
      expect(
        () => receiver.addFrame(buildFrame(id, <int>[1, 2])),
        throwsWithMessage('İzin verilmeyen dosya verisi alındı.'),
      );
    });
  });
}
