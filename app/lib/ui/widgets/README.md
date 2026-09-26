# `lib/ui/widgets` — the surfaces, the layout blocks, the states

The vocabulary every screen in MKVI is written in. Not a widget kit: there is no
button and no text field in here, because `AppearanceResolver` already dresses
Material's own ones.

```dart
MkviPanel.raised(
  title: 'Eşleşmiş cihazlar',
  subtitle: 'Bu cihazda daha önce eşleştiğin kayıtlar.',
  actions: <MkviPanelAction>[
    MkviPanelAction(label: 'Kaydet', onPressed: save, filled: true),
    MkviPanelAction(label: 'Yenile', onPressed: refresh),
  ],
  child: const MkviKeyValueRow(label: 'Eş parmak izi', value: fingerprint),
)
```

## What is here, and what each role means

| widget | surface it paints | roles it uses | what it is for |
|---|---|---|---|
| `MkviPanel.raised` | `surfaceRaised` | `text`, `textMuted`, `borderStrong` | a card: a group of things on a surface above the page |
| `MkviPanel.soft` | `surfaceSoft` | as above | a well: the same fill the input fields use |
| `MkviPanel.flat` | none — the `bg` shows through | `borderStrong` | a structure with no fill; born with an edge |
| `MkviSectionHeader` | none — it stands on the page | `text`, `textMuted` | a heading, a sentence, an action |
| `MkviKeyValueRow` | none | `textMuted` label, `text` value | a label and a value; the settings list's atom |
| `MkviEmptyState` | none | `text`, `textMuted`, `surfaceSoft` well | nothing to show, and nothing wrong |
| `MkviErrorState` | `dangerFill` + `danger` edge | `textOnAccent` only | something failed: the reason, and what to do |
| `MkviBadge` | `accentSoft` / `successSoft` / `warningSoft` / `dangerFill` | `text`, or `textOnAccent` on the danger fill | a status label |
| `MkviLinearProgress` | track `border`, fill `accent` | both | a bar: determinate, or a sweep position |
| `MkviCircularProgress` | track `border`, arc `accent` | both | a ring, where there is no width to spare |
| `MkviDivider` / `MkviVerticalDivider` | `border` | both | one hairline, one colour, one border width |
| `MkviGap` | nothing | — | empty space, named by its step |

Every one of those is a role name out of the 29 in `design/tokens.json`, read
through `AppearanceStyle.of(context)`. There is not one colour literal, one pixel
literal, one `dart:math` and one hard-coded `Duration` in this directory; the
whole tree is `style.gap('4')`, `style.shape('md')`, `style.role('surfaceSoft')`
and `style.duration('slow')`. Spacing and indents are **step names** (`'0'`..
`'10'`), not numbers, because a number here would be a literal that ignores the
user's density.

## The filled-action rule, and why it lives in this README

`ROADMAP.md` Faz 2:

> **Vurgu dolu düğme, yükseltilmiş yüzeyde `borderStrong` kenarı alacak.** Bu bir
> token kuralı değil, arayüz kuralı: token testi bunu ölçemez, vurgu dolu her
> düğme `bg`/`surface` üzerinde durmalı, `surfaceRaised`/`surfaceSoft` üzerinde ise
> kenarı olmalı. Kod yazarken uygulanacak.

**It is written down here because it is an interface rule, and an interface rule
that lives only in a test is a rule the next screen breaks.** A token rule belongs
in `design/tokens.json` and is checked by `design/test/contrast_test.dart`. This
one cannot go there: the token file can prove that `borderStrong` clears 3:1 on
all five surfaces, and that says nothing about *which controls must carry it*.
So the decision lives in one function — `mkviFilledActionNeedsEdge` — and every
button in this app that has a fill goes through it, because the caller has to
name the surface the button is standing on:

```dart
MkviPanel.raised(actions: …)   // surfaceRaised → borderStrong edge
MkviPanel.flat(actions: …)     // bg           → no edge
MkviSectionHeader(actions: …)  // bg by default → no edge
MkviErrorState(actions: …)     // dangerFill   → borderStrong edge
```

The rule is written as *the edge goes on unless the fill stands directly on `bg`
or `surface`* rather than as the list of the two cases the ROADMAP names. The two
named cases come out the same either way, and a role nobody thought of
(`surfaceOverlay` under a dialog) lands on the safe side of the decision instead
of the unsafe one.

`test/ui/widgets/surfaces_test.dart` measures it in all sixteen theme/accent
combinations by reading the role the panel paints and the button's resolved
`BorderSide` — never by comparing a colour written into the test. Its negative
control is the assertion that the resolver's own `filledButtonTheme` has **no**
`side` at all: without that, "the button has a border" would pass just as well on
a theme that gave every button one.

## The second rule, which is not in the ROADMAP yet

The theme hands `textOnAccent` to **every** button. That is right for a filled
one — it is an on-**fill** role, and the fill is `accent`, a pair the token file
measures at 4.5:1. It is wrong for a button with no fill, because that label
stands on a *surface*: in the light theme `textOnAccent` is white and
`surfaceRaised` is `#EEF2F7`, which measures **1.12:1**. So `MkviActionButton`
draws an unfilled action's label in `text` (7:1 on all five surfaces) and a
disabled one in `textSubtle` (4.5:1), and `surfaces_test.dart` measures both
against the surface the button is standing on.

**This is a decision made in the widget layer about something the resolver owns,
and it should be pushed down into `_outlinedButtonStyle` /
`_textButtonStyle` when somebody can change `appearance_resolver.dart`.** As soon
as the theme agrees, the override in `MkviActionButton` can be deleted and the
assertions in `surfaces_test.dart` will still pass.

## The rules that keep the test-suite runnable

| rule | why |
|---|---|
| a widget in this layer never starts a clock | `pumpAndSettle` is how every test here is pumped, and a `repeat()`ing `AnimationController` never lets it return — the sweep is a `phase` the caller passes in, and `MkviProgressMotion` is the one value a caller's controller is built from |
| an indeterminate progress is never `value: null` | Material's own indeterminate runs a repeating controller; the same rule, one layer down |
| reduced motion needs no branch here | `AppearanceResolver` already replaced every duration with `instant`, so `MkviProgressMotion.of(style).duration` is `Duration.zero` and `isAnimated` says so |

A caller that wants a looping bar owns the loop:

```dart
final MkviProgressMotion motion = MkviProgressMotion.of(context);
_controller = AnimationController(vsync: this, duration: motion.duration)..repeat();
// …and with reduced motion, motion.isAnimated is false: paint the phase, do
// not start a controller, because a zero period divides by zero.
```

## No strings

Every headline, reason, recovery, badge label and action label in this directory
is a constructor argument. The layer ships no wording of its own, so a state
cannot be built with nothing to say, and no English can reach a Turkish UI. The
copy in `test/ui/widgets/support/widget_samples.dart` is the layer's test copy,
and the session layer's own Turkish is used as-is in `states_test.dart` (every
`PeerReadFailure` has a `message` and a `recovery`, and both are asserted to
reach the screen).

## Files

| file | what is in it |
|---|---|
| `widgets.dart` | the barrel, and the four interface rules in prose |
| `mkvi_panel.dart` | `MkviPanel`, `MkviPanelVariant`, `MkviPanelAction`, `MkviActionButton`, `mkviFilledActionNeedsEdge` |
| `mkvi_section.dart` | `MkviSectionHeader`, `MkviKeyValueRow` |
| `mkvi_state.dart` | `MkviEmptyState`, `MkviErrorState` |
| `mkvi_badge.dart` | `MkviBadge`, `MkviBadgeTone` |
| `mkvi_progress.dart` | `MkviLinearProgress`, `MkviCircularProgress`, `MkviProgressMotion` |
| `mkvi_divider.dart` | `MkviDivider`, `MkviVerticalDivider`, `MkviGap` |

## Tests

| file | the claim under test | the measurement |
|---|---|---|
| `surfaces_test.dart` | the filled-action edge rule, in all 16 theme/accent pairs and at every density | the role the panel paints vs the button's resolved `BorderSide` |
| `states_test.dart` | an empty state says what is empty; an error state says why, in full | every declared pair on every surface; a 300-character reason that reaches the tree whole |
| `badges_test.dart` | each tone is one declared pair, and the danger tone's label is not `danger` | `danger` on `dangerFill` measured below 4.5:1, and `textOnAccent` above it |
| `progress_test.dart` | the bar is the fill and the track, and nothing here ticks | the indicator's own `value`/`color`/`minHeight`; `hasScheduledFrame` false after settling |
| `dividers_test.dart` | one divider colour, one border width, indents in space steps | `border` at 3:1 on all five surfaces in every palette |

Every one of them ends with the same two loops: `mkviAppearanceMatrix()` (4 themes
× 4 accents) and `mkviScaleMatrix()` (3 type scales × 2 densities), each with
`expectNoOverflow(tester)` after every pump, in a **320 dp column** — because
`pumpMkvi` hands the widget the full 1280 dp window, and a `Row` in 1280 dp never
overflows no matter how broken it is.

## Two things a test author in this directory has to know

Both were found by running them, and both are in `test/support/mkvi_test_app.dart`,
which is not this layer's file:

1. **`mkviStyleOf` breaks a second `pumpMkvi` in the same test.** It walks
   `tester.allElements` and calls `Theme.of` on each one, which registers an
   inherited-widget dependency from outside a build; the next `pumpWidget` then
   trips `InheritedElement.notifyClients`' "check that it really is our
   descendant" assertion, with a `MaterialApp` and a duplicate `Navigator`
   GlobalKey in a message that names neither cause. Looping a matrix is fine —
   the danger is reading the style *between* two pumps. `MkviStyleProbe` in
   `test/ui/widgets/support/widget_samples.dart` reads the same object from a
   real `build`, which is the only legal place to read it.
2. **`pumpMkvi` installs no ambient `DefaultTextStyle`.** A bare `Text` in a test
   is not under a `Scaffold`, so it inherits Flutter's *error* text style: 48 dp
   monospace, red, double-underlined. Any geometry measured around a bare `Text`
   is therefore measuring a font the app will never use. `mkviSample` wraps its
   column in the app's own `bodyMedium` for exactly that reason.
