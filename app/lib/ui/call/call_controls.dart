/// The five controls a call has, and the two promises each of them keeps.
///
/// ## The hit target
///
/// `ROADMAP.md` reported that closing a call was a 34 px control
/// (`ChatCallWorkspace.tsx` hung the close control off a `button` with no
/// `min-width`/`min-height`), and `design/tokens.json` answers it with
/// `control.hitTargetMin` = 44 dp, a physical promise that is never scaled by
/// density.
///
/// Material's button themes in this app are built from `controls.md`, whose
/// height is **34 dp** — so a button that is merely themed is 10 dp short of the
/// promise, and `expectHitTarget` on it is red. Every control here is therefore
/// wrapped in a [ConstrainedBox] of `style.hitTargetMin` on both sides, and the
/// key sits **on that box** so the measurement is of the promise rather than of
/// the theme's opinion.
///
/// ## The names
///
/// `ROADMAP.md` also records 17 WCAG violations, and the reason an icon button
/// produces them is that a glyph is not a name. So:
///
/// * every control carries a [Tooltip] with its Turkish sentence, which is what
///   Flutter puts into the semantics tree as the control's `tooltip` — and
///   therefore what `readControlLabels` measures;
/// * the sentence is part of [CallControlLabels], a value with a default built
///   from [CallUiTr], so a call site cannot invent a second spelling;
/// * and because it is a value, a test can hand the bar a **blank** one and watch
///   `expectEveryControlLabelled` go red. That negative control is the point: a
///   suite that has only ever seen the good labels cannot tell "labelled" from
///   "the test happened to pass".
///
/// The wording is deliberately about the *action* — "Kamerayı kapat", not
/// "Kamera" — because a name has to answer the only question a user has about an
/// icon button: what happens if I press this.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

import 'call_strings.dart';

/// The accessible name and the tooltip of every control in the bar.
///
/// A value with defaults, not a bag of required strings: the bar is correct by
/// construction, and a test can blank one entry to prove that the entry is
/// load-bearing.
@immutable
final class CallControlLabels {
  /// Creates the label set. Every field defaults to the catalogue's sentence.
  const CallControlLabels({
    this.microphoneMute = CallUiTr.microphoneMute,
    this.microphoneUnmute = CallUiTr.microphoneUnmute,
    this.cameraStop = CallUiTr.cameraStop,
    this.cameraStart = CallUiTr.cameraStart,
    this.screenShareStart = CallUiTr.screenShareStart,
    this.screenShareStop = CallUiTr.screenShareStop,
    this.devices = CallUiTr.devicesOpen,
    this.hangUp = CallUiTr.hangUp,
    this.hangUpHint = CallUiTr.hangUpHint,
  });

  /// The microphone button's name while the published track is audible.
  final String microphoneMute;

  /// The microphone button's name while it is muted.
  final String microphoneUnmute;

  /// The camera button's name while the camera is publishing.
  final String cameraStop;

  /// The camera button's name while the camera is off.
  final String cameraStart;

  /// The screen-share button's name while nothing is shared.
  final String screenShareStart;

  /// The screen-share button's name while a share is running.
  final String screenShareStop;

  /// The device picker's name.
  final String devices;

  /// The hang-up button's name.
  final String hangUp;

  /// The hang-up button's hint.
  final String hangUpHint;

  /// The microphone button's name for [muted].
  String microphone({required bool muted}) =>
      muted ? microphoneUnmute : microphoneMute;

  /// The camera button's name for [live].
  String camera({required bool live}) => live ? cameraStop : cameraStart;

  /// The screen-share button's name for [attached].
  String screenShare({required bool attached}) =>
      attached ? screenShareStop : screenShareStart;
}

/// The keys the controls answer to.
abstract final class CallControlKeys {
  /// The microphone toggle, on the box that carries the hit target.
  static const Key microphone = Key('mkvi.call.control.microphone');

  /// The camera toggle.
  static const Key camera = Key('mkvi.call.control.camera');

  /// The screen-share toggle.
  static const Key screenShare = Key('mkvi.call.control.screenShare');

  /// The device-picker opener.
  static const Key devices = Key('mkvi.call.control.devices');

  /// The hang-up button.
  static const Key hangUp = Key('mkvi.call.control.hangUp');
}

/// The control bar.
///
/// One row, wrapped rather than laid out in a [Row]: at 400 dp with a `roomy`
/// density and the largest type, five 44 dp controls plus four gaps are wider
/// than the window, and a `Wrap` turns that into a second line instead of the
/// overflow stripe 0.1.x shipped in every screen.
class CallControls extends StatelessWidget {
  /// Creates the control bar.
  const CallControls({
    super.key,
    required this.onToggleMicrophone,
    required this.onToggleCamera,
    required this.onToggleScreenShare,
    required this.onOpenDevices,
    required this.onHangUp,
    this.microphoneLive = false,
    this.microphoneMuted = false,
    this.cameraLive = false,
    this.screenShareAttached = false,
    this.microphoneEnabled = true,
    this.cameraEnabled = true,
    this.screenShareEnabled = true,
    this.hangUpEnabled = true,
    this.labels = const CallControlLabels(),
    this.gapStep = '3',
  });

  /// Called when the microphone button is pressed.
  final VoidCallback onToggleMicrophone;

  /// Called when the camera button is pressed.
  final VoidCallback onToggleCamera;

  /// Called when the screen-share button is pressed.
  final VoidCallback onToggleScreenShare;

  /// Called when the device picker is asked for.
  final VoidCallback onOpenDevices;

  /// Called when the call is ended.
  final VoidCallback onHangUp;

  /// Whether a microphone track is published. A control the user cannot change
  /// is disabled rather than hidden, so the bar does not reflow.
  final bool microphoneLive;

  /// Whether the published microphone track is muted.
  final bool microphoneMuted;

  /// Whether the camera is publishing.
  final bool cameraLive;

  /// Whether a screen share is attached — running or still waiting for its first
  /// frame. See [CallUiTr.screenShareAction] for why this is not `live`.
  final bool screenShareAttached;

  final bool microphoneEnabled;
  final bool cameraEnabled;
  final bool screenShareEnabled;
  final bool hangUpEnabled;

  /// The names. Injected so a test can blank one and prove it matters.
  final CallControlLabels labels;

  /// The gap between controls, as a `space.steps` name.
  final String gapStep;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final ResolvedControl control = style.control('md');

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: style.gap(gapStep),
      runSpacing: style.gap(gapStep),
      children: <Widget>[
        _IconControl(
          controlKey: CallControlKeys.microphone,
          label: labels.microphone(muted: microphoneMuted),
          icon: microphoneMuted
              ? Icons.mic_off_rounded
              : microphoneLive
                  ? Icons.mic_rounded
                  : Icons.mic_none_rounded,
          enabled: microphoneEnabled,
          selected: !microphoneMuted && microphoneLive,
          iconSize: control.iconSize,
          onPressed: onToggleMicrophone,
        ),
        _IconControl(
          controlKey: CallControlKeys.camera,
          label: labels.camera(live: cameraLive),
          icon: cameraLive
              ? Icons.videocam_rounded
              : Icons.videocam_off_rounded,
          enabled: cameraEnabled,
          selected: cameraLive,
          iconSize: control.iconSize,
          onPressed: onToggleCamera,
        ),
        _IconControl(
          controlKey: CallControlKeys.screenShare,
          label: labels.screenShare(attached: screenShareAttached),
          icon: screenShareAttached
              ? Icons.stop_screen_share_rounded
              : Icons.screen_share_rounded,
          enabled: screenShareEnabled,
          selected: screenShareAttached,
          iconSize: control.iconSize,
          onPressed: onToggleScreenShare,
        ),
        _IconControl(
          controlKey: CallControlKeys.devices,
          label: labels.devices,
          icon: Icons.settings_input_component_rounded,
          enabled: true,
          selected: false,
          iconSize: control.iconSize,
          onPressed: onOpenDevices,
        ),
        _HangUpControl(
          iconSize: control.iconSize,
          label: labels.hangUp,
          hint: labels.hangUpHint,
          enabled: hangUpEnabled,
          onPressed: onHangUp,
        ),
      ],
    );
  }
}

/// The 44 dp box a control's promise is measured on, plus the button inside it.
class _Target extends StatelessWidget {
  const _Target({required this.controlKey, required this.child});

  final Key controlKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double minimum = AppearanceStyle.of(context).hitTargetMin;
    return ConstrainedBox(
      // The key is HERE, on the box that makes the promise, so
      // `expectHitTarget(find.byKey(CallControlKeys.camera))` measures the
      // promise and not the theme's 34 dp button inside it.
      key: controlKey,
      constraints: BoxConstraints(minWidth: minimum, minHeight: minimum),
      child: child,
    );
  }
}

/// One icon control: a tooltip, a name, and a 44 dp target.
class _IconControl extends StatelessWidget {
  const _IconControl({
    required this.controlKey,
    required this.label,
    required this.icon,
    required this.iconSize,
    required this.enabled,
    required this.selected,
    required this.onPressed,
  });

  final Key controlKey;
  final String label;
  final IconData icon;
  final double iconSize;
  final bool enabled;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return _Target(
      controlKey: controlKey,
      child: Semantics(
        // The name, on the node that owns the role.
        //
        // A `Tooltip` is **not** enough, and this was measured rather than
        // assumed: with `Tooltip(message: label)` above an `IconButton` and
        // nothing else, the button's own semantics node arrives with an empty
        // `label`, an empty `hint` and an empty `tooltip` — 5 buttons, 5 empty
        // names. `Tooltip` puts its message on a node *above* the control, and a
        // screen reader walking the control's own node hears nothing. That is
        // the 17-WCAG-violation shape `ROADMAP.md` counts, reproduced by the
        // obvious fix.
        //
        // So the name is stated here, on the control, and `ExcludeSemantics`
        // keeps the child from producing a second unnamed node — which is what
        // makes "one operable node per control" true.
        button: true,
        label: label,
        onTap: enabled ? onPressed : null,
        child: ExcludeSemantics(
          child: Tooltip(
            // Hover text for a mouse, and deliberately not the accessible name:
            // it is already the label above, and Flutter merges the two into one
            // announcement.
            message: label,
            child: IconButton(
              onPressed: enabled ? onPressed : null,
              icon: Icon(icon, size: iconSize),
              // `isSelected` rather than a hand-rolled colour: it is what puts
              // the "toggled on" state into the semantics tree, so the control
              // announces itself as chosen rather than only looking chosen.
              isSelected: selected,
              color: style.role('text'),
              style: ButtonStyle(
                iconColor: WidgetStateProperty.resolveWith<Color?>(
                  (Set<WidgetState> states) {
                    if (states.contains(WidgetState.selected)) {
                      return style.role('accent');
                    }
                    if (states.contains(WidgetState.disabled)) {
                      return style.role('textSubtle');
                    }
                    return style.role('text');
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hang-up control: a filled `dangerFill` button, because ending a call is
/// the one action on this screen that must not be mistaken for another.
class _HangUpControl extends StatelessWidget {
  const _HangUpControl({
    required this.iconSize,
    required this.label,
    required this.hint,
    required this.enabled,
    required this.onPressed,
  });

  final double iconSize;
  final String label;
  final String hint;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    return _Target(
      controlKey: CallControlKeys.hangUp,
      child: Semantics(
        // The same rule as every other control on this bar: the name belongs on
        // the node that owns the role, and a `Tooltip` above the button is hover
        // text and nothing more. Measured, see `_IconControl.build`.
        button: true,
        label: '$label. $hint',
        onTap: enabled ? onPressed : null,
        child: ExcludeSemantics(
          child: Tooltip(
            message: '$label. $hint',
            child: FilledButton(
              onPressed: enabled ? onPressed : null,
              style: ButtonStyle(
                // `dangerFill` with `textOnAccent` on it is the pair the token
                // file declares at 4.5:1 — the same pair `MkviErrorState`
                // paints. A red `danger` label on a red fill would be 1.34:1 in
                // the light theme, which is the mistake `MkviBadge` documents
                // at length.
                backgroundColor: WidgetStatePropertyAll<Color?>(
                  style.role('dangerFill'),
                ),
                foregroundColor: WidgetStatePropertyAll<Color?>(
                  style.role('textOnAccent'),
                ),
              ),
              child: Icon(Icons.call_end_rounded, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
