use chacha20poly1305::aead::{Aead, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};

use crate::error::CoreError;
use crate::identity::{Identity, PublicIdentity};

/// Encrypted payload: ephemeral pubkey (32) || nonce (12) || ciphertext+tag.
#[derive(Clone, PartialEq, Eq)]
pub struct Ciphertext(Vec<u8>);

impl Ciphertext {
    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }

    pub fn into_bytes(self) -> Vec<u8> {
        self.0
    }

    pub fn from_bytes(bytes: Vec<u8>) -> Result<Self, CoreError> {
        if bytes.len() < 32 + 12 + 16 {
            return Err(CoreError::CiphertextTooShort);
        }
        Ok(Self(bytes))
    }
}

impl std::fmt::Debug for Ciphertext {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Ciphertext")
            .field("len", &self.0.len())
            .finish()
    }
}

fn derive_aead_key(shared: &[u8; 32], ephemeral_pub: &[u8; 32], recipient_pub: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(b"encrypchat-e2ee-v1");
    hasher.update(shared);
    hasher.update(ephemeral_pub);
    hasher.update(recipient_pub);
    let out = hasher.finalize();
    let mut key = [0u8; 32];
    key.copy_from_slice(&out);
    key
}

/// Encrypt `plaintext` for `recipient` using an ephemeral X25519 + ChaCha20-Poly1305.
pub fn encrypt(recipient: &PublicIdentity, plaintext: &[u8]) -> Result<Ciphertext, CoreError> {
    if plaintext.is_empty() {
        return Err(CoreError::EmptyPlaintext);
    }

    let eph_secret = StaticSecret::random_from_rng(OsRng);
    let eph_public = PublicKey::from(&eph_secret);
    let recipient_pk = PublicKey::from(recipient.public_key_bytes());
    let shared = eph_secret.diffie_hellman(&recipient_pk);

    let key = derive_aead_key(
        shared.as_bytes(),
        &eph_public.to_bytes(),
        &recipient.public_key_bytes(),
    );
    let cipher = ChaCha20Poly1305::new_from_slice(&key).expect("32-byte key");
    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let encrypted = cipher
        .encrypt(nonce, plaintext)
        .map_err(|_| CoreError::DecryptionFailed)?;

    let mut out = Vec::with_capacity(32 + 12 + encrypted.len());
    out.extend_from_slice(&eph_public.to_bytes());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&encrypted);
    Ok(Ciphertext(out))
}

/// Decrypt a blob produced by [`encrypt`] using the recipient [`Identity`].
pub fn decrypt(identity: &Identity, ciphertext: &Ciphertext) -> Result<Vec<u8>, CoreError> {
    let bytes = ciphertext.as_bytes();
    if bytes.len() < 32 + 12 + 16 {
        return Err(CoreError::CiphertextTooShort);
    }

    let mut eph_bytes = [0u8; 32];
    eph_bytes.copy_from_slice(&bytes[..32]);
    let nonce_bytes = &bytes[32..44];
    let body = &bytes[44..];

    let eph_public = PublicKey::from(eph_bytes);
    let shared = identity.static_secret().diffie_hellman(&eph_public);
    let my_pub = identity.public_key_bytes();
    let key = derive_aead_key(shared.as_bytes(), &eph_bytes, &my_pub);

    let cipher = ChaCha20Poly1305::new_from_slice(&key).expect("32-byte key");
    let nonce = Nonce::from_slice(nonce_bytes);
    cipher
        .decrypt(nonce, body)
        .map_err(|_| CoreError::DecryptionFailed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::token::Token;

    #[test]
    fn roundtrip_message() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let bob_pub = bob.public_identity();

        let ct = encrypt(&bob_pub, b"hello encrypchat").unwrap();
        let pt = decrypt(&bob, &ct).unwrap();
        assert_eq!(pt, b"hello encrypchat");

        // Alice cannot decrypt a message for Bob.
        assert!(decrypt(&alice, &ct).is_err());
    }

    #[test]
    fn empty_plaintext_rejected() {
        let bob = Identity::generate().public_identity();
        assert!(encrypt(&bob, b"").is_err());
    }

    #[test]
    fn token_matches_pubkey_hash() {
        let id = Identity::generate();
        let t1 = id.token();
        let t2 = Token::from_public_key_bytes(&id.public_key_bytes());
        assert_eq!(t1.as_str(), t2.as_str());
        assert!(t1.as_str().starts_with("ec_"));
        assert_eq!(Token::parse(t1.as_str()).unwrap().as_str(), t1.as_str());
    }
}
