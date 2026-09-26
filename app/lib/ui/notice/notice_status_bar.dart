/// The status channel, rendered as a strip that does not expire.
///
/// This is the visible half of the fix for the fourth defect. Connection state
/// and one-off events shared one `String` in TS, so "reconnecting" arrived as a
/// toast, was re-armed once a second by the loop that produced it, and covered
/// the composer. Here the state is a [ConnectionStatus] that
/// `NoticeController.setStatus` writes, and the only thing this widget can do is
/// show it. It has no timer, no close button, and no path to the notice lane, so
/// the worst it can do is sit in a header saying what the app is doing.
///
/// Place it wherever the window's status belongs — an app bar, a footer — as an
/// in-flow child. It is deliberately not a toast: it is not dismissible and it is
/// not queued.
library;

import 'package:flutter/material.dart';

import 'notice_controller.dart';
import 'notice_design.dart';
import 'notice_host.dart' show NoticeKeys;
import 'notice_status.dart';

/// Shows [ConnectionStatus] as a dot, a label and a detail sentence.
///
/// The detail is in a [Tooltip] rather than inline: the strip must stay small
/// enough to live in a header, and the detail is the sentence a user reads once
/// something has already gone wrong.
class NoticeStatusBar extends StatelessWidget {
  /// Creates a status strip bound to [controller].
  const NoticeStatusBar({
    super.key,
    required this.controller,
    required this.palette,
    this.metrics = const NoticeMetrics(),
  });

  /// The channel to render. Listened to, never written to.
  final NoticeController controller;

  /// Every colour, resolved from design tokens by the caller.
  final NoticePalette palette;

  /// The measurements.
  final NoticeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final ConnectionStatus status = controller.status;
        return Tooltip(
          key: NoticeKeys.status,
          message: status.detailTr,
          child: Semantics(
            container: true,
            // A connection state is not a moment, it is a fact about the app, so
            // it is live but not a live region: it must not interrupt whatever
            // the user is doing, it just has to be findable.
            label: '${status.labelTr}. ${status.detailTr}',
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _StatusDot(
                    color: palette.colourForStatus(status),
                    size: metrics.statusDotSize,
                  ),
                  SizedBox(width: metrics.contentGap),
                  Icon(
                    _iconFor(status),
                    size: metrics.statusIconSize,
                    color: palette.colourForStatus(status),
                  ),
                  SizedBox(width: metrics.contentGap),
                  Text(
                    status.labelTr,
                    style: TextStyle(
                      color: status == ConnectionStatus.idle
                          ? palette.muted
                          : palette.colourForStatus(status),
                      fontSize: metrics.bodyFontSize,
                      height: metrics.bodyLineHeight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The one glyph per state: a shape as well as a colour, for the same reason
  /// the notice mark has one.
  static IconData _iconFor(ConnectionStatus status) => switch (status) {
    ConnectionStatus.idle => Icons.circle_outlined,
    ConnectionStatus.connecting => Icons.sync_rounded,
    ConnectionStatus.online => Icons.lock_outline_rounded,
    ConnectionStatus.offline => Icons.cloud_off_outlined,
    ConnectionStatus.error => Icons.error_outline_rounded,
  };
}

/// A filled circle in the state's colour. Private: a dot is not a public concept.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
