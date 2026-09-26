/// The pairing screen, and the one place in the app that is allowed to be
/// reached by a [SetupState].
///
/// ## The rule this screen exists to keep
///
/// `src/App.tsx:545` gated the pairing screen on `knownPeer === null`, and a
/// *failed* read left that field null (`src/App.tsx:153-165` only set a notice).
/// So a corrupt store, a keyring that had lost its entry and a plain first run
/// all showed the same screen, and a user who had been paired for months woke up
/// being asked to pair again with no way back.
///
/// `lib/session/setup_state.dart` fixed the cause: [SetupState.showsPairingScreen]
/// is true for [SetupFirstRun] and [SetupNeedsPairing] and for nothing else. This
/// screen's **first statement** is that method and nothing else — no null check on
/// a peer, no "no peer means pair", no `canRetry` branch. When it is false the
/// screen builds a `SizedBox.shrink()` and renders nothing at all, which is a
/// measurable claim (`test/ui/pairing/pairing_screen_test.dart` walks every state
/// that is not a pairing state and measures the result) rather than a promise.
///
/// The consequence is worth writing down, because it looks like a missing feature
/// and is not one: this screen has **no** branch for `SetupRestoring` or
/// `SetupReconnecting`. Those states show a progress surface owned by the shell
/// around this screen, exactly as `SetupBroken` shows the `broken` surface with
/// its reason and its "pair a new device" action. Pairing being unreachable from
/// them is the fix, not an omission in this file.
///
/// ## The three things it does show
///
/// | state | what is on screen |
/// |---|---|
/// | [SetupFirstRun] | the code **this** device minted, split into boxes, copyable, replaceable, and the sentence telling the user to send it |
/// | [SetupNeedsPairing] | the code **the other** device minted, typed in; the peer that will be replaced, with its two names in two slots; and a confirmed way out |
/// | either, while a code is in flight | the progress surface, the field still holding the code that was sent, and the Turkish reason if it was refused |
///
/// ## The two names
///
/// `src/App.tsx:119` was `peerAlias || peerAnnouncedName || defaultPeerName`, so
/// a purely local note outranked the name the peer published about itself, and
/// `src/components/ChatCallWorkspace.tsx:490` then gated *both* the
/// "Kendi seçtiği ad: …" line and the "remove note" button on the two names
/// being **different** — so a note typed as the peer's own name silently deleted
/// both.
///
/// [PeerNameView] is two slots and answers the UI's question about the
/// annotation. This screen reads it and never recomputes a name: the peer's own
/// name is [PeerNameView.displayName] in its own row, the local note is a second
/// row with its own label, and when [PeerNameView.showsAnnouncedName] is true
/// the "Kendi seçtiği ad: …" line is drawn **even though the two strings are
/// equal** — which is the case the TypeScript original could not render and the
/// case in which the peer is most likely to want to change their name.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mkvi/session/session.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/signaling/pairing_code.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'pairing_action.dart';
import 'pairing_code_view.dart';
import 'pairing_enter.dart';
import 'pairing_strings.dart';

/// The keys this screen's parts answer to.
///
/// [hidden] is the important one: it is the key of the box the screen builds for
/// every state that may not show pairing, so "it is not on screen" is a widget a
/// test can find rather than an absence a test has to trust. It is a bare
/// [SizedBox] with no child, so a test can also assert that the screen's subtree
/// contains no [Text] at all — which is the claim the white pairing screen is
/// really about.
abstract final class PairingScreenKeys {
  /// The box a non-pairing state builds: a childless [SizedBox].
  static const Key hidden = Key('mkvi.pairing.hidden');

  /// The scrollable body of a pairing state.
  static const Key body = Key('mkvi.pairing.body');

  /// The heading, which is [SetupState.title].
  static const Key heading = Key('mkvi.pairing.heading');

  /// The generated code block. Absent outside [SetupFirstRun].
  static const Key codeBlock = Key('mkvi.pairing.code');

  /// The code entry block. Absent outside [SetupNeedsPairing].
  static const Key enterBlock = Key('mkvi.pairing.enter');

  /// The block naming the peer that pairing would replace.
  static const Key peerBlock = Key('mkvi.pairing.peer');

  /// The row holding the peer's own announced name.
  static const Key announcedRow = Key('mkvi.pairing.peer.announced');

  /// The row holding this device's local note. Absent when there is none.
  static const Key aliasRow = Key('mkvi.pairing.peer.alias');

  /// The "Kendi seçtiği ad: …" line. Absent unless
  /// [PeerNameView.showsAnnouncedName].
  static const Key announcedLine = Key('mkvi.pairing.peer.announced.line');

  /// The progress bar while a code is in flight.
  static const Key progress = Key('mkvi.pairing.progress');

  /// The block a refused exchange produces.
  static const Key failure = Key('mkvi.pairing.failure');

  /// Sends the same code again, for a refusal that is about the network.
  static const Key retry = Key('mkvi.pairing.retry');

  /// The control that asks before leaving.
  static const Key cancel = Key('mkvi.pairing.cancel');

  /// The confirmation dialog.
  static const Key cancelDialog = Key('mkvi.pairing.cancel.dialog');

  /// The confirmation's affirmative button.
  static const Key cancelConfirm = Key('mkvi.pairing.cancel.confirm');

  /// The confirmation's negative button.
  static const Key cancelDismiss = Key('mkvi.pairing.cancel.dismiss');
}

/// How a pairing exchange ended.
///
/// A value rather than a `bool`, because the three answers need three different
/// things from the screen: nothing, a progress surface, and a reason with an
/// action. A `Future<bool>` would make "refused, here is why" a second channel
/// the widget layer had to correlate.
sealed class PairingPhase {
  const PairingPhase();

  /// Nothing is in flight; the field and the generated code are live.
  const factory PairingPhase.idle() = PairingPhaseIdle;

  /// A code is with the other side.
  const factory PairingPhase.exchanging() = PairingPhaseExchanging;

  /// The other side, the network or the local store said no.
  const factory PairingPhase.refused(PairingRefusal refusal) = PairingPhaseRefused;
}

/// Nothing is in flight.
final class PairingPhaseIdle extends PairingPhase {
  const PairingPhaseIdle();
}

/// A code is with the other side.
final class PairingPhaseExchanging extends PairingPhase {
  const PairingPhaseExchanging();
}

/// The exchange ended without a peer.
final class PairingPhaseRefused extends PairingPhase {
  const PairingPhaseRefused(this.refusal);

  /// Why.
  final PairingRefusal refusal;
}

/// The one outcome a pairing exchange may have.
sealed class PairingOutcome {
  const PairingOutcome();

  /// The other device answered and the identity verified. The record is written
  /// and the controller has already left the pairing state.
  const factory PairingOutcome.accepted({
    required String publicKey,
    required String discoveryId,
    String? announcedName,
  }) = PairingAccepted;

  /// It did not. [refusal] says why, in two Turkish sentences.
  const factory PairingOutcome.refused(PairingRefusal refusal) = PairingRefused;
}

/// The pair is complete and the session has already moved on.
final class PairingAccepted extends PairingOutcome {
  const PairingAccepted({
    required this.publicKey,
    required this.discoveryId,
    this.announcedName,
  });

  /// The peer's public key, as `completePairing` needs it.
  final String publicKey;

  /// The capability that routed to the room, as `completePairing` needs it.
  final String discoveryId;

  /// Whatever the peer announced, which is very often nothing yet — and
  /// `completePairing` keeps the stored name when it is nothing.
  final String? announcedName;
}

/// The exchange did not produce a pair.
final class PairingRefused extends PairingOutcome {
  const PairingRefused(this.refusal);

  /// Why.
  final PairingRefusal refusal;
}

/// Performs one pairing attempt for a code.
///
/// A required parameter, not an optional one with a default. A screen whose
/// submit control silently does nothing is the defect this repository has paid
/// for most often (`test/support/fakes/README.md`), and making the seam
/// un-defaultable is the only way the widget layer cannot have that bug.
///
/// The production implementation is not in this directory: it is the rendezvous
/// call plus `SessionController.completePairing`, which belongs with the
/// signaling wiring `ROADMAP.md` Faz 3/Faz 4 still owes. Whoever writes it wraps
/// both in one `async` and returns one of [PairingOutcome]'s two cases — there is
/// no third, and there is no way to report a failure as anything but a
/// [PairingRefusal] with a Turkish sentence already attached.
typedef PairingExchange = Future<PairingOutcome> Function(String code);

/// The pairing screen.
///
/// [controller] is the only source of [SetupState]: the screen subscribes to
/// [SessionController.states] and never inspects a peer to decide what to show,
/// which is the property the whole `SetupState` design exists for.
class PairingScreen extends StatefulWidget {
  /// Creates the pairing screen.
  const PairingScreen({
    super.key,
    required this.controller,
    required this.exchange,
    this.sweepPhase = 0.0,
    this.copyToClipboard = copyPairingCodeToClipboard,
  });

  /// The session. Supplies the state, the peer's two names, and the way out.
  final SessionController controller;

  /// The one pairing attempt this screen can make.
  final PairingExchange exchange;

  /// Where the indeterminate progress bar's fill sits, 0..1.
  ///
  /// A number the caller owns on purpose, for the reason
  /// `lib/ui/widgets/mkvi_progress.dart` gives: a self-repeating
  /// `AnimationController` never lets `pumpAndSettle` return, and every
  /// overflow test in this repository is pumped that way. The shell that starts
  /// the exchange drives the sweep; under reduced motion it passes a fixed value
  /// and `AppearanceResolver` has already replaced the duration with `instant`.
  final double sweepPhase;

  /// Where the generated code goes when it is copied.
  final PairingClipboard copyToClipboard;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  /// The code the user is typing. Owned here rather than inside the entry block
  /// because a refused exchange has to be able to offer "send the same code
  /// again" for a transport failure — which needs the value after the child has
  /// rebuilt.
  final TextEditingController _code = TextEditingController();

  /// The last state the controller published, or its current one before it
  /// publishes anything.
  ///
  /// [SessionController.states] is the only thing this screen rebuilds from, and
  /// that is deliberate: it is the stream the whole `SetupState` design exists
  /// for. The consequence is that a value the controller holds but does not
  /// publish is read at build time and stays as it was — `setPeerAlias` writes a
  /// note and emits nothing, so a rename made while this screen is up appears
  /// the next time the *state* moves. That is correct rather than lucky: the only
  /// place a note is written from is the workspace, which is not this screen.
  late SetupState _state = widget.controller.state;

  StreamSubscription<SetupState>? _states;

  PairingPhase _phase = const PairingPhase.idle();

  @override
  void initState() {
    super.initState();
    _states = widget.controller.states.listen(_onState);
  }

  @override
  void didUpdateWidget(PairingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    _states?.cancel();
    _state = widget.controller.state;
    _states = widget.controller.states.listen(_onState);
  }

  @override
  void dispose() {
    _states?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _onState(SetupState next) {
    if (!mounted) return;
    setState(() => _state = next);
  }

  /// Sends the code currently in the field.
  ///
  /// A second press while one is in flight is ignored rather than queued: the
  /// code is single-use, and a queued second attempt would spend it twice.
  Future<void> _submit() async {
    if (_phase is PairingPhaseExchanging) return;
    setState(() => _phase = const PairingPhase.exchanging());
    final PairingOutcome outcome = await widget.exchange(
      normalizePairingCode(_code.text),
    );
    if (!mounted) return;
    setState(() => _phase = switch (outcome) {
      // On success the controller has already moved to a state that does not
      // show pairing, so this branch is only about the bookkeeping.
      PairingAccepted() => const PairingPhase.idle(),
      PairingRefused(:final PairingRefusal refusal) => PairingPhaseRefused(refusal),
    });
  }

  /// Asks before leaving, then leaves.
  ///
  /// The confirmation is not politeness: [SessionController.cancelPairing] is
  /// the only way back to a stored peer, and pressing it by accident costs the
  /// user a re-pair. Its Turkish message says what is **kept** as well as what is
  /// given up, because "you will lose everything" is the sentence a user hears
  /// when the real answer is "you will lose nothing".
  Future<void> _confirmCancel() async {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: PairingScreenKeys.cancelDialog,
        backgroundColor: style.role('surfaceOverlay'),
        title: Text(PairingTr.cancelTitle.tr),
        content: Text(PairingTr.cancelMessage.tr),
        actions: <Widget>[
          PairingActionButton(
            key: PairingScreenKeys.cancelDismiss,
            action: PairingAction(
              label: PairingTr.cancelDismissLabel.tr,
              filled: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            // A dialog's own surface is `surfaceOverlay`, so the strong-edge rule
            // applies to the emphasized button rather than being skipped.
            surfaceRole: 'surfaceOverlay',
          ),
          SizedBox(width: style.gap('2')),
          PairingActionButton(
            key: PairingScreenKeys.cancelConfirm,
            action: PairingAction(
              label: PairingTr.cancelConfirmLabel.tr,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            surfaceRole: 'surfaceOverlay',
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    await widget.controller.cancelPairing();
  }

  @override
  Widget build(BuildContext context) {
    // THE rule. One method, and no other question is asked anywhere in this file.
    if (!_state.showsPairingScreen) {
      return const SizedBox.shrink(key: PairingScreenKeys.hidden);
    }
    final AppearanceStyle style = AppearanceStyle.of(context);
    final bool swapping = _state is SetupNeedsPairing;

    // The blocks are collected first and then joined, rather than interleaved
    // with gaps: a block that is absent must not leave the gap that preceded it
    // behind, and `PairingScreenKeys.peerBlock` is absent whenever there is no
    // peer to replace.
    // A local rather than a second read of `widget.controller.peer`: Dart
    // promotes a local and not a getter on another object, and the whole point of
    // the block's absence is that it is decided once, here.
    final Widget? peer = swapping ? _peerPanel(style) : null;
    // BOTH panels, always. This used to be `swapping ? enter : code`, which
    // forced a role on the two devices before anyone had decided anything: one
    // side had to show a code and the other had to type it, and which side that
    // was depended on who ran setup first. That is a question with no good
    // answer and two bad ones, so the fix is to stop asking it. Either device
    // can show its code and type the other's, in either order.
    //
    // The cost is vertical space, and it is bounded: both panels sit inside the
    // scroll view, so a short window scrolls rather than overflows.
    // `expectNoOverflow` runs in all three window sizes.
    final List<Widget> blocks = <Widget>[
      _codePanel(),
      _enterPanel(),
      ?peer,
      if (_phase is PairingPhaseExchanging) _progressPanel(style),
      if (_phase is PairingPhaseRefused)
        ..._failureBlocks(_phase as PairingPhaseRefused),
    ];

    return Scaffold(
      backgroundColor: style.role('bg'),
      body: SafeArea(
        child: SingleChildScrollView(
          key: PairingScreenKeys.body,
          padding: EdgeInsets.all(style.gap('10')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MkviSectionHeader(
                key: PairingScreenKeys.heading,
                title: _state.title,
                description: _state.detail,
                surfaceRole: 'bg',
                // Leaving is offered exactly where it is possible: pairing a new
                // device over a stored one. On a first run there is nothing to go
                // back to, and offering a "go back" that goes nowhere is how a
                // dead control ships.
                actions: <MkviPanelAction>[
                  if (swapping)
                    MkviPanelAction(
                      label: PairingTr.cancelLabel.tr,
                      onPressed: _confirmCancel,
                    ),
                ],
              ),
              for (final Widget block in blocks) ...<Widget>[
                SizedBox(height: style.gap('6')),
                block,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _codePanel() {
    return MkviPanel.raised(
      key: PairingScreenKeys.codeBlock,
      child: PairingCodeView(copyToClipboard: widget.copyToClipboard),
    );
  }

  Widget _enterPanel() {
    return MkviPanel.raised(
      key: PairingScreenKeys.enterBlock,
      child: PairingEnter(
        controller: _code,
        busy: _phase is PairingPhaseExchanging,
        onSubmit: (String _) => _submit(),
      ),
    );
  }

  /// The peer this device already has, with its two names in two slots.
  ///
  /// `null` when there is no peer.
  ///
  /// That is not hypothetical: [SetupBroken] is the one state that
  /// `offersPairNewDevice`, and it is reachable with **no** stored peer — a read
  /// that failed has no peer to adopt — so the last resort lands here with
  /// nothing to name. A [PeerNameView] built out of nothing would show the
  /// placeholder "Kişi" as though a person called it were already paired on this
  /// device.
  ///
  /// The caller decides whether to place it, so an absent block never leaves the
  /// gap that would have preceded it behind.
  Widget? _peerPanel(AppearanceStyle style) {
    if (widget.controller.peer == null) return null;
    final PeerNameView names = widget.controller.names;
    return MkviPanel.soft(
      key: PairingScreenKeys.peerBlock,
      title: PairingTr.peerHeading.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MkviKeyValueRow(
            key: PairingScreenKeys.announcedRow,
            label: PairingTr.announcedNameLabel.tr,
            // The peer's own name, never the local note. This expression is the
            // whole reason this block exists.
            value: names.displayName,
          ),
          if (names.hasAlias) ...<Widget>[
            MkviKeyValueRow(
              key: PairingScreenKeys.aliasRow,
              label: PairingTr.aliasLabel.tr,
              value: names.alias,
            ),
            if (names.showsAnnouncedName) ...<Widget>[
              MkviDivider(startIndentStep: '2', endIndentStep: '2'),
              SizedBox(height: style.gap('2')),
              // The `src/ChatCallWorkspace.tsx:513` line, and the case the
              // TypeScript original could not draw: an annotation that happens to
              // equal the announced name. `showsAnnouncedName` asks about the
              // annotation, so the line is here precisely when it is hardest to
              // tell the two apart.
              Text(
                names.announcedNameLabel,
                key: PairingScreenKeys.announcedLine,
                style: style.styleOf('sm').copyWith(color: style.role('text')),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _progressPanel(AppearanceStyle style) {
    return MkviPanel.raised(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          MkviLinearProgress(
            key: PairingScreenKeys.progress,
            phase: widget.sweepPhase,
            heightStep: '4',
            label: PairingTr.progressLabel.tr,
          ),
          SizedBox(height: style.gap('3')),
          Text(
            PairingTr.progressTitle.tr,
            style: style.styleOf('lg').copyWith(color: style.role('text')),
          ),
          SizedBox(height: style.gap('2')),
          Text(
            PairingTr.progressNote.tr,
            style: style.styleOf('sm').copyWith(color: style.role('textMuted')),
          ),
        ],
      ),
    );
  }

  /// The refusal and, for a failure that is about the network rather than about
  /// the code, the action that sends the same code again.
  ///
  /// The action is **not** in [MkviErrorState]'s own `actions` list, which would
  /// be the idiomatic place for it. That list renders through
  /// `lib/ui/widgets`' `MkviActionButton`, which declares no `minimumSize` of its
  /// own and therefore inherits `Size(0, controls.md.height)` — 34 dp — from the
  /// resolved `filledButtonTheme`, against a `control.hitTargetMin` of 44. It
  /// clears the token today only because Material's `MaterialTapTargetSize.padded`
  /// hard-codes 48; see `pairing_action.dart`. The block keeps the two sentences
  /// it is required to have, and the screen offers the action with the token
  /// declared in the control itself.
  List<Widget> _failureBlocks(PairingPhaseRefused phase) => <Widget>[
    MkviErrorState(
      key: PairingScreenKeys.failure,
      title: PairingTr.failedTitle.tr,
      // Both sentences are required arguments, and both come from the layer that
      // refused: a screen that invented its own reason would be guessing at
      // something only the refusal knows.
      reason: phase.refusal.messageTr,
      message: phase.refusal.recoveryTr,
    ),
    if (phase.refusal.isWorthRetrying)
      PairingActionRow(
        actions: <PairingAction>[
          PairingAction(
            label: PairingTr.retryLabel.tr,
            filled: true,
            buttonKey: PairingScreenKeys.retry,
            onPressed: _submit,
          ),
        ],
        // The action row stands on the page, not on the error block's
        // `dangerFill`, so the filled action correctly takes no edge.
        surfaceRole: 'bg',
      ),
  ];
}
