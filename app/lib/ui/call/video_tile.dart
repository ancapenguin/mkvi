/// One video box: the surface a camera frame will be painted into, and the two
/// Turkish sentences that sit on it while there is no frame yet.
///
/// ## Why the size is derived and 126 px is not
///
/// 0.1.x drew the peer's video at a **hard-coded 126 px** and pinned the main
/// stage to the local camera forever, so the two halves of `ROADMAP.md`'s
/// reported defect 5 — "Ana sahne kendi kamerana sabit, karşı taraf 126 px'de" —
/// were one decision: the remote tile was given a number instead of a rule, and
/// the stage was given a *constant* where it needed a *choice*.
///
/// So nothing here is a pixel. Every metric is read from `AppearanceStyle`:
///
/// | what | where it comes from |
/// |---|---|
/// | the corner radius | `style.radius('md')` |
/// | the glyph | `style.control('lg').iconSize` |
/// | the padding inside the box | `style.gap('4')` |
/// | the label's type | `style.styleOf('sm')` |
/// | the caption's type | `style.styleOf('xs')` |
///
/// The only number in the file is [callVideoAspect], and it is a *shape* rather
/// than a metric: it says what a camera frame looks like, which no theme,
/// density or type setting can change, and the design token file has no opinion
/// about it because a token file describes this app and not the world. It is a
/// public constant with a name so a test can assert the tile really is that shape
/// instead of re-typing `16 / 9` in the assertion and agreeing with itself.
///
/// ## Why the surface is `stage` and the text is `textOnStage`
///
/// This is the pair `design/test/contrast_test.dart` measures at 4.5:1 in all
/// sixteen theme/accent combinations, and the pair the 0.1.x light theme
/// measured at **1.17:1**: it painted the placeholder at `#e9edf3` and the text
/// on it at `#f8fafc`. Every role a video box paints is therefore `stage` or
/// `textOnStage`, and nothing here reaches for `surface`, `text` or a literal.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

/// The shape of a camera frame: 16 by 9.
///
/// A constant rather than a token, on purpose — see the file header. Named so a
/// test asserts against this value and not against a second spelling of it.
const double callVideoAspect = 16 / 9;

/// The keys the parts of a video box answer to.
abstract final class VideoTileKeys {
  /// The decorated `stage` box. This is what a test measures and what the
  /// contrast assertions are made about.
  static const Key surface = Key('mkvi.call.video.surface');

  /// The participant's name, in `textOnStage`.
  static const Key label = Key('mkvi.call.video.label');

  /// The line under the name — "Aktif görüntü yok", the share phase, whatever
  /// there is to say. In `textOnStage` as well: `textMuted` on a dark stage is
  /// the sibling failure the token test also records, at 2.79:1.
  static const Key caption = Key('mkvi.call.video.caption');
}

/// One video box.
///
/// Lays out as an [AspectRatio], so it takes whatever width it is given and
/// derives its height from the shape. That is what lets the same widget be the
/// main stage (full width) and a thumbnail (a fifth of it) with no second
/// layout path and no number to keep in sync.
class VideoTile extends StatelessWidget {
  /// Creates a video box.
  const VideoTile({
    super.key,
    required this.label,
    this.caption,
    this.icon = Icons.videocam_outlined,
    this.aspectRatio = callVideoAspect,
    this.bordered = true,
  });

  /// Whose camera this box is for, in Turkish. Required, because a video box
  /// with no name is how two participants end up indistinguishable.
  final String label;

  /// The line under [label], when there is something to say. Optional: a tile
  /// that is showing frames needs no caption.
  final String? caption;

  /// The glyph shown while no frame is arriving.
  final IconData icon;

  /// The frame's shape. [callVideoAspect] unless a caller has a reason.
  final double aspectRatio;

  /// Whether the box takes a `borderStrong` edge.
  ///
  /// On by default because a `stage` box is a dark rectangle on a page that is
  /// dark too, and a shape whose only boundary is the difference between two
  /// near-blacks is not a shape.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    // Named once, so the box and its text cannot drift onto two different roles.
    final Color onStage = style.role('textOnStage');
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        key: VideoTileKeys.surface,
        decoration: BoxDecoration(
          color: style.role('stage'),
          borderRadius: style.shape('md').borderRadius,
          border: bordered
              ? Border.all(
                  color: style.role('borderStrong'),
                  width: style.borderWidth,
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.all(style.gap('4')),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // `FittedBox(scaleDown)` and not a bare `Column`, because a video
              // box is the one widget in this app whose size is decided by
              // somebody else: at a 205 dp stage the 16:9 box is 205x115, the
              // glyph and two lines of type do not fit, and a `Column` reports
              // "overflowed by 12 pixels on the bottom". Shrinking the whole
              // placeholder is what a video area does; clipping the label is not.
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  // The tile's own inner width, so a long name *wraps* at full
                  // size and only shrinks if it still does not fit.
                  width: constraints.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Icon(icon, size: style.control('lg').iconSize, color: onStage),
                      SizedBox(height: style.gap('2')),
                      Text(
                        label,
                        key: VideoTileKeys.label,
                        textAlign: TextAlign.center,
                        style: style.styleOf('sm').copyWith(color: onStage),
                      ),
                      if (caption != null) ...<Widget>[
                        SizedBox(height: style.gap('1')),
                        Text(
                          caption!,
                          key: VideoTileKeys.caption,
                          textAlign: TextAlign.center,
                          style: style.styleOf('xs').copyWith(color: onStage),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
