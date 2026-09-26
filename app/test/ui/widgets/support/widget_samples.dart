/// The copy and the bounded screens the widget tests in this directory lay out.
///
/// Two things live here on purpose:
///
/// * **Turkish copy that is long.** 0.1.x's clipping and overflow only showed up
///   at the sizes nobody tested, so every sample here is laid out in a 320 dp
///   column — a phone width, and far narrower than the 1280 dp window the
///   harness sets — with strings long enough to have to wrap several times.
/// * **A column, not the whole window.** `pumpMkvi` hands the widget under test
///   the full 1280x800 surface, so a `Row` in a sample would never overflow no
///   matter how broken it is. [mkviSample] is what makes an overflow possible,
///   and therefore what makes `expectNoOverflow` mean something.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

/// Hands the resolved [AppearanceStyle] to [onStyle] from a real `build`.
///
/// ## Why this exists instead of `mkviStyleOf`
///
/// `mkviStyleOf` walks `tester.allElements` and calls `Theme.of` on each one it
/// finds, which registers an inherited-widget dependency from *outside* a build.
/// That is harmless in a test that pumps once, and it is a landmine in a test
/// that pumps twice: the next `pumpWidget` walks the stale dependents, one of
/// them is no longer a descendant, and the framework throws
/// `Failed assertion: check that it really is our descendant` from
/// `InheritedElement.notifyClients` — with a `MaterialApp` and a duplicate
/// `Navigator` GlobalKey in the message, and nothing in it that names the cause.
///
/// A matrix test has to read the palette after *every* pump, so it reads it from
/// here, which is a build context and therefore the only legal place to read it.
class MkviStyleProbe extends StatelessWidget {
  /// Wraps [child] and reports the style it is painted with.
  const MkviStyleProbe({
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

/// Turkish wording the samples use, so no test invents a string the app has no
/// way to produce.
abstract final class SampleTr {
  /// A panel heading.
  static const String panelTitle = 'Kayıtlı eşler';

  /// A panel subheading, long enough to wrap in the sample column.
  static const String panelSubtitle =
      'Bu cihazda daha önce eşleştiğin kayıtlar ve süresi dolmuş eşleşme istekleri.';

  /// A paragraph for a panel body, long enough to fill four lines.
  static const String panelBody =
      'MKVI eşleşmeyi tek kullanımlık kodla yapar ve anahtarı bu cihazda tutar. '
      'Sunucuda hiçbir içerik saklanmaz, aktarım doğrudan iki cihaz arasındadır.';

  /// The primary action's label.
  static const String primaryAction = 'Kaydet';

  /// The secondary action's label.
  static const String secondaryAction = 'Yenile';

  /// A section heading.
  static const String sectionTitle = 'Bağlantı';

  /// A section description.
  static const String sectionDescription =
      'Eşleştiğin cihazla güvenli bağlantının kurulma biçimi.';

  /// A key/value label.
  static const String keyLabel = 'Eş parmak izi';

  /// A key/value value: a hexadecimal fingerprint, i.e. a long unbroken token,
  /// which is the case that clipped a row in 0.1.x.
  static const String keyValue =
      '9f2c41ab77de0359c1e5a4b60d8f3172e4a9b6c05';

  /// A second key/value pair.
  static const String keyLabel2 = 'Son bağlantı';

  /// A second value.
  static const String keyValue2 = 'Bugün, 14:32';

  /// An empty state's headline.
  static const String emptyTitle = 'Arama sonucu yok';

  /// An empty state's sentence.
  static const String emptyDescription =
      'Bu filtreye uyan bir mesaj yok. Filtreyi değiştirip yeniden dene.';

  /// An error block's headline.
  static const String errorTitle = 'Kayıtlı eş açılamadı';

  /// An error block's cause: what went wrong.
  static const String errorReason =
      'Anahtar kasasındaki kayıt okunamadı: beklenen biçimde değil.';

  /// An error block's recovery: what the user can do about it.
  static const String errorMessage =
      'Tekrar dene. Sorun sürerse yeni bir cihaz eşle.';

  /// A badge label.
  static const String badgeLabel = 'Eşleşti';

  /// A longer badge label, for the step-up variant.
  static const String badgeLabelLong = 'Şifreli aktarım';

  /// A progress bar's accessible name.
  static const String progressLabel = 'Dosya aktarılıyor';

  /// A determinate transfer, as a fraction.
  static const double progressValue = 0.4;

  /// A sweep position for the indeterminate bar.
  static const double progressPhase = 0.25;

  /// A quarter turn, for the ring.
  static const double ringQuarterTurn = 0.25;
}

/// A 320 dp column, so a wrapping string has to wrap and a `Row` has to fit.
///
/// 320 dp is a phone width and nothing in this app ships on one, which is the
/// point: it is the narrowest column a window can be resized to that still holds
/// a panel, and it is where a header with two Turkish action labels runs out of
/// room.
///
/// The [DefaultTextStyle] is not decoration. `pumpMkvi` puts the widget under
/// test straight into a `MaterialApp` with no `Scaffold` and therefore no
/// `Material` and no ambient text style above it, and a bare `Text` in that
/// position picks up Flutter's *error* text style — 48 dp monospace, red,
/// double-underlined. A sample built that way measures nothing real, and an
/// overflow matrix built on it is testing a font the app will never use. A real
/// screen is always under a `Scaffold`, which is where this style comes from.
Widget mkviSample(Widget child, {double width = 320}) {
  return Builder(
    builder: (BuildContext context) {
      final AppearanceStyle style = AppearanceStyle.of(context);
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: DefaultTextStyle(
            style: style.textTheme.bodyMedium!,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[child],
            ),
          ),
        ),
      );
    },
  );
}

/// A panel of [variant] with a heading, both actions and a paragraph.
Widget mkviPanelSample(MkviPanelVariant variant) {
  final List<MkviPanelAction> actions = <MkviPanelAction>[
    MkviPanelAction(
      label: SampleTr.primaryAction,
      onPressed: () {},
      filled: true,
    ),
    MkviPanelAction(label: SampleTr.secondaryAction, onPressed: () {}),
  ];
  final Widget body = const Text(SampleTr.panelBody);
  return switch (variant) {
    MkviPanelVariant.raised => MkviPanel.raised(
      title: SampleTr.panelTitle,
      subtitle: SampleTr.panelSubtitle,
      actions: actions,
      child: body,
    ),
    MkviPanelVariant.soft => MkviPanel.soft(
      title: SampleTr.panelTitle,
      subtitle: SampleTr.panelSubtitle,
      actions: actions,
      child: body,
    ),
    MkviPanelVariant.flat => MkviPanel.flat(
      title: SampleTr.panelTitle,
      subtitle: SampleTr.panelSubtitle,
      actions: actions,
      child: body,
    ),
  };
}

/// A heading with a filled action, two label/value rows and a hairline.
Widget mkviSectionSample() {
  return MkviSectionHeader(
    title: SampleTr.sectionTitle,
    description: SampleTr.sectionDescription,
    actions: <MkviPanelAction>[
      MkviPanelAction(label: SampleTr.primaryAction, onPressed: () {}, filled: true),
    ],
    trailing: MkviBadge(label: SampleTr.badgeLabel),
  );
}

/// Two label/value rows under a divider, which is the whole shape of a settings
/// list.
Widget mkviKeyValueSample() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const MkviKeyValueRow(label: SampleTr.keyLabel, value: SampleTr.keyValue),
      const MkviDivider(startIndentStep: '4'),
      const MkviKeyValueRow(
        label: SampleTr.keyLabel2,
        value: SampleTr.keyValue2,
      ),
    ],
  );
}

/// The two states, one after the other.
Widget mkviStateSample() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      MkviEmptyState(
        title: SampleTr.emptyTitle,
        description: SampleTr.emptyDescription,
        icon: Icons.search_off_rounded,
        actions: <MkviPanelAction>[
          MkviPanelAction(label: SampleTr.secondaryAction, onPressed: () {}),
        ],
      ),
      const MkviGap('4'),
      const MkviErrorState(
        title: SampleTr.errorTitle,
        reason: SampleTr.errorReason,
        message: SampleTr.errorMessage,
        actions: <MkviPanelAction>[],
      ),
    ],
  );
}

/// One badge of every tone, plus the step-up variant.
Widget mkviBadgeSample() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (final MkviBadgeTone tone in MkviBadgeTone.values)
        MkviBadge(label: SampleTr.badgeLabel, tone: tone),
      MkviBadge(
        label: SampleTr.badgeLabelLong,
        tone: MkviBadgeTone.success,
        dense: false,
      ),
    ],
  );
}

/// A determinate bar, an indeterminate bar, a determinate ring and an
/// indeterminate ring.
Widget mkviProgressSample() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      MkviLinearProgress(
        value: SampleTr.progressValue,
        label: SampleTr.progressLabel,
      ),
      const MkviGap('3'),
      MkviLinearProgress(
        phase: SampleTr.progressPhase,
        label: SampleTr.progressLabel,
      ),
      const MkviGap('3'),
      const Row(
        children: <Widget>[
          MkviCircularProgress(value: SampleTr.progressValue),
          MkviGap('3', axis: Axis.horizontal),
          MkviCircularProgress(phase: SampleTr.ringQuarterTurn),
        ],
      ),
    ],
  );
}

/// A horizontal hairline with indents, a vertical one between two columns, and
/// both kinds of gap.
Widget mkviDividerSample() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      const MkviDivider(startIndentStep: '4', endIndentStep: '4'),
      const MkviGap('3'),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const <Widget>[
            Expanded(child: Text(SampleTr.keyLabel2)),
            MkviVerticalDivider(),
            Expanded(child: Text(SampleTr.keyValue2)),
          ],
        ),
      ),
      const MkviGap('3', axis: Axis.horizontal),
    ],
  );
}
