// Generator for the mkvi design tokens.
//
//   dart run tool/generate_tokens.dart                 # -> lib/generated/tokens.g.dart
//   dart run tool/generate_tokens.dart --out <path>    # -> <path>
//   dart run tool/generate_tokens.dart --report        # print the contrast table
//   dart run tool/generate_tokens.dart --check         # fail if the output is stale
//
// It reads tokens.json and emits an immutable `MkviTokens` ThemeExtension plus
// the MkviTypeScale / MkviSpacing / MkviRadii / MkviControl / MkviMotion
// scales. Output is byte-for-byte deterministic: every collection is walked in
// a declared order, there are no timestamps and no map-iteration order in the
// output, and lines are always LF.
//
// The output lands in `lib/` ON PURPOSE: the package is a real Dart library
// (`design/lib/mkvi_design.dart` re-exports the generated file), so `app` can
// take it as a path dependency and reach the tokens as
// `package:mkvi_design/mkvi_design.dart` without copying anything. A generated
// file outside `lib/` would be unreachable from any other package, which is
// exactly the defect that left the token implementation in the test tree.
//
// The emitted file is therefore not only the colours. It also carries the
// VALUES A CONSUMER CANNOT DERIVE FROM A COLOUR: the `contrast` list, each
// theme's polarity, and each theme's `derive` amounts. A consumer that had to
// re-read tokens.json for those had a `dart:io` file read on a production code
// path, where a packaged app has no tokens.json at all. What the file declares
// is emitted; what would be invented is not.
//
// The script is also the single implementation of token resolution: the
// contrast test imports this file so the gate can never measure something
// different from what was generated.
//
// It fails loudly (exit code 2, one problem per line) when a theme is missing a
// role, when a role set differs between themes, when an unknown role is
// referenced, when a derived role disagrees with the value cached in the theme
// it was derived from, or when a value the generated file has to export per
// theme is missing or has the wrong type.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// A token file problem. Carries every problem found, not just the first.
class TokenError implements Exception {
  TokenError(this.problems);

  final List<String> problems;

  @override
  String toString() => problems.join('\n');
}

// ---------------------------------------------------------------------------
// Colour helpers
// ---------------------------------------------------------------------------

/// An 8-bit sRGB colour with an alpha channel.
class Rgb {
  const Rgb(this.r, this.g, this.b, [this.a = 255]);

  final int r;
  final int g;
  final int b;
  final int a;

  bool get isOpaque => a == 255;

  /// WCAG 2.x relative luminance.
  double get luminance =>
      0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b);

  static double _linear(int channel) {
    final c = channel / 255.0;
    return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  /// WCAG 2.x contrast ratio against [other]. Order independent.
  double contrastWith(Rgb other) {
    final a = luminance;
    final b = other.luminance;
    final lighter = math.max(a, b);
    final darker = math.min(a, b);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// `color-mix(in srgb)` semantics: interpolate each 8-bit channel
  /// independently and round half away from zero.
  static Rgb mix(Rgb from, Rgb to, double amount) {
    assert(amount >= 0.0 && amount <= 1.0, 'mix amount out of range: $amount');
    return Rgb(
      _lerpChannel(from.r, to.r, amount),
      _lerpChannel(from.g, to.g, amount),
      _lerpChannel(from.b, to.b, amount),
      _lerpChannel(from.a, to.a, amount),
    );
  }

  static int _lerpChannel(int from, int to, double amount) {
    final value = from + (to - from) * amount;
    final floor = value.floorToDouble();
    return (floor + (value - floor >= 0.5 ? 1 : 0)).clamp(0, 255).toInt();
  }

  /// `#RRGGBB`, or `#RRGGBBAA` when translucent.
  String toHex() {
    final base = _hex2(r) + _hex2(g) + _hex2(b);
    return isOpaque ? '#$base' : '#$base${_hex2(a)}';
  }

  /// `0xFFRRGGBB` / `0xAARRGGBB`, the literal form used in generated Dart.
  String toDartLiteral() => '0x${_hex2(a)}${_hex2(r)}${_hex2(g)}${_hex2(b)}';

  static String _hex2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

  @override
  bool operator ==(Object other) =>
      other is Rgb && other.r == r && other.g == g && other.b == b && other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => toHex();
}

final _hexPattern = RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

Rgb? tryParseColor(String? value) {
  if (value == null) return null;
  final text = value.trim();
  if (!_hexPattern.hasMatch(text)) return null;
  final digits = text.substring(1);
  int at(int index) => int.parse(digits.substring(index, index + 2), radix: 16);
  if (digits.length == 6) return Rgb(at(0), at(2), at(4));
  return Rgb(at(0), at(2), at(4), at(6));
}

// ---------------------------------------------------------------------------
// Token model
// ---------------------------------------------------------------------------

class ContrastPair {
  const ContrastPair(this.fg, this.bg, this.min);

  final String fg;
  final String bg;
  final double min;

  String get label => '$fg on $bg';
}

class ControlSize {
  const ControlSize({
    required this.name,
    required this.height,
    required this.paddingX,
    required this.gap,
    required this.fontSize,
    required this.iconSize,
    required this.radius,
  });

  final String name;
  final double height;
  final double paddingX;
  final double gap;
  final double fontSize;
  final double iconSize;
  final String radius;
}

/// A parsed and validated `tokens.json`.
class TokenSpec {
  TokenSpec._(this._json);

  final Map<String, dynamic> _json;

  factory TokenSpec.parse(String source, {String origin = 'tokens.json'}) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw TokenError(['$origin is not valid JSON: ${error.message}']);
    }
    if (decoded is! Map<String, dynamic>) {
      throw TokenError(['$origin must contain a JSON object at the top level.']);
    }
    final spec = TokenSpec._(decoded);
    spec.validate(origin);
    return spec;
  }

  // --- raw section accessors -----------------------------------------------

  Map<String, dynamic> get meta => _map(_json, 'meta');
  Map<String, dynamic> get themes => _map(_json, 'themes');
  Map<String, dynamic> get accents => _map(_json, 'accents');
  Map<String, dynamic> get type => _map(_json, 'type');
  Map<String, dynamic> get space => _map(_json, 'space');
  Map<String, dynamic> get radius => _map(_json, 'radius');
  Map<String, dynamic> get control => _map(_json, 'control');
  Map<String, dynamic> get motion => _map(_json, 'motion');

  List<String> get roles =>
      (meta['roles'] as List<dynamic>? ?? const []).cast<String>();

  Map<String, dynamic> get sources => _map(meta, 'sources');
  Map<String, dynamic> get roleNotes => _map(meta, 'roleNotes');

  String get name => meta['name'] as String? ?? 'unnamed-tokens';
  String get version => meta['version'] as String? ?? '0.0.0';
  String get defaultTheme => meta['defaultTheme'] as String? ?? '';
  String get defaultAccent => meta['defaultAccent'] as String? ?? '';

  /// Theme ids in declaration order (stable: JSON object order is preserved by
  /// `jsonDecode` into a LinkedHashMap).
  List<String> get themeIds => themes.keys.toList(growable: false);
  List<String> get accentIds => accents.keys.toList(growable: false);

  /// Role names in declaration order.
  List<ContrastPair> get contrastList {
    final raw = _json['contrast'] as List<dynamic>? ?? const [];
    return raw.map((entry) {
      final map = entry as Map<String, dynamic>;
      return ContrastPair(map['fg'] as String, map['bg'] as String, (map['min'] as num).toDouble());
    }).toList(growable: false);
  }

  /// Colours a theme stores directly, i.e. everything except its `derive` block
  /// and its non-colour metadata.
  Map<String, dynamic> themeRoles(String themeId) {
    final theme = themes[themeId] as Map<String, dynamic>;
    return {
      for (final entry in theme.entries)
        if (entry.key != 'derive' &&
            entry.key != 'labelTr' &&
            entry.key != 'polarity')
          entry.key: entry.value,
    };
  }

  Map<String, dynamic> themeDerive(String themeId) =>
      _map(themes[themeId] as Map<String, dynamic>, 'derive');

  /// `themes.<id>.polarity`. Only `dark` and `light` are accepted, because the
  /// generated file turns it into a boolean and a third spelling would be
  /// silently treated as light.
  String themePolarity(String themeId) =>
      (themes[themeId] as Map<String, dynamic>)['polarity'] as String? ?? '';

  /// `themes.<id>.polarity == 'dark'`.
  bool isDarkTheme(String themeId) => themePolarity(themeId) == 'dark';

  /// `themes.<id>.derive.focusRingTarget` as a literal colour.
  ///
  /// It has to be a literal: a custom accent's focus ring is mixed towards this
  /// colour, so a value that depended on the accent would not be one colour at
  /// all and could not be exported per theme.
  Rgb themeFocusRingTarget(String themeId) {
    final value = themeDerive(themeId)['focusRingTarget'];
    final parsed = tryParseColor(value as String?);
    if (parsed == null) {
      throw TokenError([
        'Theme "$themeId" derive["focusRingTarget"] is $value. It must be a '
            'literal #RRGGBB or #RRGGBBAA colour, because the generated tokens '
            'export one focus ring target per theme.',
      ]);
    }
    return parsed;
  }

  /// `themes.<id>.derive.<key>` as a `color-mix` amount in 0.0..1.0.
  double themeMix(String themeId, String key) {
    final value = themeDerive(themeId)[key];
    if (value is! num || value.toDouble() < 0.0 || value.toDouble() > 1.0) {
      throw TokenError([
        'Theme "$themeId" derive["$key"] is $value. It must be a number within '
            '0.0..1.0, because the generated tokens export it as a mix amount.',
      ]);
    }
    return value.toDouble();
  }

  String themeLabel(String themeId) =>
      (themes[themeId] as Map<String, dynamic>)['labelTr'] as String? ?? themeId;

  String accentLabel(String accentId) =>
      (accents[accentId] as Map<String, dynamic>)['labelTr'] as String? ?? accentId;

  // --- validation -----------------------------------------------------------

  void validate(String origin) {
    final problems = <String>[];

    if (!_json.containsKey('meta')) problems.add('Missing top-level section "meta".');
    if (!_json.containsKey('themes')) problems.add('Missing top-level section "themes".');
    if (!_json.containsKey('accents')) problems.add('Missing top-level section "accents".');
    if (problems.isNotEmpty) throw TokenError(['$origin:', ...problems]);

    if (roles.isEmpty) {
      throw TokenError(['$origin: meta.roles must list every colour role.']);
    }
    if (roles.toSet().length != roles.length) {
      final seen = <String>{};
      final dupes = roles.where((role) => !seen.add(role)).toSet().toList()..sort();
      throw TokenError(['$origin: meta.roles contains duplicates: ${dupes.join(', ')}']);
    }
    if (themeIds.isEmpty) problems.add('No themes defined.');
    if (accentIds.isEmpty) problems.add('No accents defined.');

    // 1. Every theme defines exactly the same role set: no missing, no extra.
    //    This is the check whose absence let forest/plum fall back to midnight.
    for (final themeId in themeIds) {
      final defined = themeRoles(themeId).keys.toSet();
      final missing = roles.where((role) => !defined.contains(role)).toList()..sort();
      final extra = defined.where((role) => !roles.contains(role)).toList()..sort();
      if (missing.isNotEmpty) {
        problems.add('Theme "$themeId" is missing ${missing.length} role(s): ${missing.join(', ')}');
      }
      if (extra.isNotEmpty) {
        problems.add('Theme "$themeId" defines unknown role(s): ${extra.join(', ')}');
      }
    }

    // 2. Every role value parses as a colour.
    for (final themeId in themeIds) {
      for (final role in roles) {
        final value = (themes[themeId] as Map<String, dynamic>)[role];
        if (value == null) continue;
        if (tryParseColor(value as String?) == null) {
          problems.add('Theme "$themeId" role "$role" is not a #RRGGBB or #RRGGBBAA colour: $value');
        }
      }
    }

    // 3. Accent records are complete.
    final accentKeys = <String>{};
    for (final accentId in accentIds) {
      final accent = accents[accentId] as Map<String, dynamic>;
      for (final key in accent.keys) {
        if (key == 'labelTr') continue;
        accentKeys.add(key);
        if (tryParseColor(accent[key] as String?) == null) {
          problems.add('Accent "$accentId" key "$key" is not a #RRGGBB or #RRGGBBAA colour: ${accent[key]}');
        }
      }
    }

    // 4. Role sources point at things that exist.
    for (final entry in sources.entries) {
      final role = entry.key;
      if (!roles.contains(role)) {
        problems.add('meta.sources references unknown role "$role".');
        continue;
      }
      final source = entry.value as Map<String, dynamic>;
      switch (source['kind']) {
        case 'accentKey':
          final key = source['key'] as String?;
          if (key == null) {
            problems.add('meta.sources["$role"] is missing "key".');
          } else if (!accentKeys.contains(key)) {
            problems.add('meta.sources["$role"] points at accent key "$key", which no accent defines.');
          }
        case 'derived':
          _validateOperand(problems, role, 'seed', source['seed'] as Map<String, dynamic>?);
          _validateOperand(problems, role, 'target', source['target'] as Map<String, dynamic>?);
          _validateOperand(problems, role, 'amount', source['amount'] as Map<String, dynamic>?);
        default:
          problems.add('meta.sources["$role"] has unknown kind "${source['kind']}".');
      }
    }

    // 5. The contrast list may only reference declared roles, and no pair may
    //    be listed twice.
    final seenPairs = <String, int>{};
    var pairIndex = 0;
    for (final entry in _json['contrast'] as List<dynamic>? ?? const <dynamic>[]) {
      pairIndex++;
      if (entry is! Map<String, dynamic>) {
        problems.add('contrast[$pairIndex] is not an object.');
        continue;
      }
      for (final key in ['fg', 'bg']) {
        final role = entry[key] as String?;
        if (role == null) {
          problems.add('contrast[$pairIndex] is missing "$key".');
        } else if (!roles.contains(role)) {
          problems.add('contrast[$pairIndex] references unknown $key role "$role".');
        }
      }
      final min = entry['min'];
      if (min is! num || min <= 0) {
        problems.add('contrast[$pairIndex] needs a positive "min".');
      }
      final label = '${entry['fg']} on ${entry['bg']}';
      final previous = seenPairs[label];
      if (previous != null) {
        problems.add('contrast[$pairIndex] duplicates contrast[$previous] ($label).');
      } else {
        seenPairs[label] = pairIndex;
      }
    }
    if ((_json['contrast'] as List<dynamic>? ?? const []).isEmpty) {
      problems.add('The contrast list is empty; the gate would validate nothing.');
    }

    // 6. Default pointers exist.
    if (defaultTheme.isEmpty || !themes.containsKey(defaultTheme)) {
      problems.add('meta.defaultTheme "$defaultTheme" is not a defined theme.');
    }
    if (defaultAccent.isEmpty || !accents.containsKey(defaultAccent)) {
      problems.add('meta.defaultAccent "$defaultAccent" is not a defined accent.');
    }

    // 7. Accent-sourced and derived roles cached in a theme must equal the
    //    value the resolution rules produce for the default accent. A stale
    //    cache is a silent-fallback bug waiting to happen.
    if (defaultTheme.isNotEmpty && defaultAccent.isNotEmpty && themes.containsKey(defaultTheme)) {
      for (final role in roles) {
        final source = sources[role];
        if (source == null) continue;
        for (final themeId in themeIds) {
          final actual = tryParseColor((themes[themeId] as Map<String, dynamic>)[role] as String?);
          if (actual == null) continue;
          Rgb expected;
          try {
            expected = resolveColor(themeId, defaultAccent, role);
          } on TokenError {
            continue;
          }
          if (actual != expected) {
            problems.add(
              'Theme "$themeId" caches "$role" as ${actual.toHex()}, but '
              'resolving it from its own derive parameters with the default '
              'accent "$defaultAccent" produces ${expected.toHex()}. Update the '
              'cached value.',
            );
          }
        }
      }
    }

    _validateScales(problems);
    _validateThemeMetadata(problems);

    if (problems.isNotEmpty) {
      throw TokenError(['$origin: ${problems.length} problem(s) found.', ...problems]);
    }
  }

  void _validateOperand(List<String> problems, String role, String slot, Map<String, dynamic>? operand) {
    if (operand == null) {
      problems.add('meta.sources["$role"] is missing "$slot".');
      return;
    }
    switch (operand['kind']) {
      case 'accentRole':
        final ref = operand['role'] as String?;
        if (ref == null || !roles.contains(ref)) {
          problems.add('meta.sources["$role"].$slot references unknown role "${operand['role']}".');
        }
      case 'themeRole':
        final ref = operand['role'] as String?;
        if (ref == null || !roles.contains(ref)) {
          problems.add('meta.sources["$role"].$slot references unknown role "${operand['role']}".');
        }
      case 'themeKey':
        final key = operand['key'] as String?;
        if (key == null) {
          problems.add('meta.sources["$role"].$slot is missing "key".');
        } else {
          for (final themeId in themeIds) {
            if (!themeDerive(themeId).containsKey(key)) {
              problems.add('Theme "$themeId" derive block is missing "$key", required by role "$role".');
            }
          }
        }
      default:
        problems.add('meta.sources["$role"].$slot has unknown kind "${operand['kind']}".');
    }
  }

  /// The per-theme values the generated file exports verbatim, because a
  /// consumer cannot derive them from a colour: the polarity, and the three
  /// `derive` amounts a CUSTOM accent is built with.
  ///
  /// They are checked here rather than while emitting, so a broken value is a
  /// token error with a message naming the theme - not a generator crash on a
  /// file somebody else has to debug.
  void _validateThemeMetadata(List<String> problems) {
    for (final themeId in themeIds) {
      final polarity = themePolarity(themeId);
      if (polarity != 'dark' && polarity != 'light') {
        problems.add(
          'Theme "$themeId" polarity is "$polarity"; it must be "dark" or '
          '"light".',
        );
      }
      final derive = themeDerive(themeId);
      final target = derive['focusRingTarget'];
      if (tryParseColor(target as String?) == null) {
        problems.add(
          'Theme "$themeId" derive["focusRingTarget"] is $target. It must be a '
          'literal #RRGGBB or #RRGGBBAA colour: a custom accent mixes towards '
          'it, so it cannot depend on the accent.',
        );
      }
      for (final key in const ['focusRingMix', 'accentSoftMix']) {
        final value = derive[key];
        if (value is! num || value.toDouble() < 0.0 || value.toDouble() > 1.0) {
          problems.add(
            'Theme "$themeId" derive["$key"] is $value. It must be a number '
            'within 0.0..1.0, i.e. a color-mix amount.',
          );
        }
      }
      // Any other derive key is still emitted, so a key with neither type is a
      // broken token file rather than a value silently dropped on the floor.
      for (final entry in derive.entries) {
        if (const ['focusRingTarget', 'focusRingMix', 'accentSoftMix']
            .contains(entry.key)) {
          continue;
        }
        final isColour = tryParseColor(entry.value as String?) != null;
        final isAmount = entry.value is num &&
            entry.value.toDouble() >= 0.0 &&
            entry.value.toDouble() <= 1.0;
        if (!isColour && !isAmount) {
          problems.add(
            'Theme "$themeId" derive["${entry.key}"] is ${entry.value}. A '
            'derive key must be a #RRGGBB colour or a number within 0.0..1.0.',
          );
        }
      }
    }
  }

  void _validateScales(List<String> problems) {
    final lineHeights = _map(type, 'lineHeights');
    final weights = _map(type, 'weights');
    for (final entry in (type['steps'] as Map<String, dynamic>? ?? const {}).entries) {
      final step = entry.value as Map<String, dynamic>;
      final height = step['lineHeight'] as String?;
      if (height == null || !lineHeights.containsKey(height)) {
        problems.add('type.steps["${entry.key}"].lineHeight "${step['lineHeight']}" is not a declared line height.');
      }
      final weight = step['weight'] as String?;
      if (weight == null || !weights.containsKey(weight)) {
        problems.add('type.steps["${entry.key}"].weight "${step['weight']}" is not a declared weight.');
      }
    }
    if ((type['steps'] as Map<String, dynamic>? ?? const {}).length != 7) {
      problems.add('type.steps must define the 7-step scale 2xs..2xl.');
    }
    for (final entry in (control['sizes'] as Map<String, dynamic>? ?? const {}).entries) {
      final size = entry.value as Map<String, dynamic>;
      final radiusStep = size['radius'] as String?;
      final steps = _map(this.radius, 'steps');
      if (radiusStep == null || !steps.containsKey(radiusStep)) {
        problems.add('control.sizes["${entry.key}"].radius "$radiusStep" is not a declared radius step.');
      }
    }
    if ((control['sizes'] as Map<String, dynamic>? ?? const {}).length != 3) {
      problems.add('control.sizes must define sm, md and lg.');
    }
    final easing = _map(motion, 'easing')['cubic'] as List<dynamic>?;
    if (easing == null || easing.length != 4) {
      problems.add('motion.easing.cubic must be four numbers.');
    }
  }

  // --- resolution -----------------------------------------------------------

  /// Resolves [role] for the given (theme, accent) pair.
  ///
  /// A role with no entry in `meta.sources` comes straight from the theme. A
  /// role with an `accentKey` source comes from the accent. A role with a
  /// `derived` source is a mix of a seed and a target in sRGB space, where the
  /// amount is chosen per theme.
  Rgb resolveColor(String themeId, String accentId, String role) {
    if (!roles.contains(role)) {
      throw TokenError(['Unknown role "$role" (not declared in meta.roles).']);
    }
    if (!themes.containsKey(themeId)) {
      throw TokenError(['Unknown theme "$themeId".']);
    }
    if (!accents.containsKey(accentId)) {
      throw TokenError(['Unknown accent "$accentId".']);
    }
    final source = sources[role] as Map<String, dynamic>?;
    if (source == null) {
      return tryParseColor((themes[themeId] as Map<String, dynamic>)[role] as String?) ??
          (throw TokenError(['Theme "$themeId" role "$role" is missing or malformed.']));
    }
    switch (source['kind']) {
      case 'accentKey':
        final value = (accents[accentId] as Map<String, dynamic>)[source['key']] as String?;
        return tryParseColor(value) ??
            (throw TokenError(['Accent "$accentId" key "${source['key']}" is malformed.']));
      case 'derived':
        final seed = _operandColor(themeId, accentId, source['seed'] as Map<String, dynamic>);
        final target = _operandColor(themeId, accentId, source['target'] as Map<String, dynamic>);
        final amount = _operandAmount(themeId, source['amount'] as Map<String, dynamic>);
        return Rgb.mix(seed, target, amount);
      default:
        throw TokenError(['Role "$role" has unknown source kind "${source['kind']}".']);
    }
  }

  Rgb _operandColor(String themeId, String accentId, Map<String, dynamic> operand) {
    switch (operand['kind']) {
      case 'accentRole':
        return resolveColor(themeId, accentId, operand['role'] as String);
      case 'themeRole':
        return resolveColor(themeId, accentId, operand['role'] as String);
      case 'themeKey':
        final key = operand['key'] as String;
        final value = themeDerive(themeId)[key];
        if (tryParseColor(value as String?) != null) return tryParseColor(value as String)!;
        if (value is String) return resolveColor(themeId, accentId, value);
        throw TokenError(['Theme "$themeId" derive["$key"] must be a colour or a role name.']);
      default:
        throw TokenError(['Unknown operand kind "${operand['kind']}".']);
    }
  }

  double _operandAmount(String themeId, Map<String, dynamic> operand) {
    if (operand['kind'] != 'themeKey') {
      throw TokenError(['Only a themeKey may be used as a mix amount.']);
    }
    final value = themeDerive(themeId)[operand['key']];
    if (value is! num) {
      throw TokenError(['Theme "$themeId" derive["${operand['key']}"] must be a number.']);
    }
    final amount = value.toDouble();
    if (amount < 0.0 || amount > 1.0) {
      throw TokenError(['Theme "$themeId" derive["${operand['key']}"] must be within 0.0..1.0.']);
    }
    return amount;
  }

  /// Every (theme, accent) combination, in a fixed order.
  List<({String theme, String accent})> get combinations {
    final result = <({String theme, String accent})>[];
    for (final theme in themeIds) {
      for (final accent in accentIds) {
        result.add((theme: theme, accent: accent));
      }
    }
    return result;
  }

  /// Resolved control sizes for a theme, already scaled by [density].
  List<ControlSize> controlSizes(double density) {
    final scale = control['densityScale'] == true ? density : 1.0;
    final sizes = _map(control, 'sizes');
    final result = <ControlSize>[];
    for (final name in const ['sm', 'md', 'lg']) {
      final size = sizes[name] as Map<String, dynamic>;
      result.add(ControlSize(
        name: name,
        height: ((size['height'] as num) * scale).toDouble(),
        paddingX: ((size['paddingX'] as num) * scale).toDouble(),
        gap: ((size['gap'] as num) * scale).toDouble(),
        fontSize: (size['fontSize'] as num).toDouble(),
        iconSize: (size['iconSize'] as num).toDouble(),
        radius: size['radius'] as String,
      ));
    }
    return result;
  }
}

Map<String, dynamic> _map(Map<String, dynamic> parent, String key) {
  final value = parent[key];
  if (value is Map<String, dynamic>) return value;
  return <String, dynamic>{};
}

// ---------------------------------------------------------------------------
// Dart emission
// ---------------------------------------------------------------------------

const _roleOrderHint = 'Roles are emitted in meta.roles order.';

String _dartString(String value) => value
    .replaceAll('\\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$');

String _dartDouble(num value) {
  final text = value.toStringAsFixed(4);
  var trimmed = text;
  while (trimmed.contains('.') && trimmed.endsWith('0')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  if (trimmed.endsWith('.')) trimmed = trimmed.substring(0, trimmed.length - 1);
  if (trimmed == '-0') trimmed = '0';
  return trimmed;
}

String _dartStringList(Object? value) {
  final items = (value as List<dynamic>? ?? const <dynamic>[])
      .map((dynamic entry) => "'${_dartString(entry as String)}'")
      .join(', ');
  return '<String>[$items]';
}

/// Token names that are not legal Dart identifiers. The token name is still
/// used verbatim as a map key and in `MkviTypeScale.step()`, so the design
/// system keeps calling the step `2xs`; only the Dart field is renamed.
const _identifierAliases = <String, String>{
  '2xs': 'xxs',
  '2xl': 'xxl',
};

String _pascal(String value) => value
    .split(RegExp(r'[^A-Za-z0-9]'))
    .where((part) => part.isNotEmpty)
    .map((part) => part[0].toUpperCase() + part.substring(1))
    .join();

String _camel(String value) {
  final alias = _identifierAliases[value];
  if (alias != null) return alias;
  final pascal = _pascal(value);
  if (pascal.isEmpty) return 'unnamed';
  var identifier = pascal[0].toLowerCase() + pascal.substring(1);
  if (RegExp(r'^[0-9]').hasMatch(identifier)) {
    identifier = 'n$identifier';
  }
  return identifier;
}

/// Emits the whole `tokens.g.dart` source. Deterministic.
String generateDart(TokenSpec spec) {
  final out = StringBuffer();
  final roles = spec.roles;
  final notes = spec.roleNotes;
  final scaleControl = spec.control['densityScale'] == true;
  final spaceUnit = (spec.space['unit'] as num).toDouble();
  final spaceDensity = (spec.space['density'] as num).toDouble();
  final spaceSteps = spec.space['steps'] as Map<String, dynamic>;
  final spaceStepNames = spaceSteps.keys.toList(growable: false);
  final radiusSteps = spec.radius['steps'] as Map<String, dynamic>;
  final radiusStepNames = radiusSteps.keys.toList(growable: false);
  final radiusPresets = spec.radius['presets'] as Map<String, dynamic>;
  final typeSteps = spec.type['steps'] as Map<String, dynamic>;
  final typeStepNames = typeSteps.keys.toList(growable: false);
  final lineHeights = spec.type['lineHeights'] as Map<String, dynamic>;
  final weights = spec.type['weights'] as Map<String, dynamic>;
  final durations = spec.motion['durations'] as Map<String, dynamic>;
  final durationNames = durations.keys.toList(growable: false);
  final easingName = (spec.motion['easing'] as Map<String, dynamic>)['name'] as String;
  final easingCubic =
      (spec.motion['easing'] as Map<String, dynamic>)['cubic'] as List<dynamic>;

  void writeln([String line = '']) => out.writeln(line);

  // -- header ---------------------------------------------------------------
  writeln('// GENERATED CODE - DO NOT EDIT BY HAND.');
  writeln('//');
  writeln('// Source:    design/tokens.json  (${spec.name} v${spec.version})');
  writeln('// Generator: design/tool/generate_tokens.dart');
  writeln('// Gate:      cd design && dart pub get && dart test');
  writeln('//');
  writeln('// ${roles.length} colour roles x ${spec.themeIds.length} themes x '
      '${spec.accentIds.length} accents = ${spec.combinations.length} immutable token sets.');
  writeln('// $_roleOrderHint');
  writeln('//');
  writeln('// Written verbatim by the generator and deliberately not `dart format`');
  writeln('// canonical, so the bytes cannot depend on the local SDK formatter.');
  writeln('//');
  writeln('// ignore_for_file: constant_identifier_names, prefer_const_constructors');
  writeln();
  writeln("import 'dart:ui' show lerpDouble;");
  writeln();
  writeln("import 'package:flutter/material.dart';");
  writeln();

  // -- enums ----------------------------------------------------------------
  writeln('/// The four shipped themes. The Turkish label is what the settings UI shows.');
  writeln('enum MkviThemeId {');
  for (final id in spec.themeIds) {
    writeln('  $id,');
  }
  writeln('}');
  writeln();
  writeln('/// The four shipped accents, independent of the theme.');
  writeln('enum MkviAccentId {');
  for (final id in spec.accentIds) {
    writeln('  $id,');
  }
  writeln('}');
  writeln();
  writeln("/// Theme names in Turkish, as shown in the appearance settings.");
  writeln('const Map<MkviThemeId, String> mkviThemeLabelsTr = <MkviThemeId, String>{');
  for (final id in spec.themeIds) {
    writeln("  MkviThemeId.$id: '${_dartString(spec.themeLabel(id))}',");
  }
  writeln('};');
  writeln();
  writeln('/// Accent names in Turkish, as shown in the appearance settings.');
  writeln('const Map<MkviAccentId, String> mkviAccentLabelsTr = <MkviAccentId, String>{');
  for (final id in spec.accentIds) {
    writeln("  MkviAccentId.$id: '${_dartString(spec.accentLabel(id))}',");
  }
  writeln('};');
  writeln();
  writeln('extension MkviThemeIdLabel on MkviThemeId {');
  writeln('  /// Turkish display label for this theme.');
  writeln('  String get labelTr => mkviThemeLabelsTr[this]!;');
  writeln('}');
  writeln();
  writeln('extension MkviAccentIdLabel on MkviAccentId {');
  writeln('  /// Turkish display label for this accent.');
  writeln('  String get labelTr => mkviAccentLabelsTr[this]!;');
  writeln('}');
  writeln();

  // -- theme metadata --------------------------------------------------------
  // A theme carries more than colours: a polarity, and the three derive
  // amounts a CUSTOM accent is built with. The colours alone cannot express
  // them, so the file has to export them or a consumer has to re-read
  // tokens.json from disk, which a packaged app does not have.
  writeln('/// The per-theme values that are not colours.');
  writeln('///');
  writeln('/// `polarity` drives light/dark selection; the three `derive` amounts');
  writeln('/// are how a custom accent is derived with the same arithmetic the');
  writeln('/// generator used for `accentSoft` and `focusRing`.');
  writeln('class MkviThemeMeta {');
  writeln('  const MkviThemeMeta({');
  writeln('    required this.isDark,');
  writeln('    required this.focusRingTarget,');
  writeln('    required this.focusRingMix,');
  writeln('    required this.accentSoftMix,');
  writeln('  });');
  writeln();
  writeln('  /// `themes.<id>.polarity == \'dark\'.');
  writeln('  final bool isDark;');
  writeln('  /// `themes.<id>.derive.focusRingTarget`.');
  writeln('  final Color focusRingTarget;');
  writeln('  /// `themes.<id>.derive.focusRingMix`.');
  writeln('  final double focusRingMix;');
  writeln('  /// `themes.<id>.derive.accentSoftMix`.');
  writeln('  final double accentSoftMix;');
  writeln('}');
  writeln();
  writeln('/// Every theme\'s non-colour declarations, keyed by theme.');
  writeln('const Map<MkviThemeId, MkviThemeMeta> mkviThemeMeta =');
  writeln('    <MkviThemeId, MkviThemeMeta>{');
  for (final id in spec.themeIds) {
    final target = spec.themeFocusRingTarget(id);
    writeln('  MkviThemeId.$id: MkviThemeMeta(');
    writeln('    isDark: ${spec.isDarkTheme(id)},');
    writeln('    focusRingTarget: Color(${target.toDartLiteral()}),');
    writeln('    focusRingMix: ${_dartDouble(spec.themeMix(id, 'focusRingMix'))},');
    writeln('    accentSoftMix: ${_dartDouble(spec.themeMix(id, 'accentSoftMix'))},');
    writeln('  ),');
  }
  writeln('};');
  writeln();
  writeln('/// The metadata of one theme.');
  writeln('///');
  writeln('/// Throws [ArgumentError] for an id no theme declares, so an unknown');
  writeln('/// theme is a caller error rather than a silent null.');
  writeln('MkviThemeMeta mkviMetaFor(MkviThemeId theme) {');
  writeln('  final meta = mkviThemeMeta[theme];');
  writeln('  if (meta == null) {');
  writeln('    throw ArgumentError.value(theme, \'theme\', \'Unknown theme\');');
  writeln('  }');
  writeln('  return meta;');
  writeln('}');
  writeln();

  // -- the accessibility gate, as data --------------------------------------
  // The `contrast` list is the gate's input. Emitting it means a consumer can
  // run the SAME gate on a custom accent or a high-contrast palette, instead
  // of hard-coding the minimums it remembers.
  writeln('/// One declared contrast requirement: `fg` on `bg` must reach `min`.');
  writeln('class MkviContrastRequirement {');
  writeln('  const MkviContrastRequirement({');
  writeln('    required this.foregroundRole,');
  writeln('    required this.backgroundRole,');
  writeln('    required this.minimum,');
  writeln('  });');
  writeln();
  writeln('  /// Role painted on top.');
  writeln('  final String foregroundRole;');
  writeln('  /// Role painted underneath.');
  writeln('  final String backgroundRole;');
  writeln('  /// The WCAG 2.x ratio the pair must reach.');
  writeln('  final double minimum;');
  writeln();
  writeln('  @override');
  writeln('  String toString() =>');
  writeln("      '\$foregroundRole on \$backgroundRole >= \$minimum';");
  writeln('}');
  writeln();
  writeln('/// The `contrast` list, in declaration order. The whole gate is here:');
  writeln('/// a pair missing from this list is a pair nobody is checking.');
  writeln('const List<MkviContrastRequirement> mkviContrastRequirements =');
  writeln('    <MkviContrastRequirement>[');
  for (final pair in spec.contrastList) {
    writeln('  MkviContrastRequirement(');
    writeln("    foregroundRole: '${_dartString(pair.fg)}',");
    writeln("    backgroundRole: '${_dartString(pair.bg)}',");
    writeln('    minimum: ${_dartDouble(pair.min)},');
    writeln('  ),');
  }
  writeln('];');
  writeln();

  // -- role enum ------------------------------------------------------------
  writeln('/// Every colour role. A theme MUST define all of them; the token gate');
  writeln('/// fails the build otherwise.');
  writeln('enum MkviRole {');
  for (final role in roles) {
    writeln('  $role,');
  }
  writeln('}');
  writeln();

  // -- type scale -----------------------------------------------------------
  writeln('/// One step of the type scale, ready to become a [TextStyle].');
  writeln('class MkviTypeStep {');
  writeln('  const MkviTypeStep({');
  writeln('    required this.size,');
  writeln('    required this.height,');
  writeln('    required this.weight,');
  writeln('    required this.tracking,');
  writeln('  });');
  writeln();
  writeln('  /// Font size in logical pixels.');
  writeln('  final double size;');
  writeln('  /// Line height as a multiple of [size].');
  writeln('  final double height;');
  writeln('  final FontWeight weight;');
  writeln('  /// Letter spacing in logical pixels.');
  writeln('  final double tracking;');
  writeln();
  writeln('  TextStyle style({String? family}) => TextStyle(');
  writeln('    fontFamily: family,');
  writeln('    fontSize: size,');
  writeln('    height: height,');
  writeln('    fontWeight: weight,');
  writeln('    letterSpacing: tracking,');
  writeln('  );');
  writeln('}');
  writeln();
  writeln('/// The 7-step type scale (2xs -> 2xl) plus the shared line heights and weights.');
  writeln('class MkviTypeScale {');
  writeln('  const MkviTypeScale({');
  writeln('    required this.family,');
  writeln('    required this.monoFamily,');
  writeln('    required this.lineHeights,');
  writeln('    required this.weights,');
  for (final name in typeStepNames) {
    writeln('    required this.${_camel(name)},');
  }
  writeln('  });');
  writeln();
  writeln('  /// Preferred UI font family, most specific first.');
  writeln('  final List<String> family;');
  writeln('  /// Preferred monospace family for codes, pairing codes and logs.');
  writeln('  final List<String> monoFamily;');
  writeln('  final Map<String, double> lineHeights;');
  writeln('  final Map<String, FontWeight> weights;');
  for (final name in typeStepNames) {
    final note = notes[name] ?? 'Type scale step $name.';
    writeln('  /// $note');
    writeln('  final MkviTypeStep ${_camel(name)};');
  }
  writeln();
  writeln('  /// Every step, keyed by its token name (2xs, xs, sm, md, lg, xl, 2xl).');
  writeln('  Map<String, MkviTypeStep> get steps => <String, MkviTypeStep>{');
  for (final name in typeStepNames) {
    writeln("    '$name': ${_camel(name)},");
  }
  writeln('  };');
  writeln();
  writeln('  MkviTypeStep step(String name) => switch (name) {');
  for (final name in typeStepNames) {
    writeln("    '$name' => ${_camel(name)},");
  }
  writeln("    _ => throw ArgumentError.value(name, 'name', 'Unknown type step'),");
  writeln('  };');
  writeln('}');
  writeln();
  writeln('const mkviType = MkviTypeScale(');
  writeln('  family: ${_dartStringList(spec.type['fontFamily'])},');
  writeln('  monoFamily: ${_dartStringList(spec.type['fontFamilyMono'])},');
  writeln('  lineHeights: <String, double>{');
  for (final entry in lineHeights.entries) {
    writeln("    '${entry.key}': ${_dartDouble(entry.value as num)},");
  }
  writeln('  },');
  writeln('  weights: <String, FontWeight>{');
  for (final entry in weights.entries) {
    writeln("    '${entry.key}': FontWeight.w${entry.value},");
  }
  writeln('  },');
  for (final name in typeStepNames) {
    final step = typeSteps[name] as Map<String, dynamic>;
    writeln('  ${_camel(name)}: MkviTypeStep(');
    writeln('    size: ${_dartDouble(step['size'] as num)},');
    writeln('    height: ${_dartDouble(lineHeights[step['lineHeight']] as num)},');
    writeln('    weight: FontWeight.w${weights[step['weight']]},');
    writeln('    tracking: ${_dartDouble(step['tracking'] as num)},');
    writeln('  ),');
  }
  writeln(');');
  writeln();

  // -- spacing --------------------------------------------------------------
  writeln('/// 4px-based spacing scale. Every step is `unit * multiplier * density`.');
  writeln('class MkviSpacing {');
  writeln('  const MkviSpacing({');
  writeln('    required this.unit,');
  writeln('    required this.density,');
  for (final name in spaceStepNames) {
    writeln('    required this.s$name,');
  }
  writeln('  });');
  writeln();
  writeln('  /// Base step in logical pixels (4).');
  writeln('  final double unit;');
  writeln('  /// User density multiplier applied to every step.');
  writeln('  final double density;');
  for (final name in spaceStepNames) {
    final value = (spaceUnit * (spaceSteps[name] as num) * spaceDensity);
    writeln('  /// space.$name');
    writeln('  final double s$name;');
    if (value == 0) continue;
  }
  writeln();
  writeln('  /// Every step, keyed by its token name (0, 1, 2 ...).');
  writeln('  Map<String, double> get steps => <String, double>{');
  for (final name in spaceStepNames) {
    writeln("    '$name': s$name,");
  }
  writeln('  };');
  writeln();
  writeln('  double gap(String name) => switch (name) {');
  for (final name in spaceStepNames) {
    writeln("    '$name' => s$name,");
  }
  writeln("    _ => throw ArgumentError.value(name, 'name', 'Unknown space step'),");
  writeln('  };');
  writeln();
  writeln('  /// The same scale at a different density.');
  writeln('  MkviSpacing withDensity(double value) => MkviSpacing(');
  writeln('    unit: unit,');
  writeln('    density: value,');
  for (final name in spaceStepNames) {
    final multiplier = (spaceSteps[name] as num);
    writeln('    s$name: unit * ${_dartDouble(multiplier)} * value,');
  }
  writeln('  );');
  writeln('}');
  writeln();
  writeln('/// The named density presets from tokens.json.');
  writeln('const Map<String, double> mkviDensities = <String, double>{');
  for (final entry in (spec.space['densities'] as Map<String, dynamic>).entries) {
    writeln("  '${entry.key}': ${_dartDouble(entry.value as num)},");
  }
  writeln('};');
  writeln();
  writeln('/// The density a fresh token set starts at, from `space.density`.');
  writeln('const double mkviDefaultDensity = ${_dartDouble(spaceDensity)};');
  writeln();
  writeln('/// The spacing scale at density 1.0. Multiply by density at the call site');
  writeln('/// or use [MkviTokens.spacing].');
  writeln('const mkviSpacing = MkviSpacing(');
  writeln('  unit: ${_dartDouble(spaceUnit)},');
  writeln('  density: 1.0,');
  for (final name in spaceStepNames) {
    final value = spaceUnit * (spaceSteps[name] as num);
    writeln('  s$name: ${_dartDouble(value)},');
  }
  writeln(');');
  writeln();

  // -- radii ----------------------------------------------------------------
  writeln('/// Corner radii derived from a single `unit`, so a preset change moves');
  writeln('/// every corner in the app at once.');
  writeln('class MkviRadii {');
  writeln('  const MkviRadii({');
  writeln('    required this.preset,');
  writeln('    required this.unit,');
  for (final name in radiusStepNames) {
    writeln('    required this.${_camel(name)},');
  }
  writeln('  });');
  writeln();
  writeln('  /// Preset name this instance was built from (cozy, crisp).');
  writeln('  final String preset;');
  writeln('  final double unit;');
  for (final name in radiusStepNames) {
    final note = notes[name] ?? 'radius.$name';
    writeln('  /// $note');
    writeln('  final double ${_camel(name)};');
  }
  writeln();
  writeln('  MkviRadii scaled(double factor) => MkviRadii(');
  writeln("    preset: 'scaled',");
  writeln('    unit: unit,');
  for (final name in radiusStepNames) {
    final step = radiusSteps[name] as Map<String, dynamic>;
    final expression = switch (step['of']) {
      'zero' => '0.0',
      'fixed' => _dartDouble(step['value'] as num),
      _ => 'unit * ${_dartDouble(step['scale'] as num)} * factor',
    };
    writeln('    ${_camel(name)}: $expression,');
  }
  writeln('  );');
  writeln('}');
  writeln();
  for (final preset in radiusPresets.entries) {
    final presetUnit = (preset.value as Map<String, dynamic>)['unit'] as num;
    final presetScale = (preset.value as Map<String, dynamic>)['scale'] as num;
    writeln("const mkviRadii${_pascal(preset.key)} = MkviRadii(");
    writeln("  preset: '${preset.key}',");
    writeln('  unit: ${_dartDouble(presetUnit)},');
    for (final name in radiusStepNames) {
      final step = radiusSteps[name] as Map<String, dynamic>;
      final value = switch (step['of']) {
        'zero' => 0.0,
        'fixed' => (step['value'] as num).toDouble(),
        _ => presetUnit * (step['scale'] as num) * presetScale,
      };
      writeln('  ${_camel(name)}: ${_dartDouble(value)},');
    }
    writeln(');');
  }
  writeln("const mkviRadii = mkviRadii${_pascal(spec.radius['defaultPreset'] as String)};");
  writeln();
  writeln('/// The radius presets, in declaration order. A consumer offers these');
  writeln('/// names; it does not type its own list beside them.');
  writeln('const List<String> mkviRadiusPresets = ${_dartStringList(radiusPresets.keys.toList(growable: false))};');
  writeln();
  writeln('/// The radii of one declared preset.');
  writeln('MkviRadii mkviRadiiFor(String preset) => switch (preset) {');
  for (final preset in radiusPresets.keys) {
    writeln("  '$preset' => mkviRadii${_pascal(preset)},");
  }
  writeln("  _ => throw ArgumentError.value(preset, 'preset', 'Unknown radius preset'),");
  writeln('};');
  writeln();
  writeln('/// Every radius step, keyed by its token name (none .. pill).');
  writeln('Map<String, double> mkviRadiusSteps(MkviRadii radii) =>');
  writeln('    <String, double>{');
  for (final name in radiusStepNames) {
    writeln("      '$name': radii.${_camel(name)},");
  }
  writeln('    };');
  writeln();

  // -- motion ---------------------------------------------------------------
  writeln('/// Durations and the single easing curve used across the app.');
  writeln('class MkviMotion {');
  writeln('  const MkviMotion({');
  writeln("    required this.easingName,");
  writeln('    required this.easing,');
  for (final name in durationNames) {
    writeln('    required this.$name,');
  }
  writeln('  });');
  writeln();
  writeln("  /// Name of the easing curve ('$easingName').");
  writeln('  final String easingName;');
  writeln('  /// The one easing curve in the system.');
  writeln('  final Cubic easing;');
  for (final name in durationNames) {
    writeln('  /// motion.durations.$name');
    writeln('  final Duration $name;');
  }
  writeln();
  writeln('  /// Every duration at a different speed (0.5 for twice as fast).');
  writeln('  MkviMotion scaled(double factor) => MkviMotion(');
  writeln('    easingName: easingName,');
  writeln('    easing: easing,');
  for (final name in durationNames) {
    writeln("    $name: Duration(microseconds: ($name.inMicroseconds * factor).round()),");
  }
  writeln('  );');
  writeln('}');
  writeln();
  writeln('const mkviMotion = MkviMotion(');
  writeln("  easingName: '$easingName',");
  writeln('  easing: Cubic(${easingCubic.map((dynamic e) => _dartDouble(e as num)).join(', ')}),');
  for (final name in durationNames) {
    writeln('  $name: Duration(milliseconds: ${durations[name]}),');
  }
  writeln(');');
  writeln();
  writeln('/// The duration names, in declaration order.');
  writeln('const List<String> mkviMotionNames = ${_dartStringList(durationNames)};');
  writeln();
  writeln('/// Every duration, keyed by its token name. `instant` is what reduced');
  writeln('/// motion replaces every other duration with, so it is looked up by');
  writeln('/// name rather than as a literal zero.');
  writeln('const Map<String, Duration> mkviMotionDurations = <String, Duration>{');
  for (final name in durationNames) {
    writeln("  '$name': Duration(milliseconds: ${durations[name]}),");
  }
  writeln('};');
  writeln();

  // -- controls -------------------------------------------------------------
  writeln('/// Height, padding and icon size of a control at one of three sizes.');
  writeln('class MkviControlSize {');
  writeln('  const MkviControlSize({');
  writeln('    required this.name,');
  writeln('    required this.height,');
  writeln('    required this.paddingX,');
  writeln('    required this.gap,');
  writeln('    required this.fontSize,');
  writeln('    required this.iconSize,');
  writeln('    required this.radiusStep,');
  writeln('  });');
  writeln();
  writeln("  /// Size name (sm, md, lg).");
  writeln('  final String name;');
  writeln('  /// Control height in logical pixels, already density-scaled.');
  writeln('  final double height;');
  writeln('  final double paddingX;');
  writeln('  final double gap;');
  writeln('  final double fontSize;');
  writeln('  final double iconSize;');
  writeln("  /// Key into [MkviRadii] for this control's corner radius.");
  writeln('  final String radiusStep;');
  writeln('}');
  writeln();
  writeln('/// Control sizes for the three sizes, at one density.');
  writeln('class MkviControls {');
  writeln('  const MkviControls({');
  writeln('    required this.density,');
  writeln('    required this.densityScale,');
  writeln('    required this.hitTargetMin,');
  writeln('    required this.borderWidth,');
  writeln('    required this.focusRingWidth,');
  writeln('    required this.focusRingGap,');
  writeln('    required this.sm,');
  writeln('    required this.md,');
  writeln('    required this.lg,');
  writeln('  });');
  writeln();
  writeln('  final double density;');
  writeln('  /// Whether heights and paddings follow [density]. Font sizes never do.');
  writeln('  final bool densityScale;');
  writeln('  /// Minimum pointer target, never scaled: ${spec.control['hitTargetMin']}px.');
  writeln('  final double hitTargetMin;');
  writeln('  final double borderWidth;');
  writeln('  final double focusRingWidth;');
  writeln('  final double focusRingGap;');
  writeln('  final MkviControlSize sm;');
  writeln('  final MkviControlSize md;');
  writeln('  final MkviControlSize lg;');
  writeln();
  writeln('  MkviControlSize of(String name) => switch (name) {');
  writeln("    'sm' => sm,");
  writeln("    'md' => md,");
  writeln("    'lg' => lg,");
  writeln("    _ => throw ArgumentError.value(name, 'name', 'Unknown control size'),");
  writeln('  };');
  writeln('}');
  writeln();
  final sizes = spec.controlSizes(1.0);
  writeln('/// Canonical control sizes at density 1.0.');
  writeln('const mkviControls = MkviControls(');
  writeln('  density: 1.0,');
  writeln('  densityScale: $scaleControl,');
  writeln('  hitTargetMin: ${_dartDouble(spec.control['hitTargetMin'] as num)},');
  writeln('  borderWidth: ${_dartDouble(spec.control['borderWidth'] as num)},');
  writeln('  focusRingWidth: ${_dartDouble(spec.control['focusRingWidth'] as num)},');
  writeln('  focusRingGap: ${_dartDouble(spec.control['focusRingGap'] as num)},');
  for (final size in sizes) {
    writeln('  ${size.name}: MkviControlSize(');
    writeln("    name: '${size.name}',");
    writeln('    height: ${_dartDouble(size.height)},');
    writeln('    paddingX: ${_dartDouble(size.paddingX)},');
    writeln('    gap: ${_dartDouble(size.gap)},');
    writeln('    fontSize: ${_dartDouble(size.fontSize)},');
    writeln('    iconSize: ${_dartDouble(size.iconSize)},');
    writeln("    radiusStep: '${size.radius}',");
    writeln('  ),');
  }
  writeln(');');
  writeln();
  writeln('/// The control size names, in declaration order.');
  writeln('const List<String> mkviControlSizeNames = ${_dartStringList(sizes.map((s) => s.name).toList(growable: false))};');
  writeln();
  // A function, not a const map: a `const` variable's field cannot be read in
  // a const expression, and the same is true for the radii steps above.
  writeln('/// Every control size at density 1.0, keyed by its token name.');
  writeln('Map<String, MkviControlSize> mkviControlSizes() =>');
  writeln('    <String, MkviControlSize>{');
  for (final size in sizes) {
    writeln("      '${size.name}': mkviControls.${size.name},");
  }
  writeln('    };');
  writeln();

  // -- tokens ---------------------------------------------------------------
  writeln('/// The design tokens for one (theme, accent) pair.');
  writeln('///');
  writeln('/// Every field is a role from `meta.roles`. Nothing in the app may');
  writeln('/// hard-code a colour; read it from here via');
  writeln('/// `Theme.of(context).extension<MkviTokens>()!`.');
  writeln('@immutable');
  writeln('class MkviTokens extends ThemeExtension<MkviTokens> {');
  writeln('  const MkviTokens({');
  writeln('    required this.themeId,');
  writeln('    required this.accentId,');
  writeln('    this.density = mkviDefaultDensity,');
  for (final role in roles) {
    writeln('    required this.$role,');
  }
  writeln('  });');
  writeln();
  writeln('  /// Which theme these colours were resolved for.');
  writeln('  final MkviThemeId themeId;');
  writeln('  /// Which accent these colours were resolved for.');
  writeln('  final MkviAccentId accentId;');
  writeln('  /// User density multiplier, applied to spacing and control sizes.');
  writeln('  final double density;');
  for (final role in roles) {
    final note = notes[role] ?? role;
    writeln('  /// $note');
    writeln('  final Color $role;');
  }
  writeln();
  writeln('  /// Type scale. Density independent. Not named `type`, because');
  writeln('  /// [ThemeExtension] already defines a `type` getter.');
  writeln('  static const MkviTypeScale typeScale = mkviType;');
  writeln();
  writeln('  /// Corner radii. Density independent.');
  writeln('  static const MkviRadii radii = mkviRadii;');
  writeln();
  writeln('  /// Durations and easing. Density independent.');
  writeln('  static const MkviMotion motion = mkviMotion;');
  writeln();
  writeln('  /// Spacing at this instance\'s density.');
  writeln('  MkviSpacing get spacing => mkviSpacing.withDensity(density);');
  writeln();
  writeln('  /// Control sizes at this instance\'s density.');
  writeln('  MkviControls get controls => controlsAt(density);');
  writeln();
  writeln('  /// Control sizes for an arbitrary density. Height, padding and gap');
  writeln('  /// follow the density; font and icon sizes do not.');
  writeln('  static MkviControls controlsAt(double value) {');
  writeln('    final double scale = mkviControls.densityScale ? value : 1.0;');
  writeln('    return MkviControls(');
  writeln('      density: value,');
  writeln('      densityScale: mkviControls.densityScale,');
  writeln('      hitTargetMin: mkviControls.hitTargetMin,');
  writeln('      borderWidth: mkviControls.borderWidth,');
  writeln('      focusRingWidth: mkviControls.focusRingWidth,');
  writeln('      focusRingGap: mkviControls.focusRingGap,');
  for (final size in sizes) {
    writeln('      ${size.name}: MkviControlSize(');
    writeln("        name: '${size.name}',");
    writeln('        height: mkviControls.${size.name}.height * scale,');
    writeln('        paddingX: mkviControls.${size.name}.paddingX * scale,');
    writeln('        gap: mkviControls.${size.name}.gap * scale,');
    writeln('        fontSize: mkviControls.${size.name}.fontSize,');
    writeln('        iconSize: mkviControls.${size.name}.iconSize,');
    writeln("        radiusStep: mkviControls.${size.name}.radiusStep,");
    writeln('      ),');
  }
  writeln('    );');
  writeln('  }');
  writeln();
  writeln('  /// The same colours at a different density.');
  writeln('  MkviTokens withDensity(double value) => MkviTokens(');
  writeln('    themeId: themeId,');
  writeln('    accentId: accentId,');
  writeln('    density: value,');
  for (final role in roles) {
    writeln('    $role: $role,');
  }
  writeln('  );');
  writeln();
  writeln('  /// Resolved value of any role, for tooling and debug overlays.');
  writeln('  Color role(MkviRole role) => switch (role) {');
  for (final role in roles) {
    writeln('    MkviRole.$role => $role,');
  }
  writeln('  };');
  writeln();
  writeln('  @override');
  writeln('  MkviTokens copyWith({');
  writeln('    MkviThemeId? themeId,');
  writeln('    MkviAccentId? accentId,');
  writeln('    double? density,');
  for (final role in roles) {
    writeln('    Color? $role,');
  }
  writeln('  }) {');
  writeln('    return MkviTokens(');
  writeln('      themeId: themeId ?? this.themeId,');
  writeln('      accentId: accentId ?? this.accentId,');
  writeln('      density: density ?? this.density,');
  for (final role in roles) {
    writeln('      $role: $role ?? this.$role,');
  }
  writeln('    );');
  writeln('  }');
  writeln();
  writeln('  @override');
  writeln('  MkviTokens lerp(MkviTokens? other, double t) {');
  writeln('    if (other is! MkviTokens) return this;');
  writeln('    return MkviTokens(');
  writeln('      themeId: t < 0.5 ? themeId : other.themeId,');
  writeln('      accentId: t < 0.5 ? accentId : other.accentId,');
  writeln('      density: lerpDouble(density, other.density, t) ?? density,');
  for (final role in roles) {
    writeln('      $role: Color.lerp($role, other.$role, t)!,');
  }
  writeln('    );');
  writeln('  }');
  writeln();
  writeln('  @override');
  writeln('  String toString() =>');
  writeln("      'MkviTokens(\${themeId.name}/\${accentId.name}, density: \$density)';");
  writeln('}');
  writeln();

  // -- instances ------------------------------------------------------------
  for (final themeId in spec.themeIds) {
    for (final accentId in spec.accentIds) {
      final name = 'mkvi${_pascal(themeId)}${_pascal(accentId)}';
      writeln('/// $themeId theme, $accentId accent.');
      writeln('const $name = MkviTokens(');
      writeln('  themeId: MkviThemeId.$themeId,');
      writeln('  accentId: MkviAccentId.$accentId,');
      for (final role in roles) {
        final colour = spec.resolveColor(themeId, accentId, role);
        final scope = spec.sources[role] == null ? 'theme' : 'derived';
        writeln('  $role: Color(${colour.toDartLiteral()}), // $role ($themeId/$accentId, $scope)');
      }
      writeln(');');
      writeln();
    }
  }

  writeln('/// Every token set, keyed by theme then accent.');
  writeln('const Map<MkviThemeId, Map<MkviAccentId, MkviTokens>> mkviTokensByTheme =');
  writeln('    <MkviThemeId, Map<MkviAccentId, MkviTokens>>{');
  for (final themeId in spec.themeIds) {
    writeln('  MkviThemeId.$themeId: <MkviAccentId, MkviTokens>{');
    for (final accentId in spec.accentIds) {
      writeln('    MkviAccentId.$accentId: mkvi${_pascal(themeId)}${_pascal(accentId)},');
    }
    writeln('  },');
  }
  writeln('};');
  writeln();
  writeln('/// The default pair declared in `meta`.');
  writeln('const mkviTokensDefault =');
  writeln('    mkvi${_pascal(defaultThemeName(spec))}${_pascal(spec.defaultAccent)};');
  writeln();
  writeln('/// The token set for an arbitrary (theme, accent) pair.');
  writeln('MkviTokens mkviTokensFor(MkviThemeId theme, MkviAccentId accent) =>');
  writeln('    mkviTokensByTheme[theme]![accent]!;');
  writeln();

  return out.toString();
}

String defaultThemeName(TokenSpec spec) =>
    spec.defaultTheme.isEmpty ? (spec.themeIds.isEmpty ? '' : spec.themeIds.first) : spec.defaultTheme;

// ---------------------------------------------------------------------------
// Contrast report
// ---------------------------------------------------------------------------

/// A markdown table of every declared pair: the minimum, the worst measured
/// ratio across all (theme, accent) combinations, and where that worst case is.
String contrastReport(TokenSpec spec) {
  final rows = <List<String>>[];
  for (final pair in spec.contrastList) {
    var worst = double.infinity;
    var worstWhere = '';
    for (final combination in spec.combinations) {
      final fg = spec.resolveColor(combination.theme, combination.accent, pair.fg);
      final bg = spec.resolveColor(combination.theme, combination.accent, pair.bg);
      final ratio = fg.contrastWith(bg);
      if (ratio < worst) {
        worst = ratio;
        worstWhere = '${combination.theme}/${combination.accent}';
      }
    }
    final margin = worst - pair.min;
    rows.add([
      '`${pair.fg}` on `${pair.bg}`',
      pair.min.toStringAsFixed(1),
      worst.toStringAsFixed(2),
      (margin >= 0 ? '+' : '') + margin.toStringAsFixed(2),
      worstWhere,
      worst >= pair.min ? 'pass' : 'FAIL',
    ]);
  }
  final buffer = StringBuffer()
    ..writeln('| role pair | min | worst measured | margin | worst combination | verdict |')
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  for (final row in rows) {
    buffer.writeln('| ${row.join(' | ')} |');
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const _usage = '''
Usage: dart run tool/generate_tokens.dart [options]

  --out <path>      Where to write the generated Dart file.
                    Default: design/lib/generated/tokens.g.dart
  --tokens <path>   Token source. Default: design/tokens.json
  --report          Print the contrast table (markdown) instead of writing.
  --check           Do not write; exit 3 if the existing output is out of date.
  --help            Show this message.

Exit codes: 0 ok, 2 invalid tokens, 3 stale output, 64 bad usage.
''';

/// Dart ignores the value returned from `main`, so the process exit code is
/// set explicitly. This is what makes the token errors fail a build.
void main(List<String> arguments) {
  exit(runGenerator(arguments));
}

int runGenerator(List<String> arguments) {
  String? outPath;
  String? tokensPath;
  var report = false;
  var check = false;

  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    switch (argument) {
      case '--out':
        if (i + 1 >= arguments.length) return _failUsage('--out needs a path.');
        outPath = arguments[++i];
      case '--tokens':
        if (i + 1 >= arguments.length) return _failUsage('--tokens needs a path.');
        tokensPath = arguments[++i];
      case '--report':
        report = true;
      case '--check':
        check = true;
      case '--help' || '-h':
        stdout.write(_usage);
        return 0;
      // ignore: no_default_cases
      default:
        return _failUsage('Unknown argument "$argument".');
    }
  }

  // Paths are resolved relative to the package, not the caller's cwd, so
  // `dart run tool/generate_tokens.dart` behaves the same from design/ or from
  // the repository root.
  final scriptPath = Platform.script.toFilePath();
  final packageRoot = File(scriptPath).parent.parent.path;
  final source = File(tokensPath ?? '$packageRoot/tokens.json');
  // The default output is INSIDE `lib/`, so the design package is a library
  // another package can depend on. See the header comment.
  final target = File(outPath ?? '$packageRoot/lib/generated/tokens.g.dart');

  if (!source.existsSync()) {
    stderr.writeln('Token file not found: ${source.path}');
    return 2;
  }

  final TokenSpec spec;
  try {
    spec = TokenSpec.parse(source.readAsStringSync(encoding: utf8), origin: source.path);
  } on TokenError catch (error) {
    stderr.writeln('Invalid design tokens in ${source.path}:');
    stderr.writeln(error.problems.join('\n'));
    return 2;
  }

  if (report) {
    stdout.write(contrastReport(spec));
    return 0;
  }

  final generated = generateDart(spec);

  if (check) {
    if (!target.existsSync()) {
      stderr.writeln('Generated file is missing: ${target.path}. Run: dart run tool/generate_tokens.dart');
      return 3;
    }
    final existing = target.readAsBytesSync();
    final expected = utf8.encode(generated);
    if (!_sameBytes(existing, expected)) {
      stderr.writeln('Generated file is out of date: ${target.path}');
      stderr.writeln('Run: dart run tool/generate_tokens.dart');
      return 3;
    }
    stdout.writeln('${target.path} is up to date.');
    return 0;
  }

  target.parent.createSync(recursive: true);
  target.writeAsStringSync(generated, encoding: utf8, flush: true);
  stdout.writeln('Wrote ${target.path} (${spec.roles.length} roles x '
      '${spec.themeIds.length} themes x ${spec.accentIds.length} accents).');
  return 0;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _failUsage(String message) {
  stderr.writeln(message);
  stderr.write(_usage);
  return 64;
}
