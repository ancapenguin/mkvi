// The transition table, the "every button can be pressed twice" rule, and the
// proof that the frames this machine builds are frames the ported protocol layer
// can read back.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/control_parser.dart';

import 'support/call_harness.dart';

void main() {
  group('the transition table', () {
    test('caller: idle -> outgoing -> connecting -> connected -> ended', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();

      final List<CallStatus?> seen = <CallStatus?>[
        harness.dial(CallMode.audio, id: id).previousStatus,
        harness.machine.onRemoteAccept(callId: id).previousStatus,
        harness.machine.onMediaReady().previousStatus,
        harness.machine.end().previousStatus,
      ];

      expect(seen, <CallStatus>[
        CallStatus.idle,
        CallStatus.outgoing,
        CallStatus.connecting,
        CallStatus.connected,
      ]);
      expect(harness.machine.status, CallStatus.ended);
      expect(
        harness.transitions.every((CallTransition t) => t.statusChanged),
        isTrue,
      );
    });

    test('callee: idle -> incoming -> connecting -> connected -> ended', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();

      final List<CallStatus?> seen = <CallStatus?>[
        harness.ring(id).previousStatus,
        harness.machine.accept().previousStatus,
        harness.machine.onMediaReady().previousStatus,
        harness.machine.end().previousStatus,
      ];

      expect(seen, <CallStatus>[
        CallStatus.idle,
        CallStatus.incoming,
        CallStatus.connecting,
        CallStatus.connected,
      ]);
      expect(harness.machine.status, CallStatus.ended);
    });

    test('ends and returns to idle, and only from ended', () {
      final CallHarness harness = CallHarness();
      harness.answerAndConnect(harness.nextId());

      expect(harness.machine.reset().refusal, CallRefusal.callStillRunning);
      expect(harness.machine.reset().refusal?.message, 'Arama hâlâ sürüyor.');
      expect(harness.machine.status, CallStatus.connected);

      harness.machine.end();
      final CallTransition reset = harness.machine.reset();

      expect(reset.applied, isTrue);
      expect(reset.status, CallStatus.idle);
      expect(reset.statusChanged, isTrue);
      expect(harness.machine.session, isNull);
      // The outcome and the history outlive the session, so the UI can render the
      // "call ended" notice from a widget that rebuilt after the reset.
      expect(harness.machine.outcome, isNotNull);
      expect(harness.machine.missedCalls, hasLength(1));
    });

    test('a new call can be taken from idle or from ended', () {
      final CallHarness fromIdle = CallHarness();
      expect(fromIdle.dial(CallMode.audio).applied, isTrue);

      final CallHarness fromEnded = CallHarness();
      final String id = fromEnded.nextId();
      fromEnded.ring(id);
      fromEnded.machine.decline();
      expect(fromEnded.machine.status, CallStatus.ended);
      expect(fromEnded.ring(fromEnded.nextId()).applied, isTrue);
      expect(fromEnded.machine.status, CallStatus.incoming);
      expect(fromEnded.machine.isRingTimerArmed, isTrue);
    });
  });

  // Bullet: "every transition that a user can trigger twice is safe to trigger
  // twice".
  group('triggering anything twice', () {
    test('twice on a ringing caller', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);

      harness.machine.startOutgoing(CallMode.video);
      harness.machine.startOutgoing(CallMode.video);
      harness.machine.accept();
      harness.machine.accept(callId: id);
      harness.machine.decline();
      harness.machine.decline();
      harness.machine.upgradeToVideo();
      harness.machine.upgradeToVideo();
      harness.machine.onMediaReady();
      harness.machine.onMediaReady();
      harness.machine.onRemoteAccept(callId: id);
      harness.machine.onRemoteAccept(callId: id);
      harness.machine.end();
      harness.machine.end();
      // Only now, with the call already over, do the peer's frames mean anything.
      harness.machine.onRemoteDecline(callId: id, reason: 'Meşgul.');
      harness.machine.onRemoteDecline(callId: id, reason: 'Meşgul.');
      harness.machine.onRemoteEnd(callId: id);
      harness.machine.onRemoteEnd(callId: id);
      harness.machine.fail();
      harness.machine.fail();
      harness.machine.reset();
      harness.machine.reset();
      harness.machine.dispose();
      harness.machine.dispose();
      harness.timers.fireAll();

      // One offer, one call-end, one record. Nothing doubled, nothing resurrected.
      expect(harness.sent.whereType<CallOfferMessage>(), hasLength(1));
      expect(harness.sent.whereType<CallEndMessage>(), hasLength(1));
      expect(harness.sent.whereType<CallAcceptMessage>(), isEmpty);
      expect(harness.sent.whereType<CallDeclineMessage>(), isEmpty);
      expect(harness.machine.missedCalls, hasLength(1));
      expect(
        harness.machine.missedCalls.single.reason,
        MissedCallReason.endedNormally,
      );
      expect(harness.machine.status, CallStatus.idle);
    });

    test('twice on a ringing callee', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);

      harness.ring(id);
      harness.machine.accept();
      harness.machine.accept();
      harness.machine.decline();
      harness.machine.upgradeToVideo();
      harness.machine.upgradeToVideo();
      harness.machine.onMediaReady();
      harness.machine.onRemoteAccept(callId: id);
      harness.machine.onRemoteDecline(callId: id);
      harness.machine.end();
      harness.machine.end();
      harness.machine.fail();
      harness.machine.reset();
      harness.machine.reset();
      harness.timers.fireAll();

      // One accept, one call-end, one record: the decline did not become a
      // second frame and the ring timeout did not become a second record.
      expect(harness.sent.whereType<CallAcceptMessage>(), hasLength(1));
      expect(harness.sent.whereType<CallEndMessage>(), hasLength(1));
      expect(harness.sent.whereType<CallDeclineMessage>(), isEmpty);
      expect(harness.machine.missedCalls, hasLength(1));
      expect(
        harness.machine.missedCalls.single.reason,
        MissedCallReason.endedNormally,
      );
      expect(harness.machine.status, CallStatus.idle);
    });

    test('twice when the peer is the one who hung up', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.answerAndConnect(id);

      harness.machine.onRemoteEnd(callId: id);
      harness.machine.onRemoteEnd(callId: id);
      harness.machine.end();
      harness.machine.end();

      // A hangup that arrives *because* the peer hung up must not be echoed back,
      // or the two peers can trade the frame forever.
      expect(harness.sent.whereType<CallEndMessage>(), isEmpty);
      expect(harness.sent.whereType<CallAcceptMessage>(), hasLength(1));
      expect(harness.machine.missedCalls, hasLength(1));
    });

    test('twice on an idle machine', () {
      final CallHarness harness = CallHarness();

      final List<CallTransition> results = <CallTransition>[
        harness.machine.end(),
        harness.machine.end(),
        harness.machine.accept(),
        harness.machine.decline(),
        harness.machine.upgradeToVideo(),
        harness.machine.onMediaReady(),
        harness.machine.onRemoteAccept(),
        harness.machine.onRemoteDecline(),
        harness.machine.onRemoteEnd(),
        harness.machine.fail(),
        harness.machine.reset(),
        harness.machine.reset(),
      ];

      expect(harness.sent, isEmpty);
      expect(harness.machine.missedCalls, isEmpty);
      expect(harness.machine.status, CallStatus.idle);
      expect(harness.machine.session, isNull);
      expect(results.every((CallTransition t) => t.applied), isFalse);
      // Only the two steps whose refusal carries a message are visible; every
      // silent no-op stays silent, and none of them woke the listener.
      expect(
        results
            .where((CallTransition t) => t.refusal != null)
            .map((CallTransition t) => t.refusal),
        <CallRefusal>[
          CallRefusal.incomingCallNotFound,
          CallRefusal.notConnected,
        ],
      );
      expect(
        harness.transitions,
        isEmpty,
        reason: 'a refusal with nothing to send must not rebuild the UI',
      );
    });

    test('a refused step does not wake the listener', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);
      final int reported = harness.transitions.length;

      final CallTransition refused = harness.dial(CallMode.video);
      final CallTransition stale = harness.machine.onRemoteAccept(
        callId: harness.nextId(),
      );

      expect(refused.applied, isFalse);
      expect(stale.applied, isFalse);
      expect(harness.transitions, hasLength(reported));
    });

    test('but a refusal that answers the peer is still reported', () {
      final CallHarness harness = CallHarness();
      harness.acceptedAndConnected(harness.nextId());
      final int reported = harness.transitions.length;

      final CallTransition refused = harness.ring(harness.nextId());

      expect(refused.applied, isFalse);
      expect(refused.refusal, isNotNull);
      expect(harness.transitions, hasLength(reported + 1));
    });
  });

  group('wire compatibility', () {
    // Everything the machine builds is a protocol type, so the bytes a peer would
    // receive are the bytes `encodeControl` produces and `parseControl` accepts.
    test('every frame survives a round trip through the wire codec', () {
      final CallHarness caller = CallHarness();
      final String callerId = caller.nextId();
      caller.dial(CallMode.video, id: callerId);
      caller.machine.onRemoteAccept(callId: callerId);
      caller.machine.onMediaReady();
      caller.machine.end();

      final CallHarness callee = CallHarness();
      final String calleeId = callee.nextId();
      callee.ring(calleeId, CallMode.video);
      callee.machine.accept();
      callee.machine.onMediaReady();
      callee.machine.end();

      final CallHarness busy = CallHarness();
      busy.acceptedAndConnected(busy.nextId());
      busy.ring(busy.nextId());

      final CallHarness timedOut = CallHarness();
      timedOut.ring(timedOut.nextId());
      timedOut.timers.only.fire();

      final List<PeerControlMessage> frames = <PeerControlMessage>[
        ...caller.sent,
        ...callee.sent,
        ...busy.sent,
        ...timedOut.sent,
      ];

      expect(frames, hasLength(7));
      for (final PeerControlMessage frame in frames) {
        expect(
          parseControl(encodeControl(frame)),
          frame,
          reason: '$frame does not survive the wire',
        );
      }
      expect(
        frames.whereType<CallDeclineMessage>().map(
          (CallDeclineMessage m) => m.reason,
        ),
        containsAll(<String>['Meşgul.', 'Cevap verilmedi.']),
      );
    });

    test('a decline reason longer than the cap is cut, not refused', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());
      final String long = List<String>.filled(400, 'a').join();

      final CallTransition transition = harness.machine.decline(reason: long);
      final CallDeclineMessage frame =
          CallHarness.framesOf(transition).single as CallDeclineMessage;

      expect(frame.reason, hasLength(256));
      expect(
        parseControl(encodeControl(frame)),
        frame,
        reason: 'a cut reason is still a frame the peer can read',
      );
    });
  });

  group('the machine has no clock of its own', () {
    test('dispose is the only thing a teardown needs, and is idempotent', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);
      final ArmedTimer ring = harness.timers.only;

      harness.machine.dispose();
      harness.machine.dispose();

      expect(ring.cancelled, isTrue);
      expect(harness.machine.isRingTimerArmed, isFalse);
      expect(harness.machine.isOfferTimerArmed, isFalse);
      // Disposing does not end the call; that is `end`'s job, and it is the UI's.
      expect(harness.machine.status, CallStatus.incoming);
    });
  });
}
