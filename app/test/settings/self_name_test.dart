// The name this device publishes about itself.
//
// Two ends, one function: `safeDisplayName`, the same one the wire uses. The old
// build only had the write end, so a value written by an older build - or by a
// hand-edited store - was announced unsanitised. Both ends are asserted here
// against that function directly, because a second implementation of the
// character rules is exactly how a name becomes safe in the UI and unsafe on
// the wire.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/core/protocol/peer_protocol.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';
import 'package:mkvi/settings/self_name.dart';
import 'package:mkvi/settings/settings_store.dart';

void main() {
  late InMemorySettingsStore store;
  late SelfNameField field;

  setUp(() {
    store = InMemorySettingsStore();
    field = SelfNameField(store);
  });

  /// U+200B ZERO WIDTH SPACE, U+202E RIGHT-TO-LEFT OVERRIDE and U+FEFF, spelled
  /// as code points so that no invisible character is ever stored in this
  /// source file.
  final String zeroWidth = String.fromCharCode(0x200b);
  final String rtlOverride = String.fromCharCode(0x202e);
  final String bom = String.fromCharCode(0xfeff);

  group('the write end', () {
    void expectSanitised(String raw) {
      field.write(raw);
      expect(
        store.read(SettingsKeys.selfName),
        safeDisplayName(raw),
        reason: 'write must store the wire\'s own sanitised form',
      );
      expect(field.read(), safeDisplayName(raw));
    }

    test('keeps an ordinary Turkish name intact', () {
      expectSanitised('Ayşe Gül');
      expect(store.read(SettingsKeys.selfName), 'Ayşe Gül');
    });

    test('trims and collapses whitespace', () {
      expectSanitised('  ali   veli \n');
      expect(store.read(SettingsKeys.selfName), 'ali veli');
    });

    test('strips control characters, invisibles and bidi overrides', () {
      expectSanitised('a${String.fromCharCode(0x00)}b');
      expectSanitised('a${zeroWidth}b');
      expectSanitised('a${rtlOverride}b');
      expectSanitised('a$bom b');
      expect(
        store.read(SettingsKeys.selfName),
        allOf(isNot(contains(zeroWidth)), isNot(contains(rtlOverride))),
      );
    });

    test('caps the length at the wire limit', () {
      field.write('x' * 200);
      expect(
        store.read(SettingsKeys.selfName)!.length,
        PeerProtocol.maxDisplayNameLength,
      );
      expect(
        store.read(SettingsKeys.selfName),
        'x' * PeerProtocol.maxDisplayNameLength,
      );
    });

    test('a name that sanitises away to nothing is stored as nothing', () {
      field.write('   ');
      expect(store.read(SettingsKeys.selfName), '');
      expect(field.read(), '');
      field.write(rtlOverride);
      expect(store.read(SettingsKeys.selfName), '');
    });
  });

  group('the read end', () {
    test('sanitises a value an older build, or a hand, left in the store', () {
      // Written directly, exactly as an older build would have: no sanitising
      // write end ever ran on this value.
      store.write(SettingsKeys.selfName, ' Ayşe$zeroWidth Gül ');
      expect(field.read(), 'Ayşe Gül');
      // And reading again changes nothing, so the read is idempotent.
      expect(field.read(), 'Ayşe Gül');
    });

    test('caps an over-long stored value', () {
      store.write(SettingsKeys.selfName, 'y' * 500);
      expect(field.read(), 'y' * PeerProtocol.maxDisplayNameLength);
    });

    test('is empty when the key was never written', () {
      expect(field.read(), '');
      expect(store.read(SettingsKeys.selfName), isNull);
    });
  });

  test('clearing forgets the name', () {
    field.write('Ayşe');
    field.clear();
    expect(store.read(SettingsKeys.selfName), isNull);
    expect(field.read(), '');
  });

  test('the two ends are the same function, so they cannot disagree', () {
    final List<String> samples = <String>[
      '',
      '   ',
      'Ayşe Gül',
      'a${String.fromCharCode(0x1b)}[31m kırmızı',
      'x' * 100,
      zeroWidth + rtlOverride + bom,
      '  çok   uzun   bir   isim  ',
    ];
    for (final String sample in samples) {
      expect(
        sanitisedSelfName(sample),
        safeDisplayName(sample),
        reason: sample,
      );
      expect(sanitisedSelfName(null), '', reason: 'null is an empty name');
      // A write followed by a read is a fixed point.
      field.write(sample);
      expect(field.read(), safeDisplayName(sample), reason: sample);
    }
  });
}
