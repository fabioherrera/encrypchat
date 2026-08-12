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

    /// Infallible, unlike the import path: a key derived from a secret we hold is canonical
    /// by construction, so there is no alias to reject ([`crate::pubkey`]).
    pub fn token(&self) -> Token {
        Token::from_secret(&self.static_secret())
    }

    pub fn public_identity(&self) -> PublicIdentity {
        PublicIdentity {
            public_key: self.public_key_bytes(),
            token: self.token(),
        }
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
    /// Import a contact's public key — a QR, a contact card, the FFI, a relay blob.
    ///
    /// [`CoreError::InvalidPublicKey`] on a non-canonical encoding: the alias is the same
    /// key to every Diffie-Hellman but a different token, so accepting it would let one
    /// peer hold several identities and walk around a block ([`crate::pubkey`], F-10).
    pub fn try_from_public_key_bytes(public_key: [u8; 32]) -> Result<Self, CoreError> {
        let token = Token::from_public_key_bytes(&public_key)?;
        Ok(Self { public_key, token })
    }

    pub fn try_from_public_key_slice(bytes: &[u8]) -> Result<Self, CoreError> {
        let arr: [u8; 32] = bytes.try_into().map_err(|_| CoreError::InvalidPublicKey)?;
        Self::try_from_public_key_bytes(arr)
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
    use crate::pubkey::test_vectors::{high_bit_alias, non_reduced_max, NON_REDUCED_ZERO};

    /// The import gate (F-10). Bob blocked Mallory; Mallory hands out a contact card with the
    /// high bit of her own key set. It is the same key to every DH, so nothing downstream
    /// would notice — the encoding is the only place to catch it.
    #[test]
    fn importing_an_alias_of_a_key_is_refused() {
        let mallory = Identity::generate();
        let real = mallory.public_key_bytes();
        assert_eq!(
            PublicIdentity::try_from_public_key_bytes(real)
                .unwrap()
                .token()
                .as_str(),
            mallory.token().as_str()
        );

        for alias in [high_bit_alias(&real), NON_REDUCED_ZERO, non_reduced_max()] {
            assert!(
                matches!(
                    PublicIdentity::try_from_public_key_bytes(alias),
                    Err(CoreError::InvalidPublicKey)
                ),
                "{} must not become an identity",
                hex::encode(alias)
            );
            assert!(matches!(
                PublicIdentity::try_from_public_key_slice(&alias),
                Err(CoreError::InvalidPublicKey)
            ));
        }
    }

    #[test]
    fn slice_import_still_rejects_the_wrong_length() {
        assert!(matches!(
            PublicIdentity::try_from_public_key_slice(&[0u8; 31]),
            Err(CoreError::InvalidPublicKey)
        ));
    }

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
