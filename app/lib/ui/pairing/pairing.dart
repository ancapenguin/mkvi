/// MKVI's pairing screen, and the second half of the white pairing screen's fix.
///
/// `lib/session/setup_state.dart` closed the cause: [SetupState.showsPairingScreen]
/// is true for `firstRun` and for an explicit `needsPairing` and for nothing
/// else, so a failed peer read, a lost keyring entry, a corrupt record and a
/// dropped channel have no value that can reach pairing. This library is where
/// that promise is kept, and it is kept in one place: [PairingScreen]'s first
/// statement is that method, and no file in this directory asks any other
/// question about whether pairing may be shown.
///
/// ## What is here
///
/// | file | what it owns |
/// |---|---|
/// | `pairing_screen.dart` | [PairingScreen], [PairingPhase], [PairingOutcome], [PairingExchange] and the keys the tests measure |
/// | `pairing_code_view.dart` | [PairingCodeView] — the code this device minted, in boxes, copyable and replaceable |
/// | `pairing_enter.dart` | [PairingEnter] — [MkviCodeField] plus the one gate that sends it |
/// | `pairing_action.dart` | [PairingActionButton] — the button that meets `control.hitTargetMin`, which the resolved theme's `minimumSize` does not |
/// | `pairing_strings.dart` | [PairingTr] and [PairingRefusal], the whole Turkish vocabulary including every error sentence |
///
/// ## Three things this directory deliberately does not do
///
/// * **It does not re-implement the code's rules.** `lib/signaling/pairing_code.dart`
///   is the only definition of a pairing code; `MkviCodeField` calls
///   `normalizePairingCode` and `isAcceptedPairingCode` and this directory calls
///   them again for the gate and nothing else.
/// * **It does not re-derive a name.** `controller.names` is the only source; a
///   screen that ranked an annotation against an announced name is the
///   `src/App.tsx:119` defect, and the peer's two names are drawn in two
///   labelled rows so neither can be mistaken for the other.
/// * **It does not own the pairing exchange.** [PairingExchange] is a required
///   parameter with no default: the rendezvous call plus
///   `SessionController.completePairing` belongs to the signaling wiring
///   `ROADMAP.md` Faz 3/Faz 4 still owes, and a screen whose submit control
///   silently does nothing is the defect `test/support/fakes/README.md` was
///   written about. A caller that cannot name the exchange cannot build the
///   screen.
///
/// ## The measurements
///
/// `test/ui/pairing/` walks the three matrices — `mkviAppearanceMatrix()` (4
/// themes × 4 accents), `mkviScaleMatrix()` and `mkviAccessibilityMatrix()` —
/// at all three of `mkviWindowSizes`, with `expectNoOverflow` after every pump
/// and the accessibility floor at the end of each screen test. Every interactive
/// element is measured with `expectHitTarget`, and `pairing_enter_test.dart`
/// measures the three numbers behind that promise — `control.hitTargetMin` (44),
/// the resolved `filledButtonTheme`'s declared `minimumSize` (`controls.md.height`,
/// 34) and the rendered box (48, from Material's `MaterialTapTargetSize.padded`).
/// See `pairing_action.dart` for why the middle number is a defect and the third
/// is luck.
library;

export 'pairing_action.dart';
export 'pairing_code_view.dart';
export 'pairing_enter.dart';
export 'pairing_screen.dart';
export 'pairing_strings.dart';
