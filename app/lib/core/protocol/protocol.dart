/// Convenience entry point for the protocol layer.
///
/// One import, no barrel-cycle surprises: everything the app, the transport and
/// the rendezvous layer need is re-exported here, while the individual files
/// remain importable on their own.
library;

export 'control_message.dart';
export 'control_parser.dart';
export 'file_frame.dart';
export 'file_transfer.dart';
export 'peer_protocol.dart';
export 'peer_protocol_exception.dart';
export 'text_sanitizer.dart';
export 'transfer_id.dart';
