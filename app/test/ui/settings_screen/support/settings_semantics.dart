/// The accessibility floor, measured — and why this file exists at all.
///
/// ## Three defects in the shared helper, all in files this layer does not own
///
/// 1. **`readControlLabels` leaks its `SemanticsHandle`.** It creates the handle
///    and disposes it from `addTearDown`:
///
///    ```dart
///    final SemanticsHandle handle = tester.ensureSemantics();
///    addTearDown(handle.dispose);
///    ```
///
///    `addTearDown` callbacks run **after**
///    `WidgetTester._endOfTestVerifications`, and that verification throws
///    *"A SemanticsHandle was active at the end of the test."* So every test
///    that calls `readControlLabels` — and therefore every test that calls
///    `expectEveryControlLabelled` — is red before it looks at a widget. The fix
///    is one line: dispose the handle in the function body.
///
/// 2. **The semantics root is read from the wrong owner.** The helper reads
///    `binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode`. On this SDK
///    each view owns its own render tree, `rootPipelineOwner.rootNode` is null,
///    and the walk therefore starts from an *empty* tree: every control in the
///    app is reported absent, which is the one false negative an accessibility
///    assertion must not have. The root lives on the view's own owner —
///    `tester.binding.renderViews.first.owner!.semanticsOwner!` — which is what
///    `flutter_test`'s own `SemanticsFinder` and `meetsGuideline` use, and why
///    `pipelineOwner` is deprecated.
///
/// 3. **`expectEveryControlLabelled` cannot fail.** `_spokenFor` substitutes
///    `"(kaydırıcı — etiketsiz)"` for a control with no label, so `spoken` is
///    never empty, so `where((r) => r.spoken.isNotEmpty) return false` filters
///    every control out. A floor that cannot be tripped is not a floor. This file
///    reports `named` separately and asserts on **that**.
///
/// A fourth is a false *positive*, and it is the reason this walk is not a copy:
///
/// 4. **A control inside a control is reported as a second control.** The
///    helper walks an operable node's children first and adds a reading for each,
///    so the `Radio` inside a named `MkviOptionRow`, and the `Switch` inside a
///    named `SwitchListTile`, are each reported as a nameless control of their
///    own. Its own comment says *"keep the outermost operable node on each
///    branch … do not report a control inside a control"*; this walk is that.
///
/// When `test/support/mkvi_test_app.dart` is fixed, delete this file and call
/// `expectEveryControlLabelled` instead — nothing else in this directory
/// changes.
///
/// ## What the claim is
///
/// `ROADMAP.md` sets the floor after 0.1.x shipped 17 WCAG violations: a control
/// the user cannot hear is not a control. So the walk reports, for every
/// **outermost** operable node, everything a screen reader would read out for it
/// (its own label, hint and tooltip plus its whole subtree's), and the assertion
/// fails on a control whose subtree says nothing at all.
library;

import 'dart:ui' show CheckedState, SemanticsValidationResult;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `validationResult` the semantics node at [finder] announces.
///
/// The one measurement that distinguishes "the field is outlined in red" from
/// "the field is announced as invalid": a sighted user sees the first and a
/// screen-reader user needs the second, and only one of them is a defect the
/// other never notices.
///
/// The handle is disposed here for the same reason [readSettingsControlLabels]
/// disposes its own.
SemanticsValidationResult? validationResultAt(
  WidgetTester tester,
  Finder finder,
) {
  final SemanticsHandle handle = tester.ensureSemantics();
  try {
    return tester.getSemantics(finder).getSemanticsData().validationResult;
  } finally {
    handle.dispose();
  }
}

/// One outermost operable control, with what a screen reader would read out for
/// it and whether it had anything to read.
typedef SettingsControlReading = ({
  String type,
  String spoken,
  bool named,
});

/// Every outermost operable control in the pumped tree.
///
/// Walks the **semantics** tree, not the widget tree, and reads a name from the
/// node *and its whole subtree*: a `TextField` with a `labelText` carries an
/// empty label itself and a labelled child, and so does a radio sitting inside
/// the option row that carries the row's name.
Future<List<SettingsControlReading>> readSettingsControlLabels(
  WidgetTester tester,
) async {
  final SemanticsHandle handle = tester.ensureSemantics();
  try {
    // Two pumps, not one: `ensureSemantics` marks the tree dirty, the first pump
    // produces the nodes and the second paints them. One pump reads an empty
    // tree and calls every control in the app absent.
    await tester.pump();
    await tester.pump();

    // The view's own `PipelineOwner`, not `binding.rootPipelineOwner` — see the
    // note at the top of this file.
    final SemanticsNode? root = tester.binding.renderViews.first.owner
        ?.semanticsOwner
        ?.rootSemanticsNode;
    if (root == null) return const <SettingsControlReading>[];

    final List<SettingsControlReading> readings = <SettingsControlReading>[];
    final Set<SemanticsNode> visited = <SemanticsNode>{};

    void take(SemanticsData from, List<String> into) {
      for (final String value in <String>[
        from.label,
        from.hint,
        from.tooltip,
      ]) {
        if (value.isNotEmpty && !into.contains(value)) into.add(value);
      }
    }

    void collect(SemanticsNode node, List<String> into) {
      take(node.getSemanticsData(), into);
      node.visitChildren((SemanticsNode child) {
        if (visited.add(child)) collect(child, into);
        return true;
      });
    }

    void walk(SemanticsNode node) {
      if (!visited.add(node)) return;
      final SemanticsData data = node.getSemanticsData();
      if (!isOperable(data)) {
        node.visitChildren((SemanticsNode child) {
          walk(child);
          return true;
        });
        return;
      }
      final List<String> parts = <String>[];
      // The node itself was already claimed by `walk`, so the recursion starts
      // at its children.
      take(data, parts);
      node.visitChildren((SemanticsNode child) {
        if (visited.add(child)) collect(child, parts);
        return true;
      });
      readings.add((
        type: kindOf(data),
        spoken: parts.isEmpty
            ? '${kindOf(data)} — etiketsiz'
            : parts.join(' · '),
        named: parts.isNotEmpty,
      ));
    }

    walk(root);
    return readings;
  } finally {
    handle.dispose();
  }
}

/// Fails unless every outermost operable control has something to read out.
///
/// [allowUnlabelled] names the controls a screen has declared exempt, so an
/// exemption is a sentence in a test rather than an omission.
Future<void> expectEveryControlIsLabelled(
  WidgetTester tester, {
  Set<String> allowUnlabelled = const <String>{},
}) async {
  final List<SettingsControlReading> unlabelled =
      (await readSettingsControlLabels(tester))
          .where((SettingsControlReading r) {
            if (r.named) return false;
            return !allowUnlabelled.contains(r.type);
          })
          .toList();
  expect(
    unlabelled,
    isEmpty,
    reason:
        'these controls have nothing to read out: '
        '${unlabelled.map((SettingsControlReading r) => r.type).join(', ')}',
  );
}

/// Whether [data]'s node is something a user operates.
///
/// `didGainAccessibilityFocus` is deliberately **not** in this list. It says a
/// node *can be focused*, not that it *does* something, and almost every
/// container in a page is focusable: with it, a focusable `Column` is reported
/// as a control, its whole subtree is swallowed as its "name", and every real
/// control under it vanishes from the report. That is the same false negative
/// one level down, and it is why the counts in `settings_screen_test.dart`'s
/// "the accessibility floor" test are what prove this walk found anything at
/// all. Every control on this screen has a tap action, a role or a checked
/// state, so nothing is lost by leaving it out.
bool isOperable(SemanticsData? data) {
  // Null means "this render object owns no semantics node at all", the normal
  // state of a `Padding` and never a control.
  if (data == null) return false;
  final SemanticsFlags flags = data.flagsCollection;
  return flags.isTextField ||
      flags.isButton ||
      flags.isSlider ||
      flags.isLink ||
      flags.isChecked != CheckedState.none ||
      data.hasAction(SemanticsAction.tap);
}

/// A stable name for the kind of control, for a failure message.
///
/// The widget type is the wrong thing to print: the node that carries the role
/// is often a bare `Semantics`, so "unlabelled: Semantics" tells nobody
/// anything. The role does.
String kindOf(SemanticsData data) {
  final SemanticsFlags flags = data.flagsCollection;
  if (flags.isTextField) return 'metin alanı';
  if (flags.isButton) return 'düğme';
  if (flags.isSlider) return 'kaydırıcı';
  if (flags.isLink) return 'bağlantı';
  if (flags.isChecked != CheckedState.none) return 'anahtar';
  return 'denetlenebilir öğe';
}
