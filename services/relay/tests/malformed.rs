//! Malformed-request properties for the relay's HTTP surface.
//!
//! Every byte the relay parses before it knows anything about the caller is reachable by
//! anyone on the internet: `/v1/enqueue` and `/v1/pull` take a JSON body and base64 blobs from
//! strangers by design, because a blind mailbox has no credential to ask for first. A panic in
//! any of that is not one user's crash, it is the mailbox of every user going away at once,
//! for the price of one request.
//!
//! The properties asserted per request are:
//!
//! 1. it answers — no panic, no hang;
//! 2. with a status that is a deliberate refusal, never a `500`: an internal error on input a
//!    stranger chose means the input reached somewhere it should not have;
//! 3. and with a body that does not grow with the request.
//!
//! Requests go through the real [`router`] with [`tower::ServiceExt::oneshot`] rather than a
//! socket. Same handlers, same extractors, same body limit, no port and no accept loop — which
//! is what makes it cheap enough to run hundreds of cases as a pull-request gate.

use std::net::SocketAddr;
use std::sync::Arc;

use axum::body::Body;
use axum::extract::ConnectInfo;
use axum::http::{Request, StatusCode};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use encrypchat_core::{pop_proof, Identity};
use encrypchat_relay::{router, AppState, RelayConfig, Store};
use proptest::prelude::*;
use serde_json::json;
use tower::ServiceExt;

/// Rate limits are lifted for these tests on purpose. With the defaults the third case would
/// get a `429` and every case after it would too, so the generators would be testing the
/// limiter instead of the parsers.
fn relay() -> (AppState, tempfile::TempDir) {
    let dir = tempfile::tempdir().expect("tempdir");
    let store = Arc::new(Store::open(&dir.path().join("relay.sqlite")).expect("store"));
    let state = AppState::with_config(
        store,
        RelayConfig {
            enqueue_per_min: u32::MAX,
            challenge_per_min: u32::MAX,
            ..RelayConfig::default()
        },
    );
    (state, dir)
}

struct Answer {
    status: StatusCode,
    body: Vec<u8>,
}

/// One request against the real router. Returns the status and body; a handler that panicked
/// unwinds through here and fails the case with the input that caused it.
fn post(state: &AppState, path: &str, body: Vec<u8>, content_type: &str) -> Answer {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("runtime");
    rt.block_on(async {
        let mut request = Request::builder()
            .method("POST")
            .uri(path)
            .header("content-type", content_type)
            .body(Body::from(body))
            .expect("request");
        request
            .extensions_mut()
            .insert(ConnectInfo(SocketAddr::from(([203, 0, 113, 7], 9000))));
        let response = router(state.clone())
            .oneshot(request)
            .await
            .expect("router answers");
        let status = response.status();
        let body = axum::body::to_bytes(response.into_body(), 1024 * 1024)
            .await
            .expect("body")
            .to_vec();
        Answer { status, body }
    })
}

/// Statuses the relay is allowed to answer a hostile body with. `500` is absent deliberately:
/// it would mean the input reached the store or the crypto instead of being turned away at the
/// edge. `507` is present because the relay running out of disk is a real answer, not a fault —
/// a *mailbox* that fills up is no longer answered at all since B-3, it is dropped under a `200`.
const EXPECTED: &[StatusCode] = &[
    StatusCode::OK,
    StatusCode::BAD_REQUEST,
    StatusCode::UNAUTHORIZED,
    StatusCode::PAYLOAD_TOO_LARGE,
    StatusCode::UNSUPPORTED_MEDIA_TYPE,
    StatusCode::UNPROCESSABLE_ENTITY,
    StatusCode::TOO_MANY_REQUESTS,
    StatusCode::INSUFFICIENT_STORAGE,
];

fn assert_deliberate_refusal(answer: &Answer, request_len: usize) {
    assert!(
        EXPECTED.contains(&answer.status),
        "unexpected status {}: {}",
        answer.status,
        String::from_utf8_lossy(&answer.body)
    );
    // No amplification: the error body is a fixed shape, not an echo of the request.
    assert!(
        answer.body.len() <= request_len + 4096,
        "a {request_len}-byte request produced a {}-byte answer",
        answer.body.len()
    );
}

fn real_token() -> String {
    Identity::from_secret_bytes([0x11; 32])
        .token()
        .as_str()
        .to_string()
}

/// Token strings shaped like the ones the relay actually receives.
fn token_field() -> impl Strategy<Value = serde_json::Value> {
    let real = real_token();
    prop_oneof![
        3 => Just(json!(real.clone())),
        1 => Just(json!(real.to_uppercase())),
        1 => Just(json!(format!("  {real}  "))),
        // One hex digit short, one too many, and the prefix alone: the boundaries of the
        // fixed-offset slice inside `Token::parse`.
        1 => Just(json!(real[..real.len() - 1].to_string())),
        1 => Just(json!(format!("{real}f"))),
        1 => Just(json!("ec_")),
        1 => Just(json!("ec_ñ")),
        2 => "[a-zA-Z0-9_ ]{0,80}".prop_map(|s| json!(s)),
        1 => json_scalar(),
    ]
}

/// Base64 fields, in the shapes that separate "not base64" from "base64 of the wrong thing".
fn b64_field() -> impl Strategy<Value = serde_json::Value> {
    prop_oneof![
        // Valid base64 of a plausible length, including the 32 bytes a key must be.
        3 => prop::collection::vec(any::<u8>(), 0..96)
            .prop_map(|bytes| json!(B64.encode(bytes))),
        2 => prop::collection::vec(any::<u8>(), 32..=32)
            .prop_map(|bytes| json!(B64.encode(bytes))),
        // Valid base64 with the whitespace a client might wrap it in.
        1 => prop::collection::vec(any::<u8>(), 0..96)
            .prop_map(|bytes| json!(format!("\n  {}  \n", B64.encode(bytes)))),
        // Not base64: wrong alphabet, broken padding, empty.
        2 => "[A-Za-z0-9+/=!@#$ ]{0,120}".prop_map(|s| json!(s)),
        1 => Just(json!("")),
        // Long enough that believing the declared size would matter.
        1 => Just(json!("A".repeat(64 * 1024))),
        1 => json_scalar(),
    ]
}

/// Values that are legal JSON and the wrong type for the field they land in.
fn json_scalar() -> impl Strategy<Value = serde_json::Value> {
    prop_oneof![
        Just(json!(null)),
        Just(json!(true)),
        Just(json!(0)),
        Just(json!(-1)),
        Just(json!(u64::MAX)),
        Just(json!(1e308)),
        Just(json!([])),
        Just(json!({ "nested": "object" })),
    ]
}

fn ttl_field() -> impl Strategy<Value = serde_json::Value> {
    prop_oneof![
        2 => Just(json!(3600)),
        1 => Just(json!(0)),
        1 => Just(json!(u64::MAX)),
        1 => Just(json!(-1)),
        1 => Just(json!(null)),
        1 => Just(json!("3600")),
        2 => any::<u64>().prop_map(|n| json!(n)),
    ]
}

/// Bodies that are mostly the right object with the wrong contents, plus a minority that are
/// not the right object at all. Keeping the majority well-shaped is the point: a body that
/// fails at `serde_json` never reaches a handler.
fn enqueue_body() -> impl Strategy<Value = Vec<u8>> {
    prop_oneof![
        6 => (token_field(), ttl_field(), b64_field(), any::<bool>()).prop_map(
            |(dest, ttl, blob, extra)| {
                let mut body = json!({ "dest_token": dest, "ttl_secs": ttl, "blob_b64": blob });
                if extra {
                    body["unknown_field"] = json!("ignored, or it should be");
                }
                serde_json::to_vec(&body).expect("json")
            }
        ),
        1 => (token_field(), b64_field()).prop_map(|(dest, blob)| {
            serde_json::to_vec(&json!({ "dest_token": dest, "blob_b64": blob })).expect("json")
        }),
        1 => raw_body(),
    ]
    .boxed()
}

fn pull_body() -> impl Strategy<Value = Vec<u8>> {
    prop_oneof![
        6 => (
            "[a-z0-9-]{0,60}",
            token_field(),
            b64_field(),
            b64_field(),
        )
            .prop_map(|(challenge_id, dest, pubkey, proof)| {
                serde_json::to_vec(&json!({
                    "challenge_id": challenge_id,
                    "dest_token": dest,
                    "pubkey_b64": pubkey,
                    "proof_b64": proof,
                }))
                .expect("json")
            }),
        1 => raw_body(),
    ]
    .boxed()
}

/// Bodies that are not the expected object: truncated JSON, arrays, deep nesting (which is
/// where a recursive descent parser goes to die), and plain noise.
fn raw_body() -> impl Strategy<Value = Vec<u8>> {
    prop_oneof![
        Just(Vec::new()),
        Just(b"{".to_vec()),
        Just(b"[]".to_vec()),
        Just(b"null".to_vec()),
        Just(br#"{"dest_token":"#.to_vec()),
        Just(format!("{}{}", "[".repeat(4096), "]".repeat(4096)).into_bytes()),
        Just(b"\xff\xfe\x00\x01".to_vec()),
        prop::collection::vec(any::<u8>(), 0..256),
    ]
}

/// One store for a whole property rather than one per case: opening SQLite is what would make
/// this expensive, and the handlers do not care that other cases have been through them.
fn config() -> ProptestConfig {
    let default = ProptestConfig::default();
    if std::env::var_os("PROPTEST_CASES").is_some() {
        default
    } else {
        ProptestConfig {
            cases: 256,
            ..default
        }
    }
}

#[test]
fn enqueue_survives_any_body() {
    let (state, _dir) = relay();
    proptest!(config(), |(body in enqueue_body())| {
        let len = body.len();
        let answer = post(&state, "/v1/enqueue", body, "application/json");
        assert_deliberate_refusal(&answer, len);
    });
}

#[test]
fn pull_survives_any_body() {
    let (state, _dir) = relay();
    proptest!(config(), |(body in pull_body())| {
        let len = body.len();
        let answer = post(&state, "/v1/pull", body, "application/json");
        assert_deliberate_refusal(&answer, len);
    });
}

/// What to put in `proof_b64`, described rather than built: the genuine proof depends on the
/// challenge, and the challenge only exists once the case is running.
#[derive(Debug, Clone)]
enum ProofShape {
    Genuine,
    /// A real proof with one bit turned over — the closest a wrong answer can be to a right one.
    FlippedBit(u8),
    /// A real proof missing its last bytes: right prefix, wrong length.
    Truncated,
    Bytes(Vec<u8>),
    NotBase64(String),
}

fn proof_shape() -> impl Strategy<Value = ProofShape> {
    prop_oneof![
        2 => Just(ProofShape::Genuine),
        2 => any::<u8>().prop_map(ProofShape::FlippedBit),
        1 => Just(ProofShape::Truncated),
        3 => prop::collection::vec(any::<u8>(), 32..=32).prop_map(ProofShape::Bytes),
        2 => prop::collection::vec(any::<u8>(), 0..96).prop_map(ProofShape::Bytes),
        1 => "[A-Za-z0-9+/= ]{0,80}".prop_map(ProofShape::NotBase64),
    ]
}

fn render_proof(shape: &ProofShape, genuine: &[u8]) -> serde_json::Value {
    match shape {
        ProofShape::Genuine => json!(B64.encode(genuine)),
        ProofShape::FlippedBit(bit) => {
            let mut bytes = genuine.to_vec();
            let bit = *bit as usize % (bytes.len() * 8);
            bytes[bit / 8] ^= 1 << (bit % 8);
            json!(B64.encode(bytes))
        }
        ProofShape::Truncated => json!(B64.encode(&genuine[..genuine.len() - 1])),
        ProofShape::Bytes(bytes) => json!(B64.encode(bytes)),
        ProofShape::NotBase64(s) => json!(s),
    }
}

/// The generated bodies above almost never get past `pubkey_matches_token`: a random key does
/// not hash to a random token, so the request is turned away two checks before the proof is
/// looked at. This property carries a real token, its real key and a freshly issued challenge,
/// so the only thing that varies is the field a caller controls at the point where the relay is
/// about to open somebody's mailbox — the deepest a stranger can push this endpoint.
#[test]
fn pull_with_a_real_challenge_survives_any_proof() {
    let (state, _dir) = relay();
    let bob = Identity::from_secret_bytes([0x11; 32]);
    let dest = real_token();

    proptest!(config(), |(shape in proof_shape())| {
        // One challenge per case: a successful pull consumes it, and reusing it would send
        // every later case down the "no valid challenge" branch instead of into the proof.
        let issued = state.store.create_challenge().expect("challenge");
        let genuine = pop_proof(
            &bob.to_secret_bytes(),
            &issued.eph.public,
            &issued.nonce,
            &dest,
        )
        .expect("proof");
        let body = serde_json::to_vec(&json!({
            "challenge_id": issued.id,
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": render_proof(&shape, &genuine),
        }))
        .expect("json");
        let len = body.len();
        let answer = post(&state, "/v1/pull", body, "application/json");
        assert_deliberate_refusal(&answer, len);
        // Only the real proof opens the mailbox. A `200` for anything else would mean the
        // property above had been passing while the relay handed mail to strangers.
        if answer.status == StatusCode::OK {
            prop_assert!(
                matches!(shape, ProofShape::Genuine),
                "{shape:?} was accepted as a proof of possession"
            );
        }
    });
}

/// `/v1/challenge` takes no body by design (F-8). "Ignored" has to mean ignored, including for
/// bodies that are not JSON at all.
#[test]
fn challenge_ignores_any_body() {
    let (state, _dir) = relay();
    proptest!(config(), |(body in raw_body())| {
        let len = body.len();
        let answer = post(&state, "/v1/challenge", body, "application/json");
        assert_deliberate_refusal(&answer, len);
        prop_assert_eq!(answer.status, StatusCode::OK);
    });
}

/// The harness needs a harness. A body that fails at `serde_json` never reaches a handler, so
/// a corpus that drifted into "always malformed JSON" would keep every property above green
/// while testing the extractor and nothing else. This one asserts the generated bodies land on
/// both sides of the door.
#[test]
fn generated_bodies_reach_the_handlers() {
    use proptest::strategy::ValueTree;
    use proptest::test_runner::TestRunner;

    const SAMPLE: usize = 256;
    let (state, _dir) = relay();
    let mut runner = TestRunner::deterministic();
    let bodies = enqueue_body();

    let (mut accepted, mut refused_by_handler) = (0usize, 0usize);
    for _ in 0..SAMPLE {
        let body = bodies.new_tree(&mut runner).expect("body").current();
        let answer = post(&state, "/v1/enqueue", body, "application/json");
        match answer.status {
            StatusCode::OK => accepted += 1,
            // The handler ran: it parsed the object and refused the token, the base64 or the
            // size. `422` would mean the extractor turned it away before that.
            StatusCode::BAD_REQUEST
            | StatusCode::PAYLOAD_TOO_LARGE
            | StatusCode::INSUFFICIENT_STORAGE => refused_by_handler += 1,
            _ => {}
        }
    }
    // Measured on the corpus as written: 40 and 142 of 256.
    assert!(
        accepted >= SAMPLE / 32,
        "only {accepted}/{SAMPLE} generated enqueues were well-formed enough to store"
    );
    assert!(
        refused_by_handler >= SAMPLE / 8,
        "only {refused_by_handler}/{SAMPLE} generated enqueues reached the handler's own checks"
    );
}

/// A body large enough to hurt has to be refused before it is buffered, whatever it contains.
/// The ceiling is Axum's default request limit rather than anything this crate writes, which
/// is exactly why it is pinned here: it would disappear silently if the router were rebuilt
/// without it.
#[test]
fn an_oversized_body_is_refused_without_being_parsed() {
    let (state, _dir) = relay();
    let huge = serde_json::to_vec(&json!({
        "dest_token": real_token(),
        "blob_b64": "A".repeat(8 * 1024 * 1024),
    }))
    .expect("json");
    let len = huge.len();
    let answer = post(&state, "/v1/enqueue", huge, "application/json");
    assert_deliberate_refusal(&answer, len);
    assert_eq!(answer.status, StatusCode::PAYLOAD_TOO_LARGE);
}

/// Base64 that decodes to more than a mailbox accepts is a `413`, not an allocation. The
/// blob below is under the request limit and over [`encrypchat_relay::MAX_BLOB_BYTES`], which
/// is the gap where a decoder that trusts its input would do the work first and refuse after.
#[test]
fn a_blob_over_the_mailbox_ceiling_is_refused() {
    let (state, _dir) = relay();
    let blob = vec![0u8; encrypchat_relay::MAX_BLOB_BYTES + 1];
    let body = serde_json::to_vec(&json!({
        "dest_token": real_token(),
        "blob_b64": B64.encode(&blob),
    }))
    .expect("json");
    let len = body.len();
    let answer = post(&state, "/v1/enqueue", body, "application/json");
    assert_deliberate_refusal(&answer, len);
    assert_eq!(answer.status, StatusCode::PAYLOAD_TOO_LARGE);
}

/// The control for the whole file: the same harness, a request that should work. Without it,
/// every property above would still pass if the router had started answering `400` to
/// everything.
#[test]
fn a_well_formed_enqueue_still_succeeds() {
    let (state, _dir) = relay();
    let body = serde_json::to_vec(&json!({
        "dest_token": real_token(),
        "ttl_secs": 3600,
        "blob_b64": B64.encode(b"opaque-ciphertext"),
    }))
    .expect("json");
    let answer = post(&state, "/v1/enqueue", body, "application/json");
    assert_eq!(answer.status, StatusCode::OK, "{:?}", answer.status);
}
