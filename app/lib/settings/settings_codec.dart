/// The appearance document: one JSON string in, one value and one report out.
///
/// ## The rule
///
/// Decoding never returns a bare value. It returns an [AppearanceDocument] -
/// the value AND every correction that had to be made to get it - so "the
/// stored value was invalid" is unrepresentable as a silent fall back to the
/// default. The old build read a settings blob and anything it could not parse
/// became the default with nothing said; a user who had chosen the plum theme
/// came back to midnight, with no reason and no way back.
///
/// ## What is reported and what is not
///
/// * A field that is ABSENT is not a problem. A document written by a build
///   that had fewer fields is read as far as it goes, silently: that is
///   forward and backward compatibility, not corruption.
/// * A field that is PRESENT and unusable is a problem, and each case has its
///   own reason: wrong shape, unknown enum id, out of range, not on a slider
///   step, or a colour that is not a colour.
/// * An unknown KEY is ignored. A newer build may have written it.
///
/// Ids are stored the way `design/tokens.json` spells them ('compact',
/// 'cozy'), the enum's own name is accepted as an alias so a value typed by
/// hand is not thrown away, and a custom accent is stored as `#RRGGBB` or
/// `#RRGGBBAA` - the same text the settings screen shows.
library;

import 'dart:convert';

import 'appearance_settings.dart';
import 'contrast.dart';
import 'settings_issue.dart';
import 'settings_messages.dart';

/// A decoded appearance document: the value, and what had to be corrected.
final class AppearanceDocument {
  const AppearanceDocument(this.settings, this.report);

  /// The usable value. Always complete: a field that could not be read is
  /// filled from the default and named in [report].
  final AppearanceSettings settings;

  /// Every correction, in the order it was found.
  final SettingsReport report;

  @override
  String toString() => 'AppearanceDocument($settings, $report)';
}

/// Reads and writes the appearance document.
final class SettingsCodec {
  const SettingsCodec();

  /// The document version this build writes and understands.
  static const int version = 1;

  /// The document keys. Public so the repository and the tests can name them
  /// instead of repeating the literals.
  static const String versionKey = 'v';
  static const String themeKey = 'theme';
  static const String accentKey = 'accent';
  static const String customAccentKey = 'custom';
  static const String fontScaleKey = 'fontScale';
  static const String densityKey = 'density';
  static const String radiusKey = 'radius';
  static const String highContrastKey = 'highContrast';
  static const String reduceMotionKey = 'reduceMotion';

  /// Encodes [appearance] as a single-line JSON object with a fixed key order,
  /// so two documents are byte-comparable and a diff is readable.
  String encodeAppearance(AppearanceSettings appearance) {
    return jsonEncode(<String, Object?>{
      versionKey: version,
      themeKey: appearance.theme.name,
      accentKey: appearance.accent.isCustom
          ? <String, Object?>{customAccentKey: hexOf(appearance.accent.custom!)}
          : appearance.accent.accentId,
      fontScaleKey: appearance.fontScale,
      densityKey: appearance.density.densityId,
      radiusKey: appearance.radius.presetId,
      highContrastKey: appearance.highContrast,
      reduceMotionKey: appearance.reduceMotion,
    });
  }

  /// Decodes [source], correcting and reporting whatever it has to.
  ///
  /// Never throws. A document that is not JSON, not an object, or not a shape
  /// this build knows about comes back as [AppearanceSettings.initial] with a
  /// report saying exactly that. Losing every appearance choice because one of
  /// them was corrupt is worse than starting over - as long as the user is
  /// told, which is the whole point of this class.
  AppearanceDocument decodeAppearance(String source) {
    final _Report report = _Report();
    final Map<String, Object?>? document = _parseObject(source, report);
    if (document == null) {
      return AppearanceDocument(AppearanceSettings.initial, report.build());
    }
    _readVersion(document, report);
    final AppearanceSettings appearance = _readAppearance(document, report);
    return AppearanceDocument(appearance, report.build());
  }

  // --- document -------------------------------------------------------------

  /// The JSON object at the top level, or null with a report.
  Map<String, Object?>? _parseObject(String source, _Report report) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source) as Object?;
    } on FormatException {
      report.add(
        const SettingsIssue(
          problem: SettingsProblem.malformedDocument,
          key: versionKey,
          received: 'geçersiz JSON',
        ),
      );
      return null;
    }
    if (decoded is! Map) {
      report.add(
        const SettingsIssue(
          problem: SettingsProblem.malformedDocument,
          key: versionKey,
          received: 'nesne değil',
        ),
      );
      return null;
    }
    return _asStringKeyed(decoded);
  }

  /// A newer document is read as far as this build understands it, and says so.
  void _readVersion(Map<String, Object?> document, _Report report) {
    final Object? stored = document[versionKey];
    if (stored == null) return;
    if (stored is! int) {
      report.add(
        const SettingsIssue(
          problem: SettingsProblem.wrongType,
          key: versionKey,
          received: 'sayı değil',
          applied: '1',
        ),
      );
      return;
    }
    if (stored > version) {
      report.add(
        SettingsIssue(
          problem: SettingsProblem.futureVersion,
          key: versionKey,
          received: '$stored',
          applied: '$version',
        ),
      );
    }
  }

  // --- fields ---------------------------------------------------------------

  AppearanceSettings _readAppearance(
    Map<String, Object?> document,
    _Report report,
  ) {
    return AppearanceSettings(
      theme: _readTheme(document, report),
      accent: _readAccent(document, report),
      fontScale: _readFontScale(document, report),
      density: _readDensity(document, report),
      radius: _readRadius(document, report),
      highContrast: _readBool(document, highContrastKey, report),
      reduceMotion: _readBool(document, reduceMotionKey, report),
    );
  }

  ThemePreference _readTheme(Map<String, Object?> document, _Report report) {
    final Object? stored = document[themeKey];
    if (stored == null) return ThemePreference.system;
    if (stored is! String) {
      report.add(
        SettingsIssue(
          problem: SettingsProblem.wrongType,
          key: themeKey,
          received: _render(stored),
          applied: ThemePreference.system.name,
        ),
      );
      return ThemePreference.system;
    }
    for (final ThemePreference candidate in ThemePreference.values) {
      if (candidate.name == stored) return candidate;
    }
    report.add(
      SettingsIssue(
        problem: SettingsProblem.unknownTheme,
        key: themeKey,
        received: stored,
        applied: ThemePreference.system.name,
      ),
    );
    return ThemePreference.system;
  }

  AccentPreference _readAccent(Map<String, Object?> document, _Report report) {
    final Object? stored = document[accentKey];
    if (stored == null) return const AccentPreference.preset(AccentId.blue);
    if (stored is String) {
      final AccentId? preset = AccentId.fromAccentId(stored);
      if (preset != null) return AccentPreference.preset(preset);
      report.add(
        SettingsIssue(
          problem: SettingsProblem.unknownAccent,
          key: accentKey,
          received: stored,
          applied: AccentId.blue.name,
        ),
      );
      return const AccentPreference.preset(AccentId.blue);
    }
    if (stored is Map) {
      final Map<String, Object?> custom = _asStringKeyed(stored);
      final Object? raw = custom[customAccentKey];
      if (raw is String) {
        final parsed = tryParseHexColor(raw);
        if (parsed != null) return AccentPreference.custom(parsed);
        report.add(
          SettingsIssue(
            problem: SettingsProblem.badAccentColour,
            key: accentKey,
            received: raw,
            applied: AccentId.blue.name,
          ),
        );
        return const AccentPreference.preset(AccentId.blue);
      }
      report.add(
        SettingsIssue(
          problem: SettingsProblem.badAccentColour,
          key: '$accentKey.$customAccentKey',
          received: _render(raw ?? custom),
          applied: AccentId.blue.name,
        ),
      );
      return const AccentPreference.preset(AccentId.blue);
    }
    report.add(
      SettingsIssue(
        problem: SettingsProblem.wrongType,
        key: accentKey,
        received: _render(stored),
        applied: AccentId.blue.name,
      ),
    );
    return const AccentPreference.preset(AccentId.blue);
  }

  double _readFontScale(Map<String, Object?> document, _Report report) {
    final Object? stored = document[fontScaleKey];
    if (stored == null) return AppearanceSettings.defaultFontScale;
    if (stored is! num) {
      report.add(
        SettingsIssue(
          problem: SettingsProblem.fontScaleNotANumber,
          key: fontScaleKey,
          received: _render(stored),
          applied: _renderNumber(AppearanceSettings.defaultFontScale),
        ),
      );
      return AppearanceSettings.defaultFontScale;
    }
    final double raw = stored.toDouble();
    final double normalised = AppearanceSettings.quantiseFontScale(raw);
    if (normalised == raw) return raw;
    final bool outOfRange =
        raw < AppearanceSettings.minFontScale ||
        raw > AppearanceSettings.maxFontScale;
    report.add(
      SettingsIssue(
        problem: outOfRange
            ? SettingsProblem.fontScaleOutOfRange
            : SettingsProblem.fontScaleNotOnStep,
        key: fontScaleKey,
        received: _renderNumber(raw),
        applied: _renderNumber(normalised),
      ),
    );
    return normalised;
  }

  DensityPreference _readDensity(
    Map<String, Object?> document,
    _Report report,
  ) {
    final Object? stored = document[densityKey];
    if (stored == null) return DensityPreference.comfortable;
    if (stored is! String) {
      report.add(
        SettingsIssue(
          problem: SettingsProblem.wrongType,
          key: densityKey,
          received: _render(stored),
          applied: DensityPreference.comfortable.densityId,
        ),
      );
      return DensityPreference.comfortable;
    }
    for (final DensityPreference candidate in DensityPreference.values) {
      if (candidate.densityId == stored || candidate.name == stored) {
        return candidate;
      }
    }
    report.add(
      SettingsIssue(
        problem: SettingsProblem.unknownDensity,
        key: densityKey,
        received: stored,
        applied: DensityPreference.comfortable.densityId,
      ),
    );
    return DensityPreference.comfortable;
  }

  RadiusPreference _readRadius(Map<String, Object?> document, _Report report) {
    final Object? stored = document[radiusKey];
    if (stored == null) return RadiusPreference.soft;
    if (stored is! String) {
      report.add(
        SettingsIssue(
          problem: SettingsProblem.wrongType,
          key: radiusKey,
          received: _render(stored),
          applied: RadiusPreference.soft.presetId,
        ),
      );
      return RadiusPreference.soft;
    }
    for (final RadiusPreference candidate in RadiusPreference.values) {
      if (candidate.presetId == stored || candidate.name == stored) {
        return candidate;
      }
    }
    report.add(
      SettingsIssue(
        problem: SettingsProblem.unknownRadius,
        key: radiusKey,
        received: stored,
        applied: RadiusPreference.soft.presetId,
      ),
    );
    return RadiusPreference.soft;
  }

  bool _readBool(Map<String, Object?> document, String key, _Report report) {
    final Object? stored = document[key];
    if (stored == null) return false;
    if (stored is bool) return stored;
    report.add(
      SettingsIssue(
        problem: SettingsProblem.wrongType,
        key: key,
        received: _render(stored),
        applied: 'false',
      ),
    );
    return false;
  }
}

/// Accumulates issues while decoding.
final class _Report {
  final List<SettingsIssue> _issues = <SettingsIssue>[];

  void add(SettingsIssue issue) => _issues.add(issue);

  SettingsReport build() =>
      SettingsReport(List<SettingsIssue>.unmodifiable(_issues));
}

/// Narrows a decoded JSON map to string keys, without letting `dynamic` out.
Map<String, Object?> _asStringKeyed(Object? value) {
  final Map<Object?, Object?> raw = value as Map<Object?, Object?>;
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in raw.entries)
      if (entry.key is String) entry.key! as String: entry.value,
  };
}

/// Renders a decoded value for a Turkish message.
String _render(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  if (value is Map) return 'nesne';
  if (value is List) return 'liste';
  return '…';
}

/// Renders a number the way the settings screen shows a scale, so a report and
/// a slider never disagree about what `1.0` looks like.
String _renderNumber(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(1) : '$value';
