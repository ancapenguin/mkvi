/// Hand-driven fakes for every seam `lib/update` exposes.
///
/// Nothing here opens a socket, reads a real key, writes a real file or waits on
/// a real clock. The signature fake is the one that is worth reading twice: it
/// behaves like `mkvi_core::update::verify_artifact` rather than like a boolean,
/// so a test that flips a byte anywhere in an artefact is testing a whole-content
/// comparison and not a flag somebody set.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/update/update_client.dart';
import 'package:mkvi/update/update_config.dart';
import 'package:mkvi/update/update_failure.dart';
import 'package:mkvi/update/update_fetcher.dart';
import 'package:mkvi/update/update_file_store.dart';
import 'package:mkvi/update/update_installer.dart';
import 'package:mkvi/update/update_manifest.dart';
import 'package:mkvi/update/update_verifier.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The version of the build the tests are pretending to run, and the version
/// the fake feed offers by default. The real numbers: `VERSION` at the repo root
/// and `pubspec.yaml:7` are both 0.2.0.
const String currentVersion = '0.2.0';

/// The offered version: one minor bump, so the comparison is unambiguous.
const String offeredVersion = '0.2.1';

/// A 42 byte minisign public key in the prehashed form: the algorithm bytes are
/// `0x45 0x44` - "ED" - and the rest is a key id and an Ed25519 key.
///
/// Shape only. Nothing in Dart decodes it, because nothing in Dart is allowed
/// to: verification is the Rust core's job and stays there.
const String prehashedKey =
    'RURaWlpaWlpaWhAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v';

/// The same 42 bytes with minisign's retired algorithm tag, `0x45 0x64` - "Ed".
///
/// This is the shape of the key `src-tauri/tauri.conf.json:41` actually holds,
/// and a strict verifier refuses every signature such a key can produce.
const String legacyKey =
    'RWRaWlpaWlpaWhAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4v';

/// The exact value from `src-tauri/tauri.conf.json:41`, verified base64 and
/// carried here so the legacy-key test is about the real configuration rather
/// than about a fixture that merely looks like it.
///
/// Decoded it is a whole `minisign.pub` file whose payload begins `Ed`, not
/// `ED` - the retired algorithm.
const String tauriConfiguredKey =
    'dW50cnVzdGVkIGNvbW1lbnQ6IG1pbmlzaWduIHB1YmxpYyBrZXk6IDg5Q0E3QjRBMEFFQTU2'
    'NDEKUldSQlZ1b0tTbnZLaWNOZ3BwRUF3RWsvVGV0V1RiMGZsR2ltak9LcGVFYkRLY2dNdVdR'
    'akJzWGYK';

/// A signature in the wire shape a feed stores: base64 of a whole `.sig` file.
/// Never decoded here either.
const String artifactSignature = 'c2lnbmF0dXJlLWJsb2NrLWJ5dGVz';

/// The endpoint the Tauri build shipped with. It answers 404, and it is named
/// here so the tests that use it say so out loud.
const String deadFeedUrl =
    'https://raw.githubusercontent.com/ancapenguin/mkvi-updates/main/latest.json';

/// A feed URL a working deployment would use.
const String liveFeedUrl = 'https://updates.example.invalid/mkvi/latest.json';

/// The artefact the release key signed. Long enough to cross more than one
/// chunk boundary, so a "check the first chunk" implementation cannot pass.
List<int> signedArtifact({int length = 4096}) =>
    List<int>.generate(length, (int index) => (index * 7 + 11) & 0xff);

/// A `latest.json` body offering [version] for the Windows target.
List<int> feedJson({
  String version = offeredVersion,
  String notes = 'Düzeltmeler',
  String url = 'https://releases.example.invalid/mkvi-setup.exe',
  String signature = artifactSignature,
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

/// An artefact stream of [length] bytes, announced honestly.
List<DownloadEvent> artifactEvents(List<int> bytes) => <DownloadEvent>[
  DownloadAnnounced(bytes.length),
  ...chunksOf(bytes, 512).map(DownloadChunk.new),
  DownloadComplete(bytes.length),
];

/// Splits [bytes] into [size] byte pieces.
List<List<int>> chunksOf(List<int> bytes, int size) {
  final List<List<int>> out = <List<int>>[];
  for (int start = 0; start < bytes.length; start += size) {
    final int end = start + size;
    out.add(bytes.sublist(start, end > bytes.length ? bytes.length : end));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Clock
// ---------------------------------------------------------------------------

/// A clock that only moves when a test moves it. The throttle is then tested by
/// setting a value rather than by sleeping.
final class FakeClock implements UpdateClock {
  FakeClock([DateTime? start]) : value = start ?? DateTime.utc(2026, 3, 1, 9);

  DateTime value;

  int reads = 0;

  void advance(Duration by) => value = value.add(by);

  @override
  DateTime now() {
    reads += 1;
    return value;
  }
}

// ---------------------------------------------------------------------------
// Fetcher
// ---------------------------------------------------------------------------

/// A [HttpFetcher] with a scripted answer for each call.
///
/// Records the URLs it was asked for and the caps it was given, so a test can
/// assert that a refusal happened *before* a request went out - which is the
/// difference between a fast answer and no answer at all.
final class FakeFetcher implements HttpFetcher {
  FakeFetcher({this.feed, this.events, this.readThrows, this.downloadThrows});

  /// What [read] answers.
  FeedRead? feed;

  /// What [download] yields. `null` until a test sets it.
  List<DownloadEvent>? events;

  Object? readThrows;
  Object? downloadThrows;

  final List<Uri> readUrls = <Uri>[];
  final List<int> readCaps = <int>[];
  final List<Uri> downloadUrls = <Uri>[];
  final List<int> downloadCaps = <int>[];
  final List<AbortToken> tokens = <AbortToken>[];

  /// How many chunks a download handed out, so a test can prove a stream was cut
  /// short rather than drained and then ignored.
  int chunksDelivered = 0;

  /// Called before each event is considered, with the number of events already
  /// delivered. A test uses it to stand in for a user pressing cancel at a
  /// chosen point, deterministically - a stream listener would work only if the
  /// timing happened to fall the right way.
  void Function(int index)? beforeEvent;

  /// Total requests made, of either kind.
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
    if (failure != null) throw failure;
    return feed ?? const FeedReadFailed('no answer scripted');
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
    if (failure != null) throw failure;
    for (final DownloadEvent event in events ?? const <DownloadEvent>[]) {
      beforeEvent?.call(chunksDelivered);
      // A real transport stops when the token fires. So does this one, which is
      // what lets "the client aborted the stream" be an observable fact.
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
/// [FakeFileStore] for the bytes that were actually written, hashes all of them
/// and compares the result with the digest of the artefact the release key
/// signed. A test that flips one byte at any offset therefore fails the way the
/// real bridge fails, and the recorded [verified] list is what proves the client
/// handed over the *whole* file rather than a window of it.
final class FakeSignatureVerifier implements SignatureVerifier {
  FakeSignatureVerifier({required this.files});

  final FakeFileStore files;

  /// What [classifyKey] answers. Defaults to the one good state.
  ReleaseKeyState keyState = const ReleaseKeyPrehashed();

  /// Set to take the verdict from the test instead of computing it, for the cases
  /// a byte comparison cannot produce (an unreadable signature, a bridge that
  /// throws).
  ArtifactVerdict? scripted;

  /// Set to make [verifyArtifact] throw, for the fail-closed path.
  Object? throwsOnVerify;

  /// The digest of the artefact that was signed. Set by the harness.
  int signedDigest = 0;

  final List<({String path, int byteLength, String signature, String key})>
  verified = <({String path, int byteLength, String signature, String key})>[];
  final List<String> classifiedKeys = <String>[];
  int classifyCalls = 0;

  @override
  Future<ReleaseKeyState> classifyKey(String publicKeyB64) async {
    classifyCalls += 1;
    classifiedKeys.add(publicKeyB64);
    return keyState;
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
    final Object? failure = throwsOnVerify;
    if (failure != null) throw failure;
    final ArtifactVerdict? forced = scripted;
    if (forced != null) return forced;
    if (keyState is! ReleaseKeyPrehashed) {
      return keyState is ReleaseKeyLegacy
          ? const ArtifactKeyIsLegacy()
          : const ArtifactKeyUnreadable();
    }
    final List<int>? actual = files.contentAt(artifactPath);
    if (actual == null) return const ArtifactSignatureRejected();
    // The length the client claims has to be the length on disk, or the client
    // has verified something other than what it wrote.
    if (actual.length != byteLength) return const ArtifactSignatureRejected();
    return digest64(actual) == signedDigest
        ? const ArtifactSignatureValid()
        : const ArtifactSignatureRejected();
  }
}

/// FNV-1a over 64 bits. A stand-in for BLAKE2b-512, and the only property that
/// matters here: every byte of the input changes the result, so a comparison of
/// this digest is a comparison of the whole artefact.
int digest64(List<int> bytes) {
  int hash = 0xcbf29ce484222325;
  for (final int byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash;
}

// ---------------------------------------------------------------------------
// Installer
// ---------------------------------------------------------------------------

/// An [InstallerLauncher] that records every launch. Nothing is executed.
final class FakeInstaller implements InstallerLauncher {
  FakeInstaller({this.outcome = const InstallStarted()});

  InstallOutcome outcome;
  Object? throwsOnLaunch;

  final List<String> launched = <String>[];

  /// How many times an installer was handed a path. The assertion "exactly once,
  /// and only after a successful verification" reads these two numbers.
  int get launches => launched.length;

  @override
  Future<InstallOutcome> launch(String artifactPath) async {
    launched.add(artifactPath);
    final Object? failure = throwsOnLaunch;
    if (failure != null) throw failure;
    return outcome;
  }
}

// ---------------------------------------------------------------------------
// File store
// ---------------------------------------------------------------------------

/// An in-memory [UpdateFileStore] that records the order of its operations.
///
/// The order is the assertion: a test can require that `commit` came after the
/// verification and that `discard` came at all.
final class FakeFileStore implements UpdateFileStore {
  FakeFileStore({this.directory = 'C:/downloads'});

  final String directory;

  final Map<String, List<int>> staging = <String, List<int>>{};
  final Map<String, List<int>> committed = <String, List<int>>{};

  /// `open`, `append`, `commit`, `discard`, in the order they happened.
  final List<String> operations = <String>[];

  Object? throwOnOpen;
  Object? throwOnAppend;
  Object? throwOnCommit;

  int _attempts = 0;

  @override
  String committedPath(UpdateOffer offer) => '$directory/${offer.fileName}';

  @override
  Future<StagedArtifact> openStaging(UpdateOffer offer) async {
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
    operations.add('append');
    final Object? failure = throwOnAppend;
    if (failure != null) throw failure;
    staging[target.path] = <int>[...staging[target.path] ?? <int>[], ...chunk];
  }

  @override
  Future<String> commit(StagedArtifact target) async {
    operations.add('commit');
    final Object? failure = throwOnCommit;
    if (failure != null) throw failure;
    final List<int> bytes = staging.remove(target.path) ?? <int>[];
    final String path = '$directory/${target.fileName}';
    committed[path] = bytes;
    return path;
  }

  @override
  Future<void> discard(StagedArtifact target) async {
    operations.add('discard');
    staging.remove(target.path);
  }

  @override
  Future<int?> committedLength(UpdateOffer offer) async =>
      committed[committedPath(offer)]?.length;

  /// The bytes a path currently holds, staged or committed.
  List<int>? contentAt(String path) => staging[path] ?? committed[path];

  /// Whether anything is left in a staging file. "A partial download must never
  /// be executable" starts here: there must be nothing to execute.
  bool get hasStagingFiles => staging.isNotEmpty;

  /// How many times an artefact was committed.
  int get commits => operations.where((String op) => op == 'commit').length;
}

// ---------------------------------------------------------------------------
// The whole client, wired to fakes
// ---------------------------------------------------------------------------

/// An [UpdateClient] with every seam faked, plus the handles a test pokes at.
final class UpdateHarness {
  UpdateHarness({
    String feedUrl = liveFeedUrl,
    String publicKey = prehashedKey,
    String version = currentVersion,
    List<int>? pinnedManifest,
    int artifactMaxBytes = 1024 * 1024,
    int manifestMaxBytes = 16 * 1024,
    Duration minCheckInterval = Duration.zero,
  }) {
    // The verifier reads the bytes the file store actually holds, which is what
    // makes it a whole-content comparison rather than a flag.
    verifier = FakeSignatureVerifier(files: files);
    config = UpdateConfig(
      currentVersion: version,
      feedUrl: Uri.parse(feedUrl),
      publicKeyB64: publicKey,
      pinnedManifest: pinnedManifest,
      artifactMaxBytes: artifactMaxBytes,
      manifestMaxBytes: manifestMaxBytes,
      minCheckInterval: minCheckInterval,
    );
    verifier.signedDigest = digest64(signedArtifact());
    events = <UpdateEvent>[];
    subscription = client.events.listen(events.add);
  }

  final FakeFetcher fetcher = FakeFetcher();
  final FakeFileStore files = FakeFileStore();
  final FakeClock clock = FakeClock();
  final FakeInstaller installer = FakeInstaller();

  /// Reads the bytes [files] actually holds, so its verdict is a whole-content
  /// comparison rather than a flag a test set.
  late final FakeSignatureVerifier verifier;

  late final UpdateConfig config;
  late final List<UpdateEvent> events;
  late final StreamSubscription<UpdateEvent> subscription;

  late final UpdateClient client = UpdateClient(
    config: config,
    fetcher: fetcher,
    verifier: verifier,
    installer: installer,
    files: files,
    clock: clock,
  );

  /// The bytes the release key is pretending to have signed.
  List<int> get artifact => signedArtifact();

  /// Lets the broadcast event stream deliver everything a test has already
  /// caused. A stream listener runs in a later turn than the `add`, so a report
  /// returned from `check()` can arrive before the last event has landed.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Points the fetcher at a feed offering [version], and the download at
  /// [bytes]. The common wiring for "an update is on offer and installs".
  ///
  /// The signed digest is recomputed **only** when [download] is left out. A test
  /// that passes different bytes is testing a rejection, and re-signing them
  /// here would quietly turn that test into a pass.
  void offerUpdate({
    List<int>? feed,
    List<int>? download,
    int declaredLength = -1,
  }) {
    final List<int> bytes = download ?? artifact;
    fetcher.feed = FeedReadOk(body: feed ?? feedJson(), declaredLength: null);
    final int declared = declaredLength < 0 ? bytes.length : declaredLength;
    fetcher.events = <DownloadEvent>[
      DownloadAnnounced(declared),
      ...chunksOf(bytes, 512).map(DownloadChunk.new),
      DownloadComplete(declared),
    ];
    if (download == null) verifier.signedDigest = digest64(bytes);
  }

  /// Runs [check] and hands back the offer it found, failing the test if there
  /// was not one.
  Future<UpdateOffer> offerFromCheck() async {
    offerUpdate();
    final UpdateReport report = await client.check();
    expect(report, isA<UpdateOffered>());
    return (report as UpdateOffered).offer;
  }

  /// The refusal a report carries, failing the test if it is not a refusal.
  UpdateFailure failureOf(UpdateReport report) {
    expect(report, isA<UpdateRefused>());
    return (report as UpdateRefused).failure;
  }

  List<T> eventsOf<T extends UpdateEvent>() =>
      events.whereType<T>().toList(growable: false);

  Future<void> dispose() async {
    await subscription.cancel();
    await client.dispose();
  }
}
