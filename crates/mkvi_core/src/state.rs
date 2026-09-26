//! The process-wide core state a host application owns and manages.
//!
//! `rusqlite::Connection` is `Send` but not `Sync`, so the history handle and the
//! open file sinks live behind mutexes that never leave this type: callers only
//! ever get `&self` methods that lock for the duration of a single call. Today the
//! Tauri shell manages one `Core`; the Flutter shell will manage its own.

use std::collections::HashMap;
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard};

use thiserror::Error;

use crate::files::{sanitize_file_name, unique_path, FileSink, MAX_FILE_BYTES};
use crate::security::{
    DeviceIdentity, EncryptedHistory, HistoryMessage, KnownPeer, SecretOrigin, SecretStore,
    SecurityError,
};

/// File name of the encrypted SQLite history inside the application data directory.
const HISTORY_FILE: &str = "history.sqlite3";

/// Every failure the core can report. The Turkish text is what the desktop shell
/// has always shown the user, so it lives here next to the code raising it and
/// hosts can forward `to_string()` unchanged.
#[derive(Debug, Error)]
pub enum CoreError {
    #[error("Yerel geçmiş kilidi kullanılamıyor.")]
    HistoryLocked,
    #[error("Yerel eş kaydı kilidi kullanılamıyor.")]
    PeerStoreLocked,
    #[error("Dosya yazma kilidi kullanılamıyor.")]
    FileSinkLocked,
    #[error("Açık dosya aktarımı yok.")]
    NoOpenTransfer,
    #[error("Aynı anda çok fazla dosya alınıyor.")]
    TooManyTransfers,
    #[error("Bu aktarım zaten açık.")]
    DuplicateTransfer,
    #[error("Dosya izin verilen boyutu aşıyor.")]
    TransferTooLarge,
    #[error("{0}")]
    Security(#[from] SecurityError),
    /// Operating system text, passed through so hosts keep reporting exactly
    /// what the file system said.
    #[error("{0}")]
    Io(String),
}

impl From<std::io::Error> for CoreError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error.to_string())
    }
}

/// Everything a front end needs from the Rust core, in one managed value.
pub struct Core {
    identity: DeviceIdentity,
    history: Mutex<EncryptedHistory>,
    sinks: Mutex<HashMap<String, FileSink>>,
}

impl Core {
    /// Prepares the data directory, opens the encrypted history and restores the
    /// device identity.
    ///
    /// The history is opened first on purpose: a paired install has to learn that
    /// a peer exists *before* the identity is restored, otherwise a missing
    /// keyring entry would be topped up with a brand new key and the saved peer
    /// would never verify again.
    pub fn open(data_dir: impl AsRef<Path>, store: &dyn SecretStore) -> Result<Self, CoreError> {
        let data_dir = data_dir.as_ref();
        std::fs::create_dir_all(data_dir)?;
        let history = EncryptedHistory::open(data_dir.join(HISTORY_FILE), store)?;
        let identity = DeviceIdentity::load_or_create(store, SecretOrigin::from_known_peers(history.peers()?.len()))?;
        Ok(Self {
            identity,
            history: Mutex::new(history),
            sinks: Mutex::new(HashMap::new()),
        })
    }

    pub fn public_key_base64(&self) -> String {
        self.identity.public_key_base64()
    }

    pub fn sign(&self, message: &[u8]) -> [u8; 64] {
        self.identity.sign(message)
    }

    pub fn append(&self, message: &HistoryMessage) -> Result<(), CoreError> {
        self.lock_history()?.append(message)?;
        Ok(())
    }

    pub fn list(&self, limit: u32) -> Result<Vec<HistoryMessage>, CoreError> {
        Ok(self.lock_history()?.list(limit)?)
    }

    pub fn remember_peer(&self, peer: &KnownPeer) -> Result<(), CoreError> {
        self.lock_peers()?.remember_peer(peer)?;
        Ok(())
    }

    pub fn peers(&self) -> Result<Vec<KnownPeer>, CoreError> {
        Ok(self.lock_peers()?.peers()?)
    }

    /// Opens a disk sink for an accepted transfer; bytes never accumulate in the UI.
    ///
    /// The concurrency cap is checked **before** the file is created. Creating
    /// first and capping afterwards (the 0.1.x behaviour) leaves a 0 byte file
    /// behind for every rejected transfer, so a peer that keeps offering files
    /// fills the download folder with empty names.
    pub fn open_sink(
        &self,
        id: &str,
        directory: &Path,
        name: &str,
        max_open: usize,
    ) -> Result<PathBuf, CoreError> {
        let mut sinks = self.lock_sinks()?;
        if sinks.len() >= max_open {
            return Err(CoreError::TooManyTransfers);
        }
        // Re-using an id replaces the sink rather than leaking the old handle.
        if sinks.contains_key(id) {
            return Err(CoreError::DuplicateTransfer);
        }
        let path = unique_path(directory, &sanitize_file_name(name));
        let handle = File::create(&path)?;
        sinks.insert(
            id.to_string(),
            FileSink {
                handle,
                path: path.clone(),
                written: 0,
            },
        );
        Ok(path)
    }

    /// Appends one chunk to an open transfer, refusing anything past the cap.
    pub fn write_sink(&self, id: &str, bytes: &[u8]) -> Result<(), CoreError> {
        let mut sinks = self.lock_sinks()?;
        let sink = sinks
            .get_mut(id)
            .ok_or(CoreError::NoOpenTransfer)?;
        let written = sink.written + bytes.len() as u64;
        if written > MAX_FILE_BYTES {
            return Err(CoreError::TransferTooLarge);
        }
        sink.handle.write_all(bytes)?;
        sink.written = written;
        Ok(())
    }

    /// Flushes and closes the sink, returning the path shown to the user.
    pub fn close_sink(&self, id: &str) -> Result<PathBuf, CoreError> {
        let mut sinks = self.lock_sinks()?;
        let mut sink = sinks.remove(id).ok_or(CoreError::NoOpenTransfer)?;
        sink.handle.flush()?;
        Ok(sink.path)
    }

    /// Drops a cancelled or failed transfer and removes the partial file.
    pub fn abort_sink(&self, id: &str) -> Result<(), CoreError> {
        let mut sinks = self.lock_sinks()?;
        if let Some(sink) = sinks.remove(id) {
            drop(sink.handle);
            let _ = std::fs::remove_file(&sink.path);
        }
        Ok(())
    }

    fn lock_history(&self) -> Result<MutexGuard<'_, EncryptedHistory>, CoreError> {
        self.history
            .lock()
            .map_err(|_| CoreError::HistoryLocked)
    }

    fn lock_peers(&self) -> Result<MutexGuard<'_, EncryptedHistory>, CoreError> {
        self.history.lock().map_err(|_| CoreError::PeerStoreLocked)
    }

    fn lock_sinks(&self) -> Result<MutexGuard<'_, HashMap<String, FileSink>>, CoreError> {
        self.sinks.lock().map_err(|_| CoreError::FileSinkLocked)
    }
}
