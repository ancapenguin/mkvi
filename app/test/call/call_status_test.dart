// The status enum, its labels, and the refusals — asserted rather than assumed.
//
// [CallStatus] is the one place the call's lifecycle is written down, so nothing
// else in the layer can keep the set and its Turkish labels in step. This file
// does: the labels are pinned verbatim, and the two predicates that decide
// whether a step is allowed (`isLive`, `isSettled`) are pinned against the
// statuses that must be in each.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';

void main() {
  group('CallStatus', () {
    // The Turkish label of every status, verbatim.
    const Map<CallStatus, String> ported = <CallStatus, String>{
      CallStatus.idle: 'Arama yok',
      CallStatus.outgoing: 'Yanıt bekleniyor',
      CallStatus.incoming: 'Gelen arama',
      CallStatus.connecting: 'Bağlanıyor',
      CallStatus.connected: 'Güvenli bağlantı',
      CallStatus.ended: 'Arama sona erdi',
    };

    test('has exactly the six statuses the old UI had', () {
      expect(CallStatus.values, hasLength(6));
      expect(CallStatus.values.toSet(), ported.keys.toSet());
    });

    test('carries the Turkish label of every status, byte for byte', () {
      for (final MapEntry<CallStatus, String> entry in ported.entries) {
        expect(
          entry.key.label,
          entry.value,
          reason: '${entry.key.name} lost its Turkish label',
        );
      }
    });

    test('is live for exactly the four states a call occupies', () {
      for (final CallStatus status in CallStatus.values) {
        expect(
          status.isLive,
          <CallStatus>[
            CallStatus.outgoing,
            CallStatus.incoming,
            CallStatus.connecting,
            CallStatus.connected,
          ].contains(status),
          reason: '${status.name} has the wrong isLive',
        );
      }
    });

    test('rings only while an answer screen is waiting', () {
      expect(
        CallStatus.values.where((CallStatus s) => s.isRinging),
        <CallStatus>[CallStatus.incoming],
      );
    });

    test('is settled once both sides have accepted', () {
      expect(
        CallStatus.values.where((CallStatus s) => s.isSettled),
        <CallStatus>[CallStatus.connecting, CallStatus.connected],
      );
    });
  });

  group('timeouts', () {
    // The caller's 45 s offer timeout.
    test("the caller's offer timeout is the ported 45 s", () {
      expect(CallMachine.callOfferTimeout, const Duration(seconds: 45));
    });

    // The callee had no timeout at all before; this is the symmetric one.
    test("the callee's ring timeout is also 45 s", () {
      expect(CallMachine.callRingTimeout, const Duration(seconds: 45));
    });

    test('they are separate constants, so one can be shortened for a test', () {
      // Equal in value, independent in identity: a test that shortens one to
      // prove which timer fired is not shortening the other by accident.
      final CallMachine machine = CallMachine(
        startTimer: disabledCallTimerStarter,
        offerTimeout: const Duration(milliseconds: 1),
        ringTimeout: const Duration(seconds: 45),
      );
      expect(machine.offerTimeout, const Duration(milliseconds: 1));
      expect(machine.ringTimeout, const Duration(seconds: 45));
    });
  });

  group('modes', () {
    // Three `sendrecv` transceivers exist from the moment the connection is
    // built, so a mode only decides whether the camera track is live - it never
    // triggers an offer.
    test('a mode is a permission, not a negotiation', () {
      expect(modeWantsVideo(CallMode.video), isTrue);
      expect(modeWantsVideo(CallMode.audio), isFalse);
    });

    test('the wire names are the two the protocol already defines', () {
      expect(CallMode.audio.wireName, 'audio');
      expect(CallMode.video.wireName, 'video');
    });
  });

  group('refusals', () {
    test('every refusal carries Turkish text', () {
      for (final CallRefusal refusal in CallRefusal.values) {
        expect(refusal.message, isNotEmpty, reason: refusal.name);
        expect(
          refusal.message.codeUnitAt(0),
          inInclusiveRange(0x0041, 0x005a),
          reason: '${refusal.name} does not start with a capital letter',
        );
      }
    });

    test('the refusals ported from TypeScript are byte-identical', () {
      // A refusal that a call is already live.
      expect(
        CallRefusal.callInProgress.message,
        'Başka bir arama zaten etkin.',
      );
      // A refusal that the answer screen is gone.
      expect(
        CallRefusal.incomingCallNotFound.message,
        'Gelen arama bulunamadı.',
      );
    });

    test('the busy decline reuses the protocol string, not a new one', () {
      expect(PeerProtocol.busyCallReason, 'Meşgul.');
      expect(
        CallMessages.declineLabel,
        'Reddet',
        reason: 'the answer dialog button label is part of the same contract',
      );
    });
  });

  group('answer dialog strings', () {
    test('name the mode the peer asked for', () {
      expect(
        CallMessages.incomingEyebrow(CallMode.video),
        'Gelen görüntülü arama',
      );
      expect(CallMessages.incomingEyebrow(CallMode.audio), 'Gelen sesli arama');
    });

    test('keep the promise the answer dialog makes', () {
      // Kept literally true: no PublishMedia action exists before `accept` has
      // emitted one.
      expect(
        CallMessages.mediaPromise,
        'Kabul edene kadar kamera ve mikrofonundan hiçbir şey gönderilmez.',
      );
    });
  });
}
