/// What the timeline renders, one entry per thing to draw.
///
/// The conversation is a list of messages, but a list of messages is not what a
/// chat surface draws: it draws day boundaries and bubble groups too. Those are
/// *derived* from the message list on every build — there is no stored group
/// flag anywhere in this layer, so a message can never be left stranded with a
/// stale "starts a group" bit after an older page is paged in above it.
library;

import 'timeline_message.dart';

/// A row of the conversation surface. Closed set, so the UI switches over every
/// case instead of testing for a nullable message.
sealed class TimelineRow {
  const TimelineRow();
}

/// A day boundary. Emitted **once per crossing**, which is why a single-day
/// conversation has none at all — see [ChatTimeline.rows].
final class DaySeparatorRow extends TimelineRow {
  const DaySeparatorRow({required this.day});

  /// Local midnight of the day the following messages belong to.
  ///
  /// The label is not stored here. `ChatMessages.dayLabel` needs "now" to decide
  /// between "Bugün" and a date, and a value type that captured the clock would
  /// have to be rebuilt every midnight; the UI supplies the clock instead.
  final DateTime day;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DaySeparatorRow && other.day == day;

  @override
  int get hashCode => day.hashCode;

  @override
  String toString() => 'DaySeparatorRow($day)';
}

/// One message, with the bubble grouping it belongs to.
final class MessageRow extends TimelineRow {
  const MessageRow({
    required this.message,
    required this.startsGroup,
    required this.endsGroup,
  });

  final TimelineMessage message;

  /// Whether the bubble draws its own sender line and rounded top.
  ///
  /// True when this is the first row, when the previous message is from the
  /// other device, or when the previous message is on an earlier day — a
  /// conversation that crosses midnight must not run one bubble across the
  /// boundary.
  final bool startsGroup;

  /// Whether the bubble draws its own rounded bottom and timestamp.
  final bool endsGroup;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageRow &&
          other.message == message &&
          other.startsGroup == startsGroup &&
          other.endsGroup == endsGroup;

  @override
  int get hashCode => Object.hash(message, startsGroup, endsGroup);

  @override
  String toString() =>
      'MessageRow(${message.id} group: $startsGroup..$endsGroup)';
}

/// Whether two instants fall on the same local calendar day.
///
/// Local, not UTC: a Turkish user reading "Dün" at 00:30 means their yesterday.
bool isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Local midnight of the day [value] falls on.
DateTime localDayOf(DateTime value) =>
    DateTime(value.year, value.month, value.day);
