/// The fixtures the input and choice tests share.
///
/// Three things live here and nothing else: a screen that hosts a control the
/// way a screen will, a catalogue with Turkish labels, and the small readers
/// that turn a widget under test into a number. Keeping them in one file is
/// what stops three test files from inventing three slightly different
/// paddings - and a padding that differs between tests is a padding no test is
/// actually measuring.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

/// Hosts one control the way a screen does: a surface, a `Scaffold`, and the
/// screen's own padding, all read from the resolved style.
///
/// [surfaceRole] is the token role the control is standing on, so a test can
/// put a control on `surfaceRaised` and measure it there - which is the only
/// way the ROADMAP's surface rule can be tested at all.
class InputHost extends StatelessWidget {
  /// Wraps [child] in a surface and a screen's padding.
  const InputHost({super.key, required this.child, this.surfaceRole = 'bg'});

  /// The control under test.
  final Widget child;

  /// The token role painted behind the control.
  final String surfaceRole;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return ColoredBox(
      color: style.role(surfaceRole),
      child: Scaffold(
        backgroundColor: style.role(surfaceRole),
        body: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(style.gap('8')),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// The three densities a test picks from, as a plain enum.
///
/// Deliberately not [DensityPreference]: this one has three options so a
/// segmented control has a middle segment, and it must not be confused with
/// the preference the settings layer stores.
enum TestDensity { compact, cozy, roomy }

/// The Turkish name of a test density.
String testDensityTr(TestDensity density) => switch (density) {
  TestDensity.compact => 'Sıkışık',
  TestDensity.cozy => 'Rahat',
  TestDensity.roomy => 'Geniş',
};

/// What a test density does, in Turkish.
String testDensityDescription(TestDensity density) => switch (density) {
  TestDensity.compact => 'Boşluklar daralır, yazı tipi boyutu değişmez.',
  TestDensity.cozy => 'Varsayılan ölçüler.',
  TestDensity.roomy => 'Boşluklar genişler, yazı tipi boyutu değişmez.',
};

/// A catalogue of the three test densities, with Turkish labels from outside.
MkviChoiceCatalog<TestDensity> testDensityCatalog({
  Set<TestDensity>? selection,
  bool multiple = false,
  void Function(Set<TestDensity> previous, Set<TestDensity> next)? onDidChange,
}) {
  return MkviChoiceCatalog<TestDensity>(
    label: 'Yoğunluk',
    multiple: multiple,
    onDidChange: onDidChange,
    selection: selection,
    options: <MkviChoiceOption<TestDensity>>[
      for (final TestDensity density in TestDensity.values)
        MkviChoiceOption<TestDensity>(
          value: density,
          label: testDensityTr(density),
          description: testDensityDescription(density),
        ),
    ],
  );
}

/// The Turkish text of a type scale, in the token file's own percent form.
///
/// The same wording `SettingsCatalog.fontScaleValue` uses, so a test that
/// measures the slider is measuring what the settings screen will say.
String testFontScaleTr(double scale) => '%${(scale * 100).round()}';

/// The [Text] data of the one text inside [finder], or '' if it is empty.
String textIn(WidgetTester tester, Finder finder) {
  final Text text = tester.widget<Text>(finder);
  return text.data ?? '';
}

/// The [TextStyle] of the one text inside [finder].
TextStyle styleIn(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).style ?? const TextStyle();

/// The colour of the top edge of the box [finder] points at.
Color borderColourOf(WidgetTester tester, Finder finder) {
  final Container container = tester.widget<Container>(finder);
  final BoxDecoration decoration = container.decoration! as BoxDecoration;
  return decoration.border!.top.color;
}
