// The token seam itself: the values this layer resolves from must be the values
// design/tokens.json declares, and the arithmetic must be the generator's.
//
// Why this file exists separately: the resolver tests prove the resolution is
// right, but if the BRIDGE drifted from the token file - if a hand-copied hex
// crept in, or a mix amount was guessed - every resolver expectation would
// still pass while the app painted colours the file does not contain. This file
// is the one that would notice, and it reads the file rather than a copy.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/appearance_settings.dart';
import 'package:mkvi/settings/contrast.dart';
import 'package:mkvi/settings/design_tokens.dart';
import 'package:mkvi/settings/settings_catalog.dart';

import '../../../design/tool/generate_tokens.dart' show ContrastPair, Rgb;
import 'support/design_bridge.dart';import 'support/tokens_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DesignTokensFixture fixture = DesignTokensFixture.load();
  final TokenFile file = fixture.file;
  final AppearanceTokens tokens = fixture.tokens;
  final SettingsCatalog catalog = SettingsCatalog(tokens);

  group('the bridge reads the token file', () {
    test('every role of every combination is the file\'s own colour', () {
      for (final String themeId in file.themeIds) {
        for (final String accentId in file.accentIds) {
          final Map<String, Color> roles = tokens.rolesFor(themeId, accentId);
          final String where = '$themeId/$accentId';
          expect(roles.keys.toSet(), file.roleNames.toSet(), reason: where);
          for (final String role in file.roleRoles) {
            expect(
              roles[role],
              tryParseHexColor(file.roleHex(themeId, role)),
              reason: '$where role $role',
            );
          }
          expect(
            roles['accent'],
            tryParseHexColor(file.accentHex(accentId, 'base')),
            reason: where,
          );
          expect(
            roles['accentHover'],
            tryParseHexColor(file.accentHex(accentId, 'hover')),
            reason: where,
          );
          expect(
            roles['accentActive'],
            tryParseHexColor(file.accentHex(accentId, 'active')),
            reason: where,
          );
          expect(
            roles['textOnAccent'],
            tryParseHexColor(file.accentHex(accentId, 'on')),
            reason: where,
          );
          expect(
            roles['accentSoft'],
            _colorOf(file.accentSoftFor(themeId, accentId)),
            reason: where,
          );
          expect(
            roles['focusRing'],
            _colorOf(file.focusRingFor(themeId, accentId)),
            reason: where,
          );
        }
      }
    });

    test('the type scale is the file\'s, at the file\'s weights', () {
      expect(tokens.typeScale.keys.toSet(), file.typeStepNames.toSet());
      for (final String step in file.typeStepNames) {
        final TypeStepMetrics metrics = tokens.typeScale[step]!;
        expect(metrics.size, file.typeSize(step), reason: step);
        expect(metrics.weight, file.typeWeight(step), reason: step);
        expect(metrics.tracking, file.typeTracking(step), reason: step);
        expect(
          metrics.lineHeight,
          file.lineHeight(file.typeLineHeightName(step)),
          reason: step,
        );
      }
      expect(tokens.fontFamily, file.fontFamily().first);
      expect(tokens.fontFamilyFallback, file.fontFamily().sublist(1));
    });

    test('spacing and density are the file\'s', () {
      expect(tokens.spaceUnit, file.spaceUnit());
      for (final String step in file.spaceStepNames) {
        expect(
          tokens.spaceSteps[step],
          file.spaceUnit() * file.spaceStep(step),
          reason: 'space step $step',
        );
      }
      for (final MapEntry<String, double> entry in tokens.densities.entries) {
        expect(entry.value, file.density(entry.key), reason: entry.key);
      }
    });

    test('radii are the file\'s, per preset', () {
      expect(tokens.radiusPresets, file.radiusPresets());
      const Map<String, double> factors = <String, double>{
        'xs': 0.25,
        'sm': 0.5,
        'md': 0.75,
        'lg': 1.0,
        'xl': 1.5,
      };
      for (final String preset in file.radiusPresets()) {
        final double unit = file.radiusPresetUnit(preset);
        final double scale = file.radiusPresetScale(preset);
        final Map<String, double> radii = tokens.radiiFor(preset);
        for (final MapEntry<String, double> factor in factors.entries) {
          expect(
            radii[factor.key],
            closeTo(unit * scale * factor.value, 1e-9),
            reason: '$preset/${factor.key}',
          );
        }
        expect(radii['none'], 0.0, reason: preset);
        expect(radii['pill'], file.radiusPill(), reason: preset);
      }
    });

    test('controls and motion are the file\'s', () {
      for (final String size in <String>['sm', 'md', 'lg']) {
        final ControlMetrics control = tokens.controlSizes[size]!;
        expect(control.height, file.controlHeight(size), reason: size);
        expect(control.paddingX, file.controlPaddingX(size), reason: size);
        expect(control.gap, file.controlGap(size), reason: size);
        expect(control.fontSize, file.controlFontSize(size), reason: size);
        expect(control.iconSize, file.controlIconSize(size), reason: size);
      }
      expect(tokens.controlSizesFollowDensity, file.controlDensityScale());
      expect(tokens.hitTargetMin, file.hitTargetMin());
      expect(tokens.borderWidth, file.borderWidth());
      expect(tokens.focusRingWidth, file.focusRingWidth());
      expect(tokens.focusRingGap, file.focusRingGap());
      expect(tokens.motionDurations.keys.toSet(), file.motionNames().toSet());
      for (final String name in file.motionNames()) {
        expect(
          tokens.motionDurations[name],
          Duration(milliseconds: file.motionDuration(name)),
          reason: name,
        );
      }
    });

    test('the contrast list is the file\'s, in the file\'s order', () {
      expect(tokens.contrastRequirements, file.contrastRequirements);
      expect(tokens.contrastRequirements.length, file.contrastPairs.length);
      for (int i = 0; i < file.contrastPairs.length; i += 1) {
        expect(
          tokens.contrastRequirements[i].foregroundRole,
          file.contrastPairs[i].fg,
          reason: 'pair $i',
        );
        expect(
          tokens.contrastRequirements[i].backgroundRole,
          file.contrastPairs[i].bg,
          reason: 'pair $i',
        );
        expect(
          tokens.contrastRequirements[i].minimum,
          file.contrastPairs[i].min,
          reason: 'pair $i',
        );
      }
    });

    test('the derive amounts and polarities are the file\'s', () {
      for (final String themeId in file.themeIds) {
        expect(
          tokens.isDarkTheme(themeId),
          file.isDarkTheme(themeId),
          reason: themeId,
        );
        expect(
          tokens.focusRingMixFor(themeId),
          file.deriveNumber(themeId, 'focusRingMix'),
          reason: themeId,
        );
        expect(
          tokens.accentSoftMixFor(themeId),
          file.deriveNumber(themeId, 'accentSoftMix'),
          reason: themeId,
        );
        expect(
          tokens.focusRingTargetFor(themeId),
          tryParseHexColor(file.deriveHex(themeId, 'focusRingTarget')),
          reason: themeId,
        );
      }
    });
  });

  group('the arithmetic is the generator\'s', () {
    test('relative luminance agrees for every colour in the file', () {
      for (final String themeId in file.themeIds) {
        for (final String role in file.roleNames) {
          final Rgb expected = file.rgb(file.roleHex(themeId, role));
          final Color actual = tryParseHexColor(file.roleHex(themeId, role))!;
          expect(
            relativeLuminance(actual),
            closeTo(expected.luminance, 1e-12),
            reason: '$themeId/$role',
          );
        }
      }
      for (final String accentId in file.accentIds) {
        for (final String key in <String>[
          'base',
          'hover',
          'active',
          'on',
          'soft',
        ]) {
          final Rgb expected = file.rgb(file.accentHex(accentId, key));
          final Color actual = tryParseHexColor(file.accentHex(accentId, key))!;
          expect(
            relativeLuminance(actual),
            closeTo(expected.luminance, 1e-12),
            reason: '$accentId/$key',
          );
        }
      }
    });

    test('contrast ratio agrees for every declared pair', () {
      for (int i = 0; i < file.contrastPairs.length; i += 1) {
        final ContrastPair pair = file.contrastPairs[i];
        for (final String themeId in file.themeIds) {
          final Rgb fg = file.rgb(file.roleHex(themeId, pair.fg));
          final Rgb bg = file.rgb(file.roleHex(themeId, pair.bg));
          final Color fgColor = tryParseHexColor(
            file.roleHex(themeId, pair.fg),
          )!;
          final Color bgColor = tryParseHexColor(
            file.roleHex(themeId, pair.bg),
          )!;
          expect(
            contrastRatio(fgColor, bgColor),
            closeTo(fg.contrastWith(bg), 1e-12),
            reason: 'pair $i in $themeId',
          );
        }
      }
    });

    test(
      'color-mix agrees with the generator for every amount the file uses',
      () {
        const List<double> amounts = <double>[
          0.0,
          0.05,
          0.1,
          0.25,
          0.42,
          0.5,
          0.78,
          0.8,
          0.88,
          1.0,
        ];
        for (final String themeId in file.themeIds) {
          final Rgb surface = file.rgb(file.roleHex(themeId, 'surface'));
          final Rgb target = file.rgb(
            file.deriveHex(themeId, 'focusRingTarget'),
          );
          for (final String accentId in file.accentIds) {
            final Rgb base = file.rgb(file.accentHex(accentId, 'base'));
            for (final double amount in amounts) {
              expect(
                _colorOf(Rgb.mix(base, target, amount)),
                mixColor(
                  tryParseHexColor(file.accentHex(accentId, 'base'))!,
                  tryParseHexColor(file.deriveHex(themeId, 'focusRingTarget'))!,
                  amount,
                ),
                reason: '$themeId/$accentId at $amount',
              );
              expect(
                _colorOf(Rgb.mix(base, surface, amount)),
                mixColor(
                  tryParseHexColor(file.accentHex(accentId, 'base'))!,
                  tryParseHexColor(file.roleHex(themeId, 'surface'))!,
                  amount,
                ),
                reason: '$themeId/$accentId at $amount',
              );
            }
          }
        }
      },
    );

    test('hex parsing round-trips every colour in the file', () {
      for (final String themeId in file.themeIds) {
        for (final String role in file.roleNames) {
          final String hex = file.roleHex(themeId, role);
          final Color? parsed = tryParseHexColor(hex);
          expect(parsed, isNotNull, reason: hex);
          expect(hexOf(parsed!).toLowerCase(), hex.toLowerCase(), reason: hex);
        }
      }
      expect(tryParseHexColor('nope'), isNull);
      expect(tryParseHexColor('#fff'), isNull);
      expect(tryParseHexColor(null), isNull);
    });
  });

  group('the Turkish catalogue', () {
    test('takes the theme names from the token file, not from itself', () {
      for (final ThemePreference preference in ThemePreference.values) {
        final String? id = preference.themeId;
        if (id == null) {
          expect(
            catalog.themeOptionLabel(preference),
            catalog.systemThemeLabel,
            reason: 'system is not a theme, so the file has no name for it',
          );
          continue;
        }
        expect(
          catalog.themeOptionLabel(preference),
          file.themeLabel(id),
          reason: id,
        );
        expect(tokens.themeLabel(id), file.themeLabel(id), reason: id);
      }
    });

    test('takes the accent names from the token file, not from itself', () {
      for (final AccentId accent in AccentId.values) {
        expect(
          catalog.accentOptionLabel(accent),
          file.accentLabel(accent.name),
          reason: accent.name,
        );
        expect(
          tokens.accentLabel(accent.name),
          file.accentLabel(accent.name),
          reason: accent.name,
        );
      }
      expect(catalog.customAccentLabel(null), catalog.customAccentName);
    });

    test('lists system first, then the file\'s themes in order', () {
      expect(catalog.themeOptions.first, ThemePreference.system);
      expect(
        catalog.themeOptions
            .sublist(1)
            .map((ThemePreference t) => t.name)
            .toList(),
        file.themeIds,
      );
    });

    test('has a Turkish label for every option a user can pick', () {
      final List<String> labels = <String>[
        for (final ThemePreference preference in catalog.themeOptions)
          catalog.themeOptionLabel(preference),
        for (final AccentId accent in AccentId.values)
          catalog.accentOptionLabel(accent),
        catalog.customAccentName,
        catalog.densityOptionLabel(DensityPreference.compact),
        catalog.densityOptionLabel(DensityPreference.comfortable),
        catalog.radiusOptionLabel(RadiusPreference.crisp),
        catalog.radiusOptionLabel(RadiusPreference.soft),
        catalog.fontScaleLabel,
        catalog.fontScaleMinimumLabel,
        catalog.fontScaleMaximumLabel,
        catalog.highContrastLabel,
        catalog.highContrastDescription,
        catalog.reduceMotionLabel,
        catalog.reduceMotionDescription,
        catalog.endpointLabel,
        catalog.endpointHint,
        catalog.endpointEmptyState,
        catalog.iceServersLabel,
        catalog.iceServersHint,
        catalog.selfNameLabel,
        catalog.selfNameHint,
        catalog.saveLabel,
        catalog.resetAppearanceLabel,
        catalog.appearanceSection,
        catalog.connectionSection,
        catalog.accessibilitySection,
        catalog.profileSection,
        catalog.repairedBannerTitle,
        catalog.systemThemeDescription,
        catalog.customAccentDescription,
        catalog.densityDescription,
      ];
      for (final String label in labels) {
        expect(label.trim(), isNotEmpty);
        // A label that is a bare token name or a hex is a sign it was never
        // written for a person.
        expect(label, isNot(matches(RegExp(r'^#[0-9a-fA-F]{6}$'))));
      }
      expect(catalog.fontScaleValue(1.25), '%125');
      expect(catalog.fontScaleValue(0.9), '%90');
    });
  });
}

/// The generator's colour, as a Flutter colour.
Color _colorOf(Rgb value) => Color.fromARGB(value.a, value.r, value.g, value.b);
