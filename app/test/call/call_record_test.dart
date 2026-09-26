// The history entry every call leaves behind, and the four reasons it can have.
//
// There was no such record before: a declined call surfaced as a rejected
// promise, a timed-out one as the same rejected promise with a different
// message, and a cancelled one as nothing at all. One [MissedCall] per call,
// with a reason, is what the UI needs to show a list at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';

import 'support/call_harness.dart';

void main() {
  /// The single record a harness ended up with, and the reason it carries.
  (MissedCall, MissedCallReason) recordOf(CallHarness harness) {
    expect(harness.machine.missedCalls, hasLength(1));
    final MissedCall record = harness.machine.missedCalls.single;
    return (record, record.reason);
  }

  group('declined', () {
    test('a local decline is one record with the protocol reason', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id, CallMode.video);

      harness.machine.decline();

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.declined);
      expect(record.id, id);
      expect(record.mode, CallMode.video);
      expect(record.at, harness.clock.value);
      expect(record.detail, PeerProtocol.defaultCallDeclineReason);
      expect(record.label, 'Arama reddedildi.');
    });

    test("a remote decline keeps the peer's own words", () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);

      harness.machine.onRemoteDecline(callId: id, reason: 'Meşgul.');

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.declined);
      expect(record.detail, 'Meşgul.');
      expect(record.label, 'Meşgul.');
    });

    test('a callee whose camera will not open is a decline, not a failure', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);

      harness.machine.fail('Medya başlatılamadı.');

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.declined);
      expect(record.detail, 'Medya başlatılamadı.');
      expect(
        harness.machine.outcome,
        isA<CallFailed>(),
        reason: 'the outcome is a failure even though the record is a decline',
      );
      expect(harness.sent.single, isA<CallDeclineMessage>());
    });

    test('dismissing the answer screen is a decline too', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());

      harness.machine.end();

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.declined);
      expect(record.detail, isNull);
      expect(record.label, 'Arama reddedildi.');
    });
  });

  group('timed out', () {
    test('the caller gives up and records a timeout', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);

      harness.timers.only.fire();

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.timedOut);
      expect(record.id, id);
      expect(record.detail, isNull);
      expect(record.label, 'Cevap verilmedi.');
    });

    test('the callee gives up and records a timeout', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id, CallMode.video);

      harness.timers.only.fire();

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.timedOut);
      expect(record.id, id);
      expect(record.mode, CallMode.video);
      expect(record.detail, 'Cevap verilmedi.');
    });
  });

  group('cancelled', () {
    test('the caller hanging up on an unanswered invitation', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.dial(CallMode.audio, id: id);

      harness.machine.end();

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.cancelled);
      expect(record.id, id);
      expect(
        harness.machine.outcome,
        isA<CallEndedLocally>().having(
          (CallEndedLocally o) => o.reason,
          'reason',
          'Arama iptal edildi.',
        ),
      );
      expect(record.label, 'Karşı taraf aramayı iptal etti.');
    });

    test('the peer hanging up while the invitation was unanswered', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.ring(id);

      harness.machine.onRemoteEnd(callId: id);

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.cancelled);
      expect(record.id, id);
      expect(harness.machine.outcome, isA<CallCancelledByRemote>());
    });
  });

  group('ended normally', () {
    test('the local user hanging up from a connected call', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id, CallMode.video);

      harness.machine.end();

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.endedNormally);
      expect(record.id, id);
      expect(record.mode, CallMode.video);
      expect(record.label, 'Arama sona erdi.');
      expect(harness.machine.outcome!.notice, 'Arama sonlandırıldı.');
    });

    test('the peer hanging up from a connected call', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.acceptedAndConnected(id);

      harness.machine.onRemoteEnd(callId: id);

      final (MissedCall record, MissedCallReason reason) = recordOf(harness);
      expect(reason, MissedCallReason.endedNormally);
      expect(harness.machine.outcome, isA<CallEndedByRemote>());
      expect(
        harness.machine.outcome!.notice,
        'Karşı taraf aramayı sonlandırdı.',
      );
    });
  });

  // Bullet: "a missed call is recorded exactly once".
  group('exactly once', () {
    test('however many times a finished call is hung up on', () {
      final CallHarness harness = CallHarness();
      final String id = harness.nextId();
      harness.answerAndConnect(id);

      harness.machine.end();
      harness.machine.end();
      harness.machine.end();
      harness.machine.onRemoteEnd(callId: id);
      harness.machine.decline();
      harness.machine.fail();
      harness.timers.fireAll();
      harness.machine.reset();

      expect(harness.machine.missedCalls, hasLength(1));
      expect(
        harness.machine.lastMissedCall?.reason,
        MissedCallReason.endedNormally,
      );
      // And exactly one call-end went out, so the peer is not told twice.
      expect(harness.sent.whereType<CallEndMessage>(), hasLength(1));
    });

    test('however many times a decline is pressed', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());

      harness.machine.decline();
      harness.machine.decline();
      harness.machine.decline();
      harness.machine.end();
      harness.machine.fail();
      harness.timers.fireAll();

      expect(harness.machine.missedCalls, hasLength(1));
      expect(harness.sent.whereType<CallDeclineMessage>(), hasLength(1));
    });

    test(
      'a ring timeout that is later followed by an accept is one record',
      () {
        final CallHarness harness = CallHarness();
        final String id = harness.nextId();
        harness.ring(id);
        harness.timers.only.fire();

        // The user taps "Kabul et" one second too late.
        final CallTransition accept = harness.machine.accept();
        expect(accept.applied, isFalse);
        expect(accept.missedCall, isNull);

        expect(harness.machine.missedCalls, hasLength(1));
        expect(
          harness.machine.lastMissedCall?.reason,
          MissedCallReason.timedOut,
        );
      },
    );

    test('an offer refused because the line was busy is not a record', () {
      final CallHarness harness = CallHarness();
      harness.acceptedAndConnected(harness.nextId());

      final CallTransition refused = harness.ring(harness.nextId());

      expect(refused.applied, isFalse);
      expect(harness.sent.last, isA<CallDeclineMessage>());
      expect(
        harness.machine.missedCalls,
        isEmpty,
        reason: 'a call this machine was never in leaves no history',
      );
    });
  });

  group('the list', () {
    test('keeps one entry per call, oldest first', () {
      final CallHarness harness = CallHarness();
      final String first = harness.nextId();
      harness.ring(first);
      harness.machine.decline();
      harness.machine.reset();

      final String second = harness.nextId();
      harness.dial(CallMode.video, id: second);
      harness.machine.onRemoteDecline(callId: second);
      harness.machine.reset();

      final String third = harness.nextId();
      harness.ring(third, CallMode.video);
      harness.machine.accept();
      harness.machine.onMediaReady();
      harness.machine.end();

      expect(
        harness.machine.missedCalls.map((MissedCall c) => c.id).toList(),
        <String>[first, second, third],
      );
      expect(
        harness.machine.missedCalls.map((MissedCall c) => c.reason).toList(),
        <MissedCallReason>[
          MissedCallReason.declined,
          MissedCallReason.declined,
          MissedCallReason.endedNormally,
        ],
      );
      expect(harness.machine.lastMissedCall?.id, third);
    });

    test('is unmodifiable, because the UI only reads it', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());
      harness.machine.decline();

      expect(
        () => harness.machine.missedCalls.add(
          MissedCall(
            id: '0' * 32,
            mode: CallMode.audio,
            at: harness.clock.value,
            reason: MissedCallReason.declined,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('survives reset, so the UI can still show the list afterwards', () {
      final CallHarness harness = CallHarness();
      harness.ring(harness.nextId());
      harness.machine.decline();
      harness.machine.reset();

      expect(harness.machine.status, CallStatus.idle);
      expect(harness.machine.session, isNull);
      expect(harness.machine.missedCalls, hasLength(1));
      expect(harness.machine.outcome, isNotNull);
    });
  });

  group('the reasons', () {
    test('are four, and each has a Turkish label', () {
      expect(MissedCallReason.values, hasLength(4));
      for (final MissedCallReason reason in MissedCallReason.values) {
        expect(reason.label, isNotEmpty, reason: reason.name);
        expect(
          reason.label.endsWith('.'),
          isTrue,
          reason: '${reason.name} is not a sentence',
        );
      }
    });

    test('reuse the protocol strings where one already exists', () {
      expect(
        MissedCallReason.declined.label,
        PeerProtocol.defaultCallDeclineReason,
      );
      expect(MissedCallReason.timedOut.label, CallMessages.ringTimeoutReason);
      expect(
        MissedCallReason.endedNormally.label,
        '${CallStatus.ended.label}.',
        reason: 'the ended status label plus a full stop',
      );
    });
  });

  group('MissedCall', () {
    test('is a value: two equal records compare and hash the same', () {
      final DateTime at = DateTime.utc(2026, 9, 26, 12);
      final MissedCall one = MissedCall(
        id: 'abc',
        mode: CallMode.video,
        at: at,
        reason: MissedCallReason.declined,
        detail: 'Meşgul.',
      );
      final MissedCall two = MissedCall(
        id: 'abc',
        mode: CallMode.video,
        at: at,
        reason: MissedCallReason.declined,
        detail: 'Meşgul.',
      );
      final MissedCall withoutDetail = MissedCall(
        id: 'abc',
        mode: CallMode.video,
        at: at,
        reason: MissedCallReason.declined,
      );

      expect(one, two);
      expect(one.hashCode, two.hashCode);
      expect(one, isNot(withoutDetail));
      expect(one.toString(), contains('declined'));
      // The peer's words win when there are any.
      expect(one.label, 'Meşgul.');
      expect(withoutDetail.label, 'Arama reddedildi.');
    });
  });
}
