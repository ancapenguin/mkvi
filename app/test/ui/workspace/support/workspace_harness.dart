/// The wiring every test in `test/ui/workspace/` builds, in one place.
///
/// The screen under test is the *real* one, over the *real* `ChatController` and
/// `TransferCoordinator`, with the seams `test/support/fakes/` already scripts.
/// Nothing here fakes a widget: a test that measured a layout around a double
/// would be measuring the double.
///
/// Two things are added on top of [FakeChatHarness], and both are deliberate:
///
/// * the **same** [ScriptedChatChannel] and the **same** [ScriptedFileSink] are
///   handed to the transfer coordinator, because that is what a real transport
///   does — one channel carries both kinds of frame, and one rule (a refused
///   transfer leaves nothing on disk) has to hold whether the bytes were going
///   out or coming in;
/// * the notice controller runs on [DisabledNoticeClock], so a notice stays up
///   until a test takes it down. A notice that vanished on its own would make
///   the defect-8 measurement depend on a clock, and the measurement must be
///   about geometry.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/chat/chat.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/file_frame.dart';
import 'package:mkvi/core/protocol/file_transfer.dart';
import 'package:mkvi/core/protocol/text_sanitizer.dart';
import 'package:mkvi/session/names.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/notice/notice.dart';
import 'package:mkvi/ui/workspace/workspace.dart';

import '../../../support/fakes/fakes.dart';
import '../../../support/mkvi_test_app.dart';

/// A well-formed transfer id: 32 copies of one hex letter, so a test can read
/// at a glance which transfer a frame belongs to.
String tid(String letter) => letter * 32;

/// Sixteen distinct hex letters, so a test can mint a different transfer id per
/// row and every one of them parses. A transfer id is 32 lowercase hex
/// characters and the protocol rejects anything else, so `'w' * 32` is not a
/// usable id however convenient it is to type.
const List<String> hexLetters = <String>[
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
];

/// [count] bytes of filler, distinct enough to be recognisable in a file.
List<int> fillerBytes(int count, [int seed = 0]) =>
    List<int>.generate(count, (int i) => (i + seed) % 256);

/// A wire frame exactly as `TransferCoordinator.onFrame` receives one.
Uint8List frameOf(String id, List<int> payload) =>
    FileFrame(id: id, payload: Uint8List.fromList(payload)).toBytes();

/// A `file-offer` frame as the peer would send it.
FileOfferMessage offerFor(
  String id, {
  required int size,
  String name = 'rapor.pdf',
  String mime = 'application/pdf',
}) => FileOfferMessage(id: id, name: safeName(name), mime: safeMime(mime), size: size);

/// The conversation, the transfers and the two notice channels, wired together.
final class WorkspaceHarness {
  /// Builds the harness. [history] seeds the local log, so a screen test can
  /// start from a conversation that already exists.
  WorkspaceHarness({
    bool channelOpen = true,
    List<StoredMessage> history = const <StoredMessage>[],
  }) {
    chat = FakeChatHarness(channelOpen: channelOpen, history: history);
    notice = NoticeController(clock: const DisabledNoticeClock());
    transfers = TransferCoordinator(
      channel: chat.channel,
      sink: chat.files,
      receiver: PeerFileReceiver(),
      idFactory: CountingChatIds.sequence(16).call,
    );
  }

  /// The real [ChatController] and its scripted seams.
  late final FakeChatHarness chat;

  /// The notice and status channels, on a clock that never fires.
  late final NoticeController notice;

  /// The real [TransferCoordinator], over the chat harness's own channel, sink
  /// and an empty receiver.
  late final TransferCoordinator transfers;

  /// The screen under test, over the three controllers above.
  ///
  /// [withTransfers] is `false` for the tests that are about a conversation
  /// with no files in it, which is the state the list is written for.
  WorkspaceScreen screen({
    PeerNameView peer = const PeerNameView(announcedName: 'Ayşe Yılmaz'),
    bool withTransfers = true,
    DateTime? now,
    VoidCallback? onForgetPeer,
    VoidCallback? onRemoveAlias,
  }) => WorkspaceScreen(
    controller: chat.controller,
    notice: notice,
    peer: peer,
    transfers: withTransfers ? transfers : null,
    now: now,
    onForgetPeer: onForgetPeer,
    onRemoveAlias: onRemoveAlias,
  );

  Future<void> dispose() async {
    await transfers.dispose();
    await chat.dispose();
    notice.dispose();
  }
}

/// Disposes a harness from the **end of a widget test's body**.
///
/// A `testWidgets` body runs in a fake-async zone, and `ChatController.dispose`
/// ends with `await _states.close()` — a broadcast stream's done future, which
/// never completes there. The consequence is not a failure but a hang: the
/// teardown sits there until the whole file's ten-minute budget is gone and the
/// only output is a `TimeoutException` naming no test. That was measured, twice:
/// awaiting the dispose hangs, and registering it with `addTearDown` inside
/// `tester.runAsync` hangs as well.
///
/// What does work is calling this while the body is still running, so:
/// ```dart
/// final harness = WorkspaceHarness();
/// ...the test...
/// await disposeHarness(tester, harness);
/// expectNoOverflow(tester);
/// ```
/// [tester.runAsync] is then the escape hatch the binding provides for exactly
/// this, and the harness is fully torn down when the line returns.
Future<void> disposeHarness(
  WidgetTester tester,
  WorkspaceHarness harness,
) async {
  await tester.runAsync(harness.dispose);
}

/// A 320 x 600 dp box, so a wrapping Turkish string has to wrap and a `Row` has
/// to fit, and so a scrollable has a bounded axis.
///
/// `pumpMkvi` hands the widget under test the whole 1280x800 surface, and a
/// `Row` in 1280 dp never overflows however broken it is — so a test in this
/// directory that wants an overflow to be *possible* narrows the column first.
///
/// The height is not decoration either, and the way it is applied is the one
/// thing worth copying: a `Column` hands its **non-flexible** children an
/// *unbounded* main axis, so a `ListView` inside a plain `Column` throws
/// "Vertical viewport was given unbounded height" — measured, and the reason
/// this helper exists in the shape it does. The child therefore goes in through
/// [Expanded], which is exactly what `WorkspaceScreen` does with the same
/// widgets. 600 dp stands for the share of a real window the conversation gets.
///
/// The `DefaultTextStyle` is not decoration either: `pumpMkvi` installs one, but
/// a second `Builder` level under a `Material` still needs it, and a bare `Text`
/// without it renders in Flutter's error style.
Widget workspaceColumn(
  Widget child, {
  double width = 320,
  double height = 600,
}) {
  return Builder(
    builder: (BuildContext context) {
      final AppearanceStyle style = AppearanceStyle.of(context);
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          height: height,
          child: DefaultTextStyle(
            style: style.textTheme.bodyMedium ?? const TextStyle(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[Expanded(child: child)],
            ),
          ),
        ),
      );
    },
  );
}

/// A 320 dp column that is exactly as tall as its content, for content that
/// sizes itself.
///
/// The counterpart to [workspaceColumn], and it exists because of a measured
/// detail of `ConstrainedBox`: a widget handed a **tight** height cannot be
/// capped, whatever its own `maxHeight` says. `BoxConstraints.enforce` clamps
/// the incoming tight `600..600` into the widget's `0..276` and lands on
/// `600..600` — the outer constraint wins. So a [TransferList] inside a
/// fixed-height box measures the box, and its own "two rows tall" cap silently
/// stops applying.
///
/// Anything that sizes itself — a stack of rows, a capped list — goes in here,
/// and anything scrollable that needs a bounded axis goes in [workspaceColumn].
Widget workspaceStack(Widget child, {double width = 320}) {
  return Builder(
    builder: (BuildContext context) {
      final AppearanceStyle style = AppearanceStyle.of(context);
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: DefaultTextStyle(
            style: style.textTheme.bodyMedium ?? const TextStyle(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[child],
            ),
          ),
        ),
      );
    },
  );
}

/// Hands the resolved [AppearanceStyle] to [onStyle] from a real `build`.
///
/// `mkviStyleOf` in `test/support/mkvi_test_app.dart` walks `tester.allElements`
/// and calls `Theme.of` on each one, which registers an inherited-widget
/// dependency from *outside* a build. That is harmless in a test that pumps
/// once and a landmine in a matrix loop, and the harness's own file says so. So
/// a test here reads the palette from a build context, which is the only legal
/// place to read it — and this directory writes its own copy rather than
/// borrowing `test/ui/widgets/support/`, which is that layer's file.
class WorkspaceStyleProbe extends StatelessWidget {
  /// Wraps [child] and reports the style it is painted with.
  const WorkspaceStyleProbe({
    super.key,
    required this.onStyle,
    required this.child,
  });

  /// Called on every build, from inside one.
  final ValueChanged<AppearanceStyle> onStyle;

  /// The widget under test.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onStyle(AppearanceStyle.of(context));
    return child;
  }
}

/// The notice palette for a preference set, resolved outside any widget tree.
///
/// The header and the screen take a [NoticePalette] rather than reading roles
/// themselves, so a test that builds either of them has to hand one over. This
/// is the same bridge the screen uses at runtime
/// ([workspaceNoticePalette]) applied to a resolved appearance, which is why a
/// header test and a screen test paint the same notice.
NoticePalette workspacePaletteFor(AppearanceSettings settings) =>
    workspaceNoticePalette(mkviAppearance(settings: settings).style);

/// The notice measurements for a preference set, resolved outside any widget
/// tree. Same reasoning as [workspacePaletteFor].
NoticeMetrics workspaceMetricsFor(AppearanceSettings settings) =>
    workspaceNoticeMetrics(mkviAppearance(settings: settings).style);

/// What a notice's body actually says, with the soft breaks taken out.
///
/// `NoticeHost` paints `noticeSoftBreaks(text)`, which inserts zero-width spaces
/// so a 300-character path has somewhere to break. The rendered `Text` is
/// therefore not the string the controller was given, and a test that looks for
/// the sentence with `find.text` finds nothing. `noticeVisibleText` is the
/// harness's own inverse of that shaping, and this is the same one-liner
/// `test/ui/notice/notice_host_test.dart` uses.
String noticeBodyText(WidgetTester tester) {
  final Text body = tester.widget<Text>(
    find.descendant(
      of: find.byKey(NoticeKeys.body),
      matching: find.byType(Text),
    ),
  );
  return noticeVisibleText(body.data!);
}

/// Every string the pumped tree actually paints, in one list.
///
/// Used by the tests that claim "the path is not on screen": asserting on one
/// `Text` widget is a claim about a widget, and this is a claim about the
/// screen. Rich text and a `Text.rich` are read through their semantics label,
/// which is what a screen reader would get anyway.
List<String> paintedText(WidgetTester tester) => <String>[
  for (final Text text in tester.widgetList<Text>(find.byType(Text)))
    if (text.data != null) text.data! else (text.semanticsLabel ?? ''),
];
