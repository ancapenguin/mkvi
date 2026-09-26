// The startup check, and the one defect it exists for.
//
// The key configured in `src-tauri/tauri.conf.json:41` decodes to minisign's
// retired "Ed" algorithm rather than the prehashed "ED", so
// `mkvi_core::update::verify_artifact` (`crates/mkvi_core/src/update.rs:98`)
// refuses every signature that key can ever produce. The Tauri updater reported
// that as a possibly modified download, on every attempt, for the whole life of
// the product - and "updating has never worked" shipped with a 404 endpoint as
// well, so nobody ever got far enough to be told the truth about either.
//
// These tests pin the difference: the legacy key is a *named*, actionable
// failure, it is refused before any request goes out, and it is never
// `UpdateFailureSignatureRejected`.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/update/update_client.dart';
import 'package:mkvi/update/update_config.dart';
import 'package:mkvi/update/update_failure.dart';
import 'package:mkvi/update/update_manifest.dart';
import 'package:mkvi/update/update_messages.dart';
import 'package:mkvi/update/update_preflight.dart';
import 'package:mkvi/update/update_verifier.dart';

import 'support/fakes.dart';

void main() {
  group('the key this product actually ships', () {
    test(
      'decodes to the retired algorithm, which is why updating never worked',
      () {
        // Read the real value out of the config and check the two bytes that
        // decide everything. `Ed` is legacy; `ED` is the only accepted form.
        const String key = tauriConfiguredKey;
        const String marker = 'untrusted comment: minisign public key:';
        // The value is a base64 encoded `minisign.pub` file, so the two algorithm
        // bytes are inside the base64 payload on the second line of it.
        final String decoded = String.fromCharCodes(_base64Bytes(key));
        expect(decoded, startsWith(marker));
        final List<String> lines = decoded.split('\n');
        expect(lines.length, greaterThanOrEqualTo(2));
        final List<int> payload = _base64Bytes(lines[1].trim());
        // 0x45 0x44 is "ED"; 0x45 0x64 is "Ed". The second is the retired one.
        expect(payload[0], 0x45);
        expect(
          payload[1],
          0x64,
          reason: 'the shipped key is the legacy "Ed" form',
        );
      },
    );

    test(
      'is reported as its own failure, not as a possible modification',
      () async {
        final UpdateHarness harness = UpdateHarness(
          publicKey: tauriConfiguredKey,
        );
        addTearDown(harness.dispose);
        harness.verifier.keyState = const ReleaseKeyLegacy();

        final UpdatePreflight result = await runUpdatePreflight(
          config: harness.config,
          verifier: harness.verifier,
        );
        expect(result, isA<UpdatePreflightBlocked>());
        final UpdatePreflightBlocked blocked = result as UpdatePreflightBlocked;
        expect(blocked.failure, isA<UpdateFailureLegacyKey>());
        expect(blocked.canUpdate, isFalse);
        expect(
          blocked.failure,
          isNot(isA<UpdateFailureSignatureRejected>()),
          reason: 'there is no attacker here to accuse',
        );
      },
    );
  });

  group('the legacy key is refused before any request', () {
    test('the preflight contacts nothing at all', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.verifier.keyState = const ReleaseKeyLegacy();

      await runUpdatePreflight(
        config: harness.config,
        verifier: harness.verifier,
      );
      expect(harness.fetcher.requests, 0);
      expect(harness.files.operations, isEmpty);
      expect(harness.installer.launches, 0);
    });

    test('check() refuses without fetching the feed', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.verifier.keyState = const ReleaseKeyLegacy();
      harness.offerUpdate();

      final UpdateReport report = await harness.client.check();
      expect(harness.failureOf(report), isA<UpdateFailureLegacyKey>());
      expect(harness.fetcher.requests, 0, reason: 'the feed was never asked');
    });

    test('install() refuses without downloading the artefact', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.verifier.keyState = const ReleaseKeyLegacy();

      final UpdateReport report = await harness.client.install(offer);
      expect(harness.failureOf(report), isA<UpdateFailureLegacyKey>());
      expect(harness.fetcher.downloadUrls, isEmpty);
      expect(harness.fetcher.requests, 1, reason: 'only the earlier check');
      expect(harness.installer.launches, 0);
      expect(harness.files.operations, isEmpty);
      expect(harness.verifier.verified, isEmpty);
    });

    test('the client preflight says the same thing', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.verifier.keyState = const ReleaseKeyLegacy();

      final UpdateReport report = await harness.client.preflight();
      expect(harness.failureOf(report), isA<UpdateFailureLegacyKey>());
      expect(harness.fetcher.requests, 0);
    });
  });

  group('a prehashed key passes the preflight', () {
    test('and reports the running version', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);

      final UpdatePreflight result = await runUpdatePreflight(
        config: harness.config,
        verifier: harness.verifier,
      );
      expect(result, isA<UpdatePreflightReady>());
      final UpdatePreflightReady ready = result as UpdatePreflightReady;
      expect(ready.current.toString(), currentVersion);
      expect(ready.canUpdate, isTrue);
      expect(ready.message, isNotEmpty);
    });

    test('and the client preflight carries the same line', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateReport report = await harness.client.preflight();
      expect(report, isA<UpdatePreflightOk>());
      expect((report as UpdatePreflightOk).current.toString(), currentVersion);
      expect(report.message, UpdateMessage.keyAccepted.text);
    });
  });

  group('every other way the preflight can block', () {
    test('an unreadable key', () async {
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.verifier.keyState = const ReleaseKeyUnreadable();

      final UpdatePreflight result = await runUpdatePreflight(
        config: harness.config,
        verifier: harness.verifier,
      );
      expect(
        (result as UpdatePreflightBlocked).failure,
        isA<UpdateFailureKeyUnreadable>(),
      );
      expect(result.canUpdate, isFalse);
    });

    test('a bridge that cannot classify keys at all', () async {
      // Distinct from an unreadable key: this build cannot read keys, and the
      // fix is a different one.
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      harness.verifier.keyState = const ReleaseKeyUnavailable();

      final UpdatePreflight result = await runUpdatePreflight(
        config: harness.config,
        verifier: harness.verifier,
      );
      expect(
        (result as UpdatePreflightBlocked).failure,
        isA<UpdateFailureVerificationUnavailable>(),
      );
    });

    test('a running version that is not a version', () async {
      final UpdateHarness harness = UpdateHarness(version: 'son sürüm');
      addTearDown(harness.dispose);

      final UpdatePreflight result = await runUpdatePreflight(
        config: harness.config,
        verifier: harness.verifier,
      );
      expect(
        (result as UpdatePreflightBlocked).failure,
        isA<UpdateFailureCurrentVersionUnreadable>(),
      );
    });

    test('a feed address that is not https', () async {
      // A feed read over plaintext is a feed somebody else chose the contents of.
      for (final String url in <String>[
        'http://updates.example.invalid/latest.json',
        'file:///C:/secrets/latest.json',
        '/local/latest.json',
        '',
      ]) {
        final UpdateHarness harness = UpdateHarness(feedUrl: url);
        addTearDown(harness.dispose);
        final UpdatePreflight result = await runUpdatePreflight(
          config: harness.config,
          verifier: harness.verifier,
        );
        expect(
          result,
          isA<UpdatePreflightBlocked>(),
          reason: '"$url" must not be accepted as a feed address',
        );
        expect(
          (result as UpdatePreflightBlocked).failure,
          isA<UpdateFailureFeedUrlUnusable>(),
        );
      }
    });

    test('a missing bridge refuses every artefact', () async {
      // The only verifier in lib/ today. It must fail closed rather than let a
      // missing bridge read as a passing check.
      const UnavailableSignatureVerifier verifier =
          UnavailableSignatureVerifier();
      final UpdateConfig config = UpdateConfig(
        currentVersion: currentVersion,
        feedUrl: Uri.parse(liveFeedUrl),
        publicKeyB64: tauriConfiguredKey,
      );
      final UpdatePreflight result = await runUpdatePreflight(
        config: config,
        verifier: verifier,
      );
      expect(
        (result as UpdatePreflightBlocked).failure,
        isA<UpdateFailureVerificationUnavailable>(),
      );
      expect(
        await verifier.verifyArtifact(
          artifactPath: 'C:/downloads/x.exe',
          byteLength: 10,
          signatureB64: artifactSignature,
          publicKeyB64: prehashedKey,
        ),
        isA<ArtifactVerificationUnavailable>(),
      );
    });
  });
}

/// Base64 decoding, so the test reads the shipped key the way the Rust core does
/// without depending on `dart:convert`'s tolerance elsewhere.
List<int> _base64Bytes(String value) => base64.decode(value);
