/// `HistoryStore` over `mkvi_core`'s encrypted history table.
///
/// ## The three gaps, stated up front because they are not implementation detail
///
/// The bridge exposes one read: `list_history(core, limit)`, newest first, with
/// the core clamping `limit` to **500** (`security.rs:268`, `limit.min(500)`).
/// There is no cursor, no conversation filter, no delete. [HistoryStore] asks for
/// all three. So:
///
/// 1. **`loadOlder` is only exact inside the 500-row window.** [HistoryWindow]
///    re-sorts the window deterministically and pages with a `(sent_at_ms, id)`
///    cursor, so paging is *correct* — but it can only see the newest 500 rows.
///    A caller that pages past that gets a short answer instead of a wrong one,
///    and [RustHistoryStore.olderRequestsBeyondWindow] counts it. Silently
///    returning "nothing older" there is the one outcome that would be a lie, so
///    it is counted instead of implied.
/// 2. **`trimTo` cannot be implemented at all.** There is no delete in the
///    bridge and no `Core` call behind it, so [RustHistoryStore.trimTo] throws
///    [HistoryTrimUnsupported] rather than reporting a trim it did not perform.
///    `HistoryStore`'s own comment says the log on disk has to be bounded, so a
///    silent no-op would turn a real defect into a green test.
/// 3. **`retentionLimit` is 5000 and the core is 500.** That is measured, not
///    assumed, and it is kept visible as [historyRetentionGap] rather than
///    papered over by quietly changing either number.
///
/// The fix for all three is in `mkvi_core`, which this change does not touch:
/// a cursor-taking list, a per-conversation filter, and a delete. See the report.
///
/// ## Why the paging arithmetic is a pure function
///
/// Same reason as the peer store's failure mapping: `bridge.HistoryMessage` is a
/// plain generated data class, so the page arithmetic is measurable without a
/// native library. [HistoryWindow] is that arithmetic, with no I/O in it.
library;

import 'dart:math' as math;

import 'package:mkvi/chat/history_store.dart';
import 'package:mkvi/chat/timeline_message.dart';
// `mkvi_bridge`'in `lib/` altında genel bir kütüphane dosyası yok ve README'i tüketiciden tam olarak bu yolu istiyor.
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/api.dart' as bridge;
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/error.dart' as bridge;

import 'rust_core.dart';

/// The core's own clamp on `list_history`. Measured at `security.rs:268`
/// (`limit.min(500)`), and re-stated here so nothing has to read Rust to know
/// the size of the window this store can see.
const int historyWindowRows = 500;

/// How much of the window a page asks for, per requested row.
///
/// A conversation filter is applied *after* the read, so asking for exactly
/// `limit` rows would return a short page whenever the window holds another
/// conversation's lines. Over-fetching widens the window; it does not make the
/// window bigger, which is why the factor is a named constant and not a guess
/// buried in a call.
const int historyConversationWindowFactor = 4;

/// The `sender_device_id` [StoredMessage.senderDeviceId] writes for an outgoing
/// line. Also the discriminator used to recover direction on a read.
const String localSenderDeviceId = 'local';

/// The `sender_device_id` for an incoming line.
const String peerSenderDeviceId = 'peer';

/// A page, plus whether the window could answer it completely.
final class HistoryPageResult {
  const HistoryPageResult({required this.page, required this.reachedWindowStart});

  /// The page, oldest line first.
  final HistoryPage page;

  /// True when the window may be hiding older rows.
  ///
  /// False means `hasMore == false` is trustworthy. True means there may be more
  /// that this bridge cannot see, and the count is on the store.
  final bool reachedWindowStart;

  @override
  String toString() =>
      'HistoryPageResult(${page.length}, hasMore: ${page.hasMore}, '
      'reachedWindowStart: $reachedWindowStart)';
}

/// The paging arithmetic, with no I/O in it.
///
/// Input is a newest-first window as the core returned it; the ordering is
/// re-established here because the core orders by `sent_at_ms` only and SQLite is
/// free to return equal timestamps in any order. Sorting by `(sent_at_ms, id)`
/// descending makes the `(beforeMs, beforeId)` cursor total and stable, which is
/// what a paged read needs and what the core alone does not provide.
final class HistoryWindow {
  const HistoryWindow._();

  /// Newest first, deterministically.
  static List<bridge.HistoryMessage> ordered(
    List<bridge.HistoryMessage> newestFirst,
  ) {
    final List<bridge.HistoryMessage> rows =
        List<bridge.HistoryMessage>.of(newestFirst);
    rows.sort((bridge.HistoryMessage a, bridge.HistoryMessage b) {
      final int byTime = b.sentAtMs.compareTo(a.sentAtMs);
      if (byTime != 0) return byTime;
      return b.id.compareTo(a.id);
    });
    return rows;
  }

  /// The newest [limit] lines of [conversationId].
  ///
  /// [requested] is how many rows were asked of the core, which is what makes
  /// "there may be older rows" answerable from a count — the answer
  /// `HistoryStore` explicitly permits, and the only one available here.
  ///
  /// The window is re-ordered before anything is read off it, for the same
  /// reason [older] does it: the core orders by `sent_at_ms` only, and reversing
  /// an order SQLite chose is how a page's order stops being a property of the
  /// type.
  static HistoryPageResult newest({
    required List<bridge.HistoryMessage> rows,
    required String conversationId,
    required int limit,
    required int requested,
  }) {
    final List<bridge.HistoryMessage> mine = ordered(rows)
        .where((bridge.HistoryMessage r) => r.conversationId == conversationId)
        .toList(growable: false);
    final List<bridge.HistoryMessage> head = mine.take(limit).toList();
    return HistoryPageResult(
      page: HistoryPage(
        messages: head.reversed.map(_toStored).toList(growable: false),
        // A full window means there is at least one row older than the page; so
        // does a filtered list longer than the page. Either is a count.
        hasMore: mine.length > limit || rows.length >= requested,
      ),
      reachedWindowStart: rows.length >= requested && mine.length <= limit,
    );
  }

  /// The [limit] lines strictly before the cursor, oldest first.
  ///
  /// The cursor is total: a row is older when its time is lower, or when the time
  /// is equal and its id sorts lower. Anything else would make a page depend on
  /// the order SQLite happened to return.
  static HistoryPageResult older({
    required List<bridge.HistoryMessage> rows,
    required String conversationId,
    required int beforeMs,
    required String beforeId,
    required int limit,
    required int requested,
  }) {
    final List<bridge.HistoryMessage> mine = ordered(rows)
        .where(
          (bridge.HistoryMessage r) =>
              r.conversationId == conversationId &&
              _isBefore(r.sentAtMs, r.id, beforeMs, beforeId),
        )
        .toList(growable: false);
    final List<bridge.HistoryMessage> head = mine.take(limit).toList();
    // The cursor row itself being absent from a full window is the only way to
    // tell "there is nothing older" from "there is something older that this
    // bridge cannot see".
    final bool cursorVisible = rows.any(
      (bridge.HistoryMessage r) =>
          r.conversationId == conversationId &&
          r.sentAtMs == beforeMs &&
          r.id == beforeId,
    );
    return HistoryPageResult(
      page: HistoryPage(
        messages: head.reversed.map(_toStored).toList(growable: false),
        hasMore: mine.length > limit,
      ),
      reachedWindowStart: rows.length >= requested && !cursorVisible,
    );
  }

  static bool _isBefore(int sentAtMs, String id, int beforeMs, String beforeId) {
    final int byTime = sentAtMs.compareTo(beforeMs);
    if (byTime != 0) return byTime < 0;
    return id.compareTo(beforeId) < 0;
  }

  /// The stored form of a bridge row.
  ///
  /// Direction is recovered from `sender_device_id`, which the core does store.
  /// **Delivery is not recoverable**: the encrypted record has no column for it,
  /// so a line persisted while still pending comes back as `sent`. That is
  /// reported to the core's owner rather than papered over; `StoredMessage`'s own
  /// comment calls the stored state the reason the column exists, so the honest
  /// answer today is that this column does not exist yet.
  static StoredMessage _toStored(bridge.HistoryMessage row) => StoredMessage(
    id: row.id,
    body: row.body,
    sentAt: DateTime.fromMillisecondsSinceEpoch(row.sentAtMs),
    direction: row.senderDeviceId == localSenderDeviceId
        ? MessageDirection.outgoing
        : MessageDirection.incoming,
    delivery: MessageDelivery.sent,
  );
}

/// What a failed `append_history` means to [HistoryStore.append].
enum HistoryAppendFailure {
  /// The id is already stored. `HistoryStore` requires this to be a silent no-op.
  duplicateId,

  /// Anything else. Rethrown: an empty or over-long id is a caller bug, and
  /// swallowing it would lose a line without a trace.
  rejected,
}

/// Classifies one failed `append_history`.
///
/// `mkvi_core` has no dedicated "duplicate" variant: `append` is a plain
/// `INSERT` into a table whose `id` is the primary key, so a repeat hits SQLite's
/// uniqueness constraint and arrives as `SecurityFailure_Database` carrying
/// SQLite's own text. The text is matched on the constant
/// `UNIQUE constraint failed`, which is the engine's message rather than
/// anything MKVI wrote, and which survived the round trip through this
/// repository's error enum unchanged.
///
/// **This is a debt, recorded rather than hidden:** the right fix is a
/// `SecurityError::DuplicateMessageId` in `mkvi_core`, which would make this a
/// type check instead of a string check.
HistoryAppendFailure classifyHistoryAppendFailure(Object failure) {
  if (failure is bridge.CoreFailure_Security) {
    final bridge.SecurityFailure inner = failure.failure;
    if (inner is bridge.SecurityFailure_Database &&
        inner.message.contains(_uniqueConstraintText)) {
      return HistoryAppendFailure.duplicateId;
    }
  }
  return HistoryAppendFailure.rejected;
}

/// SQLite's own wording for a primary-key collision.
const String _uniqueConstraintText = 'UNIQUE constraint failed';

/// The measured disagreement between what the layer asks to keep and what the
/// core keeps.
final class HistoryRetentionGap {
  const HistoryRetentionGap({
    required this.requestedLimit,
    required this.bridgeRowLimit,
  });

  /// [HistoryStore.retentionLimit]. What the layer expects to keep.
  final int requestedLimit;

  /// [historyWindowRows]. What one read of the core can return, and therefore
  /// what an implementation can reach at all.
  final int bridgeRowLimit;

  /// The number an implementation of this store can actually honour.
  int get enforcedLimit => math.min(requestedLimit, bridgeRowLimit);

  /// Whether the two agree. Measured as a value so a test can see it go red.
  bool get isAgreement => requestedLimit <= bridgeRowLimit;

  /// Turkish, and says what it means rather than what went wrong.
  String get messageTr =>
      'Son $enforcedLimit mesaj saklanıyor; katmanın istediği $requestedLimit.';

  @override
  String toString() =>
      'HistoryRetentionGap(requested: $requestedLimit, bridge: $bridgeRowLimit)';
}

/// The gap as it stands today, computed rather than written down.
final HistoryRetentionGap historyRetentionGap = HistoryRetentionGap(
  requestedLimit: HistoryStore.retentionLimit,
  bridgeRowLimit: historyWindowRows,
);

/// Thrown by [RustHistoryStore.trimTo].
final class HistoryTrimUnsupported implements Exception {
  const HistoryTrimUnsupported(this.conversationId);

  final String conversationId;

  String get messageTr =>
      'Eski mesajlar temizlenemedi: şifreli geçmiş deposu henüz silmeyi '
      'desteklemiyor.';

  String get recoveryTr =>
      'Bu bir MKVI sınırı, bir hata değil. Yeni sürümde eski mesajlar '
      'otomatik temizlenecek.';

  @override
  String toString() =>
      'HistoryTrimUnsupported: $messageTr $recoveryTr ($conversationId)';
}

/// The local conversation log, backed by the Rust core.
final class RustHistoryStore implements HistoryStore {
  RustHistoryStore(this._core);

  final RustCore _core;

  /// How many pages were answered from the very start of the 500-row window,
  /// which is to say: how many times this store could not see whether anything
  /// older exists.
  ///
  /// A counter rather than a log line, because the only thing wrong with this
  /// situation is that it is invisible, and a number on the store is the one
  /// form of it that cannot be lost.
  int windowEdgePages = 0;

  /// How many rows a page asks the core for.
  static int rowsFor(int limit) {
    if (limit <= 0) return 1;
    return math.min(historyWindowRows, limit * historyConversationWindowFactor);
  }

  /// The retention disagreement, for a screen or a log line that wants to say it.
  HistoryRetentionGap get retentionGap => historyRetentionGap;

  @override
  Future<HistoryPage> loadNewest({
    required String conversationId,
    required int limit,
  }) async {
    final int requested = rowsFor(limit);
    final List<bridge.HistoryMessage> rows = await _read(requested);
    if (rows.isEmpty) return HistoryPage.none;
    final HistoryPageResult result = HistoryWindow.newest(
      rows: rows,
      conversationId: conversationId,
      limit: limit,
      requested: requested,
    );
    if (result.reachedWindowStart) windowEdgePages += 1;
    return result.page;
  }

  @override
  Future<HistoryPage> loadOlder({
    required String conversationId,
    required int beforeMs,
    required String beforeId,
    required int limit,
  }) async {
    final int requested = rowsFor(limit);
    final List<bridge.HistoryMessage> rows = await _read(requested);
    if (rows.isEmpty) return HistoryPage.none;
    final HistoryPageResult result = HistoryWindow.older(
      rows: rows,
      conversationId: conversationId,
      beforeMs: beforeMs,
      beforeId: beforeId,
      limit: limit,
      requested: requested,
    );
    if (result.reachedWindowStart) windowEdgePages += 1;
    return result.page;
  }

  @override
  Future<void> append({
    required String conversationId,
    required StoredMessage message,
  }) async {
    if (!_core.isAvailable) {
      throw RustCoreUnavailable(
        '${_core.unavailableMessageTr} ${_core.unavailableRecoveryTr}',
      );
    }
    try {
      await bridge.appendHistory(
        core: _core.requireCore(),
        message: bridge.HistoryMessage(
          id: message.id,
          conversationId: conversationId,
          senderDeviceId: message.senderDeviceId,
          sentAtMs: message.sentAtMs,
          body: message.body,
        ),
      );
    } on Object catch (failure) {
      // A repeat is not an error here. `history_store.dart:143-145` says a
      // retried send and a re-read of the timeline both land on this call, so
      // swallowing *this one* failure is contract conformance, not a lost error.
      // Everything else is rethrown untouched.
      if (classifyHistoryAppendFailure(failure) ==
          HistoryAppendFailure.duplicateId) {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> trimTo({
    required String conversationId,
    required int keep,
  }) async {
    if (!_core.isAvailable) {
      throw RustCoreUnavailable(
        '${_core.unavailableMessageTr} ${_core.unavailableRecoveryTr}',
      );
    }
    // Loud on purpose. There is no delete in the bridge and no `Core` call
    // behind it, so anything else would be a method that reports work it did
    // not do — and the layer's whole reason for `trimTo` is that an unbounded
    // log is a defect.
    throw HistoryTrimUnsupported(conversationId);
  }

  /// Reads the window, or answers "nothing" when there is no core.
  ///
  /// The empty-list answer is a real one: the core documents that an empty
  /// result means the history is genuinely empty, and an unreadable store is a
  /// [RustCoreUnavailable] the caller already knows about. Returning empty here
  /// keeps a missing library from turning into a "you have no messages" claim.
  Future<List<bridge.HistoryMessage>> _read(int limit) async {
    if (!_core.isAvailable) return const <bridge.HistoryMessage>[];
    return bridge.listHistory(core: _core.requireCore(), limit: limit);
  }
}
