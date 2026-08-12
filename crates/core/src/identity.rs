use rand::rngs::OsRng;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::error::CoreError;
use crate::token::Token;

/// Local device identity (private key never leaves the device in product use).
#[derive(Zeroize, ZeroizeOnDrop)]
pub struct Identity {
    secret: [u8; 32],
}

/// Shareable half of an identity (public key + token).
#[derive(Clone, PartialEq, Eq)]
pub struct PublicIdentity {
    public_key: [u8; 32],
    token: Token,
}

impl Identity {
    /// Generate a new random identity.
    pub fn generate() -> Self {
        let secret = StaticSecret::random_from_rng(OsRng);
        Self {
            secret: secret.to_bytes(),
        }
    }

    /// Restore from raw 32-byte secret (secure storage / FFI).
    pub fn from_secret_bytes(bytes: [u8; 32]) -> Self {
        Self { secret: bytes }
    }

    /// Export secret bytes for encrypted local storage only. Caller must protect them.
    pub fn to_secret_bytes(&self) -> [u8; 32] {
        self.secret
    }

    pub fn public_key_bytes(&self) -> [u8; 32] {
        let secret = StaticSecret::from(self.secret);
        PublicKey::from(&secret).to_bytes()
    }

    pub fn token(&self) -> Token {
        Token::from_public_key_bytes(&self.public_key_bytes())
    }

    pub fn public_identity(&self) -> PublicIdentity {
        let public_key = self.public_key_bytes();
        let token = Token::from_public_key_bytes(&public_key);
        PublicIdentity { public_key, token }
    }

    pub(crate) fn static_secret(&self) -> StaticSecret {
        StaticSecret::from(self.secret)
    }
}

impl std::fmt::Debug for Identity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Identity")
            .field("token", &self.token().as_str())
            .field("secret", &"<redacted>")
            .finish()
    }
}

impl PublicIdentity {
    pub fn from_public_key_bytes(public_key: [u8; 32]) -> Self {
        let token = Token::from_public_key_bytes(&public_key);
        Self { public_key, token }
    }

    pub fn try_from_public_key_slice(bytes: &[u8]) -> Result<Self, CoreError> {
        let arr: [u8; 32] = bytes.try_into().map_err(|_| CoreError::InvalidPublicKey)?;
        Ok(Self::from_public_key_bytes(arr))
    }

    pub fn public_key_bytes(&self) -> [u8; 32] {
        self.public_key
    }

    pub fn token(&self) -> &Token {
        &self.token
    }
}

impl std::fmt::Debug for PublicIdentity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PublicIdentity")
            .field("token", &self.token.as_str())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_stable_from_same_secret() {
        let id = Identity::generate();
        let bytes = id.to_secret_bytes();
        let restored = Identity::from_secret_bytes(bytes);
        assert_eq!(id.token().as_str(), restored.token().as_str());
        assert_eq!(id.public_key_bytes(), restored.public_key_bytes());
    }

    #[test]
    fn debug_redacts_secret() {
        let id = Identity::generate();
        let rendered = format!("{id:?}");
        assert!(rendered.contains("<redacted>"));
        assert!(!rendered.contains(&hex::encode(id.to_secret_bytes())));
    }
}
