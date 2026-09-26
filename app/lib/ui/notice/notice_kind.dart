/// The four severities a notice can carry.
///
/// TS had none. One `notice` string served "Bağlantı ayarları kaydedildi." and
/// "Cihaz kimliği doğrulanamadı; bağlantı kapatıldı." with the same chrome, so
/// nothing on screen said which of the two the user was looking at.
///
/// Severity buys exactly two things here: a colour the palette resolves from a
/// design-token role, and a lifetime. **How long a severity may stay is
/// [lifetime] and nowhere else** — one exhaustive switch, so a new kind cannot
/// be added without deciding whether it sticks, and "an error stays until
/// dismissed, an info does not" cannot be true in one call site and false in
/// another.
library;

import 'notice_policy.dart';
import 'notice_strings.dart';

/// How serious a notice is, and therefore what it looks like and how long it
/// may stay.
enum NoticeKind {
  /// Something happened that the user did not have to act on. Auto-dismisses.
  info,

  /// Something the user asked for worked. Auto-dismisses.
  success,

  /// Something the user probably wants to know about and may want to read
  /// twice. Auto-dismisses, but for longer than [info].
  warning,

  /// Something failed and only the user can fix it. Stays until dismissed.
  error;

  /// How long a notice of this severity may stay up, or `null` when it must
  /// not expire at all.
  ///
  /// The severity rule, in one place:
  /// * [error] returns `null`. A failure nobody can see is a failure nobody
  ///   fixes, so the only thing that may remove it is the user.
  /// * [warning] returns [NoticePolicy.warningLifetime].
  /// * [info] and [success] return [NoticePolicy.transientLifetime].
  Duration? lifetime(NoticePolicy policy) => switch (this) {
    NoticeKind.info || NoticeKind.success => policy.transientLifetime,
    NoticeKind.warning => policy.warningLifetime,
    NoticeKind.error => null,
  };

  /// Whether a notice of this severity is dismissed by the clock or by the
  /// user. [NoticeController] arms no timer when this is false.
  bool isSticky(NoticePolicy policy) => lifetime(policy) == null;

  /// The Turkish name of this severity, as announced for the severity mark.
  ///
  /// The mark is an icon, so without a name it says nothing to a screen reader.
  String get labelTr => switch (this) {
    NoticeKind.info => NoticeTr.severityInfo.tr,
    NoticeKind.success => NoticeTr.severitySuccess.tr,
    NoticeKind.warning => NoticeTr.severityWarning.tr,
    NoticeKind.error => NoticeTr.severityError.tr,
  };
}
