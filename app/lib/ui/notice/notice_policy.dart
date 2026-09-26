/// The timings of the notice channel, in one immutable value.
///
/// Three numbers, each with a reason:
/// * [transientLifetime] is the 5.5 s the TypeScript toast used
///   (`src/App.tsx:185`). Keeping it means the port is not also a redesign.
/// * [warningLifetime] is longer, because a warning is the one transient
///   severity a user may have to read twice; an error does not get one at all.
/// * [minimumDismissSpacing] is the fix for the other half of the immortal
///   toast: even after a notice expires, a *different* notice must not be
///   allowed to expire in its first milliseconds, or a chatty caller produces a
///   flicker instead of a rhythm.
library;

import 'package:flutter/foundation.dart' show immutable;

/// Every duration the notice channel can wait for.
///
/// The default instance is the production policy; tests pass their own so the
/// same code path can be driven at any speed without the controller growing a
/// "test mode" branch.
@immutable
class NoticePolicy {
  /// Creates a policy. Every field is in seconds and has a production default.
  const NoticePolicy({
    this.transientLifetime = const Duration(milliseconds: 5500),
    this.warningLifetime = const Duration(milliseconds: 9000),
    this.minimumDismissSpacing = const Duration(milliseconds: 1500),
  });

  /// How long a non-sticky notice may stay up. Informational and successful
  /// notices use this.
  ///
  /// 5.5 s: the `window.setTimeout(..., 5_500)` of `src/App.tsx:185`.
  final Duration transientLifetime;

  /// How long a warning may stay up. Longer than [transientLifetime].
  final Duration warningLifetime;

  /// The smallest gap between two *automatic* dismissals.
  ///
  /// A manual dismissal is never deferred — the user asked for it — and never
  /// pushes the next automatic dismissal out, so closing a toast by hand cannot
  /// leave the following one on screen for longer than its own lifetime.
  final Duration minimumDismissSpacing;

  @override
  String toString() =>
      'NoticePolicy(${transientLifetime.inMilliseconds} ms, '
      '${warningLifetime.inMilliseconds} ms, '
      'gap ${minimumDismissSpacing.inMilliseconds} ms)';
}
