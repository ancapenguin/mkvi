/// Why an update attempt stopped, as a value the UI can branch on.
///
/// Sealed so a `switch` over it is exhaustive: a new way for an update to fail
/// becomes a compile error in every consumer instead of a silently unhandled
/// notice. Every case names exactly one [UpdateMessage], so no failure can end
/// up with a string that was written next to it and never checked.
///
/// The distinctions here are not cosmetic. [UpdateFailureLegacyKey] is separated
/// from [UpdateFailureSignatureRejected] because the release key configured in
/// `src-tauri/tauri.conf.json:41` is a retired ("legacy") minisign key - its
/// algorithm field decodes to `Ed`, not `ED` - so a strict verifier refuses
/// every signature that key can ever produce. Reporting that as a possible
/// tampering is a lie that has now been shown to a user on every attempted
/// update since 0.1.4. `crates/mkvi_core/src/update.rs:38-48` makes the same
/// split on the Rust side, for the same reason.
library;

import 'update_messages.dart';

/// A refused update. Carries no message of its own: [messageId] is the only
/// source of the Turkish line, so a failure and its text cannot drift apart.
sealed class UpdateFailure {
  const UpdateFailure();

  /// The catalogue entry this failure shows.
  UpdateMessage get messageId;

  /// The Turkish line, verbatim.
  String get message => messageId.text;
}

/// The feed could not be fetched: DNS, TLS, a refused connection, a 404.
///
/// TS: the reason updating has never worked. `endpoints` in
/// `src-tauri/tauri.conf.json:43` points at
/// `raw.githubusercontent.com/ancapenguin/mkvi-updates/main/latest.json`, and
/// that repository does not exist, so every check has always failed at the
/// first step.
final class UpdateFailureFeedUnreachable extends UpdateFailure {
  const UpdateFailureFeedUnreachable();

  @override
  UpdateMessage get messageId => UpdateMessage.feedUnreachable;

  @override
  String toString() => 'UpdateFailureFeedUnreachable()';
}

/// The feed answered, but not with a feed: invalid JSON, or a body cut short
/// against its own `Content-Length`.
final class UpdateFailureFeedUnreadable extends UpdateFailure {
  const UpdateFailureFeedUnreadable();

  @override
  UpdateMessage get messageId => UpdateMessage.feedUnreadable;

  @override
  String toString() => 'UpdateFailureFeedUnreadable()';
}

/// The feed body is past `UpdateConfig.manifestMaxBytes`.
final class UpdateFailureFeedTooLarge extends UpdateFailure {
  const UpdateFailureFeedTooLarge();

  @override
  UpdateMessage get messageId => UpdateMessage.feedTooLarge;

  @override
  String toString() => 'UpdateFailureFeedTooLarge()';
}

/// The feed does not match the pinned copy in [UpdateConfig.pinnedManifest].
///
/// Not the guarantee - the artefact signature is - but worth naming: a feed that
/// changed when it was not supposed to has either been rewritten or moved, and
/// both are things a user should hear about before anything is downloaded.
final class UpdateFailureFeedPinMismatch extends UpdateFailure {
  const UpdateFailureFeedPinMismatch();

  @override
  UpdateMessage get messageId => UpdateMessage.feedPinMismatch;

  @override
  String toString() => 'UpdateFailureFeedPinMismatch()';
}

/// A newer release was advertised with no `windows-x86_64` entry. Mirrors
/// `UpdateError::UnsupportedPlatform` at
/// `crates/mkvi_core/src/update.rs:29-30`.
final class UpdateFailureNoArtifactForPlatform extends UpdateFailure {
  const UpdateFailureNoArtifactForPlatform();

  @override
  UpdateMessage get messageId => UpdateMessage.noArtifactForPlatform;

  @override
  String toString() => 'UpdateFailureNoArtifactForPlatform()';
}

/// The configured release key is minisign's retired "legacy" form, so nothing
/// it signs can be verified.
///
/// Refused at the preflight, before a single byte is fetched, because this is a
/// property of the build and not of the network: no retry and no mirror can
/// change it, and the fix is to mint a prehashed key.
final class UpdateFailureLegacyKey extends UpdateFailure {
  const UpdateFailureLegacyKey();

  @override
  UpdateMessage get messageId => UpdateMessage.legacyKey;

  @override
  String toString() => 'UpdateFailureLegacyKey()';
}

/// The configured release key cannot be read at all.
final class UpdateFailureKeyUnreadable extends UpdateFailure {
  const UpdateFailureKeyUnreadable();

  @override
  UpdateMessage get messageId => UpdateMessage.keyUnreadable;

  @override
  String toString() => 'UpdateFailureKeyUnreadable()';
}

/// This build's own version string could not be parsed, so an offered release
/// cannot be compared against it.
final class UpdateFailureCurrentVersionUnreadable extends UpdateFailure {
  const UpdateFailureCurrentVersionUnreadable();

  @override
  UpdateMessage get messageId => UpdateMessage.currentVersionUnreadable;

  @override
  String toString() => 'UpdateFailureCurrentVersionUnreadable()';
}

/// The configured feed address is not an absolute http(s) URL.
final class UpdateFailureFeedUrlUnusable extends UpdateFailure {
  const UpdateFailureFeedUrlUnusable();

  @override
  UpdateMessage get messageId => UpdateMessage.feedUrlUnusable;

  @override
  String toString() => 'UpdateFailureFeedUrlUnusable()';
}

/// The verification bridge is absent, so no signature can be checked.
///
/// Fails closed, and says so. A verifier that returned "fine" when it had not
/// run would turn a missing bridge into a silent acceptance of anything the feed
/// points at.
final class UpdateFailureVerificationUnavailable extends UpdateFailure {
  const UpdateFailureVerificationUnavailable();

  @override
  UpdateMessage get messageId => UpdateMessage.verificationUnavailable;

  @override
  String toString() => 'UpdateFailureVerificationUnavailable()';
}

/// The transfer was stopped by [UpdateClient.abort], and whatever had been
/// written was removed.
final class UpdateFailureAborted extends UpdateFailure {
  const UpdateFailureAborted();

  @override
  UpdateMessage get messageId => UpdateMessage.aborted;

  @override
  String toString() => 'UpdateFailureAborted()';
}

/// The transport failed mid-stream. Never leaves a partial file behind.
final class UpdateFailureDownloadFailed extends UpdateFailure {
  const UpdateFailureDownloadFailed();

  @override
  UpdateMessage get messageId => UpdateMessage.downloadFailed;

  @override
  String toString() => 'UpdateFailureDownloadFailed()';
}

/// The download directory could not be written to: out of space, no permission,
/// or an antivirus holding the folder.
///
/// Its own case because the remedy is a different one. "Try again" fixes a
/// dropped connection and does nothing here.
final class UpdateFailureStorageUnavailable extends UpdateFailure {
  const UpdateFailureStorageUnavailable();

  @override
  UpdateMessage get messageId => UpdateMessage.storageUnavailable;

  @override
  String toString() => 'UpdateFailureStorageUnavailable()';
}

/// The transfer completed with nothing in it.
final class UpdateFailureArtifactEmpty extends UpdateFailure {
  const UpdateFailureArtifactEmpty();

  @override
  UpdateMessage get messageId => UpdateMessage.artifactEmpty;

  @override
  String toString() => 'UpdateFailureArtifactEmpty()';
}

/// The stream went past `UpdateConfig.artifactMaxBytes`. The client aborts the
/// transfer and deletes the partial file itself rather than trusting the
/// transport to have stopped.
final class UpdateFailureArtifactTooLarge extends UpdateFailure {
  const UpdateFailureArtifactTooLarge();

  @override
  UpdateMessage get messageId => UpdateMessage.artifactTooLarge;

  @override
  String toString() => 'UpdateFailureArtifactTooLarge()';
}

/// `Content-Length` and the number of bytes that arrived disagree.
final class UpdateFailureArtifactSizeMismatch extends UpdateFailure {
  const UpdateFailureArtifactSizeMismatch();

  @override
  UpdateMessage get messageId => UpdateMessage.artifactSizeMismatch;

  @override
  String toString() => 'UpdateFailureArtifactSizeMismatch()';
}

/// The whole artefact was hashed and did not match the release signature.
///
/// The only failure that means "the file may have been modified", and only
/// reachable once the key has already cleared the preflight.
final class UpdateFailureSignatureRejected extends UpdateFailure {
  const UpdateFailureSignatureRejected();

  @override
  UpdateMessage get messageId => UpdateMessage.signatureRejected;

  @override
  String toString() => 'UpdateFailureSignatureRejected()';
}

/// The signature field is not a readable minisign block.
final class UpdateFailureSignatureUnreadable extends UpdateFailure {
  const UpdateFailureSignatureUnreadable();

  @override
  UpdateMessage get messageId => UpdateMessage.signatureUnreadable;

  @override
  String toString() => 'UpdateFailureSignatureUnreadable()';
}

/// The bytes verified and were committed, and the platform installer refused to
/// start. The file is good; the handoff failed.
final class UpdateFailureInstallFailed extends UpdateFailure {
  const UpdateFailureInstallFailed();

  @override
  UpdateMessage get messageId => UpdateMessage.installFailed;

  @override
  String toString() => 'UpdateFailureInstallFailed()';
}
