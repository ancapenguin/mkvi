/// The screen 0.1.4 did not have: the one a callee sees instead of a call that
/// opens by itself.
///
/// ## Why this file is the answer to reported defect 3
///
/// `ROADMAP.md`: "Cevap ekranı yok, arama direkt açılıyor — 0.1.4'te otomatik kabul
/// vardı; cevap ekranı hiç yayımlanmamıştı." The state machine already closed the
/// hole — `CallMachine.accept()` is the only door to `connected`, and a refused
/// accept puts no frame on the wire and asks for no media — but a state machine
/// nobody can see is not an answer to a person whose camera opened by itself.
///
/// So the screen has exactly one job beyond showing two buttons: **it must never
/// render the stage.** [CallStageKeys.surface] is absent while
/// [CallMachine.status] is [CallStatus.incoming], and
/// `test/ui/call/incoming_call_test.dart` asserts that absence, because
/// "the answer screen is up" and "the call has opened" are the two claims the
/// reported defect conflates.
///
/// ## The countdown
///
/// The callee-side 45 s ring timer (`CallMachine.callRingTimeout`) is the timer
/// 0.1.x did not have at all, which is why a ringing dialog could sit on screen
/// forever. The screen shows the time that is left, and the number is derived
/// from `CallSession.startedAt` and the machine's own `ringTimeout` — never a
/// second copy of "45" written into a widget, because two copies of a timeout is
/// how the two 45 s timers of `call_incoming_test.dart` stop meaning what they
/// say.
///
/// ## The two buttons
///
/// `accept` is **filled**, `decline` is **outlined**, on a `surfaceRaised` panel
/// — so the one the user should press is the one with a fill, and both take the
/// `borderStrong` edge by the rule `MkviPanelVariant.givesFilledActionsAnEdge`
/// implements. Both are inside a [ConstrainedBox] of `style.hitTargetMin`,
/// because the panel's action strip is built from `controls.md` (34 dp) and the
/// promise is 44.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart' show CallMode;
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'call_screen.dart' show callCountdownTick;
import 'call_strings.dart';

/// The keys the answer screen answers to.
abstract final class IncomingCallKeys {
  /// The whole screen, so a test can assert it is up as one thing.
  static const Key screen = Key('mkvi.call.incoming.screen');

  /// The eyebrow above the title.
  static const Key eyebrow = Key('mkvi.call.incoming.eyebrow');

  /// The title, i.e. the peer's name.
  static const Key title = Key('mkvi.call.incoming.title');

  /// The remaining-seconds line. Its own key because "the countdown is on screen"
  /// is a claim about this widget and not about the text of some other one.
  static const Key countdown = Key('mkvi.call.incoming.countdown');

  /// The sentence that promises nothing is sent before the user accepts.
  static const Key promise = Key('mkvi.call.incoming.promise');

  /// The accept button, on the box that carries its hit target.
  static const Key accept = Key('mkvi.call.incoming.accept');

  /// The decline button, on the box that carries its hit target.
  static const Key decline = Key('mkvi.call.incoming.decline');
}

/// The answer screen.
///
/// Every string is Turkish and every one of them is a **required** argument, so
/// this widget cannot be built with no wording — the same rule
/// [MkviErrorState] follows for a reason.
class IncomingCallScreen extends StatelessWidget {
  /// Creates the answer screen.
  const IncomingCallScreen({
    super.key,
    required this.peerName,
    required this.mode,
    required this.remainingSeconds,
    required this.onAccept,
    required this.onDecline,
    required this.onRefresh,
    this.countdownTick = callCountdownTick,
    this.accepting = false,
  });

  /// Who is calling. Shown in the title as `X arıyor`, which is
  /// [CallMessages.peerIsCalling]'s own sentence rather than a second spelling.
  final String peerName;

  /// Whether the invitation is for audio or video, which is what the eyebrow
  /// says. One of the two `CallMode` values, so this can never be a mode the
  /// machine does not have.
  final CallMode mode;

  /// How long the callee-side ring timeout has left, in whole seconds. Already
  /// clamped to zero by the host.
  final int remainingSeconds;

  /// How often the countdown asks for a fresh read.
  ///
  /// Injected rather than read from `AppearanceStyle.duration(...)`, because those
  /// are *animation* lengths that reduced-motion replaces with `instant`, and a
  /// countdown that stopped counting would read `Kalan süre: 45 sn` for ever.
  final Duration countdownTick;

  /// Asks whoever owns the machine for a fresh countdown.
  ///
  /// Required, and the reason it is not a clock of this screen's own: the ring
  /// timeout and its deadline belong to `CallMachine`, and a second copy of "45"
  /// inside a widget is how the two 45 s timers of `call_incoming_test.dart`
  /// stop meaning what they say. The screen asks; the owner answers.
  final VoidCallback onRefresh;

  /// Called when the user accepts. The only path to `connected`.
  final VoidCallback onAccept;

  /// Called when the user declines.
  final VoidCallback onDecline;

  /// Whether an accept is already in flight.
  ///
  /// [CallMachine.accept] is idempotent, so a second press is harmless — but a
  /// *disabled* button is honest about it, and the count of frames on the wire
  /// is asserted separately in `incoming_call_test.dart`.
  final bool accepting;

  /// How many `lg` control heights wide the panel is allowed to be. See the
  /// `BoxConstraints` in [build]: a proportion, never a pixel.
  static const int _panelWidthInLgHeights = 12;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final double minimum = style.hitTargetMin;

    return ColoredBox(
      key: IncomingCallKeys.screen,
      // `bg`: the window's own background. The stage is the only `stage`
      // rectangle on this screen, and it is not here.
      color: style.role('bg'),
      child: _CountdownRefresh(
        period: countdownTick,
        onTick: onRefresh,
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              // A width cap rather than a margin, so the panel is a readable
              // column in a 1280 dp window and a full-width card in a 400 dp one.
              // Twelve `lg` control heights: a proportion, not a pixel, so it
              // follows the user's density.
              constraints: BoxConstraints(
                maxWidth: style.control('lg').height * _panelWidthInLgHeights,
              ),
              child: Padding(
                padding: EdgeInsets.all(style.gap('8')),
                child: MkviPanel.raised(
                  child: _body(style, minimum),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The panel's contents, split out so the layout closure above stays readable.
  Widget _body(AppearanceStyle style, double minimum) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          CallUiReused.eyebrow(mode),
          key: IncomingCallKeys.eyebrow,
          textAlign: TextAlign.center,
          style: style
              .styleOf('sm')
              .copyWith(color: style.role('textMuted')),
        ),
        SizedBox(height: style.gap('2')),
        Text(
          CallUiReused.title(peerName),
          key: IncomingCallKeys.title,
          textAlign: TextAlign.center,
          style: style.styleOf('xl').copyWith(color: style.role('text')),
        ),
        SizedBox(height: style.gap('4')),
        Center(child: _countdown(style)),
        SizedBox(height: style.gap('4')),
        Text(
          CallUiReused.promise,
          key: IncomingCallKeys.promise,
          textAlign: TextAlign.center,
          style: style
              .styleOf('sm')
              .copyWith(color: style.role('textMuted')),
        ),
        SizedBox(height: style.gap('8')),
        // A Wrap, so the two buttons become two lines in a 400 dp window at the
        // largest type rather than an overflow stripe. The order is
        // decline-then-accept on purpose: the button that ends the interaction is
        // not the one the eye lands on.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: style.gap('4'),
          runSpacing: style.gap('4'),
          children: <Widget>[
            ConstrainedBox(
              key: IncomingCallKeys.decline,
              constraints: BoxConstraints(
                minWidth: minimum,
                minHeight: minimum,
              ),
              child: OutlinedButton(
                onPressed: onDecline,
                child: Text(
                  CallUiReused.decline,
                  style: style.styleOf('md').copyWith(color: style.role('text')),
                ),
              ),
            ),
            ConstrainedBox(
              key: IncomingCallKeys.accept,
              constraints: BoxConstraints(
                minWidth: minimum,
                minHeight: minimum,
              ),
              child: FilledButton(
                onPressed: accepting ? null : onAccept,
                child: Text(
                  CallUiReused.accept,
                  style: style.styleOf('md').copyWith(
                    color: style.role('textOnAccent'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The remaining-seconds line: a pill, so the number is a thing on the screen
  /// rather than a sentence the eye has to find inside one.
  ///
  /// Built here rather than with `MkviBadge`, for a measured reason: the badge's
  /// inner `Row` is `MainAxisSize.min`, which lays its children out with an
  /// *unbounded* main axis, so a label wider than the column it stands in
  /// overflows instead of wrapping. Measured at a 400 dp window with the largest
  /// type this application offers, "Kalan süre: 45 sn" overflows that row by
  /// 9.3 px. The fix is one `Flexible`, and it belongs on the side of the badge
  /// that owns the string rather than on the shared widget.
  Widget _countdown(AppearanceStyle style) {
    final String text = CallUiTr.remainingSeconds(remainingSeconds);
    return Semantics(
      // The *hint* is what tells a screen reader the number is a deadline rather
      // than an id, and the pill's own text is carried as the *value* so it is
      // read once and not twice.
      label: CallUiTr.countdownHint,
      value: text,
      child: ExcludeSemantics(
        child: Container(
          key: IncomingCallKeys.countdown,
          padding: EdgeInsets.symmetric(
            horizontal: style.gap('3'),
            vertical: style.gap('1'),
          ),
          decoration: BoxDecoration(
            color: style.role('accentSoft'),
            borderRadius: style.shape('pill').borderRadius,
            border: Border.all(
              color: style.role('border'),
              width: style.borderWidth,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.timer_outlined,
                size: style.control('sm').iconSize,
                color: style.role('text'),
              ),
              SizedBox(width: style.gap('2')),
              // `Flexible` is the whole difference between wrapping and
              // overflowing here; see this method's doc comment.
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: style.styleOf('sm').copyWith(color: style.role('text')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The screen's own clock: one request for a fresh countdown per [period].
///
/// ## Why this is a `State` and not the host's timer
///
/// The obvious place for a countdown is the object that computes it, and putting
/// the timer there is a mistake with a measurable cost: the host is not a widget,
/// so nothing unmounts it, and the timer outlives the answer screen. Every widget
/// test that pumps a ringing call then fails on
///
/// ```text
/// A Timer is still pending even after the widget tree was disposed.
/// ```
///
/// even though the framework *does* dispose the tree before that check. A `State`
/// is cancelled by `dispose`, and a screen that is not on screen has nothing to
/// count down, so the ticker's lifetime is exactly the countdown's lifetime.
///
/// ## Why it does not make `pumpAndSettle` hang
///
/// `pumpAndSettle` stops as soon as a pump finds no scheduled frame, and this
/// timer is due a whole [period] after the frame that created it. So a settled
/// tree stays settled, while a test that *wants* the countdown to move pumps for
/// a second and sees it.
class _CountdownRefresh extends StatefulWidget {
  const _CountdownRefresh({
    required this.period,
    required this.onTick,
    required this.child,
  });

  final Duration period;
  final VoidCallback onTick;
  final Widget child;

  @override
  State<_CountdownRefresh> createState() => _CountdownRefreshState();
}

class _CountdownRefreshState extends State<_CountdownRefresh> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_CountdownRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.period, (Timer _) => widget.onTick());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
