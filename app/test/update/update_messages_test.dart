// The Turkish catalogue, walked exhaustively.
//
// `UpdateMessage` is an enum precisely so this can be: `values` is every entry
// there is, which means a message added without a Turkish, non-empty text cannot
// be merged quietly. The other half is the second loop - every [UpdateFailure] and
// every report has to name an entry, so no path can invent a string next to
// itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/update/update_client.dart';
import 'package:mkvi/update/update_failure.dart';
import 'package:mkvi/update/update_manifest.dart';
import 'package:mkvi/update/update_messages.dart';
import 'package:mkvi/update/update_version.dart';

import 'support/fakes.dart';

/// This build's version, read the way the client reads it.
final ReleaseVersion current = ReleaseVersion.tryParse(currentVersion)!;

/// One real offer, parsed out of a real feed body. There is no way to write an
/// [UpdateOffer] by hand, which is itself part of what the client relies on.
final UpdateOffer offer =
    (parseUpdateManifest(feedJson(), current) as ManifestOffersRelease).offer;

/// The letters that only Turkish uses in these sentences. `i` and `a` and `e` are
/// deliberately excluded: they are in English too, and including them would let
/// an English placeholder pass.
final RegExp turkish = RegExp('[çÇğĞıİöÖşŞüÜ]');

/// Every failure the library can produce, one of each. If a case is added and not
/// listed here, the test that follows cannot be satisfied, so the list is the
/// specification of "every outcome".
const List<UpdateFailure> allFailures = <UpdateFailure>[
  UpdateFailureFeedUnreachable(),
  UpdateFailureFeedUnreadable(),
  UpdateFailureFeedTooLarge(),
  UpdateFailureFeedPinMismatch(),
  UpdateFailureNoArtifactForPlatform(),
  UpdateFailureLegacyKey(),
  UpdateFailureKeyUnreadable(),
  UpdateFailureCurrentVersionUnreadable(),
  UpdateFailureFeedUrlUnusable(),
  UpdateFailureVerificationUnavailable(),
  UpdateFailureAborted(),
  UpdateFailureDownloadFailed(),
  UpdateFailureStorageUnavailable(),
  UpdateFailureArtifactEmpty(),
  UpdateFailureArtifactTooLarge(),
  UpdateFailureArtifactSizeMismatch(),
  UpdateFailureSignatureRejected(),
  UpdateFailureSignatureUnreadable(),
  UpdateFailureInstallFailed(),
];

void main() {
  group('every catalogue entry', () {
    test('is Turkish and non-empty', () {
      for (final UpdateMessage entry in UpdateMessage.values) {
        expect(
          entry.text.trim(),
          entry.text,
          reason: '${entry.name} is padded',
        );
        expect(entry.text, isNotEmpty, reason: '${entry.name} has no text');
        expect(
          turkish.hasMatch(entry.text),
          isTrue,
          reason: '${entry.name} is not Turkish: "${entry.text}"',
        );
      }
    });

    test('is a single line a notice can carry', () {
      for (final UpdateMessage entry in UpdateMessage.values) {
        expect(
          entry.text.contains('\n'),
          isFalse,
          reason: '${entry.name} spans lines: "${entry.text}"',
        );
        // Long enough to say something, short enough to read in a dialog.
        expect(entry.text.length, lessThan(220), reason: entry.name);
      }
    });

    test('carries no English sentence', () {
      // The one message that mentions a foreign word says so deliberately: a
      // Turkish user has to be able to search for "legacy" too, because that is
      // what the build setting is called.
      for (final UpdateMessage entry in UpdateMessage.values) {
        expect(
          RegExp(
            r'\b(the|is|not|failed|error|update|file|key)\b',
          ).hasMatch(entry.text.toLowerCase()),
          isFalse,
          reason: '${entry.name} reads as English: "${entry.text}"',
        );
      }
    });

    test('is unique, so two outcomes cannot say the same thing', () {
      final Set<String> seen = <String>{};
      for (final UpdateMessage entry in UpdateMessage.values) {
        expect(
          seen.add(entry.text),
          isTrue,
          reason: '${entry.name} repeats another entry\'s text',
        );
      }
    });

    test('covers every failure exactly once, and nothing else', () {
      // The failures own the "something went wrong" half of the catalogue, one
      // entry each and no entry shared: a screen branches on the failure type, so
      // two failures with one string would hide a difference.
      final Set<UpdateMessage> used = <UpdateMessage>{};
      for (final UpdateFailure failure in allFailures) {
        expect(
          used.add(failure.messageId),
          isTrue,
          reason:
              '${failure.runtimeType} shares a message with another failure',
        );
        expect(failure.message, failure.messageId.text);
        expect(failure.message, isNotEmpty);
        expect(turkish.hasMatch(failure.message), isTrue);
      }
      // The rest of the catalogue is what a report says when nothing went wrong,
      // which is a real answer and not a silence.
      expect(
        UpdateMessage.values.toSet().difference(used),
        <UpdateMessage>{
          UpdateMessage.keyAccepted,
          UpdateMessage.alreadyUpToDate,
          UpdateMessage.checkDeferred,
          UpdateMessage.offered,
          UpdateMessage.installed,
        },
        reason:
            'a catalogue entry belongs either to a failure or to a report, '
            'and this one belongs to neither',
      );
    });

    test('names the legacy key in a sentence with a fix in it', () {
      // The defect this whole layer exists for, asserted on the text a user
      // actually reads.
      final String text = UpdateMessage.legacyKey.text;
      expect(text, contains('legacy'));
      expect(text, contains('prehashed'));
      expect(
        text,
        contains('yeniden'),
        reason: 'the sentence has to say what to do, not only what is wrong',
      );
      // And it must not accuse the user of an attack that cannot have happened.
      expect(text, isNot(contains('değiştirilmiş')));
    });
  });

  group('the reports', () {
    // Built by parsing a real manifest rather than by running the client: the
    // mapping from a report to a catalogue entry is what is under test here, and
    // driving it through a whole update would only test the client again. It also
    // shows the shape a UI has to work with: an [UpdateOffer] cannot be written
    // by hand, it has to come from a feed.
    test('every report carries a Turkish, non-empty line', () {
      final DateTime at = DateTime.utc(2026, 3, 1);
      final List<UpdateReport> reports = <UpdateReport>[
        UpdatePreflightOk(at: at, current: current),
        UpdateUpToDate(at: at, current: current, offered: currentVersion),
        UpdateCheckDeferred(at: at, retryIn: const Duration(hours: 1)),
        UpdateOffered(at: at, offer: offer),
        UpdateInstalled(at: at, offer: offer, artifactPath: 'C:/x/mkvi.exe'),
        UpdateRefused(at: at, failure: const UpdateFailureLegacyKey()),
      ];
      for (final UpdateReport report in reports) {
        expect(
          report.message,
          isNotEmpty,
          reason: report.runtimeType.toString(),
        );
        expect(
          turkish.hasMatch(report.message),
          isTrue,
          reason: '${report.runtimeType}: "${report.message}"',
        );
        expect(report.message, report.messageId.text);
      }
    });

    test('and the reports are the only way a notice is spelled', () {
      // No report builds its own text: every line comes from the catalogue, so
      // this file is the complete inventory of what a user can be shown.
      expect(
        UpdateMessage.values.map((UpdateMessage m) => m.text).toSet(),
        containsAll(<String>{
          UpdatePreflightOk(at: DateTime.utc(2026), current: current).message,
          UpdateUpToDate(
            at: DateTime.utc(2026),
            current: current,
            offered: currentVersion,
          ).message,
          UpdateCheckDeferred(
            at: DateTime.utc(2026),
            retryIn: Duration.zero,
          ).message,
          UpdateOffered(at: DateTime.utc(2026), offer: offer).message,
          UpdateInstalled(
            at: DateTime.utc(2026),
            offer: offer,
            artifactPath: 'x',
          ).message,
          UpdateRefused(
            at: DateTime.utc(2026),
            failure: const UpdateFailureSignatureRejected(),
          ).message,
        }),
      );
    });
  });
}
