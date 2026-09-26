import 'dart:math';
import 'dart:typed_data';

import 'peer_protocol.dart';

/// 16 random bytes rendered as 32 lowercase hex characters.
///
/// **The shape is the contract, not the algorithm.** An id must be a bare 32
/// character hex string: the control parser rejects anything else, so a dashed
/// UUID is a message the peer will refuse to parse. Chat frames once carried
/// dashed UUIDs, which made the receiving parser throw
/// [PeerProtocol.invalidControlMessage] and silently drop *every* message — the
/// sender saw no error, because from its side the frame went out fine. The test
/// "rejects a UUID, the shape that caused the dropped-message bug" guards the
/// shape, not the randomness.
String randomTransferId() {
  final Random random = Random.secure();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < PeerProtocol.transferIdBytes; i += 1) {
    out.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// Whether [value] is a bare 32 character lowercase hex transfer id.
bool isTransferId(String value) =>
    PeerProtocol.transferIdPattern.hasMatch(value);

/// Expands a transfer id into the 16 raw bytes carried in a file frame header.
///
/// The id is known to be well-formed here, so no validation is repeated; an
/// out-of-range slice would silently produce a zero byte, which is exactly the
/// kind of quiet corruption a frame header must not be able to carry.
Uint8List transferIdToBytes(String id) {
  final Uint8List bytes = Uint8List(PeerProtocol.transferIdBytes);
  for (int i = 0; i < PeerProtocol.transferIdBytes; i += 1) {
    bytes[i] = int.parse(id.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

/// Renders 16 raw frame-header bytes back into a transfer id.
///
/// Output is always a valid id by construction, which is why the frame reader
/// never re-validates it.
String transferIdFromBytes(List<int> bytes) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < PeerProtocol.transferIdBytes; i += 1) {
    out.write((bytes[i] & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}
