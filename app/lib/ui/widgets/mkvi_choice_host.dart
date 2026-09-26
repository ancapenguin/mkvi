/// The choice list as DATA, and the one widget that renders it.
///
/// ## Why a catalogue and not a widget per setting
///
/// The settings screen has a theme picker, an accent picker, a density picker,
/// a radius picker and four switches. Written naively that is five widget trees
/// that each know how to draw a label, a selection and a description, and they
/// drift: the density list gets a title the theme list does not, the switches
/// end up one gap tighter than the radios, and the Turkish wording for "what
/// does this do" ends up written five times.
///
/// So the options are a value - [MkviChoiceCatalog] with [MkviChoiceOption]
/// entries - and [MkviChoiceGroup] is the only thing that draws them. Three
/// consequences worth stating:
///
/// * **No default labels.** There is no English string anywhere in this layer
///   and no per-enum branch. A label is a required field of an option, so a
///   missing translation is a compile error rather than an empty segment.
/// * **One feedback path.** Every change goes through [MkviChoiceCatalog.didChange],
///   which is also how a screen that owns the value reports a change made
///   elsewhere. There is no second way for a selection to move, so no test has
///   to guess which one a tap used.
/// * **One list widget per layout.** [MkviChoiceLayout] picks between the row
///   list, the segmented control and the switch list; the options and the
///   Turkish text are identical in all three.
library;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

import 'mkvi_choice.dart';

/// One entry of a choice list: the value, its name and what it does.
final class MkviChoiceOption<T> {
  /// Creates one option. [label] and [description] are Turkish, from the
  /// screen; there is no default for either, which is the point.
  const MkviChoiceOption({
    required this.value,
    required this.label,
    this.description,
  });

  /// What choosing this option means.
  final T value;

  /// The option's name, as the user reads it.
  final String label;

  /// What the option does, in one sentence. Optional, not defaulted.
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is MkviChoiceOption<T> &&
      other.value == value &&
      other.label == label &&
      other.description == description;

  @override
  int get hashCode => Object.hash(value, label, description);

  @override
  String toString() => 'MkviChoiceOption($value, $label)';
}

/// How a choice list is drawn.
enum MkviChoiceLayout {
  /// A [MkviOptionRow] per option, with radio marks. Single choice.
  rows,

  /// One [MkviSegmentedRow] with a segment per option. Single choice, and only
  /// readable while there are few enough options to fit side by side.
  segmented,

  /// A [MkviSwitchRow] per option. Multiple choice.
  switches,
}

/// The options of one setting, and the one selection of it.
///
/// Immutable from the outside: [selection] is a copy, [options] is unmodifiable,
/// and the only way to change anything is [select], which goes through
/// [didChange]. A widget cannot paint a selection the catalogue does not hold.
final class MkviChoiceCatalog<T> extends ChangeNotifier {
  /// Creates a catalogue.
  ///
  /// [label] is the setting's name and every option's label is Turkish, all
  /// from the screen. [multiple] decides whether [select] replaces the
  /// selection or toggles one entry of it.
  MkviChoiceCatalog({
    required this.label,
    required List<MkviChoiceOption<T>> options,
    Set<T>? selection,
    this.multiple = false,
    this.onDidChange,
  }) : options = List<MkviChoiceOption<T>>.unmodifiable(options) {
    for (final MkviChoiceOption<T> option in this.options) {
      _values.add(option.value);
    }
    if (selection != null) {
      for (final T value in selection) {
        if (!_values.contains(value)) {
          throw StateError(
            'The initial selection of "$label" holds a value that is not one '
            'of its options: $value.',
          );
        }
      }
      _selection.addAll(selection);
    }
  }

  /// The setting's name. Turkish, from the screen.
  final String label;

  /// The options, in the order they are shown.
  final List<MkviChoiceOption<T>> options;

  /// Whether more than one option may be selected at a time.
  final bool multiple;

  /// Called after a change that changed something, with the selection before
  /// and after. The one feedback path a screen needs.
  void Function(Set<T> previous, Set<T> next)? onDidChange;

  final Set<T> _values = <T>{};
  final Set<T> _selection = <T>{};

  /// The selected values, as a copy: the caller cannot change the selection by
  /// mutating what it read.
  Set<T> get selection => Set<T>.unmodifiable(_selection);

  /// The single selected value, or null when nothing is selected or more than
  /// one is. A single-choice list can be empty - "no endpoint yet" is a state -
  /// so this is nullable on purpose.
  T? get value => _selection.length == 1 ? _selection.first : null;

  /// Whether [option]'s value is selected.
  bool isSelected(T value) => _selection.contains(value);

  /// The Turkish name of [value].
  ///
  /// Throws rather than returning an empty string: a value with no label would
  /// render a blank row, and a blank row is exactly the class of defect this
  /// catalogue exists to remove.
  String labelOf(T value) {
    for (final MkviChoiceOption<T> option in options) {
      if (option.value == value) return option.label;
    }
    throw StateError('No option of "$label" has the value $value.');
  }

  /// The Turkish explanation of [value], or null when it has none.
  String? descriptionOf(T value) {
    for (final MkviChoiceOption<T> option in options) {
      if (option.value == value) return option.description;
    }
    throw StateError('No option of "$label" has the value $value.');
  }

  /// Selects [value]: replacing the selection, or toggling it when [multiple].
  ///
  /// Throws for a value that is not one of [options], so a typo in a screen is
  /// a crash at the first tap rather than a row that silently does nothing.
  void select(T value) {
    if (!_values.contains(value)) {
      throw StateError('No option of "$label" has the value $value.');
    }
    if (!multiple) {
      didChange(_selection, <T>{value});
      return;
    }
    final Set<T> next = Set<T>.of(_selection);
    if (!next.remove(value)) next.add(value);
    didChange(_selection, next);
  }

  /// Publishes a new selection, to the listeners and to [onDidChange].
  ///
  /// Public because a screen that owns the value - an undo, a stored setting
  /// that was corrected, a reset - has to be able to drive the SAME feedback
  /// path a tap drives. A selection that did not change publishes nothing.
  void didChange(Set<T> previous, Set<T> next) {
    if (setEquals(previous, next)) return;
    _selection
      ..clear()
      ..addAll(next);
    notifyListeners();
    onDidChange?.call(
      Set<T>.unmodifiable(previous),
      Set<T>.unmodifiable(_selection),
    );
  }

  @override
  String toString() =>
      'MkviChoiceCatalog($label, ${options.length} options, '
      'selected: $_selection)';
}

/// Draws a [MkviChoiceCatalog] as a titled group of choices.
///
/// Rebuilds when the catalogue publishes, and nothing else: the catalogue is
/// the state, so a group cannot show a selection its data does not hold.
class MkviChoiceGroup<T> extends StatelessWidget {
  /// Creates a group over [catalog].
  ///
  /// [onChanged] is for a screen that wants to know about a change without
  /// owning the catalogue; the catalogue's own `onDidChange` is the other path
  /// and both are called for the same tap.
  MkviChoiceGroup({
    super.key,
    required this.catalog,
    this.layout = MkviChoiceLayout.rows,
    this.onChanged,
    this.resting = MkviRestingSurface.surface,
  }) : assert(
         layout != MkviChoiceLayout.switches || catalog.multiple,
         'A switch list is a multiple choice; a single-choice catalogue cannot '
         'be drawn as one, because a switch cannot express "none of these".',
       );

  /// The options and the selection.
  final MkviChoiceCatalog<T> catalog;

  /// How to draw them.
  final MkviChoiceLayout layout;

  /// Called after the user picks something.
  final ValueChanged<T>? onChanged;

  /// Which surface the control rests on, for [MkviChoiceLayout.segmented]. It
  /// decides whether the selected segment takes a `borderStrong` edge.
  final MkviRestingSurface resting;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: catalog,
      builder: (BuildContext context, Widget? _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _title(context),
            SizedBox(height: AppearanceStyle.of(context).gap('2')),
            switch (layout) {
              MkviChoiceLayout.rows => _rows(context),
              MkviChoiceLayout.segmented => _segmented(context),
              MkviChoiceLayout.switches => _switches(context),
            },
          ],
        );
      },
    );
  }

  Widget _title(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return Semantics(
      header: true,
      child: Text(
        catalog.label,
        style: style.styleOf('sm').copyWith(color: style.role('textMuted')),
      ),
    );
  }

  Widget _rows(BuildContext context) {
    // One group around all the rows, not one per row: the arrow keys move
    // between options, and a screen reader hears one list of choices instead of
    // N groups of one.
    return RadioGroup<T>(
      groupValue: catalog.value,
      onChanged: (T? next) => _pick(next),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int index = 0; index < catalog.options.length; index += 1)
            MkviOptionRow<T>(
              key: MkviChoiceKeys.row(index),
              value: catalog.options[index].value,
              groupValue: catalog.value,
              onChanged: (T? next) => _pick(next),
              label: catalog.options[index].label,
              description: catalog.options[index].description,
            ),
        ],
      ),
    );
  }

  Widget _segmented(BuildContext context) {
    return MkviSegmentedRow<T>(
      values: <T>[
        for (final MkviChoiceOption<T> option in catalog.options) option.value,
      ],
      selected: catalog.value,
      labelFor: catalog.labelOf,
      onChanged: (T next) => _pick(next),
      resting: resting,
    );
  }

  Widget _switches(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int index = 0; index < catalog.options.length; index += 1)
          MkviSwitchRow(
            key: MkviChoiceKeys.switchRow(index),
            value: catalog.isSelected(catalog.options[index].value),
            onChanged: (bool on) => _pick(catalog.options[index].value),
            label: catalog.options[index].label,
            description: catalog.options[index].description,
          ),
      ],
    );
  }

  void _pick(T? value) {
    if (value == null) return;
    catalog.select(value);
    onChanged?.call(value);
  }
}
