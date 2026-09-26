/// The immutable state of the two channels.
///
/// Nothing under `lib/ui/notice` mutates a notice. The controller builds a new
/// [Notice] and a new [NoticeSnapshot] per change, which is what lets a test
/// assert the *transition* — "the deadline did not move", "the sequence is still
/// 1" — instead of reading a widget and hoping.
library;

import 'package:flutter/foundation.dart' show immutable;

import 'notice_kind.dart';
import 'notice_status.dart';

/// One thing the user is being told.
///
/// A notice is a value: it carries the deadline the controller computed, so the
/// widget layer never schedules anything and never reads a clock.
@immutable
class Notice {
  /// Creates a notice. Only [NoticeController] should do this; the sequence and
  /// the deadline are bookkeeping the caller cannot get right by hand.
  const Notice({
    required this.text,
    required this.kind,
    required this.shownAt,
    required this.expiresAt,
    required this.sequence,
  });

  /// The Turkish sentence to show, exactly as the caller wrote it.
  ///
  /// Capped and made scrollable by `NoticeSurface`; never edited here, so what
  /// the controller deduplicates on is what the user is shown.
  final String text;

  /// How serious this is, and therefore how long it may stay.
  final NoticeKind kind;

  /// When the notice was accepted, from the injected clock.
  final DateTime shownAt;

  /// When the clock may remove it, or `null` when only the user may.
  final DateTime? expiresAt;

  /// 1-based, incremented for every accepted notice and never reused.
  ///
  /// This is the dedup receipt: after a chatty caller has written the same text
  /// six times, the sequence is still 1, which is the assertion that the
  /// reported bug is gone.
  final int sequence;

  /// Whether only the user may remove this notice.
  bool get isSticky => expiresAt == null;

  /// How long the notice was given, or `null` when it is sticky.
  Duration? get lifetime => expiresAt?.difference(shownAt);

  /// Whether the deadline has passed as of [now].
  ///
  /// The controller checks this when a timer fires, so the clock — not the
  /// timer's own bookkeeping — is the single authority on what time it is.
  bool isDueAt(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  @override
  bool operator ==(Object other) =>
      other is Notice &&
      other.text == text &&
      other.kind == kind &&
      other.shownAt == shownAt &&
      other.expiresAt == expiresAt &&
      other.sequence == sequence;

  @override
  int get hashCode => Object.hash(text, kind, shownAt, expiresAt, sequence);

  @override
  String toString() =>
      'Notice(#$sequence, $kind, "${text.length} chars", '
      '${isSticky ? 'sticky' : 'until ${expiresAt?.toIso8601String()}'})';
}

/// Both channels at once, and the bookkeeping that explains them.
///
/// [notice] and [status] are deliberately in one object but not one field: the
/// UI reads them for different reasons and a status change must never be able to
/// produce a notice.
@immutable
class NoticeSnapshot {
  /// Creates a snapshot. The controller owns every one of these fields.
  const NoticeSnapshot({
    required this.notice,
    required this.status,
    required this.lastAutomaticDismissal,
    required this.dismissedText,
  });

  /// Nothing is on screen.
  static const NoticeSnapshot empty = NoticeSnapshot(
    notice: null,
    status: ConnectionStatus.idle,
    lastAutomaticDismissal: null,
    dismissedText: null,
  );

  /// The one notice currently on screen, or `null`.
  final Notice? notice;

  /// The connection state. Never a toast, never expired, never closed by hand.
  final ConnectionStatus status;

  /// When the clock last removed a notice on its own, or `null` if never.
  ///
  /// This is the rate-limit receipt: an automatic dismissal that would land
  /// within `NoticePolicy.minimumDismissSpacing` of it is deferred instead.
  final DateTime? lastAutomaticDismissal;

  /// The text the user closed by hand, while that text is still the newest one
  /// seen. A repeat of it is refused until some other text arrives.
  ///
  /// Without this the close button was decoration: `onClose={() => setNotice("")}`
  /// (`src/App.tsx:542`) and the reconnect loop refilled the field about a second
  /// later.
  final String? dismissedText;

  @override
  bool operator ==(Object other) =>
      other is NoticeSnapshot &&
      other.notice == notice &&
      other.status == status &&
      other.lastAutomaticDismissal == lastAutomaticDismissal &&
      other.dismissedText == dismissedText;

  @override
  int get hashCode =>
      Object.hash(notice, status, lastAutomaticDismissal, dismissedText);

  @override
  String toString() =>
      'NoticeSnapshot(${notice ?? '-'}, $status, dismissed: $dismissedText)';
}
