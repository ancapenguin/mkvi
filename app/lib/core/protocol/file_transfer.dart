import 'control_message.dart';
import 'file_frame.dart';
import 'peer_protocol.dart';
import 'peer_protocol_exception.dart';

/// A file the peer announced. TS: the `IncomingFile` interface.
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

/// Which way a transfer is moving. TS: the `direction` of `file-progress`.
enum TransferDirection { send, receive }

/// A progress tick. `name` travels with every tick so the UI can label a
/// transfer it never opened. TS: the `file-progress` event.
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

/// What the receiver decided to do with an announced offer. TS: the `if` at the
/// top of the `file-offer` case of `receiveControl`.
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
/// TS: the offer branch of `receiveControl`, the frame guard in `receiveFrame`,
/// and the bookkeeping fields of `PendingReceive`.
///
/// Deliberately **not** here: the chunk buffer, the flush batching and the disk
/// sink. Those need a file handle and a scheduler, they belong to the transport,
/// and keeping them out is what lets this whole layer be tested with no
/// hardware — exactly as the TypeScript suite tested it with no data channel.
final class PeerFileReceiver {
  final Map<String, _Receive> _receives = <String, _Receive>{};

  /// How many offers are waiting, accepted or not. TS: `this.receives.size`.
  int get pendingCount => _receives.length;

  /// The ids currently being received, in arrival order.
  List<String> get pendingIds => List<String>.unmodifiable(_receives.keys);

  bool contains(String id) => _receives.containsKey(id);

  IncomingFile? offerOf(String id) => _receives[id]?.file;

  /// Whether the user has already accepted this transfer; frames for a transfer
  /// that is merely announced are refused.
  bool isAccepted(String id) => _receives[id]?.accepted ?? false;

  /// Bytes accepted so far. TS: `transfer.received`.
  int receivedBytesOf(String id) => _receives[id]?.received ?? 0;

  /// Admits an announced file, or refuses it when too many are already pending.
  ///
  /// TS: the `file-offer` case of `receiveControl`, whose capacity guard sends
  /// "Çok fazla bekleyen aktarım var." and *does not* store the offer.
  ///
  /// **Deliberately not mirrored:** the original writes the transfer with
  /// `Map.set`, so a peer that re-announces an id that is already being received
  /// silently replaces it — resetting `received` to 0 and `accepted` to false
  /// mid-transfer — and, because `set` overwrites rather than adds, never trips
  /// the capacity guard. That is a denial-of-service handed to the peer for free:
  /// re-announcing the same id forever keeps the slot count at one while the
  /// bytes on disk keep growing. The frozen 0.1.x line keeps the behaviour
  /// because its wire peers depend on it; this port refuses instead.
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
  /// TS: the tail of `acceptFile`, after the sink has been opened. Opening the
  /// destination is the transport's job; once it succeeds it calls this.
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
  /// TS: `receiveFrame`. The three rejections and their order are preserved:
  /// a malformed frame, then a frame for a transfer that is not accepted, then
  /// a frame that would push the transfer past the size it declared.
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

  /// Whether a transfer has received exactly the bytes it declared. TS: the
  /// `transfer.received !== transfer.size` check in `finishReceive`.
  bool isComplete(String id) {
    final _Receive? transfer = _receives[id];
    return transfer != null && transfer.received == transfer.file.size;
  }

  /// Forgets a transfer. TS: `dropReceive`, which also deletes the partial file;
  /// deleting a file is the transport's job, so this only forgets the state.
  bool drop(String id) => _receives.remove(id) != null;
}

final class _Receive {
  _Receive({required this.file});

  final IncomingFile file;
  int received = 0;
  bool accepted = false;
}
