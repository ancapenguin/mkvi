//! The two core error types, carried across the FFI boundary as data.
//!
//! The Tauri shell returned `String` from every command and the front end threw
//! the text away, which is how "the secure store lost an entry" and "SQLite was
//! busy" both arrived as an anonymous line in a toast. flutter_rust_bridge
//! only flattens an error to a string when it is `anyhow::Error`; when the error
//! is an enum it is transmitted as a real Dart union class, so the variants
//! below stay distinguishable in Dart and the UI can react differently to each.
//!
//! Every variant carries `message`, which is the *core's own* `Display` output,
//! captured while the real error value was still in hand. The Turkish wording
//! therefore comes from `mkvi_core` and is never restated here — the bridge adds
//! a machine-readable case, not a second place to change a user-facing string.

use std::error::Error;
use std::fmt;

use mkvi_core::{CoreError, SecurityError};

/// A `mkvi_core::SecurityError`, one Dart case per Rust variant.
// The Rust derives are what flutter_rust_bridge mirrors into Dart: there is no
// `#[frb(derive(..))]` in frb 2, and the derive line has to come before any
// `#[frb(..)]` because that one is a real attribute macro and does not pass
// trailing attributes through.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SecurityFailure {
    /// The operating system secret store itself refused the call.
    SecretStore { message: String },
    /// A required entry is gone while local data still depends on it.
    ///
    /// `name` is kept because the recovery differs per entry and the UI has to
    /// be able to name the one that is missing. This is the failure mode that
    /// must never be papered over by minting a replacement key.
    KeyringEntryMissing { name: String, message: String },
    /// The store accepted a write and then could not return the value, which is
    /// how a backend that degraded to an in-memory mock behaves.
    SecretStoreMissing { message: String },
    /// A stored secret could not be decoded.
    InvalidSecret { message: String },
    /// An authenticated-encryption or signing operation failed.
    Crypto { message: String },
    /// The SQLite layer failed. `message` is the driver text, passed through.
    Database { message: String },
    /// A stored record could not be (de)serialised.
    Serialization { message: String },
    /// The caller supplied an empty or oversized message id.
    InvalidMessageId { message: String },
}

impl From<SecurityError> for SecurityFailure {
    fn from(error: SecurityError) -> Self {
        // Taken before the value is destructured, while it can still be
        // displayed: this is the one place the Turkish text is read.
        let message = error.to_string();
        match error {
            SecurityError::SecretStore(_) => Self::SecretStore { message },
            SecurityError::KeyringEntryMissing { name } => {
                Self::KeyringEntryMissing { name, message }
            }
            SecurityError::SecretStoreMissing => Self::SecretStoreMissing { message },
            SecurityError::InvalidSecret => Self::InvalidSecret { message },
            SecurityError::Crypto => Self::Crypto { message },
            SecurityError::Database(_) => Self::Database { message },
            SecurityError::Serialization(_) => Self::Serialization { message },
            SecurityError::InvalidMessageId => Self::InvalidMessageId { message },
        }
    }
}

impl SecurityFailure {
    /// The core's Turkish text, unchanged.
    pub fn message(&self) -> &str {
        match self {
            Self::SecretStore { message }
            | Self::KeyringEntryMissing { message, .. }
            | Self::SecretStoreMissing { message }
            | Self::InvalidSecret { message }
            | Self::Crypto { message }
            | Self::Database { message }
            | Self::Serialization { message }
            | Self::InvalidMessageId { message } => message,
        }
    }
}

impl fmt::Display for SecurityFailure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.message())
    }
}

impl Error for SecurityFailure {}

/// A `mkvi_core::CoreError`, one Dart case per Rust variant.
///
/// `Security` keeps the core's own nesting rather than collapsing it: the inner
/// [`SecurityFailure`] is still reachable, so "the keyring entry vanished" stays
/// distinguishable from every state-level failure.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreFailure {
    /// The encrypted history mutex could not be taken.
    HistoryLocked { message: String },
    /// The peer store mutex could not be taken.
    PeerStoreLocked { message: String },
    /// The file sink mutex could not be taken.
    FileSinkLocked { message: String },
    /// There is no open transfer for that id.
    NoOpenTransfer { message: String },
    /// The concurrent transfer cap was reached.
    TooManyTransfers { message: String },
    /// That transfer id is already open.
    DuplicateTransfer { message: String },
    /// The transfer exceeded the allowed size.
    TransferTooLarge { message: String },
    /// `CoreError::Security`, carrying the inner case.
    Security { failure: SecurityFailure },
    /// Operating system text, passed through unchanged.
    Io { message: String },
}

impl From<CoreError> for CoreFailure {
    fn from(error: CoreError) -> Self {
        let message = error.to_string();
        match error {
            CoreError::HistoryLocked => Self::HistoryLocked { message },
            CoreError::PeerStoreLocked => Self::PeerStoreLocked { message },
            CoreError::FileSinkLocked => Self::FileSinkLocked { message },
            CoreError::NoOpenTransfer => Self::NoOpenTransfer { message },
            CoreError::TooManyTransfers => Self::TooManyTransfers { message },
            CoreError::DuplicateTransfer => Self::DuplicateTransfer { message },
            CoreError::TransferTooLarge => Self::TransferTooLarge { message },
            CoreError::Security(inner) => Self::Security {
                failure: inner.into(),
            },
            CoreError::Io(_) => Self::Io { message },
        }
    }
}

impl CoreFailure {
    /// The core's Turkish text, unchanged.
    ///
    /// `CoreError::Security` delegates its `Display` to the inner
    /// `SecurityError`, so this returns exactly the same text the desktop shell
    /// showed for the same underlying fault.
    pub fn message(&self) -> &str {
        match self {
            Self::Security { failure } => failure.message(),
            Self::HistoryLocked { message }
            | Self::PeerStoreLocked { message }
            | Self::FileSinkLocked { message }
            | Self::NoOpenTransfer { message }
            | Self::TooManyTransfers { message }
            | Self::DuplicateTransfer { message }
            | Self::TransferTooLarge { message }
            | Self::Io { message } => message,
        }
    }

    /// The inner security case, when this is a `CoreError::Security`.
    pub fn security(&self) -> Option<&SecurityFailure> {
        match self {
            Self::Security { failure } => Some(failure),
            _ => None,
        }
    }
}

impl fmt::Display for CoreFailure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.message())
    }
}

impl Error for CoreFailure {}

#[cfg(test)]
mod tests {
    use super::{CoreFailure, SecurityFailure};
    use mkvi_core::{CoreError, SecurityError};

    #[test]
    fn the_missing_keyring_entry_keeps_its_name_and_its_turkish_text() {
        let failure = SecurityFailure::from(SecurityError::KeyringEntryMissing {
            name: "device-signing-key-v1".into(),
        });
        match &failure {
            SecurityFailure::KeyringEntryMissing { name, message } => {
                assert_eq!(name, "device-signing-key-v1");
                // The text is the core's, byte for byte, not a bridge rewording.
                assert_eq!(
                    message,
                    "güvenli depoda 'device-signing-key-v1' kaydı bulunamadı; \
                     yerel veriler hâlâ bu kayda bağlı"
                );
            }
            other => panic!("the variant was flattened: {other:?}"),
        }
    }

    #[test]
    fn a_security_error_nested_in_a_core_error_stays_reachable() {
        let failure = CoreFailure::from(CoreError::Security(SecurityError::SecretStoreMissing));
        assert!(matches!(
            failure.security(),
            Some(SecurityFailure::SecretStoreMissing { .. })
        ));
        assert_eq!(
            failure.message(),
            "güvenli gizli depo kullanılamıyor: yazılan değer geri okunamadı"
        );
    }

    #[test]
    fn state_level_failures_keep_their_own_turkish_text() {
        let failure = CoreFailure::from(CoreError::HistoryLocked);
        assert!(matches!(failure, CoreFailure::HistoryLocked { .. }));
        assert_eq!(failure.message(), "Yerel geçmiş kilidi kullanılamıyor.");
        assert!(failure.security().is_none());
    }

    #[test]
    fn every_core_error_variant_has_a_case() {
        // A new core variant must not silently fall through as a string.
        let all = [
            CoreFailure::from(CoreError::HistoryLocked),
            CoreFailure::from(CoreError::PeerStoreLocked),
            CoreFailure::from(CoreError::FileSinkLocked),
            CoreFailure::from(CoreError::NoOpenTransfer),
            CoreFailure::from(CoreError::TooManyTransfers),
            CoreFailure::from(CoreError::DuplicateTransfer),
            CoreFailure::from(CoreError::TransferTooLarge),
            CoreFailure::from(CoreError::Security(SecurityError::Crypto)),
            CoreFailure::from(CoreError::Io("disk full".into())),
        ];
        assert!(all.iter().all(|failure| !failure.message().is_empty()));
    }
}
