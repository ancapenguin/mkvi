/// Query-string encoding for signaling URLs.
///
/// This is the WHATWG `URLSearchParams` serializer
/// (`application/x-www-form-urlencoded`), implemented here because the exact
/// bytes matter:
///
/// * `A-Za-z0-9*._-` stay literal, a space becomes `+`, everything else becomes
///   uppercase percent-encoded UTF-8.
/// * `+` MUST become `%2B` and `/` MUST become `%2F`.
///
/// Why this is not left to `Uri.queryParameters`: that serializer emits a raw
/// `+` for a literal `+` in a value, and every server that decodes a query with
/// form rules reads that `+` back as a SPACE. A standard-base64 opaque id would
/// arrive corrupted and the Worker would answer 400 - the same class of silent
/// pairing failure as the two bugs recorded in `vectors/wire-v1.json`.
///
/// The two characters where `Uri.queryParameters` and `URLSearchParams` differ
/// are `~` (Dart leaves it, the spec encodes `%7E`) and `*` (Dart encodes
/// `%2A`, the spec leaves it). Neither appears in any signaling alphabet, and
/// both round trip correctly, so the difference is documented rather than
/// pinned by a vector.
library;

import 'dart:convert';

/// True for the characters the serializer keeps as-is.
bool _staysLiteral(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) || // A-Z
    (rune >= 0x61 && rune <= 0x7A) || // a-z
    (rune >= 0x30 && rune <= 0x39) || // 0-9
    rune == 0x2A || // *
    rune == 0x2D || // -
    rune == 0x2E || // .
    rune == 0x5F; // _

/// Encodes one query-string component exactly as `URLSearchParams` would.
String encodeQueryComponent(String value) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in value.runes) {
    if (_staysLiteral(rune)) {
      buffer.writeCharCode(rune);
    } else if (rune == 0x20) {
      buffer.write('+');
    } else {
      for (final int byte in utf8.encode(String.fromCharCode(rune))) {
        buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
  }
  return buffer.toString();
}

/// Builds `a=1&b=2` from [parameters] with [encodeQueryComponent].
///
/// The leading `?` is NOT included: `Uri(query: ...)` adds it, and a doubled `?`
/// would be read as part of the first parameter's name by the server.
///
/// Entries are emitted in iteration order, so callers pass a `LinkedHashMap` to
/// control the order the way the TypeScript client's `searchParams.set` calls
/// determine it. The endpoint's own query is never inherited: the path is fixed
/// (`/v1/rendezvous`, `/v1/peer`), so the Worker routes on the parameters below
/// and nothing else.
String encodeQuery(Map<String, String> parameters) {
  final StringBuffer buffer = StringBuffer();
  for (final MapEntry<String, String> entry in parameters.entries) {
    if (entry.value.isEmpty) continue;
    if (buffer.isNotEmpty) buffer.write('&');
    buffer.write('${encodeQueryComponent(entry.key)}=${encodeQueryComponent(entry.value)}');
  }
  return buffer.toString();
}
