/// The type scale: the slider, and a sample at both ends of the range.
///
/// ## What this section is for
///
/// `ROADMAP.md` Faz 2:
///
/// > **Ölçek/yoğunluk her yerde** (0.1.x'te `fontScale` ilk ekranlarda etkisizdi).
///
/// The old build's defect was not that the slider was missing — it was that
/// moving it changed one element, because every other rule on the screen used
/// its own literal. `AppearanceResolver` removed the second place a size could
/// hide in ([AppearanceStyle.typeScale] is the only source, already multiplied
/// by `fontScale`), and this section is where that is *visible*: the two sample
/// lines paint at `style.styleOf('sm')` and `style.styleOf('lg')`, so a test can
/// read their `fontSize` and compare it with the resolved type step. If the app
/// ever grows a second font-size source, these two lines stop tracking the
/// slider and `type_scale_test.dart` goes red.
///
/// ## Both ends, deliberately
///
/// The small end is the step a list row uses and the large end is the step a
/// heading uses, because a type scale that is only ever shown at one size cannot
/// tell the user what the ends do. Both lines are inside the same card as the
/// slider, so the whole claim fits on one screen at 400 dp as well as at 1280.
///
/// ## The numbers are not written here
///
/// The range and the step come from `AppearanceSettings.minFontScale`,
/// `maxFontScale` and `fontScaleStep`, and the percentages come from
/// `SettingsCatalog.fontScaleValue`. A literal `1.25` in this file would be a
/// second source of truth for the very thing the slider is about.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'appearance_section.dart' show SettingsCard;
import 'settings_strings.dart';

/// The keys the parts of the type scale section answer to.
abstract final class TypeScaleKeys {
  /// The card the slider and the sample share.
  static const Key card = Key('mkvi.settings.typeScale.card');

  /// The block under the slider.
  static const Key sample = Key('mkvi.settings.typeScale.sample');

  /// The small end of the sample: the step a list row paints with.
  static const Key sampleSmall = Key('mkvi.settings.typeScale.sampleSmall');

  /// The large end of the sample: the step a heading paints with.
  static const Key sampleLarge = Key('mkvi.settings.typeScale.sampleLarge');
}

/// The type scale slider and its two-ended sample.
class TypeScaleSection extends StatelessWidget {
  /// Creates the section over [controller].
  const TypeScaleSection({super.key, required this.controller});

  /// The state this screen shows and changes. Never written to directly.
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final SettingsCatalog catalog = controller.catalog;
    return SettingsCard(
      key: TypeScaleKeys.card,
      resting: MkviRestingSurface.surface,
      title: SettingsUiTr.typeScaleSection.tr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // `MergeSemantics` around the slider row, and the reason is a
          // measurement: `MkviSliderRow` renders its label as a `Semantics
          // (header: true)` **sibling** of the `Slider`, and Material's `Slider`
          // names nothing itself, so the control's own semantics node has an
          // empty label and a screen reader announces a nameless slider.
          //
          // Merging puts the label and the slider's role and value on one node,
          // which is what Material's own `ListTile`-with-a-control does. The fix
          // belongs inside `MkviSliderRow` (reported against
          // `app/lib/ui/widgets/mkvi_choice.dart`); until then the screen that
          // ships the slider is the layer that has to name it.
          MergeSemantics(
            child: MkviSliderRow(
              label: catalog.fontScaleLabel,
              // From the preference that owns the range, not from this file.
              value: controller.appearance.fontScale,
              min: AppearanceSettings.minFontScale,
              max: AppearanceSettings.maxFontScale,
              step: AppearanceSettings.fontScaleStep,
              valueLabel: catalog.fontScaleValue,
              minLabel: catalog.fontScaleMinimumLabel,
              maxLabel: catalog.fontScaleMaximumLabel,
              // The one path from this screen to the state layer, so the resolved
              // appearance is rebuilt before the next frame is drawn.
              onChanged: controller.setFontScale,
            ),
          ),
          SizedBox(height: style.gap('3')),
          _TypeScaleSample(),
        ],
      ),
    );
  }
}

/// Two lines of Turkish copy, painted at the smallest and the largest step.
class _TypeScaleSample extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Column(
      key: TypeScaleKeys.sample,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            SettingsUiTr.typeScaleSampleLabel.tr,
            style: style.styleOf('2xs').copyWith(color: style.role('textMuted')),
          ),
        ),
        SizedBox(height: style.gap('1')),
        // `styleOf` and nothing else: the size is `type.steps[step] *
        // fontScale`, so this line is the measurement of the user's choice.
        Text(
          SettingsUiTr.typeScaleSampleSmall.tr,
          key: TypeScaleKeys.sampleSmall,
          style: style.styleOf('sm').copyWith(color: style.role('text')),
        ),
        SizedBox(height: style.gap('1')),
        Text(
          SettingsUiTr.typeScaleSampleLarge.tr,
          key: TypeScaleKeys.sampleLarge,
          style: style.styleOf('lg').copyWith(color: style.role('text')),
        ),
      ],
    );
  }
}
