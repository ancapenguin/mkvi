/// The semver subset the update feed is allowed to use.
///
/// A deliberate line-by-line port of `parse_version` and `is_newer` in
/// `crates/mkvi_core/src/update.rs:198-252`. The same document is read on both
/// sides of the bridge, and two implementations that disagree about precedence
/// are a place where one of them offers a "downgrade" the other calls an
/// upgrade. The whole rule set, so a future edit knows what it is allowed to
/// change:
///
/// * `major.minor.patch`, three numeric parts and nothing else. `1.0`,
///   `1.0.0.0` and `1.0.x` are *unreadable*, not guesses.
/// * An optional `-pre` suffix. A pre-release sorts BELOW its final release, and
///   below a sibling with a larger tag, compared by UTF-16 code unit - which is
///   what semver's identifier ordering reduces to for the ASCII tags a release
///   actually uses.
/// * An optional `+build` suffix, which is dropped before anything else: semver
///   gives build metadata no precedence, so `0.1.4+build.9` is not newer than
///   `0.1.4`.
/// * A leading `v` and surrounding whitespace are tolerated, because a tag
///   written `v0.1.5` is unambiguous.
/// * Anything unreadable, on either side, means "not newer". Never "newer".
library;

/// One release version, read out of a string by [tryParse].
///
/// The constructor is private so the only way to hold one is to have parsed it:
/// there is no such thing as a [ReleaseVersion] built from parts somebody
/// assembled, which is what keeps the precedence rules in one place.
final class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion._({
    required this.major,
    required this.minor,
    required this.patch,
    required this.isFinal,
    required this.preRelease,
  });

  /// Reads `major.minor.patch[-pre][+build]`, or returns null.
  ///
  /// Returning null rather than throwing is deliberate: the caller is parsing a
  /// document an attacker may control, and a feed that cannot be read must be
  /// reported, never guessed at. `crates/mkvi_core/src/update.rs:221` makes the
  /// same choice, and the client turns a null here into a refusal instead of an
  /// offer.
  static ReleaseVersion? tryParse(String value) {
    String text = value.trim();
    if (text.startsWith('v')) text = text.substring(1);
    // Build metadata first, so `1.2.3-rc.1+build` still reads as the pre-release
    // it is. `split('+').next()` in Rust; the first `+` here.
    final int plus = text.indexOf('+');
    if (plus >= 0) text = text.substring(0, plus);
    String core = text;
    String pre = '';
    final int dash = text.indexOf('-');
    if (dash >= 0) {
      core = text.substring(0, dash);
      pre = text.substring(dash + 1);
      // `1.2.3-` is a typo, not a version. Rust rejects it at
      // `update.rs:226`; so does this.
      if (pre.isEmpty) return null;
    }
    final List<String> parts = core.split('.');
    if (parts.length != 3) return null;
    final int? major = _parseNumber(parts[0]);
    final int? minor = _parseNumber(parts[1]);
    final int? patch = _parseNumber(parts[2]);
    if (major == null || minor == null || patch == null) return null;
    return ReleaseVersion._(
      major: major,
      minor: minor,
      patch: patch,
      isFinal: pre.isEmpty,
      preRelease: pre,
    );
  }

  final int major;
  final int minor;
  final int patch;

  /// Whether this is the final release rather than a pre-release of the same
  /// numbers. `false` sorts first, which is what puts `1.0.0-alpha` below
  /// `1.0.0`.
  final bool isFinal;

  /// The pre-release suffix without its `-`, or the empty string for a final
  /// release. Kept verbatim because it is part of what a user is shown.
  final String preRelease;

  /// Whether this version is strictly ahead of [other].
  ///
  /// The one comparison the client makes, and the same question
  /// `is_newer` answers in Rust: strictly greater, never "different".
  bool isNewerThan(ReleaseVersion other) => compareTo(other) > 0;

  /// Field order is [major], [minor], [patch], final-before-pre, then the
  /// pre-release tag - the order the fields are declared in the Rust struct, so
  /// the derived `Ord` there and this `compareTo` cannot drift.
  @override
  int compareTo(ReleaseVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    final int mine = isFinal ? 1 : 0;
    final int theirs = other.isFinal ? 1 : 0;
    if (mine != theirs) return mine.compareTo(theirs);
    return preRelease.compareTo(other.preRelease);
  }

  /// The canonical form, without build metadata: what a user is shown and what
  /// the file name of a downloaded artefact is built from.
  @override
  String toString() => '$major.$minor.$patch${isFinal ? '' : '-$preRelease'}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseVersion &&
          other.major == major &&
          other.minor == minor &&
          other.patch == patch &&
          other.isFinal == isFinal &&
          other.preRelease == preRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, isFinal, preRelease);
}

/// Reads a number the way `parse_number` does at
/// `crates/mkvi_core/src/update.rs:246`.
///
/// Every byte must be an ASCII digit, so the leading `+` that `int.parse` would
/// happily accept - and semver forbids - is refused here, and `int.tryParse`
/// turning a 40 digit number into an overflow is a null here rather than a
/// thrown [FormatException] out of a parser that runs on attacker input.
int? _parseNumber(String value) {
  if (value.isEmpty) return null;
  for (final int unit in value.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return null;
  }
  return int.tryParse(value);
}
