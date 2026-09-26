/// What the update client is allowed to believe, and who it asks the time.
///
/// Everything here is injected. The client holds a config, a fetcher, a
/// verifier, an installer, a file store and a clock, and reaches for nothing
/// else - no `HttpClient()`, no `DateTime.now()`, no static path, no global. That
/// is what lets `test/update` run a whole update, including a cancelled download
/// and a throttled check, in microseconds with no network and no real timer.
library;

/// The time source. Injected so a throttle can be tested by moving a value
/// rather than by sleeping.
abstract class UpdateClock {
  /// The current time. Only ever used for the throttle interval and for the
  /// timestamp on a report; never for anything that has to agree with another
  /// machine.
  DateTime now();
}

/// The wall clock.
final class SystemUpdateClock implements UpdateClock {
  const SystemUpdateClock();

  @override
  DateTime now() => DateTime.now();

  @override
  String toString() => 'SystemUpdateClock()';
}

/// The immutable configuration of one updater.
///
/// [publicKeyB64] is the root of the whole trust chain and the only value in
/// this class that is not merely advisory. It is configured, never fetched: an
/// update client that learned the release key from the same place it learns which
/// file to download would be checking a signature against a key the attacker
/// chose.
final class UpdateConfig {
  const UpdateConfig({
    required this.currentVersion,
    required this.feedUrl,
    required this.publicKeyB64,
    this.pinnedManifest,
    this.manifestMaxBytes = defaultManifestMaxBytes,
    this.artifactMaxBytes = defaultArtifactMaxBytes,
    this.minCheckInterval = defaultMinCheckInterval,
  });

  /// This build's version, as `pubspec.yaml` and the root `VERSION` agree on.
  final String currentVersion;

  /// Where the feed lives. TS: `plugins.updater.endpoints[0]` at
  /// `src-tauri/tauri.conf.json:43`, which has answered 404 for the whole life of
  /// the product.
  final Uri feedUrl;

  /// The release public key: the bare 42 byte minisign key, or a whole
  /// `minisign.pub` file in base64 - the second is what
  /// `src-tauri/tauri.conf.json:41` holds. **The value there is a retired
  /// ("legacy", `Ed`) key, and a strict verifier refuses every signature it can
  /// produce.** [UpdateFailureLegacyKey] exists for exactly that, and the
  /// preflight reports it before a user ever sees an update fail.
  final String publicKeyB64;

  /// The manifest this build expects, byte for byte, or null to fetch whatever
  /// the feed serves.
  ///
  /// Defence in depth, not the guarantee. The guarantee is that the downloaded
  /// bytes carry a signature the configured key verifies; a pinned manifest only
  /// adds "and the feed has not been rewritten". Pinning a manifest that is
  /// served from the same host would buy nothing, so a deployment that pins one
  /// has to be serving it from somewhere the attacker does not control.
  final List<int>? pinnedManifest;

  /// Cap for the feed document. A manifest is a few hundred bytes; anything past
  /// this is a captive portal, an error page with a body, or a mistake.
  final int manifestMaxBytes;

  /// Cap for the artefact. Enforced by the client as it counts, not handed to the
  /// transport, so a transport that ignores it still cannot fill a disk.
  final int artifactMaxBytes;

  /// How long a check is good for. The endpoint this release shipped with does
  /// not exist, and a startup that re-asks on every launch would keep asking it.
  final Duration minCheckInterval;

  /// 16 KiB. Bigger than any feed Tauri produces, far smaller than any page a
  /// captive portal would serve.
  static const int defaultManifestMaxBytes = 16 * 1024;

  /// 512 MiB, the same ceiling the file transfer layer uses
  /// (`PeerProtocol.maxFileBytes`, `app/lib/core/protocol/peer_protocol.dart:43`).
  static const int defaultArtifactMaxBytes = 512 * 1024 * 1024;

  static const Duration defaultMinCheckInterval = Duration(hours: 6);

  @override
  String toString() =>
      'UpdateConfig($currentVersion <- $feedUrl, interval: $minCheckInterval)';
}

/// Whether [url] is something a feed is allowed to be served from.
///
/// `https` only, and an absolute URL with a host. A feed read over plaintext, or
/// from a `file:` URL that names a path on this machine, is a feed somebody else
/// chose the contents of.
bool isUsableFeedUrl(Uri url) => url.isScheme('https') && url.host.isNotEmpty;
