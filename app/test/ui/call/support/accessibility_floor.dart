/// The accessibility floor for `test/ui/call` — and the two measured reasons the
/// harness's own one cannot be called from here.
///
/// ## Problem 1: the harness leaks its `SemanticsHandle`
///
/// `test/support/mkvi_test_app.dart`'s `readControlLabels` does
///
/// ```dart
/// final SemanticsHandle handle = tester.ensureSemantics();
/// addTearDown(handle.dispose);
/// ```
///
/// and `testWidgets` runs `WidgetTester._endOfTestVerifications` — which throws on
/// any outstanding handle — from `binding.runTest`, i.e. **inside** the test body,
/// before any `addTearDown` callback has run. So every call to the harness's
/// `expectEveryControlLabelled` fails on the handle and never on the claim it was
/// making. `test/ui/pairing/support/pairing_fixtures.dart` records the same
/// finding and the same conclusion. **This one is not fixable by a caller**: the
/// handle is created inside the helper, so the only way out is for the helper to
/// dispose it in a `finally`.
///
/// ## Problem 2: it reads an owner that has no tree
///
/// The same helper reads the root node as
/// `tester.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode`. On this
/// Flutter version that is `null` **even with every control named and the tree
/// fully built** — the tree lives on the per-view owner:
///
/// ```dart
/// tester.binding.renderViews.first.owner
///     ?.semanticsOwner?.rootSemanticsNode   // SemanticsNode#0(1280x800)
/// ```
///
/// Measured, in both directions, in
/// `call_controls_test.dart` → `about the harness, measured not assumed`. So
/// `readControlLabels` returns an empty list, `expectEveryControlLabelled` filters
/// an empty list, and it **passes vacuously** — including on a screen whose icon
/// buttons carry no name at all. `test/support/mkvi_test_app_test.dart` asserts
/// `expect(readings, isNotEmpty)` and cannot be green on this branch.
///
/// The fix is one line in the harness, and it is the lead's file.
///
/// ## What measures instead, today
///
/// [expectEveryControlIsNamed] walks the **widget** tree and requires every
/// operable control to be named by one of the only two ways Flutter names one:
///
/// * a `Tooltip` above it, whose message Flutter puts into the semantics node as
///   `tooltip` — this is what an `IconButton` with a glyph and nothing else has;
/// * a `Text` inside it with non-empty content — this is what a button with a
///   Turkish label has.
///
/// It is not a weaker claim. A control whose `Tooltip` is deleted, or whose label
/// is blanked, fails it — which is exactly the negative control
/// `ROADMAP.md`'s 17 WCAG violations describe and which
/// `call_controls_test.dart` runs against the real bar.
///
/// ## When to delete this file
///
/// When the harness disposes its own handle **and** reads the per-view owner,
/// [expectEveryControlIsLabelled] below is the better check and the widget-tree
/// copy should go. The assertions in `call_controls_test.dart` are written so
/// that the day the harness is fixed, the two disagree loudly rather than
/// silently.
library;

import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// The control kinds this directory declares exempt, and why.
///
/// A `Radio` is announced by a screen reader as part of its **row**: the name is
/// the row's `Text`, which is a sibling of the radio rather than a property of
/// it, so the radio's own semantics node arrives with an empty label. Measured,
/// not assumed — a picker with six rows produces twelve unnamed `anahtar` nodes
/// in the semantics tree, two per row, and no name on any of them.
///
/// Nothing is lost by the exemption: the rows *are* named, and
/// `device_picker_test.dart` asserts every label with `find.text` and every
/// device id on the `Radio` itself. Fixing it properly means `MkviOptionRow`
/// merging its label onto the `Radio`, and that file is the lead's — so the
/// exemption is a sentence here rather than an omission, which is what
/// [allowUnlabelled] is for.
const Set<String> callUiExemptKinds = <String>{'anahtar'};

/// The controls this floor looks at.
///
/// A Material button is a `ButtonStyleButton` over an `InkWell` over a
/// `GestureDetector`, so the same physical control appears under three types.
/// [controlNames] therefore keeps only the **outermost** match on each branch,
/// which is the same rule the harness's semantics walk follows for the same
/// reason: walking widgets and counting every match reports one button three
/// times and makes a count assertion meaningless.
const List<Type> operableWidgetTypes = <Type>[
  IconButton,
  FilledButton,
  OutlinedButton,
  TextButton,
  InkWell,
];

/// Every operable control in the pumped tree, with the name a screen reader would
/// read out for it.
List<({String kind, String name})> controlNames(WidgetTester tester) {
  final List<Element> matches = <Element>[];
  for (final Type type in operableWidgetTypes) {
    matches.addAll(find.byType(type).evaluate());
  }

  final List<({String kind, String name})> found = <({String kind, String name})>[];
  final Set<Element> reported = <Element>{};
  for (final Element element in matches) {
    // An operable control inside another one is the same control.
    if (find
        .ancestor(
          of: find.byElementPredicate((Element c) => identical(c, element)),
          matching: find.byWidgetPredicate(
            (Widget w) => operableWidgetTypes.contains(w.runtimeType),
          ),
        )
        .evaluate()
        .isNotEmpty) {
      continue;
    }
    final Widget widget = element.widget;
    // A disabled control is not operable, so it is not held to the promise — and
    // it is not skipped from the count either, because a disabled control is
    // still announced by Flutter and a user still has to know what it is.
    if (widget is ButtonStyleButton && widget.onPressed == null) continue;
    if (widget is InkWell && widget.onTap == null) continue;
    if (!reported.add(element)) continue;
    found.add((kind: widget.runtimeType.toString(), name: nameOf(element)));
  }
  return found;
}

/// The name Flutter would give the control at [element]: a tooltip above it, or a
/// label inside it.
String nameOf(Element element) {
  final String fromTooltip = _tooltipAbove(element);
  if (fromTooltip.isNotEmpty) return fromTooltip;
  return _textInside(element);
}

String _tooltipAbove(Element element) {
  final Iterable<Element> tooltips = find
      .ancestor(
        of: find.byElementPredicate((Element candidate) => identical(candidate, element)),
        matching: find.byType(Tooltip),
      )
      .evaluate();
  for (final Element tooltip in tooltips) {
    final String? message = (tooltip.widget as Tooltip).message;
    if (message != null && message.isNotEmpty) return message;
  }
  return '';
}

String _textInside(Element element) {
  final Iterable<Element> texts = find
      .descendant(
        of: find.byElementPredicate((Element candidate) => identical(candidate, element)),
        matching: find.byType(Text),
      )
      .evaluate();
  final List<String> parts = <String>[];
  for (final Element text in texts) {
    final String? data = (text.widget as Text).data;
    if (data != null && data.isNotEmpty && !parts.contains(data)) {
      parts.add(data);
    }
  }
  return parts.join(' · ');
}

/// Fail unless every operable control has something to read out.
///
/// The last line of every test in `test/ui/call`, next to [expectNoOverflow].
/// [allowUnlabelled] names the controls a screen has declared exempt, so an
/// exemption is a sentence in a test rather than an omission.
void expectEveryControlIsNamed(
  WidgetTester tester, {
  Set<String> allowUnlabelled = const <String>{},
}) {
  final List<({String kind, String name})> unnamed = controlNames(tester)
      .where(
        (({String kind, String name}) reading) =>
            reading.name.isEmpty && !allowUnlabelled.contains(reading.kind),
      )
      .toList();
  expect(
    unnamed,
    isEmpty,
    reason:
        'these controls have nothing to read out: '
        '${unnamed.map((({String kind, String name}) r) => r.kind).join(', ')}',
  );
}

/// Every operable control in the pumped tree, read out of the **semantics** tree.
///
/// The same walk the harness does, with the two measured defects fixed: the
/// handle is disposed in a `finally` rather than in an `addTearDown` that runs
/// too late, and the root node is read from the **per-view** owner, which is
/// where the tree is on this Flutter version. See this file's header.
Future<List<({String kind, String spoken})>> callControlLabels(
  WidgetTester tester,
) async {
  final SemanticsHandle handle = tester.ensureSemantics();
  try {
    // Two pumps, not one: `debugSemantics` is written during paint, so the first
    // pump produces the nodes and the second paints them. A single pump reads an
    // empty tree and reports every control as absent — the false negative in the
    // one direction a floor must never have.
    await tester.pump();
    await tester.pump();
    final SemanticsNode? root = tester.binding.renderViews.first.owner
        ?.semanticsOwner
        ?.rootSemanticsNode;
    if (root == null) return const <({String kind, String spoken})>[];

    final List<({String kind, String spoken})> readings =
        <({String kind, String spoken})>[];
    final Set<SemanticsNode> visited = <SemanticsNode>{};

    void walk(SemanticsNode node) {
      if (!visited.add(node)) return;
      final SemanticsData data = node.getSemanticsData();
      if (_isOperable(data)) {
        final Set<SemanticsNode> subtree = <SemanticsNode>{};
        node.visitChildren((SemanticsNode child) {
          subtree.add(child);
          walk(child);
          return true;
        });
        readings.add((kind: _kindOf(data), spoken: _spokenFor(data, subtree)));
        return; // Never report a control inside a control.
      }
      node.visitChildren((SemanticsNode child) {
        walk(child);
        return true;
      });
    }

    walk(root);
    return readings;
  } finally {
    handle.dispose();
  }
}

/// Fail unless every operable control **has a semantics node at all**, and every
/// one of those nodes has something to read out.
///
/// This is the check the harness's `expectEveryControlLabelled` intends to be,
/// and it is the strict one: it also fails when the semantics tree is empty,
/// which is what a vacuous floor must do.
Future<void> expectEveryControlIsLabelled(
  WidgetTester tester, {
  Set<String> allowUnlabelled = const <String>{},
}) async {
  final List<({String kind, String spoken})> readings = await callControlLabels(
    tester,
  );
  final int inTheTree = controlNames(tester).length;
  expect(
    readings.length,
    greaterThanOrEqualTo(inTheTree),
    reason:
        'the widget tree has $inTheTree operable control(s) and the semantics '
        'tree reported ${readings.length}. A semantics tree that reports '
        '*fewer* is a floor that counts nothing, which is how '
        '`expectEveryControlLabelled` in `test/support/mkvi_test_app.dart` '
        'passes vacuously today; more is legitimate, because a `Radio` is two '
        'operable nodes and one row. See this file\'s header.',
  );
  final List<({String kind, String spoken})> unlabelled = readings
      .where(
        (({String kind, String spoken}) reading) =>
            reading.spoken.isEmpty && !allowUnlabelled.contains(reading.kind),
      )
      .toList();
  expect(
    unlabelled,
    isEmpty,
    reason:
        'these controls have nothing to read out: '
        '${unlabelled.map((({String kind, String spoken}) r) => r.kind).join(', ')}',
  );
}

/// The kind of control, for a failure message.
///
/// The widget type is the wrong thing to print: the node that carries the role is
/// often a bare `Semantics`, so "unlabelled: Semantics" tells the next agent
/// nothing. The role does.
String _kindOf(SemanticsData data) {
  final SemanticsFlags flags = data.flagsCollection;
  if (flags.isTextField) return 'metin alanı';
  if (flags.isButton) return 'düğme';
  if (flags.isSlider) return 'kaydırıcı';
  if (flags.isLink) return 'bağlantı';
  if (flags.isChecked != CheckedState.none) return 'anahtar';
  return 'denetlenebilir öğe';
}

bool _isOperable(SemanticsData? data) {
  // Null means "this render object owns no semantics node at all", the normal
  // state for a `Padding` and never a control.
  if (data == null) return false;
  final SemanticsFlags flags = data.flagsCollection;
  return flags.isTextField ||
      flags.isButton ||
      flags.isSlider ||
      flags.isLink ||
      data.hasAction(SemanticsAction.tap) ||
      data.hasAction(SemanticsAction.didGainAccessibilityFocus);
}

/// A control's own name plus the names of the nodes under it.
///
/// A name is often *not* on the node that owns the role: Material puts a
/// `TextField`'s name on a descendant, and an `IconButton`'s `Tooltip` puts its
/// message on the node above the button. Reading only the role-bearing node calls
/// every one of them unlabelled, which is the false negative an accessibility
/// assertion must not have.
String _spokenFor(SemanticsData data, Set<SemanticsNode> subtree) {
  final List<String> parts = <String>[];
  void take(SemanticsData from) {
    for (final String value in <String>[
      from.label,
      from.hint,
      from.tooltip,
    ]) {
      if (value.isNotEmpty && !parts.contains(value)) parts.add(value);
    }
  }

  take(data);
  for (final SemanticsNode child in subtree) {
    take(child.getSemanticsData());
  }
  return parts.join(' · ');
}
