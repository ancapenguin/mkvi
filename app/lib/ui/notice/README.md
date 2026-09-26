# `lib/ui/notice` — the notification layer

Two channels, and the reported bug was that they were one.

```dart
final NoticeController notices = NoticeController(clock: systemNoticeClock);

notices.show(NoticeTr.statusOffline);            // never a toast: see setStatus
notices.showText('Mesaj gönderildi.');           // transient, 5.5 s, deduped
notices.showText('Cihaz kimliği açılamadı.', kind: NoticeKind.error); // sticky
notices.setStatus(ConnectionStatus.connecting);  // a state, no timer, no toast
```

## The five defects, and where each one is pinned

| # | What the reported build did | What is here | The test that proves it |
|---|---|---|---|
| 1 | one `notice` written from six places, the 5.5 s timer re-armed by each write, so the toast could not expire and the close button looked dead (`src/App.tsx:183-187`, `:289`) | dedup by text, a close that is remembered until the text changes, a rate limit between automatic dismissals | `notice_controller_test.dart` — "six writes one second apart still expire on schedule", "a manual close is not undone by the next write of the same text" |
| 2 | `position: fixed; z-index: 100; bottom: 18px; right: 18px` inside a 100dvh grid, so the toast sat on the send button (`src/App.css:168-188`) | `NoticeHost` is an **in-flow `Column` child**; it reserves its own height or zero height, and there is no offset to tune | `notice_host_test.dart` — "the notice is laid out above the composer, not over it", "the lane reserves its own height, so the list gives way" |
| 3 | `font: 700 1.15rem/1 inherit;` is not valid CSS, so the close glyph's whole declaration was dropped, and the target was 34 px (`src/App.css:190`) | `NoticeCloseButton`: an `Icon` with an explicit size and colour, `MkviControls.hitTargetMin` (44 dp) on a side, a visible hover state and a visible focus ring | `notice_host_test.dart` — "its hit target is at least 40 dp on both sides", "its glyph has a real size and colour, not a dropped rule", "it has a visible hover state" |
| 4 | connection state went through the same transient channel, so "reconnecting" was an event with a 5.5 s life | `ConnectionStatus` + `NoticeStatusBar`; `setStatus` has no path to a `Notice` | `notice_controller_test.dart` — "no status value puts a notice on screen, at any clock time" |
| 5 | no height cap, so a saved file's full Windows path grew over the message list (`src/App.tsx:376`) | `NoticeMetrics.maxBodyHeight` caps the body, the rest stays scrollable, and `noticeSoftBreaks` gives a path the break opportunities it needs to fit inside the cap | `notice_host_test.dart` — "a 300-character Windows path is capped and scrollable", "ten times the text is exactly as tall as once" |

## Two channels, one class

| channel | written by | has a timer | can be closed | lives in |
|---|---|---|---|---|
| notice | `show`, `showText` | yes, unless the severity is `error` | yes, and the close sticks | the reserved lane, bottom-right |
| status | `setStatus` | never | never | a status strip, wherever the window puts one |

Conflating them was the cause, so nothing in `setStatus` can produce a `Notice`:
the snapshot assignment copies the notice field through untouched. That is a
property of the code, not a branch someone has to remember to keep.

## The clock is a constructor parameter

```dart
NoticeController(clock: systemNoticeClock)                  // production
NoticeController(clock: FakeNoticeClock())                  // test
NoticeController(clock: const DisabledNoticeClock())        // no auto-dismiss
```

There is no default. A controller with a default timer would be the old bug
waiting for a new call site, and the five-second TS lifetime is a
`NoticePolicy.transientLifetime` rather than a constant in the middle of a method.
`FakeNoticeClock.advance` walks to each due deadline in order, so a callback that
re-arms is handled the way a real event loop would handle it, and no test in this
directory can reach a `dart:async` `Timer`.

## Where the colours come from

`app` has no dependency on `design/`, so this layer cannot name `MkviTokens` and
therefore must not contain a colour literal — an invented colour is one that will
never follow a theme. So `NoticePalette` has **no defaults**: the only way to get
one is to build it from a resolved token set, and every field documents the
`MkviRole` it must come from. The bridge is one function in the app root:

```dart
NoticePalette paletteFor(MkviTokens t) => NoticePalette(
  surface: t.surfaceOverlay,   // MkviRole.surfaceOverlay
  onSurface: t.text,           // MkviRole.text
  muted: t.textMuted,          // MkviRole.textMuted
  border: t.border,            // MkviRole.border
  accent: t.accent,            // MkviRole.accent
  success: t.success,          // MkviRole.success
  warning: t.warning,          // MkviRole.warning
  danger: t.danger,            // MkviRole.danger
  focusRing: t.focusRing,      // MkviRole.focusRing
  shadow: t.shadow3,           // MkviRole.shadow3
);
```

That function needs `mkvi_design` in `app/pubspec.yaml`, which is a one-line
change outside this layer. `test/ui/notice/support/notice_test_screen.dart` carries
the `midnight`/`blue` values copied from the generated file, and a widget test
asserts the surface paints from whatever palette it is handed — so swapping the
copy for the real tokens is a wiring change and nothing else.

`NoticeMetrics` is the other half: measurements, not colours, with
`design/tokens.json` defaults at density 1.0, each naming the token it mirrors.

## Everything the user reads is Turkish and typed

`NoticeTr` is the whole vocabulary of this layer: the close control's name, the
scroll hint, the four severity names, and a label plus a detail for each of the
five connection states. The text is a constructor argument, so an entry without
wording will not compile.

## Files

| file | what is in it |
|---|---|
| `notice.dart` | the barrel, and the five defects in prose |
| `notice_clock.dart` | the one clock seam: `NoticeClock`, `systemNoticeClock`, `DisabledNoticeClock` |
| `notice_policy.dart` | the three timings |
| `notice_kind.dart` | the four severities and the severity rule, in one exhaustive switch |
| `notice_status.dart` | the five connection states and their Turkish labels |
| `notice_state.dart` | `Notice` and `NoticeSnapshot`, both immutable values |
| `notice_controller.dart` | the four rules |
| `notice_strings.dart` | `NoticeTr`, the Turkish catalogue |
| `notice_text.dart` | `noticeSoftBreaks` and `noticeVisibleText` |
| `notice_design.dart` | `NoticePalette` and `NoticeMetrics` |
| `notice_host.dart` | `NoticeHost`, `NoticeLane`, `NoticeSurface`, `NoticeMessage`, `NoticeCloseButton`, `NoticeKeys` |
| `notice_status_bar.dart` | `NoticeStatusBar` |
