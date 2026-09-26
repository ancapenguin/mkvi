/// The identity section: the name the other device sees.
///
/// ## The claims
///
/// 1. **A save is stored, sanitised, and reported.** The name that reaches the
///    store is the one `sanitisedSelfName` produced — the wire's own function —
///    and the confirmation line says so in Turkish, so a save is never silent.
/// 2. **The field does not enforce the wire's 40-character cap.**
///    `MaxLengthEnforcement.enforced` is the default, so a `maxLength` here would
///    *refuse* input the layer would have accepted and truncated, and the counter
///    would promise "40/40" for a value the wire still cuts. The screen is
///    asserted to leave the cap to the layer, and the reason is written down
///    where the next agent will read it.
/// 3. **The error shape is the connection's shape.** `selfNameErrorTr` is always
///    null today — a name is sanitised rather than refused — and the field shows
///    it anyway, so the form does not change shape when a future rule starts
///    refusing something. The test asserts the *absence* explicitly rather than
///    leaving it unmeasured.
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

/// The [TextField] inside [IdentityKeys.field].
TextField nameField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(IdentityKeys.field),
    matching: find.byType(TextField),
  ),
);

/// A name that has to be sanitised: control characters, zero-width marks and
/// doubled spaces, which is what the wire's function exists for.
String messyName() =>
    '  Ayşe${String.fromCharCode(0x200b)}   Gül${String.fromCharCode(0x0007)}  ';

void main() {
  group('the field', () {
    testWidgets('starts from the stored name and is named by the catalogue', (
      WidgetTester tester,
    ) async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SettingsKeys.selfName: 'Ayşe Gül',
      });
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);
      controller.load();
      await pumpMkvi(
        tester,
        mkviSettingsSection(IdentitySection(controller: controller)),
      );
      final SettingsCatalog catalog = controller.catalog;

      expect(nameField(tester).controller!.text, 'Ayşe Gül');
      expect(
        nameField(tester).decoration!.labelText,
        catalog.selfNameLabel,
        reason: 'the label is the catalogue\'s, not a second copy of the word',
      );
      expect(nameField(tester).decoration!.hintText, catalog.selfNameHint);
      expect(find.text(SettingsUiTr.identitySection.tr), findsOneWidget);
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('leaves the wire\'s 40-character cap to the layer', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(IdentitySection(controller: controller)),
      );

      expect(
        nameField(tester).maxLength,
        isNull,
        reason: 'a cap here would refuse input the sanitiser accepts and '
            'truncates, and the counter would promise a length the wire does '
            'not use — the cap is the wire\'s and it belongs to the layer that '
            'applies it',
      );
      expect(
        sanitisedSelfName('A' * 60).length,
        40,
        reason: 'and the layer does apply it, so nothing is lost by leaving it '
            'there: the cap is the wire\'s own, reached through '
            '`sanitisedSelfName`',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('has no error until one is refused, and then it would show it', (
      WidgetTester tester,
    ) async {
      final SettingsController controller = mkviSettingsController();
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(IdentitySection(controller: controller)),
      );

      // `selfNameErrorTr` is always null today: a name is sanitised rather than
      // refused. Asserted rather than left unmeasured, because "there is no
      // error" is a claim about the layer and not about this screen.
      expect(controller.selfNameErrorTr, isNull);
      expect(nameField(tester).decoration!.errorText, isNull);
      expect(
        validationResultAt(
          tester,
          find.descendant(
            of: find.byKey(IdentityKeys.field),
            matching: find.byKey(MkviFieldKeys.field),
          ),
        ),
        SemanticsValidationResult.none,
        reason: 'a field that starts out invalid teaches users to ignore it',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });

  group('a save', () {
    testWidgets('stores the sanitised name, says so, and shows what it stored', (
      WidgetTester tester,
    ) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(IdentitySection(controller: controller)),
      );
      final Finder input = find.descendant(
        of: find.byKey(IdentityKeys.field),
        matching: find.byType(TextField),
      );

      await tapInSection(tester, input);
      await tester.enterText(input, messyName());
      await tester.pump();
      await tapInSection(
        tester,
        find.widgetWithText(FilledButton, SettingsUiTr.identitySaveLabel.tr),
      );

      expect(controller.settings.selfName, 'Ayşe Gül');
      expect(
        store.read(SettingsKeys.selfName),
        'Ayşe Gül',
        reason: 'the value on disk is the one the wire will send, not what was '
            'typed',
      );
      expect(controller.selfNameErrorTr, isNull);
      expect(
        find.text(SettingsUiTr.selfNameSaved.tr),
        findsOneWidget,
        reason: 'a save that says nothing cannot be confirmed',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('an empty name is stored as an empty name, not as a leftover', (
      WidgetTester tester,
    ) async {
      final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
        SettingsKeys.selfName: 'Ayşe Gül',
      });
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);
      controller.load();
      await pumpMkvi(
        tester,
        mkviSettingsSection(IdentitySection(controller: controller)),
      );
      final Finder input = find.descendant(
        of: find.byKey(IdentityKeys.field),
        matching: find.byType(TextField),
      );

      await tapInSection(tester, input);
      await tester.enterText(input, '');
      await tester.pump();
      await tapInSection(
        tester,
        find.widgetWithText(FilledButton, SettingsUiTr.identitySaveLabel.tr),
      );

      expect(controller.settings.selfName, '');
      expect(store.read(SettingsKeys.selfName), '');
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });

    testWidgets('the keyboard\'s done key saves, and typing clears the '
        'confirmation', (WidgetTester tester) async {
      final InMemorySettingsStore store = InMemorySettingsStore();
      final SettingsController controller = mkviSettingsController(store: store);
      addTearDown(controller.dispose);
      await pumpMkvi(
        tester,
        mkviSettingsSection(IdentitySection(controller: controller)),
      );
      final Finder input = find.descendant(
        of: find.byKey(IdentityKeys.field),
        matching: find.byType(TextField),
      );

      await tapInSection(tester, input);
      await tester.enterText(input, 'Ayşe Gül');
      await tester.pump();
      expect(find.byKey(IdentityKeys.notice), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(store.read(SettingsKeys.selfName), 'Ayşe Gül');
      expect(find.byKey(IdentityKeys.notice), findsOneWidget);

      await tester.enterText(input, 'Ayşe');
      await tester.pump();
      expect(
        find.byKey(IdentityKeys.notice),
        findsNothing,
        reason: 'a confirmation about a value that has since changed is a lie',
      );
      expectNoOverflow(tester);
      await expectEveryControlIsLabelled(tester);
    });
  });
}
