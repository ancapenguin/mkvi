//! Update verification core: no network, no async, no UI framework.
//!
//! The host owns the download; this module only answers two questions. Does the
//! feed advertise something newer than what is running, and is the downloaded
//! artifact the one the release key signed. Both are pure functions over bytes.

use std::collections::HashMap;

use base64::{engine::general_purpose::STANDARD, Engine as _};
use minisign_verify::{PublicKey, Signature};
use serde::{Deserialize, Serialize};
use thiserror::Error;

/// The only target the desktop shell ships, named the way Tauri names it.
const WINDOWS_TARGET: &str = "windows-x86_64";

/// A release advertised by the static Tauri `latest.json` feed.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateInfo {
    pub version: String,
    pub notes: String,
    pub url: String,
    pub signature: String,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum UpdateError {
    #[error("Güncelleme bilgisi okunamadı.")]
    MalformedFeed,
    #[error("Bu cihaz için yayınlanmış güncelleme dosyası yok.")]
    UnsupportedPlatform,
    #[error("Güncelleme imzası okunamadı.")]
    MalformedSignature,
    #[error("Güncelleme anahtarı okunamadı.")]
    MalformedKey,
    #[error("Güncelleme dosyasının imzası doğrulanamadı; indirilen dosya değiştirilmiş olabilir.")]
    SignatureRejected,
    /// The release key, or a signature made with it, uses minisign's retired
    /// "legacy" algorithm instead of the pre-hashed one.
    ///
    /// This is deliberately a separate error rather than a generic rejection.
    /// MKVI 0.1.4's configured key is a legacy key (verified: its algorithm
    /// field decodes to `Ed`, not `ED`), so with a strict verifier every
    /// signature that key can ever produce is refused. Reporting that as
    /// "the file may have been modified" would send a user hunting for an
    /// attacker who does not exist.
    #[error("Yayın anahtarı eski (legacy) biçimde. Anahtar prehashed biçimde yeniden üretilmeli; imzası doğrulanamayan güncelleme reddedildi.")]
    LegacyKey,
}

/// The subset of `latest.json` this core reads. Unknown members such as
/// `pub_date` are ignored rather than rejected.
#[derive(Debug, Deserialize)]
struct Feed {
    version: String,
    #[serde(default)]
    notes: String,
    #[serde(default)]
    platforms: HashMap<String, FeedPlatform>,
}

#[derive(Debug, Deserialize)]
struct FeedPlatform {
    url: String,
    signature: String,
}

/// Returns the offered release, or `None` when the feed is not newer than
/// `current_version`.
pub fn parse_feed(json: &str, current_version: &str) -> Result<Option<UpdateInfo>, UpdateError> {
    let feed: Feed = serde_json::from_str(json).map_err(|_| UpdateError::MalformedFeed)?;
    if !is_newer(&feed.version, current_version) {
        return Ok(None);
    }
    let platform = feed
        .platforms
        .get(WINDOWS_TARGET)
        .ok_or(UpdateError::UnsupportedPlatform)?;
    Ok(Some(UpdateInfo {
        version: feed.version,
        notes: feed.notes,
        url: platform.url.clone(),
        signature: platform.signature.clone(),
    }))
}

/// Verifies a downloaded artifact against the release signature.
///
/// The whole buffer is verified on every call. Only the pre-hashed
/// (BLAKE2B-512) minisign form is accepted and `allow_legacy` is hard coded to
/// `false`, so there is no parameter, flag or environment switch that can turn
/// this into a partial or a weaker check.
///
/// A legacy key or signature is reported as [`UpdateError::LegacyKey`] rather
/// than as a plain rejection, because a strict verifier refuses every signature
/// the retired algorithm can produce and "the download may be tampered with" is
/// then a lie.
pub fn verify_artifact(
    bytes: &[u8],
    signature_b64: &str,
    public_key_b64: &str,
) -> Result<(), UpdateError> {
    if key_is_legacy(public_key_b64)? {
        return Err(UpdateError::LegacyKey);
    }
    let block = signature_block(signature_b64)?;
    // Named explicitly rather than "not legacy": an unrecognised algorithm is a
    // malformed signature, not something to hand to the verifier.
    match algorithm_of(&block) {
        Some(ALG_PREHASHED) => {}
        Some(ALG_LEGACY) => return Err(UpdateError::LegacyKey),
        _ => return Err(UpdateError::MalformedSignature),
    }
    let signature = Signature::decode(&block).map_err(|_| UpdateError::MalformedSignature)?;
    decode_public_key(public_key_b64)?
        .verify(bytes, &signature, false)
        .map_err(|_| UpdateError::SignatureRejected)
}

/// Whether the configured release key is a retired "legacy" minisign key.
///
/// Only the pre-hashed algorithm is ever accepted, so this is what a caller
/// checks at startup to explain an update failure instead of leaving the user
/// with a signature error. A key that cannot be read at all is an error here
/// too, since the same malformed value would fail later anyway.
///
/// Both shapes a key is stored in are accepted: the bare 42 byte key and a whole
/// `minisign.pub` file (which is what `tauri.conf.json` holds, base64 encoded).
pub fn key_is_legacy(public_key_b64: &str) -> Result<bool, UpdateError> {
    let trimmed = public_key_b64.trim();
    if let Ok(raw) = STANDARD.decode(trimmed) {
        // The same base64 encodes either the bare key bytes or a `.pub` file.
        if let Ok(text) = std::str::from_utf8(&raw) {
            if let Some(algorithm) = algorithm_of(text) {
                return Ok(algorithm == ALG_LEGACY);
            }
        }
        if let Some(algorithm) = raw.get(0..2) {
            return Ok(*algorithm == ALG_LEGACY);
        }
    }
    if let Some(algorithm) = algorithm_of(trimmed) {
        return Ok(algorithm == ALG_LEGACY);
    }
    Err(UpdateError::MalformedKey)
}

/// Minisign's two algorithm tags. `ED` pre-hashes the artifact with BLAKE2B-512
/// and is the only accepted form; `Ed` is the retired variant kept for
/// compatibility with old signers.
const ALG_PREHASHED: [u8; 2] = *b"ED";
const ALG_LEGACY: [u8; 2] = *b"Ed";

/// Reads the algorithm tag out of a decoded minisign block (a `.pub` or `.sig`
/// file). Line 0 is an untrusted comment, line 1 is the base64 payload, and the
/// payload starts with the two algorithm bytes.
fn algorithm_of(block: &str) -> Option<[u8; 2]> {
    let encoded = block.lines().nth(1)?.trim();
    if encoded.is_empty() {
        return None;
    }
    STANDARD.decode(encoded).ok()?.get(0..2)?.try_into().ok()
}

/// `signature_b64` is padded base64 of the whole four line `.sig` file, which is
/// exactly what a Tauri feed stores in `platforms.*.signature`.
fn signature_block(signature_b64: &str) -> Result<String, UpdateError> {
    let raw = STANDARD
        .decode(signature_b64.trim())
        .map_err(|_| UpdateError::MalformedSignature)?;
    String::from_utf8(raw).map_err(|_| UpdateError::MalformedSignature)
}

/// Accepts either a whole `minisign.pub` file in base64 — the shape
/// `tauri.conf.json` stores — or the file contents themselves.
fn key_block(public_key_b64: &str) -> Result<String, UpdateError> {
    let trimmed = public_key_b64.trim();
    if trimmed.contains("untrusted comment:") {
        return Ok(trimmed.to_owned());
    }
    let raw = STANDARD
        .decode(trimmed)
        .map_err(|_| UpdateError::MalformedKey)?;
    String::from_utf8(raw).map_err(|_| UpdateError::MalformedKey)
}

/// Accepts either the raw 42 byte minisign key or a whole `minisign.pub` file in
/// base64, which is the shape `tauri.conf.json` stores. Both name the same 32
/// byte Ed25519 key, so neither form is a weaker check than the other.
fn decode_public_key(public_key_b64: &str) -> Result<PublicKey, UpdateError> {
    let trimmed = public_key_b64.trim();
    if let Ok(key) = PublicKey::from_base64(trimmed) {
        return Ok(key);
    }
    PublicKey::decode(&key_block(trimmed)?).map_err(|_| UpdateError::MalformedKey)
}

fn is_newer(candidate: &str, current: &str) -> bool {
    match (parse_version(candidate), parse_version(current)) {
        (Some(candidate), Some(current)) => candidate > current,
        // A version either side cannot be read is never treated as an upgrade.
        _ => false,
    }
}

/// A small semver subset: numeric `major.minor.patch` with an optional
/// pre-release suffix. Build metadata takes no part in precedence, as semver
/// requires. Anything that does not parse is rejected rather than guessed at, so
/// a malformed feed can never look newer than it is.
#[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
struct Version {
    major: u64,
    minor: u64,
    patch: u64,
    /// `1` for a final release and `0` for a pre-release, which is what makes
    /// `1.0.0-alpha` sort below `1.0.0` while `alpha` still sorts below `beta`.
    final_release: u8,
    pre: String,
}

fn parse_version(value: &str) -> Option<Version> {
    let value = value.trim();
    let value = value.strip_prefix('v').unwrap_or(value);
    let value = value.split('+').next()?;
    let (core, pre) = match value.split_once('-') {
        Some((_, "")) => return None,
        Some((core, pre)) => (core, pre),
        None => (value, ""),
    };
    let mut parts = core.split('.');
    let major = parse_number(parts.next()?)?;
    let minor = parse_number(parts.next()?)?;
    let patch = parse_number(parts.next()?)?;
    if parts.next().is_some() {
        return None;
    }
    Some(Version {
        major,
        minor,
        patch,
        final_release: u8::from(pre.is_empty()),
        pre: pre.to_string(),
    })
}

fn parse_number(value: &str) -> Option<u64> {
    // `u64`'s parser would also accept a leading `+`, which semver does not.
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    value.parse().ok()
}

/// Test-only BLAKE2b-512, the pre-hash minisign signs.
///
/// `minisign-verify` keeps its implementation private and the fixture has to
/// produce a *pre-hashed* signature to exercise the strict path, so the hash is
/// spelled out here instead of taking a dependency for a test. The
/// `blake2b_matches_published_vectors` test below pins it to the published
/// BLAKE2b-512 digests, and the multi block case is checked against
/// `minisign-verify` itself in `a_payload_spanning_several_blocks_verifies`.
#[cfg(test)]
mod blake2b512 {
    const IV: [u64; 8] = [
        0x6a09_e667_f3bc_c908,
        0xbb67_ae85_84ca_a73b,
        0x3c6e_f372_fe94_f82b,
        0xa54f_f53a_5f1d_36f1,
        0x510e_527f_ade6_82d1,
        0x9b05_688c_2b3e_6c1f,
        0x1f83_d9ab_fb41_bd6b,
        0x5be0_cd19_137e_2179,
    ];

    const SIGMA: [[usize; 16]; 12] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    ];

    const BLOCK_BYTES: usize = 128;

    pub fn digest(input: &[u8]) -> [u8; 64] {
        let mut h = IV;
        // Unkeyed, unsalted parameter block with a 64 byte digest.
        h[0] ^= 0x0101_0000 ^ 64;
        let mut counter: u128 = 0;
        let mut offset = 0;
        // Every full block but the last one is compressed without the final flag.
        while input.len() - offset > BLOCK_BYTES {
            counter += BLOCK_BYTES as u128;
            compress(&mut h, &input[offset..offset + BLOCK_BYTES], counter, false);
            offset += BLOCK_BYTES;
        }
        let mut block = [0_u8; BLOCK_BYTES];
        let tail = &input[offset..];
        block[..tail.len()].copy_from_slice(tail);
        counter += tail.len() as u128;
        compress(&mut h, &block, counter, true);
        let mut out = [0_u8; 64];
        for (chunk, word) in out.chunks_exact_mut(8).zip(h) {
            chunk.copy_from_slice(&word.to_le_bytes());
        }
        out
    }

    fn compress(h: &mut [u64; 8], block: &[u8], counter: u128, last: bool) {
        let mut m = [0_u64; 16];
        for (word, chunk) in m.iter_mut().zip(block.chunks_exact(8)) {
            *word = u64::from_le_bytes(chunk.try_into().expect("8 byte chunk"));
        }
        let mut v = [0_u64; 16];
        v[..8].copy_from_slice(h);
        v[8..].copy_from_slice(&IV);
        v[12] ^= counter as u64;
        v[13] ^= (counter >> 64) as u64;
        if last {
            v[14] = !v[14];
        }
        for round in &SIGMA {
            mix(&mut v, 0, 4, 8, 12, m[round[0]], m[round[1]]);
            mix(&mut v, 1, 5, 9, 13, m[round[2]], m[round[3]]);
            mix(&mut v, 2, 6, 10, 14, m[round[4]], m[round[5]]);
            mix(&mut v, 3, 7, 11, 15, m[round[6]], m[round[7]]);
            mix(&mut v, 0, 5, 10, 15, m[round[8]], m[round[9]]);
            mix(&mut v, 1, 6, 11, 12, m[round[10]], m[round[11]]);
            mix(&mut v, 2, 7, 8, 13, m[round[12]], m[round[13]]);
            mix(&mut v, 3, 4, 9, 14, m[round[14]], m[round[15]]);
        }
        for index in 0..8 {
            h[index] ^= v[index] ^ v[index + 8];
        }
    }

    fn mix(v: &mut [u64; 16], a: usize, b: usize, c: usize, d: usize, x: u64, y: u64) {
        v[a] = v[a].wrapping_add(v[b]).wrapping_add(x);
        v[d] = (v[d] ^ v[a]).rotate_right(32);
        v[c] = v[c].wrapping_add(v[d]);
        v[b] = (v[b] ^ v[c]).rotate_right(24);
        v[a] = v[a].wrapping_add(v[b]).wrapping_add(y);
        v[d] = (v[d] ^ v[a]).rotate_right(16);
        v[c] = v[c].wrapping_add(v[d]);
        v[b] = (v[b] ^ v[c]).rotate_right(63);
    }
}

#[cfg(test)]
mod tests {
    use super::{blake2b512, key_is_legacy, parse_feed, verify_artifact, UpdateError};
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    use chacha20poly1305::aead::OsRng;
    use ed25519_dalek::{Signer, SigningKey};

    /// Minisign's pre-hashed algorithm tag ("ED"), the only form
    /// `verify_artifact` accepts.
    const PREHASHED: [u8; 2] = [0x45, 0x44];
    /// The retired tag ("Ed"). A key or signature carrying it is refused, and
    /// the refusal is reported as `LegacyKey` instead of as tampering.
    const LEGACY: [u8; 2] = [0x45, 0x64];
    const PAYLOAD: &[u8] = b"MKVI-0.1.5-setup.exe contents";

    /// Builds a throwaway release key and signs `payload` in exactly the wire
    /// shape a Tauri feed carries, so no long lived key is ever checked in.
    fn sign(payload: &[u8]) -> (String, String) {
        let signing_key = SigningKey::generate(&mut OsRng);
        let key_id = [0x5a_u8; 8];

        let mut public_key = Vec::new();
        public_key.extend_from_slice(&PREHASHED);
        public_key.extend_from_slice(&key_id);
        public_key.extend_from_slice(&signing_key.verifying_key().to_bytes());

        let signature = signing_key.sign(&blake2b512::digest(payload)).to_bytes();
        let trusted_comment = "timestamp:1700000000\tfile:mkvi";
        let mut global_input = signature.to_vec();
        global_input.extend_from_slice(trusted_comment.as_bytes());
        let global_signature = signing_key.sign(&global_input).to_bytes();

        let mut signed = Vec::new();
        signed.extend_from_slice(&PREHASHED);
        signed.extend_from_slice(&key_id);
        signed.extend_from_slice(&signature);
        let signature_file = format!(
            "untrusted comment: signature from minisign secret key\n{}\ntrusted comment: {}\n{}",
            STANDARD.encode(&signed),
            trusted_comment,
            STANDARD.encode(global_signature),
        );
        (
            STANDARD.encode(public_key),
            STANDARD.encode(signature_file.as_bytes()),
        )
    }

    fn feed_json(version: &str) -> String {
        format!(
            r#"{{"version":"{version}","notes":"Düzeltmeler","pub_date":"2026-01-05T10:00:00Z","platforms":{{"windows-x86_64":{{"url":"https://example.invalid/mkvi_{version}.msi","signature":"c2ln"}},"darwin-x86_64":{{"url":"https://example.invalid/mkvi_{version}.dmg","signature":"c2ln"}}}}}}"#
        )
    }

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|byte| format!("{byte:02x}")).collect()
    }

    #[test]
    fn a_signed_artifact_verifies() {
        let (public_key, signature) = sign(PAYLOAD);
        assert_eq!(verify_artifact(PAYLOAD, &signature, &public_key), Ok(()));
    }

    #[test]
    fn a_single_flipped_byte_fails() {
        let (public_key, signature) = sign(PAYLOAD);
        let mut tampered = PAYLOAD.to_vec();
        tampered[0] ^= 0x01;
        assert_eq!(
            verify_artifact(&tampered, &signature, &public_key),
            Err(UpdateError::SignatureRejected)
        );
        // A prefix of the artifact is not the artifact either: the whole buffer
        // is hashed and verified, never a caller supplied window.
        assert!(verify_artifact(&PAYLOAD[..PAYLOAD.len() - 1], &signature, &public_key).is_err());
    }

    #[test]
    fn a_signature_from_another_key_fails() {
        let (_, signature) = sign(PAYLOAD);
        let (other_public_key, _) = sign(PAYLOAD);
        assert!(verify_artifact(PAYLOAD, &signature, &other_public_key).is_err());
    }

    #[test]
    fn a_payload_spanning_several_blocks_verifies() {
        // 300 bytes crosses the 128 byte block boundary, so the fixture's
        // pre-hash is checked against `minisign-verify`'s own implementation.
        let payload = vec![0x5a_u8; 300];
        let (public_key, signature) = sign(&payload);
        assert_eq!(verify_artifact(&payload, &signature, &public_key), Ok(()));
        let mut tampered = payload.clone();
        tampered[299] ^= 0xff;
        assert!(verify_artifact(&tampered, &signature, &public_key).is_err());
    }

    #[test]
    fn unparseable_key_or_signature_is_rejected_before_verification() {
        let (public_key, signature) = sign(PAYLOAD);
        assert_eq!(
            verify_artifact(PAYLOAD, "base64 degil", &public_key),
            Err(UpdateError::MalformedSignature)
        );
        assert_eq!(
            verify_artifact(PAYLOAD, "", &public_key),
            Err(UpdateError::MalformedSignature)
        );
        assert_eq!(
            verify_artifact(PAYLOAD, &signature, "base64 degil"),
            Err(UpdateError::MalformedKey)
        );
    }

    /// Builds a key or signature in the retired "legacy" form: the same
    /// structure as `sign`, but tagged `Ed` and carrying an extra hash field.
    fn legacy(prehash: bool) -> (String, String) {
        let signing_key = SigningKey::generate(&mut OsRng);
        let key_id = [0x5a_u8; 8];

        let mut public_key = Vec::new();
        public_key.extend_from_slice(&LEGACY);
        public_key.extend_from_slice(&key_id);
        public_key.extend_from_slice(&signing_key.verifying_key().to_bytes());

        // A legacy signature covers the artifact itself; only its length differs
        // in a way the reader can see, and its bytes are never verified here.
        let mut signed = Vec::new();
        signed.extend_from_slice(&LEGACY);
        signed.extend_from_slice(&key_id);
        signed.extend_from_slice(&signing_key.sign(PAYLOAD).to_bytes());
        if prehash {
            signed.extend_from_slice(&blake2b512::digest(PAYLOAD));
        }
        let signature_file = format!(
            "untrusted comment: signature from minisign secret key\n{}\ntrusted comment: timestamp:1700000000\n{}",
            STANDARD.encode(&signed),
            STANDARD.encode([0_u8; 64]),
        );
        (
            STANDARD.encode(public_key),
            STANDARD.encode(signature_file.as_bytes()),
        )
    }

    #[test]
    fn a_prehashed_key_is_not_reported_as_legacy() {
        let (public_key, _) = sign(PAYLOAD);
        assert_eq!(key_is_legacy(&public_key), Ok(false));
        // The same key as a whole `.pub` file, which is the shape
        // `tauri.conf.json` stores.
        let file = format!(
            "untrusted comment: minisign public key: 89CA7B4A0AEA5641\n{}",
            &public_key
        );
        assert_eq!(key_is_legacy(&STANDARD.encode(file.as_bytes())), Ok(false));
    }

    /// MKVI 0.1.4's configured key is legacy, and a strict verifier refuses
    /// every signature such a key can produce. That has to be a named,
    /// explainable error rather than a generic rejection, otherwise a user is
    /// told to hunt for tampering that cannot exist.
    #[test]
    fn a_legacy_key_is_named_instead_of_looking_like_tampering() {
        let (public_key, signature) = legacy(false);
        assert_eq!(key_is_legacy(&public_key), Ok(true));
        assert_eq!(
            verify_artifact(PAYLOAD, &signature, &public_key),
            Err(UpdateError::LegacyKey)
        );
    }

    #[test]
    fn a_legacy_signature_under_a_prehashed_key_is_also_named() {
        // A key that is fine, but the signature was made by a retired signer.
        let (public_key, _) = sign(PAYLOAD);
        let (_, legacy_signature) = legacy(true);
        assert_eq!(
            verify_artifact(PAYLOAD, &legacy_signature, &public_key),
            Err(UpdateError::LegacyKey)
        );
    }

    #[test]
    fn a_key_that_cannot_be_read_is_not_silently_treated_as_fine() {
        assert_eq!(key_is_legacy("base64 degil"), Err(UpdateError::MalformedKey));
        assert_eq!(key_is_legacy(""), Err(UpdateError::MalformedKey));
    }

    #[test]
    fn a_newer_release_is_offered() {
        let info = parse_feed(&feed_json("0.1.5"), "0.1.4")
            .unwrap()
            .expect("0.1.5 is newer than 0.1.4");
        assert_eq!(info.version, "0.1.5");
        assert_eq!(info.notes, "Düzeltmeler");
        assert_eq!(info.url, "https://example.invalid/mkvi_0.1.5.msi");
        assert_eq!(info.signature, "c2ln");
    }

    #[test]
    fn an_older_or_equal_release_is_not_offered() {
        assert_eq!(parse_feed(&feed_json("0.1.4"), "0.1.4").unwrap(), None);
        assert_eq!(parse_feed(&feed_json("0.1.3"), "0.1.4").unwrap(), None);
        // A pre-release of the version already running is not an upgrade, while
        // its final release is.
        assert_eq!(parse_feed(&feed_json("0.1.4-rc.1"), "0.1.4").unwrap(), None);
        assert!(parse_feed(&feed_json("0.1.5"), "0.1.5-rc.1").unwrap().is_some());
        // Build metadata takes no part in precedence, so a rebuild is not one
        // either, but a real bump carrying metadata still is.
        assert_eq!(parse_feed(&feed_json("0.1.4+build.9"), "0.1.4").unwrap(), None);
        assert!(parse_feed(&feed_json("0.1.5+build.1"), "0.1.4").unwrap().is_some());
        // A version either side cannot be read is never guessed at.
        assert_eq!(parse_feed(&feed_json("son sürüm"), "0.1.4").unwrap(), None);
        assert_eq!(parse_feed(&feed_json("0.1"), "0.1.4").unwrap(), None);
    }

    #[test]
    fn a_malformed_feed_is_an_error_not_an_upgrade() {
        assert_eq!(parse_feed("json degil", "0.1.4"), Err(UpdateError::MalformedFeed));
        assert_eq!(
            parse_feed(r#"{"notes":"sadece notlar"}"#, "0.1.4"),
            Err(UpdateError::MalformedFeed)
        );
    }

    #[test]
    fn a_newer_release_without_this_platform_is_an_error() {
        let json = r#"{"version":"9.9.9","notes":"","platforms":{"darwin-x86_64":{"url":"u","signature":"s"}}}"#;
        assert_eq!(parse_feed(json, "0.1.4"), Err(UpdateError::UnsupportedPlatform));
    }

    #[test]
    fn blake2b_matches_published_vectors() {
        assert_eq!(
            hex(&blake2b512::digest(b"")),
            "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419\
             d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce"
        );
        assert_eq!(
            hex(&blake2b512::digest(b"abc")),
            "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1\
             7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
        );
    }
}
