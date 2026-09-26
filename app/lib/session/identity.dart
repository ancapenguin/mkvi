/// The identity, signature and transcript vocabulary of a session.
///
/// Signing and hashing both need a private key and a digest, so both are
/// injected seams: this library owns the **transcripts** — the strings that get
/// signed, which are a wire contract and must never drift — and the caller owns
/// the SHA-256 and the key. A transcript is a *signed* string, so a single
/// changed character makes every verification fail with no useful diagnostic;
/// that is why each one is a named function here and never built by hand at a
/// call site.
library;

import 'package:mkvi/signaling/identifiers.dart';

/// Signs a transcript with this device's private key.
typedef TranscriptSigner = Future<String> Function(String transcript);

/// Checks a peer's signature over a transcript.
typedef PairingVerifier =
    Future<bool> Function(
      String publicKey,
      String transcript,
      String signature,
    );

/// SHA-256 of [input], unpadded base64url. The only hashing this library needs.
typedef Sha256Base64Url = Future<String> Function(String input);

/// Derives the pair-scoped device handle.
typedef PairScopedDeviceIdFactory =
    Future<String> Function(String discoveryId, String publicKey);

/// Mints a reconnect session id.
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
/// The reconnect loop treats a throw as a retryable attempt failure and never as
/// a reason to stop. That is the whole point of this contract: a persistent read
/// failure must keep the loop retrying, because giving up leaves the UI pinned
/// on "reconnecting" until the user restarts the app — and a keyring that is
/// temporarily locked is exactly that situation.
abstract class DeviceIdentityLoader {
  Future<DeviceIdentity> load();
}

/// The reconnect transcript for a v2 identity — the `session`-carrying form.
///
/// ```mkvi/discover/v2/<discoveryId>/<session>```
///
/// The session id is what makes this transcript replay-resistant: it is fresh
/// per connection, so a captured announce cannot be replayed into a different
/// session.
String discoveryTranscript(String discoveryId, String session) =>
    'mkvi/discover/v2/$discoveryId/$session';

/// The reconnect transcript for a **v1** identity — one sent with no session at
/// all. This is a wire version, and it stays: an identity signal with no
/// `session` key is still valid input, and the Worker still relays it.
String legacyDiscoveryTranscript(String discoveryId) =>
    'mkvi/discover/v1/$discoveryId';

/// The transcript a REMOTE identity is verified against.
///
/// An empty string is treated the same as an absent one. That is not a stylistic
/// choice: `""` is a falsy value in the wire format's original encoding, so a
/// peer that sent an empty session is on the v1 path by definition. Getting this
/// wrong on one side only means the two devices compute different transcripts and
/// never verify each other — a failure that looks like a network problem.
String remoteDiscoveryTranscript(String discoveryId, String? session) =>
    (session == null || session.isEmpty)
    ? legacyDiscoveryTranscript(discoveryId)
    : discoveryTranscript(discoveryId, session);

/// The pair-scoped device handle transcript.
///
/// ```mkvi/peer-device/v1/<discoveryId>/<publicKey>```
///
/// Scoped to *both* the room and the key, so two peers pairing in the same room
/// derive different handles.
String peerDeviceTranscript(String discoveryId, String publicKey) =>
    'mkvi/peer-device/v1/$discoveryId/$publicKey';

/// The pairing transcript a fresh, user-initiated pairing signs. Bound to the
/// code the user typed, so a signature captured from one pairing cannot be
/// replayed into another.
String pairingTranscript(String code) => 'mkvi/pair/v1/$code';

/// Builds the pair-scoped device id factory from a SHA-256 seam.
///
/// The id is a bearer capability in the `/v1/peer` query, so it must be
/// base64url-only: a `+` in a query parameter is read back as a space by the
/// Worker and the id arrives corrupted.
PairScopedDeviceIdFactory pairScopedDeviceIdFactory(Sha256Base64Url digest) =>
    (String discoveryId, String publicKey) =>
        digest(peerDeviceTranscript(discoveryId, publicKey));

/// Which side offers, decided without exchanging a role.
///
/// The comparison is over UTF-16 code units in both languages, so the two sides
/// always reach the same answer from the same two public keys. If this were
/// order-sensitive in any way, exactly one of the two peers would believe it was
/// the caller and the call would never connect.
bool isInitiator({
  required String ownPublicKey,
  required String peerPublicKey,
}) => ownPublicKey.compareTo(peerPublicKey) < 0;
