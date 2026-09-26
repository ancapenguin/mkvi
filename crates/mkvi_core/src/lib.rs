//! MKVI core: the Rust half of the app, with no UI framework attached.
//!
//! The Tauri shell is one host for this crate and Flutter will be the next. Every
//! module here is pure host logic — no Tauri types, no async runtime, no network —
//! so the same behaviour is available over `flutter_rust_bridge`.

pub mod files;
pub mod security;
pub mod state;
pub mod update;

pub use files::{sanitize_file_name, unique_path, valid_transfer_id, FileSink, MAX_FILE_BYTES};
pub use security::{
    DeviceIdentity, EncryptedHistory, HistoryMessage, KnownPeer, OsSecretStore, SecretOrigin,
    SecretStore, SecurityError,
};
pub use state::{Core, CoreError};
pub use update::{parse_feed, verify_artifact, UpdateError, UpdateInfo};
