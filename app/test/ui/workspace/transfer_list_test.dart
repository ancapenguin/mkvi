/// The transfer list: five phases, a box that cannot grow, and a saved path that
/// is never painted.
///
/// `ROADMAP.md` kusur 8 is the reason two of these tests exist at all. The
/// notice's answer was a height cap ([NoticeMetrics.maxBodyHeight]) plus soft
/// breaks; the transfer row's answer is that the path is not a thing the row
/// shows, because a 300-character Windows path is not a sentence a list row can
/// say in any number of lines. Both are measured with `tester.getRect` against
/// [transferRowBudget], so a token change moves the layout and the assertion
/// together.
///
/// The last group drives the *real* [TransferCoordinator] over the scripted
/// channel and sink, because "the bar only moves forward" and "a cancelled
/// transfer leaves no file" are claims about that class and not about a
/// hand-built [TransferView].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/core/protocol/control_message.dart' show FileCancelMessage;
import 'package:mkvi/core/protocol/file_transfer.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/workspace/workspace.dart';

import '../../support/mkvi_test_app.dart';
import 'support/workspace_harness.dart';

/// A 300-character Windows path, i.e. the case ROADMAP kusur 8 is about.
const String longWindowsPath =
    'C:\\Users\\ilber\\Documents\\MKVI\\indirilenler\\2026-09-26\\'
    'cok-uzun-bir-dosya-adi-ki-her-zamanlikta-bir-klasor-acilir-ve-'
    'dosya-adlari-cok-uzun-olabilir-boylece-uzun-olarak-yazilmistir-'
    '2026-09-26-120345-1234567890123-rapor-cek-bilgi-notu-v2-final'
    '-son-bir-kopya-ve-baska-bir-kopya-ve-baska-bir-kopya.pdf';

/// One row in each of the five phases, as the layer hands them over.
List<TransferView> everyPhase(String letter) => <TransferView>[  TransferView(
    id: '${letter * 31}a',
    name: 'rapor.pdf',
    direction: TransferDirection.receive,
    phase: TransferPhase.offered,
    transferred: 0,
    total: 4096,
    detail: null,
  ),
  TransferView(
    id: '${letter * 31}b',
    name: 'arsiv.zip',
    direction: TransferDirection.send,
    phase: TransferPhase.active,
    transferred: 1024,
    total: 4096,
    detail: null,
  ),
  TransferView(
    id: '${letter * 31}c',
    name: 'notlar.txt',
    direction: TransferDirection.receive,
    phase: TransferPhase.done,
    transferred: 2048,
    total: 2048,
    detail: longWindowsPath,
  ),
  TransferView(
    id: '${letter * 31}d',
    name: 'kisisel.zip',
    direction: TransferDirection.send,
    phase: TransferPhase.failed,
    transferred: 0,
    total: 4096,
    detail: 'Dosya teklifi reddedildi.',
  ),
  TransferView(
    id: '${letter * 31}e',
    name: 'yarim.pdf',
    direction: TransferDirection.receive,
    phase: TransferPhase.cancelled,
    transferred: 512,
    total: 4096,
    detail: null,
  ),
];

/// Every row, stacked, with no list around them.
///
/// [TransferList] builds lazily inside a bounded box, so a test about what a row
/// *says* has to look at rows rather than at a list whose third item has not
/// been built yet. The list itself is measured in its own tests.
Widget allRows(
  List<TransferView> views, {
  ValueChanged<String>? onAccept,
  ValueChanged<String>? onDecline,
  ValueChanged<String>? onCancel,
  ValueChanged<String>? onDismiss,
}) => workspaceStack(
  Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final TransferView view in views)
        WorkspaceTransferRow(
          key: TransferListKeys.row(view.id),
          view: view,
          onAccept: onAccept,
          onDecline: onDecline,
          onCancel: onCancel,
          onDismiss: onDismiss,
        ),
    ],
  ),
);

void main() {
  group('the five phases are five rows, each in Turkish', () {
    testWidgets('every phase is a row with its own state word', (
      WidgetTester tester,
    ) async {
      final List<TransferView> views = everyPhase('c');
      await pumpMkvi(tester, allRows(views));

      for (final TransferView view in views) {
        expect(
          find.byKey(TransferListKeys.row(view.id)),
          findsOneWidget,
          reason: '${view.phase} is a row',
        );
        expect(
          find.descendant(
            of: find.byKey(TransferListKeys.row(view.id)),
            matching: find.text(view.stateLabel),
          ),
          findsOneWidget,
          reason: '${view.phase} says "${view.stateLabel}"',
        );
        expect(
          find.descendant(
            of: find.byKey(TransferListKeys.row(view.id)),
            matching: find.text(view.heading),
          ),
          findsOneWidget,
          reason: 'and it says which file it is, by name',
        );
      }

      // Five states, five different Turkish words. `cancelled` and `failed`
      // rendered as the same word is what made "you stopped this" and "this
      // broke" indistinguishable in 0.1.x.
      final Set<String> labels = <String>{
        for (final TransferView view in views) view.stateLabel,
      };
      expect(labels.length, 5, reason: 'five states, five words: $labels');
      expect(labels, contains(ChatMessages.awaitingDecision));
      expect(labels, contains(ChatMessages.completed));
      expect(labels, contains(ChatMessages.failed));
      expect(labels, contains(ChatMessages.cancelled));

      expectNoOverflow(tester);
      await expectEveryControlLabelled(tester);
    });

    testWidgets('the actions each phase offers, and only those', (
      WidgetTester tester,
    ) async {
      final List<String> accepted = <String>[];
      final List<String> declined = <String>[];
      final List<String> cancelled = <String>[];
      final List<String> dismissed = <String>[];
      final List<TransferView> views = everyPhase('c');

      await pumpMkvi(
        tester,
        allRows(
          views,
          onAccept: accepted.add,
          onDecline: declined.add,
          onCancel: cancelled.add,
          onDismiss: dismissed.add,
        ),
      );

      // An incoming offer is the one state where the user is being asked, so it
      // is the one state with two answers.
      expect(find.byKey(TransferListKeys.accept(views[0].id)), findsOneWidget);
      expect(find.byKey(TransferListKeys.decline(views[0].id)), findsOneWidget);
      // An outgoing offer has no local decision, but it can be withdrawn.
      expect(find.byKey(TransferListKeys.cancel(views[1].id)), findsOneWidget);
      expect(
        find.byKey(TransferListKeys.accept(views[1].id)),
        findsNothing,
        reason: 'you cannot accept your own offer',
      );
      // A moving transfer can be stopped, from either side.
      expect(find.byKey(TransferListKeys.cancel(views[1].id)), findsOneWidget);
      // A settled row is dismissed and not cancelled: cancelling a finished
      // transfer is what told the peer its file had been cancelled.
      for (final TransferView view in views.sublist(2)) {
        expect(find.byKey(TransferListKeys.dismiss(view.id)), findsOneWidget);
        expect(
          find.byKey(TransferListKeys.cancel(view.id)),
          findsNothing,
          reason: 'a ${view.phase} row is not cancellable',
        );
      }

      await tester.tap(find.byKey(TransferListKeys.accept(views[0].id)));
      await tester.tap(find.byKey(TransferListKeys.decline(views[0].id)));
      await tester.tap(find.byKey(TransferListKeys.cancel(views[1].id)));
      await tester.tap(find.byKey(TransferListKeys.dismiss(views[2].id)));
      await tester.pump();

      expect(accepted, <String>[views[0].id]);
      expect(declined, <String>[views[0].id]);
      expect(cancelled, <String>[views[1].id]);
      expect(dismissed, <String>[views[2].id]);

      expectNoOverflow(tester);
      await expectEveryControlLabelled(tester);
    });

    testWidgets('the list puts the rows in a box, oldest first', (
      WidgetTester tester,
    ) async {
      final List<TransferView> views = everyPhase('c');
      await pumpMkvi(
        tester,
        workspaceStack(TransferList(transfers: views)),
      );
      expect(find.byKey(TransferListKeys.list), findsOneWidget);
      expect(
        find.byKey(TransferListKeys.row(views[1].id)),
        findsOneWidget,
        reason: 'the first two rows are the ones inside the box',
      );
      expect(
        tester.getTopLeft(find.byKey(TransferListKeys.row(views[0].id))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(TransferListKeys.row(views[1].id))).dy,
        ),
        reason: 'and the list keeps the coordinator\'s order',
      );
      expectNoOverflow(tester);
    });
  });

  group('DEFECT 8, the row cannot grow without bound', () {
    testWidgets('a 300-character Windows path is never painted', (
      WidgetTester tester,
    ) async {
      expect(longWindowsPath.length, greaterThan(250));
      final TransferView view = TransferView(
        id: tid('p'),
        name: 'rapor.pdf',
        direction: TransferDirection.receive,
        phase: TransferPhase.done,
        transferred: 2048,
        total: 2048,
        detail: longWindowsPath,
      );

      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceStack(
            TransferList(transfers: <TransferView>[view]),
          ),
        ),
      );

      // The file's name is on screen, so the user still knows what finished.
      expect(
        find.text(view.heading),
        findsOneWidget,
        reason: 'the headline names the file: ${view.heading}',
      );
      expect(view.heading, contains('rapor.pdf'));
      // The path is not, anywhere.
      expect(
        paintedText(tester),
        everyElement(
          allOf(
            isNot(contains('C:\\')),
            isNot(contains('Documents')),
            isNot(contains('.pdf\\')),
          ),
        ),
        reason: 'a destination path is not a sentence a row can say',
      );
      expect(
        find.text(WorkspaceTr.saved.tr),
        findsOneWidget,
        reason: 'so the row says the one thing it can say',
      );
      expect(
        transferDetailLine(view),
        WorkspaceTr.saved.tr,
        reason: 'and that is a property of the view, not of this test',
      );

      // The geometry, measured rather than assumed.
      final double budget = transferRowBudget(style);
      expect(budget, greaterThan(0));
      expect(
        tester.getSize(find.byKey(TransferListKeys.row(view.id))).height,
        lessThanOrEqualTo(budget),
        reason: 'one row is one budget tall, whatever its detail says',
      );
      expect(
        tester.getSize(find.byKey(TransferListKeys.list)).height,
        lessThanOrEqualTo(budget * 2 + 0.5),
        reason: 'and the list is two rows tall, whatever it is handed',
      );

      expectNoOverflow(tester);
      await expectEveryControlLabelled(tester);
    });

    testWidgets('ten times the reason is no taller than the path was', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;
      final TransferView short = TransferView(
        id: tid('s'),
        name: 'notlar.txt',
        direction: TransferDirection.receive,
        phase: TransferPhase.done,
        transferred: 2048,
        total: 2048,
        detail: longWindowsPath,
      );
      // A failure whose *reason* is long, which is the one unbounded string that
      // legitimately reaches this row: the peer's own words.
      final TransferView long = TransferView(
        id: tid('l'),
        name: 'notlar.txt',
        direction: TransferDirection.receive,
        phase: TransferPhase.failed,
        transferred: 0,
        total: 2048,
        detail: List<String>.filled(10, 'Yerim kalmadı. ').join(),
      );
      // The short one is the interesting half: its `detail` is a 296-character
      // path and its *rendered* line is one word, because a settled row does not
      // paint a destination at all.
      expect(
        transferDetailLine(short),
        WorkspaceTr.saved.tr,
        reason: 'the 296-character path is not on the row at all',
      );
      expect(
        transferDetailLine(long).length,
        greaterThan(transferDetailLine(short).length),
        reason: 'and a long reason is longer than "Kaydedildi"',
      );

      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceStack(
            TransferList(transfers: <TransferView>[short]),
          ),
        ),
      );
      final double oneLine = tester
          .getSize(find.byKey(TransferListKeys.row(short.id)))
          .height;

      await unmountMkvi(tester);
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceStack(
            TransferList(transfers: <TransferView>[long]),
          ),
        ),
      );
      final double tenLines = tester
          .getSize(find.byKey(TransferListKeys.row(long.id)))
          .height;

      expect(tenLines, lessThanOrEqualTo(transferRowBudget(style)));
      expect(
        tenLines - oneLine,
        lessThanOrEqualTo(transferRowBudget(style) / 2),
        reason: 'the detail is capped at two lines whatever it says',
      );
      expectNoOverflow(tester);
    });

    testWidgets('a long list scrolls inside the box instead of growing', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;
      final List<TransferView> many = <TransferView>[
        for (int i = 0; i < 12; i += 1)
          TransferView(
            id: tid(hexLetters[i]),
            name: 'dosya-$i.pdf',
            direction: TransferDirection.send,
            phase: TransferPhase.active,
            transferred: i,
            total: 12,
            detail: null,
          ),
      ];

      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceStack(TransferList(transfers: many)),
        ),
      );

      expect(
        tester.getSize(find.byKey(TransferListKeys.list)).height,
        lessThanOrEqualTo(transferRowBudget(style) * 2 + 0.5),
        reason: 'twelve rows are still two rows tall',
      );
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(TransferListKeys.list),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        scrollable.position.maxScrollExtent,
        greaterThan(0),
        reason: 'and the rest is reachable by scrolling, not by pushing',
      );

      expectNoOverflow(tester);
    });

    testWidgets('an empty list is nothing at all', (WidgetTester tester) async {
      await pumpMkvi(
        tester,
        workspaceStack(const TransferList(transfers: <TransferView>[])),
      );
      expect(find.byKey(TransferListKeys.list), findsNothing);
      expectNoOverflow(tester);
    });
  });

  group('the progress bar is a fraction, never a percentage', () {
    testWidgets('the bar is asked for exactly the view\'s ratio', (
      WidgetTester tester,
    ) async {
      for (final (int transferred, int total) in <(int, int)>[
        (0, 4096),
        (1024, 4096),
        (2048, 4096),
        (4096, 4096),
      ]) {
        await unmountMkvi(tester);
        final TransferView view = TransferView(
          id: tid('b'),
          name: 'rapor.pdf',
          direction: TransferDirection.receive,
          phase: TransferPhase.active,
          transferred: transferred,
          total: total,
          detail: null,
        );
        await pumpMkvi(
          tester,
          workspaceStack(TransferList(transfers: <TransferView>[view])),
        );
        final LinearProgressIndicator bar = tester.widget<LinearProgressIndicator>(
          find.descendant(
            of: find.byKey(TransferListKeys.progress(view.id)),
            matching: find.byType(LinearProgressIndicator),
          ),
        );
        expect(bar.value, view.ratio, reason: '$transferred / $total');
        expect(bar.value, inInclusiveRange(0.0, 1.0));
        expect(view.percent, inInclusiveRange(0, 100));
      }
      expectNoOverflow(tester);
    });

    testWidgets('a settled row has no bar at all', (WidgetTester tester) async {
      final List<TransferView> views = everyPhase('c');
      await pumpMkvi(
        tester,
        workspaceStack(TransferList(transfers: views)),
      );
      for (final TransferView view in views) {
        final bool moving =
            view.phase == TransferPhase.offered ||
            view.phase == TransferPhase.active;
        expect(
          find.byKey(TransferListKeys.progress(view.id)),
          moving ? findsOneWidget : findsNothing,
          reason: '${view.phase} ${moving ? 'draws' : 'draws no'} bar',
        );
      }
      expectNoOverflow(tester);
    });
  });

  group('the controls are controls', () {
    testWidgets('every action is at least the token hit target', (
      WidgetTester tester,
    ) async {
      final List<TransferView> views = everyPhase('c');
      late AppearanceStyle style;
      await pumpMkvi(
        tester,
        WorkspaceStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: workspaceStack(TransferList(transfers: views)),
        ),
      );

      // TS: `.mkvi-toast button { width: 34px; height: 34px; … }`.
      for (final TransferView view in views) {
        for (final Key key in <Key>[
          TransferListKeys.accept(view.id),
          TransferListKeys.decline(view.id),
          TransferListKeys.cancel(view.id),
          TransferListKeys.dismiss(view.id),
        ]) {
          final Finder found = find.byKey(key);
          if (found.evaluate().isEmpty) continue;
          expectHitTarget(tester, found, style: style);
        }
      }
      expectNoOverflow(tester);
    });
  });

  group('over the real coordinator', () {
    testWidgets('progress only moves forward, and by bytes stored', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      final String id = tid('a');
      const int size = 4096;

      harness.transfers.onFileOffer(offerFor(id, size: size));
      await tester.pump();
      await harness.transfers.accept(id);
      await tester.pump();

      final List<double> seen = <double>[];
      for (int offset = 0; offset < size; offset += 1024) {
        final Object outcome = await harness.transfers.onFrame(
          frameOf(id, fillerBytes(1024, offset)),
        );
        expect(outcome, isA<FrameStored>(), reason: 'the frame was stored');
        await tester.pump();
        seen.add(harness.transfers.viewOf(id)!.ratio);
      }
      expect(await harness.transfers.onComplete(id), isA<FrameStored>());
      await tester.pump();

      for (int i = 1; i < seen.length; i += 1) {
        expect(
          seen[i],
          greaterThanOrEqualTo(seen[i - 1]),
          reason: 'a bar that walks backwards is the TS defect: $seen',
        );
      }
      for (final double ratio in seen) {
        expect(ratio, inInclusiveRange(0.0, 1.0));
      }
      expect(seen.last, 1.0);
      expect(
        harness.transfers.viewOf(id)!.phase,
        TransferPhase.done,
        reason: 'every declared byte arrived',
      );
      expect(
        harness.chat.files.disk.values.single.length,
        size,
        reason: 'and the sink stored every one of them',
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('a cancelled transfer leaves no file behind', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      final String id = tid('c');

      harness.transfers.onFileOffer(offerFor(id, size: 4096));
      await tester.pump();
      await harness.transfers.accept(id);
      await tester.pump();
      await harness.transfers.onFrame(frameOf(id, fillerBytes(2048)));
      await tester.pump();

      expect(
        harness.chat.files.disk.values,
        hasLength(1),
        reason: 'a file exists while the transfer is running',
      );
      expect(harness.chat.files.disk.values.single.length, 2048);

      expect(harness.transfers.cancel(id), isTrue, reason: 'it was live');
      await tester.pumpAndSettle();

      // The rule `crates/mkvi_core/src/state.rs` was written against: a
      // rejected, declined or cancelled transfer may not leave a 0-byte file —
      // and here the file was not even empty.
      expect(
        harness.chat.files.disk,
        isEmpty,
        reason: 'the partial file is gone, not truncated',
      );
      expect(harness.chat.files.aborted, contains(id));
      expect(
        harness.chat.files.opened,
        isEmpty,
        reason: 'and the transfer is not still open on the sink',
      );
      expect(
        harness.transfers.viewOf(id)!.phase,
        TransferPhase.cancelled,
        reason: 'which the row says as "İptal edildi", not "Başarısız"',
      );
      expect(harness.transfers.viewOf(id)!.stateLabel, ChatMessages.cancelled);
      expect(
        harness.chat.channel.cancels.map((FileCancelMessage m) => m.id),
        contains(id),
        reason: 'and the peer is told, because this was a local cancel',
      );
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });

    testWidgets('a short write moves the bar by what the sink stored', (
      WidgetTester tester,
    ) async {
      final WorkspaceHarness harness = WorkspaceHarness();
      final String id = tid('e');
      // The sink stores a quarter of every chunk: the bar must follow the sink,
      // not the frame it was handed.
      harness.chat.files.shortWriteBytes = 256;

      harness.transfers.onFileOffer(offerFor(id, size: 1024));
      await tester.pump();
      await harness.transfers.accept(id);
      await tester.pump();
      await harness.transfers.onFrame(frameOf(id, fillerBytes(1024)));
      await tester.pump();

      final TransferView view = harness.transfers.viewOf(id)!;
      expect(view.transferred, 256, reason: 'a quarter of one chunk');
      expect(view.ratio, closeTo(0.25, 0.001));
      await disposeHarness(tester, harness);
      expectNoOverflow(tester);
    });
  });
}
