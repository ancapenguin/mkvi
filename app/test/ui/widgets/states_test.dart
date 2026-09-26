/// The states, and the two promises they make that nothing else in the app
/// makes: an empty state has to say *what* is empty, and a failure has to say
/// *why*.
///
/// The second one is the `ROADMAP.md` Faz 4 item that is still open — "Keyring
/// hataları yüzeye çıkar, sessizce yeni kimleme düşmez" — and the half of it
/// that belongs to a widget rather than to the session controller. The
/// controller's half is [SetupState.broken]; this file's half is that
/// [MkviErrorState] has no constructor that can be built without a reason, and
/// no way to render one that is shortened.
///
/// The test at the bottom of the first group is the composition, with the real
/// session state and no hand-written copy: every [PeerReadFailure] the app can
/// reach has a Turkish `message` and a Turkish `recovery`, and both of them reach
/// the block. That is the assertion a user would make if they had been in the
/// 0.1.x pairing screen: "tell me what happened, then tell me what I can do".
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/session/session.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/widget_samples.dart';

/// The five surfaces the token file declares `text` and `textMuted` against.
const List<String> everySurfaceRole = <String>[
  'bg',
  'surface',
  'surfaceRaised',
  'surfaceSoft',
  'surfaceOverlay',
];

/// A reason long enough that any sane widget would want to shorten it: a Windows
/// path with a corrupted record's diagnostic behind it.
const String longReason =
    'Kayıtlı eş kaydı açılamadı: C:\\Users\\ilber\\AppData\\Roaming\\MKVI\\'
    'peers\\9f2c41ab77de0359c1e5a4b60d8f3172e4a9b6c05.json dosyasındaki '
    'şema sürümü 3, bu sürümün okuduğu sürüm 5; kayıt silinmeden önce '
    'dosyanın bir yedeği alınmalı.';

void main() {
  group('an empty state says what is empty, in two measured roles', () {
    testWidgets('the headline is text at lg and the sentence is textMuted at sm', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          MkviEmptyState(
            title: SampleTr.emptyTitle,
            description: SampleTr.emptyDescription,
            icon: Icons.search_off_rounded,
            actions: <MkviPanelAction>[
              MkviPanelAction(
                label: SampleTr.secondaryAction,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Text title = tester.widget<Text>(
        find.text(SampleTr.emptyTitle),
      );
      final Text description = tester.widget<Text>(
        find.text(SampleTr.emptyDescription),
      );

      expect(title.style?.color, style.role('text'));
      expect(title.style?.fontSize, style.typeStep('lg').size);
      expect(description.style?.color, style.role('textMuted'));
      expect(description.style?.fontSize, style.typeStep('sm').size);

      // Both pairs are the token file's, on every surface this block can stand
      // on — not just on the one the default theme happens to have.
      for (final String role in everySurfaceRole) {
        expectTokenContrast(style, 'text', role, minimum: 7);
        expectTokenContrast(style, 'textMuted', role, minimum: 4.5);
      }
    });

    testWidgets('the glyph sits in a well that is on the same centre line as the headline', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviEmptyState(
            title: SampleTr.emptyTitle,
            icon: Icons.search_off_rounded,
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Rect well = tester.getRect(find.byKey(MkviStateKeys.emptyGlyph));
      final Rect title = tester.getRect(find.text(SampleTr.emptyTitle));

      expect(
        well.center.dx,
        closeTo(title.center.dx, 0.01),
        reason: 'the block is centred, not left-aligned with a stray icon',
      );
      expect(
        well.height,
        closeTo(style.control('lg').height, 0.01),
        reason: 'and the well is an lg control square, not a guess',
      );
      final Container container = tester.widget<Container>(
        find.byKey(MkviStateKeys.emptyGlyph),
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, style.role('surfaceSoft'));
      expect(decoration.shape, BoxShape.circle);
      final Icon icon = tester.widget<Icon>(find.byIcon(Icons.search_off_rounded));
      expect(icon.size, style.control('lg').iconSize);
      expect(icon.color, style.role('textMuted'));
      expectTokenContrast(style, 'textMuted', 'surfaceSoft', minimum: 4.5);
    });

    testWidgets('a state with no glyph, no sentence and no action is just the headline', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(const MkviEmptyState(title: SampleTr.emptyTitle)),
      );

      expect(find.byKey(MkviStateKeys.emptyGlyph), findsNothing);
      expect(find.text(SampleTr.emptyDescription), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(
        tester.getSize(find.byType(MkviEmptyState)).height,
        closeTo(tester.getSize(find.text(SampleTr.emptyTitle)).height, 0.01),
        reason: 'no empty state, no gap: nothing else took vertical space',
      );
    });
  });

  group('an error block shows the reason, and shows all of it', () {
    testWidgets('the block is a dangerFill surface with a danger edge', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviErrorState(
            title: SampleTr.errorTitle,
            reason: SampleTr.errorReason,
            message: SampleTr.errorMessage,
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final DecoratedBox surface = tester.widget<DecoratedBox>(
        find.byKey(MkviStateKeys.errorSurface),
      );
      final BoxDecoration decoration = surface.decoration as BoxDecoration;

      expect(decoration.color, style.role('dangerFill'));
      expect(
        (decoration.border! as Border).top.color,
        style.role('danger'),
      );
      expect(
        (decoration.border! as Border).top.width,
        style.borderWidth,
      );
      expect(decoration.borderRadius, style.shape('lg').borderRadius);
      expectTokenContrast(
        style,
        'textOnAccent',
        MkviErrorState.surfaceRole,
        minimum: 4.5,
      );
    });

    testWidgets('every string in the block is the one colour declared on dangerFill', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviErrorState(
            title: SampleTr.errorTitle,
            reason: SampleTr.errorReason,
            message: SampleTr.errorMessage,
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Iterable<Text> texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(MkviStateKeys.errorSurface),
          matching: find.byType(Text),
        ),
      );
      expect(texts.length, 3, reason: 'a headline, a reason and a recovery');
      for (final Text text in texts) {
        expect(
          text.style?.color,
          style.role('textOnAccent'),
          reason:
              'a second, dimmer colour on dangerFill is not a pair the token '
              'file declares, and an undeclared pair is how 0.1.x measured '
              '4.47:1',
        );
      }
    });

    testWidgets('a 300 character reason reaches the tree whole and wraps', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviErrorState(reason: longReason, message: SampleTr.errorMessage),
        ),
      );

      // Whole: the widget holds the exact string, and there is exactly one of
      // it, so nothing shortened it on the way in.
      expect(find.text(longReason), findsOneWidget);
      final Text reason = tester.widget<Text>(
        find.byKey(MkviStateKeys.reason),
      );
      expect(reason.data, longReason);
      expect(
        reason.maxLines,
        isNull,
        reason: 'no cap: a diagnostic that is cut off is a diagnostic support '
            'gets asked about again',
      );
      expect(
        reason.overflow,
        isNot(TextOverflow.ellipsis),
        reason: 'and no ellipsis standing in for the text that is missing',
      );

      // Wrapped, not clipped: the reason is at least three lines tall and the
      // block grew to hold it.
      final double reasonHeight = tester
          .getSize(find.byKey(MkviStateKeys.reason))
          .height;
      final double messageHeight = tester
          .getSize(find.byKey(MkviStateKeys.message))
          .height;
      expect(
        reasonHeight,
        greaterThan(messageHeight * 3),
        reason: '300 characters in a 300 dp column cannot be one line',
      );
      expect(
        tester.getSize(find.byKey(MkviStateKeys.errorSurface)).height,
        greaterThan(reasonHeight),
        reason: 'and the block is taller than the reason inside it',
      );
    });

    testWidgets('with no headline the reason takes the headline step', (
      WidgetTester tester,
    ) async {
      late AppearanceStyle style;

      await pumpMkvi(
        tester,
        MkviStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: mkviSample(
            const MkviErrorState(
              reason: longReason,
              message: SampleTr.errorMessage,
            ),
          ),
        ),
      );
      final Text reason = tester.widget<Text>(
        find.byKey(MkviStateKeys.reason),
      );
      expect(reason.style?.fontSize, style.typeStep('lg').size);

      await pumpMkvi(
        tester,
        MkviStyleProbe(
          onStyle: (AppearanceStyle value) => style = value,
          child: mkviSample(
            const MkviErrorState(
              title: SampleTr.errorTitle,
              reason: longReason,
              message: SampleTr.errorMessage,
            ),
          ),
        ),
      );
      final Text withTitle = tester.widget<Text>(
        find.byKey(MkviStateKeys.reason),
      );
      expect(
        withTitle.style?.fontSize,
        style.typeStep('md').size,
        reason: 'under a headline the reason steps down one notch',
      );
    });

    testWidgets('every failure the session can report reaches the user, in Turkish', (
      WidgetTester tester,
    ) async {
      const List<PeerReadFailure> failures = <PeerReadFailure>[
        PeerStoreUnavailable(),
        PeerDecryptFailed(),
        PeerKeyringEntryMissing(),
        PeerRecordCorrupt(),
      ];

      for (final PeerReadFailure failure in failures) {
        // The state that carries it is the one that must not fall through to
        // the pairing screen: that was the white screen.
        const SetupState state = SetupState.broken(PeerKeyringEntryMissing());
        expect(state.showsPairingScreen, isFalse);
        expect(state.canRetry, isTrue);
        expect(state.offersPairNewDevice, isTrue);

        await pumpMkvi(
          tester,
          mkviSample(
            MkviErrorState(
              reason: failure.message,
              message: failure.recovery,
              actions: <MkviPanelAction>[
                MkviPanelAction(
                  label: SampleTr.primaryAction,
                  onPressed: () {},
                  filled: true,
                ),
                MkviPanelAction(
                  label: SampleTr.secondaryAction,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        );

        expect(
          find.text(failure.message),
          findsOneWidget,
          reason: '${failure.runtimeType}: the reason reaches the screen',
        );
        expect(
          find.text(failure.recovery),
          findsOneWidget,
          reason: '${failure.runtimeType}: and so does what to do about it',
        );
        expect(
          failure.message,
          isNot(failure.recovery),
          reason: 'a reason that is also the recovery tells the user nothing',
        );
        expectNoOverflow(tester);
      }
    });

    testWidgets('a filled action on the danger surface takes the strong edge', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviErrorState(
            reason: SampleTr.errorReason,
            message: SampleTr.errorMessage,
            actions: <MkviPanelAction>[
              MkviPanelAction(
                label: SampleTr.primaryAction,
                onPressed: _noop,
                filled: true,
              ),
            ],
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, SampleTr.primaryAction),
      );
      final ButtonStyle effective = (Theme.of(
            tester.element(
              find.widgetWithText(FilledButton, SampleTr.primaryAction),
            ),
          ).filledButtonTheme.style ??
              const ButtonStyle())
          .merge(button.style ?? const ButtonStyle());
      final BorderSide side = effective.side!.resolve(<WidgetState>{})!;
      expect(
        side.color,
        style.role('borderStrong'),
        reason: 'dangerFill is not the page, so the rule applies here too',
      );
    });
  });

  group('a section header and a key/value row are the pair a settings page is made of', () {
    testWidgets('the heading is text and the description is textMuted, on all five surfaces', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, mkviSample(mkviSectionSample()));

      final AppearanceStyle style = mkviStyleOf(tester);
      final Text title = tester.widget<Text>(
        find.text(SampleTr.sectionTitle),
      );
      final Text description = tester.widget<Text>(
        find.text(SampleTr.sectionDescription),
      );
      expect(title.style?.color, style.role('text'));
      expect(description.style?.color, style.role('textMuted'));
      for (final String role in everySurfaceRole) {
        expectTokenContrast(style, 'text', role, minimum: 7);
        expectTokenContrast(style, 'textMuted', role, minimum: 4.5);
      }
    });

    testWidgets('the action and the trailing widget are both in the strip', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(tester, mkviSample(mkviSectionSample()));

      final Rect header = tester.getRect(find.byKey(MkviSectionKeys.header));
      final Rect button = tester.getRect(
        find.widgetWithText(FilledButton, SampleTr.primaryAction),
      );
      final Rect badge = tester.getRect(find.byType(MkviBadge));

      expect(header.contains(button.topLeft), isTrue);
      expect(header.contains(button.bottomRight), isTrue);
      expect(header.contains(badge.topLeft), isTrue);
      expect(
        badge.center.dx,
        greaterThan(button.center.dx),
        reason: 'the trailing widget is after the actions, not before them',
      );
    });

    testWidgets('a key/value row is muted on the left, text on the right, value trailing', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviKeyValueRow(
            label: SampleTr.keyLabel,
            value: SampleTr.keyValue2,
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Text label = tester.widget<Text>(find.byKey(MkviSectionKeys.label));
      final Text value = tester.widget<Text>(find.byKey(MkviSectionKeys.value));

      expect(label.style?.color, style.role('textMuted'));
      expect(value.style?.color, style.role('text'));
      expect(
        value.textAlign,
        TextAlign.end,
        reason: 'a value column reads as a column only if it is aligned',
      );
      expect(
        tester.getRect(find.byKey(MkviSectionKeys.value)).right,
        closeTo(
          tester.getRect(find.byType(MkviKeyValueRow)).right,
          0.01,
        ),
        reason: 'and the right edge of the value IS the right edge of the row',
      );
      expectTokenContrast(style, 'textMuted', 'surfaceRaised', minimum: 4.5);
    });

    testWidgets('a 40 character fingerprint wraps instead of overflowing its row', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviKeyValueRow(
            label: SampleTr.keyLabel,
            value: SampleTr.keyValue,
          ),
        ),
      );

      final Text value = tester.widget<Text>(find.byKey(MkviSectionKeys.value));
      expect(value.data, SampleTr.keyValue);
      expect(value.maxLines, isNull);
      expect(value.overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester.getRect(find.byKey(MkviSectionKeys.value)).right,
        // A wrapped value still ends at the row's edge.
        closeTo(tester.getRect(find.byType(MkviKeyValueRow)).right, 0.01),
      );
    });

    testWidgets('the dense row is two type steps smaller and keeps the same two colours', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        mkviSample(
          const MkviKeyValueRow(
            label: SampleTr.keyLabel,
            value: SampleTr.keyValue2,
            dense: true,
          ),
        ),
      );

      final AppearanceStyle style = mkviStyleOf(tester);
      final Text label = tester.widget<Text>(find.byKey(MkviSectionKeys.label));
      final Text value = tester.widget<Text>(find.byKey(MkviSectionKeys.value));
      expect(label.style?.fontSize, style.typeStep('2xs').size);
      expect(value.style?.fontSize, style.typeStep('xs').size);
      expect(label.style?.color, style.role('textMuted'));
      expect(value.style?.color, style.role('text'));
    });
  });

  group('every state survives the whole matrix', () {
    testWidgets('no state overflows in any of the 16 theme/accent pairs or the 6 scale/density pairs', (
      WidgetTester tester,
    ) async {
      final List<AppearanceSettings> matrix = <AppearanceSettings>[
        ...mkviAppearanceMatrix(),
        ...mkviScaleMatrix(),
      ];
      for (final AppearanceSettings settings in matrix) {
        for (final Widget sample in <Widget>[
          mkviStateSample(),
          mkviSectionSample(),
          mkviKeyValueSample(),
        ]) {
          await pumpMkvi(tester, mkviSample(sample), settings: settings);
          expectNoOverflow(tester);
        }
      }
    });

    testWidgets('the error block keeps its contrast at the largest type and the smallest density', (
      WidgetTester tester,
    ) async {
      for (final AppearanceSettings settings in <AppearanceSettings>[
        AppearanceSettings(
          fontScale: AppearanceSettings.maxFontScale,
          density: DensityPreference.compact,
          highContrast: true,
        ),
        AppearanceSettings(
          fontScale: AppearanceSettings.minFontScale,
          theme: ThemePreference.light,
        ),
      ]) {
        late AppearanceStyle style;
        await pumpMkvi(
          tester,
          MkviStyleProbe(
            onStyle: (AppearanceStyle value) => style = value,
            child: mkviSample(
              const MkviErrorState(
                title: SampleTr.errorTitle,
                reason: longReason,
                message: SampleTr.errorMessage,
              ),
            ),
          ),
          settings: settings,
        );
        expectTokenContrast(
          style,
          'textOnAccent',
          MkviErrorState.surfaceRole,
          minimum: 4.5,
        );
        expect(
          find.text(longReason),
          findsOneWidget,
          reason: 'high contrast changes the ramps, never the string',
        );
        expectNoOverflow(tester);
      }
    });
  });
}

/// A callback for a sample action, so a sample stays `const`.
void _noop() {}
