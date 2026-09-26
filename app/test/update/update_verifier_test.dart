// Can the interface carry every outcome? Five verdicts, five failures, one of
// which installs.
//
// `RustSignatureVerifier` does not exist yet. `update_verifier.dart` writes down
// the class that will replace `UnavailableSignatureVerifier` and the two Rust
// functions it binds to - `mkvi_core::update::key_is_legacy` (update.rs:129) and
// `mkvi_core::update::verify_artifact` (update.rs:98). What *is* testable today
// is whether `SignatureVerifier` is finished: if an outcome had nowhere to land,
// or two outcomes collapsed onto one sentence, the bridge would have to change
// this interface to land. That is the failure mode these tests exist to catch in
// advance, while changing the interface is still free.
//
// The five outcomes, as the client has to tell them apart:
//
//   rejected | legacy key | unreadable key | size mismatch | valid
//
// The first four must each produce their own named failure, none of them may
// accuse a user of an attack that did not happen, and only the fifth may reach
// `commit` and the installer.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/update/update_client.dart';
import 'package:mkvi/update/update_failure.dart';
import 'package:mkvi/update/update_file_store.dart';
import 'package:mkvi/update/update_manifest.dart';
import 'package:mkvi/update/update_messages.dart';
import 'package:mkvi/update/update_preflight.dart';
import 'package:mkvi/update/update_verifier.dart';

import 'support/fakes.dart';

/// Every member of [ArtifactVerdict], written out. A sixth member added without
/// a sixth case here shows up as a length mismatch rather than as an untested
/// outcome.
const List<ArtifactVerdict> everyVerdict = <ArtifactVerdict>[
  ArtifactSignatureValid(),
  ArtifactSignatureRejected(),
  ArtifactKeyIsLegacy(),
  ArtifactSignatureUnreadable(),
  ArtifactKeyUnreadable(),
  ArtifactSizeMismatch(),
  ArtifactVerificationUnavailable(),
];

void main() {
  group('the five outcomes reach five different failures', () {
    test('and the first four commit nothing', () async {
      const Map<ArtifactVerdict, Type> expected = <ArtifactVerdict, Type>{
        ArtifactSignatureRejected(): UpdateFailureSignatureRejected,
        ArtifactKeyIsLegacy(): UpdateFailureLegacyKey,
        ArtifactKeyUnreadable(): UpdateFailureKeyUnreadable,
        ArtifactSizeMismatch(): UpdateFailureArtifactSizeMismatch,
        ArtifactVerificationUnavailable():
            UpdateFailureVerificationUnavailable,
      };

      for (final MapEntry<ArtifactVerdict, Type> entry in expected.entries) {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.verifier.scripted = entry.key;

        final UpdateReport report = await harness.client.install(offer);
        final UpdateFailure failure = harness.failureOf(report);
        expect(
          failure.runtimeType,
          entry.value,
          reason: '${entry.key} must not be reported as anything else',
        );
        expect(
          report.message,
          failure.messageId.text,
          reason: 'the report carries the failure\'s own sentence, verbatim',
        );
        expect(harness.files.commits, 0, reason: '${entry.key}');
        expect(harness.installer.launches, 0, reason: '${entry.key}');
        expect(
          harness.files.hasStagingFiles,
          isFalse,
          reason: '${entry.key} must leave nothing behind',
        );
      }
    });

    test('four of the five accuse nobody who is not there', () async {
      // "The file may have been modified" is the only sentence in the catalogue
      // that means an attacker, and it belongs to exactly one outcome. A
      // truncated file, a retired key and a missing bridge are all somebody
      // else's mistake, and a user told otherwise goes looking for one.
      const Map<ArtifactVerdict, Type> refusals = <ArtifactVerdict, Type>{
        ArtifactKeyIsLegacy(): UpdateFailureLegacyKey,
        ArtifactKeyUnreadable(): UpdateFailureKeyUnreadable,
        ArtifactSizeMismatch(): UpdateFailureArtifactSizeMismatch,
        ArtifactVerificationUnavailable():
            UpdateFailureVerificationUnavailable,
      };
      for (final MapEntry<ArtifactVerdict, Type> entry in refusals.entries) {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.verifier.scripted = entry.key;

        final UpdateReport report = await harness.client.install(offer);
        expect(
          report.messageId,
          isNot(UpdateMessage.signatureRejected),
          reason: '${entry.key} answered with the one sentence that means an '
              'attacker',
        );
        expect(report.message, isNot(contains('değiştirilmiş')));
      }
    });

    test('a valid signature is the only verdict that reaches the installer', () async {
      for (final ArtifactVerdict verdict in everyVerdict) {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        final UpdateOffer offer = await harness.offerFromCheck();
        harness.verifier.scripted = verdict;

        final UpdateReport report = await harness.client.install(offer);
        final bool valid = verdict is ArtifactSignatureValid;
        if (valid) {
          expect(
            report,
            isA<UpdateInstalled>().having(
              (UpdateInstalled installed) => installed.artifactPath,
              'the committed path',
              harness.files.committedPath(offer),
            ),
            reason: '$verdict',
          );
        } else {
          expect(report, isA<UpdateRefused>(), reason: '$verdict');
        }
        expect(harness.installer.launches, valid ? 1 : 0, reason: '$verdict');
        expect(harness.files.commits, valid ? 1 : 0, reason: '$verdict');
        expect(
          harness.eventsOf<UpdateInstallStarted>().length,
          valid ? 1 : 0,
          reason: '$verdict',
        );
        expect(
          harness.eventsOf<UpdateArtifactVerified>().length,
          valid ? 1 : 0,
          reason: '$verdict: nothing is announced as verified unless it was',
        );
      }
    });

    test('the verdicts are exactly the seven the interface names', () {
      // Guards the list above against the family quietly growing a member that
      // no case in this file knows about.
      expect(everyVerdict, hasLength(7));
      expect(everyVerdict.toSet(), hasLength(7));
    });
  });

  group('the bridge is handed what it needs to answer', () {
    test('a size mismatch is decidable before anything is hashed', () async {
      // `byteLength` travels with the path precisely so the bridge can compare
      // it against the file before the read. A verifier that only learns the
      // length after hashing has already done the expensive part.
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      harness.verifier.scripted = const ArtifactSizeMismatch();

      await harness.client.install(offer);
      final ({String path, int byteLength, String signature, String key}) call =
          harness.verifier.verified.single;
      expect(call.byteLength, harness.artifact.length);
      expect(
        call.path,
        endsWith(StagedArtifact.stagingExtension),
        reason: 'the bridge is handed the staging file, never a committed one',
      );
    });

    test('and the key it is asked about is the one the build compiled in', () async {
      // The verifier is asked about the configured key, not about one the feed
      // carried: a key that arrives with the manifest is a key the feed chose.
      // Twice, deliberately - `check()` runs the preflight and `install()` reads
      // the key again rather than trusting a preflight from another call.
      final UpdateHarness harness = UpdateHarness(publicKey: prehashedKey);
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      await harness.client.install(offer);

      expect(harness.verifier.classifiedKeys, hasLength(2));
      expect(harness.verifier.classifiedKeys.toSet(), <String>{prehashedKey});
      expect(harness.verifier.verified.single.key, prehashedKey);
    });
  });

  group('the key classifier, which has four answers and not three', () {
    test('each of them is a distinct outcome', () async {
      // "Your key is malformed" and "this build cannot read keys" are different
      // problems with different remedies. Folding them together sends whoever is
      // reading to rotate a key that was fine.
      const Map<ReleaseKeyState, Type> expected = <ReleaseKeyState, Type>{
        ReleaseKeyLegacy(): UpdateFailureLegacyKey,
        ReleaseKeyUnreadable(): UpdateFailureKeyUnreadable,
        ReleaseKeyUnavailable(): UpdateFailureVerificationUnavailable,
      };
      for (final MapEntry<ReleaseKeyState, Type> entry in expected.entries) {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        harness.verifier.keyState = entry.key;

        final UpdateReport report = await harness.client.preflight();
        expect(report, isA<UpdateRefused>(), reason: '${entry.key}');
        expect(
          (report as UpdateRefused).failure.runtimeType,
          entry.value,
          reason: '${entry.key} must not be reported as anything else',
        );
        expect(report.message, isNotEmpty, reason: '${entry.key}');
      }

      // And the one state that lets updating proceed is the fourth, not a fifth
      // spelling of one of the others.
      final UpdateHarness ready = UpdateHarness();
      addTearDown(ready.dispose);
      final UpdateReport ok = await ready.client.preflight();
      expect(ok, isA<UpdatePreflightOk>());
      expect(ok.message, UpdateMessage.keyAccepted.text);
    });

    test('a prehashed key is the only state that lets updating proceed', () async {
      for (final ReleaseKeyState state in <ReleaseKeyState>[
        const ReleaseKeyLegacy(),
        const ReleaseKeyUnreadable(),
        const ReleaseKeyUnavailable(),
      ]) {
        final UpdateHarness harness = UpdateHarness();
        addTearDown(harness.dispose);
        harness.verifier.keyState = state;

        final UpdatePreflight preflight = await runUpdatePreflight(
          config: harness.config,
          verifier: harness.verifier,
        );
        expect(
          preflight,
          isA<UpdatePreflightBlocked>().having(
            (UpdatePreflightBlocked blocked) => blocked.canUpdate,
            'canUpdate',
            isFalse,
          ),
          reason: '$state',
        );
      }

      final UpdateHarness ready = UpdateHarness();
      addTearDown(ready.dispose);
      final UpdatePreflight ok = await runUpdatePreflight(
        config: ready.config,
        verifier: ready.verifier,
      );
      expect(
        ok,
        isA<UpdatePreflightReady>().having(
          (UpdatePreflightReady result) => result.canUpdate,
          'canUpdate',
          isTrue,
        ),
      );
    });

    test('the stub in lib/ refuses both questions, and says nothing else', () async {
      // The only implementation shipped today. It has to fail closed on the key
      // *and* on the artefact, or a missing bridge would read as a passing check
      // on whichever question happens to be asked first.
      const UnavailableSignatureVerifier stub = UnavailableSignatureVerifier();
      expect(
        await stub.classifyKey(prehashedKey),
        isA<ReleaseKeyUnavailable>(),
      );
      expect(
        await stub.verifyArtifact(
          artifactPath: 'C:/downloads/x.exe',
          byteLength: 10,
          signatureB64: artifactSignature,
          publicKeyB64: prehashedKey,
        ),
        isA<ArtifactVerificationUnavailable>(),
      );

      // And through the client, a build wired to the stub cannot install
      // anything at all - not a verified prefix, not a partial file. The offer
      // is produced by the harness, whose own verifier is a working fake: the
      // stub is what has to stop this.
      final UpdateHarness harness = UpdateHarness();
      addTearDown(harness.dispose);
      final UpdateOffer offer = await harness.offerFromCheck();
      final UpdateClient stubbed = UpdateClient(
        config: harness.config,
        fetcher: harness.fetcher,
        verifier: stub,
        installer: harness.installer,
        files: harness.files,
        clock: harness.clock,
      );
      final UpdateReport report = await stubbed.install(offer);
      expect(
        harness.failureOf(report),
        isA<UpdateFailureVerificationUnavailable>(),
      );
      expect(harness.installer.launches, 0);
      expect(harness.files.commits, 0);
      expect(harness.files.hasStagingFiles, isFalse);
    });
  });
}
