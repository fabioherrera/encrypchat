use sha2::{Digest, Sha256};

use crate::error::CoreError;

/// Stable contact address derived from a public key (SHA-256, hex, `ec_` prefix).
#[derive(Clone, PartialEq, Eq, Hash)]
pub struct Token(String);

impl Token {
    pub const PREFIX: &'static str = "ec_";

    pub(crate) fn from_public_key_bytes(pubkey: &[u8; 32]) -> Self {
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

    #[test]
    fn parse_rejects_bad_prefix() {
        assert!(Token::parse("xx_deadbeef").is_err());
    }
}
