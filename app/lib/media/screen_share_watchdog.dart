import 'dart:async';

import 'media_fault.dart';
import 'media_seam.dart';
import 'media_state.dart';

/// Watches a display track for its first encoded frame and tells the user when
/// none ever arrives.
///
/// ## Why this file exists at all
///
/// Screen share that silently never produces a frame is indistinguishable, from
/// the user's side, from screen share that works. Nothing in the plugin will tell
/// us about it: **upstream issue #2137** — `getDisplayMedia` resolves
/// *successfully* with a track that never produces a frame when the shared
/// window is not foreground. The root cause is in the plugin's own source — the
/// desktop capturer's `Start()` return value is discarded and success is reported
/// regardless:
///
/// ```cpp
/// desktop_capturer->Start(uint32_t(fps));
///
/// result->Success(EncodableValue(params));
/// ```
/// (`flutter_webrtc/common/cpp/src/flutter_screen_capture.cc:373-375`).
///
/// No future completes late, no callback fires, no exception is thrown, and
/// `MediaStreamTrack` has no `readyState` for the plugin to move. In a browser,
/// `track.muted` going true is the signal. Here the only observable that ever
/// moves is `outbound-rtp.framesEncoded` in the RTP stats.
///
/// MKVI starts screen share **mid-call** through `replaceTrack`, which is exactly
/// the path where a black rectangle would otherwise sit on the call screen
/// forever with no state and no error. So: the phase becomes
/// [ScreenSharePhase.waitingForFirstFrame] the instant the track is attached, and
/// if no frame has been encoded by the timeout the phase becomes
/// [ScreenSharePhase.stalled], whose Turkish label names the remedy.
///
/// ## Why the schedule is counted, not timed
///
/// The budget is a number of polls rather than a wall clock, so the whole schedule
/// is a pure function of the injected [MediaStatsProbe] and [MediaDelay] and
/// `test/media` drives it without a clock. The cost is that a slow stats call
/// stretches the wall-clock timeout; the bound that matters — "we give up and tell
/// the user" — is still the last poll, and a stats call that never returns is the
/// platform's problem, not a reason to hang the call.
final class ScreenShareWatchdog {
  ScreenShareWatchdog({
    required MediaSeams seams,
    this.pollInterval = const Duration(milliseconds: 500),
    this.firstFrameTimeout = const Duration(seconds: 4),
  }) : _media = seams;

  final MediaSeams _media;

  /// How often `framesEncoded` is read.
  final Duration pollInterval;

  /// How long a share may go without a frame before the user is told.
  final Duration firstFrameTimeout;

  final StreamController<ScreenSharePhase> _phases =
      StreamController<ScreenSharePhase>.broadcast(sync: true);

  /// Incremented by every [arm] and [disarm]. A poll loop that is mid-`await`
  /// when a share is stopped or restarted notices the change and returns without
  /// publishing, which is what keeps a stale `stalled` from landing on a share
  /// that has already ended.
  int _generation = 0;

  ScreenSharePhase _phase = ScreenSharePhase.idle;
  bool _disposed = false;

  /// How many reads of `framesEncoded` a share gets before it is given up on.
  ///
  /// One more than the ratio, because the first read happens immediately: a track
  /// that was already encoding when it was attached must be reported live without
  /// waiting out a poll interval.
  int get pollBudget {
    if (pollInterval.inMicroseconds <= 0) return 1;
    return (firstFrameTimeout.inMicroseconds / pollInterval.inMicroseconds)
            .round() +
        1;
  }

  /// The phase as last published.
  ScreenSharePhase get phase => _phase;

  /// The phase, from [ScreenSharePhase.starting] onward.
  ///
  /// Synchronous: an `async` getter would be a lie, because the phase is set before
  /// the first `await` and a caller that awaited it could still observe the
  /// previous phase.
  Stream<ScreenSharePhase> get phases => _phases.stream;

  /// Starts watching [senderId].
  ///
  /// Publishes [ScreenSharePhase.waitingForFirstFrame] synchronously, before any
  /// stat is read: a share that will never produce a frame has to *look* like a
  /// share that is still starting, or the UI is back to showing an unexplained
  /// black rectangle.
  void arm(String senderId) {
    if (_disposed) return;
    _generation += 1;
    final int generation = _generation;
    _publish(ScreenSharePhase.starting);
    _publish(ScreenSharePhase.waitingForFirstFrame);
    unawaited(_watch(senderId, generation));
  }

  /// Stops watching and returns to [ScreenSharePhase.idle].
  ///
  /// Idempotent, and safe to call while a poll is in flight.
  void disarm() {
    _generation += 1;
    if (_disposed || _phase == ScreenSharePhase.idle) return;
    _publish(ScreenSharePhase.idle);
  }

  /// Records that capture never started, so a stopped share is distinguishable
  /// from one that was never asked for.
  void fail() {
    if (_disposed) return;
    _generation += 1;
    _publish(ScreenSharePhase.failed);
  }

  Future<void> _watch(String senderId, int generation) async {
    for (int poll = 0; poll < pollBudget; poll += 1) {
      if (poll > 0) {
        await _media.delay(pollInterval);
        if (generation != _generation || _disposed) return;
      }
      int frames = 0;
      try {
        frames = await _media.stats.framesEncoded(senderId);
      } catch (error) {
        // A stats read that fails is not evidence of a frame. Report it and keep
        // waiting: the loop below is still the bound, and a share that is quietly
        // working must not be failed because one poll hiccuped.
        _media.diagnostics?.call(
          const MediaFault(
            MediaFaultKind.deviceNotReadable,
            MediaSourceKind.screen,
          ),
          error,
        );
      }
      if (generation != _generation || _disposed) return;
      if (frames > 0) {
        _publish(ScreenSharePhase.live);
        return;
      }
    }
    if (generation != _generation || _disposed) return;
    _publish(ScreenSharePhase.stalled);
  }

  void _publish(ScreenSharePhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    if (_phases.hasListener) _phases.add(phase);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    await _phases.close();
  }
}
