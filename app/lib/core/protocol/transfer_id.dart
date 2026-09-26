import 'dart:math';
import 'dart:typed_data';

import 'peer_protocol.dart';

/// 16 random bytes rendered as 32 lowercase hex characters.
///
/// TS: `randomTransferId`. The original comment is worth repeating verbatim,
/// because it explains the shape rather than the algorithm:
///
/// > Must be a bare 32-char hex id: parseControl rejects the dashes in
/// > randomUUID().
///
/// Chat frames once used `crypto.randomUUID()`, whose dashes made the receiving
/// `parseControl` throw "Geçersiz kontrol mesajı." and silently drop every
/// message. The ported test "rejects a UUID, the shape that caused the
/// dropped-message bug" guards against that regression.
String randomTransferId() {
  final Random random = Random.secure();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < PeerProtocol.transferIdBytes; i += 1) {
    out.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// Whether [value] is a bare 32 character lowercase hex transfer id.
///
/// TS: the inline `/^[a-f0-9]{32}$/.test(message.id)` of `parseControl`.
bool isTransferId(String value) =>
    PeerProtocol.transferIdPattern.hasMatch(value);

/// Expands a transfer id into the 16 raw bytes carried in a file frame header.
///
/// TS: `idToBytes`. The id is known to be well-formed here, so no validation is
/// repeated; an out-of-range slice would silently produce a zero byte, exactly
/// as `Number.parseInt` produces `NaN` in the original.
Uint8List transferIdToBytes(String id) {
  final Uint8List bytes = Uint8List(PeerProtocol.transferIdBytes);
  for (int i = 0; i < PeerProtocol.transferIdBytes; i += 1) {
    bytes[i] = int.parse(id.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

/// Renders 16 raw frame-header bytes back into a transfer id.
///
/// TS: `bytesToId`. Output is always a valid id by construction, which is why
/// `receiveFrame` never re-validates it.
String transferIdFromBytes(List<int> bytes) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < PeerProtocol.transferIdBytes; i += 1) {
    out.write((bytes[i] & 0xff).toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}
