// Where the feed lives, and what the build hands the updater.
//
// Two claims are held here that are easy to get quietly wrong:
//
// 1. **The feed is this repository's releases.** 0.1.x read its feed from a
//    separate *private* repository, which is not served to an unauthenticated
//    client at all, so every check in the product's life failed at the first
//    step. The address below is the official Tauri updater endpoint shape, and
//    it is a compile-time constant rather than a value a caller passes.
// 2. **The two values that matter come out of the build and have no defaults.**
//    A build that forgot a `--dart-define` has to say so in Turkish, in a way
//    that is not "the download may have been modified".
//
// The last test is a source-level sweep: the retired line's file paths, its dead
// feed repository and `raw.githubusercontent.com` must not reappear anywhere in
// `lib/update`, because every one of them is either a deleted file or an
// unreachable host, and a comment that points at one is a comment that lies.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/update/update_config.dart';
import 'package:mkvi/update/update_failure.dart';
import 'package:mkvi/update/update_preflight.dart';
import 'package:mkvi/update/update_version.dart';

import 'support/fakes.dart';

void main() {
  group('the feed address', () {
    test('is the latest release of this repository, over https', () {
      expect(
        releaseFeedUrlText,
        'https://github.com/ancapenguin/mkvi/releases/latest/download/'
        'latest.json',
      );
      expect(releaseFeedUrl.scheme, 'https');
      expect(releaseFeedUrl.host, 'github.com');
      expect(
        releaseFeedUrl.path,
        '/ancapenguin/mkvi/releases/latest/download/latest.json',
      );
      expect(
        isUsableFeedUrl(releaseFeedUrl),
        isTrue,
        reason: 'the preflight refuses anything else, and it is right to',
      );
    });

    test('a shipped build reads that address and no other', () {
      // `UpdateConfig.production` takes no feed address on purpose: a release
      // whose feed can be chosen at the composition root is a release that can
      // be pointed at somebody else's document.
      final UpdateConfig config = UpdateConfig.production();
      expect(config.feedUrl, releaseFeedUrl);
      expect(
        isUsableFeedUrl(config.feedUrl),
        isTrue,
        reason: 'and it has to be an address the preflight will accept',
      );
    });

    test('and it is not served from a repository of its own', () {
      // Named separately because "we moved the feed" is a one-line change that
      // is easy to make in the wrong direction: back to a private repository,
      // where the updater reads nothing again and no test would notice.
      expect(releaseFeedUrlText, isNot(contains('mkvi-updates')));
      expect(releaseFeedUrlText, isNot(contains('raw.githubusercontent')));
      expect(releaseFeedUrl.host, 'github.com');
    });
  });

  group('what the build hands over', () {
    test('production() uses the compile-time values, unmodified', () {
      final UpdateConfig config = UpdateConfig.production();
      expect(config.publicKeyB64, buildReleaseKeyB64);
      expect(config.currentVersion, buildVersion);
      // It must not invent a key or a version. An invented default is worse than
      // an empty one: it looks configured while verifying nothing.
      expect(
        config.publicKeyB64,
        isNot(contains('REPLACE')),
        reason: 'a placeholder is not a configuration',
      );
    });

    test('a test run carries no release flags, so it is not configured', () {
      // `flutter test` is not a release build, and passing the release defines
      // into the unit tests would compile the secrets of a build into every
      // test run. This assertion is what makes the cases below reachable.
      expect(
        buildReleaseKeyB64,
        isEmpty,
        reason: 'a unit test run must not be given the release key',
      );
      expect(buildVersion, isEmpty, reason: 'nor the release version');

      final UpdateConfig config = UpdateConfig.production();
      expect(config.hasReleaseKey, isFalse);
      expect(config.hasVersion, isFalse);
      expect(config.isConfigured, isFalse);
      expect(config.toString(), contains('NOT CONFIGURED'));
    });

    test('a key is present or it is not - no third state', () {
      for (final String key in <String>[
        prehashedKey,
        legacyKey,
        retiredLegacyKey,
      ]) {
        final UpdateConfig config = UpdateConfig(
          currentVersion: currentVersion,
          feedUrl: releaseFeedUrl,
          publicKeyB64: key,
        );
        expect(config.hasReleaseKey, isTrue, reason: '${key.length} chars');
        expect(config.isConfigured, isTrue, reason: '${key.length} chars');
        expect(config.toString(), isNot(contains('NOT CONFIGURED')));
      }
    });
  });

  group('an empty publicKeyB64', () {
    test('is a named build failure, not a key that failed to verify', () async {
      // The whole point of the choice: a missing value has to be distinguishable
      // from an unreadable one and from an unverified signature, because the
      // remedy is different in all three cases and only one of them is the
      // user's to take.
      for (final String empty in <String>['', '   ', '\n']) {
        final UpdateConfig config = UpdateConfig(
          currentVersion: currentVersion,
          feedUrl: releaseFeedUrl,
          publicKeyB64: empty,
        );
        final UpdatePreflight result = await runUpdatePreflight(
          config: config,
          verifier: FakeSignatureVerifier(files: FakeFileStore()),
        );
        final UpdatePreflightBlocked blocked =
            result as UpdatePreflightBlocked;
        expect(
          blocked.failure,
          isA<UpdateFailureReleaseKeyMissing>(),
          reason: 'len: ${empty.length}',
        );
        expect(blocked.canUpdate, isFalse);
        expect(blocked.failure, isNot(isA<UpdateFailureKeyUnreadable>()));
        expect(
          blocked.failure,
          isNot(isA<UpdateFailureVerificationUnavailable>()),
        );
      }
    });

    test('a build with a key but no version is a different sentence', () async {
      // Two flags, two failures. Reporting a missing version as a missing key
      // would send whoever is reading to the wrong `--dart-define`.
      final UpdateConfig config = UpdateConfig(
        currentVersion: '',
        feedUrl: releaseFeedUrl,
        publicKeyB64: prehashedKey,
      );
      final UpdatePreflight result = await runUpdatePreflight(
        config: config,
        verifier: FakeSignatureVerifier(files: FakeFileStore()),
      );
      expect(
        (result as UpdatePreflightBlocked).failure,
        isA<UpdateFailureCurrentVersionUnreadable>(),
      );
    });
  });

  group('currentVersion against pubspec.yaml', () {
    test('the version the tests run against is the one pubspec declares', () {
      // `pubspec.yaml` is the single source Flutter itself reads, and the
      // running app never sees it: the value has to be handed to the compiler
      // as `MKVI_VERSION`. This is the guard that keeps the two from drifting
      // into a release that believes it is older than it is.
      final File pubspec = File('pubspec.yaml');
      expect(
        pubspec.existsSync(),
        isTrue,
        reason: 'the update tests run from the package root, where pubspec.yaml '
            'is; running them from anywhere else is not a supported way to run '
            'them (cwd: ${Directory.current.path})',
      );
      final String? declared = _versionIn(pubspec.readAsStringSync());
      expect(declared, isNotNull, reason: 'no "version:" line in pubspec.yaml');
      expect(
        ReleaseVersion.tryParse(declared!).toString(),
        currentVersion,
        reason: 'pubspec.yaml and the version the tests compare against have '
            'drifted apart',
      );
    });

    test('the build suffix is dropped, so the raw pubspec string is usable', () {
      // `0.2.0+1` is what pubspec says. `ReleaseVersion` drops build metadata
      // before comparing, so the release build may be given either the whole
      // string or the root `VERSION` file's contents.
      expect(
        ReleaseVersion.tryParse('$currentVersion+1')?.toString(),
        currentVersion,
      );
      expect(
        ReleaseVersion.tryParse(currentVersion)?.toString(),
        currentVersion,
      );
    });
  });

  group('the retired line, gone from the source', () {
    test('lib/update names no deleted file and no dead feed', () {
      // Every pattern below is either a file that no longer exists or a host
      // that cannot serve the updater. A comment pointing at one is a comment
      // that sends the next reader to a 404.
      const Map<String, String> retired = <String, String>{
        'src-tauri': 'the retired desktop shell, deleted 2026-09-26',
        'tauri.conf': 'the retired desktop shell configuration',
        'mkvi-updates': 'the deleted private feed repository',
        'raw.githubusercontent': 'a host that will not serve a private repo',
        'publish-update.yml': 'the workflow that pushed to it',
      };
      final Directory lib = Directory('lib/update');
      expect(
        lib.existsSync(),
        isTrue,
        reason: 'expected lib/update under ${Directory.current.path}',
      );
      final List<File> sources = lib
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
      expect(sources, isNotEmpty, reason: 'no sources found in lib/update');
      for (final File file in sources) {
        final String text = file.readAsStringSync();
        for (final MapEntry<String, String> entry in retired.entries) {
          expect(
            text.contains(entry.key),
            isFalse,
            reason: '${file.path} still mentions "${entry.key}" '
                '(${entry.value})',
          );
        }
      }
    });
  });
}

/// The `version:` of a `pubspec.yaml`, or null when there is no such line.
String? _versionIn(String pubspec) {
  for (final String line in pubspec.split('\n')) {
    final String trimmed = line.trim();
    if (trimmed.startsWith('#')) continue;
    if (!trimmed.startsWith('version:')) continue;
    return trimmed.substring('version:'.length).trim();
  }
  return null;
}
