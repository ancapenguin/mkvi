// The send path: the optimistic echo, the in-flight queue, and the reconnect.
//
// The defect under every test here is the absence of a queue. The composer was
// disabled while the peer was offline, and the send path threw when there was
// no transport — so a message written during a reconnect could not be composed
// at all, and one written in the gap between the field being enabled and the
// keypress landing was gone. There was no echo, no retry and no record of a
// failure — only a red notice.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat.dart';
// The wire type. Deliberately not re-exported by `package:mkvi/chat/chat.dart`:
// a layer that re-exports both its own `TimelineMessage` and the protocol's
// `ChatMessage` under one import is a layer where somebody will send a rendered
// value to a parser.
import 'package:mkvi/core/protocol/control_message.dart';

import 'support/chat_fakes.dart';

/// Mints `aaa…`, `bbb…`, `ccc…`, so a test can name the line it is asserting on.
String Function() letteredIds() {
  const List<String> letters = <String>['a', 'b', 'c', 'd', 'e', 'f'];
  int next = 0;
  return () => (letters[next++] * 32);
}

void main() {
  group('a send that fails', () {
    test('stays in the queue, is retried, and is never lost', () async {
      // THE DEFECT: one throw and the line was never written down, anywhere.
      final RecordingChannel channel = RecordingChannel(isOpen: false);
      final FakeHistoryStore store = FakeHistoryStore();
      final ChatController controller = ChatController(
        channel: channel,
        store: store,
        idFactory: letteredIds(),
      );
      controller.reportChannelOpen(false);

      final SendResult result = controller.send('  merhaba  ');

      expect(result, isA<MessageQueued>());
      final MessageQueued queued = result as MessageQueued;
      expect(queued.delivered, isFalse, reason: 'the channel is down');
      expect(controller.timeline.length, 1, reason: 'the echo is on screen');
      expect(
        controller.timeline.messages.single.delivery,
        MessageDelivery.sending,
      );
      expect(controller.queuedCount, 1);

      // The retry: the channel comes back and the queue is flushed by the report.
      channel.isOpen = true;
      controller.reportChannelOpen(true);

      expect(controller.queuedCount, 0);
      expect(controller.timeline.length, 1, reason: 'one line, not two');
      expect(
        controller.timeline.messages.single.delivery,
        MessageDelivery.sent,
      );
      expect(
        channel.chats.single.id,
        queued.id,
        reason: 'the same id is reused',
      );
      expect(channel.chats.single.text, 'merhaba', reason: 'and it is trimmed');

      // And it reached the disk, with the delivery state it had when it was
      // written rather than the `sending` it was created with.
      await pumpUntil(() => store.length == 1);
      expect(store.storedOf(queued.id)!.delivery, MessageDelivery.sent);
    });

    test(
      'a refusal from an open channel marks the line failed and keeps it queued',
      () {
        // THE DEFECT: the row was never given a failure state at all — the three
        // states were `active`, `done` and `failed`, and a chat line had none.
        final RecordingChannel channel = RecordingChannel(
          isOpen: true,
          refuseReason: ChatMessages.channelNotReady,
        );
        final ChatController controller = ChatController(
          channel: channel,
          store: FakeHistoryStore(),
          idFactory: letteredIds(),
        );
        controller.reportChannelOpen(true);

        controller.send('bir');

        expect(controller.queuedCount, 1);
        expect(controller.queue.single.reason, ChatMessages.channelNotReady);
        expect(
          controller.timeline.messages.single.delivery,
          MessageDelivery.failed,
        );
        expect(channel.chats, isEmpty);
      },
    );

    test('an explicit retry sends it, once, and the queue empties', () {
      final RecordingChannel channel = RecordingChannel(
        isOpen: true,
        refuseReason: ChatMessages.channelBusy,
        refuseCount: 1,
      );
      final ChatController controller = ChatController(
        channel: channel,
        store: FakeHistoryStore(),
        idFactory: letteredIds(),
      );
      controller.reportChannelOpen(true);
      controller.send('bir');
      expect(controller.queuedCount, 1);

      controller.retryQueued();

      expect(controller.queuedCount, 0);
      expect(channel.chats.single.text, 'bir');
      expect(
        controller.timeline.messages.single.delivery,
        MessageDelivery.sent,
      );
    });

    test('the flush stops at the first refusal, so the order is preserved', () {
      // THE DEFECT a retry loop introduces on its own: flushing line 3 while line
      // 2 is still held delivers the peer's replies in an order neither device
      // agreed on.
      final RecordingChannel channel = RecordingChannel(
        isOpen: true,
        refuseReason: ChatMessages.channelBusy,
        refuseEverything: true,
      );
      final ChatController controller = ChatController(
        channel: channel,
        store: FakeHistoryStore(),
        idFactory: letteredIds(),
      );
      controller.reportChannelOpen(true);

      controller.send('bir');
      controller.send('iki');
      controller.send('üç');
      expect(controller.queuedCount, 3);
      expect(channel.chats, isEmpty);

      // One refusal budget. It is spent on the head of the queue, and the head is
      // the only frame offered at all this round — which is the whole property:
      // nothing behind a stuck line may overtake it.
      channel.refuseEverything = false;
      channel.refuseCount = 1;
      controller.retryQueued();

      expect(
        channel.chats,
        isEmpty,
        reason: 'the head was refused, so nothing went',
      );
      expect(
        controller.queuedCount,
        3,
        reason: 'and nothing was dropped either',
      );

      controller.retryQueued();
      expect(
        channel.chats.map((c) => c.text).toList(),
        <String>['bir', 'iki', 'üç'],
        reason: 'and now they go out in the order they were composed',
      );
      expect(controller.queuedCount, 0);
    });

    test('only an explicit discard removes a pending line', () {
      final RecordingChannel channel = RecordingChannel(isOpen: false);
      final ChatController controller = ChatController(
        channel: channel,
        store: FakeHistoryStore(),
        idFactory: letteredIds(),
      );
      controller.reportChannelOpen(false);
      controller.send('bir');

      final String id = controller.timeline.messages.single.id;
      expect(controller.discardQueued(id), isTrue);
      expect(controller.queuedCount, 0);
      expect(controller.timeline.isEmpty, isTrue);
      expect(
        controller.discardQueued(id),
        isFalse,
        reason: 'and it is idempotent',
      );
    });
  });

  group('the queue and the channel', () {
    test('survives the channel going down and coming back', () async {
      // THE DEFECT: `setConnected(false)` on a channel close, with the composer
      // disabled and the queued text simply not there any more.
      final RecordingChannel channel = RecordingChannel(isOpen: true);
      final ChatController controller = ChatController(
        channel: channel,
        store: FakeHistoryStore(),
        idFactory: letteredIds(),
      );
      controller.reportChannelOpen(true);

      controller.send('bir');
      final String id = controller.timeline.messages.single.id;
      expect(controller.queuedCount, 0, reason: 'it went straight out');

      channel.isOpen = false;
      controller.reportChannelOpen(false);
      expect(controller.isChannelOpen, isFalse);
      expect(
        controller.timeline.length,
        1,
        reason: 'the line is still on screen',
      );
      expect(
        controller.timeline.messages.single.delivery,
        MessageDelivery.sent,
      );

      // The user keeps typing while the channel is down.
      controller.send('iki');
      controller.send('üç');
      expect(controller.queuedCount, 2);
      expect(controller.isHoldingForReconnect, isTrue);
      expect(
        controller.timeline.messages
            .map((TimelineMessage m) => m.body)
            .toList(),
        <String>['bir', 'iki', 'üç'],
      );

      // And it comes back.
      channel.isOpen = true;
      controller.reportChannelOpen(true);

      expect(controller.queuedCount, 0);
      expect(controller.isHoldingForReconnect, isFalse);
      expect(channel.chats.map((c) => c.text).toList(), <String>[
        'bir',
        'iki',
        'üç',
      ]);
      expect(controller.timeline.length, 3);
      expect(controller.timeline.contains(id), isTrue);
    });

    test('a stuck head is never evicted, and the retry still works', () {
      // THE DEFECT: a window that evicted the oldest line would take a line that
      // has not reached the peer with it — it would still go out, but the user
      // would have no way to see it or to retry it.
      //
      // The channel refuses exactly one id, so the *first* line stays pending for
      // good and everything behind it is stuck behind it. The oldest line in the
      // window is therefore the one that has not reached the peer, which is
      // precisely the line a bound must not take.
      final String pendingId = '0' * 32;
      // `refuseCount: 0` makes [refuseReason] advisory: only the ids in
      // `refuseTheseIds` are refused, so clearing that set recovers the channel.
      final RecordingChannel channel = RecordingChannel(
        isOpen: true,
        refuseReason: ChatMessages.channelBusy,
        refuseCount: 0,
      )..refuseTheseIds = <String>{pendingId};
      final ChatController controller = ChatController(
        channel: channel,
        store: FakeHistoryStore(),
        idFactory: CountingIds.sequence(10),
        window: 4,
        maxQueued: 4,
      );
      controller.reportChannelOpen(true);

      controller.send('pending');
      controller.send('bir');
      controller.send('iki');
      controller.send('üç');
      expect(controller.timeline.length, 4, reason: 'exactly at the bound');
      expect(
        controller.queuedCount,
        4,
        reason: 'the stuck head holds the rest',
      );

      // The next send is refused by the queue bound, not by evicting the oldest
      // line — the two failure modes are indistinguishable to the user and only
      // one of them loses text.
      final SendResult refused = controller.send('dört');
      expect(refused, isA<SendRefused>());
      expect((refused as SendRefused).reason, ChatMessages.queueFull);
      expect(
        controller.timeline.messages
            .map((TimelineMessage m) => m.body)
            .toList(),
        <String>['pending', 'bir', 'iki', 'üç'],
        reason: 'nothing was dropped to make room',
      );
      expect(
        controller.timeline.messageById(pendingId)!.delivery,
        MessageDelivery.failed,
      );

      // And the retry still works, which is the whole reason it had to be kept.
      channel.refuseTheseIds = const <String>{};
      controller.retryQueued();
      expect(controller.queuedCount, 0);
      expect(
        channel.chats.map((c) => c.text).toList(),
        <String>['pending', 'bir', 'iki', 'üç'],
        reason: 'in composition order, the stuck one first',
      );
    });

    test(
      'the queue refuses a new line at its bound instead of dropping an old one',
      () {
        // THE DEFECT: an eviction is a silent loss with a worse disguise, and the
        // bound is what keeps the queue from becoming a memory leak with a
        // progress bar.
        final RecordingChannel channel = RecordingChannel(isOpen: false);
        final ChatController controller = ChatController(
          channel: channel,
          store: FakeHistoryStore(),
          idFactory: CountingIds.sequence(10),
          window: 3,
          maxQueued: 2,
        );
        controller.reportChannelOpen(false);

        expect(controller.send('bir'), isA<MessageQueued>());
        expect(controller.send('iki'), isA<MessageQueued>());
        final SendResult third = controller.send('üç');

        expect(third, isA<SendRefused>());
        expect((third as SendRefused).reason, ChatMessages.queueFull);
        expect(
          controller.timeline.messages
              .map((TimelineMessage m) => m.body)
              .toList(),
          <String>['bir', 'iki'],
          reason: 'the two that were already held are untouched',
        );
      },
    );

    test('a queue wider than the window is refused at construction', () {
      // The invariant that makes "never loses a pending line" true by
      // construction rather than by hope.
      expect(
        () => ChatController(
          channel: RecordingChannel(),
          store: FakeHistoryStore(),
          window: 4,
          maxQueued: 5,
        ),
        throwsArgumentError,
      );
    });
  });

  group('refusals that happen before a line exists', () {
    test('a blank body is refused in Turkish', () {
      final ChatController controller = ChatController(
        channel: RecordingChannel(isOpen: true),
        store: FakeHistoryStore(),
      );
      controller.reportChannelOpen(true);

      for (final String body in <String>['', '   ', '\n\t ']) {
        final SendResult result = controller.send(body);
        expect(result, isA<SendRefused>());
        expect((result as SendRefused).reason, ChatMessages.emptyMessage);
      }
      expect(controller.timeline.isEmpty, isTrue);
      expect(controller.queuedCount, 0);
    });

    test(
      'a body over the byte cap is refused, and the cap is the core constant',
      () {
        // THE DEFECT: `sendChat` measured the trimmed text in UTF-8 bytes and
        // threw "Mesaj en fazla 32 KB olabilir." A `String.length` check here would
        // be a different, looser limit and would build a frame `parseControl`
        // refuses on the far side — the line would appear to send and then vanish.
        final ChatController controller = ChatController(
          channel: RecordingChannel(isOpen: true),
          store: FakeHistoryStore(),
        );
        controller.reportChannelOpen(true);

        final SendResult result = controller.send('ş' * 20000);

        expect(result, isA<SendRefused>());
        expect(
          (result as SendRefused).reason,
          'Mesaj en fazla 32 KB olabilir.',
        );
        expect(controller.timeline.isEmpty, isTrue);
      },
    );
  });

  group('receiving', () {
    test('a frame is placed by its timestamp and a repeat is dropped', () {
      // THE DEFECT: `setMessages((current) => [...current, message])` — appended,
      // undeduplicated, and positioned by the peer's clock rather than its
      // timestamp.
      final ChatController controller = ChatController(
        channel: RecordingChannel(isOpen: true),
        store: FakeHistoryStore(),
      );
      controller.reportChannelOpen(true);
      controller.send('geçmiş biri');

      final DateTime older = DateTime(2020, 1, 1, 9);
      final ChatMessage late = ChatMessage(
        id: 'f' * 32,
        text: 'daha eski',
        sentAt: older.millisecondsSinceEpoch,
      );
      expect(controller.receive(late), isTrue);
      expect(controller.receive(late), isFalse, reason: 'the same id again');
      expect(controller.receive(late), isFalse);

      expect(
        controller.timeline.messages
            .map((TimelineMessage m) => m.body)
            .toList(),
        <String>['daha eski', 'geçmiş biri'],
      );
      expect(
        controller.timeline.messages.first.direction,
        MessageDirection.incoming,
      );
    });

    test(
      'a storage failure is reported, not thrown, and the line stays',
      () async {
        // The same intent as the notice this replaces, but that notice
        // *replaced* what was on screen. Here the line
        // survives and the failure is readable on its own.
        final FakeHistoryStore store = FakeHistoryStore();
        final ChatController controller = ChatController(
          channel: RecordingChannel(isOpen: true),
          store: store,
        );
        controller.reportChannelOpen(true);
        store.failNextAppend = StateError('Kilitli.');

        final ChatMessage frame = ChatMessage(
          id: 'f' * 32,
          text: 'selam',
          sentAt: 1,
        );
        expect(controller.receive(frame), isTrue);
        await pumpUntil(() => controller.lastStorageFailure != null);

        expect(controller.lastStorageFailure, ChatMessages.messageNotStored);
        expect(controller.timeline.length, 1);
      },
    );
  });

  group('the state stream', () {
    test('emits on send, on receive and on a channel report', () async {
      final RecordingChannel channel = RecordingChannel(isOpen: false);
      final ChatController controller = ChatController(
        channel: channel,
        store: FakeHistoryStore(),
        idFactory: letteredIds(),
      );
      final List<ChatSnapshot> seen = <ChatSnapshot>[];
      final StreamSubscription<ChatSnapshot> sub = controller.states.listen(
        seen.add,
      );

      controller.reportChannelOpen(false);
      controller.send('bir');
      controller.receive(ChatMessage(id: 'f' * 32, text: 'iki', sentAt: 2));
      await pumpUntil(() => seen.length >= 3);
      await sub.cancel();

      expect(seen.first.channelOpen, isFalse);
      expect(seen[1].queue.single.body, 'bir');
      expect(seen.last.timeline.length, 2);
    });

    test('the queue handed to a listener cannot be mutated', () {
      final ChatController controller = ChatController(
        channel: RecordingChannel(isOpen: false),
        store: FakeHistoryStore(),
        idFactory: letteredIds(),
      );
      controller.reportChannelOpen(false);
      controller.send('bir');

      expect(() => controller.queue.clear(), throwsUnsupportedError);
      expect(
        () => controller.timeline.messages.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('disposal', () {
    test('drops the queue and closes the stream', () async {
      final ChatController controller = ChatController(
        channel: RecordingChannel(isOpen: false),
        store: FakeHistoryStore(),
        idFactory: letteredIds(),
      );
      controller.reportChannelOpen(false);
      controller.send('bir');
      await controller.dispose();

      expect(controller.queuedCount, 0);
      expect(controller.send('iki'), isA<SendRefused>());
      expect(
        controller.receive(ChatMessage(id: 'f' * 32, text: 'üç', sentAt: 3)),
        isFalse,
      );
      await controller.dispose();
    });
  });
}
