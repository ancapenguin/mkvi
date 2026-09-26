// The state layer end to end: store, controller, resolved appearance.
//
// This is the file that pins the shape of the layer. The old build had a
// settings panel that wrote to localStorage and forty call sites that each
// decided for themselves what a token times a stored number should be, so:
//
//   * a stored value that no longer validated came back as the default with
//     nothing said - and the OTHER settings, which were perfectly readable,
//     were collateral damage in the tests that only ever looked at the theme;
//   * a settings change reached `localStorage` and the screen that made it, but
//     nothing forced the rest of the app to re-read the resolved numbers.
//
// So here: a corrupted document is reported AND the endpoint and the self name
// survive it, and every setter persists, re-resolves and notifies.

import 'dart:convert';
import 'dart:ui' show Brightness, Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/appearance_resolver.dart';
import 'package:mkvi/settings/appearance_settings.dart';
import 'package:mkvi/settings/appearance_style.dart';
import 'package:mkvi/settings/app_settings.dart';
import 'package:mkvi/settings/contrast.dart';
import 'package:mkvi/settings/settings_codec.dart';
import 'package:mkvi/settings/settings_controller.dart';
import 'package:mkvi/settings/settings_messages.dart';
import 'package:mkvi/settings/settings_repository.dart';
import 'package:mkvi/settings/settings_store.dart';

import 'support/design_bridge.dart';import 'support/tokens_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DesignTokensFixture fixture = DesignTokensFixture.load();
  final TokenFile file = fixture.file;

  late InMemorySettingsStore store;
  late SettingsController controller;
  int notifications = 0;

  SettingsController build([Brightness? brightness]) {
    final SettingsController created = SettingsController(
      repository: SettingsRepository(store),
      resolver: AppearanceResolver(fixture.tokens),
      platformBrightness: brightness ?? Brightness.dark,
    );
    created.addListener(() => notifications += 1);
    return created;
  }

  setUp(() {
    store = InMemorySettingsStore();
    controller = build();
    notifications = 0;
  });

  String encodedAppearance([Map<String, Object?>? overrides]) {
    return jsonEncode(<String, Object?>{
      SettingsCodec.versionKey: SettingsCodec.version,
      SettingsCodec.themeKey: 'forest',
      SettingsCodec.accentKey: 'teal',
      SettingsCodec.fontScaleKey: 1.15,
      SettingsCodec.densityKey: 'compact',
      SettingsCodec.radiusKey: 'crisp',
      SettingsCodec.highContrastKey: true,
      SettingsCodec.reduceMotionKey: true,
      ...?overrides,
    });
  }

  group('an empty store', () {
    test('is the defaults, and reports nothing', () {
      controller.load();
      expect(controller.settings, AppSettings.initial);
      expect(
        controller.report.hasIssues,
        isFalse,
        reason:
            'absence is not corruption: a first launch must not warn '
            'about a document nobody wrote',
      );
      expect(controller.appearance.theme, ThemePreference.system);
      expect(controller.settings.connection.hasEndpoint, isFalse);
      expect(controller.settings.selfName, '');
    });

    test('already holds a resolved appearance, not a raw preference', () {
      expect(controller.resolved.settings, controller.appearance);
      expect(controller.resolved.style.density, file.density('cozy'));
      expect(
        controller.resolved.style.typeStep('md').size,
        file.typeSize('md'),
      );
      expect(controller.resolved.themeId, file.defaultThemeId);
    });
  });

  group('a stored document', () {
    test('round-trips through the controller', () {
      store.write(SettingsKeys.appearance, encodedAppearance());
      controller.load();
      expect(
        controller.report.hasIssues,
        isFalse,
        reason: controller.report.messagesTr.join(' / '),
      );
      expect(controller.appearance.theme, ThemePreference.forest);
      expect(
        controller.appearance.accent,
        const AccentPreference.preset(AccentId.teal),
      );
      expect(controller.appearance.fontScale, 1.15);
      expect(controller.appearance.density, DensityPreference.compact);
      expect(controller.appearance.radius, RadiusPreference.crisp);
      expect(controller.appearance.highContrast, isTrue);
      expect(controller.appearance.reduceMotion, isTrue);
      // And the resolved numbers are the token numbers multiplied out.
      final AppearanceStyle style = controller.resolved.style;
      expect(style.density, file.density('compact'));
      expect(
        style.typeStep('md').size,
        closeTo(file.typeSize('md') * 1.15, 1e-9),
      );
      expect(
        style.control('md').height,
        closeTo(file.controlHeight('md') * file.density('compact'), 1e-9),
      );
      expect(
        style.radius('md'),
        closeTo(
          file.radiusPresetUnit('crisp') *
              file.radiusPresetScale('crisp') *
              0.75,
          1e-9,
        ),
      );
      expect(
        style.duration('normal'),
        Duration.zero,
        reason: 'reduce motion was stored on',
      );
    });

    test('a custom accent survives a restart', () {
      final Color chosen = tryParseHexColor(
        file.roleHex('midnight', 'dangerFill'),
      )!;
      store.write(
        SettingsKeys.appearance,
        encodedAppearance(<String, Object?>{
          SettingsCodec.accentKey: <String, Object?>{
            SettingsCodec.customAccentKey: hexOf(chosen),
          },
        }),
      );
      controller.load();
      expect(controller.appearance.accent, AccentPreference.custom(chosen));
      expect(controller.resolved.style.role('accent'), chosen);
    });
  });

  group('a corrupted document', () {
    test('is reported, and the endpoint and the self name survive it', () {
      store.write(
        SettingsKeys.appearance,
        encodedAppearance(<String, Object?>{SettingsCodec.themeKey: 'neon'}),
      );
      store.write(SettingsKeys.endpoint, 'https://signal.example.workers.dev');
      store.write(SettingsKeys.selfName, 'Ayşe Gül');

      controller.load();

      expect(controller.report.hasIssues, isTrue);
      expect(
        controller.report.issues.first.problem,
        SettingsProblem.unknownTheme,
      );
      expect(controller.report.issues.first.messageTr, contains('neon'));
      // Everything that could be read, was read.
      expect(
        controller.appearance.accent,
        const AccentPreference.preset(AccentId.teal),
      );
      expect(controller.appearance.fontScale, 1.15);
      expect(controller.appearance.density, DensityPreference.compact);
      expect(
        controller.settings.connection.signalingEndpoint,
        Uri.parse('https://signal.example.workers.dev'),
      );
      expect(controller.settings.selfName, 'Ayşe Gül');
    });

    test('a stored endpoint that no longer validates is reported too', () {
      store.write(SettingsKeys.endpoint, 'signal.example.workers.dev');
      store.write(SettingsKeys.iceServers, 'stun:stun.example.dev:3478');
      controller.load();
      expect(controller.report.hasIssues, isTrue);
      expect(
        controller.report.issues.map((i) => i.problem),
        contains(SettingsProblem.endpointNotAbsolute),
      );
      // The refusal does NOT become somebody else's hosted server.
      expect(controller.settings.connection.signalingEndpoint, isNull);
      expect(controller.settings.connection.hasEndpoint, isFalse);
      // The ICE text the user typed is still theirs.
      expect(
        controller.settings.connection.iceServersText,
        'stun:stun.example.dev:3478',
      );
    });

    test('a stored empty endpoint is reported, not treated as unset', () {
      store.write(SettingsKeys.endpoint, '');
      controller.load();
      expect(
        controller.report.issues.map((i) => i.problem),
        contains(SettingsProblem.endpointEmpty),
      );
      expect(controller.settings.connection.hasEndpoint, isFalse);
    });

    test('a self name that was not sanitised is corrected and reported', () {
      store.write(
        SettingsKeys.selfName,
        ' Ayşe${String.fromCharCode(0x200b)} Gül ',
      );
      controller.load();
      expect(controller.settings.selfName, 'Ayşe Gül');
      expect(
        controller.report.issues.map((i) => i.problem),
        contains(SettingsProblem.selfNameSanitised),
      );
    });

    test('a document that is not JSON at all', () {
      store.write(SettingsKeys.appearance, 'not json');
      store.write(SettingsKeys.selfName, 'Ayşe');
      controller.load();
      expect(
        controller.report.issues.single.problem,
        SettingsProblem.malformedDocument,
      );
      expect(controller.appearance, AppearanceSettings.initial);
      expect(
        controller.settings.selfName,
        'Ayşe',
        reason: 'a different key is a different document',
      );
    });
  });

  group('changing the appearance', () {
    test('persists, re-resolves and notifies', () async {
      await controller.setTheme(ThemePreference.plum);
      expect(notifications, 1);
      expect(controller.appearance.theme, ThemePreference.plum);
      expect(controller.resolved.themeId, 'plum');
      expect(
        controller.resolved.style.role('bg'),
        tryParseHexColor(file.roleHex('plum', 'bg')),
      );

      // The value is on disk, in the codec's own document.
      final SettingsDocument reloaded = SettingsRepository(store).load();
      expect(reloaded.settings.appearance.theme, ThemePreference.plum);
      expect(reloaded.report.hasIssues, isFalse);
    });

    test('every preference reaches the resolved values', () async {
      final double compact = file.density('compact');
      await controller.setDensity(DensityPreference.compact);
      await controller.setFontScale(1.25);
      await controller.setRadius(RadiusPreference.crisp);
      await controller.setHighContrast(true);
      await controller.setReduceMotion(true);
      await controller.setAccent(const AccentPreference.preset(AccentId.amber));

      final AppearanceStyle style = controller.resolved.style;
      expect(style.density, compact);
      expect(style.gap('4'), closeTo(file.spaceUnit() * 4 * compact, 1e-9));
      expect(
        style.typeStep('md').size,
        closeTo(file.typeSize('md') * 1.25, 1e-9),
      );
      expect(
        style.radius('md'),
        closeTo(
          file.radiusPresetUnit('crisp') *
              file.radiusPresetScale('crisp') *
              0.75,
          1e-9,
        ),
      );
      expect(style.highContrast, isTrue);
      expect(style.reduceMotion, isTrue);
      expect(
        style.duration('fast'),
        Duration(milliseconds: file.motionDuration('instant')),
      );
      expect(
        style.role('accent'),
        tryParseHexColor(file.accentHex('amber', 'base')),
      );
      // The controller's own copy agrees with the resolved one, because the
      // controller re-resolves on every change.
      expect(controller.resolved.settings, controller.appearance);
      expect(
        SettingsRepository(store).load().settings.appearance,
        controller.appearance,
      );
    });

    test('setting the same value again is a no-op', () async {
      await controller.setFontScale(1.1);
      expect(notifications, greaterThan(0));
      final int before = notifications;
      await controller.setFontScale(1.1);
      expect(notifications, before);
    });

    test('the font scale is normalised before it is stored', () async {
      await controller.setFontScale(3);
      expect(controller.appearance.fontScale, AppearanceSettings.maxFontScale);
      expect(
        SettingsRepository(store).load().settings.appearance.fontScale,
        AppearanceSettings.maxFontScale,
      );
    });

    test('resetting returns to the shipped defaults', () async {
      await controller.setTheme(ThemePreference.plum);
      await controller.setFontScale(1.25);
      await controller.setHighContrast(true);
      await controller.resetAppearance();
      expect(controller.appearance, AppearanceSettings.initial);
      expect(controller.resolved.themeId, file.defaultThemeId);
      expect(
        SettingsRepository(store).load().settings.appearance,
        AppearanceSettings.initial,
      );
    });
  });

  group('the system theme', () {
    test('follows the platform when it changes, without a restart', () {
      final String lightTheme = file.themeIds.firstWhere(
        (String id) => !file.isDarkTheme(id),
      );
      expect(controller.resolved.themeId, file.defaultThemeId);
      controller.updatePlatformBrightness(Brightness.light);
      expect(controller.resolved.themeId, lightTheme);
      expect(controller.resolved.brightness, Brightness.light);
      expect(
        controller.resolved.style.role('bg'),
        tryParseHexColor(file.roleHex(lightTheme, 'bg')),
      );
      // The preference is still "system": nothing was written.
      expect(controller.appearance.theme, ThemePreference.system);
      expect(store.read(SettingsKeys.appearance), isNull);
    });

    test('an explicit theme is not moved by the platform', () async {
      await controller.setTheme(ThemePreference.plum);
      controller.updatePlatformBrightness(Brightness.light);
      expect(controller.resolved.themeId, 'plum');
    });
  });

  group('changing the connection', () {
    test('an empty endpoint is refused, with a Turkish reason', () async {
      expect(await controller.setEndpoint(''), isFalse);
      expect(controller.endpointErrorTr, isNotNull);
      expect(controller.endpointErrorTr, contains('boş olamaz'));
      expect(controller.settings.connection.hasEndpoint, isFalse);
      expect(store.read(SettingsKeys.endpoint), isNull);
    });

    test('a relative endpoint is refused, and nothing is written', () async {
      expect(
        await controller.setEndpoint('signal.example.workers.dev'),
        isFalse,
      );
      expect(controller.endpointErrorTr, contains('tam bir adres'));
      expect(store.read(SettingsKeys.endpoint), isNull);
      expect(store.read(SettingsKeys.iceServers), isNull);
    });

    test('a valid endpoint is accepted, stored and clears the error', () async {
      controller.setEndpoint('');
      expect(controller.endpointErrorTr, isNotNull);
      expect(
        await controller.setEndpoint(
          'https://signal.example.workers.dev',
          iceServersText: 'stun:stun.example.dev:3478',
        ),
        isTrue,
      );
      expect(controller.endpointErrorTr, isNull);
      expect(
        controller.settings.connection.signalingEndpoint,
        Uri.parse('https://signal.example.workers.dev'),
      );
      expect(
        store.read(SettingsKeys.endpoint),
        'https://signal.example.workers.dev',
      );
      expect(store.read(SettingsKeys.iceServers), 'stun:stun.example.dev:3478');
    });
  });

  group('changing the self name', () {
    test('is sanitised on the way in and on the way out', () async {
      await controller.setSelfName(
        '  Ayşe${String.fromCharCode(0x200b)}   Gül  ',
      );
      expect(controller.settings.selfName, 'Ayşe Gül');
      expect(store.read(SettingsKeys.selfName), 'Ayşe Gül');
      expect(controller.selfNameErrorTr, isNull);
      // A second controller reading the same store sees the same name.
      final SettingsController other = build();
      other.load();
      expect(other.settings.selfName, 'Ayşe Gül');
    });
  });

  test('the catalogue is reachable from the state, with token-file names', () {
    expect(
      controller.catalog.themeOptionLabel(ThemePreference.system),
      controller.catalog.systemThemeLabel,
    );
    for (final String themeId in file.themeIds) {
      expect(
        controller.catalog.themeOptionLabel(
          ThemePreference.fromThemeId(themeId),
        ),
        file.themeLabel(themeId),
        reason: themeId,
      );
    }
    for (final String accentId in file.accentIds) {
      expect(
        controller.catalog.accentOptionLabel(AccentId.fromAccentId(accentId)!),
        file.accentLabel(accentId),
        reason: accentId,
      );
    }
  });
}
