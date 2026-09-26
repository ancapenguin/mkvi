/// The bridge to the Rust verifier, as an interface.
///
/// **There is no production implementation of this yet.** `verify_artifact` and
/// `key_is_legacy` live in `crates/mkvi_core/src/update.rs:98` and `:129`, and
/// the Flutter host is not compiled against that crate - `mkvi_core` exposes no
/// C ABI and `flutter_rust_bridge` is not a dependency of this package. So the
/// contract is written down here, a fake stands in for it in the tests, and the
/// only implementation shipped in `lib/` is [UnavailableSignatureVerifier],
/// which refuses everything.
///
/// That refusal is the point, not a placeholder to be shrugged at: a verifier
/// that answered "fine" without having checked anything would turn a missing
/// bridge into a silent acceptance of whatever the feed pointed at, which is the
/// exact shape of the defect this layer exists to remove.
///
/// ## What replaces the stub
///
/// **One class: `RustSignatureVerifier implements SignatureVerifier`.** Nothing
/// else in this library has to change when it lands - no new method, no new type
/// on either sealed family, no new state on [UpdateConfig]. That is the test of
/// whether this interface is finished, and `test/update/update_verifier_test.dart`
/// is what holds it to that: all five outcomes a release can have are reachable
/// through the interface as it stands.
///
/// It binds to two Rust functions and re-implements nothing:
///
/// | Dart | Rust | Note |
/// |---|---|---|
/// | [SignatureVerifier.classifyKey] | `mkvi_core::update::key_is_legacy` (`update.rs:129`) | `Result<bool, _>` |
/// | [SignatureVerifier.verifyArtifact] | `mkvi_core::update::verify_artifact` (`update.rs:98`) | `Result<(), _>` |
///
/// **The bridge must not re-implement any of it in Dart.** The strictness in the
/// Rust core - prehashed only, whole artefact only, `allow_legacy` hard-coded
/// `false` at `update.rs:116` - is the property being protected, and a second
/// implementation is a second thing to get wrong.
///
/// ## The mapping, in full
///
/// A `Result` from either function lands on exactly one member of the family it
/// belongs to, and the members exist so that no landing is ambiguous:
///
/// | Rust | Dart |
/// |---|---|
/// | `key_is_legacy` -> `Ok(false)` | [ReleaseKeyPrehashed] |
/// | `key_is_legacy` -> `Ok(true)` | [ReleaseKeyLegacy] |
/// | `key_is_legacy` -> `Err(MalformedKey)` | [ReleaseKeyUnreadable] |
/// | the call throws, or is not wired | [ReleaseKeyUnavailable] |
/// | `verify_artifact` -> `Ok(())` | [ArtifactSignatureValid] |
/// | `Err(SignatureRejected)` | [ArtifactSignatureRejected] |
/// | `Err(LegacyKey)` | [ArtifactKeyIsLegacy] |
/// | `Err(MalformedKey)` | [ArtifactKeyUnreadable] |
/// | `Err(MalformedSignature)` | [ArtifactSignatureUnreadable] |
/// | the call throws, or is not wired | [ArtifactVerificationUnavailable] |
/// | the file on disk is not [SignatureVerifier.verifyArtifact]'s `byteLength` | [ArtifactSizeMismatch] |
///
/// The last row is the only one the Rust core does not answer, and it is the
/// reason `byteLength` travels with the path. `verify_artifact` takes
/// `&[u8]`, so the bridge does the file read itself and can compare the length
/// it finds against the length the client counted **before** hashing hundreds of
/// megabytes to learn that the two disagree. A short or padded file on the local
/// disk is not an attacker, so it gets its own failure rather than being folded
/// into "the file may have been modified".
///
/// ## What does *not* go through the bridge
///
/// `mkvi_core::update::parse_feed` (`update.rs:70`) already has a Dart port -
/// [parseUpdateManifest] in `update_manifest.dart` - and must not acquire a
/// second one. The same feed document is read on both sides of this boundary
/// somewhere down the line; two parsers that disagree about what counts as a
/// release are a place where one offers something the other calls malformed.
library;

/// What the configured release key actually is.
///
/// Mirrors `key_is_legacy`, which accepts either the bare 42 byte key or a whole
/// base64 encoded `minisign.pub` file. Both shapes name the same Ed25519 key, so
/// neither is the weaker check.
sealed class ReleaseKeyState {
  const ReleaseKeyState();
}

/// A prehashed (`ED`) key: the only form a signature can be verified against.
final class ReleaseKeyPrehashed extends ReleaseKeyState {
  const ReleaseKeyPrehashed();

  @override
  String toString() => 'ReleaseKeyPrehashed()';
}

/// A retired (`Ed`) key. Every signature such a key can produce is refused by a
/// strict verifier, so this is reported as itself and never as tampering.
final class ReleaseKeyLegacy extends ReleaseKeyState {
  const ReleaseKeyLegacy();

  @override
  String toString() => 'ReleaseKeyLegacy()';
}

/// Not a minisign block at all. An error here is an error, never a "probably
/// fine": the same value would fail at verification time anyway, and finding out
/// at startup is the entire point of the preflight.
final class ReleaseKeyUnreadable extends ReleaseKeyState {
  const ReleaseKeyUnreadable();

  @override
  String toString() => 'ReleaseKeyUnreadable()';
}

/// Nobody could say: the classifier itself is not wired yet.
///
/// Distinct from [ReleaseKeyUnreadable] on purpose. "Your key is malformed" and
/// "this build cannot read keys" are different problems with different fixes, and
/// collapsing them would send a user to rotate a key that was fine.
final class ReleaseKeyUnavailable extends ReleaseKeyState {
  const ReleaseKeyUnavailable();

  @override
  String toString() => 'ReleaseKeyUnavailable()';
}

/// The verifier's answer about one downloaded artefact.
///
/// A verdict rather than a thrown error, so the client's decision is an
/// exhaustive `switch` and a new outcome cannot be silently treated as success.
/// The names line up with `UpdateError` at
/// `crates/mkvi_core/src/update.rs:27-49`.
sealed class ArtifactVerdict {
  const ArtifactVerdict();
}

/// The whole artefact hashed to the signed pre-image. The only way past
/// verification.
final class ArtifactSignatureValid extends ArtifactVerdict {
  const ArtifactSignatureValid();

  @override
  String toString() => 'ArtifactSignatureValid()';
}

/// The bytes are not the ones the release key signed.
final class ArtifactSignatureRejected extends ArtifactVerdict {
  const ArtifactSignatureRejected();

  @override
  String toString() => 'ArtifactSignatureRejected()';
}

/// The key, or the signature, is in the retired form. Distinct from a rejection
/// for the reason `UpdateError::LegacyKey` exists.
final class ArtifactKeyIsLegacy extends ArtifactVerdict {
  const ArtifactKeyIsLegacy();

  @override
  String toString() => 'ArtifactKeyIsLegacy()';
}

/// The signature field is not a readable minisign block.
final class ArtifactSignatureUnreadable extends ArtifactVerdict {
  const ArtifactSignatureUnreadable();

  @override
  String toString() => 'ArtifactSignatureUnreadable()';
}

/// The key is not a readable minisign block.
final class ArtifactKeyUnreadable extends ArtifactVerdict {
  const ArtifactKeyUnreadable();

  @override
  String toString() => 'ArtifactKeyUnreadable()';
}

/// The file on disk is not the length the client counted, so it was never hashed.
///
/// Decided by the bridge before the read, from the `byteLength` that travels
/// with the path. Its own verdict because the honest sentence is "this file is
/// not the size it should be" and the dishonest one is "someone changed it": a
/// truncated write or a full disk is not an attacker, and a user told otherwise
/// goes looking for one.
final class ArtifactSizeMismatch extends ArtifactVerdict {
  const ArtifactSizeMismatch();

  @override
  String toString() => 'ArtifactSizeMismatch()';
}

/// The bridge is not wired, so nothing was checked. Must be treated as a refusal.
final class ArtifactVerificationUnavailable extends ArtifactVerdict {
  const ArtifactVerificationUnavailable();

  @override
  String toString() => 'ArtifactVerificationUnavailable()';
}

/// The whole verification seam. Two questions, both answered by the Rust core,
/// neither of them re-implemented in Dart.
abstract class SignatureVerifier {
  /// What [publicKeyB64] is. Cheap, local, and the thing the preflight asks at
  /// startup. Binds to `key_is_legacy`, which is already a `Result` and needs
  /// no error handling of its own beyond the mapping in the library comment.
  Future<ReleaseKeyState> classifyKey(String publicKeyB64);

  /// Whether the artefact at [artifactPath] is the one [signatureB64] signs.
  ///
  /// The path is passed rather than the bytes, and that is deliberate: an
  /// installer is far larger than it is comfortable to hold in memory, and the
  /// minisign form this feed uses pre-hashes with BLAKE2b-512, so the Rust side
  /// can read and hash the file in one pass. [byteLength] travels with it so the
  /// bridge can refuse a file whose length does not match what the client wrote,
  /// before the read rather than after it - see [ArtifactSizeMismatch].
  ///
  /// The whole file is verified. There is no offset, no length and no window in
  /// this signature, which is what makes "verify the artefact" and "verify
  /// these 200 bytes of it" the same call - there is no second, weaker one to
  /// reach for.
  Future<ArtifactVerdict> verifyArtifact({
    required String artifactPath,
    required int byteLength,
    required String signatureB64,
    required String publicKeyB64,
  });
}

/// The only [SignatureVerifier] in `lib/`, and it refuses.
///
/// It exists so the app can be wired up before the bridge exists without the
/// wiring being a lie: [UpdateClient] will run, [UpdateClient.preflight] will
/// report the key, and the first attempt to install anything will stop with
/// `UpdateFailureVerificationUnavailable` instead of installing an unverified
/// file. `RustSignatureVerifier` replaces this class and nothing else.
final class UnavailableSignatureVerifier implements SignatureVerifier {
  const UnavailableSignatureVerifier();

  @override
  Future<ReleaseKeyState> classifyKey(String publicKeyB64) async =>
      const ReleaseKeyUnavailable();

  @override
  Future<ArtifactVerdict> verifyArtifact({
    required String artifactPath,
    required int byteLength,
    required String signatureB64,
    required String publicKeyB64,
  }) async => const ArtifactVerificationUnavailable();

  @override
  String toString() => 'UnavailableSignatureVerifier()';
}
