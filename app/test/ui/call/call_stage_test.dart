/// The stage, and `ROADMAP.md` Faz 2's still-open item:
///
/// > Sahne kutuplaşması testle korunuyor (`stage` koyu, `textOnStage` açık, her
/// > temada) — 0.1.x'teki 1.17:1 sıfırının yapısal olarak geri dönmesini
/// > engelleyen şey bu.
///
/// `design/test/contrast_test.dart` already measures the *pair* in all sixteen
/// theme/accent combinations and refuses a light `stage` outright. What it cannot
/// do is say whether a **screen** uses those two roles: a stage that painted its
/// caption in `textMuted` would pass every token test and reproduce the sibling
/// failure the same test file records at 2.79:1. So this file asserts the
/// *rendered* colours — read out of the widgets the tree actually built — in all
/// four themes, and it asserts the polarity as a measured luminance difference
/// rather than as a comment.
///
/// The second half of the file is the geometry `ROADMAP.md`'s reported defect 5
/// is about: a stage pinned to the local camera with the peer in a fixed 126 px
/// box. The claims are that the box is a **multiple of a control height** rather
/// than a pixel, and that the same multiple holds at every density.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/protocol/control_message.dart' show CallMode;
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/call/call.dart';

import '../../support/mkvi_test_app.dart';
import 'support/accessibility_floor.dart';
import 'support/call_screen_fixture.dart';

/// The four themes `design/tokens.json` declares, spelled out so the failure names
/// the theme rather than an index.
const List<ThemePreference> everyTheme = <ThemePreference>[
  ThemePreference.midnight,
  ThemePreference.light,
  ThemePreference.forest,
  ThemePreference.plum,
];

/// The floor every test in `test/ui/call` ends with.
///
/// [expectNoOverflow] for the defect class 0.1.x shipped in every screen, and
/// both accessibility floors: the semantics one, which is what the harness's
/// `expectEveryControlLabelled` intends to be, and the widget-tree one. The
/// harness's own helper is not called — it disposes its `SemanticsHandle` in an
/// `addTearDown` that runs after the framework's end-of-test check, and it reads
/// an owner that has no tree. Both measured in `call_controls_test.dart` and
/// written up in `support/accessibility_floor.dart`.
Future<void> expectStageSound(WidgetTester tester) async {
  expectNoOverflow(tester);
  await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
  expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
}

/// A stage the way the screen builds it: a bounded box to lay out in.
Widget stageSample({
  String caption = 'Aktif görüntü yok',
  CallStageFocus focus = CallStageFocus.local,
  bool showPip = true,
  LocalPipCorner corner = LocalPipCorner.topRight,
  String? pipCaption,
}) {
  return Padding(
    padding: const EdgeInsets.all(24),
    child: CallStage(
      caption: caption,
      focus: focus,
      showPip: showPip,
      pipCorner: corner,
      pipCaption: pipCaption,
    ),
  );
}

void main() {
  group('the stage polarity, in every theme', () {
    for (final ThemePreference theme in everyTheme) {
      testWidgets('${theme.name}: textOnStage clears 4.5:1 on stage', (
        WidgetTester tester,
      ) async {
        final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
        late AppearanceStyle seen;
        await fixture.pumpWidget(
          tester,
          stageSample(),
          settings: AppearanceSettings(theme: theme),
          onStyle: (AppearanceStyle style) => seen = style,
        );

        expect(seen.themeId, theme.name);
        expectTokenContrast(seen, 'textOnStage', 'stage', minimum: 4.5);
        await expectStageSound(tester);
      });

      testWidgets('${theme.name}: the stage is dark and its text is light', (
        WidgetTester tester,
      ) async {
        final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
        late AppearanceStyle seen;
        await fixture.pumpWidget(
          tester,
          stageSample(),
          settings: AppearanceSettings(theme: theme),
          onStyle: (AppearanceStyle style) => seen = style,
        );

        final Color stage = seen.role('stage');
        final Color onStage = seen.role('textOnStage');
        expect(
          stage.computeLuminance(),
          lessThan(0.02),
          reason:
              'the old light theme painted the stage #e9edf3 and put #f8fafc on '
              'it: 1.17:1, the worst measured pair this app ever shipped',
        );
        expect(
          onStage.computeLuminance(),
          greaterThan(0.5),
          reason: 'textOnStage is always the light role',
        );
        expect(
          onStage.computeLuminance() - stage.computeLuminance(),
          greaterThan(0),
          reason:
              'the polarity claim as a difference rather than as two separate '
              'bounds: a theme where the two cross is a theme where the stage '
              'is unreadable and neither assertion alone would say so',
        );
        await expectStageSound(tester);
      });
    }

    testWidgets('the rendered colours ARE those two roles, in all sixteen pairs', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      final List<String> seenPairs = <String>[];

      await fixture.pumpMatrix(
        tester,
        (AppearanceSettings settings) => stageSample(),
        matrix: mkviAppearanceMatrix(),
        each: (AppearanceSettings settings, CallUiHost _) {
          final AppearanceStyle style = mkviStyleOf(tester);
          expectTokenContrast(style, 'textOnStage', 'stage', minimum: 4.5);

          // Read the *rendered* surface and the *rendered* strings, rather than
          // comparing a colour the test typed in.
          final BoxDecoration surface = tester
              .widget<DecoratedBox>(find.byKey(CallStageKeys.surface))
              .decoration as BoxDecoration;
          expect(
            surface.color,
            style.role('stage'),
            reason: 'the stage paints the `stage` role and nothing else',
          );

          final Text caption = tester.widget<Text>(
            find.descendant(
              of: find.byKey(CallStageKeys.mainTile),
              matching: find.byKey(VideoTileKeys.caption),
            ),
          );
          final Text label = tester.widget<Text>(
            find.byKey(VideoTileKeys.label).first,
          );
          expect(caption.style?.color, style.role('textOnStage'));
          expect(label.style?.color, style.role('textOnStage'));
          expect(
            caption.style?.color,
            isNot(style.role('textMuted')),
            reason:
                'textMuted on a dark stage is the 2.79:1 sibling the token test '
                'also records, and no token test can see a screen reach for it',
          );
          seenPairs.add('${settings.theme.name}/${settings.accent.accentId}');
          expectNoOverflow(tester);
        },
      );

      expect(
        seenPairs,
        hasLength(16),
        reason: 'the whole 4x4 grid, not a sample of it',
      );
      expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
    });
  });

  group('the small picture is not 126 px', () {
    testWidgets('its width is a multiple of the sm control height', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      late AppearanceStyle seen;
      await fixture.pumpWidget(
        tester,
        stageSample(),
        onStyle: (AppearanceStyle style) => seen = style,
      );

      final double width = tester
          .getSize(find.byKey(LocalPipKeys.box))
          .width;
      final double sm = seen.control('sm').height;
      expect(
        width,
        closeTo(sm * 4, 0.01),
        reason:
            'four `sm` control heights: a proportion the design system can '
            'scale, not a number 0.1.x wrote down',
      );
      expect(
        width,
        isNot(126),
        reason: 'TS: the peer sat in a fixed 126 px box with no way to take over',
      );
      expect(LocalPip.sideOf(seen), closeTo(sm * 4, 0.01));
      await expectStageSound(tester);
    });

    testWidgets('the same multiple holds at every density', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      final Map<String, double> multiples = <String, double>{};

      for (final DensityPreference density in DensityPreference.values) {
        // The style is read from inside a build; the *measurement* has to wait
        // until after the pump, because a widget that has not been laid out has
        // no rect to give.
        late AppearanceStyle seen;
        await fixture.pumpWidget(
          tester,
          stageSample(),
          settings: AppearanceSettings(density: density),
          onStyle: (AppearanceStyle style) => seen = style,
        );
        multiples[density.name] =
            tester.getSize(find.byKey(LocalPipKeys.box)).width /
            seen.control('sm').height;
        expectNoOverflow(tester);
      }

      expect(multiples, hasLength(DensityPreference.values.length));
      final Iterable<double> distinct = multiples.values.toSet();
      expect(
        distinct,
        hasLength(1),
        reason:
            'the picture is the same number of control-heights across at every '
            'density — a literal would make these differ: $multiples',
      );
      expect(multiples.values.first, closeTo(4, 0.01));
      expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
    });

    testWidgets('it sits in the corner it was told to', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      late AppearanceStyle seen;

      for (final LocalPipCorner corner in LocalPipCorner.values) {
        await fixture.pumpWidget(
          tester,
          stageSample(corner: corner),
          onStyle: (AppearanceStyle style) => seen = style,
        );
        final Rect stage = tester.getRect(find.byKey(CallStageKeys.surface));
        final Rect box = tester.getRect(find.byKey(LocalPipKeys.box));
        final double inset = seen.gap('3');
        final bool onLeft =
            corner == LocalPipCorner.topLeft ||
            corner == LocalPipCorner.bottomLeft;
        final bool onTop =
            corner == LocalPipCorner.topLeft ||
            corner == LocalPipCorner.topRight;

        expect(box.center.dx, onLeft ? lessThan(stage.center.dx) : greaterThan(stage.center.dx));
        expect(box.center.dy, onTop ? lessThan(stage.center.dy) : greaterThan(stage.center.dy));
        // The gutter is `gap('3')` from the stage's edge on both sides, which is
        // the whole of the "a corner, measured" claim.
        expect(
          onLeft ? box.left - stage.left : stage.right - box.right,
          closeTo(inset, 1.5),
          reason: '$corner keeps gap(\'3\') from the stage edge',
        );
        expect(
          onTop ? box.top - stage.top : stage.bottom - box.bottom,
          closeTo(inset, 1.5),
          reason: '$corner keeps gap(\'3\') from the stage edge',
        );
        expectNoOverflow(tester);
      }
      expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
    });

    testWidgets('the frame is 16 by 9, which is a shape and not a token', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      await fixture.pumpWidget(
        tester,
        stageSample(),
        onStyle: (AppearanceStyle _) {},
      );

      final Size main = tester.getSize(find.byKey(CallStageKeys.mainTile));
      expect(
        main.width / main.height,
        closeTo(callVideoAspect, 0.02),
        reason:
            'a camera frame is 16:9 in every theme, density and type scale; a '
            'stage that letterboxes the tile rather than stretching it is what '
            'makes this true at 1280x800 as well as at 400x720',
      );
      expect(callVideoAspect, closeTo(16 / 9, 0.0001));
      await expectStageSound(tester);
    });
  });

  group('the stage has a subject, and the subject changes', () {
    testWidgets('the main tile shows the peer once the peer\'s camera is live', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);

      await fixture.pumpWidget(
        tester,
        stageSample(focus: CallStageFocus.local),
        onStyle: (AppearanceStyle _) {},
      );
      expect(find.byKey(CallStageKeys.focus(CallStageFocus.local)), findsOneWidget);
      expect(find.text(CallUiTr.localVideoLabel), findsOneWidget);
      expect(find.text(CallUiTr.remoteVideoLabel), findsOneWidget,
          reason: 'the small picture is the other side, and is named');

      await fixture.pumpWidget(
        tester,
        stageSample(focus: CallStageFocus.remote),
        onStyle: (AppearanceStyle _) {},
      );
      expect(
        find.byKey(CallStageKeys.focus(CallStageFocus.remote)),
        findsOneWidget,
      );
      expect(
        find.text(CallUiTr.remoteVideoLabel),
        findsWidgets,
        reason: 'the peer is on the main stage now',
      );
      await expectStageSound(tester);
    });

    testWidgets('the screen flips the subject when a remote camera arrives', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      expect(
        find.byKey(CallStageKeys.focus(CallStageFocus.local)),
        findsOneWidget,
        reason: 'before the peer publishes, the stage shows this device',
      );

      fixture.host.remoteCameraLive = true;
      fixture.host.sync();
      await tester.pump();

      expect(
        find.byKey(CallStageKeys.focus(CallStageFocus.remote)),
        findsOneWidget,
        reason:
            'this is the transition 0.1.x could not express: the source '
            'selection was pinned to `local-camera`, so a peer camera had '
            'nowhere to go',
      );
      expect(
        find.byKey(CallStageKeys.surface),
        findsOneWidget,
        reason: 'and the stage itself never left the screen',
      );
      await expectStageSound(tester);
    });
  });

  group('the stage survives the matrix', () {
    testWidgets('no overflow in any theme/accent combination at any window', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => stageSample(),
          matrix: mkviAppearanceMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });

    testWidgets('no overflow at both ends of the type slider', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => stageSample(),
          matrix: mkviScaleMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });

    testWidgets('no overflow with either accessibility switch on', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => stageSample(),
          matrix: mkviAccessibilityMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });
  });
}
