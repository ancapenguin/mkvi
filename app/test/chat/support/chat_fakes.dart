/// Hand-driven fakes for every seam `lib/chat` exposes.
///
/// Nothing here opens a socket, writes a file or waits on a real clock. Three
/// behaviours are faked *deliberately* rather than conveniently, because each one
/// is a defect the suite has to be able to reproduce:
///
/// * [RecordingChannel] can refuse a frame — the channel-down case, which a
///   channel-gated send path had no way to represent at all.
/// * [FakeFileSink] can report a **short write**, so "progress is derived from
///   bytes actually written" is a claim the suite can falsify.
/// * [FakeFileSink] implements the same never-overwrite rule as
///   `crates/mkvi_core/src/files.rs`, so "two same-named transfers get distinct
///   paths" is tested against the production naming rule rather than a stub that
///   hands out `name` and therefore proves nothing.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat_channel.dart';
import 'package:mkvi/chat/file_sink.dart';
import 'package:mkvi/chat/history_store.dart';
import 'package:mkvi/chat/timeline_message.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/file_frame.dart';

/// Mints deterministic, distinct, well-formed transfer ids.
///
/// `randomTransferId()` is the production seam and is exercised by the protocol
/// suite; here a test needs to *name* the id it is about to look up.
final class CountingIds {
  CountingIds({this.prefix = 'a'});

  /// The first id is `prefix` repeated so a test can read it at a glance.
  final String prefix;

  int calls = 0;

  String call() {
    calls += 1;
    return prefix * 32;
  }

  /// A one-off factory for exactly [n] ids.
  static String Function() sequence(int n) {
    int next = 0;
    return () => (next++).toRadixString(16).padLeft(32, '0');
  }
}

/// A channel whose open state and refusals the test decides.
final class RecordingChannel implements ChatChannelBinding {
  RecordingChannel({
    this.isOpen = false,
    this.refuseReason,
    this.refuseEverything = false,
    this.refuseCount,
  });

  @override
  bool isOpen;

  /// When set, every `send` answers [ChannelUnavailable] with this text.
  String? refuseReason;

  /// When true, every `send` is refused whatever [refuseReason] says. The
  /// "channel is up but nothing is getting through" case, which is not the same
  /// thing as a dead channel and which a queue has to survive too.
  bool refuseEverything = false;

  /// When non-empty, only a frame whose transfer id is in this set is refused.
  /// The per-line seam: it lets one line stay unsent while the ones behind it go
  /// out, which is the only way to hold a pending line in front of a window that
  /// is about to overflow.
  Set<String> refuseTheseIds = const <String>{};

  final List<PeerControlMessage> controlFrames = <PeerControlMessage>[];
  final List<FileFrame> fileFrames = <FileFrame>[];

  /// How many control frames to refuse before accepting again. `null` refuses
  /// forever, which is what "the channel is down" looks like from here. `0` means
  /// [refuseReason] is advisory and only [refuseTheseIds] is refused.
  int? refuseCount;

  int get frameCount => controlFrames.length + fileFrames.length;

  List<FileAcceptMessage> get accepts =>
      controlFrames.whereType<FileAcceptMessage>().toList(growable: false);

  List<FileDeclineMessage> get declines =>
      controlFrames.whereType<FileDeclineMessage>().toList(growable: false);

  List<FileCancelMessage> get cancels =>
      controlFrames.whereType<FileCancelMessage>().toList(growable: false);

  List<FileOfferMessage> get offers =>
      controlFrames.whereType<FileOfferMessage>().toList(growable: false);

  List<FileCompleteMessage> get completes =>
      controlFrames.whereType<FileCompleteMessage>().toList(growable: false);

  List<ChatMessage> get chats =>
      controlFrames.whereType<ChatMessage>().toList(growable: false);

  void reset() {
    controlFrames.clear();
    fileFrames.clear();
  }

  @override
  SendOutcome send(PeerControlMessage message) {
    if (_shouldRefuse(message.id)) return ChannelUnavailable(reason);
    controlFrames.add(message);
    return const FrameSent();
  }

  @override
  SendOutcome sendFrame(FileFrame frame) {
    if (_shouldRefuse(frame.id)) return ChannelUnavailable(reason);
    fileFrames.add(frame);
    return const FrameSent();
  }

  bool _shouldRefuse(String id) {
    if (!isOpen || refuseEverything) return true;
    if (refuseTheseIds.contains(id)) return true;
    final String? text = refuseReason;
    if (text == null) return false;
    final int? remaining = refuseCount;
    if (remaining == null) return true;
    if (remaining <= 0) return false;
    refuseCount = remaining - 1;
    return true;
  }

  String get reason => refuseReason ?? 'Bağlantı kapatıldı.';
}

/// An in-memory [HistoryStore] that returns oldest-first pages, as the contract
/// requires, and can be made to fail.
final class FakeHistoryStore implements HistoryStore {
  FakeHistoryStore({List<StoredMessage> seed = const <StoredMessage>[]}) {
    for (final StoredMessage message in seed) {
      _rows[message.id] = message;
    }
  }

  final Map<String, StoredMessage> _rows = <String, StoredMessage>{};
  final List<String> _order = <String>[];

  /// Set to make the next read throw, the way a locked keyring would.
  Object? failNextRead;

  /// Set to make the next append throw, which is a *write* failure: the line is
  /// already on screen and the disk copy is what is lost.
  Object? failNextAppend;

  int reads = 0;
  int appends = 0;
  int trims = 0;

  /// Every id in the order it was first written.
  List<String> get storedIds => List<String>.unmodifiable(_order);

  StoredMessage? storedOf(String id) => _rows[id];

  int get length => _rows.length;

  void seed(Iterable<StoredMessage> messages) {
    for (final StoredMessage message in messages) {
      if (_rows.containsKey(message.id)) continue;
      _rows[message.id] = message;
      _order.add(message.id);
    }
    _sort();
  }

  @override
  Future<HistoryPage> loadNewest({
    required String conversationId,
    required int limit,
  }) async {
    reads += 1;
    _maybeFail();
    final List<StoredMessage> oldestFirst = _sorted();
    final int start = oldestFirst.length <= limit
        ? 0
        : oldestFirst.length - limit;
    final List<StoredMessage> page = oldestFirst.sublist(start);
    return HistoryPage(messages: page, hasMore: start > 0);
  }

  @override
  Future<HistoryPage> loadOlder({
    required String conversationId,
    required int beforeMs,
    required String beforeId,
    required int limit,
  }) async {
    reads += 1;
    _maybeFail();
    final List<StoredMessage> oldestFirst = _sorted();
    final List<StoredMessage> older = oldestFirst
        .where((StoredMessage m) => _isBefore(m, beforeMs, beforeId))
        .toList(growable: false);
    final int start = older.length <= limit ? 0 : older.length - limit;
    return HistoryPage(messages: older.sublist(start), hasMore: start > 0);
  }

  @override
  Future<void> append({
    required String conversationId,
    required StoredMessage message,
  }) async {
    appends += 1;
    final Object? failure = failNextAppend;
    if (failure != null) {
      failNextAppend = null;
      throw failure;
    }
    if (_rows.containsKey(message.id)) return;
    _rows[message.id] = message;
    _order.add(message.id);
    _sort();
  }

  @override
  Future<void> trimTo({
    required String conversationId,
    required int keep,
  }) async {
    trims += 1;
    final List<StoredMessage> newestFirst = _sorted().reversed.toList();
    final List<StoredMessage> kept = newestFirst
        .take(keep)
        .toList()
        .reversed
        .toList();
    _rows
      ..clear()
      ..addEntries(
        kept.map((StoredMessage m) => MapEntry<String, StoredMessage>(m.id, m)),
      );
    _order
      ..clear()
      ..addAll(kept.map((StoredMessage m) => m.id));
  }

  void _maybeFail() {
    final Object? failure = failNextRead;
    if (failure == null) return;
    failNextRead = null;
    throw failure;
  }

  void _sort() {
    _order.sort((String a, String b) {
      final StoredMessage left = _rows[a]!;
      final StoredMessage right = _rows[b]!;
      final int byInstant = left.sentAtMs.compareTo(right.sentAtMs);
      return byInstant != 0 ? byInstant : left.id.compareTo(right.id);
    });
  }

  List<StoredMessage> _sorted() =>
      _order.map((String id) => _rows[id]!).toList(growable: false);

  static bool _isBefore(StoredMessage m, int beforeMs, String beforeId) {
    final int byInstant = m.sentAtMs.compareTo(beforeMs);
    return byInstant < 0 || (byInstant == 0 && m.id.compareTo(beforeId) < 0);
  }
}

/// A [FileSink] with the never-overwrite rule of
/// `crates/mkvi_core/src/files.rs`, plus the two failure modes the suite needs.
final class FakeFileSink implements FileSink {
  FakeFileSink({this.directory = '/tmp/mkvi'});

  final String directory;

  /// The files that exist right now, keyed by the full path.
  final Map<String, Uint8List> disk = <String, Uint8List>{};

  /// Transfer id to the path [open] handed out, so a test can assert that a
  /// refusal happened *before* a path existed.
  final Map<String, String> opened = <String, String>{};

  final List<String> openedOrder = <String>[];
  final List<String> written = <String>[];
  final List<String> closed = <String>[];
  final List<String> aborted = <String>[];

  /// When set, [open] throws for a transfer whose name contains it.
  String? failOpenFor;

  /// When set, [write] throws for a transfer whose id contains it.
  String? failWriteFor;

  /// How many bytes [write] stores per call, when smaller than the chunk. This is
  /// the short write: a sink that batches, or one whose disk filled. `null`
  /// stores everything, which is the honest default.
  int? shortWriteBytes;

  /// How many times [write] stores nothing at all, then stops truncating.
  int zeroWrites = 0;

  /// Every path that exists, newest last.
  List<String> get existingPaths => List<String>.unmodifiable(disk.keys);

  bool exists(String path) => disk.containsKey(path);

  int lengthOf(String path) => disk[path]?.length ?? 0;

  @override
  Future<String> open({
    required String transferId,
    required String name,
    required String mime,
  }) async {
    if (failOpenFor != null && name.contains(failOpenFor!)) {
      throw FileSinkException('Dosya diske açılamadı.');
    }
    final String path = _uniquePath(name);
    disk[path] = Uint8List(0);
    opened[transferId] = path;
    openedOrder.add(transferId);
    return path;
  }

  @override
  Future<int> write({
    required String transferId,
    required List<int> chunk,
  }) async {
    if (failWriteFor != null && transferId.contains(failWriteFor!)) {
      throw FileSinkException('Dosya diske yazılamadı.');
    }
    final String? path = opened[transferId];
    if (path == null) return 0;
    final int stored = shortWriteBytes ?? chunk.length;
    if (zeroWrites > 0) {
      zeroWrites -= 1;
      written.add(transferId);
      return 0;
    }
    final int take = stored < chunk.length ? stored : chunk.length;
    final Uint8List existing = disk[path]!;
    final Uint8List next = Uint8List(existing.length + take);
    next
      ..setRange(0, existing.length, existing)
      ..setRange(existing.length, existing.length + take, chunk);
    disk[path] = next;
    written.add(transferId);
    return take;
  }

  @override
  Future<String> close({required String transferId}) async {
    final String? path = opened.remove(transferId);
    if (path == null) throw const FileSinkException('Açık dosya yok.');
    closed.add(transferId);
    return path;
  }

  @override
  Future<void> abort({required String transferId}) async {
    final String? path = opened.remove(transferId);
    aborted.add(transferId);
    // The 0-byte-file rule: an abort must leave nothing behind, not even an
    // empty file. A sink that only closed the handle would leave one.
    if (path != null) disk.remove(path);
  }

  /// `unique_path` from `crates/mkvi_core/src/files.rs:42`: never overwrite,
  /// append " (1)", " (2)", … until the name is free.
  String _uniquePath(String name) {
    final String candidate = '$directory/$name';
    if (!disk.containsKey(candidate)) return candidate;
    final int dot = name.lastIndexOf('.');
    final bool hasExtension = dot > 0 && dot < name.length - 1;
    final String stem = hasExtension ? name.substring(0, dot) : name;
    final String extension = hasExtension ? name.substring(dot) : '';
    for (int index = 1; index < 10000; index += 1) {
      final String next = '$directory/$stem ($index)$extension';
      if (!disk.containsKey(next)) return next;
    }
    return '$directory/$stem (9999)$extension';
  }
}

/// A file this device is sending, backed by an in-memory byte list.
final class FakeOutgoingFile implements OutgoingFileSource {
  FakeOutgoingFile({
    required this.name,
    required List<int> bytes,
    this.mime = 'application/octet-stream',
    this.declaredSize,
  }) : _bytes = Uint8List.fromList(bytes);

  @override
  final String name;

  @override
  final String mime;

  /// A *declared* size that disagrees with the bytes, which is how a test asks
  /// "what happens when the file is not what it claimed to be".
  final int? declaredSize;

  final Uint8List _bytes;

  /// What [read] hands back per call, when smaller than asked for.
  int? shortReadBytes;

  int reads = 0;

  @override
  int get size => declaredSize ?? _bytes.length;

  @override
  Future<List<int>> read({required int offset, required int length}) async {
    reads += 1;
    if (offset >= _bytes.length) return const <int>[];
    final int available = _bytes.length - offset;
    final int cap = shortReadBytes ?? length;
    final int take = available < cap
        ? available
        : (cap < available ? cap : available);
    return _bytes.sublist(offset, offset + take);
  }

  @override
  String toString() => 'FakeOutgoingFile($name, $size bytes)';
}

/// Lets the event loop run until [reached] is true, then fails loudly rather
/// than hanging when the code under test never arrives.
Future<void> pumpUntil(
  bool Function() reached, {
  String reason = 'the expected point',
  int turns = 1000,
}) async {
  for (int turn = 0; turn < turns; turn += 1) {
    if (reached()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(reached(), isTrue, reason: 'the loop never reached $reason');
}

/// A local-midnight anchor, so day-boundary assertions do not depend on when the
/// suite runs.
final DateTime testToday = DateTime(2026, 9, 26, 12);

/// A stored line, for seeding a [FakeHistoryStore].
StoredMessage storedAt(
  String id,
  DateTime sentAt, {
  MessageDirection direction = MessageDirection.incoming,
  String body = 'merhaba',
  MessageDelivery delivery = MessageDelivery.sent,
}) => StoredMessage(
  id: id,
  body: body,
  sentAt: sentAt,
  direction: direction,
  delivery: delivery,
);
