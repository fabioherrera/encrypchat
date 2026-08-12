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
//!
//! This layout is not what a network observer sees: since `0.8.0` the whole frame, header
//! included, travels inside the session AEAD of [`crate::transport`] (F-15). `sender_token`
//! being in the clear here used to be enough to map the social graph off the wire.

use rand::rngs::OsRng;
use rand::RngCore;

use crate::error::CoreError;
use crate::token::Token;

pub const MAGIC: &[u8; 4] = b"EC04";
pub const FRAME_VERSION: u8 = 1;
pub const MSG_ID_LEN: usize = 16;

pub(crate) const MAX_TOKEN_LEN: usize = 256;
pub(crate) const MAX_CIPHERTEXT_LEN: usize = 16 * 1024 * 1024;

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
        // Normalised on the way in, so a caller cannot hold a frame whose token is spelled in
        // a way [`decode_frame`] would refuse.
        let sender_token = Token::parse(&sender_token.into())?.as_str().to_string();
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
    // The normalised spelling, not whatever is in the struct: the fields are public, and an
    // encoder that can emit bytes its own decoder rejects is a trap for the next caller.
    let token = Token::parse(&frame.sender_token)?;
    if frame.ciphertext.is_empty() {
        return Err(CoreError::InvalidFrame);
    }
    let token_bytes = token.as_str().as_bytes();
    if token_bytes.len() > MAX_TOKEN_LEN {
        return Err(CoreError::InvalidFrame);
    }
    if frame.ciphertext.len() > MAX_CIPHERTEXT_LEN {
        return Err(CoreError::InvalidFrame);
    }

    let mut out =
        Vec::with_capacity(4 + 1 + MSG_ID_LEN + 2 + token_bytes.len() + 4 + frame.ciphertext.len());
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
    let token = Token::parse(token_str)?;
    // One message, one encoding. `Token::parse` also accepts a token spelled in upper case or
    // padded with whitespace, and normalising it here would leave several byte strings that
    // decode to the same frame — the malleability F-10 removed from public keys, one layer up.
    // Nothing downstream keys on frame bytes today; this is what keeps that from mattering.
    if token.as_str() != token_str {
        return Err(CoreError::InvalidFrame);
    }
    let sender_token = token.as_str().to_string();
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
        assert!(matches!(
            decode_frame(&encoded),
            Err(CoreError::InvalidFrame)
        ));
    }

    #[test]
    fn truncated_rejected() {
        assert!(matches!(
            decode_frame(b"EC04"),
            Err(CoreError::InvalidFrame)
        ));
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

    /// Found by the property in `src/fuzz.rs`: `Token::parse` normalises, so an upper-case
    /// token used to decode into the same frame as its lower-case spelling and give two wire
    /// encodings for one message. A frame now has exactly one.
    #[test]
    fn a_token_spelled_differently_is_not_a_second_encoding() {
        let id = Identity::generate();
        let token = id.token().as_str().to_string();
        let frame = WireFrame::new(token.clone(), vec![7]).unwrap();
        let canonical = frame.encode().unwrap();

        let shouty = format!(
            "{}{}",
            Token::PREFIX,
            token[Token::PREFIX.len()..].to_uppercase()
        );
        // The encoder normalises, so the same message cannot be put on the wire two ways even
        // by a caller that writes the field directly.
        let restated = WireFrame {
            sender_token: shouty.clone(),
            ..frame.clone()
        };
        assert_eq!(restated.encode().unwrap(), canonical);

        // And the decoder refuses it if someone hand-assembles the bytes.
        let mut spliced = canonical.clone();
        let at = spliced
            .windows(token.len())
            .position(|w| w == token.as_bytes())
            .expect("token in the frame");
        spliced[at..at + token.len()].copy_from_slice(shouty.as_bytes());
        assert!(matches!(
            decode_frame(&spliced),
            Err(CoreError::InvalidFrame)
        ));
        assert!(decode_frame(&canonical).is_ok());
    }
}
