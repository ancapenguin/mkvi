/// The two kinds of capture input MKVI ever asks for.
///
/// `audioinput` and `videoinput` are the `kind` strings `getSources` reports
/// (`common/cpp/src/flutter_media_stream.cc:434-478`); `audiooutput` is
/// deliberately absent because MKVI has no output picker and the peer connection
/// owns playback.
enum MediaDeviceKind { microphone, camera }

/// One capture input, as this process can see it.
final class MediaDevice {
  const MediaDevice({
    required this.id,
    required this.label,
    required this.kind,
  });

  /// The id the plugin and the native layer agree on.
  ///
  /// This is the same string `SanitizeDeviceIdFromVideoBuffers` /
  /// `SanitizeDeviceIdFromAudioBuffers` build from the friendly name plus the
  /// device GUID, and the same string `getUserMedia` and `selectAudioInput` both
  /// compare against. It is opaque; never parse it, never show it.
  final String id;

  /// The friendly name. Empty before the OS has granted capture permission, and
  /// on Windows it is the device manager's name, so it is a label and not an
  /// identity: two devices can share one.
  final String label;

  final MediaDeviceKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaDevice &&
          other.id == id &&
          other.label == label &&
          other.kind == kind;

  @override
  int get hashCode => Object.hash(id, label, kind);

  @override
  String toString() => 'MediaDevice(${kind.name}, $label)';
}

/// Every capture input visible right now, in two lists.
final class MediaDeviceSnapshot {
  const MediaDeviceSnapshot({
    this.microphones = const <MediaDevice>[],
    this.cameras = const <MediaDevice>[],
  });

  final List<MediaDevice> microphones;

  final List<MediaDevice> cameras;

  /// Looks a device up by id, or `null` when it is not present.
  ///
  /// The controller uses this to *refuse* a remembered device id before handing
  /// it to the native layer. That check is not defensive noise: for audio, an
  /// unrecognised `deviceId` in `getUserMedia` constraints is matched against
  /// nothing (`common/cpp/src/flutter_media_stream.cc:219-228`), `SetRecordingDevice`
  /// is then never called, and the track that comes back silently carries the
  /// *previous* microphone while reporting the *requested* id in its settings
  /// (`:267-269`). A camera switch that quietly keeps the old camera is worse
  /// than a refused one.
  MediaDevice? byId(String id) {
    for (final MediaDevice device in <MediaDevice>[
      ...microphones,
      ...cameras,
    ]) {
      if (device.id == id) return device;
    }
    return null;
  }

  /// The id of the *one* device carrying [label], or `null` when there is none or
  /// more than one.
  ///
  /// Matched on the label because that is the only device information a plugin
  /// track ever carries:
  ///
  /// ```cpp
  /// info[EncodableValue("id")] = EncodableValue(track->id().std_string());
  /// info[EncodableValue("label")] = EncodableValue(track->id().std_string());
  /// ```
  ///
  /// (`flutter_webrtc/common/cpp/src/flutter_media_stream.cc:408-410`.) Both keys
  /// get the *track's* own id, which is a fresh UUID per capture
  /// (`base_->GenerateUUID()`, `:402`) and matches no device the OS ever listed.
  /// So the only field a caller can match a track back to hardware with is the
  /// label — the device manager's friendly name.
  ///
  /// An ambiguous label answers `null` rather than picking one. Two devices can
  /// genuinely share a friendly name, and a coin-flip id would be acted on later
  /// by the unplug check, which is worse than having nothing to act on.
  String? idForLabel(String label) {
    String? found;
    for (final MediaDevice device in <MediaDevice>[
      ...microphones,
      ...cameras,
    ]) {
      if (device.label != label) continue;
      if (found != null) return null;
      found = device.id;
    }
    return found;
  }

  /// The devices that are in [newer] and were not here.
  MediaDeviceSnapshot addedComparedTo(MediaDeviceSnapshot older) {
    return MediaDeviceSnapshot(
      microphones: _arrived(older.microphones, microphones),
      cameras: _arrived(older.cameras, cameras),
    );
  }

  /// What is missing from [newer], as a snapshot-shaped answer.
  MediaDeviceSnapshot difference(MediaDeviceSnapshot newer) {
    return MediaDeviceSnapshot(
      microphones: _gone(microphones, newer.microphones),
      cameras: _gone(cameras, newer.cameras),
    );
  }
}

List<MediaDevice> _gone(List<MediaDevice> before, List<MediaDevice> after) =>
    before
        .where(
          (MediaDevice device) =>
              !after.any((MediaDevice now) => now.id == device.id),
        )
        .toList(growable: false);

List<MediaDevice> _arrived(List<MediaDevice> before, List<MediaDevice> after) =>
    after
        .where(
          (MediaDevice device) =>
              !before.any((MediaDevice then) => then.id == device.id),
        )
        .toList(growable: false);

/// One device-set change, already reduced to what actually changed.
///
/// The plugin's `ondevicechange` carries no payload — "There is no information
/// about the change included in the event object" is the spec's own comment on
/// `MediaDevices.ondevicechange` — and on Windows the event channel fires it from
/// the *audio* device module alone
/// (`common/cpp/src/flutter_webrtc_base.cc:88-92`). So it can arrive several
/// times for one physical change, and it says nothing about cameras. Both are
/// fixed here, once, in [MediaDeviceSnapshot.difference]: the controller
/// re-enumerates on every notification and publishes only a real difference, so
/// "kamera çıkarıldı" is shown once per unplug instead of once per event.
final class MediaDevicesChanged {
  const MediaDevicesChanged({
    this.removedMicrophones = const <MediaDevice>[],
    this.removedCameras = const <MediaDevice>[],
    this.addedMicrophones = const <MediaDevice>[],
    this.addedCameras = const <MediaDevice>[],
  });

  final List<MediaDevice> removedMicrophones;

  final List<MediaDevice> removedCameras;

  final List<MediaDevice> addedMicrophones;

  final List<MediaDevice> addedCameras;

  /// Whether anything at all changed. A notification that re-enumerates to the
  /// same list produces an `isEmpty` event, which the controller drops — this is
  /// the property that makes "reported once" testable.
  bool get isEmpty =>
      removedMicrophones.isEmpty &&
      removedCameras.isEmpty &&
      addedMicrophones.isEmpty &&
      addedCameras.isEmpty;

  /// Whether the camera this process was publishing is one of the ones that left.
  bool lostCamera(String? deviceId) =>
      deviceId != null &&
      removedCameras.any((MediaDevice device) => device.id == deviceId);

  /// Whether the microphone this process was publishing is gone.
  bool lostMicrophone(String? deviceId) =>
      deviceId != null &&
      removedMicrophones.any((MediaDevice device) => device.id == deviceId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaDevicesChanged &&
          _sameIds(other.removedMicrophones, removedMicrophones) &&
          _sameIds(other.removedCameras, removedCameras) &&
          _sameIds(other.addedMicrophones, addedMicrophones) &&
          _sameIds(other.addedCameras, addedCameras);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(removedMicrophones.map((MediaDevice d) => d.id)),
    Object.hashAll(removedCameras.map((MediaDevice d) => d.id)),
    Object.hashAll(addedMicrophones.map((MediaDevice d) => d.id)),
    Object.hashAll(addedCameras.map((MediaDevice d) => d.id)),
  );

  @override
  String toString() =>
      'MediaDevicesChanged(-mic:${removedMicrophones.length} '
      '-cam:${removedCameras.length} +mic:${addedMicrophones.length} '
      '+cam:${addedCameras.length})';
}

bool _sameIds(List<MediaDevice> a, List<MediaDevice> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i += 1) {
    if (a[i].id != b[i].id) return false;
  }
  return true;
}
