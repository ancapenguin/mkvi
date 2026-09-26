/// WCAG 2.x contrast arithmetic and `color-mix(in srgb)`, ported to the
/// semantics the token file declares.
///
/// `design/tokens.json` says, in `meta.derivation`:
///
/// > Derived roles are produced with color-mix(in srgb) semantics: each 8-bit
/// > channel is interpolated independently and rounded half away from zero.
///
/// A custom accent has to be built the same way the shipped `accentSoft` and
/// `focusRing` roles were built, or a user-picked colour would land in a ramp
/// the contrast gate never validated. So the mixing rule is reproduced here -
/// not as an approximation, but channel for channel - and
/// `app/test/settings/support/token_math_check.dart` measures this
/// implementation against `design/tool/generate_tokens.dart`'s, which is the
/// implementation the generated file was produced by. The two cannot drift.
///
/// The WCAG luminance and ratio formulas are likewise the standard ones, and
/// the same test asserts that the numbers this file produces match the token
/// tool's for every colour in the token file.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

/// `true` for `#RRGGBB` and `#RRGGBBAA`, the two forms tokens.json uses.
final RegExp _hexPattern = RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

/// Parses `#RRGGBB` / `#RRGGBBAA`, or returns null.
///
/// A leading or trailing space is tolerated: the value comes from a JSON file
/// a human edits.
Color? tryParseHexColor(String? value) {
  if (value == null) return null;
  final String text = value.trim();
  if (!_hexPattern.hasMatch(text)) return null;
  final String digits = text.substring(1);
  int byte(int index) =>
      int.parse(digits.substring(index, index + 2), radix: 16);
  if (digits.length == 6) {
    return Color.fromARGB(0xff, byte(0), byte(2), byte(4));
  }
  return Color.fromARGB(byte(6), byte(0), byte(2), byte(4));
}

/// The canonical `#RRGGBB` (or `#RRGGBBAA` when translucent) form of [color].
///
/// Used by the JSON codec, so a stored custom accent round-trips to the same
/// text the user typed rather than to a float-formatted value.
String hexOf(Color color) {
  final int argb = color.toARGB32();
  final String base =
      '${_hex2((argb >> 16) & 0xff)}${_hex2((argb >> 8) & 0xff)}${_hex2(argb & 0xff)}';
  final int alpha = (argb >> 24) & 0xff;
  return alpha == 0xff ? '#$base' : '#$base${_hex2(alpha)}';
}

String _hex2(int value) => value.toRadixString(16).padLeft(2, '0');

/// WCAG 2.x relative luminance of [color], 0 (black) to 1 (white).
double relativeLuminance(Color color) {
  final int argb = color.toARGB32();
  return 0.2126 * _linear((argb >> 16) & 0xff) +
      0.7152 * _linear((argb >> 8) & 0xff) +
      0.0722 * _linear(argb & 0xff);
}

double _linear(int channel) {
  final double c = channel / 255.0;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 2.x contrast ratio between [a] and [b]. Order independent, 1 to 21.
double contrastRatio(Color a, Color b) {
  final double la = relativeLuminance(a);
  final double lb = relativeLuminance(b);
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Whether [foreground] on [background] reaches [minimum].
bool clearsContrast(Color foreground, Color background, double minimum) =>
    contrastRatio(foreground, background) >= minimum;

/// The ratio rendered the way the settings screen shows it: `4.53:1`.
String contrastLabel(Color foreground, Color background) {
  final String text = contrastRatio(foreground, background).toStringAsFixed(2);
  return '$text:1';
}

/// `color-mix(in srgb, from, amount, to)`: every 8-bit channel of [from] is
/// moved [amount] of the way to [to] and rounded half away from zero.
Color mixColor(Color from, Color to, double amount) {
  final int fromArgb = from.toARGB32();
  final int toArgb = to.toARGB32();
  return Color.fromARGB(
    _mixChannel((fromArgb >> 24) & 0xff, (toArgb >> 24) & 0xff, amount),
    _mixChannel((fromArgb >> 16) & 0xff, (toArgb >> 16) & 0xff, amount),
    _mixChannel((fromArgb >> 8) & 0xff, (toArgb >> 8) & 0xff, amount),
    _mixChannel(fromArgb & 0xff, toArgb & 0xff, amount),
  );
}

int _mixChannel(int from, int to, double amount) {
  final double value = from + (to - from) * amount;
  final double floor = value.floorToDouble();
  final int rounded = (floor + (value - floor >= 0.5 ? 1 : 0))
      .clamp(0, 255)
      .toInt();
  return rounded;
}
