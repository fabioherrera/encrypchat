//! Encrypchat core — local identity and E2EE (no network I/O).
//!
//! Private key material must never be logged. Prefer [`Identity::token`] and
//! public key bytes for any diagnostics.

mod crypto;
mod error;
pub mod ffi;
mod identity;
mod token;

pub use crypto::{decrypt, encrypt, Ciphertext};
pub use error::CoreError;
pub use identity::{Identity, PublicIdentity};
pub use token::Token;

/// Crate identity for scaffolding / FFI versioning.
pub fn crate_name() -> &'static str {
    "encrypchat_core"
}

/// Semver of the public API surface (bump when FFI contract changes).
pub fn api_version() -> &'static str {
    "0.3.0"
}
