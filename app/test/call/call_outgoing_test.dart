// The caller's half of the state machine.
//
// TS: `requestCall` and the `call-accept` / `call-decline` / `call-end` branches
// of `receiveControl` in `src/services/peer-transport.ts`, plus the `onStartCall`
// handler of `src/App.tsx:563-573`.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';

import 'support/call_harness.dart';

void main() {
  group('startOutgoing', () {
    test('sends one call-offer and nothing else', () {
      final CallHarness harness = CallHarness();
      final CallTransition transition = harness.dial(CallMode.video);

      expect(transition.applied, isTrue);
      expect(transition.status, CallStatus.outgoing);
      expect(transition.previousStatus, CallStatus.idle);
      expect(CallHarness.framesOf(transition), <PeerControlMessage>[
        const CallOfferMessage(
          id: '00000000000000000000000000000001',
          mode: CallMode.video,
        ),
      ]);
      // The peer learns nothing about the caller's camera until it accepts.
      expect(transition.mediaRequest, isNull);
      expect(transition.releasesMedia, isFalse);
      expect(harness.machine.isBusy, isTrue);
    });

    test('arms exactly one timer, and it is the 45 s offer timer', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);

      expect(harness.timers.liveCount, 1);
      expect(harness.timers.only.after, const Duration(seconds: 45));
      expect(harness.machine.isOfferTimerArmed, isTrue);
      // The callee's twin must not be armed by a caller.
      expect(harness.machine.isRingTimerArmed, isFalse);
    });

    // Bullet: "the caller cannot start a second call while one is live".
    test('is refused while an invitation is unanswered', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);
      final int before = harness.timers.liveCount;

      final CallTransition second = harness.dial(CallMode.video);

      expect(second.applied, isFalse);
      expect(second.refusal, CallRefusal.callInProgress);
      expect(second.refusal!.message, 'Başka bir arama zaten etkin.');
      expect(second.actions, isEmpty);
      // The refusal put nothing on the wire, changed nothing, and armed nothing.
      expect(harness.sent, hasLength(1));
      expect(harness.timers.liveCount, before);
      expect(harness.machine.status, CallStatus.outgoing);
      expect(harness.machine.session?.id, '00000000000000000000000000000001');
      expect(harness.machine.session?.mode, CallMode.audio);
    });

    test('is refused while the call is connecting', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);
      harness.machine.onRemoteAccept(callId: id);
      expect(harness.machine.status, CallStatus.connecting);

      final CallTransition second = harness.dial(CallMode.audio);
      expect(second.refusal, CallRefusal.callInProgress);
      expect(harness.sent.whereType<CallOfferMessage>(), hasLength(1));
    });

    test('is refused while the call is connected', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id);

      expect(harness.dial(CallMode.audio).refusal, CallRefusal.callInProgress);
    });

    test('is refused while an incoming call is ringing', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());

      final CallTransition transition = harness.dial(CallMode.audio);
      expect(transition.refusal, CallRefusal.callInProgress);
      // The answer screen is still the thing on screen.
      expect(harness.machine.status, CallStatus.incoming);
      expect(harness.machine.isRingTimerArmed, isTrue);
    });
  });

  group('onRemoteAccept', () {
    test('moves to connecting, disarms the timer and asks for the media', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);
      final ArmedTimer timer = harness.timers.only;

      final CallTransition transition = harness.machine.onRemoteAccept(
        callId: id,
      );

      expect(transition.status, CallStatus.connecting);
      expect(transition.outcome, isA<CallAccepted>());
      expect(
        transition.mediaRequest,
        PublishMedia(mode: CallMode.audio, audio: true, video: false),
      );
      // The offer can no longer time out: the answer already arrived.
      expect(timer.cancelled, isTrue);
      expect(harness.machine.isOfferTimerArmed, isFalse);
      expect(harness.timers.liveCount, 0);
    });

    test('publishes a video call as audio plus video', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.video, id: id);
      final CallTransition transition = harness.machine.onRemoteAccept(
        callId: id,
      );

      expect(
        transition.mediaRequest,
        PublishMedia(mode: CallMode.video, audio: true, video: true),
      );
    });

    test('is ignored for an id this machine is not ringing for', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);

      final CallTransition transition = harness.machine.onRemoteAccept(
        callId: harness.nextId(),
      );

      expect(transition.applied, isFalse);
      expect(transition.refusal, isNull);
      expect(harness.machine.status, CallStatus.outgoing);
      expect(harness.machine.isOfferTimerArmed, isTrue);
    });

    test('is idempotent, because a peer may re-send the frame', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);
      harness.machine.onRemoteAccept(callId: id);
      harness.machine.onMediaReady();
      final int frames = harness.sent.length;

      final CallTransition again = harness.machine.onRemoteAccept(callId: id);

      expect(again.applied, isFalse);
      expect(harness.machine.status, CallStatus.connected);
      expect(harness.sent, hasLength(frames));
    });
  });

  group('onMediaReady', () {
    test('is what moves a connecting call to connected', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id);

      expect(harness.machine.status, CallStatus.connected);
      expect(harness.machine.session!.connectedAt, isNotNull);
      expect(harness.machine.session!.acceptedAt, isNotNull);
    });

    test('cannot skip the connecting step', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);

      final CallTransition transition = harness.machine.onMediaReady();
      expect(transition.applied, isFalse);
      expect(harness.machine.status, CallStatus.outgoing);
    });

    test('is idempotent', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id);
      final int at =
          harness.machine.session!.connectedAt!.millisecondsSinceEpoch;

      expect(harness.machine.onMediaReady().applied, isFalse);
      expect(
        harness.machine.session!.connectedAt!.millisecondsSinceEpoch,
        at,
        reason: 'a second media step must not move the timestamp',
      );
    });
  });

  group('the caller offer timeout', () {
    // Bug 2, caller half: the 45 s `CALL_OFFER_TIMEOUT_MS` of
    // `src/services/peer-transport.ts:113`.
    test('fires, sends call-end and gives the call up as a timeout', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);

      harness.timers.only.fire();

      expect(harness.machine.status, CallStatus.ended);
      // TS: the caller sends a `call-end` before it rejects
      // (`peer-transport.ts:110-113`), and this port keeps that.
      expect(
        harness.sent.last,
        isA<CallEndMessage>().having((CallEndMessage m) => m.id, 'id', id),
      );
      final CallTimedOut outcome = harness.machine.outcome! as CallTimedOut;
      expect(harness.machine.outcome, isA<CallTimedOut>());
      expect(
        outcome.offeredByUs,
        isTrue,
        reason: 'the caller is the side that offered',
      );
      expect(outcome.waited, const Duration(seconds: 45));
      expect(outcome.notice, 'Arama yanıtı için zaman aşımı oluştu.');
      expect(harness.machine.lastMissedCall!.reason, MissedCallReason.timedOut);
    });

    test('releases the local preview the user was watching', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.video);

      harness.timers.only.fire();

      final CallTransition transition = harness.transitions.last;
      expect(transition.releasesMedia, isTrue);
      expect(CallHarness.shapeOf(transition), <String>[
        'SendFrame',
        'ReleaseMedia',
      ]);
    });

    test('does nothing once the call has moved on', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id);
      final int reported = harness.transitions.length;
      final int frames = harness.sent.length;

      harness.timers.fireLive();

      expect(harness.transitions, hasLength(reported));
      expect(harness.sent, hasLength(frames));
      expect(harness.machine.status, CallStatus.connected);
    });
  });

  group('onRemoteDecline', () {
    // Bug 3: `call-declined` had no consumer at all in 0.1.4.
    test('arrives as a declined outcome, not a generic failure', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);

      final CallTransition transition = harness.machine.onRemoteDecline(
        callId: id,
        reason: 'Meşgul.',
      );

      expect(transition.status, CallStatus.ended);
      expect(transition.outcome, isA<CallDeclined>());
      expect(
        transition.outcome,
        isNot(isA<CallFailed>()),
        reason: 'a person saying no is not a broken microphone',
      );
      expect(transition.outcome!.notice, 'Meşgul.');
      expect(
        (transition.outcome! as CallDeclined).reason,
        'Meşgul.',
        reason: "the peer's own words must survive to the notice",
      );
      expect(harness.machine.outcome, same(transition.outcome));
    });

    test('records the call as declined and releases the preview', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.video, id: id);

      final CallTransition transition = harness.machine.onRemoteDecline(
        callId: id,
      );

      final MissedCall record = harness.machine.lastMissedCall!;
      expect(record.reason, MissedCallReason.declined);
      expect(record.detail, PeerProtocol.defaultCallDeclineReason);
      expect(record.mode, CallMode.video);
      expect(record.id, id);
      expect(transition.missedCall, same(record));
      expect(transition.releasesMedia, isTrue);
      // Nothing is sent back: a decline needs no answer.
      expect(transition.frames, isEmpty);
    });

    test('falls back to the protocol text when the frame has no reason', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);

      harness.machine.onRemoteDecline(callId: id);

      expect(
        (harness.machine.outcome! as CallDeclined).reason,
        PeerProtocol.defaultCallDeclineReason,
      );
      expect(
        harness.machine.lastMissedCall!.label,
        PeerProtocol.defaultCallDeclineReason,
      );
    });

    test('is ignored for an id this machine is not ringing for', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);

      final CallTransition transition = harness.machine.onRemoteDecline(
        callId: harness.nextId(),
        reason: 'Meşgul.',
      );

      expect(transition.applied, isFalse);
      expect(harness.machine.status, CallStatus.outgoing);
      expect(harness.machine.missedCalls, isEmpty);
    });

    test('is ignored after the call already ended', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);
      harness.timers.only.fire();

      final CallTransition late = harness.machine.onRemoteDecline(callId: id);

      expect(late.applied, isFalse);
      expect(harness.machine.missedCalls, hasLength(1));
      expect(harness.machine.lastMissedCall!.reason, MissedCallReason.timedOut);
    });

    test('does not confuse a decline with the timeout', () {
      final CallHarness declined = CallHarness();
      declined.dial(CallMode.audio);
      declined.machine.onRemoteDecline(callId: declined.dialedId);
      expect(declined.machine.outcome, isNot(isA<CallTimedOut>()));
      expect(
        declined.machine.outcome!.notice,
        isNot(CallMessages.offerTimeout),
        reason: 'a decline and a timeout are two different notices',
      );

      final CallHarness timedOut = CallHarness();
      timedOut.dial(CallMode.audio);
      timedOut.timers.only.fire();
      expect(timedOut.machine.outcome, isNot(isA<CallDeclined>()));
      expect(timedOut.machine.outcome!.notice, CallMessages.offerTimeout);
      expect(timedOut.sent, isNot(contains(isA<CallDeclineMessage>())));
    });
  });

  group('fail', () {
    test('a caller that cannot place the call cancels it, and says why', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.video);

      final CallTransition transition = harness.machine.fail(
        'Kanal açılamadı.',
      );

      expect(transition.outcome, isA<CallFailed>());
      expect(transition.outcome!.notice, 'Kanal açılamadı.');
      expect(harness.sent.last, isA<CallEndMessage>());
      expect(
        harness.machine.lastMissedCall!.reason,
        MissedCallReason.cancelled,
      );
    });

    test('is ignored when no call is live', () {
      final CallHarness harness = CallHarness();
      final CallTransition transition = harness.machine.fail();
      expect(transition.applied, isFalse);
      expect(harness.machine.status, CallStatus.idle);
    });
  });
}
