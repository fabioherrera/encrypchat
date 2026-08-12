//! Encrypchat core — local identity, E2EE, at-rest AEAD, and P2P networking.
//!
//! Private key material must never be logged. Prefer [`Identity::token`] and
//! public key bytes for any diagnostics. Network I/O carries ciphertext only.

mod crypto;
mod error;
pub mod ffi;
mod frame;
mod identity;
mod local_aead;
mod net;
mod token;

pub use crypto::{decrypt, encrypt, Ciphertext};
pub use error::CoreError;
pub use frame::{decode_frame, encode_frame, WireFrame};
pub use identity::{Identity, PublicIdentity};
pub use local_aead::{open_local, seal_local};
pub use net::{NodeHandle, PeerId};
pub use token::Token;

/// Crate identity for scaffolding / FFI versioning.
pub fn crate_name() -> &'static str {
    "encrypchat_core"
}

/// Semver of the public API surface (bump when FFI contract changes).
pub fn api_version() -> &'static str {
    "0.5.0"
}
