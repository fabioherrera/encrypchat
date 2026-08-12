//! Sealed sender for blind-relay blobs (closes the Phase 5 P0).
//!
//! A relay blob has no session behind it: until now the sender was a `from` string
//! *declared* inside the ciphertext, so anyone holding the recipient's public key
//! could encrypt a blob and claim to be one of their contacts. (The P2P path had
//! the same hole for a different reason — see [`crate::handshake`], F-1 — and the
//! two are fixed with the same primitive, [`two_layer_seal`].)
//!
//! Encrypchat identities are X25519, which cannot sign. Instead of bolting a
//! second signing key onto every identity, this module authenticates with a
//! *designated verifier*: two Diffie-Hellman operations, as in the Noise `X`
//! pattern.
//!
//! | DH | Inputs | Buys |
//! | --- | --- | --- |
//! | `es` | ephemeral × recipient static | Confidentiality and sender anonymity towards the relay |
//! | `ss` | sender static × recipient static | Proof that the holder of the sender's secret produced this blob |
//!
//! Only the recipient can check `ss`, so a blob is **not** transferable proof
//! that the sender wrote it: anyone shown the blob and the recipient's secret
//! could have produced it themselves. That deniability is deliberate — a public
//! signature would turn every relayed blob into a receipt of who wrote to whom.
//!
//! Wire format (`ECS1`), all lengths fixed:
//!
//! ```text
//! magic(4) "ECS1"
//! eph_pub(32)          X25519 ephemeral, fresh per blob
//! nonce(12)            random; used by both AEAD layers under different keys
//! sealed_sender(48)    ChaCha20-Poly1305(k_id) over the sender public key
//! body(24 + n + 16)    ChaCha20-Poly1305(k_msg) over msg_id(16) || sent_at(8) || payload(n)
//! ```
//!
//! Keys, with `S` = sender public, `R` = recipient public, `E` = ephemeral public
//! (every input is a fixed 32-byte value, so plain concatenation is unambiguous):
//!
//! ```text
//! k_id  = SHA-256("encrypchat-sealed-id-v1"  || es       || E || R)
//! k_msg = SHA-256("encrypchat-sealed-msg-v1" || es || ss || E || R || S)
//! ```
//!
//! The sender identity travels encrypted under `k_id`, so the relay sees only
//! opaque bytes and cannot correlate senders with destinations. The payload key
//! commits to `S`, so the sender is bound to the *content*: there is no separate
//! field to strip, and splicing a `sealed_sender` from one blob onto another body
//! yields a key nobody can reproduce.

use std::time::{SystemTime, UNIX_EPOCH};

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{ChaCha20Poly1305, Nonce};
use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, SharedSecret, StaticSecret};
use zeroize::Zeroizing;

use crate::error::CoreError;
use crate::identity::{Identity, PublicIdentity};
use crate::pubkey::{ensure_canonical_public_key, is_canonical_public_key};

/// Magic prefix of a sealed-sender blob.
pub const SEALED_MAGIC: &[u8; 4] = b"ECS1";

/// Domain separation for the two AEAD layers of one construction. Distinct pairs keep
/// unrelated protocols apart: an `ECS1` relay blob can never be replayed as an `EH02`
/// handshake proof, or the reverse.
pub(crate) struct TwoLayerDomains {
    pub id: &'static [u8],
    pub msg: &'static [u8],
}

pub(crate) const SEALED_DOMAINS: TwoLayerDomains = TwoLayerDomains {
    id: b"encrypchat-sealed-id-v1",
    msg: b"encrypchat-sealed-msg-v1",
};

pub(crate) const PUBKEY_LEN: usize = 32;
const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;
const SEALED_SENDER_LEN: usize = PUBKEY_LEN + TAG_LEN;

/// Bytes a two-layer blob adds on top of its payload (108).
pub(crate) const TWO_LAYER_OVERHEAD: usize = PUBKEY_LEN + NONCE_LEN + SEALED_SENDER_LEN + TAG_LEN;

/// Length of the per-blob message id the recipient uses for de-duplication.
pub const SEALED_MSG_ID_LEN: usize = 16;

/// `msg_id(16) || sent_at(8)` in front of the payload, inside the body AEAD.
const INNER_HEADER_LEN: usize = SEALED_MSG_ID_LEN + 8;

/// Bytes a sealed blob adds on top of the payload (136).
pub const SEALED_OVERHEAD: usize = SEALED_MAGIC.len() + TWO_LAYER_OVERHEAD + INNER_HEADER_LEN;

/// Oldest `sent_at` accepted by [`open_sealed`]. Matches the relay's max TTL, so a
/// blob that the relay could still be holding is never rejected as stale.
pub const SEALED_MAX_AGE_SECS: u64 = 7 * 24 * 3600;

/// Clock skew tolerated for a `sent_at` in the future.
pub const SEALED_MAX_SKEW_SECS: u64 = 300;

/// A sealed blob plus the values bound inside it.
#[derive(Clone)]
pub struct SealedMessage {
    pub blob: Vec<u8>,
    pub msg_id: [u8; SEALED_MSG_ID_LEN],
    pub sent_at_unix: u64,
}

impl std::fmt::Debug for SealedMessage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SealedMessage")
            .field("len", &self.blob.len())
            .field("msg_id", &hex::encode(self.msg_id))
            .field("sent_at_unix", &self.sent_at_unix)
            .finish()
    }
}

/// Result of opening a sealed blob. `sender` is authenticated, not declared.
#[derive(Clone)]
pub struct OpenedMessage {
    pub sender: PublicIdentity,
    pub msg_id: [u8; SEALED_MSG_ID_LEN],
    pub sent_at_unix: u64,
    pub plaintext: Vec<u8>,
}

impl std::fmt::Debug for OpenedMessage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OpenedMessage")
            .field("sender", &self.sender.token().as_str())
            .field("msg_id", &hex::encode(self.msg_id))
            .field("sent_at_unix", &self.sent_at_unix)
            .field("plaintext_len", &self.plaintext.len())
            .finish()
    }
}

fn unix_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub(crate) fn derive_key(domain: &[u8], parts: &[&[u8]]) -> Zeroizing<[u8; 32]> {
    let mut hasher = Sha256::new();
    hasher.update(domain);
    for part in parts {
        hasher.update(part);
    }
    let digest = hasher.finalize();
    let mut key = Zeroizing::new([0u8; 32]);
    key.copy_from_slice(&digest);
    key
}

/// Reject degenerate (small-order) peer keys: their shared secret is all-zero and
/// therefore known to anyone, which would let a stranger derive `ss` without
/// holding any secret.
pub(crate) fn contributory(
    shared: SharedSecret,
    on_fail: CoreError,
) -> Result<SharedSecret, CoreError> {
    if shared.was_contributory() {
        Ok(shared)
    } else {
        Err(on_fail)
    }
}

pub(crate) fn cipher(key: &[u8; 32]) -> Result<ChaCha20Poly1305, CoreError> {
    ChaCha20Poly1305::new_from_slice(key).map_err(|_| CoreError::Internal)
}

fn layer_aad(aad_prefix: &[u8], eph_pub: &[u8; 32], nonce: &[u8; NONCE_LEN]) -> Vec<u8> {
    let mut aad = Vec::with_capacity(aad_prefix.len() + PUBKEY_LEN + NONCE_LEN);
    aad.extend_from_slice(aad_prefix);
    aad.extend_from_slice(eph_pub);
    aad.extend_from_slice(nonce);
    aad
}

fn body_aad(
    aad_prefix: &[u8],
    eph_pub: &[u8; 32],
    nonce: &[u8; NONCE_LEN],
    sealed: &[u8],
) -> Vec<u8> {
    let mut aad = layer_aad(aad_prefix, eph_pub, nonce);
    aad.extend_from_slice(sealed);
    aad
}

/// Two-layer designated-verifier seal: `E(32) || nonce(12) || sealed_sender(48) || body`.
///
/// Layer one hides the sender's static public key behind `es` (fresh ephemeral × recipient),
/// layer two authenticates the payload with a key that also mixes `ss` (sender static ×
/// recipient static) **and** commits to the sender key itself. Producing a body that opens
/// therefore requires the sender's private key, and only the recipient can check it.
///
/// `aad_prefix` binds the blob to its protocol and context; nothing else distinguishes one
/// use of this primitive from another, so callers must make it unambiguous.
pub(crate) fn two_layer_seal(
    domains: &TwoLayerDomains,
    sender_secret: &StaticSecret,
    recipient_pub: &[u8; PUBKEY_LEN],
    aad_prefix: &[u8],
    payload: &[u8],
) -> Result<Vec<u8>, CoreError> {
    let recipient_key = PublicKey::from(*recipient_pub);
    let sender_pub = PublicKey::from(sender_secret).to_bytes();

    let eph_secret = StaticSecret::random_from_rng(OsRng);
    let eph_pub = PublicKey::from(&eph_secret).to_bytes();

    let es = contributory(
        eph_secret.diffie_hellman(&recipient_key),
        CoreError::InvalidPublicKey,
    )?;
    let ss = contributory(
        sender_secret.diffie_hellman(&recipient_key),
        CoreError::InvalidPublicKey,
    )?;

    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    // Both layers reuse `nonce` under different keys, which is safe, and both keys are
    // unique per blob because they hang off a fresh ephemeral.
    let k_id = derive_key(domains.id, &[es.as_bytes(), &eph_pub, recipient_pub]);
    let sealed_sender = cipher(&k_id)?
        .encrypt(
            nonce,
            Payload {
                msg: &sender_pub,
                aad: &layer_aad(aad_prefix, &eph_pub, &nonce_bytes),
            },
        )
        .map_err(|_| CoreError::Internal)?;

    let k_msg = derive_key(
        domains.msg,
        &[
            es.as_bytes(),
            ss.as_bytes(),
            &eph_pub,
            recipient_pub,
            &sender_pub,
        ],
    );
    let body = cipher(&k_msg)?
        .encrypt(
            nonce,
            Payload {
                msg: payload,
                aad: &body_aad(aad_prefix, &eph_pub, &nonce_bytes, &sealed_sender),
            },
        )
        .map_err(|_| CoreError::Internal)?;

    let mut blob = Vec::with_capacity(TWO_LAYER_OVERHEAD + payload.len());
    blob.extend_from_slice(&eph_pub);
    blob.extend_from_slice(&nonce_bytes);
    blob.extend_from_slice(&sealed_sender);
    blob.extend_from_slice(&body);
    Ok(blob)
}

/// Open a [`two_layer_seal`] blob, returning the **authenticated** sender key and the payload.
///
/// [`CoreError::DecryptionFailed`] means the blob is not addressed to this key or its header
/// is corrupt; [`CoreError::AuthFailed`] means it is addressed to us but the sender binding
/// does not hold — a forged sender or a tampered body.
pub(crate) fn two_layer_open(
    domains: &TwoLayerDomains,
    recipient_secret: &StaticSecret,
    aad_prefix: &[u8],
    blob: &[u8],
) -> Result<([u8; PUBKEY_LEN], Vec<u8>), CoreError> {
    if blob.len() < TWO_LAYER_OVERHEAD {
        return Err(CoreError::CiphertextTooShort);
    }

    let mut cursor = 0;
    let mut eph_pub = [0u8; PUBKEY_LEN];
    eph_pub.copy_from_slice(&blob[cursor..cursor + PUBKEY_LEN]);
    cursor += PUBKEY_LEN;
    let mut nonce_bytes = [0u8; NONCE_LEN];
    nonce_bytes.copy_from_slice(&blob[cursor..cursor + NONCE_LEN]);
    cursor += NONCE_LEN;
    let sealed_sender = &blob[cursor..cursor + SEALED_SENDER_LEN];
    cursor += SEALED_SENDER_LEN;
    let body = &blob[cursor..];

    // Before anything is derived from it: a non-canonical ephemeral is not a key this
    // implementation can have produced, and the header is what the error is about.
    if !is_canonical_public_key(&eph_pub) {
        return Err(CoreError::DecryptionFailed);
    }

    let nonce = Nonce::from_slice(&nonce_bytes);
    let recipient_pub = PublicKey::from(recipient_secret).to_bytes();

    let es = contributory(
        recipient_secret.diffie_hellman(&PublicKey::from(eph_pub)),
        CoreError::DecryptionFailed,
    )?;
    let k_id = derive_key(domains.id, &[es.as_bytes(), &eph_pub, &recipient_pub]);
    let sender_pub_vec = cipher(&k_id)?
        .decrypt(
            nonce,
            Payload {
                msg: sealed_sender,
                aad: &layer_aad(aad_prefix, &eph_pub, &nonce_bytes),
            },
        )
        .map_err(|_| CoreError::DecryptionFailed)?;
    let sender_pub: [u8; PUBKEY_LEN] = sender_pub_vec
        .as_slice()
        .try_into()
        .map_err(|_| CoreError::InvalidPublicKey)?;

    // The door of the relay route (F-10). Everything below — and everything the caller does
    // with the key we return — treats these bytes as *the* name of the sender, but the
    // Diffie-Hellman below would accept an alias of them just as happily: `ss` is identical
    // for `S` and `S | (1 << 255)`, and `k_msg` commits to whichever spelling the sender
    // chose. A blocked peer could therefore re-derive a clean token from the same key.
    ensure_canonical_public_key(&sender_pub)?;

    // From here the blob is provably addressed to us, so every remaining failure is an
    // authenticity failure rather than "wrong recipient".
    let ss = contributory(
        recipient_secret.diffie_hellman(&PublicKey::from(sender_pub)),
        CoreError::AuthFailed,
    )?;
    let k_msg = derive_key(
        domains.msg,
        &[
            es.as_bytes(),
            ss.as_bytes(),
            &eph_pub,
            &recipient_pub,
            &sender_pub,
        ],
    );
    let payload = cipher(&k_msg)?
        .decrypt(
            nonce,
            Payload {
                msg: body,
                aad: &body_aad(aad_prefix, &eph_pub, &nonce_bytes, sealed_sender),
            },
        )
        .map_err(|_| CoreError::AuthFailed)?;

    Ok((sender_pub, payload))
}

/// Build a blob that *claims* `claimed_sender_pub` while only holding `actual_sender_secret`
/// — everything an attacker who knows a victim's public key can do. Test-only, and the
/// reason it exists is that the negative tests must exercise the real attack rather than a
/// corrupted byte.
#[cfg(test)]
pub(crate) fn two_layer_seal_claiming(
    domains: &TwoLayerDomains,
    actual_sender_secret: &StaticSecret,
    claimed_sender_pub: &[u8; PUBKEY_LEN],
    recipient_pub: &[u8; PUBKEY_LEN],
    aad_prefix: &[u8],
    payload: &[u8],
) -> Vec<u8> {
    let recipient_key = PublicKey::from(*recipient_pub);
    let eph_secret = StaticSecret::random_from_rng(OsRng);
    let eph_pub = PublicKey::from(&eph_secret).to_bytes();
    let es = eph_secret.diffie_hellman(&recipient_key);
    // The best static-static DH the attacker can reach is her own.
    let ss = actual_sender_secret.diffie_hellman(&recipient_key);

    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let k_id = derive_key(domains.id, &[es.as_bytes(), &eph_pub, recipient_pub]);
    let sealed_sender = cipher(&k_id)
        .unwrap()
        .encrypt(
            nonce,
            Payload {
                msg: claimed_sender_pub.as_slice(),
                aad: &layer_aad(aad_prefix, &eph_pub, &nonce_bytes),
            },
        )
        .unwrap();

    let k_msg = derive_key(
        domains.msg,
        &[
            es.as_bytes(),
            ss.as_bytes(),
            &eph_pub,
            recipient_pub,
            claimed_sender_pub,
        ],
    );
    let body = cipher(&k_msg)
        .unwrap()
        .encrypt(
            nonce,
            Payload {
                msg: payload,
                aad: &body_aad(aad_prefix, &eph_pub, &nonce_bytes, &sealed_sender),
            },
        )
        .unwrap();

    let mut blob = Vec::with_capacity(TWO_LAYER_OVERHEAD + payload.len());
    blob.extend_from_slice(&eph_pub);
    blob.extend_from_slice(&nonce_bytes);
    blob.extend_from_slice(&sealed_sender);
    blob.extend_from_slice(&body);
    blob
}

/// Seal `plaintext` for `recipient`, binding `sender` to the content.
///
/// The timestamp comes from the local clock; use [`seal_sender_at`] to pin it.
pub fn seal_sender(
    sender: &Identity,
    recipient: &PublicIdentity,
    plaintext: &[u8],
) -> Result<SealedMessage, CoreError> {
    seal_sender_at(sender, recipient, plaintext, unix_now())
}

/// [`seal_sender`] with an explicit `sent_at`, in seconds since the Unix epoch.
///
/// The value is authenticated but not verifiable: a sender can always lie about
/// it. It exists so the recipient can bound how long it must remember message
/// ids, not as a trusted timestamp.
pub fn seal_sender_at(
    sender: &Identity,
    recipient: &PublicIdentity,
    plaintext: &[u8],
    sent_at_unix: u64,
) -> Result<SealedMessage, CoreError> {
    if plaintext.is_empty() {
        return Err(CoreError::EmptyPlaintext);
    }

    let mut msg_id = [0u8; SEALED_MSG_ID_LEN];
    OsRng.fill_bytes(&mut msg_id);

    let mut inner = Vec::with_capacity(INNER_HEADER_LEN + plaintext.len());
    inner.extend_from_slice(&msg_id);
    inner.extend_from_slice(&sent_at_unix.to_be_bytes());
    inner.extend_from_slice(plaintext);

    let sealed = two_layer_seal(
        &SEALED_DOMAINS,
        &sender.static_secret(),
        &recipient.public_key_bytes(),
        SEALED_MAGIC,
        &inner,
    )?;

    let mut blob = Vec::with_capacity(SEALED_MAGIC.len() + sealed.len());
    blob.extend_from_slice(SEALED_MAGIC);
    blob.extend_from_slice(&sealed);

    Ok(SealedMessage {
        blob,
        msg_id,
        sent_at_unix,
    })
}

/// Open a sealed blob and authenticate its sender.
///
/// `now_unix` enables the freshness window: `None` skips it entirely, which is for
/// tests and for callers with no trustworthy clock. Outside the window the blob is
/// rejected with [`CoreError::Expired`] *after* authentication, so a stale blob is
/// never confused with a forged one.
///
/// Failure modes are distinguishable on purpose:
///
/// | Error | Meaning |
/// | --- | --- |
/// | [`CoreError::InvalidFrame`] | Not an `ECS1` blob (e.g. a pre-0.8.0 payload) |
/// | [`CoreError::CiphertextTooShort`] | `ECS1` but truncated |
/// | [`CoreError::DecryptionFailed`] | Not addressed to this identity, or the header is corrupt |
/// | [`CoreError::InvalidPublicKey`] | Addressed to us, but the sender key is a non-canonical encoding |
/// | [`CoreError::AuthFailed`] | Addressed to us, but the sender binding does not hold: forged sender or tampered body |
/// | [`CoreError::Expired`] | Authentic, but `sent_at` is outside the window |
pub fn open_sealed(
    recipient: &Identity,
    blob: &[u8],
    now_unix: Option<u64>,
) -> Result<OpenedMessage, CoreError> {
    if blob.len() < SEALED_MAGIC.len() || &blob[..SEALED_MAGIC.len()] != SEALED_MAGIC {
        return Err(CoreError::InvalidFrame);
    }
    if blob.len() <= SEALED_OVERHEAD {
        // `<=`: an empty payload is never produced, so it is a malformed blob.
        return Err(CoreError::CiphertextTooShort);
    }

    let (sender_pub, inner) = two_layer_open(
        &SEALED_DOMAINS,
        &recipient.static_secret(),
        SEALED_MAGIC,
        &blob[SEALED_MAGIC.len()..],
    )?;

    if inner.len() <= INNER_HEADER_LEN {
        return Err(CoreError::InvalidFrame);
    }
    let mut msg_id = [0u8; SEALED_MSG_ID_LEN];
    msg_id.copy_from_slice(&inner[..SEALED_MSG_ID_LEN]);
    let mut ts_bytes = [0u8; 8];
    ts_bytes.copy_from_slice(&inner[SEALED_MSG_ID_LEN..INNER_HEADER_LEN]);
    let sent_at_unix = u64::from_be_bytes(ts_bytes);
    let plaintext = inner[INNER_HEADER_LEN..].to_vec();

    if let Some(now) = now_unix {
        let too_new = sent_at_unix.saturating_sub(now) > SEALED_MAX_SKEW_SECS;
        let too_old = now.saturating_sub(sent_at_unix) > SEALED_MAX_AGE_SECS;
        if too_new || too_old {
            return Err(CoreError::Expired);
        }
    }

    Ok(OpenedMessage {
        // Already canonical — `two_layer_open` is the gate — but this is the constructor
        // that owns the invariant, so it stays fallible rather than being asserted here.
        sender: PublicIdentity::try_from_public_key_bytes(sender_pub)?,
        msg_id,
        sent_at_unix,
        plaintext,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pubkey::test_vectors::{high_bit_alias, non_reduced_max, NON_REDUCED_ZERO};

    fn contains(haystack: &[u8], needle: &[u8]) -> bool {
        haystack.windows(needle.len()).any(|w| w == needle)
    }

    #[test]
    fn roundtrip_authenticates_sender() {
        let alice = Identity::generate();
        let bob = Identity::generate();

        let sealed = seal_sender(&alice, &bob.public_identity(), b"hola bob").unwrap();
        assert_eq!(sealed.blob.len(), SEALED_OVERHEAD + 8);

        let opened = open_sealed(&bob, &sealed.blob, Some(unix_now())).unwrap();
        assert_eq!(opened.plaintext, b"hola bob");
        assert_eq!(opened.sender.token().as_str(), alice.token().as_str());
        assert_eq!(opened.sender.public_key_bytes(), alice.public_key_bytes());
        assert_eq!(opened.msg_id, sealed.msg_id);
        assert_eq!(opened.sent_at_unix, sealed.sent_at_unix);
    }

    /// The P0 itself, built with nothing but what Mallory has: Bob's public key,
    /// Alice's public key, her own secret and an ephemeral she picks. She can
    /// rewrite the identity layer freely — it only needs `es` — but the body key
    /// commits to `DH(alice_secret, bob_pub)`, which she cannot compute.
    #[test]
    fn forged_sender_rejected() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let mallory = Identity::generate();

        let mut inner = vec![0u8; INNER_HEADER_LEN];
        inner[SEALED_MSG_ID_LEN..].copy_from_slice(&unix_now().to_be_bytes());
        inner.extend_from_slice(b"transferi a esta cuenta");

        let mut blob = Vec::from(*SEALED_MAGIC);
        blob.extend_from_slice(&two_layer_seal_claiming(
            &SEALED_DOMAINS,
            &mallory.static_secret(),
            &alice.public_key_bytes(),
            &bob.public_key_bytes(),
            SEALED_MAGIC,
            &inner,
        ));

        assert!(matches!(
            open_sealed(&bob, &blob, Some(unix_now())),
            Err(CoreError::AuthFailed)
        ));
    }

    /// F-10 on the relay route. Mallory is blocked, so she seals with her real secret while
    /// *claiming* an alias of her own public key. Every Diffie-Hellman is unchanged — `ss` is
    /// the same shared secret, so the blob is genuinely authentic — and before this check Bob
    /// opened it and derived a token he had never blocked.
    #[test]
    fn alias_of_the_sender_key_cannot_mint_a_second_identity() {
        let bob = Identity::generate();
        let mallory = Identity::generate();
        let alias = high_bit_alias(&mallory.public_key_bytes());

        // The premise, stated as an assertion: same key to the curve, different hash.
        assert_eq!(
            mallory
                .static_secret()
                .diffie_hellman(&PublicKey::from(bob.public_key_bytes()))
                .to_bytes(),
            bob.static_secret()
                .diffie_hellman(&PublicKey::from(alias))
                .to_bytes(),
            "the alias must really be the same key, or this test proves nothing"
        );
        assert_ne!(
            Sha256::digest(alias),
            Sha256::digest(mallory.public_key_bytes())
        );

        let mut inner = vec![0u8; INNER_HEADER_LEN];
        inner[SEALED_MSG_ID_LEN..].copy_from_slice(&unix_now().to_be_bytes());
        inner.extend_from_slice(b"hola de nuevo");

        let mut blob = Vec::from(*SEALED_MAGIC);
        blob.extend_from_slice(&two_layer_seal_claiming(
            &SEALED_DOMAINS,
            &mallory.static_secret(),
            &alias,
            &bob.public_key_bytes(),
            SEALED_MAGIC,
            &inner,
        ));

        assert!(matches!(
            open_sealed(&bob, &blob, Some(unix_now())),
            Err(CoreError::InvalidPublicKey)
        ));

        // Control: the same construction with the canonical key is a valid blob, so the
        // rejection above is about the encoding and nothing else.
        let honest = seal_sender(&mallory, &bob.public_identity(), b"hola de nuevo").unwrap();
        assert_eq!(
            open_sealed(&bob, &honest.blob, Some(unix_now()))
                .unwrap()
                .sender
                .token()
                .as_str(),
            mallory.token().as_str()
        );
    }

    /// The other half of the alias family: a non-reduced encoding, which needs no victim key
    /// at all — `2^255 - 19` is a spelling of `u = 0`.
    #[test]
    fn non_reduced_sender_key_rejected_before_the_dh() {
        let bob = Identity::generate();
        let mallory = Identity::generate();

        let mut inner = vec![0u8; INNER_HEADER_LEN];
        inner[SEALED_MSG_ID_LEN..].copy_from_slice(&unix_now().to_be_bytes());
        inner.extend_from_slice(b"cero disfrazado");

        for claimed in [NON_REDUCED_ZERO, non_reduced_max()] {
            let mut blob = Vec::from(*SEALED_MAGIC);
            blob.extend_from_slice(&two_layer_seal_claiming(
                &SEALED_DOMAINS,
                &mallory.static_secret(),
                &claimed,
                &bob.public_key_bytes(),
                SEALED_MAGIC,
                &inner,
            ));
            assert!(
                matches!(
                    open_sealed(&bob, &blob, Some(unix_now())),
                    Err(CoreError::InvalidPublicKey)
                ),
                "{} must not be read as a sender",
                hex::encode(claimed)
            );
        }
    }

    /// The blob header carries a public key too. Nothing derives an identity from it, but it
    /// is an X25519 key arriving from outside and the rule has no exceptions.
    #[test]
    fn non_canonical_ephemeral_in_the_header_rejected() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let mut blob = seal_sender(&alice, &bob.public_identity(), b"hola")
            .unwrap()
            .blob;
        let eph_high_byte = SEALED_MAGIC.len() + PUBKEY_LEN - 1;
        blob[eph_high_byte] |= 0x80;
        assert!(matches!(
            open_sealed(&bob, &blob, None),
            Err(CoreError::DecryptionFailed)
        ));
    }

    #[test]
    fn tampered_body_rejected() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let mut blob = seal_sender(&alice, &bob.public_identity(), b"pagame 10")
            .unwrap()
            .blob;
        let last = blob.len() - 1;
        blob[last] ^= 0xff;
        assert!(matches!(
            open_sealed(&bob, &blob, Some(unix_now())),
            Err(CoreError::AuthFailed)
        ));
    }

    /// Splicing the authenticated sender of one blob onto another body must fail:
    /// the sender is bound to the content, not carried beside it.
    #[test]
    fn spliced_sender_rejected() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let mallory = Identity::generate();

        let honest = seal_sender(&alice, &bob.public_identity(), b"de alice")
            .unwrap()
            .blob;
        let mut attack = seal_sender(&mallory, &bob.public_identity(), b"de mallory")
            .unwrap()
            .blob;
        attack[48..48 + SEALED_SENDER_LEN].copy_from_slice(&honest[48..48 + SEALED_SENDER_LEN]);

        assert!(matches!(
            open_sealed(&bob, &attack, Some(unix_now())),
            Err(CoreError::DecryptionFailed)
        ));
    }

    #[test]
    fn wrong_recipient_cannot_open() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let carol = Identity::generate();
        let sealed = seal_sender(&alice, &bob.public_identity(), b"solo para bob").unwrap();
        assert!(matches!(
            open_sealed(&carol, &sealed.blob, Some(unix_now())),
            Err(CoreError::DecryptionFailed)
        ));
    }

    #[test]
    fn tampered_identity_layer_is_not_for_us() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let mut blob = seal_sender(&alice, &bob.public_identity(), b"hola")
            .unwrap()
            .blob;
        blob[50] ^= 0xff;
        assert!(matches!(
            open_sealed(&bob, &blob, Some(unix_now())),
            Err(CoreError::DecryptionFailed)
        ));
    }

    #[test]
    fn freshness_window_enforced() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let now = 1_800_000_000u64;

        let fresh = seal_sender_at(&alice, &bob.public_identity(), b"ahora", now).unwrap();
        assert!(open_sealed(&bob, &fresh.blob, Some(now)).is_ok());

        let stale = seal_sender_at(
            &alice,
            &bob.public_identity(),
            b"viejo",
            now - SEALED_MAX_AGE_SECS - 1,
        )
        .unwrap();
        assert!(matches!(
            open_sealed(&bob, &stale.blob, Some(now)),
            Err(CoreError::Expired)
        ));
        // Without a clock the same blob still opens: the window is opt-in.
        assert!(open_sealed(&bob, &stale.blob, None).is_ok());

        let future = seal_sender_at(
            &alice,
            &bob.public_identity(),
            b"futuro",
            now + SEALED_MAX_SKEW_SECS + 1,
        )
        .unwrap();
        assert!(matches!(
            open_sealed(&bob, &future.blob, Some(now)),
            Err(CoreError::Expired)
        ));
    }

    #[test]
    fn legacy_and_truncated_blobs_are_distinguishable() {
        let bob = Identity::generate();
        let legacy = crate::crypto::encrypt(&bob.public_identity(), b"formato viejo").unwrap();
        assert!(matches!(
            open_sealed(&bob, legacy.as_bytes(), None),
            Err(CoreError::InvalidFrame)
        ));

        let alice = Identity::generate();
        let sealed = seal_sender(&alice, &bob.public_identity(), b"hola").unwrap();
        assert!(matches!(
            open_sealed(&bob, &sealed.blob[..SEALED_OVERHEAD], None),
            Err(CoreError::CiphertextTooShort)
        ));
        assert!(matches!(
            open_sealed(&bob, b"EC", None),
            Err(CoreError::InvalidFrame)
        ));
    }

    #[test]
    fn empty_plaintext_rejected() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        assert!(matches!(
            seal_sender(&alice, &bob.public_identity(), b""),
            Err(CoreError::EmptyPlaintext)
        ));
    }

    /// The relay must not learn anything it did not already know: no sender key,
    /// no sender token, and no two blobs alike even for identical content.
    #[test]
    fn blob_reveals_nothing_about_the_sender() {
        let alice = Identity::generate();
        let bob = Identity::generate();

        let first = seal_sender(&alice, &bob.public_identity(), b"mismo texto").unwrap();
        let second = seal_sender(&alice, &bob.public_identity(), b"mismo texto").unwrap();

        for sealed in [&first, &second] {
            assert!(!contains(&sealed.blob, &alice.public_key_bytes()));
            assert!(!contains(&sealed.blob, alice.token().as_str().as_bytes()));
            assert!(!contains(&sealed.blob, &bob.public_key_bytes()));
            assert!(!contains(&sealed.blob, b"mismo texto"));
        }
        assert_ne!(first.blob, second.blob);
        assert_ne!(first.msg_id, second.msg_id);
        assert_ne!(
            &first.blob[4..36],
            &second.blob[4..36],
            "ephemeral must be fresh per blob"
        );
    }

    /// A captured blob replays byte-for-byte: core hands back `msg_id` precisely so
    /// the caller can drop the duplicate. Anti-replay is the caller's job.
    #[test]
    fn replay_opens_again_with_the_same_msg_id() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let sealed = seal_sender(&alice, &bob.public_identity(), b"una vez").unwrap();

        let first = open_sealed(&bob, &sealed.blob, Some(unix_now())).unwrap();
        let replayed = open_sealed(&bob, &sealed.blob, Some(unix_now())).unwrap();
        assert_eq!(first.msg_id, replayed.msg_id);
    }

    #[test]
    fn debug_omits_payload() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let sealed = seal_sender(&alice, &bob.public_identity(), b"secreto").unwrap();
        let opened = open_sealed(&bob, &sealed.blob, None).unwrap();
        assert!(!format!("{sealed:?}").contains("secreto"));
        assert!(!format!("{opened:?}").contains("secreto"));
    }
}
