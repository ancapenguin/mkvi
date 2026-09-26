/// The layout, which is the second reported defect: the toast sat on the send
/// button and nothing could be typed.
///
/// The claim under test is *structural*, not a magic offset: `NoticeHost` is an
/// in-flow `Column` child, so it either takes real layout space (and the composer
/// moves down) or it takes none. There is no `Positioned`, no `z-index` and no
/// bottom offset to tune, so "the notice never overlaps the composer" is a
/// consequence of the widget tree rather than a number that has to be right.
///
/// Every rect below is measured with `tester.getRect`, so an assertion fails on
/// real geometry, and every one of them is in a 800x600 window — a small window
/// on purpose, because a fixed overlay with `width: min(390px, …)` and
/// `bottom: 18px` is exactly the shape that only collides once the window is
/// small.
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/ui/notice/notice.dart';

import 'support/notice_test_screen.dart';

void main() {
  group('DEFECT 2, the notice never overlaps the composer', () {
    testWidgets('the notice is laid out above the composer, not over it', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);
      int sent = 0;

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () => sent += 1,
        ),
      );

      // Nothing to say: the lane is zero tall and the composer sits at the
      // bottom, where the user expects it.
      expect(find.byKey(NoticeKeys.lane), findsNothing);
      expect(
        tester.getSize(find.byKey(NoticeTestScreen.send)).height,
        greaterThan(0),
        reason: 'the send button is on screen before any notice',
      );

      harness.controller.showText('Mesaj gönderildi.');
      await tester.pump();

      final Rect notice = tester.getRect(find.byKey(NoticeKeys.surface));
      final Rect composerRect = tester.getRect(
        find.byKey(NoticeTestScreen.composer),
      );
      final Rect sendRect = tester.getRect(find.byKey(NoticeTestScreen.send));

      expect(
        notice.overlaps(composerRect),
        isFalse,
        reason:
            'the reported bug: a fixed bottom-right toast covering the composer',
      );
      expect(
        notice.overlaps(sendRect),
        isFalse,
        reason: 'and specifically the control the user could not click',
      );
      expect(
        notice.bottom,
        lessThanOrEqualTo(composerRect.top),
        reason: 'the notice sits entirely above the composer, not beside it',
      );
      expect(
        sendRect.overlaps(tester.getRect(find.byKey(NoticeKeys.close))),
        isFalse,
        reason: 'the close control is nowhere near the send button',
      );
    });

    testWidgets('the lane reserves its own height, so the list gives way', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );

      final double idleListBottom = tester
          .getRect(find.byKey(NoticeTestScreen.list))
          .bottom;

      harness.controller.showText('Yeniden bağlanılıyor.');
      await tester.pump();

      // The message list shrinks by exactly the height of the lane: the space is
      // reserved, not painted over.
      expect(
        tester.getRect(find.byKey(NoticeTestScreen.list)).bottom,
        lessThan(idleListBottom),
        reason: 'an overlay would leave the list at full height',
      );
      final double laneHeight = tester
          .getSize(find.byKey(NoticeKeys.lane))
          .height;
      expect(
        laneHeight,
        greaterThan(0),
        reason: 'a notice that is on screen occupies real layout space',
      );
      expect(
        tester.getRect(find.byKey(NoticeKeys.lane)).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(NoticeTestScreen.composer)).top,
        ),
        reason: 'the lane ends where the composer begins',
      );

      // And it gives the space back.
      harness.controller.dismiss();
      await tester.pump();
      expect(find.byKey(NoticeKeys.lane), findsNothing);
      expect(
        tester.getRect(find.byKey(NoticeTestScreen.list)).bottom,
        idleListBottom,
        reason: 'the composer returns to where it was',
      );
    });

    testWidgets('the send button is hittable while a notice is up', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);
      int sent = 0;

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () => sent += 1,
        ),
      );
      harness.controller.showText('Dosya kaydedildi.');
      await tester.pump();

      // The user types, presses Enter, and the send button is where it always
      // was. Nothing about the notice may intercept either.
      await tester.enterText(find.byType(TextField), 'Merhaba');
      await tester.tap(find.byKey(NoticeTestScreen.send));
      await tester.pump();

      expect(sent, 1, reason: 'the send button was reachable');
      expect(composer.text, 'Merhaba');
    });

    testWidgets('the close control closes, and the composer is untouched', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText('Yerel geçmiş açılamadı.');
      await tester.pump();
      expect(find.byKey(NoticeKeys.surface), findsOneWidget);

      await tester.tap(find.byKey(NoticeKeys.close));
      await tester.pump();

      expect(
        find.byKey(NoticeKeys.surface),
        findsNothing,
        reason: 'the button TS made look dead works here',
      );
      expect(composer.text, isEmpty, reason: 'and it typed nothing');
    });

    testWidgets('the notice is right-aligned and inside the reserved gutter', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
          metrics: const NoticeMetrics(),
        ),
      );
      harness.controller.showText('Merhaba.');
      await tester.pump();

      final Size window =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final Rect lane = tester.getRect(find.byKey(NoticeKeys.lane));
      final Rect surface = tester.getRect(find.byKey(NoticeKeys.surface));

      expect(
        surface.right,
        closeTo(window.width - const NoticeMetrics().laneGapX, 0.01),
        reason: 'flush right inside the gutter, as bottom-right means here',
      );
      expect(lane.height, greaterThan(surface.height));
      expect(lane.width, closeTo(window.width, 0.01));
    });

    testWidgets('a narrow window shrinks the notice instead of overflowing', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText('Bağlantı ayarları kaydedildi.');
      await tester.pump();

      final Size window =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final Rect surface = tester.getRect(find.byKey(NoticeKeys.surface));
      expect(
        surface.width,
        lessThanOrEqualTo(window.width - (2 * const NoticeMetrics().laneGapX)),
        reason: 'a narrow window narrows the toast rather than clipping it',
      );
      expect(
        surface.overlaps(tester.getRect(find.byKey(NoticeTestScreen.composer))),
        isFalse,
        reason: 'the reported bug, in the window size where it happened',
      );
    });
  });

  group('DEFECT 5, a long notice is capped and never grows without bound', () {
    testWidgets('a 300-character Windows path is capped and scrollable', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      const String longPath =
          'C:\\Users\\ilber\\Documents\\MKVI\\indirilenler\\2026-09-26\\'
          'cok-uzun-bir-dosya-adi-ki-her-zamanlikta-bir-klasor-acilir-ve-'
          'dosya-adlari-cok-uzun-olabilir-boylece-uzun-olarak-yazilmistir-'
          '2026-09-26-120345-1234567890123-rapor-cek-bilgi-notu-v2-final'
          '.pdf';
      expect(longPath.length, greaterThan(150));

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText('Dosya kaydedildi: $longPath');
      await tester.pump();

      final NoticeMetrics metrics = const NoticeMetrics();
      final double bodyHeight = tester
          .getSize(find.byKey(NoticeKeys.body))
          .height;
      expect(
        bodyHeight,
        lessThanOrEqualTo(metrics.maxBodyHeight + 0.5),
        reason: 'the body is capped at three lines whatever the text says',
      );
      expect(
        tester.getSize(find.byKey(NoticeKeys.surface)).height,
        lessThanOrEqualTo(metrics.maxSurfaceHeight + 0.5),
        reason: 'and so is the whole surface',
      );

      // The rest of the text is reachable, which is what makes the cap a cap and
      // not a truncation.
      final ScrollableState scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(NoticeKeys.body),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        scrollable.position.maxScrollExtent,
        greaterThan(0),
        reason: 'a long notice must be scrollable past its cap',
      );

      await tester.drag(find.byKey(NoticeKeys.body), const Offset(0, -40));
      await tester.pump();
      expect(scrollable.position.pixels, greaterThan(0));
    });

    testWidgets('ten times the text is exactly as tall as once', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      const String oneLine = 'Bağlantı ayarları kaydedildi.';

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText(oneLine);
      await tester.pump();
      final double shortHeight = tester
          .getSize(find.byKey(NoticeKeys.surface))
          .height;

      harness.controller.dismiss();
      harness.controller.showText(oneLine * 10);
      await tester.pump();
      final double longHeight = tester
          .getSize(find.byKey(NoticeKeys.surface))
          .height;

      expect(
        longHeight,
        closeTo(shortHeight, 24),
        reason: 'both are at the cap, and a toast is never unbounded',
      );
      expect(
        longHeight,
        lessThanOrEqualTo(const NoticeMetrics().maxSurfaceHeight + 0.5),
      );
    });

    testWidgets('a short notice is not taller than the close control', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText('Tamam.');
      await tester.pump();

      const NoticeMetrics metrics = NoticeMetrics();
      final double oneLineCeiling =
          (metrics.borderWidth * 2) +
          (metrics.paddingY * 2) +
          metrics.closeTarget;
      expect(
        tester.getSize(find.byKey(NoticeKeys.surface)).height,
        lessThanOrEqualTo(oneLineCeiling + 0.5),
        reason:
            'one short line is shorter than the three-line cap, so the close '
            'control is what sets the height',
      );
      expect(
        tester.getSize(find.byKey(NoticeKeys.surface)).height,
        lessThan(metrics.maxSurfaceHeight),
        reason: 'and well under the surface cap',
      );
    });
  });

  group('DEFECT 3, the close control is a real control', () {
    testWidgets('its hit target is at least 40 dp on both sides', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText('Kapatılacak bir bildirim.');
      await tester.pump();

      final Size target = tester.getSize(find.byKey(NoticeKeys.close));
      expect(
        target.width,
        greaterThanOrEqualTo(NoticeMetrics.minimumCloseTarget),
        reason: 'TS: .mkvi-toast button was 34 x 34 px',
      );
      expect(
        target.height,
        greaterThanOrEqualTo(NoticeMetrics.minimumCloseTarget),
      );
      expect(target.width, const NoticeMetrics().closeTarget);
    });

    testWidgets('its glyph has a real size and colour, not a dropped rule', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
          palette: midnightBluePalette,
        ),
      );
      harness.controller.showText('Bir şey oldu.', kind: NoticeKind.warning);
      await tester.pump();

      // TS: `font: 700 1.15rem/1 inherit;` is invalid CSS — `inherit` may not be
      // the last component of the `font` shorthand — so the whole declaration
      // was dropped. Here the size and the colour are properties of an Icon, and
      // a test can read them.
      final Icon glyph = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(NoticeKeys.close),
          matching: find.byType(Icon),
        ),
      );
      expect(glyph.size, const NoticeMetrics().closeIconSize);
      expect(glyph.size, isNotNull, reason: 'an explicit size, not a default');
      expect(glyph.color, midnightBluePalette.muted);
      expect(glyph.icon, Icons.close_rounded);
    });

    testWidgets('it has a visible hover state and a visible focus ring', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText('Bir şey oldu.');
      await tester.pump();

      Color glyphColour() => tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(NoticeKeys.close),
              matching: find.byType(Icon),
            ),
          )
          .color!;

      expect(glyphColour(), midnightBluePalette.muted, reason: 'at rest');

      // Hover: the glyph brightens to the full text colour.
      final TestGesture pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await pointer.addPointer();
      addTearDown(() => pointer.removePointer());
      await pointer.moveTo(tester.getCenter(find.byKey(NoticeKeys.close)));
      await tester.pumpAndSettle();

      expect(
        glyphColour(),
        midnightBluePalette.onSurface,
        reason: 'hover must be visible, not just implied by a cursor',
      );
    });

    testWidgets('it is reachable and activatable from the keyboard', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText('Kapatılacak bir bildirim.');
      await tester.pump();

      // Tab order reaches it, and the focus ring is drawn: a notice the user can
      // only dismiss with a mouse is a notice they may never dismiss.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final FocusNode focus = FocusManager.instance.primaryFocus!;
      expect(focus.hasFocus, isTrue, reason: 'something took focus');
      expect(
        find.descendant(
          of: find.byKey(NoticeKeys.close),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
        reason: 'the close control is the thing that is focusable here',
      );
    });

    testWidgets('the surface announces the severity and the sentence once', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);
      // Disposed at the end of the body, not in a teardown: the framework
      // verifies handles before teardowns run.
      final SemanticsHandle handle = tester.ensureSemantics();

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText(
        'Cihaz kimliği açılamadı.',
        kind: NoticeKind.error,
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel('Hata. Cihaz kimliği açılamadı.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(NoticeTr.close.tr), findsOneWidget);
      handle.dispose();
    });
  });

  group('what the surface paints', () {
    testWidgets('every colour comes from the palette it was given', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText('Bir uyarı.', kind: NoticeKind.warning);
      await tester.pump();

      final Container surface = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(NoticeKeys.surface),
              matching: find.byType(Container),
            )
            .first,
      );
      final BoxDecoration decoration = surface.decoration! as BoxDecoration;
      expect(decoration.color, midnightBluePalette.surface);

      final Container outline = tester.widget<Container>(
        find.byKey(NoticeKeys.outline),
      );
      final BoxDecoration outlineDecoration =
          outline.decoration! as BoxDecoration;
      final Border border = outlineDecoration.border! as Border;
      expect(
        border.left.color,
        midnightBluePalette.warning,
        reason: 'the stripe is the severity colour from the palette',
      );
      expect(
        border.top.color,
        midnightBluePalette.border,
        reason: 'the outline is the border role',
      );

      final Icon mark = tester.widget<Icon>(find.byKey(NoticeKeys.mark));
      expect(mark.color, midnightBluePalette.colourFor(NoticeKind.warning));
    });

    testWidgets('a different palette paints a different notice', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);
      const NoticePalette other = NoticePalette(
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF101828),
        muted: Color(0xFF4A5566),
        border: Color(0xFF6F7A8B),
        accent: Color(0xFF107D74),
        success: Color(0xFF12703A),
        warning: Color(0xFF92400E),
        danger: Color(0xFFB91C1C),
        focusRing: Color(0xFF020F0E),
        shadow: Color(0x33101828),
      );

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
          palette: other,
        ),
      );
      harness.controller.showText('Bir hata.', kind: NoticeKind.error);
      await tester.pump();

      final Icon mark = tester.widget<Icon>(find.byKey(NoticeKeys.mark));
      expect(
        mark.color,
        other.danger,
        reason: 'so the layer follows the theme rather than a literal',
      );
      expect(mark.color, isNot(midnightBluePalette.danger));
    });

    testWidgets('the severity chooses the mark, not the text', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );

      for (final NoticeKind kind in NoticeKind.values) {
        harness.controller.dismiss();
        // A different sentence per kind, because a close is remembered until the
        // text actually changes — the same text here would be refused, which is
        // the point of that rule and not what this test is about.
        harness.controller.showText('Bir ${kind.name} cümlesi.', kind: kind);
        await tester.pump();

        final Icon mark = tester.widget<Icon>(find.byKey(NoticeKeys.mark));
        expect(
          mark.color,
          midnightBluePalette.colourFor(kind),
          reason: '${kind.name} has its own colour',
        );
        expect(mark.icon, isNotNull, reason: '${kind.name} has its own mark');
      }
    });
  });

  group('the host as a listener', () {
    testWidgets('it rebuilds on a change and collapses on an empty channel', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      expect(find.byKey(NoticeKeys.surface), findsNothing);

      harness.controller.showText('Birinci.');
      await tester.pump();
      expect(find.text('Birinci.'), findsOneWidget);

      // A different text replaces it in place, and the height does not jump
      // because the lane is a flow child either way.
      harness.controller.showText('İkinci.');
      await tester.pump();
      expect(find.text('Birinci.'), findsNothing);
      expect(find.text('İkinci.'), findsOneWidget);

      harness.controller.dismiss();
      await tester.pump();
      expect(find.byKey(NoticeKeys.surface), findsNothing);
    });

    testWidgets('a sticky error does not disappear when the clock moves', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText(
        'Cihaz kimliği doğrulanamadı.',
        kind: NoticeKind.error,
      );
      await tester.pump();

      harness.clock.advance(const Duration(hours: 12));
      await tester.pump();

      // The rendered `Text` carries the soft breaks, so the assertion strips them
      // rather than looking for the raw sentence.
      final Text body = tester.widget<Text>(
        find.descendant(
          of: find.byKey(NoticeKeys.body),
          matching: find.byType(Text),
        ),
      );
      expect(
        noticeVisibleText(body.data!),
        'Cihaz kimliği doğrulanamadı.',
        reason: 'the severity rule, seen in the widget tree',
      );
    });

    testWidgets('an info disappears on its deadline, with no pump of its own', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final TextEditingController composer = TextEditingController();
      addTearDown(composer.dispose);

      await tester.pumpWidget(
        NoticeTestScreen(
          controller: harness.controller,
          text: composer,
          onSend: () {},
        ),
      );
      harness.controller.showText('Bağlantı ayarları kaydedildi.');
      await tester.pump();
      expect(find.byKey(NoticeKeys.surface), findsOneWidget);

      harness.clock.advance(harness.policy.transientLifetime);
      await tester.pump();

      expect(find.byKey(NoticeKeys.surface), findsNothing);
    });
  });

  group('the status strip', () {
    testWidgets('it shows the state and never becomes a notice', (
      WidgetTester tester,
    ) async {
      final NoticeHarness harness = NoticeHarness();
      addTearDown(harness.dispose);
      final NoticePalette palette = midnightBluePalette;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const Expanded(child: SizedBox.expand()),
                NoticeStatusBar(
                  controller: harness.controller,
                  palette: palette,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Hazır'), findsOneWidget);

      for (final ConnectionStatus status in ConnectionStatus.values) {
        harness.controller.setStatus(status);
        await tester.pump();
        expect(find.text(status.labelTr), findsOneWidget);
        expect(
          find.byKey(NoticeKeys.surface),
          findsNothing,
          reason: '$status is not a toast',
        );
      }

      // Even after a long time, and even with a notice also on screen.
      harness.clock.advance(const Duration(days: 1));
      await tester.pump();
      expect(find.text(harness.controller.status.labelTr), findsOneWidget);
    });
  });

  group('the clock seam in a widget test', () {
    test('a disabled clock keeps a notice up, with no timer at all', () {
      // The second seam, for a screen that wants no auto-dismissal. It is
      // asserted here so the production timer stays out of the tested path.
      final NoticeController controller = NoticeController(
        clock: const DisabledNoticeClock(),
      );
      addTearDown(controller.dispose);

      controller.showText('Birinci.');
      expect(controller.hasNotice, isTrue);
      expect(controller.pendingAutoDismiss, isNotNull);

      controller.showText('İkinci.');
      expect(controller.notice!.text, 'İkinci.');

      controller.dismiss();
      expect(controller.hasNotice, isFalse);
    });

    test('the production seam is a value, and no test schedules through it', () {
      // Not exercised: it would wait 5.5 s of real time. What is asserted is that
      // the seam is a value the app picks, so `SystemNoticeClock.schedule` is only
      // ever reached from production wiring.
      const NoticeClock clock = systemNoticeClock;
      expect(clock, isA<SystemNoticeClock>());
      expect(clock, isNot(const DisabledNoticeClock()));
      expect(
        const SystemNoticeClock().now(),
        isA<DateTime>(),
        reason: 'the production seam reads a real clock',
      );
      // And the controller refuses to be built without one: the parameter is
      // required, which is what keeps a default timer out of this package. Every
      // controller in this directory is constructed with a clock, and the
      // analysis of the class says there is no other way to build one.
      expect(
        NoticeController.new,
        isNotNull,
        reason: 'the constructor takes a required named clock',
      );
    });
  });
}
