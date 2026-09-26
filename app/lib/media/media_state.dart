import 'media_fault.dart';
import 'media_texts.dart';

/// Where a screen share is, as far as anyone can tell.
///
/// The `waitingForFirstFrame` state is not an optimisation — it is the only
/// honest description of the interval that upstream cannot see into. See
/// [MediaStatsProbe] and upstream issue #2137.
enum ScreenSharePhase {
  /// Not sharing.
  idle(MediaTexts.screenShareIdle),

  /// `getDisplayMedia` is in flight.
  starting(MediaTexts.screenShareStarting),

  /// A track is attached and no frame has been encoded yet. Entered
  /// **immediately** on attach, not after a delay, because a share that will
  /// never produce a frame is indistinguishable from a healthy one for as long as
  /// the plugin's own API is concerned.
  waitingForFirstFrame(MediaTexts.screenShareWaitingForFirstFrame),

  /// A frame has been encoded. The share works.
  live(MediaTexts.screenShareLive),

  /// The watchdog waited and no frame ever arrived. The label names the fix.
  stalled(MediaTexts.screenShareStalled),

  /// Capture never started.
  failed(MediaTexts.screenShareFailed);

  const ScreenSharePhase(this.label);

  /// The Turkish line for this state, safe to show as-is.
  final String label;

  /// Whether a capture track is currently attached to the screen sender.
  bool get isAttached => switch (this) {
    ScreenSharePhase.starting ||
    ScreenSharePhase.waitingForFirstFrame ||
    ScreenSharePhase.live ||
    ScreenSharePhase.stalled => true,
    ScreenSharePhase.idle || ScreenSharePhase.failed => false,
  };
}

/// Everything the media layer knows, as one immutable value.
///
/// Handed to the UI whole, so a widget can never hold a camera flag that the
/// controller has already released.
final class MediaState {
  const MediaState({
    this.microphoneLive = false,
    this.cameraLive = false,
    this.screenShare = ScreenSharePhase.idle,
    this.cameraDeviceId,
    this.microphoneDeviceId,
    this.screenSourceId,
    this.screenSourceName,
    this.notice,
    this.fault,
  });

  /// Whether a microphone track is attached to the audio sender.
  final bool microphoneLive;

  /// Whether a camera track is attached to the camera sender.
  final bool cameraLive;

  final ScreenSharePhase screenShare;

  /// The id of the camera currently publishing, or `null` when there is none.
  final String? cameraDeviceId;

  final String? microphoneDeviceId;

  /// The shareable target currently being captured.
  final String? screenSourceId;

  /// Its friendly name, for the "you are sharing X" line.
  final String? screenSourceName;

  /// A standing, non-fatal Turkish line: a device that left, or a degradation the
  /// user should know about. Cleared by the next successful operation that does
  /// not replace it.
  final String? notice;

  /// The most recent failure, Turkish, or `null`. Cleared by
  /// [MediaController.clearFault] rather than by time, so the UI decides.
  final MediaFault? fault;

  /// Whether anything is being published at all.
  bool get hasMedia => microphoneLive || cameraLive || screenShare.isAttached;

  MediaState copyWith({
    bool? microphoneLive,
    bool? cameraLive,
    ScreenSharePhase? screenShare,
    String? cameraDeviceId,
    String? microphoneDeviceId,
    String? screenSourceId,
    String? screenSourceName,
    String? notice,
    MediaFault? fault,
    bool clearCameraDeviceId = false,
    bool clearMicrophoneDeviceId = false,
    bool clearScreenSourceId = false,
    bool clearScreenSourceName = false,
    bool clearNotice = false,
    bool clearFault = false,
  }) => MediaState(
    microphoneLive: microphoneLive ?? this.microphoneLive,
    cameraLive: cameraLive ?? this.cameraLive,
    screenShare: screenShare ?? this.screenShare,
    cameraDeviceId: clearCameraDeviceId
        ? null
        : cameraDeviceId ?? this.cameraDeviceId,
    microphoneDeviceId: clearMicrophoneDeviceId
        ? null
        : microphoneDeviceId ?? this.microphoneDeviceId,
    screenSourceId: clearScreenSourceId
        ? null
        : screenSourceId ?? this.screenSourceId,
    screenSourceName: clearScreenSourceName
        ? null
        : screenSourceName ?? this.screenSourceName,
    notice: clearNotice ? null : notice ?? this.notice,
    fault: clearFault ? null : fault ?? this.fault,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaState &&
          other.microphoneLive == microphoneLive &&
          other.cameraLive == cameraLive &&
          other.screenShare == screenShare &&
          other.cameraDeviceId == cameraDeviceId &&
          other.microphoneDeviceId == microphoneDeviceId &&
          other.screenSourceId == screenSourceId &&
          other.screenSourceName == screenSourceName &&
          other.notice == notice &&
          other.fault == fault;

  @override
  int get hashCode => Object.hash(
    microphoneLive,
    cameraLive,
    screenShare,
    cameraDeviceId,
    microphoneDeviceId,
    screenSourceId,
    screenSourceName,
    notice,
    fault,
  );

  @override
  String toString() =>
      'MediaState(mic: $microphoneLive, cam: $cameraLive, '
      'screen: ${screenShare.name})';
}
