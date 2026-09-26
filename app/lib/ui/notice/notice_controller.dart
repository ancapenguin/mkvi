/// The notice channel and the status channel, which are not the same channel.
///
/// The reported bug, in one sentence: **one `String` was written from six
/// places, including from inside the reconnect loop about once a second, and
/// the 5.5 s auto-dismiss was re-armed by every write.** The timer therefore
/// never expired, and closing the toast by hand looked like a dead button
/// because the next loop iteration refilled it within a second.
///
/// Four rules make that unrepresentable rather than merely unlikely:
///
/// 1. **Two channels.** `show*` writes the notice channel; `setStatus` writes
///    the status channel. `setStatus` has no path to `NoticeSnapshot.notice` —
///    there is no branch to get wrong.
/// 2. **Dedup.** A write whose text is already on screen is a no-op. The
///    deadline is computed once, when the notice is accepted, and never
///    recomputed. Six writes a second apart produce one notice with one
///    deadline, and it goes away when that deadline passes.
/// 3. **A close is a close.** [dismiss] remembers the text, and a repeat of
///    that exact text is refused until some *other* text arrives. The button
///    does not have to win a race it cannot see.
/// 4. **A rate limit.** Two automatic dismissals are never closer together than
///    `NoticePolicy.minimumDismissSpacing`. A chatty caller gets a rhythm, not
///    a flicker, and a manual dismissal is never deferred.
///
/// The clock is injected (`NoticeClock`) and is the only source of time, so
/// every one of those rules is a unit test rather than a 5.5 s wait.
library;

import 'package:flutter/foundation.dart';

import 'notice_clock.dart';
import 'notice_kind.dart';
import 'notice_policy.dart';
import 'notice_state.dart';
import 'notice_status.dart';
import 'notice_strings.dart';

/// Holds the two channels and enforces the four rules in the library docs.
///
/// A [ChangeNotifier] so `NoticeHost` can rebuild from it, and nothing else: no
/// widget, no `BuildContext`, no opinion about layout, and no way for a status
/// change to become a toast.
class NoticeController extends ChangeNotifier {
  /// Creates a controller. [clock] is required — a controller with a default
  /// timer would be the old bug waiting for a new call site.
  NoticeController({required this.clock, this.policy = const NoticePolicy()});

  /// The only source of time and of timers in this layer.
  ///
  /// Public because a test and a debug overlay both need to ask what time the
  /// controller believes it is, and because a caller that wrapped its own clock
  /// should be able to see that the controller is using it.
  final NoticeClock clock;

  /// The timings this controller applies. See `NoticePolicy`.
  final NoticePolicy policy;

  NoticeSnapshot _snapshot = NoticeSnapshot.empty;
  NoticeTimerCancel? _cancelAutoDismiss;
  String? _dismissedText;
  int _sequence = 0;

  /// Both channels as one immutable value.
  NoticeSnapshot get snapshot => _snapshot;

  /// The notice on screen, or `null`. The transient channel.
  Notice? get notice => _snapshot.notice;

  /// The connection state. The persistent channel; never a toast.
  ConnectionStatus get status => _snapshot.status;

  /// Whether a notice is on screen right now.
  bool get hasNotice => _snapshot.notice != null;

  // ----------------------------------------------------------------- notices

  /// Shows a string from the Turkish catalogue.
  ///
  /// The kind defaults to [NoticeKind.info], so a catalogue entry is one call
  /// and cannot accidentally become sticky.
  void show(NoticeTr entry, {NoticeKind kind = NoticeKind.info}) =>
      showText(entry.tr, kind: kind);

  /// Shows [text] under the four rules in the library docs.
  ///
  /// Returns `true` when a new notice was accepted. `false` means one of:
  /// * [text] is already on screen — the deadline is **not** extended, which is
  ///   the reported bug;
  /// * [text] is the text the user closed by hand and no other text has
  ///   arrived since, so the close button keeps working;
  /// * [text] is empty, which is treated as [dismiss] so that a ported
  ///   `setNotice("")` cannot resurrect a closed toast.
  bool showText(String text, {NoticeKind kind = NoticeKind.info}) {
    if (text.isEmpty) {
      dismiss();
      return false;
    }

    final Notice? current = _snapshot.notice;

    // Rule 2. Returning here is what keeps `expiresAt` where the first write put
    // it, no matter how many identical writes arrive behind it.
    if (current != null && current.text == text) return false;

    // Rule 3. The user closed this sentence; the caller has nothing new to say
    // until it has something new to say.
    if (text == _dismissedText) return false;

    _cancelAutoDismiss?.call();
    _cancelAutoDismiss = null;
    _dismissedText = null;

    final DateTime now = clock.now();
    final Duration? lifetime = kind.lifetime(policy);
    _sequence += 1;
    final Notice notice = Notice(
      text: text,
      kind: kind,
      shownAt: now,
      expiresAt: lifetime == null ? null : now.add(lifetime),
      sequence: _sequence,
    );

    _snapshot = NoticeSnapshot(
      notice: notice,
      status: _snapshot.status,
      lastAutomaticDismissal: _snapshot.lastAutomaticDismissal,
      dismissedText: null,
    );
    notifyListeners();

    if (!notice.isSticky) {
      _cancelAutoDismiss = clock.schedule(lifetime!, _onAutoDismissDue);
    }
    return true;
  }

  /// Removes the notice because the user asked for it to go.
  ///
  /// Never deferred by the rate limit: the user outranks the policy. It also
  /// never pushes the *next* automatic dismissal out, so a hand-closed toast
  /// cannot leave its successor on screen for longer than its own lifetime.
  ///
  /// The text is remembered until another text arrives, which is what makes the
  /// close button more than decoration.
  void dismiss() {
    final Notice? current = _snapshot.notice;
    if (current == null) return;

    _cancelAutoDismiss?.call();
    _cancelAutoDismiss = null;
    _dismissedText = current.text;
    _snapshot = NoticeSnapshot(
      notice: null,
      status: _snapshot.status,
      lastAutomaticDismissal: _snapshot.lastAutomaticDismissal,
      dismissedText: current.text,
    );
    notifyListeners();
  }

  /// How long until the clock removes the notice on its own, or `null` when
  /// nothing is armed.
  ///
  /// A test can watch this across a burst of identical writes: it must fall and
  /// never jump back to the full lifetime.
  Duration? get pendingAutoDismiss {
    final DateTime? due = _snapshot.notice?.expiresAt;
    if (due == null) return null;
    final Duration remaining = due.difference(clock.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Runs when the clock says the deadline is due. Rule 4 lives here.
  ///
  /// Private on purpose: a notice leaves the channel through [dismiss] or
  /// through this, and through nothing else.
  void _onAutoDismissDue() {
    final Notice? current = _snapshot.notice;
    if (current == null) return;

    final DateTime now = clock.now();
    if (!current.isDueAt(now)) {
      // The clock is the authority on time: a callback that arrives early
      // re-arms for the real remainder rather than dismissing a live notice.
      _cancelAutoDismiss = clock.schedule(
        current.expiresAt!.difference(now),
        _onAutoDismissDue,
      );
      return;
    }

    final DateTime? last = _snapshot.lastAutomaticDismissal;
    if (last != null) {
      final DateTime earliest = last.add(policy.minimumDismissSpacing);
      if (now.isBefore(earliest)) {
        // Rule 4. Too soon after the previous automatic dismissal: wait out the
        // spacing instead of flickering a second toast away.
        _cancelAutoDismiss = clock.schedule(
          earliest.difference(now),
          _onAutoDismissDue,
        );
        return;
      }
    }

    _cancelAutoDismiss = null;
    _snapshot = NoticeSnapshot(
      notice: null,
      status: _snapshot.status,
      lastAutomaticDismissal: now,
      dismissedText: _dismissedText,
    );
    notifyListeners();
  }

  // ------------------------------------------------------------------ status

  /// Sets the connection state. **Never** produces a toast.
  ///
  /// This is the fix for defect 4: "reconnecting" is a condition of the app, so
  /// it lives in a state the UI reads as a status strip, with no lifetime, no
  /// close button and no place in the notice queue. Notice the assignment: the
  /// notice channel is copied through untouched, and there is no path from here
  /// to a new `Notice`.
  void setStatus(ConnectionStatus status) {
    if (_snapshot.status == status) return;
    _snapshot = NoticeSnapshot(
      notice: _snapshot.notice,
      status: status,
      lastAutomaticDismissal: _snapshot.lastAutomaticDismissal,
      dismissedText: _snapshot.dismissedText,
    );
    notifyListeners();
  }

  @override
  String toString() => 'NoticeController($policy, $_snapshot)';

  @override
  void dispose() {
    _cancelAutoDismiss?.call();
    _cancelAutoDismiss = null;
    _dismissedText = null;
    super.dispose();
  }
}
