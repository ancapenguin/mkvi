/// The reconnect backoff, as a pure function.
///
/// Starts at 700 ms, multiplies by 1.8 per consecutive failure, and caps at
/// 12 seconds. The user is only told about it once the sleep reaches 2.8
/// seconds. All three are integers, and modelling them as a function of the
/// consecutive-failure count is what makes the schedule testable without waiting
/// 40 seconds for it.
///
/// The arithmetic is done in integers on purpose. Rounding `delay * 1.8` in
/// double precision is reproducible for a while and then quietly stops being
/// reproducible as the mantissa runs out, and a backoff schedule that drifts is
/// a backoff schedule nobody can pin in a test.
library;

/// The first sleep, and the value a success resets the schedule to.
const Duration initialReconnectDelay = Duration(milliseconds: 700);

/// The ceiling. Past this the loop is not getting anywhere, and a longer sleep
/// only makes the recovery slower when the server comes back.
const Duration maxReconnectDelay = Duration(seconds: 12);

/// The multiplier applied per consecutive failure.
const double reconnectBackoffFactor = 1.8;

/// The sleep above which the loop starts telling the user. Below this the loop
/// is still inside normal startup jitter and a toast per attempt would be the
/// first thing a user learns to ignore.
const Duration reconnectNoticeThreshold = Duration(milliseconds: 2800);

/// The sleep before attempt number `consecutiveFailures + 1`.
///
/// [consecutiveFailures] is 0 for the first failure, so this is
/// [initialReconnectDelay] on the first failure and grows by
/// [reconnectBackoffFactor] each time, clamped to [maxReconnectDelay]. A success
/// resets the counter, which is what puts the schedule back to
/// [initialReconnectDelay].
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
/// `consecutiveFailures`.
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

/// One step of the schedule, in integers: `millis * 1.8` rounded, clamped.
///
/// `round(x)` for positive `x` is `floor(x + 1/2)`, and with `x = millis * 9/5`
/// that is `floor((millis * 18 + 5) / 10)`, which is `(millis * 18 + 5) ~/ 10`
/// in Dart. The clamp is applied on every step so the schedule sticks at
/// [maxReconnectDelay] instead of growing without bound behind the cap.
int _nextBackoffMillis(int millis) {
  final int scaled = (millis * 18 + 5) ~/ 10;
  return scaled > maxReconnectDelay.inMilliseconds
      ? maxReconnectDelay.inMilliseconds
      : scaled;
}
