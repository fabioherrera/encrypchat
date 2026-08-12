//! Encrypchat core — local identity, E2EE, at-rest AEAD, and P2P networking.
//!
//! Private key material must never be logged. Prefer [`Identity::token`] and
//! public key bytes for any diagnostics. Network I/O carries ciphertext only.

mod crypto;
mod error;
pub mod ffi;
mod frame;
/// Malformed-input properties for the decoders that meet remote bytes (test-only).
#[cfg(test)]
mod fuzz;
mod handshake;
mod identity;
mod local_aead;
mod net;
pub mod pop;
mod pubkey;
mod sealed;
mod token;
mod transport;

pub use crypto::{decrypt, encrypt, Ciphertext};
pub use error::CoreError;
pub use frame::{decode_frame, encode_frame, WireFrame};
pub use identity::{Identity, PublicIdentity};
pub use local_aead::{open_local, seal_local};
pub use net::{NodeHandle, PeerId};
pub use pop::{
    pop_generate_ephemeral, pop_generate_nonce, pop_proof, pop_verify, pubkey_matches_token,
    PopEphemeral, POP_NONCE_LEN, POP_PROOF_LEN,
};
pub use sealed::{
    open_sealed, seal_sender, seal_sender_at, OpenedMessage, SealedMessage, SEALED_MAGIC,
    SEALED_MAX_AGE_SECS, SEALED_MAX_SKEW_SECS, SEALED_MSG_ID_LEN, SEALED_OVERHEAD,
};
pub use token::Token;

/// Crate identity for scaffolding / FFI versioning.
pub fn crate_name() -> &'static str {
    "encrypchat_core"
}

/// Semver of the public API surface (bump when FFI contract changes).
pub fn api_version() -> &'static str {
    "0.8.1"
}
