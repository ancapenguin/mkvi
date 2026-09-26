/// Convenience entry point for the chat and file-transfer layer.
///
/// One import, no barrel-cycle surprises: everything the surface and the Dart
/// transport need is re-exported here, while the individual files stay importable
/// on their own — the same arrangement `lib/core/protocol/protocol.dart` and
/// `lib/call/call.dart` use.
///
/// The layer is pure: `dart:async` for the production stream seams and nothing
/// else, plus the already-ported `package:mkvi/core/protocol` wire types. There
/// is no `flutter`, no `flutter_webrtc` and no `dart:io` import anywhere under
/// `lib/chat`, which is what lets `test/chat` drive a whole conversation, a
/// whole transfer and a whole reconnect with no disk, no channel and a second
/// machine.
///
/// Two seams keep the storage out of it, and neither has an implementation here
/// because neither has a bridge to call: [HistoryStore] (the encrypted local log
/// the Rust core will own) and [FileSink] (the download directory). The
/// coordinator calls [FileSink.open] in exactly one place and never touches a
/// file itself — the rule that keeps a declined transfer from leaving a 0-byte
/// file behind.
library;

export 'chat_channel.dart';
export 'chat_controller.dart';
export 'chat_messages.dart';
export 'chat_timeline.dart';
export 'file_sink.dart';
export 'history_store.dart';
export 'timeline_message.dart';
export 'timeline_row.dart';
export 'transfer_coordinator.dart';
export 'transfer_view.dart';
