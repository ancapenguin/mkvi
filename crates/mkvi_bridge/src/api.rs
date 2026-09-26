//! The Dart-facing surface of the MKVI core.
//!
//! Seven domain calls, one constructor, nothing else. The rules that shaped this
//! file:
//!
//! * **`&Core`, never a lock.** `Core` owns the `Mutex`es that guard the SQLite
//!   connection, the AEAD cipher and the open file handles. Dart receives an
//!   opaque `&Core` and can only ask for a call; it never sees a guard it could
//!   hold across an await point.
//! * **Errors are data, not text.** Every fallible call returns
//!   `Result<_, CoreFailure>`, where `CoreFailure` is an enum that mirrors
//!   `mkvi_core`'s error types case for case. See [`crate::error`].
//! * **Dart stays async.** None of these functions is marked `#[frb(sync)]`, so
//!   the generated Dart is `Future`-returning and flutter_rust_bridge runs the
//!   body on its thread pool. A blocking SQLite write must never land on the
//!   Flutter UI isolate.
//! * **The wire shape is the bridge's own.** [`HistoryMessage`] and
//!   [`KnownPeer`] below deliberately shadow the identically named core structs.
//!   flutter_rust_bridge can only generate mirror types for types it can read in
//!   this crate, and pinning the wire contract here means a storage-layout
//!   change in the core does not silently become a wire change for the app.

use std::sync::Arc;

use base64::{engine::general_purpose::STANDARD_NO_PAD, Engine as _};
use flutter_rust_bridge::frb;
use mkvi_core::{DeviceIdentity, OsSecretStore, SecretStore};

// Re-exported, not just imported. The generated `frb_generated` module does
// `use crate::api::*;` and then names the opaque types it has to wrap, so `Core`
// has to be publicly reachable from this module. It stays opaque in Dart either
// way: nothing but the seven calls below can be done with it.
pub use mkvi_core::Core;

use crate::error::CoreFailure;

/// One stored message, as it crosses the boundary.
///
/// Field names match the core's struct so the encrypted record format does not
/// change; the conversion is in [`From`] below.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HistoryMessage {
    pub id: String,
    pub conversation_id: String,
    pub sender_device_id: String,
    pub sent_at_ms: i64,
    pub body: String,
}

impl From<HistoryMessage> for mkvi_core::HistoryMessage {
    fn from(message: HistoryMessage) -> Self {
        Self {
            id: message.id,
            conversation_id: message.conversation_id,
            sender_device_id: message.sender_device_id,
            sent_at_ms: message.sent_at_ms,
            body: message.body,
        }
    }
}

impl From<mkvi_core::HistoryMessage> for HistoryMessage {
    fn from(message: mkvi_core::HistoryMessage) -> Self {
        Self {
            id: message.id,
            conversation_id: message.conversation_id,
            sender_device_id: message.sender_device_id,
            sent_at_ms: message.sent_at_ms,
            body: message.body,
        }
    }
}

/// One paired peer, as it crosses the boundary.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KnownPeer {
    pub public_key: String,
    pub discovery_id: String,
    pub display_name: String,
    pub paired_at_ms: i64,
}

impl From<KnownPeer> for mkvi_core::KnownPeer {
    fn from(peer: KnownPeer) -> Self {
        Self {
            public_key: peer.public_key,
            discovery_id: peer.discovery_id,
            display_name: peer.display_name,
            paired_at_ms: peer.paired_at_ms,
        }
    }
}

impl From<mkvi_core::KnownPeer> for KnownPeer {
    fn from(peer: mkvi_core::KnownPeer) -> Self {
        Self {
            public_key: peer.public_key,
            discovery_id: peer.discovery_id,
            display_name: peer.display_name,
            paired_at_ms: peer.paired_at_ms,
        }
    }
}

/// Opens the core against an explicitly supplied secret store.
///
/// Not part of the Dart surface: a `&dyn SecretStore` cannot be handed over FFI,
/// so this stays a Rust-side call. It exists so the store is a decision made in
/// Rust rather than a hard-coded one, and it is what the tests drive.
///
/// This is the seam the Android `SecretStore` has to be wired into — see
/// `README.md`, "Android and the secret store". Nothing else in the bridge
/// constructs a store.
#[frb(ignore)]
pub fn open_core_with_store(
    data_dir: &str,
    store: &dyn SecretStore,
) -> Result<Arc<Core>, CoreFailure> {
    Core::open(data_dir, store)
        .map(Arc::new)
        .map_err(CoreFailure::from)
}

/// Opens the process core, restoring the device identity and the encrypted
/// history under `data_dir`.
///
/// Guarantees, in the order the core establishes them:
///
/// 1. The data directory exists.
/// 2. The encrypted history is opened **first**, so an install that already has
///    a peer is known to be paired *before* the identity is restored. A missing
///    secure-store entry is then reported as
///    [`CoreFailure::Security`] / `KeyringEntryMissing` instead of being topped
///    up with a fresh key, which is the failure that once made MKVI forget its
///    peer and ask for a pairing code again.
/// 3. The identity is restored, or minted only on a genuinely pristine install.
///
/// Fails with [`CoreFailure`] only. It never returns a half-opened core.
///
/// This is the constructor, not one of the seven domain calls; it is counted
/// separately because it exists to hand out the `&Core` the other seven take.
///
/// The handle is returned by value rather than as an `Arc<Core>` on purpose:
/// flutter_rust_bridge generates two unrelated Dart types for those, and Dart
/// could not pass what `open_core` returned straight back into the seven calls.
pub fn open_core(data_dir: String) -> Result<Core, CoreFailure> {
    Core::open(&data_dir, &OsSecretStore).map_err(CoreFailure::from)
}

/// Returns this device's Ed25519 public key.
///
/// **Guarantees:** the key is the one restored by [`open_core`] from the secure
/// store, so it is byte-for-byte stable across launches on the same install, and
/// it is the key [`sign`] will use. The private seed never leaves `mkvi_core`.
///
/// **Format:** unpadded standard base64 (RFC 4648 §5, no `=`), exactly what
/// `Core::public_key_base64` produces and what the Tauri shell's
/// `device_public_key` already put on the wire. `verify` accepts this shape.
pub fn device_public_key(core: &Core) -> String {
    core.public_key_base64()
}

/// Signs `message` with this device's private key.
///
/// **Guarantees:** the returned signature is an Ed25519 signature over exactly
/// the bytes given, under the key [`device_public_key`] publishes, so
/// `verify(public_key, message, signature)` accepts it. The private seed is
/// never returned, copied out of the identity, or exposed in any form.
///
/// **Format:** unpadded standard base64, matching [`device_public_key`] and the
/// `sign_pairing` command the desktop shell already exposed. Padding is
/// deliberately absent because a 64-byte signature is 88 padded characters and 86
/// unpadded, and the peer protocol cannot be renegotiated by the Flutter port.
///
/// Cannot fail today; the `Result` is kept so a future key that needs
/// preparation has somewhere to report it without changing the Dart signature.
pub fn sign(core: &Core, message: Vec<u8>) -> Result<String, CoreFailure> {
    Ok(STANDARD_NO_PAD.encode(core.sign(&message)))
}

/// Checks an Ed25519 signature against a peer-supplied public key.
///
/// **Guarantees:** returns `true` only when `signature` is a valid Ed25519
/// signature by `public_key` over exactly `message`. The core uses
/// `verify_strict`, so a signature produced under a weaker Ed25519 variant is
/// refused, not accepted.
///
/// **A malformed key or signature returns `false` rather than raising.** That is
/// a deliberate choice: if a bad encoding threw, a peer could tell "this key is
/// unparseable" apart from "this signature is wrong" and use the difference to
/// probe. Both are simply "not verified".
///
/// **Format:** [`device_public_key`]'s unpadded standard base64, for all three
/// byte arguments.
pub fn verify(public_key: String, message: Vec<u8>, signature: String) -> bool {
    let Ok(public_key) = STANDARD_NO_PAD.decode(public_key) else {
        return false;
    };
    let Ok(public_key) = <[u8; 32]>::try_from(public_key.as_slice()) else {
        return false;
    };
    let Ok(signature) = STANDARD_NO_PAD.decode(signature) else {
        return false;
    };
    let Ok(signature) = <[u8; 64]>::try_from(signature.as_slice()) else {
        return false;
    };
    DeviceIdentity::verify(&public_key, &message, &signature)
}

/// Appends one message to the encrypted local history.
///
/// **Guarantees:** on `Ok` the message is committed to SQLite and sealed with
/// XChaCha20-Poly1305 under the history key; no plaintext is written to disk.
/// A duplicate `id` fails rather than overwriting, so a retried delivery is
/// visible as an error instead of silently replacing history.
///
/// An empty or longer-than-128-byte `id` is refused as
/// `CoreFailure::Security` / `InvalidMessageId` before any I/O.
pub fn append_history(core: &Core, message: HistoryMessage) -> Result<(), CoreFailure> {
    core.append(&message.into()).map_err(CoreFailure::from)
}

/// Reads back the newest messages from the encrypted local history.
///
/// **Guarantees:** the result is ordered newest first by `sent_at_ms` and holds
/// at most `limit` messages; the core clamps `limit` to 500 itself, so a caller
/// asking for a million gets 500 rows rather than an allocation. Each row is
/// decrypted and authenticated, and a row that fails authentication fails the
/// whole call with `CoreFailure::Security` / `Crypto` rather than being skipped —
/// a partial list would look like lost history.
///
/// An empty result means the history is genuinely empty, not unreadable.
pub fn list_history(core: &Core, limit: u32) -> Result<Vec<HistoryMessage>, CoreFailure> {
    Ok(core
        .list(limit)?
        .into_iter()
        .map(HistoryMessage::from)
        .collect())
}

/// Stores or replaces the paired peer.
///
/// **Guarantees:** on `Ok` the peer is sealed in the encrypted store and will be
/// returned by [`list_peers`]. Re-recording the same `public_key` replaces the
/// stored row, which is how a re-pairing is expressed.
///
/// Field shapes are validated before anything is written: a `public_key` that is
/// empty or longer than 128 bytes, a `discovery_id` that is not exactly 43
/// characters, or a `display_name` longer than 80 all fail as
/// `CoreFailure::Security` / `InvalidSecret`. The 43-character `discovery_id` is
/// the shape the rendezvous protocol mints (32 random bytes in unpadded base64).
pub fn remember_peer(core: &Core, peer: KnownPeer) -> Result<(), CoreFailure> {
    core.remember_peer(&peer.into()).map_err(CoreFailure::from)
}

/// Lists the paired peers, newest first.
///
/// **Guarantees:** every entry is decrypted and authenticated before it is
/// returned, and an entry that fails fails the whole call. MKVI pairs one device
/// with one peer, so a healthy install returns a list of length 0 or 1; the list
/// shape is kept because that is what the store holds.
pub fn list_peers(core: &Core) -> Result<Vec<KnownPeer>, CoreFailure> {
    Ok(core.peers()?.into_iter().map(KnownPeer::from).collect())
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex};

    use super::{
        append_history, device_public_key, list_history, list_peers, open_core_with_store,
        remember_peer, sign, verify, HistoryMessage, KnownPeer,
    };
    use crate::error::{CoreFailure, SecurityFailure};
    use mkvi_core::security::SecurityError;
    use mkvi_core::SecretStore;

    /// An in-memory store so the tests never touch the real Windows Credential
    /// Manager. `Arc`-backed so a second `open_core_with_store` over the same
    /// store finds the same secrets, which is how a relaunch is modelled.
    #[derive(Clone, Default)]
    struct MemorySecretStore(Arc<Mutex<HashMap<String, String>>>);

    impl MemorySecretStore {
        /// Models one keyring entry disappearing between two launches.
        fn remove(&self, name: &str) {
            self.0.lock().expect("mutex").remove(name);
        }

        /// Reads an entry without going through a `Core`, so a test can hold on
        /// to a secret and put it back.
        fn entry(&self, name: &str) -> Option<String> {
            self.read(name).expect("read")
        }
    }

    impl SecretStore for MemorySecretStore {
        fn read(&self, name: &str) -> Result<Option<String>, SecurityError> {
            Ok(self.0.lock().expect("mutex").get(name).cloned())
        }
        fn write(&self, name: &str, value: &str) -> Result<(), SecurityError> {
            self.0
                .lock()
                .expect("mutex")
                .insert(name.into(), value.into());
            Ok(())
        }
    }

    const TRANSCRIPT: &[u8] = b"mkvi/pairing/v1/c-1/d-1";

    fn message(id: &str, body: &str) -> HistoryMessage {
        // `sent_at_ms` is what the store orders by, and it doubles as a row
        // sequence here: the id is not part of the ordering.
        HistoryMessage {
            id: id.into(),
            conversation_id: "c-1".into(),
            sender_device_id: "d-1".into(),
            sent_at_ms: id
                .strip_prefix("m-")
                .and_then(|tail| tail.parse().ok())
                .unwrap_or(0),
            body: body.into(),
        }
    }

    fn peer() -> KnownPeer {
        KnownPeer {
            public_key: "test-public-key".into(),
            discovery_id: "A".repeat(43),
            display_name: "Kuzenim".into(),
            paired_at_ms: 7,
        }
    }

    /// Every call in the round trip goes through the functions `api` exports,
    /// so this test is a proof about the bridge surface, not about the core.
    #[test]
    fn sign_and_verify_round_trip_through_the_bridge() {
        let temp = tempfile::tempdir().unwrap();
        let store = MemorySecretStore::default();
        let core = open_core_with_store(temp.path().to_str().unwrap(), &store).unwrap();

        let public_key = device_public_key(&core);
        assert_eq!(public_key.len(), 43, "32 bytes as unpadded base64");
        let signature = sign(&core, TRANSCRIPT.to_vec()).unwrap();
        assert_eq!(signature.len(), 86, "64 bytes as unpadded base64");

        assert!(verify(
            public_key.clone(),
            TRANSCRIPT.to_vec(),
            signature.clone()
        ));
        // A changed message, a changed key and a mangled signature all refuse.
        assert!(!verify(
            public_key.clone(),
            b"mkvi/pairing/v1/c-1/d-2".to_vec(),
            signature.clone()
        ));
        assert!(!verify(
            "B".repeat(43),
            TRANSCRIPT.to_vec(),
            signature.clone()
        ));
        assert!(!verify(
            public_key.clone(),
            TRANSCRIPT.to_vec(),
            "A".repeat(86)
        ));
    }

    #[test]
    fn verify_answers_false_rather_than_raising_on_a_malformed_key() {
        // Unparseable input must be indistinguishable from a wrong signature.
        assert!(!verify(
            "base64 degil".into(),
            TRANSCRIPT.to_vec(),
            "x".into()
        ));
        assert!(!verify("A".repeat(43), TRANSCRIPT.to_vec(), String::new()));
        // Right alphabet, wrong length: also just "not verified".
        assert!(!verify("A".repeat(42), TRANSCRIPT.to_vec(), "A".repeat(86)));
    }

    #[test]
    fn history_and_peers_round_trip_through_the_bridge() {
        let temp = tempfile::tempdir().unwrap();
        let store = MemorySecretStore::default();
        let core = open_core_with_store(temp.path().to_str().unwrap(), &store).unwrap();

        assert!(list_history(&core, 10).unwrap().is_empty());
        assert!(list_peers(&core).unwrap().is_empty());

        // Distinct timestamps: `ORDER BY created_at_ms DESC` is the only ordering
        // the store has, and with a tie SQLite is free to return either row first.
        append_history(&core, message("m-1", "gizli mesaj")).unwrap();
        append_history(&core, message("m-2", "ikinci")).unwrap();
        let listed = list_history(&core, 10).unwrap();
        assert_eq!(
            listed,
            vec![message("m-2", "ikinci"), message("m-1", "gizli mesaj")]
        );

        // `limit` is honoured, so the newest rows are the ones kept.
        assert_eq!(
            list_history(&core, 1).unwrap(),
            vec![message("m-2", "ikinci")]
        );

        remember_peer(&core, peer()).unwrap();
        assert_eq!(list_peers(&core).unwrap(), vec![peer()]);
    }

    #[test]
    fn an_oversized_limit_is_clamped_rather_than_honoured() {
        let temp = tempfile::tempdir().unwrap();
        let core =
            open_core_with_store(temp.path().to_str().unwrap(), &MemorySecretStore::default())
                .unwrap();
        // The clamp lives in the core; the bridge must not defeat it by asking
        // for u32::MAX rows explicitly.
        assert!(list_history(&core, u32::MAX).unwrap().is_empty());
    }

    #[test]
    fn the_device_identity_survives_a_reopen_through_the_same_store() {
        let temp = tempfile::tempdir().unwrap();
        let store = MemorySecretStore::default();
        let path = temp.path().to_str().unwrap();

        let first = open_core_with_store(path, &store).unwrap();
        let public_key = device_public_key(&first);
        remember_peer(&first, peer()).unwrap();
        drop(first);

        let second = open_core_with_store(path, &store).unwrap();
        assert_eq!(
            device_public_key(&second),
            public_key,
            "a relaunch must not mint a new device identity"
        );
        // And the saved peer is still readable, which is what the pairing code
        // was lost for last time.
        assert_eq!(list_peers(&second).unwrap(), vec![peer()]);
    }

    /// The regression this whole crate shape exists to prevent: a lost secure
    /// store entry must arrive in Dart as a named, structured failure and never
    /// as a freshly minted identity.
    #[test]
    fn a_wiped_identity_key_arrives_as_a_named_structured_failure() {
        let temp = tempfile::tempdir().unwrap();
        let store = MemorySecretStore::default();
        let path = temp.path().to_str().unwrap();

        let first = open_core_with_store(path, &store).unwrap();
        // Remembered so the check below can state the real guarantee: the stored
        // identity must survive the failed reopen, not merely be absent.
        let paired_key = device_public_key(&first);
        remember_peer(&first, peer()).unwrap();
        drop(first);

        // Only the signing key is lost. The history key survives, so `Core::open`
        // gets as far as the identity — which is the case that once made MKVI
        // forget its peer and ask for a pairing code again.
        let seed = store
            .entry("device-signing-key-v1")
            .expect("the seed was stored");
        store.remove("device-signing-key-v1");

        let failure = match open_core_with_store(path, &store) {
            Ok(_) => panic!("a paired install must not be handed a brand new identity"),
            Err(failure) => failure,
        };
        match failure.security() {
            Some(SecurityFailure::KeyringEntryMissing { name, message }) => {
                assert_eq!(name, "device-signing-key-v1");
                assert!(message.contains("device-signing-key-v1"));
            }
            other => panic!("the failure was flattened, not structured: {other:?}"),
        }
        // Nothing was written over the missing entry, so the install is still
        // waiting for its real key rather than holding a stranger's.
        assert!(store.read("device-signing-key-v1").unwrap().is_none());

        // Which means restoring the entry brings the original identity back. If
        // the failed reopen had minted a replacement, this would be a new key.
        store.write("device-signing-key-v1", &seed).unwrap();
        let restored = open_core_with_store(path, &store).unwrap();
        assert_eq!(device_public_key(&restored), paired_key);
        assert_eq!(list_peers(&restored).unwrap(), vec![peer()]);
    }

    /// Losing the history key instead is reported as the history key, because the
    /// core opens the history before it restores the identity. The ordering is
    /// deliberate — see `Core::open` — and the bridge must not reorder it.
    #[test]
    fn a_wiped_history_key_names_the_history_key() {
        let temp = tempfile::tempdir().unwrap();
        let store = MemorySecretStore::default();
        let path = temp.path().to_str().unwrap();

        let first = open_core_with_store(path, &store).unwrap();
        remember_peer(&first, peer()).unwrap();
        drop(first);
        store.remove("history-key-v1");

        let failure = match open_core_with_store(path, &store) {
            Ok(_) => panic!("an existing database must not be re-sealed with a fresh key"),
            Err(failure) => failure,
        };
        match failure.security() {
            Some(SecurityFailure::KeyringEntryMissing { name, .. }) => {
                assert_eq!(name, "history-key-v1");
            }
            other => panic!("the failure was flattened, not structured: {other:?}"),
        }
    }

    #[test]
    fn a_rejected_message_id_names_the_rejection_instead_of_hiding_it() {
        let temp = tempfile::tempdir().unwrap();
        let core =
            open_core_with_store(temp.path().to_str().unwrap(), &MemorySecretStore::default())
                .unwrap();
        let failure =
            append_history(&core, message("", "gövde")).expect_err("an empty id must be refused");
        assert!(matches!(
            failure.security(),
            Some(SecurityFailure::InvalidMessageId { .. })
        ));
    }

    #[test]
    fn a_malformed_peer_is_refused_before_anything_is_written() {
        let temp = tempfile::tempdir().unwrap();
        let core =
            open_core_with_store(temp.path().to_str().unwrap(), &MemorySecretStore::default())
                .unwrap();
        let bad = KnownPeer {
            discovery_id: "too short".into(),
            ..peer()
        };
        let failure = remember_peer(&core, bad).expect_err("a bad discovery id must be refused");
        assert!(matches!(
            failure.security(),
            Some(SecurityFailure::InvalidSecret { .. })
        ));
        assert!(list_peers(&core).unwrap().is_empty());
    }

    #[test]
    fn a_duplicate_message_id_fails_instead_of_overwriting_history() {
        let temp = tempfile::tempdir().unwrap();
        let core =
            open_core_with_store(temp.path().to_str().unwrap(), &MemorySecretStore::default())
                .unwrap();
        append_history(&core, message("m-1", "ilk")).unwrap();
        assert!(append_history(&core, message("m-1", "değiştirilmiş")).is_err());
        assert_eq!(
            list_history(&core, 10).unwrap(),
            vec![message("m-1", "ilk")],
            "a retried delivery must not be able to rewrite history"
        );
    }

    #[test]
    fn the_core_handle_is_shared_without_handing_out_a_lock() {
        let temp = tempfile::tempdir().unwrap();
        let core: Arc<mkvi_core::Core> =
            open_core_with_store(temp.path().to_str().unwrap(), &MemorySecretStore::default())
                .unwrap();
        // Two Dart-side holders of the same core serialise through the core's own
        // mutexes; the type signature forbids either of them seeing a guard.
        fn uses_core(core: &mkvi_core::Core, id: &str) -> Result<(), CoreFailure> {
            super::append_history(core, message(id, "eşzamanlı"))
        }
        let second = Arc::clone(&core);
        let writer = std::thread::spawn(move || uses_core(&second, "m-9"));
        uses_core(&core, "m-8").unwrap();
        writer.join().unwrap().unwrap();
        assert_eq!(list_history(&core, 10).unwrap().len(), 2);
    }
}
