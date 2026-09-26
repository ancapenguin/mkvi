//! Audited local security primitives. No application-defined cryptography.
use std::path::Path;
#[cfg(test)]
use std::{collections::HashMap, sync::Mutex};

use base64::{engine::general_purpose::STANDARD_NO_PAD, Engine as _};
use chacha20poly1305::{
    aead::{Aead, KeyInit, OsRng, Payload},
    XChaCha20Poly1305, XNonce,
};
use ed25519_dalek::{Signer, SigningKey, VerifyingKey};
use rand_core::RngCore;
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use zeroize::Zeroizing;

const SERVICE: &str = "app.mkvi.desktop";
const IDENTITY_SECRET: &str = "device-signing-key-v1";
const HISTORY_SECRET: &str = "history-key-v1";
const HISTORY_AAD: &[u8] = b"mkvi/history-payload/v1";

#[derive(Debug, Error)]
pub enum SecurityError {
    #[error("işletim sistemi güvenli deposu hatası: {0}")]
    SecretStore(String),
    /// A required keyring entry is gone while local data still depends on it.
    /// Minting a replacement would orphan that data, so it is reported instead.
    #[error("güvenli depoda '{name}' kaydı bulunamadı; yerel veriler hâlâ bu kayda bağlı")]
    KeyringEntryMissing { name: String },
    /// The store reported a successful write but could not return the value. That
    /// is exactly how a `keyring` backend that degraded to its in-memory mock
    /// behaves, and it used to make every launch look like a brand new install.
    #[error("güvenli gizli depo kullanılamıyor: yazılan değer geri okunamadı")]
    SecretStoreMissing,
    #[error("geçersiz saklanmış gizli veri")]
    InvalidSecret,
    #[error("kriptografik işlem başarısız oldu")]
    Crypto,
    #[error("yerel geçmiş veritabanı hatası: {0}")]
    Database(#[from] rusqlite::Error),
    #[error("yerel geçmiş verisi çözülemedi")]
    Serialization(#[from] serde_json::Error),
    #[error("mesaj kimliği boş veya çok uzun")]
    InvalidMessageId,
}

/// Tells the secret loaders whether the install still has nothing to lose.
///
/// A missing secret is only ever created on a pristine install. Anywhere else it
/// is an error, because re-minting a device identity or a database key is what
/// made MKVI forget its peer and ask for a pairing code again.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SecretOrigin {
    /// Nothing on disk depends on this secret yet.
    FirstRun,
    /// Local state already exists and cannot be read without this secret.
    Existing,
}

impl SecretOrigin {
    /// A paired install must never re-mint its identity: the stored peer was
    /// verified against the old key and would be unusable afterwards.
    pub fn from_known_peers(known_peers: usize) -> Self {
        if known_peers == 0 {
            Self::FirstRun
        } else {
            Self::Existing
        }
    }

    /// SQLite leaves a zero byte file until the first page is written, so any
    /// non-empty database means rows are already sealed with this key.
    pub fn from_database_file(path: &Path) -> Self {
        match std::fs::metadata(path) {
            Ok(metadata) if metadata.len() > 0 => Self::Existing,
            _ => Self::FirstRun,
        }
    }
}

/// Windows'ta Credential Manager/DPAPI, diğer desteklenen masaüstlerinde yerel
/// sistem anahtarlığını kullanır. Testler bellek içi uygulama kullanır.
pub trait SecretStore: Send + Sync {
    fn read(&self, name: &str) -> Result<Option<String>, SecurityError>;
    fn write(&self, name: &str, value: &str) -> Result<(), SecurityError>;
}

#[derive(Default)]
pub struct OsSecretStore;

impl SecretStore for OsSecretStore {
    fn read(&self, name: &str) -> Result<Option<String>, SecurityError> {
        let entry = keyring::Entry::new(SERVICE, name)
            .map_err(|e| SecurityError::SecretStore(e.to_string()))?;
        match entry.get_password() {
            Ok(value) => Ok(Some(value)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(e) => Err(SecurityError::SecretStore(e.to_string())),
        }
    }
    fn write(&self, name: &str, value: &str) -> Result<(), SecurityError> {
        keyring::Entry::new(SERVICE, name)
            .map_err(|e| SecurityError::SecretStore(e.to_string()))?
            .set_password(value)
            .map_err(|e| SecurityError::SecretStore(e.to_string()))
    }
}

#[cfg(test)]
#[derive(Default)]
struct MemorySecretStore(Mutex<HashMap<String, String>>);
#[cfg(test)]
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
#[cfg(test)]
impl MemorySecretStore {
    /// Models a keyring entry that disappeared between two launches.
    fn wipe(&self) {
        self.0.lock().expect("mutex").clear();
    }
}

/// Models the historical `keyring` failure: `write` reports success and then
/// forgets the value, so the next launch cannot read back what it just stored.
#[cfg(test)]
#[derive(Default)]
struct LossyWriteSecretStore(Mutex<HashMap<String, String>>);
#[cfg(test)]
impl SecretStore for LossyWriteSecretStore {
    fn read(&self, name: &str) -> Result<Option<String>, SecurityError> {
        Ok(self.0.lock().expect("mutex").get(name).cloned())
    }
    fn write(&self, _name: &str, _value: &str) -> Result<(), SecurityError> {
        Ok(())
    }
}

/// Stable Ed25519 device identity. Its private seed never crosses this module.
pub struct DeviceIdentity {
    signing_key: SigningKey,
}
impl DeviceIdentity {
    /// Restores the device identity, creating one only on a genuine first run.
    pub fn load_or_create(
        store: &dyn SecretStore,
        origin: SecretOrigin,
    ) -> Result<Self, SecurityError> {
        if let Some(value) = store.read(IDENTITY_SECRET)? {
            let seed = decode_key(&value)?;
            return Ok(Self {
                signing_key: SigningKey::from_bytes(&seed),
            });
        }
        if origin == SecretOrigin::Existing {
            return Err(SecurityError::KeyringEntryMissing {
                name: IDENTITY_SECRET.into(),
            });
        }
        let signing_key = SigningKey::generate(&mut OsRng);
        store_verified(
            store,
            IDENTITY_SECRET,
            &Zeroizing::new(STANDARD_NO_PAD.encode(signing_key.to_bytes())),
        )?;
        Ok(Self { signing_key })
    }
    pub fn public_key(&self) -> [u8; 32] {
        self.signing_key.verifying_key().to_bytes()
    }
    pub fn public_key_base64(&self) -> String {
        STANDARD_NO_PAD.encode(self.public_key())
    }
    pub fn sign(&self, message: &[u8]) -> [u8; 64] {
        self.signing_key.sign(message).to_bytes()
    }
    pub fn verify(public_key: &[u8; 32], message: &[u8], signature: &[u8; 64]) -> bool {
        VerifyingKey::from_bytes(public_key)
            .map(|key| {
                key.verify_strict(message, &ed25519_dalek::Signature::from_bytes(signature))
                    .is_ok()
            })
            .unwrap_or(false)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoryMessage {
    pub id: String,
    pub conversation_id: String,
    pub sender_device_id: String,
    pub sent_at_ms: i64,
    pub body: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KnownPeer {
    pub public_key: String,
    pub discovery_id: String,
    pub display_name: String,
    pub paired_at_ms: i64,
}

/// SQLite retains ordering and record IDs only. Message body, conversation and
/// sender metadata are protected by XChaCha20-Poly1305 with a random nonce.
pub struct EncryptedHistory {
    connection: Connection,
    cipher: XChaCha20Poly1305,
}
impl EncryptedHistory {
    pub fn open(path: impl AsRef<Path>, store: &dyn SecretStore) -> Result<Self, SecurityError> {
        let path = path.as_ref();
        // An existing database is sealed with the key we are about to look up, so
        // a missing keyring entry is never quietly replaced by a fresh one.
        let key = load_or_create_key(
            store,
            HISTORY_SECRET,
            SecretOrigin::from_database_file(path),
        )?;
        let connection = Connection::open(path)?;
        connection.execute_batch(
            "PRAGMA foreign_keys = ON; PRAGMA secure_delete = ON;
          CREATE TABLE IF NOT EXISTS encrypted_history (
            id TEXT PRIMARY KEY, created_at_ms INTEGER NOT NULL,
            nonce BLOB NOT NULL CHECK(length(nonce) = 24), ciphertext BLOB NOT NULL);
          CREATE TABLE IF NOT EXISTS encrypted_peers (
            id TEXT PRIMARY KEY, created_at_ms INTEGER NOT NULL,
            nonce BLOB NOT NULL CHECK(length(nonce) = 24), ciphertext BLOB NOT NULL);",
        )?;
        let cipher =
            XChaCha20Poly1305::new_from_slice(key.as_slice()).map_err(|_| SecurityError::Crypto)?;
        Ok(Self { connection, cipher })
    }
    pub fn append(&self, message: &HistoryMessage) -> Result<(), SecurityError> {
        if message.id.is_empty() || message.id.len() > 128 {
            return Err(SecurityError::InvalidMessageId);
        }
        let bytes = serde_json::to_vec(message)?;
        let mut nonce = [0_u8; 24];
        OsRng.fill_bytes(&mut nonce);
        let ciphertext = self
            .cipher
            .encrypt(
                XNonce::from_slice(&nonce),
                Payload {
                    msg: &bytes,
                    aad: HISTORY_AAD,
                },
            )
            .map_err(|_| SecurityError::Crypto)?;
        self.connection.execute("INSERT INTO encrypted_history (id, created_at_ms, nonce, ciphertext) VALUES (?1, ?2, ?3, ?4)", params![message.id, message.sent_at_ms, nonce.as_slice(), ciphertext])?;
        Ok(())
    }
    pub fn list(&self, limit: u32) -> Result<Vec<HistoryMessage>, SecurityError> {
        let mut query = self.connection.prepare(
            "SELECT nonce, ciphertext FROM encrypted_history ORDER BY created_at_ms DESC LIMIT ?1",
        )?;
        let rows = query.query_map([i64::from(limit.min(500))], |row| {
            Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, Vec<u8>>(1)?))
        })?;
        rows.map(|row| {
            let (nonce, ciphertext) = row?;
            if nonce.len() != 24 {
                return Err(SecurityError::InvalidSecret);
            }
            let plaintext = self
                .cipher
                .decrypt(
                    XNonce::from_slice(&nonce),
                    Payload {
                        msg: &ciphertext,
                        aad: HISTORY_AAD,
                    },
                )
                .map_err(|_| SecurityError::Crypto)?;
            Ok(serde_json::from_slice(&plaintext)?)
        })
        .collect()
    }

    pub fn remember_peer(&self, peer: &KnownPeer) -> Result<(), SecurityError> {
        if peer.public_key.is_empty()
            || peer.public_key.len() > 128
            || peer.discovery_id.len() != 43
            || peer.display_name.len() > 80
        {
            return Err(SecurityError::InvalidSecret);
        }
        let bytes = serde_json::to_vec(peer)?;
        let mut nonce = [0_u8; 24];
        OsRng.fill_bytes(&mut nonce);
        let ciphertext = self
            .cipher
            .encrypt(
                XNonce::from_slice(&nonce),
                Payload {
                    msg: &bytes,
                    aad: HISTORY_AAD,
                },
            )
            .map_err(|_| SecurityError::Crypto)?;
        self.connection.execute(
            "INSERT OR REPLACE INTO encrypted_peers (id, created_at_ms, nonce, ciphertext) VALUES (?1, ?2, ?3, ?4)",
            params![peer.public_key, peer.paired_at_ms, nonce.as_slice(), ciphertext],
        )?;
        Ok(())
    }

    pub fn peers(&self) -> Result<Vec<KnownPeer>, SecurityError> {
        let mut query = self
            .connection
            .prepare("SELECT nonce, ciphertext FROM encrypted_peers ORDER BY created_at_ms DESC")?;
        let rows = query.query_map([], |row| {
            Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, Vec<u8>>(1)?))
        })?;
        rows.map(|row| {
            let (nonce, ciphertext) = row?;
            if nonce.len() != 24 {
                return Err(SecurityError::InvalidSecret);
            }
            let plaintext = self
                .cipher
                .decrypt(
                    XNonce::from_slice(&nonce),
                    Payload {
                        msg: &ciphertext,
                        aad: HISTORY_AAD,
                    },
                )
                .map_err(|_| SecurityError::Crypto)?;
            Ok(serde_json::from_slice(&plaintext)?)
        })
        .collect()
    }
}

fn load_or_create_key(
    store: &dyn SecretStore,
    name: &str,
    origin: SecretOrigin,
) -> Result<Zeroizing<[u8; 32]>, SecurityError> {
    if let Some(value) = store.read(name)? {
        return decode_key(&value);
    }
    if origin == SecretOrigin::Existing {
        return Err(SecurityError::KeyringEntryMissing {
            name: name.into(),
        });
    }
    let mut key = Zeroizing::new([0_u8; 32]);
    OsRng.fill_bytes(key.as_mut_slice());
    store_verified(store, name, &Zeroizing::new(STANDARD_NO_PAD.encode(key.as_slice())))?;
    Ok(key)
}

/// Writes a secret and immediately reads it back.
///
/// `keyring` 3 silently degrades to an in-memory mock store when no platform
/// backend feature is compiled in, so a `write` can report success and still be
/// gone by the next launch. Never trust a write that cannot be read back.
fn store_verified(store: &dyn SecretStore, name: &str, value: &str) -> Result<(), SecurityError> {
    store.write(name, value)?;
    if store.read(name)?.as_deref() == Some(value) {
        return Ok(());
    }
    debug_assert!(
        false,
        "secret store accepted '{name}' but did not return it: no platform backend is active"
    );
    Err(SecurityError::SecretStoreMissing)
}

fn decode_key(value: &str) -> Result<Zeroizing<[u8; 32]>, SecurityError> {
    let bytes = decode_exact(value, 32)?;
    let key: [u8; 32] = bytes
        .as_slice()
        .try_into()
        .map_err(|_| SecurityError::InvalidSecret)?;
    Ok(Zeroizing::new(key))
}

fn decode_exact(value: &str, expected: usize) -> Result<Zeroizing<Vec<u8>>, SecurityError> {
    let bytes = STANDARD_NO_PAD
        .decode(value)
        .map_err(|_| SecurityError::InvalidSecret)?;
    if bytes.len() == expected {
        Ok(Zeroizing::new(bytes))
    } else {
        Err(SecurityError::InvalidSecret)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn identity_is_stable_and_signatures_verify() {
        let store = MemorySecretStore::default();
        let first = DeviceIdentity::load_or_create(&store, SecretOrigin::FirstRun).unwrap();
        let sig = first.sign(b"pairing transcript");
        assert!(DeviceIdentity::verify(
            &first.public_key(),
            b"pairing transcript",
            &sig
        ));
        assert!(!DeviceIdentity::verify(
            &first.public_key(),
            b"changed",
            &sig
        ));
        assert_eq!(
            first.public_key(),
            DeviceIdentity::load_or_create(&store, SecretOrigin::FirstRun)
                .unwrap()
                .public_key()
        );
    }
    #[test]
    fn encrypted_history_round_trips_without_plaintext_on_disk() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("history.sqlite3");
        let store = MemorySecretStore::default();
        let history = EncryptedHistory::open(&path, &store).unwrap();
        let message = HistoryMessage {
            id: "m-1".into(),
            conversation_id: "c-1".into(),
            sender_device_id: "d-1".into(),
            sent_at_ms: 42,
            body: "gizli mesaj".into(),
        };
        history.append(&message).unwrap();
        drop(history);
        let reopened = EncryptedHistory::open(&path, &store).unwrap();
        assert_eq!(reopened.list(10).unwrap(), vec![message]);
        assert!(!std::fs::read(&path)
            .unwrap()
            .windows("gizli mesaj".len())
            .any(|bytes| bytes == "gizli mesaj".as_bytes()));
    }

    #[test]
    fn known_peer_round_trips_encrypted() {
        let temp = tempfile::tempdir().unwrap();
        let store = MemorySecretStore::default();
        let history = EncryptedHistory::open(temp.path().join("history.sqlite3"), &store).unwrap();
        let peer = KnownPeer {
            public_key: "test-public-key".into(),
            discovery_id: "A".repeat(43),
            display_name: "Kuzenim".into(),
            paired_at_ms: 7,
        };
        history.remember_peer(&peer).unwrap();
        assert_eq!(history.peers().unwrap(), vec![peer]);
    }

    #[test]
    fn a_pristine_install_still_creates_its_secrets() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("history.sqlite3");
        let store = MemorySecretStore::default();
        assert_eq!(SecretOrigin::from_database_file(&path), SecretOrigin::FirstRun);
        assert!(EncryptedHistory::open(&path, &store).is_ok());
        assert!(DeviceIdentity::load_or_create(&store, SecretOrigin::from_known_peers(0)).is_ok());
        assert!(store.read(IDENTITY_SECRET).unwrap().is_some());
        assert!(store.read(HISTORY_SECRET).unwrap().is_some());
    }

    #[test]
    fn a_wiped_identity_entry_never_re_keys_a_paired_install() {
        let store = MemorySecretStore::default();
        let paired = DeviceIdentity::load_or_create(&store, SecretOrigin::FirstRun).unwrap();
        store.wipe();
        let error = match DeviceIdentity::load_or_create(&store, SecretOrigin::from_known_peers(1)) {
            Ok(_) => panic!("a paired install must not be handed a brand new identity"),
            Err(error) => error,
        };
        assert!(
            matches!(error, SecurityError::KeyringEntryMissing { .. }),
            "unexpected error: {error}"
        );
        // Nothing was written over the missing entry either, so the install is
        // still waiting for its real key rather than holding a stranger's.
        assert!(store.read(IDENTITY_SECRET).unwrap().is_none());
        assert_ne!(paired.public_key(), [0_u8; 32]);
    }

    #[test]
    fn a_wiped_history_key_never_orphans_an_existing_database() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("history.sqlite3");
        let store = MemorySecretStore::default();
        let history = EncryptedHistory::open(&path, &store).unwrap();
        history
            .remember_peer(&KnownPeer {
                public_key: "test-public-key".into(),
                discovery_id: "A".repeat(43),
                display_name: "Kuzenim".into(),
                paired_at_ms: 7,
            })
            .unwrap();
        drop(history);
        store.wipe();
        assert_eq!(SecretOrigin::from_database_file(&path), SecretOrigin::Existing);
        let error = match EncryptedHistory::open(&path, &store) {
            Ok(_) => panic!("an existing database must not be re-sealed with a fresh key"),
            Err(error) => error,
        };
        assert!(
            matches!(error, SecurityError::KeyringEntryMissing { .. }),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn a_store_that_drops_the_write_fails_instead_of_minting_a_new_identity() {
        let store = LossyWriteSecretStore::default();
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            DeviceIdentity::load_or_create(&store, SecretOrigin::FirstRun)
        }));
        match outcome {
            // Debug builds trip the `debug_assert!` on the broken store contract.
            Err(_) => {}
            Ok(Ok(_)) => panic!("a store that dropped the write must not yield an identity"),
            Ok(Err(SecurityError::SecretStoreMissing)) => {}
            Ok(Err(error)) => panic!("unexpected error: {error}"),
        }
    }
}
