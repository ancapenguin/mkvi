/// The reconnect backoff, pinned.
///
/// It starts at 700 ms, multiplies by 1.8 and caps at 12 s, and the user is only
/// told once the sleep reaches 2.8 s. None of it needs a socket, and none of it
/// needs 40 seconds of waiting, because it is a pure function of the
/// consecutive-failure count.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/session/reconnect_schedule.dart';

void main() {
  test('the first sleep is 700 ms, the value App.tsx:216 starts from', () {
    expect(initialReconnectDelay, const Duration(milliseconds: 700));
    expect(reconnectBackoffDelay(0), const Duration(milliseconds: 700));
  });

  test('the schedule is exactly the expected sequence and caps at 12 s', () {
    // 700 -> round(700 * 1.8) = 1260 -> 2268 -> 4082 -> 7348 -> 13226 -> 12000.
    // The cap is applied on every step, as `Math.min(12_000, Math.round(delay * 1.8))`
    // applied it, so the schedule sticks at 12 s instead of asking for a value
    // it will never use.
    expect(reconnectBackoffSchedule(12), const <Duration>[
      Duration(milliseconds: 700),
      Duration(milliseconds: 1260),
      Duration(milliseconds: 2268),
      Duration(milliseconds: 4082),
      Duration(milliseconds: 7348),
      Duration(milliseconds: 12000),
      Duration(milliseconds: 12000),
      Duration(milliseconds: 12000),
      Duration(milliseconds: 12000),
      Duration(milliseconds: 12000),
      Duration(milliseconds: 12000),
      Duration(milliseconds: 12000),
    ]);
  });

  test('the integer arithmetic matches Math.round(delay * 1.8) for 40 steps', () {
    // The schedule multiplies in integers so it cannot drift. This is the check
    // that the integer form is the same function as a floating-point one, for
    // every value the schedule visits.
    for (int failures = 0; failures < 40; failures += 1) {
      final int ported = reconnectBackoffDelay(failures).inMilliseconds;
      // A local copy of the schedule, evaluated in doubles.
      double original = 700;
      for (int step = 0; step < failures; step += 1) {
        original = original * reconnectBackoffFactor;
        original = original.roundToDouble();
        if (original > maxReconnectDelay.inMilliseconds) {
          original = maxReconnectDelay.inMilliseconds.toDouble();
        }
      }
      expect(ported, original.round(), reason: 'after $failures failures');
    }
  });

  test('the cap is 12 s and is never exceeded', () {
    for (int failures = 0; failures < 200; failures += 1) {
      expect(
        reconnectBackoffDelay(failures) <= maxReconnectDelay,
        isTrue,
        reason: 'failure $failures must not exceed the cap',
      );
    }
    expect(reconnectBackoffDelay(5), const Duration(milliseconds: 12000));
    expect(reconnectBackoffDelay(199), const Duration(milliseconds: 12000));
  });

  test('the schedule is monotonically non-decreasing', () {
    int previous = 0;
    for (int failures = 0; failures < 100; failures += 1) {
      final int millis = reconnectBackoffDelay(failures).inMilliseconds;
      expect(
        millis,
        greaterThanOrEqualTo(previous),
        reason: 'failure $failures',
      );
      previous = millis;
    }
  });

  test('a negative count is a programming error, not a zero delay', () {
    expect(() => reconnectBackoffDelay(-1), throwsArgumentError);
    expect(() => reconnectBackoffSchedule(-1), throwsArgumentError);
  });

  test('the user is told from the fourth failure onwards, the 2.8 s gate', () {
    // The notice gate, asked as one question.
    expect(reconnectNoticeThreshold, const Duration(milliseconds: 2800));
    expect(shouldReportReconnectFailure(0), isFalse);
    expect(shouldReportReconnectFailure(1), isFalse);
    expect(
      shouldReportReconnectFailure(2),
      isFalse,
      reason: '2268 ms is still below the gate',
    );
    expect(
      shouldReportReconnectFailure(3),
      isTrue,
      reason: '4082 ms is the first one above it',
    );
    for (int failures = 3; failures < 50; failures += 1) {
      expect(
        shouldReportReconnectFailure(failures),
        isTrue,
        reason: 'failure $failures',
      );
    }
  });
}
