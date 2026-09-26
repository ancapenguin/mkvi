/// The harness every widget test in `test/ui/` uses.
///
/// ## Why this file exists
///
/// `AppearanceStyle.of(context)` throws on purpose when the `ThemeData` carries
/// no style, so a widget test cannot simply wrap a widget in a bare
/// `MaterialApp`: the widget under test would throw before it drew anything, and
/// every test would end up inventing its own spacing, its own colours and its
/// own idea of what a hit target is. That is the defect this app already paid
/// for once — `density` was honoured in 8 call sites out of ~40 and `fontScale`
/// in none, because both were values nobody was obliged to read.
///
/// So there is exactly one way to put a widget under test:
///
/// ```dart
/// await pumpMkvi(tester, const MyWidget());
/// ```
///
/// and the theme it paints with comes from the real token file, through the real
/// [AppearanceResolver], so a test cannot pass with a colour or a padding the
/// design system does not have.
///
/// ## The matrix, and the trap that comes with it
///
/// [mkviAppearanceMatrix] is the 4x4 theme/accent grid `ROADMAP.md` Faz 2 asks
/// for, [mkviScaleMatrix] is both ends of the type slider at both densities,
/// and [mkviAccessibilityMatrix] is the two accessibility switches both ways.
/// Every screen test is expected to walk them, which means **pumping more than
/// once inside a single test** — and that is where pumping a whole app twice
/// used to throw:
///
/// ```text
/// 'package:flutter/src/widgets/framework.dart': A Theme was inherited but an
/// unrelated ancestor of the widget that requested the inheritance is
/// introducing a new Theme...
/// ```
///
/// Replacing the root widget inside one frame leaves the outgoing `Theme`'s
/// dependants registered against an element that is being torn down, and
/// `InheritedElement.notifyClients` refuses. Three agents hit it independently
/// and each wrote their own workaround, which is the worst possible outcome for
/// a shared harness.
///
/// The fix is [unmountMkvi]: **pump an empty tree first, let the frame commit,
/// then pump the next one.** [pumpMkviMatrix] does it for you.
///
/// ## The rules this harness enforces for you
///
/// * [pumpMkvi] always installs a real `AppearanceStyle` and an ambient
///   `DefaultTextStyle`. Never wrap a widget under test in your own
///   `MaterialApp`: a bare `Text` with no `DefaultTextStyle` renders in
///   Flutter's *error* style — red, monospace, double-underlined — so any
///   geometry measured around one is measuring the error style, not the app.
/// * Widgets read spacing from `AppearanceStyle.of(context).gap('4')`, never a
///   literal. A literal in a widget is a bug.
/// * [pumpMkvi] must not be called twice in one test without [unmountMkvi] in
///   between. Use [pumpMkviMatrix] for the loop case.
/// * Every screen test ends with [expectNoOverflow] and
///   [expectEveryControlLabelled]. The first is the defect class 0.1.x shipped
///   in every one of its screens; the second is the other one.
library;

import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/settings/settings.dart';

import '../settings/support/design_bridge.dart';

/// The desktop window this app ships in, in logical pixels.
///
/// The default `flutter test` surface is 800x600, which is a phone. Every layout
/// bug this app is prone to — a composer a toast covers, a call stage a
/// placeholder hides, a settings row that clips its own label — is a bug at
/// 1280x800 and invisible at 600.
const Size mkviWindowSize = Size(1280, 800);

/// The small desktop window the layout must survive without a single overflow.
const Size mkviNarrowWindowSize = Size(720, 640);

/// The phone-shaped window, for the screens that also have to work in a corner.
const Size mkviPhoneWindowSize = Size(400, 720);

/// Every window size the matrix helpers offer.
const List<Size> mkviWindowSizes = <Size>[
  mkviWindowSize,
  mkviNarrowWindowSize,
  mkviPhoneWindowSize,
];

/// The token file, loaded once.
DesignTokensFixture get mkviTokenFixture => DesignTokensFixture.load();

/// A resolver over the real token file.
AppearanceResolver mkviResolver() =>
    AppearanceResolver(mkviTokenFixture.tokens);

/// A resolved appearance, straight from a preference.
///
/// Defaults to what a fresh install resolves to on a dark platform.
ResolvedAppearance mkviAppearance({
  AppearanceSettings settings = AppearanceSettings.initial,
  Brightness platformBrightness = Brightness.dark,
}) => mkviResolver().resolve(
  settings,
  platformBrightness: platformBrightness,
);

/// The 4x4 grid `ROADMAP.md` Faz 2 names: every theme against every accent.
///
/// A widget that only survives `midnight` + `blue` has not been tested, and the
/// old build's worst measured pair — a video placeholder at 1.17:1 — lived in
/// exactly one theme. Iterate it inside a single `testWidgets` and let
/// [pumpMkviMatrix] handle the unmounting, so a failure names the combination
/// instead of an index.
Iterable<AppearanceSettings> mkviAppearanceMatrix() sync* {
  for (final ThemePreference theme in <ThemePreference>[
    ThemePreference.midnight,
    ThemePreference.light,
    ThemePreference.forest,
    ThemePreference.plum,
  ]) {
    for (final AccentId accent in AccentId.values) {
      yield AppearanceSettings(
        theme: theme,
        accent: AccentPreference.preset(accent),
      );
    }
  }
}

/// The smallest and largest type the settings screen offers, at both densities.
///
/// The token file declares three densities (`compact`, `cozy`, `roomy`) but
/// `DensityPreference` exposes only two, so this is six combinations, not
/// twelve. That gap is a decision to make, not an oversight: add `roomy` to
/// `DensityPreference` and this helper widens on its own.
Iterable<AppearanceSettings> mkviScaleMatrix() sync* {
  for (final double scale in <double>[
    AppearanceSettings.minFontScale,
    AppearanceSettings.defaultFontScale,
    AppearanceSettings.maxFontScale,
  ]) {
    for (final DensityPreference density in DensityPreference.values) {
      yield AppearanceSettings(fontScale: scale, density: density);
    }
  }
}

/// The two accessibility switches, as a matrix of their own.
///
/// High contrast pushes the ramps towards their extremes and thickens the focus
/// ring; reduced motion replaces every duration. Both change what a widget is
/// asked to draw, so both belong in the sweep rather than in one test at the end.
Iterable<AppearanceSettings> mkviAccessibilityMatrix() sync* {
  for (final bool highContrast in <bool>[false, true]) {
    for (final bool reduceMotion in <bool>[false, true]) {
      yield AppearanceSettings(
        highContrast: highContrast,
        reduceMotion: reduceMotion,
      );
    }
  }
}

/// Every type step name in the token file, smallest first.
const List<String> mkviTypeSteps = <String>[
  '2xs',
  'xs',
  'sm',
  'md',
  'lg',
  'xl',
  '2xl',
];

/// Every spacing step name in the token file, smallest first.
const List<String> mkviSpaceSteps = <String>[
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '10',
];

/// The radius preset names, `design/tokens.json`'s own.
const List<String> mkviRadiusPresets = <String>['cozy', 'crisp'];

/// The app under test: a [MaterialApp] carrying the real theme.
///
/// Use it when the widget needs a `Navigator`, a `Directionality` or an
/// `Overlay`. [pumpMkvi] is the normal way in.
class MkviTestApp extends StatelessWidget {
  const MkviTestApp({
    super.key,
    required this.home,
    required this.appearance,
    this.themeMode,
  });

  /// What to show.
  final Widget home;

  /// The theme to paint with. Must come from [mkviAppearance] or [mkviResolver].
  final ResolvedAppearance appearance;

  /// Overrides the appearance's own `ThemeMode`, for a test about the switch
  /// rather than about one resolved theme.
  final ThemeMode? themeMode;

  @override
  Widget build(BuildContext context) {
    final AppearanceThemes themes = mkviResolver().resolveThemes(
      appearance.settings,
    );
    return MaterialApp(
      title: 'MKVI',
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: themeMode ?? themes.mode,
      home: home,
    );
  }
}

/// Pump [child] inside a real themed app, at [size].
///
/// This is the only supported way to put a widget under test. It installs a real
/// [AppearanceStyle] — and an ambient `DefaultTextStyle`, so a bare `Text` does
/// not render in Flutter's error style — sizes the surface, and restores both
/// when the test ends.
///
/// **Not callable twice in one test without [unmountMkvi] in between.** Use
/// [pumpMkviMatrix] for that case.
Future<void> pumpMkvi(
  WidgetTester tester,
  Widget child, {
  AppearanceSettings settings = AppearanceSettings.initial,
  Brightness platformBrightness = Brightness.dark,
  ThemeMode? themeMode,
  Size size = mkviWindowSize,
  bool settle = true,
}) async {
  await setMkviSurfaceSize(tester, size);
  final ResolvedAppearance appearance = mkviAppearance(
    settings: settings,
    platformBrightness: platformBrightness,
  );
  await tester.pumpWidget(
    MkviTestApp(
      // `Material` is not decoration: `TextField`, `DropdownButton`, `ListTile`
      // and every other Material control ASSERT without an ancestor that
      // provides `MaterialLocalizations`/`Material`'s ink and a text direction.
      //
      // This was measured, not assumed. Without it a `TextField` in a widget
      // test throws while BUILDING - so the widget never reaches the layout
      // pass, the semantics tree never gains a node, and an accessibility
      // assertion reports "no control found" instead of "the field has no
      // label". A helper that silently drops half the tree is worse than no
      // helper, because the failure looks like a passing test.
      //
      // `Scaffold` would also work and would bring a `ScaffoldMessenger`, but a
      // test should not inherit an app bar and a floating action button it
      // never asked for. `Material` is the smallest correct ancestor.
      home: Material(
        child: DefaultTextStyle(
          style: appearance.style.textTheme.bodyMedium ?? const TextStyle(),
          child: child,
        ),
      ),
      appearance: appearance,
      themeMode: themeMode,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Take the previous tree down and let the frame commit.
///
/// `InheritedElement.notifyClients` throws "A Theme was inherited but an
/// unrelated ancestor ... is introducing a new Theme" when a root widget is
/// replaced inside one frame, which is exactly what a matrix loop does. Three
/// agents hit this independently and wrote three workarounds; this is the one.
Future<void> unmountMkvi(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Pump [build] once per [settings] in [matrix], unmounting between each.
///
/// This is the shape a screen test should have, because it is the shape the
/// product has: one window, one preference set, every combination. [each] runs
/// after the pump, so the assertions live there and a failure names the
/// combination through [describeCombination].
Future<void> pumpMkviMatrix(
  WidgetTester tester,
  Widget Function(AppearanceSettings settings) build, {
  required Iterable<AppearanceSettings> matrix,
  Size size = mkviWindowSize,
  Brightness platformBrightness = Brightness.dark,
  void Function(AppearanceSettings settings)? each,
}) async {
  for (final AppearanceSettings settings in matrix) {
    await unmountMkvi(tester);
    await pumpMkvi(
      tester,
      build(settings),
      settings: settings,
      platformBrightness: platformBrightness,
      size: size,
    );
    each?.call(settings);
  }
}

/// A readable name for one matrix entry, for a failure message.
String describeCombination(AppearanceSettings settings) =>
    '${settings.theme.name}/${settings.accent.accentId} '
    'font ${settings.fontScale} ${settings.density.name}';

/// Resize the test surface and restore it when the test ends.
Future<void> setMkviSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// The style the pumped tree is actually painting with.
///
/// Read this in a test to assert a number instead of hard-coding it: the
/// assertion then survives a token change and still fails when the widget stops
/// using the style.
///
/// The lookup walks the element tree rather than starting at the `MaterialApp`,
/// because `Theme.of` on the `MaterialApp`'s own element reads the theme
/// **above** the app — the one `MaterialApp` itself installs, which carries no
/// `AppearanceStyle`.
AppearanceStyle mkviStyleOf(WidgetTester tester) {
  for (final Element element in tester.allElements) {
    final AppearanceStyle? style = Theme.of(
      element,
    ).extension<AppearanceStyle>();
    if (style != null) return style;
  }
  throw StateError(
    'No AppearanceStyle anywhere in the pumped tree. Was the widget pumped '
    'with pumpMkvi rather than a bare MaterialApp?',
  );
}

/// Fail unless [foregroundRole] on [backgroundRole] clears [minimum] in the
/// palette the style is about to paint.
///
/// `ROADMAP.md` records the two worst measured pairs of the old build — a video
/// placeholder at 1.17:1 and a focus ring identical to the accent at 1.00:1 —
/// and both were invisible until something measured them.
void expectTokenContrast(
  AppearanceStyle style,
  String foregroundRole,
  String backgroundRole, {
  double minimum = 4.5,
}) {
  final double ratio = style.contrast(foregroundRole, backgroundRole);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason:
        '$foregroundRole on $backgroundRole is ${ratio.toStringAsFixed(2)}:1, '
        'below the required ${minimum.toStringAsFixed(2)}:1 '
        '(theme ${style.themeId}, accent ${style.accentId}, '
        'highContrast: ${style.highContrast})',
  );
}

/// Fail when [finder]'s box is smaller than the token hit target on its short
/// side.
///
/// 44 dp is a physical promise in `design/tokens.json` (`control.hitTargetMin`),
/// not a style, so it is never scaled by density.
void expectHitTarget(
  WidgetTester tester,
  Finder finder, {
  AppearanceStyle? style,
}) {
  final double minimum = (style ?? mkviStyleOf(tester)).hitTargetMin;
  final Size size = tester.getSize(finder);
  expect(
    size.shortestSide,
    greaterThanOrEqualTo(minimum - 0.01),
    reason:
        'hit target is ${size.width.toStringAsFixed(1)}x'
        '${size.height.toStringAsFixed(1)}, short side below '
        '${minimum.toStringAsFixed(1)} dp',
  );
}

/// Fail when the pumped tree reported a layout overflow.
///
/// A `FlutterError` during layout does not fail a widget test on its own in
/// every configuration, and an overflow is exactly the class of defect that
/// shipped in 0.1.x in every screen, so this belongs at the end of every one.
void expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

/// What a screen reader would announce for one operable control.
///
/// [spoken] is the **actual** announcement and nothing else. A failure message
/// like "(dugme - etiketsiz)" does NOT belong in it: that would make [spoken]
/// non-empty for an unlabelled control, so an assertion of the form "every
/// control has something to read out" could then NEVER fail.
///
/// That is not hypothetical. This helper did exactly that until 2026-09-26:
/// it reported 22 named controls and then refused to go red on a
/// deliberately nameless one. The kind travels in [type] instead, where a
/// failure message can use it and [spoken] stays honest.
typedef ControlReading = ({String type, String spoken});

/// Every operable control in the pumped tree, with what a screen reader would
/// read out for it.
///
/// This is the accessibility floor `ROADMAP.md` sets after 0.1.x shipped 17
/// WCAG violations, expressed as something a test can fail on: a control the
/// user cannot hear is not a control, and a widget test that never asks about
/// semantics cannot tell "labelled" from "painted".
///
/// Returns the readings rather than asserting, so a screen can decide what
/// "labelled enough" means for itself; [expectEveryControlLabelled] is the
/// strict form.
Future<List<ControlReading>> readControlLabels(WidgetTester tester) async {
  // Iki sey 2026-09-26'da bir saat tuttu ve IKISI DE OLCULDU, tahmin
  // edilmedi:
  //
  // 1. KOK `renderViews.first.owner` -- `rootPipelineOwner` DEGIL.
  //    `binding.rootPipelineOwner` bir `_DefaultRootPipelineOwner` ve onun
  //    `semanticsOwner`'i null. Onu yuruyunce agac BOS doner ve uygulamanin
  //    hicbir kontrolunu sayilmaz -- yani bir erisilebilirlik kontrolunun
  //    GECMEZ YONUNDE hatasi. Her view kendi agacina sahip ve test
  //    binding'inde tek view var.
  // 2. HANDLE TEST BITMEDEN BIRAKILMALI, `addTearDown` DEGIL.
  //    `addTearDown`, `WidgetTester._verifySemanticsHandlesWereDisposed`
  //    CALISTIKTAN SONRA kosar. Yani bu yardimciyi cagiran her test, bir
  //    widget'a bakmadan "A SemanticsHandle was active at the end of the test"
  //    ile kirmiziya donuyordu. Satir ici kapatmak guvenli: asagidaki
  //    yuruyus senkron.
  final SemanticsHandle handle = tester.ensureSemantics();
  try {
    // `ensureSemantics` agaci kirletir; `debugSemantics` paint sirasinda
    // yazilir. Bir pump dugumleri uretir, ikincisi boyar ve arada
    // okumak bos agac doner.
    await tester.pump();
    await tester.pump();

    final SemanticsNode? root =
        tester.binding.renderViews.first.owner?.semanticsOwner
            ?.rootSemanticsNode;
    if (root == null) return const <ControlReading>[];

    // Widget agacini degil SEMANTIK agacini yuruyun ve her daldaki EN DIS
    // denetlenebilir dugumu bir kez alin. Ekran okuyucunun yurudugu agac
    // budur, yani cevap burada tanimlidir: widget agacini yuruyunce bir
    // Material dugmesi uc kez sayilir (dugme, `InkWell`, `GestureDetector`)
    // ve `TextField` hic sayilmaz, cunku etiketini tasiyan dugum o widgetin
    // sahibi degildir.
    final List<ControlReading> readings = <ControlReading>[];
    final Set<SemanticsNode> visited = <SemanticsNode>{};

    void walk(SemanticsNode node) {
      if (!visited.add(node)) return;
      final SemanticsData data = node.getSemanticsData();
      if (_isOperable(data)) {
        // Alt agacin kelimelerini topla, ama baska bir denetlenebilir
        // dugume INME: isimli bir satirin icindeki `Radio` ikinci bir adsiz
        // kontrol degil, o satirin bir parcasidir.
        final List<String> parts = <String>[];
        _takeWords(data, parts);
        node.visitChildren((SemanticsNode child) {
          if (_isOperable(child.getSemanticsData())) return true;
          _takeWords(child.getSemanticsData(), parts);
          walk(child);
          return true;
        });
        readings.add((type: _describeKind(data), spoken: parts.join(' · ')));
        return;
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

/// A stable name for the kind of control, for a failure message.
///
/// The widget type is the wrong thing to print here: the node that carries the
/// role is often a bare `Semantics`, so a message reading "unlabelled:
/// Semantics" tells the next agent nothing. The role does.
String _describeKind(SemanticsData data) {
  final SemanticsFlags flags = data.flagsCollection;
  if (flags.isTextField) return 'metin alanı';
  if (flags.isButton) return 'düğme';
  if (flags.isSlider) return 'kaydırıcı';
  if (flags.isLink) return 'bağlantı';
  if (flags.isChecked != CheckedState.none) return 'anahtar';
  return 'denetlenebilir öğe';
}

void _takeWords(SemanticsData data, List<String> parts) {
  for (final String value in <String>[data.label, data.hint, data.tooltip]) {
    if (value.isNotEmpty && !parts.contains(value)) parts.add(value);
  }
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

/// Fail unless every operable control has something to read out.
///
/// [allowUnlabelled] names the controls a screen has declared exempt, so an
/// exemption is a sentence in a test rather than an omission.
Future<void> expectEveryControlLabelled(
  WidgetTester tester, {
  Set<String> allowUnlabelled = const <String>{},
}) async {
  final List<ControlReading> unlabelled = (await readControlLabels(tester))
      .where((ControlReading r) {
        if (r.spoken.isNotEmpty) return false;
        return !allowUnlabelled.contains(r.type);
      })
      .toList();
  expect(
    unlabelled,
    isEmpty,
    reason:
        'bu denetlenebilir öğelerin okunacak bir adı yok: '
        '${unlabelled.map((ControlReading r) => r.type).join(', ')}',
  );
}
