/// The colours and the measurements of the notice layer, as two injectable
/// values — and **not one colour literal in this file**.
///
/// The design system is generated into `design/lib/generated/tokens.g.dart` and is
/// reached as `package:mkvi_design/mkvi_design.dart`. `app` depends on it as a
/// path dependency (added 2026-09-26), so this layer *can* now name
/// `MkviTokens` — but it still does not, and that is deliberate.
///
/// A layer that imports the generated file binds itself to a generator's output
/// shape. The rule stays structural: **[NoticePalette] has no defaults.** The
/// only way to get one is to build it from a resolved token set, and every
/// field names the `MkviRole` it must come from. The bridge is one function in
/// the app root:
///
/// ```dart
/// NoticePalette paletteFor(MkviTokens t) => NoticePalette(
///   surface: t.surfaceOverlay,
///   onSurface: t.text,
///   muted: t.textMuted,
///   border: t.border,
///   accent: t.accent,
///   success: t.success,
///   warning: t.warning,
///   danger: t.danger,
///   focusRing: t.focusRing,
///   shadow: t.shadow3,
/// );
/// ```
///
/// `NoticeMetrics` does have defaults, because a measurement is not a colour:
/// each default is the `design/tokens.json` value at density 1.0 and says which
/// token it mirrors, so an app at another density passes its own.
library;

import 'package:flutter/painting.dart' show Color, EdgeInsets, Offset;

import 'package:flutter/foundation.dart' show immutable;

import 'notice_kind.dart';
import 'notice_status.dart';

/// Every colour the notice layer draws with, and where each one comes from.
@immutable
class NoticePalette {
  /// Creates a palette from resolved design tokens. No field has a default, on
  /// purpose: see the library docs.
  const NoticePalette({
    required this.surface,
    required this.onSurface,
    required this.muted,
    required this.border,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.focusRing,
    required this.shadow,
  });

  /// `MkviRole.surfaceOverlay` — the top-most floating layer. A toast is a
  /// floating layer, so it takes this and not `surface`.
  final Color surface;

  /// `MkviRole.text` — the notice body, measured against [surface].
  final Color onSurface;

  /// `MkviRole.textMuted` — the close glyph at rest, and the status detail text.
  final Color muted;

  /// `MkviRole.border` — the 1 px outline. Structural, not decorative: it is
  /// what keeps the toast legible on a light surface.
  final Color border;

  /// `MkviRole.accent` — informational severity, and the "connecting" status.
  final Color accent;

  /// `MkviRole.success` — successful severity, and the "online" status.
  final Color success;

  /// `MkviRole.warning` — warning severity, and the "offline" status.
  final Color warning;

  /// `MkviRole.danger` — error severity, and the "error" status.
  final Color danger;

  /// `MkviRole.focusRing` — the keyboard focus outline on the close control.
  /// Must clear 3:1 against [surface], which the token gate already checks.
  final Color focusRing;

  /// `MkviRole.shadow3` — elevation 3, the level the token file reserves for
  /// popovers, menus and dialogs. A toast over the message list is the same
  /// class of object.
  final Color shadow;

  /// The one colour a severity is drawn in: its stripe, its icon, nothing else.
  ///
  /// Keeping the mapping here rather than at four call sites is what stops a
  /// warning from being painted `danger` on the stripe and `warning` in the
  /// text.
  Color colourFor(NoticeKind kind) => switch (kind) {
    NoticeKind.info => accent,
    NoticeKind.success => success,
    NoticeKind.warning => warning,
    NoticeKind.error => danger,
  };

  /// The one colour a connection state is drawn in.
  ///
  /// [ConnectionStatus.idle] takes [muted] on purpose: "nothing is happening"
  /// must not look like something needs attention.
  Color colourForStatus(ConnectionStatus status) => switch (status) {
    ConnectionStatus.idle => muted,
    ConnectionStatus.connecting => accent,
    ConnectionStatus.online => success,
    ConnectionStatus.offline => warning,
    ConnectionStatus.error => danger,
  };

  @override
  String toString() => 'NoticePalette(${surface.toARGB32().toRadixString(16)})';
}

/// The measurements of the notice layer, in logical pixels.
///
/// Every default is the `design/tokens.json` value at density 1.0; the comment on
/// each field names the token it mirrors, so a density-aware app passes
/// `NoticeMetrics` built from `MkviSpacing` / `MkviControls` instead of using
/// the defaults.
@immutable
class NoticeMetrics {
  /// Creates a metric set. The defaults are the density-1.0 token values.
  const NoticeMetrics({
    this.maxWidth = 420,
    this.maxBodyLines = 3,
    this.bodyFontSize = 13,
    this.bodyLineHeight = 1.45,
    this.closeTarget = 44,
    this.closeIconSize = 18,
    this.focusRingWidth = 2,
    this.severityIconSize = 18,
    this.stripeWidth = 4,
    this.stripeGap = 12,
    this.contentGap = 8,
    this.paddingX = 12,
    this.paddingY = 12,
    this.laneGapX = 16,
    this.laneGapY = 8,
    this.cornerRadius = 12,
    this.shadowBlur = 24,
    this.shadowDx = 0,
    this.shadowDy = 8,
    this.statusIconSize = 16,
    this.statusDotSize = 8,
    this.borderWidth = 1,
  }) : assert(
         closeTarget >= minimumCloseTarget,
         'the close control is the only way out of a notice, so it may not be '
         'smaller than the smallest pointer target: '
         '$minimumCloseTarget dp',
       );

  /// The smallest close control this layer will build, whatever the tokens say.
  ///
  /// 40 dp is the smallest pointer target a person can hit reliably, and the
  /// close control is the only way out of a notice. `MkviControls.hitTargetMin`
  /// is 44, so the tokens are already above this; the floor is here so that a
  /// denser app cannot quietly make the button unhittable.
  static const double minimumCloseTarget = 40;

  /// How wide a notice may be. It is right-aligned, so this is a cap, not a
  /// width: narrow windows simply get a narrower toast.
  final double maxWidth;

  /// How many lines of body text are shown before the rest is scrollable.
  final int maxBodyLines;

  /// `typeScale.sm.size` at density 1.0.
  final double bodyFontSize;

  /// `lineHeights['normal']` at density 1.0.
  final double bodyLineHeight;

  /// `controls.hitTargetMin` at density 1.0: the side of the close button.
  final double closeTarget;

  /// `controls.md.iconSize` at density 1.0: the close glyph.
  final double closeIconSize;

  /// `controls.focusRingWidth` at density 1.0: the keyboard focus outline.
  final double focusRingWidth;

  /// `controls.md.iconSize` at density 1.0: the severity mark.
  final double severityIconSize;

  /// `space.1` at density 1.0: the severity stripe.
  final double stripeWidth;

  /// The gap between the severity stripe and the message. `space.3`, i.e. the
  /// same as the surface's padding, so the stripe reads as part of the padding
  /// rather than as another column.
  final double stripeGap;

  /// `space.2` at density 1.0: the gap between the mark, the body and the close
  /// control, and between the surface and the reserved gutter.
  final double contentGap;

  /// `space.3` at density 1.0: the surface's horizontal padding.
  final double paddingX;

  /// `space.3` at density 1.0: the surface's vertical padding.
  final double paddingY;

  /// `space.4` at density 1.0: the reserved gutter on the open side.
  final double laneGapX;

  /// `space.2` at density 1.0: the reserved gutter above and below the lane.
  final double laneGapY;

  /// `radius.lg` at density 1.0: the surface's corner radius.
  final double cornerRadius;

  /// The blur of the elevation-3 shadow. Not a token: `MkviTokens.shadow3` is a
  /// colour, and the offset and blur are the only two numbers a shadow needs.
  final double shadowBlur;

  /// The horizontal offset of the elevation-3 shadow. Zero: a toast is centred
  /// on its own column, not on the window.
  final double shadowDx;

  /// The downward offset of the elevation-3 shadow, so the toast reads as lifted
  /// off the message list rather than glowing behind it.
  final double shadowDy;

  /// [shadowDx] and [shadowDy] as the one value a [BoxShadow] wants.
  Offset get shadowOffset => Offset(shadowDx, shadowDy);

  /// `controls.sm.iconSize` at density 1.0: the status mark.
  final double statusIconSize;

  /// `space.2` at density 1.0: the status dot.
  final double statusDotSize;

  /// `controls.borderWidth` at density 1.0: the surface outline.
  final double borderWidth;

  /// The cap on the scrollable body, derived from the type scale.
  ///
  /// This is the answer to "there was no height cap, so a long notice with a
  /// Windows file path grew over the message list": a notice can never be
  /// taller than its padding, plus the close control, plus this.
  double get maxBodyHeight => bodyFontSize * bodyLineHeight * maxBodyLines;

  /// The cap on the whole surface, for tests and for callers that need to know
  /// how much vertical space a notice can ask for.
  ///
  /// An upper bound: the border, the stripe and the mark make the real worst
  /// case slightly smaller, and it can only ever be the sum of these terms.
  double get maxSurfaceHeight =>
      (borderWidth * 2) + (paddingY * 2) + closeTarget + maxBodyHeight;

  /// The padding inside the surface.
  EdgeInsets get surfacePadding =>
      EdgeInsets.symmetric(horizontal: paddingX, vertical: paddingY);

  /// The reserved gutter around the surface. This is the documented space the
  /// host keeps, so a notice is never flush against a window edge or a
  /// neighbouring control.
  EdgeInsets get lanePadding =>
      EdgeInsets.symmetric(horizontal: laneGapX, vertical: laneGapY);

  @override
  String toString() =>
      'NoticeMetrics(maxWidth: $maxWidth, body: $maxBodyHeight)';
}
