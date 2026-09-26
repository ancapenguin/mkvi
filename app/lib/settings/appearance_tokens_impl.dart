/// The one implementation of [AppearanceTokens], over the compiled token file.
///
/// ## Why this file exists at all
///
/// [AppearanceTokens] is an INTERFACE, and an interface needs one real
/// implementation. Until the design package became a library, that
/// implementation had nowhere in production to live: the generated token file
/// sat in `design/generated/`, outside `lib/`, so no library under `app/lib/`
/// could import it. The interface's only implementation therefore ended up in
/// `app/test/settings/support/design_bridge.dart` - production code had no token
/// implementation, and the tests were standing in for one.
///
/// `mkvi_design` is now a path dependency, so the tokens are a normal import
/// and this file is that implementation, in `lib/`, where production code can
/// reach it.
///
/// ## Why `TokenFile` is dead
///
/// The old bridge covered a real gap: the generated file baked the `derive`
/// amounts, the theme polarities and the `contrast` list into colours, so the
/// bridge read `design/tokens.json` off disk to get them back. That is what
/// made it test-only code: `dart:io` and a file read cannot sit on a production
/// path in a packaged app, which has no `design/tokens.json` next to it and
/// would throw at the first frame instead of at build time.
///
/// The generator now exports all of it - `mkviThemeMeta` for polarity and the
/// three derive amounts, `mkviContrastRequirements` for the gate - so the disk
/// read is gone rather than moved. This file contains no `dart:io` import and
/// no path: every value below arrives as a compile-time constant, which is also
/// why it can be `const`.
///
/// ## What it does not do
///
/// It resolves nothing. Font scale, density, high contrast and a custom
/// accent are [AppearanceResolver]'s arithmetic; this file only says what the
/// token file contains. A value that is not in `tokens.json` has no way to
/// appear here.
library;

import 'dart:ui' show Color;

import 'package:flutter/animation.dart' show Cubic;
import 'package:mkvi_design/mkvi_design.dart';
import 'package:mkvi/settings/design_tokens.dart';

/// [AppearanceTokens] over the generated token file.
final class DesignTokens implements AppearanceTokens {
  const DesignTokens();

  // --- identity -------------------------------------------------------------

  @override
  List<String> get themeIds => MkviThemeId.values
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
  bool isDarkTheme(String themeId) => _meta(themeId).isDark;

  @override
  String themeLabel(String themeId) => mkviThemeLabelsTr[_theme(themeId)]!;

  @override
  String accentLabel(String accentId) => mkviAccentLabelsTr[_accent(accentId)]!;

  // --- one resolved (theme, accent) pair ------------------------------------

  @override
  Set<String> get roleNames =>
      MkviRole.values.map((MkviRole role) => role.name).toSet();

  @override
  Map<String, Color> rolesFor(String themeId, String accentId) {
    final MkviTokens tokens = mkviTokensFor(_theme(themeId), _accent(accentId));
    final Map<String, Color> roles = <String, Color>{};
    for (final String name in roleNames) {
      final MkviRole? role = _rolesByName[name];
      // Unreachable through a correctly generated file, because [roleNames] and
      // the enum are emitted from the same `meta.roles` list. It stays because a
      // token set missing a role must be a loud failure, never a silent fallback
      // to another theme's colour - and this is the one place that promise is
      // kept on the production path.
      if (role == null) {
        throw StateError(
          'Token set ${tokens.themeId.name}/${tokens.accentId.name} has no '
          'role "$name". The generated token file is inconsistent with '
          'meta.roles; re-run design/tool/generate_tokens.dart.',
        );
      }
      roles[name] = tokens.role(role);
    }
    return roles;
  }

  // --- derivation data for a CUSTOM accent ----------------------------------

  @override
  Color focusRingTargetFor(String themeId) => _meta(themeId).focusRingTarget;

  @override
  double focusRingMixFor(String themeId) => _meta(themeId).focusRingMix;

  @override
  double accentSoftMixFor(String themeId) => _meta(themeId).accentSoftMix;

  // --- the accessibility gate, as data --------------------------------------

  @override
  List<ContrastRequirement> get contrastRequirements =>
      <ContrastRequirement>[
        for (final MkviContrastRequirement requirement
            in mkviContrastRequirements)
          ContrastRequirement(
            foregroundRole: requirement.foregroundRole,
            backgroundRole: requirement.backgroundRole,
            minimum: requirement.minimum,
          ),
      ];

  // --- type -----------------------------------------------------------------

  @override
  String? get fontFamily =>
      mkviType.family.isEmpty ? null : mkviType.family.first;

  @override
  List<String> get fontFamilyFallback => mkviType.family.length < 2
      ? const <String>[]
      : mkviType.family.sublist(1);

  @override
  Map<String, TypeStepMetrics> get typeScale => <String, TypeStepMetrics>{
    for (final MapEntry<String, MkviTypeStep> step in mkviType.steps.entries)
      step.key: TypeStepMetrics(
        size: step.value.size,
        lineHeight: step.value.height,
        weight: step.value.weight.value,
        tracking: step.value.tracking,
      ),
  };

  // --- space ----------------------------------------------------------------

  @override
  double get spaceUnit => mkviSpacing.unit;

  @override
  Map<String, double> get spaceSteps =>
      Map<String, double>.of(mkviSpacing.steps);

  @override
  Map<String, double> get densities => Map<String, double>.of(mkviDensities);

  // --- radius ---------------------------------------------------------------

  @override
  List<String> get radiusPresets => mkviRadiusPresets;

  @override
  Map<String, double> radiiFor(String presetId) =>
      mkviRadiusSteps(mkviRadiiFor(presetId));

  // --- controls -------------------------------------------------------------

  @override
  Map<String, ControlMetrics> get controlSizes => <String, ControlMetrics>{
    for (final MapEntry<String, MkviControlSize> size
        in mkviControlSizes().entries)
      size.key: ControlMetrics(
        height: size.value.height,
        paddingX: size.value.paddingX,
        gap: size.value.gap,
        fontSize: size.value.fontSize,
        iconSize: size.value.iconSize,
      ),
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

  // --- motion ---------------------------------------------------------------

  @override
  Map<String, Duration> get motionDurations =>
      Map<String, Duration>.of(mkviMotionDurations);

  @override
  Cubic get motionEasing => mkviMotion.easing;

  // --- lookups --------------------------------------------------------------
  //
  // An id the token file does not declare is an [ArgumentError]: the caller
  // asked for a theme that does not exist. A token set that is missing a role
  // it declared is a [StateError]: the file is broken. The two are different
  // faults and get different exception types.

  static final Map<String, MkviRole> _rolesByName = <String, MkviRole>{
    for (final MkviRole role in MkviRole.values) role.name: role,
  };

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

  static MkviThemeMeta _meta(String themeId) =>
      mkviThemeMeta[_theme(themeId)]!;
}
