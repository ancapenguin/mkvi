/// The one clock of the notice layer: it reads the time *and* it arms the
/// auto-dismissal.
///
/// TS: `window.setTimeout(() => setNotice(""), 5_500)` in an effect keyed on
/// `notice`, `src/App.tsx:183-187`. That effect cleaned the timer up and
/// re-armed it on every write, and the reconnect loop wrote roughly once a
/// second (`src/App.tsx:289`), so the 5.5 s never elapsed: the toast was
/// immortal. A re-arming timer is the bug, not a slow one.
///
/// The controller therefore has **no timer of its own**, not even as a default:
/// a [NoticeClock] is a required constructor parameter, so a `dart:async` `Timer`
/// can only exist in this layer if somebody wrote [systemNoticeClock]. Reading
/// the time and scheduling on the same seam is deliberate — a controller that
/// read a fake clock but armed a real timer would pass a test and still be
/// wrong in the app.
library;

import 'dart:async';

/// Cancels a pending callback. Idempotent: calling it twice, or after the
/// callback has already fired, must be harmless.
typedef NoticeTimerCancel = void Function();

/// The scheduling seam, as one object.
///
/// [now] is read on every write and on every automatic dismissal; [schedule]
/// arms the single outstanding auto-dismissal.
abstract interface class NoticeClock {
  /// The current time. Read once per operation, never cached: the rate limit is
  /// measured against the same reading that decided the deadline.
  DateTime now();

  /// Runs [onFire] after [delay] and returns the function that cancels it.
  NoticeTimerCancel schedule(Duration delay, void Function() onFire);
}

/// The production seam: `DateTime.now()` and a real `dart:async` timer.
///
/// Production wiring is one line — `NoticeController(clock: systemNoticeClock)`
/// — and the test wiring is one line the other way, `clock: fake`. No test under
/// `test/ui/notice` uses this class.
final class SystemNoticeClock implements NoticeClock {
  /// A const instance; the class holds no state.
  const SystemNoticeClock();

  @override
  DateTime now() => DateTime.now();

  @override
  NoticeTimerCancel schedule(Duration delay, void Function() onFire) =>
      Timer(delay, onFire).cancel;
}

/// The production seam, as a value.
const NoticeClock systemNoticeClock = SystemNoticeClock();

/// A seam that never fires and reports a frozen time.
///
/// For a caller that does not want an auto-dismissal at all — a widget test
/// that is about layout, or a screen that must keep one notice up until the
/// user reads it. A notice written through this clock is effectively sticky
/// because the callback that would dismiss it never runs.
final class DisabledNoticeClock implements NoticeClock {
  /// Creates a clock frozen at [frozenAt], or at the Unix epoch when omitted.
  const DisabledNoticeClock([this.frozenAt]);

  /// The single instant this clock ever reports.
  final DateTime? frozenAt;

  @override
  DateTime now() => frozenAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  @override
  NoticeTimerCancel schedule(Duration delay, void Function() onFire) => () {};
}
