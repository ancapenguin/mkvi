/// BUG 2, the alias that ate the peer's real name.
///
/// `src/App.tsx:119` was
///
/// ```ts
/// const peerName = peerAlias || peerAnnouncedName || defaultPeerName;
/// ```
///
/// so a purely local annotation outranked the name the peer published about
/// itself. Worse, `src/components/ChatCallWorkspace.tsx:490` computed
/// `aliasIsSet = Boolean(peerAnnouncedName && peerAnnouncedName !== peerName)`
/// and gated BOTH the "Kendi seçtiği ad: …" line and the "Takma adı kaldır"
/// button on it. Type the annotation as the peer's own name and both vanish:
/// the peer can never change their name again from the UI.
///
/// And `src/App.tsx:438` wrote `display_name: peerAnnouncedName ||
/// defaultPeerName` on re-pairing, so a known name was downgraded to the
/// placeholder "Kişi" every time the channel came up before the peer's
/// `profile` frame did.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/session/session.dart';
import 'package:mkvi/signaling/rendezvous_client.dart';
import 'package:mkvi/signaling/signal_payload.dart';

import 'support/fakes.dart';

/// A signaling client factory that never dials: the controller tears its loop
/// down in the tear-down, and these tests are about names, not about sockets.
final class FakePairingOnlySignaling {
  static RendezvousClient newClient() =>
      throw StateError('bu test soket açmaz');
}

const String firstPeerKey = fakePeerPublicKey;
const String secondPeerKey = fakeOtherPublicKey;

/// BEL, the control character a hand-edited store would carry.
final String bell = String.fromCharCode(0x07);

/// ZERO WIDTH SPACE, another one a hand-edited store would carry.
final String zeroWidthSpace = String.fromCharCode(0x200b);

const KnownPeer peerOne = KnownPeer(
  publicKey: firstPeerKey,
  discoveryId: 'room-one',
  announcedName: 'Ayşe',
  pairedAtMs: 1735689600000,
);

const KnownPeer peerTwo = KnownPeer(
  publicKey: secondPeerKey,
  discoveryId: 'room-two',
  announcedName: 'Mehmet',
  pairedAtMs: 1735689601000,
);

void main() {
  group('the announced name is the primary slot', () {
    test('an annotation does not change the displayed name', () {
      // TS: `peerAlias || peerAnnouncedName || defaultPeerName` put the alias
      // here, so the peer became "Patron" on this device and "Ayşe" everywhere
      // else.
      final PeerNameView view = PeerNameView(
        announcedName: 'Ayşe',
        alias: 'Patron',
      );
      expect(
        view.displayName,
        'Ayşe',
        reason: 'the announced name is the peer identity',
      );
      expect(view.alias, 'Patron');
      expect(view.hasAlias, isTrue);
      expect(view.displayName, isNot(view.alias));
    });

    test('no annotation and an unknown name falls back to the placeholder', () {
      // TS: `defaultPeerName` at `src/App.tsx:31`.
      final PeerNameView view = PeerNameView(announcedName: '');
      expect(view.displayName, KnownPeer.defaultAnnouncedName);
      expect(view.displayName, 'Kişi');
      expect(view.announcedNameIsUnknown, isTrue);
      expect(view.hasAlias, isFalse);
      expect(
        view.showsAnnouncedName,
        isFalse,
        reason: 'there is no second name to show',
      );
    });

    test(
      'the annotation cannot become the display name by being the only one',
      () {
        // A record from 0.1.0 with no name at all, plus a note. The note is a
        // note; the primary slot is the placeholder, exactly as before.
        final PeerNameView view = PeerNameView(
          announcedName: '',
          alias: 'Patron',
        );
        expect(view.displayName, 'Kişi');
        expect(view.alias, 'Patron');
        expect(view.showsAnnouncedName, isFalse);
      },
    );
  });

  group('an annotation EQUAL to the announced name keeps both affordances', () {
    // This is the exact `aliasIsSet` trap: `peerAnnouncedName !== peerName`
    // became false, so the announced-name line and the remove button both
    // disappeared, and the peer could not change their name from the UI again.
    test('the announced-name line stays visible', () {
      final PeerNameView view = PeerNameView(
        announcedName: 'Ayşe',
        alias: 'Ayşe',
      );
      expect(view.hasAlias, isTrue);
      expect(
        view.showsAnnouncedName,
        isTrue,
        reason:
            'the whole point: an annotation equal to the name is still an annotation',
      );
      expect(view.announcedNameLabel, 'Kendi seçtiği ad: Ayşe');
    });

    test('the remove-annotation affordance stays available', () {
      final PeerNameView view = PeerNameView(
        announcedName: 'Ayşe',
        alias: 'Ayşe',
      );
      expect(
        view.canRemoveAlias,
        isTrue,
        reason:
            'TS: src/ChatCallWorkspace.tsx:514 was gated on the same broken expression',
      );
      expect(view.removeAliasLabel, 'Takma adı kaldır');
    });

    test(
      'the primary name is still the announced name, so nothing is hidden',
      () {
        final PeerNameView view = PeerNameView(
          announcedName: 'Ayşe',
          alias: 'Ayşe',
        );
        expect(view.displayName, 'Ayşe');
        expect(view.displayName, view.alias);
        expect(view.aliasButtonLabel, 'Takma ad');
        expect(view.aliasFieldLabel, 'Bu cihazdaki kişi takma adı');
      },
    );

    test('the editor opens on the annotation, not on the display name', () {
      // TS: `setNameDraft(aliasIsSet ? peerName : "")` at
      // `src/ChatCallWorkspace.tsx:506`, which opened the editor on the DISPLAY
      // name and so re-labelled the peer as themselves.
      expect(
        PeerNameView(announcedName: 'Ayşe', alias: 'Patron').aliasDraft,
        'Patron',
      );
      expect(PeerNameView(announcedName: 'Ayşe').aliasDraft, isEmpty);
      expect(
        PeerNameView(announcedName: 'Ayşe', alias: 'Ayşe').aliasDraft,
        'Ayşe',
      );
      // And the placeholder shows the peer what they actually call themselves.
      expect(PeerNameView(announcedName: 'Ayşe').aliasFieldPlaceholder, 'Ayşe');
    });

    test('every combination of the two names behaves', () {
      for (final String announced in <String>['', 'Ayşe']) {
        for (final String alias in <String>['', 'Ayşe', 'Patron']) {
          final PeerNameView view = PeerNameView(
            announcedName: announced,
            alias: alias,
          );
          final String label = '$announced / $alias';
          expect(view.hasAlias, alias.isNotEmpty, reason: label);
          expect(view.canRemoveAlias, alias.isNotEmpty, reason: label);
          expect(
            view.showsAnnouncedName,
            alias.isNotEmpty && announced.isNotEmpty,
            reason: label,
          );
          // The primary slot is the announced name or the placeholder. It is
          // NEVER the annotation.
          expect(
            view.displayName,
            announced.isEmpty ? KnownPeer.defaultAnnouncedName : announced,
            reason: label,
          );
        }
      }
    });
  });

  group('the annotation is keyed by the peer public key', () {
    test('one peer annotation is not returned for a different peer key', () {
      final FakeSettings settings = FakeSettings();
      final PeerAliasStore aliases = PeerAliasStore(settings);

      aliases.write(firstPeerKey, 'Patron');
      expect(aliases.read(firstPeerKey), 'Patron');
      expect(
        aliases.read(secondPeerKey),
        isEmpty,
        reason: 'a note about one person is not a note about the next',
      );
      expect(aliases.read('some-other-key'), isEmpty);

      aliases.write(secondPeerKey, 'Eş');
      expect(aliases.read(firstPeerKey), 'Patron');
      expect(aliases.read(secondPeerKey), 'Eş');

      aliases.remove(firstPeerKey);
      expect(aliases.read(firstPeerKey), isEmpty);
      expect(
        aliases.read(secondPeerKey),
        'Eş',
        reason: 'removing one note must not touch the other',
      );
    });

    test('the storage key is the public key, and only the public key', () {
      expect(peerAliasKey(firstPeerKey), 'mkvi.peerAlias.$firstPeerKey');
      final FakeSettings settings = FakeSettings();
      PeerAliasStore(settings).write(firstPeerKey, 'Patron');
      expect(settings.values.keys.single, 'mkvi.peerAlias.$firstPeerKey');
      expect(settings.serialized, 'mkvi.peerAlias.$firstPeerKey=Patron');
    });

    test(
      'there is NO unscoped fallback, which is the leak in the original',
      () {
        // `readPeerAlias` at `src/App.tsx:77-85` returned the UNSCOPED
        // `mkvi.peerName` for any peer with no scoped entry, and copied it onto
        // whoever happened to be read first.
        final FakeSettings settings = FakeSettings();
        final PeerAliasStore aliases = PeerAliasStore(settings);
        expect(aliases.read(firstPeerKey), isEmpty);
        expect(aliases.read(secondPeerKey), isEmpty);
      },
    );

    test(
      'the legacy key is migrated once, for the peer that is actually restored',
      () {
        final FakeSettings settings = FakeSettings()
          ..write(SettingsKeys.legacyPeerAlias, 'Patron');
        final PeerAliasStore aliases = PeerAliasStore(settings);

        expect(aliases.migrateLegacyAlias(firstPeerKey), 'Patron');
        expect(
          settings.read(SettingsKeys.legacyPeerAlias),
          isNull,
          reason: 'the legacy key is consumed',
        );
        expect(aliases.read(firstPeerKey), 'Patron');

        // A second peer paired later gets nothing.
        expect(aliases.migrateLegacyAlias(secondPeerKey), isEmpty);
        expect(aliases.read(secondPeerKey), isEmpty);
      },
    );

    test('a scoped entry is never overwritten by the migration', () {
      final FakeSettings settings = FakeSettings()
        ..write(SettingsKeys.legacyPeerAlias, 'Eski')
        ..write(peerAliasKey(firstPeerKey), 'Yeni');
      expect(PeerAliasStore(settings).migrateLegacyAlias(firstPeerKey), 'Yeni');
      expect(
        settings.read(SettingsKeys.legacyPeerAlias),
        'Eski',
        reason: 'and the legacy key is left alone',
      );
    });

    test('an annotation is trimmed, capped and stripped of invisibles', () {
      final FakeSettings settings = FakeSettings();
      final PeerAliasStore aliases = PeerAliasStore(settings);

      aliases.write(firstPeerKey, '  Patron$bell  ');
      expect(aliases.read(firstPeerKey), 'Patron');

      aliases.write(firstPeerKey, 'A' * 80);
      expect(
        aliases.read(firstPeerKey).length,
        40,
        reason: 'the same 40 code point cap the wire uses',
      );

      // An empty or all-invisible annotation removes the entry rather than
      // storing an empty string.
      aliases.write(firstPeerKey, '   ');
      expect(settings.values.containsKey(peerAliasKey(firstPeerKey)), isFalse);
    });
  });

  group('this device own name', () {
    test('is sanitised on write AND on read', () {
      // TS read `localStorage.getItem("mkvi.selfName")` raw at `src/App.tsx:35`
      // and only truncated on write, so a value from an older build reached
      // `sendProfile` unsanitised.
      final FakeSettings settings = FakeSettings();
      final SelfName self = SelfName(settings);

      self.write('  Ayşe$bell  ');
      expect(settings.values[SettingsKeys.selfName], 'Ayşe');
      expect(self.read(), 'Ayşe');

      // A hand-edited store, read without a write in between. The zero-width
      // space becomes a space rather than vanishing, exactly as
      // `safeDisplayName` has always done: it maps invisibles to a space and
      // then collapses runs of them, so nothing invisible can reach the wire and
      // no two invisibles can turn into two visible ones.
      settings.values[SettingsKeys.selfName] = 'Bo${zeroWidthSpace}zul';
      expect(self.read(), 'Bo zul');

      settings.values[SettingsKeys.selfName] = 'C' * 100;
      expect(self.read().length, 40);

      settings.values[SettingsKeys.selfName] = '';
      expect(self.read(), isEmpty);
      settings.values.remove(SettingsKeys.selfName);
      expect(self.read(), isEmpty);
    });
  });

  group('re-pairing must not downgrade a known name', () {
    test('no fresh profile keeps the previously stored name', () {
      // TS: `display_name: peerAnnouncedName || defaultPeerName` at
      // `src/App.tsx:438`, with `peerAnnouncedName` still empty because the
      // channel came up before the profile frame.
      expect(resolveStoredAnnouncedName(fresh: null, stored: 'Ayşe'), 'Ayşe');
      expect(resolveStoredAnnouncedName(fresh: '', stored: 'Ayşe'), 'Ayşe');
      expect(resolveStoredAnnouncedName(fresh: '   ', stored: 'Ayşe'), 'Ayşe');
      expect(
        resolveStoredAnnouncedName(fresh: 'Beyza', stored: 'Ayşe'),
        'Beyza',
        reason: 'a fresh name always wins',
      );
    });

    test(
      'the record built for a re-pairing keeps the name, not the placeholder',
      () {
        final KnownPeer rePaired = KnownPeer.forPairing(
          publicKey: firstPeerKey,
          discoveryId: 'room-one',
          pairedAtMs: 1735690000000,
          freshAnnouncedName: null,
          previousAnnouncedName: 'Ayşe',
        );
        expect(rePaired.announcedName, 'Ayşe');
        expect(rePaired.toJson()['display_name'], 'Ayşe');
        expect(rePaired.encode(), isNot(contains('Kişi')));
      },
    );

    test('with no previous name either, the store writes no name at all', () {
      final KnownPeer fresh = KnownPeer.forPairing(
        publicKey: firstPeerKey,
        discoveryId: 'room-one',
        pairedAtMs: 1735690000000,
      );
      expect(fresh.announcedName, isEmpty);
      // The UI is the layer that substitutes the placeholder, so the STORE never
      // has to invent a name for a peer that has not announced one.
      expect(
        PeerNameView(announcedName: fresh.announcedName).displayName,
        KnownPeer.defaultAnnouncedName,
      );
    });

    test('a fresh name is sanitised before it is stored', () {
      final KnownPeer rePaired = KnownPeer.forPairing(
        publicKey: firstPeerKey,
        discoveryId: 'room-one',
        pairedAtMs: 1735690000000,
        freshAnnouncedName: '  Beyza$bell  ',
      );
      expect(rePaired.announcedName, 'Beyza');
    });
  });

  group('the annotation never leaves this device', () {
    test(
      'it is not in the stored display_name, asserted on the serialized form',
      () {
        final KnownPeer stored = KnownPeer.forPairing(
          publicKey: firstPeerKey,
          discoveryId: 'room-one',
          pairedAtMs: 1735690000000,
          freshAnnouncedName: 'Ayşe',
        );
        final String serialized = stored.encode();

        expect(serialized, isNot(contains('Patron')));
        expect(jsonDecode(serialized), <String, Object?>{
          'public_key': firstPeerKey,
          'discovery_id': 'room-one',
          'display_name': 'Ayşe',
          'paired_at_ms': 1735690000000,
        });
        expect(stored.toJson().keys, <String>[
          'public_key',
          'discovery_id',
          'display_name',
          'paired_at_ms',
        ]);
      },
    );

    test('it is not in anything that goes on the wire', () {
      // The closed set of payloads the session layer can originate. None of them
      // has a name field at all: the signaling server sees a public key, a
      // signature and a session id, and a name goes on the data channel.
      for (final SignalPayload payload in sessionOutboundPayloads(
        publicKey: firstPeerKey,
        signature: fakeSignature,
        session: fakeOpaqueId('S00'),
        sdp: 'v=0',
        candidate: const IceCandidate(
          candidate: 'candidate:1 1 udp 1 127.0.0.1 9 typ host',
        ),
      )) {
        final String encoded = jsonEncode(payload.toJson());
        expect(encoded, isNot(contains('Patron')), reason: '$payload');
        expect(encoded, isNot(contains('alias')), reason: '$payload');
        expect(encoded, isNot(contains('display_name')), reason: '$payload');
      }
    });

    test(
      'the identity envelope has exactly the four keys the Worker allows',
      () {
        final IdentitySignal identity = IdentitySignal(
          publicKey: firstPeerKey,
          signature: fakeSignature,
          session: fakeOpaqueId('S00'),
        );
        expect(identity.toJson().keys.toList(), <String>[
          'kind',
          'publicKey',
          'signature',
          'session',
        ]);
        // And the port own mirror agrees, so a name could not be smuggled in.
        expect(isSignalPayload(identity.toJson()), isTrue);
      },
    );

    test(
      "a peer's announced name does not leak into the signaling wire either",
      () {
        // The announced name is a data-channel fact, not a signaling fact. A
        // Worker that saw it would be holding content, which is the whole reason
        // the payload allow-list exists.
        final String encoded = jsonEncode(
          IdentitySignal(
            publicKey: firstPeerKey,
            signature: fakeSignature,
          ).toJson(),
        );
        expect(encoded, isNot(contains('Ayşe')));
      },
    );
  });

  group('through the controller', () {
    late FakePeerStore store;
    late FakeSettings settings;
    late RecordingTransport transport;
    late SessionController controller;

    Future<void> build(PeerReadResult answer) async {
      store = FakePeerStore(answer: answer);
      settings = FakeSettings();
      transport = RecordingTransport();
      controller = SessionController(
        peerStore: store,
        settings: settings,
        identityLoader: FakeIdentityLoader(),
        // The controller tears the loop down in the tear-down; this factory
        // never gets far enough to matter, and it keeps the test from needing a
        // socket at all.
        rendezvousClientFactory: FakePairingOnlySignaling.newClient,
        verifyPairing: FakePairVerifier().call,
        transport: transport,
        pairScopedDeviceId: FakeDeviceIdFactory().call,
        sessionIdFactory: countingSessionIds(),
        delay: RecordingDelay().call,
      );
      settings.write(SettingsKeys.rendezvousEndpoint, 'https://signal.example');
      await controller.bootstrap();
    }

    tearDown(() async => await controller.dispose());

    test(
      'an annotation set for one peer is not shown for another peer',
      () async {
        await build(PeerFound(peerOne));
        controller.setPeerAlias('Patron');
        expect(controller.names.displayName, 'Ayşe');
        expect(controller.names.alias, 'Patron');

        // The user pairs a new device. The old note stays with the old key and is
        // not carried over.
        final bool saved = await controller.completePairing(
          publicKey: secondPeerKey,
          discoveryId: 'room-two',
          freshAnnouncedName: 'Mehmet',
          pairedAtMs: 1735690000000,
        );
        expect(saved, isTrue);

        expect(controller.names.displayName, 'Mehmet');
        expect(
          controller.names.alias,
          isEmpty,
          reason: 'a note about Ayşe is not a note about Mehmet',
        );
        expect(controller.names.hasAlias, isFalse);
        expect(
          controller.aliasFor(firstPeerKey),
          'Patron',
          reason: 'and the old note is still there, for its own key',
        );
        expect(controller.aliasFor(secondPeerKey), isEmpty);
      },
    );

    test('an annotation never reaches the stored record', () async {
      await build(PeerFound(peerOne));
      controller.setPeerAlias('Patron');

      // Whatever is written to the store - on re-pairing, or on a later
      // announced name - carries the announced name and never the note.
      await controller.applyAnnouncedName('Ayşe Yılmaz');
      await controller.completePairing(
        publicKey: firstPeerKey,
        discoveryId: 'room-one',
        pairedAtMs: 1735690000000,
      );

      expect(store.writes, isNotEmpty);
      for (final KnownPeer written in store.writes) {
        expect(
          written.encode(),
          isNot(contains('Patron')),
          reason: written.encode(),
        );
        expect(written.toJson()['display_name'], isNot('Patron'));
      }
      expect(store.writes.last.announcedName, 'Ayşe Yılmaz');
    });

    test(
      'the announced name the peer sends is persisted, and the annotation is untouched',
      () async {
        await build(PeerFound(peerOne));
        controller.setPeerAlias('Patron');
        await controller.applyAnnouncedName('Ayşe Yılmaz');

        expect(controller.names.displayName, 'Ayşe Yılmaz');
        expect(
          controller.names.alias,
          'Patron',
          reason: 'the note belongs to this device, and survives a name change',
        );
        expect(controller.names.showsAnnouncedName, isTrue);
        expect(store.writes.single.announcedName, 'Ayşe Yılmaz');
        expect(settings.read(peerAliasKey(firstPeerKey)), 'Patron');
      },
    );

    test('a failed store write leaves the state alone', () async {
      await build(PeerFound(peerOne));
      store.throwOnWrite = StateError('kasa kilitli.');
      final bool saved = await controller.completePairing(
        publicKey: secondPeerKey,
        discoveryId: 'room-two',
        freshAnnouncedName: 'Mehmet',
      );
      expect(saved, isFalse);
      expect(
        controller.peer,
        peerOne,
        reason: 'nothing is adopted before it is on disk',
      );
      expect(controller.state, isA<SetupReconnecting>());
    });

    test(
      'a failed peer read never reaches the pairing screen through the controller',
      () async {
        // BUG 1, end to end: the real production symptom.
        await build(const PeerUnreadable(PeerKeyringEntryMissing()));

        expect(controller.state, isA<SetupBroken>());
        expect(controller.state.showsPairingScreen, isFalse);
        expect(controller.peer, isNull);
        expect(controller.state.canRetry, isTrue);

        // The channel cannot open a workspace either.
        controller.reportChannelOpen(true);
        expect(
          controller.state,
          isA<SetupBroken>(),
          reason: 'there is no peer to be connected to',
        );
        expect(controller.state.showsWorkspace, isFalse);
      },
    );

    test(
      'an explicit "pair a new device" is the only way to the pairing screen',
      () async {
        await build(PeerFound(peerOne));
        expect(controller.state, isA<SetupReconnecting>());
        expect(controller.state.showsPairingScreen, isFalse);

        await controller.openPairing();
        expect(controller.state, const SetupState.needsPairing());
        expect(controller.state.showsPairingScreen, isTrue);

        // And it can be backed out of, which is the escape the first-run screen
        // does not have.
        await controller.cancelPairing();
        expect(controller.state, isA<SetupReconnecting>());
        expect(controller.state.showsPairingScreen, isFalse);
      },
    );

    test(
      'the channel moves between connected and reconnecting, and only there',
      () async {
        await build(PeerFound(peerOne));

        controller.reportChannelOpen(true);
        expect(controller.state, const SetupState.connected());
        controller.reportChannelOpen(false);
        expect(controller.state, const SetupState.reconnecting());
        expect(
          controller.state.showsWorkspace,
          isTrue,
          reason: 'a saved pair owns the main screen even while offline',
        );
        expect(controller.state.showsPairingScreen, isFalse);
      },
    );

    test(
      'a first run is a first run, and the workspace is not shown',
      () async {
        await build(const PeerAbsent());
        expect(controller.state, const SetupState.firstRun());
        expect(controller.state.showsPairingScreen, isTrue);

        controller.reportChannelOpen(true);
        expect(
          controller.state,
          const SetupState.firstRun(),
          reason: 'a channel report cannot invent a peer',
        );
      },
    );

    test(
      'the self name round-trips through the settings, sanitised on both sides',
      () async {
        await build(PeerFound(peerOne));
        controller.setSelfName('  Ayşe$bell  ');
        expect(controller.selfName, 'Ayşe');
        expect(settings.read(SettingsKeys.selfName), 'Ayşe');

        // A value written by an older build, or by a hand-edited store.
        settings.values[SettingsKeys.selfName] = 'Bo${zeroWidthSpace}zul';
        await controller.bootstrap();
        expect(controller.selfName, 'Bo zul');
      },
    );

    test(
      'the endpoint comes from the settings, and a blank one is refused',
      () async {
        await build(PeerFound(peerOne));
        expect(controller.endpoint, 'https://signal.example');

        expect(
          controller.saveConnectionSettings(
            endpoint: '  ws://localhost:8787  ',
            iceText: '  stun:x  ',
          ),
          isTrue,
        );
        expect(controller.endpoint, 'ws://localhost:8787');
        expect(settings.read(SettingsKeys.iceServers), 'stun:x');

        expect(
          controller.saveConnectionSettings(endpoint: '   ', iceText: ''),
          isFalse,
        );
        expect(
          controller.endpoint,
          'ws://localhost:8787',
          reason: 'a blank endpoint is not stored',
        );
      },
    );
  });

  group('the avatar initials', () {
    test('use Turkish casing, as toLocaleUpperCase("tr-TR") did', () {
      // TS: `peerName.slice(0, 2).toLocaleUpperCase("tr-TR")` at
      // `src/ChatCallWorkspace.tsx:218`.
      expect(PeerNameView(announcedName: 'Ayşe').avatarInitials, 'AY');
      expect(PeerNameView(announcedName: 'iğne').avatarInitials, 'İĞ');
      expect(PeerNameView(announcedName: 'ıslak').avatarInitials, 'IS');
      expect(PeerNameView(announcedName: 'Kişi').avatarInitials, 'Kİ');
      // With no announced name the initials are the PLACEHOLDER's, because the
      // placeholder is the primary slot. TS: `peerName.slice(0, 2)` over
      // `peerAlias || peerAnnouncedName || defaultPeerName`.
      expect(PeerNameView(announcedName: '').avatarInitials, 'Kİ');
      // And the annotation is not in the primary slot, so it is not the initials.
      expect(
        PeerNameView(announcedName: 'Ayşe', alias: 'zz').avatarInitials,
        'AY',
      );
    });
  });
}
