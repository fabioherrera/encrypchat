//! HTTP handlers for the blind relay.

use std::net::SocketAddr;
use std::sync::Arc;

use axum::extract::{ConnectInfo, State};
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use encrypchat_core::{pubkey_matches_token, Token};
use serde::{Deserialize, Serialize};
use tower_http::cors::{Any, CorsLayer};

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
        Self {
            store,
            config: Arc::new(config),
            enqueue_limit,
            challenge_limit,
            pull_limit,
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

#[derive(Debug, Serialize)]
pub struct EnqueueResponse {
    pub id: String,
}

#[derive(Debug, Deserialize)]
pub struct ChallengeRequest {
    pub dest_token: String,
}

#[derive(Debug, Serialize)]
pub struct ChallengeResponse {
    pub nonce_b64: String,
    pub eph_pubkey_b64: String,
}

#[derive(Debug, Deserialize)]
pub struct PullRequest {
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

fn rate_limit(limiter: &RateLimiter, peer: SocketAddr) -> Result<(), ApiError> {
    if limiter.allow(peer.ip()) {
        Ok(())
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

async fn enqueue(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Json(body): Json<EnqueueRequest>,
) -> Result<Json<EnqueueResponse>, ApiError> {
    rate_limit(&state.enqueue_limit, peer)?;
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
    let id = state
        .store
        .enqueue(token.as_str(), &blob, ttl, state.config.mailbox_quota())
        .map_err(|e| match e {
            // Deliberately opaque: no counts, no limits, same text for msgs and bytes.
            EnqueueError::QuotaFull => err(
                StatusCode::INSUFFICIENT_STORAGE,
                "destination mailbox unavailable",
            ),
            EnqueueError::Invalid(msg) => err(StatusCode::BAD_REQUEST, msg),
            EnqueueError::Db(msg) => err(StatusCode::INTERNAL_SERVER_ERROR, msg),
        })?;
    // No `dest_token` in logs: "who receives and when" is the metadata a blind
    // relay promises not to retain. See README → Log policy.
    tracing::info!(id = %id, bytes = blob.len(), ttl_secs = ttl, "enqueued");
    Ok(Json(EnqueueResponse { id }))
}

async fn challenge(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Json(body): Json<ChallengeRequest>,
) -> Result<Json<ChallengeResponse>, ApiError> {
    rate_limit(&state.challenge_limit, peer)?;
    let _ = state.store.purge_expired();
    let token = parse_token(&body.dest_token)?;
    let (nonce, eph) = state
        .store
        .create_challenge(token.as_str())
        .map_err(|e| err(StatusCode::INTERNAL_SERVER_ERROR, e))?;
    Ok(Json(ChallengeResponse {
        nonce_b64: B64.encode(&nonce),
        eph_pubkey_b64: B64.encode(eph.public),
    }))
}

async fn pull(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    Json(body): Json<PullRequest>,
) -> Result<Json<PullResponse>, ApiError> {
    rate_limit(&state.pull_limit, peer)?;
    let _ = state.store.purge_expired();
    let token = parse_token(&body.dest_token)?;
    let pubkey = decode_b64_32("pubkey", &body.pubkey_b64)?;
    let proof = decode_b64_32("proof", &body.proof_b64)?;

    let matches = pubkey_matches_token(&pubkey, token.as_str())
        .map_err(|_| err(StatusCode::BAD_REQUEST, "invalid dest_token"))?;
    if !matches {
        return Err(err(
            StatusCode::UNAUTHORIZED,
            "pubkey does not match dest_token",
        ));
    }

    match state.store.pull_with_pop(token.as_str(), &pubkey, &proof) {
        Ok(rows) => {
            tracing::info!(count = rows.len(), "pull ok");
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
