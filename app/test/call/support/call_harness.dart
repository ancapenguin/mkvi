/// Deterministic seams for the call state machine: a clock the test steps, and a
/// timer that is *captured* instead of scheduled.
///
/// Nothing here imports `dart:async`, so no test under `test/call` can reach a
/// real `Timer` — the machine has no timer of its own to reach for one.
library;

import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';

/// A clock that only moves when the machine asks it to, and then by a fixed step.
final class FakeClock {
  FakeClock([DateTime? start]) : value = start ?? DateTime.utc(2026, 9, 26, 12);

  DateTime value;

  /// How many times the machine read the clock. A test that expects exactly one
  /// read per transition is asserting that the machine did not read it twice.
  int reads = 0;

  DateTime call() {
    reads += 1;
    value = value.add(const Duration(seconds: 1));
    return value;
  }

  void advance(Duration delta) {
    value = value.add(delta);
  }
}

/// One armed timer, held instead of scheduled.
final class ArmedTimer {
  ArmedTimer(this.after, this.onFire);

  /// The duration the machine asked for. 45 s on both sides, and the test can
  /// tell which one it is looking at.
  final Duration after;

  final void Function() onFire;

  bool cancelled = false;
  bool fired = false;

  /// Fires the callback once. A cancelled or already-fired timer is inert, which
  /// is what `dart:async`'s `Timer` does too.
  void fire() {
    if (cancelled || fired) return;
    fired = true;
    onFire();
  }

  /// Fires the callback even if the machine cancelled it.
  ///
  /// `dart:async` makes this impossible, which is the point: a test that uses it
  /// is not claiming a production scenario, it is proving the machine does not
  /// *depend* on the guarantee. Every late-callback guard exists so that a
  /// cancelled timer arriving anyway is harmless.
  void forceFire() => onFire();
}

/// The [CallTimerStarter] a test hands to [CallMachine].
final class FakeCallTimers {
  final List<ArmedTimer> armed = <ArmedTimer>[];

  CallTimerCancel start(Duration delay, void Function() onFire) {
    final ArmedTimer timer = ArmedTimer(delay, onFire);
    armed.add(timer);
    return () => timer.cancelled = true;
  }

  /// Timers that are neither cancelled nor fired, in the order they were armed.
  List<ArmedTimer> get live => armed
      .where((ArmedTimer t) => !t.cancelled && !t.fired)
      .toList(growable: false);

  int get liveCount => live.length;

  /// The single live timer. Fails loudly rather than returning the wrong one: a
  /// test that means "the ring timer" must not silently get the offer timer.
  ArmedTimer get only {
    final List<ArmedTimer> current = live;
    if (current.length != 1) {
      throw StateError(
        'expected exactly one live timer, found ${current.length}',
      );
    }
    return current.single;
  }

  /// Fires every live timer, oldest first.
  void fireLive() {
    for (final ArmedTimer timer in List<ArmedTimer>.of(armed)) {
      timer.fire();
    }
  }

  /// Fires *every* callback ever handed out, cancelled ones included.
  ///
  /// For the "a timer that has already lost its call cannot touch the next one"
  /// assertions; see [ArmedTimer.forceFire].
  void fireAll() {
    for (final ArmedTimer timer in List<ArmedTimer>.of(armed)) {
      timer.forceFire();
    }
  }

  /// Fires every callback except [keep], which is the one the live call owns.
  ///
  /// The precise form of the stale-timer assertions: the test fires the callbacks
  /// of calls that are already over, without also firing the current one.
  void fireAllExcept(ArmedTimer keep) {
    for (final ArmedTimer timer in List<ArmedTimer>.of(armed)) {
      if (!identical(timer, keep)) timer.forceFire();
    }
  }
}

/// A whole call, wired to the fakes, with the wiring assertions in one place.
final class CallHarness {
  CallHarness([DateTime? startAt]) : clock = FakeClock(startAt) {
    machine = CallMachine(
      startTimer: timers.start,
      now: clock.call,
      idFactory: nextId,
      onTransition: transitions.add,
    );
  }

  final FakeCallTimers timers = FakeCallTimers();
  final FakeClock clock;

  /// Every transition the machine reported, in order. A refused or stale step is
  /// not here, which is what makes "the UI was not woken" assertable.
  final List<CallTransition> transitions = <CallTransition>[];

  late final CallMachine machine;

  int _ids = 0;

  /// Ids are bare 32 character lowercase hex, the only shape `parseControl`
  /// accepts, so a frame the machine produces is a frame the peer can read.
  String nextId() {
    _ids += 1;
    return _ids.toRadixString(16).padLeft(32, '0');
  }

  /// Every frame the machine asked to be sent, in order.
  List<PeerControlMessage> get sent => <PeerControlMessage>[
    for (final CallTransition transition in transitions) ...transition.frames,
  ];

  /// The frames of one transition, in the order the machine listed them.
  static List<PeerControlMessage> framesOf(CallTransition transition) =>
      transition.frames.toList(growable: false);

  /// The action kinds of one transition, in order. Cheaper to read in a failure
  /// message than the actions themselves.
  static List<String> shapeOf(CallTransition transition) => <String>[
    for (final CallAction action in transition.actions)
      action.runtimeType.toString(),
  ];

  /// Puts this machine in the callee seat, the way the transport does when a
  /// parsed `call-offer` arrives on the data channel.
  CallTransition ring(String id, [CallMode mode = CallMode.audio]) =>
      machine.onIncomingOffer(CallOfferMessage(id: id, mode: mode));

  /// Puts this machine in the caller seat.
  CallTransition dial(CallMode mode, {String? id}) =>
      machine.startOutgoing(mode, id: id);

  /// The id the machine generated for the outgoing call, or `null` if it is not
  /// holding one.
  String? get dialedId => machine.session?.id;

  /// A callee that has answered and published its media.
  CallTransition answerAndConnect(String id, [CallMode mode = CallMode.audio]) {
    ring(id, mode);
    machine.accept();
    return machine.onMediaReady();
  }

  /// A caller whose invitation the peer accepted and whose media is published.
  CallTransition acceptedAndConnected(
    String id, [
    CallMode mode = CallMode.audio,
  ]) {
    dial(mode, id: id);
    machine.onRemoteAccept(callId: id);
    return machine.onMediaReady();
  }
}
