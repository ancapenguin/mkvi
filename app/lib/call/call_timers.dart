/// The one scheduling seam of the call state machine.
///
/// TS: `window.setTimeout` inside `requestCall`, `src/services/peer-transport.ts:108`.
///
/// The machine has **no timer of its own** — not even as a default. `startTimer`
/// is a required constructor parameter, so a `Timer` can only exist in this
/// package if somebody wrote [asyncCallTimerStarter] at the call site. That makes
/// "no real `Timer` in any tested path" a structural property rather than a
/// convention, and it is why the ring timeout is testable at all: 0.1.x's missing
/// callee timer was untestable *and* unshippable, and this port pins both halves
/// of that at once.
library;

import 'dart:async';

/// Cancels a pending callback. Idempotent: calling it twice, or after the
/// callback has already fired, must be harmless.
typedef CallTimerCancel = void Function();

/// Schedules [onFire] after [delay] and returns the function that cancels it.
typedef CallTimerStarter =
    CallTimerCancel Function(Duration delay, void Function() onFire);

/// The production seam: a real `dart:async` timer.
///
/// Production wiring is one line — `CallMachine(startTimer: asyncCallTimerStarter)`
/// — and the test wiring is one line the other way, `startTimer: fake.start`. No
/// test in `test/call` uses this.
CallTimerCancel asyncCallTimerStarter(Duration delay, void Function() onFire) =>
    Timer(delay, onFire).cancel;

/// A seam that never fires and never cancels anything.
///
/// For a caller that does not want a 45 s timer at all — a widget test, or a
/// machine that is only being used to check the refusal paths.
CallTimerCancel disabledCallTimerStarter(
  Duration delay,
  void Function() onFire,
) => () {};
