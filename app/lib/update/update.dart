/// MKVI self-update: the feed, the trust chain, and the install handoff.
///
/// One import for the composition root. Comments are English; every string a user
/// can see is Turkish and lives in [UpdateMessage].
///
/// ## What was broken
///
/// **Updating has never worked**, for two separate reasons, and both of them are
/// addressed here rather than papered over:
///
/// * `src-tauri/tauri.conf.json:43` points the updater at
///   `raw.githubusercontent.com/ancapenguin/mkvi-updates/main/latest.json`, and
///   that repository answers 404. Every check has therefore always failed at the
///   first step, before any signature was ever looked at.
/// * The key at `src-tauri/tauri.conf.json:41` decodes to minisign's retired
///   `Ed` algorithm rather than the prehashed `ED`, so
///   `mkvi_core::update::verify_artifact`
///   (`crates/mkvi_core/src/update.rs:98`) refuses **every** signature that key
///   can ever produce. The Tauri updater reported that refusal the way it reports
///   any other failed verification - as a file that may have been modified - so
///   the honest answer to "why does updating not work" was an accusation against
///   the user, forever.
///
/// The first is a deployment problem: the feed has to exist. The second is a
/// build problem: a prehashed release key has to be generated and configured
/// before the first Flutter release. [UpdateClient.preflight] reports the second
/// on a startup screen, in Turkish, with the fix in the sentence - before a user
/// can reach anything that says "update failed".
///
/// ## What this library does
///
/// * [UpdateClient] runs the flow with every side effect injected - a
///   [HttpFetcher], a [SignatureVerifier], an [InstallerLauncher], an
///   [UpdateFileStore] and an [UpdateClock] - so the whole thing is testable with
///   no network, no disk and no real timer.
/// * [runUpdatePreflight] is the startup check: local, cheap, and decisive.
/// * [ReleaseVersion] is the semver subset, ported to agree with the Rust core
///   case for case, and it refuses to guess.
/// * [parseUpdateManifest] reads the feed, and [UpdateOffer] - whose constructor
///   is private - is the only way to name something to install.
/// * [UpdateFailure] and [UpdateMessage] are the exhaustive, typed, Turkish
///   account of every way an update can end.
///
/// The verification itself is **not** implemented here, on purpose. It lives in
/// `mkvi_core::update` and the bridge to it does not exist yet;
/// [UnavailableSignatureVerifier] is the shipped answer, and it refuses
/// everything rather than pretending.
library;

export 'update_client.dart';
export 'update_config.dart';
export 'update_failure.dart';
export 'update_fetcher.dart';
export 'update_file_store.dart';
export 'update_installer.dart';
export 'update_manifest.dart';
export 'update_messages.dart';
export 'update_preflight.dart';
export 'update_verifier.dart';
export 'update_version.dart';
