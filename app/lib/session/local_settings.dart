/// The local, unencrypted key/value store.
///
/// Nothing secret may ever be written here. The peer record lives in the
/// encrypted [PeerStore] and the private key lives in the OS keyring; this
/// store holds the signaling endpoint, this device's own display name, and the
/// peer's local annotation - and that last one is a note about a person, not
/// data about a secret.
library;

/// The production signaling endpoint.
///
/// It is a default, not a promise: nobody is served by it, and a user who points
/// the app at their own Worker overwrites it (see [saveEndpointAndIce]).
const String defaultRendezvousEndpoint =
    'https://mkvi-signal.12orgcom09.workers.dev';

/// Every key the app reads or writes here, in one place.
///
/// One owner for the key strings is what keeps a read and a write from drifting
/// onto two different literals — a store where `write` and `read` disagree on
/// the spelling loses data silently.
final class SettingsKeys {
  const SettingsKeys._();

  static const String rendezvousEndpoint = 'mkvi.rendezvousEndpoint';
  static const String iceServers = 'mkvi.iceServers';
  static const String selfName = 'mkvi.selfName';
  static const String appearance = 'mkvi.appearance';

  /// The unscoped key an earlier build wrote the peer's annotation under, and
  /// which no current code path writes. Read exactly once, by
  /// [PeerAliasStore.migrateLegacyAlias], and never as a fallback — a fallback
  /// would let an annotation written for one person attach to the next.
  static const String legacyPeerAlias = 'mkvi.peerName';

  /// The scoped prefix.
  static const String peerAliasPrefix = 'mkvi.peerAlias.';
}

/// `mkvi.peerAlias.<publicKey>`.
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
/// Read through a function rather than captured once at load, so a test does not
/// have to arrange module-load order to change it.
String readEndpoint(LocalSettings settings) {
  final String stored = settings.read(SettingsKeys.rendezvousEndpoint) ?? '';
  return stored.trim().isEmpty ? defaultRendezvousEndpoint : stored.trim();
}

/// Persists the endpoint and the ICE text as one unit, and reports whether it
/// wrote.
///
/// A blank endpoint is refused rather than stored: writing it would leave the
/// app with no address at all, and [readEndpoint] would then substitute the
/// production default, so a half-finished edit would silently talk to the real
/// server. Storing the pair as one unit is what stops the endpoint and the ICE
/// text describing two different configurations.
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
