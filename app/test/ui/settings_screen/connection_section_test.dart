/// The connection section, and the refusal it shows instead of swallowing.
///
/// ## The claims
///
/// 1. **A refused endpoint is shown, in the layer's own Turkish sentence, and
///    nothing is stored.** `SettingsController.setEndpoint` returns false before
///    it writes; the section copies `endpointErrorTr` into the field and the
///    confirmation line does not appear. Four refusal shapes are tested —
///    blank, scheme-less, host-less and another scheme — because
///    `settings_messages.dart` has a different sentence for each and a form that
///    showed one of them for all four would be a form nobody could act on.
/// 2. **The field announces the refusal.** `MkviTextField` puts
///    `SemanticsValidationResult.invalid` on the field when `errorText` is set,
///    and the theme's `errorBorder`/`errorStyle` are the `danger` role: a red
///    edge nobody hears is a defect only for sighted keyboard users.
/// 3. **A valid endpoint is stored, with its ICE text, and the refusal is
///    cleared.** The store is read directly, not the controller's echo.
/// 4. **Typing clears a stale verdict**, because the sentence is about the value
///    that was refused and the value has changed.
///
/// ## On `http://`
///
/// `validateEndpoint` accepts `http` and `https` and refuses every other scheme;
/// its own message says so. These tests follow the layer rather than adding a
/// second rule: a form that refused something `setEndpoint` accepts would give
/// one question two answers, and the state layer is not this screen's to change.
library;

import 'dart:ui' show SemanticsValidationResult;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/settings_screen/settings_screen_ui.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';
import 'support/settings_fixtures.dart';
import 'support/settings_semantics.dart';

/// The [TextField] inside [ConnectionKeys.endpointField].
TextField endpointField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(ConnectionKeys.endpointField),
    matching: find.byType(TextField),
  ),
);

/// The [TextField] inside [ConnectionKeys.iceField].
TextField iceField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(ConnectionKeys.iceField),
    matching: find.byType(TextField),
  ),
);

/// The `validationResult` the field announces, read off the `Semantics` that
/// `MkviTextField` puts around the group — the node that carries
/// `validationResult`, not the field's own node.
SemanticsValidationResult? announcedResult(WidgetTester tester, Key field) =>
    validationResultAt(
      tester,
      find.descendant(
        of: find.byKey(field),
        matching: find.byKey(MkviFieldKeys.field),
      ),
    );

void main() {
  group('a refused endpoint', () {
    /// Types [raw], saves, and returns the Turkish sentence now on screen.
    Future<String?> refuse(
      WidgetTester tester,
      SettingsController controller,
      InMemorySettingsStore store,
      String raw,
    ) async {
      await pumpMkvi(
        tester,
        mkviSettingsSection(ConnectionSection(controller: controller)),
      );
      await tapInSection(
        tester,
        find.descendant(
          of: find.byKey(ConnectionKeys.endpointField),
          matching: find.byType(TextField),
        ),
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(ConnectionKeys.endpointField),
          matching: find.byType(TextField),
        ),
        raw,
      );
      await tester.pump();
      await tapInSection(
        tester,
        find.widgetWithText(FilledButton, controller.catalog.saveLabel),
      );
      return controller.endpointErrorTr;
    }

    testWidgets('a blank address is refused, nothing is stored, and the field '
        'says why', (WidgetTester tester) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);

      await refuse(tester, controller, store, '   ');

      expect(controller.endpointErrorTr, contains('boş olamaz'));
      expect(endpointField(tester).decoration!.errorText,
          controller.endpointErrorTr);
      expect(
        find.byKey(ConnectionKeys.notice),
        findsNothing,
        reason: 'a refused save is not a saved one, and it must not say it was',
      );
      expect(controller.settings.connection.hasEndpoint, isFalse);
      expect(
        store.read(SettingsKeys.endpoint),
        isNull,
        reason: 'measured on the store, not on the controller\'s echo',
      );
      expect(store.read(SettingsKeys.iceServers), isNull);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('a scheme-less address is refused, in the layer\'s own sentence', (
      WidgetTester tester,
    ) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);

      final String? shown = await refuse(
        tester,
        controller,
        store,
        'signal.example.workers.dev',
      );

      expect(shown, contains('tam bir adres'));
      expect(endpointField(tester).decoration!.errorText, shown);
      expect(store.read(SettingsKeys.endpoint), isNull);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('a host-less address is refused with the host sentence', (
      WidgetTester tester,
    ) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);

      final String? shown = await refuse(tester, controller, store, 'https://');

      expect(shown, contains('alan adı yok'));
      expect(store.read(SettingsKeys.endpoint), isNull);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('another scheme is refused, and the message names the two that '
        'are accepted', (WidgetTester tester) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);

      final String? shown = await refuse(
        tester,
        controller,
        store,
        'ftp://signal.example.dev',
      );

      expect(shown, contains('http://'));
      expect(store.read(SettingsKeys.endpoint), isNull);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('the refusal is visible and audible', () {
    testWidgets('the field announces invalid and the edge is the danger role', (
      WidgetTester tester,
    ) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(ConnectionSection(controller: controller)),
      );
      final AppearanceStyle style = mkviStyleOf(tester);

      // Before a refusal the field is not invalid.
      expect(
        endpointField(tester).decoration!.errorText,
        isNull,
        reason: 'a field that starts out invalid teaches users to ignore it',
      );
      expect(
        announcedResult(tester, ConnectionKeys.endpointField),
        SemanticsValidationResult.none,
      );

      await tapInSection(
        tester,
        find.descendant(
          of: find.byKey(ConnectionKeys.endpointField),
          matching: find.byType(TextField),
        ),
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(ConnectionKeys.endpointField),
          matching: find.byType(TextField),
        ),
        'signal.example.workers.dev',
      );
      await tester.pump();
      await tapInSection(
        tester,
        find.widgetWithText(FilledButton, controller.catalog.saveLabel),
      );

      expect(
        announcedResult(tester, ConnectionKeys.endpointField),
        SemanticsValidationResult.invalid,
        reason: 'a red edge nobody hears is a defect only for sighted users',
      );

      // The danger edge and the danger sentence come from the theme the
      // resolver built, so they are the token roles and not a colour written
      // into this test.
      final BuildContext fieldContext = tester.element(
        find.descendant(
          of: find.byKey(ConnectionKeys.endpointField),
          matching: find.byType(TextField),
        ),
      );
      final InputDecorationThemeData decoration = Theme.of(
        fieldContext,
      ).inputDecorationTheme;
      expect(
        decoration.errorBorder!.borderSide.color,
        style.role('danger'),
        reason: 'the edge of a refused field is the danger role',
      );
      expect(decoration.errorBorder!.borderSide.width, style.borderWidth);
      expect(decoration.errorStyle!.color, style.role('danger'));
      // And the edge has to be visible on the fill the field is painted with —
      // 3:1 is the token file's own floor for an edge, not the 4.5:1 of text.
      expect(
        style.contrast('danger', 'surfaceSoft'),
        greaterThanOrEqualTo(3),
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('typing clears a stale verdict, and the notice with it', (
      WidgetTester tester,
    ) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(ConnectionSection(controller: controller)),
      );
      final Finder input = find.descendant(
        of: find.byKey(ConnectionKeys.endpointField),
        matching: find.byType(TextField),
      );

      await tapInSection(tester, input);
      await tester.enterText(input, 'https://');
      await tester.pump();
      await tapInSection(
        tester,
        find.widgetWithText(FilledButton, controller.catalog.saveLabel),
      );
      expect(endpointField(tester).decoration!.errorText, isNotNull);

      await tester.enterText(input, 'https://signal.example.workers.dev');
      await tester.pump();
      expect(
        endpointField(tester).decoration!.errorText,
        isNull,
        reason: 'the sentence was about the value that was refused',
      );
      // The controller still holds its own last verdict; only the field stopped
      // showing a verdict that no longer describes what is in the box.
      expect(controller.endpointErrorTr, isNotNull);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('an accepted endpoint', () {
    testWidgets('is stored with its ICE text, and the refusal is cleared', (
      WidgetTester tester,
    ) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(ConnectionSection(controller: controller)),
      );
      final Finder input = find.descendant(
        of: find.byKey(ConnectionKeys.endpointField),
        matching: find.byType(TextField),
      );

      await tapInSection(tester, input);
      await tester.enterText(input, 'https://signal.example.workers.dev');
      await tester.enterText(
        find.descendant(
          of: find.byKey(ConnectionKeys.iceField),
          matching: find.byType(TextField),
        ),
        'stun:stun.example.dev:3478',
      );
      await tester.pump();
      await tapInSection(
        tester,
        find.widgetWithText(FilledButton, controller.catalog.saveLabel),
      );

      expect(controller.endpointErrorTr, isNull);
      expect(endpointField(tester).decoration!.errorText, isNull);
      expect(
        store.read(SettingsKeys.endpoint),
        'https://signal.example.workers.dev',
      );
      expect(store.read(SettingsKeys.iceServers), 'stun:stun.example.dev:3478');
      expect(
        controller.settings.connection.signalingEndpoint,
        Uri.parse('https://signal.example.workers.dev'),
      );
      expect(
        find.text(SettingsUiTr.connectionSaved.tr),
        findsOneWidget,
        reason: 'a save that says nothing is a save the user cannot confirm',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('a stored endpoint loads into the field, and the empty-state '
        'sentence goes away', (WidgetTester tester) async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SettingsKeys.endpoint: 'https://signal.example.workers.dev',
        SettingsKeys.iceServers: 'stun:stun.example.dev:3478',
      });
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);
      controller.load();
      await pumpMkvi(
        tester,
        mkviSettingsSection(ConnectionSection(controller: controller)),
      );

      expect(
        endpointField(tester).controller!.text,
        'https://signal.example.workers.dev',
      );
      expect(
        iceField(tester).controller!.text,
        'stun:stun.example.dev:3478',
      );
      expect(
        endpointField(tester).decoration!.helperText,
        isNull,
        reason: 'the empty-state sentence explains an empty field, and this one '
            'is not empty',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('an unconfigured install says what is missing, in Turkish', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(ConnectionSection(controller: controller)),
      );

      expect(
        endpointField(tester).decoration!.helperText,
        controller.catalog.endpointEmptyState,
        reason: 'MKVI ships no server, so "nothing configured" is the first-run '
            'state and it has to be explained, not left blank',
      );
      expect(find.text(controller.catalog.endpointHint), findsOneWidget);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });
}
