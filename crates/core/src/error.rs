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
}
