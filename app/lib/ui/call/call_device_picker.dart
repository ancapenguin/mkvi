/// The three lists a user picks from mid-call: which camera, which microphone,
/// and which screen or window to share.
///
/// ## Why this widget exists at all
///
/// **There is no native display picker on Windows** in `flutter_webrtc` 1.6.2, and
/// `MediaController.availableDisplaySources` is public API for exactly that
/// reason — see [DisplaySource]'s own header. So the third list here is not a
/// convenience: on Windows it is the only way a user can choose what to share, and
/// a build that hid the enumeration would have no share target at all.
///
/// The other two lists are not decoration either. [MediaController.switchCamera]
/// re-captures rather than calling `Helper.switchCamera`, which ignores its
/// `deviceId` off the web branch and whose Windows handler is literally
/// `result->NotImplemented()`; and `switchMicrophone` refuses an id the OS does
/// not have, because a `getUserMedia` with an unknown audio `deviceId` matches
/// nothing and quietly keeps the **previous** microphone while reporting the
/// requested one. A switch that appears to work and does not is worse than one
/// that refuses — so the picker only ever hands over an id the controller has
/// already seen in its device list.
///
/// ## What it does *not* do
///
/// It owns no media and starts nothing. Every row reports an id upwards and the
/// host runs the operation, so the ordering contract
/// `accept → [SendFrame, PublishMedia]` cannot be broken by a list of radio
/// buttons.
library;

import 'package:flutter/material.dart';
import 'package:mkvi/media/media.dart';
import 'package:mkvi/settings/settings.dart';
import 'package:mkvi/ui/widgets/widgets.dart';

import 'call_strings.dart';

/// Which of the three lists a key belongs to.
enum CallDeviceKind {
  /// `MediaState.cameraDeviceId`, and `MediaController.switchCamera`.
  camera,

  /// `MediaState.microphoneDeviceId`, and `MediaController.switchMicrophone`.
  microphone,

  /// `MediaState.screenSourceId`, and `MediaController.startScreenShare`.
  display,
}

/// The keys the picker's rows answer to.
abstract final class CallDevicePickerKeys {
  /// The picker itself.
  static const Key panel = Key('mkvi.call.devices.panel');

  /// The nth row of [kind]'s list, in the order the caller passed the devices.
  static Key row(CallDeviceKind kind, int index) =>
      Key('mkvi.call.devices.${kind.name}.$index');

  /// The "nothing here" block of [kind].
  static Key empty(CallDeviceKind kind) =>
      Key('mkvi.call.devices.${kind.name}.empty');
}

/// The device picker.
///
/// Three sections, each with its own list, each with its own empty state — a
/// Windows machine with no camera is an ordinary machine, and "no camera" printed
/// as nothing at all is how a user concludes the app is broken.
class CallDevicePicker extends StatelessWidget {
  /// Creates the picker.
  const CallDevicePicker({
    super.key,
    this.cameras = const <MediaDevice>[],
    this.microphones = const <MediaDevice>[],
    this.displaySources = const <DisplaySource>[],
    this.cameraDeviceId,
    this.microphoneDeviceId,
    this.displaySourceId,
    this.onSelectCamera,
    this.onSelectMicrophone,
    this.onStartShare,
    this.gapStep = '4',
  });

  /// What the OS enumerates for `videoinput`, in its own order.
  final List<MediaDevice> cameras;

  /// What the OS enumerates for `audioinput`, in its own order.
  final List<MediaDevice> microphones;

  /// What `DesktopCapturer.getSources` reports, in its own order.
  final List<DisplaySource> displaySources;

  /// Which camera is publishing, from `MediaState.cameraDeviceId`.
  final String? cameraDeviceId;

  /// Which microphone is publishing, from `MediaState.microphoneDeviceId`.
  final String? microphoneDeviceId;

  /// Which target is being shared, from `MediaState.screenSourceId`.
  final String? displaySourceId;

  /// Called with a camera id. `null` leaves the picker inert, which is what a
  /// screen that is not in a call wants.
  final ValueChanged<String>? onSelectCamera;

  /// Called with a microphone id.
  final ValueChanged<String>? onSelectMicrophone;

  /// Called with a display-source id, to start sharing it.
  final ValueChanged<String>? onStartShare;

  /// The gap between the three sections, as a `space.steps` name.
  final String gapStep;

  @override
  Widget build(BuildContext context) {
    final AppearanceStyle style = AppearanceStyle.of(context);
    final ValueChanged<String>? selectCamera = onSelectCamera;
    final ValueChanged<String>? selectMicrophone = onSelectMicrophone;
    final ValueChanged<String>? startShare = onStartShare;

    return SingleChildScrollView(
      child: Column(
        key: CallDevicePickerKeys.panel,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _section(
            style,
            CallDeviceKind.camera,
            title: CallUiTr.cameraSection,
            entries: <_DeviceEntry>[
              for (final MediaDevice device in cameras)
                _DeviceEntry(id: device.id, label: device.label),
            ],
            selectedId: cameraDeviceId,
            onSelected: selectCamera,
            empty: CallUiTr.noCameras,
          ),
          SizedBox(height: style.gap(gapStep)),
          _section(
            style,
            CallDeviceKind.microphone,
            title: CallUiTr.microphoneSection,
            entries: <_DeviceEntry>[
              for (final MediaDevice device in microphones)
                _DeviceEntry(id: device.id, label: device.label),
            ],
            selectedId: microphoneDeviceId,
            onSelected: selectMicrophone,
            empty: CallUiTr.noMicrophones,
          ),
          SizedBox(height: style.gap(gapStep)),
          _section(
            style,
            CallDeviceKind.display,
            title: CallUiTr.displaySection,
            entries: <_DeviceEntry>[
              for (final DisplaySource source in displaySources)
                _DeviceEntry(
                  id: source.id,
                  label: source.name,
                  description: source.kind == DisplaySourceKind.screen
                      ? CallUiTr.displayScreenKind
                      : CallUiTr.displayWindowKind,
                ),
            ],
            selectedId: displaySourceId,
            onSelected: startShare,
            empty: CallUiTr.noDisplaySources,
          ),
        ],
      ),
    );
  }

  /// One section: a panel with a heading and either its rows or its empty state.
  Widget _section(
    AppearanceStyle style,
    CallDeviceKind kind, {
    required String title,
    required List<_DeviceEntry> entries,
    required String? selectedId,
    required ValueChanged<String>? onSelected,
    required String empty,
  }) {
    return MkviPanel.soft(
      title: title,
      // `surfaceSoft` is the role the rows' own padding is measured against, so
      // the surface rule travels with the section rather than with a call site.
      child: entries.isEmpty
          ? MkviEmptyState(
              key: CallDevicePickerKeys.empty(kind),
              title: empty,
              icon: Icons.devices_other_rounded,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int index = 0; index < entries.length; index += 1)
                  MkviOptionRow<String>(
                    key: CallDevicePickerKeys.row(kind, index),
                    value: entries[index].id,
                    groupValue: selectedId,
                    onChanged: onSelected == null
                        ? (String? _) {}
                        : (String? value) {
                            if (value != null) onSelected(value);
                          },
                    label: entries[index].label,
                    description: entries[index].description,
                    enabled: onSelected != null,
                  ),
              ],
            ),
    );
  }
}

/// One row's data, flattened so the three sections share one list-building code
/// path instead of three near-identical ones.
final class _DeviceEntry {
  const _DeviceEntry({
    required this.id,
    required this.label,
    this.description,
  });

  final String id;
  final String label;
  final String? description;
}
