/// The reconnect backoff, as a pure function.
///
/// `src/App.tsx:216` starts at `let delay = 700`, `src/App.tsx:306` multiplies
/// by 1.8 and caps at 12 seconds, and `src/App.tsx:289` only starts telling the
/// user about it once the sleep reaches 2.8 seconds. All three are integers, and
/// modelling them as a function of the consecutive-failure count is what makes
/// the schedule testable without waiting 40 seconds for it.
///
/// The arithmetic is done in integers on purpose. `Math.round(delay * 1.8)` in
/// double precision is reproducible for a while and then quietly stops being
/// reproducible as the mantissa runs out, and a backoff schedule that drifts is
/// a backoff schedule nobody can pin in a test.
library;

/// TS: `let delay = 700` at `src/App.tsx:216` and `delay = 700` at
/// `src/App.tsx:285`.
const Duration initialReconnectDelay = Duration(milliseconds: 700);

/// TS: `Math.min(12_000, ...)` at `src/App.tsx:306`.
const Duration maxReconnectDelay = Duration(seconds: 12);

/// TS: the `* 1.8` at `src/App.tsx:306`.
const double reconnectBackoffFactor = 1.8;

/// TS: the `delay >= 2_800` that gates the user-visible notice at
/// `src/App.tsx:289`. Below this the loop is still inside normal startup jitter
/// and a toast per attempt would be the first thing a user learns to ignore.
const Duration reconnectNoticeThreshold = Duration(milliseconds: 2800);

/// The sleep before attempt number `consecutiveFailures + 1`.
///
/// [consecutiveFailures] is 0 for the first failure, so this is
/// `initialReconnectDelay` on the first failure and grows by 1.8 each time,
/// clamped to [maxReconnectDelay]. A success resets the counter, which is what
/// `delay = 700` at `src/App.tsx:285` does.
Duration reconnectBackoffDelay(int consecutiveFailures) {
  if (consecutiveFailures < 0) {
    throw ArgumentError.value(
      consecutiveFailures,
      'consecutiveFailures',
      'must not be negative',
    );
  }
  int millis = initialReconnectDelay.inMilliseconds;
  for (int step = 0; step < consecutiveFailures; step += 1) {
    millis = _nextBackoffMillis(millis);
  }
  return Duration(milliseconds: millis);
}

/// Whether the loop should tell the user about failure number
/// `consecutiveFailures`. TS: `if (!cancelled && delay >= 2_800)` at
/// `src/App.tsx:289`.
bool shouldReportReconnectFailure(int consecutiveFailures) =>
    reconnectBackoffDelay(consecutiveFailures).inMilliseconds >=
    reconnectNoticeThreshold.inMilliseconds;

/// The first `count` delays, for a UI that wants to show a progress hint.
List<Duration> reconnectBackoffSchedule(int count) {
  if (count < 0) {
    throw ArgumentError.value(count, 'count', 'must not be negative');
  }
  return List<Duration>.generate(count, reconnectBackoffDelay);
}

/// `Math.round(millis * 1.8)` clamped to the cap, in integers.
///
/// `round(x)` for positive `x` is `floor(x + 1/2)`, and with `x = millis * 9/5`
/// that is `floor((millis * 18 + 5) / 10)`, which is `(millis * 18 + 5) ~/ 10`
/// in Dart. The clamp is applied on every step, exactly as
/// `Math.min(12_000, Math.round(delay * 1.8))` applied it, so the schedule
/// sticks at 12 seconds instead of trying a value it will never use.
int _nextBackoffMillis(int millis) {
  final int scaled = (millis * 18 + 5) ~/ 10;
  return scaled > maxReconnectDelay.inMilliseconds
      ? maxReconnectDelay.inMilliseconds
      : scaled;
}
