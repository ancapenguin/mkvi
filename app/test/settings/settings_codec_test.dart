// The JSON codec: every field round-trips, and every correction is reported in
// Turkish instead of being swallowed.
//
// The live defect this file pins: a persisted appearance setting that no longer
// validated silently fell back to the default, so a user who had chosen the
// plum theme came back to midnight with no reason and no way back. Here a
// stored value that cannot be used is REPORTED - with what was found, what was
// applied, and why - while every OTHER field survives untouched.

import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/appearance_settings.dart';
import 'package:mkvi/settings/contrast.dart';
import 'package:mkvi/settings/settings_codec.dart';
import 'package:mkvi/settings/settings_issue.dart';
import 'package:mkvi/settings/settings_messages.dart';

import 'support/design_bridge.dart';
void main() {
  const SettingsCodec codec = SettingsCodec();

  /// A colour that exists in design/tokens.json, used as a custom accent so
  /// this file declares no colour of its own.
  final Color customAccent = tryParseHexColor(
    DesignTokensFixture.load().file.roleHex('midnight', 'dangerFill'),
  )!;

  AppearanceSettings maximal() => AppearanceSettings(
    theme: ThemePreference.plum,
    accent: AccentPreference.custom(customAccent),
    fontScale: 1.25,
    density: DensityPreference.compact,
    radius: RadiusPreference.crisp,
    highContrast: true,
    reduceMotion: true,
  );

  group('round trip', () {
    test('the default settings survive an encode and a decode', () {
      final String encoded = codec.encodeAppearance(AppearanceSettings.initial);
      final AppearanceDocument decoded = codec.decodeAppearance(encoded);
      expect(decoded.settings, AppearanceSettings.initial);
      expect(
        decoded.report.hasIssues,
        isFalse,
        reason: decoded.report.messagesTr.join(' / '),
      );
    });

    test('every field survives, all of them at once', () {
      final AppearanceSettings original = maximal();
      final AppearanceDocument decoded = codec.decodeAppearance(
        codec.encodeAppearance(original),
      );
      expect(decoded.settings, original);
      expect(decoded.settings.theme, ThemePreference.plum);
      expect(decoded.settings.accent, AccentPreference.custom(customAccent));
      expect(decoded.settings.fontScale, 1.25);
      expect(decoded.settings.density, DensityPreference.compact);
      expect(decoded.settings.radius, RadiusPreference.crisp);
      expect(decoded.settings.highContrast, isTrue);
      expect(decoded.settings.reduceMotion, isTrue);
      expect(
        decoded.report.hasIssues,
        isFalse,
        reason: decoded.report.messagesTr.join(' / '),
      );
    });

    test('every theme, accent, density and radius round-trips', () {
      for (final ThemePreference theme in ThemePreference.values) {
        for (final AccentId accent in AccentId.values) {
          for (final DensityPreference density in DensityPreference.values) {
            for (final RadiusPreference radius in RadiusPreference.values) {
              final AppearanceSettings original = AppearanceSettings(
                theme: theme,
                accent: AccentPreference.preset(accent),
                density: density,
                radius: radius,
              );
              final AppearanceDocument decoded = codec.decodeAppearance(
                codec.encodeAppearance(original),
              );
              expect(decoded.settings, original, reason: original.toString());
              expect(
                decoded.report.hasIssues,
                isFalse,
                reason: decoded.report.messagesTr.join(' / '),
              );
            }
          }
        }
      }
    });

    test('every font scale the slider offers round-trips exactly', () {
      for (int step = 0; step <= 7; step += 1) {
        final double scale = AppearanceSettings(
          fontScale:
              AppearanceSettings.minFontScale +
              step * AppearanceSettings.fontScaleStep,
        ).fontScale;
        final AppearanceSettings original = AppearanceSettings(
          fontScale: scale,
        );
        final AppearanceDocument decoded = codec.decodeAppearance(
          codec.encodeAppearance(original),
        );
        expect(decoded.settings.fontScale, scale, reason: 'step $step');
        expect(decoded.report.hasIssues, isFalse, reason: 'step $step');
      }
    });

    test('the encoding is stable, so two settings can be compared', () {
      expect(
        codec.encodeAppearance(maximal()),
        codec.encodeAppearance(maximal()),
      );
      final Map<String, Object?> decoded =
          jsonDecode(codec.encodeAppearance(maximal())) as Map<String, Object?>;
      expect(decoded[SettingsCodec.versionKey], SettingsCodec.version);
      expect(decoded[SettingsCodec.themeKey], 'plum');
      expect(decoded[SettingsCodec.densityKey], 'compact');
      expect(decoded[SettingsCodec.radiusKey], 'crisp');
      expect(decoded[SettingsCodec.fontScaleKey], 1.25);
      expect(decoded[SettingsCodec.highContrastKey], isTrue);
      expect(decoded[SettingsCodec.reduceMotionKey], isTrue);
      final Object? accent = decoded[SettingsCodec.accentKey];
      expect(accent, isA<Map<Object?, Object?>>());
      expect(
        (accent! as Map<Object?, Object?>)[SettingsCodec.customAccentKey],
        hexOf(customAccent),
      );
    });
  });

  group('a corrupted value is reported, and the rest survives', () {
    /// A document where every field is valid, so a test can corrupt one and
    /// check that the other seven are untouched.
    String validDocument() => jsonEncode(<String, Object?>{
      SettingsCodec.versionKey: SettingsCodec.version,
      SettingsCodec.themeKey: 'forest',
      SettingsCodec.accentKey: 'teal',
      SettingsCodec.fontScaleKey: 1.15,
      SettingsCodec.densityKey: 'compact',
      SettingsCodec.radiusKey: 'crisp',
      SettingsCodec.highContrastKey: true,
      SettingsCodec.reduceMotionKey: false,
    });

    void expectTheRestSurvived(
      AppearanceDocument decoded, {
      required String corrupted,
      required SettingsProblem problem,
      String? key,
    }) {
      // Every field EXCEPT the one this test deliberately corrupted must come
      // back untouched: that is the "the rest of the settings survive" half of
      // the contract, and it is the half a naive fall-back-to-default loses.
      if (corrupted != 'theme') {
        expect(
          decoded.settings.theme,
          ThemePreference.forest,
          reason: 'the other fields must survive',
        );
      }
      if (corrupted != 'accent') {
        expect(
          decoded.settings.accent,
          const AccentPreference.preset(AccentId.teal),
          reason: 'the other fields must survive',
        );
      }
      if (corrupted != 'fontScale') {
        expect(
          decoded.settings.fontScale,
          1.15,
          reason: 'the other fields must survive',
        );
      }
      if (corrupted != 'density') {
        expect(
          decoded.settings.density,
          DensityPreference.compact,
          reason: 'the other fields must survive',
        );
      }
      if (corrupted != 'radius') {
        expect(
          decoded.settings.radius,
          RadiusPreference.crisp,
          reason: 'the other fields must survive',
        );
      }
      if (corrupted != 'highContrast') {
        expect(
          decoded.settings.highContrast,
          isTrue,
          reason: 'the other fields must survive',
        );
      }
      if (corrupted != 'reduceMotion') {
        expect(
          decoded.settings.reduceMotion,
          isFalse,
          reason: 'the other fields must survive',
        );
      }
      expect(decoded.report.hasIssues, isTrue);
      final SettingsIssue issue = decoded.report.issues.first;
      expect(issue.problem, problem);
      if (key != null) expect(issue.key, key);
      // The reason is Turkish, and it says what was found and what was used.
      expect(issue.messageTr, isNotEmpty);
      expect(issue.messageTr, isNot(contains('Exception')));
      expect(
        issue.received ?? issue.applied,
        isNotNull,
        reason: 'a report must carry at least one side of the change',
      );
    }

    test('an unknown theme', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        validDocument().replaceFirst('"forest"', '"neon"'),
      );
      expectTheRestSurvived(
        decoded,
        corrupted: 'theme',
        problem: SettingsProblem.unknownTheme,
        key: SettingsCodec.themeKey,
      );
      expect(decoded.settings.theme, ThemePreference.system);
      expect(decoded.report.issues.first.received, 'neon');
      expect(decoded.report.issues.first.messageTr, contains('neon'));
      expect(decoded.report.issues.first.messageTr, contains('Sistem'));
    });

    test('an unknown accent', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        validDocument().replaceFirst('"teal"', '"pembe"'),
      );
      expectTheRestSurvived(
        decoded,
        corrupted: 'accent',
        problem: SettingsProblem.unknownAccent,
        key: SettingsCodec.accentKey,
      );
      expect(
        decoded.settings.accent,
        const AccentPreference.preset(AccentId.blue),
      );
    });

    test('a custom accent that is not a colour', () {
      final String document = validDocument().replaceFirst(
        '"teal"',
        '{"custom": "kırmızı"}',
      );
      final AppearanceDocument decoded = codec.decodeAppearance(document);
      expectTheRestSurvived(
        decoded,
        corrupted: 'accent',
        problem: SettingsProblem.badAccentColour,
        key: SettingsCodec.accentKey,
      );
      expect(
        decoded.settings.accent,
        const AccentPreference.preset(AccentId.blue),
      );
    });

    test('a font scale out of range', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        validDocument().replaceFirst('1.15', '3'),
      );
      expectTheRestSurvived(
        decoded,
        corrupted: 'fontScale',
        problem: SettingsProblem.fontScaleOutOfRange,
        key: SettingsCodec.fontScaleKey,
      );
      expect(decoded.settings.fontScale, AppearanceSettings.maxFontScale);
      expect(decoded.report.issues.first.applied, '1.25');
      expect(decoded.report.issues.first.messageTr, contains('1.25'));
    });

    test('a font scale that is not on a slider step', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        validDocument().replaceFirst('1.15', '1.07'),
      );
      expectTheRestSurvived(
        decoded,
        corrupted: 'fontScale',
        problem: SettingsProblem.fontScaleNotOnStep,
        key: SettingsCodec.fontScaleKey,
      );
      expect(decoded.settings.fontScale, 1.05);
    });

    test('a font scale that is not a number', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        validDocument().replaceFirst('1.15', '"çok büyük"'),
      );
      expectTheRestSurvived(
        decoded,
        corrupted: 'fontScale',
        problem: SettingsProblem.fontScaleNotANumber,
        key: SettingsCodec.fontScaleKey,
      );
      expect(decoded.settings.fontScale, AppearanceSettings.defaultFontScale);
    });

    test('an unknown density', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        validDocument().replaceFirst('"compact"', '"devasa"'),
      );
      expectTheRestSurvived(
        decoded,
        corrupted: 'density',
        problem: SettingsProblem.unknownDensity,
        key: SettingsCodec.densityKey,
      );
      expect(decoded.settings.density, DensityPreference.comfortable);
    });

    test('an unknown radius', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        validDocument().replaceFirst('"crisp"', '"yuvarlak"'),
      );
      expectTheRestSurvived(
        decoded,
        corrupted: 'radius',
        problem: SettingsProblem.unknownRadius,
        key: SettingsCodec.radiusKey,
      );
      expect(decoded.settings.radius, RadiusPreference.soft);
    });

    test('a switch that is not a boolean', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        validDocument().replaceFirst('true', '"evet"'),
      );
      expectTheRestSurvived(
        decoded,
        corrupted: 'highContrast',
        problem: SettingsProblem.wrongType,
        key: SettingsCodec.highContrastKey,
      );
      expect(decoded.settings.highContrast, isFalse);
    });

    test('two corrupt fields are both reported', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        validDocument()
            .replaceFirst('"forest"', '"neon"')
            .replaceFirst('1.15', '9'),
      );
      expect(decoded.report.count, 2);
      expect(
        decoded.report.issues
            .map((SettingsIssue issue) => issue.problem)
            .toSet(),
        <SettingsProblem>{
          SettingsProblem.unknownTheme,
          SettingsProblem.fontScaleOutOfRange,
        },
      );
      expect(decoded.report.summaryTr, contains('+1'));
      // And the six untouched fields are still right.
      expect(decoded.settings.density, DensityPreference.compact);
      expect(
        decoded.settings.accent,
        const AccentPreference.preset(AccentId.teal),
      );
    });
  });

  group('what is deliberately not a problem', () {
    test('an absent field is read as the default, in silence', () {
      final AppearanceDocument decoded = codec.decodeAppearance('{}');
      expect(decoded.settings, AppearanceSettings.initial);
      expect(
        decoded.report.hasIssues,
        isFalse,
        reason: 'a document from a build with fewer fields is not corruption',
      );
    });

    test('an unknown key is ignored, for a newer build', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        jsonEncode(<String, Object?>{
          SettingsCodec.versionKey: SettingsCodec.version,
          SettingsCodec.themeKey: 'forest',
          'glassBlur': 12,
        }),
      );
      expect(decoded.settings.theme, ThemePreference.forest);
      expect(decoded.report.hasIssues, isFalse);
    });

    test('a newer document version is reported, and still read', () {
      final AppearanceDocument decoded = codec.decodeAppearance(
        jsonEncode(<String, Object?>{
          SettingsCodec.versionKey: SettingsCodec.version + 1,
          SettingsCodec.themeKey: 'plum',
          SettingsCodec.densityKey: 'compact',
        }),
      );
      expect(decoded.report.hasIssues, isTrue);
      expect(
        decoded.report.issues.first.problem,
        SettingsProblem.futureVersion,
      );
      expect(decoded.report.issues.first.messageTr, contains('daha yeni'));
      // The fields this build understands are still honoured.
      expect(decoded.settings.theme, ThemePreference.plum);
      expect(decoded.settings.density, DensityPreference.compact);
    });

    test('a document that is not JSON at all', () {
      final AppearanceDocument decoded = codec.decodeAppearance('{ nope');
      expect(decoded.settings, AppearanceSettings.initial);
      expect(decoded.report.hasIssues, isTrue);
      expect(
        decoded.report.issues.first.problem,
        SettingsProblem.malformedDocument,
      );
      expect(decoded.report.issues.first.messageTr, contains('okunamadı'));
    });

    test('a document that is JSON but not an object', () {
      final AppearanceDocument decoded = codec.decodeAppearance('[1, 2, 3]');
      expect(decoded.settings, AppearanceSettings.initial);
      expect(
        decoded.report.issues.first.problem,
        SettingsProblem.malformedDocument,
      );
    });

    test('an enum name is accepted next to the token key', () {
      // A value typed by hand can use either spelling; neither is an error.
      final Map<String, DensityPreference> densities =
          <String, DensityPreference>{
            'compact': DensityPreference.compact,
            'cozy': DensityPreference.comfortable,
            'comfortable': DensityPreference.comfortable,
          };
      for (final MapEntry<String, DensityPreference> entry
          in densities.entries) {
        final AppearanceDocument decoded = codec.decodeAppearance(
          jsonEncode(<String, Object?>{SettingsCodec.densityKey: entry.key}),
        );
        expect(decoded.settings.density, entry.value, reason: entry.key);
        expect(decoded.report.hasIssues, isFalse, reason: entry.key);
      }
      for (final MapEntry<String, RadiusPreference> entry
          in <String, RadiusPreference>{
            'crisp': RadiusPreference.crisp,
            'cozy': RadiusPreference.soft,
            'soft': RadiusPreference.soft,
          }.entries) {
        final AppearanceDocument decoded = codec.decodeAppearance(
          jsonEncode(<String, Object?>{SettingsCodec.radiusKey: entry.key}),
        );
        expect(decoded.settings.radius, entry.value, reason: entry.key);
        expect(decoded.report.hasIssues, isFalse, reason: entry.key);
      }
    });
  });

  group('the report itself', () {
    test('is a value, with a Turkish summary', () {
      const SettingsReport clean = SettingsReport.clean;
      expect(clean.hasIssues, isFalse);
      expect(clean.count, 0);
      expect(clean.summaryTr, '');

      final SettingsReport one = clean.plus(
        const SettingsIssue(
          problem: SettingsProblem.unknownTheme,
          key: 'theme',
          received: 'neon',
          applied: 'system',
        ),
      );
      expect(one.hasIssues, isTrue);
      expect(one.count, 1);
      expect(one.summaryTr, contains('neon'));

      final SettingsReport two = one.merge(one);
      expect(two.count, 2);
      expect(two.summaryTr, contains('+1'));
      expect(two.messagesTr, hasLength(2));
    });
  });
}
