use thiserror::Error;

/// Errors from identity or E2EE operations.
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
            Self::Internal => 255,
        }
    }
}
