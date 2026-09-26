/// The one scheduling seam of the call state machine.
///
/// The machine has **no timer of its own** — not even as a default. `startTimer`
/// is a required constructor parameter, so a `Timer` can only exist in this
/// package if somebody wrote [asyncCallTimerStarter] at the call site. That makes
/// "no real `Timer` in any tested path" a structural property rather than a
/// convention, and it is why the ring timeout is testable at all: a callee timer
/// nobody can start by accident is a timer a test can pin, and a callee timer that
/// can hang on screen forever is a defect that ships.
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
