/// File transfer, both directions, over the already-ported protocol half.
///
/// `PeerFileReceiver` decides *which* offers are admitted and accounts every
/// frame. This class owns the two things the receiver deliberately does not: the
/// bytes, and the disk. It is also the only place in the application that
/// creates or destroys a file, and it does so through [FileSink].
///
/// ## The four rules, and where each came from
///
/// 1. **Progress is monotonic and comes from bytes actually written.**
///    `peer-transport.ts` emitted `transferred: transfer.received` — the peer's
///    own running total — and `App.tsx` `trackTransfer` replaced the whole row
///    from the last event with no ordering guard:
///    `next[index] = { ...current[index], ...patch }`. Any event that arrived out
///    of order, or any sink that stored fewer bytes than it was handed, moved the
///    bar backwards and left a row that could read 90% at 100 bytes. Here the
///    only numbers that reach [TransferView.transferred] are the ones
///    [FileSink.write] and [OutgoingFileSource.read] return, and every write
///    passes through [_advance], which clamps.
/// 2. **Cancelling works from either side, and is idempotent.** `cancelFile` had
///    one defect: it removed the send *and* the receive under one id and then
///    unconditionally sent a `file-cancel`, so cancelling an already-finished
///    transfer told the peer its file had been cancelled. Here every teardown
///    path returns `false` for a transfer that is not live, and only a *local*
///    cancel puts a frame on the wire.
/// 3. **A refused transfer leaves nothing on disk.** `crates/mkvi_core/src/state.rs`
///    documents the bug this rule is written against — the cap was checked after
///    the file was created, so every rejected offer left a 0 byte file. So
///    [FileSink.open] is called in exactly one method, after every check that can
///    refuse has refused, and [FileSink.abort] runs on every path that is not
///    [FileSink.close]. A decline never opens a sink at all.
/// 4. **Two transfers of the same name do not collide.** Nothing in this layer
///    keys anything by name: a sink is opened per *transfer id* and returns the
///    path it chose, so the non-overwriting rule lives in one place — the
///    production sink, mirroring `unique_path` in
///    `crates/mkvi_core/src/files.rs` — instead of being re-implemented per caller.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/file_frame.dart';
import 'package:mkvi/core/protocol/file_transfer.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/peer_protocol_exception.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';
import 'package:mkvi/core/protocol/transfer_id.dart';

import 'chat_channel.dart';
import 'chat_messages.dart';
import 'file_sink.dart';
import 'transfer_view.dart';

/// What happened to one binary frame.
sealed class FrameOutcome {
  const FrameOutcome();
}

/// The frame was stored and the progress advanced.
final class FrameStored extends FrameOutcome {
  const FrameStored(this.progress);

  final TransferProgress progress;

  @override
  String toString() => 'FrameStored($progress)';
}

/// The frame was refused. [reason] is Turkish and the transfer was torn down
/// with nothing left on disk.
final class FrameRefused extends FrameOutcome {
  const FrameRefused(this.reason);

  final String reason;

  @override
  String toString() => 'FrameRefused($reason)';
}

/// The outcome of an admission decision.
sealed class OfferOutcome {
  const OfferOutcome();
}

/// The offer was admitted and is waiting for a decision. Nothing was opened.
final class OfferAwaitingDecision extends OfferOutcome {
  const OfferAwaitingDecision(this.file, this.view);

  final IncomingFile file;
  final TransferView view;

  @override
  String toString() => 'OfferAwaitingDecision(${view.name})';
}

/// The offer was auto-declined, [reason] went to the peer and nothing was
/// created.
final class OfferAutoDeclined extends OfferOutcome {
  const OfferAutoDeclined(this.id, this.reason);

  final String id;
  final String reason;

  @override
  String toString() => 'OfferAutoDeclined($id, $reason)';
}

/// The outcome of a user decision on an announced offer.
sealed class DecisionOutcome {
  const DecisionOutcome();
}

/// The transfer is now receiving. [path] is the destination the sink chose.
final class DecisionAccepted extends DecisionOutcome {
  const DecisionAccepted(this.path);

  final String path;

  @override
  String toString() => 'DecisionAccepted($path)';
}

/// The decision was refused or the transfer was already gone. [reason] is
/// Turkish; the peer has been told wherever it had to be told.
final class DecisionRefused extends DecisionOutcome {
  const DecisionRefused(this.reason);

  final String reason;

  @override
  String toString() => 'DecisionRefused($reason)';
}

/// The outcome of an outgoing offer.
sealed class SendFileOutcome {
  const SendFileOutcome();
}

/// The offer is on the wire. [view] is the row to show.
final class FileOffered extends SendFileOutcome {
  const FileOffered(this.view);

  final TransferView view;

  @override
  String toString() => 'FileOffered(${view.name})';
}

/// Nothing was offered and nothing was created.
final class SendFileRefused extends SendFileOutcome {
  const SendFileRefused(this.reason);

  final String reason;

  @override
  String toString() => 'SendFileRefused($reason)';
}

/// Runs every file transfer, incoming and outgoing, on one stream of views.
final class TransferCoordinator {
  /// The named parameters are `channel`, `sink` and `receiver`; they are written
  /// as initialising formals of the private fields so there is exactly one place
  /// where each dependency is bound.
  TransferCoordinator({
    required this._channel,
    required this._sink,
    required this._receiver,
    String Function()? idFactory,
    int maxVisibleTransfers = defaultMaxVisibleTransfers,
    int maxOutgoing = defaultMaxOutgoing,
  }) : _idFactory = idFactory ?? randomTransferId,
       _maxVisibleTransfers = maxVisibleTransfers,
       _maxOutgoing = maxOutgoing {
    if (maxVisibleTransfers < 1) {
      throw ArgumentError.value(
        maxVisibleTransfers,
        'maxVisibleTransfers',
        'must be at least 1',
      );
    }
    if (maxOutgoing < 1) {
      throw ArgumentError.value(
        maxOutgoing,
        'maxOutgoing',
        'must be at least 1',
      );
    }
    // Live rows are never evicted from the visible list, so a visible list that
    // cannot hold every live transfer would have to refuse the newest one. The
    // bound is therefore only meaningful if it can hold all of them, and saying
    // so at construction beats growing a list that quietly ignores its own cap.
    if (maxVisibleTransfers <
        maxOutgoing + PeerProtocol.maxConcurrentReceives) {
      throw ArgumentError.value(
        maxVisibleTransfers,
        'maxVisibleTransfers',
        'must hold every live transfer '
            '($maxOutgoing outgoing + ${PeerProtocol.maxConcurrentReceives} incoming)',
      );
    }
  }

  /// How many rows the transfer list keeps.
  ///
  /// The original had `const [transfers, setTransfers] = useState([])` and only
  /// ever appended, so a session that sent a few hundred files showed a list
  /// nobody could scroll. When the bound is reached the oldest **terminal** row
  /// goes, and a live transfer is never evicted — an evicted live row is a
  /// transfer the user can no longer cancel.
  static const int defaultMaxVisibleTransfers = 32;

  /// How many outgoing files may be offered at once.
  static const int defaultMaxOutgoing = 4;

  final ChatChannelBinding _channel;
  final FileSink _sink;
  final PeerFileReceiver _receiver;
  final String Function() _idFactory;
  final int _maxVisibleTransfers;
  final int _maxOutgoing;

  final Map<String, _Incoming> _incoming = <String, _Incoming>{};
  final Map<String, _Outgoing> _outgoing = <String, _Outgoing>{};
  final Map<String, TransferView> _views = <String, TransferView>{};
  final List<String> _order = <String>[];

  final StreamController<TransferView> _changes =
      StreamController<TransferView>.broadcast();

  bool _disposed = false;

  /// Every row, oldest first. Unmodifiable, and at most
  /// [maxVisibleTransfers] long.
  List<TransferView> get views =>
      List<TransferView>.unmodifiable(_order.map((String id) => _views[id]!));

  /// The rows that are still moving.
  List<TransferView> get liveViews => views
      .where((TransferView v) => v.phase == TransferPhase.active)
      .toList(growable: false);

  /// The row stream. A surface listens to this; it never polls.
  Stream<TransferView> get changes => _changes.stream;

  TransferView? viewOf(String id) => _views[id];

  /// What the *peer* claims to have sent for [id], in bytes.
  ///
  /// Exposed for diagnostics only. It is deliberately never what a row renders:
  /// see [FileSink.write].
  int claimedBytesOf(String id) => _incoming[id]?.claimed ?? 0;

  // -----------------------------------------------------------------------
  // Incoming
  // -----------------------------------------------------------------------

  /// The peer announced a file. TS: the `file-offer` case of `receiveControl`.
  ///
  /// The size cap is checked **here**, before the offer is admitted, so an
  /// over-cap announcement never becomes a pending transfer at all. That ordering
  /// is the whole point of the 0-byte-file fix: refuse first, create nothing.
  ///
  /// Nothing is opened. A transfer the user is about to decline must not have a
  /// file, a handle or a name yet.
  OfferOutcome onFileOffer(FileOfferMessage message) {
    if (_disposed) {
      return OfferAutoDeclined(message.id, ChatMessages.sendFailed);
    }
    if (message.size <= 0 || message.size > PeerProtocol.maxFileBytes) {
      // The cap comes from `PeerProtocol`, and the Turkish text that says so is
      // formatted from that same constant — there is no "512" written twice.
      return _decline(message.id, ChatMessages.fileOverCap());
    }
    if (_listIsFull()) {
      return _decline(message.id, ChatMessages.tooManyTransfers());
    }
    final FileOfferAdmission admission = _receiver.offer(message);
    switch (admission) {
      case FileOfferRefused(:final String id, :final String reason):
        return _decline(id, reason);
      case FileOfferAccepted(:final IncomingFile file):
        _incoming[file.id] = _Incoming(file);
        return OfferAwaitingDecision(
          file,
          _publish(
            TransferView(
              id: file.id,
              name: file.name,
              direction: TransferDirection.receive,
              phase: TransferPhase.offered,
              transferred: 0,
              total: file.size,
              detail: null,
            ),
          ),
        );
    }
  }

  /// The user accepted an announced offer. TS: `acceptFile`.
  ///
  /// The one and only [FileSink.open] call in the application.
  Future<DecisionOutcome> accept(String id) async {
    final _Incoming? record = _incoming[id];
    if (record == null) {
      return const DecisionRefused(PeerProtocol.transferNotFound);
    }
    final String? already = record.sinkPath;
    if (already != null) {
      // Accepting twice is a no-op, not a second file — TS had the same
      // `if (transfer.accepted) return;`.
      return DecisionAccepted(already);
    }
    final String path;
    try {
      path = await _sink.open(
        transferId: id,
        name: record.file.name,
        mime: record.file.mime,
      );
    } on FileSinkException {
      // The destination could not be created, so nothing exists to clean up and
      // the peer is told why rather than left waiting for a file-complete that
      // will never come.
      _teardown(id, record, TransferPhase.failed);
      _update(
        id,
        (TransferView v) => v.copyWith(
          phase: TransferPhase.failed,
          detail: PeerProtocol.sinkOpenFailed,
        ),
      );
      _send(
        FileDeclineMessage(
          id: id,
          reason: safeReason(PeerProtocol.sinkOpenFailed),
        ),
      );
      return const DecisionRefused(PeerProtocol.sinkOpenFailed);
    }
    // TS: `if (this.receives.get(id) !== transfer) { void sink.abort(id); return; }`.
    // A cancel or a decline that landed while the open was in flight has already
    // torn the transfer down and already scheduled its abort; the file that was
    // just created is that abort's business, so the same scheduled chain is
    // awaited rather than a second abort being issued for the same id.
    if (!identical(_incoming[id], record) || record.tornDown) {
      await record.aborting;
      return const DecisionRefused(ChatMessages.remoteCancelled);
    }
    record.sinkPath = path;
    _receiver.accept(id);
    record.phase = TransferPhase.active;
    // `detail` is cleared, not set to the path: TS put the saved path in
    // `detail` only on `file-complete`, and a destination path under a running
    // progress bar is a string the user can do nothing with yet.
    _update(
      id,
      (TransferView v) =>
          v.copyWith(phase: TransferPhase.active, clearDetail: true),
    );
    _send(FileAcceptMessage(id: id));
    return DecisionAccepted(path);
  }

  /// The user declined an announced offer. TS: `declineFile`.
  ///
  /// **Opens nothing.** A declined transfer is refused before a file exists, and
  /// if one somehow does — an accept that raced this call — [FileSink.abort]
  /// removes it, because that is the 0-byte-file defect with a different name.
  DecisionOutcome decline(String id, {String? reason}) {
    final _Incoming? record = _incoming[id];
    if (record == null) {
      return const DecisionRefused(PeerProtocol.transferNotFound);
    }
    final String text = safeReason(
      reason != null && reason.trim().isNotEmpty
          ? reason
          : PeerProtocol.defaultFileDeclineReason,
    );
    _teardown(id, record, TransferPhase.failed);
    _update(
      id,
      (TransferView v) => v.copyWith(phase: TransferPhase.failed, detail: text),
    );
    _send(FileDeclineMessage(id: id, reason: text));
    return DecisionRefused(text);
  }

  /// Takes one binary frame off the wire. TS: `receiveFrame` plus the flush.
  ///
  /// The frame is decoded twice on purpose. `PeerFileReceiver.addFrame` accounts
  /// the payload but deliberately does not hand it back — buffering it there
  /// would put the whole file in the protocol layer's heap. [FileFrame.decode]
  /// is pure, so decoding again here cannot disagree with the accounting it just
  /// performed.
  Future<FrameOutcome> onFrame(List<int> frame) async {
    if (_disposed) return const FrameRefused(ChatMessages.sendFailed);
    final FileFrame decoded;
    try {
      decoded = FileFrame.decode(frame);
    } on PeerProtocolException catch (error) {
      return FrameRefused(error.message);
    }
    final _Incoming? record = _incoming[decoded.id];
    if (record == null) {
      // TS: `if (!transfer || !transfer.accepted) throw … unauthorizedFileData`.
      return const FrameRefused(PeerProtocol.unauthorizedFileData);
    }
    final TransferProgress claimed;
    try {
      claimed = _receiver.addFrame(frame);
    } on PeerProtocolException catch (error) {
      _failFrame(decoded.id, record, error.message);
      return FrameRefused(error.message);
    }
    // The claimed number is the *peer's* opinion of how much it sent. It is
    // recorded for diagnostics and never rendered; the bar moves by what the
    // sink reports it stored.
    record.claimed = claimed.transferred;

    // Writes are chained per transfer so an abort always runs after the last
    // write, exactly like TS's `transfer.writes` promise chain. Without the chain
    // a cancel that races a write deletes the file and then lets the write
    // recreate it.
    record.writes = record.writes.then((_) => _storeChunk(record, decoded));
    await record.writes;
    if (record.tornDown) {
      return const FrameRefused(PeerProtocol.transferNotFound);
    }
    return FrameStored(
      TransferProgress(
        id: decoded.id,
        name: record.file.name,
        direction: TransferDirection.receive,
        transferred: record.written,
        total: record.file.size,
      ),
    );
  }

  /// The peer says it is done sending. TS: `finishReceive`.
  Future<FrameOutcome> onComplete(String id) async {
    final _Incoming? record = _incoming[id];
    if (record == null || record.tornDown) {
      // Idempotent: a `file-complete` for a transfer that is already settled —
      // cancelled, or the frame arriving twice — is not an error and must not
      // touch the disk.
      return const FrameRefused(PeerProtocol.transferNotFound);
    }
    await record.writes;
    if (record.tornDown) {
      return const FrameRefused(PeerProtocol.transferNotFound);
    }
    // Two independent completeness checks, and both have to pass. The receiver
    // knows whether the *peer* sent what it declared; the sink knows whether
    // *storage* took it. A transfer that the peer completed but the disk only
    // partly accepted is not a finished file, and closing it would leave a short
    // file on disk with a "Tamamlandı" row above it.
    if (!_receiver.isComplete(id) || record.written < record.file.size) {
      _failFrame(id, record, PeerProtocol.transferIncomplete);
      await record.aborting;
      return const FrameRefused(PeerProtocol.transferIncomplete);
    }
    _incoming.remove(id);
    _receiver.drop(id);
    final String path;
    try {
      path = await _sink.close(transferId: id);
    } on FileSinkException {
      await _abortQuietly(id);
      _update(
        id,
        (TransferView v) => v.copyWith(detail: PeerProtocol.transferIncomplete),
      );
      return const FrameRefused(PeerProtocol.transferIncomplete);
    }
    _update(
      id,
      (TransferView v) => v.copyWith(
        phase: TransferPhase.done,
        transferred: record.file.size,
        total: record.file.size,
        detail: path,
      ),
    );
    return FrameStored(
      TransferProgress(
        id: id,
        name: record.file.name,
        direction: TransferDirection.receive,
        transferred: record.file.size,
        total: record.file.size,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Outgoing
  // -----------------------------------------------------------------------

  /// Offers a file. TS: `sendFile`.
  ///
  /// No bytes move until the peer accepts. The size is validated against
  /// [PeerProtocol.maxFileBytes] here, so a 600 MB file never becomes a row.
  SendFileOutcome offerFile(OutgoingFileSource source) {
    if (_disposed) return const SendFileRefused(ChatMessages.sendFailed);
    if (source.size <= 0 || source.size > PeerProtocol.maxFileBytes) {
      return SendFileRefused(ChatMessages.fileSizeOutOfRange());
    }
    if (_outgoing.length >= _maxOutgoing || _listIsFull()) {
      return SendFileRefused(ChatMessages.tooManyTransfers());
    }
    final String id = _idFactory();
    final String name = safeName(source.name);
    _outgoing[id] = _Outgoing(id: id, source: source, name: name);
    final TransferView view = _publish(
      TransferView(
        id: id,
        name: name,
        direction: TransferDirection.send,
        phase: TransferPhase.offered,
        transferred: 0,
        total: source.size,
        detail: null,
      ),
    );
    final SendOutcome outcome = _send(
      FileOfferMessage(
        id: id,
        name: name,
        mime: safeMime(source.mime),
        size: source.size,
      ),
    );
    if (outcome is ChannelUnavailable) {
      // TS rejected the `sendFile` promise and left the row `active` at 0% for
      // ever, because the row was only ever patched by progress events that
      // could not arrive. There is no offer on the wire, so the record goes and
      // the caller is told why.
      _outgoing.remove(id);
      _update(
        id,
        (TransferView v) =>
            v.copyWith(phase: TransferPhase.failed, detail: outcome.reason),
      );
      return SendFileRefused(outcome.reason);
    }
    return FileOffered(view);
  }

  /// The peer accepted our offer. TS: the `file-accept` case and `streamFile`.
  Future<void> onAccept(String id) async {
    final _Outgoing? record = _outgoing[id];
    // A second `file-accept` for a live id is a retransmission, not a second
    // transfer: streaming it again would send the file twice.
    if (record == null || record.started) return;
    record.started = true;
    record.phase = TransferPhase.active;
    _update(
      id,
      (TransferView v) =>
          v.copyWith(phase: TransferPhase.active, clearDetail: true),
    );
    await _stream(record);
  }

  /// Streams one outgoing file, one frame at a time.
  ///
  /// Cancellation is checked before every chunk, which is what makes a cancel
  /// effective at chunk granularity: the peer is told with a `file-cancel` and no
  /// further bytes of this file are ever handed over.
  Future<void> _stream(_Outgoing record) async {
    final int total = record.source.size;
    int offset = 0;
    while (offset < total) {
      if (record.cancelled || !_outgoing.containsKey(record.id)) {
        _finishCancelled(record);
        return;
      }
      final int remaining = total - offset;
      final int want = remaining < PeerProtocol.fileChunkBytes
          ? remaining
          : PeerProtocol.fileChunkBytes;
      final List<int> payload = await record.source.read(
        offset: offset,
        length: want,
      );
      if (payload.isEmpty) break;
      // A source that hands back more than it was asked for is clamped, not
      // trusted: the frame is the wire contract and it cannot exceed the chunk
      // the receiver is prepared for.
      final Uint8List chunk = payload.length > want
          ? Uint8List.fromList(payload.sublist(0, want))
          : Uint8List.fromList(payload);
      final SendOutcome outcome = _sendFrame(
        FileFrame(id: record.id, payload: chunk),
      );
      if (outcome is ChannelUnavailable) {
        _outgoing.remove(record.id);
        _update(
          record.id,
          (TransferView v) =>
              v.copyWith(phase: TransferPhase.failed, detail: outcome.reason),
        );
        return;
      }
      offset += chunk.length;
      // Bytes this device actually read off its own disk: the same rule as the
      // receiving side, so a peer that walks its progress backwards is answered
      // with a row that does not.
      _advance(record.id, offset);
    }
    if (record.cancelled || !_outgoing.containsKey(record.id)) return;
    _outgoing.remove(record.id);
    record.phase = TransferPhase.done;
    _update(
      record.id,
      (TransferView v) => v.copyWith(
        phase: TransferPhase.done,
        transferred: total,
        total: total,
        clearDetail: true,
      ),
    );
    _send(FileCompleteMessage(id: record.id));
  }

  void _finishCancelled(_Outgoing record) {
    _outgoing.remove(record.id);
    record.phase = TransferPhase.cancelled;
    _update(
      record.id,
      (TransferView v) => v.copyWith(phase: TransferPhase.cancelled),
    );
  }

  // -----------------------------------------------------------------------
  // The peer's decisions
  // -----------------------------------------------------------------------

  /// The peer refused our offer. TS: the `file-decline` case.
  ///
  /// [reason] is the peer's own text and is shown verbatim, which is the point:
  /// "yerim kalmadı" and "bu tür dosyaları kabul etmiyorum" are different problems
  /// and the sender can only answer one of them if it is told.
  bool onDecline(String id, String? reason) {
    final _Outgoing? record = _outgoing[id];
    if (record == null) return false;
    _outgoing.remove(id);
    _update(
      id,
      (TransferView v) => v.copyWith(
        phase: TransferPhase.failed,
        detail: reason == null || reason.isEmpty
            ? ChatMessages.offerDeclined
            : reason,
      ),
    );
    return true;
  }

  /// The peer cancelled one of its transfers. TS: the `file-cancel` case.
  ///
  /// Honoured unconditionally and answered with silence: a `file-cancel` is not
  /// acknowledged, because acknowledging it would race the peer's own teardown.
  bool onPeerCancel(String id, String? reason) {
    final _Incoming? incoming = _incoming[id];
    if (incoming != null) {
      _teardown(id, incoming, TransferPhase.cancelled);
      _update(
        id,
        (TransferView v) => v.copyWith(
          phase: TransferPhase.cancelled,
          detail: reason == null || reason.isEmpty
              ? PeerProtocol.defaultFileCancelReason
              : reason,
        ),
      );
      return true;
    }
    final _Outgoing? outgoing = _outgoing[id];
    if (outgoing == null) return false;
    _outgoing.remove(id);
    outgoing.cancelled = true;
    _update(
      id,
      (TransferView v) => v.copyWith(
        phase: TransferPhase.cancelled,
        detail: reason == null || reason.isEmpty
            ? ChatMessages.remoteCancelled
            : reason,
      ),
    );
    return true;
  }

  /// Stops a transfer from this side. TS: `cancelFile`.
  ///
  /// Idempotent: a second call, or a call on a transfer that already finished,
  /// does nothing and says so by returning `false`. Only a *local* cancel puts a
  /// `file-cancel` on the wire — cancelling an already-finished transfer must
  /// not tell the peer its file was cancelled, which is the bug
  /// `cancelFile`'s unconditional `sendControl` had.
  bool cancel(String id, {String? reason}) {
    final String text = safeReason(
      reason != null && reason.trim().isNotEmpty
          ? reason
          : PeerProtocol.defaultFileCancelReason,
    );
    final _Incoming? incoming = _incoming[id];
    if (incoming != null) {
      _teardown(id, incoming, TransferPhase.cancelled);
      _update(
        id,
        (TransferView v) => v.copyWith(
          phase: TransferPhase.cancelled,
          detail: reason ?? PeerProtocol.defaultFileCancelReason,
        ),
      );
      _send(FileCancelMessage(id: id, reason: text));
      return true;
    }
    final _Outgoing? outgoing = _outgoing[id];
    if (outgoing == null) return false;
    _outgoing.remove(id);
    outgoing.cancelled = true;
    _update(
      id,
      (TransferView v) => v.copyWith(
        phase: TransferPhase.cancelled,
        detail: reason ?? PeerProtocol.defaultFileCancelReason,
      ),
    );
    _send(FileCancelMessage(id: id, reason: text));
    return true;
  }

  // -----------------------------------------------------------------------
  // Plumbing
  // -----------------------------------------------------------------------

  /// Writes one chunk and advances the row by what was *stored*.
  ///
  /// This runs as a step of the per-transfer write chain, so it must never await
  /// that chain — not even to report its own failure. [sinkOpenFailed] is reused
  /// as the reason because "the disk would not take it" and "the disk would not
  /// open it" are the same sentence to the user, and both mean *your storage*
  /// rather than *the peer*.
  Future<void> _storeChunk(_Incoming record, FileFrame frame) async {
    if (record.tornDown || record.sinkPath == null) return;
    final int written;
    try {
      written = await _sink.write(transferId: frame.id, chunk: frame.payload);
    } on FileSinkException {
      _failFrame(frame.id, record, PeerProtocol.sinkOpenFailed);
      return;
    }
    if (written <= 0) return;
    record.written += written;
    if (record.tornDown) return;
    _advance(frame.id, record.written);
  }

  /// Moves a row's `transferred` to [candidate], never backwards.
  ///
  /// This is the one place progress is written. Clamping here — rather than
  /// trusting each source — is what makes the row monotonic against a peer's
  /// out-of-order frame, a short write, and a peer that cancels and re-announces
  /// the same id with a smaller size.
  void _advance(String id, int candidate) {
    final TransferView? view = _views[id];
    if (view == null) return;
    final int total = view.total;
    final int ceiling = total > 0 && candidate > total ? total : candidate;
    if (ceiling <= view.transferred) return;
    _update(id, (TransferView v) => v.copyWith(transferred: ceiling));
  }

  /// A failure that has to remove the partial file.
  ///
  /// Deliberately **not** `async`, and deliberately does not await the write
  /// chain. It is reached from two places: `onComplete`, which has already awaited
  /// the chain, and `_storeChunk`, which is *itself a step of* that chain.
  /// Awaiting a chain from inside one of its own steps is a deadlock that no
  /// timeout surfaces as anything but a hung transfer — the row would sit at its
  /// last percentage for ever and the partial file would stay on disk, which is
  /// the exact symptom the teardown exists to prevent. The abort is therefore
  /// *scheduled* on the chain and the row is updated straight away.
  void _failFrame(String id, _Incoming record, String reason) {
    _teardown(id, record, TransferPhase.failed);
    _update(
      id,
      (TransferView v) =>
          v.copyWith(phase: TransferPhase.failed, detail: reason),
    );
  }

  /// Forgets an incoming transfer and removes anything it left on disk.
  ///
  /// [FileSink.abort] is chained behind the outstanding writes, so a cancel that
  /// races a write cannot delete the file and then let the write recreate it.
  ///
  /// The chain it produces is left in `record.aborting` rather than reassigned
  /// over `record.writes`, for the reason [_failFrame] explains. A caller that
  /// needs the file *gone* — a test, or a teardown that closes the session —
  /// awaits `record.aborting`.
  void _teardown(String id, _Incoming record, TransferPhase phase) {
    if (record.tornDown) return;
    record.tornDown = true;
    record.phase = phase;
    _incoming.remove(id);
    _receiver.drop(id);
    record.aborting = record.writes.then((_) => _abortQuietly(id));
  }

  Future<void> _abortQuietly(String id) async {
    try {
      await _sink.abort(transferId: id);
    } on FileSinkException {
      // A storage layer that cannot delete its own partial file is already
      // broken; a throw here would poison the write chain that is trying to clean
      // up, and there is nothing else this layer can do about it.
    }
  }

  /// Sends an auto-decline and reports it. Nothing was created.
  OfferOutcome _decline(String id, String reason) {
    _send(FileDeclineMessage(id: id, reason: safeReason(reason)));
    return OfferAutoDeclined(id, reason);
  }

  SendOutcome _send(PeerControlMessage message) => _channel.send(message);

  SendOutcome _sendFrame(FileFrame frame) => _channel.sendFrame(frame);

  /// Whether a new row would overflow the visible list with nothing evictable.
  bool _listIsFull() {
    if (_views.length < _maxVisibleTransfers) return false;
    return !_order.any((String id) => _views[id]!.phase.isTerminal);
  }

  /// Publishes a row and applies the visible bound.
  TransferView _publish(TransferView view) {
    _views[view.id] = view;
    _order.add(view.id);
    _trim();
    if (!_disposed && !_changes.isClosed) _changes.add(view);
    return view;
  }

  void _update(String id, TransferView Function(TransferView) change) {
    final TransferView? current = _views[id];
    if (current == null) return;
    final TransferView next = change(current);
    if (next == current) return;
    _views[id] = next;
    if (!_disposed && !_changes.isClosed) _changes.add(next);
  }

  /// Drops the oldest terminal rows until the list fits.
  ///
  /// Live rows are never dropped: an evicted live row is a transfer the user can
  /// no longer see and therefore no longer cancel. When every row is live the
  /// list is already at its bound, and [_listIsFull] has refused the new one.
  void _trim() {
    while (_order.length > _maxVisibleTransfers) {
      int victim = -1;
      for (int i = 0; i < _order.length; i += 1) {
        if (_views[_order[i]]!.phase.isTerminal) {
          victim = i;
          break;
        }
      }
      if (victim < 0) return;
      _views.remove(_order.removeAt(victim));
    }
  }

  /// Tears every live transfer down and waits for the disk to be clean.
  ///
  /// The aborts are awaited, so a caller that has disposed this coordinator can
  /// rely on there being no partial file left behind — a session that quits with
  /// a half-written download on disk is how a folder fills with truncated files
  /// that look finished.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final List<Future<void>> pending = <Future<void>>[];
    for (final _Incoming record in _incoming.values.toList(growable: false)) {
      _teardown(record.file.id, record, TransferPhase.cancelled);
      pending.add(record.aborting);
    }
    for (final _Outgoing record in _outgoing.values.toList(growable: false)) {
      record.cancelled = true;
    }
    _incoming.clear();
    _outgoing.clear();
    await Future.wait(pending);
    await _changes.close();
  }
}

/// Live state of one incoming transfer.
final class _Incoming {
  _Incoming(this.file);

  final IncomingFile file;

  /// Set by [FileSink.open]. `null` until the user accepted, and the reason a
  /// declined transfer has nothing to clean up.
  String? sinkPath;

  /// Bytes the sink reported written. The only number that becomes progress.
  int written = 0;

  /// Bytes the *peer* claims to have sent. For diagnostics, never rendered.
  int claimed = 0;

  TransferPhase phase = TransferPhase.offered;

  /// Set by every teardown, so a write that was already in flight can notice.
  bool tornDown = false;

  /// The per-transfer write chain. TS: `transfer.writes`.
  Future<void> writes = Future<void>.value();

  /// The abort [TransferCoordinator._teardown] scheduled behind [writes]. Kept
  /// apart from [writes] so nothing can await the chain it is standing in.
  Future<void> aborting = Future<void>.value();
}

/// Live state of one outgoing transfer.
final class _Outgoing {
  _Outgoing({required this.id, required this.source, required this.name});

  final String id;
  final OutgoingFileSource source;

  /// The `safeName` form, which is what the peer was told and what the row shows.
  final String name;

  TransferPhase phase = TransferPhase.offered;
  bool cancelled = false;

  /// Guards against a second `file-accept` restarting the stream.
  bool started = false;
}
