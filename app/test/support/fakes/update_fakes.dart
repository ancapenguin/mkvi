/// Fakes for every seam `lib/update` exposes: the network, the verifier, the
/// installer, the file store and the clock.
///
/// The signature fake is the one worth reading twice. It behaves like
/// `mkvi_core::update::verify_artifact` rather than like a boolean: it goes to
/// the file store for the bytes that were actually written, hashes **all** of
/// them and compares the result with the digest of the artefact the release key
/// signed. A test that flips one byte at any offset therefore fails the way the
/// real bridge fails, and [ScriptedSignatureVerifier.verified] is what proves
/// the client handed over the whole file rather than a window of it.
///
/// Two refusals are load-bearing:
///
/// * A `read` with no answer arranged **raises**. Answering
///   `FeedReadFailed('no answer scripted')` is worse than useless: the client
///   turns that into `UpdateFailureDownloadFailed`, which is exactly what a dead
///   server produces, so a test could never tell "the feed is unreachable" from
///   "the fake had nothing to say".
/// * An `append` to a staging file that was never opened **raises**. The old
///   fake appended into a map entry that did not exist, which in Dart silently
///   discards the chunk - so a test asserting "the whole artefact was written"
///   passed against a fake that had written nothing.
library;

import 'dart:convert';

import 'package:mkvi/update/update.dart';

import 'script_log.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The version the tests pretend to run, and the version the fake feed offers by
/// default. The real numbers: `VERSION` and `pubspec.yaml` are both 0.2.0.
const String fakeCurrentVersion = '0.2.0';

/// The offered version: one minor bump, so the comparison is unambiguous.
const String fakeOfferedVersion = '0.2.1';

/// A 42 byte minisign public key in the prehashed form: the algorithm bytes are
/// `0x45 0x44` - "ED" - and the rest is a key id and an Ed25519 key.
///
/// Shape only. Nothing in Dart decodes it, because nothing in Dart is allowed
/// to: verification is the Rust core's job and stays there.
const String fakePrehashedKey =
    'RURaWlpaWlpaWhAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v';

/// The same 42 bytes with minisign's retired algorithm tag, `0x45 0x64` - "Ed".
///
/// This is the shape the key in `src-tauri/tauri.conf.json:41` actually holds,
/// and a strict verifier refuses every signature such a key can produce. That
/// is why `UpdateFailureLegacyKey` exists and why the preflight asks at startup.
const String fakeLegacyKey =
    'RWRaWlpaWlpaWhAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v';

/// The exact value from `src-tauri/tauri.conf.json:41`, base64 and carried here
/// so the legacy-key scenario is about the real configuration rather than about a
/// fixture that merely looks like it.
const String fakeTauriConfiguredKey =
    'dW50cnVzdGVkIGNvbW1lbnQ6IG1pbmlzaWduIHB1YmxpYyBrZXk6IDg5Q0E3QjRBMEFFQTU2'
    'NDEKUldSQlZ1b0tTbnZLaWNOZ3BwRUF3RWsvVGV0V1RiMGZsR2ltak9LcGVFYkRLY2dNdVdR'
    'akJzWGYK';

/// A signature in the wire shape a feed stores: base64 of a whole `.sig` file.
/// Never decoded here either.
const String fakeArtifactSignature = 'c2lnbmF0dXJlLWJsb2NrLWJ5dGVz';

/// The endpoint the Tauri build shipped with. It answers 404, and it is named
/// here so the tests that use it say so out loud.
const String fakeDeadFeedUrl =
    'https://raw.githubusercontent.com/ancapenguin/mkvi-updates/main/latest.json';

/// A feed URL a working deployment would use.
const String fakeLiveFeedUrl = 'https://updates.example.invalid/mkvi/latest.json';

/// The artefact the release key signed. Long enough to cross more than one chunk
/// boundary, so an implementation that checks only the first chunk cannot pass.
List<int> fakeSignedArtifact({int length = 4096}) =>
    List<int>.generate(length, (int index) => (index * 7 + 11) & 0xff);

/// A `latest.json` body offering [version] for the Windows target.
List<int> fakeFeedJson({
  String version = fakeOfferedVersion,
  String notes = 'Düzeltmeler',
  String url = 'https://releases.example.invalid/mkvi-setup.exe',
  String signature = fakeArtifactSignature,
  String target = windowsUpdateTarget,
  bool includePlatforms = true,
}) {
  final String platforms = includePlatforms
      ? '"$target":{"url":"$url","signature":"$signature"}'
      : '"darwin-x86_64":{"url":"u","signature":"s"}';
  return utf8.encode(
    '{"version":"$version","notes":"$notes",'
    '"pub_date":"2026-01-05T10:00:00Z","platforms":{$platforms}}',
  );
}

/// Splits [bytes] into [size] byte pieces.
List<List<int>> fakeChunksOf(List<int> bytes, int size) {
  final List<List<int>> out = <List<int>>[];
  for (int start = 0; start < bytes.length; start += size) {
    final int end = start + size;
    out.add(bytes.sublist(start, end > bytes.length ? bytes.length : end));
  }
  return out;
}

/// An artefact stream of [bytes], announced honestly.
List<DownloadEvent> fakeArtifactEvents(
  List<int> bytes, {
  int chunkSize = 512,
  int? declaredLength,
}) {
  final int declared = declaredLength ?? bytes.length;
  return <DownloadEvent>[
    DownloadAnnounced(declared),
    ...fakeChunksOf(bytes, chunkSize).map(DownloadChunk.new),
    DownloadComplete(declared),
  ];
}

/// FNV-1a over 64 bits. A stand-in for BLAKE2b-512, and the only property that
/// matters here: every byte of the input changes the result, so a comparison of
/// this digest is a comparison of the whole artefact.
int fakeDigest64(List<int> bytes) {
  int hash = 0xcbf29ce484222325;
  for (final int byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash;
}

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------

/// A clock that only moves when a test moves it, so a throttle is tested by
/// setting a value rather than by sleeping.
final class ScriptedUpdateClock implements UpdateClock {
  ScriptedUpdateClock([DateTime? start])
    : value = start ?? DateTime.utc(2026, 3, 1, 9) {
    log
      ..define('now', 'poll')
      ..define('advance', 'moves the clock forward');
  }

  final ScriptLog log = ScriptLog('ScriptedUpdateClock');

  DateTime value;

  /// How many times the client asked for the time.
  int reads = 0;

  void advance(Duration by) {
    value = value.add(by);
    log.record('advance', detail: by);
  }

  @override
  DateTime now() {
    reads += 1;
    log.poll('now');
    return value;
  }
}

// ---------------------------------------------------------------------------
// Network
// ---------------------------------------------------------------------------

/// An [HttpFetcher] whose two answers are both explicit.
final class ScriptedHttpFetcher implements HttpFetcher {
  ScriptedHttpFetcher() {
    log
      ..define('read', 'answers the arranged feed read')
      ..define('download', 'yields the arranged download events');
  }

  final ScriptLog log = ScriptLog('ScriptedHttpFetcher');

  /// What `read` answers. Null means "not arranged", and `read` raises.
  FeedRead? feed;

  /// What `download` yields. Null means "not arranged", and `download` raises.
  List<DownloadEvent>? downloadEvents;

  Object? readThrows;
  Object? downloadThrows;

  final List<Uri> readUrls = <Uri>[];
  final List<int> readCaps = <int>[];
  final List<Uri> downloadUrls = <Uri>[];
  final List<int> downloadCaps = <int>[];
  final List<AbortToken> tokens = <AbortToken>[];

  /// How many chunks were handed out, so a test can prove a stream was cut short
  /// rather than drained and then ignored.
  int chunksDelivered = 0;

  /// Called before each event is considered, with the number of events already
  /// delivered. A test uses it to stand in for a user pressing cancel at a
  /// chosen point, deterministically.
  void Function(int index)? beforeEvent;

  /// Total requests made, of either kind. "A refusal happened *before* a request
  /// went out" is an assertion about this number.
  int get requests => readUrls.length + downloadUrls.length;

  @override
  Future<FeedRead> read(
    Uri url, {
    required int maxBytes,
    required AbortToken abort,
  }) async {
    readUrls.add(url);
    readCaps.add(maxBytes);
    tokens.add(abort);
    final Object? failure = readThrows;
    if (failure != null) {
      log.record('read', detail: url);
      throw failure;
    }
    final FeedRead? answer = feed;
    if (answer == null) {
      log.record('read', detail: url);
      throw UnscriptedCallError(
        seam: 'ScriptedHttpFetcher',
        member: 'read',
        detail: url,
        arranged: log.arrangedMembers,
        hint:
            'set feed, or use FakeUpdateHarness.rejectFeed() for the 404 - an '
            'unanswered read must not look like a dead server',
      );
    }
    log.record('read', detail: url);
    return answer;
  }

  @override
  Stream<DownloadEvent> download(
    Uri url, {
    required int maxBytes,
    required AbortToken abort,
  }) async* {
    downloadUrls.add(url);
    downloadCaps.add(maxBytes);
    tokens.add(abort);
    final Object? failure = downloadThrows;
    if (failure != null) {
      log.record('download', detail: url);
      throw failure;
    }
    final List<DownloadEvent>? events = downloadEvents;
    if (events == null) {
      log.record('download', detail: url);
      throw UnscriptedCallError(
        seam: 'ScriptedHttpFetcher',
        member: 'download',
        detail: url,
        arranged: log.arrangedMembers,
        hint: 'set downloadEvents, or the client would see a stream that never '
            'said it finished - which it cannot tell from a truncated one',
      );
    }
    log.record('download', detail: url);
    for (final DownloadEvent event in events) {
      beforeEvent?.call(chunksDelivered);
      // A real transport stops when the token fires. So does this one, which is
      // what makes "the client aborted the stream" an observable fact.
      if (abort.isAborted) {
        yield const DownloadAborted();
        return;
      }
      if (event is DownloadChunk) chunksDelivered += 1;
      yield event;
    }
    if (abort.isAborted) yield const DownloadAborted();
  }
}

// ---------------------------------------------------------------------------
// Verifier
// ---------------------------------------------------------------------------

/// A [SignatureVerifier] that reads the whole file and compares a digest.
///
/// Deliberately not a boolean. [verifyArtifact] is handed a path, goes to
/// [ScriptedUpdateFileStore] for the bytes that were actually written, hashes
/// all of them and compares the result with [signedDigest].
final class ScriptedSignatureVerifier implements SignatureVerifier {
  ScriptedSignatureVerifier({required this.files, int? signedDigest})
    : signedDigest = signedDigest ?? fakeDigest64(fakeSignedArtifact()) {
    log
      ..define('classifyKey', 'answers the arranged key state')
      ..define(
        'verifyArtifact',
        'hashes the bytes the file store holds and compares them',
      );
  }

  final ScriptLog log = ScriptLog('ScriptedSignatureVerifier');

  /// The store whose bytes are read. Wiring it here rather than handing the
  /// verifier a list of bytes is what makes the comparison a whole-content one.
  final ScriptedUpdateFileStore files;

  /// The digest of the artefact the release key signed. Re-signed by the harness
  /// whenever it arranges a download, and **not** re-signed when a test passes
  /// different bytes - that asymmetry is the whole point of the rejection tests.
  int signedDigest;

  /// What `classifyKey` answers. Null means "not arranged", and `classifyKey`
  /// raises, because every key state leads somewhere different.
  ReleaseKeyState? keyState;

  /// Takes the verdict instead of computing it, for the cases a byte comparison
  /// cannot produce: an unreadable signature, a bridge that throws.
  ArtifactVerdict? scripted;

  /// Thrown by `verifyArtifact`, for the fail-closed path.
  Object? throwsOnVerify;

  final List<({String path, int byteLength, String signature, String key})>
  verified = <({String path, int byteLength, String signature, String key})>[];
  final List<String> classifiedKeys = <String>[];
  int classifyCalls = 0;

  @override
  Future<ReleaseKeyState> classifyKey(String publicKeyB64) async {
    classifyCalls += 1;
    classifiedKeys.add(publicKeyB64);
    final ReleaseKeyState? state = keyState;
    if (state == null) {
      log.record('classifyKey', detail: publicKeyB64);
      throw UnscriptedCallError(
        seam: 'ScriptedSignatureVerifier',
        member: 'classifyKey',
        detail: publicKeyB64,
        arranged: log.arrangedMembers,
        hint: 'set keyState: ReleaseKeyPrehashed, ReleaseKeyLegacy, '
            'ReleaseKeyUnreadable or ReleaseKeyUnavailable',
      );
    }
    log.record('classifyKey', detail: publicKeyB64);
    return state;
  }

  @override
  Future<ArtifactVerdict> verifyArtifact({
    required String artifactPath,
    required int byteLength,
    required String signatureB64,
    required String publicKeyB64,
  }) async {
    verified.add((
      path: artifactPath,
      byteLength: byteLength,
      signature: signatureB64,
      key: publicKeyB64,
    ));
    log.record('verifyArtifact', detail: artifactPath);
    final Object? failure = throwsOnVerify;
    if (failure != null) throw failure;
    final ArtifactVerdict? forced = scripted;
    if (forced != null) return forced;
    final ReleaseKeyState state =
        keyState ?? const ReleaseKeyPrehashed();
    if (state is! ReleaseKeyPrehashed) {
      return state is ReleaseKeyLegacy
          ? const ArtifactKeyIsLegacy()
          : const ArtifactKeyUnreadable();
    }
    final List<int>? actual = files.contentAt(artifactPath);
    if (actual == null) return const ArtifactSignatureRejected();
    // The length the client claims has to be the length on disk, or the client
    // has verified something other than what it wrote.
    if (actual.length != byteLength) return const ArtifactSignatureRejected();
    return fakeDigest64(actual) == signedDigest
        ? const ArtifactSignatureValid()
        : const ArtifactSignatureRejected();
  }
}

// ---------------------------------------------------------------------------
// Installer
// ---------------------------------------------------------------------------

/// An [InstallerLauncher] that records every launch. Nothing is executed.
final class ScriptedInstallerLauncher implements InstallerLauncher {
  ScriptedInstallerLauncher() {
    log.define('launch', 'records the path and answers the arranged outcome');
  }

  final ScriptLog log = ScriptLog('ScriptedInstallerLauncher');

  /// What `launch` answers. Null means "not arranged", and `launch` raises:
  /// an installer that "succeeded" without a test saying so is the one outcome
  /// that must never be a default.
  InstallOutcome? outcome;

  Object? throwsOnLaunch;

  final List<String> launched = <String>[];

  /// How many times an installer was handed a path. "Exactly once, and only
  /// after a successful verification" reads these two numbers.
  int get launches => launched.length;

  @override
  Future<InstallOutcome> launch(String artifactPath) async {
    log.record('launch', detail: artifactPath);
    final Object? failure = throwsOnLaunch;
    if (failure != null) throw failure;
    final InstallOutcome? answer = outcome;
    if (answer == null) {
      throw UnscriptedCallError(
        seam: 'ScriptedInstallerLauncher',
        member: 'launch',
        detail: artifactPath,
        arranged: log.arrangedMembers,
        hint: 'set outcome: InstallStarted or InstallRefused(detail)',
      );
    }
    launched.add(artifactPath);
    return answer;
  }
}

// ---------------------------------------------------------------------------
// File store
// ---------------------------------------------------------------------------

/// An in-memory [UpdateFileStore] that records the order of its operations and
/// refuses to write or commit a staging file that was never opened.
///
/// The order is the assertion: a test can require that `commit` came after the
/// verification and that `discard` came at all.
final class ScriptedUpdateFileStore implements UpdateFileStore {
  ScriptedUpdateFileStore({this.directory = 'C:/downloads'}) {
    log
      ..define('openStaging', 'creates a fresh .part staging file')
      ..define('append', 'appends to an open staging file')
      ..define('commit', 'promotes a staging file to its final name')
      ..define('discard', 'removes a staging file')
      ..define('committedPath', 'poll')
      ..define('committedLength', 'poll');
  }

  final ScriptLog log = ScriptLog('ScriptedUpdateFileStore');

  final String directory;

  final Map<String, List<int>> staging = <String, List<int>>{};
  final Map<String, List<int>> committed = <String, List<int>>{};

  /// `openStaging`, `append`, `commit`, `discard`, in the order they happened.
  final List<String> operations = <String>[];

  Object? throwOnOpen;
  Object? throwOnAppend;
  Object? throwOnCommit;

  int _attempts = 0;

  @override
  String committedPath(UpdateOffer offer) {
    log.poll('committedPath');
    return '$directory/${offer.fileName}';
  }

  @override
  Future<StagedArtifact> openStaging(UpdateOffer offer) async {
    log.record('openStaging', detail: offer.fileName);
    operations.add('open');
    final Object? failure = throwOnOpen;
    if (failure != null) throw failure;
    _attempts += 1;
    final String path =
        '$directory/.${offer.fileName}.$_attempts${StagedArtifact.stagingExtension}';
    staging[path] = <int>[];
    return StagedArtifact(path: path, fileName: offer.fileName, byteLength: 0);
  }

  @override
  Future<void> append(StagedArtifact target, List<int> chunk) async {
    final List<int>? open = staging[target.path];
    if (open == null) {
      log.record('append', detail: target.path);
      throw UnscriptedCallError(
        seam: 'ScriptedUpdateFileStore',
        member: 'append',
        detail: target.path,
        arranged: log.arrangedMembers,
        hint: 'openStaging() first - appending into a map entry that does not '
            'exist silently discards the chunk',
      );
    }
    log.record('append', detail: target.path);
    operations.add('append');
    final Object? failure = throwOnAppend;
    if (failure != null) throw failure;
    open.addAll(chunk);
  }

  @override
  Future<String> commit(StagedArtifact target) async {
    final List<int>? bytes = staging[target.path];
    if (bytes == null) {
      log.record('commit', detail: target.path);
      throw UnscriptedCallError(
        seam: 'ScriptedUpdateFileStore',
        member: 'commit',
        detail: target.path,
        arranged: log.arrangedMembers,
        hint: 'commit() only promotes something that was staged',
      );
    }
    log.record('commit', detail: target.path);
    operations.add('commit');
    final Object? failure = throwOnCommit;
    if (failure != null) throw failure;
    staging.remove(target.path);
    final String path = '$directory/${target.fileName}';
    committed[path] = bytes;
    return path;
  }

  @override
  Future<void> discard(StagedArtifact target) async {
    log.record('discard', detail: target.path);
    operations.add('discard');
    staging.remove(target.path);
  }

  @override
  Future<int?> committedLength(UpdateOffer offer) async {
    log.poll('committedLength');
    return committed[committedPath(offer)]?.length;
  }

  /// The bytes a path currently holds, staged or committed.
  List<int>? contentAt(String path) => staging[path] ?? committed[path];

  /// Whether anything is left in a staging file. "A partial download must never
  /// be executable" starts here: there must be nothing to execute.
  bool get hasStagingFiles => staging.isNotEmpty;

  /// How many times an artefact was committed.
  int get commits => operations.where((String op) => op == 'commit').length;
}
