/// The fixtures the pairing tests share: a scripted exchange, a recording
/// clipboard, and the small readers that turn a widget under test into a number.
///
/// Kept in one file for the reason `test/ui/widgets/support/widget_fixtures.dart`
/// is: a reader written twice is a reader that measures two different things in
/// two files, and the numbers are what these tests assert on.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show CheckedState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/pairing/pairing.dart';

import '../../../support/fakes/fakes.dart';

/// A [PairingExchange] that records the codes it was given and answers from a
/// script.
///
/// A queue first and a standing answer after it, which is the same shape
/// `ScriptedDelay` and `FakePeerStore` use: "this attempt fails, the next one
/// succeeds" is a claim a test has to be able to make, and a single mutable
/// answer cannot express it without the test reaching into the seam mid-flight.
final class ScriptedPairingExchange {
  /// Creates an exchange that answers [answer] until a script entry is consumed.
  ScriptedPairingExchange(this.answer);

  /// The answer every call gets once [script] is empty.
  PairingOutcome answer;

  /// Consumed in order, before [answer].
  final List<PairingOutcome> script = <PairingOutcome>[];

  /// Every code the screen sent, in order.
  final List<String> codes = <String>[];

  /// How many attempts were made. A second one for one code is a defect.
  int calls = 0;

  /// The codes, deduplicated — "the same code was sent twice" reads off this.
  Set<String> get distinctCodes => codes.toSet();

  Future<PairingOutcome> call(String code) async {
    calls += 1;
    codes.add(code);
    return script.isNotEmpty ? script.removeAt(0) : answer;
  }
}

/// The outcome a completed pair reports: the two fields
/// `SessionController.completePairing` needs, and no name, because a late
/// `profile` frame must not be able to downgrade a stored one.
PairingOutcome scriptedAccepted({String? announcedName}) => PairingOutcome.accepted(
  publicKey: fakePeerPublicKey,
  discoveryId: fakeOpaqueId('room'),
  announcedName: announcedName,
);

/// A [PairingClipboard] that records the codes written to it and answers
/// [result].
PairingClipboard recordingClipboard({
  List<String>? written,
  bool result = true,
}) {
  final List<String> sink = written ?? <String>[];
  return (String code) async {
    sink.add(code);
    return result;
  };
}

/// Intercepts `SystemChannels.platform`'s clipboard messages for the test and
/// returns the calls that arrived.
///
/// The production seam (`copyPairingCodeToClipboard`) is a real
/// `Clipboard.setData`, so "the copy button works" is only provable against the
/// channel it actually talks to. `removeTearDown` is registered here rather than
/// by the caller, because a handler left installed would answer for the next
/// test in the file.
List<MethodCall> interceptClipboard() {
  final List<MethodCall> calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (
        MethodCall call,
      ) async {
        calls.add(call);
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

/// The [Text] data of the one text inside [finder], or '' if it has none.
String textIn(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).data ?? '';

/// The [BoxDecoration] of the [Container] [finder] points at.
BoxDecoration decorationIn(WidgetTester tester, Finder finder) =>
    tester.widget<Container>(finder).decoration! as BoxDecoration;

/// The [BoxDecoration] of whichever single box [finder] points at.
///
/// A [Container] and a [DecoratedBox] are the two shapes the layers here draw
/// with — `MkviPanel` uses a `DecoratedBox` and this directory's own cells use a
/// `Container` — and a reader that only understood one of them would make half
/// the palette assertions in this suite impossible to write.
BoxDecoration decorationOf(WidgetTester tester, Finder finder) {
  final Widget widget = tester.widget(finder);
  return switch (widget) {
    final Container box => box.decoration! as BoxDecoration,
    final DecoratedBox box => box.decoration as BoxDecoration,
    _ => throw StateError('${widget.runtimeType} paints no BoxDecoration'),
  };
}

/// The [TextStyle] of the one text inside [finder].
TextStyle styleIn(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).style ?? const TextStyle();

/// The enabled/locked state of the one button inside [finder], read off the
/// widget rather than off the ripple.
///
/// "The button is locked" has to be a claim about the handler, because a
/// disabled button still has a full-size ripple target and looks pressable in a
/// screenshot. The key is on [PairingActionButton], so the Material widget is
/// found underneath it.
bool buttonEnabled(WidgetTester tester, Finder finder) {
  final Finder filled = find.descendant(
    of: finder,
    matching: find.byType(FilledButton),
  );
  if (filled.evaluate().isNotEmpty) {
    return tester.widget<FilledButton>(filled).onPressed != null;
  }
  return tester
          .widget<OutlinedButton>(
            find.descendant(of: finder, matching: find.byType(OutlinedButton)),
          )
          .onPressed !=
      null;
}

/// Hosts one block the way the pairing screen does: a `Scaffold` on the page
/// background, with the screen's own padding.
///
/// `PairingScreen` carries its own `Scaffold`, so a test of a *block* — the code
/// view, the entry — is the only place a host is needed, and Material's controls
/// need a `Material` ancestor that a bare `MaterialApp` does not provide.
class PairingHost extends StatelessWidget {
  /// Wraps [child] in a scaffold and the screen's padding.
  const PairingHost({super.key, required this.child, this.surfaceRole = 'bg'});

  /// The block under test.
  final Widget child;

  /// The token role painted behind it.
  final String surfaceRole;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Scaffold(
      backgroundColor: style.role(surfaceRole),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(style.gap('10')),
        child: child,
      ),
    );
  }
}

/// Every operable control the pairing screen builds, so a hit-target sweep
/// cannot forget one.
///
/// Keys whose widget is absent on the current state are dropped, because the
/// two states genuinely have different controls and a finder that must match
/// exactly one widget cannot be walked over both.
List<Finder> pairingControls(WidgetTester tester, {List<Key> keys = const <Key>[]}) {
  final List<Key> all = <Key>[
    PairingCodeKeys.copy,
    PairingCodeKeys.regenerate,
    PairingEnterKeys.submit,
    ...keys,
  ];
  return <Finder>[
    for (final Key key in all)
      if (find.byKey(key).evaluate().isNotEmpty) find.byKey(key),
  ];
}

// ---------------------------------------------------------------------------
// The accessibility floor
// ---------------------------------------------------------------------------

/// One operable control and what a screen reader would read for it.
typedef PairingReading = ({String kind, String spoken});

/// Every operable control on screen, with what a screen reader would read.
///
/// ## Why this is here and not `readControlLabels`
///
/// Two measured defects in `test/support/mkvi_test_app.dart`, both of which make
/// `expectEveryControlLabelled` an assertion that cannot fail:
///
/// 1. it disposes its `SemanticsHandle` from an `addTearDown`, while
///    `testWidgets` runs `WidgetTester._endOfTestVerifications` — which throws on
///    any handle still outstanding — from `binding.runTest`, i.e. **inside** the
///    test body, before any teardown has run:
///
///    ```text
///    A SemanticsHandle was active at the end of the test.
///    All SemanticsHandle instances must be disposed by calling dispose() on the SemanticsHandle.
///    ```
///
/// 2. it reads the tree through `tester.binding.rootPipelineOwner.semanticsOwner`,
///    whose `rootSemanticsNode` is `null` in a widget test; the populated owner is
///    `tester.binding.pipelineOwner.semanticsOwner` (measured: `rootPipelineOwner`
///    prints `root node: null`, `pipelineOwner` prints the 1280x800 node). So
///    `readControlLabels` returns an empty list, and an empty list passes.
///
/// This is the lead's file, so it is not touched here. This walk fixes both and
/// should be deleted the moment the harness does. A null root **throws** here
/// rather than returning an empty list, because a reader that reports "nothing
/// to check" is a reader that can never fail.
Future<List<PairingReading>> pairingControlReadings(
  WidgetTester tester,
) async {
  final SemanticsHandle handle = tester.ensureSemantics();
  try {
    // Two pumps, not one: `ensureSemantics` marks the tree dirty, the first pump
    // produces the nodes and the second paints them. A single pump reads an
    // empty tree and reports every control in the app as absent.
    await tester.pump();
    await tester.pump();
    // The non-deprecated route is `rootPipelineOwner`, and it is the one the
    // shared harness takes — but in a widget test it owns a `SemanticsOwner`
    // whose `rootSemanticsNode` is `null` (measured), so it can only ever return
    // an empty reading. The populated owner is the deprecated
    // `binding.pipelineOwner`, and a deprecation is a smaller problem than an
    // accessibility assertion that measures nothing.
    // ignore: deprecated_member_use
    final SemanticsNode? root = tester.binding.pipelineOwner.semanticsOwner
        ?.rootSemanticsNode;
    if (root == null) {
      throw StateError(
        'No semantics tree after ensureSemantics() and two pumps. A reader '
        'that reports "nothing to check" here is a reader that can never fail.',
      );
    }

    final List<PairingReading> readings = <PairingReading>[];
    final Set<SemanticsNode> walked = <SemanticsNode>{};

    /// Everything a screen reader would read for one control: its own label, hint
    /// and tooltip, and those of the nodes under it — because Material puts a
    /// control's name on a DESCENDANT node, not on the node that owns the role,
    /// and a reader that reads only the role-bearing node calls every text field
    /// in the app unlabelled.
    List<String> spokenFor(SemanticsNode node, List<SemanticsNode> children) {
      final List<String> parts = <String>[];
      void collect(SemanticsData from) {
        for (final String value in <String>[
          from.label,
          from.hint,
          from.tooltip,
        ]) {
          if (value.isNotEmpty && !parts.contains(value)) parts.add(value);
        }
      }

      collect(node.getSemanticsData());
      for (final SemanticsNode child in children) {
        collect(child.getSemanticsData());
      }
      return parts;
    }

    void walk(SemanticsNode node) {
      if (!walked.add(node)) return;
      final List<SemanticsNode> children = <SemanticsNode>[];
      node.visitChildren((SemanticsNode child) {
        children.add(child);
        return true;
      });
      final SemanticsData data = node.getSemanticsData();
      if (_isOperable(data)) {
        readings.add((
          kind: _kindOf(data),
          spoken: spokenFor(node, children).join(' · '),
        ));
        // Do not report a control inside a control: a Material button is an
        // `ElevatedButton` over an `InkWell` over a `GestureDetector`, and a
        // reader that reported all three would fail on one control three times.
        return;
      }
      for (final SemanticsNode child in children) {
        walk(child);
      }
    }

    walk(root);
    return readings;
  } finally {
    handle.dispose();
  }
}

/// The operable controls with nothing to read out.
Future<List<String>> unlabelledControls(
  WidgetTester tester, {
  Set<String> allowUnlabelled = const <String>{},
}) async => <String>[
  for (final PairingReading reading in await pairingControlReadings(tester))
    if (reading.spoken.isEmpty && !allowUnlabelled.contains(reading.kind))
      reading.kind,
];

/// Fail unless every operable control on this screen has something to read out.
///
/// ## Why this no longer exempts anything
///
/// It used to exempt `metin alanı` outright, and the exemption was correct at
/// the time: the code field sat under `Opacity(opacity: 0)`, Flutter dropped it
/// from the semantics tree, and the field was *absent* rather than unlabelled.
/// There was nothing to exempt — it simply was not there.
///
/// `mkvi_code_field.dart` now passes `alwaysIncludeSemantics: true`, so the
/// field IS in the tree and IS a text field, and an exemption would hide the
/// exact regression it was added to survive. The list is empty on purpose: a
/// screen that genuinely needs one should name that control and its reason in
/// its own test, where a reader will see the sentence.
Future<void> expectPairingControlsLabelled(
  WidgetTester tester, {
  Set<String> allowUnlabelled = const <String>{},
}) async {
  expect(
    await unlabelledControls(tester, allowUnlabelled: allowUnlabelled),
    isEmpty,
    reason:
        'these controls have nothing to read out. If one of them is the code '
        'field, the regression is `Opacity` without `alwaysIncludeSemantics`.',
  );
}

/// The role the control's kind carries, for a failure message.
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
  if (data == null) return false;
  final SemanticsFlags flags = data.flagsCollection;
  return flags.isTextField ||
      flags.isButton ||
      flags.isSlider ||
      flags.isLink ||
      data.hasAction(SemanticsAction.tap) ||
      data.hasAction(SemanticsAction.didGainAccessibilityFocus);
}
