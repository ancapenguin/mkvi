/// The state the whole app reads, and the only place a setting is written.
///
/// The settings screen does not own a value and the app does not own another
/// one: both go through here, and both read the same [resolved] appearance.
/// That is the point of the layer. The old build had a settings panel that
/// wrote to `localStorage` and forty call sites that each decided for
/// themselves what a token times a stored number should be, so "density"
/// meant something different in a chat row than in a settings row and the
/// type scale simply did not reach the first-run screens.
///
/// ## What the state holds
///
/// * [settings] - the raw preference, so a control can show what the user
///   picked even when it has not been accepted yet.
/// * [resolved] - the RESOLVED appearance: every spacing step, radius, type
///   size, control height and duration already multiplied out, plus the
///   `ThemeData`. This is the value the UI reads; there is nothing left for it
///   to resolve, which is why it cannot resolve something differently in the
///   fortieth place.
/// * [report] - what the last read had to correct, in Turkish, so a silent
///   fall back to a default is not representable.
/// * [endpointErrorTr] - the Turkish reason the last endpoint was refused,
///   cleared as soon as it is accepted, so the field can show the reason
///   instead of the user guessing.
library;

import 'package:flutter/foundation.dart';

import 'appearance_resolver.dart';
import 'appearance_settings.dart';
import 'app_settings.dart';
import 'connection_settings.dart';
import 'self_name.dart';
import 'settings_catalog.dart';
import 'settings_issue.dart';
import 'settings_repository.dart';

/// The observable settings state.
final class SettingsController extends ChangeNotifier {
  SettingsController({
    required SettingsRepository repository,
    required AppearanceResolver resolver,
    Brightness? platformBrightness,
    // A named parameter cannot be an initialising formal for a private field:
    // Dart forbids a named parameter whose name starts with an underscore, so
    // `this._repository` is not available and the assignment has to stand.
    // ignore: prefer_initializing_formals
  }) : _repository = repository,
       _resolver = resolver,
       _platformBrightness = platformBrightness,
       _catalog = SettingsCatalog(resolver.tokens),
       _settings = AppSettings.initial,
       _report = SettingsReport.clean,
       _resolved = resolver.resolve(
         AppSettings.initial.appearance,
         platformBrightness: platformBrightness,
       );

  final SettingsRepository _repository;
  final AppearanceResolver _resolver;
  final SettingsCatalog _catalog;
  Brightness? _platformBrightness;
  AppSettings _settings;
  SettingsReport _report;
  ResolvedAppearance _resolved;
  String? _endpointErrorTr;
  String? _selfNameErrorTr;

  // --- what the app reads ----------------------------------------------------

  /// The Turkish text of the settings screen.
  SettingsCatalog get catalog => _catalog;

  /// The stored preference.
  AppSettings get settings => _settings;

  /// The appearance preference, for a control that only shows appearance.
  AppearanceSettings get appearance => _settings.appearance;

  /// The resolved appearance: the `ThemeData`, the palette and every number.
  ///
  /// Recomputed on every change, so there is no way to paint with a stale one.
  ResolvedAppearance get resolved => _resolved;

  /// What the last read had to correct, in Turkish.
  SettingsReport get report => _report;

  /// The Turkish reason the last endpoint was refused, or null.
  String? get endpointErrorTr => _endpointErrorTr;

  /// The Turkish reason the last self name was refused, or null.
  ///
  /// Always null today: a name is sanitised rather than refused. The getter
  /// exists so the field has one shape whether or not a future rule refuses
  /// something.
  String? get selfNameErrorTr => _selfNameErrorTr;

  // --- reading ---------------------------------------------------------------

  /// Reads the store and resolves. Safe to call again at any time.
  ///
  /// A store that is empty yields the defaults and an EMPTY report: absence is
  /// not corruption, and a first launch must not greet the user with a warning
  /// about a document nobody wrote.
  void load() {
    final SettingsDocument document = _repository.load();
    _settings = document.settings;
    _report = document.report;
    _endpointErrorTr = null;
    _selfNameErrorTr = null;
    _rebuild();
  }

  /// Re-resolves after the platform changed its light/dark setting.
  ///
  /// Called on a `didChangePlatformBrightness` so `system` follows the OS
  /// without a restart - which is the whole reason the old build made a
  /// light-OS user pick the light theme by hand, on every install.
  void updatePlatformBrightness(Brightness brightness) {
    if (_platformBrightness == brightness) return;
    _platformBrightness = brightness;
    _rebuild();
  }

  // --- appearance ------------------------------------------------------------

  /// Applies [appearance], saves it and re-resolves.
  Future<void> setAppearance(AppearanceSettings appearance) async {
    if (appearance == _settings.appearance) return;
    _settings = _settings.withAppearance(appearance);
    _rebuild();
    await _repository.saveAppearance(_settings.appearance);
  }

  /// Sets the theme, including [ThemePreference.system].
  Future<void> setTheme(ThemePreference theme) =>
      setAppearance(appearance.withTheme(theme));

  /// Sets the accent, shipped or custom.
  Future<void> setAccent(AccentPreference accent) =>
      setAppearance(appearance.withAccent(accent));

  /// Sets the type size. The scale is normalised before it is stored.
  Future<void> setFontScale(double scale) =>
      setAppearance(appearance.withFontScale(scale));

  /// Sets the density.
  Future<void> setDensity(DensityPreference density) =>
      setAppearance(appearance.withDensity(density));

  /// Sets the corner preset.
  Future<void> setRadius(RadiusPreference radius) =>
      setAppearance(appearance.withRadius(radius));

  /// Turns high contrast on or off.
  Future<void> setHighContrast(bool value) =>
      setAppearance(appearance.withHighContrast(value));

  /// Turns reduced motion on or off.
  Future<void> setReduceMotion(bool value) =>
      setAppearance(appearance.withReduceMotion(value));

  /// Back to [AppearanceSettings.initial].
  Future<void> resetAppearance() => setAppearance(AppearanceSettings.initial);

  // --- connection ------------------------------------------------------------

  /// Applies an endpoint typed into the settings form.
  ///
  /// Returns false and leaves everything untouched when the value is refused;
  /// the reason is then in [endpointErrorTr]. MKVI embeds no server, so an
  /// empty value is not "use the default one" - it is a refusal, and there is
  /// no default one to fall back to.
  Future<bool> setEndpoint(String raw, {String iceServersText = ''}) async {
    final ({ConnectionSettings? settings, EndpointValidation? validation})
    form = ConnectionSettings.fromForm(
      endpointText: raw,
      iceServersText: iceServersText,
    );
    final EndpointValidation? validation = form.validation;
    if (validation == null || !validation.isAccepted) {
      _endpointErrorTr = validation?.errorTr;
      notifyListeners();
      return false;
    }
    _endpointErrorTr = null;
    _settings = _settings.copyWith(connection: form.settings);
    _rebuild();
    await _repository.saveConnection(_settings.connection);
    return true;
  }

  // --- identity --------------------------------------------------------------

  /// Applies a self name typed into the settings form.
  ///
  /// Sanitised on the way in by the same function the wire uses, and sanitised
  /// again on the next read, so neither an old build nor a hand-edited store
  /// can get an unsanitised name onto the wire.
  Future<void> setSelfName(String raw) async {
    _selfNameErrorTr = null;
    _settings = _settings.copyWith(selfName: sanitisedSelfName(raw));
    notifyListeners();
    await _repository.saveSelfName(raw);
  }

  // --- internals -------------------------------------------------------------

  void _rebuild() {
    _resolved = _resolver.resolve(
      _settings.appearance,
      platformBrightness: _platformBrightness,
    );
    notifyListeners();
  }
}
