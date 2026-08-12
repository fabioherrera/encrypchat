//! Local at-rest AEAD for message bodies sealed with the device `db_key`.
//!
//! Format: `nonce(12) || chacha20poly1305_ciphertext+tag`.
//! Network E2EE blobs use [`crate::crypto`]; this module is storage-only.

use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use rand::rngs::OsRng;
use rand::RngCore;

use crate::error::CoreError;

const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;
const AAD: &[u8] = b"encrypchat-local-v1";

/// Seal plaintext for local storage with a 32-byte `db_key`.
pub fn seal_local(key: &[u8; 32], plaintext: &[u8]) -> Result<Vec<u8>, CoreError> {
    if plaintext.is_empty() {
        return Err(CoreError::EmptyPlaintext);
    }

    let cipher = ChaCha20Poly1305::new_from_slice(key).map_err(|_| CoreError::Internal)?;
    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let encrypted = cipher
        .encrypt(
            nonce,
            chacha20poly1305::aead::Payload {
                msg: plaintext,
                aad: AAD,
            },
        )
        .map_err(|_| CoreError::Internal)?;

    let mut out = Vec::with_capacity(NONCE_LEN + encrypted.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&encrypted);
    Ok(out)
}

/// Open a blob produced by [`seal_local`].
pub fn open_local(key: &[u8; 32], sealed: &[u8]) -> Result<Vec<u8>, CoreError> {
    if sealed.len() < NONCE_LEN + TAG_LEN {
        return Err(CoreError::CiphertextTooShort);
    }

    let nonce_bytes = &sealed[..NONCE_LEN];
    let body = &sealed[NONCE_LEN..];
    let cipher = ChaCha20Poly1305::new_from_slice(key).map_err(|_| CoreError::Internal)?;
    let nonce = Nonce::from_slice(nonce_bytes);

    cipher
        .decrypt(
            nonce,
            chacha20poly1305::aead::Payload {
                msg: body,
                aad: AAD,
            },
        )
        .map_err(|_| CoreError::DecryptionFailed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let key = [7u8; 32];
        let sealed = seal_local(&key, b"stored body").unwrap();
        assert!(sealed.len() >= NONCE_LEN + TAG_LEN + 1);
        let pt = open_local(&key, &sealed).unwrap();
        assert_eq!(pt, b"stored body");
    }

    #[test]
    fn empty_plaintext_rejected() {
        let key = [1u8; 32];
        assert!(matches!(
            seal_local(&key, b""),
            Err(CoreError::EmptyPlaintext)
        ));
    }

    #[test]
    fn tamper_fails() {
        let key = [9u8; 32];
        let mut sealed = seal_local(&key, b"hello").unwrap();
        let last = sealed.len() - 1;
        sealed[last] ^= 0xff;
        assert!(matches!(
            open_local(&key, &sealed),
            Err(CoreError::DecryptionFailed)
        ));
    }

    #[test]
    fn wrong_key_fails() {
        let sealed = seal_local(&[1u8; 32], b"hello").unwrap();
        assert!(matches!(
            open_local(&[2u8; 32], &sealed),
            Err(CoreError::DecryptionFailed)
        ));
    }

    #[test]
    fn too_short_rejected() {
        let key = [3u8; 32];
        assert!(matches!(
            open_local(&key, &[0u8; 10]),
            Err(CoreError::CiphertextTooShort)
        ));
    }
}
