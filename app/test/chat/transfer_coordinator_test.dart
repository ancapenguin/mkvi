// The file-transfer layer, both directions.
//
// Every test here pins a defect that was real:
//
// * `crates/mkvi_core/src/state.rs` documents the 0-byte-file bug: the concurrency
//   cap was checked *after* the destination was created, so every rejected offer
//   left an empty file and a peer could fill the download folder with them.
// * `peer-transport.ts` emitted `file-progress` carrying `transfer.received` —
//   the peer's own byte count — and `App.tsx` `trackTransfer` wrote the row
//   straight from the last event with no ordering guard, so any out-of-order or
//   short event moved the bar backwards.
// * `cancelFile` removed the send and the receive under one id and then sent a
//   `file-cancel` unconditionally, so cancelling a finished transfer told the peer
//   its file had been cancelled.
// * `App.tsx` had `const [transfers, setTransfers] = useState([])` with append-only
//   writes, so the transfer list was unbounded.
// * `sendFile` rejected on a bad size and left the row `active` at 0% for ever,
//   because only a progress event could ever have moved it.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/file_frame.dart';
import 'package:mkvi/core/protocol/file_transfer.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';

import 'support/chat_fakes.dart';

/// A wire frame exactly as `streamFile` builds it.
Uint8List frameOf(String id, List<int> payload) =>
    FileFrame(id: id, payload: Uint8List.fromList(payload)).toBytes();

/// A well-formed transfer id: 32 copies of one hex letter, so a test can read it.
String tid(String letter) => letter * 32;

/// [count] bytes of filler, distinct enough to be recognisable in a file.
List<int> bytes(int count, [int seed = 0]) =>
    List<int>.generate(count, (int i) => (i + seed) % 256);

FileOfferMessage offerFor(
  String id, {
  required int size,
  String name = 'rapor.pdf',
  String mime = 'application/pdf',
}) => FileOfferMessage(id: id, name: safeName(name), mime: mime, size: size);

/// A coordinator with every seam faked, plus the handles a test pokes at.
final class Harness {
  Harness({
    RecordingChannel? channel,
    FakeFileSink? sink,
    int maxVisibleTransfers = TransferCoordinator.defaultMaxVisibleTransfers,
    int maxOutgoing = TransferCoordinator.defaultMaxOutgoing,
  }) : channel = channel ?? RecordingChannel(isOpen: true),
       sink = sink ?? FakeFileSink() {
    coordinator = TransferCoordinator(
      channel: this.channel,
      sink: this.sink,
      receiver: receiver,
      idFactory: CountingIds.sequence(64).call,
      maxVisibleTransfers: maxVisibleTransfers,
      maxOutgoing: maxOutgoing,
    );
  }

  final RecordingChannel channel;
  final FakeFileSink sink;
  final PeerFileReceiver receiver = PeerFileReceiver();
  late final TransferCoordinator coordinator;

  /// Announces a file and answers with the offer outcome.
  OfferOutcome announce(
    String id, {
    required int size,
    String name = 'rapor.pdf',
  }) => coordinator.onFileOffer(offerFor(id, size: size, name: name));

  /// Announces, accepts, and hands over every byte, then the completion.
  Future<void> deliver(
    String id, {
    required int size,
    required List<int> payload,
    String name = 'rapor.pdf',
    int? shortWriteBytes,
  }) async {
    announce(id, size: size, name: name);
    await coordinator.accept(id);
    final FakeFileSink target = sink;
    if (shortWriteBytes != null) target.shortWriteBytes = shortWriteBytes;
    await coordinator.onFrame(frameOf(id, payload));
    sink.shortWriteBytes = null;
    await coordinator.onComplete(id);
  }
}

void main() {
  group('progress is derived from bytes written, never from the peer', () {
    test(
      'a short write moves the bar by what the sink stored, not by the frame',
      () async {
        // THE DEFECT: `file-progress` carried `transfer.received` — how much the
        // *peer* said it sent — and the row was written from it verbatim. A sink
        // that stored 3 of 10 bytes produced a bar at 10 bytes.
        final Harness h = Harness();
        await h.deliver(
          'a' * 32,
          size: 10,
          payload: bytes(10),
          shortWriteBytes: 3,
        );

        expect(
          h.coordinator.claimedBytesOf('a' * 32),
          0,
          reason: 'the transfer is gone',
        );
        final TransferView view = h.coordinator.viewOf('a' * 32)!;
        expect(
          view.phase,
          TransferPhase.failed,
          reason: '3 of 10 declared bytes is not a finished file',
        );
        expect(view.transferred, 3, reason: 'the sink reported 3, so 3 it is');
        expect(view.detail, PeerProtocol.transferIncomplete);
      },
    );

    test('progress never goes backwards when a later write reports less', () async {
      // THE DEFECT, in the form the brief names it: the last event wins, so a
      // smaller number arriving later walks the bar back. `shortWriteBytes` is
      // set *after* the first frame, which is the moment a real sink starts
      // reporting less than it is handed — a full disk, a batching layer.
      final Harness h = Harness();
      final String id = tid('b');
      h.announce(id, size: 400);
      await h.coordinator.accept(id);

      await h.coordinator.onFrame(frameOf(id, bytes(100)));
      expect(h.coordinator.viewOf(id)!.transferred, 100);

      h.sink.shortWriteBytes = 10;
      await h.coordinator.onFrame(frameOf(id, bytes(100)));
      // The sink stored 10 more, so the truth is 110. The *frame* said 200 and
      // the peer therefore "claims" 200; the row must show 110 and never 200.
      expect(
        h.coordinator.viewOf(id)!.transferred,
        110,
        reason: 'bytes actually written, not bytes the peer announced',
      );
      expect(h.coordinator.claimedBytesOf(id), 200);

      // A third frame that stores nothing at all must not move the bar either.
      h.sink.shortWriteBytes = 0;
      await h.coordinator.onFrame(frameOf(id, bytes(100)));
      expect(h.coordinator.viewOf(id)!.transferred, 110);
      expect(h.coordinator.claimedBytesOf(id), 300);

      // And a reported number that is *smaller* than what is already on screen is
      // impossible to reach: the counter is a running sum, not a claim.
      expect(h.coordinator.viewOf(id)!.transferred, lessThan(300));
      expect(h.coordinator.viewOf(id)!.transferred, greaterThanOrEqualTo(110));
    });

    test(
      'a sink that stores nothing still leaves the row short, not full',
      () async {
        final Harness h = Harness();
        final String id = tid('c');
        h.announce(id, size: 64);
        await h.coordinator.accept(id);
        h.sink.shortWriteBytes = 0;
        await h.coordinator.onFrame(frameOf(id, bytes(64)));
        await h.coordinator.onComplete(id);

        final TransferView view = h.coordinator.viewOf(id)!;
        expect(view.phase, TransferPhase.failed);
        expect(view.transferred, 0);
        expect(view.percent, 0);
        expect(
          h.sink.disk,
          isEmpty,
          reason: 'a transfer that stored nothing must leave nothing on disk',
        );
      },
    );

    test('the sending side advances by the bytes it actually read', () async {
      final RecordingChannel channel = RecordingChannel(isOpen: true);
      final Harness h = Harness(channel: channel);
      final FakeOutgoingFile file = FakeOutgoingFile(
        name: 'notlar.txt',
        bytes: bytes(5000),
        mime: 'text/plain',
      )..shortReadBytes = 1000;

      final SendFileOutcome offered = h.coordinator.offerFile(file);
      final FileOffered sent = offered as FileOffered;
      expect(sent.view.total, 5000);
      expect(sent.view.phase, TransferPhase.offered);

      // The peer accepts; the source only ever hands back 1000 bytes at a time.
      channel.fileFrames.clear();
      await h.coordinator.onAccept(sent.view.id);

      expect(
        channel.fileFrames.fold<int>(
          0,
          (int sum, FileFrame f) => sum + f.payloadLength,
        ),
        5000,
        reason: 'the whole file went out, in five chunks',
      );
      expect(file.reads, 5);
      expect(h.coordinator.viewOf(sent.view.id)!.phase, TransferPhase.done);
      expect(h.coordinator.viewOf(sent.view.id)!.transferred, 5000);
      expect(channel.completes.single.id, sent.view.id);
    });
  });

  group('a refused transfer leaves nothing on disk', () {
    test('a declined offer is never opened', () async {
      // THE DEFECT: the cap was checked after the file was created, so a rejected
      // offer left a 0 byte file behind — `unique_path` then handed the next
      // attempt a *different* name and the folder filled with empty ones.
      final Harness h = Harness();
      h.announce('d' * 32, size: 2048);

      expect(h.sink.opened, isEmpty, reason: 'announced, nothing created');
      expect(h.sink.disk, isEmpty);
      expect(h.coordinator.viewOf('d' * 32)!.phase, TransferPhase.offered);

      final DecisionOutcome decision = h.coordinator.decline('d' * 32);

      expect(decision, isA<DecisionRefused>());
      expect(
        h.sink.opened,
        isEmpty,
        reason: 'declining must not create a file',
      );
      expect(h.sink.disk, isEmpty);
      expect(h.sink.aborted, isEmpty, reason: 'there was nothing to remove');
      expect(h.channel.declines.single.id, 'd' * 32);
      expect(
        h.channel.declines.single.reason,
        PeerProtocol.defaultFileDeclineReason,
      );
      expect(h.coordinator.viewOf('d' * 32)!.phase, TransferPhase.failed);
    });

    test('a cancel after an accept removes the partial file', () async {
      // THE DEFECT: `dropReceive` existed but `cancelFile` could leave a handle,
      // and a 0-byte file that never went away was the visible symptom.
      final Harness h = Harness();
      final String id = tid('e');
      h.announce(id, size: 4096);
      await h.coordinator.accept(id);
      await h.coordinator.onFrame(frameOf(id, bytes(1000)));

      expect(h.sink.disk, hasLength(1), reason: 'the partial file is real');
      expect(h.sink.lengthOf(h.sink.opened[id]!), 1000);

      expect(h.coordinator.cancel(id), isTrue);
      await pumpUntil(() => h.sink.disk.isEmpty);

      expect(h.sink.disk, isEmpty, reason: 'and it is gone, not empty');
      expect(h.sink.aborted, <String>[id]);
      expect(h.channel.cancels.single.id, id);
      expect(h.coordinator.viewOf(id)!.phase, TransferPhase.cancelled);
    });

    test("a peer's decline is reported with the peer's own reason", () async {
      // THE DEFECT: `setNotice(event.reason ?? "Dosya teklifi reddedildi.")`
      // threw the peer's text away half the time, and the sender could not tell
      // "there is no room" from "I do not accept this kind of file".
      final Harness h = Harness();
      final SendFileOutcome offered = h.coordinator.offerFile(
        FakeOutgoingFile(name: 'sunum.pptx', bytes: bytes(64)),
      );
      final String id = (offered as FileOffered).view.id;

      expect(h.coordinator.onDecline(id, 'Cihazımda yer kalmadı.'), isTrue);
      expect(h.coordinator.onDecline(id, 'Cihazımda yer kalmadı.'), isFalse);

      final TransferView view = h.coordinator.viewOf(id)!;
      expect(view.phase, TransferPhase.failed);
      expect(view.detail, 'Cihazımda yer kalmadı.');
      expect(view.stateLabel, ChatMessages.failed);
    });

    test('a decline with no reason still says something in Turkish', () {
      final Harness h = Harness();
      final String id =
          (h.coordinator.offerFile(
                    FakeOutgoingFile(name: 'a.bin', bytes: bytes(8)),
                  )
                  as FileOffered)
              .view
              .id;

      expect(h.coordinator.onDecline(id, null), isTrue);
      expect(h.coordinator.viewOf(id)!.detail, ChatMessages.offerDeclined);
    });
  });

  group('cancelling works from either side and is idempotent', () {
    test('a local cancel ends it, twice, with one frame on the wire', () async {
      // THE DEFECT: `cancelFile` sent a `file-cancel` unconditionally, so
      // cancelling an already-finished transfer told the peer its file had been
      // cancelled.
      final Harness h = Harness();
      final String id = tid('f');
      h.announce(id, size: 1024);
      await h.coordinator.accept(id);

      expect(h.coordinator.cancel(id), isTrue);
      expect(h.coordinator.cancel(id), isFalse, reason: 'idempotent');
      expect(h.coordinator.cancel(id), isFalse);
      expect(
        h.channel.cancels,
        hasLength(1),
        reason: 'and one frame, not three',
      );
      expect(h.coordinator.viewOf(id)!.phase, TransferPhase.cancelled);
      expect(
        h.coordinator.viewOf(id)!.detail,
        PeerProtocol.defaultFileCancelReason,
      );
    });

    test("a peer's cancel is honoured and answered with silence", () async {
      final Harness h = Harness();
      final String id = tid('a');
      h.announce(id, size: 1024);
      await h.coordinator.accept(id);
      await h.coordinator.onFrame(frameOf(id, bytes(500)));
      h.channel.reset();

      expect(h.coordinator.onPeerCancel(id, 'Yeterli yer yok.'), isTrue);
      await pumpUntil(() => h.sink.disk.isEmpty);

      expect(h.sink.disk, isEmpty, reason: 'the partial file is gone');
      expect(h.channel.cancels, isEmpty, reason: 'no echo, no second cancel');
      expect(h.coordinator.viewOf(id)!.phase, TransferPhase.cancelled);
      expect(h.coordinator.viewOf(id)!.detail, 'Yeterli yer yok.');
      expect(
        h.coordinator.onPeerCancel(id, null),
        isFalse,
        reason: 'idempotent',
      );
    });

    test('frames after a cancel are refused and write nothing', () async {
      final Harness h = Harness();
      final String id = tid('b');
      h.announce(id, size: 1024);
      await h.coordinator.accept(id);
      h.coordinator.cancel(id);
      await pumpUntil(() => h.sink.disk.isEmpty);

      final FrameOutcome outcome = await h.coordinator.onFrame(
        frameOf(id, bytes(1024)),
      );

      expect(outcome, isA<FrameRefused>());
      expect(h.sink.disk, isEmpty);
      expect(h.sink.written, isEmpty, reason: 'the write chain stopped');
    });

    test('a cancel that races the sink open deletes the file it created', () async {
      // TS: `if (this.receives.get(id) !== transfer) { void sink.abort(id); return; }`
      // — the guard that stops an accept landing after a cancel and leaving a file.
      final Harness h = Harness();
      final String id = tid('c');
      h.announce(id, size: 1024);

      final Future<DecisionOutcome> accepting = h.coordinator.accept(id);
      // The cancel lands while `sink.open` is still in flight.
      h.coordinator.cancel(id);
      final DecisionOutcome decision = await accepting;
      await pumpUntil(() => h.sink.disk.isEmpty);

      expect(decision, isA<DecisionRefused>());
      expect(
        h.channel.accepts,
        isEmpty,
        reason: 'the accept was never announced',
      );
      expect(h.sink.disk, isEmpty, reason: 'and the file it created is gone');
    });

    test(
      'cancelling a finished transfer changes nothing and says so',
      () async {
        final Harness h = Harness();
        final String id = tid('d');
        await h.deliver(id, size: 100, payload: bytes(100));

        expect(h.coordinator.viewOf(id)!.phase, TransferPhase.done);
        expect(h.coordinator.cancel(id), isFalse);
        expect(h.channel.cancels, isEmpty);
        expect(
          h.coordinator.viewOf(id)!.phase,
          TransferPhase.done,
          reason: 'a finished file is not a cancelled file',
        );
      },
    );

    test(
      'a file-complete for a transfer that is already settled is inert',
      () async {
        final Harness h = Harness();
        final String id = tid('e');
        await h.deliver(id, size: 100, payload: bytes(100));

        final FrameOutcome again = await h.coordinator.onComplete(id);

        expect(again, isA<FrameRefused>());
        expect(
          h.sink.closed,
          hasLength(1),
          reason: 'and it did not close twice',
        );
        expect(h.coordinator.viewOf(id)!.detail, '/tmp/mkvi/rapor.pdf');
        expect(h.coordinator.viewOf(id)!.phase, TransferPhase.done);
      },
    );
  });

  group('the size cap comes from the core constant', () {
    test(
      'an announced file over the cap is declined before anything is created',
      () {
        // THE DEFECT: the cap was checked after the file was created. Here the check
        // is the first thing `onFileOffer` does, and the Turkish text is formatted
        // from the same constant, so there is no second "512" to forget.
        final Harness h = Harness();
        final String id = tid('a');

        final OfferOutcome outcome = h.announce(
          id,
          size: PeerProtocol.maxFileBytes + 1,
        );

        expect(outcome, isA<OfferAutoDeclined>());
        expect(
          (outcome as OfferAutoDeclined).reason,
          'Dosya boyutu en fazla 512 MB olabilir.',
        );
        expect(h.sink.opened, isEmpty);
        expect(h.sink.disk, isEmpty);
        expect(
          h.coordinator.viewOf(id),
          isNull,
          reason: 'no row was ever created',
        );
        expect(h.channel.declines.single.id, id);
        expect(
          h.receiver.pendingCount,
          0,
          reason: 'and the receiver never saw it',
        );
      },
    );

    test('a frame for a refused offer is refused too', () async {
      final Harness h = Harness();
      final String id = tid('b');
      h.announce(id, size: PeerProtocol.maxFileBytes + 1);

      final FrameOutcome outcome = await h.coordinator.onFrame(
        frameOf(id, bytes(16)),
      );

      expect(outcome, isA<FrameRefused>());
      expect(
        (outcome as FrameRefused).reason,
        PeerProtocol.unauthorizedFileData,
      );
      expect(h.sink.disk, isEmpty);
    });

    test('a file exactly at the cap is admitted', () {
      final Harness h = Harness();
      expect(
        h.announce('c' * 32, size: PeerProtocol.maxFileBytes),
        isA<OfferAwaitingDecision>(),
      );
      expect(h.sink.disk, isEmpty, reason: 'admitted, still nothing created');
    });

    test(
      'an outgoing file over the cap is refused with a Turkish size range',
      () {
        final Harness h = Harness();
        final SendFileOutcome outcome = h.coordinator.offerFile(
          FakeOutgoingFile(
            name: 'buyuk.mkv',
            bytes: bytes(16),
            declaredSize: PeerProtocol.maxFileBytes + 1,
          ),
        );

        expect(outcome, isA<SendFileRefused>());
        expect(
          (outcome as SendFileRefused).reason,
          'Dosya boyutu 1 bayt ile 512 MB arasında olmalı.',
        );
        expect(h.channel.offers, isEmpty, reason: 'nothing was announced');
        expect(h.coordinator.views, isEmpty, reason: 'and no row was created');
      },
    );

    test('an outgoing file of zero bytes is refused', () {
      final Harness h = Harness();
      final SendFileOutcome outcome = h.coordinator.offerFile(
        FakeOutgoingFile(name: 'bos.bin', bytes: const <int>[]),
      );
      expect(outcome, isA<SendFileRefused>());
      expect(
        (outcome as SendFileRefused).reason,
        'Dosya boyutu 1 bayt ile 512 MB arasında olmalı.',
      );
    });
  });

  group('two transfers of the same name do not collide', () {
    test('get distinct paths, distinct sinks and distinct rows', () async {
      // THE DEFECT: nothing in the old stack keyed a transfer by anything other
      // than the id it happened to have, and the naming rule lived in three
      // places. Here the sink is opened per transfer id and returns the path it
      // chose, so the never-overwrite rule has exactly one home.
      final Harness h = Harness();
      final String first = tid('a');
      final String second = tid('b');

      h.announce(first, size: 100, name: 'rapor.pdf');
      h.announce(second, size: 200, name: 'rapor.pdf');
      expect(
        h.receiver.pendingIds,
        <String>[first, second],
        reason: 'both are pending, keyed by id and not by name',
      );

      await h.coordinator.accept(first);
      await h.coordinator.accept(second);
      await h.coordinator.onFrame(frameOf(first, bytes(100)));
      await h.coordinator.onFrame(frameOf(second, bytes(200)));
      await h.coordinator.onComplete(first);
      await h.coordinator.onComplete(second);

      expect(
        h.sink.opened,
        isEmpty,
        reason:
            'a closed transfer is no longer open; the sink is keyed by id '
            'from open to close and never by name',
      );
      expect(h.sink.closed, <String>[first, second], reason: 'in offer order');

      expect(
        h.sink.disk.keys.toList()..sort(),
        <String>['/tmp/mkvi/rapor (1).pdf', '/tmp/mkvi/rapor.pdf'],
        reason: 'the second one got its own name',
      );
      expect(h.sink.lengthOf('/tmp/mkvi/rapor.pdf'), 100);
      expect(h.sink.lengthOf('/tmp/mkvi/rapor (1).pdf'), 200);

      expect(h.coordinator.views, hasLength(2));
      expect(
        h.coordinator.views.map((TransferView v) => v.name).toList(),
        <String>['rapor.pdf', 'rapor.pdf'],
        reason: 'both rows show the name the peer sent',
      );
      expect(
        h.coordinator.views.map((TransferView v) => v.transferred).toList(),
        <int>[100, 200],
      );
      expect(
        h.coordinator.viewOf(first)!.detail,
        isNot(h.coordinator.viewOf(second)!.detail),
        reason: 'two different saved paths',
      );
    });

    test(
      'a re-announced id is refused rather than replacing a live transfer',
      () {
        // The 0.1.x `Map.set` behaviour, already fixed in `PeerFileReceiver`:
        // re-announcing a live id reset `received` to 0 and `accepted` to false
        // mid-transfer, and never counted against the cap — a denial of service
        // handed to the peer for free.
        final Harness h = Harness();
        final String id = tid('c');
        h.announce(id, size: 100, name: 'a.bin');
        final OfferOutcome again = h.announce(id, size: 100, name: 'a.bin');

        expect(again, isA<OfferAutoDeclined>());
        expect(
          (again as OfferAutoDeclined).reason,
          PeerProtocol.transferAlreadyReceiving,
        );
        expect(h.receiver.pendingCount, 1);
        expect(h.coordinator.views, hasLength(1));
      },
    );
  });

  group('the visible list is bounded', () {
    test('a full list of live transfers refuses the next one', () async {
      // THE DEFECT: `setTransfers` appended and nothing was ever removed, so the
      // list was unbounded. Dropping a *live* row is not a fix — an invisible
      // transfer is one the user can no longer cancel.
      //
      // Three rows is the smallest bound this coordinator accepts: one outgoing
      // plus the two incoming the protocol admits. Filling all three with live
      // transfers is what forces the refusal.
      final Harness h = Harness(maxVisibleTransfers: 3, maxOutgoing: 1);
      h.announce(tid('1'), size: 100, name: 'bir.pdf');
      h.announce(tid('2'), size: 100, name: 'iki.pdf');
      expect(
        h.coordinator.offerFile(
          FakeOutgoingFile(name: 'uc.bin', bytes: bytes(4)),
        ),
        isA<FileOffered>(),
      );
      expect(h.coordinator.views, hasLength(3));
      expect(
        h.coordinator.liveViews,
        isEmpty,
        reason: 'all three are announced',
      );

      final SendFileOutcome refused = h.coordinator.offerFile(
        FakeOutgoingFile(name: 'dort.bin', bytes: bytes(4)),
      );

      expect(refused, isA<SendFileRefused>());
      expect(
        (refused as SendFileRefused).reason,
        ChatMessages.tooManyTransfers(),
      );
      expect(h.coordinator.views, hasLength(3), reason: 'nothing was evicted');
      expect(
        h.channel.offers,
        hasLength(1),
        reason: 'only the first was announced',
      );
    });

    test(
      'the oldest finished row is evicted once there is one to evict',
      () async {
        final Harness h = Harness(maxVisibleTransfers: 3, maxOutgoing: 1);
        final String first =
            (h.coordinator.offerFile(
                      FakeOutgoingFile(name: 'a.bin', bytes: bytes(4)),
                    )
                    as FileOffered)
                .view
                .id;
        h.coordinator.onDecline(first, 'Olmadı.');

        final String live = tid('2');
        h.announce(live, size: 100, name: 'canli.pdf');
        await h.coordinator.accept(live);
        final String second =
            (h.coordinator.offerFile(
                      FakeOutgoingFile(name: 'b.bin', bytes: bytes(4)),
                    )
                    as FileOffered)
                .view
                .id;
        expect(
          h.coordinator.views,
          hasLength(3),
          reason: 'one finished, two live',
        );

        // The fourth row only fits by evicting the one that already finished.
        h.announce(tid('3'), size: 100, name: 'ucuncu.pdf');

        expect(h.coordinator.views, hasLength(3));
        expect(
          h.coordinator.viewOf(first),
          isNull,
          reason: 'the finished row went, not a live one',
        );
        expect(h.coordinator.viewOf(live), isNotNull);
        expect(h.coordinator.viewOf(second), isNotNull);
        expect(h.coordinator.viewOf(tid('3')), isNotNull);
      },
    );

    test('a list that cannot hold every live transfer is refused outright', () {
      expect(
        () => TransferCoordinator(
          channel: RecordingChannel(isOpen: true),
          sink: FakeFileSink(),
          receiver: PeerFileReceiver(),
          maxVisibleTransfers: 2,
          maxOutgoing: 4,
        ),
        throwsArgumentError,
      );
    });
  });

  group('the frame guard', () {
    test('a frame for a transfer that was never accepted is refused', () async {
      final Harness h = Harness();
      final String id = tid('a');
      h.announce(id, size: 100);

      final FrameOutcome outcome = await h.coordinator.onFrame(
        frameOf(id, bytes(10)),
      );

      expect(
        (outcome as FrameRefused).reason,
        PeerProtocol.unauthorizedFileData,
      );
      expect(h.sink.disk, isEmpty);
    });

    test('a frame past the declared size tears the transfer down', () async {
      final Harness h = Harness();
      final String id = tid('b');
      h.announce(id, size: 32);
      await h.coordinator.accept(id);

      final FrameOutcome outcome = await h.coordinator.onFrame(
        frameOf(id, bytes(64)),
      );
      await pumpUntil(() => h.sink.disk.isEmpty);

      expect((outcome as FrameRefused).reason, PeerProtocol.fileSizeOverflow);
      expect(h.sink.disk, isEmpty, reason: 'and the partial file is gone');
      expect(h.coordinator.viewOf(id)!.phase, TransferPhase.failed);
    });

    test('a malformed frame is refused without touching the disk', () async {
      final Harness h = Harness();
      final String id = tid('c');
      h.announce(id, size: 32);
      await h.coordinator.accept(id);

      final FrameOutcome outcome = await h.coordinator.onFrame(<int>[
        9,
        1,
        2,
        3,
      ]);

      expect((outcome as FrameRefused).reason, PeerProtocol.invalidFrame);
      expect(h.sink.written, isEmpty);
    });

    test('a completion that arrives short is failed and deleted', () async {
      // THE DEFECT: `finishReceive` compared `received !== size` and emitted an
      // error, but the row was never told, so a short transfer stayed at its last
      // percentage with no explanation and its partial file stayed on disk.
      final Harness h = Harness();
      final String id = tid('d');
      h.announce(id, size: 1000);
      await h.coordinator.accept(id);
      await h.coordinator.onFrame(frameOf(id, bytes(400)));

      final FrameOutcome outcome = await h.coordinator.onComplete(id);
      await pumpUntil(() => h.sink.disk.isEmpty);

      expect((outcome as FrameRefused).reason, PeerProtocol.transferIncomplete);
      expect(h.sink.disk, isEmpty);
      expect(h.coordinator.viewOf(id)!.phase, TransferPhase.failed);
      expect(h.coordinator.viewOf(id)!.detail, PeerProtocol.transferIncomplete);
    });

    test(
      'a sink that cannot open is declined, and the peer is told why',
      () async {
        final FakeFileSink sink = FakeFileSink()..failOpenFor = 'rapor';
        final Harness h = Harness(sink: sink);
        final String id = tid('e');
        h.announce(id, size: 100);

        final DecisionOutcome decision = await h.coordinator.accept(id);

        expect(
          (decision as DecisionRefused).reason,
          PeerProtocol.sinkOpenFailed,
        );
        expect(
          sink.disk,
          isEmpty,
          reason: 'nothing to clean up: nothing was made',
        );
        expect(h.channel.declines.single.reason, PeerProtocol.sinkOpenFailed);
        expect(h.channel.accepts, isEmpty);
        expect(h.coordinator.viewOf(id)!.phase, TransferPhase.failed);
      },
    );

    test('a sink that cannot write fails the transfer and deletes the file', () async {
      // THE DEFECT this pins is the hang. The frame handler awaits the per-transfer
      // write chain, and a failure raised *from inside a step of* that chain must
      // not await the chain again — it used to, and the transfer simply stopped:
      // the row frozen at its last percentage, the partial file left on disk, and
      // no error anywhere. That is the exact symptom the teardown exists to
      // prevent, so the test carries its own timeout.
      final FakeFileSink sink = FakeFileSink()..failWriteFor = 'a';
      final Harness h = Harness(sink: sink);
      final String id = tid('a');
      h.announce(id, size: 1000);
      await h.coordinator.accept(id);
      expect(sink.disk, hasLength(1), reason: 'the partial file is real');

      final FrameOutcome outcome = await h.coordinator
          .onFrame(frameOf(id, bytes(500)))
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              fail('a failing write must not hang the frame');
            },
          );

      expect(
        outcome,
        isA<FrameRefused>(),
        reason:
            'the write failed, so the transfer is gone and the frame is a '
            'refusal — the *row* is where the Turkish reason lives',
      );
      expect((outcome as FrameRefused).reason, PeerProtocol.transferNotFound);
      expect(h.coordinator.viewOf(id)!.phase, TransferPhase.failed);
      expect(
        h.coordinator.viewOf(id)!.detail,
        PeerProtocol.sinkOpenFailed,
        reason: 'and the user is told it was their storage, not the peer',
      );
      await pumpUntil(() => sink.disk.isEmpty);
      expect(sink.disk, isEmpty, reason: 'the partial file is gone');
      expect(sink.aborted, <String>[id]);
    });
  });

  group('the row as the surface draws it', () {
    test('every state has a Turkish label and the counts add up', () async {
      final Harness h = Harness();
      final String id = tid('a');

      h.announce(id, size: 400);
      TransferView view = h.coordinator.viewOf(id)!;
      expect(view.heading, 'Alınıyor: rapor.pdf');
      expect(view.stateLabel, ChatMessages.awaitingDecision);
      expect(view.percent, 0);
      expect(view.detailLabel, '0 B / 400 B');
      expect(view.dismissLabel, 'rapor.pdf satırını kapat');
      expect(view.progressLabel, 'rapor.pdf aktarım ilerlemesi');

      await h.coordinator.accept(id);
      await h.coordinator.onFrame(frameOf(id, bytes(200)));
      view = h.coordinator.viewOf(id)!;
      expect(view.phase, TransferPhase.active);
      expect(view.stateLabel, '%50');
      expect(view.percent, 50);
      expect(view.detailLabel, '200 B / 400 B');

      await h.coordinator.onFrame(frameOf(id, bytes(200)));
      await h.coordinator.onComplete(id);
      view = h.coordinator.viewOf(id)!;
      expect(view.phase, TransferPhase.done);
      expect(view.stateLabel, ChatMessages.completed);
      expect(view.percent, 100);
      expect(view.detail, '/tmp/mkvi/rapor.pdf');
    });

    test(
      'an outgoing row says "Gönderiliyor", which is a different Turkish string',
      () {
        final Harness h = Harness();
        final String id =
            (h.coordinator.offerFile(
                      FakeOutgoingFile(
                        name: 'notlar.txt',
                        bytes: bytes(10),
                        mime: 'text/plain',
                      ),
                    )
                    as FileOffered)
                .view
                .id;

        final TransferView view = h.coordinator.viewOf(id)!;
        expect(view.heading, 'Gönderiliyor: notlar.txt');
        expect(view.direction, TransferDirection.send);
        // And the name the peer was told is the sanitised one.
        expect(h.channel.offers.single.name, 'notlar.txt');
        expect(h.channel.offers.single.mime, 'text/plain');
      },
    );

    test('the list handed to a surface cannot be mutated', () {
      final Harness h = Harness();
      h.coordinator.offerFile(FakeOutgoingFile(name: 'a.bin', bytes: bytes(4)));
      expect(() => h.coordinator.views.clear(), throwsUnsupportedError);
    });
  });

  group('the layer opens a sink in exactly one place', () {
    test('the source calls FileSink.open once, and aborts everywhere else', () {
      // THE DEFECT, at its root: `crates/mkvi_core/src/state.rs` checked the cap
      // *after* `File::create`, so every rejected offer left a 0 byte file. The
      // fix in Rust was a reordering inside one function; the fix here is that
      // there is exactly one function in the whole Dart layer that can create a
      // file, and it runs after every check that can refuse.
      //
      // Counted from the source rather than asserted behaviourally, because the
      // failure mode is a *second* call site added later — which no behavioural
      // test would notice until a peer exploited it.
      final String source = File(
        'lib/chat/transfer_coordinator.dart',
      ).readAsStringSync();
      final int opens = '_sink.open('.allMatches(source).length;
      final int aborts = '_sink.abort('.allMatches(source).length;
      final int closes = '_sink.close('.allMatches(source).length;

      expect(
        opens,
        1,
        reason: 'one call site, inside accept(), after every refusal',
      );
      expect(
        closes,
        1,
        reason: 'one call site, and only on a complete transfer',
      );
      expect(
        aborts,
        1,
        reason: 'one call site, reached from every teardown path',
      );
    });

    test('no file is created before the user accepted the offer', () async {
      // The ordering itself, asserted as behaviour: an announced offer has no
      // path, an accepted one does, and a declined one never had one.
      final Harness h = Harness();
      final String id = tid('a');
      h.announce(id, size: 100);

      expect(h.sink.opened, isEmpty);
      expect(h.sink.disk, isEmpty);

      await h.coordinator.accept(id);
      expect(h.sink.opened.keys.single, id);
      expect(h.sink.disk, hasLength(1), reason: 'and now it exists');
    });
  });

  group('disposal', () {
    test('tears down every live transfer and leaves nothing on disk', () async {
      final Harness h = Harness();
      final String incoming = tid('a');
      h.announce(incoming, size: 1000);
      await h.coordinator.accept(incoming);
      await h.coordinator.onFrame(frameOf(incoming, bytes(100)));
      h.coordinator.offerFile(FakeOutgoingFile(name: 'b.bin', bytes: bytes(4)));

      await h.coordinator.dispose();
      await pumpUntil(() => h.sink.disk.isEmpty);

      expect(
        h.sink.disk,
        isEmpty,
        reason: 'no partial file outlives the session',
      );
      expect(
        h.coordinator.offerFile(
          FakeOutgoingFile(name: 'c.bin', bytes: bytes(4)),
        ),
        isA<SendFileRefused>(),
      );
      await h.coordinator.dispose();
    });
  });
}
