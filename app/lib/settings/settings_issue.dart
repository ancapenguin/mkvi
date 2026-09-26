/// What validation changed, and the Turkish sentence that says so.
///
/// The shape of this file is the answer to the third live defect: "a
/// persisted appearance setting that no longer validates silently fell back to
/// the default, losing the user's choice". A [SettingsReport] is produced by
/// every read of every persisted value, and it travels with the value. A
/// decode can therefore never be "just the default" - it is the default plus a
/// list of what had to be corrected, and the settings screen has something to
/// show without re-deriving anything.
library;

import 'settings_messages.dart';

/// One correction, with the reason and both sides of it.
final class SettingsIssue {
  const SettingsIssue({
    required this.problem,
    required this.key,
    this.received,
    this.applied,
    this.detail,
  });

  /// Why the stored value could not be used.
  final SettingsProblem problem;

  /// The stored key, or the field name, as it appears in the document.
  final String key;

  /// What the store held, rendered for a human. Null when the field was absent.
  final String? received;

  /// What the app used instead, rendered for a human.
  final String? applied;

  /// A short technical fragment for a measurement, e.g.
  /// `accent / bg = 1.24:1, en az 3 gerekiyor`.
  final String? detail;

  /// The Turkish sentence, ready to render.
  String get messageTr => settingsProblemTr(
    problem,
    key: key,
    received: received,
    applied: applied,
    detail: detail,
  );

  @override
  bool operator ==(Object other) =>
      other is SettingsIssue &&
      other.problem == problem &&
      other.key == key &&
      other.received == received &&
      other.applied == applied &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(problem, key, received, applied, detail);

  @override
  String toString() => 'SettingsIssue($key, ${problem.name})';
}

/// Every correction made while reading one document.
///
/// Immutable, ordered, and never empty-but-unnoticed: if [issues] is empty
/// nothing had to be corrected, and if it is not empty the caller has to decide
/// what to do about it.
final class SettingsReport {
  const SettingsReport(this.issues);

  /// Nothing had to be corrected.
  static const SettingsReport clean = SettingsReport(<SettingsIssue>[]);

  /// The corrections, in the order they were found.
  final List<SettingsIssue> issues;

  /// Whether anything had to be corrected.
  bool get hasIssues => issues.isNotEmpty;

  /// How many corrections were made.
  int get count => issues.length;

  /// Every sentence, for a screen that shows the lot.
  List<String> get messagesTr => issues
      .map((SettingsIssue issue) => issue.messageTr)
      .toList(growable: false);

  /// One line for a banner: the first sentence, and the count when there is
  /// more than one.
  String get summaryTr {
    if (issues.isEmpty) return '';
    if (issues.length == 1) return issues.first.messageTr;
    return '${issues.first.messageTr} (+${issues.length - 1} ayar daha düzeltildi)';
  }

  /// A report with [issue] appended.
  SettingsReport plus(SettingsIssue issue) =>
      SettingsReport(<SettingsIssue>[...issues, issue]);

  /// The report of two reads, [this] first.
  SettingsReport merge(SettingsReport other) =>
      SettingsReport(<SettingsIssue>[...issues, ...other.issues]);

  @override
  String toString() => 'SettingsReport(${issues.length} issue(s))';
}
