/// The composer: never disabled by the peer, disabled only by emptiness, and the
/// one place where a refusal has to keep the text.
///
/// ## The defect this inverts
///
/// `src/App.tsx` wrote
///
/// ```ts
/// const id = peer.current?.sendChat(body);
/// if (!id) throw new Error("Karşı cihaz çevrimdışı.");
/// ```
///
/// and disabled the field on the peer's state, so the two windows in which a
/// user most wants to type — during a reconnect, and in the instant between a
/// field becoming enabled and the keypress landing — were the two windows in
/// which typing was impossible, and one throw lost the paragraph.
///
/// So the composer has exactly one disabled state, and it is the text being
/// blank. [MessageComposer.channelOpen] changes one *sentence* under the field
/// and nothing else, and the test below measures that: the field is still
/// typeable, and a line written during a closed channel still reaches the
/// screen (that half is `workspace_screen_test.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/workspace/workspace.dart';

import '../../support/mkvi_test_app.dart';
import 'support/workspace_harness.dart';

/// The composer in a 320 dp column, which is the width that makes an overflow
/// possible and the height that gives it room to grow into.
Widget composerUnderTest({
  required bool Function(String body) onSend,
  bool channelOpen = true,
  int queuedCount = 0,
  TextEditingController? text,
  int maxLines = 4,
}) => workspaceColumn(
  MessageComposer(
    onSend: onSend,
    channelOpen: channelOpen,
    queuedCount: queuedCount,
    controller: text,
    maxLines: maxLines,
  ),
);

/// The send control, as the button it is.
FilledButton sendButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(ComposerKeys.send));

void main() {
  group('the only disabled state is an empty field', () {
    testWidgets('blank: the button is there and it is disabled', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, composerUnderTest(onSend: (_) => true));

      expect(find.byKey(ComposerKeys.send), findsOneWidget);
      expect(
        sendButton(tester).onPressed,
        isNull,
        reason: 'there is nothing to send, and the control says so',
      );
      expectNoOverflow(tester);
      await expectEveryControlLabelled(tester);
    });

    testWidgets('whitespace is still empty', (WidgetTester tester) async {
      await pumpMkvi(tester, composerUnderTest(onSend: (_) => true));
      await tester.enterText(find.byKey(ComposerKeys.input), '   \n  ');
      await tester.pump();
      expect(
        sendButton(tester).onPressed,
        isNull,
        reason: 'the layer trims before it refuses, so this is the same state',
      );
      expectNoOverflow(tester);
    });

    testWidgets('text: the button comes alive', (WidgetTester tester) async {
      final List<String> sent = <String>[];
      await pumpMkvi(
        tester,
        composerUnderTest(onSend: (String body) {
          sent.add(body);
          return true;
        }),
      );

      await tester.enterText(find.byKey(ComposerKeys.input), 'Merhaba');
      await tester.pump();
      expect(sendButton(tester).onPressed, isNotNull);
      expect(sendButton(tester).onPressed, isA<VoidCallback>());

      await tester.tap(find.byKey(ComposerKeys.send));
      await tester.pump();
      expect(sent, <String>['Merhaba']);
      expect(
        tester.widget<TextField>(find.byKey(ComposerKeys.input)).controller?.text,
        isEmpty,
        reason: 'the field is cleared only because the line was written down',
      );
      expect(
        sendButton(tester).onPressed,
        isNull,
        reason: 'and the button goes back to being disabled',
      );
      expectNoOverflow(tester);
    });

    testWidgets('a refused send keeps the text where it was typed', (
      WidgetTester tester,
    ) async {
      final List<String> sent = <String>[];
      final TextEditingController text = TextEditingController();
      addTearDown(text.dispose);
      await pumpMkvi(
        tester,
        composerUnderTest(
          text: text,
          onSend: (String body) {
            sent.add(body);
            return false;
          },
        ),
      );

      await tester.enterText(find.byKey(ComposerKeys.input), 'Bir paragraf');
      await tester.pump();
      await tester.tap(find.byKey(ComposerKeys.send));
      await tester.pump();

      expect(sent, <String>['Bir paragraf'], reason: 'it was offered');
      expect(
        text.text,
        'Bir paragraf',
        reason:
            'and a refusal that never reached the queue must not cost the user '
            'the paragraph: a send that clears the field first and then fails '
            'loses it',
      );
      expect(sendButton(tester).onPressed, isNotNull);
      expectNoOverflow(tester);
    });
  });

  group('the channel being down changes one sentence', () {
    testWidgets('the field is still typeable, and the send still works', (
      WidgetTester tester,
    ) async {
      final List<String> sent = <String>[];
      await pumpMkvi(
        tester,
        composerUnderTest(
          channelOpen: false,
          onSend: (String body) {
            sent.add(body);
            return true;
          },
        ),
      );

      // TS: `<input … disabled={!peerOnline} …/>`. The field is not disabled
      // here, and the typing and the send below are the assertion that says so —
      // `TextField.enabled` is `null` by default, which means "inherit", so
      // reading it would assert nothing.
      expect(
        find.text(ChatMessages.holdingForReconnect),
        findsOneWidget,
        reason: 'what the user is told instead of a disabled field',
      );

      await tester.enterText(find.byKey(ComposerKeys.input), 'Yine de yazdim');
      await tester.pump();
      await tester.tap(find.byKey(ComposerKeys.send));
      await tester.pump();
      expect(sent, <String>['Yine de yazdim']);
      expectNoOverflow(tester);
    });

    testWidgets('the helper line names the queue, in Turkish', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, composerUnderTest(onSend: (_) => true));
      expect(
        find.descendant(
          of: find.byKey(ComposerKeys.input),
          matching: find.text(WorkspaceTr.composerHelper.tr),
        ),
        findsOneWidget,
        reason: 'with nothing queued it says where a message will go',
      );

      await unmountMkvi(tester);
      await pumpMkvi(
        tester,
        composerUnderTest(onSend: (_) => true, queuedCount: 3),
      );
      expect(
        find.descendant(
          of: find.byKey(ComposerKeys.input),
          matching: find.text(workspaceQueuedLines(3)),
        ),
        findsOneWidget,
        reason: 'three lines are waiting, and the user is told there are three',
      );
      expect(
        find.descendant(
          of: find.byKey(ComposerKeys.input),
          matching: find.text(WorkspaceTr.composerHelper.tr),
        ),
        findsNothing,
      );
      expectNoOverflow(tester);
    });
  });

  group('the field is a field', () {
    testWidgets('it is at least the token hit target, at every density', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in mkviScaleMatrix()) {
        await unmountMkvi(tester);
        late AppearanceStyle style;
        await pumpMkvi(
          tester,
          WorkspaceStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: composerUnderTest(onSend: (_) => true),
          ),
          settings: settings,
        );
        expectHitTarget(tester, find.byKey(ComposerKeys.input), style: style);
        expectHitTarget(tester, find.byKey(ComposerKeys.send), style: style);
        expectNoOverflow(tester);
      }
    });

    testWidgets('it is several lines tall and none of them overflows', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, composerUnderTest(onSend: (_) => true));
      final double oneLine = tester
          .getSize(find.byKey(ComposerKeys.input))
          .height;

      await tester.enterText(
        find.byKey(ComposerKeys.input),
        'birinci satir\nikinci satir\nucuncu satir',
      );
      await tester.pump();

      expect(
        tester.getSize(find.byKey(ComposerKeys.input)).height,
        greaterThan(oneLine),
        reason: 'a paragraph is typed as a paragraph, not pasted sideways',
      );
      expect(
        tester.widget<TextField>(find.byKey(ComposerKeys.input)).maxLines,
        4,
        reason: 'and the field stops growing at four lines',
      );
      expectNoOverflow(tester);
    });

    testWidgets('it grows to its cap and no further', (WidgetTester tester) async {
      await pumpMkvi(
        tester,
        workspaceColumn(
          MessageComposer(
            onSend: (_) => true,
            maxLines: 2,
            controller: TextEditingController(
              text: List<String>.filled(20, 'satir').join('\n'),
            ),
          ),
        ),
      );
      final double cap = tester.getSize(find.byKey(ComposerKeys.input)).height;
      await tester.enterText(
        find.byKey(ComposerKeys.input),
        List<String>.filled(40, 'satir').join('\n'),
      );
      await tester.pump();
      expect(
        tester.getSize(find.byKey(ComposerKeys.input)).height,
        closeTo(cap, 0.01),
        reason: 'twice the text is exactly as tall as once: a bounded composer',
      );
      expectNoOverflow(tester);
    });

    testWidgets('the composer is announced with a Turkish name', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, composerUnderTest(onSend: (_) => true));
      // Read through the harness's own reader rather than
      // `tester.getSemantics`: the hint reaches the field through the
      // `InputDecorator`'s node, which is *above* the node the key names, and
      // `expectEveryControlLabelled` already knows to look at a control's whole
      // subtree.
      final List<ControlReading> readings = await readControlLabels(tester);
      expect(
        readings.map((ControlReading r) => r.spoken).join(' | '),
        contains(WorkspaceTr.composerHint.tr),
        reason: 'a field with no name is a field a screen reader cannot find',
      );
      expect(
        readings.map((ControlReading r) => r.spoken).join(' | '),
        contains(WorkspaceTr.send.tr),
        reason: 'and the send button names itself in Turkish too',
      );
      expectNoOverflow(tester);
    });
  });

  group('the whole screen surface survives its extremes', () {
    testWidgets('every theme, accent, scale and accessibility switch', (
      WidgetTester tester,
    ) async {
      final Iterable<AppearanceSettings> everything = <Iterable<AppearanceSettings>>[
        mkviAppearanceMatrix(),
        mkviScaleMatrix(),
        mkviAccessibilityMatrix(),
      ].expand((Iterable<AppearanceSettings> m) => m);

      for (final AppearanceSettings settings in everything) {
        await unmountMkvi(tester);
        await pumpMkvi(
          tester,
          composerUnderTest(
            onSend: (_) => true,
            channelOpen: false,
            queuedCount: 2,
          ),
          settings: settings,
        );
        expectNoOverflow(tester);
        expect(
          sendButton(tester).onPressed,
          isNull,
          reason: describeCombination(settings),
        );
      }
    });
  });
}
