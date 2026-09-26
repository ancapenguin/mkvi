/// BUG 1, the white pairing screen: "After closing and reopening the app it
/// does not reconnect; it dumps me back on the same white screen."
///
/// When the UI decided what to render from a single nullable "known peer"
/// value, the pairing screen was the fallback branch, reached whenever that value
/// was null. A first run, a corrupt store and a transient read failure all left
/// it null — the catch only set a notice — so two of the three rendered pairing.
///
/// Every test in this file is about that, and the assertion is always the same
/// single question: [SetupState.showsPairingScreen].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/session/peer_store.dart';
import 'package:mkvi/session/session_bootstrap.dart';
import 'package:mkvi/session/setup_state.dart';

import 'support/fakes.dart';

const KnownPeer storedPeer = KnownPeer(
  publicKey: fakePeerPublicKey,
  discoveryId: 'stored-discovery-room',
  announcedName: 'Ayşe',
  pairedAtMs: 1735689600000,
);

void main() {
  group('the single guard, on its own', () {
    test('showsPairingScreen is true for firstRun and needsPairing only', () {
      const List<SetupState> every = <SetupState>[
        SetupState.firstRun(),
        SetupState.restoring(),
        SetupState.reconnecting(),
        SetupState.connected(),
        SetupState.needsPairing(),
        SetupState.broken(PeerStoreUnavailable()),
        SetupState.broken(PeerDecryptFailed()),
        SetupState.broken(PeerKeyringEntryMissing()),
        SetupState.broken(PeerRecordCorrupt()),
      ];
      expect(
        every.where((SetupState state) => state.showsPairingScreen).toList(),
        const <SetupState>[SetupState.firstRun(), SetupState.needsPairing()],
        reason:
            'pairing is reachable from a first run and from an explicit request, and from nothing else',
      );
    });

    test('every broken case offers an actionable Turkish reason', () {
      for (final PeerReadFailure failure in <PeerReadFailure>[
        const PeerStoreUnavailable(),
        const PeerDecryptFailed(),
        const PeerKeyringEntryMissing(),
        const PeerRecordCorrupt(),
      ]) {
        final SetupState state = SetupState.broken(failure);
        expect(state, isA<SetupBroken>(), reason: '$failure');
        expect(state.showsPairingScreen, isFalse, reason: '$failure');
        expect(state.title, 'Kayıtlı eş açılamadı', reason: '$failure');
        expect(
          state.detail,
          '${failure.message} ${failure.recovery}',
          reason: '$failure',
        );
        expect(
          state.canRetry,
          isTrue,
          reason: 'a failed read can succeed the second time: $failure',
        );
        expect(
          state.showsWorkspace,
          isFalse,
          reason: 'there is no peer to chat with: $failure',
        );
        // The recovery lives on the broken case alone, because only it has one.
        final SetupBroken broken = state as SetupBroken;
        expect(broken.failure, same(failure));
        expect(
          broken.recovery,
          failure.recovery,
          reason: 'the UI needs the action on its own',
        );
      }
    });

    test('the pairing screen is not reachable from any other state', () {
      const List<SetupState> notPairing = <SetupState>[
        SetupState.restoring(),
        SetupState.reconnecting(),
        SetupState.connected(),
        SetupState.broken(PeerDecryptFailed()),
      ];
      for (final SetupState state in notPairing) {
        expect(state.showsPairingScreen, isFalse, reason: '$state');
      }
      // `reconnecting`, `connected` and `broken` offer the ACTION; acting on it is
      // a separate explicit call, and only that call produces `needsPairing`.
      expect(const SetupState.reconnecting().offersPairNewDevice, isTrue);
      expect(const SetupState.connected().offersPairNewDevice, isTrue);
      expect(
        const SetupState.broken(PeerDecryptFailed()).offersPairNewDevice,
        isTrue,
      );
      expect(
        const SetupState.firstRun().offersPairNewDevice,
        isFalse,
        reason: 'already pairing',
      );
      expect(
        const SetupState.needsPairing().offersPairNewDevice,
        isFalse,
        reason: 'already pairing',
      );
    });
  });

  group('a failed peer read', () {
    test('reaches broken and never the pairing screen', () async {
      // The exact production case: a device paired months ago, the keyring is
      // unhappy this morning.
      final FakePeerStore store = FakePeerStore(
        answer: const PeerUnreadable(PeerDecryptFailed()),
      );
      final BootstrapOutcome outcome = await SessionBootstrap(store).restore();

      expect(
        outcome.state,
        isA<SetupBroken>(),
        reason: 'a paired-but-unreadable device is broken',
      );
      expect(outcome.state.showsPairingScreen, isFalse);
      expect(
        outcome.peer,
        isNull,
        reason: 'and it is NOT the same answer as "never paired"',
      );
      expect(store.reads, 1);
    });

    test('a store that throws is broken, not a first run', () async {
      // A store that throws leaves no peer at all, which is the value the
      // pairing screen was gated on.
      final FakePeerStore store = FakePeerStore(
        answer: PeerFound(storedPeer),
        throwOnRead: StateError('IPC köprüsü yanıt vermiyor.'),
      );
      final BootstrapOutcome outcome = await SessionBootstrap(store).restore();

      expect(outcome.state, isA<SetupBroken>());
      expect(outcome.state, SetupState.broken(const PeerStoreUnavailable()));
      expect(outcome.state.showsPairingScreen, isFalse);
    });

    test('every failure mode is broken, and none of them is pairing', () async {
      for (final PeerReadResult unreadable in <PeerReadResult>[
        const PeerUnreadable(PeerStoreUnavailable()),
        const PeerUnreadable(PeerDecryptFailed()),
        const PeerUnreadable(PeerKeyringEntryMissing()),
        const PeerUnreadable(PeerRecordCorrupt()),
      ]) {
        final BootstrapOutcome outcome = await SessionBootstrap(
          FakePeerStore(answer: unreadable),
        ).restore();
        expect(
          outcome.state.showsPairingScreen,
          isFalse,
          reason: '$unreadable',
        );
        expect(outcome.state, isA<SetupBroken>(), reason: '$unreadable');
        expect(outcome.peer, isNull, reason: '$unreadable');
      }
    });

    test(
      'a retry that succeeds reaches reconnecting, so a transient failure is not a dead end',
      () async {
        final FakePeerStore store = FakePeerStore(
          script: <PeerReadResult>[
            const PeerUnreadable(PeerStoreUnavailable()),
            PeerFound(storedPeer),
          ],
        );
        final SessionBootstrap bootstrap = SessionBootstrap(store);

        final BootstrapOutcome first = await bootstrap.restore();
        expect(first.state, isA<SetupBroken>());

        final BootstrapOutcome second = await bootstrap.retry();
        expect(second.state, isA<SetupReconnecting>());
        expect(second.peer, storedPeer);
        expect(second.state.showsPairingScreen, isFalse);
      },
    );

    test(
      'a retry that fails again stays broken and never degrades into pairing',
      () async {
        final FakePeerStore store = FakePeerStore(
          answer: const PeerUnreadable(PeerKeyringEntryMissing()),
        );
        final SessionBootstrap bootstrap = SessionBootstrap(store);

        for (int attempt = 0; attempt < 5; attempt += 1) {
          final BootstrapOutcome outcome = await bootstrap.retry();
          expect(
            outcome.state.showsPairingScreen,
            isFalse,
            reason: 'attempt $attempt',
          );
        }
        expect(store.reads, 5);
      },
    );
  });

  group('a first run', () {
    test('reaches the pairing screen', () async {
      final FakePeerStore store = FakePeerStore(answer: const PeerAbsent());
      final BootstrapOutcome outcome = await SessionBootstrap(store).restore();

      expect(outcome.state, const SetupState.firstRun());
      expect(
        outcome.state.showsPairingScreen,
        isTrue,
        reason: 'this is the one case where pairing is correct',
      );
      expect(outcome.peer, isNull);
    });

    test(
      'an empty store that throws nothing is a first run, not a broken store',
      () async {
        // The distinction has to be a VALUE, not the absence of an exception.
        final FakePeerStore store = FakePeerStore(answer: const PeerAbsent());
        final BootstrapOutcome outcome = await SessionBootstrap(
          store,
        ).restore();
        expect(outcome.state, isA<SetupFirstRun>());
        expect(outcome.state.canRetry, isFalse);
      },
    );
  });

  group('an explicit request to pair a new device', () {
    test(
      'reaches the pairing screen, and only an explicit request does',
      () async {
        final SessionBootstrap bootstrap = SessionBootstrap(
          FakePeerStore(answer: PeerFound(storedPeer)),
        );

        // A stored peer does NOT put the app on the pairing screen.
        expect((await bootstrap.restore()).state.showsPairingScreen, isFalse);

        // The user pressed the button.
        final BootstrapOutcome pairing = bootstrap.startPairing();
        expect(pairing.state, const SetupState.needsPairing());
        expect(pairing.state.showsPairingScreen, isTrue);
      },
    );

    test(
      'a broken device is only put on the pairing screen by that request',
      () async {
        final SessionBootstrap bootstrap = SessionBootstrap(
          FakePeerStore(answer: const PeerUnreadable(PeerRecordCorrupt())),
        );

        // Broken, with pairing NOT available yet: the user is told what happened
        // and offered a retry.
        final BootstrapOutcome broken = await bootstrap.restore();
        expect(broken.state, isA<SetupBroken>());
        expect(broken.state.showsPairingScreen, isFalse);
        expect(broken.state.canRetry, isTrue);

        // Only the explicit request, which is a separate call, does it.
        expect(bootstrap.startPairing().state.showsPairingScreen, isTrue);
        // And `restore()` never produces it, however many times it is called.
        for (int attempt = 0; attempt < 3; attempt += 1) {
          expect(
            (await bootstrap.restore()).state,
            isA<SetupBroken>(),
            reason: 'attempt $attempt',
          );
        }
      },
    );
  });

  group('a readable peer', () {
    test('reaches reconnecting and carries the peer', () async {
      final BootstrapOutcome outcome = await SessionBootstrap(
        FakePeerStore(answer: PeerFound(storedPeer)),
      ).restore();

      expect(outcome.state, const SetupState.reconnecting());
      expect(outcome.state.showsPairingScreen, isFalse);
      expect(
        outcome.state.showsWorkspace,
        isTrue,
        reason: 'a saved pair owns the main screen even while offline',
      );
      expect(outcome.peer, storedPeer);
    });

    test('a stored name is sanitised on the way out of the store', () async {
      // A line separator (U+2028) and a zero-width space (U+200B) appended to a
      // name, as a corrupted or hand-edited record would carry. Built from code
      // points so the source file stays readable.
      final String hostile =
          'Ayşe${String.fromCharCode(0x2028)}${String.fromCharCode(0x200B)}${String.fromCharCode(0x00)}';
      final PeerReadResult decoded = decodeStoredPeer(<Object?, Object?>{
        'public_key': fakePeerPublicKey,
        'discovery_id': 'room',
        'display_name': hostile,
        'paired_at_ms': 1735689600000,
      });
      final BootstrapOutcome outcome = await SessionBootstrap(
        FakePeerStore(answer: decoded),
      ).restore();

      final KnownPeer? peer = outcome.peer;
      expect(peer, isNotNull);
      expect(peer!.announcedName, 'Ayşe');
      expect(peer.announcedName.runes.every((int rune) => rune > 0x20), isTrue);
    });

    test(
      'a row of the wrong shape is a corrupt record, not an absent one',
      () async {
        for (final Object? row in <Object?>[
          null,
          'not a record',
          42,
          <Object?, Object?>{},
          <Object?, Object?>{'public_key': fakePeerPublicKey},
          <Object?, Object?>{'discovery_id': 'room'},
          <Object?, Object?>{'public_key': 17, 'discovery_id': 'room'},
          <Object?, Object?>{'public_key': '', 'discovery_id': 'room'},
        ]) {
          final PeerReadResult decoded = decodeStoredPeer(row);
          expect(decoded, isA<PeerUnreadable>(), reason: 'row $row');
          expect(
            decoded,
            const PeerUnreadable(PeerRecordCorrupt()),
            reason: 'row $row',
          );
        }
      },
    );

    test(
      'a record with no display_name is a 0.1.x record, not a corrupt one',
      () async {
        // An older stored record did not persist a name. Decoding it must not be
        // an error, and it must not show the pairing screen either.
        final PeerReadResult decoded = decodeStoredPeer(<Object?, Object?>{
          'public_key': fakePeerPublicKey,
          'discovery_id': 'room',
          'paired_at_ms': 1735689600000,
        });
        final BootstrapOutcome outcome = await SessionBootstrap(
          FakePeerStore(answer: decoded),
        ).restore();

        expect(outcome.state, isA<SetupReconnecting>());
        expect(outcome.state.showsPairingScreen, isFalse);
        expect(outcome.peer!.announcedName, isEmpty);
      },
    );
  });
}
