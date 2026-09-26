/// Everything a user can set, in one immutable value.
///
/// Three parts, three files: what the app looks like
/// ([AppearanceSettings]), where it connects ([ConnectionSettings]) and what it
/// calls itself (a sanitised string). They are bundled because they are read
/// and written together, and a settings screen that assembles three objects
/// itself will eventually save one of them without the other two.
library;

import 'appearance_settings.dart';
import 'connection_settings.dart';

/// The whole settings document, in memory.
final class AppSettings {
  const AppSettings({
    this.appearance = AppearanceSettings.initial,
    this.connection = ConnectionSettings.initial,
    this.selfName = '',
  });

  /// A fresh install: follow the operating system's theme, the default accent,
  /// no server configured, no name chosen.
  static const AppSettings initial = AppSettings();

  /// Theme, accent, type scale, density, radius and the two accessibility
  /// switches.
  final AppearanceSettings appearance;

  /// The signaling endpoint and the ICE text.
  final ConnectionSettings connection;

  /// This device's own name, already sanitised. Always read through
  /// `SelfNameField`; a name that reaches here unsanitised is a bug in the
  /// caller, and this value refuses to be one by construction.
  final String selfName;

  AppSettings copyWith({
    AppearanceSettings? appearance,
    ConnectionSettings? connection,
    String? selfName,
  }) {
    return AppSettings(
      appearance: appearance ?? this.appearance,
      connection: connection ?? this.connection,
      selfName: selfName ?? this.selfName,
    );
  }

  /// The same value, a different appearance.
  AppSettings withAppearance(AppearanceSettings value) =>
      copyWith(appearance: value);

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.appearance == appearance &&
      other.connection == connection &&
      other.selfName == selfName;

  @override
  int get hashCode => Object.hash(appearance, connection, selfName);

  @override
  String toString() =>
      'AppSettings($appearance, $connection, selfName: "$selfName")';
}
