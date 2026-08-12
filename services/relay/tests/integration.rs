//! Integration tests for the blind relay HTTP API.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use encrypchat_core::{pop_proof, Identity};
use encrypchat_relay::{router, AppState, RelayConfig, Store, TrustedProxies};
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
    let (addr, _store, dir) = spawn_relay_keeping_store(config).await;
    (addr, dir)
}

/// Same relay, with the store handed back. The lease tests need it: "the blob is hidden" and
/// "the blob is gone" look identical over HTTP, and only one of them is the behaviour under
/// test.
async fn spawn_relay_keeping_store(
    config: RelayConfig,
) -> (SocketAddr, Arc<Store>, tempfile::TempDir) {
    let dir = tempdir().expect("tempdir");
    let db = dir.path().join("relay.sqlite");
    let store = Arc::new(Store::open(&db).expect("open store"));
    let addr = serve(AppState::with_config(Arc::clone(&store), config)).await;
    (addr, store, dir)
}

/// Limits out of the way, and a lease short enough to wait out in a test.
fn lease_test_config(pull_lease_secs: i64) -> RelayConfig {
    RelayConfig {
        pull_lease_secs,
        enqueue_per_min: 1_000,
        challenge_per_min: 1_000,
        ..RelayConfig::default()
    }
}

/// A challenge as the relay now issues it: no destination, just an id and the material.
struct Challenge {
    id: String,
    nonce: Vec<u8>,
    eph_pub: [u8; 32],
}

async fn get_challenge(client: &reqwest::Client, base: &str) -> Challenge {
    let resp = client
        .post(format!("{base}/v1/challenge"))
        .json(&json!({}))
        .send()
        .await
        .expect("challenge");
    assert_eq!(resp.status(), 200);
    let body: serde_json::Value = resp.json().await.unwrap();
    Challenge {
        id: body["challenge_id"].as_str().unwrap().to_string(),
        nonce: B64.decode(body["nonce_b64"].as_str().unwrap()).unwrap(),
        eph_pub: B64
            .decode(body["eph_pubkey_b64"].as_str().unwrap())
            .unwrap()
            .try_into()
            .unwrap(),
    }
}

/// Full authenticated pull for `who`, returning the raw response.
async fn pull_as(
    client: &reqwest::Client,
    base: &str,
    who: &Identity,
    ch: &Challenge,
) -> reqwest::Response {
    let dest = who.token().as_str().to_string();
    let proof = pop_proof(&who.to_secret_bytes(), &ch.eph_pub, &ch.nonce, &dest).unwrap();
    client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "challenge_id": ch.id,
            "dest_token": dest,
            "pubkey_b64": B64.encode(who.public_key_bytes()),
            "proof_b64": B64.encode(proof),
        }))
        .send()
        .await
        .expect("pull")
}

/// Challenge + pull in one step, asserting success and returning the blobs.
async fn drain(client: &reqwest::Client, base: &str, who: &Identity) -> Vec<Vec<u8>> {
    let ch = get_challenge(client, base).await;
    let resp = pull_as(client, base, who, &ch).await;
    assert_eq!(resp.status(), 200);
    let body: serde_json::Value = resp.json().await.unwrap();
    body["messages"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| B64.decode(m["blob_b64"].as_str().unwrap()).unwrap())
        .collect()
}

/// The failure the lease exists for: the client got its `200` and died before writing the
/// message down. It comes back to find the message still there — once.
#[tokio::test]
async fn a_client_that_dies_after_the_pull_gets_the_message_again() {
    let (addr, store, _dir) = spawn_relay_keeping_store(lease_test_config(1)).await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let blob = b"opaque-ciphertext".to_vec();
    assert_eq!(
        enqueue_blob(&client, &base, bob.token().as_str(), &blob).await,
        200
    );

    // The pull that the client never got to commit.
    assert_eq!(drain(&client, &base, &bob).await, vec![blob.clone()]);
    // Still on disk, which is what makes the recovery possible at all.
    assert!(store.total_bytes().unwrap() >= blob.len());

    // It restarts and pulls straight away, inside the lease: nothing yet.
    assert!(drain(&client, &base, &bob).await.is_empty());

    // Once the lease runs out, the second and last delivery.
    tokio::time::sleep(Duration::from_millis(1_200)).await;
    assert_eq!(drain(&client, &base, &bob).await, vec![blob]);

    // And that delivery deleted it: no third copy, and no bytes left behind. Waiting out
    // another lease is what separates "deleted" from "leased again".
    tokio::time::sleep(Duration::from_millis(1_200)).await;
    assert!(drain(&client, &base, &bob).await.is_empty());
    assert_eq!(store.total_bytes().unwrap(), 0);
}

/// The decision about the normal case: a healthy client polls again 8 s later and is served
/// nothing, so the batch crosses the wire once rather than once per poll.
///
/// The relay cannot distinguish this from a second device holding the same key — same token,
/// same proof — so this is also the answer to "does a leased message go to anyone else": no,
/// not to the next poll of the same client and not to another holder of the key.
#[tokio::test]
async fn a_leased_batch_is_served_to_nobody_until_the_lease_ends() {
    let (addr, store, _dir) = spawn_relay_keeping_store(lease_test_config(600)).await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let blob = b"opaque-ciphertext".to_vec();
    assert_eq!(
        enqueue_blob(&client, &base, bob.token().as_str(), &blob).await,
        200
    );
    assert_eq!(drain(&client, &base, &bob).await, vec![blob.clone()]);

    // Several polls' worth, all empty.
    for _ in 0..3 {
        assert!(drain(&client, &base, &bob).await.is_empty());
    }
    // Empty because it is hidden, not because it is gone: with a 10-minute lease the row is
    // still there, and that is the only difference between this and the old delete-on-pull.
    assert!(store.total_bytes().unwrap() >= blob.len());

    // A stranger's mailbox is unaffected by any of it.
    let carol = Identity::generate();
    assert!(drain(&client, &base, &carol).await.is_empty());
}

/// Two pulls of the same mailbox in flight at once. Exactly one of them gets the blob: the
/// lease is written in the same transaction that reads the rows, so there is no window where
/// both see them undelivered.
#[tokio::test]
async fn two_overlapping_pulls_hand_the_batch_to_one_of_them() {
    let (addr, _dir) = spawn_relay_with(lease_test_config(600)).await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    assert_eq!(
        enqueue_blob(&client, &base, bob.token().as_str(), b"opaque-ciphertext").await,
        200
    );

    // Both challenges first: they are one-shot, so each pull needs its own.
    let first = get_challenge(&client, &base).await;
    let second = get_challenge(&client, &base).await;
    let (a, b) = tokio::join!(
        pull_as(&client, &base, &bob, &first),
        pull_as(&client, &base, &bob, &second),
    );
    assert_eq!(a.status(), 200);
    assert_eq!(b.status(), 200);

    let count = |body: serde_json::Value| body["messages"].as_array().unwrap().len();
    let delivered = count(a.json().await.unwrap()) + count(b.json().await.unwrap());
    assert_eq!(delivered, 1, "the blob was handed out {delivered} times");
}

/// A lease holds bytes, so it is counted like any other bytes — including against the
/// per-destination quota. The window is one lease long and it closes on its own.
///
/// Every enqueue here answers `200`, so the assertions are on the mailbox instead: since B-3 a
/// quota drop is not visible over HTTP, and `stored_for` is the only way to tell "kept" from
/// "silently dropped".
#[tokio::test]
async fn a_leased_blob_still_counts_against_the_quota() {
    let (addr, dir) = spawn_relay_with(RelayConfig {
        max_mailbox_msgs: 1,
        ..lease_test_config(1)
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let dest = bob.token().as_str().to_string();
    assert_eq!(enqueue_blob(&client, &base, &dest, b"first").await, 200);
    assert_eq!(enqueue_blob(&client, &base, &dest, b"second").await, 200);
    assert_eq!(stored_for(&dir, &dest), 1, "the second blob was kept");

    // Delivered, but not yet deleted: the slot is still taken, so the next blob is still
    // dropped. This is the price of the lease on the send path, and it is bounded by the lease.
    assert_eq!(drain(&client, &base, &bob).await.len(), 1);
    assert_eq!(enqueue_blob(&client, &base, &dest, b"second").await, 200);
    assert_eq!(stored_for(&dir, &dest), 1);

    // The second delivery deletes the row, and the slot comes back.
    tokio::time::sleep(Duration::from_millis(1_200)).await;
    assert_eq!(drain(&client, &base, &bob).await.len(), 1);
    assert_eq!(enqueue_blob(&client, &base, &dest, b"second").await, 200);
    assert_eq!(stored_for(&dir, &dest), 1, "the slot never came back");
}

/// The lease must never extend a row's life. Otherwise a delivered blob could sit past the TTL
/// its sender chose, and the ceiling would be holding bytes nobody can account for.
#[tokio::test]
async fn a_lease_does_not_outlive_the_ttl() {
    let (addr, store, _dir) = spawn_relay_keeping_store(lease_test_config(600)).await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let enq = client
        .post(format!("{base}/v1/enqueue"))
        .json(&json!({
            "dest_token": bob.token().as_str(),
            "ttl_secs": 1,
            "blob_b64": B64.encode(b"opaque-ciphertext"),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(enq.status(), 200);

    // Delivered once and leased for ten minutes, with one second of TTL left.
    assert_eq!(drain(&client, &base, &bob).await.len(), 1);
    tokio::time::sleep(Duration::from_millis(1_200)).await;

    assert!(store.purge_expired().unwrap() >= 1);
    assert_eq!(store.total_bytes().unwrap(), 0);
    // No second delivery: past the TTL, at-least-once degrades to at-most-once by design.
    assert!(drain(&client, &base, &bob).await.is_empty());
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

    // Pull with a garbage challenge id and proof → unauthorized.
    let bad = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "challenge_id": "00000000-0000-0000-0000-000000000000",
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": B64.encode([0u8; 32]),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(bad.status(), 401);

    // Challenge → PoP → pull succeeds, and the mailbox does not serve the same blob twice in
    // a row. Note what this assertion no longer proves: since the lease landed, the second
    // pull is empty because the blob is *hidden* for the lease, not because it was deleted.
    // The distinction is the whole state machine, and it is tested by the lease tests above.
    assert_eq!(drain(&client, &base, &bob).await, vec![blob.to_vec()]);
    assert!(drain(&client, &base, &bob).await.is_empty());
}

/// F-8: a stranger asking for challenges must not be able to stop the owner from reading.
///
/// The old store kept one challenge per destination and replaced it on every request, so this
/// loop used to leave the victim unable to pull at all — mailbox full, later messages dropped,
/// the queued ones lost to TTL.
#[tokio::test]
async fn third_party_challenges_cannot_lock_a_mailbox() {
    let (addr, _dir) = spawn_relay_with(RelayConfig {
        challenge_per_min: 1_000,
        enqueue_per_min: 1_000,
        ..RelayConfig::default()
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let dest = bob.token().as_str().to_string();
    assert_eq!(
        enqueue_blob(&client, &base, &dest, b"ciphertext").await,
        200
    );

    // Bob starts his exchange.
    let bobs = get_challenge(&client, &base).await;

    // A stranger hammers the endpoint in the middle of it.
    for _ in 0..25 {
        let _ = get_challenge(&client, &base).await;
    }

    // Bob's challenge is still his.
    let resp = pull_as(&client, &base, &bob, &bobs).await;
    assert_eq!(resp.status(), 200);
    let body: serde_json::Value = resp.json().await.unwrap();
    assert_eq!(body["messages"].as_array().unwrap().len(), 1);
}

/// One-shot on success, still usable after a failure: an attacker cannot burn a challenge by
/// presenting a bad proof, and a captured good proof cannot be replayed.
#[tokio::test]
async fn challenge_survives_a_failed_proof_but_not_a_successful_one() {
    let (addr, _dir) = spawn_relay_with(RelayConfig {
        challenge_per_min: 1_000,
        enqueue_per_min: 1_000,
        ..RelayConfig::default()
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let dest = bob.token().as_str().to_string();
    assert_eq!(
        enqueue_blob(&client, &base, &dest, b"ciphertext").await,
        200
    );
    let ch = get_challenge(&client, &base).await;

    // Wrong proof against Bob's challenge.
    let bad = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "challenge_id": ch.id,
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": B64.encode([9u8; 32]),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(bad.status(), 401);

    // Same challenge still works for its owner.
    let proof = pop_proof(&bob.to_secret_bytes(), &ch.eph_pub, &ch.nonce, &dest).unwrap();
    let good = pull_as(&client, &base, &bob, &ch).await;
    assert_eq!(good.status(), 200);

    // Replaying the proof that just worked does not open the mailbox again.
    let replay = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "challenge_id": ch.id,
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": B64.encode(proof),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(replay.status(), 401);
}

/// F-10 at the relay edge. An alias of Bob's key is the same key to every Diffie-Hellman, so
/// the PoP over it is arithmetically fine; it is only a different `SHA-256`. The relay must
/// refuse the encoding rather than let a caller pick which of several names a key has.
#[tokio::test]
async fn a_non_canonical_pubkey_is_refused_on_pull() {
    let (addr, _dir) = spawn_relay().await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let dest = bob.token().as_str().to_string();
    assert_eq!(
        enqueue_blob(&client, &base, &dest, b"ciphertext").await,
        200
    );

    let mut alias = bob.public_key_bytes();
    alias[31] |= 0x80;

    let ch = get_challenge(&client, &base).await;
    let proof = pop_proof(&bob.to_secret_bytes(), &ch.eph_pub, &ch.nonce, &dest).unwrap();
    let resp = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "challenge_id": ch.id,
            "dest_token": dest,
            "pubkey_b64": B64.encode(alias),
            "proof_b64": B64.encode(proof),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 400);

    // The mailbox is untouched and the canonical spelling still drains it.
    assert_eq!(drain(&client, &base, &bob).await.len(), 1);
}

/// A challenge is not a capability over a mailbox: it authenticates nothing by itself.
#[tokio::test]
async fn a_challenge_does_not_open_someone_elses_mailbox() {
    let (addr, _dir) = spawn_relay_with(RelayConfig {
        challenge_per_min: 1_000,
        enqueue_per_min: 1_000,
        ..RelayConfig::default()
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let mallory = Identity::generate();
    let dest = bob.token().as_str().to_string();
    assert_eq!(
        enqueue_blob(&client, &base, &dest, b"ciphertext").await,
        200
    );

    // Mallory holds a perfectly valid challenge and Bob's public key.
    let ch = get_challenge(&client, &base).await;
    let her_proof = pop_proof(&mallory.to_secret_bytes(), &ch.eph_pub, &ch.nonce, &dest).unwrap();
    let resp = client
        .post(format!("{base}/v1/pull"))
        .json(&json!({
            "challenge_id": ch.id,
            "dest_token": dest,
            "pubkey_b64": B64.encode(bob.public_key_bytes()),
            "proof_b64": B64.encode(her_proof),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(resp.status(), 401);

    // And Bob's message is untouched.
    assert_eq!(drain(&client, &base, &bob).await.len(), 1);
}

/// F-13: the ceiling is global, and reaching it must not cost anyone their already-accepted
/// messages.
#[tokio::test]
async fn global_storage_ceiling_refuses_without_evicting() {
    let (addr, _dir) = spawn_relay_with(RelayConfig {
        max_total_bytes: 300,
        enqueue_per_min: 1_000,
        challenge_per_min: 1_000,
        ..RelayConfig::default()
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let victim = Identity::generate();
    let victim_dest = victim.token().as_str().to_string();
    assert_eq!(
        enqueue_blob(&client, &base, &victim_dest, b"legitimate-ciphertext").await,
        200
    );

    // An attacker fills the relay across tokens it invents.
    let mut filled = 0;
    for _ in 0..20 {
        let dest = Identity::generate().token().as_str().to_string();
        if enqueue_blob(&client, &base, &dest, &[0u8; 100]).await == 507 {
            break;
        }
        filled += 1;
    }
    assert!(filled >= 1, "the ceiling should allow some traffic first");

    // Full: new writes are refused, and the message says nothing about any mailbox.
    let refused = client
        .post(format!("{base}/v1/enqueue"))
        .json(&json!({
            "dest_token": Identity::generate().token().as_str(),
            "blob_b64": B64.encode(vec![0u8; 100]),
        }))
        .send()
        .await
        .unwrap();
    assert_eq!(refused.status(), 507);
    let body: serde_json::Value = refused.json().await.unwrap();
    assert_eq!(body["error"].as_str().unwrap(), "relay storage unavailable");

    // The point of refusing rather than evicting: the victim's message is still deliverable.
    assert_eq!(
        drain(&client, &base, &victim).await,
        vec![b"legitimate-ciphertext".to_vec()]
    );

    // And draining freed space, so the relay recovers on its own.
    assert_eq!(
        enqueue_blob(&client, &base, &victim_dest, b"after-recovery").await,
        200
    );
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
    assert!(drain(&client, &base, &bob).await.is_empty());
}

/// Rows the relay is really holding for `dest`, read straight out of SQLite.
///
/// The only way to test the per-destination quota since B-3: the enqueue response is identical
/// whether the blob was stored or dropped, deliberately, so "did the quota bite" is not a
/// question the API answers any more. Nothing outside the tests looks behind it like this.
fn stored_for(dir: &tempfile::TempDir, dest: &str) -> usize {
    let conn = rusqlite::Connection::open(dir.path().join("relay.sqlite")).expect("open store");
    conn.query_row(
        "SELECT COUNT(*) FROM mailbox WHERE dest_token = ?1",
        rusqlite::params![dest],
        |row| row.get::<_, i64>(0),
    )
    .expect("count mailbox") as usize
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
    let (addr, dir) = spawn_relay_with(RelayConfig {
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
    // Over quota: the blob is dropped and the sender is told nothing about it.
    assert_eq!(
        enqueue_blob(&client, &base, &dest, b"ciphertext").await,
        200
    );
    assert_eq!(stored_for(&dir, &dest), 3, "the quota did not hold");

    // A different destination is unaffected: the quota is per token.
    let carol = Identity::generate();
    let carol_dest = carol.token().as_str().to_string();
    assert_eq!(
        enqueue_blob(&client, &base, &carol_dest, b"ciphertext").await,
        200
    );
    assert_eq!(stored_for(&dir, &carol_dest), 1);

    // Draining used to free the quota on the spot. It no longer does: the blobs are leased,
    // still on disk and still counted, until their second delivery deletes them. The slot
    // coming back is asserted in `a_leased_blob_still_counts_against_the_quota`, which is
    // where the lease is short enough to wait out.
    assert_eq!(drain(&client, &base, &bob).await.len(), 3);
    assert_eq!(
        enqueue_blob(&client, &base, &dest, b"ciphertext").await,
        200
    );
    assert_eq!(stored_for(&dir, &dest), 3, "a leased row stopped counting");
}

#[tokio::test]
async fn per_destination_byte_quota() {
    let (addr, dir) = spawn_relay_with(RelayConfig {
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
    // 60 + 60 > 100 → dropped on bytes even though the message count is fine.
    assert_eq!(enqueue_blob(&client, &base, &dest, &blob).await, 200);
    assert_eq!(stored_for(&dir, &dest), 1);
    // One that fits is still taken: the ceiling is on bytes, not a latch on the mailbox.
    assert_eq!(enqueue_blob(&client, &base, &dest, &[1u8; 20]).await, 200);
    assert_eq!(stored_for(&dir, &dest), 2);
}

/// B-3: the whole point. A stranger who knows a token can fill that mailbox — `enqueue` is open
/// to anyone by design — so if a full mailbox answered differently from an empty one, probing it
/// would time the recipient's collections. Everything a third party can observe must be equal on
/// both sides of the drain.
#[tokio::test]
async fn a_full_mailbox_answers_exactly_like_an_empty_one() {
    let (addr, dir) = spawn_relay_with(RelayConfig {
        max_mailbox_msgs: 2,
        enqueue_per_min: 1_000,
        challenge_per_min: 1_000,
        ..lease_test_config(1)
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    let dest = bob.token().as_str().to_string();

    // Baseline: what an accepted enqueue looks like, byte for byte in shape.
    let accepted = probe(&client, &base, &dest).await;
    assert_eq!(accepted.0, 200);

    // Mallory fills the rest of the box, then probes it.
    assert_eq!(enqueue_blob(&client, &base, &dest, b"filler").await, 200);
    let refused = probe(&client, &base, &dest).await;
    assert_eq!(stored_for(&dir, &dest), 2, "the probe was stored after all");

    // Same status, same field, same id shape — and the ids differ, as two accepted enqueues
    // would. A constant or absent id would be the tell.
    assert_eq!(refused.0, accepted.0);
    assert_eq!(refused.1.len(), accepted.1.len());
    assert_ne!(refused.1, accepted.1);

    // Bob collects. If the answer had changed here, that change would be the oracle: this is
    // the exact transition an attacker polls for.
    assert_eq!(drain(&client, &base, &bob).await.len(), 2);
    let while_leased = probe(&client, &base, &dest).await;
    assert_eq!(while_leased.0, accepted.0);

    tokio::time::sleep(Duration::from_millis(1_200)).await;
    assert_eq!(drain(&client, &base, &bob).await.len(), 2);
    let drained = probe(&client, &base, &dest).await;
    assert_eq!(drained.0, accepted.0);
    // The mailbox really is empty now, so the last probe was genuinely stored. Indistinguishable
    // from the three before it, which is the property under test.
    assert_eq!(stored_for(&dir, &dest), 1);
}

/// One-byte probe, as an attacker would send it. Returns the status and the id.
async fn probe(client: &reqwest::Client, base: &str, dest: &str) -> (reqwest::StatusCode, String) {
    let resp = client
        .post(format!("{base}/v1/enqueue"))
        .json(&json!({ "dest_token": dest, "blob_b64": B64.encode(b"x") }))
        .send()
        .await
        .expect("probe");
    let status = resp.status();
    let body: serde_json::Value = resp.json().await.expect("json");
    (status, body["id"].as_str().unwrap_or_default().to_string())
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
        .json(&json!({}))
        .send()
        .await
        .unwrap();
    assert_eq!(first.status(), 200);
    let second = client
        .post(format!("{base}/v1/challenge"))
        .json(&json!({}))
        .send()
        .await
        .unwrap();
    assert_eq!(second.status(), 429);

    // Health stays reachable: limits are per endpoint, not global.
    let health = client.get(format!("{base}/healthz")).send().await.unwrap();
    assert_eq!(health.status(), 200);
}

/// F-13, through the whole stack: behind a declared proxy each forwarded client gets its own
/// bucket, so one of them cannot spend everybody's budget.
#[tokio::test]
async fn forwarded_clients_get_separate_buckets() {
    let (addr, _dir) = spawn_relay_with(RelayConfig {
        enqueue_per_min: 1,
        trusted_proxies: TrustedProxies::parse("127.0.0.1, ::1").expect("proxies"),
        ..RelayConfig::default()
    })
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();
    let dest = Identity::generate().token().as_str().to_string();

    let enqueue_as = |forwarded: &'static str| {
        let client = client.clone();
        let base = base.clone();
        let dest = dest.clone();
        async move {
            client
                .post(format!("{base}/v1/enqueue"))
                .header("x-forwarded-for", forwarded)
                .json(&json!({ "dest_token": dest, "blob_b64": B64.encode(b"ciphertext") }))
                .send()
                .await
                .unwrap()
                .status()
        }
    };

    assert_eq!(enqueue_as("203.0.113.1").await, 200);
    assert_eq!(enqueue_as("203.0.113.1").await, 429);
    // A different client behind the same proxy is unaffected — the bug was that it was not.
    assert_eq!(enqueue_as("203.0.113.2").await, 200);
}

/// Upgrading a relay that is already holding mail: the mailbox table predates `leased_until`,
/// and the blobs in it must survive the migration and then behave like any other — delivered,
/// leased, and deliverable a second time.
#[tokio::test]
async fn a_mailbox_written_before_the_lease_is_migrated_in_place() {
    let dir = tempdir().unwrap();
    let db = dir.path().join("relay.sqlite");
    let bob = Identity::generate();
    {
        let conn = rusqlite::Connection::open(&db).unwrap();
        conn.execute_batch(
            "CREATE TABLE mailbox (
                id TEXT PRIMARY KEY NOT NULL,
                dest_token TEXT NOT NULL,
                blob BLOB NOT NULL,
                expires_at TEXT NOT NULL,
                created_at TEXT NOT NULL
            );",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO mailbox (id, dest_token, blob, expires_at, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            rusqlite::params![
                "pre-lease-id",
                bob.token().as_str(),
                b"opaque-ciphertext",
                "2999-01-01T00:00:00+00:00",
                "2020-01-01T00:00:00+00:00",
            ],
        )
        .unwrap();
    }

    let store = Arc::new(Store::open(&db).expect("open over pre-lease schema"));
    let addr = serve(AppState::with_config(store, lease_test_config(1))).await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    // Undelivered, which is what a row from the old schema always is: the old pull deleted
    // whatever it returned, so there was no such thing as a delivered row left behind.
    assert_eq!(
        drain(&client, &base, &bob).await,
        vec![b"opaque-ciphertext".to_vec()]
    );
    assert!(drain(&client, &base, &bob).await.is_empty());
    tokio::time::sleep(Duration::from_millis(1_200)).await;
    assert_eq!(drain(&client, &base, &bob).await.len(), 1);
}

/// Upgrading an existing deployment: the old per-destination challenge table is dropped, not
/// carried forward, and the relay works on first boot.
#[tokio::test]
async fn legacy_challenge_table_is_replaced_on_open() {
    let dir = tempdir().unwrap();
    let db = dir.path().join("relay.sqlite");
    {
        let conn = rusqlite::Connection::open(&db).unwrap();
        conn.execute_batch(
            "CREATE TABLE challenges (
                dest_token TEXT PRIMARY KEY NOT NULL,
                eph_secret BLOB NOT NULL,
                eph_pub BLOB NOT NULL,
                nonce BLOB NOT NULL,
                expires_at TEXT NOT NULL
            );",
        )
        .unwrap();
        conn.execute(
            "INSERT INTO challenges VALUES (?1, ?2, ?3, ?4, ?5)",
            rusqlite::params![
                "ec_old",
                [0u8; 32],
                [0u8; 32],
                [0u8; 32],
                "2999-01-01T00:00:00+00:00"
            ],
        )
        .unwrap();
    }

    let store = Arc::new(Store::open(&db).expect("open over legacy schema"));
    let addr = serve(AppState::with_config(
        store,
        RelayConfig {
            challenge_per_min: 1_000,
            enqueue_per_min: 1_000,
            ..RelayConfig::default()
        },
    ))
    .await;
    let base = format!("http://{addr}");
    let client = reqwest::Client::new();

    let bob = Identity::generate();
    assert_eq!(
        enqueue_blob(&client, &base, bob.token().as_str(), b"ciphertext").await,
        200
    );
    assert_eq!(drain(&client, &base, &bob).await.len(), 1);
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
