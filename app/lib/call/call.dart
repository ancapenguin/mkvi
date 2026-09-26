/// Convenience entry point for the call layer.
///
/// One import, no barrel-cycle surprises: everything the UI layer and the Dart
/// transport need is re-exported here, while the individual files stay importable
/// on their own — the same arrangement `lib/core/protocol/protocol.dart` uses.
///
/// The layer is pure: `dart:async` for the production timer seam and nothing
/// else, plus the already-ported `package:mkvi/core/protocol` wire types. There
/// is no `flutter` and no `flutter_webrtc` import anywhere under `lib/call`, which
/// is what lets `test/call` drive a whole call — including both 45 s timeouts —
/// without a camera, a peer or a second machine.
library;

export 'call_action.dart';
export 'call_machine.dart';
export 'call_messages.dart';
export 'call_outcome.dart';
export 'call_refusal.dart';
export 'call_session.dart';
export 'call_status.dart';
export 'call_timers.dart';
export 'call_transition.dart';
export 'missed_call.dart';
