/// The conversation as a value: ordered, deduplicated by id, grouped, day
/// separated and bounded.
///
/// ## Why the conversation is a value
///
/// An append-only list in mutable state cannot be trusted to stay a
/// conversation. Nothing is ever removed from it, so a long-lived thread grows
/// without bound and every rebuild re-maps the whole array. Two failure modes
/// make it worse:
///
/// * appending an incoming line to the end makes the *peer's clock* decide where
///   it lands — a device whose clock lagged put its line *after* lines it had
///   already caused;
/// * reversing the newest-first history page on load reverses the whole array
///   every time, and therefore depends on the store keeping that order forever.
///
/// ## The four properties, and how each is enforced
///
/// * **Stable id.** [add] and [prepend] are keyed on [TimelineMessage.id], so a
///   frame that arrives twice is one line and a re-read of history never
///   duplicates a line that is already on screen.
/// * **Stable order.** Lines are kept sorted by
///   [TimelineMessage.compare] — instant, then id — so a late line with an older
///   timestamp lands where its timestamp says, and the relative order of the
///   lines already on screen never changes.
/// * **Day separators.** Derived in [rows], one per crossing. Zero for a
///   single-day conversation.
/// * **Bounded.** [window] is a hard cap. Crossing it drops from the **oldest**
///   end and counts the drop in [dropped], so the surface can say "showing the
///   last N" without inventing a "load more" for messages it no longer holds.
///
/// Every accessor hands out an unmodifiable copy, and every mutation returns a
/// new [ChatTimeline]. A UI cannot reorder the conversation by accident.
library;

import 'dart:collection';

import 'timeline_message.dart';
import 'timeline_row.dart';

/// An immutable, ordered window over one conversation.
final class ChatTimeline {
  const ChatTimeline._({
    required this._messages,
    required this._ids,
    required this.window,
    required this.dropped,
    required this.exhausted,
  });

  /// An empty conversation that will hold up to [window] lines.
  factory ChatTimeline.empty({int window = defaultWindow}) {
    if (window < 1) {
      throw ArgumentError.value(window, 'window', 'must be at least 1');
    }
    return ChatTimeline._(
      messages: const <TimelineMessage>[],
      ids: const <String>{},
      window: window,
      dropped: 0,
      exhausted: false,
    );
  }

  /// Builds a conversation from lines in any order.
  ///
  /// [exhausted] is the store's answer to "is there anything older than this?".
  /// It is `true` by default because a list assembled from a full history dump
  /// has, by definition, no older page.
  factory ChatTimeline.fromMessages(
    Iterable<TimelineMessage> messages, {
    int window = defaultWindow,
    bool exhausted = true,
  }) {
    if (window < 1) {
      throw ArgumentError.value(window, 'window', 'must be at least 1');
    }
    final ChatTimeline seed = ChatTimeline.empty(window: window);
    final ChatTimeline grown = seed.addAll(messages);
    return grown._copyWith(exhausted: exhausted);
  }

  /// Lines kept in memory at once.
  ///
  /// 500 is a deliberate choice: a screen shows a dozen bubbles, and a bound is
  /// what stops a month-long conversation from turning every rebuild into a
  /// 500-element walk — while still holding roughly a hundred turns of chat.
  static const int defaultWindow = 500;

  final List<TimelineMessage> _messages;
  final Set<String> _ids;
  final int window;

  /// How many lines the bound has evicted from the oldest end so far.
  final int dropped;

  /// Whether the history is known to have no older page. `false` until a store
  /// says so, which is what makes "scroll up to load more" appear on an empty
  /// conversation and then disappear.
  final bool exhausted;

  /// The lines, oldest first. Unmodifiable.
  UnmodifiableListView<TimelineMessage> get messages =>
      UnmodifiableListView<TimelineMessage>(_messages);

  /// The lines, oldest first, in an unmodifiable list.
  List<TimelineMessage> get messageList =>
      List<TimelineMessage>.unmodifiable(_messages);

  int get length => _messages.length;

  bool get isEmpty => _messages.isEmpty;

  bool get isNotEmpty => _messages.isNotEmpty;

  bool contains(String id) => _ids.contains(id);

  TimelineMessage? messageById(String id) {
    for (final TimelineMessage message in _messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  /// The lines the surface draws, day separators included.
  ///
  /// A [DaySeparatorRow] is emitted only where the day actually **changes** —
  /// there is no unconditional leading separator. That is the difference from a
  /// naive "put `Bugün` above the first message", which shows a redundant header
  /// on every conversation that has not crossed midnight, which is nearly all of
  /// them.
  UnmodifiableListView<TimelineRow> get rows {
    final List<TimelineRow> built = <TimelineRow>[];
    for (int i = 0; i < _messages.length; i += 1) {
      final TimelineMessage current = _messages[i];
      final TimelineMessage? previous = i == 0 ? null : _messages[i - 1];
      final TimelineMessage? next = i == _messages.length - 1
          ? null
          : _messages[i + 1];
      // A separator marks a **crossing**, so the first line of the conversation
      // does not get one. "Once per boundary" is what keeps a single-day
      // conversation — nearly all of them — free of a redundant header, and what
      // makes the count of separators equal to the count of midnight boundaries
      // rather than the count of days.
      final bool crossedMidnight =
          previous != null && !isSameLocalDay(previous.sentAt, current.sentAt);
      if (crossedMidnight) {
        built.add(DaySeparatorRow(day: localDayOf(current.sentAt)));
      }
      // Written as positive questions rather than a chain of null checks, so the
      // promotion of `previous`/`next` is local and obvious.
      final bool isFirst = previous == null;
      final bool followsSameSender =
          previous != null && previous.direction == current.direction;
      final bool leadsToSameSender =
          next != null &&
          next.direction == current.direction &&
          isSameLocalDay(current.sentAt, next.sentAt);
      built.add(
        MessageRow(
          message: current,
          startsGroup: isFirst || crossedMidnight || !followsSameSender,
          endsGroup: !leadsToSameSender,
        ),
      );
    }
    return UnmodifiableListView<TimelineRow>(built);
  }

  // -----------------------------------------------------------------------
  // Mutations. Each returns a new timeline; none mutates this one.
  // -----------------------------------------------------------------------

  /// Adds one line, or replaces an existing line that carries the same id.
  ///
  /// Replacing in place is what makes the delivery transitions of the optimistic
  /// echo work: `ChatController` creates a line with
  /// [MessageDelivery.sending] and later moves the *same* line to
  /// [MessageDelivery.sent], at the position it was first inserted at.
  ///
  /// [isPinned] exempts a line from the bound. `ChatController` pins its queued
  /// lines, so a conversation longer than the window can never evict a line that
  /// has not reached the peer yet — a line that fell off the oldest end would
  /// stay in the queue and still go out, but the surface would have no way to
  /// show it or to offer a retry.
  ChatTimeline add(
    TimelineMessage message, {
    bool Function(TimelineMessage message)? isPinned,
  }) => addAll(<TimelineMessage>[message], isPinned: isPinned);

  /// Adds many lines, skipping any whose id is already held.
  ///
  /// The *held* copy wins. A line on screen is at least as fresh as a stored
  /// copy of the same line, and the stored copy is exactly the one that still
  /// says `sending` — letting it through would resurrect a sent line as pending.
  ChatTimeline addAll(
    Iterable<TimelineMessage> incoming, {
    bool Function(TimelineMessage message)? isPinned,
  }) {
    if (incoming.isEmpty) return this;
    final List<TimelineMessage> merged = List<TimelineMessage>.of(_messages);
    bool inserted = false;
    for (final TimelineMessage message in incoming) {
      if (_indexOf(merged, message.id) >= 0) continue;
      merged.insert(_insertionPoint(merged, message), message);
      inserted = true;
    }
    // A merge that changed nothing must hand back the same value, so an
    // idempotent `add` is observable as one and a UI cannot be woken for a line
    // that did not move.
    if (!inserted) return this;
    return _rebuild(
      merged,
      limit: window,
      dropped: dropped,
      exhausted: exhausted,
      isPinned: isPinned,
    );
  }

  /// Merges one older page read from the history store.
  ///
  /// The page is merged by the same sorted insert as [add], so paging in can
  /// never reorder what is already on screen and never re-adds an id that is
  /// already held — which is the failure a naive `older = [...page, ...older]`
  /// has the moment the store and the live timeline overlap by even one line.
  ///
  /// [hasMore] is the store's answer for the line *before* this page, so a
  /// conversation reaches [exhausted] exactly when the store runs out.
  ChatTimeline prepend(
    Iterable<TimelineMessage> page, {
    required bool hasMore,
    bool Function(TimelineMessage message)? isPinned,
  }) => _rebuild(
    addAll(page, isPinned: isPinned)._messages,
    limit: window,
    dropped: dropped,
    exhausted: !hasMore,
    isPinned: isPinned,
  );

  /// Replaces one line by id, keeping its position. `null` when absent.
  ChatTimeline replace(TimelineMessage message) {
    final int index = _indexOf(_messages, message.id);
    if (index < 0) return this;
    final List<TimelineMessage> next = List<TimelineMessage>.of(_messages);
    next[index] = message;
    return ChatTimeline._(
      messages: List<TimelineMessage>.unmodifiable(next),
      ids: _ids,
      window: window,
      dropped: dropped,
      exhausted: exhausted,
    );
  }

  /// Applies [change] to the line with [id]. A no-op when the line is not held.
  ChatTimeline update(
    String id,
    TimelineMessage Function(TimelineMessage message) change,
  ) {
    final TimelineMessage? current = messageById(id);
    if (current == null) return this;
    return replace(change(current));
  }

  /// Removes one line, for an explicit user discard. Does not touch [dropped] —
  /// that counter measures the bound, not deletions.
  ChatTimeline remove(String id) {
    final int index = _indexOf(_messages, id);
    if (index < 0) return this;
    final List<TimelineMessage> next = List<TimelineMessage>.of(_messages)
      ..removeAt(index);
    return _rebuild(
      next,
      limit: window,
      dropped: dropped,
      exhausted: exhausted,
    );
  }

  /// Re-binds the window, trimming from the oldest end if it shrank.
  ChatTimeline withWindow(
    int newWindow, {
    bool Function(TimelineMessage message)? isPinned,
  }) {
    if (newWindow < 1) {
      throw ArgumentError.value(newWindow, 'newWindow', 'must be at least 1');
    }
    if (newWindow == window) return this;
    return _rebuild(
      _messages,
      limit: newWindow,
      dropped: dropped,
      exhausted: exhausted,
      isPinned: isPinned,
    );
  }

  /// Marks the history as exhausted, for a store that has nothing older.
  ChatTimeline markExhausted() => _copyWith(exhausted: true);

  ChatTimeline _copyWith({List<TimelineMessage>? messages, bool? exhausted}) =>
      ChatTimeline._(
        messages: messages ?? _messages,
        ids: _ids,
        window: window,
        dropped: dropped,
        exhausted: exhausted ?? this.exhausted,
      );

  /// Rebuilds from a merged list, applying [limit] as the bound and freezing the
  /// result.
  ///
  /// [limit] is a parameter rather than this [window] because a rebind has to be
  /// able to shrink the bound: reading the old field here silently applied *no*
  /// bound at all on the one call whose whole job was to change it.
  ChatTimeline _rebuild(
    List<TimelineMessage> merged, {
    required int limit,
    required int dropped,
    required bool exhausted,
    bool Function(TimelineMessage message)? isPinned,
  }) {
    // Copied unconditionally: callers hand over their own unmodifiable list as
    // often as a mutable one, and trimming in place is the whole point of this
    // method. A shared list that is trimmed by accident is a conversation that
    // loses lines for everyone holding the previous value.
    final List<TimelineMessage> work = List<TimelineMessage>.of(merged);
    int evicted = dropped;
    // The bound drops from the oldest end, skipping anything pinned, because the
    // oldest end is the only end that can be dropped without losing a line the
    // user has not seen yet: the newest line is the one the surface is scrolled
    // to. If literally everything is pinned the bound is still honoured and the
    // oldest line goes — `ChatController` makes that unreachable by refusing a
    // queue wider than the window, and a bound that could be exceeded is not a
    // bound.
    while (work.length > limit) {
      int victim = 0;
      if (isPinned != null) {
        int candidate = 0;
        while (candidate < work.length && isPinned(work[candidate])) {
          candidate += 1;
        }
        if (candidate < work.length) victim = candidate;
      }
      work.removeAt(victim);
      evicted += 1;
    }
    return ChatTimeline._(
      messages: List<TimelineMessage>.unmodifiable(work),
      ids: Set<String>.unmodifiable(<String>{
        for (final TimelineMessage message in work) message.id,
      }),
      window: limit,
      dropped: evicted,
      exhausted: exhausted,
    );
  }

  static int _indexOf(List<TimelineMessage> list, String id) {
    for (int i = 0; i < list.length; i += 1) {
      if (list[i].id == id) return i;
    }
    return -1;
  }

  /// Binary search for [message]'s slot in an already-sorted [list].
  static int _insertionPoint(
    List<TimelineMessage> list,
    TimelineMessage message,
  ) {
    int low = 0;
    int high = list.length;
    while (low < high) {
      final int middle = (low + high) ~/ 2;
      if (TimelineMessage.compare(list[middle], message) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// Line-by-line equality, which is what comparing two conversations means.
  ///
  /// There is deliberately no `operator ==`. Two timelines that hold the same
  /// lines can differ in [dropped] and [exhausted], and an `==` that compared
  /// only the lines would say they are the same while one of them can page and
  /// the other cannot — which is the one difference a caller has to notice.
  bool hasSameMessages(ChatTimeline other) {
    if (other._messages.length != _messages.length) return false;
    for (int i = 0; i < _messages.length; i += 1) {
      if (_messages[i] != other._messages[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'ChatTimeline(${_messages.length}/$window lines, dropped: $dropped, '
      'exhausted: $exhausted)';
}
