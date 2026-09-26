// Mid-call audio -> video, and the guards around it.
//
// The Dart transport creates an audio, a camera and a screen transceiver as
// `sendrecv` when the peer connection is built, so turning the camera on
// mid-call is a `replaceTrack` on a sender that already exists: no new call, no
// new id, no offer, no renegotiation.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';

import 'support/call_harness.dart';

void main() {
  group('upgradeToVideo', () {
    // Bullet: "an audio call can be upgraded to video mid-call and the machine
    // reports it".
    test('turns the camera on without a new call, a frame or a timer', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id, CallMode.audio);
      final int framesBefore = harness.sent.length;
      expect(harness.machine.session?.mode, CallMode.audio);
      expect(harness.machine.session?.hasVideo, isFalse);

      final CallTransition transition = harness.machine.upgradeToVideo();

      // One local media step, and nothing else at all.
      expect(
        CallHarness.shapeOf(transition),
        <String>['PublishMedia'],
        reason: 'no frame means no SDP means no renegotiation',
      );
      expect(transition.frames, isEmpty);
      expect(
        transition.mediaRequest,
        PublishMedia(mode: CallMode.video, audio: true, video: true),
      );
      // The call is the same call.
      expect(transition.status, CallStatus.connected);
      expect(transition.statusChanged, isFalse);
      expect(harness.machine.session?.id, id);
      expect(harness.sent, hasLength(framesBefore));
      // No timer is armed by an upgrade: nothing can time out mid-call.
      expect(harness.timers.liveCount, 0);
    });

    test('reports the upgrade in the session', () {
      final CallHarness harness = CallHarness();
      harness.acceptedAndConnected(harness.nextId(), CallMode.audio);
      final DateTime before = harness.clock.value;

      final CallTransition transition = harness.machine.upgradeToVideo();

      expect(transition.applied, isTrue);
      expect(harness.machine.session?.mode, CallMode.video);
      expect(harness.machine.session?.hasVideo, isTrue);
      expect(
        harness.machine.session?.upgradedAt,
        before.add(const Duration(seconds: 1)),
      );
      expect(harness.machine.status, CallStatus.connected);
    });

    test('keeps the audio track live', () {
      final CallHarness harness = CallHarness();
      harness.acceptedAndConnected(harness.nextId(), CallMode.audio);

      expect(
        harness.machine.upgradeToVideo().mediaRequest?.audio,
        isTrue,
        reason: 'upgrading video must not mute the microphone',
      );
    });

    test('is refused before the call is connected', () {
      final CallHarness ringing = CallHarness();
      ringing.ring(ringing.nextId());
      final CallTransition whileRinging = ringing.machine.upgradeToVideo();
      expect(whileRinging.refusal, CallRefusal.notConnected);
      expect(whileRinging.refusal!.message, 'Arama bağlı değil.');
      expect(whileRinging.mediaRequest, isNull);

      final CallHarness connecting = CallHarness();
      final String id = connecting.nextId();
      connecting.dial(CallMode.audio);
      connecting.machine.onRemoteAccept(callId: id);
      final CallTransition whileConnecting = connecting.machine
          .upgradeToVideo();
      expect(whileConnecting.refusal, CallRefusal.notConnected);
      expect(connecting.machine.session?.mode, CallMode.audio);
    });

    test('is refused when the call started as video', () {
      final CallHarness harness = CallHarness();
      harness.acceptedAndConnected(harness.nextId(), CallMode.video);
      final int frames = harness.sent.length;

      final CallTransition transition = harness.machine.upgradeToVideo();

      expect(transition.refusal, CallRefusal.alreadyVideo);
      expect(transition.refusal!.message, 'Arama zaten görüntülü.');
      expect(transition.mediaRequest, isNull);
      expect(harness.sent, hasLength(frames));
    });

    test('is idempotent: a second press does nothing', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id, CallMode.audio);
      harness.machine.upgradeToVideo();
      final DateTime upgradedAt = harness.machine.session!.upgradedAt!;
      final int reported = harness.transitions.length;

      final CallTransition again = harness.machine.upgradeToVideo();

      expect(again.applied, isFalse);
      expect(again.refusal, CallRefusal.alreadyVideo);
      expect(harness.transitions, hasLength(reported));
      expect(harness.machine.session?.upgradedAt, upgradedAt);
      expect(harness.machine.session?.id, id);
    });

    test('is refused after the call ended', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id, CallMode.audio);
      harness.machine.end();

      final CallTransition transition = harness.machine.upgradeToVideo();

      expect(transition.applied, isFalse);
      expect(transition.refusal, CallRefusal.notConnected);
    });

    test('works the same on the callee side', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.answerAndConnect(id, CallMode.audio);

      final CallTransition transition = harness.machine.upgradeToVideo();

      expect(transition.applied, isTrue);
      expect(transition.mediaRequest?.video, isTrue);
      expect(harness.machine.session?.side, CallSide.callee);
      expect(harness.machine.session?.id, id);
    });

    test('an upgraded call is recorded as the mode it ended in', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id, CallMode.audio);
      harness.machine.upgradeToVideo();

      harness.machine.end();

      expect(harness.machine.lastMissedCall?.mode, CallMode.video);
      expect(
        harness.machine.lastMissedCall?.reason,
        MissedCallReason.endedNormally,
      );
      expect(harness.machine.lastMissedCall?.id, id);
    });

    test('an upgrade does not re-arm a timer that a hangup disarmed', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id, CallMode.audio);
      harness.machine.end();
      expect(harness.machine.isOfferTimerArmed, isFalse);
      expect(harness.machine.isRingTimerArmed, isFalse);

      harness.machine.upgradeToVideo();
      harness.timers.fireAll();

      expect(harness.machine.status, CallStatus.ended);
      expect(harness.sent.whereType<CallOfferMessage>(), hasLength(1));
    });
  });
}
