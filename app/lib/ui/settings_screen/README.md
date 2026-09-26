# `lib/ui/settings_screen` — the settings screen

The one place a preference is changed, and the one place its effect can be
**seen**.

```dart
SettingsScreen(
  controller: controller,          // the shared SettingsController
  appVersion: '0.2.0',             // pubspec.yaml is the only source of it
  onCheckUpdate: () => ...,        // null until a host wires UpdateClient
  updateStatusTr: 'Güncel',        // the host's own Turkish sentence
)
```

## The defect this screen exists to close

`ROADMAP.md` Faz 2:

> **Ölçek/yoğunluk her yerde** (0.1.x'te `fontScale` ilk ekranlarda etkisizdi).

0.1.x scaled one element and let every other rule use its own literal, so moving
the type slider on the settings panel changed nothing on the first-run screens.
`AppearanceResolver` removed the cause — `AppearanceStyle.typeScale` is the only
font-size source and it is already multiplied by the user's number — but a state
layer cannot demonstrate its own fix. **This screen does**, in three places that
are measured rather than asserted:

| where | what it shows | what proves it |
|---|---|---|
| the live preview (`appearance_section.dart`) | the chosen palette, on a `surface` card | the accent pill's fill is `style.role('accent')` and its label is `style.role('textOnAccent')`, in all 16 theme/accent pairs |
| the type sample (`type_scale_section.dart`) | one line at `sm`, one at `lg` | after `setFontScale(1.25)` both `fontSize`s equal `style.typeStep(…).size`; a hard-coded size goes red |
| the density sample rows (`density_section.dart`) | three rows one `space` step apart | the gap between two rows is `style.gap('2')`, and it is *smaller* at `compact` |

## The rules this directory keeps

| rule | why |
|---|---|
| a value belongs to `SettingsController`, never to a widget | `SettingsChoiceGroup` pushes the controller's value into its catalogue after every change, so a reset — or a store read that corrected a value — cannot leave a picker showing something the app no longer holds |
| a label belongs to `SettingsCatalog` or to `SettingsUiTr` | a theme name typed into this tree drifts from `design/tokens.json` silently; `settings_screen_test.dart` asserts the catalogue's own strings are the ones on screen |
| an error belongs to the layer that refused the value | `endpointErrorTr` is shown verbatim; this directory has no second validation and no wording of its own |
| no colour, no pixel, no `dart:math`, no hard-coded `Duration` | everything is `style.gap('4')`, `style.role('surface')`, `style.shape('md')`, `style.control('md').height`, `style.hitTargetMin` |
| an accent fill on `surface` takes no edge, on `surfaceRaised` it takes `borderStrong` | `ROADMAP.md` Faz 2's open item, **shipped** in both directions rather than only tested: the density picker stands on a `surface` card and the accent picker on the raised panel |

## Two building blocks, and why they are here

* **`SettingsCard`** — a card on one of the four `MkviRestingSurface`s.
  `MkviPanel` has three variants and none of them is `surface`, and `surface` is
  the surface the ROADMAP rule says a filled control may stand on *without* an
  edge. A screen that demonstrates the rule has to be able to stand on it.
* **`SettingsChoiceGroup<T>`** — a `MkviChoiceGroup` whose catalogue is owned by a
  `State` and synced from the controller. It also wraps a switch list in its own
  `Material`, because `ListTile` refuses to be built between a coloured
  `DecoratedBox` and the nearest `Material`.

## Gaps found while writing this, all in files this layer does not own

1. **`MkviChoiceCatalog.didChange` hands over the same set twice.**
   `select` calls `didChange(_selection, next)` with its own live set as
   `previous`, and `didChange` then does `_selection..clear()..addAll(next)` — so
   `previous` is mutated before `onDidChange` runs. A callback that diffs the two
   sees no change. `appearance_section.dart` applies the whole selection instead
   of diffing, and says why in a comment. *(`app/lib/ui/widgets/mkvi_choice_host.dart`)*
2. **`MkviSwitchRow` has no `Material`.** It is built from a `SwitchListTile`,
   which paints its background and ink on the nearest `Material`; inside
   `MkviPanel` or `SettingsCard` the framework throws *"ListTile background
   color or ink splashes may be invisible"*. Worked around in
   `SettingsChoiceGroup`; the fix belongs in `MkviSwitchRow`, next to the
   `Material` `MkviOptionRow` already has. *(`app/lib/ui/widgets/mkvi_choice.dart`)*

3. **`MkviSliderRow` names the slider with a sibling.** Its label is a
   `Semantics(header: true)` **next to** the `Slider`, and Material's `Slider`
   names nothing itself, so the control's own semantics node has an empty label
   and a screen reader announces a nameless slider. `type_scale_section.dart`
   wraps the row in `MergeSemantics`, which is what Material's own
   `ListTile`-with-a-control does; the fix belongs in `MkviSliderRow`.
   *(`app/lib/ui/widgets/mkvi_choice.dart`)*

### And three in the shared harness

`test/ui/settings_screen/support/settings_semantics.dart` carries a corrected
copy of the harness's walk and explains each defect; delete it when the harness
is fixed. *(`test/support/mkvi_test_app.dart`)*

4. **`readControlLabels` leaks its `SemanticsHandle`**: it disposes it from
   `addTearDown`, which runs *after* `WidgetTester._endOfTestVerifications`, so
   **every** test that calls `expectEveryControlLabelled` is red with "A
   SemanticsHandle was active at the end of the test" before it looks at a
   widget.
5. **It reads the semantics root from the wrong owner.**
   `binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode` is null on this
   SDK, because each view owns its render tree, so the walk starts from an empty
   tree and reports every control in the app as absent — the one false negative
   an accessibility assertion must not have. The root is on
   `tester.binding.renderViews.first.owner`, which is what `flutter_test`'s own
   `SemanticsFinder` uses, and why `pipelineOwner` is deprecated.
6. **Two more in the same walk:** it reports a control *inside* a control (the
   `Radio` in a named option row, the `Switch` in a named tile) as a second
   nameless control, and `_spokenFor`'s `"(kaydırıcı — etiketsiz)"` placeholder
   makes `spoken` never empty, so `expectEveryControlLabelled` **cannot fail**.

## The `roomy` density, and the `http://` endpoint

* `design/tokens.json` declares three densities (`compact`, `cozy`, `roomy`);
  `DensityPreference` has two, so `mkviScaleMatrix()` yields six combinations and
  not twelve. The density picker iterates `DensityPreference.values`, so adding
  `roomy` to the enum adds a segment and widens the matrix with no change here.
  The enum is in `app/lib/settings/`, which this layer does not own.
* `validateEndpoint` accepts `http` **and** `https` and refuses every other
  scheme; its own message says so
  (`yalnızca http:// veya https:// ile başlayabilir`). The four refusal shapes
  this screen handles are blank, scheme-less, host-less and another scheme — not
  `http://`, which the state layer accepts. A form that refused something
  `setEndpoint` accepts would give one question two answers.

## Tests

```powershell
cd app; flutter test test/ui/settings_screen
```

| file | the claim under test |
|---|---|
| `settings_screen_test.dart` | the page, its order, the catalogue's labels, the repaired-settings banner, the filled-action edge in both directions, every hit target, and the whole matrix (16 + 6 + 4) at three window sizes in a 320 dp column |
| `appearance_section_test.dart` | a tap reaches the controller, the preview paints what was chosen, the corner preset moves a painted radius, both switches both ways, a reset puts every control back |
| `type_scale_test.dart` | `setFontScale` reaches the resolved style *and* the sample, the range is the preference's, the labels are not elided at either end, neither end overflows in 16 pairs |
| `density_test.dart` | the row gap is the resolved step, and the two densities are not the same number |
| `connection_section_test.dart` | four refusals with four Turkish sentences and nothing stored, the field announces `invalid` and its edge is the `danger` role, a valid endpoint is stored with its ICE text |
| `identity_section_test.dart` | the sanitised name is stored, the field leaves the 40-character cap to the layer, the confirmation is not stale |

Every test ends with `expectNoOverflow` and an accessibility check, and every
measurement reads a number — a rectangle, a `fontSize`, a `BorderSide`, a role
from the palette about to be painted — rather than a colour written into the
test.
