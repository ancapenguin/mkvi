/// The local, unencrypted key/value store: `localStorage` in the TypeScript
/// original.
///
/// Nothing secret may ever be written here. The peer record lives in the
/// encrypted [PeerStore] and the private key lives in the OS keyring; this
/// store holds the signaling endpoint, this device's own display name, and the
/// peer's local annotation - and that last one is a note about a person, not
/// data about a secret.
library;

/// The production signaling endpoint. TS: `defaultEndpoint` at `src/App.tsx:32`.
const String defaultRendezvousEndpoint =
    'https://mkvi-signal.12orgcom09.workers.dev';

/// Every key the app reads or writes here. TS: the `mkvi.*` literals at
/// `src/App.tsx:33-35`, `75`, `81`, `328-329`, `522` and `595`.
final class SettingsKeys {
  const SettingsKeys._();

  static const String rendezvousEndpoint = 'mkvi.rendezvousEndpoint';
  static const String iceServers = 'mkvi.iceServers';
  static const String selfName = 'mkvi.selfName';
  static const String appearance = 'mkvi.appearance';

  /// The unscoped key 0.1.x wrote the peer's annotation under. Read exactly
  /// once, by [PeerAliasStore.migrateLegacyAlias], and never as a fallback.
  static const String legacyPeerAlias = 'mkvi.peerName';

  /// The scoped prefix. TS: `peerAliasKey` at `src/App.tsx:75`.
  static const String peerAliasPrefix = 'mkvi.peerAlias.';
}

/// `mkvi.peerAlias.<publicKey>`. TS: `src/App.tsx:75`.
///
/// The public key is part of the key on purpose: an annotation is a note about
/// ONE person, and scoping it by anything weaker (a discovery id, a device id,
/// a slot number) is how the note ends up attached to the next person.
String peerAliasKey(String publicKey) =>
    '${SettingsKeys.peerAliasPrefix}$publicKey';

/// The local store. Implemented over `shared_preferences` or a small file;
/// a fake stands in for it in tests.
abstract class LocalSettings {
  /// The stored value, or null when the key was never written.
  String? read(String key);

  void write(String key, String value);

  void remove(String key);
}

/// The saved signaling endpoint, falling back to the production one.
///
/// TS: `const savedEndpoint = localStorage.getItem(...) ?? defaultEndpoint` at
/// `src/App.tsx:33`, read once at module load. Reading it through a function
/// means a test does not have to arrange module-load order to change it.
String readEndpoint(LocalSettings settings) {
  final String stored = settings.read(SettingsKeys.rendezvousEndpoint) ?? '';
  return stored.trim().isEmpty ? defaultRendezvousEndpoint : stored.trim();
}

/// Persists the endpoint and the ICE text as one unit, the way
/// `saveEndpoint` at `src/App.tsx:322-331` did, and reports whether it wrote.
///
/// A blank endpoint is refused rather than stored: writing it would leave the
/// app with no address at all, and `readEndpoint` would then substitute the
/// production default, so a half-finished edit would silently talk to the real
/// server. The TypeScript original had no such check and its `ready` memo at
/// `src/App.tsx:136` simply hid the pairing screen instead.
bool saveEndpointAndIce(
  LocalSettings settings, {
  required String endpoint,
  required String iceText,
}) {
  final String cleanEndpoint = endpoint.trim();
  final String cleanIce = iceText.trim();
  if (cleanEndpoint.isEmpty) return false;
  settings.write(SettingsKeys.rendezvousEndpoint, cleanEndpoint);
  settings.write(SettingsKeys.iceServers, cleanIce);
  return true;
}
