/// The appearance section: the theme, the accent, the corner preset, the two
/// accessibility switches — and a live preview that proves the change landed.
///
/// ## Why the preview is here and not "trust me"
///
/// `ROADMAP.md` Faz 2 leaves one item open and it is the item this section is
/// about:
///
/// > **Ölçek/yoğunluk her yerde** (0.1.x'te `fontScale` ilk ekranlarda etkisizdi).
///
/// The old build scaled one element and let every other rule use its own
/// literal, so a user who moved the type slider on the settings panel saw
/// nothing happen on the first-run screens. `AppearanceResolver` fixed the
/// cause — there is one resolved number and a widget can only ask for a token —
/// but a state layer cannot demonstrate its own fix. The settings screen is the
/// one place that can: it shows the chosen palette, the chosen type scale and
/// the chosen density on screen next to the control that changes them, and
/// `app/test/ui/settings_screen/` measures the numbers the preview paints with.
///
/// ## What this section does NOT do
///
/// It does not own a value. Every change goes through
/// `SettingsController.setTheme` / `setAccent` / `setRadius` /
/// `setHighContrast` / `setReduceMotion`, and the selection shown is pushed
/// *from* the controller — including after a reset, or after a value that came
/// from a hand-edited store. A picker that keeps its own copy of the choice is
/// how "Görünümü sıfırla" leaves four radios lit; see [SettingsChoiceGroup].
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'settings_strings.dart';

/// The keys the parts of the appearance section answer to.
abstract final class AppearanceKeys {
  /// The theme list.
  static const Key themeGroup = Key('mkvi.settings.appearance.theme');

  /// The accent segmented control.
  static const Key accentGroup = Key('mkvi.settings.appearance.accent');

  /// The corner preset segmented control.
  static const Key radiusGroup = Key('mkvi.settings.appearance.radius');

  /// The two accessibility switches.
  static const Key accessibilityGroup = Key(
    'mkvi.settings.appearance.accessibility',
  );

  /// The `surface` card the preview is painted on.
  static const Key previewCard = Key('mkvi.settings.appearance.previewCard');

  /// The accent pill: the chosen fill, with the on-accent role on it.
  static const Key previewAccent = Key('mkvi.settings.appearance.previewAccent');

  /// The preview's sample name.
  static const Key previewName = Key('mkvi.settings.appearance.previewName');

  /// The preview's sample detail.
  static const Key previewDetail = Key('mkvi.settings.appearance.previewDetail');

  /// The line that says the reset happened, so a reset is never silent.
  static const Key notice = Key('mkvi.settings.appearance.notice');
}

/// The two on/off appearance choices, as values.
///
/// They are one `multiple` catalogue rather than two loose `MkviSwitchRow`s so
/// that every choice list on this screen is drawn by the same widget, and so
/// "which switches are on" is one selection a test can read.
enum AppearanceSwitch {
  /// Push the colour ramps towards their extremes and thicken the focus ring.
  highContrast,

  /// Replace every duration with `instant`.
  reduceMotion,
}

/// One rectangle of one of the four resting surfaces, with an optional strip.
///
/// ## Why this is not `MkviPanel`
///
/// `MkviPanel` has three variants and none of them is `surface`: a raised panel
/// is `surfaceRaised`, a well is `surfaceSoft`, and a flat panel paints no fill
/// at all. This screen needs a `surface` card — the density picker stands on
/// one, and so does the live preview — because `surface` is the plain card the
/// token file declares, and the one a filled control may stand on **without** an
/// edge. `ROADMAP.md` names exactly that case, so the screen that demonstrates
/// the rule has to be able to stand on it.
///
/// ## The edge rule, applied one level up
///
/// `mkviFilledActionNeedsEdge` says a *filled control* takes the `borderStrong`
/// edge unless it stands directly on `bg` or `surface`. This card applies the
/// same split to *itself*: a card whose fill is a step away from the panel it
/// sits in is born with the edge, because otherwise there is nothing to see it
/// by, and a card that IS the panel's own step takes none — exactly like
/// `MkviPanel.raised`. Pass `bordered` to decide it by hand.
class SettingsCard extends StatelessWidget {
  /// Creates a card on [resting].
  const SettingsCard({
    super.key,
    required this.resting,
    required this.child,
    this.title,
    this.subtitle,
    this.actions = const <MkviPanelAction>[],
    this.bordered,
    this.paddingStep = '4',
    this.headerGapStep = '3',
    this.radiusStep = 'md',
  });

  /// The surface this card is painted with, and therefore what its actions are
  /// told they are standing on.
  final MkviRestingSurface resting;

  /// The content.
  final Widget child;

  /// The heading. Optional: a card with no title, subtitle or action has no
  /// strip at all.
  final String? title;

  /// One line under the heading.
  final String? subtitle;

  /// The buttons in the strip, built through the same edge rule a panel uses.
  final List<MkviPanelAction> actions;

  /// Whether the card takes the `borderStrong` edge.
  ///
  /// Defaults to the split described above: an edge on `bg` and `surface`, none
  /// on `surfaceRaised` and `surfaceSoft`.
  final bool? bordered;

  /// The padding between the edge and the content, as a `space.steps` name.
  final String paddingStep;

  /// The gap between the strip and the body, as a `space.steps` name.
  final String headerGapStep;

  /// The corner radius, as a `radius.steps` name.
  final String radiusStep;

  /// Whether the card paints a heading strip.
  bool get hasHeader =>
      title != null || subtitle != null || actions.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final bool edge = bordered ?? !resting.needsBorder;
    return Material(
      // Transparent: the card paints itself below, and this exists so the
      // actions inside it have a `Material` ancestor for their ink.
      type: MaterialType.transparency,
      child: DecoratedBox(
        key: SettingsCardKeys.surface,
        decoration: BoxDecoration(
          color: style.role(resting.roleName),
          borderRadius: style.shape(radiusStep).borderRadius,
          border: edge
              ? Border.all(
                  color: style.role('borderStrong'),
                  width: style.borderWidth,
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.all(style.gap(paddingStep)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (hasHeader) _strip(style),
              if (hasHeader) SizedBox(height: style.gap(headerGapStep)),
              KeyedSubtree(key: SettingsCardKeys.body, child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _strip(AppearanceStyle style) {
    return Row(
      key: SettingsCardKeys.header,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title != null)
                Text(
                  title!,
                  style: style
                      .styleOf('lg')
                      .copyWith(color: style.role('text')),
                ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: style
                      .styleOf('sm')
                      .copyWith(color: style.role('textMuted')),
                ),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...<Widget>[
          SizedBox(width: style.gap('3')),
          // A wrap, not a row: two Turkish action labels in a 320 dp card must
          // become two lines, not an overflow stripe.
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: style.gap('2'),
              runSpacing: style.gap('2'),
              children: <Widget>[
                for (final MkviPanelAction action in actions)
                  MkviActionButton(
                    action: action,
                    surfaceRole: resting.roleName,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The keys a [SettingsCard] answers to, so a test measures the box the eye sees
/// and not the first `Padding` it finds.
abstract final class SettingsCardKeys {
  /// The decorated card.
  static const Key surface = Key('mkvi.settings.card.surface');

  /// The heading strip, absent when the card has no heading.
  static const Key header = Key('mkvi.settings.card.header');

  /// The body.
  static const Key body = Key('mkvi.settings.card.body');
}

/// One choice list whose selection is the controller's, never the widget's.
///
/// ## Why the wrapper exists
///
/// `MkviChoiceGroup` renders a `MkviChoiceCatalog`, and a catalogue is a
/// `ChangeNotifier` with its own selection. Building one inside `build` would
/// create a new one every frame and leak the old; keeping it in a `State` and
/// never syncing it would make the picker show a choice the app no longer
/// holds — which is exactly what happens after "Görünümü sıfırla" or after a
/// store read that corrected a value.
///
/// So this owns the catalogue, listens to the controller, and pushes
/// [selectionOf] into it after every change. The catalogue is a `ChangeNotifier`
/// and its own `ListenableBuilder` is a widget, so the push happens from the
/// controller's listener — never from `build`, where notifying a descendant
/// would call `setState` while the tree is building.
class SettingsChoiceGroup<T> extends StatefulWidget {
  /// Creates a choice list over [controller].
  const SettingsChoiceGroup({
    super.key,
    required this.controller,
    required this.label,
    required this.options,
    required this.selectionOf,
    required this.onDidChange,
    this.multiple = false,
    this.layout = MkviChoiceLayout.rows,
    this.resting = MkviRestingSurface.surface,
  }) : assert(
         layout != MkviChoiceLayout.switches || multiple,
         'A switch list is a multiple choice; a single-choice catalogue cannot '
         'be drawn as one, because a switch cannot express "none of these".',
       );

  /// The state the selection is read from, and never written to here.
  final SettingsController controller;

  /// The setting's name. Turkish, from the catalogue.
  final String label;

  /// The options, in the order they are shown. Turkish, from the catalogue.
  final List<MkviChoiceOption<T>> options;

  /// The selection, read from the controller every time it changes.
  final Set<T> Function(SettingsController controller) selectionOf;

  /// Called after a change, with the selection before and after.
  final void Function(Set<T> previous, Set<T> next) onDidChange;

  /// Whether more than one option may be selected at a time.
  final bool multiple;

  /// How the list is drawn.
  final MkviChoiceLayout layout;

  /// Which surface the control rests on, for [MkviChoiceLayout.segmented].
  final MkviRestingSurface resting;

  @override
  State<SettingsChoiceGroup<T>> createState() => _SettingsChoiceGroupState<T>();
}

class _SettingsChoiceGroupState<T> extends State<SettingsChoiceGroup<T>> {
  late MkviChoiceCatalog<T> _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = _build();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(SettingsChoiceGroup<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller.removeListener(_onControllerChanged);
    widget.controller.addListener(_onControllerChanged);
    _catalog = _build();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _catalog.dispose();
    super.dispose();
  }

  MkviChoiceCatalog<T> _build() => MkviChoiceCatalog<T>(
    label: widget.label,
    options: widget.options,
    multiple: widget.multiple,
    selection: widget.selectionOf(widget.controller),
    // Reads `widget` at call time, so a rebuilt parent cannot leave a stale
    // controller in the catalogue's callback.
    onDidChange: (Set<T> previous, Set<T> next) =>
        widget.onDidChange(previous, next),
  );

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      _catalog.didChange(
        _catalog.selection,
        widget.selectionOf(widget.controller),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget group = MkviChoiceGroup<T>(
      catalog: _catalog,
      layout: widget.layout,
      resting: widget.resting,
    );
    if (widget.layout != MkviChoiceLayout.switches) return group;
    // A `Material` between the card's `DecoratedBox` and the `SwitchListTile`
    // inside `MkviSwitchRow`. `ListTile` paints its background and its ink on
    // the nearest `Material` ancestor, and the framework refuses to be built
    // when a coloured `DecoratedBox` sits between the two:
    //
    //   "ListTile background color or ink splashes may be invisible."
    //
    // `MkviSwitchRow` does not bring its own, and `MkviPanel` and [SettingsCard]
    // both paint through a `DecoratedBox`, so the wrapper belongs to the layer
    // that puts a switch on a card. Reported against
    // `app/lib/ui/widgets/mkvi_choice.dart`: the fix belongs inside
    // `MkviSwitchRow`, beside the `Material` `MkviOptionRow` already has.
    return Material(type: MaterialType.transparency, child: group);
  }
}

/// The appearance section: theme, accent, corners, accessibility and a preview.
class AppearanceSection extends StatefulWidget {
  /// Creates the section over [controller].
  const AppearanceSection({
    super.key,
    required this.controller,
    this.resting = MkviRestingSurface.raised,
  });

  /// The state this screen shows and changes. Never written to directly.
  final SettingsController controller;

  /// The surface the accent and corner pickers stand on.
  ///
  /// The screen puts this section in a [MkviPanel.raised], so the default is
  /// [MkviRestingSurface.raised] and the two segmented controls take the
  /// `borderStrong` edge. A test that wants the other half of the rule passes
  /// [MkviRestingSurface.surface] here and measures that the edge is gone.
  final MkviRestingSurface resting;

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  /// The sentence shown after a reset.
  ///
  /// Local, because "you pressed the button" is not a setting and must not be
  /// persisted — and cleared by the next change, because a stale "varsayılanlara
  /// döndü" under a preview showing something else is a lie.
  String? _notice;

  void _reset() {
    widget.controller.resetAppearance();
    setState(() => _notice = widget.controller.catalog.appearanceResetDone);
  }

  void _changed() {
    if (_notice == null) return;
    setState(() => _notice = null);
  }

  void _onSwitchChanged(
    Set<AppearanceSwitch> previous,
    Set<AppearanceSwitch> next,
  ) {
    // The whole selection is applied, not a diff of the two sets, and that is
    // not a style choice: `MkviChoiceCatalog.select` calls
    // `didChange(_selection, next)` with its OWN live set as `previous`, and
    // `didChange` then does `_selection..clear()..addAll(next)` — so by the time
    // `onDidChange` runs, `previous` and `next` are the same object. A callback
    // that diffs them sees no change and writes nothing, which is how a switch
    // row can turn on while the preference stays false.
    //
    // `next` is the authoritative one (`didChange` hands over
    // `Set.unmodifiable(_selection)` after the mutation), and applying the whole
    // selection is idempotent: `SettingsController.setHighContrast` with the
    // value it already holds writes nothing and publishes nothing.
    //
    // Reported against `app/lib/ui/widgets/mkvi_choice_host.dart`: `didChange`
    // should hand over a copy of the selection as it was on entry.
    widget.controller.setHighContrast(
      next.contains(AppearanceSwitch.highContrast),
    );
    widget.controller.setReduceMotion(
      next.contains(AppearanceSwitch.reduceMotion),
    );
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final SettingsController controller = widget.controller;
    final MkviRestingSurface resting = widget.resting;
    final SettingsCatalog catalog = controller.catalog;
    return MkviPanel.raised(
      title: catalog.appearanceSection,
      subtitle: SettingsUiTr.appearanceDescription.tr,
      actions: <MkviPanelAction>[
        MkviPanelAction(label: catalog.resetAppearanceLabel, onPressed: _reset),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsChoiceGroup<ThemePreference>(
            key: AppearanceKeys.themeGroup,
            controller: controller,
            label: catalog.themeLabel,
            layout: MkviChoiceLayout.rows,
            selectionOf: (SettingsController c) => <ThemePreference>{
              c.appearance.theme,
            },
            onDidChange: (Set<ThemePreference> _, Set<ThemePreference> next) {
              controller.setTheme(next.first);
              _changed();
            },
            options: <MkviChoiceOption<ThemePreference>>[
              for (final ThemePreference theme in catalog.themeOptions)
                MkviChoiceOption<ThemePreference>(
                  value: theme,
                  label: catalog.themeOptionLabel(theme),
                  // Only the system theme needs explaining: it is a decision
                  // about the platform rather than a theme, and the catalogue
                  // says so.
                  description: theme == ThemePreference.system
                      ? catalog.systemThemeDescription
                      : null,
                ),
            ],
          ),
          SizedBox(height: style.gap('4')),
          SettingsChoiceGroup<AccentId>(
            key: AppearanceKeys.accentGroup,
            controller: controller,
            label: catalog.accentLabel,
            layout: MkviChoiceLayout.segmented,
            resting: resting,
            selectionOf: (SettingsController c) {
              final AccentId? preset = c.appearance.accent.presetId;
              // A custom accent has no segment here: this screen offers the
              // four shipped ramps, and "nothing is selected" is the honest
              // answer where no option matches.
              return preset == null ? <AccentId>{} : <AccentId>{preset};
            },
            onDidChange: (Set<AccentId> _, Set<AccentId> next) {
              controller.setAccent(AccentPreference.preset(next.first));
              _changed();
            },
            options: <MkviChoiceOption<AccentId>>[
              for (final AccentId accent in AccentId.values)
                MkviChoiceOption<AccentId>(
                  value: accent,
                  // From the token file, never retyped.
                  label: catalog.accentOptionLabel(accent),
                ),
            ],
          ),
          SizedBox(height: style.gap('4')),
          SettingsChoiceGroup<RadiusPreference>(
            key: AppearanceKeys.radiusGroup,
            controller: controller,
            label: catalog.radiusLabel,
            layout: MkviChoiceLayout.segmented,
            resting: resting,
            selectionOf: (SettingsController c) => <RadiusPreference>{
              c.appearance.radius,
            },
            onDidChange: (Set<RadiusPreference> _, Set<RadiusPreference> next) {
              controller.setRadius(next.first);
              _changed();
            },
            options: <MkviChoiceOption<RadiusPreference>>[
              for (final RadiusPreference radius in RadiusPreference.values)
                MkviChoiceOption<RadiusPreference>(
                  value: radius,
                  label: catalog.radiusOptionLabel(radius),
                ),
            ],
          ),
          SizedBox(height: style.gap('4')),
          const _Preview(),
          SizedBox(height: style.gap('4')),
          SettingsChoiceGroup<AppearanceSwitch>(
            key: AppearanceKeys.accessibilityGroup,
            controller: controller,
            label: catalog.accessibilitySection,
            layout: MkviChoiceLayout.switches,
            multiple: true,
            selectionOf: (SettingsController c) => <AppearanceSwitch>{
              if (c.appearance.highContrast) AppearanceSwitch.highContrast,
              if (c.appearance.reduceMotion) AppearanceSwitch.reduceMotion,
            },
            onDidChange: _onSwitchChanged,
            options: <MkviChoiceOption<AppearanceSwitch>>[
              MkviChoiceOption<AppearanceSwitch>(
                value: AppearanceSwitch.highContrast,
                label: catalog.highContrastLabel,
                description: catalog.highContrastDescription,
              ),
              MkviChoiceOption<AppearanceSwitch>(
                value: AppearanceSwitch.reduceMotion,
                label: catalog.reduceMotionLabel,
                description: catalog.reduceMotionDescription,
              ),
            ],
          ),
          if (_notice != null) ...<Widget>[
            SizedBox(height: style.gap('2')),
            Semantics(
              key: AppearanceKeys.notice,
              liveRegion: true,
              child: Text(
                _notice!,
                style: style.styleOf('sm').copyWith(
                  color: style.role('textMuted'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The live preview: the chosen palette and the chosen type, painted here.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return SettingsCard(
      key: AppearanceKeys.previewCard,
      // `surface`, not the panel's `surfaceRaised`: a step down reads as a
      // preview well, and it is the surface the ROADMAP rule says a filled
      // control may stand on without an edge.
      resting: MkviRestingSurface.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              SettingsUiTr.previewLabel.tr,
              style: style.styleOf('sm').copyWith(color: style.role('text')),
            ),
          ),
          SizedBox(height: style.gap('1')),
          Text(
            SettingsUiTr.previewDescription.tr,
            style: style.styleOf('2xs').copyWith(color: style.role('textMuted')),
          ),
          SizedBox(height: style.gap('3')),
          // The accent fill, seen, with the on-accent role on it. No edge: it
          // stands on `surface`, which is the case the rule exempts.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              key: AppearanceKeys.previewAccent,
              constraints: BoxConstraints(
                minHeight: style.control('sm').height,
              ),
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: style.gap('3')),
              decoration: BoxDecoration(
                color: style.role('accent'),
                borderRadius: style.shape('pill').borderRadius,
              ),
              child: Text(
                SettingsUiTr.previewAccentLabel.tr,
                style: style
                    .styleOf('sm')
                    .copyWith(color: style.role('textOnAccent')),
              ),
            ),
          ),
          SizedBox(height: style.gap('3')),
          Text(
            SettingsUiTr.previewSampleName.tr,
            key: AppearanceKeys.previewName,
            style: style.styleOf('sm').copyWith(color: style.role('text')),
          ),
          SizedBox(height: style.gap('1')),
          Text(
            SettingsUiTr.previewSampleDetail.tr,
            key: AppearanceKeys.previewDetail,
            style: style.styleOf('2xs').copyWith(color: style.role('textMuted')),
          ),
        ],
      ),
    );
  }
}
