/// The check a UI runs at startup, before anything is offered and before
/// anything is downloaded.
///
/// One local question: is the configured release key a key a strict verifier can
/// use? No network, no clock, no file, no timer - it is cheap enough to run on
/// every launch, and that is the point.
///
/// It exists because of a defect that never surfaced, and the retired 0.1.x line
/// is the reason it is written this way.
///
/// The key that line shipped decodes to minisign's retired `Ed` algorithm rather
/// than the prehashed `ED`, so `verify_artifact`
/// (`crates/mkvi_core/src/update.rs:98`) refuses **every** signature that key can
/// ever produce - and the core hard-codes `allow_legacy = false`
/// (`update.rs:116`), so that strictness is a decision, not an oversight.
///
/// Correction, 2026-09-26: this file used to claim the old Tauri updater made the
/// same refusal and told the user their download may have been modified. It did
/// not - `tauri-plugin-updater` 2.10.1 passes `allow_legacy = true`
/// (`src/updater.rs:1461`) - so 0.1.x was stopped by its dead private feed, not
/// by the key. What this preflight protects is 0.2.0 and later, where the strict
/// core would otherwise reject every artefact an `Ed` key signs.
///
/// A preflight turns that into a sentence with a fix in it, on a screen the user
/// reaches before they ever press "check for updates". It also has a second job
/// now that the two build-time values are compile-time constants: a build that
/// was compiled without `--dart-define=MKVI_VERSION` or
/// `--dart-define=MKVI_UPDATE_KEY_B64` arrives here with a value missing, and
/// the honest answer is a sentence that names the build flag rather than a
/// signature error the user cannot act on.
library;

import 'update_config.dart';
import 'update_failure.dart';
import 'update_manifest.dart';
import 'update_messages.dart';
import 'update_verifier.dart';
import 'update_version.dart';

/// The preflight's answer.
///
/// Sealed for the same reason [UpdateFailure] is: two ways to answer, and a
/// `switch` that cannot be silently incomplete.
sealed class UpdatePreflight {
  const UpdatePreflight();

  /// The Turkish line for this answer. Never empty.
  String get message;

  /// The catalogue entry, so the wording lives in one place.
  UpdateMessage get messageId;

  /// Whether an update can be attempted at all. `false` means every attempt will
  /// fail the same way, and retrying will not help.
  bool get canUpdate;
}

/// The key is prehashed and readable, and this build's own version parses, and
/// the feed address is usable. Updating can be attempted.
final class UpdatePreflightReady extends UpdatePreflight {
  const UpdatePreflightReady(this.current);

  /// This build's parsed version, carried so a caller does not parse it again and
  /// get a different answer.
  final ReleaseVersion current;

  @override
  UpdateMessage get messageId => UpdateMessage.keyAccepted;

  @override
  String get message => messageId.text;

  @override
  bool get canUpdate => true;

  @override
  String toString() => 'UpdatePreflightReady($current)';
}

/// Something about this build makes every update attempt impossible.
///
/// [failure] says which thing, and it is a [UpdateFailure] rather than a string
/// so a diagnostics screen can branch on it without matching text.
final class UpdatePreflightBlocked extends UpdatePreflight {
  const UpdatePreflightBlocked(this.failure);

  final UpdateFailure failure;

  @override
  UpdateMessage get messageId => failure.messageId;

  @override
  String get message => failure.message;

  @override
  bool get canUpdate => false;

  @override
  String toString() => 'UpdatePreflightBlocked($failure)';
}

/// Answers the preflight. Cheap, local, and safe to call on every launch.
///
/// Checked in the order the cheapest and most decisive things come first. Whether
/// a key was compiled in at all, and what shape it is, are both properties of the
/// build rather than of the network: if either is wrong then no amount of
/// patience, retry or mirroring will help, so both are settled before a socket is
/// opened. The version and the feed address are checked after, and a bad value in
/// any of the four is its own named answer.
Future<UpdatePreflight> runUpdatePreflight({
  required UpdateConfig config,
  required SignatureVerifier verifier,
}) async {
  // First, and without asking anybody: is there a key at all? An empty value is
  // not a key that fails to verify, it is a build that was compiled without the
  // flag. Answering that with `UpdateFailureKeyUnreadable` would be a guess, and
  // answering it by calling the verifier would hand the question to a bridge
  // that is not there yet - which reports "verification unavailable" and sends
  // the reader after the wrong problem entirely.
  if (!config.hasReleaseKey) {
    return const UpdatePreflightBlocked(UpdateFailureReleaseKeyMissing());
  }
  final ReleaseKeyState key = await verifier.classifyKey(config.publicKeyB64);
  switch (key) {
    case ReleaseKeyUnavailable():
      return const UpdatePreflightBlocked(
        UpdateFailureVerificationUnavailable(),
      );
    case ReleaseKeyUnreadable():
      return const UpdatePreflightBlocked(UpdateFailureKeyUnreadable());
    case ReleaseKeyLegacy():
      // The whole reason this function exists. Reported here, before the feed is
      // even contacted, because it is a property of the build and not of the
      // network.
      return const UpdatePreflightBlocked(UpdateFailureLegacyKey());
    case ReleaseKeyPrehashed():
      break;
  }
  final ReleaseVersion? current = ReleaseVersion.tryParse(
    config.currentVersion,
  );
  if (current == null) {
    return const UpdatePreflightBlocked(
      UpdateFailureCurrentVersionUnreadable(),
    );
  }
  if (!isUsableFeedUrl(config.feedUrl)) {
    return const UpdatePreflightBlocked(UpdateFailureFeedUrlUnusable());
  }
  return UpdatePreflightReady(current);
}

/// Exposed for the composition root: the target the feed has to name.
///
/// Re-exported from the manifest so a caller wiring the client writes one import
/// and gets the constant that has to match the Rust core's.
const String defaultUpdateTarget = windowsUpdateTarget;
