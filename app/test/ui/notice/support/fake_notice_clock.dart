/// Deterministic seams for the notice layer: a clock the test steps, and a
/// timer that is *held* rather than scheduled.
///
/// Nothing here imports `dart:async`, so no test under `test/ui/notice` can reach
/// a real `Timer` — the controller has no timer of its own to reach for one, and
/// `SystemNoticeClock` is never handed to one in this directory.
library;

import 'package:mkvi/ui/notice/notice.dart';

/// One armed timer, held instead of scheduled.
final class ArmedNoticeTimer {
  ArmedNoticeTimer({
    required this.due,
    required this.after,
    required this.onFire,
  });

  /// The instant this callback is due, on the fake clock's own scale.
  final DateTime due;

  /// The delay the controller asked for. The dedup receipt: the reconnect loop
  /// must produce one of these, not one per write.
  final Duration after;

  /// What the controller registered.
  final void Function() onFire;

  bool cancelled = false;

  /// Fires the callback if it has not been cancelled, which is what
  /// `dart:async`'s `Timer` does.
  void fire() {
    if (cancelled) return;
    onFire();
  }
}

/// A clock that only moves when the test moves it, and a timer registry that only
/// fires when the clock passes its deadline.
///
/// [advance] jumps to each due deadline in order rather than sampling, so a
/// controller that re-arms inside a callback is handled the way a real event loop
/// would handle it — and no wall-clock time passes at all.
final class FakeNoticeClock implements NoticeClock {
  FakeNoticeClock([DateTime? start])
    : _now = start ?? DateTime.utc(2026, 9, 26, 12);

  DateTime _now;
  final List<ArmedNoticeTimer> _armed = <ArmedNoticeTimer>[];

  /// Every timer this clock has been asked for, in request order, including the
  /// ones that have since fired or been cancelled.
  ///
  /// The dedup receipt. A chatty caller must show up here once, not once per
  /// write, so this list is kept even after a timer leaves [_armed].
  final List<ArmedNoticeTimer> _history = <ArmedNoticeTimer>[];

  /// The timers still waiting to fire.
  List<ArmedNoticeTimer> get armed =>
      List<ArmedNoticeTimer>.unmodifiable(_armed);

  /// Every timer ever requested, fired and cancelled ones included.
  List<ArmedNoticeTimer> get requested =>
      List<ArmedNoticeTimer>.unmodifiable(_history);

  /// How many timers are still armed. A chatty caller must not raise this: the
  /// reconnect loop is the case this exists for.
  int get pending => _armed.where((ArmedNoticeTimer t) => !t.cancelled).length;

  /// The delay of every timer ever requested, in order. One entry per *accepted*
  /// notice, never one per write.
  List<Duration> get requestedDelays => _history
      .map((ArmedNoticeTimer timer) => timer.after)
      .toList(growable: false);

  @override
  DateTime now() => _now;

  @override
  NoticeTimerCancel schedule(Duration delay, void Function() onFire) {
    final ArmedNoticeTimer timer = ArmedNoticeTimer(
      due: _now.add(delay),
      after: delay,
      onFire: onFire,
    );
    _armed.add(timer);
    _history.add(timer);
    return () => timer.cancelled = true;
  }

  /// Moves the clock forward by [delta], firing every timer that comes due on the
  /// way, in deadline order.
  void advance(Duration delta) {
    final DateTime target = _now.add(delta);
    while (true) {
      final ArmedNoticeTimer? next = _nextDueBefore(target);
      if (next == null) break;
      _now = next.due;
      _armed.remove(next);
      next.fire();
    }
    _now = target;
  }

  ArmedNoticeTimer? _nextDueBefore(DateTime target) {
    ArmedNoticeTimer? earliest;
    for (final ArmedNoticeTimer timer in _armed) {
      if (timer.cancelled) continue;
      if (timer.due.isAfter(target)) continue;
      if (earliest == null || timer.due.isBefore(earliest.due)) {
        earliest = timer;
      }
    }
    return earliest;
  }
}
