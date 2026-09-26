/// The call stage: the big dark rectangle the conversation happens in, the
/// picture that is in it, and the small picture that is not.
///
/// ## The polarity rule, which is a ROADMAP item and not a preference
///
/// `ROADMAP.md` Faz 2, still open:
///
/// > Sahne kutuplaşması testle korunuyor (`stage` koyu, `textOnStage` açık, her
/// > temada) — 0.1.x'teki 1.17:1 sıfırının yapısal olarak geri dönmesini
/// > engelleyen şey bu.
///
/// The token test (`design/test/contrast_test.dart`) already measures the *pair*
/// in all sixteen theme/accent combinations and refuses a light `stage` outright.
/// What it cannot do is say whether a **screen** uses those two roles — a widget
/// that painted its caption in `textMuted` would pass every token test and
/// reproduce the 2.79:1 sibling failure. So:
///
/// * the surface is `style.role('stage')` and nothing else;
/// * every string on it is `style.role('textOnStage')` and nothing else;
/// * the two are read in `build` from the style the tree is painting with, so
///   `test/ui/call/call_stage_test.dart` can assert the *rendered* colours and
///   not a value the test typed in.
///
/// ## Why the focus is a parameter
///
/// `ROADMAP.md` reported defect 5: the main stage was pinned to the local camera
/// and the peer sat in a fixed 126 px box with no way to take over. The fix is not
/// a bigger peer box; it is that **the stage has a subject and the subject
/// changes**. [CallStageFocus] names the two subjects, the host decides which one
/// is on (a remote camera arriving is the only thing that moves it), and a test
/// asserts the switch by reading [CallStageKeys.focus] after a remote camera goes
/// live.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/settings/settings.dart';

import 'call_strings.dart';
import 'local_pip.dart';
import 'video_tile.dart';

/// Whose camera the main stage is showing.
enum CallStageFocus {
  /// The other side. The stage shows the peer whenever the peer's camera is
  /// live, which is the transition 0.1.x had no way to express.
  remote,

  /// This device. The stage's own subject before the peer's camera arrives, so
  /// there is never a stage with nothing in it.
  local,
}

/// The keys the parts of the stage answer to.
abstract final class CallStageKeys {
  /// The `stage` surface itself. The answer screen must **not** contain it —
  /// that is how "the answer screen is up, so the call has not opened" is
  /// measured.
  static const Key surface = Key('mkvi.call.stage.surface');

  /// The main picture's video box.
  static const Key mainTile = Key('mkvi.call.stage.mainTile');

  /// The small picture, when there is one.
  static const Key pip = Key('mkvi.call.stage.pip');

  /// A marker whose presence names the focus, so a test can read the choice
  /// without inspecting an icon.
  static Key focus(CallStageFocus focus) => Key('mkvi.call.stage.focus.${focus.name}');
}

/// The stage.
///
/// [caption] is the one line that sits under the picture and is required,
/// because "nothing to show here" has to be a *sentence* — `CallMessages`
/// already owns the two the app can actually say, and a stage that could be built
/// with no caption is a stage that will be.
class CallStage extends StatelessWidget {
  /// Creates the stage.
  const CallStage({
    super.key,
    required this.caption,
    required this.focus,
    this.showPip = true,
    this.pipCorner = LocalPipCorner.topRight,
    this.pipLabel,
    this.pipCaption,
  });

  /// The line under the picture. Turkish, from the host.
  final String caption;

  /// Whose camera the main stage is showing.
  final CallStageFocus focus;

  /// Whether the small picture is on screen at all.
  ///
  /// `false` for an audio-only call with no local camera open, which is a real
  /// state: the stage then shows a single picture and nothing floats over it.
  final bool showPip;

  /// Which corner the small picture is in.
  final LocalPipCorner pipCorner;

  /// The small picture's own caption, when it has one. Usually the screen-share
  /// phase line, because that is what the user needs to read there.
  final String? pipCaption;

  /// The small picture's label. Defaults to whichever side is *not* on the main
  /// stage, so a caller cannot get the two labels the wrong way round.
  final String? pipLabel;

  String get _resolvedPipLabel => pipLabel ??
      (focus == CallStageFocus.remote
          ? CallUiTr.localVideoLabel
          : CallUiTr.remoteVideoLabel);

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final String mainLabel = focus == CallStageFocus.remote
        ? CallUiTr.remoteVideoLabel
        : CallUiTr.localVideoLabel;

    return DecoratedBox(
      key: CallStageKeys.surface,
      decoration: BoxDecoration(
        color: style.role('stage'),
        borderRadius: style.shape('lg').borderRadius,
        border: Border.all(
          color: style.role('borderStrong'),
          width: style.borderWidth,
        ),
      ),
      child: ClipRRect(
        // Clipped to the same radius the box declares, so the picture inside it
        // cannot paint past the corner the surface promised.
        borderRadius: style.shape('lg').borderRadius,
        child: Padding(
          padding: EdgeInsets.all(style.gap('3')),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                // `Center` loosens the constraints, which is what lets the
                // `AspectRatio` inside the tile keep 16:9 in a stage of any
                // shape. `Positioned.fill` alone hands down *tight* constraints
                // and the frame is then whatever the leftover numbers make it:
                // measured at 1.66:1 in a 1280x800 window, which is a video box
                // with a different aspect ratio than a video.
                child: Center(
                  child: KeyedSubtree(
                    key: CallStageKeys.focus(focus),
                    child: VideoTile(
                      key: CallStageKeys.mainTile,
                      label: mainLabel,
                      caption: caption,
                      icon: focus == CallStageFocus.remote
                          ? Icons.videocam_outlined
                          : Icons.person_outline_rounded,
                      // A floating small picture must not be able to hide behind
                      // the main one's own edge.
                      bordered: false,
                    ),
                  ),
                ),
              ),
              if (showPip)
                Align(
                  key: CallStageKeys.pip,
                  child: LocalPip(
                    corner: pipCorner,
                    label: _resolvedPipLabel,
                    caption: pipCaption,
                    icon: focus == CallStageFocus.remote
                        ? Icons.person_outline_rounded
                        : Icons.videocam_outlined,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
