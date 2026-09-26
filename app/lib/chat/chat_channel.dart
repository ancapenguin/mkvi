/// The data-channel seam: how the chat and transfer layers put a frame on the
/// wire, and how they learn that they could not.
///
/// The Rust/WebRTC transport does not exist yet. What exists is the *shape* of
/// the seam, and the shape is the interesting part: every way a write can fail
/// is a **return value**, not an exception carrying a user-facing string from a
/// foreign layer.
///
/// `peer-transport.ts` threw `new Error("Doğrudan bağlantı henüz hazır değil.")`
/// and `App.tsx` caught it and read `error.message` to fill a Turkish notice box.
/// That works only as long as every producer of the exception is Turkish, which
/// is exactly the assumption that produced the mixed-language UI. Here a refusal
/// carries [ChatChannelBinding.unavailableReason], a Turkish string the chat
/// layer itself chose, and the transport only has to say *which* of the two
/// reasons applies.
library;

import 'package:mkvi/core/protocol/control_message.dart';
import 'package:mkvi/core/protocol/file_frame.dart';

/// What happened to a frame handed to the channel.
sealed class SendOutcome {
  const SendOutcome();
}

/// The frame is on the wire.
final class FrameSent extends SendOutcome {
  const FrameSent();
}

/// The frame did not go out, and [reason] is the Turkish text to show.
final class ChannelUnavailable extends SendOutcome {
  const ChannelUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'ChannelUnavailable($reason)';
}

/// The one object this layer sends through.
///
/// [isOpen] is polled, not pushed: the reconnect loop that owns the channel
/// reports a change by calling `ChatController.reportChannelOpen`, and a poll at
/// flush time means a queue is never flushed against a channel that closed
/// between the report and the flush.
///
/// Back-pressure is a refusal, not a throw: a transport that is not ready to take
/// a frame answers with `ChannelUnavailable(ChatMessages.channelBusy)`, which is
/// the same shape as a dead channel and needs the same handling.
abstract interface class ChatChannelBinding {
  bool get isOpen;

  /// Puts one control frame on the wire.
  ///
  /// Returns [FrameSent] or [ChannelUnavailable]. It must not throw: an
  /// exception escaping here would escape through a UI callback carrying a string
  /// the chat layer did not write.
  SendOutcome send(PeerControlMessage message);

  /// Puts one binary file frame on the wire. Same contract as [send].
  SendOutcome sendFrame(FileFrame frame);
}
