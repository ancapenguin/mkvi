// The appearance resolver: every theme and accent, and every preference that
// has to reach the pixels.
//
// The three live defects this file pins:
//
//   1. `fontScale` did nothing on the first-run screens, because the one rule
//      that scaled the type size applied to an element whose children used
//      their own literals. Here the resolved type scale and the whole
//      TextTheme are asserted to carry the scale, and to differ measurably
//      between 0.9 and 1.25.
//   2. `density` was honoured in 8 places out of ~40. Here the resolved spacing
//      and the resolved control heights are asserted against the token file's
//      own numbers, and asserted to reach the ThemeData's button metrics
//      rather than sitting in a field nobody reads.
//   3. A custom accent is either safe or REPORTED. It is never silently
//      replaced, and the report is Turkish.
//
// Every expectation is a number read from design/tokens.json, or a colour
// computed by design/tool/generate_tokens.dart. No hex is written here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/appearance_resolver.dart';
import 'package:mkvi/settings/appearance_settings.dart';
import 'package:mkvi/settings/appearance_style.dart';
import 'package:mkvi/settings/contrast.dart';
import 'package:mkvi/settings/settings_issue.dart';
import 'package:mkvi/settings/settings_messages.dart';

import '../../../design/tool/generate_tokens.dart' show Rgb;
import 'support/design_bridge.dart';import 'support/tokens_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DesignTokensFixture fixture = DesignTokensFixture.load();
  final TokenFile file = fixture.file;
  final AppearanceResolver resolver = AppearanceResolver(fixture.tokens);

  /// Every role a theme stores directly, i.e. everything except the six roles
  /// `meta.sources` derives from the accent.
  const List<String> themeRoles = <String>[
    'bg',
    'surface',
    'surfaceRaised',
    'surfaceSoft',
    'surfaceOverlay',
    'text',
    'textMuted',
    'textSubtle',
    'textOnStage',
    'stage',
    'border',
    'borderStrong',
    'success',
    'successSoft',
    'warning',
    'warningSoft',
    'danger',
    'dangerFill',
    'dangerFillHover',
    'scrim',
    'shadow1',
    'shadow2',
    'shadow3',
  ];

  /// Every type step, from the file.
  const List<String> typeSteps = <String>[
    '2xs',
    'xs',
    'sm',
    'md',
    'lg',
    'xl',
    '2xl',
  ];

  AppearanceSettings settingsFor(String themeId, String accentId) {
    return AppearanceSettings(
      theme: ThemePreference.fromThemeId(themeId),
      accent: AccentPreference.preset(AccentId.fromAccentId(accentId)!),
    );
  }

  Brightness polarityOf(String themeId) =>
      file.isDarkTheme(themeId) ? Brightness.dark : Brightness.light;

  group('every theme and accent', () {
    test('this layer and the token file agree on what exists', () {
      // If tokens.json gains a theme or an accent, this fails until the
      // resolver, the catalogue and the enums know about it.
      expect(fixture.tokens.themeIds, file.themeIds);
      expect(fixture.tokens.accentIds, file.accentIds);
      expect(fixture.tokens.roleNames, file.roleNames.toSet());
      expect(fixture.tokens.defaultThemeId, file.defaultThemeId);
      expect(fixture.tokens.defaultAccentId, file.defaultAccentId);
      expect(
        ThemePreference.values.map((ThemePreference t) => t.name).toSet(),
        <String>{...file.themeIds, 'system'},
        reason:
            'a theme in the file that this layer cannot name would be '
            'unreachable for the user',
      );
      expect(
        AccentId.values.map((AccentId a) => a.name).toSet(),
        file.accentIds.toSet(),
      );
      for (final DensityPreference density in DensityPreference.values) {
        expect(
          fixture.tokens.densities.containsKey(density.densityId),
          isTrue,
          reason: '${density.name} must map to a density the file declares',
        );
      }
      for (final RadiusPreference radius in RadiusPreference.values) {
        expect(
          fixture.tokens.radiusPresets,
          contains(radius.presetId),
          reason: '${radius.name} must map to a preset the file declares',
        );
      }
    });

    test('all 16 combinations resolve, and resolve to the token file', () {
      for (final String themeId in file.themeIds) {
        for (final String accentId in file.accentIds) {
          final AppearanceSettings preference = settingsFor(themeId, accentId);
          final ResolvedAppearance resolved = resolver.resolve(
            preference,
            platformBrightness: polarityOf(themeId),
          );
          final String where = '$themeId/$accentId';

          expect(resolved.themeId, themeId, reason: where);
          expect(resolved.report.hasIssues, isFalse, reason: where);
          expect(resolved.brightness, polarityOf(themeId), reason: where);

          // Every role the file defines is present: a theme that lost a role is
          // an error here, never a fall back to another theme.
          expect(
            resolved.style.roles.keys.toSet(),
            file.roleNames.toSet(),
            reason: where,
          );

          for (final String role in themeRoles) {
            expect(
              resolved.style.role(role),
              tryParseHexColor(file.roleHex(themeId, role)),
              reason: '$where role $role',
            );
          }
          expect(
            resolved.style.role('accent'),
            tryParseHexColor(file.accentHex(accentId, 'base')),
            reason: where,
          );
          expect(
            resolved.style.role('accentHover'),
            tryParseHexColor(file.accentHex(accentId, 'hover')),
            reason: where,
          );
          expect(
            resolved.style.role('accentActive'),
            tryParseHexColor(file.accentHex(accentId, 'active')),
            reason: where,
          );
          expect(
            resolved.style.role('textOnAccent'),
            tryParseHexColor(file.accentHex(accentId, 'on')),
            reason: where,
          );

          // The two derived roles are computed with the GENERATOR's mixing
          // rule, from the file's own amounts.
          expect(
            resolved.style.role('accentSoft'),
            _colorOf(file.accentSoftFor(themeId, accentId)),
            reason: where,
          );
          expect(
            resolved.style.role('focusRing'),
            _colorOf(file.focusRingFor(themeId, accentId)),
            reason: where,
          );
        }
      }
    });

    test('the ThemeData is built out of those roles, not out of its own', () {
      final String themeId = file.themeIds.first;
      final ResolvedAppearance resolved = resolver.resolve(
        settingsFor(themeId, file.accentIds.first),
        platformBrightness: Brightness.dark,
      );
      final ColorScheme scheme = resolved.themeData.colorScheme;
      final Map<String, Color> roles = resolved.style.roles;
      expect(scheme.primary, roles['accent']!);
      expect(scheme.onPrimary, roles['textOnAccent']!);
      expect(scheme.primaryContainer, roles['accentSoft']!);
      expect(scheme.onPrimaryContainer, roles['text']);
      expect(scheme.surface, roles['surface']);
      expect(scheme.onSurface, roles['text']);
      expect(scheme.outline, roles['border']);
      expect(scheme.scrim, roles['scrim']);
      expect(scheme.inverseSurface, roles['stage']);
      expect(scheme.onInverseSurface, roles['textOnStage']);
      expect(scheme.error, roles['danger']);
      expect(resolved.themeData.scaffoldBackgroundColor, roles['bg']);
      expect(resolved.themeData.canvasColor, roles['bg']);
      expect(resolved.themeData.cardColor, roles['surface']);
      expect(resolved.themeData.dividerColor, roles['border']);
      expect(resolved.themeData.hintColor, roles['textSubtle']);
      expect(resolved.themeData.disabledColor, roles['textSubtle']);
      expect(
        resolved.themeData.extension<AppearanceStyle>(),
        same(resolved.style),
        reason: 'the resolved style must be the one on the ThemeData',
      );
    });

    test('no text on a fill is unreadable, and the stage stays dark', () {
      // The 1.17:1 class the redesign exists to remove, checked at the layer
      // that now owns the palette: for all 16 combinations, the four
      // on-colour pairs the ColorScheme paints, plus the text ramp and the
      // stage.
      for (final String themeId in file.themeIds) {
        for (final String accentId in file.accentIds) {
          final ResolvedAppearance resolved = resolver.resolve(
            settingsFor(themeId, accentId),
            platformBrightness: polarityOf(themeId),
          );
          final ColorScheme scheme = resolved.themeData.colorScheme;
          final String where = '$themeId/$accentId';
          expect(
            contrastRatio(scheme.onPrimary, scheme.primary),
            greaterThanOrEqualTo(4.5),
            reason: '$where onPrimary',
          );
          expect(
            contrastRatio(scheme.onSecondary, scheme.secondary),
            greaterThanOrEqualTo(4.5),
            reason: '$where onSecondary',
          );
          expect(
            contrastRatio(scheme.onTertiary, scheme.tertiary),
            greaterThanOrEqualTo(4.5),
            reason: '$where onTertiary',
          );
          expect(
            contrastRatio(scheme.onError, scheme.error),
            greaterThanOrEqualTo(4.5),
            reason: '$where onError',
          );
          expect(
            contrastRatio(scheme.onSurface, scheme.surface),
            greaterThanOrEqualTo(7.0),
            reason: '$where onSurface',
          );
          expect(
            contrastRatio(scheme.onSurfaceVariant, scheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$where onSurfaceVariant',
          );
          expect(
            contrastRatio(scheme.onPrimaryContainer, scheme.primaryContainer),
            greaterThanOrEqualTo(6.0),
            reason: '$where onPrimaryContainer',
          );
          // The stage is always dark and always carries textOnStage.
          expect(
            resolved.style.contrast('textOnStage', 'stage'),
            greaterThanOrEqualTo(4.5),
            reason: '$where stage',
          );
          expect(
            relativeLuminance(resolved.style.role('stage')),
            lessThan(relativeLuminance(resolved.style.role('surface'))),
            reason: '$where: the stage must stay darker than the surface',
          );
        }
      }
    });
  });

  group('the system theme', () {
    test('follows the platform brightness that was supplied', () {
      final String lightTheme = file.themeIds.firstWhere(
        (String id) => !file.isDarkTheme(id),
      );

      final ResolvedAppearance onLight = resolver.resolve(
        AppearanceSettings(),
        platformBrightness: Brightness.light,
      );
      final ResolvedAppearance onDark = resolver.resolve(
        AppearanceSettings(),
        platformBrightness: Brightness.dark,
      );

      expect(onLight.themeId, lightTheme);
      expect(onLight.brightness, Brightness.light);
      expect(onDark.themeId, file.defaultThemeId);
      expect(onDark.brightness, Brightness.dark);
      expect(onLight.themeId, isNot(onDark.themeId));
      expect(
        onLight.style.role('bg'),
        tryParseHexColor(file.roleHex(lightTheme, 'bg')),
      );
    });

    test('is the default a fresh install starts with', () {
      expect(AppearanceSettings.initial.theme, ThemePreference.system);
    });

    test('hands MaterialApp a light theme, a dark theme and a system mode', () {
      final String lightTheme = file.themeIds.firstWhere(
        (String id) => !file.isDarkTheme(id),
      );
      final AppearanceThemes themes = resolver.resolveThemes(
        AppearanceSettings(),
      );
      expect(themes.mode, ThemeMode.system);
      expect(themes.light.colorScheme.brightness, Brightness.light);
      expect(themes.dark.colorScheme.brightness, Brightness.dark);
      expect(
        themes.light.scaffoldBackgroundColor,
        tryParseHexColor(file.roleHex(lightTheme, 'bg')),
      );
      expect(
        themes.dark.scaffoldBackgroundColor,
        tryParseHexColor(file.roleHex(file.defaultThemeId, 'bg')),
      );
      // Both halves are the token file's own palettes, so the pair a user sees
      // on a light OS is not a recoloured version of the dark one.
      expect(
        themes.light.colorScheme.surface,
        tryParseHexColor(file.roleHex(lightTheme, 'surface')),
      );
      expect(
        themes.dark.colorScheme.surface,
        tryParseHexColor(file.roleHex(file.defaultThemeId, 'surface')),
      );
    });

    test('an explicit theme fills both slots and pins the mode', () {
      for (final String themeId in file.themeIds) {
        final AppearanceThemes themes = resolver.resolveThemes(
          AppearanceSettings(theme: ThemePreference.fromThemeId(themeId)),
        );
        expect(
          themes.mode,
          file.isDarkTheme(themeId) ? ThemeMode.dark : ThemeMode.light,
          reason: themeId,
        );
        expect(
          themes.light.colorScheme.surface,
          themes.dark.colorScheme.surface,
          reason: '$themeId: nothing outside this layer may swap the theme',
        );
        expect(
          themes.light.colorScheme.surface,
          tryParseHexColor(file.roleHex(themeId, 'surface')),
          reason: themeId,
        );
      }
    });

    test('an explicit theme ignores the platform', () {
      for (final String themeId in file.themeIds) {
        final ResolvedAppearance resolved = resolver.resolve(
          AppearanceSettings(theme: ThemePreference.fromThemeId(themeId)),
          platformBrightness: polarityOf(themeId) == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        );
        expect(
          resolved.themeId,
          themeId,
          reason: 'an explicit theme must not follow the platform',
        );
      }
    });
  });

  group('a custom accent', () {
    test('is accepted, and the colour the user chose is the accent', () {
      // The destructive fill, a colour that already exists in the token file
      // and that a user really might pick as an accent, so this test declares
      // no colour of its own.
      final Color chosen = tryParseHexColor(
        file.roleHex('midnight', 'dangerFill'),
      )!;
      final ResolvedAppearance resolved = resolver.resolve(
        AppearanceSettings(accent: AccentPreference.custom(chosen)),
        platformBrightness: Brightness.dark,
      );

      expect(resolved.style.accentId, 'custom');
      expect(
        resolved.style.role('accent'),
        chosen,
        reason: 'the user\'s colour must survive resolution untouched',
      );
      expect(
        resolved.report.hasIssues,
        isFalse,
        reason:
            'a readable custom accent reports nothing: '
            '${resolved.report.messagesTr}',
      );
      // The ramp around it is built with the file's own machinery: the soft
      // fill is the user's colour mixed toward the surface by the file's own
      // amount, computed here with the GENERATOR's mixing rule.
      expect(
        resolved.style.role('accentSoft'),
        _colorOf(
          file.mixed(
            file.roleHex('midnight', 'dangerFill'),
            file.roleHex(resolved.themeId, 'surface'),
            file.deriveNumber(resolved.themeId, 'accentSoftMix'),
          ),
        ),
      );
      expect(resolved.style.role('accentSoft'), isNot(chosen));
      expect(
        resolved.style.role('focusRing'),
        _colorOf(
          file.mixed(
            file.roleHex('midnight', 'dangerFill'),
            file.deriveHex(resolved.themeId, 'focusRingTarget'),
            file.deriveNumber(resolved.themeId, 'focusRingMix'),
          ),
        ),
      );
      expect(
        resolved.style.contrast('focusRing', 'accent'),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('gets its on-colour by measurement, not by assumption', () {
      // A colour from the token file that is very light: the on-colour has to
      // become the dark extreme, which is what stops a pale accent from
      // producing white-on-pale text.
      final Color pale = tryParseHexColor(file.roleHex('light', 'surface'))!;
      final ResolvedAppearance resolved = resolver.resolve(
        AppearanceSettings(
          theme: ThemePreference.light,
          accent: AccentPreference.custom(pale),
        ),
        platformBrightness: Brightness.light,
      );
      expect(resolved.style.role('textOnAccent'), resolved.style.role('stage'));
      expect(
        contrastRatio(
          resolved.style.role('textOnAccent'),
          resolved.style.role('accent'),
        ),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('is REPORTED when it cannot be read, and never silently replaced', () {
      // The always-dark stage colour, used as an accent: it disappears into the
      // window background, so the structural pairs fail.
      final Color unreadable = tryParseHexColor(
        file.roleHex('midnight', 'stage'),
      )!;
      final ResolvedAppearance resolved = resolver.resolve(
        AppearanceSettings(accent: AccentPreference.custom(unreadable)),
        platformBrightness: Brightness.dark,
      );

      expect(
        resolved.style.role('accent'),
        unreadable,
        reason: 'the choice is kept; the app reports it instead of swapping it',
      );
      expect(resolved.report.hasIssues, isTrue);
      final List<String> messages = resolved.report.messagesTr;
      expect(messages, isNotEmpty);
      for (final String message in messages) {
        expect(
          message,
          contains('ölçüldü'),
          reason: 'every report must carry its measurement: $message',
        );
      }
      expect(
        resolved.report.issues.map((SettingsIssue issue) => issue.key),
        contains(contains('accent')),
      );
      expect(
        resolved.report.issues.every(
          (SettingsIssue issue) =>
              issue.problem == SettingsProblem.contrastRequirementFailed,
        ),
        isTrue,
      );
      // A failed pair is named with its own numbers, not with a verdict.
      expect(resolved.report.summaryTr, contains(':1'));
    });
  });

  group('fontScale', () {
    test('changes every resolved type size, and the numbers really differ', () {
      // The live defect: the slider moved nothing on the first-run screens.
      final double base = file.typeSize('md');
      final ResolvedAppearance small = resolver.resolve(
        AppearanceSettings(fontScale: AppearanceSettings.minFontScale),
        platformBrightness: Brightness.dark,
      );
      final ResolvedAppearance large = resolver.resolve(
        AppearanceSettings(fontScale: AppearanceSettings.maxFontScale),
        platformBrightness: Brightness.dark,
      );

      expect(small.style.typeStep('md').size, closeTo(base * 0.9, 1e-9));
      expect(large.style.typeStep('md').size, closeTo(base * 1.25, 1e-9));
      expect(
        small.style.typeStep('md').size,
        isNot(large.style.typeStep('md').size),
      );

      // Every step of the scale moves, and moves by the same multiplier.
      for (final String step in typeSteps) {
        final double token = file.typeSize(step);
        expect(
          small.style.typeStep(step).size,
          closeTo(token * 0.9, 1e-9),
          reason: 'step $step',
        );
        expect(
          large.style.typeStep(step).size,
          closeTo(token * 1.25, 1e-9),
          reason: 'step $step',
        );
      }

      // The ThemeData is built from the same steps, so a Material default size
      // cannot survive anywhere.
      expect(
        small.themeData.textTheme.bodyLarge!.fontSize,
        closeTo(base * 0.9, 1e-9),
      );
      expect(
        large.themeData.textTheme.bodyLarge!.fontSize,
        closeTo(base * 1.25, 1e-9),
      );
      expect(
        large.themeData.textTheme.titleLarge!.fontSize,
        closeTo(file.typeSize('lg') * 1.25, 1e-9),
      );

      final List<TextStyle?> slots = <TextStyle?>[
        large.themeData.textTheme.displayLarge,
        large.themeData.textTheme.displayMedium,
        large.themeData.textTheme.displaySmall,
        large.themeData.textTheme.headlineLarge,
        large.themeData.textTheme.headlineMedium,
        large.themeData.textTheme.headlineSmall,
        large.themeData.textTheme.titleLarge,
        large.themeData.textTheme.titleMedium,
        large.themeData.textTheme.titleSmall,
        large.themeData.textTheme.bodyLarge,
        large.themeData.textTheme.bodyMedium,
        large.themeData.textTheme.bodySmall,
        large.themeData.textTheme.labelLarge,
        large.themeData.textTheme.labelMedium,
        large.themeData.textTheme.labelSmall,
      ];
      expect(slots, hasLength(15));
      for (final TextStyle? style in slots) {
        expect(
          style?.fontSize,
          isNotNull,
          reason:
              'an unfilled TextTheme slot lets a Material default size '
              'through, which is how the scale was lost',
        );
      }
      // The TextTheme is what a screen reads, so it is the thing that has to
      // move when the scale moves.
      expect(
        small.themeData.textTheme,
        isNot(equals(large.themeData.textTheme)),
      );
    });

    test('scales a control\'s font size, and clamps out-of-range input', () {
      final ResolvedAppearance large = resolver.resolve(
        AppearanceSettings(fontScale: AppearanceSettings.maxFontScale),
        platformBrightness: Brightness.dark,
      );
      expect(
        large.style.control('md').fontSize,
        closeTo(file.controlFontSize('md') * 1.25, 1e-9),
      );

      // 3.0 is not a scale the slider offers, so the state refuses to hold it
      // and the codec reports the correction rather than hiding it.
      expect(
        AppearanceSettings(fontScale: 3.0).fontScale,
        AppearanceSettings.maxFontScale,
      );
      expect(
        AppearanceSettings(fontScale: 0.1).fontScale,
        AppearanceSettings.minFontScale,
      );
      expect(
        AppearanceSettings(fontScale: double.nan).fontScale,
        AppearanceSettings.defaultFontScale,
      );
      expect(AppearanceSettings(fontScale: 1.0).fontScale, 1.0);
      expect(AppearanceSettings(fontScale: 1.25).fontScale, 1.25);
      expect(AppearanceSettings(fontScale: 0.9).fontScale, 0.9);
      expect(
        AppearanceSettings(fontScale: 0.93).fontScale,
        0.95,
        reason: 'the slider snaps to 0.05 steps',
      );
    });
  });

  group('density', () {
    test('changes every spacing step and every control height', () {
      // The live defect: honoured in 8 places out of ~40.
      final ResolvedAppearance compact = resolver.resolve(
        AppearanceSettings(density: DensityPreference.compact),
        platformBrightness: Brightness.dark,
      );
      final ResolvedAppearance comfortable = resolver.resolve(
        AppearanceSettings(density: DensityPreference.comfortable),
        platformBrightness: Brightness.dark,
      );
      final double compactDensity = file.density('compact');
      final double cozyDensity = file.density('cozy');

      for (final String step in <String>[
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '10',
      ]) {
        // `space.steps` holds multipliers of `space.unit`, exactly as the file
        // writes them; the resolved value is unit x multiplier x density.
        final double token = file.spaceUnit() * file.spaceStep(step);
        expect(
          compact.style.gap(step),
          closeTo(token * compactDensity, 1e-9),
          reason: 'space step $step',
        );
        expect(
          comfortable.style.gap(step),
          closeTo(token * cozyDensity, 1e-9),
          reason: 'space step $step',
        );
        expect(
          compact.style.gap(step),
          isNot(comfortable.style.gap(step)),
          reason: 'space step $step must actually move',
        );
      }
      expect(
        compact.style.spaceUnit,
        closeTo(file.spaceUnit() * compactDensity, 1e-9),
      );
      expect(compact.style.density, compactDensity);

      for (final String size in <String>['sm', 'md', 'lg']) {
        expect(
          compact.style.control(size).height,
          closeTo(file.controlHeight(size) * compactDensity, 1e-9),
          reason: 'control $size height',
        );
        expect(
          compact.style.control(size).paddingX,
          closeTo(file.controlPaddingX(size) * compactDensity, 1e-9),
          reason: 'control $size padding',
        );
        expect(
          compact.style.control(size).gap,
          closeTo(file.controlGap(size) * compactDensity, 1e-9),
          reason: 'control $size gap',
        );
        expect(
          comfortable.style.control(size).height,
          closeTo(file.controlHeight(size) * cozyDensity, 1e-9),
          reason: 'control $size height',
        );
        expect(
          compact.style.control(size).height,
          isNot(comfortable.style.control(size).height),
          reason: 'control $size height must actually move',
        );
      }

      // The token file says font and icon sizes never follow density, and this
      // layer obeys it instead of scaling twice.
      expect(file.controlDensityScale(), isTrue);
      expect(compact.style.control('md').fontSize, file.controlFontSize('md'));
      expect(compact.style.control('md').iconSize, file.controlIconSize('md'));
      expect(
        compact.style.hitTargetMin,
        file.hitTargetMin(),
        reason: 'a pointer target is a physical promise, not a style',
      );

      // The resolved height reaches the ThemeData, so a Material button built
      // from it moves too.
      final Size compactButton = compact
          .themeData
          .filledButtonTheme
          .style!
          .minimumSize!
          .resolve(<WidgetState>{})!;
      final Size comfortableButton = comfortable
          .themeData
          .filledButtonTheme
          .style!
          .minimumSize!
          .resolve(<WidgetState>{})!;
      expect(
        compactButton.height,
        closeTo(file.controlHeight('md') * compactDensity, 1e-9),
      );
      expect(
        comfortableButton.height,
        closeTo(file.controlHeight('md') * cozyDensity, 1e-9),
      );
      expect(
        compact.themeData.filledButtonTheme,
        isNot(equals(comfortable.themeData.filledButtonTheme)),
      );
    });
  });

  group('radius', () {
    test('changes every radius the token file parameterises by preset', () {
      final ResolvedAppearance crisp = resolver.resolve(
        AppearanceSettings(radius: RadiusPreference.crisp),
        platformBrightness: Brightness.dark,
      );
      final ResolvedAppearance soft = resolver.resolve(
        AppearanceSettings(radius: RadiusPreference.soft),
        platformBrightness: Brightness.dark,
      );
      final double unit = file.radiusPresetUnit('crisp');
      final double crispScale = file.radiusPresetScale('crisp');
      final double softScale = file.radiusPresetScale('cozy');

      expect(soft.style.radiusPresetId, 'cozy');
      expect(crisp.style.radiusPresetId, 'crisp');

      // The steps the file derives from the preset's unit and scale.
      const Map<String, double> factors = <String, double>{
        'xs': 0.25,
        'sm': 0.5,
        'md': 0.75,
        'lg': 1.0,
        'xl': 1.5,
      };
      for (final MapEntry<String, double> step in factors.entries) {
        expect(
          crisp.style.radius(step.key),
          closeTo(unit * crispScale * step.value, 1e-9),
          reason: 'crisp ${step.key}',
        );
        expect(
          soft.style.radius(step.key),
          closeTo(unit * softScale * step.value, 1e-9),
          reason: 'soft ${step.key}',
        );
        expect(
          crisp.style.radius(step.key),
          isNot(soft.style.radius(step.key)),
          reason: '${step.key} must actually move',
        );
      }
      // The two steps the file declares preset independent: `none` is zero and
      // `pill` is a fixed value, so neither can move, and both are checked
      // against the file rather than assumed.
      for (final ResolvedAppearance resolved in <ResolvedAppearance>[
        crisp,
        soft,
      ]) {
        expect(resolved.style.radius('none'), 0.0);
        expect(resolved.style.radius('pill'), file.radiusPill());
      }
      expect(
        crisp.themeData.cardTheme,
        isNot(equals(soft.themeData.cardTheme)),
      );
      expect(
        crisp.themeData.inputDecorationTheme,
        isNot(equals(soft.themeData.inputDecorationTheme)),
      );
    });

    test('reaches the ThemeData shapes, with no second radius table', () {
      final ResolvedAppearance crisp = resolver.resolve(
        AppearanceSettings(radius: RadiusPreference.crisp),
        platformBrightness: Brightness.dark,
      );
      final BorderRadius cardRadius =
          (crisp.themeData.cardTheme.shape! as RoundedRectangleBorder)
              .borderRadius
              .resolve(TextDirection.ltr);
      expect(cardRadius.topLeft.x, closeTo(crisp.style.radius('md'), 1e-9));
      final BorderRadius inputRadius =
          (crisp.themeData.inputDecorationTheme.focusedBorder!
                  as OutlineInputBorder)
              .borderRadius
              .resolve(TextDirection.ltr);
      expect(inputRadius.topLeft.x, closeTo(crisp.style.radius('sm'), 1e-9));
    });
  });

  group('high contrast', () {
    test('pushes the ramps to their extremes and widens the focus ring', () {
      final AppearanceSettings base = settingsFor('midnight', 'blue');
      final ResolvedAppearance off = resolver.resolve(
        base,
        platformBrightness: Brightness.dark,
      );
      final ResolvedAppearance on = resolver.resolve(
        base.withHighContrast(true),
        platformBrightness: Brightness.dark,
      );

      // The text ramp collapses to one step and the primary goes to the extreme.
      expect(on.style.role('text'), on.style.role('textOnAccent'));
      expect(on.style.role('textMuted'), off.style.role('text'));
      expect(on.style.role('textSubtle'), off.style.role('text'));
      // The border ramp steps up one rung.
      expect(on.style.role('border'), off.style.role('borderStrong'));
      expect(on.style.role('borderStrong'), off.style.role('textMuted'));
      expect(on.style.highContrast, isTrue);
      expect(off.style.highContrast, isFalse);

      // Nothing is dimmed with an alpha, and every ramp step gets MORE contrast.
      for (final String role in <String>[
        'text',
        'textMuted',
        'textSubtle',
        'border',
      ]) {
        expect(on.style.role(role).a, 1.0, reason: role);
        expect(
          contrastRatio(on.style.role(role), on.style.role('surface')),
          greaterThanOrEqualTo(
            contrastRatio(off.style.role(role), off.style.role('surface')),
          ),
          reason: '$role must get more contrast, not less',
        );
      }
      expect(
        on.style.focusRingWidth,
        closeTo(file.focusRingWidth() + file.borderWidth(), 1e-9),
      );
      expect(off.style.focusRingWidth, file.focusRingWidth());
      expect(on.themeData.colorScheme.onSurface, on.style.role('text'));
      expect(
        on.themeData.colorScheme,
        isNot(equals(off.themeData.colorScheme)),
      );
      // And the palette still passes the token file's own gate.
      expect(
        on.report.hasIssues,
        isFalse,
        reason: on.report.messagesTr.join(' / '),
      );
    });

    test('pushes a light theme to its dark extreme instead', () {
      final AppearanceSettings base = settingsFor('light', 'teal');
      final ResolvedAppearance on = resolver.resolve(
        base.withHighContrast(true),
        platformBrightness: Brightness.light,
      );
      // In a light theme the extreme is the always-dark `stage`, not the white
      // `textOnAccent`, and `borderStrong` takes the ORIGINAL primary text -
      // which is what made the border step a real step.
      expect(on.style.role('text'), on.style.role('stage'));
      expect(
        on.style.role('text'),
        isNot(tryParseHexColor(file.roleHex('light', 'text'))!),
      );
      expect(
        on.style.role('borderStrong'),
        tryParseHexColor(file.roleHex('light', 'text')),
      );
      expect(
        contrastRatio(on.style.role('text'), on.style.role('surface')),
        greaterThanOrEqualTo(
          contrastRatio(
            tryParseHexColor(file.roleHex('light', 'text'))!,
            tryParseHexColor(file.roleHex('light', 'surface'))!,
          ),
        ),
      );
      expect(
        on.report.hasIssues,
        isFalse,
        reason: on.report.messagesTr.join(' / '),
      );
    });
  });

  group('reduce motion', () {
    test('replaces every duration with the token file\'s instant', () {
      final AppearanceSettings base = settingsFor('midnight', 'blue');
      final ResolvedAppearance off = resolver.resolve(
        base,
        platformBrightness: Brightness.dark,
      );
      final ResolvedAppearance on = resolver.resolve(
        base.withReduceMotion(true),
        platformBrightness: Brightness.dark,
      );

      final int instantMs = file.motionDuration('instant');
      for (final String name in file.motionNames()) {
        expect(
          on.style.duration(name),
          Duration(milliseconds: instantMs),
          reason: name,
        );
        expect(
          off.style.duration(name),
          Duration(milliseconds: file.motionDuration(name)),
          reason: name,
        );
      }
      expect(on.style.reduceMotion, isTrue);
      expect(off.style.reduceMotion, isFalse);
      // A ripple is motion too, so it is switched off rather than shortened.
      expect(on.themeData.splashFactory, NoSplash.splashFactory);
      expect(off.themeData.splashFactory, isNot(NoSplash.splashFactory));
      expect(
        on.themeData.splashFactory,
        isNot(equals(off.themeData.splashFactory)),
      );
      expect(
        on.style.motionEasing,
        off.style.motionEasing,
        reason: 'the curve stays; only the durations change',
      );
    });
  });

  test('the same preference resolves to the same theme twice', () {
    final ResolvedAppearance a = resolver.resolve(
      AppearanceSettings(),
      platformBrightness: Brightness.dark,
    );
    final ResolvedAppearance b = resolver.resolve(
      AppearanceSettings(),
      platformBrightness: Brightness.dark,
    );
    expect(a.style, b.style);
    expect(a.style.typeScale, b.style.typeScale);
    expect(a.style.space, b.style.space);
    expect(a.style.roles, b.style.roles);
    expect(a.themeData.colorScheme, b.themeData.colorScheme);
    expect(a.themeData.textTheme, b.themeData.textTheme);
  });
}

/// The generator's colour, as a Flutter colour.
Color _colorOf(Rgb value) => Color.fromARGB(value.a, value.r, value.g, value.b);
