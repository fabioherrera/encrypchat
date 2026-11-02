//! `GET /v1/ws`: an authenticated doorbell.
//!
//! The socket opens with the same proof of possession a pull uses, so only a mailbox's owner can
//! listen for it. After that the relay sends `wake` and the client pulls over HTTP. TURN
//! credentials are also issued here, because this is the one place that already knows the caller
//! holds a key.

use std::net::SocketAddr;
use std::time::{Duration, Instant};

use axum::extract::ws::{CloseFrame, Message, WebSocket, WebSocketUpgrade};
use axum::extract::{ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use encrypchat_core::{pubkey_matches_token, Token};
use serde::Deserialize;
use serde_json::json;

use crate::api::{client_address, AppState};
use crate::hub::SocketSlot;

const AUTH_TIMEOUT: Duration = Duration::from_secs(15);

/// Under Cloudflare's 100 s idle cut, and frequent enough to notice a dead peer quickly.
const PING_EVERY: Duration = Duration::from_secs(30);
const IDLE_LIMIT: Duration = Duration::from_secs(95);

/// Nothing a client sends here is larger than an auth frame.
const MAX_FRAME_BYTES: usize = 4 * 1024;

const CLOSE_POLICY: u16 = 1008;

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ClientFrame {
    Auth {
        challenge_id: String,
        dest_token: String,
        pubkey_b64: String,
        proof_b64: String,
    },
    Turn,
}

pub async fn upgrade(
    State(state): State<AppState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Response {
    let ip = client_address(&state, peer, &headers);
    state.proxy_watch.observe(ip);
    if !state.challenge_limit.allow(ip) {
        return StatusCode::TOO_MANY_REQUESTS.into_response();
    }
    let Some(slot) = state
        .hub
        .admit(ip, state.config.max_ws_per_ip, state.config.max_ws_total)
    else {
        return StatusCode::SERVICE_UNAVAILABLE.into_response();
    };
    ws.max_message_size(MAX_FRAME_BYTES)
        .max_frame_size(MAX_FRAME_BYTES)
        .on_upgrade(move |socket| run(socket, state, ip, slot))
}

async fn run(mut socket: WebSocket, state: AppState, ip: std::net::IpAddr, _slot: SocketSlot) {
    let Some(token) = authenticate(&mut socket, &state).await else {
        return;
    };
    let mut bell = state.hub.subscribe(&token);
    let ready = json!({ "type": "ready", "turn": state.turn.is_some() });
    if send(&mut socket, &ready).await.is_err() {
        return;
    }

    let mut ping = tokio::time::interval(PING_EVERY);
    ping.tick().await;
    let mut last_seen = Instant::now();
    loop {
        tokio::select! {
            rang = bell.rung() => {
                if !rang || send(&mut socket, &json!({ "type": "wake" })).await.is_err() {
                    break;
                }
            }
            _ = ping.tick() => {
                if last_seen.elapsed() > IDLE_LIMIT
                    || socket.send(Message::Ping(Default::default())).await.is_err()
                {
                    break;
                }
            }
            incoming = socket.recv() => {
                let Some(Ok(message)) = incoming else { break };
                last_seen = Instant::now();
                match message {
                    Message::Text(text) => {
                        if let Ok(ClientFrame::Turn) = serde_json::from_str(text.as_str()) {
                            let reply = turn_reply(&state, ip).await;
                            if send(&mut socket, &reply).await.is_err() {
                                break;
                            }
                        }
                    }
                    Message::Close(_) => break,
                    _ => {}
                }
            }
        }
    }
}

async fn authenticate(socket: &mut WebSocket, state: &AppState) -> Option<String> {
    let issued = state.store.create_challenge().ok()?;
    let hello = json!({
        "type": "challenge",
        "challenge_id": issued.id,
        "nonce_b64": B64.encode(&issued.nonce),
        "eph_pubkey_b64": B64.encode(issued.eph.public),
    });
    send(socket, &hello).await.ok()?;

    let frame = tokio::time::timeout(AUTH_TIMEOUT, next_text(socket))
        .await
        .ok()??;
    let verified = match serde_json::from_str(&frame) {
        Ok(ClientFrame::Auth {
            challenge_id,
            dest_token,
            pubkey_b64,
            proof_b64,
        }) => verify(state, &challenge_id, &dest_token, &pubkey_b64, &proof_b64),
        _ => None,
    };
    if verified.is_none() {
        let _ = socket
            .send(Message::Close(Some(CloseFrame {
                code: CLOSE_POLICY,
                reason: "auth".into(),
            })))
            .await;
    }
    verified
}

fn verify(
    state: &AppState,
    challenge_id: &str,
    dest_token: &str,
    pubkey_b64: &str,
    proof_b64: &str,
) -> Option<String> {
    let token = Token::parse(dest_token).ok()?;
    let pubkey = decode_32(pubkey_b64)?;
    let proof = decode_32(proof_b64)?;
    if !pubkey_matches_token(&pubkey, token.as_str()).ok()? {
        return None;
    }
    state
        .store
        .verify_pop(challenge_id, token.as_str(), &pubkey, &proof)
        .ok()?;
    Some(token.as_str().to_string())
}

fn decode_32(b64: &str) -> Option<[u8; 32]> {
    B64.decode(b64.trim()).ok()?.try_into().ok()
}

async fn next_text(socket: &mut WebSocket) -> Option<String> {
    loop {
        match socket.recv().await? {
            Ok(Message::Text(text)) => return Some(text.to_string()),
            Ok(Message::Ping(_) | Message::Pong(_)) => {}
            _ => return None,
        }
    }
}

/// `turn_unavailable` is an answer, not a failure: the client calls with STUN alone.
async fn turn_reply(state: &AppState, ip: std::net::IpAddr) -> serde_json::Value {
    let unavailable = json!({ "type": "turn_unavailable" });
    let Some(turn) = state.turn.as_ref() else {
        return unavailable;
    };
    if !state.turn_limit.allow(ip) {
        return unavailable;
    }
    match turn.ice_servers().await {
        Ok(ice_servers) => json!({ "type": "turn", "ice_servers": ice_servers }),
        Err(e) => {
            tracing::warn!(error = %e, "could not issue TURN credentials");
            unavailable
        }
    }
}

async fn send(socket: &mut WebSocket, value: &serde_json::Value) -> Result<(), axum::Error> {
    socket.send(Message::Text(value.to_string().into())).await
}
