// The conversation as a value: order, grouping, day boundaries, the window, and
// paging.
//
// Each test names the defect it pins. The defects are real: the conversation was
// once an append-only list in mutable state, so the four properties below were
// not merely untested — they were all absent from the shipped build.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat.dart';

import 'support/chat_fakes.dart';

/// A line [minutes] after local midnight on [day] of the anchor month.
DateTime at(int day, [int hour = 12, int minute = 0]) =>
    DateTime(testToday.year, testToday.month, day, hour, minute);

/// A 32 hex id that sorts after every other one here, so the tiebreak in
/// [TimelineMessage.compare] is what decides and the intent is readable.
String idOf(int index) => index.toRadixString(16).padLeft(32, '0');

TimelineMessage line(
  int index, {
  required DateTime sentAt,
  MessageDirection direction = MessageDirection.incoming,
  MessageDelivery delivery = MessageDelivery.sent,
  String body = 'merhaba',
}) => TimelineMessage(
  id: idOf(index),
  body: body,
  sentAt: sentAt,
  direction: direction,
  delivery: delivery,
);

void main() {
  group('ordering', () {
    test(
      'a late line with an older timestamp lands in its place, not at the end',
      () {
        // THE DEFECT: `setMessages((current) => [...current, message])` on an
        // incoming frame. A peer whose clock lags by a minute put its reply *after*
        // the messages it had already caused, and nothing ever corrected it.
        final ChatTimeline built = ChatTimeline.empty()
            .add(line(2, sentAt: at(26, 12, 2)))
            .add(line(3, sentAt: at(26, 12, 3)));

        final ChatTimeline withLate = built.add(
          line(1, sentAt: at(26, 12, 1), direction: MessageDirection.outgoing),
        );

        expect(
          withLate.messages.map((TimelineMessage m) => m.id).toList(),
          <String>[idOf(1), idOf(2), idOf(3)],
          reason: 'the late line belongs at its timestamp, not at the end',
        );
        // And the lines that were already on screen did not move relative to
        // each other, which is what "stable" has to mean for a scrolling surface.
        expect(
          withLate.messages
              .map((TimelineMessage m) => m.id)
              .toList()
              .sublist(1),
          built.messages.map((TimelineMessage m) => m.id).toList(),
        );
      },
    );

    test(
      'equal timestamps are ordered by id, so arrival order cannot reshuffle them',
      () {
        // THE DEFECT: two devices with their own clocks send equal `sentAt` values
        // routinely — a whole second is the resolution, and two messages in the same
        // second are the normal case, not the exotic one. Without a total order the
        // surface visibly reordered when a page was re-read.
        final DateTime stamp = at(26, 12, 5);
        final ChatTimeline forward = ChatTimeline.empty()
            .add(line(7, sentAt: stamp))
            .add(line(9, sentAt: stamp));
        final ChatTimeline backward = ChatTimeline.empty()
            .add(line(9, sentAt: stamp))
            .add(line(7, sentAt: stamp));

        expect(
          forward.messages.map((TimelineMessage m) => m.id).toList(),
          backward.messages.map((TimelineMessage m) => m.id).toList(),
        );
      },
    );

    test('the same id twice is one line, and the second copy is ignored', () {
      // THE DEFECT: a data channel that redelivered showed the same line twice,
      // because the append was blind and there was no id index at all.
      final TimelineMessage original = line(
        4,
        sentAt: at(26, 11),
        delivery: MessageDelivery.sending,
      );
      final ChatTimeline once = ChatTimeline.empty().add(original);
      final ChatTimeline twice = once.add(
        line(4, sentAt: at(26, 11), body: 'farklı'),
      );

      expect(twice.length, 1);
      expect(twice.messageById(idOf(4))!.body, 'merhaba');
      expect(identical(once, twice), isTrue, reason: 'no change, no new value');
    });
  });

  group('day separators', () {
    test('a single-day conversation has none', () {
      // THE DEFECT: the original had no day separator at all, so a two-week
      // conversation and a two-minute one rendered identically; adding a header
      // per conversation then showed a redundant "Bugün" on nearly every chat.
      final ChatTimeline sameDay = ChatTimeline.fromMessages(<TimelineMessage>[
        line(1, sentAt: at(26, 8, 1)),
        line(2, sentAt: at(26, 8, 2)),
        line(3, sentAt: at(26, 23, 59)),
      ]);

      expect(sameDay.rows.whereType<DaySeparatorRow>(), isEmpty);
    });

    test('one separator per crossing, and the bubble group breaks with it', () {
      // THE DEFECT: a bubble that ran across midnight is a bubble that claims
      // both days, and the day header lands in the middle of it.
      final ChatTimeline spanning = ChatTimeline.fromMessages(<TimelineMessage>[
        line(1, sentAt: at(25, 23, 50), direction: MessageDirection.outgoing),
        line(2, sentAt: at(25, 23, 59), direction: MessageDirection.outgoing),
        line(3, sentAt: at(26, 0, 1), direction: MessageDirection.outgoing),
        line(4, sentAt: at(27, 12), direction: MessageDirection.outgoing),
      ]);

      final List<DaySeparatorRow> separators = spanning.rows
          .whereType<DaySeparatorRow>()
          .toList(growable: false);
      // Two crossings, two separators: 25 -> 26 and 26 -> 27. The first line of
      // the conversation gets none, because nothing was crossed to get there.
      expect(separators.map((DaySeparatorRow r) => r.day).toList(), <DateTime>[
        DateTime(2026, 9, 26),
        DateTime(2026, 9, 27),
      ]);

      final List<MessageRow> rows = spanning.rows
          .whereType<MessageRow>()
          .toList(growable: false);
      // 23:50 opens a group, 23:59 continues it, 00:01 must NOT: the day changed.
      expect(rows[0].startsGroup, isTrue);
      expect(rows[0].endsGroup, isFalse);
      expect(rows[1].startsGroup, isFalse);
      expect(rows[1].endsGroup, isTrue);
      expect(
        rows[2].startsGroup,
        isTrue,
        reason: 'a new day opens a new group',
      );
    });

    test('consecutive lines from the same device share a group', () {
      final ChatTimeline grouped = ChatTimeline.fromMessages(<TimelineMessage>[
        line(1, sentAt: at(26, 9), direction: MessageDirection.outgoing),
        line(2, sentAt: at(26, 9, 1), direction: MessageDirection.outgoing),
        line(3, sentAt: at(26, 9, 2), direction: MessageDirection.incoming),
        line(4, sentAt: at(26, 9, 3), direction: MessageDirection.incoming),
      ]);

      final List<MessageRow> rows = grouped.rows.whereType<MessageRow>().toList(
        growable: false,
      );
      expect(rows.map((MessageRow r) => r.startsGroup).toList(), <bool>[
        true,
        false,
        true,
        false,
      ]);
      expect(rows.map((MessageRow r) => r.endsGroup).toList(), <bool>[
        false,
        true,
        false,
        true,
      ]);
    });
  });

  group('the window', () {
    test('crossing the bound drops the oldest and keeps the newest', () {
      // THE DEFECT: `useState<ChatMessage[]>([])` with append-only writes and no
      // removal anywhere in the app. Nothing bounded the conversation.
      final ChatTimeline bounded = ChatTimeline.fromMessages(
        List<TimelineMessage>.generate(
          10,
          (int i) => line(i, sentAt: at(26, 8, i)),
        ),
        window: 4,
      );

      expect(bounded.length, 4);
      expect(
        bounded.messages.map((TimelineMessage m) => m.id).toList(),
        <String>[idOf(6), idOf(7), idOf(8), idOf(9)],
        reason: 'the newest lines are the ones the surface is scrolled to',
      );
      expect(bounded.dropped, 6);
    });

    test('a pinned line is never the one that falls off', () {
      // THE DEFECT this pins is the interaction with the send queue: a line that
      // has not reached the peer must stay visible, or the user has no way to see
      // it or to retry it. The queue is the pin, and it is what makes this
      // possible without making the window unbounded.
      final TimelineMessage pending = line(
        1,
        sentAt: at(26, 8),
        delivery: MessageDelivery.failed,
      );
      ChatTimeline built = ChatTimeline.empty(window: 3).add(pending);
      for (int i = 2; i <= 6; i += 1) {
        built = built.add(
          line(i, sentAt: at(26, 8, i), delivery: MessageDelivery.sent),
          isPinned: (TimelineMessage m) => m.id == pending.id,
        );
      }

      expect(
        built.messages.map((TimelineMessage m) => m.id).toList(),
        <String>[idOf(1), idOf(5), idOf(6)],
        reason: 'the oldest *settled* line went, not the pending one',
      );
      expect(built.contains(idOf(1)), isTrue);
      expect(built.dropped, 3);
    });

    test('shaving the window trims from the oldest end', () {
      final ChatTimeline wide = ChatTimeline.fromMessages(
        List<TimelineMessage>.generate(
          8,
          (int i) => line(i, sentAt: at(26, 7, i)),
        ),
        window: 8,
      );
      final ChatTimeline narrow = wide.withWindow(3);

      expect(narrow.length, 3);
      expect(
        narrow.messages.map((TimelineMessage m) => m.id).toList(),
        <String>[idOf(5), idOf(6), idOf(7)],
      );
      expect(narrow.dropped, 5);
    });
  });

  group('paging older history', () {
    test('overlapping pages produce no duplicate ids and no reordering', () async {
      // THE DEFECT: `stored.reverse()` over a newest-first page, spliced under the
      // live array. Any overlap between the store and the live timeline produced
      // a doubled line, and a page that arrived late reversed the whole thing.
      final FakeHistoryStore store = FakeHistoryStore();
      store.seed(<StoredMessage>[
        storedAt(idOf(1), at(25, 9)),
        storedAt(idOf(2), at(25, 10)),
        storedAt(idOf(3), at(26, 9)),
        storedAt(idOf(4), at(26, 10)),
        storedAt(idOf(5), at(26, 11)),
      ]);
      final ChatController controller = ChatController(
        channel: RecordingChannel(isOpen: false),
        store: store,
        historyPageSize: 2,
      );

      expect(await controller.loadInitialHistory(), isTrue);
      expect(
        controller.timeline.messages.map((TimelineMessage m) => m.id).toList(),
        <String>[idOf(4), idOf(5)],
      );
      expect(controller.hasOlderHistory, isTrue);

      expect(await controller.loadOlderHistory(), isTrue);
      expect(
        controller.timeline.messages.map((TimelineMessage m) => m.id).toList(),
        <String>[idOf(2), idOf(3), idOf(4), idOf(5)],
      );

      expect(await controller.loadOlderHistory(), isTrue);
      expect(
        controller.timeline.messages.map((TimelineMessage m) => m.id).toList(),
        <String>[idOf(1), idOf(2), idOf(3), idOf(4), idOf(5)],
      );
      expect(
        controller.timeline.messages
            .map((TimelineMessage m) => m.id)
            .toSet()
            .length,
        5,
        reason: 'five distinct ids, no matter how many pages were read',
      );
      expect(controller.hasOlderHistory, isFalse);
      expect(
        await controller.loadOlderHistory(),
        isFalse,
        reason: 'and it stops',
      );
    });

    test('a page that overlaps what is already held adds nothing twice', () async {
      // The overlap is not hypothetical: `loadNewest` and the first `loadOlder` ask
      // for the same boundary line, and a store that is one line short of the
      // cursor returns it again.
      final FakeHistoryStore store = FakeHistoryStore();
      store.seed(<StoredMessage>[
        storedAt(idOf(1), at(26, 8)),
        storedAt(idOf(2), at(26, 9)),
        storedAt(idOf(3), at(26, 10)),
      ]);
      final ChatController controller = ChatController(
        channel: RecordingChannel(),
        store: store,
        historyPageSize: 10,
      );
      await controller.loadInitialHistory();

      // The store is asked for the page before the oldest line held, and the
      // cursor is the *second* line rather than the first, so the first line comes
      // back a second time.
      final HistoryPage overlapping = await store.loadOlder(
        conversationId: ChatController.defaultConversationId,
        beforeMs: at(26, 9).millisecondsSinceEpoch,
        beforeId: idOf(2),
        limit: 10,
      );
      final ChatTimeline merged = controller.timeline.prepend(
        overlapping.messages.map((StoredMessage m) => m.toTimeline()),
        hasMore: false,
      );

      expect(
        merged.messages.map((TimelineMessage m) => m.id).toList(),
        <String>[idOf(1), idOf(2), idOf(3)],
      );
    });

    test(
      'the handoff refuses to run on a conversation that already has lines',
      () async {
        // THE DEFECT: the history read ran on *every* `pairingConfirmed` and did
        // `setMessages(stored)` — replacing the array. A pairing re-confirmed
        // mid-conversation threw away every unsent line on screen.
        final FakeHistoryStore store = FakeHistoryStore();
        store.seed(<StoredMessage>[storedAt(idOf(1), at(26, 8))]);
        final RecordingChannel channel = RecordingChannel(isOpen: true);
        final ChatController controller = ChatController(
          channel: channel,
          store: store,
          idFactory: CountingIds().call,
        );
        controller.reportChannelOpen(true);
        controller.send('buradayım');

        expect(await controller.loadInitialHistory(), isFalse);
        expect(controller.timeline.length, 1);
        expect(controller.timeline.messages.single.body, 'buradayım');
      },
    );
  });
}
