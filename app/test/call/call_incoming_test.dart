// The callee's half of the state machine: the answer screen that 0.1.4 did not
// have, and the 45 s ring timeout it did not have either.
//
// TS: `acceptCall` / `declineCall` and the `call-offer` branch of `receiveControl`
// in `src/services/peer-transport.ts`, plus the `onAcceptIncomingCall` handler of
// `src/App.tsx:574-589`.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';

import 'support/call_harness.dart';

void main() {
  group('onIncomingOffer', () {
    test('puts an answer screen up and puts nothing on the wire', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();

      final CallTransition transition = harness.ring(id, CallMode.video);

      expect(transition.status, CallStatus.incoming);
      expect(transition.applied, isTrue);
      expect(transition.actions, isEmpty);
      expect(harness.sent, isEmpty);
      expect(harness.machine.isRinging, isTrue);
      expect(harness.machine.session?.id, id);
      expect(harness.machine.session?.mode, CallMode.video);
      expect(harness.machine.session?.side, CallSide.callee);
    });

    test('arms the 45 s ring timer and not the offer timer', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());

      expect(harness.timers.liveCount, 1);
      expect(harness.timers.only.after, const Duration(seconds: 45));
      expect(harness.machine.isRingTimerArmed, isTrue);
      expect(harness.machine.isOfferTimerArmed, isFalse);
    });

    // The promise the answer dialog makes, `ChatCallWorkspace.tsx:184`.
    test('no media step exists before the user accepts', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());
      harness.machine.upgradeToVideo();

      for (final CallTransition transition in harness.transitions) {
        expect(
          transition.mediaRequest,
          isNull,
          reason: 'nothing may be published before accept()',
        );
        expect(transition.releasesMedia, isFalse);
      }
    });

    // Bug 1: 0.1.4 auto-accepted, so the callee's call opened by itself.
    test('the call cannot open by itself: only accept() connects a callee', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);

      // Everything a peer or a stray tap could do, none of which is the user
      // pressing "Kabul et".
      harness.machine.onRemoteAccept(callId: id);
      harness.machine.onRemoteDecline(callId: id);
      harness.machine.onMediaReady();
      harness.machine.upgradeToVideo();

      expect(harness.sent, isEmpty);
      expect(
        harness.machine.status,
        CallStatus.incoming,
        reason: 'the answer screen is the only state a callee can sit in',
      );

      harness.machine.accept();

      // The only frame the whole exchange produced, and it came from the accept.
      expect(harness.sent, <PeerControlMessage>[
        CallAcceptMessage(id: id),
      ], reason: 'no frame may exist before the user accepted');
      expect(harness.machine.status, CallStatus.connecting);
      expect(
        harness.transitions
            .where((CallTransition t) => t.mediaRequest != null)
            .length,
        1,
      );
    });

    // Bullet: "an incoming offer while a call is live is declined with the right
    // reason".
    test('is declined with Meşgul. while a call is live', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());
      harness.machine.accept();
      harness.machine.onMediaReady();
      expect(harness.machine.status, CallStatus.connected);
      final String busy = harness.nextId();

      final CallTransition transition = harness.ring(busy);

      expect(transition.applied, isFalse);
      expect(transition.refusal, CallRefusal.callInProgress);
      expect(
        harness.sent.last,
        isA<CallDeclineMessage>()
            .having((CallDeclineMessage m) => m.id, 'id', busy)
            .having(
              (CallDeclineMessage m) => m.reason,
              'reason',
              PeerProtocol.busyCallReason,
            ),
      );
      // The call in progress is untouched.
      expect(harness.machine.status, CallStatus.connected);
      expect(harness.machine.session?.id, isNot(busy));
    });

    test('is declined with Meşgul. while the machine is calling', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);
      final String busy = harness.nextId();

      final CallTransition transition = harness.ring(busy);

      expect(transition.refusal, CallRefusal.callInProgress);
      expect(
        (harness.sent.last as CallDeclineMessage).reason,
        PeerProtocol.busyCallReason,
      );
      expect(harness.machine.status, CallStatus.outgoing);
    });

    test('is declined with Meşgul. while another answer screen is up', () {
      final CallHarness harness = CallHarness();
      final String first = harness.nextId();
      harness.ring(first);
      final int timers = harness.timers.liveCount;

      final CallTransition transition = harness.ring(harness.nextId());

      expect(transition.refusal, CallRefusal.callInProgress);
      expect(harness.machine.session?.id, first);
      expect(harness.machine.isRingTimerArmed, isTrue);
      // The busy decline must not re-arm or replace the first screen's timer.
      expect(harness.timers.liveCount, timers);
    });

    // A peer that re-announces its offer must not be able to keep the dialog up
    // forever. TS: `if (this.incomingCalls.has(message.id)) break;`.
    test('a repeated offer is ignored and does not re-arm the ring timer', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);
      final ArmedTimer timer = harness.timers.only;
      final int reported = harness.transitions.length;

      final CallTransition again = harness.ring(id);

      expect(again.applied, isFalse);
      expect(again.refusal, isNull);
      expect(again.actions, isEmpty);
      expect(harness.timers.only, same(timer));
      expect(harness.timers.liveCount, 1);
      expect(harness.transitions, hasLength(reported));
    });
  });

  group('accept', () {
    // Bug 4: `App.tsx:580-581` published the callee's media *before* it accepted.
    test('puts call-accept on the wire before the media step', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id, CallMode.video);
      final ArmedTimer ring = harness.timers.only;

      final CallTransition transition = harness.machine.accept();

      expect(
        CallHarness.shapeOf(transition),
        <String>['SendFrame', 'PublishMedia'],
        reason: 'the decision must reach the peer before the camera does',
      );
      expect(CallHarness.framesOf(transition), <PeerControlMessage>[
        CallAcceptMessage(id: id),
      ]);
      expect(
        transition.mediaRequest,
        PublishMedia(mode: CallMode.video, audio: true, video: true),
      );
      expect(harness.machine.status, CallStatus.connecting);
      expect(ring.cancelled, isTrue);
      expect(harness.machine.isRingTimerArmed, isFalse);
    });

    test('publishes audio only for an audio call', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId(), CallMode.audio);
      expect(
        harness.machine.accept().mediaRequest,
        PublishMedia(mode: CallMode.audio, audio: true, video: false),
      );
    });

    test('is refused for an id that is not on screen', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);

      final CallTransition transition = harness.machine.accept(
        callId: harness.nextId(),
      );

      expect(transition.applied, isFalse);
      expect(transition.refusal, CallRefusal.incomingCallNotFound);
      expect(transition.refusal!.message, 'Gelen arama bulunamadı.');
      expect(transition.mediaRequest, isNull);
      expect(harness.machine.status, CallStatus.incoming);
      expect(harness.sent, isEmpty);
    });

    // Bullet: "accept is refused after the call already ended (the race), and the
    // media step never runs".
    test(
      'is refused after the caller timed out and hung up, and never publishes',
      () {
        final CallHarness harness = CallHarness();
        final String id = harness.nextId();
        harness.ring(id);
        // The caller's 45 s offer timeout reaches the callee as a `call-end`
        // (`peer-transport.ts:110`), while the user is still opening the camera.
        harness.machine.onRemoteEnd(callId: id);
        expect(harness.machine.status, CallStatus.ended);
        expect(
          harness.machine.lastMissedCall!.reason,
          MissedCallReason.cancelled,
        );

        final CallTransition transition = harness.machine.accept();

        expect(transition.applied, isFalse);
        expect(transition.refusal, CallRefusal.incomingCallNotFound);
        expect(transition.actions, isEmpty);
        expect(transition.mediaRequest, isNull);
        expect(transition.missedCall, isNull);
        // The whole race put exactly zero frames on the wire: no `call-accept`
        // reached a peer that had already walked away.
        expect(harness.sent, isEmpty);
      },
    );

    test('is refused after the ring timeout fired, and never publishes', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);
      harness.timers.only.fire();
      expect(harness.machine.status, CallStatus.ended);

      final CallTransition transition = harness.machine.accept();

      expect(transition.applied, isFalse);
      expect(transition.refusal, CallRefusal.incomingCallNotFound);
      expect(transition.mediaRequest, isNull);
      expect(
        harness.sent.whereType<CallAcceptMessage>(),
        isEmpty,
        reason: 'the call was already declined on the wire',
      );
    });

    test('is idempotent, because the answer button can be tapped twice', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);
      harness.machine.accept();
      final int frames = harness.sent.length;

      final CallTransition again = harness.machine.accept();

      expect(again.applied, isFalse);
      expect(again.refusal, CallRefusal.incomingCallNotFound);
      expect(harness.sent, hasLength(frames));
      expect(harness.machine.status, CallStatus.connecting);
    });

    test('is refused on the caller side, which has no answer screen', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);

      final CallTransition transition = harness.machine.accept();

      expect(transition.applied, isFalse);
      expect(transition.refusal, CallRefusal.incomingCallNotFound);
      expect(transition.mediaRequest, isNull);
      expect(harness.sent, hasLength(1));
    });
  });

  group('decline', () {
    test('sends one call-decline with the protocol default reason', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);
      final ArmedTimer ring = harness.timers.only;

      final CallTransition transition = harness.machine.decline();

      expect(CallHarness.framesOf(transition), <PeerControlMessage>[
        CallDeclineMessage(
          id: id,
          reason: PeerProtocol.defaultCallDeclineReason,
        ),
      ]);
      expect(transition.outcome, isA<CallEndedLocally>());
      expect(transition.outcome!.notice, 'Arama reddedildi.');
      expect(transition.missedCall?.reason, MissedCallReason.declined);
      expect(harness.machine.status, CallStatus.ended);
      expect(ring.cancelled, isTrue);
      expect(harness.machine.isRingTimerArmed, isFalse);
    });

    test('scrubs and caps the reason it was given', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());

      final CallTransition transition = harness.machine.decline(
        reason: '  Meşgul.\n\t',
      );

      expect(
        (CallHarness.framesOf(transition).single as CallDeclineMessage).reason,
        'Meşgul.',
      );
    });

    // The callee has captured nothing, so there is nothing to release. This is
    // the same promise as "no media step before accept", seen from the end.
    test('releases no media, because it never had any', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());

      final CallTransition transition = harness.machine.decline();

      expect(transition.releasesMedia, isFalse);
      expect(CallHarness.shapeOf(transition), <String>['SendFrame']);
    });

    // Bullet: "decline is idempotent".
    test('is idempotent, and never sends a second call-decline', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);
      harness.machine.decline();
      final int frames = harness.sent.length;
      final int reported = harness.transitions.length;

      final CallTransition again = harness.machine.decline();
      final CallTransition third = harness.machine.decline(
        reason: 'Başka bir sebep.',
      );

      expect(again.applied, isFalse);
      expect(again.refusal, isNull);
      expect(third.applied, isFalse);
      expect(harness.sent, hasLength(frames));
      expect(harness.transitions, hasLength(reported));
      expect(harness.machine.missedCalls, hasLength(1));
    });

    test('is ignored when the call is already connected', () {
      final CallHarness harness = CallHarness();
      harness.answerAndConnect(harness.nextId());

      final CallTransition transition = harness.machine.decline();

      expect(transition.applied, isFalse);
      expect(harness.sent, hasLength(1));
      expect(harness.sent.single, isA<CallAcceptMessage>());
    });
  });

  group('the callee ring timeout', () {
    // Bug 2: the callee had no timer, so `incomingCalls` was only ever cleared by
    // accept/decline/stop/close and a ringing dialog could stay on screen forever
    // with both buttons disabled.
    test('fires and sends a decline with Cevap verilmedi.', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id, CallMode.video);

      harness.timers.only.fire();

      expect(harness.machine.status, CallStatus.ended);
      expect(harness.machine.isRinging, isFalse);
      expect(
        harness.sent.single,
        isA<CallDeclineMessage>()
            .having((CallDeclineMessage m) => m.id, 'id', id)
            .having(
              (CallDeclineMessage m) => m.reason,
              'reason',
              'Cevap verilmedi.',
            ),
      );
      expect(harness.machine.outcome, isA<CallTimedOut>());
      final CallTimedOut outcome = harness.machine.outcome! as CallTimedOut;
      expect(
        outcome.offeredByUs,
        isFalse,
        reason: 'the callee is the side that waited for an answer',
      );
      expect(outcome.waited, const Duration(seconds: 45));
      expect(outcome.notice, 'Cevap verilmedi.');
      expect(harness.machine.lastMissedCall?.reason, MissedCallReason.timedOut);
      expect(harness.machine.lastMissedCall?.detail, 'Cevap verilmedi.');
    });

    test('clears the entry, so the answer screen can be dismissed', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());
      harness.timers.only.fire();

      // The dialog is driven by `session == null || status != incoming`.
      expect(harness.machine.isRinging, isFalse);
      expect(harness.machine.isBusy, isFalse);
      expect(harness.machine.isRingTimerArmed, isFalse);
      // And a new call can be taken right away.
      expect(harness.ring(harness.nextId()).applied, isTrue);
    });

    test('never sends call-end, which is the caller\'s frame', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());

      harness.timers.only.fire();

      expect(harness.sent, isNot(contains(isA<CallEndMessage>())));
      expect(harness.sent.whereType<CallDeclineMessage>(), hasLength(1));
    });
  });

  group('the two timeouts are not the same timeout', () {
    test('the caller sends call-end, the callee sends call-decline', () {
      final CallHarness caller = CallHarness();
      caller.dial(CallMode.audio);
      caller.timers.only.fire();

      final CallHarness callee = CallHarness();
      callee.ring(callee.nextId());
      callee.timers.only.fire();

      expect(caller.sent.last, isA<CallEndMessage>());
      expect(caller.sent, isNot(contains(isA<CallDeclineMessage>())));
      expect(callee.sent.single, isA<CallDeclineMessage>());
      expect((caller.machine.outcome! as CallTimedOut).offeredByUs, isTrue);
      expect((callee.machine.outcome! as CallTimedOut).offeredByUs, isFalse);
      expect(
        caller.machine.outcome!.notice,
        isNot(callee.machine.outcome!.notice),
      );
    });

    test('a ringing callee has no offer timer to fire', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());

      expect(harness.machine.isOfferTimerArmed, isFalse);
      expect(harness.machine.isRingTimerArmed, isTrue);
    });

    test('a ringing caller has no ring timer to fire', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);

      expect(harness.machine.isRingTimerArmed, isFalse);
      expect(harness.machine.isOfferTimerArmed, isTrue);
    });

    test('a spent ring timer cannot end the next call of either side', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());
      final ArmedTimer spentRingTimer = harness.timers.only;
      spentRingTimer.fire();
      harness.machine.reset();

      final String second = harness.nextId();
      harness.ring(second);
      // Only the spent callback fires; the live ring timer is left alone.
      harness.timers.fireAllExcept(harness.timers.only);

      expect(harness.machine.status, CallStatus.incoming);
      expect(harness.machine.session?.id, second);
      expect(harness.machine.missedCalls, hasLength(1));
    });

    test('a spent offer timer cannot decline a call that is now ringing', () {
      final CallHarness harness = CallHarness();
      harness.dial(CallMode.audio);
      final ArmedTimer spentOfferTimer = harness.timers.only;
      spentOfferTimer.fire();
      expect(harness.machine.status, CallStatus.ended);
      harness.machine.reset();

      harness.ring(harness.nextId());
      final int frames = harness.sent.length;

      harness.timers.fireAllExcept(harness.timers.only);

      expect(harness.machine.status, CallStatus.incoming);
      expect(
        harness.sent,
        hasLength(frames),
        reason: 'the offer timeout must not speak for the ring timeout',
      );
      expect(harness.sent, isNot(contains(isA<CallDeclineMessage>())));
    });
  });
}
