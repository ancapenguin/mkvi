import 'package:mkvi/core/protocol/control_message.dart';

import 'call_action.dart';
import 'call_outcome.dart';
import 'call_refusal.dart';
import 'call_session.dart';
import 'call_status.dart';
import 'missed_call.dart';

/// What one call to [CallMachine] did.
///
/// Every public method of the machine returns one of these and never throws, so a
/// UI can drive the machine from a button handler without a `try`/`catch` and
/// still knows exactly what to do: [actions] in order, and the one line to show
/// ([outcome] or [refusal]).
final class CallTransition {
  const CallTransition({
    required this.status,
    required this.applied,
    this.previousStatus,
    this.session,
    this.actions = const <CallAction>[],
    this.outcome,
    this.missedCall,
    this.refusal,
  });

  /// The machine's status after the call. Never null, so a consumer can render
  /// straight from a transition without also reading the machine.
  final CallStatus status;

  /// The status before, or `null` for the very first transition. Useful for a
  /// `didChangeStatus` style hook, and for asserting in a test that a refused
  /// step really did not move anything.
  final CallStatus? previousStatus;

  /// Whether anything changed.
  ///
  /// `false` for a step that changed no state — a duplicate offer, a stale
  /// `call-end`, a second `end()`. A refused *user* step also reports `false`,
  /// and explains itself through [refusal].
  final bool applied;

  /// The session after the call, or `null` when the machine holds none.
  final CallSession? session;

  /// What the caller must do, in this order. Empty when there is nothing to do.
  final List<CallAction> actions;

  /// Set when the call reached a result. Every terminal transition sets one.
  final CallOutcome? outcome;

  /// Set when this transition is the one that recorded the call's single history
  /// entry. `null` for every other transition, which is what makes "recorded
  /// exactly once" checkable by counting non-null values.
  final MissedCall? missedCall;

  /// Set when a user-triggered step was refused. Never set for a remote event,
  /// which has no user to explain anything to.
  final CallRefusal? refusal;

  /// Whether the status changed. The one thing a `ChangeNotifier` needs.
  bool get statusChanged => previousStatus != null && previousStatus != status;

  /// The frames to put on the wire, in order.
  Iterable<PeerControlMessage> get frames =>
      actions.whereType<SendFrame>().map((SendFrame action) => action.message);

  /// The media step, if this transition asks for one.
  ///
  /// A callee must run this **after** it has put the `call-accept` on the wire:
  /// [actions] is ordered, and that order is the contract.
  PublishMedia? get mediaRequest {
    for (final CallAction action in actions) {
      if (action is PublishMedia) return action;
    }
    return null;
  }

  /// Whether the caller must stop local capture.
  bool get releasesMedia => actions.any((CallAction a) => a is ReleaseMedia);

  @override
  String toString() =>
      'CallTransition($previousStatus -> $status applied=$applied '
      'actions=$actions outcome=$outcome missedCall=$missedCall '
      'refusal=$refusal)';
}
