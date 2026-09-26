/// The identity, signature and transcript vocabulary of a session.
///
/// `src/App.tsx:60-73` and `src/services/local-security.ts:3-12` are the
/// TypeScript originals. Two of those functions hash with
/// `crypto.subtle.digest`, so the digest itself is an injected seam: this
/// library owns the TRANSCRIPTS (the strings that get signed, which are a wire
/// contract and must never drift) and the caller owns the SHA-256.
library;

import 'package:mkvi/signaling/identifiers.dart';

/// Signs a transcript with this device's private key.
typedef TranscriptSigner = Future<String> Function(String transcript);

/// Checks a peer's signature over a transcript. TS: `verifyPairing`.
typedef PairingVerifier =
    Future<bool> Function(
      String publicKey,
      String transcript,
      String signature,
    );

/// SHA-256 of [input], unpadded base64url. The only hashing this library needs.
typedef Sha256Base64Url = Future<String> Function(String input);

/// Derives the pair-scoped device handle. TS: `createPairScopedDeviceId`.
typedef PairScopedDeviceIdFactory =
    Future<String> Function(String discoveryId, String publicKey);

/// Mints a reconnect session id. TS: `createRendezvousId` at
/// `src/App.tsx:60-65`.
typedef SessionIdFactory = String Function();

/// The production session id: 32 random bytes as unpadded base64url, which is
/// exactly the 43 character `^[A-Za-z0-9_-]{43}$` the Worker accepts.
String defaultSessionIdFactory() => createOpaqueId();

/// This device's long-term key.
final class DeviceIdentity {
  const DeviceIdentity({required this.publicKey, required this.sign});

  final String publicKey;
  final TranscriptSigner sign;
}

/// Loads the device identity, or throws.
///
/// The reconnect loop treats a throw as a retryable attempt failure and never
/// as a reason to stop: `src/App.tsx:217-222` `return`ed out of the enclosing
/// async IIFE, which ended the loop permanently and left the UI pinned on
/// "reconnecting" until the user restarted the app.
abstract class DeviceIdentityLoader {
  Future<DeviceIdentity> load();
}

/// The reconnect transcript for a v2 identity. TS: `src/App.tsx:230`.
///
/// ```mkvi/discover/v2/<discoveryId>/<session>```
String discoveryTranscript(String discoveryId, String session) =>
    'mkvi/discover/v2/$discoveryId/$session';

/// The reconnect transcript for an identity sent by 0.1.0 - 0.1.3, which
/// carries no session at all. TS: `src/App.tsx:253`.
String legacyDiscoveryTranscript(String discoveryId) =>
    'mkvi/discover/v1/$discoveryId';

/// The transcript a REMOTE identity is verified against.
///
/// An empty string is treated the same as an absent one, because the TypeScript
/// original used a truthiness test (`signal.session ? ... : ...`) and a `""`
/// session is falsy in JavaScript. Getting this wrong on one side only means
/// the two devices compute different transcripts and never verify each other.
String remoteDiscoveryTranscript(String discoveryId, String? session) =>
    (session == null || session.isEmpty)
    ? legacyDiscoveryTranscript(discoveryId)
    : discoveryTranscript(discoveryId, session);

/// The pair-scoped device handle transcript. TS: `src/App.tsx:68`.
///
/// ```mkvi/peer-device/v1/<discoveryId>/<publicKey>```
String peerDeviceTranscript(String discoveryId, String publicKey) =>
    'mkvi/peer-device/v1/$discoveryId/$publicKey';

/// The pairing transcript a fresh, user-initiated pairing signs. TS:
/// `src/App.tsx:415`.
String pairingTranscript(String code) => 'mkvi/pair/v1/$code';

/// Builds the pair-scoped device id factory from a SHA-256 seam.
///
/// The id is a bearer capability in the `/v1/peer` query, so it must be
/// base64url-only: a `+` in a query parameter is read back as a space by the
/// Worker and the id arrives corrupted.
PairScopedDeviceIdFactory pairScopedDeviceIdFactory(Sha256Base64Url digest) =>
    (String discoveryId, String publicKey) =>
        digest(peerDeviceTranscript(discoveryId, publicKey));

/// Which side offers. TS: `src/App.tsx:223`.
///
/// The comparison is over UTF-16 code units in both languages, so the two sides
/// always agree without exchanging a role.
bool isInitiator({
  required String ownPublicKey,
  required String peerPublicKey,
}) => ownPublicKey.compareTo(peerPublicKey) < 0;
