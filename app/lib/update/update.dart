/// MKVI self-update: the feed, the trust chain, and the install handoff.
///
/// One import for the composition root. Comments are English; every string a user
/// can see is Turkish and lives in [UpdateMessage].
///
/// ## What the retired 0.1.x line shipped
///
/// The 0.1.x Tauri line was retired and deleted on 2026-09-26. Two of its
/// defects are worth carrying forward, because the code here is shaped by both
/// and would otherwise look unmotivated:
///
/// * **The feed could not be read, by anybody.** It lived in a separate private
///   repository, and a private repository is not served to an unauthenticated
///   client. Every check therefore failed at the first step, before any
///   signature was looked at. Confirmed live on 2026-09-26. This is why the
///   feed is [releaseFeedUrlText] - this repository's own releases, whose assets
///   are public downloads - and why no layer here names a second repository
///   again.
/// * **The release key was in minisign's retired `Ed` form, not the prehashed
///   `ED`.** A strict verifier refuses every signature such a key can produce,
///   and this core is deliberately strict: `allow_legacy` is hard-coded `false`
///   at `crates/mkvi_core/src/update.rs:116`.
///
/// A correction that was measured rather than assumed, and that matters for
/// reading the rest of this layer: the old updater did **not** refuse the legacy
/// key. `tauri-plugin-updater` 2.10.1 passes `allow_legacy = true` at
/// `src/updater.rs:1461` and `minisign-verify` 0.3.0 accepts both algorithm tags
/// (`lib.rs:296-299`), so the dead feed stopped 0.1.x and the dead feed alone.
/// The legacy key is a defect pointing the other way: it blocks **0.2.0 and
/// later**, whose core is strict on purpose. That is the direction this layer
/// protects.
///
/// [UpdateClient.preflight] turns both into a sentence on a startup screen, in
/// Turkish, with the fix in it. The 0.1.x history itself is recorded in the
/// project's legacy notes rather than in this file.
///
/// ## What this library does
///
/// * [UpdateClient] runs the flow with every side effect injected - a
///   [HttpFetcher], a [SignatureVerifier], an [InstallerLauncher], an
///   [UpdateFileStore] and an [UpdateClock] - so the whole thing is testable with
///   no network, no disk and no real timer.
/// * [UpdateConfig] carries the two values that come out of the build - the
///   version and the release key - and [releaseFeedUrlText] is the one address
///   any shipped build reads.
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
/// everything rather than pretending. `update_verifier.dart` writes down the
/// exact class and the exact two Rust calls that replace it.
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
