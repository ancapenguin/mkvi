/// One assembled call screen per test: a real [CallMachine] on a controlled
/// clock, a real [MediaController] with every seam faked, and the real
/// [CallUiHost] that drives both.
///
/// ## Why it exists
///
/// `ROADMAP.md`'s whole test harness rests on two claims that are easy to state
/// and easy to fake:
///
/// * the answer screen is on screen **because** the machine is `incoming`, and
/// * the media opened **after** the peer was told.
///
/// A fixture that hand-built a [CallUiSnapshot] would prove neither, and would
/// pass with a screen that ignored the machine entirely. So this file wires the
/// real three together and adds exactly two things on top: the single seam
/// [CallUiHost.sync] needs when the machine is not the host's own listener, and a
/// Turkish peer name long enough to have to wrap in a narrow window.
///
/// ## The clock seam
///
/// [FakeCallClock] is the call layer's clock *and* its timer registry, so
/// `harness.clock.call` is what the host reads for the countdown and
/// `harness.advance(…)` is what fires the 45 s ring timeout. There is therefore
/// **one** 45 in the whole fixture: `harness.machine.ringTimeout` and the number
/// the answer screen prints come from the same field.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/call/call.dart';
import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/media/media.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/call/call.dart';

import '../../../support/fakes/fakes.dart';
import '../../../support/mkvi_test_app.dart';

/// A call screen and the two layers under it.
final class CallScreenFixture {
  CallScreenFixture({
    bool withMedia = true,
    List<DisplaySource>? sources,
    MediaDeviceSnapshot? devices,
  }) {
    call = FakeCallHarness();
    // One snapshot, shared with the picker: the two device lists the media
    // controller does *not* publish are injected, and they have to be the same
    // lists the controller validates against, or a row can offer an id the
    // controller refuses — which is correct behaviour and makes for a confusing
    // test.
    final MediaDeviceSnapshot snapshot = devices ?? fakeDeviceList();
    if (withMedia) {
      media = FakeMediaHarness(devices: snapshot, sources: sources);
    }
    host = CallUiHost(
      machine: call.machine,
      // The call layer's own clock, so the countdown and the ring timeout are
      // measured on one scale and `advance` moves both.
      now: call.clock.call,
      media: media?.controller,
      sendFrame: frames.add,
      inventory: CallDeviceInventory(
        cameras: snapshot.cameras,
        microphones: snapshot.microphones,
      ),
    );
    addTearDown(dispose);
  }

  /// The call layer: a real machine, a real clock, a real 45 s ring timer.
  late final FakeCallHarness call;

  /// The media layer, faked at every seam. `null` for a screen measured with no
  /// capture backend at all.
  FakeMediaHarness? media;

  /// The host, i.e. the thing the screen renders from.
  late final CallUiHost host;

  /// Every frame the host handed to [CallUiHost.sendFrame], in order.
  ///
  /// A second log beside `FakeCallHarness.sent`, and not a replacement for it:
  /// `sent` is what the **machine** produced, this is what reached the wire
  /// **through the screen's own executor**. A screen that dropped a frame would
  /// leave the first list full and the second one empty.
  final List<PeerControlMessage> frames = <PeerControlMessage>[];

  /// A peer name long enough to wrap twice in a 400 dp window, which is the width
  /// `mkviPhoneWindowSize` gives and the one a Turkish name has to survive.
  static const String peerName = 'Ayşe Nur Karadeniz — Masaüstü';

  /// Every sent frame of type [T].
  List<T> framesOf<T extends PeerControlMessage>() =>
      frames.whereType<T>().toList(growable: false);

  // -- rendering --------------------------------------------------------------

  /// Renders the whole call screen and hands the resolved style to [onStyle].
  Future<void> pump(
    WidgetTester tester, {
    AppearanceSettings settings = AppearanceSettings.initial,
    Brightness platformBrightness = Brightness.dark,
    Size size = mkviWindowSize,
    bool settle = true,
    bool showDevicePicker = false,
    required void Function(CallUiHost host) onStyle,
  }) async {
    await pumpWidget(
      tester,
      CallScreen(
        host: host,
        peerName: peerName,
        showDevicePicker: showDevicePicker,
      ),
      settings: settings,
      platformBrightness: platformBrightness,
      size: size,
      settle: settle,
      onStyle: (AppearanceStyle _) => onStyle(host),
    );
  }

  /// Renders [child] — a single widget of the call screen, or a host-free
  /// sample — inside the real themed app and hands the resolved style to
  /// [onStyle].
  ///
  /// [onStyle] is called from inside a `build`, which is the only legal place to
  /// read an [AppearanceStyle]: `mkviStyleOf` walks `tester.allElements` and
  /// registers an inherited-widget dependency from outside a build, which is a
  /// landmine the moment a matrix loop pumps twice.
  Future<void> pumpWidget(
    WidgetTester tester,
    Widget child, {
    AppearanceSettings settings = AppearanceSettings.initial,
    Brightness platformBrightness = Brightness.dark,
    Size size = mkviWindowSize,
    bool settle = true,
    required void Function(AppearanceStyle style) onStyle,
  }) async {
    await pumpMkvi(
      tester,
      Builder(
        builder: (BuildContext context) {
          onStyle(AppearanceStyle.of(context));
          return child;
        },
      ),
      settings: settings,
      platformBrightness: platformBrightness,
      size: size,
      settle: settle,
    );
  }

  /// Pumps [child] once per [matrix], unmounting between each.
  ///
  /// The screen is rebuilt for every combination because the host is a listener
  /// and a fresh tree has to attach to it again; [unmountMkvi] is what keeps
  /// `InheritedElement.notifyClients` from throwing.
  Future<void> pumpMatrix(
    WidgetTester tester,
    Widget Function(AppearanceSettings settings) build, {
    required Iterable<AppearanceSettings> matrix,
    Size size = mkviWindowSize,
    Brightness platformBrightness = Brightness.dark,
    void Function(AppearanceSettings settings, CallUiHost host)? each,
  }) async {
    await pumpMkviMatrix(
      tester,
      (AppearanceSettings settings) => build(settings),
      matrix: matrix,
      size: size,
      platformBrightness: platformBrightness,
      each: (AppearanceSettings settings) => each?.call(settings, host),
    );
  }

  // -- driving ----------------------------------------------------------------

  /// Moves the call clock and lets the host hear about it.
  ///
  /// This is the seam, and it is one line: the ring timeout fires *inside* the
  /// machine, so a host whose machine reports to somebody else has to be told
  /// that something changed. In production [CallUiHost.onTransition] is the
  /// machine's own listener and does this by itself.
  void advance(Duration by) {
    call.advance(by);
    host.sync();
  }

  /// Puts the machine in the callee seat with a call already ringing.
  String ring([CallMode mode = CallMode.audio]) {
    final String id = call.ids.call();
    call.ring(id, mode);
    host.sync();
    return id;
  }

  /// Puts the machine in the caller seat.
  String dial(CallMode mode) {
    final String id = call.ids.call();
    call.dial(mode, id: id);
    host.sync();
    return id;
  }

  /// Answers the ringing screen and lets the media step that follows it finish.
  Future<void> accept(WidgetTester tester) async {
    host.accept();
    await tester.pumpAndSettle();
  }

  /// A connected call with media on the senders: open, ring, accept, publish.
  Future<void> connect(WidgetTester tester, [CallMode mode = CallMode.video]) async {
    await openMedia();
    ring(mode);
    await accept(tester);
  }

  /// Opens the media controller, i.e. builds the three pre-negotiated senders.
  ///
  /// Required before any accept that is expected to *reach* `connected`: without
  /// it [MediaController.startCall] answers `connectionNotReady` and the machine
  /// declines the call with that reason — which is correct behaviour and is what
  /// `test/media/media_call_start_test.dart` pins.
  Future<void> openMedia() async {
    await media?.open();
  }

  // -- teardown ---------------------------------------------------------------

  /// Cancels the countdown and the machine's timers.
  ///
  /// Synchronous on purpose: a widget test verifies that no `Timer` is still
  /// pending, and the countdown is the one this package owns.
  void dispose() {
    host.dispose();
    call.dispose();
  }

  /// [dispose], plus the media layer's four streams.
  Future<void> disposeAsync() async {
    dispose();
    await media?.dispose();
  }
}
