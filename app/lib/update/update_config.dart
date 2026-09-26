/// What the update client is allowed to believe, and who it asks the time.
///
/// Everything here is injected. The client holds a config, a fetcher, a
/// verifier, an installer, a file store and a clock, and reaches for nothing
/// else - no `HttpClient()`, no `DateTime.now()`, no static path, no global.
/// That is what lets `test/update` run a whole update, including a cancelled
/// download and a throttled check, in microseconds with no network and no real
/// timer.
///
/// ## The two values that come out of the build
///
/// [buildVersion] and [buildReleaseKeyB64] are `String.fromEnvironment`, so the
/// compiler resolves them while it compiles and the answers end up inside the
/// binary. Nothing afterwards can move them: not the feed, not a file on disk,
/// not an environment variable the running process reads. That is the property
/// worth paying for. The release key is not a secret - it is public material by
/// design - but it is the **root** of the trust chain, and a root that can be
/// re-pointed after the build is not a root.
///
/// A release is built with both, and the release workflow is the only place
/// that writes them:
///
/// ```text
/// flutter build windows \
///   --dart-define=MKVI_VERSION=0.2.0 \
///   --dart-define=MKVI_UPDATE_KEY_B64=<base64 of the minisign.pub file>
/// ```
///
/// Both are **empty when the flag is left out**, and that is a decision rather
/// than an oversight. There is no default here, because a default would be worse
/// than nothing in both directions: a default version would make a shipped
/// release believe it is older than it is and offer a downgrade, and a
/// placeholder key would look configured to [UpdateConfig.isConfigured] while
/// verifying nothing at all. Empty is a state the preflight can name in Turkish,
/// so a build that forgot a flag says so on a screen instead of shipping quiet.
///
/// ## Why the feed is this repository's releases
///
/// [releaseFeedUrlText] is the official Tauri updater endpoint: the `latest`
/// release of this repository, and the `latest.json` asset attached to it. The
/// 0.1.x line instead pointed at a **separate, private feed repository** that no
/// unauthenticated client could read, which is why updating had never once
/// worked. That shape cannot work by construction - a git host will not serve a
/// private repository to a client that has not authenticated - so the feed had
/// to move into the repository the app is shipped from, where the assets are
/// public downloads anyway. Neither that retired repository nor the host that
/// served it is named anywhere in this layer any more, and
/// `test/update/update_config_test.dart` holds that line: both are swept for
/// across `lib/update`.
library;

/// The feed: the `latest.json` asset of this repository's newest release.
///
/// A constant in the build rather than a value a caller passes, and the address
/// itself is not overridable through [UpdateConfig.production]. A release whose
/// feed address can be chosen at the composition root is a release that can be
/// pointed at a feed somebody else wrote; the feed is advisory, so that is
/// survivable, but it is a hole nobody needs.
const String releaseFeedUrlText =
    'https://github.com/ancapenguin/mkvi/releases/latest/download/latest.json';

/// [releaseFeedUrlText] as a [Uri], for the config and for the tests that pin
/// it.
final Uri releaseFeedUrl = Uri.parse(releaseFeedUrlText);

/// This build's version, compiled in.
///
/// Pass the root `VERSION` file's contents, or the `version:` line from
/// `pubspec.yaml` - `0.2.0` and `0.2.0+1` both read as `0.2.0`, because
/// [ReleaseVersion] drops build metadata before it compares anything.
///
/// Empty when `--dart-define=MKVI_VERSION` was not passed.
const String buildVersion = String.fromEnvironment('MKVI_VERSION');

/// The release public key, compiled in. See [UpdateConfig.publicKeyB64] for
/// which two shapes are accepted.
///
/// Empty when `--dart-define=MKVI_UPDATE_KEY_B64` was not passed. An empty key
/// is not a key: [UpdateConfig.isConfigured] is false and the preflight says so
/// in Turkish before a single byte is fetched.
const String buildReleaseKeyB64 = String.fromEnvironment(
  'MKVI_UPDATE_KEY_B64',
);

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
/// this class that is not merely advisory. It is compiled in, never fetched: an
/// update client that learned the release key from the same place it learns
/// which file to download would be checking a signature against a key the
/// attacker chose.
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

  /// The configuration a shipped build uses, with nothing left to choose.
  ///
  /// The two build values and the feed address come from the compile-time
  /// constants, not from parameters, so a caller cannot move the trust root or
  /// the feed. The sizes and the throttle stay overridable because those are
  /// resource limits, not trust.
  factory UpdateConfig.production({
    List<int>? pinnedManifest,
    int manifestMaxBytes = defaultManifestMaxBytes,
    int artifactMaxBytes = defaultArtifactMaxBytes,
    Duration minCheckInterval = defaultMinCheckInterval,
  }) => UpdateConfig(
    currentVersion: buildVersion,
    feedUrl: releaseFeedUrl,
    publicKeyB64: buildReleaseKeyB64,
    pinnedManifest: pinnedManifest,
    manifestMaxBytes: manifestMaxBytes,
    artifactMaxBytes: artifactMaxBytes,
    minCheckInterval: minCheckInterval,
  );

  /// This build's version, as the root `VERSION` file and `pubspec.yaml` agree
  /// on. [buildVersion] in a shipped build; a literal in a test.
  final String currentVersion;

  /// Where the feed lives. [releaseFeedUrl] in every shipped build.
  final Uri feedUrl;

  /// The release public key: the bare 42 byte minisign key, or a whole
  /// `minisign.pub` file in base64. Both name the same 32 byte Ed25519 key, so
  /// neither is the weaker check, and the Rust core accepts both.
  ///
  /// **Only the prehashed (`ED`) algorithm can ever verify anything.** The
  /// retired (`Ed`) form is a key whose every signature a strict verifier
  /// refuses, which is `UpdateFailureLegacyKey` and not a tampering report. Any
  /// key shipped from here on has to be minted with `minisign -W`; the key the
  /// 0.1.x line was built with was not, and that mistake is the reason the
  /// legacy-key case exists at all.
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

  /// How long a check is good for. A startup that re-asks on every launch would
  /// ask a public endpoint on every launch, which is both rude and slow.
  final Duration minCheckInterval;

  /// 16 KiB. Bigger than any feed a release publishes, far smaller than any page
  /// a captive portal would serve.
  static const int defaultManifestMaxBytes = 16 * 1024;

  /// 512 MiB, the same ceiling the file transfer layer uses
  /// (`PeerProtocol.maxFileBytes`, `app/lib/core/protocol/peer_protocol.dart:43`).
  static const int defaultArtifactMaxBytes = 512 * 1024 * 1024;

  static const Duration defaultMinCheckInterval = Duration(hours: 6);

  /// Whether a release key arrived with this build.
  ///
  /// False means the binary was compiled without
  /// `--dart-define=MKVI_UPDATE_KEY_B64`. That is a build mistake, not a network
  /// one, and no user can fix it, which is why the preflight names it as itself
  /// instead of letting a later "the file may have been modified" do the talking.
  bool get hasReleaseKey => publicKeyB64.trim().isNotEmpty;

  /// Whether a version arrived with this build. Same story: `pubspec.yaml` is
  /// read by the toolchain at build time, never by the running app, so the value
  /// has to be handed to the compiler as well.
  bool get hasVersion => currentVersion.trim().isNotEmpty;

  /// Whether this build was given everything an update needs to even be
  /// attempted.
  ///
  /// Necessary and not sufficient: the key still has to turn out to be
  /// prehashed, which is the next question the preflight asks. This only answers
  /// "was a build flag left out".
  bool get isConfigured => hasReleaseKey && hasVersion;

  @override
  String toString() =>
      'UpdateConfig($currentVersion <- $feedUrl, interval: $minCheckInterval'
      '${isConfigured ? '' : ', NOT CONFIGURED'})';
}

/// Whether [url] is something a feed is allowed to be served from.
///
/// `https` only, and an absolute URL with a host. A feed read over plaintext, or
/// from a `file:` URL that names a path on this machine, is a feed somebody else
/// chose the contents of.
bool isUsableFeedUrl(Uri url) => url.isScheme('https') && url.host.isNotEmpty;
