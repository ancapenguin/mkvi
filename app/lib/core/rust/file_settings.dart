/// One settings file, and the two interfaces that read it.
///
/// ## Why this file is the point
///
/// Two interfaces in two layers describe the same store:
///
/// | | `read` | `write` | `remove` |
/// |---|---|---|---|
/// | `LocalSettings` (`session/local_settings.dart:50-57`) | `String?` | `void` | `void` |
/// | `SettingsStore` (`settings/settings_store.dart:45-54`) | `String?` | `Future<void>` | `Future<void>` |
///
/// and two writers in two layers write the same key — `mkvi.selfName`:
/// `SettingsController.setSelfName` goes through
/// `SettingsRepository.saveSelfName`, and `SessionController.setSelfName` goes
/// through `SelfName.write`. Give them two backends and a user who renames
/// themselves in settings sends the old name to the peer, because the session
/// layer still reads the key its own writer wrote. The two `SettingsKeys`
/// classes already repeat the literals on purpose, so the *strings* agreeing is
/// not evidence; one backend answering both interfaces is.
///
/// **Zero new packages.** `local_settings.dart:48` says "implemented over
/// `shared_preferences` or a small file", and the ADR accepts "a small file":
/// `path_provider` is already a dependency, it was simply not imported anywhere
/// (`pubspec.yaml:32`). So this is a file, and `path_provider` is used exactly
/// where it is needed — to find the directory.
///
/// ## Sync reads over an async file
///
/// `LocalSettings.read` is synchronous because the app has to paint a theme
/// before its first frame. The backend therefore holds the whole document in
/// memory and treats the file as its durable copy: a read is a map lookup, and a
/// write updates memory **synchronously** before the flush is scheduled. That is
/// what lets the two interfaces share one value — a `void` write through
/// `LocalSettings` is visible to the next synchronous read, and to the next
/// awaited `SettingsStore.read`, with no ordering rule a caller has to know.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mkvi/session/local_settings.dart';
import 'package:mkvi/settings/settings_store.dart';
import 'package:path_provider/path_provider.dart';

/// The file name inside the application support directory.
const String settingsFileName = 'settings.json';

/// The settings document, as one JSON object of strings.
///
/// Every value is a string because that is what both interfaces promise; a store
/// that validated would have to know the schema, and the schema lives in the two
/// layers above, in one place each.
final class FileSettingsBackend {
  FileSettingsBackend._(this.directory, this._values);

  /// The directory the file lives in.
  final Directory directory;

  final Map<String, String> _values;

  File get _file => File('${directory.path}${Platform.pathSeparator}$settingsFileName');

  /// Everything stored, as an unmodifiable copy.
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_values);

  /// Completes when the file matches memory.
  ///
  /// Exists because [LocalSettings.write] cannot await: the durability of a
  /// `void` write is a promise the backend keeps on its own behalf, and this is
  /// how a test or a shutdown path waits for it.
  Future<void> get idle => _pendingFlush;

  Future<void> _pendingFlush = Future<void>.value();

  /// Opens the backend over an explicit directory, creating it if needed.
  ///
  /// The whole file is read once, here. A file that does not exist is a first
  /// run, not an error; a file that exists but is not a JSON object of strings is
  /// **refused** rather than silently replaced, because overwriting it is how a
  /// hand-edited or truncated settings file loses everything at once.
  static FileSettingsBackend openAt(Directory directory) {
    directory.createSync(recursive: true);
    final File file = File(
      '${directory.path}${Platform.pathSeparator}$settingsFileName',
    );
    final Map<String, String> values = <String, String>{};
    if (file.existsSync()) {
      final String raw = file.readAsStringSync(encoding: utf8);
      if (raw.trim().isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is! Map<String, Object?>) {
          throw const FileSettingsCorrupt(
            'Ayar dosyası okunamadı: dosya bir anahtar-değer listesi değil.',
          );
        }
        decoded.forEach((String key, Object? value) {
          if (value is String) values[key] = value;
        });
      }
    }
    return FileSettingsBackend._(directory, values);
  }

  /// Opens the backend in the platform's application support directory.
  ///
  /// [path_provider] reaches a platform channel, so it fails under a plain
  /// `flutter test` and on a platform without the plugin. That is reported as a
  /// value, never as a throw, for the same reason the bridge is: a machine
  /// without the plumbing must show a message, not a stack trace.
  static Future<FileSettingsOpenResult> openDefault() async {
    try {
      final Directory support = await getApplicationSupportDirectory();
      return FileSettingsOpened(FileSettingsBackend.openAt(support));
    } on Object catch (failure) {
      return FileSettingsUnopened(
        'Uygulama ayarları açılamadı: veri klasörü bulunamadı.',
        'Uygulamayı yeniden başlat. Sorun sürerse cihazdaki '
        'depolama iznini kontrol et.',
        cause: failure,
      );
    }
  }

  /// The stored value, or null when the key was never written.
  String? read(String key) => _values[key];

  /// Stores [value] under [key]. Memory changes **synchronously**; the file
  /// follows.
  void put(String key, String value) {
    if (_values[key] == value) return;
    _values[key] = value;
    _scheduleFlush();
  }

  /// Deletes [key]. Memory changes **synchronously**; the file follows.
  void drop(String key) {
    if (_values.remove(key) == null) return;
    _scheduleFlush();
  }

  /// Writes the file now, whatever is pending.
  Future<void> flush() {
    _scheduleFlush();
    return _pendingFlush;
  }

  void _scheduleFlush() {
    // Chained rather than concurrent: two overlapping writes to the same file
    // would let the slower one land last, and a settings screen that saves the
    // endpoint and then the self name must not end up with the first one back.
    _pendingFlush = _pendingFlush.then((_) => _writeFile(), onError: (Object _) {
      return _writeFile();
    });
  }

  Future<void> _writeFile() async {
    final File target = _file;
    final File temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(_values), encoding: utf8, flush: true);
    // Replace rather than truncate in place: a crash mid-write then leaves the
    // previous document intact instead of a half-written one.
    if (target.existsSync()) await target.delete();
    await temporary.rename(target.path);
  }
}

/// A settings file that is not a JSON object of strings.
final class FileSettingsCorrupt implements Exception {
  const FileSettingsCorrupt(this.message);

  /// Turkish, and says what happened.
  final String message;

  @override
  String toString() => 'FileSettingsCorrupt: $message';
}

/// The outcome of [FileSettingsBackend.openDefault].
sealed class FileSettingsOpenResult {
  const FileSettingsOpenResult();
}

/// Opened.
final class FileSettingsOpened extends FileSettingsOpenResult {
  const FileSettingsOpened(this.backend);

  final FileSettingsBackend backend;
}

/// Could not be opened, with a Turkish reason and remedy.
final class FileSettingsUnopened extends FileSettingsOpenResult {
  const FileSettingsUnopened(this.message, this.recovery, {this.cause});

  final String message;
  final String recovery;
  final Object? cause;

  @override
  String toString() => 'FileSettingsUnopened: $message $recovery';
}

/// `LocalSettings` over [FileSettingsBackend].
///
/// The session layer's half. Synchronous, as its interface demands.
final class FileLocalSettings implements LocalSettings {
  const FileLocalSettings(this._backend);

  final FileSettingsBackend _backend;

  /// The backend behind this interface, for a caller that also needs the
  /// `SettingsStore` half. One backend, two views — that is the whole point.
  FileSettingsBackend get backend => _backend;

  @override
  String? read(String key) => _backend.read(key);

  @override
  void write(String key, String value) => _backend.put(key, value);

  @override
  void remove(String key) => _backend.drop(key);
}

/// `SettingsStore` over the same [FileSettingsBackend].
///
/// The settings layer's half. Awaited, as its interface demands — and the await
/// is real, because the backend serialises its flushes.
final class FileSettingsStore implements SettingsStore {
  const FileSettingsStore(this._backend);

  final FileSettingsBackend _backend;

  /// The backend behind this interface.
  FileSettingsBackend get backend => _backend;

  @override
  String? read(String key) => _backend.read(key);

  @override
  Future<void> write(String key, String value) async {
    _backend.put(key, value);
    await _backend.idle;
  }

  @override
  Future<void> remove(String key) async {
    _backend.drop(key);
    await _backend.idle;
  }
}
