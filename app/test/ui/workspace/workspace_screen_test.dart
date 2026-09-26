/// The screen, and the two live defects it closes.
///
/// ## ROADMAP kusur 8 — the notice sat on the writer's hands
///
/// The report was "the bottom-right notification never goes away" and, worse,
/// "a window in which nothing can be typed, because the toast was sitting on the
/// send button". Five causes, one of them layout: `.mkvi-toast { position: fixed;
/// z-index: 100; bottom: 18px; right: 18px; }` (`src/App.css:168-172`) inside a
/// 100dvh grid, re-armed about once a second by six writers.
///
/// [NoticeController] fixed four of them. This file is the fifth: **where the
/// lane is put**. `NoticeHost` is an in-flow `Column` child, so it cannot overlap
/// anything — but only if it is placed in the flow, and the only place it can be
/// placed without covering the composer is between the list and the composer.
///
/// Every assertion in the first group is a `tester.getRect` measurement, in all
/// three window sizes, because a fixed bottom-right overlay is exactly the shape
/// that only collides once the window is small. `test/ui/notice/notice_host_test.
/// dart` measures the same property on a purpose-built screen; this one measures
/// it on the screen that ships.
///
/// ## ROADMAP kusur 7 — the note overwrote the name
///
/// Asserted here over the whole screen, since the header is where the two names
/// meet the connection state. The header's own tests carry the detail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/core/protocol/control_message.dart' show FileCancelMessage;
import 'package:mkvi/core/protocol/file_transfer.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/session/names.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/notice/notice.dart';
import 'package:mkvi/ui/workspace/workspace.dart';

import '../../support/fakes/fakes.dart' show fakeStored;
import '../../support/mkvi_test_app.dart';
import 'support/workspace_harness.dart';

/// A fixed "now", so "Bugün" is an answer rather than a guess.
final DateTime screenNoon = DateTime(2026, 9, 26, 12);

/// A conversation with one line in it, so the list is a list and not an empty
/// state — the layout measurement needs something to give way.
void seedOneLine(WorkspaceHarness harness) {
  harness.chat.controller.reportChannelOpen(false);
  harness.chat.send('Merhaba');
  harness.chat.openChannel();
}

void main() {
  group('DEFECT 8, the notice is in the flow and never covers the composer', () {
    for (final Size window in mkviWindowSizes) {
      testWidgets('nothing overlaps, in a ${window.width.toInt()} dp window', (
        WidgetTester tester,
      ) async {
        final WorkspaceHarness harness = WorkspaceHarness();
        seedOneLine(harness);
        await pumpMkvi(
          tester,
          harness.screen(now: screenNoon),
          size: window,
        );

        // Nothing to say: the lane takes no space at all and the composer sits
        // at the bottom, where the user expects it.
        expect(find.byKey(NoticeKeys.lane), findsNothing);
        expect(
          tester.getSize(find.byKey(ComposerKeys.send)).height,
          greaterThan(0),
          reason: 'the send button is on screen before any notice',
        );
        final double idleListBottom = tester
            .getRect(find.byKey(MessageListKeys.list))
            .bottom;

        harness.notice.showText('Mesaj gönderilemedi.', kind: NoticeKind.error);
        await tester.pump();

        final Rect notice = tester.getRect(find.byKey(NoticeKeys.surface));
        final Rect lane = tester.getRect(find.byKey(NoticeKeys.lane));
        final Rect composer = tester.getRect(find.byKey(ComposerKeys.composer));
        final Rect send = tester.getRect(find.byKey(ComposerKeys.send));

        expect(
          notice.overlaps(composer),
          isFalse,
          reason: 'the reported bug: a fixed bottom-right toast over the composer',
        );
        expect(
          notice.overlaps(send),
          isFalse,
          reason: 'and specifically over the control that could not be clicked',
        );
        expect(
          notice.bottom,
          lessThanOrEqualTo(composer.top),
          reason: 'the notice sits entirely above the composer, not beside it',
        );
        expect(
          lane.bottom,
          lessThanOrEqualTo(composer.top),
          reason: 'the reserved lane ends where the composer begins',
        );
        expect(lane.height, greaterThan(0), reason: 'a notice takes real space');
        expect(
          tester.getRect(find.byKey(MessageListKeys.list)).bottom,
          lessThan(idleListBottom),
          reason:
              'and the conversation gives the space up — an overlay would '
              'leave it at full height, which is what the notice is painted on '
              'top of in 0.1.x',
        );
        expect(
          idleListBottom - tester.getRect(find.byKey(MessageListKeys.list)).bottom,
          closeTo(lane.height, 0.5),
          reason: 'by exactly the height of the lane, and nothing else',
        );

        // And it gives it back.
        harness.notice.dismiss();
        await tester.pump();
        expect(find.byKey(NoticeKeys.lane), findsNothing);
        expect(
          tester.getRect(find.byKey(MessageListKeys.list)).bottom,
          idleListBottom,
          reason: 'the conversation returns to where it was',
        );
        await expectEveryControlLabelled(tester);
        await disposeHarness(tester, harness);
      });
    }

    testWidgets('the user can still type and send while a notice is up', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      await pumpMkvi(tester, harness.screen(now: screenNoon));
      harness.notice.showText('Bağlantı bekleniyor.');
      await tester.pump();

      await tester.enterText(find.byKey(ComposerKeys.input), 'Yazdım');
      await tester.pump();
      await tester.tap(find.byKey(ComposerKeys.send));
      await tester.pump();

      expect(
        find.byKey(MessageListKeys.body(harness.chat.controller.timeline.messages.last.id)),
        findsOneWidget,
        reason: '"nothing could be typed" is a claim about input, and it is false here',
      );
      expect(
        tester.getRect(find.byKey(NoticeKeys.surface)).overlaps(
          tester.getRect(find.byKey(ComposerKeys.send)),
        ),
        isFalse,
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('the close control closes it and types nothing', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      await pumpMkvi(tester, harness.screen(now: screenNoon));
      harness.notice.showText('Yerel geçmiş açılamadı.');
      await tester.pump();
      expect(find.byKey(NoticeKeys.surface), findsOneWidget);

      await tester.tap(find.byKey(NoticeKeys.close));
      await tester.pump();

      expect(find.byKey(NoticeKeys.surface), findsNothing);
      expect(
        tester.widget<TextField>(find.byKey(ComposerKeys.input)).controller?.text,
        anyOf(isNull, isEmpty),
        reason: 'and it typed nothing',
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('a 300-character path in a notice is still capped', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      seedOneLine(harness);
      await pumpMkvi(tester, harness.screen(now: screenNoon));

      harness.notice.showText(
        'Dosya kaydedildi: ${List<String>.filled(20, 'C:\\Users\\ilber\\Documents\\MKVI\\').join()}',
        kind: NoticeKind.success,
      );
      await tester.pump();

      final NoticeMetrics metrics = workspaceNoticeMetrics(
        mkviAppearance().style,
      );
      expect(
        tester.getSize(find.byKey(NoticeKeys.body)).height,
        lessThanOrEqualTo(metrics.maxBodyHeight + 0.5),
        reason: 'the notice body is capped at three lines whatever the path is',
      );
      expect(
        tester.getRect(find.byKey(NoticeKeys.surface)).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(ComposerKeys.composer)).top,
        ),
      );
      expectNoOverflow(tester);
      await disposeHarness(tester, harness);
    });
  });

  group('sending: a line written while the channel is down still arrives', () {
    testWidgets('it is on screen, queued, and goes out when the channel returns', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness(channelOpen: false);
      await pumpMkvi(tester, harness.screen(now: screenNoon));

      await tester.enterText(find.byKey(ComposerKeys.input), 'Merhaba');
      await tester.pump();
      await tester.tap(find.byKey(ComposerKeys.send));
      await tester.pump();

      final String id = harness.chat.controller.timeline.messages.last.id;
      expect(
        find.byKey(MessageListKeys.row(id)),
        findsOneWidget,
        reason: 'TS: the field was disabled, and one throw lost the text',
      );
      expect(
        find.descendant(
          of: find.byKey(MessageListKeys.row(id)),
          matching: find.text(WorkspaceTr.deliverySending.tr),
        ),
        findsOneWidget,
        reason: 'and it says it is on its way',
      );
      expect(
        harness.chat.channel.wire,
        isEmpty,
        reason: 'nothing has gone out: the channel is down',
      );
      expect(harness.chat.controller.queuedCount, 1);

      harness.chat.openChannel();
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(MessageListKeys.row(id)),
          matching: find.text(WorkspaceTr.deliverySent.tr),
        ),
        findsOneWidget,
      );
      expect(
        harness.chat.channel.chats.single.text,
        'Merhaba',
        reason: 'and the line really went out when the channel came back',
      );
      expect(harness.chat.controller.queuedCount, 0);
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('a refusal keeps the text and says why, in Turkish', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      await pumpMkvi(tester, harness.screen(now: screenNoon));

      // Over the protocol's byte cap: the one refusal a user can cause by
      // typing, and the one that must not cost them the paragraph.
      final String tooLong = 'a' * (PeerProtocol.maxMessageBytes + 1);
      await tester.enterText(find.byKey(ComposerKeys.input), tooLong);
      await tester.pump();
      await tester.tap(find.byKey(ComposerKeys.send));
      await tester.pump();

      expect(find.byKey(NoticeKeys.surface), findsOneWidget);
      expect(
        noticeBodyText(tester),
        ChatMessages.messageTooLarge(),
        reason:
            'the reason names the cap the protocol actually enforces, and it is '
            'the layer\'s own sentence rather than a reworded one',
      );
      expect(
        tester.widget<TextField>(find.byKey(ComposerKeys.input)).controller?.text,
        tooLong,
        reason: 'and the field still holds what was typed',
      );
      expect(harness.chat.controller.timeline.isEmpty, isTrue);
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('a failed line offers a retry that really sends again', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      // The channel is up but takes nothing: refused once, then it behaves.
      harness.chat.channel.refuse(reason: ChatMessages.channelBusy, times: 1);
      await pumpMkvi(tester, harness.screen(now: screenNoon));

      await tester.enterText(find.byKey(ComposerKeys.input), 'Bir kez daha');
      await tester.pump();
      await tester.tap(find.byKey(ComposerKeys.send));
      await tester.pump();

      final String id = harness.chat.controller.timeline.messages.last.id;
      expect(
        find.byKey(MessageListKeys.retry(id)),
        findsOneWidget,
        reason: 'the line is on screen and the reason is offered',
      );
      expect(
        find.descendant(
          of: find.byKey(MessageListKeys.row(id)),
          matching: find.text(WorkspaceTr.deliveryFailed.tr),
        ),
        findsOneWidget,
      );
      expect(harness.chat.channel.chats, isEmpty, reason: 'nothing went out');

      await tester.tap(find.byKey(MessageListKeys.retry(id)));
      await tester.pump();

      expect(
        harness.chat.channel.chats.single.text,
        'Bir kez daha',
        reason: 'the retry really puts the line on the wire',
      );
      expect(
        find.descendant(
          of: find.byKey(MessageListKeys.row(id)),
          matching: find.text(WorkspaceTr.deliverySent.tr),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(MessageListKeys.retry(id)),
        findsNothing,
        reason: 'and a line that went out has nothing left to resolve',
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('the discard action is the only way a pending line goes', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      harness.chat.channel.refuse(reason: ChatMessages.channelBusy, times: 99);
      await pumpMkvi(tester, harness.screen(now: screenNoon));

      await tester.enterText(find.byKey(ComposerKeys.input), 'Sileceğim');
      await tester.pump();
      await tester.tap(find.byKey(ComposerKeys.send));
      await tester.pump();

      final String id = harness.chat.controller.timeline.messages.last.id;
      expect(find.byKey(MessageListKeys.row(id)), findsOneWidget);
      expect(harness.chat.controller.queuedCount, 1);

      await tester.tap(find.byKey(MessageListKeys.discard(id)));
      await tester.pump();

      expect(find.byKey(MessageListKeys.row(id)), findsNothing);
      expect(harness.chat.controller.queuedCount, 0);
      expect(
        harness.chat.controller.hasQueuedMessages,
        isFalse,
        reason: 'and it is gone from the queue, not just from the screen',
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });
  });

  group('the history control', () {
    testWidgets('an older page is read, and the control says when there is none', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness(
        history: <StoredMessage>[
          for (int i = 0; i < 4; i += 1)
            fakeStored(
              'b${i.toRadixString(16).padLeft(31, '0')}',
              sentAt: DateTime(2026, 9, 26, 8, i),
              body: 'eski $i',
            ),
        ],
      );
      await pumpMkvi(tester, harness.screen(now: screenNoon));

      expect(
        find.byKey(WorkspaceHistoryKeys.control),
        findsOneWidget,
        reason: 'the store may still have an older page, and the control says so',
      );
      expect(find.byKey(WorkspaceHistoryKeys.status), findsNothing);

      await tester.tap(find.byKey(WorkspaceHistoryKeys.control));
      await tester.pumpAndSettle();

      // The store had exactly one page, so the read emptied it and the timeline
      // now shows it.
      expect(find.text('eski 0'), findsOneWidget);
      expect(find.text('eski 3'), findsOneWidget);
      expect(
        find.byKey(WorkspaceHistoryKeys.control),
        findsNothing,
        reason: 'and there is nothing older, so there is no button',
      );
      expect(
        find.byKey(WorkspaceHistoryKeys.status),
        findsOneWidget,
        reason: 'a vanished control with no explanation is the broken-screen question',
      );
      expect(
        tester.widget<Text>(find.byKey(WorkspaceHistoryKeys.status)).data,
        WorkspaceTr.historyComplete.tr,
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('a read that fails says the history could not be opened', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      harness.chat.store.failNextRead = StateError('depo erişilemiyor');
      await pumpMkvi(tester, harness.screen(now: screenNoon));

      await tester.tap(find.byKey(WorkspaceHistoryKeys.control));
      await tester.pumpAndSettle();

      expect(
        find.byKey(NoticeKeys.surface),
        findsOneWidget,
        reason:
            '"we could not look" and "there is nothing there" are different '
            'answers, and the user is told which one this is',
      );
      expect(
        noticeBodyText(tester),
        ChatMessages.historyUnavailable,
        reason: 'in the layer\'s own Turkish, not a reworded one',
      );
      expect(
        find.byKey(ComposerKeys.send),
        findsOneWidget,
        reason: 'and the composer still works',
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('an empty conversation shows the control and says what is empty', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      await pumpMkvi(tester, harness.screen(now: screenNoon));

      expect(find.text(ChatMessages.emptyChatTitle), findsOneWidget);
      expect(
        find.byKey(WorkspaceHistoryKeys.status),
        findsNothing,
        reason: 'the empty state already says there is nothing; a second line '
            'would say it twice',
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });
  });

  group('the file lane on the screen', () {
    testWidgets('an announced offer is answered from the screen', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      await pumpMkvi(tester, harness.screen(now: screenNoon));
      expect(find.byKey(TransferListKeys.list), findsNothing, reason: 'no files yet');

      final String id = tid('a');
      harness.transfers.onFileOffer(offerFor(id, size: 4096));
      // The row is published on a broadcast stream and the screen rebuilds from
      // its listener, so the frame after the offer is the one that has the row —
      // and it is a plain `pump`, not a settle, so nothing else can be hiding it.
      await tester.pump();
      await tester.pump();

      expect(find.byKey(TransferListKeys.list), findsOneWidget);
      expect(
        find.byKey(TransferListKeys.row(id)),
        findsOneWidget,
        reason: 'the coordinator holds ${harness.transfers.views}',
      );
      expect(
        find.byKey(TransferListKeys.accept(id)),
        findsOneWidget,
        reason: 'a waiting offer is visible and answerable',
      );
      expect(find.text(ChatMessages.awaitingDecision), findsOneWidget);

      await tester.tap(find.byKey(TransferListKeys.accept(id)));
      await tester.pumpAndSettle();

      expect(
        find.byKey(TransferListKeys.cancel(id)),
        findsOneWidget,
        reason: 'and a moving transfer can be stopped',
      );
      expect(harness.chat.files.opened, hasLength(1), reason: 'one file, one id');

      await tester.tap(find.byKey(TransferListKeys.cancel(id)));
      await tester.pumpAndSettle();
      expect(
        harness.chat.files.disk,
        isEmpty,
        reason: 'and stopping it leaves nothing on disk',
      );
      expect(harness.chat.channel.cancels, isNotEmpty);
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('a finished transfer can be cleared from the row', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      await pumpMkvi(tester, harness.screen(now: screenNoon));

      final String id = tid('b');
      harness.transfers.onFileOffer(offerFor(id, size: 1024));
      await tester.pump();
      await harness.transfers.accept(id);
      await harness.transfers.onFrame(frameOf(id, fillerBytes(1024)));
      await harness.transfers.onComplete(id);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(TransferListKeys.row(id)), findsOneWidget);
      expect(find.text(WorkspaceTr.saved.tr), findsOneWidget);

      await tester.tap(find.byKey(TransferListKeys.dismiss(id)));
      await tester.pump();
      expect(
        find.byKey(TransferListKeys.row(id)),
        findsNothing,
        reason: 'the row goes; the transfer itself was finished and stays so',
      );
      expect(harness.transfers.viewOf(id), isNotNull, reason: 'the layer still has it');
      expect(
        harness.chat.channel.cancels.where((FileCancelMessage m) => m.id == id),
        isEmpty,
        reason: 'and clearing a row is not a cancel: the peer hears nothing',
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('the file lane never grows over the conversation', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: harness.screen(now: screenNoon),
        ),
        size: mkviPhoneWindowSize,
      );

      final String longPath = List<String>.filled(
        20,
        'C:\\Users\\ilber\\Documents\\MKVI\\',
      ).join();
      for (int i = 0; i < 6; i += 1) {
        harness.transfers.onFileOffer(
          offerFor(tid(hexLetters[i]), size: 4096, name: 'r$i.pdf'),
        );
      }
      await tester.pump();
      await tester.pump();

      expect(
        tester.getSize(find.byKey(TransferListKeys.list)).height,
        lessThanOrEqualTo(transferRowBudget(style) * 2 + 0.5),
        reason: 'six files are still two rows tall in a 400 dp window',
      );
      expect(
        tester.getRect(find.byKey(TransferListKeys.list)).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(MessageListKeys.list)).top + 0.01,
        ),
        reason: 'and the lane takes its space from the list, not from the composer',
      );
      expectNoOverflow(tester);
      await disposeHarness(tester, harness);
      // A path of that length is what the notice lane is capped for, and the row
      // never shows one at all: `transferDetailLine` says "Kaydedildi".
      expect(longPath.length, greaterThan(250));
      expect(transferDetailLine(TransferView(
        id: tid('c'),
        name: 'r.pdf',
        direction: TransferDirection.receive,
        phase: TransferPhase.done,
        transferred: 1,
        total: 1,
        detail: longPath,
      )), WorkspaceTr.saved.tr);
    });
  });

  group('the two names on the screen', () {
    testWidgets('both are on screen, and neither eats the other', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      await pumpMkvi(
        tester,
        harness.screen(
          peer: const PeerNameView(announcedName: 'Ayşe Yılmaz', alias: 'Kübra'),
          onRemoveAlias: () {},
          onForgetPeer: () {},
          now: screenNoon,
        ),
      );

      expect(
        tester.widget<Text>(find.byKey(WorkspaceHeaderKeys.name)).data,
        'Ayşe Yılmaz',
        reason: 'TS: peerAlias || peerAnnouncedName made this the note',
      );
      expect(
        tester.widget<Text>(find.byKey(WorkspaceHeaderKeys.aliasLine)).data,
        workspaceAliasLine('Kübra'),
      );
      expect(find.byKey(WorkspaceHeaderKeys.announcedLine), findsOneWidget);
      expect(find.byKey(WorkspaceHeaderKeys.removeAlias), findsOneWidget);
      expect(
        find.byKey(WorkspaceHeaderKeys.forgetPeer),
        findsOneWidget,
        reason: 'and the one action that cannot be undone is offered, not hidden',
      );
      expectNoOverflow(tester);
      await expectEveryControlLabelled(tester);
      await disposeHarness(tester, harness);
    });
  });

  group('the whole screen, in every combination the app ships', () {
    testWidgets('no overflow in any theme, accent, scale or switch', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      seedOneLine(harness);
      harness.transfers.onFileOffer(offerFor(tid('a'), size: 4096));
      harness.notice.showText('Bağlantı bekleniyor.', kind: NoticeKind.warning);

      final Iterable<AppearanceSettings> everything = <Iterable<AppearanceSettings>>[
        mkviAppearanceMatrix(),
        mkviScaleMatrix(),
        mkviAccessibilityMatrix(),
      ].expand((Iterable<AppearanceSettings> m) => m);

      for (final Size window in mkviWindowSizes) {
        for (final AppearanceSettings settings in everything) {
          await unmountMkvi(tester);
          await pumpMkvi(
            tester,
            harness.screen(
              peer: const PeerNameView(announcedName: 'Ayşe Yılmaz', alias: 'Kübra'),
              onRemoveAlias: () {},
              onForgetPeer: () {},
              now: screenNoon,
            ),
            settings: settings,
            size: window,
          );
          expectNoOverflow(tester);
          // The structural claims, re-measured in every combination rather than
          // in one: a layout that only holds at the default font size is the
          // defect class 0.1.x shipped in every screen.
          expect(
            tester
                .getRect(find.byKey(NoticeKeys.surface))
                .overlaps(tester.getRect(find.byKey(ComposerKeys.send))),
            isFalse,
            reason: 'the notice never covers the writer: '
                '${describeCombination(settings)} at ${window.width.toInt()} dp',
          );
          expect(
            find.byKey(WorkspaceHeaderKeys.name),
            findsOneWidget,
            reason: 'and the peer still has a name: '
                '${describeCombination(settings)}',
          );
        }
      }
      await expectEveryControlLabelled(tester);
      await disposeHarness(tester, harness);
    });
  });

  // -----------------------------------------------------------------------------
  // The one control that cannot be undone
  // -----------------------------------------------------------------------------

  group('forgetting the peer asks first', () {
    testWidgets('a tap opens the dialog and does not forget', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      int forgot = 0;
      await pumpMkvi(
        tester,
        harness.screen(now: screenNoon, onForgetPeer: () => forgot += 1),
      );

      expect(forgot, 0, reason: 'nothing has been tapped yet');

      await tester.tap(find.byKey(WorkspaceHeaderKeys.forgetPeer));
      await tester.pumpAndSettle();

      // The dialog is up AND the callback has not run. That second half is
      // the assertion that matters: a dialog that appears only after the
      // action already happened is a confirmation of nothing.
      expect(find.byKey(WorkspaceScreenKeys.forgetConfirm), findsOneWidget);
      expect(forgot, 0, reason: 'asking must not have forgotten yet');

      // And the dialog says what is lost, not just what the button is.
      expect(find.text(WorkspaceTr.forgetTitle.tr), findsOneWidget);
      expect(find.textContaining('eşleştirmeniz'), findsOneWidget);

      await disposeHarness(tester, harness);
    });

    testWidgets('Vazgeç forgets nothing', (WidgetTester tester) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      int forgot = 0;
      await pumpMkvi(
        tester,
        harness.screen(now: screenNoon, onForgetPeer: () => forgot += 1),
      );

      await tester.tap(find.byKey(WorkspaceHeaderKeys.forgetPeer));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WorkspaceScreenKeys.forgetCancel));
      await tester.pumpAndSettle();

      expect(find.byKey(WorkspaceScreenKeys.forgetConfirm), findsNothing);
      expect(forgot, 0);

      await disposeHarness(tester, harness);
    });

    testWidgets('Unut forgets exactly once', (WidgetTester tester) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      int forgot = 0;
      await pumpMkvi(
        tester,
        harness.screen(now: screenNoon, onForgetPeer: () => forgot += 1),
      );

      await tester.tap(find.byKey(WorkspaceHeaderKeys.forgetPeer));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(WorkspaceScreenKeys.forgetConfirmButton));
      await tester.pumpAndSettle();

      expect(forgot, 1, reason: 'one tap, one forget — not zero, not two');
      expect(find.byKey(WorkspaceScreenKeys.forgetConfirm), findsNothing);

      await disposeHarness(tester, harness);
    });

    testWidgets('both buttons are reachable by a screen reader', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      await pumpMkvi(
        tester,
        harness.screen(
          now: screenNoon,
          onForgetPeer: () {},
        ),
      );

      await tester.tap(find.byKey(WorkspaceHeaderKeys.forgetPeer));
      await tester.pumpAndSettle();
      await expectEveryControlLabelled(tester);

      await disposeHarness(tester, harness);
    });
  });
}

