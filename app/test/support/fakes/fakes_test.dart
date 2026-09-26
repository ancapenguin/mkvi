/// The fakes' own tests.
///
/// Every fake here is a piece of test infrastructure that silently decides what a
/// whole layer's tests are allowed to claim. If a fake answers an unarranged
/// call, or loses the order of the calls it recorded, or swallows a scripted
/// error, then every test above it is green for a reason nobody wrote down.
///
/// So the suite below is not a coverage exercise. It asserts four things, for
/// every fake:
///
/// 1. **An unarranged call goes red.** Not "returns null", not "returns 0" -
///    raises [UnscriptedCallError].
/// 2. **The record keeps the order.** `log.order` is the contract Faz 5 models
///    as data.
/// 3. **A scripted error propagates.** A fake that cannot throw cannot prove a
///    swallowed error was removed.
/// 4. **Teardown closes what it opened.** A leaked track or stream controller
///    is a leak in the tests too.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/chat/chat_channel.dart';
import 'package:mkvi/chat/chat_controller.dart';
import 'package:mkvi/chat/file_sink.dart';
import 'package:mkvi/chat/history_store.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/file_frame.dart';
import 'package:mkvi/media/media.dart';
import 'package:mkvi/session/identity.dart';
import 'package:mkvi/session/peer_store.dart';
import 'package:mkvi/session/setup_state.dart';
import 'package:mkvi/signaling/rendezvous_client.dart';
import 'package:mkvi/signaling/signal_payload.dart';
import 'package:mkvi/update/update.dart';

import 'fakes.dart';

/// Names the member an unarranged call was refused for, so a failure names the
/// member instead of printing the whole constructor text.
Matcher isUnscripted(String member) => throwsA(
  isA<UnscriptedCallError>().having(
    (UnscriptedCallError e) => e.member,
    'member',
    member,
  ),
);

/// A `file-offer` frame as the peer would send it.
FileOfferMessage fakeOfferFrame(String id, {String name = 'rapor.pdf'}) =>
    FileOfferMessage(id: id, name: name, mime: 'application/pdf', size: 1024);

/// An [UpdateOffer] for a store fake that has no client to get one from.
///
/// [UpdateOffer] has a private constructor in production on purpose, so the only
/// honest way to have one is to parse a feed - which is what this does.
UpdateOffer _offerFromFeed() {
  final ReleaseVersion current =
      ReleaseVersion.tryParse(fakeCurrentVersion)!;
  final UpdateManifest manifest = parseUpdateManifest(fakeFeedJson(), current);
  if (manifest is! ManifestOffersRelease) {
    throw StateError('the fixture feed did not offer a release: $manifest');
  }
  return manifest.offer;
}

void main() {
  group('ScriptLog', () {
    test('refuses a member no test arranged, and keeps the receipt', () {
      final ScriptLog log = ScriptLog('X');
      expect(() => log.record('open'), throwsA(isA<UnscriptedCallError>()));
      expect(log.calls.single.member, 'open');
      expect(log.unrecorded.single.member, 'open');
    });

    test('accepts a written default without a test arranging it', () {
      final ScriptLog log = ScriptLog('X')
        ..define('read', 'returns the stored value');
      log.record('read');
      expect(log.unrecorded, isEmpty);
      expect(log.writtenDefaults.keys, <String>['read']);
    });

    test('keeps the call order, and counts one member without losing it', () {
      final ScriptLog log = ScriptLog('X')
        ..define('send', 'appends to the wire')
        ..define('abort', 'drops the wire');
      log
        ..record('send', detail: 'a')
        ..record('abort', detail: 'b')
        ..record('send', detail: 'c');
      expect(log.order, <String>['send', 'abort', 'send']);
      expect(log.countOf('send'), 2);
      expect(log.detailsOf('send'), <Object?>['a', 'c']);
    });

    test('arrangeAll arranges every member it is given, and no other', () {
      // There is deliberately no "allow anything" switch: a fake that answers a
      // call nobody arranged proves nothing, and it proves it loudly green. So
      // `arrangeAll` is a shorthand for `arrange` over a list, not a wildcard.
      final ScriptLog log = ScriptLog('X')
        ..arrangeAll(<String>['anything', 'else']);
      log
        ..record('anything')
        ..record('else');
      expect(log.unrecorded, isEmpty);

      expect(
        () => log.record('somethingElse'),
        throwsA(isA<UnscriptedCallError>()),
      );
      expect(log.unrecorded.single.member, 'somethingElse');
    });

    test('an empty arrangeAll arranges nothing, so everything still raises', () {
      final ScriptLog log = ScriptLog('X')..arrangeAll(<String>[]);
      expect(() => log.record('anything'), throwsA(isA<UnscriptedCallError>()));
    });

    test('poll records but never refuses', () {
      final ScriptLog log = ScriptLog('X')..poll('isOpen');
      expect(log.calls.single.member, 'isOpen');
      expect(log.unrecorded, isEmpty);
    });

    test('clear forgets the calls but keeps the arrangements', () {
      final ScriptLog log = ScriptLog('X')
        ..define('read', 'returns the stored value')
        ..record('read');
      log.clear();
      expect(log.isEmpty, isTrue);
      log.record('read');
      expect(log.unrecorded, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------
  group('FakePeerStore', () {
    test('an unarranged read raises instead of answering PeerAbsent', () {
      final FakePeerStore store = FakePeerStore();
      expect(store.readPeer, isUnscripted('readPeer'));
    });

    test('the three read outcomes are all reachable by name', () async {
      expect(await FakePeerStore.absent().readPeer(), isA<PeerAbsent>());
      expect(await FakePeerStore.paired().readPeer(), isA<PeerFound>());
      expect(
        await FakePeerStore.unreadable().readPeer(),
        isA<PeerUnreadable>(),
      );
    });

    test('a scripted throw from the store propagates', () {
      final FakePeerStore store = FakePeerStore()
        ..readThrows = StateError('kasa kilitli');
      expect(store.readPeer, throwsStateError);
    });

    test('a scripted write throw propagates and stores nothing', () async {
      final FakePeerStore store = FakePeerStore.paired()
        ..writeThrows = StateError('yazılamadı');
      await expectLater(
        store.writePeer(fakeKnownPeer()),
        throwsStateError,
      );
      expect(store.writes, isEmpty);
      expect(store.stored, isNull);
    });

    test('the record is written in the order it was written', () async {
      final FakePeerStore store = FakePeerStore.absent();
      await store.writePeer(fakeKnownPeer(announcedName: 'Ada'));
      await store.writePeer(fakeKnownPeer(announcedName: 'Grace'));
      expect(
        store.writes.map((KnownPeer p) => p.announcedName),
        <String>['Ada', 'Grace'],
      );
      expect(store.writeCount, 2);
    });

    test('a local alias can never reach the serialized record', () async {
      final FakePeerStore store = FakePeerStore.paired();
      await store.writePeer(fakeKnownPeer(announcedName: 'Ada'));
      expect(store.storedJson, isNot(contains('alias')));
    });
  });

  group('FakeLocalSettings', () {
    test('reads the value it wrote, in order', () {
      final FakeLocalSettings settings = FakeLocalSettings();
      settings.write('mkvi.selfName', 'Ada');
      expect(settings.read('mkvi.selfName'), 'Ada');
      expect(settings.log.order, <String>['write', 'read']);
    });

    test('a strict read of an undeclared key raises', () {
      final FakeLocalSettings settings = FakeLocalSettings(strictReads: true);
      expect(
        () => settings.read('mkvi.peerAlias.xyz'),
        isUnscripted('read:mkvi.peerAlias.xyz'),
      );
    });

    test('a declared key reads as absent rather than raising', () {
      final FakeLocalSettings settings = FakeLocalSettings(strictReads: true)
        ..declare('mkvi.selfName');
      expect(settings.read('mkvi.selfName'), isNull);
    });

    test('a write declares the key for a later strict read', () {
      final FakeLocalSettings settings = FakeLocalSettings(strictReads: true);
      settings.write('mkvi.iceServers', 'stun:stun.example');
      expect(settings.read('mkvi.iceServers'), 'stun:stun.example');
    });
  });

  group('FakeDeviceIdentityLoader', () {
    test('load counts every call, which is the Faz 4 counter', () async {
      final FakeDeviceIdentityLoader loader = FakeDeviceIdentityLoader();
      expect(loader.calls, 0);
      await loader.load();
      await loader.load();
      expect(loader.calls, 2);
    });

    test('the first N reads throw, then it succeeds', () async {
      final FakeDeviceIdentityLoader loader = FakeDeviceIdentityLoader(
        failuresBeforeSuccess: 2,
      );
      await expectLater(loader.load(), throwsStateError);
      await expectLater(loader.load(), throwsStateError);
      expect(await loader.load(), isA<DeviceIdentity>());
      expect(loader.calls, 3);
    });

    test('every signed transcript is kept, in order', () async {
      final FakeDeviceIdentityLoader loader = FakeDeviceIdentityLoader();
      await loader.identity.sign('mkvi/discover/v2/room/a');
      await loader.identity.sign('mkvi/discover/v2/room/b');
      expect(loader.signedTranscripts, <String>[
        'mkvi/discover/v2/room/a',
        'mkvi/discover/v2/room/b',
      ]);
    });
  });

  group('FakePairingVerifier', () {
    test('an unarranged verdict raises rather than answering', () {
      final FakePairingVerifier verifier = FakePairingVerifier();
      expect(verifier.call('pk', 'transcript', 'sig'), isUnscripted('call'));
    });

    test('a scripted refusal is a refusal, and the transcript is kept', () async {
      final FakePairingVerifier verifier = FakePairingVerifier()
        ..verify(accept: false);
      expect(await verifier.call('pk', 'mkvi/discover/v1/room', 'sig'), isFalse);
      expect(verifier.transcriptAt(0), 'mkvi/discover/v1/room');
    });

    test('a verifier bridge that throws propagates', () {
      final FakePairingVerifier verifier = FakePairingVerifier(accept: true)
        ..throwOnVerify = StateError('köprü yok');
      expect(verifier.call('pk', 't', 's'), throwsA(isA<StateError>()));
    });
  });

  group('FakePairScopedDeviceIdFactory', () {
    test('mints one id per call and records the pair it was for', () async {
      final FakePairScopedDeviceIdFactory ids = FakePairScopedDeviceIdFactory();
      final String first = await ids.call('room', 'pk-a');
      final String second = await ids.call('room', 'pk-b');
      expect(ids.minted, 2);
      expect(ids.calls.first.publicKey, 'pk-a');
      expect(first, isNot(second));
    });
  });

  group('ScriptedSignalingSocket', () {
    test('records the frames and the close arguments, in order', () {
      final ScriptedSignalingSocket socket = ScriptedSignalingSocket(
        Uri.parse('wss://signal.example/v1/peer?pair=abc'),
      );
      socket.send('one');
      socket.send('two');
      socket.close(1000, 'bitti');
      expect(socket.sent, <String>['one', 'two']);
      expect(socket.closeCalls.single.code, 1000);
      expect(socket.log.order, <String>['send', 'send', 'close']);
      expect(socket.readyState, SignalingSocket.closed);
    });

    test('an identity frame reaches the client in the shape it was built', () {
      final ScriptedSignalingSocket socket = ScriptedSignalingSocket(
        Uri.parse('wss://signal.example/v1/peer'),
      );
      String? seen;
      socket.onMessage = (String data) => seen = data;
      announceIdentity(socket);
      expect(seen, contains('"kind":"identity"'));
      expect(seen, contains(fakePeerPublicKey));
    });

    test('a legacy peer sends no session key at all', () {
      final ScriptedSignalingSocket socket = ScriptedSignalingSocket(
        Uri.parse('wss://signal.example/v1/peer'),
      );
      String? seen;
      socket.onMessage = (String data) => seen = data;
      announceIdentity(socket, legacy: true);
      expect(seen, isNot(contains('session')));
    });
  });

  // ---------------------------------------------------------------------------
  // Chat
  // ---------------------------------------------------------------------------
  group('ScriptedChatChannel', () {
    test('records control and binary frames in one ordered list', () {
      final ScriptedChatChannel channel = ScriptedChatChannel();
      channel.send(fakeChatFrame('m1'));
      channel.sendFrame(
        FileFrame(id: 'f1', payload: Uint8List.fromList(<int>[1, 2])),
      );
      channel.send(fakeOfferFrame('f2'));
      expect(
        channel.wire.map((Object f) => f.runtimeType.toString()),
        <String>['ChatMessage', 'FileFrame', 'FileOfferMessage'],
      );
      expect(channel.frameCount, 3);
    });

    test('a closed channel with no arranged refusal raises', () {
      final ScriptedChatChannel channel = ScriptedChatChannel(isOpen: false);
      expect(() => channel.send(fakeChatFrame('m1')), isUnscripted('send'));
      expect(channel.wire, isEmpty, reason: 'the frame must not half-happen');
    });

    test('an arranged refusal carries its Turkish reason and keeps the frame',
        () {
      final ScriptedChatChannel channel = ScriptedChatChannel(isOpen: false)
        ..refuse(reason: 'Bağlantı kapatıldı.');
      final SendOutcome outcome = channel.send(fakeChatFrame('m1'));
      expect(outcome, isA<ChannelUnavailable>());
      expect((outcome as ChannelUnavailable).reason, 'Bağlantı kapatıldı.');
      expect(channel.refused, hasLength(1));
      expect(channel.controlFrames, isEmpty);
    });

    test('a per-line refusal lets the lines behind it out', () {
      final ScriptedChatChannel channel = ScriptedChatChannel()
        ..refuseTheseIds = <String>{'m2'};
      channel.send(fakeChatFrame('m1'));
      channel.send(fakeChatFrame('m2'));
      channel.send(fakeChatFrame('m3'));
      expect(
        channel.chats.map((ChatMessage m) => m.id),
        <String>['m1', 'm3'],
      );
      expect(channel.refused, hasLength(1));
    });

    test('a bounded refusal count stops refusing', () {
      final ScriptedChatChannel channel = ScriptedChatChannel()
        ..refuse(reason: 'Kanal meşgul.', times: 2);
      expect(channel.send(fakeChatFrame('a')), isA<ChannelUnavailable>());
      expect(channel.send(fakeChatFrame('b')), isA<ChannelUnavailable>());
      expect(channel.send(fakeChatFrame('c')), isA<FrameSent>());
    });
  });

  group('ScriptedHistoryStore', () {
    test('a read of an unseeded store raises when emptiness is not allowed',
        () {
      final ScriptedHistoryStore store = ScriptedHistoryStore(allowEmpty: false);
      expect(
        store.loadNewest(conversationId: 'default', limit: 50),
        isUnscripted('loadNewest'),
      );
    });

    test('pages come back oldest-first, which is the contract', () async {
      final ScriptedHistoryStore store = ScriptedHistoryStore(
        seed: <StoredMessage>[
          fakeStored('a', sentAt: fakeNoon.subtract(const Duration(minutes: 2))),
          fakeStored('b', sentAt: fakeNoon.subtract(const Duration(minutes: 1))),
          fakeStored('c', sentAt: fakeNoon),
        ],
      );
      final HistoryPage page = await store.loadNewest(
        conversationId: 'default',
        limit: 2,
      );
      expect(page.messages.map((StoredMessage m) => m.id), <String>['b', 'c']);
      expect(page.hasMore, isTrue);
    });

    test('a scripted read failure propagates, and only once', () async {
      final ScriptedHistoryStore store = ScriptedHistoryStore()
        ..failNextRead = StateError('kilitli');
      await expectLater(
        store.loadNewest(conversationId: 'default', limit: 10),
        throwsStateError,
      );
      final HistoryPage page = await store.loadNewest(
        conversationId: 'default',
        limit: 10,
      );
      expect(page.isEmpty, isTrue);
      expect(store.reads, 2);
    });

    test('a scripted append failure is a write failure, not a read one',
        () async {
      final ScriptedHistoryStore store = ScriptedHistoryStore()
        ..failNextAppend = StateError('disk dolu');
      await expectLater(
        store.append(
          conversationId: 'default',
          message: fakeStored('a'),
        ),
        throwsStateError,
      );
      expect(store.length, 0);
      expect(store.appends, 1);
    });

    test('appending a known id is a no-op, not a second row', () async {
      final ScriptedHistoryStore store = ScriptedHistoryStore();
      await store.append(conversationId: 'default', message: fakeStored('a'));
      await store.append(conversationId: 'default', message: fakeStored('a'));
      expect(store.length, 1);
      expect(store.appends, 2);
    });

    test('trimTo keeps the newest lines', () async {
      final ScriptedHistoryStore store = ScriptedHistoryStore(
        seed: <StoredMessage>[
          fakeStored('a', sentAt: fakeNoon.subtract(const Duration(minutes: 2))),
          fakeStored('b', sentAt: fakeNoon.subtract(const Duration(minutes: 1))),
          fakeStored('c', sentAt: fakeNoon),
        ],
      );
      await store.trimTo(conversationId: 'default', keep: 1);
      expect(store.storedIds, <String>['c']);
    });
  });

  group('ScriptedFileSink', () {
    test('a write to a transfer nobody opened raises instead of returning 0',
        () {
      final ScriptedFileSink sink = ScriptedFileSink();
      expect(
        sink.write(transferId: 'ghost', chunk: <int>[1, 2, 3]),
        isUnscripted('write'),
      );
    });

    test('a close of a transfer nobody opened raises', () {
      final ScriptedFileSink sink = ScriptedFileSink();
      expect(sink.close(transferId: 'ghost'), isUnscripted('close'));
    });

    test('abort is total, and leaves nothing behind', () async {
      final ScriptedFileSink sink = ScriptedFileSink();
      await sink.abort(transferId: 'never-opened');
      final String path = await sink.open(
        transferId: 't1',
        name: 'rapor.pdf',
        mime: 'application/pdf',
      );
      expect(sink.exists(path), isTrue);
      await sink.abort(transferId: 't1');
      expect(
        sink.disk,
        isEmpty,
        reason: 'an abort must not leave a 0 byte file behind',
      );
    });

    test('a short write reports fewer bytes than it was handed', () async {
      final ScriptedFileSink sink = ScriptedFileSink()..shortWriteBytes = 2;
      final String path = await sink.open(
        transferId: 't1',
        name: 'a.bin',
        mime: 'application/octet-stream',
      );
      final int stored = await sink.write(
        transferId: 't1',
        chunk: <int>[1, 2, 3, 4, 5],
      );
      expect(stored, 2);
      expect(sink.lengthOf(path), 2);
    });

    test('a sink that stores nothing says so', () async {
      // The zero-byte write is the defect class `FileSink.write` exists to
      // expose: a transfer that reports "wrote N bytes" must have written N.
      // Two one-byte writes, the first one swallowed, so the file holds exactly
      // one byte and the second return value proves the ledger agrees.
      final ScriptedFileSink sink = ScriptedFileSink()..zeroWrites = 1;
      final String path = await sink.open(
        transferId: 't1',
        name: 'a.bin',
        mime: 'application/octet-stream',
      );
      expect(await sink.write(transferId: 't1', chunk: <int>[1]), 0);
      expect(
        sink.lengthOf(path),
        0,
        reason: 'nothing was stored, so nothing is on the fake disk',
      );
      expect(await sink.write(transferId: 't1', chunk: <int>[1]), 1);
      expect(sink.lengthOf(path), 1);
      expect(sink.written, <String>['t1', 't1']);
    });

    test('a short write stores only what it reported', () async {
      // The other half of the same contract: a sink that reports fewer bytes
      // than it was handed must not have quietly written the rest.
      final ScriptedFileSink sink = ScriptedFileSink()..shortWriteBytes = 2;
      final String path = await sink.open(
        transferId: 't1',
        name: 'b.bin',
        mime: 'application/octet-stream',
      );
      expect(await sink.write(transferId: 't1', chunk: <int>[1, 2, 3, 4, 5]), 2);
      expect(sink.lengthOf(path), 2);
    });

    test('two transfers of the same name get two paths', () async {
      final ScriptedFileSink sink = ScriptedFileSink();
      final String first = await sink.open(
        transferId: 't1',
        name: 'rapor.pdf',
        mime: 'application/pdf',
      );
      final String second = await sink.open(
        transferId: 't2',
        name: 'rapor.pdf',
        mime: 'application/pdf',
      );
      expect(first, isNot(second));
      expect(second, endsWith('rapor (1).pdf'));
    });

    test('a scripted open failure propagates and creates nothing', () async {
      final ScriptedFileSink sink = ScriptedFileSink()..failOpenFor = 'rapor';
      await expectLater(
        sink.open(transferId: 't1', name: 'rapor.pdf', mime: 'x'),
        throwsA(isA<FileSinkException>()),
      );
      expect(sink.existingPaths, isEmpty);
    });
  });

  group('ScriptedOutgoingFile', () {
    test('a declared size may disagree with the bytes', () {
      final ScriptedOutgoingFile file = ScriptedOutgoingFile(
        name: 'a.bin',
        bytes: <int>[1, 2, 3],
        declaredSize: 99,
      );
      expect(file.size, 99);
      expect(file.bytes, hasLength(3));
    });

    test('a short read is legal and returns what it had', () async {
      final ScriptedOutgoingFile file = ScriptedOutgoingFile(
        name: 'a.bin',
        bytes: <int>[1, 2, 3, 4],
      )..shortReadBytes = 1;
      expect(await file.read(offset: 0, length: 4), <int>[1]);
      expect(await file.read(offset: 3, length: 4), <int>[4]);
      expect(await file.read(offset: 4, length: 4), isEmpty);
    });

    test('a scripted read failure propagates once', () async {
      final ScriptedOutgoingFile file = ScriptedOutgoingFile(
        name: 'a.bin',
        bytes: <int>[1],
      )..failNextRead = StateError('dosya silindi');
      await expectLater(
        file.read(offset: 0, length: 1),
        throwsStateError,
      );
      expect(await file.read(offset: 0, length: 1), <int>[1]);
    });
  });

  // ---------------------------------------------------------------------------
  // Call
  // ---------------------------------------------------------------------------
  group('FakeCallClock', () {
    test('advance fires a due timer and lands the clock on the target', () {
      final DateTime start = DateTime.utc(2026, 1, 1);
      final FakeCallClock clock = FakeCallClock(start);
      int fired = 0;
      clock.start(const Duration(seconds: 45), () => fired += 1);
      clock.advance(const Duration(seconds: 44));
      expect(fired, 0);
      expect(clock.now, start.add(const Duration(seconds: 44)));
      clock.advance(const Duration(seconds: 1));
      expect(fired, 1);
      expect(clock.now, start.add(const Duration(seconds: 45)));
    });

    test('two timers due at different instants fire in deadline order', () {
      final FakeCallClock clock = FakeCallClock(DateTime.utc(2026, 1, 1));
      final List<String> order = <String>[];
      clock.start(const Duration(seconds: 30), () => order.add('offer'));
      clock.start(const Duration(seconds: 45), () => order.add('ring'));
      clock.advance(const Duration(seconds: 60));
      expect(order, <String>['offer', 'ring']);
    });

    test('a timer re-armed inside its own callback still fires', () {
      final FakeCallClock clock = FakeCallClock(DateTime.utc(2026, 1, 1));
      int fired = 0;
      void rearm() {
        fired += 1;
        if (fired < 3) clock.start(const Duration(seconds: 10), rearm);
      }

      clock.start(const Duration(seconds: 10), rearm);
      clock.advance(const Duration(seconds: 35));
      expect(fired, 3);
    });

    test('a cancelled timer does not fire, and a forced one does', () {
      final FakeCallClock clock = FakeCallClock(DateTime.utc(2026, 1, 1));
      int fired = 0;
      final CallTimerCancel cancel = clock.start(
        const Duration(seconds: 5),
        () => fired += 1,
      );
      cancel();
      clock.advance(const Duration(seconds: 10));
      expect(fired, 0);
      clock.fireAll();
      expect(fired, 1, reason: 'the machine must not depend on the guarantee');
    });

    test('refuses to guess when there is not exactly one live timer', () {
      final FakeCallClock clock = FakeCallClock();
      expect(() => clock.only, throwsStateError);
      clock.start(const Duration(seconds: 1), () {});
      expect(clock.only.after, const Duration(seconds: 1));
      clock.start(const Duration(seconds: 2), () {});
      expect(() => clock.only, throwsStateError);
    });

    test('records every arm, so a double arm is visible', () {
      final FakeCallClock clock = FakeCallClock();
      clock
        ..start(const Duration(seconds: 45), () {})
        ..start(const Duration(seconds: 45), () {});
      expect(clock.requestedDelays, <Duration>[
        const Duration(seconds: 45),
        const Duration(seconds: 45),
      ]);
    });

    test('reset forgets the timers and puts the clock back', () {
      final FakeCallClock clock = FakeCallClock(DateTime.utc(2026, 1, 1));
      clock.start(const Duration(seconds: 5), () {});
      clock.reset();
      expect(clock.history, isEmpty);
      expect(clock.reads, 0);
      expect(clock.now, DateTime.utc(2026, 9, 26, 12));
    });
  });

  group('FakeCallHarness', () {
    test('rings, accepts and connects without any wall-clock time', () {
      final FakeCallHarness harness = FakeCallHarness();
      addTearDown(harness.dispose);
      harness.answerAndConnect('a'.padRight(32, '0'));
      expect(harness.machine.status, CallStatus.connected);
      expect(harness.clock.now, DateTime.utc(2026, 9, 26, 12));
      expect(harness.transitions, isNotEmpty);
    });

    test('the 45 s ring timeout fires when the clock reaches it', () {
      final FakeCallHarness harness = FakeCallHarness();
      addTearDown(harness.dispose);
      harness.ring('b'.padRight(32, '0'));
      expect(harness.liveTimers, hasLength(1));
      expect(harness.onlyLiveTimer.after, const Duration(seconds: 45));
      harness.advance(const Duration(seconds: 45));
      expect(harness.machine.status, isNot(CallStatus.incoming));
    });

    test('the frames of a transition are readable in order', () {
      final FakeCallHarness harness = FakeCallHarness();
      addTearDown(harness.dispose);
      harness.dial(CallMode.audio, id: 'c'.padRight(32, '0'));
      expect(harness.sent, isNotEmpty);
      final CallTransition first = harness.transitions.first;
      expect(FakeCallHarness.shapeOf(first), isNotEmpty);
      expect(
        FakeCallHarness.framesOf(first).length,
        harness.sent.take(first.frames.length).length,
      );
    });

    test('ending a call disarms its timers', () {
      final FakeCallHarness harness = FakeCallHarness();
      addTearDown(harness.dispose);
      harness.answerAndConnect('d'.padRight(32, '0'));
      harness.end();
      expect(harness.liveTimers, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Media
  // ---------------------------------------------------------------------------
  group('ScriptedStatsProbe', () {
    test('a poll for an undeclared sender raises rather than answering 0', () {
      final ScriptedStatsProbe stats = ScriptedStatsProbe();
      expect(
        stats.framesEncoded('sender-screen'),
        isUnscripted('framesEncoded'),
      );
    });

    test('a declared sender answers, and every poll is kept in order', () async {
      final ScriptedStatsProbe stats = ScriptedStatsProbe()
        ..declareDefaultSenders(0);
      expect(await stats.framesEncoded(screenSenderId), 0);
      stats.bump(screenSenderId, 12);
      expect(await stats.framesEncoded(screenSenderId), 12);
      expect(stats.asked, <String>[screenSenderId, screenSenderId]);
      expect(stats.pollCounts[screenSenderId], 2);
    });

    test('defaultFrames covers every sender, which is the blunt instrument',
        () async {
      final ScriptedStatsProbe stats = ScriptedStatsProbe()
        ..defaultFrames = 3;
      expect(await stats.framesEncoded('anything'), 3);
    });

    test('a failing poll propagates and does not poison the next one', () async {
      final ScriptedStatsProbe stats = ScriptedStatsProbe(
        frameTally: <String, int>{screenSenderId: 7},
      )..failNextPoll = StateError('istatistik yok');
      await expectLater(
        stats.framesEncoded(screenSenderId),
        throwsStateError,
      );
      expect(await stats.framesEncoded(screenSenderId), 7);
    });
  });

  group('ScriptedTrack', () {
    test('stopped exactly once is a stronger claim than stopped', () async {
      final ScriptedTrack track = ScriptedTrack(kind: 'video');
      expect(track.isLive, isTrue);
      await track.stop();
      expect(track.isLive, isFalse);
      expect(track.stopCount, 1);
    });

    test('a scripted stop failure propagates', () {
      final ScriptedTrack track = ScriptedTrack(
        kind: 'audio',
        stopError: StateError('cihaz hata verdi'),
      );
      expect(track.stop, throwsStateError);
    });

    test('a mute the platform refuses is a failure, not a mute', () {
      final ScriptedTrack track = ScriptedTrack(kind: 'audio')
        ..failOnEnable = true;
      expect(() => track.enabled = false, throwsA(isA<String>()));
      expect(track.enabled, isTrue);
    });
  });

  group('ScriptedSender', () {
    test('records attaches and detaches in one ordered list', () async {
      final ScriptedSender sender = ScriptedSender(slot: 'camera');
      final ScriptedTrack track = ScriptedTrack(kind: 'video');
      await sender.replaceTrack(track);
      await sender.replaceTrack(null);
      expect(sender.calls, hasLength(2));
      expect(sender.detaches, hasLength(1));
      expect(sender.track, isNull);
    });

    test('a scripted replace failure propagates and leaves the old track',
        () async {
      final ScriptedSender sender = ScriptedSender(slot: 'camera')
        ..failAllReplaces = StateError('replace başarısız');
      await expectLater(
        sender.replaceTrack(ScriptedTrack(kind: 'video')),
        throwsStateError,
      );
      expect(sender.calls, hasLength(1));
      expect(sender.track, isNull);
    });
  });

  group('ScriptedSenderRegistry', () {
    test('open creates the three transceivers and raises one negotiation',
        () async {
      final ScriptedSenderRegistry registry = ScriptedSenderRegistry();
      final MediaSenderSet senders = await registry.open();
      expect(senders.audio.slot, 'audio');
      expect(senders.camera.slot, 'camera');
      expect(senders.screen.slot, 'screen');
      expect(registry.negotiations, hasLength(1));
      expect(registry.slots, <String>['audio', 'camera', 'screen']);
    });

    test('a scripted open failure propagates and raises no negotiation', () {
      final ScriptedSenderRegistry registry = ScriptedSenderRegistry()
        ..failOpen = StateError('bağlantı kurulamadı');
      expect(registry.open(), throwsStateError);
      expect(registry.negotiations, isEmpty);
    });
  });

  group('ScriptedCapture', () {
    test('hands back one track per device, labelled as the plugin does',
        () async {
      final ScriptedCapture capture = ScriptedCapture(devices: fakeDeviceList());
      final CapturedMedia media = await capture.getUserMedia(
        const MediaCaptureRequest(audio: true, video: true),
      );
      expect(media.firstAudio!.label, defaultMicLabel);
      expect(media.firstVideo!.label, defaultCameraLabel);
      expect(capture.created, hasLength(2));
    });

    test('a scripted answer that is an error is thrown, not returned', () {
      final ScriptedCapture capture = ScriptedCapture(requireScript: true)
        ..getUserMediaScript.add(StateError('izin yok'));
      expect(
        capture.getUserMedia(const MediaCaptureRequest(video: true)),
        throwsStateError,
      );
    });

    test('requireScript turns the cooperative default into a refusal', () {
      final ScriptedCapture capture = ScriptedCapture(requireScript: true);
      expect(
        capture.getUserMedia(const MediaCaptureRequest(video: true)),
        isUnscripted('getUserMedia'),
      );
    });

    test('a failing enumeration propagates', () {
      final ScriptedCapture capture = ScriptedCapture()
        ..failEnumerate = StateError('cihaz listelenemedi');
      expect(capture.enumerateDevices(), throwsStateError);
    });

    test('the display catalogue and the share record are both kept', () async {
      final ScriptedCapture capture = ScriptedCapture(
        sources: fakeDisplaySources(),
      );
      expect(await capture.displaySources(), hasLength(2));
      await capture.getDisplayMedia(fakeScreen());
      expect(capture.shared.single.id, 'screen-0');
    });

    test('a failing re-point propagates and records nothing', () {
      final ScriptedCapture capture = ScriptedCapture()
        ..failSelectAudioInput = StateError('cihaz yok');
      expect(
        capture.selectAudioInput('mic-9'),
        throwsStateError,
      );
      expect(capture.selectedInputs, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Update
  // ---------------------------------------------------------------------------
  group('ScriptedUpdateClock', () {
    test('only moves when a test moves it, and counts its reads', () {
      final ScriptedUpdateClock clock = ScriptedUpdateClock(
        DateTime.utc(2026, 3, 1, 9),
      );
      expect(clock.now(), DateTime.utc(2026, 3, 1, 9));
      expect(clock.now(), DateTime.utc(2026, 3, 1, 9));
      expect(clock.reads, 2);
      clock.advance(const Duration(hours: 6));
      expect(clock.now(), DateTime.utc(2026, 3, 1, 15));
    });
  });

  group('ScriptedHttpFetcher', () {
    test('an unarranged read raises instead of faking a dead server', () {
      final ScriptedHttpFetcher fetcher = ScriptedHttpFetcher();
      expect(
        fetcher.read(
          Uri.parse(fakeLiveFeedUrl),
          maxBytes: 1024,
          abort: AbortToken(),
        ),
        isUnscripted('read'),
      );
    });

    test('an unarranged download raises, so a silent stream is impossible', () {
      final ScriptedHttpFetcher fetcher = ScriptedHttpFetcher();
      expect(
        fetcher
            .download(
              Uri.parse(fakeLiveFeedUrl),
              maxBytes: 1024,
              abort: AbortToken(),
            )
            .toList(),
        isUnscripted('download'),
      );
    });

    test('records the URLs and the caps it was given', () async {
      final ScriptedHttpFetcher fetcher = ScriptedHttpFetcher()
        ..feed = const FeedReadOk(body: <int>[1, 2, 3], declaredLength: 3);
      await fetcher.read(
        Uri.parse(fakeLiveFeedUrl),
        maxBytes: 99,
        abort: AbortToken(),
      );
      expect(fetcher.readCaps, <int>[99]);
      expect(fetcher.requests, 1);
    });

    test('an abort token stops the stream and says so', () async {
      final AbortToken abort = AbortToken();
      final ScriptedHttpFetcher fetcher = ScriptedHttpFetcher()
        ..downloadEvents = fakeArtifactEvents(fakeSignedArtifact(length: 8))
        ..beforeEvent = (int index) {
          if (index == 1) abort.abort();
        };
      final List<DownloadEvent> events = await fetcher
          .download(
            Uri.parse(fakeLiveFeedUrl),
            maxBytes: 1024,
            abort: abort,
          )
          .toList();
      expect(events.last, isA<DownloadAborted>());
      expect(fetcher.chunksDelivered, lessThan(2));
    });
  });

  group('ScriptedSignatureVerifier', () {
    test('compares the bytes the store holds, not a flag', () async {
      final ScriptedUpdateFileStore files = ScriptedUpdateFileStore();
      final List<int> artifact = fakeSignedArtifact();
      final ScriptedSignatureVerifier verifier = ScriptedSignatureVerifier(
        files: files,
        signedDigest: fakeDigest64(artifact),
      )..keyState = const ReleaseKeyPrehashed();
      final StagedArtifact staged = await files.openStaging(_offerFromFeed());
      await files.append(staged, artifact);
      expect(
        await verifier.verifyArtifact(
          artifactPath: staged.path,
          byteLength: artifact.length,
          signatureB64: fakeArtifactSignature,
          publicKeyB64: fakePrehashedKey,
        ),
        isA<ArtifactSignatureValid>(),
      );
    });

    test('one flipped byte anywhere rejects', () async {
      final ScriptedUpdateFileStore files = ScriptedUpdateFileStore();
      final List<int> artifact = fakeSignedArtifact();
      final ScriptedSignatureVerifier verifier = ScriptedSignatureVerifier(
        files: files,
        signedDigest: fakeDigest64(artifact),
      )..keyState = const ReleaseKeyPrehashed();
      final StagedArtifact staged = await files.openStaging(_offerFromFeed());
      final List<int> tampered = <int>[...artifact];
      tampered[tampered.length - 1] ^= 0x01;
      await files.append(staged, tampered);
      expect(
        await verifier.verifyArtifact(
          artifactPath: staged.path,
          byteLength: tampered.length,
          signatureB64: fakeArtifactSignature,
          publicKeyB64: fakePrehashedKey,
        ),
        isA<ArtifactSignatureRejected>(),
      );
    });

    test('a length that disagrees with the disk rejects', () async {
      final ScriptedUpdateFileStore files = ScriptedUpdateFileStore();
      final List<int> artifact = fakeSignedArtifact();
      final ScriptedSignatureVerifier verifier = ScriptedSignatureVerifier(
        files: files,
        signedDigest: fakeDigest64(artifact),
      )..keyState = const ReleaseKeyPrehashed();
      final StagedArtifact staged = await files.openStaging(_offerFromFeed());
      await files.append(staged, artifact);
      expect(
        await verifier.verifyArtifact(
          artifactPath: staged.path,
          byteLength: artifact.length - 1,
          signatureB64: fakeArtifactSignature,
          publicKeyB64: fakePrehashedKey,
        ),
        isA<ArtifactSignatureRejected>(),
      );
    });

    test('a legacy key is reported as itself, never as tampering', () async {
      final ScriptedSignatureVerifier verifier = ScriptedSignatureVerifier(
        files: ScriptedUpdateFileStore(),
      )..keyState = const ReleaseKeyLegacy();
      expect(
        await verifier.verifyArtifact(
          artifactPath: 'yok',
          byteLength: 0,
          signatureB64: 'sig',
          publicKeyB64: fakeLegacyKey,
        ),
        isA<ArtifactKeyIsLegacy>(),
      );
    });

    test('an unarranged key state raises: every state leads somewhere', () {
      final ScriptedSignatureVerifier verifier = ScriptedSignatureVerifier(
        files: ScriptedUpdateFileStore(),
      );
      expect(verifier.classifyKey(fakePrehashedKey), isUnscripted('classifyKey'));
    });

    test('a verifier that throws propagates, for the fail-closed path', () {
      final ScriptedSignatureVerifier verifier = ScriptedSignatureVerifier(
        files: ScriptedUpdateFileStore(),
      )..throwsOnVerify = StateError('köprü yok');
      expect(
        verifier.verifyArtifact(
          artifactPath: 'p',
          byteLength: 0,
          signatureB64: 's',
          publicKeyB64: 'k',
        ),
        throwsStateError,
      );
    });
  });

  group('ScriptedInstallerLauncher', () {
    test('an unarranged outcome raises: the default must never be success', () {
      final ScriptedInstallerLauncher installer = ScriptedInstallerLauncher();
      expect(installer.launch('mkvi-setup.exe'), isUnscripted('launch'));
      expect(installer.launched, isEmpty);
    });

    test('records every launch, in order', () async {
      final ScriptedInstallerLauncher installer = ScriptedInstallerLauncher()
        ..outcome = const InstallStarted();
      await installer.launch('a.exe');
      await installer.launch('b.exe');
      expect(installer.launched, <String>['a.exe', 'b.exe']);
      expect(installer.launches, 2);
    });

    test('a scripted launch failure propagates and launches nothing', () {
      final ScriptedInstallerLauncher installer = ScriptedInstallerLauncher()
        ..outcome = const InstallStarted()
        ..throwsOnLaunch = StateError('dosya yok');
      expect(installer.launch('a.exe'), throwsStateError);
      expect(installer.launched, isEmpty);
    });
  });

  group('ScriptedUpdateFileStore', () {
    test('an append to a staging file nobody opened raises', () {
      final ScriptedUpdateFileStore files = ScriptedUpdateFileStore();
      expect(
        files.append(
          const StagedArtifact(
            path: 'ghost.part',
            fileName: 'ghost.exe',
            byteLength: 0,
          ),
          <int>[1, 2, 3],
        ),
        isUnscripted('append'),
      );
    });

    test('a commit of something never staged raises', () {
      final ScriptedUpdateFileStore files = ScriptedUpdateFileStore();
      expect(
        files.commit(
          const StagedArtifact(
            path: 'ghost.part',
            fileName: 'ghost.exe',
            byteLength: 0,
          ),
        ),
        isUnscripted('commit'),
      );
    });

    test('the operation order is the ordering contract', () async {
      final ScriptedUpdateFileStore files = ScriptedUpdateFileStore();
      final StagedArtifact staged = await files.openStaging(_offerFromFeed());
      await files.append(staged, <int>[1, 2]);
      await files.commit(staged);
      expect(files.operations, <String>['open', 'append', 'commit']);
      expect(files.commits, 1);
      expect(files.hasStagingFiles, isFalse);
    });

    test('a discard leaves nothing runnable behind', () async {
      final ScriptedUpdateFileStore files = ScriptedUpdateFileStore();
      final StagedArtifact staged = await files.openStaging(_offerFromFeed());
      await files.append(staged, <int>[1]);
      await files.discard(staged);
      expect(files.hasStagingFiles, isFalse);
      expect(files.committed, isEmpty);
      expect(staged.path, endsWith(StagedArtifact.stagingExtension));
    });
  });

  // ---------------------------------------------------------------------------
  // The harnesses
  // ---------------------------------------------------------------------------
  group('FakeChatHarness', () {
    test('a line is written down before the channel is touched', () {
      final FakeChatHarness harness = FakeChatHarness(channelOpen: false)
        ..channel.refuse(reason: 'Bağlantı kapatıldı.');
      addTearDown(harness.dispose);
      final SendResult result = harness.send('merhaba');
      expect(result, isA<MessageQueued>());
      expect(harness.controller.timeline.length, 1);
      expect(harness.controller.queuedCount, 1);
      expect(harness.controller.isHoldingForReconnect, isTrue);
    });

    test('opening the channel flushes the queue oldest first', () {
      final FakeChatHarness harness = FakeChatHarness(channelOpen: false);
      addTearDown(harness.dispose);
      harness.send('birinci');
      harness.send('ikinci');
      expect(harness.controller.queuedCount, 2);
      harness.openChannel();
      expect(harness.controller.queuedCount, 0);
      expect(
        harness.channel.chats.map((ChatMessage m) => m.text),
        <String>['birinci', 'ikinci'],
      );
    });

    test('a channel that closes mid-conversation holds the next line', () {
      final FakeChatHarness harness = FakeChatHarness();
      addTearDown(harness.dispose);
      harness.send('birinci');
      harness.closeChannel();
      harness.send('ikinci');
      expect(harness.controller.queuedCount, 1);
      expect(
        harness.controller.queue.single.body,
        'ikinci',
        reason: 'a close must not lose a line, and must not reorder the queue',
      );
      expect(harness.controller.timeline.length, 2);
    });

    test('a received frame lands in the timeline and in the log', () async {
      final FakeChatHarness harness = FakeChatHarness();
      addTearDown(harness.dispose);
      expect(harness.receive(fakeChatFrame('r1', text: 'selam')), isTrue);
      expect(harness.receive(fakeChatFrame('r1', text: 'selam')), isFalse);
      await pumpUntil(() => harness.store.appends == 1);
      expect(harness.controller.timeline.length, 1);
      expect(harness.store.storedIds, <String>['r1']);
    });
  });

  group('FakeMediaHarness', () {
    test('a call that ends leaves no orphaned track', () async {
      final FakeMediaHarness harness = FakeMediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      expect(harness.controller.negotiationCount, 1);
      await harness.controller.startCall(video: false);
      expect(harness.liveTracks, isNotEmpty);
      await harness.controller.stop();
      expect(
        harness.orphanedTracks,
        isEmpty,
        reason:
            'a camera light on after the call is the defect this layer exists for',
      );
      expect(harness.liveTracks, isEmpty);
    });

    test('a mid-call attach never raises a negotiation', () async {
      final FakeMediaHarness harness = FakeMediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);
      await harness.controller.enableCamera();
      expect(harness.registry.negotiations, hasLength(1));
      expect(harness.controller.negotiationCount, 1);
    });

    test('the display catalogue is the OS list, not a literal', () async {
      final FakeMediaHarness harness = FakeMediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      final List<DisplaySource> sources = await harness
          .availableDisplaySources();
      expect(sources.map((DisplaySource s) => s.id), <String>[
        'screen-0',
        'window-3',
      ]);
    });

    test('the watchdog reads a declared sender, never an invented one', () async {
      final FakeMediaHarness harness = FakeMediaHarness();
      addTearDown(harness.dispose);
      await harness.open();
      await harness.controller.startCall(video: false);
      await harness.controller.startScreenShare();
      await pumpUntil(() => harness.stats.asked.isNotEmpty);
      expect(
        harness.stats.asked.every((String id) => id == screenSenderId),
        isTrue,
        reason: 'the watchdog must poll the screen sender it published to',
      );
    });
  });

  group('FakeSessionHarness', () {
    test('bootstrap counts the call and the identity reads it caused', () async {
      final FakeSessionHarness harness = FakeSessionHarness()..seedPaired();
      addTearDown(harness.dispose);
      await harness.bootstrap();
      expect(harness.bootstrapCalls, 1);
      expect(harness.identityCallsAtBootstrap, <int>[0]);
      await pumpUntil(() => harness.sockets.sockets.isNotEmpty);
      expect(harness.identity.calls, greaterThanOrEqualTo(1));
    });

    test('one bootstrap does not read the identity twice for itself', () async {
      final FakeSessionHarness harness = FakeSessionHarness()..seedPaired();
      addTearDown(harness.dispose);
      await harness.bootstrap();
      await pumpUntil(() => harness.sockets.sockets.isNotEmpty);
      expect(harness.bootstrapCalls, 1);
      expect(harness.identityCallsAtBootstrap, hasLength(1));
    });

    test('an absent store reaches the first run, and only that', () async {
      final FakeSessionHarness harness = FakeSessionHarness()..seedAbsent();
      addTearDown(harness.dispose);
      await harness.bootstrap();
      expect(harness.controller.state, isA<SetupFirstRun>());
      expect(harness.controller.state.showsPairingScreen, isTrue);
    });

    test('an unreadable store reaches broken, never the pairing screen',
        () async {
      final FakeSessionHarness harness = FakeSessionHarness()
        ..seedUnreadable();
      addTearDown(harness.dispose);
      await harness.bootstrap();
      expect(harness.controller.state, isA<SetupBroken>());
      expect(
        harness.controller.state.showsPairingScreen,
        isFalse,
        reason: 'this is the white pairing screen fix',
      );
    });

    test('a paired store starts the loop and opens a socket at the endpoint',
        () async {
      final FakeSessionHarness harness = FakeSessionHarness(
        endpoint: 'https://signal.example',
      )..seedPaired();
      addTearDown(harness.dispose);
      harness.watchDriver();
      await harness.bootstrap();
      await pumpUntil(() => harness.sockets.sockets.isNotEmpty);
      expect(harness.controller.state, isA<SetupReconnecting>());
      expect(harness.sockets.urls.single.host, 'signal.example');
      expect(harness.sockets.urls.single.scheme, 'wss');
    });

    test('the local annotation never reaches the encrypted record', () async {
      final FakeSessionHarness harness = FakeSessionHarness()..seedPaired();
      addTearDown(harness.dispose);
      await harness.bootstrap();
      harness.controller.setPeerAlias('Eşim');
      expect(harness.controller.names.alias, 'Eşim');
      expect(harness.peerStore.storedJson, isNot(contains('Eşim')));
    });

    test('no session payload the layer originates carries a name', () {
      for (final SignalPayload payload in outboundSignals()) {
        expect(payload.toString(), isNot(contains('Eşim')));
      }
    });
  });

  group('FakeUpdateHarness', () {
    test('an offered update installs, and the order is readable', () async {
      final FakeUpdateHarness harness = FakeUpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      final UpdateReport report = await harness.client.install(offer);
      expect(report, isA<UpdateInstalled>());
      expect(harness.storeOperations.first, 'open');
      expect(harness.storeOperations.last, 'commit');
      expect(
        harness.storeOperations
            .where((String op) => op == 'append')
            .length,
        greaterThan(1),
      );
      expect(harness.installer.launches, 1);
      expect(harness.files.hasStagingFiles, isFalse);
    });

    test('a rejected signature leaves nothing behind and launches nothing',
        () async {
      final FakeUpdateHarness harness = FakeUpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.rejectSignature();
      final UpdateReport report = await harness.client.install(offer);
      expect(harness.failureOf(report), isA<UpdateFailureSignatureRejected>());
      expect(harness.files.hasStagingFiles, isFalse);
      expect(harness.installer.launches, 0);
    });

    test('a legacy key is refused before the feed is contacted', () async {
      final FakeUpdateHarness harness = FakeUpdateHarness()..useLegacyKey();
      addTearDown(harness.dispose);
      final UpdateReport report = await harness.client.check();
      expect(harness.failureOf(report), isA<UpdateFailureLegacyKey>());
      expect(harness.fetcher.requests, 0);
    });

    test('a 404 feed is a transport failure, not a malformed manifest',
        () async {
      final FakeUpdateHarness harness = FakeUpdateHarness()..feedNotFound();
      addTearDown(harness.dispose);
      final UpdateReport report = await harness.client.check();
      expect(harness.failureOf(report), isA<UpdateFailureFeedUnreachable>());
    });

    test('a size mismatch is refused and nothing is committed', () async {
      final FakeUpdateHarness harness = FakeUpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.sizeMismatch();
      final UpdateReport report = await harness.client.install(offer);
      expect(
        harness.failureOf(report),
        isA<UpdateFailureArtifactSizeMismatch>(),
      );
      expect(harness.files.committed, isEmpty);
      expect(harness.installer.launches, 0);
    });

    test('a download that never says it finished is a failed download',
        () async {
      final FakeUpdateHarness harness = FakeUpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.truncateDownload();
      final UpdateReport report = await harness.client.install(offer);
      expect(harness.failureOf(report), isA<UpdateFailureDownloadFailed>());
      expect(harness.installer.launches, 0);
    });

    test('a refusing installer keeps the committed file', () async {
      final FakeUpdateHarness harness = FakeUpdateHarness()..refuseInstall();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      final UpdateReport report = await harness.client.install(offer);
      expect(report, isA<UpdateRefused>());
      expect(harness.installer.launches, 1);
      expect(harness.files.committed, isNotEmpty);
    });

    test('a flipped byte at the end of the artefact is still rejected',
        () async {
      final FakeUpdateHarness harness = FakeUpdateHarness();
      addTearDown(harness.dispose);
      final List<int> tampered = <int>[...fakeSignedArtifact()];
      tampered[tampered.length - 1] ^= 0x01;
      harness.offerUpdate(bytes: tampered);
      final UpdateReport check = await harness.client.check();
      final UpdateOffer offer = (check as UpdateOffered).offer;
      final UpdateReport report = await harness.client.install(offer);
      expect(harness.failureOf(report), isA<UpdateFailureSignatureRejected>());
    });
  });
}
