/// MKVI session: startup, the reconnect loop, and who the peer is.
///
/// One import for the UI layer. Comments are English; every string the user can
/// see is Turkish.
///
/// The three production defects this library exists to make impossible:
///
/// * A failed peer read rendered the FIRST-RUN pairing screen, because a
///   rejected read and "no peer yet" left the same null behind.
///   [SetupState] splits the two, and [SetupState.showsPairingScreen] is the only
///   thing that may answer the question.
/// * A transient identity-read failure ended the reconnect loop forever, and a
///   stale epoch's teardown wrote "disconnected" / "reconnecting" over a live
///   successor's state. [ReconnectDriver] guards both structurally.
/// * A local annotation outranked the name the peer announced for itself, and
///   when it happened to equal it, silently removed both the announced-name line
///   and the "remove annotation" button. [PeerNameView] has two slots and answers
///   the UI's question about the annotation, not about the two names' equality.
library;

export 'identity.dart';
export 'local_settings.dart';
export 'names.dart';
export 'peer_store.dart';
export 'reconnect_driver.dart';
export 'reconnect_schedule.dart';
export 'session_bootstrap.dart';
export 'session_controller.dart';
export 'setup_state.dart';
