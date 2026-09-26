/// `PeerStore` over `mkvi_core`'s encrypted peer table.
///
/// ## What the bridge gives and what it does not
///
/// `list_peers` and `remember_peer` are a complete peer store. There is no third
/// call, and none is needed: MKVI pairs one device with one peer, so the list
/// shape the core returns (0 or 1 on a healthy install) is enough.
///
/// ## Why the failure mapping is a pure function
///
/// `peer_store.dart`'s library header says a throw from `readPeer` is legal but
/// easy to mishandle, and that the store's job is to be *unforgettable* at a call
/// site. That only works if the classification is somewhere a test can reach
/// without a native library. So [mapCoreFailureToPeerReadFailure] is a pure
/// function from a `CoreFailure` to a `PeerReadFailure`, and the five branches
/// are measured directly against real `CoreFailure` values — which are plain
/// generated data classes, constructible without the library because
/// `mkvi_bridge/README.md` keeps errors as data rather than as text.
///
/// The five branches, and why each is a different answer:
///
/// | `CoreFailure` | `PeerReadFailure` | Why it cannot be another one |
/// |---|---|---|
/// | `Security` / `KeyringEntryMissing` | `PeerKeyringEntryMissing` | The OS keystore lost the entry. Minting a replacement would orphan the record, so the user is told to pair again — never silently re-keyed. |
/// | `Security` / `Crypto` | `PeerDecryptFailed` | The record is there and authentication failed: the pairing key on this device no longer matches the one it was written with. |
/// | `Security` / `InvalidSecret`, `Serialization` | `PeerRecordCorrupt` | The row exists and is shaped wrong or will not decode: truncated, hand-edited, or written by a build this one does not understand. |
/// | a row that decodes to the wrong shape | `PeerRecordCorrupt` | Same answer as above, found on this side of the boundary — through `decodeStoredPeer`, which already owns that judgement. |
/// | anything else, and no library at all | `PeerStoreUnavailable` | A locked mutex, a SQLite error, a refused keystore, or a missing native library. None of those means "you have no peer", and `PeerAbsent` is the one answer that may lead to the pairing screen. |
library;

import 'package:mkvi/session/peer_store.dart';
// `mkvi_bridge`'in `lib/` altında genel bir kütüphane dosyası yok ve README'i tüketiciden tam olarak bu yolu istiyor.
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/api.dart' as bridge;
// ignore: implementation_imports
import 'package:mkvi_bridge/src/rust/error.dart' as bridge;

import 'rust_core.dart';

/// Maps one bridge failure onto the answer the session layer can act on.
///
/// Pure, and therefore the whole of the error contract in one testable place.
/// The input is whatever the bridge threw; a non-`CoreFailure` value is treated
/// as "the bridge is not usable", which is what an arbitrary `Object` from a
/// failed FFI call actually is.
PeerReadFailure mapCoreFailureToPeerReadFailure(Object failure) {
  if (failure is! bridge.CoreFailure_Security) {
    return const PeerStoreUnavailable();
  }
  return switch (failure.failure) {
    bridge.SecurityFailure_KeyringEntryMissing() =>
      const PeerKeyringEntryMissing(),
    bridge.SecurityFailure_Crypto() => const PeerDecryptFailed(),
    bridge.SecurityFailure_InvalidSecret() ||
    bridge.SecurityFailure_Serialization() => const PeerRecordCorrupt(),
    // `SecretStore` (the OS refused), `SecretStoreMissing` (it degraded to an
    // in-memory mock), `Database` (SQLite), `InvalidMessageId` (a write-side
    // check): none of them says the record is gone, so none of them may answer
    // "you have no peer".
    _ => const PeerStoreUnavailable(),
  };
}

/// Decodes one row the core returned, reusing `peer_store.dart`'s own judgement
/// about what a usable record is.
///
/// The name is sanitised on the way out, exactly as it is for a JSON record,
/// because a stored name is peer-supplied text written by some build of this app
/// and no future call site should be able to forget that.
PeerReadResult decodeBridgePeer(bridge.KnownPeer peer) =>
    decodeStoredPeer(<Object?, Object?>{
      'public_key': peer.publicKey,
      'discovery_id': peer.discoveryId,
      'display_name': peer.displayName,
      'paired_at_ms': peer.pairedAtMs,
    });

/// The encrypted peer store, backed by the Rust core.
final class RustPeerStore implements PeerStore {
  const RustPeerStore(this._core);

  final RustCore _core;

  @override
  Future<PeerReadResult> readPeer() async {
    if (!_core.isAvailable) {
      return PeerUnreadable(const PeerStoreUnavailable());
    }
    final List<bridge.KnownPeer> peers;
    try {
      peers = await bridge.listPeers(core: _core.requireCore());
    } on Object catch (failure) {
      return PeerUnreadable(mapCoreFailureToPeerReadFailure(failure));
    }
    if (peers.isEmpty) return const PeerAbsent();
    // The core orders newest first, and MKVI holds one peer. A list longer than
    // one is a store written by something else, not a reason to fail the read:
    // the newest row is the one this install paired last.
    return decodeBridgePeer(peers.first);
  }

  @override
  Future<void> writePeer(KnownPeer peer) async {
    if (!_core.isAvailable) {
      throw RustCoreUnavailable(
        '${_core.unavailableMessageTr} ${_core.unavailableRecoveryTr}',
      );
    }
    try {
      await bridge.rememberPeer(
        core: _core.requireCore(),
        // The wire field is `display_name` and the Dart field is
        // `announcedName`. A local alias must never be written into it; see
        // `peer_store.dart`.
        peer: bridge.KnownPeer(
          publicKey: peer.publicKey,
          discoveryId: peer.discoveryId,
          displayName: peer.announcedName,
          pairedAtMs: peer.pairedAtMs,
        ),
      );
    } on Object catch (failure) {
      throw RustPeerStoreWriteFailed(mapCoreFailureToPeerReadFailure(failure));
    }
  }
}

/// A write that failed, carrying the same classified answer a read would have.
///
/// A separate type from the bare `CoreFailure` so a caller can act on "the key
/// is gone" without re-running the classification, and so nothing above this line
/// has to know what a `CoreFailure` is.
final class RustPeerStoreWriteFailed implements Exception {
  const RustPeerStoreWriteFailed(this.failure);

  /// What went wrong, in the session layer's vocabulary.
  final PeerReadFailure failure;

  @override
  String toString() => 'RustPeerStoreWriteFailed: ${failure.message}';
}
