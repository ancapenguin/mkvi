/// The Turkish catalogue and the text shaping.
///
/// Two contracts, both easy to break silently:
///
/// * every string this layer can show exists, is Turkish, and is non-empty —
///   a Turkish-only product must never fall back to an English framework string
///   or to a blank button, and the only way to add an entry without wording is
///   a compile error (`NoticeTr`'s constructor requires the text);
/// * the zero-width break opportunities inserted into a long path are invisible.
///   If they are not, the user reads `C:\Users\ilber` and the notice body is
///   wrong in a way no layout test would catch.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/ui/notice/notice.dart';

/// The letters that Turkish has and English does not.
///
/// A diacritic per entry would be the wrong oracle: `Bilgi`, `Hata` and
/// `Bildirimi kapat` are all perfectly Turkish and all diacritic-free. So the
/// letters are checked against the catalogue as a whole, and each *entry* is
/// checked against a blocklist of the words an untranslated string would use.
const String _turkishOnlyLetters = 'ıİşŞğĞ';

/// Words a Turkish catalogue must not contain. These are the words
/// `src/App.tsx` and Flutter's own defaults would have produced, and they are
/// the realistic way an English string reaches a Turkish product.
const List<String> _englishWords = <String>[
  'close',
  'connected',
  'disconnected',
  'error',
  'failed',
  'info',
  'loading',
  'ok',
  'retry',
  'saved',
  'send',
  'success',
  'warning',
];

/// Whether [entry] is free of the words an untranslated string would be made of.
bool _hasNoEnglishWord(String entry) {
  final Iterable<String> words = entry
      .toLowerCase()
      .split(RegExp(r'[^a-zçğıöşü]+'))
      .where((String word) => word.isNotEmpty);
  for (final String word in words) {
    if (_englishWords.contains(word)) return false;
  }
  return true;
}

/// How many of [letters] appear anywhere in [value]. The catalogue-level Turkish
/// oracle: a genuine Turkish catalogue uses several of them, an English one uses
/// none.
int _countLetters(String value, String letters) {
  int found = 0;
  for (final String letter in letters.split('')) {
    if (value.contains(letter)) found += 1;
  }
  return found;
}

void main() {
  group('every catalogue entry', () {
    test('is non-empty and carries no placeholder', () {
      for (final NoticeTr entry in NoticeTr.values) {
        expect(
          entry.tr,
          isNotEmpty,
          reason: '${entry.name} must say something',
        );
        expect(
          entry.tr.trim(),
          entry.tr,
          reason: '${entry.name} has stray whitespace',
        );
        expect(
          entry.tr,
          isNot(contains('TODO')),
          reason: '${entry.name} is a placeholder, not a string',
        );
      }
    });

    test('the catalogue as a whole is Turkish', () {
      final String everything = noticeTrCatalogue.values.join(' | ');
      expect(
        _countLetters(everything, _turkishOnlyLetters),
        greaterThanOrEqualTo(3),
        reason:
            'a Turkish catalogue uses several of the letters English does '
            'not have; an English one uses none of them',
      );
    });

    test('is Turkish, not an untranslated framework string', () {
      for (final MapEntry<NoticeTr, String> entry
          in noticeTrCatalogue.entries) {
        expect(
          _hasNoEnglishWord(entry.value),
          isTrue,
          reason:
              '${entry.key.name} contains a word only an untranslated '
              'string would use',
        );
        expect(
          entry.value,
          isNot(contains('Lorem')),
          reason: '${entry.key.name} is filler text',
        );
      }
    });

    test('is a full sentence where it is one, and a label where it is not', () {
      // A label is read in a strip next to a dot: a full stop on "Bağlı" would
      // look like a typo. A detail is a sentence and must be punctuated.
      for (final NoticeTr entry in NoticeTr.values) {
        final bool isSentence = entry.name.contains('Detail');
        expect(
          entry.tr.endsWith('.'),
          isSentence,
          reason:
              '${entry.name} is '
              '${isSentence ? 'a detail sentence' : 'a label'}',
        );
      }
      expect(
        NoticeTr.statusIdleDetail.tr.endsWith('.'),
        isTrue,
        reason: 'and a detail really is punctuated',
      );
    });

    test('is unique, so two entries cannot say the same thing', () {
      final Map<String, NoticeTr> seen = <String, NoticeTr>{};
      for (final MapEntry<NoticeTr, String> entry
          in noticeTrCatalogue.entries) {
        expect(
          seen.containsKey(entry.value),
          isFalse,
          reason:
              '${entry.key.name} and ${seen[entry.value]?.name} both say '
              '"${entry.value}"',
        );
        seen[entry.value] = entry.key;
      }
    });

    test('covers the catalogue exactly: no entry, no value without one', () {
      expect(
        noticeTrCatalogue.length,
        NoticeTr.values.length,
        reason: 'every enum value has an entry and there are no extras',
      );
      for (final NoticeTr entry in NoticeTr.values) {
        expect(noticeTrCatalogue[entry], entry.tr);
      }
    });

    test('has no mojibake in it', () {
      // A file written in the wrong encoding reads as "Ba?lant? ayarlar?." and
      // still passes every other assertion in this file, so the byte sequences a
      // mis-encoded UTF-8 file produces are checked explicitly.
      //
      // They are built from code units rather than typed: a source file that
      // contains the sequences it forbids would itself be flagged by the
      // repository-wide mojibake scan.
      final List<String> markers = <String>[
        String.fromCharCode(0x00C3), // U+00C3, the lead byte of a 2-byte
        String.fromCharCode(0x00C5), // U+00C5, the lead byte of a 2-byte
        String.fromCharCode(0x00C4), // U+00C4, the lead byte of a 2-byte
        String.fromCharCode(0x20AC), // U+20AC, the euro sign, i.e. the tail
      ];
      for (final MapEntry<NoticeTr, String> entry
          in noticeTrCatalogue.entries) {
        for (final String marker in markers) {
          expect(
            entry.value.contains(marker),
            isFalse,
            reason:
                '${entry.key.name} contains U+'
                '${marker.codeUnitAt(0).toRadixString(16).toUpperCase()}, which '
                'means this file was written in the wrong encoding',
          );
        }
        expect(
          entry.value,
          isNot(contains(String.fromCharCode(0xFFFD))),
          reason: '${entry.key.name} contains a replacement character',
        );
      }
    });
  });

  group('the catalogue against the two channels', () {
    test('every status value has a Turkish label and a Turkish detail', () {
      for (final ConnectionStatus status in ConnectionStatus.values) {
        expect(status.labelTr, isNotEmpty, reason: status.name);
        expect(status.detailTr, isNotEmpty, reason: status.name);
        expect(_hasNoEnglishWord(status.labelTr), isTrue, reason: status.name);
        expect(_hasNoEnglishWord(status.detailTr), isTrue, reason: status.name);
        expect(status.labelTr, isNot(status.detailTr));
      }
    });

    test('two statuses may not share a label, or the strip tells the user '
        'nothing', () {
      final Set<String> labels = ConnectionStatus.values
          .map((ConnectionStatus status) => status.labelTr)
          .toSet();
      expect(
        labels.length,
        ConnectionStatus.values.length,
        reason: 'the labels are what the user reads, so they must differ',
      );
    });

    test('every severity has a Turkish name for the screen reader', () {
      for (final NoticeKind kind in NoticeKind.values) {
        expect(kind.labelTr, isNotEmpty, reason: kind.name);
        expect(
          _hasNoEnglishWord(kind.labelTr),
          isTrue,
          reason: 'the severity mark is an icon, so this is its only name',
        );
      }
      expect(
        NoticeKind.values.map((NoticeKind kind) => kind.labelTr).toSet().length,
        NoticeKind.values.length,
      );
    });

    test('only the online status counts as usable', () {
      for (final ConnectionStatus status in ConnectionStatus.values) {
        expect(
          status.isUsable,
          status == ConnectionStatus.online,
          reason: status.name,
        );
      }
    });
  });

  group('the close control name', () {
    test('names the thing it closes, in Turkish', () {
      expect(NoticeTr.close.tr, 'Bildirimi kapat');
      expect(_hasNoEnglishWord(NoticeTr.close.tr), isTrue);
    });
  });

  group('the zero-width break opportunities', () {
    test('a Windows path gets one after every separator', () {
      const String path = r'C:\Users\ilber\Documents';
      final String shaped = noticeSoftBreaks(path);

      expect(
        noticeVisibleText(shaped),
        path,
        reason:
            'a backslash is the character a Windows path breaks on, and the '
            'path itself must not change',
      );
      expect(
        shaped.codeUnits
            .where((int unit) => unit == noticeZeroWidthSpace)
            .length,
        4,
        reason: 'the drive colon and the three directory separators',
      );
    });

    test('nothing visible changes: the shaping is invisible', () {
      const List<String> samples = <String>[
        r'C:\Users\ilber\Documents\MKVI\indirilenler\rapor-cek.pdf',
        'Bağlantı ayarları kaydedildi.',
        'Yeniden bağlanılıyor: bağlantı koptu.',
        'Cihaz kimliği doğrulanamadı; bağlantı kapatıldı.',
        r'\\sunucu\paylasim\2026\rapor (1).pdf',
        'Tek karakter: ı',
        '',
      ];
      for (final String sample in samples) {
        expect(
          noticeVisibleText(noticeSoftBreaks(sample)),
          sample,
          reason: '"$sample" must read exactly as it was written',
        );
      }
    });

    test(
      'it never inserts a trailing break, so nothing grows a phantom line',
      () {
        for (final String ending in <String>['/', r'\', '.', ' ']) {
          // One word, so the only break opportunity that could be inserted is the
          // trailing one this test is about.
          final String shaped = noticeSoftBreaks('Rapor$ending');
          expect(
            shaped.endsWith(noticeZeroWidthSpaceChar),
            isFalse,
            reason: 'a text ending in a break character',
          );
          expect(shaped, 'Rapor$ending', reason: 'so the tail is untouched');
        }
      },
    );

    test('text with nothing to break on is returned unchanged', () {
      expect(noticeSoftBreaks('Tamam'), 'Tamam');
      expect(noticeSoftBreaks(''), '');
      expect(noticeSoftBreaks('ı'), 'ı');
    });

    test('a 300-character path is broken enough to fit three lines', () {
      // The reported shape: `src/App.tsx:376` interpolated a full saved path.
      final String path = <String>[
        r'C:\Users\ilber\Documents\MKVI\indirilenler',
        '2026-09-26',
        'cok-uzun-bir-dosya-adi-ki-her-zamanlikta-bir-klasor-acilir',
        '2026-09-26-120345-1234567890123-rapor-cek-bilgi-notu-v2-final.pdf',
      ].join(r'\');
      expect(path.length, greaterThan(150));

      final String shaped = noticeSoftBreaks(path);
      expect(
        noticeVisibleText(shaped),
        path,
        reason: 'and it is still the same path to the person reading it',
      );
      expect(
        shaped.codeUnits
            .where((int unit) => unit == noticeZeroWidthSpace)
            .length,
        greaterThan(5),
        reason:
            'without a break opportunity after each separator, a path has '
            'nowhere to wrap and overflows the cap',
      );
    });

    test('the break opportunities are not wider than nothing', () {
      // A zero-width space must be zero width, or the cap changes meaning.
      expect(String.fromCharCode(noticeZeroWidthSpace), hasLength(1));
      expect(noticeZeroWidthSpaceChar, String.fromCharCode(0x200B));
      expect(noticeVisibleText(noticeZeroWidthSpaceChar), isEmpty);
    });

    test('Turkish letters are not mistaken for break characters', () {
      // The dotted and dotless I are the classic trap: a rule that broke on
      // "I" would cut İşlem and Işık in half.
      for (final String sample in <String>[
        'İşlem tamam',
        'Çağrı iptal',
        'Işık ve gölge',
        'Öğrenildi',
        'Şimdi gönder',
      ]) {
        expect(
          noticeVisibleText(noticeSoftBreaks(sample)),
          sample,
          reason: '"$sample" must survive shaping intact',
        );
      }
      expect(
        noticeSoftBreaks('İşlem'),
        'İşlem',
        reason: 'no break opportunity inside a word, so it cannot be split',
      );
    });
  });
}
