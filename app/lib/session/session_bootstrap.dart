/// One peer read, turned into one [SetupState].
///
/// This is the whole of the white pairing screen fix, and it is a value
/// computation with no UI in it. `src/App.tsx` decided what to render from the
/// VALUE of `knownPeer`, so a first run, a corrupt store and a failed IPC call
/// were the same value and two of them rendered pairing. Here the read has
/// three outcomes and only one of them is a first run.
library;

import 'peer_store.dart';
import 'setup_state.dart';

/// What a restore produced: the state to be in, and the peer when there is one.
final class BootstrapOutcome {
  const BootstrapOutcome({required this.state, this.peer});

  /// No peer. The pairing screen is allowed from here and nowhere else.
  const BootstrapOutcome.firstRun()
    : state = const SetupState.firstRun(),
      peer = null;

  /// A readable peer. The pairing screen is not allowed from here.
  const BootstrapOutcome.reconnecting(this.peer)
    : state = const SetupState.reconnecting();

  /// A peer that exists and cannot be read. The pairing screen is not allowed
  /// from here either, and this is the case the TypeScript original could not
  /// express. Not `const`, because the failure is a runtime value.
  BootstrapOutcome.broken(PeerReadFailure failure)
    : state = SetupState.broken(failure),
      peer = null;

  final SetupState state;

  /// Non-null exactly for [BootstrapOutcome.reconnecting].
  final KnownPeer? peer;

  @override
  String toString() => 'BootstrapOutcome($state)';
}

/// Reads the stored peer once and says where the app starts.
final class SessionBootstrap {
  const SessionBootstrap(this.peerStore);

  final PeerStore peerStore;

  /// Reads the store and classifies the answer.
  ///
  /// Every path out of here is [SetupState.broken], [SetupState.firstRun] or
  /// [SetupState.reconnecting]. There is no fourth path, and none of the three
  /// can be reached with `peer == null` except the first run and the broken
  /// case - which is the distinction `src/App.tsx` did not have.
  Future<BootstrapOutcome> restore() async {
    final PeerReadResult result;
    try {
      result = await peerStore.readPeer();
    } on Object {
      // A store that throws is a store that cannot be read.
      // `src/App.tsx:163-164` only called `setNotice` here and left
      // `knownPeer` null, which is the exact value the pairing screen was
      // gated on, so a transient IPC failure rendered the first-run screen.
      return BootstrapOutcome.broken(const PeerStoreUnavailable());
    }
    return switch (result) {
      PeerAbsent() => const BootstrapOutcome.firstRun(),
      PeerFound(:final KnownPeer peer) => BootstrapOutcome.reconnecting(peer),
      PeerUnreadable(:final PeerReadFailure failure) => BootstrapOutcome.broken(
        failure,
      ),
    };
  }

  /// TS has no counterpart: the `broken` screen's primary action. A read that
  /// failed can perfectly well succeed the second time, and this is what stops
  /// a failed read from being a dead end that forces a restart.
  Future<BootstrapOutcome> retry() => restore();

  /// The state a user-initiated pairing starts from.
  ///
  /// Kept next to the other two constructors so all three are written in one
  /// place: only a user-initiated pairing may produce [SetupState.needsPairing],
  /// and it is produced here and nowhere else.
  BootstrapOutcome startPairing() =>
      const BootstrapOutcome(state: SetupState.needsPairing());
}
