//! Malformed-input properties for every decoder that meets remote bytes.
//!
//! The four security bugs closed in `0.8.x` were all found by reading, not by a test, and the
//! last one (F-10) got in precisely because nothing exercised *structured garbage*. The
//! example-based tests next to each module pin the attacks we already know about; this module
//! asserts the property that has to hold for the attacks we do not:
//!
//! > No byte string, however malformed, makes a decoder panic, overflow, allocate without
//! > bound, or take unbounded time. `Err` is always an acceptable answer.
//!
//! A panic here is not a cosmetic failure. In the client it is a remote crash reachable by
//! anyone who can drop a blob in a mailbox; in the relay — which shares [`crate::pop`] and the
//! canonical-key check — it takes the service down for every user at once.
//!
//! ## Why the generators are structure-aware
//!
//! Uniformly random bytes against a parser with a magic prefix exercise one branch: the first
//! `if`. Every strategy below therefore either starts from a **valid** artefact and damages
//! it, or builds a synthetic input that satisfies the surface checks — magic, version, length
//! class — and lies deeper down: a declared length that does not match the body, a canonical
//! ephemeral in front of a corrupt identity layer, a token field that is valid UTF-8 and not a
//! token. That is where the arithmetic lives, and arithmetic is what breaks.
//!
//! The value each strategy yields is the finished byte string, so a failing case prints as a
//! reproducer rather than as a recipe.
//!
//! ## Why proptest and not `cargo-fuzz`
//!
//! `cargo-fuzz` needs a nightly toolchain. A gate that cannot run in CI on stable runs
//! manually, which means it runs the day it is written and never again. These properties run
//! inside `cargo test` on the same toolchain as everything else, and shrink a failure to a
//! minimal input. Coverage guidance is what is given up; see `docs/how-to-test.md`.

use std::time::{Duration, Instant};

use proptest::prelude::*;
use proptest::strategy::ValueTree;
use proptest::test_runner::TestRunner;
use x25519_dalek::{PublicKey, StaticSecret};

use crate::crypto::{decrypt, Ciphertext};
use crate::error::CoreError;
use crate::frame::{
    decode_frame, encode_frame, FRAME_VERSION, MAGIC, MAX_CIPHERTEXT_LEN, MAX_TOKEN_LEN, MSG_ID_LEN,
};
use crate::handshake::{
    challenge_bytes, hello_bytes, initiator_proof, parse_challenge, parse_hello,
    verify_initiator_proof, Ephemeral, Transcript, EH02_CHALLENGE_LEN, EH02_HELLO_LEN, EH02_MAGIC,
    EH02_PROOF_LEN, EH02_PUBKEY_LEN, EH02_VERSION,
};
use crate::identity::Identity;
use crate::pop::pop_verify;
use crate::pubkey::is_canonical_public_key;
use crate::sealed::{
    open_sealed, seal_sender_at, two_layer_open, SEALED_DOMAINS, SEALED_MAGIC, SEALED_OVERHEAD,
};
use crate::token::Token;

/// Wall-clock ceiling for one decode of one input.
///
/// None of these parsers loops over anything but the bytes it was handed, so the real numbers
/// are microseconds. The budget sits far above that on purpose: it is not a benchmark, it is a
/// tripwire for a decoder that starts scaling with a *declared* length instead of a real one,
/// which is how a length field turns into a denial of service.
const DECODE_BUDGET: Duration = Duration::from_millis(500);

/// Cases per property, with `PROPTEST_CASES` left in charge when it is set.
///
/// The per-property numbers are sized for a pull request: the whole module runs in well under
/// a second, so it costs nothing to be a gate. A scheduled job re-runs the same generators
/// with `PROPTEST_CASES` in the tens of thousands, which is where a fuzzer's depth comes from
/// — and it does it without a second copy of the harness to keep in sync.
fn config(cases: u32) -> ProptestConfig {
    let default = ProptestConfig::default();
    if std::env::var_os("PROPTEST_CASES").is_some() {
        default
    } else {
        ProptestConfig { cases, ..default }
    }
}

fn timed<T>(what: &str, f: impl FnOnce() -> T) -> T {
    let start = Instant::now();
    let out = f();
    let elapsed = start.elapsed();
    assert!(
        elapsed < DECODE_BUDGET,
        "{what} spent {elapsed:?} on one input"
    );
    out
}

/// Fixed identities and ephemerals: everything a case depends on that is not generated has to
/// be the same on the next run, or a shrunk failure does not reproduce. X25519 clamps the
/// secret, so any 32 bytes are a usable key.
fn alice() -> Identity {
    Identity::from_secret_bytes([0x11; 32])
}

fn bob() -> Identity {
    Identity::from_secret_bytes([0x22; 32])
}

fn fixed_ephemeral(seed: u8) -> Ephemeral {
    let secret = StaticSecret::from([seed; 32]);
    let public = PublicKey::from(&secret).to_bytes();
    Ephemeral { secret, public }
}

/// Strings with the shapes that break fixed-offset slicing: ASCII most of the time, multi-byte
/// code points often enough to matter.
fn arbitrary_string(max: usize) -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop_oneof![
            3 => prop::char::range('\u{20}', '\u{7e}'),
            1 => any::<char>(),
        ],
        0..max,
    )
    .prop_map(|chars| chars.into_iter().collect())
}

/// Damage applied to a valid artefact. Starting from something that decodes and breaking it is
/// what reaches the code past the first `if`; the variants are the shapes the manual audits
/// actually used — a flipped byte, a truncation, a splice between two regions.
#[derive(Debug, Clone)]
enum Mutation {
    SetByte { at: usize, value: u8 },
    Xor { at: usize, mask: u8 },
    Truncate { keep: usize },
    Append { bytes: Vec<u8> },
    Splice { from: usize, to: usize, len: usize },
}

fn mutation() -> impl Strategy<Value = Mutation> {
    prop_oneof![
        3 => (any::<usize>(), any::<u8>()).prop_map(|(at, value)| Mutation::SetByte { at, value }),
        3 => (any::<usize>(), 1u8..=255).prop_map(|(at, mask)| Mutation::Xor { at, mask }),
        2 => any::<usize>().prop_map(|keep| Mutation::Truncate { keep }),
        1 => prop::collection::vec(any::<u8>(), 0..64).prop_map(|bytes| Mutation::Append { bytes }),
        1 => (any::<usize>(), any::<usize>(), 1usize..64)
            .prop_map(|(from, to, len)| Mutation::Splice { from, to, len }),
    ]
}

fn mutations() -> impl Strategy<Value = Vec<Mutation>> {
    prop::collection::vec(mutation(), 0..6)
}

/// Positions are taken modulo the current length, so the generator keeps landing on header
/// fields instead of scattering over the tail of a long blob.
fn mutate(base: &[u8], muts: &[Mutation]) -> Vec<u8> {
    let mut out = base.to_vec();
    for m in muts {
        if out.is_empty() {
            break;
        }
        match m {
            Mutation::SetByte { at, value } => {
                let i = at % out.len();
                out[i] = *value;
            }
            Mutation::Xor { at, mask } => {
                let i = at % out.len();
                out[i] ^= *mask;
            }
            Mutation::Truncate { keep } => out.truncate(keep % (out.len() + 1)),
            Mutation::Append { bytes } => out.extend_from_slice(bytes),
            Mutation::Splice { from, to, len } => {
                let len = (*len).min(out.len());
                let from = from % (out.len() - len + 1);
                let to = to % (out.len() - len + 1);
                let window = out[from..from + len].to_vec();
                out[to..to + len].copy_from_slice(&window);
            }
        }
    }
    out
}

// ---------------------------------------------------------------------------------------
// Sealed sender (`ECS1`): what a stranger reaches through the blind relay, with no key and no
// handshake — only the recipient's token.
// ---------------------------------------------------------------------------------------

fn sealed_blob() -> impl Strategy<Value = Vec<u8>> {
    let valid = seal_sender_at(&alice(), &bob().public_identity(), b"hola", 1_800_000_000)
        .expect("seal for the corpus")
        .blob;
    let eph = fixed_ephemeral(0x33).public;

    prop_oneof![
        // A real blob, damaged. Damage in the body still opens the identity layer, so these
        // are the cases that reach the second AEAD.
        4 => (Just(valid), mutations()).prop_map(|(base, muts)| mutate(&base, &muts)),
        // Right magic, canonical ephemeral, noise after it: the header passes and the identity
        // layer is what has to refuse.
        3 => (Just(eph), prop::collection::vec(any::<u8>(), 0..256)).prop_map(|(eph, tail)| {
            let mut blob = Vec::from(*SEALED_MAGIC);
            blob.extend_from_slice(&eph);
            blob.extend_from_slice(&tail);
            blob
        }),
        // Right magic, every length around the overhead boundary.
        2 => prop_oneof![
            Just(0usize),
            Just(SEALED_OVERHEAD - 1),
            Just(SEALED_OVERHEAD),
            Just(SEALED_OVERHEAD + 1),
            0usize..512,
        ]
        .prop_flat_map(|len| prop::collection::vec(any::<u8>(), len..=len))
        .prop_map(|tail| {
            let mut blob = Vec::from(*SEALED_MAGIC);
            blob.extend_from_slice(&tail);
            blob
        }),
        // Not an `ECS1` blob at all.
        1 => prop::collection::vec(any::<u8>(), 0..256),
    ]
}

proptest! {
    #![proptest_config(config(1024))]

    #[test]
    fn open_sealed_survives_any_blob(blob in sealed_blob()) {
        let bob = bob();
        for clock in [None, Some(1_800_000_000u64)] {
            match timed("open_sealed", || open_sealed(&bob, &blob, clock)) {
                Ok(opened) => {
                    // Output bounded by input: a decoder that can be made to return more than
                    // it was given is an amplifier even when it does not crash.
                    prop_assert_eq!(opened.plaintext.len() + SEALED_OVERHEAD, blob.len());
                    // Whatever came back has to be a name we would accept at import (F-10).
                    prop_assert!(is_canonical_public_key(&opened.sender.public_key_bytes()));
                    prop_assert!(Token::parse(opened.sender.token().as_str()).is_ok());
                }
                Err(e) => prop_assert!(matches!(
                    e,
                    CoreError::InvalidFrame
                        | CoreError::CiphertextTooShort
                        | CoreError::DecryptionFailed
                        | CoreError::InvalidPublicKey
                        | CoreError::AuthFailed
                        | CoreError::Expired
                )),
            }
        }
    }

    /// The primitive under both `ECS1` and `EH02`, driven directly so the associated data is
    /// attacker-shaped too — a caller binds a blob to a context, and the context is bytes.
    #[test]
    fn two_layer_open_survives_any_blob(
        blob in prop::collection::vec(any::<u8>(), 0..256),
        aad in prop::collection::vec(any::<u8>(), 0..64),
    ) {
        let secret = bob().static_secret();
        let out = timed("two_layer_open", || {
            two_layer_open(&SEALED_DOMAINS, &secret, &aad, &blob)
        });
        if let Ok((sender, payload)) = out {
            prop_assert!(is_canonical_public_key(&sender));
            prop_assert!(payload.len() <= blob.len());
        }
    }
}

// ---------------------------------------------------------------------------------------
// EH02: the pre-authentication surface. Anyone who can open a TCP connection reaches it, and
// the responder parses all of it before it knows who is talking.
// ---------------------------------------------------------------------------------------

/// The transcript both sides of the corpus agree on. Fixed so a damaged proof is a damaged
/// version of something that would otherwise verify, rather than noise against noise.
fn fixed_transcript() -> Transcript {
    Transcript {
        initiator_eph: fixed_ephemeral(0x44).public,
        responder_eph: fixed_ephemeral(0x55).public,
        nonce_i: [0x66; 32],
        nonce_r: [0x77; 32],
    }
}

fn hello_buf() -> impl Strategy<Value = [u8; EH02_HELLO_LEN]> {
    (
        prop::array::uniform4(any::<u8>()),
        any::<u8>(),
        prop::array::uniform32(any::<u8>()),
        prop::array::uniform32(any::<u8>()),
        prop::bool::weighted(0.8),
        prop::bool::weighted(0.8),
        prop::bool::weighted(0.3),
    )
        .prop_map(
            |(magic, version, key, nonce, real_magic, real_version, real_key)| {
                let mut buf = [0u8; EH02_HELLO_LEN];
                buf[..4].copy_from_slice(if real_magic { EH02_MAGIC } else { &magic });
                buf[4] = if real_version { EH02_VERSION } else { version };
                let key = if real_key {
                    fixed_ephemeral(0x88).public
                } else {
                    key
                };
                buf[5..5 + EH02_PUBKEY_LEN].copy_from_slice(&key);
                buf[5 + EH02_PUBKEY_LEN..].copy_from_slice(&nonce);
                buf
            },
        )
}

/// Proofs an unauthenticated peer can put on the wire: a real one with damage, and synthetic
/// buffers at and around the only length the reader accepts.
fn proof_bytes() -> impl Strategy<Value = Vec<u8>> {
    let real = initiator_proof(&alice().static_secret(), &fixed_transcript())
        .expect("proof for the corpus");

    prop_oneof![
        3 => (Just(real), mutations()).prop_map(|(base, muts)| mutate(&base, &muts)),
        2 => prop::collection::vec(any::<u8>(), EH02_PROOF_LEN..=EH02_PROOF_LEN),
        1 => prop::collection::vec(any::<u8>(), 0..EH02_PROOF_LEN + 64),
    ]
}

proptest! {
    #![proptest_config(config(512))]

    #[test]
    fn parse_hello_survives_any_buffer(buf in hello_buf()) {
        match timed("parse_hello", || parse_hello(&buf)) {
            Ok((eph, nonce)) => {
                prop_assert!(is_canonical_public_key(&eph));
                prop_assert_eq!(&buf[..4], EH02_MAGIC);
                prop_assert_eq!(buf[4], EH02_VERSION);
                // An accepted hello re-encodes to the bytes it came from, so the two ends
                // cannot end up with different transcripts for the same exchange.
                prop_assert_eq!(hello_bytes(&eph, &nonce), buf);
            }
            Err(e) => prop_assert!(matches!(e, CoreError::AuthFailed)),
        }
    }

    #[test]
    fn parse_challenge_survives_any_buffer(
        key in prop::array::uniform32(any::<u8>()),
        nonce in prop::array::uniform32(any::<u8>()),
        real_key in prop::bool::weighted(0.4),
    ) {
        let mut raw = [0u8; EH02_CHALLENGE_LEN];
        let key = if real_key { fixed_ephemeral(0x99).public } else { key };
        raw[..EH02_PUBKEY_LEN].copy_from_slice(&key);
        raw[EH02_PUBKEY_LEN..].copy_from_slice(&nonce);

        match timed("parse_challenge", || parse_challenge(&raw)) {
            Ok((eph, got_nonce)) => {
                prop_assert!(is_canonical_public_key(&eph));
                prop_assert_eq!(challenge_bytes(&eph, &got_nonce), raw);
            }
            Err(e) => prop_assert!(matches!(e, CoreError::AuthFailed)),
        }
    }

    /// Message 3 verification: the responder runs this over bytes from a peer that has proved
    /// nothing whatsoever, which makes it the most exposed function in the crate.
    #[test]
    fn verify_initiator_proof_survives_any_bytes(
        proof in proof_bytes(),
        nonce_i in prop::array::uniform32(any::<u8>()),
        substitute_nonce in prop::bool::weighted(0.3),
    ) {
        let responder = fixed_ephemeral(0x55);
        let mut transcript = fixed_transcript();
        // Most cases keep the transcript the corpus was built for, so a damaged proof still
        // opens the identity layer and the *second* AEAD is what refuses it. The rest are an
        // active attacker rewriting the transcript under a captured proof.
        if substitute_nonce {
            transcript.nonce_i = nonce_i;
        }

        match timed("verify_initiator_proof", || {
            verify_initiator_proof(&responder.secret, &transcript, &proof)
        }) {
            Ok(key) => {
                prop_assert!(is_canonical_public_key(&key));
                prop_assert_eq!(proof.len(), EH02_PROOF_LEN);
                prop_assert!(!substitute_nonce);
            }
            Err(e) => prop_assert!(matches!(e, CoreError::AuthFailed)),
        }
    }
}

// ---------------------------------------------------------------------------------------
// `EC04` frames. Decoded inside an authenticated session, but "authenticated" only means the
// peer proved possession of a key: an accepted peer can still send anything at all.
// ---------------------------------------------------------------------------------------

/// A length the sender declares, beside a body that may have nothing to do with it. This
/// pairing is the point of the whole generator: `token_len` and `ct_len` are the two places
/// where a remote number decides how many bytes the decoder is asked to read.
fn declared_len() -> impl Strategy<Value = u32> {
    prop_oneof![
        1 => Just(0u32),
        1 => Just(u32::MAX),
        1 => Just(MAX_CIPHERTEXT_LEN as u32),
        1 => Just(MAX_CIPHERTEXT_LEN as u32 + 1),
        1 => Just(MAX_TOKEN_LEN as u32),
        1 => Just(MAX_TOKEN_LEN as u32 + 1),
        3 => 0u32..96,
        2 => any::<u32>(),
    ]
}

/// Token bytes: real, real-with-damage, non-UTF-8, and past the ceiling.
fn token_field() -> impl Strategy<Value = Vec<u8>> {
    let real = alice().token().as_str().as_bytes().to_vec();
    prop_oneof![
        3 => Just(real.clone()),
        3 => (Just(real), mutations()).prop_map(|(base, muts)| mutate(&base, &muts)),
        2 => prop::collection::vec(any::<u8>(), 0..80),
        1 => prop::collection::vec(any::<u8>(), MAX_TOKEN_LEN..MAX_TOKEN_LEN + 8),
    ]
}

fn frame_bytes() -> impl Strategy<Value = Vec<u8>> {
    (
        prop::bool::weighted(0.85),
        any::<u8>(),
        prop::array::uniform16(any::<u8>()),
        declared_len(),
        token_field(),
        declared_len(),
        prop::collection::vec(any::<u8>(), 0..96),
        prop::bool::weighted(0.5),
    )
        .prop_map(
            |(real_magic, version, msg_id, token_len, token, ct_len, ct, honest_lens)| {
                let mut out = Vec::with_capacity(32 + token.len() + ct.len());
                out.extend_from_slice(if real_magic { MAGIC } else { b"EC03" });
                out.push(if version % 4 == 0 {
                    version
                } else {
                    FRAME_VERSION
                });
                out.extend_from_slice(&msg_id);
                // Half the cases declare the truth and lie about the content; half declare a
                // length with nothing to do with the body that follows it.
                let token_len = if honest_lens {
                    token.len().min(u16::MAX as usize) as u16
                } else {
                    token_len as u16
                };
                out.extend_from_slice(&token_len.to_be_bytes());
                out.extend_from_slice(&token);
                let ct_len = if honest_lens { ct.len() as u32 } else { ct_len };
                out.extend_from_slice(&ct_len.to_be_bytes());
                out.extend_from_slice(&ct);
                out
            },
        )
}

proptest! {
    #![proptest_config(config(2048))]

    #[test]
    fn decode_frame_survives_any_bytes(bytes in frame_bytes()) {
        match timed("decode_frame", || decode_frame(&bytes)) {
            Ok(frame) => {
                // Exactly one byte string decodes to a given frame. Without this a peer could
                // choose between several encodings of one message — the same shape of bug as
                // the alias public keys of F-10, one layer up.
                prop_assert_eq!(encode_frame(&frame).expect("re-encode"), bytes);
                prop_assert!(frame.ciphertext.len() <= MAX_CIPHERTEXT_LEN);
                prop_assert!(Token::parse(&frame.sender_token).is_ok());
                prop_assert_eq!(frame.msg_id.len(), MSG_ID_LEN);
            }
            Err(e) => prop_assert!(matches!(
                e,
                CoreError::InvalidFrame | CoreError::InvalidToken
            )),
        }
    }

    /// `Token::parse` decides whether a byte string names a peer, and it slices at a fixed
    /// offset. Non-ASCII input is the classic way to turn that into a panic.
    #[test]
    fn token_parse_survives_any_string(raw in arbitrary_string(80)) {
        if let Ok(token) = timed("Token::parse", || Token::parse(&raw)) {
            let s = token.as_str();
            prop_assert!(s.starts_with(Token::PREFIX));
            prop_assert_eq!(s.len(), Token::PREFIX.len() + 64);
            prop_assert_eq!(s, s.to_ascii_lowercase());
            // Normalisation is idempotent, or a token could name a peer under two spellings.
            let reparsed = Token::parse(s).expect("reparse");
            prop_assert_eq!(reparsed.as_str(), s);
        }
    }

    /// The pre-`0.8.0` payload format, which still arrives inside `EC04` frames.
    #[test]
    fn decrypt_survives_any_ciphertext(bytes in prop::collection::vec(any::<u8>(), 0..160)) {
        let bob = bob();
        if let Ok(ct) = Ciphertext::from_bytes(bytes.clone()) {
            if let Ok(plaintext) = timed("decrypt", || decrypt(&bob, &ct)) {
                prop_assert!(plaintext.len() < bytes.len());
            }
        }
    }
}

/// The harness needs a harness. A generator that bounces off the magic byte proves nothing,
/// and it degrades *silently*: the properties above keep passing while covering the first `if`
/// and none of the arithmetic below it. This samples each corpus and asserts that a real
/// fraction of it reaches the code those properties are about.
///
/// The thresholds are an order of magnitude below what the generators produce today. They are
/// there to catch a corpus that has collapsed, not to pin a distribution.
#[test]
fn generators_reach_past_the_surface_checks() {
    const SAMPLE: usize = 512;
    let mut runner = TestRunner::deterministic();

    let bob = bob();
    let blobs = sealed_blob();
    let (mut past_header, mut past_identity_layer) = (0usize, 0usize);
    for _ in 0..SAMPLE {
        let blob = blobs.new_tree(&mut runner).expect("blob").current();
        match open_sealed(&bob, &blob, None) {
            Err(CoreError::InvalidFrame | CoreError::CiphertextTooShort) => {}
            // Header accepted; the sender layer is what refused it.
            Err(CoreError::DecryptionFailed) => past_header += 1,
            // The sender layer opened: the key and the body AEAD were reached.
            _ => {
                past_header += 1;
                past_identity_layer += 1;
            }
        }
    }
    // Measured on the corpus as written: 269 and 49 of 512.
    assert!(
        past_header >= SAMPLE / 8,
        "only {past_header}/{SAMPLE} sealed blobs got past the magic and length checks"
    );
    assert!(
        past_identity_layer >= SAMPLE / 64,
        "only {past_identity_layer}/{SAMPLE} sealed blobs reached the body AEAD"
    );

    let frames = frame_bytes();
    let (mut decoded, mut bad_token) = (0usize, 0usize);
    for _ in 0..SAMPLE {
        let bytes = frames.new_tree(&mut runner).expect("frame").current();
        match decode_frame(&bytes) {
            Ok(_) => decoded += 1,
            // Lengths parsed and agreed with the body; the token field is what failed.
            Err(CoreError::InvalidToken) => bad_token += 1,
            Err(_) => {}
        }
    }
    // Measured on the corpus as written: 68 and 54 of 512.
    assert!(
        decoded >= SAMPLE / 32,
        "only {decoded}/{SAMPLE} generated frames were well-formed"
    );
    assert!(
        bad_token >= SAMPLE / 32,
        "only {bad_token}/{SAMPLE} generated frames reached the token check"
    );
}

// ---------------------------------------------------------------------------------------
// Proof of possession: the relay runs this over an unauthenticated request body, so a panic
// here is a remote kill switch for the whole service.
// ---------------------------------------------------------------------------------------

fn token_string() -> impl Strategy<Value = String> {
    let real = alice().token().as_str().to_string();
    prop_oneof![
        3 => Just(real.clone()),
        2 => Just(real.to_uppercase()),
        2 => (Just(real), mutations()).prop_map(|(base, muts)| {
            String::from_utf8_lossy(&mutate(base.as_bytes(), &muts)).into_owned()
        }),
        2 => arbitrary_string(80),
    ]
}

proptest! {
    #![proptest_config(config(512))]

    #[test]
    fn pop_verify_survives_any_request(
        eph_secret in prop::array::uniform32(any::<u8>()),
        client_pub in prop::array::uniform32(any::<u8>()),
        nonce in prop::collection::vec(any::<u8>(), 0..96),
        dest_token in token_string(),
        proof in prop::array::uniform32(any::<u8>()),
        real_key in prop::bool::weighted(0.4),
    ) {
        let client_pub = if real_key { alice().public_key_bytes() } else { client_pub };

        match timed("pop_verify", || {
            pop_verify(&eph_secret, &client_pub, &nonce, &dest_token, &proof)
        }) {
            Ok(true) => {
                // A `true` is the relay handing over a mailbox: the key must be canonical and
                // must be the one the destination token names.
                prop_assert!(is_canonical_public_key(&client_pub));
                let named = Token::from_public_key_bytes(&client_pub).expect("canonical");
                let asked = Token::parse(&dest_token).expect("parsed");
                prop_assert_eq!(named.as_str(), asked.as_str());
            }
            Ok(false) => {}
            Err(e) => prop_assert!(matches!(
                e,
                CoreError::InvalidToken | CoreError::InvalidPublicKey | CoreError::AuthFailed
            )),
        }
    }
}
