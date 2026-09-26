/// The call screen: the answer dialog 0.1.4 never shipped, the stage it never
/// let change subject, and the five controls it hung off a 34 px close button.
///
/// ## What this layer is
///
/// `app/lib/call/` is a 110-test state machine and `main.dart` was still the
/// Flutter template, so nothing in the application could *show* any of it. This
/// package is that missing half, and it is deliberately thin: it owns no call
/// state, no timer and no WebRTC, because the layer below already owns all three
/// and a second copy of any of them is how the two 45 s timeouts of
/// `call_incoming_test.dart` stop meaning what they say.
///
/// | file | what it is |
/// |---|---|
/// | [call_strings.dart] | the Turkish catalogue, reusing [CallMessages] rather than retyping it |
/// | [video_tile.dart] | one video box, sized from tokens and never from 126 px |
/// | [local_pip.dart] | the small picture, in a corner, `sm`-control-proportional |
/// | [call_stage.dart] | the `stage` surface, its `textOnStage` text, and whose camera is in it |
/// | [call_controls.dart] | five controls, each 44 dp and each with a Turkish name |
/// | [call_device_picker.dart] | the camera, microphone and share-target lists |
/// | [incoming_call_screen.dart] | accept / decline, with the 45 s countdown |
/// | [call_screen.dart] | [CallUiHost] and [CallScreen] |
///
/// ## The four `ROADMAP.md` items this package exists to close
///
/// 1. **"Cevap ekranı yok, arama direkt açılıyor"** — [IncomingCallScreen] and the
///    fact that no [CallStage] is built while the status is
///    [CallStatus.incoming].
/// 2. **The callee had no ring timeout** — [CallUiHost.remainingRingSeconds] and
///    the countdown it feeds, both derived from the machine's own timer.
/// 3. **"Sahne kutuplaşması testle korunuyor"** — `CallStage` paints `stage` and
///    `textOnStage` and nothing else, and
///    `test/ui/call/call_stage_test.dart` measures the rendered pair in all four
///    themes.
/// 4. **"Kabul medyadan önce"** — [CallUiHost.onTransition] runs the frames
///    before it queues the media step, and [CallUiHost.operations] is the log a
///    test reads.
///
/// ## The design rules this package obeys
///
/// * **No colour, no pixel, no `dart:math`, no animation `Duration` literal.** A
///   number is read from [AppearanceStyle], or it is a *proportion* with a name
///   ([callVideoAspect], `LocalPip.sideOf`, `CallControlLabels`). `design/tokens.json`
///   is the only place a measurement is written down.
/// * **Every user-facing string is Turkish and lives in [CallUiTr]** or is
///   re-used from [CallMessages] / [MediaTexts]; a required argument is never a
///   `String` a call site may leave empty.
/// * **Every operable control has a Turkish name**, which for an icon button is
///   its `Tooltip`, and `test/ui/call/call_controls_test.dart` includes the
///   negative control: the same bar with one name blanked goes red under
///   `expectEveryControlLabelled`.
library;

export 'call_controls.dart';
export 'call_device_picker.dart';
export 'call_screen.dart';
export 'call_stage.dart';
export 'call_strings.dart';
export 'incoming_call_screen.dart';
export 'local_pip.dart';
export 'video_tile.dart';
