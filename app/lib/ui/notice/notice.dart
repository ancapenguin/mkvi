/// The notification layer: one transient channel, one persistent one, and a
/// layout that reserves its space instead of stealing it.
///
/// The bug this layer exists for was reported from two Windows machines as "the
/// bottom-right notification never goes away" — and, worse, as a window in which
/// nothing could be typed, because the toast was sitting on the send button.
/// Five separate causes, all in one `String` and one CSS rule:
///
/// 1. **One channel, six writers, a re-arming timer.** `App.tsx` had a single
///    `notice` written from six places, one of them inside the reconnect loop
///    (`src/App.tsx:289`), and the 5.5 s auto-dismiss effect keyed on `notice`
///    (`src/App.tsx:183-187`) re-armed on every write. It could not expire, and
///    `onClose={() => setNotice("")}` looked like a dead button because the loop
///    refilled the field within a second. → [NoticeController] splits the
///    channels and applies four rules (dedup, a close that sticks, a severity
///    rule, a rate limit), and the clock is injected, so all four are tests.
/// 2. **A fixed overlay on top of the composer.** `.mkvi-toast { position:
///    fixed; z-index: 100; bottom: 18px; right: 18px; }` (`src/App.css:168-172`)
///    inside a 100dvh grid. → [NoticeHost] is an in-flow `Column` child, so it
///    takes real space and the composer can never be covered.
/// 3. **A close button that was not styled at all.** `font: 700 1.15rem/1
///    inherit;` is not valid CSS — `inherit` may not be the last component of the
///    `font` shorthand — so the declaration was dropped whole
///    (`src/App.css:190`). → [NoticeCloseButton] builds an [Icon] with an
///    explicit size and colour, a 44 dp target, a hover state and a focus ring.
/// 4. **A condition rendered as an event.** "Reconnecting" is a state, and it
///    went through the same transient channel as "settings saved", so the UI
///    could not tell "something happened" from "the app is broken". →
///    [ConnectionStatus] and [NoticeStatusBar], with no timer and no close button
///    anywhere in that path.
/// 5. **No height cap.** A saved file's full Windows path grew the toast down
///    over the message list. → [NoticeMetrics.maxBodyHeight] caps the body,
///    [noticeSoftBreaks] gives a 300-character path the break opportunities it
///    needs to fit inside that cap, and the rest stays scrollable.
///
/// Everything the layer can say to a user is in [NoticeTr], in Turkish, with no
/// way to add an entry and leave it empty. Every colour comes from a
/// [NoticePalette] the caller builds from the generated design tokens, and this
/// package contains no colour literal.
///
/// The layer is not a monolith: `notice_controller.dart` and the rest of the
/// state model have no widget in them, so the four rules are unit-tested without
/// a widget tree, and the layout is a widget test over real rects.
library;

export 'notice_clock.dart';
export 'notice_controller.dart';
export 'notice_design.dart';
export 'notice_host.dart';
export 'notice_kind.dart';
export 'notice_policy.dart';
export 'notice_state.dart';
export 'notice_status.dart';
export 'notice_status_bar.dart';
export 'notice_strings.dart';
export 'notice_text.dart';
