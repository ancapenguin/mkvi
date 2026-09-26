/// The control bar, and the two promises each of its five controls keeps.
///
/// | promise | 0.1.x | here |
/// |---|---|---|
/// | every control is at least `control.hitTargetMin` | the close control was a 34 px `button` | a [ConstrainedBox] of `style.hitTargetMin` on both sides, with the key **on that box** so the measurement is of the promise and not of the theme's 34 dp `controls.md` |
/// | every control has a Turkish name | an `IconButton` with no `tooltip`: 17 WCAG violations | the name is a `CallUiTr` constant carried by `CallControlLabels`, and it is a *value* so the negative control below can blank it |
///
/// The negative control is the part that matters. A suite that has only ever
/// seen good labels cannot tell "labelled" from "the test happened to pass", so
/// the same bar with one name blanked is asserted to go **red**, with a message
/// that names the role rather than the widget wrapper.
///
/// The last group is a measurement *about the harness*: the repository's
/// semantics-based floor is vacuous on this engine, and the proof is here rather
/// than in a comment. See `support/accessibility_floor.dart` for the table of
/// strategies that were tried.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/protocol/control_message.dart' show CallMode;
import 'package:mkvi/media/media.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/call/call.dart';

import '../../support/mkvi_test_app.dart';
import 'support/accessibility_floor.dart';
import 'support/call_screen_fixture.dart';

/// Every test in `test/ui/call` ends with this.
///
/// Three assertions: [expectNoOverflow] for the defect class 0.1.x shipped in
/// every screen, then both accessibility floors — the semantics one, which is
/// what the harness's `expectEveryControlLabelled` intends to be and is the
/// check the WCAG claim rests on, and the widget-tree one, which says the same
/// thing a different way and names the offending control.
///
/// The harness's own `expectEveryControlLabelled` is **not** called: it disposes
/// its `SemanticsHandle` in an `addTearDown` that runs after the framework's
/// end-of-test check, so every call to it fails on the handle instead of on the
/// claim. Both that and the second defect are measured, not assumed, in
/// `about the harness, measured not assumed` below and written up in
/// `support/accessibility_floor.dart`.
Future<void> expectControlsSound(WidgetTester tester) async {
  expectNoOverflow(tester);
  await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
  expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
}

/// Every control's key, so "each of the five" is a loop and not five lines that
/// can drift apart.
const List<Key> everyControlKey = <Key>[
  CallControlKeys.microphone,
  CallControlKeys.camera,
  CallControlKeys.screenShare,
  CallControlKeys.devices,
  CallControlKeys.hangUp,
];

/// A control bar on its own, with a record of which control was pressed.
Widget controlsSample({
  CallControlLabels labels = const CallControlLabels(),
  bool microphoneLive = true,
  bool microphoneMuted = false,
  bool cameraLive = true,
  bool screenShareAttached = false,
  bool allEnabled = true,
  void Function(String which)? onPressed,
}) {
  void record(String which) => onPressed?.call(which);
  return Padding(
    padding: const EdgeInsets.all(24),
    child: CallControls(
      labels: labels,
      microphoneLive: microphoneLive,
      microphoneMuted: microphoneMuted,
      cameraLive: cameraLive,
      screenShareAttached: screenShareAttached,
      microphoneEnabled: allEnabled,
      cameraEnabled: allEnabled,
      screenShareEnabled: allEnabled,
      onToggleMicrophone: () => record('microphone'),
      onToggleCamera: () => record('camera'),
      onToggleScreenShare: () => record('screenShare'),
      onOpenDevices: () => record('devices'),
      onHangUp: () => record('hangUp'),
    ),
  );
}

/// Every name the bar currently announces.
List<String> announcedNames(WidgetTester tester) => <String>[
  for (final ({String kind, String name}) reading in controlNames(tester))
    reading.name,
];

/// Every name in [candidate] appears in the bar's announcements.
bool announces(WidgetTester tester, String candidate) =>
    announcedNames(tester).any((String said) => said.contains(candidate));

void main() {
  group('every control is at least the token hit target', () {
    testWidgets('all five, on the short side, at the default appearance', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      late AppearanceStyle seen;
      await fixture.pumpWidget(
        tester,
        controlsSample(),
        onStyle: (AppearanceStyle style) => seen = style,
      );

      expect(everyControlKey, hasLength(5));
      for (final Key key in everyControlKey) {
        expect(find.byKey(key), findsOneWidget, reason: '$key is on screen');
        expectHitTarget(tester, find.byKey(key), style: seen);
      }
      expect(
        seen.hitTargetMin,
        44,
        reason:
            'design/tokens.json, never scaled — and the theme\'s own button '
            'height is 34, so a merely themed button would fail this',
      );
      expect(seen.control('md').height, lessThan(seen.hitTargetMin));
      await expectControlsSound(tester);
    });

    testWidgets('all five still are, at the largest type and density', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      late AppearanceStyle seen;
      await fixture.pumpWidget(
        tester,
        controlsSample(),
        settings: AppearanceSettings(
          fontScale: AppearanceSettings.maxFontScale,
          density: DensityPreference.values.last,
        ),
        onStyle: (AppearanceStyle style) => seen = style,
      );

      for (final Key key in everyControlKey) {
        expectHitTarget(tester, find.byKey(key), style: seen);
      }
      expect(seen.hitTargetMin, 44, reason: 'a physical promise, not a style');
      await expectControlsSound(tester);
    });
  });

  group('every control has a Turkish name', () {
    testWidgets('the five names are the catalogue\'s, and each is announced', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      await fixture.pumpWidget(
        tester,
        controlsSample(),
        onStyle: (AppearanceStyle _) {},
      );

      final List<({String kind, String name})> readings = controlNames(tester);
      expect(
        readings,
        hasLength(5),
        reason: 'one name per operable control: $readings',
      );
      for (final String expected in <String>[
        CallUiTr.microphoneMute,
        CallUiTr.cameraStop,
        CallUiTr.screenShareStart,
        CallUiTr.devicesOpen,
        CallUiTr.hangUp,
      ]) {
        expect(
          announces(tester, expected),
          isTrue,
          reason: '"$expected" is announced by nothing: ${announcedNames(tester)}',
        );
      }
      expect(
        CallUiTr.catalogue.values,
        everyElement(isNotEmpty),
        reason: 'no entry of the catalogue may be blank',
      );
      await expectControlsSound(tester);
    });

    testWidgets('the name follows the state, not the press', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);

      Future<void> showWith({
        bool cameraLive = true,
        bool microphoneMuted = false,
        bool screenShareAttached = false,
      }) async {
        await fixture.pumpWidget(
          tester,
          controlsSample(
            cameraLive: cameraLive,
            microphoneMuted: microphoneMuted,
            screenShareAttached: screenShareAttached,
          ),
          onStyle: (AppearanceStyle _) {},
        );
      }

      await showWith();
      expect(announces(tester, CallUiTr.cameraStop), isTrue);

      await showWith(cameraLive: false);
      expect(
        announces(tester, CallUiTr.cameraStart),
        isTrue,
        reason: 'the label answers "what happens if I press this"',
      );
      expect(announces(tester, CallUiTr.cameraStop), isFalse);

      await showWith(microphoneMuted: true);
      expect(announces(tester, CallUiTr.microphoneUnmute), isTrue);

      await showWith(screenShareAttached: true);
      expect(
        announces(tester, CallUiTr.screenShareStop),
        isTrue,
        reason:
            'a share that started and has not produced a frame is still running '
            '(upstream #2137), so the button must offer to stop it',
      );
      await expectControlsSound(tester);
    });

    testWidgets('the derived wordings are the catalogue\'s functions', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      final CallControlLabels labels = const CallControlLabels();

      expect(labels.microphone(muted: true), CallUiTr.microphoneAction(muted: true));
      expect(labels.microphone(muted: false), CallUiTr.microphoneMute);
      expect(labels.camera(live: true), CallUiTr.cameraAction(live: true));
      expect(labels.camera(live: false), CallUiTr.cameraStart);
      expect(
        labels.screenShare(attached: true),
        CallUiTr.screenShareAction(attached: true),
      );
      await fixture.pumpWidget(
        tester,
        controlsSample(),
        onStyle: (AppearanceStyle _) {},
      );
      await expectControlsSound(tester);
    });

    // The negative control. Without it, every other test in this file could pass
    // with the labels removed.
    testWidgets('NEGATIVE CONTROL: one blanked name is one red control', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      await fixture.pumpWidget(
        tester,
        controlsSample(labels: const CallControlLabels(cameraStop: '')),
        onStyle: (AppearanceStyle _) {},
      );

      var thrown = false;
      try {
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
      } on TestFailure catch (failure) {
        thrown = true;
        expect(
          failure.message,
          allOf(
            contains('these controls have nothing to read out'),
            contains('düğme'),
          ),
          reason:
              'the semantics tree itself reports the unnamed control, and the '
              'failure names the role rather than a widget wrapper',
        );
      }
      expect(
        thrown,
        isTrue,
        reason:
            'a control the user cannot hear is not a control; with one name '
            'blanked the bar must fail the floor',
      );
      // The widget floor agrees, and says exactly which control is at fault.
      expect(
        () => expectEveryControlIsNamed(tester),
        throwsA(isA<TestFailure>()),
      );
      expect(
        controlNames(tester).where((({String kind, String name}) r) => r.name.isEmpty),
        hasLength(1),
      );
      expectNoOverflow(tester);
    });
  });

  group('the camera button drives the media controller', () {
    testWidgets('pressing it changes cameraLive and the name with it', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      final MediaController media = fixture.media!.controller;
      expect(media.state.cameraLive, isTrue, reason: 'a video call starts live');
      expect(announces(tester, CallUiTr.cameraStop), isTrue);

      await tester.tap(find.byKey(CallControlKeys.camera));
      await tester.pumpAndSettle();

      expect(
        media.state.cameraLive,
        isFalse,
        reason:
            'disableCamera stops the track rather than muting it, so the camera '
            'light goes out — the state is the camera, not a flag',
      );
      expect(fixture.media!.orphanedTracks, isEmpty);
      expect(announces(tester, CallUiTr.cameraStart), isTrue);
      expect(announces(tester, CallUiTr.cameraStop), isFalse);

      await tester.tap(find.byKey(CallControlKeys.camera));
      await tester.pumpAndSettle();

      expect(media.state.cameraLive, isTrue, reason: 'and it comes back');
      expect(
        media.negotiationCount,
        1,
        reason:
            'turning a camera on mid-call is one `replaceTrack` and no offer, '
            'which is what makes the audio-to-video upgrade frameless',
      );
      expect(announces(tester, CallUiTr.cameraStop), isTrue);
      await expectControlsSound(tester);
    });

    testWidgets('the microphone button mutes without detaching the track', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      final MediaController media = fixture.media!.controller;
      expect(media.state.microphoneLive, isTrue);

      await tester.tap(find.byKey(CallControlKeys.microphone));
      await tester.pumpAndSettle();

      expect(
        media.state.microphoneLive,
        isTrue,
        reason:
            'a mute keeps the sender alive and sends silence; detaching would '
            'look to the peer like a broken track',
      );
      expect(fixture.host.snapshot.microphoneMuted, isTrue);
      expect(fixture.host.microphoneAudible, isFalse);
      expect(announces(tester, CallUiTr.microphoneUnmute), isTrue);
      await expectControlsSound(tester);
    });

    testWidgets('hanging up ends the call and the screen goes with it', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.connect(tester, CallMode.video);
      await fixture.pump(tester, onStyle: (CallUiHost _) {});

      await tester.tap(find.byKey(CallControlKeys.hangUp));
      await tester.pumpAndSettle();

      expect(fixture.call.machine.status.isLive, isFalse);
      expect(find.byKey(CallStageKeys.surface), findsNothing);
      expect(find.byKey(CallScreenKeys.empty), findsOneWidget);
      expect(
        fixture.host.operations,
        containsAllInOrder(<String>['frame:call-accept', 'media:publish']),
      );
      expect(fixture.host.operations, contains('media:release'));
      expect(
        fixture.media!.orphanedTracks,
        isEmpty,
        reason: 'the camera light is off when the call is over',
      );
      await expectControlsSound(tester);
    });
  });

  group('the hang-up button is not another button', () {
    testWidgets('it is a dangerFill with the on-fill text on it', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      late AppearanceStyle seen;
      await fixture.pumpWidget(
        tester,
        controlsSample(),
        onStyle: (AppearanceStyle style) => seen = style,
      );

      final FilledButton button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(CallControlKeys.hangUp),
          matching: find.byType(FilledButton),
        ),
      );
      final ButtonStyle style = button.style!;
      expect(
        style.backgroundColor!.resolve(<WidgetState>{}),
        seen.role('dangerFill'),
      );
      expect(
        style.foregroundColor!.resolve(<WidgetState>{}),
        seen.role('textOnAccent'),
        reason:
            'a `danger` label on a `dangerFill` measures 1.34:1 in the light '
            'theme; the declared pair is the on-fill one',
      );
      expect(
        seen.contrast('textOnAccent', 'dangerFill'),
        greaterThanOrEqualTo(4.5),
      );
      expect(seen.contrast('danger', 'dangerFill'), lessThan(4.5));
      await expectControlsSound(tester);
    });
  });

  group('about the harness, measured not assumed', () {
    testWidgets('the semantics floor reads the wrong owner, and that is '
        'asserted rather than assumed', (WidgetTester tester) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      await fixture.pumpWidget(
        tester,
        controlsSample(),
        onStyle: (AppearanceStyle _) {},
      );

      // The real floor, on the real tree: five controls, five Turkish names.
      await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
      final List<({String kind, String spoken})> named = await callControlLabels(
        tester,
      );
      expect(named, hasLength(5));
      for (final ({String kind, String spoken}) reading in named) {
        expect(
          reading.spoken,
          isNotEmpty,
          reason: 'a control the user cannot hear is not a control',
        );
      }

      // The owner the harness reads, and the one the tree is actually on.
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pump();
      await tester.pump();
      final SemanticsNode? harnessRoot = tester.binding.rootPipelineOwner
          .semanticsOwner
          ?.rootSemanticsNode;
      final SemanticsNode? realRoot = tester.binding.renderViews.first.owner
          ?.semanticsOwner
          ?.rootSemanticsNode;
      handle.dispose();

      expect(
        harnessRoot,
        isNull,
        reason:
            "this is the finding, and it is not a rounding error: "
            "`readControlLabels` reads `rootPipelineOwner.semanticsOwner"
            ".rootSemanticsNode`, which is null, so it walks an empty tree and "
            "`expectEveryControlLabelled` passes on a screen whose buttons are "
            "named nothing at all. The fix is one line in the harness — read "
            "`renderViews.first.owner` — and that file is the lead's.",
      );
      expect(
        realRoot,
        isNotNull,
        reason: 'the tree is right there on the per-view owner',
      );
      expectNoOverflow(tester);
    });
  });

  group('the control bar survives the matrix', () {
    testWidgets('no overflow in any theme/accent combination at any window', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => controlsSample(),
          matrix: mkviAppearanceMatrix(),
          size: window,
          each: (AppearanceSettings settings, CallUiHost _) {
            for (final Key key in everyControlKey) {
              expectHitTarget(tester, find.byKey(key));
            }
          },
        );
        expectNoOverflow(tester);
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
          (AppearanceSettings settings) => controlsSample(),
          matrix: mkviScaleMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
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
          (AppearanceSettings settings) => controlsSample(),
          matrix: mkviAccessibilityMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });

    testWidgets('a disabled control keeps its place and its name', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      late Rect live;
      await fixture.pumpWidget(
        tester,
        controlsSample(),
        onStyle: (AppearanceStyle _) {},
      );
      live = tester.getRect(find.byKey(CallControlKeys.camera));

      await fixture.pumpWidget(
        tester,
        controlsSample(allEnabled: false),
        onStyle: (AppearanceStyle _) {},
      );

      expect(
        tester.getRect(find.byKey(CallControlKeys.camera)),
        live,
        reason: 'a control the user cannot change is disabled, not removed',
      );
      final IconButton button = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(CallControlKeys.camera),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
      // A disabled control is still announced by Flutter, so it is still named.
      expect(announces(tester, CallUiTr.cameraStop), isTrue);
      await expectControlsSound(tester);
    });
  });
}
