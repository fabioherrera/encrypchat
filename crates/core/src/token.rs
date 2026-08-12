use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};

use crate::error::CoreError;
use crate::pubkey::{ensure_canonical_public_key, PUBLIC_KEY_LEN};

/// Stable contact address derived from a public key (SHA-256, hex, `ec_` prefix).
///
/// There is deliberately no infallible way from arbitrary bytes to a `Token`: the hash is
/// only a stable name for a peer if the key has one encoding, so every byte string that
/// arrives from outside goes through [`Token::from_public_key_bytes`], which rejects the
/// aliases X25519 allows ([`crate::pubkey`], F-10). Keys this device derives from its own
/// secret take [`Token::from_secret`] and cannot fail, because a derived key is canonical by
/// construction. Adding a third path means adding it here, where the check is.
#[derive(Clone, PartialEq, Eq, Hash)]
pub struct Token(String);

impl Token {
    pub const PREFIX: &'static str = "ec_";

    /// Derive from a public key that came from outside: a contact card, a QR, the wire, or
    /// the FFI. [`CoreError::InvalidPublicKey`] on a non-canonical encoding.
    pub(crate) fn from_public_key_bytes(pubkey: &[u8; PUBLIC_KEY_LEN]) -> Result<Self, CoreError> {
        ensure_canonical_public_key(pubkey)?;
        Ok(Self::digest(pubkey))
    }

    /// Derive from a secret held on this device.
    pub(crate) fn from_secret(secret: &StaticSecret) -> Self {
        Self::digest(&PublicKey::from(secret).to_bytes())
    }

    fn digest(pubkey: &[u8; PUBLIC_KEY_LEN]) -> Self {
        let digest = Sha256::digest(pubkey);
        let hex = hex::encode(digest);
        Self(format!("{}{hex}", Self::PREFIX))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn parse(raw: &str) -> Result<Self, CoreError> {
        let trimmed = raw.trim();
        if !trimmed.starts_with(Self::PREFIX) {
            return Err(CoreError::InvalidToken);
        }
        let hex_part = &trimmed[Self::PREFIX.len()..];
        if hex_part.len() != 64 || !hex_part.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(CoreError::InvalidToken);
        }
        Ok(Self(trimmed.to_ascii_lowercase()))
    }
}

impl std::fmt::Display for Token {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::fmt::Debug for Token {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("Token").field(&self.0).finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity::Identity;
    use crate::pubkey::test_vectors::{high_bit_alias, non_reduced_max, NON_REDUCED_ZERO};

    #[test]
    fn parse_rejects_bad_prefix() {
        assert!(Token::parse("xx_deadbeef").is_err());
    }

    /// The compatibility claim, pinned: a canonical key derives the token it always did, so
    /// no stored contact, blocklist entry or printed QR changes meaning. The key is the RFC
    /// 7748 §6.1 vector. If this ever moves, existing identities have been renamed.
    #[test]
    fn canonical_keys_keep_their_historical_token() {
        let pubkey: [u8; 32] =
            hex::decode("8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f")
                .unwrap()
                .try_into()
                .unwrap();
        assert_eq!(
            Token::from_public_key_bytes(&pubkey).unwrap().as_str(),
            "ec_eedd883da0a9451593dc0a38e583fb770fa27dbbed209c20404e075e68c4f0c9"
        );
    }

    /// Both halves of the F-10 alias family, at the one place a token can be minted.
    #[test]
    fn alias_encodings_cannot_become_a_token() {
        let key = Identity::generate().public_key_bytes();
        assert!(Token::from_public_key_bytes(&key).is_ok());

        for alias in [
            high_bit_alias(&key),
            NON_REDUCED_ZERO,
            non_reduced_max(),
            high_bit_alias(&[0u8; 32]),
        ] {
            assert!(
                matches!(
                    Token::from_public_key_bytes(&alias),
                    Err(CoreError::InvalidPublicKey)
                ),
                "{} must not mint a token",
                hex::encode(alias)
            );
        }
    }

    /// A device's own key never takes the fallible path, and both paths agree.
    #[test]
    fn own_key_and_external_key_agree() {
        let id = Identity::generate();
        assert_eq!(
            Token::from_secret(&StaticSecret::from(id.to_secret_bytes())).as_str(),
            Token::from_public_key_bytes(&id.public_key_bytes())
                .unwrap()
                .as_str()
        );
    }
}
