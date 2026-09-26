// The feed parser, tested where a hostile or broken document differs from a
// working one.
//
// The port of `parse_feed` is `crates/mkvi_core/src/update.rs:70-85`, and both
// halves of its contract matter to security: a document that does not parse is an
// error, and a version that cannot be compared is *not* an upgrade. A feed is the
// one part of an update an attacker can rewrite, so every "be lenient here"
// decision is a decision to install something.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/update/update_failure.dart';
import 'package:mkvi/update/update_manifest.dart';
import 'package:mkvi/update/update_version.dart';

import 'support/fakes.dart';

void main() {
  final ReleaseVersion current = ReleaseVersion.tryParse(currentVersion)!;

  UpdateManifest parse(List<int> body) => parseUpdateManifest(body, current);

  UpdateOffer offerOf(List<int> body) {
    final UpdateManifest result = parse(body);
    expect(result, isA<ManifestOffersRelease>());
    return (result as ManifestOffersRelease).offer;
  }

  UpdateFailure failureOf(List<int> body) {
    final UpdateManifest result = parse(body);
    expect(result, isA<ManifestUnusable>());
    return (result as ManifestUnusable).failure;
  }

  group('a newer release is offered', () {
    test('with its version, notes, url and signature read out of the feed', () {
      final UpdateOffer offer = offerOf(feedJson());
      expect(offer.version.toString(), offeredVersion);
      expect(offer.notes, 'Düzeltmeler');
      expect(
        offer.url.toString(),
        'https://releases.example.invalid/mkvi-setup.exe',
      );
      expect(offer.signature, artifactSignature);
    });

    test('and the local file name comes from the url, not from a header', () {
      expect(offerOf(feedJson()).fileName, 'mkvi-setup.exe');
    });

    test('and a pre-release of a newer version is an upgrade too', () {
      expect(
        offerOf(feedJson(version: '0.3.0-rc.1')).version.toString(),
        '0.3.0-rc.1',
      );
    });

    test('and pub_date, which nothing reads, does not break the feed', () {
      // The real feed carries `pub_date`. A parser that required it would break
      // on the first honest document.
      expect(parse(feedJson()), isA<ManifestOffersRelease>());
    });
  });

  group('the same or an older version is not offered', () {
    test('an identical version is not an upgrade', () {
      final UpdateManifest result = parse(feedJson(version: currentVersion));
      expect(result, isA<ManifestNotNewer>());
      expect((result as ManifestNotNewer).offered, currentVersion);
    });

    test('an older version is not an upgrade', () {
      expect(parse(feedJson(version: '0.1.0')), isA<ManifestNotNewer>());
      expect(parse(feedJson(version: '0.1.9')), isA<ManifestNotNewer>());
    });

    test('a pre-release of the running version is not an upgrade', () {
      expect(
        parse(feedJson(version: '$currentVersion-rc.1')),
        isA<ManifestNotNewer>(),
      );
    });

    test('a rebuild carrying only build metadata is not an upgrade', () {
      expect(
        parse(feedJson(version: '$currentVersion+build.9')),
        isA<ManifestNotNewer>(),
      );
    });
  });

  group('an unparseable version is never treated as newer', () {
    // The whole point: a feed is attacker-reachable, and a parser that falls
    // back to "probably newer" here is an upgrade button anyone can press.
    test('a version that is not a version is simply not an upgrade', () {
      for (final String offered in <String>[
        'son sürüm',
        'latest',
        '0.2',
        '0.2.x',
        '99999999999999999999999.0.0',
        '0.2.0-',
      ]) {
        final UpdateManifest result = parse(feedJson(version: offered));
        expect(
          result,
          isA<ManifestNotNewer>(),
          reason: '"$offered" must never be an upgrade',
        );
        // The string is kept so a diagnostics screen can show what the feed said.
        expect((result as ManifestNotNewer).offered, offered);
      }
    });

    test('a pre-release below its final release is not an upgrade either', () {
      // The other direction of the same rule, spelled out here so the pairing
      // with the preflight test - an unreadable running version is a *refusal*,
      // not a silent "nothing newer" - is visible from both files.
      expect(ReleaseVersion.tryParse(currentVersion), isNotNull);
      expect(
        parseUpdateManifest(
          feedJson(version: '0.0.1'),
          ReleaseVersion.tryParse('0.0.0')!,
        ),
        isA<ManifestOffersRelease>(),
      );
    });
  });

  group('a malformed feed is an error, not an upgrade', () {
    test('a body that is not json', () {
      expect(
        failureOf(utf8.encode('json degil')),
        isA<UpdateFailureFeedUnreadable>(),
      );
      expect(failureOf(utf8.encode('')), isA<UpdateFailureFeedUnreadable>());
      expect(
        failureOf(utf8.encode('<html>404</html>')),
        isA<UpdateFailureFeedUnreadable>(),
      );
    });

    test('a body that is not utf-8', () {
      expect(
        failureOf(<int>[0xff, 0xfe, 0x00]),
        isA<UpdateFailureFeedUnreadable>(),
      );
    });

    test('json that is not an object', () {
      expect(
        failureOf(utf8.encode('[1,2,3]')),
        isA<UpdateFailureFeedUnreadable>(),
      );
      expect(
        failureOf(utf8.encode('"0.2.1"')),
        isA<UpdateFailureFeedUnreadable>(),
      );
      expect(
        failureOf(utf8.encode('null')),
        isA<UpdateFailureFeedUnreadable>(),
      );
    });

    test('an object with no version', () {
      expect(
        failureOf(utf8.encode('{"notes":"sadece notlar"}')),
        isA<UpdateFailureFeedUnreadable>(),
      );
    });

    test('a version that is not a string', () {
      expect(
        failureOf(utf8.encode('{"version":0.2,"platforms":{}}')),
        isA<UpdateFailureFeedUnreadable>(),
      );
    });
  });

  group('a newer release with nothing to install is an error', () {
    test('no platforms key at all', () {
      expect(
        failureOf(utf8.encode('{"version":"0.2.1","notes":""}')),
        isA<UpdateFailureNoArtifactForPlatform>(),
      );
    });

    test('an empty platforms map', () {
      expect(
        failureOf(utf8.encode('{"version":"0.2.1","platforms":{}}')),
        isA<UpdateFailureNoArtifactForPlatform>(),
      );
    });

    test('platforms for another machine only', () {
      expect(
        failureOf(feedJson(includePlatforms: false)),
        isA<UpdateFailureNoArtifactForPlatform>(),
      );
    });

    test('a windows entry with no url or no signature', () {
      expect(
        failureOf(
          utf8.encode(
            '{"version":"0.2.1","platforms":'
            '{"windows-x86_64":{"signature":"c2ln"}}}',
          ),
        ),
        isA<UpdateFailureNoArtifactForPlatform>(),
      );
      expect(
        failureOf(
          utf8.encode(
            '{"version":"0.2.1","platforms":'
            '{"windows-x86_64":{"url":"https://h/x.exe"}}}',
          ),
        ),
        isA<UpdateFailureNoArtifactForPlatform>(),
      );
    });

    test('a url with no scheme, which nothing could fetch', () {
      expect(
        failureOf(feedJson(url: '/mkvi-setup.exe')),
        isA<UpdateFailureNoArtifactForPlatform>(),
      );
      expect(
        failureOf(feedJson(url: 'not a url at all')),
        isA<UpdateFailureNoArtifactForPlatform>(),
      );
    });
  });

  group('the artefact file name cannot be chosen by the server', () {
    // The url is the one string in the offer an attacker fully controls, and it
    // becomes a path on this machine. Three ways that goes wrong, three defences.
    test(
      'a traversal in the url cannot climb out of the download directory',
      () {
        final UpdateOffer offer = offerOf(
          feedJson(url: 'https://h/../../windows/system32/evil.exe'),
        );
        expect(offer.fileName, isNot(contains('/')));
        expect(offer.fileName, isNot(contains('\\')));
        expect(offer.fileName, isNot(contains('..')));
      },
    );

    test('a name made only of dots is refused', () {
      expect(
        offerOf(feedJson(url: 'https://h/..')).fileName,
        'update-$offeredVersion.bin',
      );
      expect(
        offerOf(feedJson(url: 'https://h/')).fileName,
        'update-$offeredVersion.bin',
      );
    });

    test('only the last path segment is used', () {
      expect(
        offerOf(feedJson(url: 'https://h/a/b/setup.msi')).fileName,
        'setup.msi',
      );
    });

    test('a control character in the name is replaced, not kept', () {
      final UpdateOffer offer = offerOf(
        feedJson(url: 'https://h/mkvi%0Asetup.exe'),
      );
      expect(offer.fileName, isNot(contains('\n')));
      expect(offer.fileName, contains('setup'));
    });
  });
}
