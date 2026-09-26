/// A controlled clock for the call state machine: the instant it reads, and
/// every timer it arms, on one scale.
///
/// The existing `test/call/support/call_harness.dart` fires timers by hand, which
/// is right for "make this one timer fire and assert the other one did not" and
/// wrong for "45 seconds pass". This one can do both: [advance] jumps to each
/// due deadline in order, so a callback that re-arms a timer inside itself is
/// handled the way a real event loop would handle it - and no wall-clock time
/// passes at all.
///
/// ## No real `Timer` is ever constructed
///
/// [FakeCallClock.start] is the whole scheduling seam, and it stores a
/// [ArmedCallTimer]. Nothing here calls `Timer`, so the ring timeout cannot
/// pass by accident and a test that forgets to advance simply sees a call that
/// is still ringing.
library;

import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';

import 'script_log.dart';
/// One armed timer, held instead of scheduled.
final class ArmedCallTimer {
  ArmedCallTimer({
    required this.armedAt,
    required this.after,
    required this.onFire,
  });

  /// The instant the timer came due, on the fake clock's own scale.
  final DateTime armedAt;

  /// The duration the machine asked for. 45 s on both sides, and the test can
  /// tell which one it is looking at.
  final Duration after;

  final void Function() onFire;

  bool cancelled = false;
  bool fired = false;

  /// Whether the machine still owns this timer.
  bool get isLive => !cancelled && !fired;

  /// Fires the callback once. A cancelled or already-fired timer is inert, which
  /// is what `dart:async`'s `Timer` does too.
  void fire() {
    if (!isLive) return;
    fired = true;
    onFire();
  }

  /// Fires the callback even if the machine cancelled it.
  ///
  /// `dart:async` makes this impossible, which is the point: a test that uses it
  /// is not claiming a production scenario, it is proving the machine does not
  /// *depend* on the guarantee. Every late-callback guard exists so a cancelled
  /// timer arriving anyway is harmless.
  void forceFire() => onFire();

  @override
  String toString() =>
      'ArmedCallTimer($after at $armedAt'
      '${cancelled ? ', cancelled' : ''}${fired ? ', fired' : ''})';
}

/// The clock and the timer registry in one value, so a deadline is a real
/// instant on a real scale rather than a list index.
final class FakeCallClock {
  FakeCallClock([DateTime? start])
    : _now = start ?? DateTime.utc(2026, 9, 26, 12) {
    log
      ..define('now', 'poll')
      ..define('start', 'arms a timer and returns its cancel function')
      ..define('advance', 'moves the clock and fires everything that comes due');
  }

  final ScriptLog log = ScriptLog('FakeCallClock');

  DateTime _now;

  /// How many times the machine read the clock. A test that expects one read per
  /// transition is asserting the machine did not read it twice.
  int reads = 0;

  /// How many timers were ever armed, in order, including the fired and the
  /// cancelled ones. The dedup receipt: the machine arms an offer timer and a
  /// ring timer, never two of the same one.
  final List<ArmedCallTimer> history = <ArmedCallTimer>[];

  DateTime get now => _now;

  /// The timers still waiting to fire.
  List<ArmedCallTimer> get armed => <ArmedCallTimer>[
    for (final ArmedCallTimer timer in history)
      if (timer.isLive) timer,
  ];

  /// Every timer ever requested, in request order.
  List<ArmedCallTimer> get requested =>
      List<ArmedCallTimer>.unmodifiable(history);

  /// The delays of every timer ever requested, in order.
  List<Duration> get requestedDelays => <Duration>[
    for (final ArmedCallTimer timer in history) timer.after,
  ];

  int get liveCount => armed.length;

  /// The single live timer. Fails loudly rather than returning the wrong one: a
  /// test that means "the ring timer" must not silently get the offer timer.
  ArmedCallTimer get only {
    final List<ArmedCallTimer> current = armed;
    if (current.length != 1) {
      throw StateError(
        'expected exactly one live timer, found ${current.length}',
      );
    }
    return current.single;
  }

  /// Reads the clock. This is the `now` a [CallMachine] is built with.
  DateTime call() {
    reads += 1;
    log.poll('now');
    return _now;
  }

  /// The [CallTimerStarter] a machine is built with.
  CallTimerCancel start(Duration delay, void Function() onFire) {
    log.record('start', detail: delay);
    final ArmedCallTimer timer = ArmedCallTimer(
      armedAt: _now.add(delay),
      after: delay,
      onFire: onFire,
    );
    history.add(timer);
    return () => timer.cancelled = true;
  }

  /// Moves the clock forward by [by], firing every timer that comes due on the
  /// way, in deadline order.
  ///
  /// Jumps to each deadline rather than sampling, so a callback that re-arms a
  /// timer is seen at the right instant. A [by] of zero fires everything already
  /// due, which cannot happen through this clock, so it is a no-op.
  void advance(Duration by) {
    log.record('advance', detail: by);
    final DateTime target = _now.add(by);
    while (true) {
      final ArmedCallTimer? next = _nextDueBefore(target);
      if (next == null) break;
      _now = next.armedAt;
      next.fire();
    }
    _now = target;
  }

  /// Fires every live timer, oldest deadline first, without moving the clock.
  void fireLive() {
    for (final ArmedCallTimer timer in armed) {
      timer.fire();
    }
  }

  /// Fires *every* callback ever handed out, cancelled ones included. See
  /// [ArmedCallTimer.forceFire].
  void fireAll() {
    for (final ArmedCallTimer timer in List<ArmedCallTimer>.of(history)) {
      timer.forceFire();
    }
  }

  /// Fires every callback except [keep], which is the one the live call owns.
  ///
  /// The precise form of the stale-timer assertions: the callbacks of calls that
  /// are already over, without also firing the current one.
  void fireAllExcept(ArmedCallTimer keep) {
    for (final ArmedCallTimer timer in List<ArmedCallTimer>.of(history)) {
      if (!identical(timer, keep)) timer.forceFire();
    }
  }

  /// Forgets every timer and puts the clock back to [start]. Only useful between
  /// phases of one test.
  void reset([DateTime? start]) {
    _now = start ?? DateTime.utc(2026, 9, 26, 12);
    history.clear();
    reads = 0;
    log.clear();
  }

  ArmedCallTimer? _nextDueBefore(DateTime target) {
    ArmedCallTimer? earliest;
    for (final ArmedCallTimer timer in history) {
      if (!timer.isLive) continue;
      if (timer.armedAt.isAfter(target)) continue;
      if (earliest == null || timer.armedAt.isBefore(earliest.armedAt)) {
        earliest = timer;
      }
    }
    return earliest;
  }
}

/// Ids a [CallMachine] accepts: 32 lowercase hex characters, the only shape
/// `parseControl` reads, so a frame the machine produces is a frame the peer can
/// parse. `Harness` mints a different one on every call.
final class FakeCallIds {
  int minted = 0;

  String call() {
    minted += 1;
    return minted.toRadixString(16).padLeft(32, '0');
  }

  /// A one-off factory for exactly [n] ids, for a test that names the id it
  /// expects rather than reading it back.
  static String Function() sequence(int n) {
    int next = 0;
    return () => (next++).toRadixString(16).padLeft(32, '0');
  }
}

/// A `call-offer` frame as the transport would build it from the wire.
CallOfferMessage fakeOffer(
  String id, [
  CallMode mode = CallMode.audio,
]) => CallOfferMessage(id: id, mode: mode);
