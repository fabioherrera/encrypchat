//! Integration tests for the blind relay HTTP API.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use encrypchat_core::{pop_proof, Identity};
use encrypchat_relay::{router, AppState, RelayConfig, Store};
use serde_json::json;
use tempfile::tempdir;

async fn serve(state: AppState) -> SocketAddr {
    let app = router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind");
    let addr = listener.local_addr().expect("addr");
    tokio::spawn(async move {
        axum::serve(
            listener,
            app.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await
        .expect("serve");
    });
    // Brief settle for accept loop.
    tokio::time::sleep(Duration::from_millis(20)).await;
    addr
}

async fn spawn_relay() -> (SocketAddr, tempfile::TempDir) {
    spawn_relay_with(RelayConfig::default()).await
}

async fn spawn_relay_with(config: RelayConfig) -> (SocketAddr, tempfile::TempDir) {
    let dir = tempdir().expect("tempdir");
    let db = dir.path().join("relay.sqlite");
    let store = Arc::new(Store::open(&db).expect("open store"));
    let addr = serve(AppState::with_config(store, config)).await;
    (addr, dir)
}

#[tokio::test]
async fn enqueue_requires_pop_then_empty_second_pull() {
    let (addr, _dir) = spawn_relay().await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let dest = bob.token().as_str().to_string();
    let blob = b"opaque-ciphertext-not-plaintext";
    let blob_b64 = B64.encode(blob);

    // Enqueue without auth.
    let enq = client
        .post(format!("{base}/v1/enqueue"))
        .json(&json!({
            "dest_token": dest,
            "ttl_secs": 3600,
            "blob_b64": blob_b64,
        }))
        .send()
        .await
        .expect("enqueue");
    assert_eq!(enq.status(), 200);
    let enq_body: serde_json::Value = enq.json().await.unwrap();
    assert!(enq_body["id"].as_str().unwrap().len() > 10);

    // Pull without challenge / with garbage proof → unauthorized.
    let bad = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": B64.encode([0u8; 32]),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(bad.status(), 401);

    // Challenge → PoP → pull succeeds and deletes.
    let ch = client
        .post(format!("{base}/v1/challenge"))
        .json(&json!({ "dest_token": dest }))
        .send()
        .await
        .unwrap();
    assert_eq!(ch.status(), 200);
    let ch_body: serde_json::Value = ch.json().await.unwrap();
    let nonce = B64.decode(ch_body["nonce_b64"].as_str().unwrap()).unwrap();
    let eph_pub: [u8; 32] = B64
        .decode(ch_body["eph_pubkey_b64"].as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap();

    let proof = pop_proof(&bob.to_secret_bytes(), &eph_pub, &nonce, &dest).unwrap();

    let pull = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": B64.encode(proof),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(pull.status(), 200);
    let pull_body: serde_json::Value = pull.json().await.unwrap();
    let msgs = pull_body["messages"].as_array().unwrap();
    assert_eq!(msgs.len(), 1);
    let got = B64.decode(msgs[0]["blob_b64"].as_str().unwrap()).unwrap();
    assert_eq!(got, blob);

    // Fresh challenge + pull → empty (already deleted).
    let ch2 = client
        .post(format!("{base}/v1/challenge"))
        .json(&json!({ "dest_token": dest }))
        .send()
        .await
        .unwrap();
    let ch2_body: serde_json::Value = ch2.json().await.unwrap();
    let nonce2 = B64.decode(ch2_body["nonce_b64"].as_str().unwrap()).unwrap();
    let eph2: [u8; 32] = B64
        .decode(ch2_body["eph_pubkey_b64"].as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap();
    let proof2 = pop_proof(&bob.to_secret_bytes(), &eph2, &nonce2, &dest).unwrap();
    let pull2 = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": B64.encode(proof2),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(pull2.status(), 200);
    let pull2_body: serde_json::Value = pull2.json().await.unwrap();
    assert!(pull2_body["messages"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn expired_ttl_purged() {
    let dir = tempdir().unwrap();
    let db = dir.path().join("relay.sqlite");
    let store = Store::open(&db).unwrap();
    let bob = Identity::generate();
    let dest = bob.token().as_str().to_string();

    // Insert directly with past expiry via enqueue + manual SQL would need access;
    // use enqueue with ttl=1 then wait, or write expired row via reopen.
    // Fast path: open rusqlite and insert expired row.
    {
        let conn = rusqlite::Connection::open(&db).unwrap();
        conn.execute(
            "INSERT INTO mailbox (id, dest_token, blob, expires_at, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            rusqlite::params![
                "expired-id",
                dest,
                b"gone",
                "2000-01-01T00:00:00+00:00",
                "2000-01-01T00:00:00+00:00",
            ],
        )
        .unwrap();
    }

    let n = store.purge_expired().unwrap();
    assert!(n >= 1);

    // Fresh challenge/pull should yield empty even with PoP.
    let store = Arc::new(store);
    let addr = serve(AppState::new(Arc::clone(&store))).await;

    let client = reqwest::Client::new();
    let base = format!("http://{addr}");
    let ch = client
        .post(format!("{base}/v1/challenge"))
        .json(&json!({ "dest_token": dest }))
        .send()
        .await
        .unwrap();
    let ch_body: serde_json::Value = ch.json().await.unwrap();
    let nonce = B64.decode(ch_body["nonce_b64"].as_str().unwrap()).unwrap();
    let eph: [u8; 32] = B64
        .decode(ch_body["eph_pubkey_b64"].as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap();
    let proof = pop_proof(&bob.to_secret_bytes(), &eph, &nonce, &dest).unwrap();
    let pull = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": B64.encode(proof),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(pull.status(), 200);
    let body: serde_json::Value = pull.json().await.unwrap();
    assert!(body["messages"].as_array().unwrap().is_empty());
}

/// Enqueue a small opaque blob; returns the HTTP status.
async fn enqueue_blob(
    client: &reqwest::Client,
    base: &str,
    dest: &str,
    blob: &[u8],
) -> reqwest::StatusCode {
    client
        .post(format!("{base}/v1/enqueue"))
        .json(&json!({
            "dest_token": dest,
            "ttl_secs": 3600,
            "blob_b64": B64.encode(blob),
        }))
        .send()
        .await
        .expect("enqueue")
        .status()
}

#[tokio::test]
async fn per_destination_message_quota() {
    let (addr, _dir) = spawn_relay_with(RelayConfig {
        max_mailbox_msgs: 3,
        enqueue_per_min: 1_000,
        challenge_per_min: 1_000,
        ..RelayConfig::default()
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let dest = bob.token().as_str().to_string();

    for _ in 0..3 {
        assert_eq!(
            enqueue_blob(&client, &base, &dest, b"ciphertext").await,
            200
        );
    }
    // Over quota: opaque 507, no mailbox counters leaked.
    let over = client
        .post(format!("{base}/v1/enqueue"))
        .json(&json!({
            "dest_token": dest,
            "blob_b64": B64.encode(b"ciphertext"),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(over.status(), 507);
    let body: serde_json::Value = over.json().await.unwrap();
    let msg = body["error"].as_str().unwrap();
    assert_eq!(msg, "destination mailbox unavailable");
    assert!(!msg.contains('3'));

    // A different destination is unaffected: the quota is per token.
    let carol = Identity::generate();
    assert_eq!(
        enqueue_blob(&client, &base, carol.token().as_str(), b"ciphertext").await,
        200
    );

    // Draining the mailbox frees the quota again.
    let ch: serde_json::Value = client
        .post(format!("{base}/v1/challenge"))
        .json(&json!({ "dest_token": dest }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let nonce = B64.decode(ch["nonce_b64"].as_str().unwrap()).unwrap();
    let eph: [u8; 32] = B64
        .decode(ch["eph_pubkey_b64"].as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap();
    let proof = pop_proof(&bob.to_secret_bytes(), &eph, &nonce, &dest).unwrap();
    let pull = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": B64.encode(proof),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(pull.status(), 200);
    assert_eq!(
        enqueue_blob(&client, &base, &dest, b"ciphertext").await,
        200
    );
}

#[tokio::test]
async fn per_destination_byte_quota() {
    let (addr, _dir) = spawn_relay_with(RelayConfig {
        max_mailbox_bytes: 100,
        enqueue_per_min: 1_000,
        ..RelayConfig::default()
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();
    let dest = Identity::generate().token().as_str().to_string();

    let blob = vec![7u8; 60];
    assert_eq!(enqueue_blob(&client, &base, &dest, &blob).await, 200);
    // 60 + 60 > 100 → rejected on bytes even though the message count is fine.
    assert_eq!(enqueue_blob(&client, &base, &dest, &blob).await, 507);
    assert_eq!(enqueue_blob(&client, &base, &dest, &[1u8; 20]).await, 200);
}

#[tokio::test]
async fn per_ip_rate_limit_on_enqueue_and_challenge() {
    let (addr, _dir) = spawn_relay_with(RelayConfig {
        enqueue_per_min: 2,
        challenge_per_min: 1,
        ..RelayConfig::default()
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();
    let dest = Identity::generate().token().as_str().to_string();

    assert_eq!(enqueue_blob(&client, &base, &dest, b"one").await, 200);
    assert_eq!(enqueue_blob(&client, &base, &dest, b"two").await, 200);
    assert_eq!(enqueue_blob(&client, &base, &dest, b"three").await, 429);

    let first = client
        .post(format!("{base}/v1/challenge"))
        .json(&json!({ "dest_token": dest }))
        .send()
        .await
        .unwrap();
    assert_eq!(first.status(), 200);
    let second = client
        .post(format!("{base}/v1/challenge"))
        .json(&json!({ "dest_token": dest }))
        .send()
        .await
        .unwrap();
    assert_eq!(second.status(), 429);

    // Health stays reachable: limits are per endpoint, not global.
    let health = client.get(format!("{base}/healthz")).send().await.unwrap();
    assert_eq!(health.status(), 200);
}

#[tokio::test]
async fn rejects_oversized_blob_and_bad_token() {
    let (addr, _dir) = spawn_relay().await;
    let client = reqwest::Client::new();
    let base = format!("http://{addr}");

    let bad_token = client
        .post(format!("{base}/v1/enqueue"))
        .json(&json!({
            "dest_token": "not_a_token",
            "blob_b64": B64.encode(b"x"),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(bad_token.status(), 400);

    let bob = Identity::generate();
    let huge = vec![0u8; encrypchat_relay::MAX_BLOB_BYTES + 1];
    let big = client
        .post(format!("{base}/v1/enqueue"))
        .json(&json!({
            "dest_token": bob.token().as_str(),
            "blob_b64": B64.encode(&huge),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(big.status(), 413);
}
