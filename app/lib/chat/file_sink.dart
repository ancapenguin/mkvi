/// Where the bytes of an accepted file go, and where an outgoing file comes
/// from. Both are interfaces, both are fakeable with no disk and no platform.
///
/// ## The one thing this layer must never do
///
/// Open the destination itself. `crates/mkvi_core/src/state.rs` documents the
/// defect this port is written against:
///
/// > The concurrency cap is checked **before** the file is created. Creating
/// > first and capping afterwards leaves a 0 byte file behind for every rejected
/// > transfer, so a peer that keeps offering files fills the download folder with
/// > empty names.
///
/// In the browser build the same mistake was one line of React away:
/// `acceptFile` opened the sink *after* `MAX_CONCURRENT_RECEIVES` had already
/// admitted the offer, so an offer that was admitted and then declined by the
/// user left a handle and a name behind.
///
/// So [FileSink] has exactly four methods, and [TransferCoordinator] calls
/// [FileSink.open] in exactly one place — after every check that can refuse the
/// transfer has already refused it — and calls [FileSink.abort] on every path
/// that is not [FileSink.close]. Nothing in this package creates a file.
library;

/// A refusal from the storage layer. The message is Turkish because the storage
/// layer is *this application's* code, not a foreign bridge's.
final class FileSinkException implements Exception {
  const FileSinkException(this.message);

  final String message;

  @override
  String toString() => 'FileSinkException: $message';
}

/// Disk destination for one accepted transfer.
///
/// The contract, in the order the calls must happen:
///
/// 1. [open] creates the destination and returns the path it chose. It must
///    **never overwrite**: two transfers of `rapor.pdf` get two paths.
/// 2. [write] appends and returns **how many bytes it actually stored**. The
///    return value is the ground truth of this whole layer — a peer can claim
///    any payload it likes, and only this number becomes progress.
/// 3. [close] flushes and returns the saved path, or throws. A file that is
///    never closed is a file that must be [abort]ed.
/// 4. [abort] removes the partial file and **must leave nothing behind**, not
///    even a 0 byte one. Aborting a transfer that was never opened is a no-op.
abstract interface class FileSink {
  /// Creates the destination for [transferId] and returns the path chosen.
  ///
  /// [name] has already been through `safeName`, so it cannot contain a path
  /// separator; the sink is still responsible for not overwriting an existing
  /// file, because two peers can legitimately send the same name twice.
  Future<String> open({
    required String transferId,
    required String name,
    required String mime,
  });

  /// Appends [chunk] and returns the number of bytes actually stored.
  ///
  /// Returning less than `chunk.length` is legal and is the case
  /// `TransferCoordinator` has to survive: a sink that batches, or one whose
  /// disk filled, both report a short write, and neither may make the progress
  /// bar go backwards.
  Future<int> write({required String transferId, required List<int> chunk});

  /// Flushes, closes and returns the saved path.
  Future<String> close({required String transferId});

  /// Removes the partial file. Leaves nothing on disk, not even an empty one.
  Future<void> abort({required String transferId});
}

/// A file this device wants to send.
///
/// Deliberately a pull interface, chunk by chunk, because the 512 MB cap is a
/// worst case and buffering a whole file to find out how big it is would defeat
/// it. [size] is the *declared* size, checked against `PeerProtocol.maxFileBytes`
/// before a single byte moves.
abstract interface class OutgoingFileSource {
  String get name;
  String get mime;

  /// The declared size in bytes.
  int get size;

  /// Reads at most [length] bytes from [offset] and returns what it read.
  ///
  /// Fewer bytes than asked for means end of file. A source that returns more
  /// than it was asked for is a bug in the source, and [TransferCoordinator]
  /// clamps rather than trusting it.
  Future<List<int>> read({required int offset, required int length});
}
