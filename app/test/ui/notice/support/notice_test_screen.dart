/// The palette and the screen the widget tests lay out.
///
/// The colours are the `midnight` theme, `blue` accent values of
/// `design/generated/tokens.g.dart` (`mkviMidnightBlue`, lines 925-957), copied
/// here because `app` cannot import the generated token file: the package has no
/// dependency on `design/`, and adding one is not this layer's to do (see the
/// orphan comment in `app/pubspec.yaml`).
///
/// So the *values* are the design system's and the *wiring* is a one-line bridge
/// in the app root — see `notice_design.dart` for the `NoticePalette` that bridge
/// returns. What is being tested here is that the layer paints from the palette
/// it is handed, which is the property that makes the bridge a formality later.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/ui/notice/notice.dart';

import 'fake_notice_clock.dart';

/// `mkviMidnightBlue`, role by role.
const NoticePalette midnightBluePalette = NoticePalette(
  surface: Color(0xFF18212D), // surfaceOverlay
  onSurface: Color(0xFFF2F6FB), // text
  muted: Color(0xFFB6C2D2), // textMuted
  border: Color(0xFF7B8698), // border
  accent: Color(0xFF2665EF), // accent
  success: Color(0xFF4ADE80), // success
  warning: Color(0xFFFBBF24), // warning
  danger: Color(0xFFF87171), // danger
  focusRing: Color(0xFFC9D9F9), // focusRing
  shadow: Color(0x8C000000), // shadow3
);

/// The screen a notice test lays out: a message list, the notice lane, and a
/// composer with a send button — the three things the reported bug was about.
///
/// The composer is a real [TextField] with a real [TextEditingController] and a
/// real send button, because "nothing could be typed" is a claim about input, and
/// a test that only measures rectangles cannot make it. Tapping the send button
/// must also be possible, which is the other half of the report.
class NoticeTestScreen extends StatelessWidget {
  const NoticeTestScreen({
    super.key,
    required this.controller,
    required this.text,
    required this.onSend,
    this.palette = midnightBluePalette,
    this.metrics = const NoticeMetrics(),
  });

  /// The channel to render.
  final NoticeController controller;

  /// The composer's controller, so a test can assert what was typed.
  final TextEditingController text;

  /// Called when the send button is pressed.
  final VoidCallback onSend;

  /// Every colour.
  final NoticePalette palette;

  /// The measurements.
  final NoticeMetrics metrics;

  /// The key on the composer row, so a test can measure it as one box.
  static const Key composer = Key('mkvi.test.composer');

  /// The key on the send button, i.e. the control the toast used to cover.
  static const Key send = Key('mkvi.test.send');

  /// The key on the message list, i.e. what a notice is supposed to shrink.
  static const Key list = Key('mkvi.test.list');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            const Expanded(
              child: ColoredBox(
                key: list,
                color: Color(0xFF000000),
                child: Center(child: Text('mesajlar')),
              ),
            ),
            // The placement that makes overlap impossible: the lane is an
            // in-flow sibling between the list and the composer.
            NoticeHost(
              controller: controller,
              palette: palette,
              metrics: metrics,
            ),
            Padding(
              key: composer,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: text,
                      decoration: const InputDecoration(hintText: 'mesaj'),
                    ),
                  ),
                  ElevatedButton(
                    key: send,
                    onPressed: onSend,
                    child: const Text('Gönder'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A controller, a fake clock and a teardown, so a test cannot leak one.
class NoticeHarness {
  /// Builds a controller on a clock the caller can step.
  factory NoticeHarness({NoticePolicy policy = const NoticePolicy()}) {
    final FakeNoticeClock clock = FakeNoticeClock();
    return NoticeHarness._(
      clock,
      NoticeController(clock: clock, policy: policy),
      policy,
    );
  }

  const NoticeHarness._(this.clock, this.controller, this.policy);

  /// The clock the test steps.
  final FakeNoticeClock clock;

  /// The controller under test.
  final NoticeController controller;

  /// The timings in force.
  final NoticePolicy policy;

  /// Disposes the controller. Register it with `addTearDown` right after
  /// building the harness.
  void dispose() => controller.dispose();
}
