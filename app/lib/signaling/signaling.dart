/// MKVI signaling: the Dart side of the wire contract in `vectors/wire-v1.json`.
///
/// Both this library and `src/domain/signaling.ts` + `src/services/rendezvous.ts`
/// are held to that one file, so neither can drift from the other without a test
/// going red. Comments are English, every string the user can see is Turkish.
library;

export 'identifiers.dart';
export 'pairing_code.dart';
export 'query_encoding.dart';
export 'rendezvous_client.dart';
export 'signal_payload.dart';
