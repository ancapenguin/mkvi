/// The fixtures the settings screen tests share.
///
/// Three things, and nothing else:
///
/// * a [SettingsController] over the **real** token resolver and an in-memory
///   store, so a test cannot pass with a colour or a padding the design system
///   does not have — the same rule the harness enforces for the theme;
/// * [mkviSettingsPage], the screen inside a **320 dp column**, because
///   `pumpMkvi` hands a widget the full 1280 dp window and a `Row` in 1280 dp
///   never overflows no matter how broken it is. Without the column,
///   `expectNoOverflow` in this directory measures nothing;
/// * [SettingsStyleProbe], which hands the resolved style to a test from a real
///   `build` — the only legal place to read it in a test that pumps more than
///   once. See the long note in `test/support/mkvi_test_app.dart` about
///   `mkviStyleOf` and `InheritedElement.notifyClients`.
///
/// The Turkish copy the assertions look for is never written here: it is read
/// from `SettingsCatalog` and `SettingsUiTr`, the same two places the screen
/// reads it from, so a renamed theme breaks one test instead of two drifting
/// copies of the same word.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/settings_screen/settings_screen_ui.dart';

import '../../../support/mkvi_test_app.dart';

/// The width the samples are laid out in.
///
/// A phone width, and far narrower than the window the harness sets. Not a
/// design decision — it is the width at which an overflow becomes possible.
const double mkviSettingsColumnWidth = 320;

/// The version the tests report, as `pubspec.yaml` does.
///
/// Written here because the screen takes it as an argument rather than reading a
/// package manifest at runtime: a second source of the version inside
/// `app/lib/` is a value that will drift, and the test copy cannot.
const String mkviTestAppVersion = '0.2.0';

/// A controller over the real resolver and [store], or a fresh in-memory one.
SettingsController mkviSettingsController({
  SettingsStore? store,
  Brightness platformBrightness = Brightness.dark,
}) => SettingsController(
  repository: SettingsRepository(store ?? InMemorySettingsStore()),
  resolver: mkviResolver(),
  platformBrightness: platformBrightness,
);

/// The whole screen, in a column narrow enough for an overflow to happen.
Widget mkviSettingsPage(
  SettingsController controller, {
  VoidCallback? onCheckUpdate,
  String? updateStatusTr,
}) => SizedBox(
  width: mkviSettingsColumnWidth,
  child: SettingsScreen(
    controller: controller,
    appVersion: mkviTestAppVersion,
    onCheckUpdate: onCheckUpdate,
    updateStatusTr: updateStatusTr,
  ),
);

/// One section on its own, in the same narrow column.
///
/// A section test measures one section, and a screen test measures all of them;
/// neither should be measuring the other's layout. The scroll view is here
/// because a bare section is taller than the window: a `Column` that does not
/// fit is an overflow, and the only way to lay one section out at 320 dp is the
/// way the screen lays it out — inside a scroll view.
Widget mkviSettingsSection(Widget section) => SizedBox(
  width: mkviSettingsColumnWidth,
  child: SingleChildScrollView(child: section),
);

/// Hands the resolved [AppearanceStyle] to [onStyle] from a real `build`.
///
/// ## Why this exists instead of `mkviStyleOf`
///
/// `mkviStyleOf` walks `tester.allElements` and calls `Theme.of` on each one,
/// which registers an inherited-widget dependency from *outside* a build. That
/// is harmless in a test that pumps once and a landmine in one that pumps twice:
/// the next `pumpWidget` walks the stale dependents, one of them is no longer a
/// descendant, and the framework throws `Failed assertion: check that it really
/// is our descendant` from `InheritedElement.notifyClients` — with a
/// `MaterialApp` and a duplicate `Navigator` GlobalKey in the message, and
/// nothing in it that names the cause.
///
/// A matrix test has to read the palette after *every* pump, so it reads it from
/// here, which is a build context and therefore the only legal place.
class SettingsStyleProbe extends StatelessWidget {
  /// Wraps [child] and reports the style it is painted with.
  const SettingsStyleProbe({
    super.key,
    required this.onStyle,
    required this.child,
  });

  /// Called on every build, from inside one.
  final ValueChanged<AppearanceStyle> onStyle;

  /// The widget under test.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onStyle(AppearanceStyle.of(context));
    return child;
  }
}

/// Pumps the whole screen once per [matrix] entry, in [size], unmounting between.
///
/// The controller is moved to each entry first, so the *rendered* values
/// (`%125` on the slider, the sample rows, the stored endpoint) belong to the
/// same combination as the theme. A sweep that only changed the theme would
/// measure a screen showing one scale in a palette resolved for another.
///
/// [each] runs after the pump and receives the resolved style, captured by
/// [SettingsStyleProbe] during the build — never by `mkviStyleOf`, which would
/// register a dependency from outside a build and break the next `pumpWidget`.
Future<void> pumpSettingsMatrix(
  WidgetTester tester,
  SettingsController controller, {
  required Iterable<AppearanceSettings> matrix,
  required Size size,
  Widget Function(Widget page)? build,
  void Function(AppearanceSettings settings, AppearanceStyle style)? each,
}) async {
  for (final AppearanceSettings settings in matrix) {
    await controller.setAppearance(settings);
    late AppearanceStyle style;
    await unmountMkvi(tester);
    await pumpMkvi(
      tester,
      SettingsStyleProbe(
        onStyle: (AppearanceStyle value) => style = value,
        child: build?.call(mkviSettingsPage(controller)) ??
            mkviSettingsPage(controller),
      ),
      settings: settings,
      size: size,
    );
    each?.call(settings, style);
  }
}

/// Taps [finder] after bringing it on screen, and lets the frame commit.
///
/// A section on its own is inside a scroll view, so a control near the bottom of
/// it is off the 800 dp window and `tap` would hit nothing — a warning, then a
/// test failure that reads like a broken widget. `ensureVisible` is the fix, and
/// doing it in one place stops each test from remembering.
Future<void> tapInSection(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

/// The width one line of [text] needs in [style], measured rather than guessed.
///
/// How a test proves a label was **not** elided: the framework gives a clipped
/// or ellipsised line the width of its box, not the width of its text, so
/// comparing the two numbers is the only measurement that distinguishes "it
/// fits" from "it was cut". (`OverflowBar` and friends aside, a `Text` in a
/// `Row` with no `Flexible` around it is not elided — it overflows — so this is
/// also the assertion that catches a label that fell off the end of its row.)
double intrinsicLineWidth(String text, TextStyle style) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

/// The [Text] inside [finder], for a measurement.
Text textAt(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder);

/// The [TextStyle] the [Text] inside [finder] paints with.
TextStyle textStyleAt(WidgetTester tester, Finder finder) =>
    tester.widget<Text>(finder).style ?? const TextStyle();
