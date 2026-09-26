/// The one place a preference becomes pixels.
///
/// ## What this file is for
///
/// The old UI multiplied a token by a stored number at each call site, and
/// there were about forty of them: `density` was honoured in eight, `radius`
/// in six hardcoded exceptions, and `fontScale` in none of the first-run
/// screens because the one rule that scaled it applied to an element whose
/// children all used their own literals.
///
/// Here the multiplication happens exactly once, per resolve, and the result
/// is a value - [AppearanceStyle] - that the UI can only read and never
/// recompute. A widget that wants a gap reads `style.gap('4')`; a widget that
/// wants a font size reads `style.styleOf('md')`; there is no second source
/// for either, so there is nowhere for the preference to be honoured in eight
/// places out of forty.
///
/// ## The rules, all of them arithmetic on token values
///
/// * theme: `system` picks the token theme whose declared polarity matches the
///   platform brightness, preferring the token file's own default when several
///   match. An explicit theme wins, always.
/// * accent: one of the four shipped ramps, or a ramp built around the user's
///   colour with the token file's own machinery - `hover` and `active` reuse
///   the shipped ramp's channel deltas, `accentSoft` and `focusRing` are mixed
///   with the theme's own `derive` amounts, and the on-colour is the token
///   extreme that MEASURES best against the fill.
/// * fontScale: every type step and every control font size, once.
/// * density: every spacing step, every control height, padding and gap, and
///   nothing the token file says must not scale (font sizes, icon sizes, the
///   hit-target minimum, the stage).
/// * radius: the whole radius table of one preset. There is no second radius
///   table anywhere, which is what "radius in 6 hardcoded exceptions" was.
/// * highContrast: the ramps pushed to their extremes and the focus ring
///   widened by the token file's own border width.
/// * reduceMotion: every duration replaced with `motion.durations.instant`, per
///   the token file's `reducedMotionNote`, and the ink ripple switched off,
///   because a ripple is motion too.
///
/// ## What it checks
///
/// Every pair in the token file's `contrast` list is measured against the FINAL
/// colours - after the high-contrast adjustment, after a custom accent's ramp
/// was derived - and a pair that fails is reported in Turkish with its ratio
/// instead of being shipped. For the four shipped themes and four shipped
/// accents this is already guaranteed by `design/test/contrast_test.dart`, so a
/// report can only mean a custom accent or a future token change. That is
/// exactly the case a user needs to hear about, and exactly the case the old
/// build shipped silently.
library;

import 'dart:ui' show Brightness, Color, PlatformDispatcher;

import 'package:flutter/material.dart';

import 'appearance_settings.dart';
import 'appearance_style.dart';
import 'contrast.dart';
import 'design_tokens.dart';
import 'settings_issue.dart';
import 'settings_messages.dart';

/// A resolved appearance: the theme, the numbers and the `ThemeData`.
final class ResolvedAppearance {
  const ResolvedAppearance({
    required this.settings,
    required this.themeId,
    required this.brightness,
    required this.style,
    required this.themeData,
    required this.report,
  });

  /// The preference this was resolved from.
  final AppearanceSettings settings;

  /// The `themes` key in force, after `system` was followed.
  final String themeId;

  /// The polarity of [themeId], which is also what `system` followed.
  final Brightness brightness;

  /// Every resolved number and colour, attached to [themeData].
  final AppearanceStyle style;

  /// The theme the app hands to `MaterialApp`.
  final ThemeData themeData;

  /// What could not be used as asked. Empty for every shipped combination.
  final SettingsReport report;

  /// Whether anything had to be reported.
  bool get hasWarnings => report.hasIssues;

  @override
  String toString() =>
      'ResolvedAppearance($themeId/${style.accentId}, $brightness, $style, $report)';
}

/// The pair of themes `MaterialApp` needs, and which one it should show.
///
/// A `system` preference needs both a light and a dark `ThemeData` and
/// `ThemeMode.system`; an explicit one needs its own theme in both slots, so
/// that a `themeMode` the app does not control cannot paint a theme the user
/// did not pick. That is the whole reason `system` is a value and not an
/// absence: the old build had no system theme, so a light-OS user picked the
/// light theme by hand on every fresh install.
final class AppearanceThemes {
  const AppearanceThemes({
    required this.light,
    required this.dark,
    required this.mode,
  });

  /// `MaterialApp.theme`.
  final ThemeData light;

  /// `MaterialApp.darkTheme`.
  final ThemeData dark;

  /// `MaterialApp.themeMode`.
  final ThemeMode mode;

  @override
  String toString() => 'AppearanceThemes($mode)';
}

/// Turns an [AppearanceSettings] into a `ThemeData`.
final class AppearanceResolver {
  const AppearanceResolver(this.tokens);

  /// The token file, as values. The only source of a colour, a size, a radius
  /// or a duration in this layer.
  final AppearanceTokens tokens;

  /// The minimum a derived on-colour pair must measure: the same floor the
  /// token file's `contrast` list uses for `textOnAccent` on `accent` and for
  /// `textOnStage` on `stage`.
  static const double minimumOnColourContrast = 4.5;

  /// The pair `MaterialApp` needs for [settings].
  ///
  /// `system` resolves both polarities: the light one to the token file's
  /// light theme, the dark one to the token file's default dark theme, and
  /// hands Flutter `ThemeMode.system`. An explicit theme fills BOTH slots with
  /// that theme and pins the mode to the theme's own polarity, so nothing
  /// outside this layer can swap in a theme the user did not choose - which is
  /// why [platformBrightness] only matters for a `system` preference: an
  /// explicit one is not a function of the platform at all.
  AppearanceThemes resolveThemes(
    AppearanceSettings settings, {
    Brightness? platformBrightness,
  }) {
    final String? explicit = settings.theme.themeId;
    if (explicit != null) {
      final ThemeData theme = resolve(
        settings,
        platformBrightness: tokens.isDarkTheme(explicit)
            ? Brightness.dark
            : Brightness.light,
      ).themeData;
      return AppearanceThemes(
        light: theme,
        dark: theme,
        mode: tokens.isDarkTheme(explicit) ? ThemeMode.dark : ThemeMode.light,
      );
    }
    return AppearanceThemes(
      light: resolve(settings, platformBrightness: Brightness.light).themeData,
      dark: resolve(settings, platformBrightness: Brightness.dark).themeData,
      mode: ThemeMode.system,
    );
  }

  /// Resolves [settings] for a platform brightness.
  ///
  /// [platformBrightness] is what `system` follows. It is a parameter rather
  /// than a hidden read so a test can state the platform it is testing, so a
  /// caller that already knows the answer does not ask for it twice, and so
  /// null means "read it from the platform".
  ResolvedAppearance resolve(
    AppearanceSettings settings, {
    Brightness? platformBrightness,
  }) {
    final Brightness platform = platformBrightness ?? currentPlatformBrightness;
    final String themeId = resolveThemeId(settings.theme, platform);
    final Brightness brightness = tokens.isDarkTheme(themeId)
        ? Brightness.dark
        : Brightness.light;
    final double density = _densityOf(settings.density);
    final double fontScale = AppearanceSettings.quantiseFontScale(
      settings.fontScale,
    );

    Map<String, Color> roles = settings.accent.isCustom
        ? _customAccentRoles(themeId, settings.accent.custom!)
        : Map<String, Color>.of(
            tokens.rolesFor(themeId, settings.accent.accentId),
          );

    if (settings.highContrast) {
      roles = _applyHighContrast(roles, brightness == Brightness.dark);
    }

    final AppearanceStyle style = _buildStyle(
      settings: settings,
      themeId: themeId,
      roles: roles,
      density: density,
      fontScale: fontScale,
    );
    final List<SettingsIssue> issues = <SettingsIssue>[
      ..._checkDeclaredPairs(roles),
      ..._checkDerivedOnColours(roles),
    ];
    final SettingsReport report = SettingsReport(
      List<SettingsIssue>.unmodifiable(issues),
    );

    return ResolvedAppearance(
      settings: settings,
      themeId: themeId,
      brightness: brightness,
      style: style,
      themeData: _buildThemeData(style),
      report: report,
    );
  }

  /// The `themes` key a preference resolves to for [platformBrightness].
  ///
  /// `system` picks the theme whose declared polarity matches the platform,
  /// preferring the token file's default among several that match, so a
  /// three-dark-theme token file still lands on the one it nominates rather
  /// than on whichever key happens to be listed first.
  String resolveThemeId(
    ThemePreference preference,
    Brightness platformBrightness,
  ) {
    final String? explicit = preference.themeId;
    if (explicit != null) return explicit;
    final bool wantDark = platformBrightness == Brightness.dark;
    final List<String> matching = tokens.themeIds
        .where((String id) => tokens.isDarkTheme(id) == wantDark)
        .toList(growable: false);
    if (matching.isEmpty) return tokens.defaultThemeId;
    if (matching.contains(tokens.defaultThemeId)) return tokens.defaultThemeId;
    return matching.first;
  }

  // --- metrics --------------------------------------------------------------

  double _densityOf(DensityPreference preference) {
    final String key = preference.densityId;
    final double? value = tokens.densities[key];
    if (value == null) {
      throw StateError('space.densities has no "$key" in the token file.');
    }
    return value;
  }

  AppearanceStyle _buildStyle({
    required AppearanceSettings settings,
    required String themeId,
    required Map<String, Color> roles,
    required double density,
    required double fontScale,
  }) {
    final Map<String, double> space = <String, double>{
      for (final MapEntry<String, double> step in tokens.spaceSteps.entries)
        step.key: step.value * density,
    };
    final Map<String, ResolvedTypeStep> typeScale = <String, ResolvedTypeStep>{
      for (final MapEntry<String, TypeStepMetrics> step
          in tokens.typeScale.entries)
        step.key: ResolvedTypeStep(
          size: step.value.size * fontScale,
          lineHeight: step.value.lineHeight,
          weight: fontWeightOf(step.value.weight),
          tracking: step.value.tracking * fontScale,
        ),
    };
    final double heightScale = tokens.controlSizesFollowDensity ? density : 1.0;
    final Map<String, ResolvedControl> controls = <String, ResolvedControl>{
      for (final MapEntry<String, ControlMetrics> size
          in tokens.controlSizes.entries)
        size.key: ResolvedControl(
          height: size.value.height * heightScale,
          paddingX: size.value.paddingX * heightScale,
          gap: size.value.gap * heightScale,
          fontSize: size.value.fontSize * fontScale,
          iconSize: size.value.iconSize,
        ),
    };
    // `motion.reducedMotionNote`: replace every duration with `instant`, which
    // is the token file's value rather than a hard-coded zero.
    final Duration instant = tokens.motionDurations['instant'] ?? Duration.zero;
    final Map<String, Duration> motion = <String, Duration>{
      for (final MapEntry<String, Duration> entry
          in tokens.motionDurations.entries)
        entry.key: settings.reduceMotion ? instant : entry.value,
    };
    final String? family = tokens.fontFamily;
    final List<String> fallback = tokens.fontFamilyFallback;

    return AppearanceStyle(
      themeId: themeId,
      accentId: settings.accent.accentId,
      roles: roles,
      space: space,
      spaceUnit: tokens.spaceUnit * density,
      radii: Map<String, double>.of(tokens.radiiFor(settings.radius.presetId)),
      radiusPresetId: settings.radius.presetId,
      typeScale: typeScale,
      textTheme: _buildTextTheme(typeScale, family, fallback),
      controls: controls,
      hitTargetMin: tokens.hitTargetMin,
      borderWidth: tokens.borderWidth,
      // High contrast widens the ring by the token file's own border width: a
      // thicker line is the other half of "more contrast", and the token file
      // declares exactly one ring width to widen.
      focusRingWidth: settings.highContrast
          ? tokens.focusRingWidth + tokens.borderWidth
          : tokens.focusRingWidth,
      focusRingGap: tokens.focusRingGap,
      motion: motion,
      motionEasing: tokens.motionEasing,
      density: density,
      fontScale: fontScale,
      highContrast: settings.highContrast,
      reduceMotion: settings.reduceMotion,
      fontFamily: family,
      fontFamilyFallback: fallback,
    );
  }

  /// Every [TextTheme] slot, from the resolved type scale.
  ///
  /// All fifteen are filled, and that is the point: an empty slot lets
  /// Material's own default size through, which is how a font scale ends up
  /// honoured on four screens out of ten.
  TextTheme _buildTextTheme(
    Map<String, ResolvedTypeStep> steps,
    String? family,
    List<String> fallback,
  ) {
    TextStyle of(String step) =>
        steps[step]!.style(fontFamily: family, fontFamilyFallback: fallback);
    return TextTheme(
      displayLarge: of('2xl'),
      displayMedium: of('2xl'),
      displaySmall: of('xl'),
      headlineLarge: of('xl'),
      headlineMedium: of('lg'),
      headlineSmall: of('lg'),
      titleLarge: of('lg'),
      titleMedium: of('md'),
      titleSmall: of('sm'),
      bodyLarge: of('md'),
      bodyMedium: of('sm'),
      bodySmall: of('xs'),
      labelLarge: of('sm'),
      labelMedium: of('2xs'),
      labelSmall: of('2xs'),
    );
  }

  // --- the palette ----------------------------------------------------------

  /// Builds a ramp around a colour the user picked, and never replaces it.
  ///
  /// * `hover` and `active` reuse the SHIPPED ramp's channel deltas, because
  ///   the token file's ramps are hand-picked hexes rather than mixes and the
  ///   deltas are the only description of "one step lighter" it contains.
  /// * `accentSoft` and `focusRing` are mixed exactly as `meta.sources` says,
  ///   with the theme's own `derive` amounts and target.
  /// * `textOnAccent` is whichever token extreme MEASURES best against the
  ///   fill, so a light custom accent gets dark text on it and a dark one gets
  ///   light text. This is what makes an arbitrary colour safe: a hard-coded
  ///   white on a yellow accent is the same unreadable-text class the redesign
  ///   exists to remove.
  Map<String, Color> _customAccentRoles(String themeId, Color base) {
    final Map<String, Color> shipped = tokens.rolesFor(
      themeId,
      tokens.defaultAccentId,
    );
    final Color referenceBase = shipped['accent']!;
    return <String, Color>{
      ...shipped,
      'accent': base,
      'accentHover': _applyDelta(base, shipped['accentHover']!, referenceBase),
      'accentActive': _applyDelta(
        base,
        shipped['accentActive']!,
        referenceBase,
      ),
      'accentSoft': mixColor(
        base,
        shipped['surface']!,
        tokens.accentSoftMixFor(themeId),
      ),
      'focusRing': mixColor(
        base,
        tokens.focusRingTargetFor(themeId),
        tokens.focusRingMixFor(themeId),
      ),
      'textOnAccent': onColourFor(base, shipped),
    };
  }

  /// [from] with the channel deltas between [baseRef] and [to] applied, which
  /// is how a shipped ramp steps from its base to its hover and its active.
  Color _applyDelta(Color from, Color to, Color baseRef) {
    final int fromArgb = from.toARGB32();
    final int toArgb = to.toARGB32();
    final int refArgb = baseRef.toARGB32();
    int channel(int shift) {
      final int delta =
          ((toArgb >> shift) & 0xff) - ((refArgb >> shift) & 0xff);
      return (((fromArgb >> shift) & 0xff) + delta).clamp(0, 255);
    }

    return Color.fromARGB(
      ((fromArgb >> 24) & 0xff).clamp(0, 255),
      channel(16),
      channel(8),
      channel(0),
    );
  }

  /// Pushes the ramps to their extremes.
  ///
  /// * the text ramp collapses from three steps to one, and the primary is
  ///   pushed to the theme's extreme: `textOnAccent` in a dark theme (white in
  ///   all four) and the always-dark `stage` in a light one.
  /// * the border ramp steps up: `border` takes `borderStrong`'s colour, and
  ///   `borderStrong` takes the strongest text step the theme had.
  ///
  /// Nothing is dimmed and no alpha appears, because the token file forbids
  /// expressing hierarchy with opacity - which is where the old 4.47:1
  /// timestamp came from.
  Map<String, Color> _applyHighContrast(Map<String, Color> roles, bool isDark) {
    final Color text = roles['text']!;
    final Color textMuted = roles['textMuted']!;
    final Color borderStrong = roles['borderStrong']!;
    final Color extreme = isDark ? roles['textOnAccent']! : roles['stage']!;
    return <String, Color>{
      ...roles,
      'text': extreme,
      'textMuted': text,
      'textSubtle': text,
      'border': borderStrong,
      'borderStrong': isDark ? textMuted : text,
    };
  }

  /// The token extreme that measures best on [fill]: `textOnAccent`, which is
  /// white in every theme, or the always-dark `stage`.
  ///
  /// Measured rather than assumed, because the token file's fills are not all
  /// dark: `danger` in a light theme is a mid red that only the dark extreme
  /// reaches 4.5:1 with, and `focusRing` in a dark theme is a pale tint that
  /// only the light one does.
  Color onColourFor(Color fill, Map<String, Color> roles) {
    final Color light = roles['textOnAccent']!;
    final Color dark = roles['stage']!;
    return contrastRatio(fill, light) >= contrastRatio(fill, dark)
        ? light
        : dark;
  }

  // --- the accessibility gate, run on the final colours ---------------------

  /// Measures every pair the token file declares, against the palette as it is
  /// about to be painted.
  List<SettingsIssue> _checkDeclaredPairs(Map<String, Color> roles) {
    final List<SettingsIssue> issues = <SettingsIssue>[];
    for (final ContrastRequirement requirement in tokens.contrastRequirements) {
      final Color? foreground = roles[requirement.foregroundRole];
      final Color? background = roles[requirement.backgroundRole];
      if (foreground == null || background == null) continue;
      final double ratio = contrastRatio(foreground, background);
      if (ratio >= requirement.minimum) continue;
      issues.add(
        SettingsIssue(
          problem: SettingsProblem.contrastRequirementFailed,
          key: '${requirement.foregroundRole} / ${requirement.backgroundRole}',
          detail:
              '${contrastLabel(foreground, background)} ölçüldü, '
              'en az ${requirement.minimum} gerekiyor',
        ),
      );
    }
    return issues;
  }

  /// Measures the on-colour pairs the resolver DERIVES, which the token file's
  /// list cannot cover because it only declares pairs for shipped roles.
  ///
  /// The four are the fills a `ColorScheme` actually paints text on: the accent,
  /// its hover, the focus ring and the danger colour.
  List<SettingsIssue> _checkDerivedOnColours(Map<String, Color> roles) {
    const List<String> fills = <String>[
      'accent',
      'accentHover',
      'focusRing',
      'danger',
    ];
    final List<SettingsIssue> issues = <SettingsIssue>[];
    for (final String fill in fills) {
      final Color? colour = roles[fill];
      if (colour == null) continue;
      final Color on = onColourFor(colour, roles);
      final double ratio = contrastRatio(on, colour);
      if (ratio >= minimumOnColourContrast) continue;
      issues.add(
        SettingsIssue(
          problem: SettingsProblem.contrastRequirementFailed,
          key: '$fill / on',
          detail:
              '$fill üzerine yazılan metin ${contrastLabel(on, colour)} '
              'ölçüldü, en az $minimumOnColourContrast gerekiyor',
        ),
      );
    }
    return issues;
  }

  // --- the ThemeData --------------------------------------------------------

  /// Builds the `ThemeData`, filling every slot a Material default would
  /// otherwise fill with a colour the token file never declared.
  ///
  /// That is the second half of the "unreadable text" fix: `ThemeData`'s own
  /// defaults include `Colors.white.withOpacity(0.12)` hover tints,
  /// `Colors.black38` disabled text and a `surfaceVariant` computed from the
  /// primary, none of which the contrast gate has ever measured.
  ThemeData _buildThemeData(AppearanceStyle style) {
    final Map<String, Color> roles = style.roles;
    final bool isDark =
        style.roles['stage'] != null &&
        relativeLuminance(roles['bg']!) < relativeLuminance(roles['text']!);
    final Color accent = roles['accent']!;
    final Color onAccent = roles['textOnAccent']!;
    final Color text = roles['text']!;
    final Color textMuted = roles['textMuted']!;
    final Color surface = roles['surface']!;
    final Color border = roles['border']!;
    final Color borderStrong = roles['borderStrong']!;
    // The subtle and the strong step of the surface ramp, chosen by how far
    // each one sits from `surface` rather than by the theme's polarity: in a
    // dark theme the soft well is the lighter step, in a light theme it is the
    // darker one.
    final Color raised = roles['surfaceRaised']!;
    final Color soft = roles['surfaceSoft']!;
    final Color subtleStep = _isCloserTo(surface, raised, soft) ? raised : soft;
    final Color strongStep = identical(subtleStep, raised) ? soft : raised;

    final ColorScheme scheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: roles['accentSoft']!,
      onPrimaryContainer: text,
      secondary: roles['accentHover']!,
      onSecondary: onColourFor(roles['accentHover']!, roles),
      secondaryContainer: raised,
      onSecondaryContainer: text,
      tertiary: roles['focusRing']!,
      onTertiary: onColourFor(roles['focusRing']!, roles),
      tertiaryContainer: soft,
      onTertiaryContainer: text,
      // `error` is the role the token file validates as TEXT on every surface
      // (`danger` clears 4.5:1 on bg, surface and surfaceRaised in all four
      // themes). `dangerFill` is a validated FILL and is what a destructive
      // button uses, set explicitly in [filledButtonStyle] below.
      error: roles['danger']!,
      onError: onColourFor(roles['danger']!, roles),
      errorContainer: soft,
      onErrorContainer: text,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: textMuted,
      surfaceDim: roles['bg']!,
      surfaceBright: roles['surfaceOverlay']!,
      surfaceContainerLowest: roles['surfaceOverlay']!,
      surfaceContainerLow: surface,
      surfaceContainer: raised,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: soft,
      outline: border,
      // MKVI has exactly one divider colour, and it clears 3:1 on every
      // surface. Using it for both outline slots is the safe direction; a
      // second, subtler line is what measured 1.6:1 in the old UI.
      outlineVariant: border,
      shadow: roles['shadow1']!,
      scrim: roles['scrim']!,
      inverseSurface: roles['stage']!,
      onInverseSurface: roles['textOnStage']!,
      // The token system's own "light primary": the focus ring is the one
      // accent-tinted colour in a dark theme that is validated at 4.5:1, and
      // the token file forbids accent-coloured text everywhere else.
      inversePrimary: isDark ? roles['focusRing']! : roles['accentActive']!,
      // MKVI expresses elevation with the surface roles, not with a tint, so
      // the tint is the window background and cannot wash out a measured pair.
      surfaceTint: roles['bg']!,
    );

    final ResolvedControl md = style.control('md');
    final ResolvedControl sm = style.control('sm');

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      scaffoldBackgroundColor: roles['bg']!,
      canvasColor: roles['bg']!,
      cardColor: surface,
      dividerColor: border,
      focusColor: roles['accentSoft']!,
      hoverColor: subtleStep,
      highlightColor: strongStep,
      splashColor: accent,
      disabledColor: roles['textSubtle']!,
      unselectedWidgetColor: border,
      hintColor: roles['textSubtle']!,
      shadowColor: roles['shadow1']!,
      textTheme: style.textTheme,
      primaryTextTheme: style.textTheme.apply(
        bodyColor: onAccent,
        displayColor: onAccent,
      ),
      iconTheme: IconThemeData(color: text, size: md.iconSize),
      primaryIconTheme: IconThemeData(color: onAccent, size: md.iconSize),
      appBarTheme: AppBarThemeData(
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: roles['bg']!,
        elevation: 0,
        titleTextStyle: style.styleOf('lg').copyWith(color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: roles['bg']!,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: style.shape('md'),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: roles['surfaceOverlay']!,
        surfaceTintColor: roles['bg']!,
        elevation: 0,
        shape: style.shape('lg'),
        titleTextStyle: style.styleOf('lg').copyWith(color: text),
        contentTextStyle: style.styleOf('md').copyWith(color: textMuted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: roles['surfaceOverlay']!,
        surfaceTintColor: roles['bg']!,
        elevation: 0,
        shape: style.shape('lg'),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textMuted,
        textColor: text,
        shape: style.shape('sm'),
        contentPadding: EdgeInsets.symmetric(horizontal: md.paddingX),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: style.borderWidth,
        space: style.gap('4'),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: soft,
        hintStyle: style.styleOf('md').copyWith(color: roles['textSubtle']!),
        labelStyle: style.styleOf('sm').copyWith(color: textMuted),
        errorStyle: style.styleOf('sm').copyWith(color: roles['danger']!),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
        contentPadding: EdgeInsets.symmetric(
          horizontal: md.paddingX,
          vertical: style.gap('3'),
        ),
        border: _inputBorder(style, borderStrong),
        enabledBorder: _inputBorder(style, borderStrong),
        focusedBorder: _inputBorder(
          style,
          borderStrong,
          width: style.focusRingWidth,
        ),
        errorBorder: _inputBorder(style, roles['danger']!),
        focusedErrorBorder: _inputBorder(
          style,
          roles['danger']!,
          width: style.focusRingWidth,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: _filledButtonStyle(style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _outlinedButtonStyle(style, onAccent),
      ),
      textButtonTheme: TextButtonThemeData(
        style: _textButtonStyle(style, onAccent),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: _iconButtonStyle(style, accent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: roles['accentSoft']!,
        labelStyle: style.styleOf('sm').copyWith(color: text),
        secondaryLabelStyle: style.styleOf('sm').copyWith(color: textMuted),
        side: BorderSide.none,
        shape: style.shape('pill'),
        padding: EdgeInsets.symmetric(
          horizontal: sm.gap,
          vertical: style.gap('1'),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raised,
        contentTextStyle: style.styleOf('md').copyWith(color: text),
        // The focus ring is the token file's one accent-tinted colour that is
        // validated at 4.5:1 on every surface, which is exactly what an action
        // label on a snackbar is.
        actionTextColor: roles['focusRing']!,
        shape: style.shape('sm'),
        behavior: SnackBarBehavior.floating,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: roles['surfaceOverlay']!,
          border: Border.all(color: border),
          borderRadius: style.shape('sm').borderRadius,
        ),
        textStyle: style.styleOf('xs').copyWith(color: text),
        padding: EdgeInsets.symmetric(
          horizontal: sm.paddingX,
          vertical: style.gap('1'),
        ),
        waitDuration: style.duration('fast'),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? onAccent
              : roles['textSubtle'],
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.selected) ? accent : border,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? roles['accentActive']
              : borderStrong,
        ),
      ),
      // A ripple is motion, so reduced motion switches it off rather than
      // merely shortening it: the ink itself is the animation.
      splashFactory: style.reduceMotion
          ? NoSplash.splashFactory
          : InkRipple.splashFactory,
      extensions: <ThemeExtension<Object?>>[style],
    );
  }

  OutlineInputBorder _inputBorder(
    AppearanceStyle style,
    Color colour, {
    double? width,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(style.radius('sm'))),
      borderSide: BorderSide(color: colour, width: width ?? style.borderWidth),
    );
  }

  ButtonStyle _filledButtonStyle(AppearanceStyle style) {
    final Map<String, Color> roles = style.roles;
    final ResolvedControl md = style.control('md');
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) return roles['surfaceSoft'];
        if (states.contains(WidgetState.pressed)) return roles['accentActive'];
        if (states.contains(WidgetState.hovered)) return roles['accentHover'];
        return roles['accent'];
      }),
      // A destructive button is the one place `dangerFill` is painted, and the
      // token file validates `textOnAccent` on it in all four themes.
      foregroundColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => states.contains(WidgetState.disabled)
            ? roles['textSubtle']
            : roles['textOnAccent'],
      ),
      minimumSize: WidgetStatePropertyAll<Size>(Size(0, md.height)),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: md.paddingX),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(style.shape('md')),
      textStyle: WidgetStatePropertyAll<TextStyle>(
        style.styleOf('sm').copyWith(color: roles['textOnAccent']),
      ),
    );
  }

  ButtonStyle _outlinedButtonStyle(AppearanceStyle style, Color onAccent) {
    final Map<String, Color> roles = style.roles;
    final ResolvedControl md = style.control('md');
    return ButtonStyle(
      foregroundColor: WidgetStatePropertyAll<Color?>(onAccent),
      minimumSize: WidgetStatePropertyAll<Size>(Size(0, md.height)),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: md.paddingX),
      ),
      side: WidgetStatePropertyAll<BorderSide>(
        BorderSide(color: roles['borderStrong']!, width: style.borderWidth),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(style.shape('md')),
      textStyle: WidgetStatePropertyAll<TextStyle>(style.styleOf('sm')),
    );
  }

  ButtonStyle _textButtonStyle(AppearanceStyle style, Color onAccent) {
    final ResolvedControl md = style.control('md');
    return ButtonStyle(
      foregroundColor: WidgetStatePropertyAll<Color?>(onAccent),
      minimumSize: WidgetStatePropertyAll<Size>(Size(0, md.height)),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: md.paddingX),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(style.shape('md')),
      textStyle: WidgetStatePropertyAll<TextStyle>(style.styleOf('sm')),
    );
  }

  ButtonStyle _iconButtonStyle(AppearanceStyle style, Color accent) {
    final ResolvedControl md = style.control('md');
    return ButtonStyle(
      foregroundColor: WidgetStatePropertyAll<Color?>(accent),
      minimumSize: WidgetStatePropertyAll<Size>(Size(md.height, md.height)),
      shape: WidgetStatePropertyAll<OutlinedBorder>(style.shape('md')),
    );
  }
}

/// Whether [candidate] sits closer to [from] than [other] does, measured.
bool _isCloserTo(Color from, Color candidate, Color other) {
  return (contrastRatio(from, candidate) - 1).abs() <=
      (contrastRatio(from, other) - 1).abs();
}

/// The platform brightness right now.
Brightness get currentPlatformBrightness =>
    PlatformDispatcher.instance.platformBrightness;

/// The [FontWeight] for a `type.weights` value, which the token file stores as
/// a hundredths number (400, 500, 600, 700).
FontWeight fontWeightOf(int hundredths) {
  final int index = hundredths ~/ 100 - 1;
  if (index < 0 || index >= FontWeight.values.length) return FontWeight.w400;
  return FontWeight.values[index];
}
