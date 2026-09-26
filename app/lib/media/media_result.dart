import 'media_fault.dart';
import 'media_state.dart';
import 'media_texts.dart';

/// The outcome of one media operation.
///
/// Sealed, so a `switch` is exhaustive and a new outcome cannot be added without
/// every caller noticing. **No operation in this layer throws**: a capture
/// failure is a normal answer, not an exception, because every one of them ends
/// up in the same Turkish media-error box and a caller that has to remember a
/// `try` around each one is a caller that will forget one.
sealed class MediaOutcome {
  const MediaOutcome();
}

/// Something worked. [notice] is non-null exactly when the operation succeeded
/// at something other than what the user asked for.
final class MediaSucceeded extends MediaOutcome {
  const MediaSucceeded({this.notice});

  /// Turkish, set only for a degradation the user has to be told about.
  final String? notice;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaSucceeded && other.notice == notice;

  @override
  int get hashCode => notice?.hashCode ?? 0;

  @override
  String toString() => 'MediaSucceeded(${notice ?? "no notice"})';
}

/// Something failed, and the user is being told so in Turkish.
final class MediaFailed extends MediaOutcome {
  const MediaFailed(this.fault);

  final MediaFault fault;

  /// The line to show. Always Turkish; see [MediaFault.message].
  String get message => fault.message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MediaFailed && other.fault == fault;

  @override
  int get hashCode => fault.hashCode;

  @override
  String toString() => 'MediaFailed($fault)';
}

/// The result of [MediaController.startCall].
///
/// The distinction the ladder exists to make: [MediaCallStarted.audio] and
/// [MediaCallStarted.video] are what is *actually* on the wire, which is not
/// always what was requested. A caller that asked for video and got audio is
/// looking at [MediaCallFailed] — that combination is not constructible.
sealed class MediaCallStarted {
  const MediaCallStarted();
}

/// The call has media on the senders.
final class MediaCallLive extends MediaCallStarted {
  const MediaCallLive({required this.audio, required this.video, this.notice});

  /// Whether a microphone track is attached.
  final bool audio;

  /// Whether a camera track is attached. `false` only for a call that was
  /// *started* as audio; [MediaCallFailed] covers a video request that could not
  /// get one.
  final bool video;

  /// Turkish, non-null only for the one permitted degradation: a video call whose
  /// microphone was unavailable, which continues as video-only.
  final String? notice;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaCallLive &&
          other.audio == audio &&
          other.video == video &&
          other.notice == notice;

  @override
  int get hashCode => Object.hash(audio, video, notice);

  @override
  String toString() => 'MediaCallLive(audio: $audio, video: $video)';
}

/// The call could not get what it was asked for. Reported, never downgraded.
final class MediaCallFailed extends MediaCallStarted {
  const MediaCallFailed(this.fault);

  final MediaFault fault;

  /// The line to show.
  ///
  /// A permission refusal is the one fault whose text is *about the call* rather
  /// than about one device: a combined `getUserMedia({audio: true, video: true})`
  /// cannot say which device the OS refused, and the advice that can be right for
  /// both is "allow the app", so this is a single combined sentence rather than
  /// a per-device one.
  String get message => fault.kind == MediaFaultKind.permissionDenied
      ? MediaTexts.callPermissionDenied
      : fault.message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaCallFailed && other.fault == fault;

  @override
  int get hashCode => fault.hashCode;

  @override
  String toString() => 'MediaCallFailed($fault)';
}

/// The result of [MediaController.startScreenShare].
///
/// Carries [ScreenSharePhase.starting], not [ScreenSharePhase.live], on success:
/// a successful `getDisplayMedia` proves the capture *started*, and upstream
/// issue #2137 is precisely the case where that is the strongest claim it can
/// make. `MediaState.screenShare` is what says whether frames followed.
sealed class MediaScreenShare {
  const MediaScreenShare();
}

/// Capture is under way. The share works once the phase reaches
/// [ScreenSharePhase.live].
final class MediaScreenShareStarted extends MediaScreenShare {
  const MediaScreenShareStarted(this.source);

  /// The target actually being captured, which is the whole point of returning
  /// it: with no native picker, a caller that guessed an id has to be able to
  /// show the user what it guessed.
  final String source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaScreenShareStarted && other.source == source;

  @override
  int get hashCode => source.hashCode;

  @override
  String toString() => 'MediaScreenShareStarted($source)';
}

/// Capture did not start. [cancelled] is the user closing the picker, which is
/// not a failure to apologise for and is reported as its own type so the UI can
/// stay silent.
final class MediaScreenShareFailed extends MediaScreenShare {
  const MediaScreenShareFailed(this.fault);

  final MediaFault fault;

  /// The line to show, when there is a line to show. Suppress it when
  /// [cancelled] is true.
  String get message => fault.message;

  /// Whether the user dismissed the picker. The Turkish text is still available
  /// on [fault] for a caller that wants it, but the common case is silence.
  bool get cancelled => fault.kind == MediaFaultKind.cancelled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaScreenShareFailed && other.fault == fault;

  @override
  int get hashCode => fault.hashCode;

  @override
  String toString() => 'MediaScreenShareFailed($fault)';
}
