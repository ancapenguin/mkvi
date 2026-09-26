/// Where a setting is kept, and the one in-memory implementation.
///
/// The interface is deliberately tiny - read, write, remove - and deliberately
/// untyped at the edges: every value is a string, because the layer above
/// decides what a value MEANS and is the only place that can report a
/// correction. A store that validated would have to know the schema, and then
/// the schema would live in two files.
///
/// The key strings are the ones `app/lib/session/local_settings.dart` writes,
/// so the two halves of the app read one store. They are repeated rather than
/// imported because that module belongs to the session layer, and a settings
/// layer that has to be able to run on its own is easier to test than one that
/// drags the session with it.
library;

/// The keys the settings layer owns.
final class SettingsKeys {
  const SettingsKeys._();

  /// The whole appearance document, as one JSON object.
  static const String appearance = 'mkvi.appearance';

  /// The signaling endpoint, as a URL.
  static const String endpoint = 'mkvi.rendezvousEndpoint';

  /// The ICE server list, as free text.
  static const String iceServers = 'mkvi.iceServers';

  /// This device's own name.
  static const String selfName = 'mkvi.selfName';
}

/// The key the self name is stored under.
///
/// Spelled as its own constant because the self-name field and the settings
/// document both name it, and a typo in either would be silent.
const String selfNameKey = SettingsKeys.selfName;

/// A persistent key/value store.
///
/// Reads are synchronous because the app has to paint a theme before its first
/// frame; writes are not, because the real backing store is a file or
/// `shared_preferences` and pretending otherwise is how a settings screen ends
/// up lying about what it saved.
abstract interface class SettingsStore {
  /// The stored value, or null when the key was never written.
  String? read(String key);

  /// Writes [value] under [key] and completes when it is durable.
  Future<void> write(String key, String value);

  /// Removes [key] and completes when it is gone.
  Future<void> remove(String key);
}

/// An in-memory [SettingsStore].
///
/// The fake the tests use and the default a preview or a test harness uses, so
/// "no store configured" is never a reason to crash. It keeps insertion order,
/// which makes a failing assertion about a rewritten key readable.
final class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, String>? initial])
    : _values = <String, String>{...?initial};

  final Map<String, String> _values;

  /// The keys currently written, in the order they were first written.
  Iterable<String> get keys => _values.keys;

  /// The value under [key], or null.
  @override
  String? read(String key) => _values[key];

  /// Writes [value]. Completes immediately.
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  /// Removes [key]. Completes immediately.
  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  /// A copy of everything stored, for a test that wants to assert on the bytes.
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_values);

  /// Empties the store.
  void clear() => _values.clear();
}
