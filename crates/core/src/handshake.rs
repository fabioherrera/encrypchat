//! EH02 — mutual authentication for the P2P transport (closes F-1 and part of F-5).
//!
//! ## What was broken
//!
//! EH01 proved nothing. Its proof was `encrypt(peer_pubkey, nonces || own_token)`, and
//! [`crate::crypto::encrypt`] generates a *sender* ephemeral, so building that blob only
//! required the **verifier's public key**. Everything the verifier then checked — the two
//! nonces, and that the declared token was `SHA-256(offered pubkey)` — is public
//! information. Mallory could take Alice's contact card, dial Bob claiming Alice's token
//! and pubkey, and be registered as Alice.
//!
//! ## What replaces it
//!
//! The same designated-verifier primitive the relay path uses,
//! [`crate::sealed::two_layer_seal`]: a proof opens only if its author could compute a
//! static-static Diffie-Hellman against the verifier's key. Holding the victim's *public*
//! key is not enough, which is exactly the property EH01 lacked.
//!
//! ```text
//! 1. initiator → EH02(4) || ver(1) || e_i_pub(32) || nonce_i(32)
//! 2. responder ← e_r_pub(32) || nonce_r(32)          no identity yet
//! 3. initiator → len(4) || proof_i(108)              seals S_i to e_r_pub
//! 4. responder ← len(4) || proof_r(108)              seals S_r to S_i
//! ```
//!
//! Message 3 is sealed to the responder's **ephemeral** key, which is why the initiator can
//! authenticate first without knowing who it is talking to. Producing it requires
//! `DH(initiator_secret, e_r_pub)`. Message 4 is sealed to the initiator's now-authenticated
//! static key and requires `DH(responder_secret, S_i)`.
//!
//! Both payloads are empty: everything either side needs to agree on — protocol, version,
//! role, both ephemerals and both nonces — is in the AEAD associated data, so a proof cannot
//! be lifted into another session, another role, or another protocol. In particular the two
//! ephemerals are covered by both proofs, so an active attacker cannot substitute one.
//!
//! ## Session keys
//!
//! The ephemerals exist twice over: they let the initiator authenticate first, and they give
//! the session key its forward secrecy. [`SessionKeys`] mixes the four Diffie-Hellmans of
//! the Noise `XX` schedule and splits the result per direction; the transport
//! ([`crate::transport`]) encrypts every record with them.
//!
//! ## Identity exposure (F-5)
//!
//! The responder emits nothing but random-looking bytes until the initiator has
//! authenticated, so a passive observer learns no identity from a handshake and a stranger
//! who cannot prove *some* identity learns nothing at all. What remains is inherent to
//! authenticating two parties who do not know each other's keys in advance: the initiator
//! must reveal itself first, and an active connector with a throwaway identity therefore
//! still obtains the responder's identity. See `docs/threat-model.md` §6.2.

use rand::rngs::OsRng;
use rand::RngCore;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::Zeroizing;

use crate::error::CoreError;
use crate::pubkey::is_canonical_public_key;
use crate::sealed::{
    contributory, derive_key, two_layer_open, two_layer_seal, TwoLayerDomains, TWO_LAYER_OVERHEAD,
};

pub(crate) const EH02_MAGIC: &[u8; 4] = b"EH02";
pub(crate) const EH02_VERSION: u8 = 2;
pub(crate) const EH02_NONCE_LEN: usize = 32;
pub(crate) const EH02_PUBKEY_LEN: usize = 32;

/// `EH02 || ver || e_i_pub || nonce_i`.
pub(crate) const EH02_HELLO_LEN: usize = 4 + 1 + EH02_PUBKEY_LEN + EH02_NONCE_LEN;
/// `e_r_pub || nonce_r`.
pub(crate) const EH02_CHALLENGE_LEN: usize = EH02_PUBKEY_LEN + EH02_NONCE_LEN;
/// Both proofs are a two-layer blob over an empty payload.
pub(crate) const EH02_PROOF_LEN: usize = TWO_LAYER_OVERHEAD;

const EH02_DOMAINS: TwoLayerDomains = TwoLayerDomains {
    id: b"encrypchat-eh02-id-v1",
    msg: b"encrypchat-eh02-msg-v1",
};

const SESSION_DOMAIN: &[u8] = b"encrypchat-eh02-session-v1";
const I2R_DOMAIN: &[u8] = b"encrypchat-eh02-i2r-v1";
const R2I_DOMAIN: &[u8] = b"encrypchat-eh02-r2i-v1";

const ROLE_INITIATOR: u8 = 3;
const ROLE_RESPONDER: u8 = 4;

/// One-shot X25519 keypair. Each side contributes one: they let the initiator authenticate
/// before knowing who the responder is, and they are what makes the session key forward
/// secret. The secret must be dropped when the handshake ends — that is the whole point.
pub(crate) struct Ephemeral {
    pub secret: StaticSecret,
    pub public: [u8; EH02_PUBKEY_LEN],
}

impl Ephemeral {
    pub fn generate() -> Self {
        let secret = StaticSecret::random_from_rng(OsRng);
        let public = PublicKey::from(&secret).to_bytes();
        Self { secret, public }
    }
}

impl std::fmt::Debug for Ephemeral {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Ephemeral")
            .field("public", &hex::encode(self.public))
            .field("secret", &"<redacted>")
            .finish()
    }
}

/// Everything both sides must agree on. Carried in the AAD of both proofs and mixed into the
/// session key, so nothing here can be substituted by an attacker in the middle.
pub(crate) struct Transcript {
    pub initiator_eph: [u8; EH02_PUBKEY_LEN],
    pub responder_eph: [u8; EH02_PUBKEY_LEN],
    pub nonce_i: [u8; EH02_NONCE_LEN],
    pub nonce_r: [u8; EH02_NONCE_LEN],
}

impl Transcript {
    fn bytes(&self, role: u8) -> Vec<u8> {
        let mut out = Vec::with_capacity(4 + 2 + 2 * EH02_PUBKEY_LEN + 2 * EH02_NONCE_LEN);
        out.extend_from_slice(EH02_MAGIC);
        out.push(EH02_VERSION);
        out.push(role);
        out.extend_from_slice(&self.initiator_eph);
        out.extend_from_slice(&self.responder_eph);
        out.extend_from_slice(&self.nonce_i);
        out.extend_from_slice(&self.nonce_r);
        out
    }

    /// Role byte `0`: the session key belongs to both sides, not to one direction of the
    /// handshake. Direction is separated afterwards, per key.
    fn session_bytes(&self) -> Vec<u8> {
        self.bytes(0)
    }
}

/// Transport keys for one session, already split by direction for the local role.
pub(crate) struct SessionKeys {
    pub send: Zeroizing<[u8; 32]>,
    pub recv: Zeroizing<[u8; 32]>,
}

pub(crate) fn new_nonce() -> [u8; EH02_NONCE_LEN] {
    let mut nonce = [0u8; EH02_NONCE_LEN];
    OsRng.fill_bytes(&mut nonce);
    nonce
}

pub(crate) fn hello_bytes(
    eph_pub: &[u8; EH02_PUBKEY_LEN],
    nonce_i: &[u8; EH02_NONCE_LEN],
) -> [u8; EH02_HELLO_LEN] {
    let mut out = [0u8; EH02_HELLO_LEN];
    out[..4].copy_from_slice(EH02_MAGIC);
    out[4] = EH02_VERSION;
    out[5..5 + EH02_PUBKEY_LEN].copy_from_slice(eph_pub);
    out[5 + EH02_PUBKEY_LEN..].copy_from_slice(nonce_i);
    out
}

/// Parse message 1. A peer still speaking EH01 fails here on the magic, which is the
/// intended outcome: the handshake changed and both ends must be on `0.8.0`.
///
/// The ephemeral is checked for a canonical encoding even though no identity is derived from
/// it: it is covered by both proofs and by the session key, so an alias only ever means a
/// transcript the two sides disagree about. Refusing it here keeps the rule uniform — no
/// non-canonical public key crosses into the core — instead of leaving an exception whose
/// safety has to be re-argued every time the handshake grows a field.
pub(crate) fn parse_hello(
    buf: &[u8; EH02_HELLO_LEN],
) -> Result<([u8; EH02_PUBKEY_LEN], [u8; EH02_NONCE_LEN]), CoreError> {
    if &buf[..4] != EH02_MAGIC || buf[4] != EH02_VERSION {
        return Err(CoreError::AuthFailed);
    }
    let mut eph_pub = [0u8; EH02_PUBKEY_LEN];
    eph_pub.copy_from_slice(&buf[5..5 + EH02_PUBKEY_LEN]);
    if !is_canonical_public_key(&eph_pub) {
        return Err(CoreError::AuthFailed);
    }
    let mut nonce = [0u8; EH02_NONCE_LEN];
    nonce.copy_from_slice(&buf[5 + EH02_PUBKEY_LEN..]);
    Ok((eph_pub, nonce))
}

pub(crate) fn challenge_bytes(
    eph_pub: &[u8; EH02_PUBKEY_LEN],
    nonce_r: &[u8; EH02_NONCE_LEN],
) -> [u8; EH02_CHALLENGE_LEN] {
    let mut out = [0u8; EH02_CHALLENGE_LEN];
    out[..EH02_PUBKEY_LEN].copy_from_slice(eph_pub);
    out[EH02_PUBKEY_LEN..].copy_from_slice(nonce_r);
    out
}

/// Parse message 2, with the same encoding rule as [`parse_hello`].
pub(crate) fn parse_challenge(
    buf: &[u8; EH02_CHALLENGE_LEN],
) -> Result<([u8; EH02_PUBKEY_LEN], [u8; EH02_NONCE_LEN]), CoreError> {
    let mut eph_pub = [0u8; EH02_PUBKEY_LEN];
    eph_pub.copy_from_slice(&buf[..EH02_PUBKEY_LEN]);
    if !is_canonical_public_key(&eph_pub) {
        return Err(CoreError::AuthFailed);
    }
    let mut nonce_r = [0u8; EH02_NONCE_LEN];
    nonce_r.copy_from_slice(&buf[EH02_PUBKEY_LEN..]);
    Ok((eph_pub, nonce_r))
}

/// Message 3: prove possession of the initiator's identity key to the responder's ephemeral.
pub(crate) fn initiator_proof(
    initiator_secret: &StaticSecret,
    transcript: &Transcript,
) -> Result<Vec<u8>, CoreError> {
    two_layer_seal(
        &EH02_DOMAINS,
        initiator_secret,
        &transcript.responder_eph,
        &transcript.bytes(ROLE_INITIATOR),
        &[],
    )
    .map_err(|_| CoreError::AuthFailed)
}

/// Verify message 3 and return the initiator's **authenticated** public key.
pub(crate) fn verify_initiator_proof(
    responder_eph_secret: &StaticSecret,
    transcript: &Transcript,
    proof: &[u8],
) -> Result<[u8; EH02_PUBKEY_LEN], CoreError> {
    open_proof(
        responder_eph_secret,
        &transcript.bytes(ROLE_INITIATOR),
        proof,
    )
}

/// Message 4: prove possession of the responder's identity key to the authenticated initiator.
pub(crate) fn responder_proof(
    responder_secret: &StaticSecret,
    initiator_pub: &[u8; EH02_PUBKEY_LEN],
    transcript: &Transcript,
) -> Result<Vec<u8>, CoreError> {
    two_layer_seal(
        &EH02_DOMAINS,
        responder_secret,
        initiator_pub,
        &transcript.bytes(ROLE_RESPONDER),
        &[],
    )
    .map_err(|_| CoreError::AuthFailed)
}

/// Verify message 4 and return the responder's **authenticated** public key.
pub(crate) fn verify_responder_proof(
    initiator_secret: &StaticSecret,
    transcript: &Transcript,
    proof: &[u8],
) -> Result<[u8; EH02_PUBKEY_LEN], CoreError> {
    open_proof(initiator_secret, &transcript.bytes(ROLE_RESPONDER), proof)
}

/// Session keys as seen by the initiator.
pub(crate) fn initiator_session_keys(
    initiator_secret: &StaticSecret,
    initiator_eph_secret: &StaticSecret,
    responder_pub: &[u8; EH02_PUBKEY_LEN],
    transcript: &Transcript,
) -> Result<SessionKeys, CoreError> {
    let responder_eph = PublicKey::from(transcript.responder_eph);
    let responder_static = PublicKey::from(*responder_pub);
    let master = session_master(
        initiator_eph_secret.diffie_hellman(&responder_eph),
        initiator_eph_secret.diffie_hellman(&responder_static),
        initiator_secret.diffie_hellman(&responder_eph),
        initiator_secret.diffie_hellman(&responder_static),
        transcript,
    )?;
    Ok(split(&master, true))
}

/// Session keys as seen by the responder. Same four Diffie-Hellmans, reached from the other
/// side, so both ends land on the same master secret.
pub(crate) fn responder_session_keys(
    responder_secret: &StaticSecret,
    responder_eph_secret: &StaticSecret,
    initiator_pub: &[u8; EH02_PUBKEY_LEN],
    transcript: &Transcript,
) -> Result<SessionKeys, CoreError> {
    let initiator_eph = PublicKey::from(transcript.initiator_eph);
    let initiator_static = PublicKey::from(*initiator_pub);
    let master = session_master(
        responder_eph_secret.diffie_hellman(&initiator_eph),
        responder_secret.diffie_hellman(&initiator_eph),
        responder_eph_secret.diffie_hellman(&initiator_static),
        responder_secret.diffie_hellman(&initiator_static),
        transcript,
    )?;
    Ok(split(&master, false))
}

/// `ee` is what makes the session forward secret: an attacker who later obtains **both**
/// identity keys still cannot recompute it, because the ephemeral secrets are gone. `es`,
/// `se` and `ss` tie the key to the two identities the proofs authenticated, so the key
/// cannot be shared with anyone who was not one of the two parties.
fn session_master(
    ee: x25519_dalek::SharedSecret,
    es: x25519_dalek::SharedSecret,
    se: x25519_dalek::SharedSecret,
    ss: x25519_dalek::SharedSecret,
    transcript: &Transcript,
) -> Result<Zeroizing<[u8; 32]>, CoreError> {
    let ee = contributory(ee, CoreError::AuthFailed)?;
    let es = contributory(es, CoreError::AuthFailed)?;
    let se = contributory(se, CoreError::AuthFailed)?;
    let ss = contributory(ss, CoreError::AuthFailed)?;
    Ok(derive_key(
        SESSION_DOMAIN,
        &[
            ee.as_bytes(),
            es.as_bytes(),
            se.as_bytes(),
            ss.as_bytes(),
            &transcript.session_bytes(),
        ],
    ))
}

fn split(master: &[u8; 32], is_initiator: bool) -> SessionKeys {
    let i2r = derive_key(I2R_DOMAIN, &[master]);
    let r2i = derive_key(R2I_DOMAIN, &[master]);
    if is_initiator {
        SessionKeys {
            send: i2r,
            recv: r2i,
        }
    } else {
        SessionKeys {
            send: r2i,
            recv: i2r,
        }
    }
}

/// Every way a proof can be bad is the same answer to the peer: [`CoreError::AuthFailed`].
/// The distinction the relay path draws between "not for me" and "forged" is useful to a
/// message recipient deciding what to display; here it would only tell an attacker which
/// half of the exchange to adjust.
///
/// That includes a non-canonical peer identity key, which [`two_layer_open`] rejects: the
/// key this returns becomes the peer's token, and the blocklist is only worth anything if
/// each key has exactly one of those (F-10).
fn open_proof(
    recipient_secret: &StaticSecret,
    aad: &[u8],
    proof: &[u8],
) -> Result<[u8; EH02_PUBKEY_LEN], CoreError> {
    if proof.len() != EH02_PROOF_LEN {
        return Err(CoreError::AuthFailed);
    }
    let (peer_pub, payload) = two_layer_open(&EH02_DOMAINS, recipient_secret, aad, proof)
        .map_err(|_| CoreError::AuthFailed)?;
    if !payload.is_empty() {
        return Err(CoreError::AuthFailed);
    }
    Ok(peer_pub)
}

/// Message 3 as an attacker who holds `claimed_pub` but not its secret would build it:
/// the identity layer says whatever she likes, the body is the best she can do with her own
/// key. Test-only, and shared with the transport tests so the F-1 regression is exercised
/// as the real attack rather than as a corrupted byte.
#[cfg(test)]
pub(crate) fn forged_initiator_proof(
    actual_secret: &StaticSecret,
    claimed_pub: &[u8; EH02_PUBKEY_LEN],
    transcript: &Transcript,
) -> Vec<u8> {
    crate::sealed::two_layer_seal_claiming(
        &EH02_DOMAINS,
        actual_secret,
        claimed_pub,
        &transcript.responder_eph,
        &transcript.bytes(ROLE_INITIATOR),
        &[],
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity::Identity;
    use crate::pubkey::test_vectors::{high_bit_alias, non_reduced_max, NON_REDUCED_ZERO};

    struct Session {
        initiator_eph: Ephemeral,
        responder_eph: Ephemeral,
        transcript: Transcript,
    }

    fn session() -> Session {
        let initiator_eph = Ephemeral::generate();
        let responder_eph = Ephemeral::generate();
        let transcript = Transcript {
            initiator_eph: initiator_eph.public,
            responder_eph: responder_eph.public,
            nonce_i: new_nonce(),
            nonce_r: new_nonce(),
        };
        Session {
            initiator_eph,
            responder_eph,
            transcript,
        }
    }

    /// Both sides of a full exchange, including the key agreement the transport runs on.
    #[test]
    fn mutual_roundtrip_and_agreed_session_keys() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let s = session();

        let p3 = initiator_proof(&alice.static_secret(), &s.transcript).unwrap();
        assert_eq!(p3.len(), EH02_PROOF_LEN);
        let seen_alice =
            verify_initiator_proof(&s.responder_eph.secret, &s.transcript, &p3).unwrap();
        assert_eq!(seen_alice, alice.public_key_bytes());

        let p4 = responder_proof(&bob.static_secret(), &seen_alice, &s.transcript).unwrap();
        let seen_bob = verify_responder_proof(&alice.static_secret(), &s.transcript, &p4).unwrap();
        assert_eq!(seen_bob, bob.public_key_bytes());

        let a = initiator_session_keys(
            &alice.static_secret(),
            &s.initiator_eph.secret,
            &seen_bob,
            &s.transcript,
        )
        .unwrap();
        let b = responder_session_keys(
            &bob.static_secret(),
            &s.responder_eph.secret,
            &seen_alice,
            &s.transcript,
        )
        .unwrap();

        assert_eq!(*a.send, *b.recv, "initiator→responder key must agree");
        assert_eq!(*a.recv, *b.send, "responder→initiator key must agree");
        assert_ne!(*a.send, *a.recv, "directions must not share a key");
    }

    /// Two connections between the same pair share no key material: the ephemerals differ,
    /// so recorded traffic cannot be decrypted with a key recovered from another session.
    #[test]
    fn session_keys_are_per_connection() {
        let alice = Identity::generate();
        let bob = Identity::generate();

        let keys = |s: &Session| {
            initiator_session_keys(
                &alice.static_secret(),
                &s.initiator_eph.secret,
                &bob.public_key_bytes(),
                &s.transcript,
            )
            .unwrap()
        };

        let first = session();
        let second = session();
        assert_ne!(*keys(&first).send, *keys(&second).send);

        // And the key commits to the transcript, not just to the ephemerals: flipping a
        // nonce an attacker could have tampered with yields a different key.
        let mut tampered = session();
        tampered.transcript.initiator_eph = first.transcript.initiator_eph;
        tampered.transcript.responder_eph = first.transcript.responder_eph;
        tampered.transcript.nonce_i = first.transcript.nonce_i;
        assert_ne!(*keys(&first).send, *keys(&tampered).send);
    }

    /// F-1 as a unit: Mallory has Alice's public key and nothing else. Under EH01 that was
    /// enough to be registered as Alice.
    #[test]
    fn public_key_alone_cannot_impersonate() {
        let alice = Identity::generate();
        let mallory = Identity::generate();
        let s = session();

        let forged = forged_initiator_proof(
            &mallory.static_secret(),
            &alice.public_key_bytes(),
            &s.transcript,
        );

        assert!(matches!(
            verify_initiator_proof(&s.responder_eph.secret, &s.transcript, &forged),
            Err(CoreError::AuthFailed)
        ));
    }

    /// F-10 on the P2P route, as a unit. Mallory holds her own secret and claims an alias of
    /// her own public key: `ss` is unchanged, so the proof is *valid*, and before this check
    /// the responder accepted it and named her by a token that was not on any blocklist.
    #[test]
    fn alias_of_the_peer_key_is_not_a_second_identity() {
        let mallory = Identity::generate();
        let s = session();

        for alias in [
            high_bit_alias(&mallory.public_key_bytes()),
            NON_REDUCED_ZERO,
            non_reduced_max(),
        ] {
            let proof = forged_initiator_proof(&mallory.static_secret(), &alias, &s.transcript);
            assert!(
                matches!(
                    verify_initiator_proof(&s.responder_eph.secret, &s.transcript, &proof),
                    Err(CoreError::AuthFailed)
                ),
                "{} must not authenticate as an identity",
                hex::encode(alias)
            );
        }

        // Control: the canonical spelling of the same key still authenticates.
        let honest = initiator_proof(&mallory.static_secret(), &s.transcript).unwrap();
        assert_eq!(
            verify_initiator_proof(&s.responder_eph.secret, &s.transcript, &honest).unwrap(),
            mallory.public_key_bytes()
        );
    }

    #[test]
    fn non_canonical_ephemerals_are_refused_on_the_wire() {
        let eph = Ephemeral::generate();
        let nonce = new_nonce();

        let mut hello = hello_bytes(&eph.public, &nonce);
        hello[5 + EH02_PUBKEY_LEN - 1] |= 0x80;
        assert!(matches!(parse_hello(&hello), Err(CoreError::AuthFailed)));

        let mut challenge = challenge_bytes(&eph.public, &nonce);
        challenge[EH02_PUBKEY_LEN - 1] |= 0x80;
        assert!(matches!(
            parse_challenge(&challenge),
            Err(CoreError::AuthFailed)
        ));
    }

    /// A proof is worth nothing outside the exact transcript it was made for.
    #[test]
    fn proof_is_bound_to_session_and_role() {
        let alice = Identity::generate();
        let s = session();
        let proof = initiator_proof(&alice.static_secret(), &s.transcript).unwrap();

        // Same session, wrong role: message 3 replayed as message 4.
        assert!(verify_responder_proof(&alice.static_secret(), &s.transcript, &proof).is_err());

        // Any change to the transcript, including the ephemeral an attacker would want to
        // substitute to break forward secrecy.
        let swapped = Ephemeral::generate().public;
        for tampered in [
            Transcript {
                nonce_i: new_nonce(),
                ..transcript_of(&s)
            },
            Transcript {
                nonce_r: new_nonce(),
                ..transcript_of(&s)
            },
            Transcript {
                initiator_eph: swapped,
                ..transcript_of(&s)
            },
        ] {
            assert!(matches!(
                verify_initiator_proof(&s.responder_eph.secret, &tampered, &proof),
                Err(CoreError::AuthFailed)
            ));
        }

        // Another responder's ephemeral cannot verify it either.
        let other = Ephemeral::generate();
        assert!(verify_initiator_proof(&other.secret, &s.transcript, &proof).is_err());
    }

    fn transcript_of(s: &Session) -> Transcript {
        Transcript {
            initiator_eph: s.transcript.initiator_eph,
            responder_eph: s.transcript.responder_eph,
            nonce_i: s.transcript.nonce_i,
            nonce_r: s.transcript.nonce_r,
        }
    }

    #[test]
    fn malformed_proofs_rejected() {
        let alice = Identity::generate();
        let s = session();
        let mut proof = initiator_proof(&alice.static_secret(), &s.transcript).unwrap();

        for bad in [&proof[..EH02_PROOF_LEN - 1], &[][..]] {
            assert!(matches!(
                verify_initiator_proof(&s.responder_eph.secret, &s.transcript, bad),
                Err(CoreError::AuthFailed)
            ));
        }

        let last = proof.len() - 1;
        proof[last] ^= 0xff;
        assert!(matches!(
            verify_initiator_proof(&s.responder_eph.secret, &s.transcript, &proof),
            Err(CoreError::AuthFailed)
        ));
    }

    #[test]
    fn hello_rejects_eh01_and_wrong_version() {
        let eph = Ephemeral::generate();
        let nonce = new_nonce();
        let good = hello_bytes(&eph.public, &nonce);
        assert_eq!(parse_hello(&good).unwrap(), (eph.public, nonce));

        let mut legacy = good;
        legacy[..4].copy_from_slice(b"EH01");
        assert!(matches!(parse_hello(&legacy), Err(CoreError::AuthFailed)));

        let mut future = good;
        future[4] = EH02_VERSION + 1;
        assert!(matches!(parse_hello(&future), Err(CoreError::AuthFailed)));
    }

    /// Neither pre-authentication message carries an identity — the F-5 property, at the
    /// level of the bytes that go on the wire.
    #[test]
    fn handshake_preamble_carries_no_identity() {
        let bob = Identity::generate();
        let s = session();
        let hello = hello_bytes(&s.transcript.initiator_eph, &s.transcript.nonce_i);
        let challenge = challenge_bytes(&s.transcript.responder_eph, &s.transcript.nonce_r);

        for haystack in [hello.as_slice(), challenge.as_slice()] {
            for needle in [
                bob.public_key_bytes().as_slice(),
                bob.token().as_str().as_bytes(),
            ] {
                assert!(!haystack.windows(needle.len()).any(|w| w == needle));
            }
        }

        let (eph_pub, nonce_r) = parse_challenge(&challenge).unwrap();
        assert_eq!(eph_pub, s.transcript.responder_eph);
        assert_eq!(nonce_r, s.transcript.nonce_r);
    }

    #[test]
    fn debug_redacts_ephemeral_secret() {
        let eph = Ephemeral::generate();
        let rendered = format!("{eph:?}");
        assert!(rendered.contains("<redacted>"));
        assert!(!rendered.contains(&hex::encode(eph.secret.to_bytes())));
    }
}
