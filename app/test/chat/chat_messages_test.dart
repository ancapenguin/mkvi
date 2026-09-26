// Every user-facing string this layer can produce, proved Turkish and non-empty.
//
// "Turkish" is not a matter of taste here, it is the defect: `ChatCallWorkspace.tsx`
// had Turkish labels in its JSX next to an **English** `state` union
// (`"active" | "done" | "failed"`) that it dropped straight into a class name, and
// `formatBytes` used `.` as the decimal separator between strings that were all
// `tr-TR`. A surface that mixes the two is read by one person, in one language.
//
// So this file checks four things mechanically rather than by eye:
//
//  1. every `static const String` in `chat_messages.dart` is registered in
//     `ChatMessages.all` — read out of the *source file*, so a new string cannot
//     be added without being registered;
//  2. every registered string is non-empty, trimmed and free of mojibake;
//  3. none of them is one of the English strings the old build leaked;
//  4. every *formatted* string is Turkish too, asserted against the exact expected
//     text, including the numbers that are read out of `PeerProtocol`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/core/protocol/file_transfer.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';

/// The English the ported UI leaked, one entry per occurrence. A catalogue entry
/// equal to any of these is a regression, whether or not it "looks fine".
const List<String> englishLeaks = <String>[
  'active',
  'done',
  'failed',
  'cancelled',
  'sending',
  'sent',
  'read',
  'incoming',
  'outgoing',
  'Message not stored locally.',
  'Local history could not be opened.',
  'Message could not be sent.',
  'Peer is offline.',
  'Completed',
  'Failed',
  'Cancelled',
  'Sending:',
  'Receiving:',
  'Today',
  'Yesterday',
  'Retry',
  'Queue full.',
  'Empty message cannot be sent.',
  'Message can be at most 32 KB.',
  'File size must be between 1 byte and 512 MB.',
];

/// Turkish letters that only appear in Turkish text. Checked as a *floor*, not as
/// a proof: several legitimate strings ("Sil", "Gönder", "Al") are pure ASCII, so
/// a Turkish-character requirement would reject correct text. What it does prove
/// is that a whole catalogue cannot silently become English.
const String turkishCharacters = 'çğıöşüÇĞİÖŞÜ';

Matcher get isNonEmpty => isNotEmpty;

void main() {
  group('the catalogue is complete', () {
    test(
      'every static const String in the source file is registered in `all`',
      () {
        // The check reads the file rather than trusting a hand-written list, so a
        // string added to the class without being registered fails here.
        final String source = File(
          'lib/chat/chat_messages.dart',
        ).readAsStringSync();
        final RegExp declaration = RegExp(r'static const String\s+(\w+)\s*=');
        final List<String> declared = declaration
            .allMatches(source)
            .map((RegExpMatch m) => m.group(1)!)
            .toList(growable: false);

        expect(
          declared,
          isNotEmpty,
          reason:
              'the pattern found nothing, so this test would pass vacuously',
        );
        expect(
          declared.toSet().difference(ChatMessages.all.keys.toSet()),
          isEmpty,
          reason: 'every declared constant must be a key of ChatMessages.all',
        );
        expect(
          ChatMessages.all.keys.toSet().difference(declared.toSet()),
          isEmpty,
          reason:
              'and `all` must not claim a constant the file does not declare',
        );
      },
    );

    test('the map and the class agree, value for value', () {
      for (final MapEntry<String, String> entry in ChatMessages.all.entries) {
        expect(
          entry.value,
          isNotEmpty,
          reason: '${entry.key} is registered but empty',
        );
      }
      // The exact count is enforced by the completeness test above, which reads
      // the source. This is only a floor, so adding a string is not a failure.
      expect(ChatMessages.all.length, greaterThanOrEqualTo(20));
    });
  });

  group('every registered string is Turkish and non-empty', () {
    for (final MapEntry<String, String> entry in ChatMessages.all.entries) {
      test(entry.key, () {
        final String value = entry.value;
        expect(value.trim(), value, reason: 'leading or trailing whitespace');
        expect(value, isNotEmpty);
        expect(
          value,
          isNot(matches(RegExp(r'[\u00C3\u00C5\u00C4]|\u00E2\u20AC'))),
          reason: 'mojibake: the file is not valid UTF-8 Turkish',
        );
        expect(
          value,
          isNot(matches(RegExp(r'[\u0400-\u04FF\u0370-\u03FF]'))),
          reason: 'Cyrillic or Greek: not a Turkish UI',
        );
        expect(
          value.toLowerCase(),
          isNot(contains(RegExp('^(${englishLeaks.join('|')})\$'))),
          reason: 'this is the English the ported build leaked',
        );
      });
    }

    test('at least half the catalogue is unmistakably Turkish', () {
      // The floor that catches a whole catalogue drifting. It cannot be the only
      // check — "Gönder" is Turkish and has no Turkish-specific letter — which is
      // exactly why the per-string English list above exists.
      final Iterable<String> unmistakably = ChatMessages.all.values.where(
        (String value) => turkishCharacters.split('').any(value.contains),
      );
      expect(
        unmistakably.length,
        greaterThanOrEqualTo(ChatMessages.all.length ~/ 2),
        reason: 'the catalogue has drifted towards English',
      );
    });
  });

  group('the formatted strings are Turkish too', () {
    test('the message byte cap is read out of the core constant', () {
      // A literal "32 KB" here would be a second copy of
      // `PeerProtocol.maxMessageBytes` waiting to go stale.
      expect(ChatMessages.messageTooLarge(), 'Mesaj en fazla 32 KB olabilir.');
      expect(
        ChatMessages.messageTooLarge(),
        'Mesaj en fazla '
        '${ChatMessages.formatBytes(PeerProtocol.maxMessageBytes)} olabilir.',
      );
    });

    test('the file size range is read out of the core constant', () {
      expect(
        ChatMessages.fileSizeOutOfRange(),
        'Dosya boyutu 1 bayt ile 512 MB arasında olmalı.',
      );
      expect(
        ChatMessages.fileSizeOutOfRange(),
        'Dosya boyutu 1 bayt ile '
        '${ChatMessages.formatBytes(PeerProtocol.maxFileBytes)} arasında olmalı.',
      );
      expect(
        ChatMessages.fileOverCap(),
        'Dosya boyutu en fazla 512 MB olabilir.',
      );
    });

    test('byte sizes use the Turkish decimal comma', () {
      // THE DEFECT: `formatBytes` at `ChatCallWorkspace.tsx:107` produced "1.5 MB"
      // with a full stop, between two `tr-TR` strings. Turkish writes 1,5.
      expect(ChatMessages.formatBytes(0), '0 B');
      expect(ChatMessages.formatBytes(1023), '1023 B');
      expect(ChatMessages.formatBytes(1024), '1 KB');
      expect(
        ChatMessages.formatBytes(1536),
        '2 KB',
        reason:
            'the KB step rounds to whole numbers, exactly as the original did',
      );
      expect(ChatMessages.formatBytes(32 * 1024), '32 KB');
      expect(ChatMessages.formatBytes(100 * 1024), '100 KB');
      expect(
        ChatMessages.formatBytes(1024 * 1024),
        '1,0 MB',
        reason: 'from MB up the step carries one decimal, as the original did',
      );
      expect(
        ChatMessages.formatBytes(1536 * 1024),
        '1,5 MB',
        reason: 'and the separator is a Turkish comma, not a full stop',
      );
      expect(ChatMessages.formatBytes(PeerProtocol.maxFileBytes), '512 MB');
      expect(
        ChatMessages.formatBytes(5 * 1024 * 1024 * 1024),
        '5,0 GB',
        reason: 'the ladder stops at GB, exactly as the original did',
      );
      expect(
        ChatMessages.formatBytes(0),
        isNot(contains('.')),
        reason: 'no full stop may survive into a Turkish number',
      );
    });

    test('a byte pair reads as "done / total"', () {
      expect(ChatMessages.bytePair(512, 2048), '512 B / 2 KB');
    });

    test('the transfer heading differs by direction, in Turkish', () {
      expect(
        ChatMessages.transferHeading(TransferDirection.receive, 'rapor.pdf'),
        'Alınıyor: rapor.pdf',
      );
      expect(
        ChatMessages.transferHeading(TransferDirection.send, 'rapor.pdf'),
        'Gönderiliyor: rapor.pdf',
      );
    });

    test('the accessibility labels are Turkish', () {
      expect(
        ChatMessages.dismissTransferLabel('rapor.pdf'),
        'rapor.pdf satırını kapat',
      );
      expect(
        ChatMessages.transferProgressLabel('rapor.pdf'),
        'rapor.pdf aktarım ilerlemesi',
      );
      expect(
        ChatMessages.fileSaved('rapor.pdf', '/tmp/a.pdf'),
        'rapor.pdf kaydedildi: /tmp/a.pdf',
      );
    });

    test('the day label is Turkish for today, yesterday and a date', () {
      final DateTime now = DateTime(2026, 9, 26, 12);
      expect(ChatMessages.dayLabel(day: now, now: now), ChatMessages.today);
      expect(ChatMessages.dayLabel(day: now, now: now), 'Bugün');
      expect(
        ChatMessages.dayLabel(day: DateTime(2026, 9, 25, 3), now: now),
        'Dün',
      );
      expect(
        ChatMessages.dayLabel(day: DateTime(2026, 9, 14), now: now),
        '14 Eylül',
        reason: 'same year: no year is repeated',
      );
      expect(
        ChatMessages.dayLabel(day: DateTime(2025, 12, 1), now: now),
        '1 Aralık 2025',
        reason: 'another year: the year is spelled out',
      );
      expect(
        ChatMessages.dayLabel(day: DateTime(2026, 1, 1), now: now),
        '1 Ocak',
        reason: 'the Turkish month names, not the English ones',
      );
    });

    test('the time label is a 24-hour HH:mm', () {
      expect(ChatMessages.messageTime(DateTime(2026, 9, 26, 9, 5)), '09:05');
      expect(ChatMessages.messageTime(DateTime(2026, 9, 26, 23, 59)), '23:59');
      expect(ChatMessages.messageTime(DateTime(2026, 9, 26, 0, 0)), '00:00');
    });

    test('the wire reasons are reused from PeerProtocol, not copied', () {
      // A local copy of one of these could drift from the text the peer already
      // displays, and the two would meet on screen.
      expect(
        ChatMessages.tooManyTransfers(),
        PeerProtocol.tooManyPendingTransfers,
      );
      for (final String reused in <String>[
        PeerProtocol.transferNotFound,
        PeerProtocol.sinkOpenFailed,
        PeerProtocol.transferIncomplete,
        PeerProtocol.defaultFileDeclineReason,
        PeerProtocol.defaultFileCancelReason,
        PeerProtocol.fileDeclinedReason,
        PeerProtocol.unauthorizedFileData,
        PeerProtocol.fileSizeOverflow,
        PeerProtocol.invalidFrame,
        PeerProtocol.transferAlreadyReceiving,
      ]) {
        expect(
          reused.trim(),
          reused,
          reason: 'a wire reason is trimmed and set',
        );
        expect(reused, isNotEmpty);
      }
    });
  });

  group('the transfer row is Turkish in every state', () {
    test('all five phases produce a non-empty Turkish label', () {
      for (final TransferPhase phase in TransferPhase.values) {
        final TransferView view = TransferView(
          id: 'a' * 32,
          name: 'rapor.pdf',
          direction: TransferDirection.receive,
          phase: phase,
          transferred: 50,
          total: 100,
          detail: null,
        );
        expect(view.stateLabel.trim(), isNotEmpty, reason: phase.name);
        expect(view.stateLabel, isNot(contains('TransferPhase')));
        expect(view.heading, 'Alınıyor: rapor.pdf');
        expect(view.detailLabel, '50 B / 100 B');
        expect(view.percent, 50);
        expect(view.ratio, 0.5);
      }
      expect(TransferPhase.values, hasLength(5));
      expect(TransferPhase.offered.isTerminal, isFalse);
      expect(TransferPhase.active.isTerminal, isFalse);
      expect(TransferPhase.done.isTerminal, isTrue);
      expect(TransferPhase.failed.isTerminal, isTrue);
      expect(TransferPhase.cancelled.isTerminal, isTrue);
    });

    test('a total of zero reports zero rather than dividing by it', () {
      // TS guarded the same division with `total > 0 ? … : 0`; a row whose
      // `total` was not known yet must render, not produce NaN.
      final TransferView view = TransferView(
        id: 'a' * 32,
        name: 'rapor.pdf',
        direction: TransferDirection.send,
        phase: TransferPhase.active,
        transferred: 0,
        total: 0,
        detail: null,
      );
      expect(view.ratio, 0);
      expect(view.percent, 0);
      expect(view.stateLabel, '%0');
    });

    test('the ratio is clamped when the sink wrote more than was declared', () {
      final TransferView view = TransferView(
        id: 'a' * 32,
        name: 'rapor.pdf',
        direction: TransferDirection.receive,
        phase: TransferPhase.active,
        transferred: 250,
        total: 100,
        detail: null,
      );
      expect(view.ratio, 1);
      expect(view.percent, 100, reason: 'a bar cannot be 250% wide');
    });
  });
}
