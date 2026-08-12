use thiserror::Error;

/// Errors from identity, E2EE, local AEAD, framing, or networking.
#[derive(Debug, Error)]
pub enum CoreError {
    #[error("invalid token encoding")]
    InvalidToken,
    #[error("invalid public key")]
    InvalidPublicKey,
    #[error("decryption failed")]
    DecryptionFailed,
    #[error("ciphertext too short")]
    CiphertextTooShort,
    #[error("empty plaintext not allowed")]
    EmptyPlaintext,
    #[error("output buffer too small")]
    BufferTooSmall,
    #[error("null pointer")]
    NullPointer,
    #[error("peer offline or unknown")]
    PeerOffline,
    #[error("no message available")]
    Empty,
    #[error("invalid wire frame")]
    InvalidFrame,
    #[error("peer authentication failed")]
    AuthFailed,
    #[error("peer token is on the local blocklist")]
    PeerBlocked,
    #[error("sealed blob outside the freshness window")]
    Expired,
    #[error("internal error")]
    Internal,
}

impl CoreError {
    /// Stable FFI / C ABI error codes.
    pub fn as_code(&self) -> i32 {
        match self {
            Self::InvalidToken => 1,
            Self::InvalidPublicKey => 2,
            Self::DecryptionFailed => 3,
            Self::CiphertextTooShort => 4,
            Self::EmptyPlaintext => 5,
            Self::BufferTooSmall => 6,
            Self::NullPointer => 7,
            Self::PeerOffline => 8,
            Self::Empty => 9,
            Self::InvalidFrame => 10,
            Self::AuthFailed => 11,
            Self::PeerBlocked => 12,
            Self::Expired => 13,
            Self::Internal => 255,
        }
    }
}
