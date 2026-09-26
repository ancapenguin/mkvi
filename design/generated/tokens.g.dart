// GENERATED CODE - DO NOT EDIT BY HAND.
//
// Source:    design/tokens.json  (mkvi-design-tokens v1.0.0)
// Generator: design/tool/generate_tokens.dart
// Gate:      cd design && dart pub get && dart test
//
// 29 colour roles x 4 themes x 4 accents = 16 immutable token sets.
// Roles are emitted in meta.roles order.
//
// Written verbatim by the generator and deliberately not `dart format`
// canonical, so the bytes cannot depend on the local SDK formatter.
//
// ignore_for_file: constant_identifier_names, prefer_const_constructors

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The four shipped themes. The Turkish label is what the settings UI shows.
enum MkviThemeId {
  midnight,
  light,
  forest,
  plum,
}

/// The four shipped accents, independent of the theme.
enum MkviAccentId {
  blue,
  teal,
  amber,
  rose,
}

/// Theme names in Turkish, as shown in the appearance settings.
const Map<MkviThemeId, String> mkviThemeLabelsTr = <MkviThemeId, String>{
  MkviThemeId.midnight: 'Gece',
  MkviThemeId.light: 'Açık',
  MkviThemeId.forest: 'Orman',
  MkviThemeId.plum: 'Erik',
};

/// Accent names in Turkish, as shown in the appearance settings.
const Map<MkviAccentId, String> mkviAccentLabelsTr = <MkviAccentId, String>{
  MkviAccentId.blue: 'Mavi',
  MkviAccentId.teal: 'Deniz',
  MkviAccentId.amber: 'Kehribar',
  MkviAccentId.rose: 'Gül',
};

extension MkviThemeIdLabel on MkviThemeId {
  /// Turkish display label for this theme.
  String get labelTr => mkviThemeLabelsTr[this]!;
}

extension MkviAccentIdLabel on MkviAccentId {
  /// Turkish display label for this accent.
  String get labelTr => mkviAccentLabelsTr[this]!;
}

/// Every colour role. A theme MUST define all of them; the token gate
/// fails the build otherwise.
enum MkviRole {
  bg,
  surface,
  surfaceRaised,
  surfaceSoft,
  surfaceOverlay,
  text,
  textMuted,
  textSubtle,
  textOnAccent,
  textOnStage,
  stage,
  border,
  borderStrong,
  accent,
  accentHover,
  accentActive,
  accentSoft,
  focusRing,
  success,
  successSoft,
  warning,
  warningSoft,
  danger,
  dangerFill,
  dangerFillHover,
  scrim,
  shadow1,
  shadow2,
  shadow3,
}

/// One step of the type scale, ready to become a [TextStyle].
class MkviTypeStep {
  const MkviTypeStep({
    required this.size,
    required this.height,
    required this.weight,
    required this.tracking,
  });

  /// Font size in logical pixels.
  final double size;
  /// Line height as a multiple of [size].
  final double height;
  final FontWeight weight;
  /// Letter spacing in logical pixels.
  final double tracking;

  TextStyle style({String? family}) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: tracking,
  );
}

/// The 7-step type scale (2xs -> 2xl) plus the shared line heights and weights.
class MkviTypeScale {
  const MkviTypeScale({
    required this.family,
    required this.monoFamily,
    required this.lineHeights,
    required this.weights,
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
  });

  /// Preferred UI font family, most specific first.
  final List<String> family;
  /// Preferred monospace family for codes, pairing codes and logs.
  final List<String> monoFamily;
  final Map<String, double> lineHeights;
  final Map<String, FontWeight> weights;
  /// Type scale step 2xs.
  final MkviTypeStep xxs;
  /// Type scale step xs.
  final MkviTypeStep xs;
  /// Type scale step sm.
  final MkviTypeStep sm;
  /// Type scale step md.
  final MkviTypeStep md;
  /// Type scale step lg.
  final MkviTypeStep lg;
  /// Type scale step xl.
  final MkviTypeStep xl;
  /// Type scale step 2xl.
  final MkviTypeStep xxl;

  /// Every step, keyed by its token name (2xs, xs, sm, md, lg, xl, 2xl).
  Map<String, MkviTypeStep> get steps => <String, MkviTypeStep>{
    '2xs': xxs,
    'xs': xs,
    'sm': sm,
    'md': md,
    'lg': lg,
    'xl': xl,
    '2xl': xxl,
  };

  MkviTypeStep step(String name) => switch (name) {
    '2xs' => xxs,
    'xs' => xs,
    'sm' => sm,
    'md' => md,
    'lg' => lg,
    'xl' => xl,
    '2xl' => xxl,
    _ => throw ArgumentError.value(name, 'name', 'Unknown type step'),
  };
}

const mkviType = MkviTypeScale(
  family: <String>['Segoe UI Variable', 'Segoe UI', 'system-ui', 'sans-serif'],
  monoFamily: <String>['Cascadia Code', 'Consolas', 'monospace'],
  lineHeights: <String, double>{
    'tight': 1.15,
    'snug': 1.3,
    'normal': 1.45,
    'relaxed': 1.6,
    'loose': 1.75,
  },
  weights: <String, FontWeight>{
    'regular': FontWeight.w400,
    'medium': FontWeight.w500,
    'semibold': FontWeight.w600,
    'bold': FontWeight.w700,
  },
  xxs: MkviTypeStep(
    size: 11,
    height: 1.6,
    weight: FontWeight.w500,
    tracking: 0.4,
  ),
  xs: MkviTypeStep(
    size: 12,
    height: 1.45,
    weight: FontWeight.w400,
    tracking: 0.2,
  ),
  sm: MkviTypeStep(
    size: 13,
    height: 1.45,
    weight: FontWeight.w400,
    tracking: 0.1,
  ),
  md: MkviTypeStep(
    size: 15,
    height: 1.45,
    weight: FontWeight.w400,
    tracking: 0,
  ),
  lg: MkviTypeStep(
    size: 18,
    height: 1.3,
    weight: FontWeight.w500,
    tracking: -0.1,
  ),
  xl: MkviTypeStep(
    size: 22,
    height: 1.3,
    weight: FontWeight.w600,
    tracking: -0.3,
  ),
  xxl: MkviTypeStep(
    size: 30,
    height: 1.15,
    weight: FontWeight.w700,
    tracking: -0.6,
  ),
);

/// 4px-based spacing scale. Every step is `unit * multiplier * density`.
class MkviSpacing {
  const MkviSpacing({
    required this.unit,
    required this.density,
    required this.s0,
    required this.s1,
    required this.s2,
    required this.s3,
    required this.s4,
    required this.s5,
    required this.s6,
    required this.s7,
    required this.s8,
    required this.s9,
    required this.s10,
  });

  /// Base step in logical pixels (4).
  final double unit;
  /// User density multiplier applied to every step.
  final double density;
  /// space.0
  final double s0;
  /// space.1
  final double s1;
  /// space.2
  final double s2;
  /// space.3
  final double s3;
  /// space.4
  final double s4;
  /// space.5
  final double s5;
  /// space.6
  final double s6;
  /// space.7
  final double s7;
  /// space.8
  final double s8;
  /// space.9
  final double s9;
  /// space.10
  final double s10;

  /// Every step, keyed by its token name (0, 1, 2 ...).
  Map<String, double> get steps => <String, double>{
    '0': s0,
    '1': s1,
    '2': s2,
    '3': s3,
    '4': s4,
    '5': s5,
    '6': s6,
    '7': s7,
    '8': s8,
    '9': s9,
    '10': s10,
  };

  double gap(String name) => switch (name) {
    '0' => s0,
    '1' => s1,
    '2' => s2,
    '3' => s3,
    '4' => s4,
    '5' => s5,
    '6' => s6,
    '7' => s7,
    '8' => s8,
    '9' => s9,
    '10' => s10,
    _ => throw ArgumentError.value(name, 'name', 'Unknown space step'),
  };

  /// The same scale at a different density.
  MkviSpacing withDensity(double value) => MkviSpacing(
    unit: unit,
    density: value,
    s0: unit * 0 * value,
    s1: unit * 1 * value,
    s2: unit * 2 * value,
    s3: unit * 3 * value,
    s4: unit * 4 * value,
    s5: unit * 5 * value,
    s6: unit * 6 * value,
    s7: unit * 8 * value,
    s8: unit * 10 * value,
    s9: unit * 12 * value,
    s10: unit * 16 * value,
  );
}

/// The named density presets from tokens.json.
const Map<String, double> mkviDensities = <String, double>{
  'compact': 0.875,
  'cozy': 1,
  'roomy': 1.125,
};

/// The density a fresh token set starts at, from `space.density`.
const double mkviDefaultDensity = 1;

/// The spacing scale at density 1.0. Multiply by density at the call site
/// or use [MkviTokens.spacing].
const mkviSpacing = MkviSpacing(
  unit: 4,
  density: 1.0,
  s0: 0,
  s1: 4,
  s2: 8,
  s3: 12,
  s4: 16,
  s5: 20,
  s6: 24,
  s7: 32,
  s8: 40,
  s9: 48,
  s10: 64,
);

/// Corner radii derived from a single `unit`, so a preset change moves
/// every corner in the app at once.
class MkviRadii {
  const MkviRadii({
    required this.preset,
    required this.unit,
    required this.none,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.pill,
  });

  /// Preset name this instance was built from (cozy, crisp).
  final String preset;
  final double unit;
  /// radius.none
  final double none;
  /// radius.xs
  final double xs;
  /// radius.sm
  final double sm;
  /// radius.md
  final double md;
  /// radius.lg
  final double lg;
  /// radius.xl
  final double xl;
  /// radius.pill
  final double pill;

  MkviRadii scaled(double factor) => MkviRadii(
    preset: 'scaled',
    unit: unit,
    none: 0.0,
    xs: unit * 0.25 * factor,
    sm: unit * 0.5 * factor,
    md: unit * 0.75 * factor,
    lg: unit * 1 * factor,
    xl: unit * 1.5 * factor,
    pill: 999,
  );
}

const mkviRadiiCozy = MkviRadii(
  preset: 'cozy',
  unit: 12,
  none: 0,
  xs: 3,
  sm: 6,
  md: 9,
  lg: 12,
  xl: 18,
  pill: 999,
);
const mkviRadiiCrisp = MkviRadii(
  preset: 'crisp',
  unit: 12,
  none: 0,
  xs: 1.26,
  sm: 2.52,
  md: 3.78,
  lg: 5.04,
  xl: 7.56,
  pill: 999,
);
const mkviRadii = mkviRadiiCozy;

/// Durations and the single easing curve used across the app.
class MkviMotion {
  const MkviMotion({
    required this.easingName,
    required this.easing,
    required this.instant,
    required this.fast,
    required this.normal,
    required this.slow,
    required this.deliberate,
  });

  /// Name of the easing curve ('standard').
  final String easingName;
  /// The one easing curve in the system.
  final Cubic easing;
  /// motion.durations.instant
  final Duration instant;
  /// motion.durations.fast
  final Duration fast;
  /// motion.durations.normal
  final Duration normal;
  /// motion.durations.slow
  final Duration slow;
  /// motion.durations.deliberate
  final Duration deliberate;

  /// Every duration at a different speed (0.5 for twice as fast).
  MkviMotion scaled(double factor) => MkviMotion(
    easingName: easingName,
    easing: easing,
    instant: Duration(microseconds: (instant.inMicroseconds * factor).round()),
    fast: Duration(microseconds: (fast.inMicroseconds * factor).round()),
    normal: Duration(microseconds: (normal.inMicroseconds * factor).round()),
    slow: Duration(microseconds: (slow.inMicroseconds * factor).round()),
    deliberate: Duration(microseconds: (deliberate.inMicroseconds * factor).round()),
  );
}

const mkviMotion = MkviMotion(
  easingName: 'standard',
  easing: Cubic(0.2, 0, 0, 1),
  instant: Duration(milliseconds: 0),
  fast: Duration(milliseconds: 120),
  normal: Duration(milliseconds: 180),
  slow: Duration(milliseconds: 260),
  deliberate: Duration(milliseconds: 420),
);

/// Height, padding and icon size of a control at one of three sizes.
class MkviControlSize {
  const MkviControlSize({
    required this.name,
    required this.height,
    required this.paddingX,
    required this.gap,
    required this.fontSize,
    required this.iconSize,
    required this.radiusStep,
  });

  /// Size name (sm, md, lg).
  final String name;
  /// Control height in logical pixels, already density-scaled.
  final double height;
  final double paddingX;
  final double gap;
  final double fontSize;
  final double iconSize;
  /// Key into [MkviRadii] for this control's corner radius.
  final String radiusStep;
}

/// Control sizes for the three sizes, at one density.
class MkviControls {
  const MkviControls({
    required this.density,
    required this.densityScale,
    required this.hitTargetMin,
    required this.borderWidth,
    required this.focusRingWidth,
    required this.focusRingGap,
    required this.sm,
    required this.md,
    required this.lg,
  });

  final double density;
  /// Whether heights and paddings follow [density]. Font sizes never do.
  final bool densityScale;
  /// Minimum pointer target, never scaled: 44px.
  final double hitTargetMin;
  final double borderWidth;
  final double focusRingWidth;
  final double focusRingGap;
  final MkviControlSize sm;
  final MkviControlSize md;
  final MkviControlSize lg;

  MkviControlSize of(String name) => switch (name) {
    'sm' => sm,
    'md' => md,
    'lg' => lg,
    _ => throw ArgumentError.value(name, 'name', 'Unknown control size'),
  };
}

/// Canonical control sizes at density 1.0.
const mkviControls = MkviControls(
  density: 1.0,
  densityScale: true,
  hitTargetMin: 44,
  borderWidth: 1,
  focusRingWidth: 2,
  focusRingGap: 2,
  sm: MkviControlSize(
    name: 'sm',
    height: 28,
    paddingX: 10,
    gap: 6,
    fontSize: 13,
    iconSize: 16,
    radiusStep: 'sm',
  ),
  md: MkviControlSize(
    name: 'md',
    height: 34,
    paddingX: 12,
    gap: 8,
    fontSize: 15,
    iconSize: 18,
    radiusStep: 'md',
  ),
  lg: MkviControlSize(
    name: 'lg',
    height: 42,
    paddingX: 16,
    gap: 10,
    fontSize: 15,
    iconSize: 20,
    radiusStep: 'lg',
  ),
);

/// The design tokens for one (theme, accent) pair.
///
/// Every field is a role from `meta.roles`. Nothing in the app may
/// hard-code a colour; read it from here via
/// `Theme.of(context).extension<MkviTokens>()!`.
@immutable
class MkviTokens extends ThemeExtension<MkviTokens> {
  const MkviTokens({
    required this.themeId,
    required this.accentId,
    this.density = mkviDefaultDensity,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSoft,
    required this.surfaceOverlay,
    required this.text,
    required this.textMuted,
    required this.textSubtle,
    required this.textOnAccent,
    required this.textOnStage,
    required this.stage,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentHover,
    required this.accentActive,
    required this.accentSoft,
    required this.focusRing,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerFill,
    required this.dangerFillHover,
    required this.scrim,
    required this.shadow1,
    required this.shadow2,
    required this.shadow3,
  });

  /// Which theme these colours were resolved for.
  final MkviThemeId themeId;
  /// Which accent these colours were resolved for.
  final MkviAccentId accentId;
  /// User density multiplier, applied to spacing and control sizes.
  final double density;
  /// Window background behind every panel.
  final Color bg;
  /// Default card, panel and list background. Text is measured against this.
  final Color surface;
  /// Cards, popovers, menus and anything that must read as lifted.
  final Color surfaceRaised;
  /// Inset wells: input fields, hovered rows, code blocks, empty states.
  final Color surfaceSoft;
  /// Top-most floating layer: command palette, dialog, tooltip.
  final Color surfaceOverlay;
  /// Primary text and icons. 7:1 minimum everywhere.
  final Color text;
  /// Secondary text, labels, helper copy.
  final Color textMuted;
  /// Tertiary text: placeholders, timestamps, disabled controls. 4.5:1 floor.
  final Color textSubtle;
  /// Text and icons on `accent`, `accentHover`, `accentActive`, `dangerFill`.
  final Color textOnAccent;
  /// Text on the always-dark media/call stage.
  final Color textOnStage;
  /// Video, screen-share and call surfaces. Always dark, in every theme.
  final Color stage;
  /// Structural outline and separator. 3:1 on every surface.
  final Color border;
  /// Outline for controls that must be unmistakable: inputs, focusable rows.
  final Color borderStrong;
  /// Primary action fill, selection, active nav marker.
  final Color accent;
  /// Primary action fill under the pointer.
  final Color accentHover;
  /// Primary action fill while pressed or selected.
  final Color accentActive;
  /// Tinted background for selected rows, chips and badges. Text on it is `text`.
  final Color accentSoft;
  /// Keyboard focus outline. Must differ from `accent` and clear 3:1 against it.
  final Color focusRing;
  /// Positive status text and icon.
  final Color success;
  /// Positive status background.
  final Color successSoft;
  /// Caution status text and icon.
  final Color warning;
  /// Caution status background.
  final Color warningSoft;
  /// Destructive text, icon and outline.
  final Color danger;
  /// Destructive fill, e.g. hang up. Takes `textOnAccent`.
  final Color dangerFill;
  /// Destructive fill under the pointer.
  final Color dangerFillHover;
  /// Modal scrim laid over content.
  final Color scrim;
  /// Elevation 1: resting cards, list rows.
  final Color shadow1;
  /// Elevation 2: hovered cards, raised controls, sticky bars.
  final Color shadow2;
  /// Elevation 3: popovers, menus, dialogs.
  final Color shadow3;

  /// Type scale. Density independent. Not named `type`, because
  /// [ThemeExtension] already defines a `type` getter.
  static const MkviTypeScale typeScale = mkviType;

  /// Corner radii. Density independent.
  static const MkviRadii radii = mkviRadii;

  /// Durations and easing. Density independent.
  static const MkviMotion motion = mkviMotion;

  /// Spacing at this instance's density.
  MkviSpacing get spacing => mkviSpacing.withDensity(density);

  /// Control sizes at this instance's density.
  MkviControls get controls => controlsAt(density);

  /// Control sizes for an arbitrary density. Height, padding and gap
  /// follow the density; font and icon sizes do not.
  static MkviControls controlsAt(double value) {
    final double scale = mkviControls.densityScale ? value : 1.0;
    return MkviControls(
      density: value,
      densityScale: mkviControls.densityScale,
      hitTargetMin: mkviControls.hitTargetMin,
      borderWidth: mkviControls.borderWidth,
      focusRingWidth: mkviControls.focusRingWidth,
      focusRingGap: mkviControls.focusRingGap,
      sm: MkviControlSize(
        name: 'sm',
        height: mkviControls.sm.height * scale,
        paddingX: mkviControls.sm.paddingX * scale,
        gap: mkviControls.sm.gap * scale,
        fontSize: mkviControls.sm.fontSize,
        iconSize: mkviControls.sm.iconSize,
        radiusStep: mkviControls.sm.radiusStep,
      ),
      md: MkviControlSize(
        name: 'md',
        height: mkviControls.md.height * scale,
        paddingX: mkviControls.md.paddingX * scale,
        gap: mkviControls.md.gap * scale,
        fontSize: mkviControls.md.fontSize,
        iconSize: mkviControls.md.iconSize,
        radiusStep: mkviControls.md.radiusStep,
      ),
      lg: MkviControlSize(
        name: 'lg',
        height: mkviControls.lg.height * scale,
        paddingX: mkviControls.lg.paddingX * scale,
        gap: mkviControls.lg.gap * scale,
        fontSize: mkviControls.lg.fontSize,
        iconSize: mkviControls.lg.iconSize,
        radiusStep: mkviControls.lg.radiusStep,
      ),
    );
  }

  /// The same colours at a different density.
  MkviTokens withDensity(double value) => MkviTokens(
    themeId: themeId,
    accentId: accentId,
    density: value,
    bg: bg,
    surface: surface,
    surfaceRaised: surfaceRaised,
    surfaceSoft: surfaceSoft,
    surfaceOverlay: surfaceOverlay,
    text: text,
    textMuted: textMuted,
    textSubtle: textSubtle,
    textOnAccent: textOnAccent,
    textOnStage: textOnStage,
    stage: stage,
    border: border,
    borderStrong: borderStrong,
    accent: accent,
    accentHover: accentHover,
    accentActive: accentActive,
    accentSoft: accentSoft,
    focusRing: focusRing,
    success: success,
    successSoft: successSoft,
    warning: warning,
    warningSoft: warningSoft,
    danger: danger,
    dangerFill: dangerFill,
    dangerFillHover: dangerFillHover,
    scrim: scrim,
    shadow1: shadow1,
    shadow2: shadow2,
    shadow3: shadow3,
  );

  /// Resolved value of any role, for tooling and debug overlays.
  Color role(MkviRole role) => switch (role) {
    MkviRole.bg => bg,
    MkviRole.surface => surface,
    MkviRole.surfaceRaised => surfaceRaised,
    MkviRole.surfaceSoft => surfaceSoft,
    MkviRole.surfaceOverlay => surfaceOverlay,
    MkviRole.text => text,
    MkviRole.textMuted => textMuted,
    MkviRole.textSubtle => textSubtle,
    MkviRole.textOnAccent => textOnAccent,
    MkviRole.textOnStage => textOnStage,
    MkviRole.stage => stage,
    MkviRole.border => border,
    MkviRole.borderStrong => borderStrong,
    MkviRole.accent => accent,
    MkviRole.accentHover => accentHover,
    MkviRole.accentActive => accentActive,
    MkviRole.accentSoft => accentSoft,
    MkviRole.focusRing => focusRing,
    MkviRole.success => success,
    MkviRole.successSoft => successSoft,
    MkviRole.warning => warning,
    MkviRole.warningSoft => warningSoft,
    MkviRole.danger => danger,
    MkviRole.dangerFill => dangerFill,
    MkviRole.dangerFillHover => dangerFillHover,
    MkviRole.scrim => scrim,
    MkviRole.shadow1 => shadow1,
    MkviRole.shadow2 => shadow2,
    MkviRole.shadow3 => shadow3,
  };

  @override
  MkviTokens copyWith({
    MkviThemeId? themeId,
    MkviAccentId? accentId,
    double? density,
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSoft,
    Color? surfaceOverlay,
    Color? text,
    Color? textMuted,
    Color? textSubtle,
    Color? textOnAccent,
    Color? textOnStage,
    Color? stage,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? accentHover,
    Color? accentActive,
    Color? accentSoft,
    Color? focusRing,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerFill,
    Color? dangerFillHover,
    Color? scrim,
    Color? shadow1,
    Color? shadow2,
    Color? shadow3,
  }) {
    return MkviTokens(
      themeId: themeId ?? this.themeId,
      accentId: accentId ?? this.accentId,
      density: density ?? this.density,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textSubtle: textSubtle ?? this.textSubtle,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      textOnStage: textOnStage ?? this.textOnStage,
      stage: stage ?? this.stage,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentActive: accentActive ?? this.accentActive,
      accentSoft: accentSoft ?? this.accentSoft,
      focusRing: focusRing ?? this.focusRing,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerFill: dangerFill ?? this.dangerFill,
      dangerFillHover: dangerFillHover ?? this.dangerFillHover,
      scrim: scrim ?? this.scrim,
      shadow1: shadow1 ?? this.shadow1,
      shadow2: shadow2 ?? this.shadow2,
      shadow3: shadow3 ?? this.shadow3,
    );
  }

  @override
  MkviTokens lerp(MkviTokens? other, double t) {
    if (other is! MkviTokens) return this;
    return MkviTokens(
      themeId: t < 0.5 ? themeId : other.themeId,
      accentId: t < 0.5 ? accentId : other.accentId,
      density: lerpDouble(density, other.density, t) ?? density,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSubtle: Color.lerp(textSubtle, other.textSubtle, t)!,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t)!,
      textOnStage: Color.lerp(textOnStage, other.textOnStage, t)!,
      stage: Color.lerp(stage, other.stage, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentActive: Color.lerp(accentActive, other.accentActive, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerFill: Color.lerp(dangerFill, other.dangerFill, t)!,
      dangerFillHover: Color.lerp(dangerFillHover, other.dangerFillHover, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      shadow1: Color.lerp(shadow1, other.shadow1, t)!,
      shadow2: Color.lerp(shadow2, other.shadow2, t)!,
      shadow3: Color.lerp(shadow3, other.shadow3, t)!,
    );
  }

  @override
  String toString() =>
      'MkviTokens(${themeId.name}/${accentId.name}, density: $density)';
}

/// midnight theme, blue accent.
const mkviMidnightBlue = MkviTokens(
  themeId: MkviThemeId.midnight,
  accentId: MkviAccentId.blue,
  bg: Color(0xFF0D1117), // bg (midnight/blue, theme)
  surface: Color(0xFF131A24), // surface (midnight/blue, theme)
  surfaceRaised: Color(0xFF1A2330), // surfaceRaised (midnight/blue, theme)
  surfaceSoft: Color(0xFF212C3C), // surfaceSoft (midnight/blue, theme)
  surfaceOverlay: Color(0xFF18212D), // surfaceOverlay (midnight/blue, theme)
  text: Color(0xFFF2F6FB), // text (midnight/blue, theme)
  textMuted: Color(0xFFB6C2D2), // textMuted (midnight/blue, theme)
  textSubtle: Color(0xFF93A1B5), // textSubtle (midnight/blue, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (midnight/blue, derived)
  textOnStage: Color(0xFFEEF4FB), // textOnStage (midnight/blue, theme)
  stage: Color(0xFF080B10), // stage (midnight/blue, theme)
  border: Color(0xFF7B8698), // border (midnight/blue, theme)
  borderStrong: Color(0xFF9AA7B8), // borderStrong (midnight/blue, theme)
  accent: Color(0xFF2665EF), // accent (midnight/blue, derived)
  accentHover: Color(0xFF2768F8), // accentHover (midnight/blue, derived)
  accentActive: Color(0xFF1D4DB8), // accentActive (midnight/blue, derived)
  accentSoft: Color(0xFF1D408A), // accentSoft (midnight/blue, derived)
  focusRing: Color(0xFFC9D9F9), // focusRing (midnight/blue, derived)
  success: Color(0xFF4ADE80), // success (midnight/blue, theme)
  successSoft: Color(0xFF14301F), // successSoft (midnight/blue, theme)
  warning: Color(0xFFFBBF24), // warning (midnight/blue, theme)
  warningSoft: Color(0xFF33280A), // warningSoft (midnight/blue, theme)
  danger: Color(0xFFF87171), // danger (midnight/blue, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (midnight/blue, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (midnight/blue, theme)
  scrim: Color(0xB804070A), // scrim (midnight/blue, theme)
  shadow1: Color(0x33000000), // shadow1 (midnight/blue, theme)
  shadow2: Color(0x59000000), // shadow2 (midnight/blue, theme)
  shadow3: Color(0x8C000000), // shadow3 (midnight/blue, theme)
);

/// midnight theme, teal accent.
const mkviMidnightTeal = MkviTokens(
  themeId: MkviThemeId.midnight,
  accentId: MkviAccentId.teal,
  bg: Color(0xFF0D1117), // bg (midnight/teal, theme)
  surface: Color(0xFF131A24), // surface (midnight/teal, theme)
  surfaceRaised: Color(0xFF1A2330), // surfaceRaised (midnight/teal, theme)
  surfaceSoft: Color(0xFF212C3C), // surfaceSoft (midnight/teal, theme)
  surfaceOverlay: Color(0xFF18212D), // surfaceOverlay (midnight/teal, theme)
  text: Color(0xFFF2F6FB), // text (midnight/teal, theme)
  textMuted: Color(0xFFB6C2D2), // textMuted (midnight/teal, theme)
  textSubtle: Color(0xFF93A1B5), // textSubtle (midnight/teal, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (midnight/teal, derived)
  textOnStage: Color(0xFFEEF4FB), // textOnStage (midnight/teal, theme)
  stage: Color(0xFF080B10), // stage (midnight/teal, theme)
  border: Color(0xFF7B8698), // border (midnight/teal, theme)
  borderStrong: Color(0xFF9AA7B8), // borderStrong (midnight/teal, theme)
  accent: Color(0xFF107D74), // accent (midnight/teal, derived)
  accentHover: Color(0xFF108178), // accentHover (midnight/teal, derived)
  accentActive: Color(0xFF0C5F59), // accentActive (midnight/teal, derived)
  accentSoft: Color(0xFF124C4C), // accentSoft (midnight/teal, derived)
  focusRing: Color(0xFFC5DEE0), // focusRing (midnight/teal, derived)
  success: Color(0xFF4ADE80), // success (midnight/teal, theme)
  successSoft: Color(0xFF14301F), // successSoft (midnight/teal, theme)
  warning: Color(0xFFFBBF24), // warning (midnight/teal, theme)
  warningSoft: Color(0xFF33280A), // warningSoft (midnight/teal, theme)
  danger: Color(0xFFF87171), // danger (midnight/teal, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (midnight/teal, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (midnight/teal, theme)
  scrim: Color(0xB804070A), // scrim (midnight/teal, theme)
  shadow1: Color(0x33000000), // shadow1 (midnight/teal, theme)
  shadow2: Color(0x59000000), // shadow2 (midnight/teal, theme)
  shadow3: Color(0x8C000000), // shadow3 (midnight/teal, theme)
);

/// midnight theme, amber accent.
const mkviMidnightAmber = MkviTokens(
  themeId: MkviThemeId.midnight,
  accentId: MkviAccentId.amber,
  bg: Color(0xFF0D1117), // bg (midnight/amber, theme)
  surface: Color(0xFF131A24), // surface (midnight/amber, theme)
  surfaceRaised: Color(0xFF1A2330), // surfaceRaised (midnight/amber, theme)
  surfaceSoft: Color(0xFF212C3C), // surfaceSoft (midnight/amber, theme)
  surfaceOverlay: Color(0xFF18212D), // surfaceOverlay (midnight/amber, theme)
  text: Color(0xFFF2F6FB), // text (midnight/amber, theme)
  textMuted: Color(0xFFB6C2D2), // textMuted (midnight/amber, theme)
  textSubtle: Color(0xFF93A1B5), // textSubtle (midnight/amber, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (midnight/amber, derived)
  textOnStage: Color(0xFFEEF4FB), // textOnStage (midnight/amber, theme)
  stage: Color(0xFF080B10), // stage (midnight/amber, theme)
  border: Color(0xFF7B8698), // border (midnight/amber, theme)
  borderStrong: Color(0xFF9AA7B8), // borderStrong (midnight/amber, theme)
  accent: Color(0xFFB45309), // accent (midnight/amber, derived)
  accentHover: Color(0xFFB95609), // accentHover (midnight/amber, derived)
  accentActive: Color(0xFF8A4007), // accentActive (midnight/amber, derived)
  accentSoft: Color(0xFF643717), // accentSoft (midnight/amber, derived)
  focusRing: Color(0xFFE6D5CB), // focusRing (midnight/amber, derived)
  success: Color(0xFF4ADE80), // success (midnight/amber, theme)
  successSoft: Color(0xFF14301F), // successSoft (midnight/amber, theme)
  warning: Color(0xFFFBBF24), // warning (midnight/amber, theme)
  warningSoft: Color(0xFF33280A), // warningSoft (midnight/amber, theme)
  danger: Color(0xFFF87171), // danger (midnight/amber, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (midnight/amber, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (midnight/amber, theme)
  scrim: Color(0xB804070A), // scrim (midnight/amber, theme)
  shadow1: Color(0x33000000), // shadow1 (midnight/amber, theme)
  shadow2: Color(0x59000000), // shadow2 (midnight/amber, theme)
  shadow3: Color(0x8C000000), // shadow3 (midnight/amber, theme)
);

/// midnight theme, rose accent.
const mkviMidnightRose = MkviTokens(
  themeId: MkviThemeId.midnight,
  accentId: MkviAccentId.rose,
  bg: Color(0xFF0D1117), // bg (midnight/rose, theme)
  surface: Color(0xFF131A24), // surface (midnight/rose, theme)
  surfaceRaised: Color(0xFF1A2330), // surfaceRaised (midnight/rose, theme)
  surfaceSoft: Color(0xFF212C3C), // surfaceSoft (midnight/rose, theme)
  surfaceOverlay: Color(0xFF18212D), // surfaceOverlay (midnight/rose, theme)
  text: Color(0xFFF2F6FB), // text (midnight/rose, theme)
  textMuted: Color(0xFFB6C2D2), // textMuted (midnight/rose, theme)
  textSubtle: Color(0xFF93A1B5), // textSubtle (midnight/rose, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (midnight/rose, derived)
  textOnStage: Color(0xFFEEF4FB), // textOnStage (midnight/rose, theme)
  stage: Color(0xFF080B10), // stage (midnight/rose, theme)
  border: Color(0xFF7B8698), // border (midnight/rose, theme)
  borderStrong: Color(0xFF9AA7B8), // borderStrong (midnight/rose, theme)
  accent: Color(0xFFDA1545), // accent (midnight/rose, derived)
  accentHover: Color(0xFFE11547), // accentHover (midnight/rose, derived)
  accentActive: Color(0xFFA91035), // accentActive (midnight/rose, derived)
  accentSoft: Color(0xFF771835), // accentSoft (midnight/rose, derived)
  focusRing: Color(0xFFEDC9D7), // focusRing (midnight/rose, derived)
  success: Color(0xFF4ADE80), // success (midnight/rose, theme)
  successSoft: Color(0xFF14301F), // successSoft (midnight/rose, theme)
  warning: Color(0xFFFBBF24), // warning (midnight/rose, theme)
  warningSoft: Color(0xFF33280A), // warningSoft (midnight/rose, theme)
  danger: Color(0xFFF87171), // danger (midnight/rose, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (midnight/rose, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (midnight/rose, theme)
  scrim: Color(0xB804070A), // scrim (midnight/rose, theme)
  shadow1: Color(0x33000000), // shadow1 (midnight/rose, theme)
  shadow2: Color(0x59000000), // shadow2 (midnight/rose, theme)
  shadow3: Color(0x8C000000), // shadow3 (midnight/rose, theme)
);

/// light theme, blue accent.
const mkviLightBlue = MkviTokens(
  themeId: MkviThemeId.light,
  accentId: MkviAccentId.blue,
  bg: Color(0xFFF5F7FA), // bg (light/blue, theme)
  surface: Color(0xFFFFFFFF), // surface (light/blue, theme)
  surfaceRaised: Color(0xFFEEF2F7), // surfaceRaised (light/blue, theme)
  surfaceSoft: Color(0xFFE4EAF3), // surfaceSoft (light/blue, theme)
  surfaceOverlay: Color(0xFFFFFFFF), // surfaceOverlay (light/blue, theme)
  text: Color(0xFF101828), // text (light/blue, theme)
  textMuted: Color(0xFF4A5566), // textMuted (light/blue, theme)
  textSubtle: Color(0xFF5A6577), // textSubtle (light/blue, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (light/blue, derived)
  textOnStage: Color(0xFFEEF4FB), // textOnStage (light/blue, theme)
  stage: Color(0xFF0B1016), // stage (light/blue, theme)
  border: Color(0xFF6F7A8B), // border (light/blue, theme)
  borderStrong: Color(0xFF4B5565), // borderStrong (light/blue, theme)
  accent: Color(0xFF2665EF), // accent (light/blue, derived)
  accentHover: Color(0xFF2768F8), // accentHover (light/blue, derived)
  accentActive: Color(0xFF1D4DB8), // accentActive (light/blue, derived)
  accentSoft: Color(0xFFCFDDFB), // accentSoft (light/blue, derived)
  focusRing: Color(0xFF050C1D), // focusRing (light/blue, derived)
  success: Color(0xFF12703A), // success (light/blue, theme)
  successSoft: Color(0xFFDCFCE7), // successSoft (light/blue, theme)
  warning: Color(0xFF92400E), // warning (light/blue, theme)
  warningSoft: Color(0xFFFEF3C7), // warningSoft (light/blue, theme)
  danger: Color(0xFFB91C1C), // danger (light/blue, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (light/blue, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (light/blue, theme)
  scrim: Color(0xA61A2233), // scrim (light/blue, theme)
  shadow1: Color(0x14101828), // shadow1 (light/blue, theme)
  shadow2: Color(0x1F101828), // shadow2 (light/blue, theme)
  shadow3: Color(0x33101828), // shadow3 (light/blue, theme)
);

/// light theme, teal accent.
const mkviLightTeal = MkviTokens(
  themeId: MkviThemeId.light,
  accentId: MkviAccentId.teal,
  bg: Color(0xFFF5F7FA), // bg (light/teal, theme)
  surface: Color(0xFFFFFFFF), // surface (light/teal, theme)
  surfaceRaised: Color(0xFFEEF2F7), // surfaceRaised (light/teal, theme)
  surfaceSoft: Color(0xFFE4EAF3), // surfaceSoft (light/teal, theme)
  surfaceOverlay: Color(0xFFFFFFFF), // surfaceOverlay (light/teal, theme)
  text: Color(0xFF101828), // text (light/teal, theme)
  textMuted: Color(0xFF4A5566), // textMuted (light/teal, theme)
  textSubtle: Color(0xFF5A6577), // textSubtle (light/teal, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (light/teal, derived)
  textOnStage: Color(0xFFEEF4FB), // textOnStage (light/teal, theme)
  stage: Color(0xFF0B1016), // stage (light/teal, theme)
  border: Color(0xFF6F7A8B), // border (light/teal, theme)
  borderStrong: Color(0xFF4B5565), // borderStrong (light/teal, theme)
  accent: Color(0xFF107D74), // accent (light/teal, derived)
  accentHover: Color(0xFF108178), // accentHover (light/teal, derived)
  accentActive: Color(0xFF0C5F59), // accentActive (light/teal, derived)
  accentSoft: Color(0xFFCAE2E0), // accentSoft (light/teal, derived)
  focusRing: Color(0xFF020F0E), // focusRing (light/teal, derived)
  success: Color(0xFF12703A), // success (light/teal, theme)
  successSoft: Color(0xFFDCFCE7), // successSoft (light/teal, theme)
  warning: Color(0xFF92400E), // warning (light/teal, theme)
  warningSoft: Color(0xFFFEF3C7), // warningSoft (light/teal, theme)
  danger: Color(0xFFB91C1C), // danger (light/teal, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (light/teal, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (light/teal, theme)
  scrim: Color(0xA61A2233), // scrim (light/teal, theme)
  shadow1: Color(0x14101828), // shadow1 (light/teal, theme)
  shadow2: Color(0x1F101828), // shadow2 (light/teal, theme)
  shadow3: Color(0x33101828), // shadow3 (light/teal, theme)
);

/// light theme, amber accent.
const mkviLightAmber = MkviTokens(
  themeId: MkviThemeId.light,
  accentId: MkviAccentId.amber,
  bg: Color(0xFFF5F7FA), // bg (light/amber, theme)
  surface: Color(0xFFFFFFFF), // surface (light/amber, theme)
  surfaceRaised: Color(0xFFEEF2F7), // surfaceRaised (light/amber, theme)
  surfaceSoft: Color(0xFFE4EAF3), // surfaceSoft (light/amber, theme)
  surfaceOverlay: Color(0xFFFFFFFF), // surfaceOverlay (light/amber, theme)
  text: Color(0xFF101828), // text (light/amber, theme)
  textMuted: Color(0xFF4A5566), // textMuted (light/amber, theme)
  textSubtle: Color(0xFF5A6577), // textSubtle (light/amber, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (light/amber, derived)
  textOnStage: Color(0xFFEEF4FB), // textOnStage (light/amber, theme)
  stage: Color(0xFF0B1016), // stage (light/amber, theme)
  border: Color(0xFF6F7A8B), // border (light/amber, theme)
  borderStrong: Color(0xFF4B5565), // borderStrong (light/amber, theme)
  accent: Color(0xFFB45309), // accent (light/amber, derived)
  accentHover: Color(0xFFB95609), // accentHover (light/amber, derived)
  accentActive: Color(0xFF8A4007), // accentActive (light/amber, derived)
  accentSoft: Color(0xFFEFD9C9), // accentSoft (light/amber, derived)
  focusRing: Color(0xFF160A01), // focusRing (light/amber, derived)
  success: Color(0xFF12703A), // success (light/amber, theme)
  successSoft: Color(0xFFDCFCE7), // successSoft (light/amber, theme)
  warning: Color(0xFF92400E), // warning (light/amber, theme)
  warningSoft: Color(0xFFFEF3C7), // warningSoft (light/amber, theme)
  danger: Color(0xFFB91C1C), // danger (light/amber, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (light/amber, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (light/amber, theme)
  scrim: Color(0xA61A2233), // scrim (light/amber, theme)
  shadow1: Color(0x14101828), // shadow1 (light/amber, theme)
  shadow2: Color(0x1F101828), // shadow2 (light/amber, theme)
  shadow3: Color(0x33101828), // shadow3 (light/amber, theme)
);

/// light theme, rose accent.
const mkviLightRose = MkviTokens(
  themeId: MkviThemeId.light,
  accentId: MkviAccentId.rose,
  bg: Color(0xFFF5F7FA), // bg (light/rose, theme)
  surface: Color(0xFFFFFFFF), // surface (light/rose, theme)
  surfaceRaised: Color(0xFFEEF2F7), // surfaceRaised (light/rose, theme)
  surfaceSoft: Color(0xFFE4EAF3), // surfaceSoft (light/rose, theme)
  surfaceOverlay: Color(0xFFFFFFFF), // surfaceOverlay (light/rose, theme)
  text: Color(0xFF101828), // text (light/rose, theme)
  textMuted: Color(0xFF4A5566), // textMuted (light/rose, theme)
  textSubtle: Color(0xFF5A6577), // textSubtle (light/rose, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (light/rose, derived)
  textOnStage: Color(0xFFEEF4FB), // textOnStage (light/rose, theme)
  stage: Color(0xFF0B1016), // stage (light/rose, theme)
  border: Color(0xFF6F7A8B), // border (light/rose, theme)
  borderStrong: Color(0xFF4B5565), // borderStrong (light/rose, theme)
  accent: Color(0xFFDA1545), // accent (light/rose, derived)
  accentHover: Color(0xFFE11547), // accentHover (light/rose, derived)
  accentActive: Color(0xFFA91035), // accentActive (light/rose, derived)
  accentSoft: Color(0xFFF7CCD6), // accentSoft (light/rose, derived)
  focusRing: Color(0xFF1A0308), // focusRing (light/rose, derived)
  success: Color(0xFF12703A), // success (light/rose, theme)
  successSoft: Color(0xFFDCFCE7), // successSoft (light/rose, theme)
  warning: Color(0xFF92400E), // warning (light/rose, theme)
  warningSoft: Color(0xFFFEF3C7), // warningSoft (light/rose, theme)
  danger: Color(0xFFB91C1C), // danger (light/rose, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (light/rose, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (light/rose, theme)
  scrim: Color(0xA61A2233), // scrim (light/rose, theme)
  shadow1: Color(0x14101828), // shadow1 (light/rose, theme)
  shadow2: Color(0x1F101828), // shadow2 (light/rose, theme)
  shadow3: Color(0x33101828), // shadow3 (light/rose, theme)
);

/// forest theme, blue accent.
const mkviForestBlue = MkviTokens(
  themeId: MkviThemeId.forest,
  accentId: MkviAccentId.blue,
  bg: Color(0xFF08110D), // bg (forest/blue, theme)
  surface: Color(0xFF0F1A15), // surface (forest/blue, theme)
  surfaceRaised: Color(0xFF16241D), // surfaceRaised (forest/blue, theme)
  surfaceSoft: Color(0xFF1D2F26), // surfaceSoft (forest/blue, theme)
  surfaceOverlay: Color(0xFF132019), // surfaceOverlay (forest/blue, theme)
  text: Color(0xFFF0F7F3), // text (forest/blue, theme)
  textMuted: Color(0xFFAECABD), // textMuted (forest/blue, theme)
  textSubtle: Color(0xFF8AA89A), // textSubtle (forest/blue, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (forest/blue, derived)
  textOnStage: Color(0xFFEAF4EE), // textOnStage (forest/blue, theme)
  stage: Color(0xFF050C09), // stage (forest/blue, theme)
  border: Color(0xFF6F8A7C), // border (forest/blue, theme)
  borderStrong: Color(0xFF90A99A), // borderStrong (forest/blue, theme)
  accent: Color(0xFF2665EF), // accent (forest/blue, derived)
  accentHover: Color(0xFF2768F8), // accentHover (forest/blue, derived)
  accentActive: Color(0xFF1D4DB8), // accentActive (forest/blue, derived)
  accentSoft: Color(0xFF1B4082), // accentSoft (forest/blue, derived)
  focusRing: Color(0xFFC8DAF2), // focusRing (forest/blue, derived)
  success: Color(0xFF4ADE80), // success (forest/blue, theme)
  successSoft: Color(0xFF10281A), // successSoft (forest/blue, theme)
  warning: Color(0xFFFBBF24), // warning (forest/blue, theme)
  warningSoft: Color(0xFF2F2A0A), // warningSoft (forest/blue, theme)
  danger: Color(0xFFF87171), // danger (forest/blue, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (forest/blue, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (forest/blue, theme)
  scrim: Color(0xB8030A07), // scrim (forest/blue, theme)
  shadow1: Color(0x33000000), // shadow1 (forest/blue, theme)
  shadow2: Color(0x59000000), // shadow2 (forest/blue, theme)
  shadow3: Color(0x8C000000), // shadow3 (forest/blue, theme)
);

/// forest theme, teal accent.
const mkviForestTeal = MkviTokens(
  themeId: MkviThemeId.forest,
  accentId: MkviAccentId.teal,
  bg: Color(0xFF08110D), // bg (forest/teal, theme)
  surface: Color(0xFF0F1A15), // surface (forest/teal, theme)
  surfaceRaised: Color(0xFF16241D), // surfaceRaised (forest/teal, theme)
  surfaceSoft: Color(0xFF1D2F26), // surfaceSoft (forest/teal, theme)
  surfaceOverlay: Color(0xFF132019), // surfaceOverlay (forest/teal, theme)
  text: Color(0xFFF0F7F3), // text (forest/teal, theme)
  textMuted: Color(0xFFAECABD), // textMuted (forest/teal, theme)
  textSubtle: Color(0xFF8AA89A), // textSubtle (forest/teal, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (forest/teal, derived)
  textOnStage: Color(0xFFEAF4EE), // textOnStage (forest/teal, theme)
  stage: Color(0xFF050C09), // stage (forest/teal, theme)
  border: Color(0xFF6F8A7C), // border (forest/teal, theme)
  borderStrong: Color(0xFF90A99A), // borderStrong (forest/teal, theme)
  accent: Color(0xFF107D74), // accent (forest/teal, derived)
  accentHover: Color(0xFF108178), // accentHover (forest/teal, derived)
  accentActive: Color(0xFF0C5F59), // accentActive (forest/teal, derived)
  accentSoft: Color(0xFF104C45), // accentSoft (forest/teal, derived)
  focusRing: Color(0xFFC3DFDA), // focusRing (forest/teal, derived)
  success: Color(0xFF4ADE80), // success (forest/teal, theme)
  successSoft: Color(0xFF10281A), // successSoft (forest/teal, theme)
  warning: Color(0xFFFBBF24), // warning (forest/teal, theme)
  warningSoft: Color(0xFF2F2A0A), // warningSoft (forest/teal, theme)
  danger: Color(0xFFF87171), // danger (forest/teal, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (forest/teal, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (forest/teal, theme)
  scrim: Color(0xB8030A07), // scrim (forest/teal, theme)
  shadow1: Color(0x33000000), // shadow1 (forest/teal, theme)
  shadow2: Color(0x59000000), // shadow2 (forest/teal, theme)
  shadow3: Color(0x8C000000), // shadow3 (forest/teal, theme)
);

/// forest theme, amber accent.
const mkviForestAmber = MkviTokens(
  themeId: MkviThemeId.forest,
  accentId: MkviAccentId.amber,
  bg: Color(0xFF08110D), // bg (forest/amber, theme)
  surface: Color(0xFF0F1A15), // surface (forest/amber, theme)
  surfaceRaised: Color(0xFF16241D), // surfaceRaised (forest/amber, theme)
  surfaceSoft: Color(0xFF1D2F26), // surfaceSoft (forest/amber, theme)
  surfaceOverlay: Color(0xFF132019), // surfaceOverlay (forest/amber, theme)
  text: Color(0xFFF0F7F3), // text (forest/amber, theme)
  textMuted: Color(0xFFAECABD), // textMuted (forest/amber, theme)
  textSubtle: Color(0xFF8AA89A), // textSubtle (forest/amber, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (forest/amber, derived)
  textOnStage: Color(0xFFEAF4EE), // textOnStage (forest/amber, theme)
  stage: Color(0xFF050C09), // stage (forest/amber, theme)
  border: Color(0xFF6F8A7C), // border (forest/amber, theme)
  borderStrong: Color(0xFF90A99A), // borderStrong (forest/amber, theme)
  accent: Color(0xFFB45309), // accent (forest/amber, derived)
  accentHover: Color(0xFFB95609), // accentHover (forest/amber, derived)
  accentActive: Color(0xFF8A4007), // accentActive (forest/amber, derived)
  accentSoft: Color(0xFF62370F), // accentSoft (forest/amber, derived)
  focusRing: Color(0xFFE4D6C4), // focusRing (forest/amber, derived)
  success: Color(0xFF4ADE80), // success (forest/amber, theme)
  successSoft: Color(0xFF10281A), // successSoft (forest/amber, theme)
  warning: Color(0xFFFBBF24), // warning (forest/amber, theme)
  warningSoft: Color(0xFF2F2A0A), // warningSoft (forest/amber, theme)
  danger: Color(0xFFF87171), // danger (forest/amber, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (forest/amber, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (forest/amber, theme)
  scrim: Color(0xB8030A07), // scrim (forest/amber, theme)
  shadow1: Color(0x33000000), // shadow1 (forest/amber, theme)
  shadow2: Color(0x59000000), // shadow2 (forest/amber, theme)
  shadow3: Color(0x8C000000), // shadow3 (forest/amber, theme)
);

/// forest theme, rose accent.
const mkviForestRose = MkviTokens(
  themeId: MkviThemeId.forest,
  accentId: MkviAccentId.rose,
  bg: Color(0xFF08110D), // bg (forest/rose, theme)
  surface: Color(0xFF0F1A15), // surface (forest/rose, theme)
  surfaceRaised: Color(0xFF16241D), // surfaceRaised (forest/rose, theme)
  surfaceSoft: Color(0xFF1D2F26), // surfaceSoft (forest/rose, theme)
  surfaceOverlay: Color(0xFF132019), // surfaceOverlay (forest/rose, theme)
  text: Color(0xFFF0F7F3), // text (forest/rose, theme)
  textMuted: Color(0xFFAECABD), // textMuted (forest/rose, theme)
  textSubtle: Color(0xFF8AA89A), // textSubtle (forest/rose, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (forest/rose, derived)
  textOnStage: Color(0xFFEAF4EE), // textOnStage (forest/rose, theme)
  stage: Color(0xFF050C09), // stage (forest/rose, theme)
  border: Color(0xFF6F8A7C), // border (forest/rose, theme)
  borderStrong: Color(0xFF90A99A), // borderStrong (forest/rose, theme)
  accent: Color(0xFFDA1545), // accent (forest/rose, derived)
  accentHover: Color(0xFFE11547), // accentHover (forest/rose, derived)
  accentActive: Color(0xFFA91035), // accentActive (forest/rose, derived)
  accentSoft: Color(0xFF75182D), // accentSoft (forest/rose, derived)
  focusRing: Color(0xFFECCAD0), // focusRing (forest/rose, derived)
  success: Color(0xFF4ADE80), // success (forest/rose, theme)
  successSoft: Color(0xFF10281A), // successSoft (forest/rose, theme)
  warning: Color(0xFFFBBF24), // warning (forest/rose, theme)
  warningSoft: Color(0xFF2F2A0A), // warningSoft (forest/rose, theme)
  danger: Color(0xFFF87171), // danger (forest/rose, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (forest/rose, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (forest/rose, theme)
  scrim: Color(0xB8030A07), // scrim (forest/rose, theme)
  shadow1: Color(0x33000000), // shadow1 (forest/rose, theme)
  shadow2: Color(0x59000000), // shadow2 (forest/rose, theme)
  shadow3: Color(0x8C000000), // shadow3 (forest/rose, theme)
);

/// plum theme, blue accent.
const mkviPlumBlue = MkviTokens(
  themeId: MkviThemeId.plum,
  accentId: MkviAccentId.blue,
  bg: Color(0xFF100A14), // bg (plum/blue, theme)
  surface: Color(0xFF180F1E), // surface (plum/blue, theme)
  surfaceRaised: Color(0xFF20162A), // surfaceRaised (plum/blue, theme)
  surfaceSoft: Color(0xFF281D33), // surfaceSoft (plum/blue, theme)
  surfaceOverlay: Color(0xFF1D1424), // surfaceOverlay (plum/blue, theme)
  text: Color(0xFFF7F1FA), // text (plum/blue, theme)
  textMuted: Color(0xFFC9B6D2), // textMuted (plum/blue, theme)
  textSubtle: Color(0xFFA894B4), // textSubtle (plum/blue, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (plum/blue, derived)
  textOnStage: Color(0xFFF2EAF6), // textOnStage (plum/blue, theme)
  stage: Color(0xFF0A060D), // stage (plum/blue, theme)
  border: Color(0xFF8B7597), // border (plum/blue, theme)
  borderStrong: Color(0xFFA493AF), // borderStrong (plum/blue, theme)
  accent: Color(0xFF2665EF), // accent (plum/blue, derived)
  accentHover: Color(0xFF2768F8), // accentHover (plum/blue, derived)
  accentActive: Color(0xFF1D4DB8), // accentActive (plum/blue, derived)
  accentSoft: Color(0xFF1F3A87), // accentSoft (plum/blue, derived)
  focusRing: Color(0xFFCDD5F8), // focusRing (plum/blue, derived)
  success: Color(0xFF4ADE80), // success (plum/blue, theme)
  successSoft: Color(0xFF152A1C), // successSoft (plum/blue, theme)
  warning: Color(0xFFFBBF24), // warning (plum/blue, theme)
  warningSoft: Color(0xFF2E240F), // warningSoft (plum/blue, theme)
  danger: Color(0xFFF87171), // danger (plum/blue, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (plum/blue, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (plum/blue, theme)
  scrim: Color(0xB807040A), // scrim (plum/blue, theme)
  shadow1: Color(0x33000000), // shadow1 (plum/blue, theme)
  shadow2: Color(0x59000000), // shadow2 (plum/blue, theme)
  shadow3: Color(0x8C000000), // shadow3 (plum/blue, theme)
);

/// plum theme, teal accent.
const mkviPlumTeal = MkviTokens(
  themeId: MkviThemeId.plum,
  accentId: MkviAccentId.teal,
  bg: Color(0xFF100A14), // bg (plum/teal, theme)
  surface: Color(0xFF180F1E), // surface (plum/teal, theme)
  surfaceRaised: Color(0xFF20162A), // surfaceRaised (plum/teal, theme)
  surfaceSoft: Color(0xFF281D33), // surfaceSoft (plum/teal, theme)
  surfaceOverlay: Color(0xFF1D1424), // surfaceOverlay (plum/teal, theme)
  text: Color(0xFFF7F1FA), // text (plum/teal, theme)
  textMuted: Color(0xFFC9B6D2), // textMuted (plum/teal, theme)
  textSubtle: Color(0xFFA894B4), // textSubtle (plum/teal, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (plum/teal, derived)
  textOnStage: Color(0xFFF2EAF6), // textOnStage (plum/teal, theme)
  stage: Color(0xFF0A060D), // stage (plum/teal, theme)
  border: Color(0xFF8B7597), // border (plum/teal, theme)
  borderStrong: Color(0xFFA493AF), // borderStrong (plum/teal, theme)
  accent: Color(0xFF107D74), // accent (plum/teal, derived)
  accentHover: Color(0xFF108178), // accentHover (plum/teal, derived)
  accentActive: Color(0xFF0C5F59), // accentActive (plum/teal, derived)
  accentSoft: Color(0xFF144649), // accentSoft (plum/teal, derived)
  focusRing: Color(0xFFC9DADF), // focusRing (plum/teal, derived)
  success: Color(0xFF4ADE80), // success (plum/teal, theme)
  successSoft: Color(0xFF152A1C), // successSoft (plum/teal, theme)
  warning: Color(0xFFFBBF24), // warning (plum/teal, theme)
  warningSoft: Color(0xFF2E240F), // warningSoft (plum/teal, theme)
  danger: Color(0xFFF87171), // danger (plum/teal, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (plum/teal, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (plum/teal, theme)
  scrim: Color(0xB807040A), // scrim (plum/teal, theme)
  shadow1: Color(0x33000000), // shadow1 (plum/teal, theme)
  shadow2: Color(0x59000000), // shadow2 (plum/teal, theme)
  shadow3: Color(0x8C000000), // shadow3 (plum/teal, theme)
);

/// plum theme, amber accent.
const mkviPlumAmber = MkviTokens(
  themeId: MkviThemeId.plum,
  accentId: MkviAccentId.amber,
  bg: Color(0xFF100A14), // bg (plum/amber, theme)
  surface: Color(0xFF180F1E), // surface (plum/amber, theme)
  surfaceRaised: Color(0xFF20162A), // surfaceRaised (plum/amber, theme)
  surfaceSoft: Color(0xFF281D33), // surfaceSoft (plum/amber, theme)
  surfaceOverlay: Color(0xFF1D1424), // surfaceOverlay (plum/amber, theme)
  text: Color(0xFFF7F1FA), // text (plum/amber, theme)
  textMuted: Color(0xFFC9B6D2), // textMuted (plum/amber, theme)
  textSubtle: Color(0xFFA894B4), // textSubtle (plum/amber, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (plum/amber, derived)
  textOnStage: Color(0xFFF2EAF6), // textOnStage (plum/amber, theme)
  stage: Color(0xFF0A060D), // stage (plum/amber, theme)
  border: Color(0xFF8B7597), // border (plum/amber, theme)
  borderStrong: Color(0xFFA493AF), // borderStrong (plum/amber, theme)
  accent: Color(0xFFB45309), // accent (plum/amber, derived)
  accentHover: Color(0xFFB95609), // accentHover (plum/amber, derived)
  accentActive: Color(0xFF8A4007), // accentActive (plum/amber, derived)
  accentSoft: Color(0xFF663114), // accentSoft (plum/amber, derived)
  focusRing: Color(0xFFEAD1CA), // focusRing (plum/amber, derived)
  success: Color(0xFF4ADE80), // success (plum/amber, theme)
  successSoft: Color(0xFF152A1C), // successSoft (plum/amber, theme)
  warning: Color(0xFFFBBF24), // warning (plum/amber, theme)
  warningSoft: Color(0xFF2E240F), // warningSoft (plum/amber, theme)
  danger: Color(0xFFF87171), // danger (plum/amber, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (plum/amber, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (plum/amber, theme)
  scrim: Color(0xB807040A), // scrim (plum/amber, theme)
  shadow1: Color(0x33000000), // shadow1 (plum/amber, theme)
  shadow2: Color(0x59000000), // shadow2 (plum/amber, theme)
  shadow3: Color(0x8C000000), // shadow3 (plum/amber, theme)
);

/// plum theme, rose accent.
const mkviPlumRose = MkviTokens(
  themeId: MkviThemeId.plum,
  accentId: MkviAccentId.rose,
  bg: Color(0xFF100A14), // bg (plum/rose, theme)
  surface: Color(0xFF180F1E), // surface (plum/rose, theme)
  surfaceRaised: Color(0xFF20162A), // surfaceRaised (plum/rose, theme)
  surfaceSoft: Color(0xFF281D33), // surfaceSoft (plum/rose, theme)
  surfaceOverlay: Color(0xFF1D1424), // surfaceOverlay (plum/rose, theme)
  text: Color(0xFFF7F1FA), // text (plum/rose, theme)
  textMuted: Color(0xFFC9B6D2), // textMuted (plum/rose, theme)
  textSubtle: Color(0xFFA894B4), // textSubtle (plum/rose, theme)
  textOnAccent: Color(0xFFFFFFFF), // textOnAccent (plum/rose, derived)
  textOnStage: Color(0xFFF2EAF6), // textOnStage (plum/rose, theme)
  stage: Color(0xFF0A060D), // stage (plum/rose, theme)
  border: Color(0xFF8B7597), // border (plum/rose, theme)
  borderStrong: Color(0xFFA493AF), // borderStrong (plum/rose, theme)
  accent: Color(0xFFDA1545), // accent (plum/rose, derived)
  accentHover: Color(0xFFE11547), // accentHover (plum/rose, derived)
  accentActive: Color(0xFFA91035), // accentActive (plum/rose, derived)
  accentSoft: Color(0xFF791232), // accentSoft (plum/rose, derived)
  focusRing: Color(0xFFF1C5D6), // focusRing (plum/rose, derived)
  success: Color(0xFF4ADE80), // success (plum/rose, theme)
  successSoft: Color(0xFF152A1C), // successSoft (plum/rose, theme)
  warning: Color(0xFFFBBF24), // warning (plum/rose, theme)
  warningSoft: Color(0xFF2E240F), // warningSoft (plum/rose, theme)
  danger: Color(0xFFF87171), // danger (plum/rose, theme)
  dangerFill: Color(0xFFDC2626), // dangerFill (plum/rose, theme)
  dangerFillHover: Color(0xFFB91C1C), // dangerFillHover (plum/rose, theme)
  scrim: Color(0xB807040A), // scrim (plum/rose, theme)
  shadow1: Color(0x33000000), // shadow1 (plum/rose, theme)
  shadow2: Color(0x59000000), // shadow2 (plum/rose, theme)
  shadow3: Color(0x8C000000), // shadow3 (plum/rose, theme)
);

/// Every token set, keyed by theme then accent.
const Map<MkviThemeId, Map<MkviAccentId, MkviTokens>> mkviTokensByTheme =
    <MkviThemeId, Map<MkviAccentId, MkviTokens>>{
  MkviThemeId.midnight: <MkviAccentId, MkviTokens>{
    MkviAccentId.blue: mkviMidnightBlue,
    MkviAccentId.teal: mkviMidnightTeal,
    MkviAccentId.amber: mkviMidnightAmber,
    MkviAccentId.rose: mkviMidnightRose,
  },
  MkviThemeId.light: <MkviAccentId, MkviTokens>{
    MkviAccentId.blue: mkviLightBlue,
    MkviAccentId.teal: mkviLightTeal,
    MkviAccentId.amber: mkviLightAmber,
    MkviAccentId.rose: mkviLightRose,
  },
  MkviThemeId.forest: <MkviAccentId, MkviTokens>{
    MkviAccentId.blue: mkviForestBlue,
    MkviAccentId.teal: mkviForestTeal,
    MkviAccentId.amber: mkviForestAmber,
    MkviAccentId.rose: mkviForestRose,
  },
  MkviThemeId.plum: <MkviAccentId, MkviTokens>{
    MkviAccentId.blue: mkviPlumBlue,
    MkviAccentId.teal: mkviPlumTeal,
    MkviAccentId.amber: mkviPlumAmber,
    MkviAccentId.rose: mkviPlumRose,
  },
};

/// The default pair declared in `meta`.
const mkviTokensDefault =
    mkviMidnightBlue;

/// The token set for an arbitrary (theme, accent) pair.
MkviTokens mkviTokensFor(MkviThemeId theme, MkviAccentId accent) =>
    mkviTokensByTheme[theme]![accent]!;

