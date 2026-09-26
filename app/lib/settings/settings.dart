/// The appearance and settings state layer.
///
/// Comments are English, every string a user can read is Turkish, and no
/// colour, size, radius or duration is written down in this library: they all
/// come from `design/tokens.json` through [AppearanceTokens].
///
/// The pieces, and which one a caller wants:
///
/// * [AppearanceSettings] - the raw preference. A settings control reads and
///   writes this.
/// * [AppearanceStyle] - the RESOLVED value, attached to the `ThemeData` as a
///   `ThemeExtension`. A widget reads this, and it is the only source of a
///   spacing step, a radius, a font size, a control height or a duration.
/// * [AppearanceResolver] - the one function that turns the first into the
///   second. Nothing else multiplies anything.
/// * [SettingsController] - the observable state: read the store, apply a
///   change, save it, re-resolve. The app and the settings screen share it.
/// * [SettingsRepository] / [SettingsStore] / [SettingsCodec] - persistence,
///   with a report of every correction instead of a silent default.
/// * [ConnectionSettings] / [SelfNameField] - where to connect and what to
///   call ourselves, both refusing a value they cannot use.
/// * [SettingsCatalog] - every label the settings screen shows.
library;

export 'appearance_resolver.dart';
export 'appearance_settings.dart';
export 'appearance_style.dart';
export 'app_settings.dart';
export 'connection_settings.dart';
export 'contrast.dart';
export 'design_tokens.dart';
export 'self_name.dart';
export 'settings_catalog.dart';
export 'settings_controller.dart';
export 'settings_codec.dart';
export 'settings_issue.dart';
export 'settings_messages.dart';
export 'settings_repository.dart';
export 'settings_store.dart';
