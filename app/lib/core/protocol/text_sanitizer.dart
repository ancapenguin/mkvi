/// Text sanitisers, ported one-for-one from `src/services/peer-transport.ts`.
///
/// Every function here is pure, allocation-only and has no dependency on the
/// transport, which is what makes the whole protocol layer testable without a
/// data channel, a renderer or a disk.
///
/// ## Two deliberate deviations from the TypeScript original
///
/// 1. **Truncation is by code point, not by UTF-16 code unit.** The original
///    ends with `.slice(0, 40)`, which cuts JavaScript strings at UTF-16 code
///    unit boundaries and can therefore split a surrogate pair (a broken
///    emoji) in half. Dart strings are also UTF-16, but `String.runes` iterates
///    by code point, and every cut here is made on runes. For ASCII — which is
///    all the ported test-suite asserts — the two are byte-identical.
/// 2. **A display name is cut on a grapheme-cluster boundary.** Rune truncation
///    alone would still leave `"I"` + U+0307 (Turkish dotted capital I) or an
///    emoji ZWJ sequence dangling at the cap, which renders as a broken glyph.
///    See [_isGraphemeExtender].
library;

import 'dart:convert';

import 'peer_protocol.dart';

/// UTF-8 length of [value], which is what the 32 KB control cap is measured in.
///
/// `utf8.encode` never throws on this SDK: an unpaired surrogate is encoded as
/// the three bytes of U+FFFD, so a hostile or damaged string is measured rather
/// than crashing the receive loop. The count is therefore the number of bytes
/// that would actually go on the wire.
int utf8ByteLength(String value) => utf8.encode(value).length;

/// Strips control characters, zero-width/bidi marks and the BOM from a name that
/// a peer chose for itself, collapses whitespace, and caps the result.
///
/// TS: `safeDisplayName`.
String safeDisplayName(String value) {
  // `map(invisible -> " ")` followed by `/\s+/ -> " "` of the TypeScript
  // original, fused into one pass: both steps only ever turn a run of
  // invisible-or-space characters into a single space.
  final StringBuffer out = StringBuffer();
  bool pendingSpace = false;
  for (final int rune in value.runes) {
    if (_isInvisible(rune) || _isEcmaWhitespace(rune)) {
      if (!pendingSpace) {
        out.write(' ');
        pendingSpace = true;
      }
    } else {
      out.writeCharCode(rune);
      pendingSpace = false;
    }
  }
  // `.trim().slice(0, 40).trim()`
  return _ecmaTrim(
    _truncateOnGrapheme(
      _ecmaTrim(out.toString()),
      PeerProtocol.maxDisplayNameLength,
    ),
  );
}

/// Reduces a peer-supplied file name to something that cannot escape a download
/// directory, falling back to a Turkish placeholder when nothing is left.
///
/// TS: `safeName`. Note that the TypeScript character class omits U+007F, so this
/// port does not strip DEL either; the cap is also by code point here.
String safeName(String value) {
  final StringBuffer out = StringBuffer();
  for (final int rune in value.runes) {
    out.writeCharCode(_isUnsafeForFileName(rune) ? 0x5f : rune);
  }
  final String trimmed = _ecmaTrim(out.toString());
  // `... || "dosya"`: only an *empty* result falls back, not a blank one.
  final String cut = _truncateRunes(trimmed, PeerProtocol.maxFileNameLength);
  return cut.isEmpty ? PeerProtocol.defaultFileName : cut;
}

/// Keeps a conventional media type, otherwise declares opaque bytes.
///
/// TS: `safeMime`, whose regular expression is
/// `/^[a-zA-Z0-9][a-zA-Z0-9!#$&^_.+-]*\/[a-zA-Z0-9][a-zA-Z0-9!#$&^_.+-]*$/`.
/// The original validates the whole string first and only then slices to 128
/// characters, and that order is preserved here.
String safeMime(String value) {
  if (!_isMediaType(value)) return PeerProtocol.defaultMimeType;
  return _truncateRunes(value, PeerProtocol.maxMimeLength);
}

/// Flattens the free-text `reason` a peer attaches to a decline or a cancel.
///
/// TS: the private `safeReason`, which 0.1.x reaches through `parseControl` for
/// `call-decline` and through `declineCall` for outgoing frames. This port also
/// applies it to `file-decline` and `file-cancel`, which 0.1.x only sliced; see
/// `control_parser.dart` for why.
String safeReason(String value) {
  final StringBuffer out = StringBuffer();
  bool pendingSpace = false;
  for (final int rune in value.runes) {
    if (rune <= 0x1f || rune == 0x7f || _isEcmaWhitespace(rune)) {
      if (!pendingSpace) {
        out.write(' ');
        pendingSpace = true;
      }
    } else {
      out.writeCharCode(rune);
      pendingSpace = false;
    }
  }
  return _truncateRunes(
    _ecmaTrim(out.toString()),
    PeerProtocol.maxReasonLength,
  );
}

// ---------------------------------------------------------------------------
// Truncation
// ---------------------------------------------------------------------------

/// Cuts [value] to [limit] code points without ever splitting one.
///
/// Difference from the TypeScript original, which uses `.slice(0, 40)` on a
/// UTF-16 string: this cannot cut a surrogate pair, and [_truncateOnGrapheme]
/// additionally cannot cut a combining sequence.
String _truncateRunes(String value, int limit) =>
    sliceToCodePoints(value, limit);

/// Cuts [value] to [limit] code points without ever splitting one.
///
/// This is the port of the original's `.slice(0, n)`. Dart strings are UTF-16
/// like JavaScript strings, but slicing them at a code-unit boundary can cut a
/// surrogate pair in half, so the port slices code points instead. For ASCII —
/// which is everything the ported test-suite asserts — the result is identical.
String sliceToCodePoints(String value, int limit) {
  if (value.length <= limit) return value; // fast path: length == rune count
  return String.fromCharCodes(value.runes.take(limit));
}

/// Cuts [value] to at most [limit] code points, backing off while the cut would
/// either leave a dangling mark at the end or cut a cluster in the middle.
///
/// A full UAX #29 grapheme segmenter needs a Unicode property table far larger
/// than this file can justify, so [_isGraphemeExtender] implements the
/// "extend / spacing mark / joiner" part of the rule over the ranges that
/// actually occur in a 40 character display name. Being over-eager here only
/// shortens the name by one more character; being too lax would show a broken
/// glyph, so the table errs towards inclusion.
///
/// The two directions matter equally. Backing off only when the *last kept* code
/// point is a mark leaves the far more common bug in place: a base character that
/// is kept while its own combining mark is the first code point cut off, which is
/// exactly what truncating "39 letters then I + COMBINING DOT" at 40 would do.
String _truncateOnGrapheme(String value, int limit) {
  final List<int> runes = value.runes.toList(growable: false);
  if (runes.length <= limit) return value;
  int end = limit;
  bool backedOff = true;
  while (end > 0 && backedOff) {
    backedOff = false;
    // The first cut code point extends the last kept one, so the base goes too.
    if (end < runes.length && _isGraphemeExtender(runes[end])) {
      end -= 1;
      backedOff = true;
      continue;
    }
    // The last kept code point has nothing to attach to, so it goes too.
    if (_isGraphemeExtender(runes[end - 1])) {
      end -= 1;
      backedOff = true;
    }
  }
  // A kept regional indicator whose partner was cut off would render as a bare
  // letter box instead of a flag, so it has to go as well.
  if (end > 0 &&
      end < runes.length &&
      _isRegionalIndicator(runes[end - 1]) &&
      _isRegionalIndicator(runes[end])) {
    end -= 1;
  }
  return String.fromCharCodes(runes.take(end));
}

/// Whether [rune] is a grapheme "extend" or joiner code point: it only has
/// meaning next to another code point, and it can never be the last character of
/// a grapheme cluster.
bool _isGraphemeExtender(int rune) {
  if (rune >= 0x0300 && rune <= 0x036f) return true; // combining diacritics
  if (rune >= 0x0483 && rune <= 0x0489) return true; // Cyrillic
  if (rune >= 0x0591 && rune <= 0x05bd) return true; // Hebrew
  if (rune >= 0x05bf && rune <= 0x05c7) return true;
  if (rune >= 0x0610 && rune <= 0x065f) return true; // Arabic
  if (rune == 0x0670 || (rune >= 0x06d6 && rune <= 0x06ed)) return true;
  if (rune >= 0x0711 && rune <= 0x073f) return true; // Syriac, Thaana
  if (rune >= 0x07a6 && rune <= 0x07b0) return true;
  if (rune >= 0x07eb && rune <= 0x07f3) return true;
  if (rune >= 0x0816 && rune <= 0x082d) return true;
  if (rune >= 0x0900 && rune <= 0x0903) return true; // Devanagari
  if (rune >= 0x093a && rune <= 0x094f) return true;
  if (rune >= 0x0951 && rune <= 0x0957) return true;
  if (rune >= 0x0962 && rune <= 0x0963) return true;
  if (rune == 0x0e31 || (rune >= 0x0e34 && rune <= 0x0e3a)) return true; // Thai
  if (rune >= 0x0e47 && rune <= 0x0e4e) return true;
  if (rune >= 0x1ab0 && rune <= 0x1aff) return true; // supplemental diacritics
  if (rune >= 0x1dc0 && rune <= 0x1dff) return true;
  if (rune == 0x200d) return true; // zero-width joiner
  if (rune >= 0x20d0 && rune <= 0x20f0) return true; // marks for symbols
  if (rune == 0x20e3) return true; // enclosing keycap
  if (rune >= 0xfe00 && rune <= 0xfe0f) return true; // variation selectors
  if (rune >= 0xfe20 && rune <= 0xfe2f) return true; // combining half marks
  if (rune >= 0x1f3fb && rune <= 0x1f3ff) return true; // emoji skin tones
  if (rune >= 0xe0020 && rune <= 0xe007f) return true; // emoji tag sequences
  if (rune >= 0xe0100 && rune <= 0xe01ef) return true; // variation selectors
  return false;
}

bool _isRegionalIndicator(int rune) => rune >= 0x1f1e6 && rune <= 0x1f1ff;

// ---------------------------------------------------------------------------
// Character classes
// ---------------------------------------------------------------------------

/// The TypeScript `invisible` predicate of `safeDisplayName`, plus one addition.
///
/// Unpaired surrogates (U+D800..U+DFFF) are *kept* by the original, because
/// JavaScript strings can hold them and `JSON.stringify` escapes them. A Dart
/// string holds them too, but such a string cannot be encoded by strict UTF-8
/// consumers and renders as tofu, so they collapse to a space here. A *valid*
/// surrogate pair is reported by `String.runes` as the single code point above
/// U+FFFF, so emoji are never affected by this.
bool _isInvisible(int rune) {
  if (rune < 0x20 || rune == 0x7f) return true;
  if (rune >= 0xd800 && rune <= 0xdfff) return true; // unpaired surrogate
  if (rune >= 0x200b && rune <= 0x200f) {
    return true; // zero-width and bidi marks
  }
  if (rune >= 0x202a && rune <= 0x202e) return true; // bidi embedding
  if (rune >= 0x2066 && rune <= 0x2069) return true; // bidi isolates
  if (rune == 0xfeff) return true; // BOM / zero-width no-break space
  return false;
}

/// `/[\\/:*?"<>|\u0000-\u001f]/`, the character class of `safeName`.
bool _isUnsafeForFileName(int rune) {
  if (rune <= 0x1f) return true; // NUL through US, the `\u0000-\u001f` range
  return rune == 0x2f || // /
      rune == 0x5c || // backslash
      rune == 0x3a || // :
      rune == 0x2a || // *
      rune == 0x3f || // ?
      rune == 0x22 || // "
      rune == 0x3c || // <
      rune == 0x3e || // >
      rune == 0x7c; // |
}

/// ECMAScript's `WhiteSpace` union `LineTerminator`, i.e. exactly what
/// JavaScript's `\s`, `String.prototype.trim` and `String.prototype.slice` agree
/// on. `dart:core`'s own `String.trim` uses the Unicode `White_Space` property
/// instead, which differs in both directions (it misses U+FEFF, it adds
/// U+0085), so the port implements the ECMAScript set explicitly rather than
/// inheriting a subtly different one.
bool _isEcmaWhitespace(int rune) {
  if (rune >= 0x0009 && rune <= 0x000d) return true; // tab, LF, VT, FF, CR
  if (rune == 0x0020) return true; // space
  if (rune == 0x00a0) return true; // no-break space
  if (rune == 0x1680) return true; // ogham space mark
  if (rune >= 0x2000 && rune <= 0x200a) {
    return true; // en/em quad ... hair space
  }
  if (rune == 0x2028 || rune == 0x2029) return true; // line/paragraph separator
  if (rune == 0x202f) return true; // narrow no-break space
  if (rune == 0x205f) return true; // medium mathematical space
  if (rune == 0x3000) return true; // ideographic space
  if (rune == 0xfeff) return true; // BOM counts as whitespace in ECMAScript
  return false;
}

String _ecmaTrim(String value) {
  final List<int> runes = value.runes.toList(growable: false);
  int start = 0;
  int end = runes.length;
  while (start < end && _isEcmaWhitespace(runes[start])) {
    start += 1;
  }
  while (end > start && _isEcmaWhitespace(runes[end - 1])) {
    end -= 1;
  }
  if (start == 0 && end == runes.length) return value;
  return String.fromCharCodes(runes.sublist(start, end));
}

// ---------------------------------------------------------------------------
// Media types
// ---------------------------------------------------------------------------

/// Hand-rolled equivalent of the `safeMime` regular expression.
///
/// It is a scanner rather than a `RegExp` on purpose: the pattern is pure ASCII
/// and a scanner cannot be surprised by `$` anchoring, by a platform regex
/// engine, or by a `RegExp` that happens to be case-insensitive by default.
bool _isMediaType(String value) {
  final int slash = value.indexOf('/');
  if (slash <= 0 || slash != value.lastIndexOf('/')) return false;
  return _isMediaToken(value.substring(0, slash)) &&
      _isMediaToken(value.substring(slash + 1));
}

bool _isMediaToken(String token) {
  if (token.isEmpty) return false;
  if (!_isAsciiAlphaNumeric(token.codeUnitAt(0))) return false;
  for (int i = 1; i < token.length; i += 1) {
    final int unit = token.codeUnitAt(i);
    if (!_isAsciiAlphaNumeric(unit) && !_isMediaTypeExtra(unit)) return false;
  }
  return true;
}

bool _isAsciiAlphaNumeric(int unit) =>
    (unit >= 0x30 && unit <= 0x39) ||
    (unit >= 0x41 && unit <= 0x5a) ||
    (unit >= 0x61 && unit <= 0x7a);

/// The `[!#$&^_.+-]` continuation class of the `safeMime` pattern.
bool _isMediaTypeExtra(int unit) =>
    unit == 0x21 || // !
    unit == 0x23 || // #
    unit == 0x24 || // $
    unit == 0x26 || // &
    unit == 0x5e || // ^
    unit == 0x5f || // _
    unit == 0x2e || // .
    unit == 0x2b || // +
    unit == 0x2d; // -
