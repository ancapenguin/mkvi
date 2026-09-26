/// Fakes for every seam `lib/chat` exposes: the data channel, the local log,
/// the download sink and an outgoing file.
///
/// The three behaviours scripted here that a convenient double would skip are
/// the whole reason this file exists:
///
/// * **A closed channel is a decision.** [ScriptedChatChannel] will not quietly
///   drop a frame for a closed channel. A refusal is arranged, with a Turkish
///   reason, or the send raises. The old fake answered
///   `ChannelUnavailable` for a closed channel as a matter of course, so every
///   "the composer must not lose a line" test passed against a fake that was
///   actually throwing the line away.
/// * **A short write is a real answer.** [ScriptedFileSink] reports fewer bytes
///   than it was handed, so "progress is derived from bytes actually stored" is
///   a claim a test can falsify instead of a comment.
/// * **A write to a transfer nobody opened raises.** Returning `0` is a silent
///   no-op that reads exactly like "the disk filled up" and proves nothing.
library;

import 'dart:typed_data';

import 'package:mkvi/chat/chat_channel.dart';
import 'package:mkvi/chat/file_sink.dart';
import 'package:mkvi/chat/history_store.dart';
import 'package:mkvi/chat/timeline_message.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/file_frame.dart';

import 'script_log.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A local-midnight anchor, so a day-boundary assertion does not depend on when
/// the suite runs.
final DateTime fakeNoon = DateTime(2026, 9, 26, 12);

/// A stored line, for seeding a [ScriptedHistoryStore] and for asserting on what
/// the controller persisted.
StoredMessage fakeStored(
  String id, {
  DateTime? sentAt,
  MessageDirection direction = MessageDirection.incoming,
  String body = 'merhaba',
  MessageDelivery delivery = MessageDelivery.sent,
}) => StoredMessage(
  id: id,
  body: body,
  sentAt: sentAt ?? fakeNoon,
  direction: direction,
  delivery: delivery,
);

/// A `chat` frame as the peer would send it.
ChatMessage fakeChatFrame(String id, {String text = 'merhaba', int sentAt = 0}) =>
    ChatMessage(id: id, text: text, sentAt: sentAt);

// ---------------------------------------------------------------------------
// The data channel
// ---------------------------------------------------------------------------

/// A [ChatChannelBinding] that records every frame in the order it was sent and
/// refuses only what a test arranged.
final class ScriptedChatChannel implements ChatChannelBinding {
  ScriptedChatChannel({bool isOpen = true})
    // ignore: prefer_initializing_formals
    : _isOpen = isOpen {
    log
      ..define('isOpen', 'poll')
      ..define('send', 'records the control frame and answers FrameSent')
      ..define('sendFrame', 'records the binary frame and answers FrameSent');
  }

  final ScriptLog log = ScriptLog('ScriptedChatChannel');

  bool _isOpen;

  /// Whether the channel is up. Polled rather than pushed, exactly as the
  /// contract says, so a queue is never flushed against a channel that closed
  /// between the report and the flush.
  @override
  bool get isOpen {
    log.poll('isOpen');
    return _isOpen;
  }

  set isOpen(bool value) => _isOpen = value;

  /// Refuses every control frame with this Turkish text, whatever the open
  /// state. The "channel is up but nothing is getting through" case, which is
  /// not the same as a dead channel and which a queue has to survive too.
  String? refuseReason;

  /// When set, only a frame carrying one of these transfer ids is refused. The
  /// per-line seam: one line stays unsent while the ones behind it go out.
  Set<String> refuseTheseIds = const <String>{};

  /// How many frames to refuse before accepting again. `null` refuses forever,
  /// which is what "the channel is down" looks like from here. `0` means
  /// [refuseReason] is advisory and only [refuseTheseIds] refuses.
  int? refuseCount;

  /// Every control frame that went out, in order.
  final List<PeerControlMessage> controlFrames = <PeerControlMessage>[];

  /// Every binary frame that went out, in order.
  final List<FileFrame> fileFrames = <FileFrame>[];

  /// Every frame that was **refused**, in order. Together with [wire] this is
  /// the order contract `ROADMAP.md` Faz 5 asks for, refusals included.
  final List<Object> refused = <Object>[];

  /// Every frame offered to the channel, in order, whatever the verdict.
  ///
  /// One list across both kinds on purpose: the contract under test is a
  /// *sequence* of steps (`accept` -> `[SendFrame, PublishMedia]`), and a test
  /// that has to merge two lists to read it is a test that will read it wrong.
  final List<Object> wire = <Object>[];

  List<ChatMessage> get chats =>
      controlFrames.whereType<ChatMessage>().toList(growable: false);

  List<FileOfferMessage> get offers =>
      controlFrames.whereType<FileOfferMessage>().toList(growable: false);

  List<FileAcceptMessage> get accepts =>
      controlFrames.whereType<FileAcceptMessage>().toList(growable: false);

  List<FileDeclineMessage> get declines =>
      controlFrames.whereType<FileDeclineMessage>().toList(growable: false);

  List<FileCancelMessage> get cancels =>
      controlFrames.whereType<FileCancelMessage>().toList(growable: false);

  List<FileCompleteMessage> get completes =>
      controlFrames.whereType<FileCompleteMessage>().toList(growable: false);

  int get frameCount => controlFrames.length + fileFrames.length;

  /// Arranges a refusal with a Turkish [reason].
  void refuse({required String reason, int? times}) {
    refuseReason = reason;
    refuseCount = times;
  }

  /// Forgets the frames. A channel outlives many transfers; the record should be
  /// clearable between phases of one test.
  void reset() {
    controlFrames.clear();
    fileFrames.clear();
    refused.clear();
    wire.clear();
    log.clear();
  }

  @override
  SendOutcome send(PeerControlMessage message) {
    final SendOutcome outcome = _judge(message.id, message, 'send');
    if (outcome is FrameSent) controlFrames.add(message);
    return outcome;
  }

  @override
  SendOutcome sendFrame(FileFrame frame) {
    final SendOutcome outcome = _judge(frame.id, frame, 'sendFrame');
    if (outcome is FrameSent) fileFrames.add(frame);
    return outcome;
  }

  SendOutcome _judge(String id, Object frame, String member) {
    if (!isOpen && refuseReason == null) {
      // A closed channel that nobody arranged a refusal for is a frame the fake
      // would drop on the floor, and the caller would see a refusal carrying a
      // reason nobody chose. Refuse before touching any state.
      throw UnscriptedCallError(
        seam: 'ScriptedChatChannel',
        member: member,
        detail: 'channel closed, no refusal arranged',
        arranged: log.arrangedMembers,
        hint: "call refuse(reason: '...'), or isOpen = true",
      );
    }
    wire.add(frame);
    log.record(member, detail: id);
    if (_shouldRefuse(id)) {
      refused.add(frame);
      return ChannelUnavailable(reason);
    }
    return const FrameSent();
  }

  bool _shouldRefuse(String id) {
    if (refuseEverything) return true;
    if (refuseTheseIds.contains(id)) return true;
    final String? text = refuseReason;
    if (text == null) return false;
    final int? remaining = refuseCount;
    if (remaining == null) return true;
    if (remaining <= 0) return false;
    refuseCount = remaining - 1;
    return true;
  }

  /// Whether a refusal is arranged at all. A convenience for a test that wants to
  /// assert the *shape* of the refusal rather than its reason.
  bool get refuseEverything => refuseReason != null && refuseCount == null;

  /// The Turkish text a refusal carries.
  String get reason => refuseReason ?? 'Bağlantı kapatıldı.';
}

// ---------------------------------------------------------------------------
// The local log
// ---------------------------------------------------------------------------

/// An in-memory [HistoryStore] that pages oldest-first, as the contract
/// requires, and refuses a read nobody seeded.
final class ScriptedHistoryStore implements HistoryStore {
  ScriptedHistoryStore({
    List<StoredMessage> seed = const <StoredMessage>[],
    this.allowEmpty = true,
  }) {
    seedAll(seed);
    log
      ..define('loadNewest', 'returns the newest page, oldest-first')
      ..define('loadOlder', 'returns the page before a line, oldest-first')
      ..define('append', 'stores the line, or throws once when asked to')
      ..define('trimTo', 'keeps the newest lines and forgets the rest')
      ..define('committedLength', 'how many lines are stored');
  }

  final ScriptLog log = ScriptLog('ScriptedHistoryStore');

  /// When false, a read of an empty store raises instead of answering an empty
  /// page. "There is no history" and "the log could not be read" are different
  /// facts and a test should have to say which one it means.
  bool allowEmpty;

  final Map<String, StoredMessage> _rows = <String, StoredMessage>{};
  final List<String> _order = <String>[];

  /// One answer per read, consumed in order. The "a read fails and then
  /// succeeds" case, which is exactly the retry the broken screen offers.
  final List<HistoryPage> readScript = <HistoryPage>[];

  /// Thrown by the next read, once.
  Object? failNextRead;

  /// Thrown by the next append, once. A *write* failure: the line is already on
  /// screen and the disk copy is what is lost.
  Object? failNextAppend;

  int reads = 0;
  int appends = 0;
  int trims = 0;

  /// Every id in the order it was first written.
  List<String> get storedIds => List<String>.unmodifiable(_order);

  StoredMessage? storedOf(String id) => _rows[id];

  int get length => _rows.length;

  /// Arranges the answer for the next [n] reads.
  void scriptReads(List<HistoryPage> pages) => readScript.addAll(pages);

  /// Adds lines, ignoring ids that are already stored.
  void seedAll(Iterable<StoredMessage> messages) {
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
    _guardRead('loadNewest');
    if (readScript.isNotEmpty) return readScript.removeAt(0);
    final List<StoredMessage> oldestFirst = _sorted();
    final int start =
        oldestFirst.length <= limit ? 0 : oldestFirst.length - limit;
    return HistoryPage(
      messages: oldestFirst.sublist(start),
      hasMore: start > 0,
    );
  }

  @override
  Future<HistoryPage> loadOlder({
    required String conversationId,
    required int beforeMs,
    required String beforeId,
    required int limit,
  }) async {
    reads += 1;
    _guardRead('loadOlder');
    if (readScript.isNotEmpty) return readScript.removeAt(0);
    final List<StoredMessage> older = _sorted()
        .where(
          (StoredMessage m) =>
              m.sentAtMs < beforeMs ||
              (m.sentAtMs == beforeMs && m.id.compareTo(beforeId) < 0),
        )
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
    log.record('append', detail: message.id);
    final Object? failure = failNextAppend;
    if (failure != null) {
      failNextAppend = null;
      throw failure;
    }
    // A retried send and a re-read of the timeline both land here, so an id that
    // is already stored is a no-op rather than a second row.
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
    log.record('trimTo', detail: keep);
    final List<StoredMessage> newestFirst = _sorted().reversed.toList();
    final List<StoredMessage> kept = newestFirst
        .take(keep)
        .toList()
        .reversed
        .toList();
    _rows
      ..clear()
      ..addEntries(
        kept.map(
          (StoredMessage m) => MapEntry<String, StoredMessage>(m.id, m),
        ),
      );
    _order
      ..clear()
      ..addAll(kept.map((StoredMessage m) => m.id));
  }

  void _guardRead(String member) {
    log.record(member, detail: _rows.length);
    final Object? failure = failNextRead;
    if (failure != null) {
      failNextRead = null;
      throw failure;
    }
    if (!allowEmpty && _rows.isEmpty && readScript.isEmpty) {
      throw UnscriptedCallError(
        seam: 'ScriptedHistoryStore',
        member: member,
        detail: 'the log is empty and nothing was seeded',
        arranged: log.arrangedMembers,
        hint: 'seed a line, script a read, or set allowEmpty = true',
      );
    }
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
}

// ---------------------------------------------------------------------------
// The download sink
// ---------------------------------------------------------------------------

/// A [FileSink] with the never-overwrite rule of
/// `crates/mkvi_core/src/files.rs`, plus the failure modes a suite needs.
final class ScriptedFileSink implements FileSink {
  ScriptedFileSink({this.directory = '/tmp/mkvi'}) {
    log
      ..define(
        'open',
        'creates a never-overwriting path and records it for the transfer',
      )
      ..define('write', 'appends and reports the bytes actually stored')
      ..define('close', 'forgets the transfer and returns its path')
      ..define('abort', 'removes the partial file and leaves nothing behind');
  }

  final ScriptLog log = ScriptLog('ScriptedFileSink');

  final String directory;

  /// The files that exist right now, keyed by the full path.
  final Map<String, Uint8List> disk = <String, Uint8List>{};

  /// Transfer id to the path [open] handed out, so a test can assert a refusal
  /// happened *before* a path existed.
  final Map<String, String> opened = <String, String>{};

  final List<String> openedOrder = <String>[];
  final List<String> written = <String>[];
  final List<String> closed = <String>[];
  final List<String> aborted = <String>[];

  /// When set, `open` throws for a transfer whose name contains it. The disk
  /// refused, or the folder is gone.
  String? failOpenFor;

  /// When set, `write` throws for a transfer whose id contains it.
  String? failWriteFor;

  /// When set, `open` throws for every transfer, not just matching names.
  Object? failOpen;

  /// How many bytes `write` stores per call when fewer than the chunk. The short
  /// write: a sink that batches, or one whose disk filled. Null stores
  /// everything, which is the honest default.
  int? shortWriteBytes;

  /// How many calls store nothing at all, then stop truncating. The sink that
  /// is alive and reports no progress.
  int zeroWrites = 0;

  /// Every path that exists, in the order it was created.
  List<String> get existingPaths => List<String>.unmodifiable(disk.keys);

  bool exists(String path) => disk.containsKey(path);

  int lengthOf(String path) => disk[path]?.length ?? 0;

  @override
  Future<String> open({
    required String transferId,
    required String name,
    required String mime,
  }) async {
    log.record('open', detail: name);
    final Object? failure = failOpen;
    if (failure != null) throw failure;
    if (failOpenFor != null && name.contains(failOpenFor!)) {
      throw FileSinkException('Dosya diske açılamadı.');
    }
    final String path = uniquePath(name);
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
    final String? path = opened[transferId];
    if (path == null) {
      // The old fake returned 0 here, and 0 is indistinguishable from "the
      // disk filled up" - so a test asserting the progress bar held still
      // passed against a fake that was really dropping the bytes.
      throw UnscriptedCallError(
        seam: 'ScriptedFileSink',
        member: 'write',
        detail: transferId,
        arranged: log.arrangedMembers,
        hint: 'open() the transfer first',
      );
    }
    log.record('write', detail: transferId);
    final String? failure = failWriteFor;
    if (failure != null && transferId.contains(failure)) {
      throw FileSinkException('Dosya diske yazılamadı.');
    }
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
    log.record('close', detail: transferId);
    final String? path = opened.remove(transferId);
    if (path == null) {
      throw UnscriptedCallError(
        seam: 'ScriptedFileSink',
        member: 'close',
        detail: transferId,
        arranged: log.arrangedMembers,
        hint: 'close() is only for a transfer that was open()ed',
      );
    }
    closed.add(transferId);
    return path;
  }

  @override
  Future<void> abort({required String transferId}) async {
    // Total on purpose: `FileSink.abort` is documented as a no-op for a transfer
    // that was never opened, and a cleanup path that raises would take the
    // transfer it is cleaning up after down with it.
    log.record('abort', detail: transferId);
    final String? path = opened.remove(transferId);
    aborted.add(transferId);
    // The 0-byte-file rule: an abort must leave nothing behind, not even an
    // empty one.
    if (path != null) disk.remove(path);
  }

  /// `unique_path` from `crates/mkvi_core/src/files.rs:42`: never overwrite,
  /// append " (1)", " (2)", ... until the name is free.
  String uniquePath(String name) {
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
final class ScriptedOutgoingFile implements OutgoingFileSource {
  ScriptedOutgoingFile({
    required this.name,
    required List<int> bytes,
    this.mime = 'application/octet-stream',
    this.declaredSize,
  }) : _bytes = Uint8List.fromList(bytes) {
    log
      ..define('read', 'returns up to length bytes from offset')
      ..define('size', 'poll');
  }

  final ScriptLog log = ScriptLog('ScriptedOutgoingFile');

  @override
  final String name;

  @override
  final String mime;

  /// A *declared* size that disagrees with the bytes. "What happens when the
  /// file is not what it claimed to be" - the check that has to happen before a
  /// single byte moves.
  final int? declaredSize;

  final Uint8List _bytes;

  /// What `read` hands back per call when fewer than asked for. The source that
  /// returns short reads, which is legal.
  int? shortReadBytes;

  /// Thrown by the next `read`, once. The file was deleted mid-send.
  Object? failNextRead;

  int reads = 0;

  @override
  int get size {
    log.poll('size');
    return declaredSize ?? _bytes.length;
  }

  @override
  Future<List<int>> read({required int offset, required int length}) async {
    reads += 1;
    log.record('read', detail: offset);
    final Object? failure = failNextRead;
    if (failure != null) {
      failNextRead = null;
      throw failure;
    }
    if (offset >= _bytes.length || length <= 0) return const <int>[];
    final int available = _bytes.length - offset;
    final int cap = shortReadBytes ?? length;
    final int take = available < cap ? available : cap;
    return _bytes.sublist(offset, offset + take);
  }

  /// The bytes the file really holds. A test compares this against [size].
  List<int> get bytes => List<int>.unmodifiable(_bytes);

  @override
  String toString() => 'ScriptedOutgoingFile($name, $size bytes)';
}
