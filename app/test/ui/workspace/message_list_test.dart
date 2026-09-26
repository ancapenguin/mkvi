/// The conversation: five kinds of line, each drawn as its own row in Turkish,
/// and a line that has not gone out kept on screen with the two actions that
/// resolve it.
///
/// The claim under test in the first group is that the four [MessageDelivery]
/// states are four *rows* and not one row with a hopeful icon: `sending`,
/// `sent`, `read` and `failed` are four different Turkish words, and the row
/// shows each of them. `App.tsx` had one class string — `mkvi-msg
/// ${message.status}` — and the `status` field was English while the sentence
/// around it was Turkish, which is the split `lib/chat/chat_messages.dart` was
/// written to end.
///
/// The second group is the queue. A line that could not go out is a **state of
/// the line**, not a reason to remove it: the row stays, it says why, and it
/// offers `ChatController.retryQueued` and `ChatController.discardQueued`. That
/// is the difference between "the message you wrote is somewhere" and the
/// reported "no message ever arrives".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/workspace/workspace.dart';

import '../../support/mkvi_test_app.dart';
import 'support/workspace_harness.dart';

/// A fixed "now", so "Bugün" and "Dün" are answers and not guesses.
final DateTime workspaceNoon = DateTime(2026, 9, 26, 12);

/// A line with an explicit state, sent at a fixed instant.
TimelineMessage lineWith(
  String id, {
  MessageDirection direction = MessageDirection.outgoing,
  MessageDelivery delivery = MessageDelivery.sent,
  String body = 'merhaba',
  DateTime? sentAt,
}) => TimelineMessage(
  id: id,
  body: body,
  sentAt: sentAt ?? DateTime(2026, 9, 26, 11, 30),
  direction: direction,
  delivery: delivery,
);

/// Five pairs: the peer's line and mine, and the four outgoing states.
///
/// The order here is the order on screen, and it is reached by giving every line
/// a **distinct** instant: `ChatTimeline` sorts by instant and then by id, so
/// eight lines that share a timestamp are sorted by id and the four `a…` lines
/// end up adjacent — one bubble, three of them with no meta line, and the
/// "every state says its own word" assertion quietly measuring nothing.
///
/// Alternating direction also keeps every line in its own bubble, which is what
/// `endsGroup` is for: one timestamp per bubble, on its last line.
List<TimelineMessage> everyDelivery() => <TimelineMessage>[
  lineWith(
    'b1',
    direction: MessageDirection.incoming,
    sentAt: DateTime(2026, 9, 26, 11, 1),
    body: 'selam',
  ),
  lineWith(
    'a1',
    delivery: MessageDelivery.sending,
    sentAt: DateTime(2026, 9, 26, 11, 2),
    body: 'kuyrukta',
  ),
  lineWith(
    'b2',
    direction: MessageDirection.incoming,
    sentAt: DateTime(2026, 9, 26, 11, 3),
    body: 'selam',
  ),
  lineWith(
    'a2',
    delivery: MessageDelivery.sent,
    sentAt: DateTime(2026, 9, 26, 11, 4),
    body: 'gonderildi',
  ),
  lineWith(
    'b3',
    direction: MessageDirection.incoming,
    sentAt: DateTime(2026, 9, 26, 11, 5),
    body: 'selam',
  ),
  lineWith(
    'a3',
    delivery: MessageDelivery.read,
    sentAt: DateTime(2026, 9, 26, 11, 6),
    body: 'okundu',
  ),
  lineWith(
    'b4',
    direction: MessageDirection.incoming,
    sentAt: DateTime(2026, 9, 26, 11, 7),
    body: 'selam',
  ),
  lineWith(
    'a4',
    delivery: MessageDelivery.failed,
    sentAt: DateTime(2026, 9, 26, 11, 8),
    body: 'gonderilemedi',
  ),
];

void main() {
  group('every delivery state is its own row, in Turkish', () {
    testWidgets('the four states say four different words', (
      WidgetTester tester,
    ) async {
      final List<TimelineMessage> lines = everyDelivery();
      await pumpMkvi(
        tester,
        workspaceColumn(
          MessageList(
            timeline: ChatTimeline.fromMessages(lines),
            now: workspaceNoon,
          ),
        ),
      );

      for (final TimelineMessage line in lines) {
        expect(
          find.byKey(MessageListKeys.row(line.id)),
          findsOneWidget,
          reason: '${line.direction.name}/${line.delivery.name} is a row',
        );
        expect(
          find.byKey(MessageListKeys.body(line.id)),
          findsOneWidget,
          reason: 'and it says what was written',
        );
      }

      // The four words, one per state, and none of them is another's.
      final Map<MessageDelivery, String> spoken = <MessageDelivery, String>{
        for (final MessageDelivery delivery in MessageDelivery.values)
          delivery: workspaceDeliveryLabel(delivery),
      };
      expect(spoken[MessageDelivery.sending], WorkspaceTr.deliverySending.tr);
      expect(spoken[MessageDelivery.sent], WorkspaceTr.deliverySent.tr);
      expect(spoken[MessageDelivery.read], ChatMessages.readReceipt);
      expect(spoken[MessageDelivery.failed], WorkspaceTr.deliveryFailed.tr);
      expect(spoken.values.toSet().length, 4, reason: 'four words: $spoken');

      // And each one is on its own row, where the user can read it.
      for (final TimelineMessage line in lines) {
        if (line.direction != MessageDirection.outgoing) continue;
        expect(
          find.byKey(MessageListKeys.status(line.id)),
          findsOneWidget,
          reason: '${line.id} (${line.delivery.name}) is built and says its state',
        );
        expect(
          tester.widget<Text>(
            find.byKey(MessageListKeys.status(line.id)),
          ).data,
          workspaceDeliveryLabel(line.delivery),
          reason: '${line.id} says its own state',
        );
      }

      expectNoOverflow(tester);
      await expectEveryControlLabelled(tester);
    });

    testWidgets('the direction is readable from the geometry alone', (
      WidgetTester tester,
    ) async {
      final TimelineMessage incoming = lineWith(
        'b1',
        direction: MessageDirection.incoming,
      );
      final TimelineMessage outgoing = lineWith('a1');
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceColumn(
            MessageList(
              timeline: ChatTimeline.fromMessages(<TimelineMessage>[
                incoming,
                outgoing,
              ]),
              now: workspaceNoon,
            ),
          ),
        ),
      );

      final Rect fromPeer = tester.getRect(
        find.byKey(MessageListKeys.bubble('b1')),
      );
      final Rect mine = tester.getRect(find.byKey(MessageListKeys.bubble('a1')));
      expect(
        mine.left,
        greaterThan(fromPeer.left + style.gap('4')),
        reason: 'a line from the peer hugs the left, one of mine hugs the right',
      );
      expect(
        fromPeer.right,
        lessThan(mine.right - style.gap('4')),
        reason: 'and a line of mine is inset from the right by the same amount',
      );
      expect(
        find.byKey(MessageListKeys.status('b1')),
        findsNothing,
        reason: 'a received line has no delivery state of ours to show',
      );

      expectNoOverflow(tester);
    });

    testWidgets('the timestamp comes from the type scale', (
      WidgetTester tester,
    ) async {
      final TimelineMessage line = lineWith(
        'a1',
        sentAt: DateTime(2026, 9, 26, 9, 5),
      );
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceColumn(
            MessageList(
              timeline: ChatTimeline.fromMessages(<TimelineMessage>[line]),
              now: workspaceNoon,
            ),
          ),
        ),
      );

      final Text stamp = tester.widget<Text>(
        find.byKey(MessageListKeys.time('a1')),
      );
      expect(stamp.data, '09:05', reason: 'the layer formats it, not the widget');
      expect(
        stamp.style?.fontSize,
        style.typeStep('2xs').size,
        reason: 'and the size is the 2xs step the user scaled, not a literal',
      );
      expect(
        stamp.style?.color,
        style.role('textMuted'),
        reason: '4.5:1 on every surface, which is the declared pair',
      );
      expectTokenContrast(style, 'textMuted', 'bg');

      expectNoOverflow(tester);
    });

    testWidgets('the body is legible on both bubble fills', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceColumn(
            MessageList(
              timeline: ChatTimeline.fromMessages(everyDelivery()),
              now: workspaceNoon,
            ),
          ),
        ),
      );
      // `accentSoft` for a line of mine, `surfaceRaised` for one of theirs: the
      // two are told apart by fill as well as by position, and `text` is the
      // role the token file declares on both.
      expectTokenContrast(style, 'text', 'accentSoft');
      expectTokenContrast(style, 'text', 'surfaceRaised');
      expectNoOverflow(tester);
    });
  });

  group('a line that has not gone out stays on screen', () {
    testWidgets('the failed row offers both actions, and only that row does', (
      WidgetTester tester,
    ) async {
      int retried = 0;
      final List<String> discarded = <String>[];
      final TimelineMessage failed = lineWith(
        'a9',
        delivery: MessageDelivery.failed,
      );
      final TimelineMessage sent = lineWith('a8');
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceColumn(
            MessageList(
              timeline: ChatTimeline.fromMessages(<TimelineMessage>[sent, failed]),
              now: workspaceNoon,
              failureReasons: <String, String>{'a9': 'Bağlantı şu anda meşgul.'},
              onRetry: () => retried += 1,
              onDiscard: discarded.add,
            ),
          ),
        ),
      );

      expect(
        find.byKey(MessageListKeys.retry('a9')),
        findsOneWidget,
        reason: 'the line is still there, so the fix has to be on the line',
      );
      expect(find.byKey(MessageListKeys.discard('a9')), findsOneWidget);
      expect(find.text('Bağlantı şu anda meşgul.'), findsOneWidget);
      // A line that went out has nothing to resolve.
      expect(find.byKey(MessageListKeys.retry('a8')), findsNothing);
      expect(find.byKey(MessageListKeys.discard('a8')), findsNothing);
      // Neither does a line that is merely on its way.
      expect(find.byKey(MessageListKeys.retry('a7')), findsNothing);

      expectHitTarget(tester, find.byKey(MessageListKeys.retry('a9')), style: style);
      expectHitTarget(
        tester,
        find.byKey(MessageListKeys.discard('a9')),
        style: style,
      );

      await tester.tap(find.byKey(MessageListKeys.retry('a9')));
      await tester.tap(find.byKey(MessageListKeys.discard('a9')));
      await tester.pump();

      expect(retried, 1);
      expect(discarded, <String>['a9'], reason: 'and the discard is per line');

      expectNoOverflow(tester);
      await expectEveryControlLabelled(tester);
    });

    testWidgets('without the callbacks the row is still there, just inert', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        workspaceColumn(
          MessageList(
            timeline: ChatTimeline.fromMessages(<TimelineMessage>[
              lineWith('a9', delivery: MessageDelivery.failed),
            ]),
            now: workspaceNoon,
          ),
        ),
      );
      expect(
        find.byKey(MessageListKeys.row('a9')),
        findsOneWidget,
        reason: 'a failed line never disappears because nothing was wired up',
      );
      expect(find.byKey(MessageListKeys.retry('a9')), findsNothing);
      expect(find.text(workspaceDeliveryLabel(MessageDelivery.failed)), findsOneWidget);
      expectNoOverflow(tester);
    });
  });

  group('the day boundary and the bubble group', () {
    testWidgets('one separator per midnight crossing, and none for one day', (
      WidgetTester tester,
    ) async {
      final DateTime yesterday = DateTime(2026, 9, 25, 23, 58);
      final List<TimelineMessage> twoDays = <TimelineMessage>[
        lineWith('b1', direction: MessageDirection.incoming, sentAt: yesterday),
        lineWith('b2', direction: MessageDirection.incoming, sentAt: yesterday),
        lineWith(
          'b3',
          direction: MessageDirection.incoming,
          sentAt: DateTime(2026, 9, 26, 0, 2),
        ),
      ];
      await pumpMkvi(
        tester,
        workspaceColumn(
          MessageList(
            timeline: ChatTimeline.fromMessages(twoDays),
            now: workspaceNoon,
          ),
        ),
      );
      expect(
        find.byKey(MessageListKeys.daySeparator(DateTime(2026, 9, 26))),
        findsOneWidget,
        reason: 'a crossing gets one separator',
      );
      expect(
        find.text(ChatMessages.today),
        findsOneWidget,
        reason: 'and the label is "Bugün", decided by the clock the caller gave',
      );
      expect(find.text(ChatMessages.yesterday), findsNothing);

      // One day, no crossing, no separator: the redundant header 0.1.x would
      // have shown above every conversation that has not crossed midnight.
      await unmountMkvi(tester);
      await pumpMkvi(
        tester,
        workspaceColumn(
          MessageList(
            timeline: ChatTimeline.fromMessages(everyDelivery()),
          ),
        ),
      );
      expect(find.byType(Row), findsWidgets);
      expect(
        find.byKey(MessageListKeys.daySeparator(DateTime(2026, 9, 26))),
        findsNothing,
        reason: 'a single-day conversation has no boundary to mark',
      );
      expectNoOverflow(tester);
    });

    testWidgets('a separator says "Dün" for yesterday', (WidgetTester tester) async {
      await pumpMkvi(
        tester,
        workspaceColumn(
          MessageList(
            timeline: ChatTimeline.fromMessages(<TimelineMessage>[
              lineWith(
                'b1',
                direction: MessageDirection.incoming,
                sentAt: DateTime(2026, 9, 24, 8),
              ),
              lineWith(
                'b2',
                direction: MessageDirection.incoming,
                sentAt: DateTime(2026, 9, 25, 8),
              ),
              lineWith(
                'b3',
                direction: MessageDirection.incoming,
                sentAt: DateTime(2026, 9, 26, 8),
              ),
            ]),
            now: workspaceNoon,
          ),
        ),
      );
      // One separator per crossing, so the first day is marked by the *next*
      // one's arrival: two crossings, two labels, and the oldest day has no
      // label of its own because there is nothing above it to separate from.
      expect(
        find.byKey(MessageListKeys.daySeparator(DateTime(2026, 9, 24))),
        findsNothing,
      );
      expect(find.text(ChatMessages.yesterday), findsOneWidget);
      expect(find.text(ChatMessages.today), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('two lines in a row carry one timestamp, on the last', (
      WidgetTester tester,
    ) async {
      final List<TimelineMessage> pair = <TimelineMessage>[
        lineWith('a1', sentAt: DateTime(2026, 9, 26, 9, 5)),
        lineWith('a2', sentAt: DateTime(2026, 9, 26, 9, 6)),
      ];
      await pumpMkvi(
        tester,
        workspaceColumn(
          MessageList(
            timeline: ChatTimeline.fromMessages(pair),
            now: workspaceNoon,
          ),
        ),
      );

      // `endsGroup` is the reason the timestamp rides the last line of a bubble.
      expect(find.byKey(MessageListKeys.time('a2')), findsOneWidget);
      expect(
        find.byKey(MessageListKeys.time('a1')),
        findsNothing,
        reason: 'one timestamp per bubble, not one per line',
      );
      // And the joined corner is the square one.
      expectNoOverflow(tester);
    });
  });

  group('the list as a whole', () {
    testWidgets('an empty conversation says what is empty', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        workspaceColumn(MessageList(timeline: ChatTimeline.empty())),
      );
      expect(find.text(ChatMessages.emptyChatTitle), findsOneWidget);
      expect(find.text(ChatMessages.emptyChatBody), findsOneWidget);
      expect(find.byKey(MessageListKeys.viewport), findsNothing);
      // The box is still there, because it is the thing a notice shrinks.
      expect(find.byKey(MessageListKeys.list), findsOneWidget);
      expectNoOverflow(tester);
    });

    testWidgets('the newest line is the one at the bottom, with no scrolling', (
      WidgetTester tester,
    ) async {
      final List<TimelineMessage> lines = <TimelineMessage>[
        lineWith('a1', sentAt: DateTime(2026, 9, 26, 9)),
        lineWith('a2', sentAt: DateTime(2026, 9, 26, 10)),
        lineWith('a3', sentAt: DateTime(2026, 9, 26, 11)),
      ];
      await pumpMkvi(
        tester,
        workspaceColumn(
          MessageList(
            timeline: ChatTimeline.fromMessages(lines),
            now: workspaceNoon,
          ),
          width: 400,
        ),
      );
      final Rect oldest = tester.getRect(find.byKey(MessageListKeys.row('a1')));
      final Rect newest = tester.getRect(find.byKey(MessageListKeys.row('a3')));
      expect(
        newest.bottom,
        greaterThan(oldest.bottom),
        reason: 'the conversation reads downwards, oldest at the top',
      );
      expect(
        tester.getRect(find.byKey(MessageListKeys.viewport)).bottom,
        greaterThanOrEqualTo(newest.bottom - 0.01),
        reason: 'and the list opens on the newest line without a jump',
      );
      expectNoOverflow(tester);
    });

    testWidgets('a 32 KB line wraps inside a 320 dp column', (
      WidgetTester tester,
    ) async {
      // `PeerProtocol.maxMessageBytes` is the cap the composer enforces, so a
      // line that long is one the user was allowed to write.
      final TimelineMessage huge = lineWith(
        'a1',
        body: List<String>.filled(400, 'cok-uzun-bir-mesaj').join(),
      );
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceColumn(
            MessageList(
              timeline: ChatTimeline.fromMessages(<TimelineMessage>[huge]),
              now: workspaceNoon,
            ),
          ),
        ),
      );
      expect(huge.body.length, greaterThan(1000));
      expect(
        style.role('accentSoft'),
        isNotNull,
        reason: 'the bubble fill the 32 KB line is painted on',
      );
      expect(
        tester.getSize(find.byKey(MessageListKeys.list)).width,
        lessThanOrEqualTo(320 + 0.01),
        reason: 'the column is the bound, whatever the text is',
      );
      expectNoOverflow(tester);
    });

    testWidgets('it is announced as the message log', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await pumpMkvi(
        tester,
        workspaceColumn(
          MessageList(
            timeline: ChatTimeline.fromMessages(everyDelivery()),
            now: workspaceNoon,
          ),
        ),
      );
      // Two pumps: the semantics tree is written during paint, so the frame
      // that turns the flag on produces no nodes and the next one does.
      await tester.pump();
      await tester.pump();
      expect(
        find.bySemanticsLabel(ChatMessages.messageLogLabel),
        findsOneWidget,
        reason: 'TS: the aria-label of the message log',
      );
      handle.dispose();
      expectNoOverflow(tester);
    });
  });
}
