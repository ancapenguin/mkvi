//! The Flutter bridge: `mkvi_core` exposed to Dart over `flutter_rust_bridge`.
//!
//! Layout:
//!
//! * [`api`] — the Dart-facing surface. Seven domain calls plus a constructor.
//! * [`error`] — `mkvi_core`'s error types as Dart-visible unions.
//! * [`frb_generated`] — written by `flutter_rust_bridge_codegen generate`, never
//!   by hand. It only exists after a codegen run and is checked in, so a clean
//!   clone builds without running the generator first.
//!
//! This crate holds no behaviour. Every guarantee the Dart side relies on is
//! implemented and tested in `mkvi_core`; what lives here is the encoding, the
//! error mapping, and nothing else. See `README.md` for how to regenerate the
//! bindings and for the Android secret-store caveat.

pub mod api;
pub mod error;
pub mod frb_generated;
