/// The update client: fetch the feed, compare, download, verify, install.
///
/// ## The trust chain
///
/// There are four links, and the order is the security property:
///
/// 1. **The configured release key** ([UpdateConfig.publicKeyB64]) is the root of
///    trust. It is configured, never fetched, and lives in the build. A client
///    that learned the release key from the same place it learns which file to
///    download would be checking a signature against a key the attacker picked.
/// 2. **The feed** (`latest.json`) is *advisory*. It is fetched over https from a
///    configured address, and [UpdateConfig.pinnedManifest] pins it byte for byte
///    when the deployment can serve the pin from somewhere the attacker does not
///    control. The feed contributes two things and nothing else: where to look,
///    and which signature to expect.
/// 3. **The downloaded bytes** are verified in full against the signature from
///    link 2, using the key from link 1, in `mkvi_core::update::verify_artifact`
///    (`crates/mkvi_core/src/update.rs:98`). This is the link that carries the
///    guarantee, and it is why a feed an attacker fully controls still cannot
///    cause an unsigned artefact to be installed: they may point anywhere, but
///    the bytes at that address must carry a signature the *configured* key
///    verifies, and they control neither the key nor the signing side of it.
/// 4. **The installer** is handed the file only after link 3 passed and only
///    after [UpdateFileStore.commit] gave it its final name.
///
/// So the manifest is never trusted for anything a signature would have to
/// cover. It is a pointer, and the pointer's target is checked.
///
/// ## The filesystem rules
///
/// Bytes are written to a staging file whose name ends in `.part`, counted by
/// the client as they arrive, and promoted with a rename only after verification.
/// A partial download therefore never has a runnable name and never reaches the
/// final location, and every failure path - cap tripped, transport broke, abort,
/// bad signature, unreadable signature - leaves the final location empty because
/// the delete is in a `finally` rather than in each branch.
///
/// There is no download cache. Nothing is ever reused because a URL matched; see
/// [UpdateFileStore] for why that lookup would be the hole in this design.
library;

import 'dart:async';

import 'update_config.dart';
import 'update_failure.dart';
import 'update_fetcher.dart';
import 'update_file_store.dart';
import 'update_installer.dart';
import 'update_manifest.dart';
import 'update_messages.dart';
import 'update_preflight.dart';
import 'update_verifier.dart';
import 'update_version.dart';

/// Everything an update attempt can end with, as a value the UI can branch on.
///
/// One flat sealed family rather than one per stage, so a screen that has to
/// render whatever happened has one exhaustive `switch` and one place to get the
/// Turkish line from. Each report names exactly one [UpdateMessage].
sealed class UpdateReport {
  const UpdateReport({required this.at});

  /// When the attempt was decided, from the injected clock.
  final DateTime at;

  /// The catalogue entry this report shows.
  UpdateMessage get messageId;

  /// The Turkish line, verbatim.
  String get message => messageId.text;
}

/// The preflight passed: the key is usable, this build's version parses, and the
/// feed address is one a feed may be served from.
final class UpdatePreflightOk extends UpdateReport {
  const UpdatePreflightOk({required super.at, required this.current});

  final ReleaseVersion current;

  @override
  UpdateMessage get messageId => UpdateMessage.keyAccepted;

  @override
  String toString() => 'UpdatePreflightOk($current)';
}

/// The feed is readable and offers nothing newer.
final class UpdateUpToDate extends UpdateReport {
  const UpdateUpToDate({
    required super.at,
    required this.current,
    required this.offered,
  });

  final ReleaseVersion current;

  /// The version string the feed carried, kept even when it was unreadable, so a
  /// diagnostics screen can show "the feed says X" for an X nobody can parse.
  final String offered;

  @override
  UpdateMessage get messageId => UpdateMessage.alreadyUpToDate;

  @override
  String toString() => 'UpdateUpToDate($current, feed offered $offered)';
}

/// A check was asked for too soon after the last one. [retryIn] is how long is
/// left of [UpdateConfig.minCheckInterval].
final class UpdateCheckDeferred extends UpdateReport {
  const UpdateCheckDeferred({required super.at, required this.retryIn});

  final Duration retryIn;

  @override
  UpdateMessage get messageId => UpdateMessage.checkDeferred;

  @override
  String toString() => 'UpdateCheckDeferred(retry in $retryIn)';
}

/// A newer release is on offer. Nothing has been downloaded yet: this is the
/// report a UI shows before the user agrees to fetch anything.
final class UpdateOffered extends UpdateReport {
  const UpdateOffered({required super.at, required this.offer});

  final UpdateOffer offer;

  @override
  UpdateMessage get messageId => UpdateMessage.offered;

  @override
  String toString() => 'UpdateOffered($offer)';
}

/// The artefact verified, was committed, and the installer was started.
final class UpdateInstalled extends UpdateReport {
  const UpdateInstalled({
    required super.at,
    required this.offer,
    required this.artifactPath,
  });

  final UpdateOffer offer;

  /// Where the verified file was committed. The only path this layer ever hands
  /// out, and only after a signature check passed.
  final String artifactPath;

  @override
  UpdateMessage get messageId => UpdateMessage.installed;

  @override
  String toString() => 'UpdateInstalled($offer -> $artifactPath)';
}

/// The attempt stopped. [failure] says why, and says it in one catalogue entry.
final class UpdateRefused extends UpdateReport {
  const UpdateRefused({required super.at, required this.failure});

  final UpdateFailure failure;

  @override
  UpdateMessage get messageId => failure.messageId;

  @override
  String toString() => 'UpdateRefused($failure at $at)';
}

/// Something the client wants a UI to know about while it works.
///
/// A broadcast stream, so a screen may attach after the first byte and a slow
/// listener cannot stall a download. Carries no path, no URL and no key: these go
/// to a log as readily as to a widget.
sealed class UpdateEvent {
  const UpdateEvent();
}

/// A manifest read has begun.
final class UpdateCheckStarted extends UpdateEvent {
  const UpdateCheckStarted(this.at);

  final DateTime at;

  @override
  String toString() => 'UpdateCheckStarted($at)';
}

/// The feed named a newer release.
final class UpdateOfferFound extends UpdateEvent {
  const UpdateOfferFound(this.offer);

  final UpdateOffer offer;

  @override
  String toString() => 'UpdateOfferFound($offer)';
}

/// Bytes have been written to the staging file. [total] is the server's
/// `Content-Length` when there was one.
final class UpdateDownloadProgress extends UpdateEvent {
  const UpdateDownloadProgress({required this.received, required this.total});

  final int received;
  final int? total;

  @override
  String toString() =>
      'UpdateDownloadProgress($received'
      '${total == null ? '' : '/$total'} bytes)';
}

/// The whole artefact hashed to the signed pre-image. Emitted once, after which
/// the file is committed.
final class UpdateArtifactVerified extends UpdateEvent {
  const UpdateArtifactVerified({
    required this.version,
    required this.byteLength,
  });

  final String version;
  final int byteLength;

  @override
  String toString() => 'UpdateArtifactVerified($version, $byteLength bytes)';
}

/// The installer is being started. The app is expected to exit.
final class UpdateInstallStarted extends UpdateEvent {
  const UpdateInstallStarted(this.version);

  final String version;

  @override
  String toString() => 'UpdateInstallStarted($version)';
}

/// One updater.
///
/// Immutable collaborators, one piece of state: the time of the last check that
/// reached the feed, which exists only to answer [minCheckInterval].
final class UpdateClient {
  UpdateClient({
    required this.config,
    required this.fetcher,
    required this.verifier,
    required this.installer,
    required this.files,
    this.clock = const SystemUpdateClock(),
  });

  final UpdateConfig config;
  final HttpFetcher fetcher;
  final SignatureVerifier verifier;
  final InstallerLauncher installer;
  final UpdateFileStore files;
  final UpdateClock clock;

  final StreamController<UpdateEvent> _events =
      StreamController<UpdateEvent>.broadcast();

  AbortToken? _active;
  DateTime? _lastCheckAt;
  bool _disposed = false;

  /// Progress, as a broadcast stream.
  Stream<UpdateEvent> get events => _events.stream;

  /// When the last check that reached the feed was made.
  DateTime? get lastCheckAt => _lastCheckAt;

  /// Whether a transfer is running that [abort] would stop.
  bool get isTransferring => _active != null;

  /// The local, no-network check. Safe to call on every launch, and the thing a
  /// startup path should call: it is how a legacy key is reported before a user
  /// ever reaches a screen that could say "update failed".
  Future<UpdateReport> preflight() async {
    final DateTime at = clock.now();
    final UpdatePreflight result = await runUpdatePreflight(
      config: config,
      verifier: verifier,
    );
    switch (result) {
      case UpdatePreflightBlocked(:final UpdateFailure failure):
        return UpdateRefused(at: at, failure: failure);
      case UpdatePreflightReady(:final ReleaseVersion current):
        return UpdatePreflightOk(at: at, current: current);
    }
  }

  /// Reads the feed and reports whether it offers anything. Downloads nothing.
  Future<UpdateReport> check() async {
    final DateTime at = clock.now();
    final UpdatePreflight result = await runUpdatePreflight(
      config: config,
      verifier: verifier,
    );
    // The key is refused here, before the feed is contacted: a retired key is a
    // property of this build, so asking the network first would only produce a
    // slower version of the same answer.
    switch (result) {
      case UpdatePreflightBlocked(:final UpdateFailure failure):
        return UpdateRefused(at: at, failure: failure);
      case UpdatePreflightReady(:final ReleaseVersion current):
        return _readManifest(at: at, current: current);
    }
  }

  /// Downloads [offer], verifies the bytes, and installs.
  ///
  /// [offer] cannot be built by a caller - see [UpdateOffer] - so anything
  /// arriving here has already been compared against the running version and had
  /// a signature read out of a feed. What it has *not* done is check a single
  /// byte of the artefact, and that happens here, before anything is committed.
  Future<UpdateReport> install(UpdateOffer offer) async {
    final DateTime at = clock.now();
    // Re-read the key rather than trusting a preflight from another call. It is
    // configuration, the read is local, and "the key was fine ten minutes ago" is
    // not a thing worth relying on when the whole cost of asking is nothing.
    final ReleaseKeyState key = await verifier.classifyKey(config.publicKeyB64);
    switch (key) {
      case ReleaseKeyUnavailable():
        return _refused(at, const UpdateFailureVerificationUnavailable());
      case ReleaseKeyUnreadable():
        return _refused(at, const UpdateFailureKeyUnreadable());
      case ReleaseKeyLegacy():
        return _refused(at, const UpdateFailureLegacyKey());
      case ReleaseKeyPrehashed():
        break;
    }

    final AbortToken abort = AbortToken();
    _active = abort;
    // Everything from here to the rename happens against this one staging file,
    // and every exit from this function other than the commit runs the delete in
    // the `finally` below. That is what makes "a failed verification leaves
    // nothing behind" a property of the shape rather than of each branch.
    final StagedArtifact staging;
    try {
      staging = await files.openStaging(offer);
    } on Object {
      if (identical(_active, abort)) _active = null;
      return _refused(at, const UpdateFailureStorageUnavailable());
    }
    var committed = false;
    var received = 0;
    var complete = false;
    int? announced;
    try {
      try {
        await for (final DownloadEvent event in fetcher.download(
          offer.url,
          maxBytes: config.artifactMaxBytes,
          abort: abort,
        )) {
          switch (event) {
            case DownloadAnnounced(:final int? declaredLength):
              announced = declaredLength;
              // A server that announces more than the cap is refused before a
              // byte is written, not after.
              if (declaredLength != null &&
                  declaredLength > config.artifactMaxBytes) {
                abort.abort();
                return _refused(at, const UpdateFailureArtifactTooLarge());
              }
            case DownloadChunk(:final List<int> bytes):
              received += bytes.length;
              // The cap is counted HERE, not taken from the transport. A
              // transport that ignores `maxBytes` still cannot fill a disk, and
              // the chunk that crosses the line is never written.
              if (received > config.artifactMaxBytes) {
                abort.abort();
                return _refused(at, const UpdateFailureArtifactTooLarge());
              }
              try {
                await files.append(staging, bytes);
              } on Object {
                abort.abort();
                return _refused(at, const UpdateFailureStorageUnavailable());
              }
              _emit(
                UpdateDownloadProgress(received: received, total: announced),
              );
            case DownloadLimitReached():
              abort.abort();
              return _refused(at, const UpdateFailureArtifactTooLarge());
            case DownloadAborted():
              return _refused(at, const UpdateFailureAborted());
            case DownloadFailed():
              return _refused(at, const UpdateFailureDownloadFailed());
            case DownloadComplete(:final int? declaredLength):
              if (declaredLength != null && declaredLength != received) {
                return _refused(at, const UpdateFailureArtifactSizeMismatch());
              }
              _emit(
                UpdateDownloadProgress(
                  received: received,
                  total: declaredLength,
                ),
              );
              complete = true;
          }
        }
      } on Object {
        // A transport that throws is a transport that failed; it is not a reason
        // to escape with a file on disk.
        return _refused(at, const UpdateFailureDownloadFailed());
      }
      // A stream that simply stopped, without saying it finished, is a failed
      // transfer. Treating the end of a stream as success is how a truncated
      // installer gets to be an installer.
      if (!complete) {
        return _refused(at, const UpdateFailureDownloadFailed());
      }
      if (received == 0) {
        return _refused(at, const UpdateFailureArtifactEmpty());
      }

      // Link 3 of the trust chain. The whole file, by path, with the length this
      // client wrote: `verify_artifact` pre-hashes and reads it in one pass, and
      // there is no offset or window in the call for a partial check to hide in.
      final ArtifactVerdict verdict;
      try {
        verdict = await verifier.verifyArtifact(
          artifactPath: staging.path,
          byteLength: received,
          signatureB64: offer.signature,
          publicKeyB64: config.publicKeyB64,
        );
      } on Object {
        // A bridge that throws has not verified anything. Fail closed rather than
        // letting an exception decide.
        return _refused(at, const UpdateFailureVerificationUnavailable());
      }
      switch (verdict) {
        case ArtifactVerificationUnavailable():
          return _refused(at, const UpdateFailureVerificationUnavailable());
        case ArtifactKeyUnreadable():
          return _refused(at, const UpdateFailureKeyUnreadable());
        case ArtifactKeyIsLegacy():
          return _refused(at, const UpdateFailureLegacyKey());
        case ArtifactSignatureUnreadable():
          return _refused(at, const UpdateFailureSignatureUnreadable());
        case ArtifactSignatureRejected():
          return _refused(at, const UpdateFailureSignatureRejected());
        case ArtifactSignatureValid():
          break;
      }
      _emit(
        UpdateArtifactVerified(
          version: offer.version.toString(),
          byteLength: received,
        ),
      );

      // Link 4. The one place in this file an installer is reached, and it is
      // below a verification that returned `ArtifactSignatureValid` and nothing
      // else. `committed` is set before the launch, so even a launcher that
      // throws leaves the verified file in place instead of deleting it.
      final String path;
      try {
        path = await files.commit(staging);
      } on Object {
        return _refused(at, const UpdateFailureStorageUnavailable());
      }
      committed = true;
      _emit(UpdateInstallStarted(offer.version.toString()));
      final InstallOutcome outcome;
      try {
        outcome = await installer.launch(path);
      } on Object {
        return _refused(at, const UpdateFailureInstallFailed());
      }
      return switch (outcome) {
        InstallStarted() => UpdateInstalled(
          at: at,
          offer: offer,
          artifactPath: path,
        ),
        InstallRefused() => _refused(at, const UpdateFailureInstallFailed()),
      };
    } finally {
      if (!committed) await files.discard(staging);
      if (identical(_active, abort)) _active = null;
    }
  }

  /// [check], and then [install] if there is something to install.
  Future<UpdateReport> checkAndInstall() async {
    final UpdateReport report = await check();
    switch (report) {
      case UpdateOffered(:final UpdateOffer offer):
        return install(offer);
      case UpdateUpToDate():
      case UpdateCheckDeferred():
      case UpdatePreflightOk():
      case UpdateInstalled():
      case UpdateRefused():
        return report;
    }
  }

  /// Stops a running transfer. The staging file goes with it, because the
  /// `finally` in [install] runs for every return.
  void abort() => _active?.abort();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    abort();
    await _events.close();
  }

  // -----------------------------------------------------------------------
  // The feed
  // -----------------------------------------------------------------------

  Future<UpdateReport> _readManifest({
    required DateTime at,
    required ReleaseVersion current,
  }) async {
    // A throttled check is only deferred after an answer was actually obtained.
    // A transport that never reached the server does not throttle, so somebody
    // whose train arrived can press the button again straight away.
    final DateTime? last = _lastCheckAt;
    if (last != null) {
      final Duration since = at.difference(last);
      if (since < config.minCheckInterval) {
        return UpdateCheckDeferred(
          at: at,
          retryIn: config.minCheckInterval - since,
        );
      }
    }
    _emit(UpdateCheckStarted(at));
    final AbortToken abort = AbortToken();
    _active = abort;
    final FeedRead read;
    try {
      read = await fetcher.read(
        config.feedUrl,
        maxBytes: config.manifestMaxBytes,
        abort: abort,
      );
    } on Object {
      return _refused(at, const UpdateFailureFeedUnreachable());
    } finally {
      if (identical(_active, abort)) _active = null;
    }
    switch (read) {
      case FeedReadTooLarge():
        _lastCheckAt = at;
        return _refused(at, const UpdateFailureFeedTooLarge());
      case FeedReadFailed():
        // Not throttled: no answer was obtained, so there is nothing to remember.
        return _refused(at, const UpdateFailureFeedUnreachable());
      case FeedReadOk(:final List<int> body, :final int? declaredLength):
        // Counted again on this side. A transport that hands back more than the
        // cap was given is refused rather than believed.
        if (body.length > config.manifestMaxBytes) {
          _lastCheckAt = at;
          return _refused(at, const UpdateFailureFeedTooLarge());
        }
        // A body shorter than its own `Content-Length` arrived. Truncated, so
        // unreadable - never parsed as a smaller manifest.
        if (declaredLength != null && declaredLength > body.length) {
          return _refused(at, const UpdateFailureFeedUnreadable());
        }
        final List<int>? pin = config.pinnedManifest;
        if (pin != null && !_sameBytes(pin, body)) {
          _lastCheckAt = at;
          return _refused(at, const UpdateFailureFeedPinMismatch());
        }
        _lastCheckAt = at;
        final UpdateManifest manifest = parseUpdateManifest(body, current);
        switch (manifest) {
          case ManifestUnusable(:final UpdateFailure failure):
            return _refused(at, failure);
          case ManifestNotNewer(:final String offered):
            return UpdateUpToDate(at: at, current: current, offered: offered);
          case ManifestOffersRelease(:final UpdateOffer offer):
            _emit(UpdateOfferFound(offer));
            return UpdateOffered(at: at, offer: offer);
        }
    }
  }

  // -----------------------------------------------------------------------
  // Plumbing
  // -----------------------------------------------------------------------

  UpdateRefused _refused(DateTime at, UpdateFailure failure) =>
      UpdateRefused(at: at, failure: failure);

  void _emit(UpdateEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

/// Whether two byte strings are equal, length first.
///
/// Not a constant-time comparison and deliberately not pretending to be: there
/// is no oracle here for an attacker to measure, since the manifest is fetched
/// fresh each time and a mismatch produces the same notice either way. The
/// length check first is a cheap short-circuit, nothing more.
bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
