/// The RESOLVED appearance: every token already multiplied out.
///
/// This is the value the whole app reads. It is attached to the `ThemeData` as
/// a [ThemeExtension], so a widget asks
/// `AppearanceStyle.of(context).space['4']` and gets a number that already
/// includes the user's density, rather than multiplying a token by a number
/// read out of a settings object and hoping every call site did it.
///
/// That is the whole answer to the first two live defects:
///
/// * `fontScale` did nothing on the first-run screens because the old UI
///   scaled one element and every child rule used its own literal. Here
///   [typeScale] is the ONLY font size source, each step already multiplied by
///   the user's scale, and [textTheme] in the same object is built from those
///   same steps - so there is no second place for a size to hide in.
/// * `density` was honoured in 8 places out of ~40 because it was a value
///   nobody was obliged to read. Here [space] and [controls] are resolved once
///   and there is nothing left to honour: a widget either uses a resolved
///   number or it hard-codes one, and the second is a bug with no excuse.
///
/// Every number in this object came from `design/tokens.json` multiplied by a
/// preference. Nothing here is a literal.
library;

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';

import 'contrast.dart';

/// One type step, resolved: [size] and [tracking] already carry `fontScale`.
final class ResolvedTypeStep {
  const ResolvedTypeStep({
    required this.size,
    required this.lineHeight,
    required this.weight,
    required this.tracking,
  });

  /// Font size in logical pixels, `token * fontScale`.
  final double size;

  /// Line height as a multiple of [size]. Never scaled: it is a ratio.
  final double lineHeight;

  /// `FontWeight` of the step, from `type.weights`.
  final FontWeight weight;

  /// Letter spacing in logical pixels, `token * fontScale`.
  final double tracking;

  /// The [TextStyle] for this step, in the app's own font family.
  TextStyle style({String? fontFamily, List<String>? fontFamilyFallback}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFamilyFallback,
        fontSize: size,
        height: lineHeight,
        fontWeight: weight,
        letterSpacing: tracking,
      );

  @override
  bool operator ==(Object other) =>
      other is ResolvedTypeStep &&
      other.size == size &&
      other.lineHeight == lineHeight &&
      other.weight == weight &&
      other.tracking == tracking;

  @override
  int get hashCode => Object.hash(size, lineHeight, weight, tracking);
}

/// One control size, resolved: height, padding and gap carry `density`, the
/// font size carries `fontScale`, the icon size carries neither.
final class ResolvedControl {
  const ResolvedControl({
    required this.height,
    required this.paddingX,
    required this.gap,
    required this.fontSize,
    required this.iconSize,
  });

  /// Control height in logical pixels.
  final double height;

  /// Horizontal padding in logical pixels.
  final double paddingX;

  /// Gap between leading icon and label.
  final double gap;

  /// The control's font size.
  final double fontSize;

  /// The control's icon size.
  final double iconSize;

  @override
  bool operator ==(Object other) =>
      other is ResolvedControl &&
      other.height == height &&
      other.paddingX == paddingX &&
      other.gap == gap &&
      other.fontSize == fontSize &&
      other.iconSize == iconSize;

  @override
  int get hashCode => Object.hash(height, paddingX, gap, fontSize, iconSize);

  @override
  String toString() => 'ResolvedControl(h: $height, p: $paddingX)';
}

/// The resolved appearance, carried on the `ThemeData`.
///
/// Immutable, complete, and the only place a widget should read spacing, radii,
/// type, control metrics, durations or a raw token role from.
class AppearanceStyle extends ThemeExtension<AppearanceStyle> {
  const AppearanceStyle({
    required this.themeId,
    required this.accentId,
    required this.roles,
    required this.space,
    required this.spaceUnit,
    required this.radii,
    required this.radiusPresetId,
    required this.typeScale,
    required this.textTheme,
    required this.controls,
    required this.hitTargetMin,
    required this.borderWidth,
    required this.focusRingWidth,
    required this.focusRingGap,
    required this.motion,
    required this.motionEasing,
    required this.density,
    required this.fontScale,
    required this.highContrast,
    required this.reduceMotion,
    required this.fontFamily,
    required this.fontFamilyFallback,
  });

  /// The style of the nearest [ThemeData].
  ///
  /// Throws when there is none, on purpose: a widget that has to invent its own
  /// spacing is exactly the bug this object exists to remove.
  static AppearanceStyle of(BuildContext context) {
    final AppearanceStyle? style = Theme.of(
      context,
    ).extension<AppearanceStyle>();
    if (style == null) {
      throw FlutterError(
        'No AppearanceStyle on this ThemeData. The app must be built with '
        'AppearanceResolver.resolve(...).themeData.',
      );
    }
    return style;
  }

  /// The `themes` key these colours came from.
  final String themeId;

  /// The `accents` key, or `custom`.
  final String accentId;

  /// The 29 colour roles, exactly as the app is about to paint them, i.e.
  /// AFTER the high-contrast adjustment.
  final Map<String, Color> roles;

  /// `space.steps * density`, keyed by token name ('0' .. '10').
  final Map<String, double> space;

  /// `space.unit * density`: one multiplier for everything in [space].
  final double spaceUnit;

  /// `radius.steps` of the chosen preset, keyed by token name.
  final Map<String, double> radii;

  /// The `radius.presets` key these radii came from.
  final String radiusPresetId;

  /// `type.steps * fontScale`, keyed by token name ('2xs' .. '2xl').
  final Map<String, ResolvedTypeStep> typeScale;

  /// Every [TextTheme] slot, built from [typeScale]. No Material default size
  /// can leak in, because every slot is filled.
  final TextTheme textTheme;

  /// `control.sizes`, resolved, keyed by token name ('sm', 'md', 'lg').
  final Map<String, ResolvedControl> controls;

  /// `control.hitTargetMin`. Never scaled.
  final double hitTargetMin;

  /// `control.borderWidth`.
  final double borderWidth;

  /// `control.focusRingWidth`, widened under [highContrast].
  final double focusRingWidth;

  /// `control.focusRingGap`.
  final double focusRingGap;

  /// `motion.durations`, or every value zero when [reduceMotion].
  final Map<String, Duration> motion;

  /// `motion.easing.cubic`.
  final Cubic motionEasing;

  /// The `space.densities` value in force.
  final double density;

  /// The user's type multiplier in force.
  final double fontScale;

  /// Whether the ramps were pushed towards their extremes.
  final bool highContrast;

  /// Whether every duration is `instant`.
  final bool reduceMotion;

  /// `type.fontFamily`'s first entry, or null.
  final String? fontFamily;

  /// `type.fontFamily` minus the first entry.
  final List<String> fontFamilyFallback;

  /// One colour role, after the high-contrast adjustment.
  Color role(String name) => roles[name]!;

  /// One spacing step, density already applied.
  double gap(String step) => space[step]!;

  /// One radius, preset already applied.
  double radius(String step) => radii[step]!;

  /// One type step, scale already applied.
  ResolvedTypeStep typeStep(String step) => typeScale[step]!;

  /// One control size, density and scale already applied.
  ResolvedControl control(String size) => controls[size]!;

  /// One duration, reduced motion already applied.
  Duration duration(String name) => motion[name]!;

  /// The measured ratio between two roles of the palette about to be painted.
  double contrast(String foregroundRole, String backgroundRole) =>
      contrastRatio(role(foregroundRole), role(backgroundRole));

  /// The `TextStyle` for one type step.
  TextStyle styleOf(String step) => typeStep(
    step,
  ).style(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback);

  /// A rounded rectangle in one of the token radii.
  RoundedRectangleBorder shape(String radiusStep) => RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radius(radiusStep))),
  );

  @override
  AppearanceStyle copyWith({
    String? themeId,
    String? accentId,
    Map<String, Color>? roles,
    Map<String, double>? space,
    double? spaceUnit,
    Map<String, double>? radii,
    String? radiusPresetId,
    Map<String, ResolvedTypeStep>? typeScale,
    TextTheme? textTheme,
    Map<String, ResolvedControl>? controls,
    double? hitTargetMin,
    double? borderWidth,
    double? focusRingWidth,
    double? focusRingGap,
    Map<String, Duration>? motion,
    Cubic? motionEasing,
    double? density,
    double? fontScale,
    bool? highContrast,
    bool? reduceMotion,
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    return AppearanceStyle(
      themeId: themeId ?? this.themeId,
      accentId: accentId ?? this.accentId,
      roles: roles ?? this.roles,
      space: space ?? this.space,
      spaceUnit: spaceUnit ?? this.spaceUnit,
      radii: radii ?? this.radii,
      radiusPresetId: radiusPresetId ?? this.radiusPresetId,
      typeScale: typeScale ?? this.typeScale,
      textTheme: textTheme ?? this.textTheme,
      controls: controls ?? this.controls,
      hitTargetMin: hitTargetMin ?? this.hitTargetMin,
      borderWidth: borderWidth ?? this.borderWidth,
      focusRingWidth: focusRingWidth ?? this.focusRingWidth,
      focusRingGap: focusRingGap ?? this.focusRingGap,
      motion: motion ?? this.motion,
      motionEasing: motionEasing ?? this.motionEasing,
      density: density ?? this.density,
      fontScale: fontScale ?? this.fontScale,
      highContrast: highContrast ?? this.highContrast,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      fontFamily: fontFamily ?? this.fontFamily,
      fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
    );
  }

  @override
  AppearanceStyle lerp(AppearanceStyle? other, double t) {
    if (other == null) return this;
    return AppearanceStyle(
      themeId: t < 0.5 ? themeId : other.themeId,
      accentId: t < 0.5 ? accentId : other.accentId,
      roles: _lerpColors(roles, other.roles, t),
      space: _lerpDoubles(space, other.space, t),
      spaceUnit: _lerpDouble(spaceUnit, other.spaceUnit, t),
      radii: _lerpDoubles(radii, other.radii, t),
      radiusPresetId: t < 0.5 ? radiusPresetId : other.radiusPresetId,
      typeScale: <String, ResolvedTypeStep>{
        for (final String step in typeScale.keys)
          step: ResolvedTypeStep(
            size: _lerpDouble(
              typeScale[step]!.size,
              other.typeScale[step]!.size,
              t,
            ),
            lineHeight: _lerpDouble(
              typeScale[step]!.lineHeight,
              other.typeScale[step]!.lineHeight,
              t,
            ),
            weight: t < 0.5
                ? typeScale[step]!.weight
                : other.typeScale[step]!.weight,
            tracking: _lerpDouble(
              typeScale[step]!.tracking,
              other.typeScale[step]!.tracking,
              t,
            ),
          ),
      },
      textTheme: TextTheme.lerp(textTheme, other.textTheme, t),
      controls: <String, ResolvedControl>{
        for (final String size in controls.keys)
          size: ResolvedControl(
            height: _lerpDouble(
              controls[size]!.height,
              other.controls[size]!.height,
              t,
            ),
            paddingX: _lerpDouble(
              controls[size]!.paddingX,
              other.controls[size]!.paddingX,
              t,
            ),
            gap: _lerpDouble(controls[size]!.gap, other.controls[size]!.gap, t),
            fontSize: _lerpDouble(
              controls[size]!.fontSize,
              other.controls[size]!.fontSize,
              t,
            ),
            iconSize: _lerpDouble(
              controls[size]!.iconSize,
              other.controls[size]!.iconSize,
              t,
            ),
          ),
      },
      hitTargetMin: _lerpDouble(hitTargetMin, other.hitTargetMin, t),
      borderWidth: _lerpDouble(borderWidth, other.borderWidth, t),
      focusRingWidth: _lerpDouble(focusRingWidth, other.focusRingWidth, t),
      focusRingGap: _lerpDouble(focusRingGap, other.focusRingGap, t),
      motion: <String, Duration>{
        for (final String name in motion.keys)
          name: Duration(
            microseconds: _lerpDouble(
              motion[name]!.inMicroseconds.toDouble(),
              other.motion[name]!.inMicroseconds.toDouble(),
              t,
            ).round(),
          ),
      },
      motionEasing: motionEasing,
      density: _lerpDouble(density, other.density, t),
      fontScale: _lerpDouble(fontScale, other.fontScale, t),
      highContrast: t < 0.5 ? highContrast : other.highContrast,
      reduceMotion: t < 0.5 ? reduceMotion : other.reduceMotion,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  @override
  String toString() =>
      'AppearanceStyle($themeId/$accentId, density: $density, '
      'fontScale: $fontScale, highContrast: $highContrast, '
      'reduceMotion: $reduceMotion)';

  /// Two styles are equal when they would paint the same app.
  ///
  /// This is not decoration: a `ThemeData` compares its extensions, so without
  /// it two resolves of the same preference would look different and every
  /// "this preference changed the theme" assertion in the test-suite would pass
  /// on identity alone - which is exactly the kind of assertion that hid the
  /// density defect for a whole release.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppearanceStyle) return false;
    return other.themeId == themeId &&
        other.accentId == accentId &&
        mapEquals(other.roles, roles) &&
        mapEquals(other.space, space) &&
        other.spaceUnit == spaceUnit &&
        mapEquals(other.radii, radii) &&
        other.radiusPresetId == radiusPresetId &&
        _mapEquals(other.typeScale, typeScale) &&
        other.textTheme == textTheme &&
        _mapEquals(other.controls, controls) &&
        other.hitTargetMin == hitTargetMin &&
        other.borderWidth == borderWidth &&
        other.focusRingWidth == focusRingWidth &&
        other.focusRingGap == focusRingGap &&
        mapEquals(other.motion, motion) &&
        other.motionEasing == motionEasing &&
        other.density == density &&
        other.fontScale == fontScale &&
        other.highContrast == highContrast &&
        other.reduceMotion == reduceMotion &&
        other.fontFamily == fontFamily &&
        listEquals(other.fontFamilyFallback, fontFamilyFallback);
  }

  /// `mapEquals` for maps whose values have their own `==`.
  static bool _mapEquals<T>(Map<String, T> a, Map<String, T> b) {
    if (a.length != b.length) return false;
    for (final MapEntry<String, T> entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    themeId,
    accentId,
    Object.hashAllUnordered(roles.values),
    Object.hashAllUnordered(space.values),
    spaceUnit,
    Object.hashAllUnordered(radii.values),
    radiusPresetId,
    Object.hashAllUnordered(typeScale.values),
    textTheme,
    Object.hashAllUnordered(controls.values),
    hitTargetMin,
    borderWidth,
    focusRingWidth,
    focusRingGap,
    Object.hashAllUnordered(motion.values),
    motionEasing,
    density,
    fontScale,
    highContrast,
    reduceMotion,
    fontFamily,
    Object.hashAllUnordered(fontFamilyFallback),
  ]);
}

Map<String, double> _lerpDoubles(
  Map<String, double> a,
  Map<String, double> b,
  double t,
) {
  return <String, double>{
    for (final String key in a.keys)
      key: _lerpDouble(a[key]!, b[key] ?? a[key]!, t),
  };
}

Map<String, Color> _lerpColors(
  Map<String, Color> a,
  Map<String, Color> b,
  double t,
) {
  return <String, Color>{
    for (final String key in a.keys)
      key: Color.lerp(a[key]!, b[key] ?? a[key]!, t)!,
  };
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
