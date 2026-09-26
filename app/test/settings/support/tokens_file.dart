/// `design/tokens.json`, read from disk, for the assertions.
///
/// The tests in this directory must assert against the token FILE, not against
/// hex values copied into a test: a copied hex cannot fail when the file
/// changes, which is how a test ends up protecting a colour nobody uses any
/// more. So the file is read once, and every expectation in
/// `appearance_test.dart` is looked up here.
///
/// A theme's own roles come straight out of the file. A DERIVED role - an
/// `accentSoft` for a theme whose stored `accentSoft` belongs to a different
/// accent - is computed with the generator's own `Rgb.mix`, i.e. with the same
/// arithmetic that produced `design/generated/tokens.g.dart`. That is
/// deliberately not this layer's `mixColor`: if the two ever disagree, the
/// test that matters is the one that uses the generator.
library;

import 'dart:convert';
import 'dart:io';

import '../../../../design/tool/generate_tokens.dart';
import 'package:mkvi/settings/design_tokens.dart';

/// The token file, typed.
final class TokenFile {
  TokenFile._(this._root, this.path);

  /// The decoded top-level object.
  final Map<Object?, Object?> _root;

  /// Where it was found, for a failure message.
  final String path;

  /// The `meta.roles` list, in declaration order.
  late final List<String> roleNames = _stringList(_section('meta'), 'roles');

  /// The roles whose value does not depend on the accent: everything except
  /// the six `meta.sources` derives. A theme section stores all 29, but the
  /// six accent roles it stores are the ones cached for `meta.defaultAccent`,
  /// so only these 23 are comparable across all four accents.
  late final List<String> roleRoles = <String>[
    for (final String role in roleNames)
      if (!_accentDerivedRoles.contains(role)) role,
  ];

  /// The six roles `meta.sources` derives from the accent.
  static const Set<String> _accentDerivedRoles = <String>{
    'accent',
    'accentHover',
    'accentActive',
    'accentSoft',
    'focusRing',
    'textOnAccent',
  };

  /// `type.steps` keys, in declaration order.
  late final List<String> typeStepNames = _keysOf(
    _child(_section('type'), 'steps'),
  );

  /// `space.steps` keys, in declaration order.
  late final List<String> spaceStepNames = _keysOf(_spaceSteps());

  /// `type.lineHeights.<name>`.
  double lineHeight(String name) =>
      _number(_child(_section('type'), 'lineHeights'), name);

  /// `themes` keys, in declaration order.
  late final List<String> themeIds = _section(
    'themes',
  ).keys.whereType<String>().toList(growable: false);

  /// `accents` keys, in declaration order.
  late final List<String> accentIds = _section(
    'accents',
  ).keys.whereType<String>().toList(growable: false);

  /// `meta.defaultTheme`.
  late final String defaultThemeId = _string(_section('meta'), 'defaultTheme');

  /// `meta.defaultAccent`.
  late final String defaultAccentId = _string(
    _section('meta'),
    'defaultAccent',
  );

  /// `themes.<id>.polarity == 'dark'`.
  bool isDarkTheme(String themeId) => _polarity(themeId) == 'dark';

  /// `themes.<id>.labelTr`.
  String themeLabel(String themeId) => _string(_theme(themeId), 'labelTr');

  /// `accents.<id>.labelTr`.
  String accentLabel(String accentId) => _string(_accent(accentId), 'labelTr');

  /// The stored colour of a role, as the file spells it (`#rrggbb`).
  ///
  /// Only roles a theme stores directly are present; the derived ones belong to
  /// whichever accent the file happened to cache.
  String roleHex(String themeId, String role) => _string(_theme(themeId), role);

  /// `themes.<id>.derive.<key>` as a number.
  double deriveNumber(String themeId, String key) =>
      _number(_derive(themeId), key);

  /// `themes.<id>.derive.<key>` as a colour string.
  String deriveHex(String themeId, String key) =>
      _string(_derive(themeId), key);

  /// The `contrast` list, as the requirements the resolver must satisfy.
  late final List<ContrastRequirement> contrastRequirements = _contrastList();

  /// The `contrast` list exactly as the file spells it, for a test that wants
  /// to know a pair was not quietly deleted.
  late final List<ContrastPair> contrastPairs = _contrastListRaw();

  /// The generator's own colour type for a stored hex.
  Rgb rgb(String hex) {
    final Rgb? parsed = tryParseColor(hex);
    if (parsed == null) throw StateError('Not a colour in $path: $hex');
    return parsed;
  }

  /// The colour a derived role must have, computed by the GENERATOR's mixing
  /// rule. `from` and `to` are stored hexes, [amount] the file's own mix.
  Rgb mixed(String fromHex, String toHex, double amount) =>
      Rgb.mix(rgb(fromHex), rgb(toHex), amount);

  /// The `accentSoft` a theme and accent must produce, per `meta.sources`.
  Rgb accentSoftFor(String themeId, String accentId) => mixed(
    accentHex(accentId, 'base'),
    roleHex(themeId, 'surface'),
    deriveNumber(themeId, 'accentSoftMix'),
  );

  /// The `focusRing` a theme and accent must produce, per `meta.sources`.
  Rgb focusRingFor(String themeId, String accentId) => mixed(
    accentHex(accentId, 'base'),
    deriveHex(themeId, 'focusRingTarget'),
    deriveNumber(themeId, 'focusRingMix'),
  );

  /// `accents.<id>.<key>`, one of base, hover, active, on, soft, focusRing.
  String accentHex(String accentId, String key) =>
      _string(_accent(accentId), key);

  /// `type.steps.<step>.size`.
  double typeSize(String step) => _number(_typeStep(step), 'size');

  /// `type.steps.<step>.weight`, the NAME of a `type.weights` entry.
  String typeWeightName(String step) => _string(_typeStep(step), 'weight');

  /// The number `type.steps.<step>.weight` names in `type.weights`.
  int typeWeight(String step) => _number(
    _child(_section('type'), 'weights'),
    typeWeightName(step),
  ).toInt();

  /// `type.steps.<step>.lineHeight`, named.
  String typeLineHeightName(String step) =>
      _string(_typeStep(step), 'lineHeight');

  /// `type.steps.<step>.tracking`.
  double typeTracking(String step) => _number(_typeStep(step), 'tracking');

  /// `type.fontFamily`.
  List<String> fontFamily() => _stringList(_section('type'), 'fontFamily');

  /// `space.steps.<step>`.
  double spaceStep(String step) => _number(_spaceSteps(), step);

  /// `space.unit`.
  double spaceUnit() => _number(_section('space'), 'unit');

  /// `space.densities.<id>`.
  double density(String id) => _number(_densitySection(), id);

  /// `radius.steps.<step>.scale`, or the fixed value for `pill`.
  double radiusStep(String step) => _number(_radiusStep(step), 'scale');

  /// `radius.steps.pill.value`, which is preset independent.
  double radiusPill() => _number(_radiusStep('pill'), 'value');

  /// The unit of a radius preset, which is the same in both.
  double radiusPresetUnit(String presetId) =>
      _number(_radiusPreset(presetId), 'unit');

  /// The scale of a radius preset.
  double radiusPresetScale(String presetId) =>
      _number(_radiusPreset(presetId), 'scale');

  /// `radius.presets`, in declaration order.
  List<String> radiusPresets() =>
      _keysOf(_child(_section('radius'), 'presets'));

  /// `control.sizes.<size>.height`.
  double controlHeight(String size) => _number(_controlSize(size), 'height');

  /// `control.sizes.<size>.paddingX`.
  double controlPaddingX(String size) =>
      _number(_controlSize(size), 'paddingX');

  /// `control.sizes.<size>.gap`.
  double controlGap(String size) => _number(_controlSize(size), 'gap');

  /// `control.sizes.<size>.fontSize`.
  double controlFontSize(String size) =>
      _number(_controlSize(size), 'fontSize');

  /// `control.sizes.<size>.iconSize`.
  double controlIconSize(String size) =>
      _number(_controlSize(size), 'iconSize');

  /// `control.hitTargetMin`.
  double hitTargetMin() => _number(_section('control'), 'hitTargetMin');

  /// `control.borderWidth`.
  double borderWidth() => _number(_section('control'), 'borderWidth');

  /// `control.focusRingWidth`.
  double focusRingWidth() => _number(_section('control'), 'focusRingWidth');

  /// `control.focusRingGap`.
  double focusRingGap() => _number(_section('control'), 'focusRingGap');

  /// `control.densityScale`.
  bool controlDensityScale() => _bool(_section('control'), 'densityScale');

  /// `motion.durations.<name>` in milliseconds.
  int motionDuration(String name) => _number(_motionDurations(), name).toInt();

  /// `motion.durations`, in declaration order.
  List<String> motionNames() =>
      _keysOf(_child(_section('motion'), 'durations'));

  /// The string keys of a JSON object, in declaration order.
  static List<String> _keysOf(Map<Object?, Object?> map) =>
      map.keys.whereType<String>().toList(growable: false);

  // --- loading ---------------------------------------------------------------

  /// Reads `design/tokens.json` by walking up from the current directory.
  ///
  /// `flutter test` runs with the package root as the working directory, and the
  /// token file is a sibling of it; the walk makes the test independent of
  /// where it was started from.
  static TokenFile load() {
    Directory directory = Directory.current;
    for (int depth = 0; depth < 6; depth += 1) {
      final File candidate = File(
        '${directory.path}${Platform.pathSeparator}design'
        '${Platform.pathSeparator}tokens.json',
      );
      if (candidate.existsSync()) {
        final Object? decoded =
            jsonDecode(candidate.readAsStringSync()) as Object?;
        if (decoded is! Map) {
          throw StateError('${candidate.path} is not a JSON object.');
        }
        return TokenFile._(decoded, candidate.path);
      }
      final Directory parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    throw StateError(
      'design/tokens.json not found above ${Directory.current.path}',
    );
  }

  // --- typed access ----------------------------------------------------------

  Map<Object?, Object?> _section(String key) {
    final Object? value = _root[key];
    if (value is! Map) throw StateError('No section "$key" in $path');
    return value;
  }

  Map<Object?, Object?> _theme(String themeId) =>
      _child(_section('themes'), themeId);

  Map<Object?, Object?> _accent(String accentId) =>
      _child(_section('accents'), accentId);

  Map<Object?, Object?> _derive(String themeId) =>
      _child(_theme(themeId), 'derive');

  String _polarity(String themeId) => _string(_theme(themeId), 'polarity');

  Map<Object?, Object?> _typeStep(String step) =>
      _child(_child(_section('type'), 'steps'), step);

  Map<Object?, Object?> _spaceSteps() => _child(_section('space'), 'steps');

  Map<Object?, Object?> _densitySection() =>
      _child(_section('space'), 'densities');

  Map<Object?, Object?> _radiusStep(String step) =>
      _child(_child(_section('radius'), 'steps'), step);

  Map<Object?, Object?> _radiusPreset(String presetId) =>
      _child(_child(_section('radius'), 'presets'), presetId);

  Map<Object?, Object?> _controlSize(String size) =>
      _child(_child(_section('control'), 'sizes'), size);

  Map<Object?, Object?> _motionDurations() =>
      _child(_section('motion'), 'durations');

  Map<Object?, Object?> _child(Map<Object?, Object?> parent, String key) {
    final Object? value = parent[key];
    if (value is! Map) throw StateError('No object at "$key" in $path');
    return value;
  }

  List<ContrastRequirement> _contrastList() {
    return <ContrastRequirement>[
      for (final ContrastPair pair in contrastPairs)
        ContrastRequirement(
          foregroundRole: pair.fg,
          backgroundRole: pair.bg,
          minimum: pair.min,
        ),
    ];
  }

  List<ContrastPair> _contrastListRaw() {
    final Object? value = _root['contrast'];
    if (value is! List) throw StateError('No "contrast" list in $path');
    return <ContrastPair>[
      for (final Object? entry in value)
        if (entry is Map)
          ContrastPair(
            _string(entry, 'fg'),
            _string(entry, 'bg'),
            _number(entry, 'min'),
          ),
    ];
  }

  static String _string(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is String) return value;
    throw StateError('"${map['id'] ?? key}" is not a string in the token file');
  }

  static double _number(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is num) return value.toDouble();
    throw StateError('"$key" is not a number in the token file');
  }

  static bool _bool(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is bool) return value;
    throw StateError('"$key" is not a boolean in the token file');
  }

  static List<String> _stringList(Map<Object?, Object?> map, String key) {
    final Object? value = map[key];
    if (value is! List) {
      throw StateError('"$key" is not a list in the token file');
    }
    return <String>[for (final Object? item in value) item! as String];
  }
}
