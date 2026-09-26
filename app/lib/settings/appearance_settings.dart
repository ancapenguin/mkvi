/// The appearance preference, as the user chose it.
///
/// This is a value object and nothing else: no colours beyond the user's own
/// custom accent, no resolution, no I/O. The preference is deliberately
/// dumb so that there is exactly one place - `AppearanceResolver` - where it
/// becomes pixels, and so that the settings screen can render a choice the app
/// has not accepted yet.
///
/// Two shapes of value live here, and the difference between them is the
/// difference the live defects were made of:
///
/// * [AppearanceSettings] is the RAW preference: what the user picked.
/// * `ResolvedAppearance` (in `appearance_resolver.dart`) is the RESOLVED
///   value: every spacing step, radius, type size, control height and duration
///   already multiplied out, plus the `ThemeData` they produce.
///
/// The old build had only the first shape and spread the second one across
/// ~40 call sites, which is why `density` was honoured in 8 of them and
/// `fontScale` in none of the first-run screens: a number in a state object
/// that nobody was obliged to read. Holding the resolved shape as a value
/// makes reading it the only option - the numbers exist in one object, and a
/// widget that wants a gap asks for `resolved.space['4']` instead of
/// multiplying something itself.
library;

import 'dart:ui' show Color;

/// Which theme to paint with.
///
/// `system` is a value, not an absence: the old build had no system theme at
/// all, so a light-OS user had to pick the light theme by hand on every fresh
/// install and again after every update that reset storage. Here `system` is
/// the DEFAULT, and resolving it is the resolver's job.
enum ThemePreference {
  /// Follow the operating system's light/dark setting.
  ///
  /// Resolves to the token file's default dark theme, or to the token file's
  /// light theme, whichever matches the platform brightness.
  system,

  /// `tokens.json` `themes.midnight` - the file's own default.
  midnight,

  /// `tokens.json` `themes.light`.
  light,

  /// `tokens.json` `themes.forest`.
  forest,

  /// `tokens.json` `themes.plum`.
  plum;

  /// Whether this preference names a theme outright.
  bool get isExplicit => this != ThemePreference.system;

  /// The `themes` key, or null for [system].
  String? get themeId => isExplicit ? name : null;

  /// The preference for a `themes` key, or [system] for an unknown id.
  static ThemePreference fromThemeId(String? id) {
    if (id == null) return ThemePreference.system;
    for (final ThemePreference value in ThemePreference.values) {
      if (value.name == id) return value;
    }
    return ThemePreference.system;
  }
}

/// An accent id from `tokens.json` `accents`.
///
/// The four names are the token file's, not a list invented here, and
/// `app/test/settings/appearance_test.dart` asserts this enum against the file
/// so a renamed accent fails the build.
enum AccentId {
  blue,
  teal,
  amber,
  rose;

  /// The accent for an `accents` key, or null when it is not one of ours.
  static AccentId? fromAccentId(String id) {
    for (final AccentId value in AccentId.values) {
      if (value.name == id) return value;
    }
    return null;
  }
}

/// The accent fill: one of the four shipped ramps, or a colour the user picked.
///
/// A custom accent is kept, never swapped for a shipped one. The old build
/// offered four hardcoded swatches and no colour input at all, so "fully
/// customisable" was literally false; here the value is the user's colour and
/// the resolver builds the rest of the ramp around it - and if the colour
/// cannot carry text, that is REPORTED (Turkish, with the measured ratio)
/// rather than silently replaced behind the user's back.
final class AccentPreference {
  const AccentPreference.preset(this.presetId) : custom = null;

  const AccentPreference.custom(this.custom) : presetId = null;

  /// A shipped accent, or null when [custom] is set.
  final AccentId? presetId;

  /// The user's own colour, or null for a shipped accent.
  final Color? custom;

  /// Whether the user picked a colour.
  bool get isCustom => custom != null;

  /// The `accents` key, or `custom`.
  String get accentId => presetId?.name ?? customAccentId;

  /// The key a custom accent is stored and reported under.
  static const String customAccentId = 'custom';

  AccentPreference withCustom(Color value) => AccentPreference.custom(value);

  @override
  bool operator ==(Object other) =>
      other is AccentPreference &&
      other.presetId == presetId &&
      other.custom == custom;

  @override
  int get hashCode => Object.hash(presetId, custom);

  @override
  String toString() => isCustom
      ? 'AccentPreference.custom($custom)'
      : 'AccentPreference($accentId)';
}

/// How much space the layout breathes.
///
/// The two names are the product's; the multipliers behind them are
/// `space.densities` in the token file ('compact' and 'cozy'), read through
/// [AppearanceTokens.densities].
enum DensityPreference {
  /// `space.densities.compact`.
  compact,

  /// `space.densities.cozy`.
  comfortable;

  /// The `space.densities` key.
  String get densityId => name == 'comfortable' ? 'cozy' : name;

  /// The preference for a `space.densities` key, or [comfortable].
  static DensityPreference fromDensityId(String? id) {
    if (id == 'compact') return DensityPreference.compact;
    return DensityPreference.comfortable;
  }
}

/// How round the corners are.
///
/// 'crisp' and 'cozy' are `radius.presets` in the token file. The user-facing
/// name is "soft" because that is the word for it; the token name stays
/// "cozy" because that is what the file calls the same preset.
enum RadiusPreference {
  /// `radius.presets.crisp`.
  crisp,

  /// `radius.presets.cozy`.
  soft;

  /// The `radius.presets` key.
  String get presetId => name == 'soft' ? 'cozy' : name;

  /// The preference for a `radius.presets` key, or [soft].
  static RadiusPreference fromPresetId(String? id) =>
      id == 'crisp' ? RadiusPreference.crisp : RadiusPreference.soft;
}

/// Every appearance choice, normalised.
final class AppearanceSettings {
  /// Builds a preference, clamping and quantising [fontScale].
  ///
  /// Normalising here rather than at the point of use is what makes the
  /// invariant "a stored font scale is in range" true of the state itself, so
  /// no resolver can be handed an out-of-range number and quietly clamp it
  /// where nobody can see. The codec still REPORTS every correction it has to
  /// make, because a silent correction is the defect this layer exists to
  /// remove.
  factory AppearanceSettings({
    ThemePreference theme = ThemePreference.system,
    AccentPreference accent = const AccentPreference.preset(AccentId.blue),
    double fontScale = defaultFontScale,
    DensityPreference density = DensityPreference.comfortable,
    RadiusPreference radius = RadiusPreference.soft,
    bool highContrast = false,
    bool reduceMotion = false,
  }) {
    return AppearanceSettings._(
      theme: theme,
      accent: accent,
      fontScale: quantiseFontScale(fontScale),
      density: density,
      radius: radius,
      highContrast: highContrast,
      reduceMotion: reduceMotion,
    );
  }

  const AppearanceSettings._({
    required this.theme,
    required this.accent,
    required this.fontScale,
    required this.density,
    required this.radius,
    required this.highContrast,
    required this.reduceMotion,
  });

  /// Smallest font scale the slider offers.
  static const double minFontScale = 0.9;

  /// Largest font scale the slider offers.
  static const double maxFontScale = 1.25;

  /// The step the slider snaps to. 0.9 + 7 * 0.05 == 1.25 exactly.
  static const double fontScaleStep = 0.05;

  /// The scale a fresh install starts at.
  static const double defaultFontScale = 1.0;

  /// The preference a fresh install starts at: follow the operating system.
  static const AppearanceSettings initial = AppearanceSettings._(
    theme: ThemePreference.system,
    accent: AccentPreference.preset(AccentId.blue),
    fontScale: 1.0,
    density: DensityPreference.comfortable,
    radius: RadiusPreference.soft,
    highContrast: false,
    reduceMotion: false,
  );

  /// Which theme. [ThemePreference.system] follows the platform.
  final ThemePreference theme;

  /// The accent fill, shipped or custom.
  final AccentPreference accent;

  /// The user's type size multiplier, in [minFontScale]..[maxFontScale].
  final double fontScale;

  /// How much space the layout breathes.
  final DensityPreference density;

  /// How round the corners are.
  final RadiusPreference radius;

  /// Collapse the colour ramps towards their extremes and thicken the focus
  /// ring. Off by default; the token file's own ratios already pass the gate,
  /// this buys margin for the eye and for a washed-out display.
  final bool highContrast;

  /// Replace every duration with `motion.durations.instant`, per the token
  /// file's `motion.reducedMotionNote`.
  final bool reduceMotion;

  /// Clamps to the slider range, snaps to [fontScaleStep], and turns a value
  /// that is not a number (NaN, infinity) into [defaultFontScale].
  ///
  /// The result is rounded to two decimals so a scale that came in as `1.25`
  /// comes out as `1.25` and not as `1.2499999999999998`, which matters the
  /// moment a test or a stored value compares them.
  static double quantiseFontScale(double value) {
    if (value.isNaN || value.isInfinite) return defaultFontScale;
    final double clamped = value.clamp(minFontScale, maxFontScale);
    final int steps = ((clamped - minFontScale) / fontScaleStep).round();
    final double snapped = minFontScale + steps * fontScaleStep;
    return _round2(snapped);
  }

  /// Whether [value] would come out of [quantiseFontScale] unchanged.
  static bool isFontScaleNormalised(double value) =>
      quantiseFontScale(value) == value;

  static double _round2(double value) {
    final double scaled = value * 100;
    final int rounded = scaled.round();
    return rounded / 100;
  }

  AppearanceSettings copyWith({
    ThemePreference? theme,
    AccentPreference? accent,
    double? fontScale,
    DensityPreference? density,
    RadiusPreference? radius,
    bool? highContrast,
    bool? reduceMotion,
  }) {
    return AppearanceSettings(
      theme: theme ?? this.theme,
      accent: accent ?? this.accent,
      fontScale: fontScale ?? this.fontScale,
      density: density ?? this.density,
      radius: radius ?? this.radius,
      highContrast: highContrast ?? this.highContrast,
      reduceMotion: reduceMotion ?? this.reduceMotion,
    );
  }

  /// Same value, different theme.
  AppearanceSettings withTheme(ThemePreference value) => copyWith(theme: value);

  /// Same value, different accent.
  AppearanceSettings withAccent(AccentPreference value) =>
      copyWith(accent: value);

  /// Same value, different font scale. The scale is normalised on the way in.
  AppearanceSettings withFontScale(double value) => copyWith(fontScale: value);

  /// Same value, different density.
  AppearanceSettings withDensity(DensityPreference value) =>
      copyWith(density: value);

  /// Same value, different radius preset.
  AppearanceSettings withRadius(RadiusPreference value) =>
      copyWith(radius: value);

  /// Same value, high contrast on or off.
  AppearanceSettings withHighContrast(bool value) =>
      copyWith(highContrast: value);

  /// Same value, reduced motion on or off.
  AppearanceSettings withReduceMotion(bool value) =>
      copyWith(reduceMotion: value);

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.theme == theme &&
      other.accent == accent &&
      other.fontScale == fontScale &&
      other.density == density &&
      other.radius == radius &&
      other.highContrast == highContrast &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(
    theme,
    accent,
    fontScale,
    density,
    radius,
    highContrast,
    reduceMotion,
  );

  @override
  String toString() =>
      'AppearanceSettings(${theme.name}, ${accent.accentId}, '
      'font $fontScale, ${density.name}, ${radius.name}, '
      'highContrast: $highContrast, reduceMotion: $reduceMotion)';
}
