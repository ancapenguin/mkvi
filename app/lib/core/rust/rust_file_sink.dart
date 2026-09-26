/// `FileSink` over `mkvi_core`'s open file handles.
///
/// ## The gap, and why this file exists at all
///
/// `Core` has all four calls the Dart contract needs:
///
/// | `Core` (`crates/mkvi_core/src/state.rs`) | returns |
/// |---|---|
/// | `open_sink(id, directory, name, max_open)` (`:117`) | `PathBuf` |
/// | `write_sink(id, bytes)` (`:146`) | `Result<(), CoreError>` |
/// | `close_sink(id)` (`:161`) | `PathBuf` |
/// | `abort_sink(id)` (`:169`) | `Result<(), CoreError>` |
///
/// None of them is on the bridge. `mkvi_bridge/README.md:135-143` records that as
/// a deliberate deferral, and `api.rs` exports none of the four — so a
/// `FileSink` on top of the bridge is not writable today, and pretending
/// otherwise would mean a sink that silently creates nothing.
///
/// **The byte count needs no core change.** `FileSink.write` must return the
/// number of bytes actually stored (`file_sink.dart:44-48`, and
/// `file_sink.dart:61-67` calls that the ground truth of the whole transfer
/// layer), and it looks like a signature problem because `write_sink` returns
/// `()`. It is not: `state.rs:155` is `sink.handle.write_all(bytes)?` — all or
/// nothing, no short write, no buffering. So `Ok` means every byte landed and the
/// adapter returns `chunk.length`, and a failure is a failure. That is why this
/// file needs no change to `mkvi_core` at all; what it needs is four thin
/// wrappers in `api.rs`, which belong to the bridge's owner.
///
/// ## Why the default is a refusal and not a stub
///
/// `file_sink.dart`'s library header names the exact defect this layer exists to
/// prevent: opening the destination before the checks that can refuse the
/// transfer have refused it leaves a 0-byte file behind for every rejected
/// transfer. An implementation that answered `open` with a path and then wrote
/// nothing would be that defect wearing a Rust costume, so [RustFileTransfer]
/// refuses and says so in Turkish. [RustFileSink] measures the refusal for all
/// four methods, which is the only thing testable before the bridge grows them.
library;

import 'package:mkvi/chat/file_sink.dart';

import 'rust_core.dart';

/// The four `Core` calls [RustFileSink] needs, as the bridge will expose them.
///
/// An interface with exactly one implementation, and that implementation
/// refuses. It is not a fake: there is no second implementation to confuse a
/// test with, and it exists so the refusal has a name and the four call sites are
/// written once.
abstract interface class RustFileTransfer {
  /// `open_sink(id, directory, name, max_open)`.
  Future<String> openSink({
    required String id,
    required String directory,
    required String name,
    required int maxOpen,
  });

  /// `write_sink(id, bytes)`.
  Future<void> writeSink({required String id, required List<int> bytes});

  /// `close_sink(id)`.
  Future<String> closeSink({required String id});

  /// `abort_sink(id)`.
  Future<void> abortSink({required String id});
}

/// The only implementation: the bridge does not carry the four calls yet.
///
/// Every method throws, and the message is Turkish and names the limit, because
/// the alternative — returning a path and storing nothing — is a file that looks
/// saved and is not.
final class MissingRustFileTransfer implements RustFileTransfer {
  const MissingRustFileTransfer();

  static const String _message =
      'Dosya kaydedilemedi: Rust köprüsü dosya yazma çağrılarını henüz '
      'taşımıyor.';

  static const String _recovery =
      'Bu bir MKVI sınırı, bir hata değil. Dosya indirme yeni sürümde açılacak.';

  @override
  Future<String> openSink({
    required String id,
    required String directory,
    required String name,
    required int maxOpen,
  }) => throw const FileSinkException('$_message $_recovery');

  @override
  Future<void> writeSink({
    required String id,
    required List<int> bytes,
  }) => throw const FileSinkException('$_message $_recovery');

  @override
  Future<String> closeSink({required String id}) =>
      throw const FileSinkException('$_message $_recovery');

  @override
  Future<void> abortSink({required String id}) => throw const FileSinkException(
    'Dosya temizlenemedi: Rust köprüsü dosya yazma çağrılarını henüz '
    'taşımıyor. $_recovery',
  );
}

/// `FileSink` over the Rust core.
///
/// [directory] is the download folder; [maxOpen] is the core's own concurrency
/// cap, checked inside `open_sink` *before* the file is created
/// (`state.rs:124-131`). Passing it in rather than hard-coding it is what keeps
/// `peer_protocol.dart`'s `maxConcurrentReceives` the one owner of that number.
final class RustFileSink implements FileSink {
  RustFileSink({
    required this.directory,
    required RustCore core,
    RustFileTransfer? transfer,
    this.maxOpen = 2,
    // A named parameter cannot be an initialising formal for a private field:
    // Dart forbids a named parameter whose name starts with an underscore.
    // ignore: prefer_initializing_formals
  }) : _core = core,
       _transfer = transfer ?? const MissingRustFileTransfer();

  /// Where accepted files are written.
  final String directory;

  /// How many transfers may be open at once. `peer_protocol.dart`'s
  /// `maxConcurrentReceives` is 2 and this defaults to the same number.
  final int maxOpen;

  final RustCore _core;
  final RustFileTransfer _transfer;

  /// Transfer ids that reached [open], in order. A record, so a test can prove
  /// nothing was opened for a transfer that was refused.
  final List<String> opened = <String>[];

  /// The Turkish refusal for "the bridge is not there", shared with the core so
  /// the app says one thing about one failure.
  static String unavailableMessage(RustCore core) =>
      '${core.unavailableMessageTr ?? ''} ${core.unavailableRecoveryTr ?? ''}'.trim();

  @override
  Future<String> open({
    required String transferId,
    required String name,
    required String mime,
  }) async {
    if (!_core.isAvailable) {
      throw FileSinkException(unavailableMessage(_core));
    }
    final String path = await _transfer.openSink(
      id: transferId,
      directory: directory,
      name: name,
      maxOpen: maxOpen,
    );
    opened.add(transferId);
    return path;
  }

  @override
  Future<int> write({
    required String transferId,
    required List<int> chunk,
  }) async {
    if (!_core.isAvailable) {
      throw FileSinkException(unavailableMessage(_core));
    }
    await _transfer.writeSink(id: transferId, bytes: chunk);
    // `write_sink` is `write_all` or an error (`state.rs:155`), so a completed
    // call stored every byte. Returning `chunk.length` is the truth, not an
    // estimate: a short write is not a thing this core can produce, and
    // `TransferCoordinator` clamps a larger number rather than trusting it.
    return chunk.length;
  }

  @override
  Future<String> close({required String transferId}) async {
    if (!_core.isAvailable) {
      throw FileSinkException(unavailableMessage(_core));
    }
    return _transfer.closeSink(id: transferId);
  }

  @override
  Future<void> abort({required String transferId}) async {
    if (!_core.isAvailable) {
      throw FileSinkException(unavailableMessage(_core));
    }
    await _transfer.abortSink(id: transferId);
  }
}
