/// The bridge to the Rust verifier, as an interface.
///
/// **There is no production implementation of this yet.** `verify_artifact` and
/// `key_is_legacy` live in `crates/mkvi_core/src/update.rs:98` and `:122`, and
/// the Flutter host is not compiled against that crate - `mkvi_core` exposes no
/// C ABI and `flutter_rust_bridge` is not a dependency. So the contract is
/// written down here, a fake stands in for it in the tests, and the only
/// implementation shipped in `lib/` is [UnavailableSignatureVerifier], which
/// refuses everything.
///
/// That refusal is the point, not a placeholder to be shrugged at: a verifier
/// that answered "fine" without having checked anything would turn a missing
/// bridge into a silent acceptance of whatever the feed pointed at, which is the
/// exact shape of the defect this layer exists to remove. When the bridge lands,
/// it must delegate to `mkvi_core::update` and must not re-implement any of it
/// in Dart - the strictness in the Rust core (prehashed only, whole artefact
/// only, `allow_legacy` hard-coded false) is the property being protected, and
/// a second implementation is a second thing to get wrong.
library;

/// What the configured release key actually is.
///
/// Mirrors `key_is_legacy`, which accepts either the bare 42 byte key or a whole
/// base64 encoded `minisign.pub` file - the second is the shape
/// `src-tauri/tauri.conf.json:41` stores.
sealed class ReleaseKeyState {
  const ReleaseKeyState();
}

/// A prehashed ("ED") key: the only form a signature can be verified against.
final class ReleaseKeyPrehashed extends ReleaseKeyState {
  const ReleaseKeyPrehashed();

  @override
  String toString() => 'ReleaseKeyPrehashed()';
}

/// A retired ("Ed") key. Every signature such a key can produce is refused by a
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
  /// startup.
  Future<ReleaseKeyState> classifyKey(String publicKeyB64);

  /// Whether the artefact at [artifactPath] is the one [signatureB64] signs.
  ///
  /// The path is passed rather than the bytes, and that is deliberate: an
  /// installer is far larger than it is comfortable to hold in memory, and the
  /// minisign form this feed uses pre-hashes with BLAKE2b-512, so the Rust side
  /// can read and hash the file in one pass. [byteLength] travels with it so the
  /// bridge can refuse a file whose length does not match what the client wrote.
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
/// file. The Rust bridge replaces this class and nothing else.
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
