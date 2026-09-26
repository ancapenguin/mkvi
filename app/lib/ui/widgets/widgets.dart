/// The vocabulary every screen in this app is made of.
///
/// `app/lib/` had ten layers before this one and not one screen: `core`,
/// `protocol`, `signaling`, `session`, `chat`, `call`, `media`, `settings`,
/// `update` and `ui/notice` were all written and tested, and `main.dart` was
/// still the Flutter template. So the gap was not a missing screen, it was a
/// missing vocabulary: without this layer, every screen would have written its
/// own panel, its own empty state and its own status pill, and nothing in the
/// repository would have stopped any of them.
///
/// ## What is here, and what is deliberately not
///
/// Two halves, written side by side:
///
/// * **Surfaces and states** — [MkviPanel] with its three variants,
///   [MkviSectionHeader], [MkviKeyValueRow], [MkviEmptyState], [MkviErrorState],
///   [MkviBadge], [MkviLinearProgress], [MkviCircularProgress], [MkviDivider],
///   [MkviVerticalDivider], [MkviGap].
/// * **Inputs and choices** — [MkviTextField], [MkviMultilineField],
///   [MkviCodeField], [MkviOptionRow], [MkviSwitchRow], [MkviSliderRow],
///   [MkviSegmentedRow], [MkviChoiceGroup] and [MkviChoiceCatalog].
///
/// It is **not** a widget kit. There is no plain "button" here on purpose:
/// `AppearanceResolver` builds a complete `ThemeData` — filled, outlined, text
/// and icon buttons, input borders, the focus ring, all fifteen text-theme slots
/// and all twenty-nine colour roles — and Material's own widget is the correct
/// thing to use for a control. Rewriting a button would put two sources of truth
/// for the same control in one app, which is the defect this redesign exists to
/// end. What is here is the part Material cannot reach: **the relationships
/// between a control and the surface it stands on.**
///
/// ## The interface rules, and why they are code and not a document
///
/// | rule | where | why a token test cannot hold it |
/// |---|---|---|
/// | a filled action on a raised surface takes the `borderStrong` edge; on `bg`/`surface` it does not | [mkviFilledActionNeedsEdge] | a token file can measure `borderStrong` on every surface; it cannot say which controls must carry it |
/// | the label of an action with **no** fill is a *surface* role, not an on-**fill** role | [MkviActionButton] | `textOnAccent` is declared on `accent` and `dangerFill`; on a light `surface` it measures 1.12:1, so putting it there is a contrast bug no token test can see |
/// | an error block shows its reason in full, and the reason is a required argument | [MkviErrorState] | nothing measures "the diagnostic was dropped" |
/// | a self-looping animation is the caller's clock, not the widget's | [MkviProgressMotion] | `pumpAndSettle` is how every overflow test runs; a widget that never settles removes them all |
///
/// The first is `ROADMAP.md` Faz 2's unchecked item, implemented rather than
/// ticked, and `test/ui/widgets/surfaces_test.dart` measures it in all sixteen
/// theme/accent combinations by reading the role the panel paints — not by
/// comparing a colour written into the test.
///
/// ## Where the numbers come from
///
/// Every colour, radius, gap, type step, control metric and duration is read
/// from `AppearanceStyle.of(context)`, and there is not one literal among them.
/// That is possible because the resolver already multiplied the user's density,
/// radius preset, type scale, high contrast and reduced motion into a single
/// object; a widget that wants a gap can only ask for a token step.
/// `design/tokens.json` is the only place a number is written down.
///
/// `app/lib/ui/notice/` takes a different route on purpose: it cannot import the
/// generated tokens, so it takes an injected `NoticePalette` with no defaults.
/// This layer needs no palette parameter at all, because the resolved style is
/// already on the `ThemeData`.
///
/// Every user-facing string in this layer is a constructor argument, so a state
/// cannot be built with no wording and no English can reach a Turkish UI.
library;

export 'mkvi_badge.dart';
export 'mkvi_choice.dart';
export 'mkvi_choice_host.dart';
export 'mkvi_code_field.dart';
export 'mkvi_divider.dart';
export 'mkvi_field.dart';
export 'mkvi_panel.dart';
export 'mkvi_progress.dart';
export 'mkvi_section.dart';
export 'mkvi_state.dart';
