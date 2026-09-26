import 'dart:ui' show Color;
import 'package:flutter/animation.dart' show Cubic;
import '../../../../design/generated/tokens.g.dart';
import 'package:mkvi/settings/contrast.dart';
import 'package:mkvi/settings/design_tokens.dart';
import 'tokens_file.dart';

/// The one implementation of [AppearanceTokens], over the generated token file.
///
/// This is the wiring the app needs and the only place in the repository where
/// `design/generated/tokens.g.dart` and `design/tokens.json` are both in
/// scope. `app/lib/` cannot import either (see `design_tokens.dart`), so the
/// seam is implemented here, next to the tests that prove it is faithful:
///
/// * every colour comes from the generated `MkviTokens`, i.e. from the token
///   file by way of the generator;
/// * the `derive` amounts, the declared contrast minimums and the theme
///   polarity come from `design/tokens.json`, because the generated file bakes
///   those into colours instead of exposing them;
/// * the Turkish theme and accent names come from the generated maps, which is
///   how they reach the settings catalogue without being retyped.
///
/// `bridge_matches_tokens_json_test.dart` asserts the whole mapping against the
/// file, so this class cannot quietly drift from it.






/// [AppearanceTokens] over the real token file.
final class DesignTokens implements AppearanceTokens {
  DesignTokens(this.file);

  /// The token file, for the parts the generated file does not expose.
  final TokenFile file;

  @override
  List<String> get themeIds => mkviTokensByTheme.keys
      .map((MkviThemeId id) => id.name)
      .toList(growable: false);

  @override
  List<String> get accentIds => MkviAccentId.values
      .map((MkviAccentId id) => id.name)
      .toList(growable: false);

  @override
  String get defaultThemeId => mkviTokensDefault.themeId.name;

  @override
  String get defaultAccentId => mkviTokensDefault.accentId.name;

  @override
  bool isDarkTheme(String themeId) => file.isDarkTheme(themeId);

  @override
  String themeLabel(String themeId) => mkviThemeLabelsTr[_theme(themeId)]!;

  @override
  String accentLabel(String accentId) => mkviAccentLabelsTr[_accent(accentId)]!;

  @override
  Set<String> get roleNames =>
      MkviRole.values.map((MkviRole role) => role.name).toSet();

  @override
  Map<String, Color> rolesFor(String themeId, String accentId) {
    final MkviTokens tokens = mkviTokensFor(_theme(themeId), _accent(accentId));
    return <String, Color>{
      for (final MkviRole role in MkviRole.values) role.name: tokens.role(role),
    };
  }

  @override
  Color focusRingTargetFor(String themeId) =>
      tryParseHexColor(file.deriveHex(themeId, 'focusRingTarget'))!;

  @override
  double focusRingMixFor(String themeId) =>
      file.deriveNumber(themeId, 'focusRingMix');

  @override
  double accentSoftMixFor(String themeId) =>
      file.deriveNumber(themeId, 'accentSoftMix');

  @override
  List<ContrastRequirement> get contrastRequirements =>
      file.contrastRequirements;

  @override
  String? get fontFamily =>
      mkviType.family.isEmpty ? null : mkviType.family.first;

  @override
  List<String> get fontFamilyFallback => mkviType.family.length < 2
      ? const <String>[]
      : mkviType.family.sublist(1);

  @override
  Map<String, TypeStepMetrics> get typeScale => <String, TypeStepMetrics>{
    for (final String step in mkviType.steps.keys)
      step: _metricsOf(mkviType.step(step)),
  };

  @override
  double get spaceUnit => mkviSpacing.unit;

  @override
  Map<String, double> get spaceSteps =>
      Map<String, double>.of(mkviSpacing.steps);

  @override
  Map<String, double> get densities => Map<String, double>.of(mkviDensities);

  @override
  List<String> get radiusPresets => <String>['cozy', 'crisp'];

  @override
  Map<String, double> radiiFor(String presetId) {
    final MkviRadii radii = switch (presetId) {
      'crisp' => mkviRadiiCrisp,
      _ => mkviRadiiCozy,
    };
    return <String, double>{
      'none': radii.none,
      'xs': radii.xs,
      'sm': radii.sm,
      'md': radii.md,
      'lg': radii.lg,
      'xl': radii.xl,
      'pill': radii.pill,
    };
  }

  @override
  Map<String, ControlMetrics> get controlSizes => <String, ControlMetrics>{
    for (final String size in <String>['sm', 'md', 'lg'])
      size: _controlOf(mkviControls.of(size)),
  };

  @override
  bool get controlSizesFollowDensity => mkviControls.densityScale;

  @override
  double get hitTargetMin => mkviControls.hitTargetMin;

  @override
  double get borderWidth => mkviControls.borderWidth;

  @override
  double get focusRingWidth => mkviControls.focusRingWidth;

  @override
  double get focusRingGap => mkviControls.focusRingGap;

  @override
  Map<String, Duration> get motionDurations => <String, Duration>{
    'instant': mkviMotion.instant,
    'fast': mkviMotion.fast,
    'normal': mkviMotion.normal,
    'slow': mkviMotion.slow,
    'deliberate': mkviMotion.deliberate,
  };

  @override
  Cubic get motionEasing => mkviMotion.easing;

  static MkviThemeId _theme(String themeId) {
    for (final MkviThemeId id in MkviThemeId.values) {
      if (id.name == themeId) return id;
    }
    throw ArgumentError.value(themeId, 'themeId', 'Unknown theme');
  }

  static MkviAccentId _accent(String accentId) {
    for (final MkviAccentId id in MkviAccentId.values) {
      if (id.name == accentId) return id;
    }
    throw ArgumentError.value(accentId, 'accentId', 'Unknown accent');
  }

  static TypeStepMetrics _metricsOf(MkviTypeStep step) => TypeStepMetrics(
    size: step.size,
    lineHeight: step.height,
    weight: step.weight.value,
    tracking: step.tracking,
  );

  static ControlMetrics _controlOf(MkviControlSize size) => ControlMetrics(
    height: size.height,
    paddingX: size.paddingX,
    gap: size.gap,
    fontSize: size.fontSize,
    iconSize: size.iconSize,
  );
}



/// The token file and its bridge, loaded once per test run.
final class DesignTokensFixture {
  DesignTokensFixture._(this.file, this.tokens);

  /// The token file.
  final TokenFile file;

  /// The seam implementation.
  final DesignTokens tokens;

  static DesignTokensFixture? _cached;

  /// Loads both, or returns the ones already loaded.
  factory DesignTokensFixture.load() {
    return _cached ??= _load();
  }

  static DesignTokensFixture _load() {
    final TokenFile file = TokenFile.load();
    return DesignTokensFixture._(file, DesignTokens(file));
  }
}

