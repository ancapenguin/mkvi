/// The settings store, the appearance codec and the self-name field, composed.
///
/// One object owns the whole read and the whole write, so there is exactly one
/// place that knows which key holds what. The old build spread that over
/// `localStorage.getItem` calls scattered through a component, which is how a
/// settings screen ends up painting one value and saving another.
///
/// The values keep the key names `app/lib/session/local_settings.dart` already
/// writes - one appearance document, one endpoint, one ICE text, one self name
/// - so there is one copy of each on disk, not two that can drift.
library;

import 'appearance_settings.dart';
import 'app_settings.dart';
import 'connection_settings.dart';
import 'self_name.dart';
import 'settings_codec.dart';
import 'settings_issue.dart';
import 'settings_messages.dart';
import 'settings_store.dart';

/// A loaded settings document: the value, and what had to be corrected.
final class SettingsDocument {
  const SettingsDocument(this.settings, this.report);

  /// The usable value. Always complete.
  final AppSettings settings;

  /// Every correction made while reading, in the order it was found.
  final SettingsReport report;

  @override
  String toString() => 'SettingsDocument($settings, $report)';
}

/// Reads and writes [AppSettings] through a [SettingsStore].
final class SettingsRepository {
  const SettingsRepository(this.store, {this.codec = const SettingsCodec()});

  /// Where the bytes live.
  final SettingsStore store;

  /// The appearance document's reader and writer.
  final SettingsCodec codec;

  /// Every key this repository touches, in the order it reads them.
  static const List<String> keys = <String>[
    SettingsKeys.appearance,
    SettingsKeys.endpoint,
    SettingsKeys.iceServers,
    SettingsKeys.selfName,
  ];

  /// Reads everything, correcting and reporting whatever it has to.
  ///
  /// A store with nothing in it yields [AppSettings.initial] and an empty
  /// report: absence is not corruption, and a fresh install must not greet the
  /// user with a warning about a document that was never written.
  SettingsDocument load() {
    final List<SettingsIssue> issues = <SettingsIssue>[];

    final String? storedAppearance = store.read(SettingsKeys.appearance);
    AppearanceSettings appearance = AppearanceSettings.initial;
    if (storedAppearance != null) {
      final AppearanceDocument document = codec.decodeAppearance(
        storedAppearance,
      );
      appearance = document.settings;
      issues.addAll(document.report.issues);
    }

    final ConnectionSettings connection = _readConnection(issues);
    final String selfName = _readSelfName(issues);

    return SettingsDocument(
      AppSettings(
        appearance: appearance,
        connection: connection,
        selfName: selfName,
      ),
      SettingsReport(List<SettingsIssue>.unmodifiable(issues)),
    );
  }

  /// Writes the appearance document.
  Future<void> saveAppearance(AppearanceSettings appearance) =>
      store.write(SettingsKeys.appearance, codec.encodeAppearance(appearance));

  /// Writes the endpoint and the ICE text.
  ///
  /// An unset endpoint REMOVES its key rather than writing an empty string, so
  /// "not configured" has one representation on disk. The two writes are not
  /// atomic; a crash between them leaves a stale ICE text next to a correct
  /// endpoint, which the next load reports rather than hides.
  Future<void> saveConnection(ConnectionSettings connection) async {
    final String? endpoint = connection.signalingEndpoint?.toString();
    if (endpoint == null) {
      await store.remove(SettingsKeys.endpoint);
    } else {
      await store.write(SettingsKeys.endpoint, endpoint);
    }
    if (connection.iceServersText.isEmpty) {
      await store.remove(SettingsKeys.iceServers);
    } else {
      await store.write(SettingsKeys.iceServers, connection.iceServersText);
    }
  }

  /// Writes the self name, sanitised. See [SelfNameField].
  Future<void> saveSelfName(String raw) async =>
      store.write(selfNameKey, sanitisedSelfName(raw));

  ConnectionSettings _readConnection(List<SettingsIssue> issues) {
    final String iceServersText = (store.read(SettingsKeys.iceServers) ?? '')
        .trim();

    final String? storedEndpoint = store.read(SettingsKeys.endpoint);
    if (storedEndpoint == null) {
      return ConnectionSettings(iceServersText: iceServersText);
    }

    // The stored value is a URL this build already accepted once. If it does
    // not validate now, something changed underneath us - and the correct
    // behaviour is to refuse to use it AND say so, never to fall back to
    // somebody's hosted server.
    final EndpointValidation validation = validateEndpoint(storedEndpoint);
    if (validation.isAccepted) {
      return ConnectionSettings(
        signalingEndpoint: validation.endpoint,
        iceServersText: iceServersText,
      );
    }
    issues.add(validation.toIssue('yapılandırılmamış'));
    return ConnectionSettings(iceServersText: iceServersText);
  }

  String _readSelfName(List<SettingsIssue> issues) {
    final String? stored = store.read(SettingsKeys.selfName);
    if (stored == null) return '';
    final String clean = sanitisedSelfName(stored);
    if (clean != stored) {
      issues.add(
        const SettingsIssue(
          problem: SettingsProblem.selfNameSanitised,
          key: SettingsKeys.selfName,
        ),
      );
    }
    return clean;
  }
}
