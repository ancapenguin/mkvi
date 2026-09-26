/// The widgets: a reserved lane that cannot overlap the composer, and a surface
/// that cannot grow without bound.
///
/// The second reported defect was pure layout. TS: `.mkvi-toast { position:
/// fixed; z-index: 100; right: …; bottom: 18px; width: min(390px, …) }`
/// (`src/App.css:168-188`), rendered inside a 100dvh grid from
/// `src/App.tsx:542`. A fixed overlay has no relationship with the composer
/// underneath it, so the toast landed on the send button and on the transfer
/// close buttons, and two machines reported that nothing could be typed any more.
///
/// The fix here is not a larger bottom offset, it is a different kind of layout.
/// [NoticeHost] is an **in-flow sibling**, not an overlay:
///
/// ```dart
/// Column(
///   children: <Widget>[
///     Expanded(child: messageList),
///     NoticeHost(controller: controller, palette: palette), // height 0, or the notice
///     Composer(sendButton: …),                              // can never be covered
///   ],
/// )
/// ```
///
/// When there is nothing to say the host is exactly zero tall, so the composer
/// does not move. When there is a notice the host is exactly as tall as the
/// notice, so the message list gives up the space instead of the composer being
/// drawn over. There is no `z-index` to win and no offset to get wrong, and
/// `test/ui/notice/notice_host_test.dart` asserts the two rects do not intersect.
///
/// Two more things the old toast did not have: a cap on the body
/// ([NoticeMetrics.maxBodyHeight], scrollable past it) and a close control with a
/// real target ([NoticeCloseButton], `MkviControls.hitTargetMin` = 44 dp, with
/// hover and keyboard-focus states). TS's close button was
/// `.mkvi-toast button { width: 34px; height: 34px; … font: 700 1.15rem/1 inherit; }`
/// (`src/App.css:190`) — 34 px, and `inherit` as the last component of the `font`
/// shorthand is not valid CSS, so the whole declaration was dropped and the glyph
/// rendered unstyled. That defect is a tested property here: the button is an
/// [Icon] with an explicit size and colour, at least
/// [NoticeMetrics.minimumCloseTarget] on a side, and it answers to Enter.
library;

import 'package:flutter/material.dart';

import 'notice_controller.dart';
import 'notice_design.dart';
import 'notice_kind.dart';
import 'notice_state.dart';
import 'notice_strings.dart';
import 'notice_text.dart';

/// Keys for the parts of this layer, so a test asserts on the widget it means.
///
/// `mkvi.` prefixed because these names end up in golden files and in
/// `find.byKey` calls.
abstract final class NoticeKeys {
  /// The reserved lane. Its height is the space the layer asks for.
  static const Key lane = Key('mkvi.notice.lane');

  /// The surface, i.e. the box the eye sees.
  static const Key surface = Key('mkvi.notice.surface');

  /// The scrollable body. Its height is capped at
  /// [NoticeMetrics.maxBodyHeight].
  static const Key body = Key('mkvi.notice.body');

  /// The close control.
  static const Key close = Key('mkvi.notice.close');

  /// The severity mark.
  static const Key mark = Key('mkvi.notice.mark');

  /// The inner box that carries the severity stripe and the outline.
  static const Key outline = Key('mkvi.notice.outline');

  /// The status strip.
  static const Key status = Key('mkvi.notice.status');
}

/// The notice channel, rendered as an in-flow lane that reserves its own space.
///
/// Place it between the message list and the composer, as a `Column` child with
/// nothing expanded around it. That placement is the contract: the lane takes
/// real layout space, so a notice can never cover the composer, the transfer
/// close buttons, or the send button. Putting this widget in a `Stack` would
/// restore the reported bug, and no widget can detect that, so it is written up
/// here instead.
///
/// Rebuilds only when [controller] publishes, and never animates: an animation
/// would need a second clock, and this layer has exactly one — the injected
/// `NoticeClock`, which a test drives.
class NoticeHost extends StatelessWidget {
  /// Creates the lane. [palette] is required so that no colour in this layer
  /// can have a default; see `notice_design.dart`.
  const NoticeHost({
    super.key,
    required this.controller,
    required this.palette,
    this.metrics = const NoticeMetrics(),
  });

  /// The channel to render. Listened to, never written to.
  final NoticeController controller;

  /// Every colour, resolved from design tokens by the caller.
  final NoticePalette palette;

  /// The measurements, defaulting to the density-1.0 token values.
  final NoticeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final Notice? notice = controller.notice;
        if (notice == null) {
          // Zero height: the composer does not move for a notice that is not
          // there, which is the other half of "it can never be covered".
          return const SizedBox.shrink();
        }
        return NoticeLane(
          key: NoticeKeys.lane,
          notice: notice,
          palette: palette,
          metrics: metrics,
          onDismiss: controller.dismiss,
        );
      },
    );
  }
}

/// The reserved gutter plus the surface, right-aligned.
///
/// Separate from [NoticeHost] so a screen that wants the notice somewhere else can
/// place the same reserved box without re-deriving the gutter.
class NoticeLane extends StatelessWidget {
  /// Creates a lane for one notice.
  const NoticeLane({
    super.key,
    required this.notice,
    required this.palette,
    required this.metrics,
    required this.onDismiss,
  });

  /// What to show.
  final Notice notice;

  /// Every colour, resolved from design tokens by the caller.
  final NoticePalette palette;

  /// The measurements.
  final NoticeMetrics metrics;

  /// Called when the user closes the notice.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: metrics.lanePadding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: metrics.maxWidth),
              child: NoticeSurface(
                notice: notice,
                palette: palette,
                metrics: metrics,
                onDismiss: onDismiss,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One notice: a severity stripe, a severity mark, a capped body, a close button.
///
/// The height is bounded by construction rather than by a clamp: the body is
/// capped at [NoticeMetrics.maxBodyHeight], the close control is
/// [NoticeMetrics.closeTarget] on a side, and the padding is fixed. So
/// [NoticeMetrics.maxSurfaceHeight] is the worst case whatever the text says, and
/// a 3000-character path is exactly as tall as a 300-character one.
class NoticeSurface extends StatelessWidget {
  /// Creates a surface for one notice.
  const NoticeSurface({
    super.key,
    required this.notice,
    required this.palette,
    required this.metrics,
    required this.onDismiss,
  });

  /// What to show.
  final Notice notice;

  /// Every colour, resolved from design tokens by the caller.
  final NoticePalette palette;

  /// The measurements.
  final NoticeMetrics metrics;

  /// Called when the user closes the notice.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: NoticeKeys.surface,
      // Transparent: the surface paints itself below, and this exists so the
      // scrollbar and the close control's ink have a Material ancestor.
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(metrics.cornerRadius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: palette.shadow,
              blurRadius: metrics.shadowBlur,
              offset: metrics.shadowOffset,
            ),
          ],
        ),
        // The severity stripe is the left *border* of an inner box, and the
        // rounding is a clip over it. `Border.paint` refuses a `borderRadius`
        // with non-uniform side colours — "A borderRadius can only be given on
        // borders with uniform colors" — and stretching a stripe widget would
        // need an intrinsic height, which a capped scroll view cannot give. A
        // clipped inner border has neither problem, and it is exactly as tall as
        // the surface by construction.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(metrics.cornerRadius),
          child: Container(
            key: NoticeKeys.outline,
            // The stripe is a border, so the left inset has to make room for it;
            // the other three sides are the surface's own padding.
            padding: metrics.surfacePadding.copyWith(
              left: metrics.stripeGap + metrics.stripeWidth,
            ),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: palette.colourFor(notice.kind),
                  width: metrics.stripeWidth,
                ),
                top: BorderSide(
                  color: palette.border,
                  width: metrics.borderWidth,
                ),
                right: BorderSide(
                  color: palette.border,
                  width: metrics.borderWidth,
                ),
                bottom: BorderSide(
                  color: palette.border,
                  width: metrics.borderWidth,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: NoticeMessage(
                    notice: notice,
                    palette: palette,
                    metrics: metrics,
                  ),
                ),
                SizedBox(width: metrics.contentGap),
                NoticeCloseButton(
                  key: NoticeKeys.close,
                  palette: palette,
                  metrics: metrics,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The severity mark and the capped body, announced as one live region.
///
/// The two are wrapped together so a screen reader says "Uyarı. Dosya kaydedildi."
/// instead of announcing an unlabelled glyph and then the sentence. The glyph and
/// the shaped text are excluded from semantics, which also keeps the inserted
/// zero-width spaces out of the announcement; [Notice.text] is what gets read.
///
/// It is a `StatefulWidget` for one boolean: whether the body is taller than its
/// cap, which decides the always-visible scrollbar thumb and the Turkish
/// "scroll to read the rest" hint.
class NoticeMessage extends StatefulWidget {
  /// Creates the message group for one notice.
  const NoticeMessage({
    super.key,
    required this.notice,
    required this.palette,
    required this.metrics,
  });

  /// What to show.
  final Notice notice;

  /// Every colour, resolved from design tokens by the caller.
  final NoticePalette palette;

  /// The measurements.
  final NoticeMetrics metrics;

  @override
  State<NoticeMessage> createState() => _NoticeMessageState();
}

class _NoticeMessageState extends State<NoticeMessage> {
  final ScrollController _scroll = ScrollController();
  bool _overflowing = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The viewport reports its own extents, which is the only honest way to know
  /// whether there is anything to scroll: the alternative is to guess from the
  /// character count, and a Windows path's character count says nothing about
  /// its height.
  bool _onMetrics(ScrollMetricsNotification notification) {
    final bool overflow = notification.metrics.maxScrollExtent > 0;
    if (overflow == _overflowing) return false;
    // A metrics notification can arrive while the tree is being laid out, and
    // setState is not allowed there, so the change lands in the next frame.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || overflow == _overflowing) return;
      setState(() => _overflowing = overflow);
    });
    // The notice itself is not a scrollable, so nothing above needs the event.
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final NoticeMetrics metrics = widget.metrics;
    final NoticePalette palette = widget.palette;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${widget.notice.kind.labelTr}. ${widget.notice.text}',
      hint: _overflowing ? NoticeTr.bodyScrollHint.tr : null,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              key: NoticeKeys.mark,
              _iconFor(widget.notice.kind),
              size: metrics.severityIconSize,
              color: palette.colourFor(widget.notice.kind),
            ),
            SizedBox(width: metrics.contentGap),
            Expanded(
              child: NotificationListener<ScrollMetricsNotification>(
                onNotification: _onMetrics,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: metrics.maxBodyHeight),
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: _overflowing,
                    // Not interactive: an interactive thumb drags an English
                    // framework tooltip into a Turkish UI, and a three-line body
                    // does not need one.
                    interactive: false,
                    child: SingleChildScrollView(
                      key: NoticeKeys.body,
                      controller: _scroll,
                      child: Text(
                        noticeSoftBreaks(widget.notice.text),
                        style: TextStyle(
                          color: palette.onSurface,
                          fontSize: metrics.bodyFontSize,
                          height: metrics.bodyLineHeight,
                          // `typeScale.sm.weight`, i.e. regular: a toast is a
                          // sentence, not a heading.
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The one glyph per severity: the outline set, so a severity reads as a shape
  /// as well as a colour.
  static IconData _iconFor(NoticeKind kind) => switch (kind) {
    NoticeKind.info => Icons.info_outline_rounded,
    NoticeKind.success => Icons.check_circle_outline_rounded,
    NoticeKind.warning => Icons.warning_amber_rounded,
    NoticeKind.error => Icons.error_outline_rounded,
  };
}

/// The close control: at least [NoticeMetrics.minimumCloseTarget] on a side,
/// with a visible hover state and a visible keyboard focus ring.
///
/// The three properties TS's button did not have, and the three this widget test
/// asserts:
///
/// * a real target — 44 dp by default (`MkviControls.hitTargetMin`), and
///   [NoticeMetrics] refuses to be built with anything smaller;
/// * a hover state — the glyph goes from [NoticePalette.muted] to
///   [NoticePalette.onSurface] under the pointer, and a press paints a token ink
///   splash in a circular well;
/// * a focus state — the glyph brightens and a [NoticePalette.focusRing] ring
///   appears, from an [Icon] with an explicit size and colour rather than from a
///   CSS shorthand that a browser may discard.
///
/// The optional [focusNode] exists so a screen can move focus here on purpose —
/// for a sticky error, say — without this widget inventing a traversal order.
/// It is never auto-focused: a toast that grabs focus is the reported bug's
/// cousin, since the user is typing in the composer.
class NoticeCloseButton extends StatefulWidget {
  /// Creates the close control.
  const NoticeCloseButton({
    super.key,
    required this.palette,
    required this.metrics,
    required this.onPressed,
    this.focusNode,
  });

  /// Every colour, resolved from design tokens by the caller.
  final NoticePalette palette;

  /// The measurements.
  final NoticeMetrics metrics;

  /// Called on tap, on Enter and on Space.
  final VoidCallback onPressed;

  /// An externally owned node, when the screen wants to focus this on purpose.
  final FocusNode? focusNode;

  @override
  State<NoticeCloseButton> createState() => _NoticeCloseButtonState();
}

class _NoticeCloseButtonState extends State<NoticeCloseButton> {
  FocusNode? _ownNode;
  bool _hovered = false;
  bool _focused = false;

  /// The caller's node when there is one, otherwise one this widget owns and
  /// disposes.
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NoticeMetrics metrics = widget.metrics;
    final NoticePalette palette = widget.palette;
    final bool active = _hovered || _focused;
    return Semantics(
      button: true,
      label: NoticeTr.close.tr,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          focusNode: _node,
          onFocusChange: (bool value) => setState(() => _focused = value),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onPressed,
              customBorder: const CircleBorder(),
              // The only text-free icon button in the app that has to be
              // operable by keyboard, so it is the one that gets a ring.
              focusColor: palette.focusRing,
              child: SizedBox.square(
                dimension: metrics.closeTarget,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: _focused
                          ? Border.all(
                              color: palette.focusRing,
                              width: metrics.focusRingWidth,
                            )
                          : null,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: metrics.closeIconSize,
                      color: active ? palette.onSurface : palette.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
