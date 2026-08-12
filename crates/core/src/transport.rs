//! Session encryption for the P2P transport (closes F-15).
//!
//! EH02 authenticates identities but used to leave the wire in the clear: only the *payload*
//! of an `EC04` frame was E2EE, so its header — including `sender_token` — was readable by
//! anyone watching the network. Authenticating the handshake and then narrating the social
//! graph in cleartext defeats the point.
//!
//! Every record of an established session is now encrypted under a key derived from the
//! handshake ([`crate::handshake::SessionKeys`]), with **one key per direction**:
//!
//! ```text
//! record:    len(4, big endian) || ciphertext
//! ciphertext ChaCha20-Poly1305(k_dir, nonce = counter) over plaintext
//! plaintext: kind(1) || payload_len(4) || payload || padding
//! ```
//!
//! ## Order and repetition
//!
//! The nonce is an implicit per-direction counter: it is never transmitted, and the receiver
//! only ever tries the next one. A record that is replayed, reordered, dropped or injected by
//! an active attacker decrypts under the wrong counter and fails its tag, which closes the
//! session. So within a session the stream is exactly-once and in-order, or it stops — there
//! is no window to slide and no state to bound, unlike the relay replay problem, where the
//! recipient has no session to anchor to.
//!
//! ## Padding
//!
//! Plaintext is zero-padded up to [`PAD_FLOOR`]. That makes every short record the same size
//! on the wire: an ACK, a "ok", and a two-line message are indistinguishable by length. Above
//! the floor nothing is padded and **length leaks** — see the module docs of
//! [`crate::net`] and `docs/threat-model.md` §5 for what that still gives away.

use chacha20poly1305::aead::{Aead, Payload};
use chacha20poly1305::Nonce;
use zeroize::Zeroizing;

use crate::error::CoreError;
use crate::sealed::cipher;

/// Records shorter than this are padded up to it. 512 bytes covers a typical chat frame
/// (`EC04` header + a few hundred characters of ciphertext) and costs nothing next to a
/// media chunk.
pub(crate) const PAD_FLOOR: usize = 512;

/// `kind(1) || payload_len(4)`.
const HEADER_LEN: usize = 5;
const TAG_LEN: usize = 16;

/// Worst-case bytes a record adds on top of its payload, for buffer bounds. Records below
/// [`PAD_FLOOR`] are larger than their payload, but never larger than the floor plus this.
pub(crate) const TRANSPORT_OVERHEAD: usize = HEADER_LEN + TAG_LEN;

/// A counter that has run out is a bug, not an attack: `u64` records at line rate is not
/// reachable. It fails loudly rather than wrapping, because wrapping means nonce reuse.
fn nonce_for(counter: u64) -> Nonce {
    let mut bytes = [0u8; 12];
    bytes[4..].copy_from_slice(&counter.to_be_bytes());
    *Nonce::from_slice(&bytes)
}

/// Outbound half of a session. One per direction, never shared between them.
pub(crate) struct SendCipher {
    key: Zeroizing<[u8; 32]>,
    counter: u64,
}

/// Inbound half of a session.
pub(crate) struct RecvCipher {
    key: Zeroizing<[u8; 32]>,
    counter: u64,
}

impl SendCipher {
    pub(crate) fn new(key: Zeroizing<[u8; 32]>) -> Self {
        Self { key, counter: 0 }
    }

    /// Seal one record, returning it with its length prefix so the caller writes it in a
    /// single call — the counter and the bytes on the socket must not interleave with
    /// another sender's.
    pub(crate) fn seal(&mut self, kind: u8, payload: &[u8]) -> Result<Vec<u8>, CoreError> {
        let mut plaintext = Zeroizing::new(Vec::with_capacity(
            HEADER_LEN + payload.len().max(PAD_FLOOR),
        ));
        plaintext.push(kind);
        let payload_len = u32::try_from(payload.len()).map_err(|_| CoreError::InvalidFrame)?;
        plaintext.extend_from_slice(&payload_len.to_be_bytes());
        plaintext.extend_from_slice(payload);
        let padded_len = plaintext.len().max(PAD_FLOOR);
        plaintext.resize(padded_len, 0);

        let ciphertext = cipher(&self.key)?
            .encrypt(
                &nonce_for(self.counter),
                Payload {
                    msg: &plaintext,
                    aad: &[],
                },
            )
            .map_err(|_| CoreError::Internal)?;
        self.counter = self.counter.checked_add(1).ok_or(CoreError::Internal)?;

        let len = u32::try_from(ciphertext.len()).map_err(|_| CoreError::InvalidFrame)?;
        let mut record = Vec::with_capacity(4 + ciphertext.len());
        record.extend_from_slice(&len.to_be_bytes());
        record.extend_from_slice(&ciphertext);
        Ok(record)
    }
}

impl RecvCipher {
    pub(crate) fn new(key: Zeroizing<[u8; 32]>) -> Self {
        Self { key, counter: 0 }
    }

    /// Open one record body (the bytes after the length prefix).
    ///
    /// Anything other than the next record of this session fails: the length prefix is
    /// covered because the tag covers the exact bytes read, and the position in the stream is
    /// covered because the counter is implicit.
    pub(crate) fn open(&mut self, body: &[u8]) -> Result<(u8, Vec<u8>), CoreError> {
        let plaintext = Zeroizing::new(
            cipher(&self.key)?
                .decrypt(
                    &nonce_for(self.counter),
                    Payload {
                        msg: body,
                        aad: &[],
                    },
                )
                .map_err(|_| CoreError::AuthFailed)?,
        );
        self.counter = self.counter.checked_add(1).ok_or(CoreError::Internal)?;

        if plaintext.len() < HEADER_LEN {
            return Err(CoreError::InvalidFrame);
        }
        let kind = plaintext[0];
        let mut len_bytes = [0u8; 4];
        len_bytes.copy_from_slice(&plaintext[1..HEADER_LEN]);
        let payload_len = u32::from_be_bytes(len_bytes) as usize;
        let end = HEADER_LEN
            .checked_add(payload_len)
            .ok_or(CoreError::InvalidFrame)?;
        if end > plaintext.len() {
            return Err(CoreError::InvalidFrame);
        }
        Ok((kind, plaintext[HEADER_LEN..end].to_vec()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pair() -> (SendCipher, RecvCipher) {
        let key = Zeroizing::new([7u8; 32]);
        (SendCipher::new(key.clone()), RecvCipher::new(key))
    }

    #[test]
    fn roundtrip_in_order() {
        let (mut send, mut recv) = pair();
        for i in 0..4u8 {
            let payload = vec![i; 100 * (i as usize + 1)];
            let record = send.seal(i, &payload).unwrap();
            let opened = recv.open(&record[4..]).unwrap();
            assert_eq!(opened, (i, payload));
        }
        assert_eq!(send.counter, 4);
        assert_eq!(recv.counter, 4);
    }

    /// The property that replaces a replay window: the counter is implicit, so anything but
    /// the next record fails.
    #[test]
    fn replayed_or_reordered_record_fails() {
        let (mut send, mut recv) = pair();
        let first = send.seal(1, b"uno").unwrap();
        let second = send.seal(1, b"dos").unwrap();

        // Out of order: the second record cannot open at position 0.
        let mut ahead = RecvCipher::new(Zeroizing::new([7u8; 32]));
        assert!(matches!(
            ahead.open(&second[4..]),
            Err(CoreError::AuthFailed)
        ));

        recv.open(&first[4..]).unwrap();
        // Replay of a record already accepted.
        assert!(matches!(recv.open(&first[4..]), Err(CoreError::AuthFailed)));

        // A rejected record does not consume a counter, so injecting one cannot silently
        // desynchronise a stream. It does not need to: `reader_loop` drops the session on the
        // first failure, and this is what keeps that decision from being load-bearing.
        recv.open(&second[4..]).unwrap();
    }

    #[test]
    fn wrong_key_and_tampered_record_fail() {
        let (mut send, _) = pair();
        let mut record = send.seal(1, b"hola").unwrap();

        let mut other = RecvCipher::new(Zeroizing::new([8u8; 32]));
        assert!(matches!(
            other.open(&record[4..]),
            Err(CoreError::AuthFailed)
        ));

        let last = record.len() - 1;
        record[last] ^= 0xff;
        let mut recv = RecvCipher::new(Zeroizing::new([7u8; 32]));
        assert!(matches!(
            recv.open(&record[4..]),
            Err(CoreError::AuthFailed)
        ));
    }

    /// The one thing padding buys: below the floor, an ACK and a short message are the same
    /// size on the wire. Above it, length is the payload's.
    #[test]
    fn short_records_share_one_size() {
        let (mut send, _) = pair();
        let ack = send.seal(2, &[]).unwrap();
        let short = send.seal(1, b"si").unwrap();
        let longer = send
            .seal(1, &vec![0u8; PAD_FLOOR - HEADER_LEN - 1])
            .unwrap();
        assert_eq!(ack.len(), short.len());
        assert_eq!(ack.len(), longer.len());
        assert_eq!(ack.len(), 4 + PAD_FLOOR + TAG_LEN);

        let big = send.seal(1, &vec![0u8; 4096]).unwrap();
        assert_eq!(big.len(), 4 + 4096 + TRANSPORT_OVERHEAD);
    }

    /// The generalisation of the example below, and the reason it lives here instead of in
    /// [`crate::fuzz`]: forging a record needs the session key, which only this module can
    /// reach. A peer that finished EH02 *has* that key, so an inner header that lies is not a
    /// hypothetical — it is the one decode in the transport an authenticated peer still
    /// controls. The name starts with `fuzz` so the nightly `--lib fuzz` filter picks it up.
    #[test]
    fn fuzz_any_inner_header_is_refused_or_stays_inside_the_record() {
        use proptest::prelude::*;

        proptest!(|(kind in any::<u8>(), declared in any::<u32>(), body_len in 0usize..1024)| {
            let key = Zeroizing::new([7u8; 32]);
            let mut plaintext = vec![kind];
            plaintext.extend_from_slice(&declared.to_be_bytes());
            plaintext.resize(HEADER_LEN + body_len, 0xab);
            let sealed = cipher(&key)
                .unwrap()
                .encrypt(&nonce_for(0), Payload { msg: &plaintext, aad: &[] })
                .unwrap();

            let mut recv = RecvCipher::new(key);
            match recv.open(&sealed) {
                // Accepting means the declared length fits: the payload has to be the slice it
                // named, never more than the record carried.
                Ok((got_kind, payload)) => {
                    prop_assert_eq!(got_kind, kind);
                    prop_assert_eq!(payload.len(), declared as usize);
                    prop_assert!(payload.len() <= body_len);
                }
                Err(CoreError::InvalidFrame) => {}
                Err(e) => prop_assert!(false, "unexpected error {e:?}"),
            }
        });
    }

    #[test]
    fn payload_length_lie_is_rejected() {
        let key = Zeroizing::new([7u8; 32]);
        let mut plaintext = vec![1u8];
        // Claim a payload longer than the plaintext that carries it.
        plaintext.extend_from_slice(&u32::MAX.to_be_bytes());
        plaintext.resize(PAD_FLOOR, 0);
        let body = cipher(&key)
            .unwrap()
            .encrypt(
                &nonce_for(0),
                Payload {
                    msg: &plaintext,
                    aad: &[],
                },
            )
            .unwrap();

        let mut recv = RecvCipher::new(key);
        assert!(matches!(recv.open(&body), Err(CoreError::InvalidFrame)));
    }
}
