/// The static Tauri `latest.json` feed, read.
///
/// A port of `parse_feed` at `crates/mkvi_core/src/update.rs:70-85`, including
/// its decision to be strict: a feed that cannot be read is an error, and a
/// version that cannot be compared is *not* an upgrade. Both matter here because
/// the document is exactly the part an attacker can rewrite.
///
/// [UpdateOffer] is declared in this file, with a private constructor, on purpose.
/// It is the only way to hold one of these, so the only way to get one into
/// [UpdateClient.install] is to have read the feed, compared versions and read a
/// signature out of it. A caller cannot assemble an offer that points at an
/// arbitrary URL and call it verified - not by convention, because there is no
/// constructor to call.
library;

import 'dart:convert';

import 'package:mkvi/core/protocol/text_sanitizer.dart';

import 'update_failure.dart';
import 'update_version.dart';

/// The one target the desktop shell ships, named the way Tauri names it.
/// `WINDOWS_TARGET` at `crates/mkvi_core/src/update.rs:15`.
const String windowsUpdateTarget = 'windows-x86_64';

/// A release the feed advertised, already compared against what is running.
///
/// Immutable, and only [parseUpdateManifest] can build one.
final class UpdateOffer {
  UpdateOffer._({
    required this.version,
    required this.notes,
    required this.url,
    required this.signature,
    required this.fileName,
  });

  /// The offered version, already parsed. [ReleaseVersion.toString] is the
  /// canonical text, without build metadata.
  final ReleaseVersion version;

  /// The release notes, or the empty string when the feed carried none.
  final String notes;

  /// Where the artefact is. **Advisory**: this URL came from a document that may
  /// be under someone else's control, which is why it is only ever the place a
  /// download *starts from* and never a reason to trust what arrives there.
  final Uri url;

  /// The release signature over the artefact, base64 of a whole `.sig` file.
  /// Checked against the key compiled into the app, not against the feed.
  final String signature;

  /// The local file name the artefact will be committed under.
  ///
  /// Derived from the URL once, here, and never from a header: a name that
  /// arrives per response is a name the server chooses twice. See
  /// [artifactFileName] for the rules.
  final String fileName;

  @override
  String toString() => 'UpdateOffer($version -> $fileName)';
}

/// What reading the feed produced.
sealed class UpdateManifest {
  const UpdateManifest();
}

/// A newer release, described well enough to download.
final class ManifestOffersRelease extends UpdateManifest {
  const ManifestOffersRelease(this.offer);

  final UpdateOffer offer;

  @override
  String toString() => 'ManifestOffersRelease($offer)';
}

/// The feed is readable and is not offering anything newer.
///
/// [offered] is the version string the feed carried, kept verbatim even when it
/// could not be parsed: "the feed says 0.1.5-something-we-cannot-read" is worth
/// being able to show, and it is emphatically not an upgrade.
final class ManifestNotNewer extends UpdateManifest {
  const ManifestNotNewer(this.offered);

  final String offered;

  @override
  String toString() => 'ManifestNotNewer(offered: $offered)';
}

/// The feed cannot be used. Mirrors the `Err` half of `parse_feed`.
final class ManifestUnusable extends UpdateManifest {
  const ManifestUnusable(this.failure);

  final UpdateFailure failure;

  @override
  String toString() => 'ManifestUnusable($failure)';
}

/// Reads the feed and decides whether it offers anything.
///
/// [current] is this build's version, already parsed by the caller: parsing it
/// here too would let a broken build string decide silently that nothing is
/// newer, which is the reading `UpdateFailureCurrentVersionUnreadable` exists to
/// stop.
///
/// The unknown members of the real feed - `pub_date` above all - are ignored
/// rather than rejected, exactly as `serde` does at
/// `crates/mkvi_core/src/update.rs:53-59`. A feed that grows a field is still a
/// feed; a feed that loses `version` is not.
UpdateManifest parseUpdateManifest(List<int> body, ReleaseVersion current) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(body));
  } on Object {
    return const ManifestUnusable(UpdateFailureFeedUnreadable());
  }
  if (decoded is! Map<Object?, Object?>) {
    return const ManifestUnusable(UpdateFailureFeedUnreadable());
  }
  final Object? versionValue = decoded['version'];
  if (versionValue is! String) {
    return const ManifestUnusable(UpdateFailureFeedUnreadable());
  }
  final Object? notesValue = decoded['notes'];
  final String notes = notesValue is String ? notesValue : '';
  final ReleaseVersion? offered = ReleaseVersion.tryParse(versionValue);
  // `is_newer` at update.rs:198: an unreadable version on either side is never
  // an upgrade. A feed offering `son surum` is not a reason to install anything.
  if (offered == null || !offered.isNewerThan(current)) {
    return ManifestNotNewer(versionValue);
  }
  final Object? platformsValue = decoded['platforms'];
  if (platformsValue is! Map<Object?, Object?>) {
    return const ManifestUnusable(UpdateFailureNoArtifactForPlatform());
  }
  final Object? entry = platformsValue[windowsUpdateTarget];
  if (entry is! Map<Object?, Object?>) {
    return const ManifestUnusable(UpdateFailureNoArtifactForPlatform());
  }
  final Object? urlValue = entry['url'];
  final Object? signatureValue = entry['signature'];
  if (urlValue is! String || signatureValue is! String) {
    return const ManifestUnusable(UpdateFailureNoArtifactForPlatform());
  }
  final Uri? url = Uri.tryParse(urlValue);
  // A URL the manifest names and the transport cannot even parse is the same
  // class of problem as one with no entry for this platform: there is nothing
  // here to download.
  if (url == null || !url.hasScheme) {
    return const ManifestUnusable(UpdateFailureNoArtifactForPlatform());
  }
  return ManifestOffersRelease(
    UpdateOffer._(
      version: offered,
      notes: notes,
      url: url,
      signature: signatureValue,
      fileName: artifactFileName(url, offered),
    ),
  );
}

/// The local name an artefact is committed under.
///
/// Three rules, and every one of them exists because the URL comes from a
/// document somebody else wrote:
///
/// * Only the last non-empty path segment is used. `https://h/a/b/setup.exe`
///   becomes `setup.exe`, not `a_b_setup.exe`.
/// * It goes through the session layer's [safeName], which is the repository's
///   single file-name sanitiser (`app/lib/core/protocol/text_sanitizer.dart:68`,
///   a port of the peer's `safeName`). Separators and control characters become
///   underscores, so no `..` in a URL can climb out of the download directory.
/// * A name made only of dots is refused, because `..` is a directory entry and
///   an installer pointed at one is a bug rather than an update.
String artifactFileName(Uri url, ReleaseVersion version) {
  String fallback() => 'update-$version.bin';
  final Iterable<String> segments = url.pathSegments.where(
    (String segment) => segment.isNotEmpty,
  );
  if (segments.isEmpty) return fallback();
  final String safe = safeName(segments.last);
  if (safe.isEmpty) return fallback();
  bool onlyDots = true;
  for (final int unit in safe.codeUnits) {
    if (unit != 0x2e) {
      onlyDots = false;
      break;
    }
  }
  return onlyDots ? fallback() : safe;
}
