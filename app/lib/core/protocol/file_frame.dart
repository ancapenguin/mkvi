import 'dart:typed_data';

import 'peer_protocol.dart';
import 'peer_protocol_exception.dart';
import 'transfer_id.dart';

/// One binary file frame, laid out byte for byte as both ends must agree on it:
///
/// ```text
/// offset 0            1 byte    frame tag, always PeerProtocol.fileFrameTag
/// offset 1 .. 16     16 bytes   the transfer id, raw — not its hex text
/// offset 17 ..        n bytes   file payload
/// ```
///
/// The header is therefore [PeerProtocol.fileFrameHeaderBytes] — tag plus the
/// transfer id's raw bytes — and the id travels as *bytes*, not as its 32
/// character hex text, so a frame header is a fixed size.
///
/// There is **no length prefix**. The frame length is implicit — it is however
/// many bytes the data channel delivered past the header. A frame is therefore
/// only ever "short" in the sense that the transport cut it, and the receiver
/// catches that by comparing the running total against the size declared in the
/// `file-offer`. A frame carrying zero payload bytes is rejected outright,
/// because it would advance nothing and can only be a mistake.
final class FileFrame {
  const FileFrame({required this.id, required this.payload});

  /// Transfer id recovered from the header; always valid by construction.
  final String id;

  /// At least one byte, and at most [PeerProtocol.fileChunkBytes] in practice.
  final Uint8List payload;

  /// Serialises the frame.
  ///
  /// Throws [ArgumentError] for an empty payload, because such a frame could
  /// never be decoded again. That is a bug in the sender, not a protocol
  /// violation, which is why it is not a [PeerProtocolException].
  Uint8List toBytes() {
    if (payload.isEmpty) {
      throw ArgumentError.value(
        payload,
        'payload',
        'a file frame must carry at least one byte',
      );
    }
    final Uint8List frame = Uint8List(
      PeerProtocol.fileFrameHeaderBytes + payload.length,
    );
    frame[0] = PeerProtocol.fileFrameTag;
    frame.setRange(1, PeerProtocol.fileFrameHeaderBytes, transferIdToBytes(id));
    frame.setRange(PeerProtocol.fileFrameHeaderBytes, frame.length, payload);
    return frame;
  }

  /// Reads a frame, rejecting anything that is not one.
  ///
  /// The length is checked before the tag, and both raise the same message: a
  /// frame too short to hold a header has no tag to check, so checking the tag
  /// first would read a byte that is not there.
  static FileFrame decode(List<int> bytes) {
    if (bytes.length <= PeerProtocol.fileFrameHeaderBytes ||
        bytes[0] != PeerProtocol.fileFrameTag) {
      throw const PeerProtocolException(PeerProtocol.invalidFrame);
    }
    return FileFrame(
      id: transferIdFromBytes(
        bytes.sublist(1, PeerProtocol.fileFrameHeaderBytes),
      ),
      payload: Uint8List.fromList(
        bytes.sublist(PeerProtocol.fileFrameHeaderBytes),
      ),
    );
  }

  /// The payload length, which is `bytes.length - 17` on the wire.
  int get payloadLength => payload.length;

  @override
  String toString() => 'FileFrame(id: $id, payload: $payloadLength bytes)';
}
