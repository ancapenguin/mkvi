/// The code **entry**: `MkviCodeField` and the one control that sends it.
///
/// ## The field is not re-implemented here
///
/// `MkviCodeField` already owns everything that makes a pairing code safe to
/// type: it calls `normalizePairingCode` from a `TextInputFormatter` (so a paste
/// of `abcd efgh-jklmn` fills all thirteen cells), it drops `I`, `O`, `0` and
/// `1` at the source instead of explaining them in the UI, it reports an input
/// of nothing the alphabet accepts rather than swallowing it, and it refuses a
/// short code on submit. `lib/signaling/pairing_code.dart` is the only definition
/// of a pairing code and this file re-derives none of it.
///
/// ## The gate, and why it is a locked button rather than a message
///
/// The send control is `onPressed: null` unless
/// `isAcceptedPairingCode(normalizePairingCode(value))` is true. A button that
/// is present, enabled and refuses on press is the worst of the three options: it
/// tells the user the action is available and then does nothing. A locked button
/// plus the Turkish reason under the field is what the user can act on.
///
/// The reason sentence is cleared by the next keystroke rather than persisting,
/// because "Kod eksik: 9 karakter daha gerekiyor" is a statement about a value
/// that no longer exists, and a form that keeps correcting a value the user has
/// already fixed is how a form starts shouting.
///
/// ## One sentence, from one layer
///
/// The reason comes from [PairingTr] here and from `MkviCodeTr` inside the
/// field. That is a duplication, and it is the honest one: the field owns what it
/// can say *while it is being edited* and this block owns what it can say *after
/// a send was refused*. The two are never on screen for the same state — the
/// field hides its own line while it has focus, and this line only exists after
/// a submit that never left the device.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/signaling/pairing_code.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'pairing_action.dart';
import 'pairing_strings.dart';

/// The keys this block's parts answer to.
abstract final class PairingEnterKeys {
  /// The whole block.
  static const Key block = Key('mkvi.pairing.enter.block');

  /// The send control — locked or not, and the test asks the widget, not the
  /// ripple.
  static const Key submit = Key('mkvi.pairing.enter.submit');

  /// The Turkish reason a refused send produced. Absent while there is none.
  static const Key error = Key('mkvi.pairing.enter.error');

  /// The one-time-use promise under the field.
  static const Key onceNote = Key('mkvi.pairing.enter.once');

  /// The hint above the field, before anything is typed.
  static const Key hint = Key('mkvi.pairing.enter.hint');
}

/// Whether [code] can be sent, and the Turkish reason when it cannot.
///
/// One function, called from two places — the gate on the button and the sentence
/// under it — so the button and the sentence can never disagree about the same
/// value. It is the only place in this directory that decides anything about a
/// code, and it decides it with `isAcceptedPairingCode`, which is the Worker's
/// own rule.
({bool accepted, String? reason}) pairingCodeProblem(String code) {
  final String clean = normalizePairingCode(code);
  if (isAcceptedPairingCode(clean)) {
    return (accepted: true, reason: null);
  }
  if (clean.isEmpty) {
    return (accepted: false, reason: PairingTr.emptyCode.tr);
  }
  if (clean.length < pairingCodeLength) {
    return (
      accepted: false,
      reason: PairingTr.tooShort.format(pairingCodeLength - clean.length),
    );
  }
  return (accepted: false, reason: PairingTr.invalidCode.tr);
}

/// The entry block: a pairing code field and the control that sends it.
///
/// [controller] is owned by the screen, not here, because the screen has to be
/// able to read the value back after a failed exchange in order to offer "send
/// the same code again". Nothing is disposed here.
class PairingEnter extends StatefulWidget {
  /// Creates the entry block.
  const PairingEnter({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.busy = false,
    this.autofocus = false,
  });

  /// The text, owned by the screen.
  final TextEditingController controller;

  /// Called with a normalised, accepted code — and with nothing else, ever.
  final ValueChanged<String> onSubmit;

  /// Whether an exchange is in flight. Locks the control and changes its label.
  final bool busy;

  /// Whether the field takes the keyboard on first build.
  ///
  /// **Off by default, and that is a decision about a defect rather than about
  /// taste.** `MkviCodeField` hides its own error line while it has focus
  /// (`_showsError` needs `!_focused || _submitted`), and on an autofocused field
  /// focus does not leave: measured on this branch, `FocusManager.primaryFocus
  /// ?.unfocus()` after an `autofocus: true` field has typed leaves
  /// `focusNode.hasFocus == true` and `primaryFocus == node`, while the identical
  /// sequence on a non-autofocused field clears both.
  ///
  /// The consequence is that on an autofocused field the "Kodda kullanılamayan
  /// karakterler var" sentence — the one the field exists to show instead of
  /// silently swallowing the input — can never appear. A field that cannot report
  /// what it refused is worse than a field that needs one tap, so the default is
  /// off and the shell that wants the keyboard can turn it on knowingly. The
  /// fix belongs in `lib/ui/widgets/mkvi_code_field.dart`.
  final bool autofocus;

  @override
  State<PairingEnter> createState() => _PairingEnterState();
}

class _PairingEnterState extends State<PairingEnter> {
  /// The Turkish reason the last *send* was refused, or `null`.
  ///
  /// Set only from `onRejected` — the keyboard's own submit path — because the
  /// button cannot be pressed while the code is unacceptable. A user who typed
  /// nine characters and hit the keyboard's arrow is exactly the case the field's
  /// "hide the error while I am typing" rule would otherwise say nothing about.
  String? _refused;

  /// The normalised value [_refused] is a sentence *about*.
  ///
  /// Not the whole `_refused` string: the reason a user is owed a fresh one is
  /// that the value it described has changed, and a controller notification that
  /// only moved the caret is not that.
  String _refusedFor = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  /// Rebuilds on every notification, and drops the standing complaint when — and
  /// only when — the value it was about is gone.
  ///
  /// The rebuild is unconditional: the control's locked state is read from the
  /// controller's value at build time, so a block that only rebuilt on a refusal
  /// would leave the control locked after the code became acceptable, and a send
  /// button that ignores the field's value is a dead control.
  ///
  /// The comparison is on the *normalised* text and not on the notification
  /// itself, because `EditableText` sends a second `updateEditingValue` when a
  /// keyboard submit finalises the editing state, and that one only moves the
  /// caret. Clearing on it wiped the refusal in the same frame it was given,
  /// which is how "the keyboard's submit says nothing" shipped.
  void _onTextChanged() {
    if (!mounted) return;
    final String value = normalizePairingCode(widget.controller.text);
    setState(() {
      if (_refused != null && value != _refusedFor) _refused = null;
    });
  }

  void _send() {
    final String code = normalizePairingCode(widget.controller.text);
    final ({bool accepted, String? reason}) problem = pairingCodeProblem(code);
    if (!problem.accepted) {
      setState(() {
        _refused = problem.reason;
        _refusedFor = code;
      });
      return;
    }
    setState(() => _refused = null);
    widget.onSubmit(code);
  }

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    // Read from the controller rather than from a mirrored field, so a value
    // written by anything else — a paste, a deep link, a future "read it from
    // the clipboard" button — goes through exactly the same gate.
    final ({bool accepted, String? reason}) problem = pairingCodeProblem(
      widget.controller.text,
    );
    final bool locked = !problem.accepted || widget.busy;

    return Column(
      key: PairingEnterKeys.block,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          PairingTr.enterHint.tr,
          key: PairingEnterKeys.hint,
          style: style.styleOf('md').copyWith(color: style.role('text')),
        ),
        SizedBox(height: style.gap('3')),
        MkviCodeField(
          controller: widget.controller,
          // The field's own Turkish label, not a new one: the label is the
          // field's name and two names for one value is how a form ends up
          // ambiguous.
          label: MkviCodeTr.fieldLabel.tr,
          autofocus: widget.autofocus,
          // `MkviCodeField` is a gate, not a notification: it calls
          // `onSubmitted` only for a code `isAcceptedPairingCode` accepts and
          // `onRejected` for everything else. Wiring one and not the other is how
          // a keyboard submit ends up saying nothing at all.
          onSubmitted: (String code) {
            final String clean = normalizePairingCode(code);
            setState(() => _refused = null);
            widget.onSubmit(clean);
          },
          onRejected: (String code) {
            final String clean = normalizePairingCode(code);
            final ({bool accepted, String? reason}) refused = pairingCodeProblem(
              clean,
            );
            setState(() {
              _refused = refused.reason;
              _refusedFor = clean;
            });
          },
        ),
        SizedBox(height: style.gap('2')),
        Text(
          PairingTr.enterOnceNote.tr,
          key: PairingEnterKeys.onceNote,
          style: style.styleOf('sm').copyWith(color: style.role('textMuted')),
        ),
        if (_refused != null) ...<Widget>[
          SizedBox(height: style.gap('2')),
          Text(
            _refused!,
            key: PairingEnterKeys.error,
            style: style.styleOf('sm').copyWith(color: style.role('danger')),
          ),
        ],
        SizedBox(height: style.gap('4')),
        PairingActionButton(
          key: PairingEnterKeys.submit,
          action: PairingAction(
            label: widget.busy
                ? PairingTr.submittingLabel.tr
                : PairingTr.submitLabel.tr,
            filled: true,
            onPressed: locked ? null : _send,
          ),
          // Inside the screen's `surfaceRaised` panel, so the strong edge rule
          // applies to the one filled control on the screen.
          surfaceRole: 'surfaceRaised',
        ),
      ],
    );
  }
}
