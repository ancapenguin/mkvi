/// The choice controls: a radio row, a switch row, a slider row and a segmented
/// row, plus the surface rule that decides which of them get an edge.
///
/// ## The surface rule (ROADMAP.md, Faz 2)
///
/// > An accent-filled button takes a `borderStrong` edge on a raised surface.
/// > Every accent-filled button stands on `bg`/`surface`, and takes an edge on
/// > `surfaceRaised`/`surfaceSoft`. This is an interface rule, not a token rule:
/// > a token test cannot measure it.
///
/// A token test cannot measure it because the *placement* is a fact about the
/// widget tree, not about `tokens.json` - so it is a parameter here
/// ([MkviRestingSurface]) and a testable property: [MkviSegmentedRow] on
/// [MkviRestingSurface.surface] paints no edge, and on
/// [MkviRestingSurface.raised] paints a `borderStrong` edge at
/// `style.borderWidth`. The reason it matters is contrast, not decoration: an
/// accent fill on `surfaceRaised` is a shape the eye has to find, and in the
/// themes where the fill and the raised step are close, the fill reads as a
/// smudge until it has an edge.
///
/// ## Why the colours here are set and not inherited
///
/// `ThemeData` fills the switch, the list tile, the divider and the text theme,
/// but it does NOT fill `radioTheme`, `sliderTheme` or a segmented control -
/// Material's defaults for those are computed from `ColorScheme`, i.e. from
/// colours the contrast gate has never measured. So every colour in this file
/// is read from a role, and every one of them is a value a test can compare
/// against [AppearanceStyle.role].
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

/// Keys for the parts of the choice controls.
abstract final class MkviChoiceKeys {
  /// The [Slider] itself.
  static const Key slider = Key('mkvi.choice.slider');

  /// The area around the [Slider], which is what the hit target is measured on.
  static const Key sliderTarget = Key('mkvi.choice.sliderTarget');

  /// The segmented control.
  static const Key segmented = Key('mkvi.choice.segmented');

  /// The box around the segments, which carries the surface rule's edge.
  static const Key segmentedBorder = Key('mkvi.choice.segmentedBorder');

  /// The nth option row.
  static Key row(int index) => Key('mkvi.choice.row.$index');

  /// The nth switch row.
  static Key switchRow(int index) => Key('mkvi.choice.switch.$index');

  /// The nth segment.
  static Key segment(int index) => Key('mkvi.choice.segment.$index');
}

/// The surface an accent-filled control is standing on.
///
/// The four values are the four roles a control can rest on, and the split is
/// the ROADMAP rule: [background] and [surface] are the page and the plain
/// card, so an accent fill has nothing to compete with; [raised] and [soft] are
/// one step away from the accent in at least one theme, so a fill there needs
/// an edge to be seen at all.
enum MkviRestingSurface {
  /// `bg`: the page behind everything.
  background('bg'),

  /// `surface`: a plain card.
  surface('surface'),

  /// `surfaceRaised`: a card, a panel or a row on top of one.
  raised('surfaceRaised'),

  /// `surfaceSoft`: a well, a field or an input.
  soft('surfaceSoft');

  const MkviRestingSurface(this.roleName);

  /// The token role this surface is painted with.
  final String roleName;

  /// Whether an accent-filled control here must take a `borderStrong` edge.
  bool get needsBorder => this == MkviRestingSurface.raised ||
      this == MkviRestingSurface.soft;
}

/// One single-choice option: a value, its Turkish label and its explanation.
///
/// A bare `T` is not enough: the settings screen renders a list of
/// [ThemePreference]s and a list of [DensityPreference]s from the SAME widget,
/// and the only thing that distinguishes them on screen is the label. Carrying
/// the label as data is what keeps that widget free of a per-enum branch, and
/// it is why there is no English default anywhere in this layer.
class MkviOptionRow<T> extends StatelessWidget {
  /// Creates one option of a single-choice list.
  const MkviOptionRow({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.label,
    this.description,
    this.enabled = true,
  });

  /// What choosing this row means.
  final T value;

  /// What is chosen now, from the enclosing [RadioGroup].
  final T? groupValue;

  /// Called with [value] when the row is chosen. Nullable because
  /// [RadioGroup.onChanged] is, and it hands back null when a toggleable radio
  /// is un-selected.
  final ValueChanged<T?> onChanged;

  /// The row's name. Turkish, from the screen.
  final String label;

  /// What the row does. Turkish, from the screen.
  final String? description;

  /// Whether the row can be chosen.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final ResolvedControl md = style.control('md');
    // A row that is not inside a group yet creates one, so a bare row works on
    // its own. A row that IS inside one uses that group - which is what gives
    // the arrow-key navigation between options that per-row groups would
    // destroy.
    final RadioGroupRegistry<T>? group = RadioGroup.maybeOf<T>(context);

    Widget row = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: enabled
            ? () => (group?.onChanged ?? onChanged)(value)
            : null,
        borderRadius: BorderRadius.circular(style.radius('sm')),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: style.hitTargetMin),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: style.gap('4'),
              vertical: style.gap('2'),
            ),
            child: Row(
              children: <Widget>[
                Radio<T>(
                  value: value,
                  enabled: enabled,
                  fillColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) {
                      if (states.contains(WidgetState.disabled)) {
                        return style.role('surfaceSoft');
                      }
                      return states.contains(WidgetState.selected)
                          ? style.role('accent')
                          : style.role('surfaceRaised');
                    },
                  ),
                  backgroundColor: WidgetStatePropertyAll<Color?>(
                    style.role('surface'),
                  ),
                  side: BorderSide(
                    color: style.role('borderStrong'),
                    width: style.borderWidth,
                  ),
                  overlayColor: WidgetStatePropertyAll<Color?>(
                    style.role('accentSoft'),
                  ),
                ),
                SizedBox(width: md.gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: style.styleOf('sm').copyWith(
                          color: style.role('text'),
                        ),
                      ),
                      if (description != null)
                        Text(
                          description!,
                          style: style.styleOf('2xs').copyWith(
                            color: style.role('textMuted'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (group == null) {
      row = RadioGroup<T>(
        groupValue: groupValue,
        onChanged: onChanged,
        child: row,
      );
    }
    return row;
  }
}

/// One on/off choice: a [SwitchListTile] whose colours are token roles.
class MkviSwitchRow extends StatelessWidget {
  /// Creates an on/off row.
  const MkviSwitchRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
    this.enabled = true,
  });

  /// Whether this choice is on.
  final bool value;

  /// Called with the new state.
  final ValueChanged<bool> onChanged;

  /// The row's name. Turkish, from the screen.
  final String label;

  /// What the row does. Turkish, from the screen.
  final String? description;

  /// Whether the row can be changed.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final ResolvedControl md = style.control('md');
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: style.hitTargetMin),
      child: SwitchListTile(
        value: value,
        onChanged: enabled ? onChanged : null,
        title: Text(
          label,
          style: style.styleOf('sm').copyWith(color: style.role('text')),
        ),
        subtitle: description == null
            ? null
            : Text(
                description!,
                style: style.styleOf('2xs').copyWith(
                  color: style.role('textMuted'),
                ),
              ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: md.paddingX,
          vertical: style.gap('1'),
        ),
        // Spelled out rather than inherited: `switchTheme` sets the same four
        // roles today, and a test that reads the widget measures THIS control
        // rather than whatever the theme happens to say.
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? style.role('textOnAccent')
              : style.role('textSubtle'),
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? style.role('accent')
              : style.role('border'),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? style.role('accentActive')
              : style.role('borderStrong'),
        ),
      ),
    );
  }
}

/// One stepped value: a label, the value as Turkish text, and a [Slider].
///
/// [valueLabel] is a function, not a format string, because the one thing this
/// row is used for is a scale whose unit is a token - `%90`, `%125` - and a
/// format string would be a place where a second, unscaled copy of that unit
/// could grow.
class MkviSliderRow extends StatelessWidget {
  /// Creates a stepped value row.
  const MkviSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.valueLabel,
    this.description,
    this.minLabel,
    this.maxLabel,
    this.onChanged,
  });

  /// The row's name. Turkish, from the screen.
  final String label;

  /// The value now, in [min]..[max].
  final double value;

  /// The smallest value the row offers. From the token file or the preference
  /// that owns it, never from this widget.
  final double min;

  /// The largest value the row offers.
  final double max;

  /// The step the value snaps to.
  final double step;

  /// The value as Turkish text, and the same text as the slider's label and its
  /// screen-reader announcement.
  final String Function(double value) valueLabel;

  /// What the row changes. Turkish, from the screen.
  final String? description;

  /// The name of [min]. Turkish, from the screen.
  final String? minLabel;

  /// The name of [max]. Turkish, from the screen.
  final String? maxLabel;

  /// Called with the new value.
  final ValueChanged<double>? onChanged;

  /// How many stops the slider has, from [min], [max] and [step].
  ///
  /// `divisions` is what makes the value snap: without it a slider hands back
  /// whatever the pointer landed on, and a 0.05 step stored as 0.0833 is a
  /// setting the codec then has to report as corrected.
  int get divisions {
    if (step <= 0 || max <= min) return 0;
    return ((max - min) / step).round();
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final double clamped = value.clamp(min, max).toDouble();
    final String text = valueLabel(clamped);
    final int stops = divisions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  label,
                  style: style.styleOf('sm').copyWith(color: style.role('text')),
                ),
              ),
            ),
            Text(
              text,
              style: style.styleOf('sm').copyWith(color: style.role('accent')),
            ),
          ],
        ),
        if (description != null) ...<Widget>[
          SizedBox(height: style.gap('1')),
          Text(
            description!,
            style: style.styleOf('2xs').copyWith(color: style.role('textMuted')),
          ),
        ],
        SizedBox(height: style.gap('2')),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (minLabel != null)
              Text(
                minLabel!,
                style: style
                    .styleOf('2xs')
                    .copyWith(color: style.role('textMuted')),
              ),
            Expanded(
              child: ConstrainedBox(
                key: MkviChoiceKeys.sliderTarget,
                constraints: BoxConstraints(minHeight: style.hitTargetMin),
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: style.role('accent'),
                    inactiveTrackColor: style.role('border'),
                    thumbColor: style.role('accent'),
                    overlayColor: style.role('accentSoft'),
                  ),
                  child: Slider(
                    key: MkviChoiceKeys.slider,
                    value: clamped,
                    min: min,
                    max: max,
                    divisions: stops < 1 ? null : stops,
                    label: text,
                    semanticFormatterCallback: valueLabel,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
            if (maxLabel != null)
              Text(
                maxLabel!,
                style: style
                    .styleOf('2xs')
                    .copyWith(color: style.role('textMuted')),
              ),
          ],
        ),
      ],
    );
  }
}

/// A small set of mutually exclusive choices, side by side.
///
/// The selected segment is an accent fill with `textOnAccent` on it, which is
/// the only accent fill in this layer and therefore the only one the surface
/// rule applies to.
class MkviSegmentedRow<T> extends StatelessWidget {
  /// Creates a segmented control.
  const MkviSegmentedRow({
    super.key,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
    this.resting = MkviRestingSurface.surface,
  });

  /// The choices, in the order they are shown.
  final List<T> values;

  /// Which one is chosen now.
  final T? selected;

  /// The name of a choice. Turkish, from the screen.
  final String Function(T value) labelFor;

  /// Called with the newly chosen value.
  final ValueChanged<T> onChanged;

  /// Which surface this control is standing on, and therefore whether the
  /// accent fill takes a `borderStrong` edge.
  final MkviRestingSurface resting;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final ResolvedControl md = style.control('md');
    final bool bordered = resting.needsBorder;

    return Container(
      key: MkviChoiceKeys.segmentedBorder,
      padding: EdgeInsets.all(
        bordered ? style.borderWidth : style.gap('0'),
      ),
      decoration: BoxDecoration(
        // No fill: the control rests on the surface it was told about, and
        // painting over it would hide the very thing the rule is about.
        border: bordered
            ? Border.all(
                color: style.role('borderStrong'),
                width: style.borderWidth,
              )
            : null,
        borderRadius: style.shape('md').borderRadius,
      ),
      child: Row(
        key: MkviChoiceKeys.segmented,
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          for (int index = 0; index < values.length; index += 1)
            Expanded(
              child: _segment(
                style,
                md,
                values[index],
                index,
                index == values.length - 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _segment(
    AppearanceStyle style,
    ResolvedControl md,
    T value,
    int index,
    bool last,
  ) {
    final bool isSelected = value == selected;
    return Padding(
      padding: EdgeInsets.only(right: last ? 0.0 : style.gap('1')),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(style.radius('sm')),
          child: Semantics(
            button: true,
            selected: isSelected,
            label: labelFor(value),
            child: Container(
              key: MkviChoiceKeys.segment(index),
              constraints: BoxConstraints(
                minHeight: style.hitTargetMin,
                minWidth: md.paddingX,
              ),
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(
                horizontal: style.gap('2'),
                vertical: style.gap('1'),
              ),
              decoration: BoxDecoration(
                // The unselected segment is the surface the control rests on,
                // not a second fill: an accent fill next to another fill is
                // what the surface rule is about.
                color: isSelected
                    ? style.role('accent')
                    : style.role(resting.roleName),
                borderRadius: style.shape('sm').borderRadius,
              ),
              // The label is named once, by the button above, so a screen
              // reader says "Sıkışık, selected" rather than both twice.
              child: ExcludeSemantics(
                child: Text(
                  labelFor(value),
                  maxLines: 1,
                  // A segmented control is a fixed set of fixed cells; a label
                  // that does not fit is elided, and the accessible name above
                  // is the whole label.
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: style.styleOf('sm').copyWith(
                    color: isSelected
                        ? style.role('textOnAccent')
                        : style.role('text'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
