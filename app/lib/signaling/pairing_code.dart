/// Alphabet and length rules for the human-typed pairing code.
///
/// The alphabet deliberately omits `I`, `O`, `0` and `1`, and contains no
/// lowercase letters at all. A user reads "1" as "l" and "0" as "O" and types
/// the wrong code, which the Worker answers with a bare 400 - so the ambiguity
/// is removed at the source instead of being explained in the UI.
///
/// 13 characters x 32 symbols is 65 bits, which is far more than a guessing
/// attacker can search inside the 15 minute room window.
///
/// Mirrors `createPairingCode` / `normalizePairingCode` in
/// `src/domain/signaling.ts`. The shapes are pinned by `vectors/wire-v1.json`,
/// which both implementations read.
library;

import 'dart:math';

/// The 32 symbols a pairing code may contain.
const String pairingCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Length of a generated pairing code.
const int pairingCodeLength = 13;

/// Longest code either side accepts; longer input is truncated while typing.
const int pairingCodeMaxLength = 16;

/// The Worker's own routing rule, `^[A-HJ-NP-Z2-9]{13,16}$` in
/// `cloudflare/src/index.ts`.
final RegExp pairingCodePattern = RegExp(r'^[A-HJ-NP-Z2-9]{13,16}$');

/// Creates a 65-bit pairing code from [random], or a secure source by default.
String createPairingCode({Random? random}) {
  final Random source = random ?? Random.secure();
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < pairingCodeLength; index++) {
    buffer.write(pairingCodeAlphabet[source.nextInt(pairingCodeAlphabet.length)]);
  }
  return buffer.toString();
}
/// Cleans a typed or pasted code: upper-cases it the way **ECMAScript** does,
/// drops every symbol outside the alphabet (including `I`, `O`, `0`, `1`,
/// separators and punctuation) and truncates to [pairingCodeMaxLength].
///
/// Lowercase letters are folded, not rejected, EXCEPT the ambiguous ones:
/// `i` and `o` become `I` and `O` and are then dropped. See the
/// `normalizePairingCode` cases in `vectors/wire-v1.json`.
///
/// ## Why this does not simply call `toUpperCase()`
///
/// `'ß'.toUpperCase()` is `'SS'` in JavaScript and `'ß'` in Dart. ECMAScript
/// mandates the *full* Unicode case conversion from `SpecialCasing.txt`, where
/// Dart's `String.toUpperCase` applies only the simple one. The difference is
/// invisible for ordinary typing but not for this function: the expanded `'S'`
/// survives the alphabet filter and lands in the code, so this function yields
/// `SFI` for `'ßﬁ'` in the Tauri build. The simple conversion would silently
/// drop those letters instead, and the two builds would then disagree on the
/// same input — the exact drift `vectors/wire-v1.json` exists to prevent.
String normalizePairingCode(String input) {
  final StringBuffer out = StringBuffer();
  for (final int rune in input.runes) {
    for (final int upper in _ecmaScriptUpperCase(rune)) {
      if (_isPairingAlphabet(upper)) out.writeCharCode(upper);
    }
  }
  // `.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, "").slice(0, 16)`
  return out.length <= pairingCodeMaxLength
      ? out.toString()
      : String.fromCharCodes(out.toString().runes.take(pairingCodeMaxLength));
}

/// `^[A-HJ-NP-Z2-9]$` — A-Z without `I` and `O` (they collide with `1` and
/// `0`), plus 2-9.
bool _isPairingAlphabet(int unit) {
  if (unit >= 0x41 && unit <= 0x5a) {
    return unit != 0x49 && unit != 0x4f;
  }
  return unit >= 0x32 && unit <= 0x39;
}

/// The `SpecialCasing.txt` entries whose unconditional expansion contains an
/// ASCII letter. The remaining multi-character entries — U+0390, U+03B0,
/// U+0587 and the Greek ypogegrammeni of U+1F50..U+1F56 — expand to non-ASCII
/// only, and every non-ASCII code point is dropped by [_isPairingAlphabet] in
/// both languages, so listing them would change nothing.
const Map<int, List<int>> _multiCharacterUppercase = <int, List<int>>{
  0x00df: <int>[0x0053, 0x0073], // LATIN SMALL LETTER SHARP S              -> "Ss"
  0x0149: <int>[0x02bc, 0x004e], // LATIN SMALL LETTER N WITH APOSTROPHE     -> "'N"
  0x01f0: <int>[0x004a, 0x030c], // LATIN SMALL LETTER J WITH CARON          -> "J"
  0x1e96: <int>[0x0048, 0x0331], // LATIN SMALL LETTER H WITH LINE BELOW     -> "H"
  0x1e97: <int>[0x0054, 0x0308], // LATIN SMALL LETTER T WITH DIAERESIS      -> "T"
  0x1e98: <int>[0x0057, 0x030a], // LATIN SMALL LETTER W WITH RING ABOVE     -> "W"
  0x1e99: <int>[0x0059, 0x030a], // LATIN SMALL LETTER Y WITH RING ABOVE     -> "Y"
  0x1e9a: <int>[0x0041, 0x02be], // LATIN SMALL LETTER A WITH RIGHT HALF RING -> "A"
  0xfb00: <int>[0x0046, 0x0046], // LATIN SMALL LIGATURE FF                 -> "FF"
  0xfb01: <int>[0x0046, 0x0049], // LATIN SMALL LIGATURE FI                 -> "FI"
  0xfb02: <int>[0x0046, 0x004c], // LATIN SMALL LIGATURE FL                 -> "FL"
  0xfb03: <int>[
    0x0046,
    0x0046,
    0x0049,
  ], // LATIN SMALL LIGATURE FFI -> "FFI"
  0xfb04: <int>[
    0x0046,
    0x0046,
    0x004c,
  ], // LATIN SMALL LIGATURE FFL -> "FFL"
  0xfb05: <int>[0x0053, 0x0054], // LATIN SMALL LIGATURE LONG S T           -> "ST"
  0xfb06: <int>[0x0053, 0x0054], // LATIN SMALL LIGATURE ST                 -> "ST"
};

/// The upper-cased code points of a single code point, matching JavaScript.
Iterable<int> _ecmaScriptUpperCase(int rune) {
  final List<int>? special = _multiCharacterUppercase[rune];
  if (special != null) return special;
  // `String.fromCharCodes`, not `fromCharCode`: the latter takes a 16 bit unit
  // and would truncate a supplementary code point.
  return String.fromCharCodes(<int>[rune]).toUpperCase().runes;
}

/// Whether the Worker would accept this code on `/v1/rendezvous`.
///
/// The Worker uppercases the query value before testing it, so a lowercase but
/// unambiguous code is accepted while a code containing `i`/`o`/`0`/`1` is not.
bool isAcceptedPairingCode(String value) => pairingCodePattern.hasMatch(value.toUpperCase());
