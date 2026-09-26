/// The density: two choices, and a list of sample rows that shows the difference.
///
/// ## Why the sample rows are not decoration
///
/// `density` was honoured in 8 call sites out of ~40 in 0.1.x, because it was a
/// value nobody was obliged to read. The state layer fixed the cause — one
/// resolved `space` map — but a picker that only says "Sıkışık" or "Rahat" asks
/// the user to take the word for it. The three rows under the picker are laid
/// out with `style.gap('2')` between them and `style.gap('4')` inside one, so
/// the difference is *visible* and, more usefully, **measurable**:
/// `density_section_test.dart` reads the gap between two rows at `compact` and
/// at `comfortable` and fails if they are equal.
///
/// ## Two densities, not three
///
/// `design/tokens.json` declares three (`compact`, `cozy`, `roomy`) and
/// `DensityPreference` exposes two, so this section offers the two the state
/// layer can store. Adding `roomy` is a change to `app/lib/settings/`, which
/// this screen does not own; the moment the enum has a third value, the
/// `for` loop below picks it up with no change here, and `mkviScaleMatrix()`
/// widens from six combinations to nine on its own. A screen that hard-coded
/// two options would be the thing that has to be remembered.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'appearance_section.dart' show SettingsCard, SettingsChoiceGroup;
import 'settings_strings.dart';

/// The keys the parts of the density section answer to.
abstract final class DensityKeys {
  /// The `surface` card the picker and the sample share.
  static const Key card = Key('mkvi.settings.density.card');

  /// The sample block under the picker.
  static const Key sample = Key('mkvi.settings.density.sample');

  /// The nth sample row.
  static Key row(int index) => Key('mkvi.settings.density.row.$index');

  /// The name inside sample row [index].
  static Key rowName(int index) => Key('mkvi.settings.density.rowName.$index');

  /// The secondary line inside sample row [index].
  static Key rowDetail(int index) =>
      Key('mkvi.settings.density.rowDetail.$index');
}

/// The density picker and the rows that show what it does.
class DensitySection extends StatelessWidget {
  /// Creates the section over [controller].
  const DensitySection({super.key, required this.controller});

  /// The state this screen shows and changes. Never written to directly.
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final SettingsCatalog catalog = controller.catalog;
    return SettingsCard(
      key: DensityKeys.card,
      // `surface`, not the panel's `surfaceRaised`: a step down reads as a
      // well, and `surface` is the surface the ROADMAP rule says a filled
      // control may stand on WITHOUT a `borderStrong` edge. This section is
      // where that half of the rule is shipped rather than only tested.
      resting: MkviRestingSurface.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsChoiceGroup<DensityPreference>(
            controller: controller,
            label: catalog.densityLabel,
            layout: MkviChoiceLayout.segmented,
            resting: MkviRestingSurface.surface,
            selectionOf: (SettingsController c) => <DensityPreference>{
              c.appearance.density,
            },
            onDidChange: (
              Set<DensityPreference> _,
              Set<DensityPreference> next,
            ) => controller.setDensity(next.first),
            options: <MkviChoiceOption<DensityPreference>>[
              // Over `DensityPreference.values`, not a list of two: a third
              // density in the enum appears here without a change to this file.
              for (final DensityPreference density in DensityPreference.values)
                MkviChoiceOption<DensityPreference>(
                  value: density,
                  label: catalog.densityOptionLabel(density),
                ),
            ],
          ),
          SizedBox(height: style.gap('2')),
          Text(
            catalog.densityDescription,
            style: style.styleOf('2xs').copyWith(color: style.role('textMuted')),
          ),
          SizedBox(height: style.gap('3')),
          const _DensitySample(),
        ],
      ),
    );
  }
}

/// Three rows whose gaps are the resolved `space` steps, and nothing else.
class _DensitySample extends StatelessWidget {
  const _DensitySample();

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Column(
      key: DensityKeys.sample,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            SettingsUiTr.densitySampleLabel.tr,
            style: style.styleOf('2xs').copyWith(color: style.role('textMuted')),
          ),
        ),
        SizedBox(height: style.gap('2')),
        for (int index = 0; index < 3; index += 1) ...<Widget>[
          if (index > 0) SizedBox(height: style.gap('2')),
          Padding(
            key: DensityKeys.row(index),
            padding: EdgeInsets.symmetric(vertical: style.gap('1')),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  SettingsUiTr.densitySampleName.tr,
                  key: DensityKeys.rowName(index),
                  style: style.styleOf('sm').copyWith(
                    color: style.role('text'),
                  ),
                ),
                SizedBox(height: style.gap('1')),
                Text(
                  SettingsUiTr.densitySampleDetail.tr,
                  key: DensityKeys.rowDetail(index),
                  style: style.styleOf('2xs').copyWith(
                    color: style.role('textMuted'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
