import 'control_message.dart';
import 'file_frame.dart';
import 'peer_protocol.dart';
import 'peer_protocol_exception.dart';

/// A file the peer announced, after validation.
final class IncomingFile {
  const IncomingFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
  });

  final String id;

  /// Already run through `safeName` by `parseControl`, so it cannot contain a
  /// path separator.
  final String name;

  /// Already run through `safeMime` by `parseControl`.
  final String mime;

  /// Declared size, guaranteed `0 < size <= PeerProtocol.maxFileBytes`.
  final int size;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IncomingFile &&
          other.id == id &&
          other.name == name &&
          other.mime == mime &&
          other.size == size;

  @override
  int get hashCode => Object.hash(id, name, mime, size);

  @override
  String toString() =>
      'IncomingFile(id: $id, name: $name, mime: $mime, size: $size)';
}

/// Which way a transfer is moving.
enum TransferDirection { send, receive }

/// A progress tick. `name` travels with every tick so the UI can label a
/// transfer it never opened.
final class TransferProgress {
  const TransferProgress({
    required this.id,
    required this.name,
    required this.direction,
    required this.transferred,
    required this.total,
  });

  final String id;
  final String name;
  final TransferDirection direction;
  final int transferred;
  final int total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransferProgress &&
          other.id == id &&
          other.name == name &&
          other.direction == direction &&
          other.transferred == transferred &&
          other.total == total;

  @override
  int get hashCode => Object.hash(id, name, direction, transferred, total);

  @override
  String toString() =>
      'TransferProgress($direction $id $transferred/$total "$name")';
}

/// What the receiver decided to do with an announced offer.
sealed class FileOfferAdmission {
  const FileOfferAdmission();
}

final class FileOfferAccepted extends FileOfferAdmission {
  const FileOfferAccepted(this.file);

  final IncomingFile file;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileOfferAccepted && other.file == file;

  @override
  int get hashCode => file.hashCode;

  @override
  String toString() => 'FileOfferAccepted($file)';
}

/// The offer must be auto-declined; [reason] is the Turkish text the transport
/// puts in the `file-decline` it sends back.
final class FileOfferRefused extends FileOfferAdmission {
  const FileOfferRefused(this.id, this.reason);

  final String id;
  final String reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileOfferRefused && other.id == id && other.reason == reason;

  @override
  int get hashCode => Object.hash(id, reason);

  @override
  String toString() => 'FileOfferRefused($id, $reason)';
}

/// The protocol half of an incoming file transfer: which offers are admitted,
/// when a frame is allowed to land, and how many bytes have arrived.
///
/// Deliberately **not** here: the chunk buffer, the flush batching and the disk
/// sink. Those need a file handle and a scheduler, they belong to the transport,
/// and keeping them out is what lets this whole layer be tested with no
/// hardware at all.
final class PeerFileReceiver {
  final Map<String, _Receive> _receives = <String, _Receive>{};

  /// How many offers are waiting, accepted or not. This is the number the
  /// [PeerProtocol.maxConcurrentReceives] guard is checked against.
  int get pendingCount => _receives.length;

  /// The ids currently being received, in arrival order.
  List<String> get pendingIds => List<String>.unmodifiable(_receives.keys);

  bool contains(String id) => _receives.containsKey(id);

  IncomingFile? offerOf(String id) => _receives[id]?.file;

  /// Whether the user has already accepted this transfer; frames for a transfer
  /// that is merely announced are refused.
  bool isAccepted(String id) => _receives[id]?.accepted ?? false;

  /// Bytes accepted so far, as accounted by this receiver and not as asserted by
  /// the peer.
  int receivedBytesOf(String id) => _receives[id]?.received ?? 0;

  /// Admits an announced file, or refuses it when too many are already pending.
  ///
  /// A refused offer is *not* stored: it is answered with
  /// [PeerProtocol.tooManyPendingTransfers] and forgotten, so a peer cannot fill
  /// the pending table with offers that will never be accepted.
  ///
  /// **Deliberately not mirrored:** a peer that re-announces an id that is
  /// already being received must not be able to silently replace it — resetting
  /// `received` to 0 and `accepted` to false mid-transfer — nor slip past the
  /// capacity guard by overwriting an existing entry instead of adding one.
  /// Otherwise this is a denial-of-service handed to the peer for free:
  /// re-announcing the same id forever keeps the slot count at one while the
  /// bytes on disk keep growing. This port refuses the repeat instead.
  FileOfferAdmission offer(FileOfferMessage message) {
    if (_receives.length >= PeerProtocol.maxConcurrentReceives) {
      return FileOfferRefused(message.id, PeerProtocol.tooManyPendingTransfers);
    }
    // A re-announcement of a live transfer is not a new transfer. Ignoring it
    // keeps the progress and the acceptance the user already granted.
    if (_receives.containsKey(message.id)) {
      return FileOfferRefused(message.id, PeerProtocol.transferAlreadyReceiving);
    }
    final IncomingFile file = IncomingFile(
      id: message.id,
      name: message.name,
      mime: message.mime,
      size: message.size,
    );
    _receives[message.id] = _Receive(file: file);
    return FileOfferAccepted(file);
  }

  /// Marks an announced transfer as accepted so its frames are allowed in.
  ///
  /// Opening the destination is the transport's job; once it succeeds it calls
  /// this. The order matters: the sink is opened *before* the offer is marked
  /// accepted, so a sink that refuses leaves the transfer unaccepted rather than
  /// accepted-but-undeliverable.
  void accept(String id) {
    final _Receive? transfer = _receives[id];
    if (transfer == null) {
      throw const PeerProtocolException(PeerProtocol.transferNotFound);
    }
    // `if (transfer.accepted) return;` — accepting twice is a no-op, not an error.
    transfer.accepted = true;
  }

  /// Validates and accounts one binary frame.
  ///
  /// The three rejections and their order are deliberate: a malformed frame,
  /// then a frame for a transfer that is not accepted, then a frame that would
  /// push the transfer past the size it declared. A peer that sends data for a
  /// transfer it was never granted is refused before its bytes are counted, and
  /// the size check runs last so the accounting is never touched by a frame that
  /// is going to be refused anyway.
  TransferProgress addFrame(List<int> frame) {
    final FileFrame decoded = FileFrame.decode(frame);
    final _Receive? transfer = _receives[decoded.id];
    if (transfer == null || !transfer.accepted) {
      throw const PeerProtocolException(PeerProtocol.unauthorizedFileData);
    }
    final int arriving = decoded.payloadLength;
    if (transfer.received + arriving > transfer.file.size) {
      throw const PeerProtocolException(PeerProtocol.fileSizeOverflow);
    }
    transfer.received += arriving;
    return TransferProgress(
      id: decoded.id,
      name: transfer.file.name,
      direction: TransferDirection.receive,
      transferred: transfer.received,
      total: transfer.file.size,
    );
  }

  /// Whether a transfer has received exactly the bytes it declared. Equality,
  /// not "at least": a transfer that received *more* than it declared has
  /// already been refused by [addFrame], so it can only be short.
  bool isComplete(String id) {
    final _Receive? transfer = _receives[id];
    return transfer != null && transfer.received == transfer.file.size;
  }

  /// Forgets a transfer. Deleting the partial file is the transport's job, so
  /// this only forgets the state; a caller that drops a transfer and keeps its
  /// file has leaked a partial download.
  bool drop(String id) => _receives.remove(id) != null;
}

final class _Receive {
  _Receive({required this.file});

  final IncomingFile file;
  int received = 0;
  bool accepted = false;
}
