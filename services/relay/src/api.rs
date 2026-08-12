//! HTTP handlers for the blind relay.

use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;

use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{get, post};
use axum::{Json, Router};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use encrypchat_core::{pubkey_matches_token, Token};
use serde::{Deserialize, Serialize};
use tower_http::cors::{Any, CorsLayer};
use uuid::Uuid;

use crate::client_ip::{client_ip, ProxyWatch};
use crate::limit::RateLimiter;
use crate::store::{EnqueueError, Store};
use crate::{RelayConfig, DEFAULT_TTL_SECS, MAX_BLOB_BYTES, MAX_TTL_SECS};

#[derive(Clone)]
pub struct AppState {
    pub store: Arc<Store>,
    config: Arc<RelayConfig>,
    enqueue_limit: Arc<RateLimiter>,
    challenge_limit: Arc<RateLimiter>,
    pull_limit: Arc<RateLimiter>,
    proxy_watch: Arc<ProxyWatch>,
}

impl AppState {
    pub fn new(store: Arc<Store>) -> Self {
        Self::with_config(store, RelayConfig::default())
    }

    pub fn with_config(store: Arc<Store>, config: RelayConfig) -> Self {
        // Pull shares the challenge budget: it is unauthenticated until PoP runs,
        // so it needs its own ceiling even though a valid pull needs a challenge.
        let enqueue_limit = Arc::new(RateLimiter::per_minute(config.enqueue_per_min));
        let challenge_limit = Arc::new(RateLimiter::per_minute(config.challenge_per_min));
        let pull_limit = Arc::new(RateLimiter::per_minute(config.challenge_per_min));
        let proxy_watch = Arc::new(ProxyWatch::new(!config.trusted_proxies.is_empty()));
        Self {
            store,
            config: Arc::new(config),
            enqueue_limit,
            challenge_limit,
            pull_limit,
            proxy_watch,
        }
    }
}

pub fn router(state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/healthz", get(|| async { StatusCode::OK }))
        .route("/v1/enqueue", post(enqueue))
        .route("/v1/challenge", post(challenge))
        .route("/v1/pull", post(pull))
        .layer(cors)
        .with_state(state)
}

#[derive(Debug, Deserialize)]
pub struct EnqueueRequest {
    pub dest_token: String,
    pub ttl_secs: Option<u64>,
    pub blob_b64: String,
}

/// Acknowledges *receipt*, and nothing more.
///
/// `id` names the row when there is a row, but a caller cannot tell that case from a blob the
/// destination's quota dropped: both answers are this, with a fresh v4 id. There is no endpoint
/// that takes an id back, so the two are not separable after the fact either. See `enqueue`.
#[derive(Debug, Serialize)]
pub struct EnqueueResponse {
    pub id: String,
}

#[derive(Debug, Serialize)]
pub struct ChallengeResponse {
    pub challenge_id: String,
    pub nonce_b64: String,
    pub eph_pubkey_b64: String,
}

#[derive(Debug, Deserialize)]
pub struct PullRequest {
    pub challenge_id: String,
    pub dest_token: String,
    pub pubkey_b64: String,
    pub proof_b64: String,
}

#[derive(Debug, Serialize)]
pub struct PullMessage {
    pub id: String,
    pub blob_b64: String,
}

#[derive(Debug, Serialize)]
pub struct PullResponse {
    pub messages: Vec<PullMessage>,
}

#[derive(Debug, Serialize)]
struct ErrorBody {
    error: String,
}

type ApiError = (StatusCode, Json<ErrorBody>);

fn err(status: StatusCode, msg: impl Into<String>) -> ApiError {
    (status, Json(ErrorBody { error: msg.into() }))
}

fn parse_token(raw: &str) -> Result<Token, ApiError> {
    Token::parse(raw).map_err(|_| err(StatusCode::BAD_REQUEST, "invalid dest_token"))
}

/// Resolve who to charge, then charge them. Behind a proxy the peer address is the proxy's,
/// so `client_ip` is what keeps one bucket from covering every user (F-13).
fn rate_limit(
    state: &AppState,
    limiter: &RateLimiter,
    peer: SocketAddr,
    headers: &HeaderMap,
) -> Result<IpAddr, ApiError> {
    let ip = client_ip(peer, headers, &state.config.trusted_proxies);
    state.proxy_watch.observe(ip);
    if limiter.allow(ip) {
        Ok(ip)
    } else {
        Err(err(StatusCode::TOO_MANY_REQUESTS, "rate limit exceeded"))
    }
}

fn decode_b64_32(label: &str, b64: &str) -> Result<[u8; 32], ApiError> {
    let bytes = B64
        .decode(b64.trim())
        .map_err(|_| err(StatusCode::BAD_REQUEST, format!("invalid {label} base64")))?;
    bytes
        .try_into()
        .map_err(|_| err(StatusCode::BAD_REQUEST, format!("{label} must be 32 bytes")))
}

/// Accept an opaque blob for a destination token.
///
/// Unauthenticated by design. The one refusal this can answer with — `507`, the global storage
/// ceiling — depends on nothing about the destination; a per-mailbox drop is invisible. See the
/// `QuotaFull` arm below for the attack that forced it and the price it charges.
async fn enqueue(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<EnqueueRequest>,
) -> Result<Json<EnqueueResponse>, ApiError> {
    rate_limit(&state, &state.enqueue_limit, peer, &headers)?;
    let _ = state.store.purge_expired();
    let token = parse_token(&body.dest_token)?;
    let blob = B64
        .decode(body.blob_b64.trim())
        .map_err(|_| err(StatusCode::BAD_REQUEST, "invalid blob_b64"))?;
    if blob.is_empty() {
        return Err(err(StatusCode::BAD_REQUEST, "empty blob"));
    }
    if blob.len() > MAX_BLOB_BYTES {
        return Err(err(
            StatusCode::PAYLOAD_TOO_LARGE,
            format!("blob exceeds {MAX_BLOB_BYTES} bytes"),
        ));
    }
    let ttl = body
        .ttl_secs
        .unwrap_or(DEFAULT_TTL_SECS)
        .clamp(1, MAX_TTL_SECS);
    match state
        .store
        .enqueue(token.as_str(), &blob, ttl, state.config.mailbox_quota())
    {
        Ok(id) => {
            // No `dest_token` in logs: "who receives and when" is the metadata a blind
            // relay promises not to retain. See README → Log policy.
            tracing::info!(id = %id, bytes = blob.len(), ttl_secs = ttl, "enqueued");
            Ok(Json(EnqueueResponse { id }))
        }
        // Dropped, and answered exactly like an acceptance — same status, same shape, an id
        // that was simply never stored (B-3).
        //
        // A distinguishable quota refusal was a presence oracle for any token at all: `enqueue`
        // is open to anyone by design, so a stranger could fill a mailbox with 32 blobs and then
        // poll it with one byte, and the answer flipping back timed the recipient's collection —
        // metadata the threat model attributes to the operator alone. Keeping `enqueue` open is
        // not negotiable (sealed sender authenticates to the recipient, never to the relay), so
        // the distinguishability is what goes.
        //
        // What it costs the honest sender: nothing it could rely on. This response has always
        // acknowledged *receipt*, never storage and never delivery — a blob can still die of TTL
        // with nobody notified. What is new is that a dropped blob looks like a stored one, so
        // silent loss now covers a case that used to be loud. Bounded by the same quota as
        // before: it takes a full mailbox.
        Err(EnqueueError::QuotaFull) => {
            // The operator's replacement for the status code the sender no longer sees. Named
            // without the destination, like every other line here.
            tracing::warn!(
                bytes = blob.len(),
                ttl_secs = ttl,
                "dropped: destination mailbox at quota"
            );
            Ok(Json(EnqueueResponse {
                id: Uuid::new_v4().to_string(),
            }))
        }
        // Reportable, because the store checks this ceiling before it looks at the destination:
        // "the relay is out of space" is the same fact for every token and singles out nobody.
        Err(EnqueueError::StorageFull) => Err(err(
            StatusCode::INSUFFICIENT_STORAGE,
            "relay storage unavailable",
        )),
        Err(EnqueueError::Invalid(msg)) => Err(err(StatusCode::BAD_REQUEST, msg)),
        Err(EnqueueError::Db(msg)) => Err(err(StatusCode::INTERNAL_SERVER_ERROR, msg)),
    }
}

/// Issue a PoP challenge.
///
/// Deliberately takes no request body: a challenge is not *for* a destination, and the
/// handler must not be able to learn one. That is what closes F-8 — with no per-token row
/// there is nothing for a stranger to overwrite — and it also stops the relay from being told
/// which mailbox is about to be read. Any body sent by a caller is ignored.
async fn challenge(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
) -> Result<Json<ChallengeResponse>, ApiError> {
    rate_limit(&state, &state.challenge_limit, peer, &headers)?;
    let _ = state.store.purge_expired();
    let issued = state
        .store
        .create_challenge()
        .map_err(|e| err(StatusCode::INTERNAL_SERVER_ERROR, e))?;
    Ok(Json(ChallengeResponse {
        challenge_id: issued.id,
        nonce_b64: B64.encode(&issued.nonce),
        eph_pubkey_b64: B64.encode(issued.eph.public),
    }))
}

async fn pull(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(body): Json<PullRequest>,
) -> Result<Json<PullResponse>, ApiError> {
    rate_limit(&state, &state.pull_limit, peer, &headers)?;
    let _ = state.store.purge_expired();
    let token = parse_token(&body.dest_token)?;
    let pubkey = decode_b64_32("pubkey", &body.pubkey_b64)?;
    let proof = decode_b64_32("proof", &body.proof_b64)?;

    // `dest_token` already parsed above, so anything left is the key itself: wrong length is
    // caught by `decode_b64_32`, and a non-canonical encoding is refused by the core, which
    // names one key with exactly one token (core 0.8.1).
    let matches = pubkey_matches_token(&pubkey, token.as_str())
        .map_err(|_| err(StatusCode::BAD_REQUEST, "invalid pubkey"))?;
    if !matches {
        return Err(err(
            StatusCode::UNAUTHORIZED,
            "pubkey does not match dest_token",
        ));
    }

    match state.store.pull_with_pop(
        &body.challenge_id,
        token.as_str(),
        &pubkey,
        &proof,
        state.config.pull_lease_secs,
    ) {
        Ok(rows) => {
            // `redelivered` counts blobs handed out for the second time, which is how an
            // operator sees clients dying between the `200` and their own commit. It names no
            // destination, so it stays inside the log policy.
            let redelivered = rows.iter().filter(|r| r.redelivered).count();
            tracing::info!(count = rows.len(), redelivered, "pull ok");
            Ok(Json(PullResponse {
                messages: rows
                    .into_iter()
                    .map(|r| PullMessage {
                        id: r.id,
                        blob_b64: B64.encode(r.blob),
                    })
                    .collect(),
            }))
        }
        Err(e) if e == "pop failed" || e == "no valid challenge" => {
            Err(err(StatusCode::UNAUTHORIZED, e))
        }
        Err(e) => Err(err(StatusCode::INTERNAL_SERVER_ERROR, e)),
    }
}
