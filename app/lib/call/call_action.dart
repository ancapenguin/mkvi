import 'package:mkvi/core/protocol/control_message.dart';

/// One thing the caller of the machine must do, in the order the machine listed
/// it.
///
/// The machine has no WebRTC, no capture and no data channel, so it cannot send a
/// frame or publish a track itself. What it *can* do — and what it does here — is
/// decide the order, and hand the caller an ordered list. That is the whole
/// defence against publishing the callee's camera before the user has accepted
/// anything: the decision to send `call-accept` and the permission to open a
/// camera are two entries in one list, so they cannot be reordered by a caller
/// that awaits the wrong one first, while an answer dialog on the same screen
/// promises the opposite.
///
/// Sealed, so a `switch` over an action list is exhaustive and a new kind of step
/// cannot be added without every consumer noticing.
sealed class CallAction {
  const CallAction();
}

/// Put one control frame on the wire.
///
/// Every frame the machine produces is built with the already-ported protocol
/// types, so `encodeControl` accepts it and the peer's `parseControl` produces the
/// same value back — no hand-written JSON, no second spelling of `call-decline`.
final class SendFrame extends CallAction {
  const SendFrame(this.message);

  final PeerControlMessage message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SendFrame && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'SendFrame($message)';
}

/// Capture (or re-capture) media and publish it on the pre-negotiated
/// transceivers with `replaceTrack`.
///
/// [audio] and [video] are the tracks the camera/microphone pair should carry.
/// There is no `renegotiate` flag and there does not need to be one: the Dart
/// transport creates an audio, a camera and a screen transceiver as `sendrecv`
/// when the connection is built, so turning a track on or off is a `replaceTrack`
/// and never a new offer. A `PublishMedia` in a transition is therefore always
/// local — it never comes with a `SendFrame` that would trigger negotiation.
final class PublishMedia extends CallAction {
  const PublishMedia({
    required this.mode,
    required this.audio,
    required this.video,
  });

  /// The mode the session is in, which is also what the peer should end up with.
  final CallMode mode;

  /// Whether the microphone track should be live.
  final bool audio;

  /// Whether the camera track should be live.
  final bool video;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublishMedia &&
          other.mode == mode &&
          other.audio == audio &&
          other.video == video;

  @override
  int get hashCode => Object.hash(mode, audio, video);

  @override
  String toString() =>
      'PublishMedia(${mode.wireName} audio=$audio video=$video)';
}

/// Stop local capture and mute the outgoing senders.
///
/// Emitted on every terminal transition, including the ones where nothing was
/// ever published: the UI captures a preview of its own camera *before* the peer
/// accepts, and a call that is declined must not leave that camera light on.
final class ReleaseMedia extends CallAction {
  const ReleaseMedia();

  @override
  bool operator ==(Object other) => other is ReleaseMedia;

  @override
  int get hashCode => 0x1e1e;

  @override
  String toString() => 'ReleaseMedia()';
}
