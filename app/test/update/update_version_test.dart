// The semver subset, tested against the same rules the Rust core applies.
//
// Every case here is a case where "guess" and "read" disagree. The feed is
// attacker-reachable, so the only safe answer to a string that does not parse is
// "no", and the port in `lib/update/update_version.dart` has to make the same
// choices `crates/mkvi_core/src/update.rs:198-252` makes - a disagreement there
// is a place where one side of the bridge offers a downgrade the other calls an
// upgrade.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/update/update_version.dart';

void main() {
  group('reading a version', () {
    test('reads the three numeric parts', () {
      final ReleaseVersion? version = ReleaseVersion.tryParse('1.2.3');
      expect(version, isNotNull);
      expect(version!.major, 1);
      expect(version.minor, 2);
      expect(version.patch, 3);
      expect(version.isFinal, isTrue);
      expect(version.preRelease, isEmpty);
      expect(version.toString(), '1.2.3');
    });

    test('tolerates a leading v and surrounding space', () {
      expect(ReleaseVersion.tryParse('v0.2.1')?.toString(), '0.2.1');
      expect(ReleaseVersion.tryParse('  0.2.1\n')?.toString(), '0.2.1');
      expect(ReleaseVersion.tryParse(' v0.2.1 ')?.toString(), '0.2.1');
    });

    test('reads a pre-release suffix', () {
      final ReleaseVersion? version = ReleaseVersion.tryParse('1.0.0-rc.1');
      expect(version, isNotNull);
      expect(version!.isFinal, isFalse);
      expect(version.preRelease, 'rc.1');
      expect(version.toString(), '1.0.0-rc.1');
    });

    test('refuses anything that is not major.minor.patch', () {
      // The shapes a real feed has carried, and the shapes a mistyped tag has.
      for (final String bad in <String>[
        '',
        ' ',
        '0',
        '0.1',
        '0.1.2.3',
        '1.2.x',
        'x.2.3',
        '1..3',
        '1.2.',
        '.2.3',
        '+1.2.3',
        '1.2.3-',
        '-1.2.3',
        'son sürüm',
        'latest',
        '1 . 2 . 3',
        '01a.2.3',
        // `int.parse` would take a leading `+`; semver does not.
        '+1.2',
        // A number too large for the host's integers.
        '99999999999999999999999.0.0',
      ]) {
        expect(
          ReleaseVersion.tryParse(bad),
          isNull,
          reason: '"$bad" must be unreadable rather than guessed at',
        );
      }
    });

    test('build metadata is dropped before anything is read', () {
      // `1.0.0-rc.1+build.7` is still the pre-release it looks like, which only
      // works if the `+` is handled before the `-`.
      final ReleaseVersion? version = ReleaseVersion.tryParse(
        '1.0.0-rc.1+build.7',
      );
      expect(version, isNotNull);
      expect(version!.isFinal, isFalse);
      expect(version.preRelease, 'rc.1');
      expect(version.toString(), '1.0.0-rc.1');
      expect(ReleaseVersion.tryParse('1.0.0+build.7')?.toString(), '1.0.0');
    });
  });

  group('precedence', () {
    ReleaseVersion parse(String value) => ReleaseVersion.tryParse(value)!;

    test('a pre-release sorts below its own final release', () {
      // The property that makes "do not offer 1.0.0-rc.1 to somebody on 1.0.0"
      // true, and the one a naive string comparison gets wrong.
      expect(parse('1.0.0-rc.1').compareTo(parse('1.0.0')), lessThan(0));
      expect(parse('1.0.0-rc.1').isNewerThan(parse('1.0.0')), isFalse);
      expect(parse('1.0.0').isNewerThan(parse('1.0.0-rc.1')), isTrue);
      expect(parse('1.0.0-alpha').compareTo(parse('1.0.0-beta')), lessThan(0));
      expect(parse('1.0.0').isNewerThan(parse('1.0.0-alpha')), isTrue);
    });

    test('a pre-release of a newer version is still an upgrade', () {
      expect(parse('1.0.1-rc.1').isNewerThan(parse('1.0.0')), isTrue);
      expect(parse('0.2.1-rc.1').isNewerThan(parse('0.2.0')), isTrue);
    });

    test('build metadata takes no part at all', () {
      expect(parse('1.0.0+build.9').isNewerThan(parse('1.0.0')), isFalse);
      expect(parse('1.0.0').isNewerThan(parse('1.0.0+build.9')), isFalse);
      expect(
        parse('1.0.1+build.1').isNewerThan(parse('1.0.0+build.9')),
        isTrue,
      );
      expect(parse('1.0.0+build.9'), parse('1.0.0'));
    });

    test('numbers compare as numbers, not as text', () {
      // The defect a lexicographic comparison has: "0.10.0" sorts below
      // "0.9.0" as text and above it as a version.
      expect(parse('0.10.0').isNewerThan(parse('0.9.0')), isTrue);
      expect(parse('0.9.0').isNewerThan(parse('0.10.0')), isFalse);
      expect(parse('10.0.0').isNewerThan(parse('9.0.0')), isTrue);
      expect(parse('0.2.10').isNewerThan(parse('0.2.9')), isTrue);
      expect(parse('0.2.0').isNewerThan(parse('0.1.99')), isTrue);
    });

    test('an equal version is not newer, however it is written', () {
      expect(parse('0.2.0').isNewerThan(parse('0.2.0')), isFalse);
      expect(parse('v0.2.0').isNewerThan(parse('0.2.0')), isFalse);
      expect(parse('0.2.0+7').isNewerThan(parse('0.2.0')), isFalse);
    });

    test('ordering is total over a mixed list', () {
      final List<ReleaseVersion> sorted = <ReleaseVersion>[
        parse('1.0.0'),
        parse('0.9.9'),
        parse('1.0.0-rc.1'),
        parse('0.10.0'),
        parse('1.0.0-alpha'),
        parse('1.0.0+build.1'),
      ]..sort();
      expect(sorted.map((ReleaseVersion v) => v.toString()).toList(), <String>[
        '0.9.9',
        '0.10.0',
        '1.0.0-alpha',
        '1.0.0-rc.1',
        '1.0.0',
        '1.0.0',
      ]);
    });
  });

  test('equality and hashing agree', () {
    final ReleaseVersion a = ReleaseVersion.tryParse('1.2.3-rc.1+build.4')!;
    final ReleaseVersion b = ReleaseVersion.tryParse('v1.2.3-rc.1')!;
    final ReleaseVersion c = ReleaseVersion.tryParse('1.2.3')!;
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
    expect(<ReleaseVersion>{a, b, c}, hasLength(2));
  });
}
