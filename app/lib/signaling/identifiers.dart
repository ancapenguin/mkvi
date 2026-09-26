/// Identifier shapes that travel on the signaling wire.
///
/// Two of them exist, and both were once wrong in production:
///
/// * The 43 character base64url opaque id (`pair`, `device`, `session`). 32
///   random bytes, base64url, padding stripped. It is an unguessable bearer
///   capability, not a user identifier, and it is also a URL query value - which
///   is why it must never be produced in the standard alphabet.
/// * The 32 character lowercase hex transfer id used by the peer transport's
///   control messages. `crypto.randomUUID()` was used here once and produced a
///   hyphenated 36 character string, which the receiving `parseControl` rejected:
///   not a single message ever arrived. See the `transferId` cases in
///   `vectors/wire-v1.json`, which pin both the accepted and the rejected form.
library;

import 'dart:convert';
import 'dart:math';

const int _opaqueIdByteLength = 32;
const int _transferIdByteLength = 16;

/// The Worker's `OPAQUE_ID`, `^[A-Za-z0-9_-]{43}$`.
final RegExp opaqueIdPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// The transport's message id, `^[a-f0-9]{32}$`.
final RegExp transferIdPattern = RegExp(r'^[a-f0-9]{32}$');

List<int> _randomBytes(int length, Random? random) {
  final Random source = random ?? Random.secure();
  return List<int>.generate(length, (_) => source.nextInt(256));
}

/// 32 random bytes as unpadded base64url: 43 characters, `pair`/`device`/
/// `session`. Mirrors `createRendezvousId` in `src/App.tsx`.
String createOpaqueId({Random? random}) =>
    base64Url.encode(_randomBytes(_opaqueIdByteLength, random)).replaceAll('=', '');

/// 16 random bytes as lowercase hex: 32 characters. Mirrors `randomTransferId`
/// in `src/services/peer-transport.ts`, which is the fix for the `randomUUID()`
/// regression described in this file's header.
String createTransferId({Random? random}) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in _randomBytes(_transferIdByteLength, random)) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

bool isValidOpaqueId(String value) => opaqueIdPattern.hasMatch(value);

bool isValidTransferId(String value) => transferIdPattern.hasMatch(value);
