/// The design-token contract this layer paints from, as an interface.
///
/// ## Why an interface at all
///
/// `design/tokens.json` is the only place a colour, a size, a radius or a
/// duration may be written down, and its compiled form is GENERATED. So the
/// split is: **the design package owns every value, this layer owns the
/// arithmetic and the contract.** [AppearanceTokens] contains no colour, no
/// size, no radius, no duration and not even a magic constant - it is a typed
/// description of what the token file contains.
///
/// The interface buys one thing that a direct import of the generated file
/// would not: the layer above this one can be tested, and reasoned about,
/// without a Flutter binding or a token file on disk. And it buys the error
/// contract: an id the token file does not declare is an [ArgumentError] the
/// caller caused, while a token set missing a role it declared is a
/// [StateError] the file caused. Those are different faults and this layer
/// gives them different types.
///
/// The one implementation is `appearance_tokens_impl.dart`, in `lib/`, and it
/// resolves everything from `package:mkvi_design/mkvi_design.dart`.
///
/// Everything downstream of the interface is resolution, not invention:
/// font scale multiplies a token size, density multiplies a token step,
/// a radius preset selects a token radius, and a custom accent is built with
/// the same `color-mix(in srgb)` arithmetic `design/tool/generate_tokens.dart`
/// uses for `accentSoft` and `focusRing`.
library;

import 'dart:ui' show Color;

import 'package:flutter/animation.dart' show Cubic;

/// One step of the type scale, in token units (before `fontScale`).
final class TypeStepMetrics {
  const TypeStepMetrics({
    required this.size,
    required this.lineHeight,
    required this.weight,
    required this.tracking,
  });

  /// Font size in logical pixels at `fontScale` 1.0.
  final double size;

  /// Line height as a multiple of [size].
  final double lineHeight;

  /// `type.weights.<key>` of the step.
  final int weight;

  /// Letter spacing in logical pixels at `fontScale` 1.0.
  final double tracking;
}

/// One control size, in token units (before `density` and `fontScale`).
final class ControlMetrics {
  const ControlMetrics({
    required this.height,
    required this.paddingX,
    required this.gap,
    required this.fontSize,
    required this.iconSize,
  });

  /// Control height in logical pixels at `density` 1.0.
  final double height;

  /// Horizontal padding in logical pixels at `density` 1.0.
  final double paddingX;

  /// Gap between the leading icon and the label, at `density` 1.0.
  final double gap;

  /// Control font size at `fontScale` 1.0. Never follows `density`: that is a
  /// `control.densityScale` decision in the token file, and this layer obeys
  /// it instead of second-guessing it.
  final double fontSize;

  /// Icon size in logical pixels. Density and font scale independent.
  final double iconSize;
}

/// One declared contrast requirement, from `contrast` in tokens.json.
///
/// The resolver checks every requirement against the FINAL colours it is about
/// to hand to a `ThemeData`, including the ones a high-contrast switch or a
/// custom accent produced. A pair that fails is reported in Turkish, never
/// quietly shipped.
final class ContrastRequirement {
  const ContrastRequirement({
    required this.foregroundRole,
    required this.backgroundRole,
    required this.minimum,
  });

  /// Role name painted on top.
  final String foregroundRole;

  /// Role name painted underneath.
  final String backgroundRole;

  /// The WCAG 2.x ratio the pair must reach.
  final double minimum;

  @override
  bool operator ==(Object other) =>
      other is ContrastRequirement &&
      other.foregroundRole == foregroundRole &&
      other.backgroundRole == backgroundRole &&
      other.minimum == minimum;

  @override
  int get hashCode => Object.hash(foregroundRole, backgroundRole, minimum);

  @override
  String toString() => '$foregroundRole on $backgroundRole >= $minimum';
}

/// The whole token file, as values.
///
/// Every member returns data that came from `design/tokens.json` unchanged.
/// Ids are strings rather than enums for one reason: this layer cannot name
/// the generated `MkviThemeId` / `MkviAccentId`, and a string id is checked
/// against the token file by tests instead of being re-declared here.
abstract interface class AppearanceTokens {
  // --- identity -------------------------------------------------------------

  /// `themes` keys, in declaration order.
  List<String> get themeIds;

  /// `accents` keys, in declaration order.
  List<String> get accentIds;

  /// `meta.defaultTheme`.
  String get defaultThemeId;

  /// `meta.defaultAccent`.
  String get defaultAccentId;

  /// `themes.<id>.polarity == 'dark'`.
  bool isDarkTheme(String themeId);

  /// `themes.<id>.labelTr`, the name the settings screen shows.
  String themeLabel(String themeId);

  /// `accents.<id>.labelTr`.
  String accentLabel(String accentId);

  // --- one resolved (theme, accent) pair ------------------------------------

  /// `meta.roles`: every colour role a token set must define.
  Set<String> get roleNames;

  /// The 29 roles of one (theme, accent) pair, keyed by role name.
  ///
  /// Throws [ArgumentError] when either id is unknown, and
  /// [StateError] when a role is missing: a theme without a role is a build
  /// error in the token system, never a silent fallback to another theme.
  Map<String, Color> rolesFor(String themeId, String accentId);

  // --- derivation data for a CUSTOM accent ----------------------------------

  /// `themes.<id>.derive.focusRingTarget`.
  Color focusRingTargetFor(String themeId);

  /// `themes.<id>.derive.focusRingMix`.
  double focusRingMixFor(String themeId);

  /// `themes.<id>.derive.accentSoftMix`.
  double accentSoftMixFor(String themeId);

  // --- the accessibility gate, as data --------------------------------------

  /// The `contrast` list: every pair that must clear a declared minimum.
  List<ContrastRequirement> get contrastRequirements;

  // --- type -----------------------------------------------------------------

  /// `type.fontFamily`, most specific first. Null when the token file declares
  /// no family, in which case the platform default is used.
  String? get fontFamily;

  /// `type.fontFamily` minus the first entry.
  List<String> get fontFamilyFallback;

  /// `type.steps`, keyed by token name ('2xs' .. '2xl'), at font scale 1.0.
  Map<String, TypeStepMetrics> get typeScale;

  // --- space ----------------------------------------------------------------

  /// `space.unit`, the base step in logical pixels.
  double get spaceUnit;

  /// `space.steps`, keyed by token name ('0' .. '10'), at density 1.0.
  Map<String, double> get spaceSteps;

  /// `space.densities`, keyed by token name ('compact', 'cozy', 'roomy').
  Map<String, double> get densities;

  // --- radius ---------------------------------------------------------------

  /// `radius.presets`, in declaration order.
  List<String> get radiusPresets;

  /// `radius.steps` of one preset, keyed by token name ('none' .. 'pill').
  Map<String, double> radiiFor(String presetId);

  // --- controls -------------------------------------------------------------

  /// `control.sizes`, keyed by token name ('sm', 'md', 'lg'), at density 1.0.
  Map<String, ControlMetrics> get controlSizes;

  /// `control.densityScale`. When false the resolver must not scale heights.
  bool get controlSizesFollowDensity;

  /// `control.hitTargetMin`. Never scaled: a pointer target is a physical
  /// promise, not a style.
  double get hitTargetMin;

  /// `control.borderWidth`.
  double get borderWidth;

  /// `control.focusRingWidth`.
  double get focusRingWidth;

  /// `control.focusRingGap`.
  double get focusRingGap;

  // --- motion ---------------------------------------------------------------

  /// `motion.durations`, keyed by token name.
  Map<String, Duration> get motionDurations;

  /// `motion.easing.cubic`.
  Cubic get motionEasing;
}
