/// The device picker, and the three reasons it exists at all.
///
/// ## Why the third list is the interesting one
///
/// **There is no native display picker on Windows** in `flutter_webrtc` 1.6.2:
/// `getDisplayMedia` takes a `video/deviceId.exact` constraint and the only way
/// to learn a legal value is `DesktopCapturer.getSources`, which
/// [MediaController.availableDisplaySources] exposes for exactly this reason
/// (see `DisplaySource`'s own header). So the share-target list is not a
/// convenience — a build that hid the enumeration would have no picker at all,
/// and a build that guessed an id would share a window the user did not choose.
///
/// ## Why the other two are not decoration either
///
/// * `MediaController.switchCamera` **re-captures** rather than calling
///   `Helper.switchCamera`, which ignores its `deviceId` off the web branch and
///   whose Windows handler is literally `NotImplemented()`. A camera switch that
///   quietly keeps the old camera is worse than one that refuses, so the picker
///   only ever hands over an id the controller has already seen.
/// * `MediaController.switchMicrophone` **refuses** an id the OS does not have,
///   because `getUserMedia` with an unknown audio `deviceId` matches nothing and
///   returns a track that keeps the *previous* microphone while reporting the
///   requested one (`flutter_media_stream.cc:219-228`, `:267-269`).
///
/// ## The share phase
///
/// The picker's other job is the phase. A share that starts and never delivers a
/// frame is upstream issue #2137, and `ScreenShareWatchdog` is the only thing in
/// the application that can see it — so the tests here drive the watch to
/// `stalled` and assert the Turkish sentence that names the fix.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mkvi/media/media.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/call/call.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import '../../support/fakes/fakes.dart';
import '../../support/mkvi_test_app.dart';
import 'support/accessibility_floor.dart';
import 'support/call_screen_fixture.dart';

/// The picker is where the [callUiExemptKinds] exemption actually bites — a
/// `Radio` is named by its row's text, not by itself — so the floor is spelled
/// out here where that is visible.
Future<void> expectPickerSound(WidgetTester tester) async {
  expectNoOverflow(tester);
  await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
  expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
}

/// Two cameras, two microphones, one screen and one window — a machine with more
/// than one of each, which is the only case in which "which one?" is a question.
const List<MediaDevice> twoCameras = <MediaDevice>[
  MediaDevice(id: 'cam-1', label: 'Kamera (Integrated Webcam)', kind: MediaDeviceKind.camera),
  MediaDevice(id: 'cam-2', label: 'Kamera (USB HD Webcam)', kind: MediaDeviceKind.camera),
];

const List<MediaDevice> twoMicrophones = <MediaDevice>[
  MediaDevice(
    id: 'mic-1',
    label: 'Mikrofon (Realtek Audio)',
    kind: MediaDeviceKind.microphone,
  ),
  MediaDevice(
    id: 'mic-2',
    label: 'Mikrofon (Webcam Mic)',
    kind: MediaDeviceKind.microphone,
  ),
];

/// The snapshot both layers of the fixture are built from, so the picker's rows
/// and the media controller's device list are the same list.
const MediaDeviceSnapshot richDeviceList = MediaDeviceSnapshot(
  microphones: twoMicrophones,
  cameras: twoCameras,
);

/// A picker on its own, reporting which id each list handed upwards.
Widget pickerSample({
  List<MediaDevice> cameras = twoCameras,
  List<MediaDevice> microphones = twoMicrophones,
  List<DisplaySource>? sources,
  String? cameraDeviceId,
  String? microphoneDeviceId,
  String? displaySourceId,
  void Function(String which, String id)? onSelected,
}) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: CallDevicePicker(
      cameras: cameras,
      microphones: microphones,
      displaySources: sources ?? fakeDisplaySources(),
      cameraDeviceId: cameraDeviceId,
      microphoneDeviceId: microphoneDeviceId,
      displaySourceId: displaySourceId,
      onSelectCamera: (String id) => onSelected?.call('camera', id),
      onSelectMicrophone: (String id) => onSelected?.call('microphone', id),
      onStartShare: (String id) => onSelected?.call('display', id),
    ),
  );
}

void main() {
  group('the three lists', () {
    testWidgets('each section shows every device the OS reported', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      await fixture.pumpWidget(
        tester,
        pickerSample(),
        onStyle: (AppearanceStyle _) {},
      );

      for (final String label in <String>[
        'Kamera (Integrated Webcam)',
        'Kamera (USB HD Webcam)',
        'Mikrofon (Realtek Audio)',
        'Mikrofon (Webcam Mic)',
        'Tüm Ekranlar',
        'Not Defteri',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label is listed');
      }
      expect(find.text(CallUiTr.cameraSection), findsOneWidget);
      expect(find.text(CallUiTr.microphoneSection), findsOneWidget);
      expect(find.text(CallUiTr.displaySection), findsOneWidget);
      expect(
        find.byType(MkviOptionRow<String>),
        findsNWidgets(6),
        reason: 'six rows, one per device, and no invented ones',
      );
      expect(find.byKey(CallDevicePickerKeys.empty(CallDeviceKind.camera)), findsNothing);
      await expectPickerSound(tester);
    });

    testWidgets('a machine with nothing to pick says so in Turkish', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      await fixture.pumpWidget(
        tester,
        pickerSample(
          cameras: const <MediaDevice>[],
          microphones: const <MediaDevice>[],
          sources: const <DisplaySource>[],
        ),
        onStyle: (AppearanceStyle _) {},
      );

      expect(find.text(CallUiTr.noCameras), findsOneWidget);
      expect(find.text(CallUiTr.noMicrophones), findsOneWidget);
      expect(find.text(CallUiTr.noDisplaySources), findsOneWidget);
      for (final CallDeviceKind kind in CallDeviceKind.values) {
        expect(
          find.byKey(CallDevicePickerKeys.empty(kind)),
          findsOneWidget,
          reason: 'the $kind list says it is empty rather than showing nothing',
        );
      }
      expect(find.byType(MkviOptionRow<String>), findsNothing);
      await expectPickerSound(tester);
    });

    testWidgets('the publishing device is the chosen one', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      await fixture.pumpWidget(
        tester,
        pickerSample(
          cameraDeviceId: 'cam-2',
          microphoneDeviceId: 'mic-1',
          displaySourceId: 'window-3',
        ),
        onStyle: (AppearanceStyle _) {},
      );

      // The publishing id is carried by the `RadioGroup` the row creates, not by
      // the `Radio` itself: a `Radio` inside a group takes its selection from the
      // group, and reading `Radio.groupValue` says nothing.
      String? groupValueAt(CallDeviceKind kind, int index) => tester
          .widget<RadioGroup<String>>(
            find.descendant(
              of: find.byKey(CallDevicePickerKeys.row(kind, index)),
              matching: find.byType(RadioGroup<String>),
            ),
          )
          .groupValue;

      expect(
        groupValueAt(CallDeviceKind.camera, 0),
        'cam-2',
        reason: 'the row carries the id, so a duplicate label cannot be confused',
      );
      expect(
        groupValueAt(CallDeviceKind.microphone, 0),
        'mic-1',
      );
      expect(
        groupValueAt(CallDeviceKind.display, 1),
        'window-3',
      );
      // And the rows really do carry those ids, not just a group value.
      final List<String> cameraIds = <String>[
        for (int index = 0; index < twoCameras.length; index += 1)
          tester
              .widget<Radio<String>>(
                find.descendant(
                  of: find.byKey(
                    CallDevicePickerKeys.row(CallDeviceKind.camera, index),
                  ),
                  matching: find.byType(Radio<String>),
                ),
              )
              .value,
      ];
      expect(cameraIds, <String>['cam-1', 'cam-2']);
      await expectPickerSound(tester);
    });

    testWidgets('every row is a control with a name and a 44 dp target', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      late AppearanceStyle seen;
      await fixture.pumpWidget(
        tester,
        pickerSample(),
        onStyle: (AppearanceStyle style) => seen = style,
      );

      for (final CallDeviceKind kind in CallDeviceKind.values) {
        final int rows = switch (kind) {
          CallDeviceKind.camera => twoCameras.length,
          CallDeviceKind.microphone => twoMicrophones.length,
          CallDeviceKind.display => 2,
        };
        for (int index = 0; index < rows; index += 1) {
          expectHitTarget(
            tester,
            find.byKey(CallDevicePickerKeys.row(kind, index)),
            style: seen,
          );
        }
      }
      expect(seen.hitTargetMin, 44);
      await expectPickerSound(tester);
    });
  });

  group('choosing hands an id upwards and nothing else', () {
    testWidgets('the picker owns no media: it reports, the host acts', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      final List<String> chosen = <String>[];
      await fixture.pumpWidget(
        tester,
        pickerSample(
          onSelected: (String which, String id) => chosen.add('$which:$id'),
        ),
        onStyle: (AppearanceStyle _) {},
      );

      await tester.tap(find.byKey(CallDevicePickerKeys.row(CallDeviceKind.camera, 1)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(CallDevicePickerKeys.row(CallDeviceKind.microphone, 0)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CallDevicePickerKeys.row(CallDeviceKind.display, 1)));
      await tester.pumpAndSettle();

      expect(chosen, <String>['camera:cam-2', 'microphone:mic-1', 'display:window-3']);
      expect(
        fixture.media,
        isNull,
        reason:
            'the sample ran with no media layer at all, which is the proof that '
            'the list is inert on its own',
      );
      await expectPickerSound(tester);
    });

    testWidgets('switching a camera re-captures and never negotiates', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(
        devices: richDeviceList,
      );
      await fixture.openMedia();
      await fixture.media!.controller.enableCamera(deviceId: 'cam-1');
      expect(fixture.media!.controller.state.cameraDeviceId, 'cam-1');

      await fixture.host.selectCamera('cam-2');
      await tester.pumpAndSettle();

      expect(
        fixture.media!.controller.state.cameraDeviceId,
        'cam-2',
        reason: 'the track the OS handed back carries the second camera label',
      );
      expect(
        fixture.media!.controller.negotiationCount,
        1,
        reason:
            'still 1 after `open`: a camera switch is a `replaceTrack`, never a '
            'new offer. `Helper.switchCamera` would have been `NotImplemented` '
            'on Windows.',
      );
      expect(fixture.media!.orphanedTracks, isEmpty);
      await expectPickerSound(tester);
    });

    testWidgets('switching a microphone re-points the capture, not the track', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      await fixture.media!.controller.startCall(video: false);

      await fixture.host.selectMicrophone('mic-1');
      await tester.pumpAndSettle();

      expect(
        fixture.media!.capture.selectedInputs,
        <String>['mic-1'],
        reason:
            '`selectAudioInput` is the one device switch the Windows native '
            'handler validates; a fresh `getUserMedia` would have kept the old '
            'microphone while reporting the new id',
      );
      expect(fixture.media!.controller.state.microphoneDeviceId, 'mic-1');
      await expectPickerSound(tester);
    });

    testWidgets('an id the OS does not have is refused, not silently kept', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      await fixture.media!.controller.startCall(video: false);
      await fixture.host.selectMicrophone('mic-1');
      await tester.pumpAndSettle();

      await fixture.host.selectMicrophone('mic-does-not-exist');
      await tester.pumpAndSettle();

      expect(
        fixture.media!.capture.selectedInputs,
        <String>['mic-1'],
        reason: 'the native layer was never asked about the unknown id',
      );
      expect(fixture.media!.controller.state.microphoneDeviceId, 'mic-1');
      expect(
        fixture.media!.controller.state.fault,
        const MediaFault(MediaFaultKind.deviceNotFound, MediaSourceKind.microphone),
      );
      expect(
        fixture.media!.controller.state.fault!.message,
        MediaTexts.microphoneNotFound,
        reason: 'and the user is told in Turkish, with the fix in the sentence',
      );
      await expectPickerSound(tester);
    });
  });

  group('the share phase, which only the watchdog can see', () {
    testWidgets('a share that produces a frame is reported live', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      // The counter is declared *before* the share, so the first poll sees a
      // frame: upstream reports success for a track that never encodes anything,
      // and this is the only place in the app that can tell the two apart.
      fixture.media!.stats.declare(screenSenderId, 1);

      await fixture.host.toggleScreenShare(sourceId: 'window-3');
      await tester.pumpAndSettle();

      expect(
        fixture.media!.controller.state.screenShare,
        ScreenSharePhase.live,
      );
      expect(fixture.media!.phases, contains(ScreenSharePhase.waitingForFirstFrame));
      expect(fixture.media!.phases, isNot(contains(ScreenSharePhase.stalled)));
      expect(
        fixture.media!.controller.state.screenSourceName,
        'Not Defteri',
        reason: 'the app can always say what it is actually sharing',
      );
      expect(
        fixture.media!.capture.shared.single.id,
        'window-3',
        reason: 'the id the user chose is the id that was captured',
      );
      await expectPickerSound(tester);
    });

    testWidgets('a share that never produces a frame says so, in Turkish', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      // Frames stay at 0, which is the default this harness ships: upstream issue
      // #2137 is exactly this case.
      fixture.media!.stats.declare(screenSenderId, 0);

      await fixture.host.toggleScreenShare(sourceId: 'screen-0');
      await tester.pumpAndSettle();

      expect(
        fixture.media!.controller.state.screenShare,
        ScreenSharePhase.stalled,
        reason:
            'a track that resolved successfully and never encodes a frame is '
            'indistinguishable from a working one for as long as the plugin\'s '
            'own API is concerned',
      );
      expect(
        fixture.media!.phases,
        contains(ScreenSharePhase.waitingForFirstFrame),
        reason: 'and "waiting" was on screen from the moment it was attached',
      );
      expect(
        fixture.media!.controller.state.screenShare.label,
        MediaTexts.screenShareStalled,
      );
      expect(
        MediaTexts.screenShareStalled,
        contains('öne getirip'),
        reason: 'the sentence names the remedy, which is the whole point of it',
      );
      await expectPickerSound(tester);
    });

    testWidgets('stopping the share releases the track and the phase', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture();
      await fixture.openMedia();
      fixture.media!.stats.declare(screenSenderId, 1);
      await fixture.host.toggleScreenShare(sourceId: 'screen-0');
      await tester.pumpAndSettle();
      expect(fixture.media!.controller.state.screenShare.isAttached, isTrue);

      await fixture.host.toggleScreenShare();
      await tester.pumpAndSettle();

      expect(
        fixture.media!.controller.state.screenShare,
        ScreenSharePhase.idle,
      );
      expect(
        fixture.media!.orphanedTracks,
        isEmpty,
        reason: 'the screen capture is stopped, not left running',
      );
      expect(fixture.media!.controller.state.screenSourceId, isNull);
      await expectPickerSound(tester);
    });
  });

  group('the picker survives the matrix', () {
    testWidgets('no overflow in any theme/accent combination at any window', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => pickerSample(),
          matrix: mkviAppearanceMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });

    testWidgets('no overflow at both ends of the type slider', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => pickerSample(),
          matrix: mkviScaleMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });

    testWidgets('no overflow with either accessibility switch on', (
      WidgetTester tester,
    ) async {
      final CallScreenFixture fixture = CallScreenFixture(withMedia: false);
      for (final Size window in mkviWindowSizes) {
        await fixture.pumpMatrix(
          tester,
          (AppearanceSettings settings) => pickerSample(),
          matrix: mkviAccessibilityMatrix(),
          size: window,
        );
        expectNoOverflow(tester);
        await expectEveryControlIsLabelled(tester, allowUnlabelled: callUiExemptKinds);
        expectEveryControlIsNamed(tester, allowUnlabelled: callUiExemptKinds);
      }
    });
  });
}
