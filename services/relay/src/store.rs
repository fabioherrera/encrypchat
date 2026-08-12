//! SQLite mailbox + challenge store for the blind relay.
//!
//! ## Why challenges are not keyed by destination (F-8)
//!
//! They used to be, with one row per `dest_token` and an upsert on collision. Since anyone
//! can ask for a challenge for any token — they must be able to, or proof-of-possession
//! could never bootstrap — a third party could overwrite the victim's pending challenge and
//! make every pull fail. The mailbox then filled, later messages for the victim were refused,
//! and the queued ones expired by TTL. Targeted censorship of one person, from one address,
//! inside the rate-limit budget.
//!
//! A per-token ceiling with several live challenges does not fix it, it only sets a price:
//! evict the oldest and the attacker races the victim's challenge out again; refuse when full
//! and the attacker locks the victim out instead. Either way the per-token namespace is the
//! weapon. So there is no per-token namespace: a challenge is an ephemeral keypair and a
//! nonce, which are the same for every destination, and the destination is bound at *pull*
//! time by the proof itself ([`encrypchat_core::pop_verify`] takes `dest_token` into the
//! transcript). Challenges are keyed by an unguessable id, and the only ceiling is global.
//!
//! A side effect worth having: `/v1/challenge` no longer tells the relay which mailbox
//! somebody is about to read.

use std::path::Path;
use std::sync::Mutex;

use chrono::{Duration, Utc};
use encrypchat_core::{
    pop_generate_ephemeral, pop_generate_nonce, pop_verify, PopEphemeral, POP_NONCE_LEN,
    POP_PROOF_LEN,
};
use rusqlite::{params, Connection, OptionalExtension};
use uuid::Uuid;

use crate::{CHALLENGE_TTL_SECS, MAX_BLOB_BYTES, MAX_LIVE_CHALLENGES, MAX_TTL_SECS};

#[derive(Debug, Clone)]
pub struct MailboxRow {
    pub id: String,
    pub blob: Vec<u8>,
    /// True when this row had already been handed out once, so this pull is its last.
    pub redelivered: bool,
}

#[derive(Debug)]
pub struct ChallengeRow {
    pub eph_secret: [u8; 32],
    pub nonce: [u8; POP_NONCE_LEN],
}

/// A challenge handed to whoever asked for it. `id` is the unguessable handle that must come
/// back with the proof.
#[derive(Debug)]
pub struct IssuedChallenge {
    pub id: String,
    pub nonce: Vec<u8>,
    pub eph: PopEphemeral,
}

/// Ceilings on pending (non-expired) blobs: per destination, and for the whole store.
#[derive(Debug, Clone, Copy)]
pub struct MailboxQuota {
    pub max_msgs: usize,
    pub max_bytes: usize,
    pub max_total_bytes: usize,
}

#[derive(Debug)]
pub enum EnqueueError {
    /// Destination is at its message or byte quota, so the blob was **not** stored.
    ///
    /// **This must not be observable by the caller** (B-3). Anyone may enqueue to any token —
    /// sealed sender authenticates to the recipient, never to the relay — so a refusal that
    /// happens only for a *full* mailbox is a presence oracle for an arbitrary token: fill the
    /// box, then poll it with one byte, and the moment the answer changes is the moment the
    /// recipient collected. The HTTP layer therefore answers this with the same body an
    /// accepted enqueue gets, and this variant exists for the store's own honesty, for the
    /// operator log and for the tests.
    QuotaFull,
    /// The whole store is at its byte ceiling, whoever the destination is.
    ///
    /// Safe to report, and reported: it is checked *before* the per-destination quota, so the
    /// state it reveals is the same for every token and reveals nothing about any recipient.
    StorageFull,
    Invalid(String),
    Db(String),
}

/// Fraction of the global ceiling that triggers an operator warning.
const HIGH_WATER: f64 = 0.9;

pub struct Store {
    conn: Mutex<Connection>,
}

impl Store {
    pub fn open(path: &Path) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            if !parent.as_os_str().is_empty() {
                std::fs::create_dir_all(parent).map_err(|e| format!("create db dir: {e}"))?;
            }
        }
        let conn = Connection::open(path).map_err(|e| format!("open db: {e}"))?;
        conn.execute_batch(
            "
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS mailbox (
                id TEXT PRIMARY KEY NOT NULL,
                dest_token TEXT NOT NULL,
                blob BLOB NOT NULL,
                expires_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                leased_until TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_mailbox_dest ON mailbox(dest_token);
            CREATE INDEX IF NOT EXISTS idx_mailbox_exp ON mailbox(expires_at);
            ",
        )
        .map_err(|e| format!("migrate: {e}"))?;
        migrate_mailbox_lease(&conn)?;
        migrate_challenges(&conn)?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    /// Live (non-expired) bytes across every mailbox.
    pub fn total_bytes(&self) -> Result<usize, String> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        live_bytes(&conn)
    }

    pub fn purge_expired(&self) -> Result<usize, String> {
        let now = Utc::now().to_rfc3339();
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        let n_mail = conn
            .execute("DELETE FROM mailbox WHERE expires_at <= ?1", params![now])
            .map_err(|e| format!("purge mailbox: {e}"))?;
        let n_ch = conn
            .execute(
                "DELETE FROM challenges WHERE expires_at <= ?1",
                params![now],
            )
            .map_err(|e| format!("purge challenges: {e}"))?;
        Ok(n_mail + n_ch)
    }

    /// Store one blob for `dest_token`.
    ///
    /// The two ceilings are evaluated **global first, per-destination second**, and the order is
    /// load-bearing rather than incidental: it is what keeps the only refusal the caller gets to
    /// see (`StorageFull`) independent of the destination. Reversed, a globally full relay would
    /// answer differently depending on whether the addressed mailbox was also full, which is the
    /// oracle [`EnqueueError::QuotaFull`] describes.
    ///
    /// The order also flattens the cheapest timing difference between the two outcomes: the
    /// whole-store `SUM` runs either way, so an accepted enqueue and a quota-dropped one differ
    /// by the `INSERT` alone.
    pub fn enqueue(
        &self,
        dest_token: &str,
        blob: &[u8],
        ttl_secs: u64,
        quota: MailboxQuota,
    ) -> Result<String, EnqueueError> {
        if blob.is_empty() {
            return Err(EnqueueError::Invalid("empty blob".into()));
        }
        if blob.len() > MAX_BLOB_BYTES {
            return Err(EnqueueError::Invalid(format!(
                "blob exceeds {MAX_BLOB_BYTES} bytes"
            )));
        }
        let ttl = ttl_secs.clamp(1, MAX_TTL_SECS);
        let now = Utc::now();
        let expires = now + Duration::seconds(ttl as i64);
        let id = Uuid::new_v4().to_string();
        let conn = self
            .conn
            .lock()
            .map_err(|_| EnqueueError::Db("db lock poisoned".into()))?;

        // Global ceiling (F-13), and first on purpose — see the note above. Nothing is evicted
        // to make room: the only rows this store ever deletes are expired ones and delivered
        // ones. A purge policy that dropped live blobs to fit a new one would let anyone expel
        // other people's messages by filling the disk, which is a worse outcome than refusing
        // the write.
        let total = live_bytes(&conn).map_err(EnqueueError::Db)?;
        let after = total.saturating_add(blob.len());
        if after > quota.max_total_bytes {
            tracing::warn!(
                limit_bytes = quota.max_total_bytes,
                "relay storage ceiling reached: refusing new blobs until pulls or TTL free space"
            );
            return Err(EnqueueError::StorageFull);
        }

        // Per destination, counted under the same lock as the insert so concurrent enqueues
        // cannot both slip past the ceiling. Nothing about this outcome reaches the caller.
        let (msgs, bytes): (i64, i64) = conn
            .query_row(
                "SELECT COUNT(*), COALESCE(SUM(LENGTH(blob)), 0) FROM mailbox
                 WHERE dest_token = ?1 AND expires_at > ?2",
                params![dest_token, now.to_rfc3339()],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .map_err(|e| EnqueueError::Db(format!("count mailbox: {e}")))?;
        let used_msgs = msgs.max(0) as usize;
        let used_bytes = bytes.max(0) as usize;
        if used_msgs + 1 > quota.max_msgs || used_bytes.saturating_add(blob.len()) > quota.max_bytes
        {
            return Err(EnqueueError::QuotaFull);
        }

        // After the quota check, so the notice tracks bytes that were really written: a blob a
        // mailbox drops does not move the store's usage and must not be reported as if it had.
        if total <= high_water(quota.max_total_bytes) && after > high_water(quota.max_total_bytes) {
            tracing::warn!(
                used_bytes = after,
                limit_bytes = quota.max_total_bytes,
                "relay storage above 90% of its ceiling"
            );
        }

        conn.execute(
            "INSERT INTO mailbox (id, dest_token, blob, expires_at, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id, dest_token, blob, expires.to_rfc3339(), now.to_rfc3339()],
        )
        .map_err(|e| EnqueueError::Db(format!("insert mailbox: {e}")))?;
        Ok(id)
    }

    /// Issue a challenge. It belongs to whoever asked for it, not to a destination: see the
    /// module docs for why binding it to `dest_token` was the bug.
    pub fn create_challenge(&self) -> Result<IssuedChallenge, String> {
        let eph = pop_generate_ephemeral();
        let nonce = pop_generate_nonce();
        let id = Uuid::new_v4().to_string();
        let now = Utc::now();
        let expires = now + Duration::seconds(CHALLENGE_TTL_SECS);
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;

        // Global ceiling, trimmed oldest-first. With no per-token key there is no victim to
        // aim at: to evict one particular pending challenge an attacker has to push the entire
        // table through in the seconds between that client's challenge and its pull. Bounding
        // the request rate that would take is the proxy's job (F-13).
        let live: i64 = conn
            .query_row("SELECT COUNT(*) FROM challenges", [], |row| row.get(0))
            .map_err(|e| format!("count challenges: {e}"))?;
        if live as usize >= MAX_LIVE_CHALLENGES {
            let excess = live as usize - MAX_LIVE_CHALLENGES + 1;
            conn.execute(
                "DELETE FROM challenges WHERE id IN
                 (SELECT id FROM challenges ORDER BY expires_at ASC LIMIT ?1)",
                params![excess as i64],
            )
            .map_err(|e| format!("trim challenges: {e}"))?;
            tracing::warn!(
                live,
                trimmed = excess,
                "challenge table at its ceiling: oldest entries dropped"
            );
        }

        conn.execute(
            "INSERT INTO challenges (id, eph_secret, eph_pub, nonce, expires_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                id,
                eph.secret.as_slice(),
                eph.public.as_slice(),
                nonce.as_slice(),
                expires.to_rfc3339()
            ],
        )
        .map_err(|e| format!("insert challenge: {e}"))?;
        Ok(IssuedChallenge {
            id,
            nonce: nonce.to_vec(),
            eph,
        })
    }

    /// Verify the PoP presented with `challenge_id`, then return the destination's deliverable
    /// blobs, leasing the ones delivered for the first time and deleting the ones delivered
    /// for the second.
    ///
    /// The challenge is consumed **only on success**, so a failed attempt costs the caller
    /// nothing and costs a third party nothing either — ids are unguessable, so the only party
    /// who can burn a challenge is the one who was given it. Consuming on success is what
    /// keeps a captured proof from being replayed.
    ///
    /// ## The lease (F-5 delete-before-durable-ack)
    ///
    /// A row is in one of two states, held in `leased_until`:
    ///
    /// | `leased_until` | Meaning | What a pull does to it |
    /// | --- | --- | --- |
    /// | `NULL` | never delivered | return it, set the lease |
    /// | in the future | delivered, still hidden | nothing: it is not selected |
    /// | in the past | delivered, its lease ran out | return it again, **delete** it |
    ///
    /// So every blob is delivered once, and a second time only if the recipient comes back
    /// after the lease. That second delivery is the whole point: a client killed between the
    /// `200` and its own commit — the ordinary case on mobile, where pulls happen on resume and
    /// in background fetches — finds the message still there.
    ///
    /// **A recipient who pulls again inside the lease is served nothing, deliberately.** The
    /// alternative, re-offering leased rows on every poll, hands the client the same batch
    /// every 8 seconds for the whole lease; the de-duplication added on the client absorbs it
    /// on screen but the bytes and the radio time are spent anyway, and for an 8 MiB mailbox
    /// that is the difference between one wasted copy and seven. Hiding does not remove the
    /// duplicate — nothing can, without the relay learning that the client persisted the batch,
    /// which is the explicit ACK this design exists to avoid — it caps it at exactly one.
    /// The cost of that choice, stated plainly: a client that lost the first batch waits out
    /// the lease before it sees those messages.
    ///
    /// Two consequences to keep in mind, both deliberate:
    ///
    /// - **The relay cannot tell a re-poll from a second device holding the same key.** They
    ///   present the same proof over the same token, so "hidden from the same client" and
    ///   "hidden from the other device" are one behaviour, not two.
    /// - **A leased row still occupies disk, so it still counts** against the per-destination
    ///   quota and the global ceiling. It has to: excluding it would let a recipient hold twice
    ///   its byte quota by pulling. The effect is that draining a *full* mailbox frees its quota
    ///   one lease later than it used to — silently, since B-3: blobs sent into that window are
    ///   dropped and their senders are told nothing. There is no new way to pin bytes here —
    ///   creating a lease needs the destination's private key, and anyone at all can already
    ///   hold those bytes for the whole TTL by enqueueing, which is days rather than a minute.
    ///
    /// `expires_at` is never touched, so the TTL always wins: a row whose TTL runs out while
    /// leased is purged and never gets its second delivery. With a TTL shorter than the lease,
    /// delivery is still at-most-once.
    pub fn pull_with_pop(
        &self,
        challenge_id: &str,
        dest_token: &str,
        client_pub: &[u8; 32],
        proof: &[u8; POP_PROOF_LEN],
        lease_secs: i64,
    ) -> Result<Vec<MailboxRow>, String> {
        let started = Utc::now();
        let now = started.to_rfc3339();
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        let tx = conn
            .unchecked_transaction()
            .map_err(|e| format!("begin tx: {e}"))?;

        let challenge: Option<ChallengeRow> = tx
            .query_row(
                "SELECT eph_secret, nonce FROM challenges
                 WHERE id = ?1 AND expires_at > ?2",
                params![challenge_id, now],
                |row| {
                    let secret: Vec<u8> = row.get(0)?;
                    let nonce: Vec<u8> = row.get(1)?;
                    let mut eph_secret = [0u8; 32];
                    let mut nonce_arr = [0u8; POP_NONCE_LEN];
                    if secret.len() != 32 || nonce.len() != POP_NONCE_LEN {
                        return Err(rusqlite::Error::InvalidQuery);
                    }
                    eph_secret.copy_from_slice(&secret);
                    nonce_arr.copy_from_slice(&nonce);
                    Ok(ChallengeRow {
                        eph_secret,
                        nonce: nonce_arr,
                    })
                },
            )
            .optional()
            .map_err(|e| format!("select challenge: {e}"))?;

        let Some(ch) = challenge else {
            return Err("no valid challenge".into());
        };

        let ok = pop_verify(&ch.eph_secret, client_pub, &ch.nonce, dest_token, proof)
            .map_err(|_| "pop verify error".to_string())?;
        if !ok {
            return Err("pop failed".into());
        }

        // One-shot from here on: the proof was good, so this id must never open a mailbox
        // again even if someone captured it in transit.
        tx.execute(
            "DELETE FROM challenges WHERE id = ?1",
            params![challenge_id],
        )
        .map_err(|e| format!("delete challenge: {e}"))?;

        let mut stmt = tx
            .prepare(
                "SELECT id, blob, leased_until IS NOT NULL FROM mailbox
                 WHERE dest_token = ?1 AND expires_at > ?2
                   AND (leased_until IS NULL OR leased_until <= ?2)
                 ORDER BY created_at ASC",
            )
            .map_err(|e| format!("prepare pull: {e}"))?;
        let rows = stmt
            .query_map(params![dest_token, now], |row| {
                Ok(MailboxRow {
                    id: row.get(0)?,
                    blob: row.get(1)?,
                    redelivered: row.get(2)?,
                })
            })
            .map_err(|e| format!("query pull: {e}"))?;
        let mut items = Vec::new();
        for r in rows {
            items.push(r.map_err(|e| format!("row: {e}"))?);
        }
        drop(stmt);

        // Both writes are in the same transaction as the read, so an overlapping pull of this
        // mailbox either sees the rows before the lease and gets them, or after it and gets
        // nothing. It cannot see them mid-flight and hand out a second copy.
        let leased_until = (started + Duration::seconds(lease_secs)).to_rfc3339();
        for row in &items {
            if row.redelivered {
                tx.execute("DELETE FROM mailbox WHERE id = ?1", params![row.id])
                    .map_err(|e| format!("delete delivered: {e}"))?;
            } else {
                tx.execute(
                    "UPDATE mailbox SET leased_until = ?1 WHERE id = ?2",
                    params![leased_until, row.id],
                )
                .map_err(|e| format!("lease mailbox: {e}"))?;
            }
        }

        tx.commit().map_err(|e| format!("commit: {e}"))?;
        Ok(items)
    }
}

fn high_water(limit: usize) -> usize {
    (limit as f64 * HIGH_WATER) as usize
}

fn live_bytes(conn: &Connection) -> Result<usize, String> {
    let now = Utc::now().to_rfc3339();
    let total: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(LENGTH(blob)), 0) FROM mailbox WHERE expires_at > ?1",
            params![now],
            |row| row.get(0),
        )
        .map_err(|e| format!("count storage: {e}"))?;
    Ok(total.max(0) as usize)
}

/// Adds `leased_until` to a mailbox table written before the lease existed. The rows already
/// there are undelivered by definition — the old `pull` deleted what it returned — so `NULL`
/// is the right value for every one of them and there is nothing to backfill.
fn migrate_mailbox_lease(conn: &Connection) -> Result<(), String> {
    let has_column = conn
        .prepare("SELECT 1 FROM pragma_table_info('mailbox') WHERE name = 'leased_until'")
        .and_then(|mut stmt| stmt.exists([]))
        .map_err(|e| format!("inspect mailbox: {e}"))?;
    if !has_column {
        conn.execute_batch("ALTER TABLE mailbox ADD COLUMN leased_until TEXT;")
            .map_err(|e| format!("add leased_until: {e}"))?;
        tracing::info!("mailbox table upgraded: delivery is now at-least-once with a lease");
    }
    Ok(())
}

/// Challenges used to be keyed by `dest_token` (F-8). They live two minutes and cost one round
/// trip to replace, so the old table is dropped rather than migrated.
fn migrate_challenges(conn: &Connection) -> Result<(), String> {
    let legacy = conn
        .prepare("SELECT 1 FROM pragma_table_info('challenges') WHERE name = 'dest_token'")
        .and_then(|mut stmt| stmt.exists([]))
        .map_err(|e| format!("inspect challenges: {e}"))?;
    if legacy {
        conn.execute_batch("DROP TABLE challenges;")
            .map_err(|e| format!("drop legacy challenges: {e}"))?;
        tracing::info!("dropped pre-0.8 challenge table (was keyed by destination)");
    }
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS challenges (
            id TEXT PRIMARY KEY NOT NULL,
            eph_secret BLOB NOT NULL,
            eph_pub BLOB NOT NULL,
            nonce BLOB NOT NULL,
            expires_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_challenges_exp ON challenges(expires_at);
        ",
    )
    .map_err(|e| format!("migrate challenges: {e}"))
}
