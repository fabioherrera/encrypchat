//! Wire frame for one P2P chat message (bytes sent on the Phase 4 TCP transport).
//!
//! Layout:
//! ```text
//! magic:          b"EC04" (4)
//! version:        u8 = 1
//! msg_id:         16 bytes
//! sender_token:   u16 BE length + UTF-8 bytes
//! ciphertext:     u32 BE length + bytes (E2EE blob from encrypt())
//! ```

use rand::rngs::OsRng;
use rand::RngCore;

use crate::error::CoreError;
use crate::token::Token;

pub const MAGIC: &[u8; 4] = b"EC04";
pub const FRAME_VERSION: u8 = 1;
pub const MSG_ID_LEN: usize = 16;

const MAX_TOKEN_LEN: usize = 256;
const MAX_CIPHERTEXT_LEN: usize = 16 * 1024 * 1024;

/// Decoded chat wire frame (payload is opaque E2EE ciphertext).
#[derive(Clone, PartialEq, Eq)]
pub struct WireFrame {
    pub msg_id: [u8; MSG_ID_LEN],
    pub sender_token: String,
    pub ciphertext: Vec<u8>,
}

impl std::fmt::Debug for WireFrame {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("WireFrame")
            .field("msg_id_len", &self.msg_id.len())
            .field("sender_token", &self.sender_token)
            .field("ciphertext_len", &self.ciphertext.len())
            .finish()
    }
}

impl WireFrame {
    /// Build a frame with a random `msg_id`.
    pub fn new(sender_token: impl Into<String>, ciphertext: Vec<u8>) -> Result<Self, CoreError> {
        let sender_token = sender_token.into();
        Token::parse(&sender_token)?;
        if ciphertext.is_empty() {
            return Err(CoreError::InvalidFrame);
        }
        let mut msg_id = [0u8; MSG_ID_LEN];
        OsRng.fill_bytes(&mut msg_id);
        Ok(Self {
            msg_id,
            sender_token,
            ciphertext,
        })
    }

    pub fn encode(&self) -> Result<Vec<u8>, CoreError> {
        encode_frame(self)
    }
}

/// Encode a [`WireFrame`] to wire bytes.
pub fn encode_frame(frame: &WireFrame) -> Result<Vec<u8>, CoreError> {
    Token::parse(&frame.sender_token)?;
    if frame.ciphertext.is_empty() {
        return Err(CoreError::InvalidFrame);
    }
    let token_bytes = frame.sender_token.as_bytes();
    if token_bytes.len() > MAX_TOKEN_LEN {
        return Err(CoreError::InvalidFrame);
    }
    if frame.ciphertext.len() > MAX_CIPHERTEXT_LEN {
        return Err(CoreError::InvalidFrame);
    }

    let mut out = Vec::with_capacity(
        4 + 1 + MSG_ID_LEN + 2 + token_bytes.len() + 4 + frame.ciphertext.len(),
    );
    out.extend_from_slice(MAGIC);
    out.push(FRAME_VERSION);
    out.extend_from_slice(&frame.msg_id);
    out.extend_from_slice(&(token_bytes.len() as u16).to_be_bytes());
    out.extend_from_slice(token_bytes);
    out.extend_from_slice(&(frame.ciphertext.len() as u32).to_be_bytes());
    out.extend_from_slice(&frame.ciphertext);
    Ok(out)
}

/// Decode and validate wire bytes into a [`WireFrame`].
pub fn decode_frame(bytes: &[u8]) -> Result<WireFrame, CoreError> {
    if bytes.len() < 4 + 1 + MSG_ID_LEN + 2 + 4 {
        return Err(CoreError::InvalidFrame);
    }
    if &bytes[0..4] != MAGIC {
        return Err(CoreError::InvalidFrame);
    }
    if bytes[4] != FRAME_VERSION {
        return Err(CoreError::InvalidFrame);
    }

    let mut offset = 5;
    let mut msg_id = [0u8; MSG_ID_LEN];
    msg_id.copy_from_slice(&bytes[offset..offset + MSG_ID_LEN]);
    offset += MSG_ID_LEN;

    if bytes.len() < offset + 2 {
        return Err(CoreError::InvalidFrame);
    }
    let token_len = u16::from_be_bytes([bytes[offset], bytes[offset + 1]]) as usize;
    offset += 2;
    if token_len == 0 || token_len > MAX_TOKEN_LEN || bytes.len() < offset + token_len {
        return Err(CoreError::InvalidFrame);
    }
    let token_str = std::str::from_utf8(&bytes[offset..offset + token_len])
        .map_err(|_| CoreError::InvalidFrame)?;
    let sender_token = Token::parse(token_str)?.as_str().to_string();
    offset += token_len;

    if bytes.len() < offset + 4 {
        return Err(CoreError::InvalidFrame);
    }
    let ct_len = u32::from_be_bytes([
        bytes[offset],
        bytes[offset + 1],
        bytes[offset + 2],
        bytes[offset + 3],
    ]) as usize;
    offset += 4;
    if ct_len == 0 || ct_len > MAX_CIPHERTEXT_LEN || bytes.len() != offset + ct_len {
        return Err(CoreError::InvalidFrame);
    }
    let ciphertext = bytes[offset..offset + ct_len].to_vec();

    Ok(WireFrame {
        msg_id,
        sender_token,
        ciphertext,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity::Identity;

    #[test]
    fn roundtrip() {
        let token = Identity::generate().token().as_str().to_string();
        let frame = WireFrame::new(token, vec![1, 2, 3, 4]).unwrap();
        let encoded = encode_frame(&frame).unwrap();
        let decoded = decode_frame(&encoded).unwrap();
        assert_eq!(decoded, frame);
    }

    #[test]
    fn bad_magic_rejected() {
        let token = Identity::generate().token().as_str().to_string();
        let mut encoded = WireFrame::new(token, vec![9]).unwrap().encode().unwrap();
        encoded[0] = b'X';
        assert!(matches!(decode_frame(&encoded), Err(CoreError::InvalidFrame)));
    }

    #[test]
    fn truncated_rejected() {
        assert!(matches!(decode_frame(b"EC04"), Err(CoreError::InvalidFrame)));
    }

    #[test]
    fn empty_ciphertext_rejected() {
        let token = Identity::generate().token().as_str().to_string();
        assert!(matches!(
            WireFrame::new(token, vec![]),
            Err(CoreError::InvalidFrame)
        ));
    }

    #[test]
    fn invalid_token_rejected() {
        assert!(matches!(
            WireFrame::new("not-a-token", vec![1]),
            Err(CoreError::InvalidToken)
        ));
    }
}
