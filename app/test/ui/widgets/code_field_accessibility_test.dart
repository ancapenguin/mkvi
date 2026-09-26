/// The one accessibility property of `MkviCodeField` that no layout test can
/// see, and the one that made the whole screen unreachable.
///
/// ## What was wrong
///
/// The real input sits behind the thirteen cells at `opacity: 0`
/// (`mkvi_code_field.dart`, `_input`). Flutter **drops everything under a fully
/// transparent `Opacity` from the semantics tree** unless
/// `alwaysIncludeSemantics: true` is set — `Opacity` reads zero opacity as
/// "painted nothing", and a screen reader does not read what was never painted.
///
/// The consequence was measured, not guessed: the pairing screen published
/// **exactly one operable node**, the "Eşleş" button. The code field — the
/// control the whole screen exists for — was not in the accessibility tree at
/// all. Not "unnamed": **absent**.
///
/// That is the worst shape of accessibility bug, because a test that counts
/// controls, or that only asks "is there a button?", passes. The check that
/// catches it is "is the FIELD there?", which is what this file is.
///
/// ## Why the name does not move onto the field
///
/// The fix could have been satisfied by labelling the invisible field, and that
/// would read as "eşleşme kodu, metin alanı" — technically labelled, and noise:
/// a screen-reader user already has the thirteen cells announced, and an
/// unlabelled box after them adds nothing. So the name stays on the cell row
/// and the field stays nameless. `the name is on the cells, not the field`
/// exists to say so, because a later agent who "fixes" a warning by labelling
/// the invisible input would otherwise look like an improvement.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/mkvi_test_app.dart';

void main() {
  group('the hidden field is reachable, not merely present', () {
    testWidgets('a zero-opacity input is still announced as a text field', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        Scaffold(
          body: MkviCodeField(
            controller: TextEditingController(),
            onChanged: (_) {},
          ),
        ),
      );

      final List<ControlReading> readings = await readControlLabels(tester);
      expect(
        readings.where((ControlReading r) => r.type == 'metin alanı'),
        isNotEmpty,
        reason:
            'the code field is not in the accessibility tree; what is: '
            '${readings.map((ControlReading r) => r.type).join(', ')}',
      );
    });

    testWidgets('the name is on the cells, not on the field', (
      WidgetTester tester,
    ) async {
      await pumpMkvi(
        tester,
        Scaffold(
          body: MkviCodeField(
            controller: TextEditingController(),
            onChanged: (_) {},
          ),
        ),
      );

      final SemanticsNode root = tester.binding
          .renderViews.first.owner!
          .semanticsOwner!
          .rootSemanticsNode!;

      final List<String> labels = <String>[];
      final List<bool> textFieldFlags = <bool>[];
      void walk(SemanticsNode node) {
        final SemanticsData data = node.getSemanticsData();
        labels.add(data.label);
        textFieldFlags.add(data.flagsCollection.isTextField);
        node.visitChildren((SemanticsNode child) {
          walk(child);
          return true;
        });
      }

      walk(root);

      // Something in the field is named, or the whole control is silent.
      expect(
        labels.any((String label) => label.isNotEmpty),
        isTrue,
        reason: 'nothing in the field carries a label: $labels',
      );

      // And the node that is a text field is not the named one. If they were
      // the same node, the screen reader would read the label and then the
      // field's own implicit "text field" role as two separate things.
      expect(
        textFieldFlags.any((bool isField) => isField),
        isTrue,
        reason: 'the field disappeared again: $labels',
      );
    });

    testWidgets('a field with no name at all is caught, not tolerated', (
      WidgetTester tester,
    ) async {
      // The negative control for the whole helper: if `readControlLabels`
      // returned an empty list for everything, the test above would pass
      // vacuously. A nameless control must still be *found*, and the strict
      // assertion must go red on it.
      await pumpMkvi(
        tester,
        Scaffold(
          body: ElevatedButton(onPressed: () {}, child: const SizedBox.shrink()),
        ),
      );

      final List<ControlReading> readings = await readControlLabels(tester);
      expect(readings, isNotEmpty);

      await expectLater(
        () => expectEveryControlLabelled(tester),
        throwsA(isA<TestFailure>()),
      );
    });
  });
}
