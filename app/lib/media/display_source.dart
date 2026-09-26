/// What kind of thing can be shared, mirroring the plugin's `SourceType`.
///
/// [SourceType] is re-exported by the plugin as an enum of its own; MKVI does not
/// leak plugin enums into its own API, because a caller that has to import
/// `flutter_webrtc` to name a screen share has lost the point of the seam.
enum DisplaySourceKind { screen, window }

/// One shareable target, as `DesktopCapturer.getSources` reported it.
///
/// ## Why MKVI builds this list itself
///
/// There is **no native display picker on Windows** in
/// `flutter_webrtc` 1.6.2+hotfix.3. `getDisplayMedia` takes a
/// `video.deviceId.exact` constraint
/// (`common/cpp/src/flutter_screen_capture.cc:186-198`) and the only way to
/// learn a legal value is `DesktopCapturer.getSources({types: [...]})`. In a
/// browser the user picks from an OS dialog; in a Flutter desktop build the
/// application has to present that choice itself.
///
/// That is why [MediaController.availableDisplaySources] is part of the public
/// API rather than a detail: a build that hid the enumeration behind
/// `startScreenShare` would have no picker at all, and a build that guessed a
/// device id would share the wrong screen — which on Windows means the
/// `source not found` error at
/// `common/cpp/src/flutter_screen_capture.cc:331-334`, or a window the user did
/// not choose.
final class DisplaySource {
  const DisplaySource({
    required this.id,
    required this.name,
    required this.kind,
  });

  /// The `deviceId.exact` value to hand to `getDisplayMedia`.
  final String id;

  /// The device manager's window title, or the display's name.
  final String name;

  final DisplaySourceKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplaySource &&
          other.id == id &&
          other.name == name &&
          other.kind == kind;

  @override
  int get hashCode => Object.hash(id, name, kind);

  @override
  String toString() => 'DisplaySource(${kind.name}, $name)';
}
