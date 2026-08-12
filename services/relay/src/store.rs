//! SQLite mailbox + challenge store for the blind relay.

use std::path::Path;
use std::sync::Mutex;

use chrono::{Duration, Utc};
use encrypchat_core::{
    pop_generate_ephemeral, pop_generate_nonce, pop_verify, PopEphemeral, POP_NONCE_LEN,
    POP_PROOF_LEN,
};
use rusqlite::{params, Connection, OptionalExtension};
use uuid::Uuid;

use crate::{CHALLENGE_TTL_SECS, MAX_BLOB_BYTES, MAX_TTL_SECS};

#[derive(Debug, Clone)]
pub struct MailboxRow {
    pub id: String,
    pub blob: Vec<u8>,
}

#[derive(Debug)]
pub struct ChallengeRow {
    pub eph_secret: [u8; 32],
    pub nonce: [u8; POP_NONCE_LEN],
}

/// Per-destination ceiling on pending (non-expired) blobs.
#[derive(Debug, Clone, Copy)]
pub struct MailboxQuota {
    pub max_msgs: usize,
    pub max_bytes: usize,
}

#[derive(Debug)]
pub enum EnqueueError {
    /// Destination is at its message or byte quota. Callers must not echo the
    /// counters back: that would turn enqueue into a mailbox-state oracle.
    QuotaFull,
    Invalid(String),
    Db(String),
}

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
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_mailbox_dest ON mailbox(dest_token);
            CREATE INDEX IF NOT EXISTS idx_mailbox_exp ON mailbox(expires_at);
            CREATE TABLE IF NOT EXISTS challenges (
                dest_token TEXT PRIMARY KEY NOT NULL,
                eph_secret BLOB NOT NULL,
                eph_pub BLOB NOT NULL,
                nonce BLOB NOT NULL,
                expires_at TEXT NOT NULL
            );
            ",
        )
        .map_err(|e| format!("migrate: {e}"))?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
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

        // Counted under the same lock as the insert so concurrent enqueues cannot
        // both slip past the ceiling.
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

        conn.execute(
            "INSERT INTO mailbox (id, dest_token, blob, expires_at, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id, dest_token, blob, expires.to_rfc3339(), now.to_rfc3339()],
        )
        .map_err(|e| EnqueueError::Db(format!("insert mailbox: {e}")))?;
        Ok(id)
    }

    /// Create (or replace) a one-shot PoP challenge for `dest_token`.
    pub fn create_challenge(&self, dest_token: &str) -> Result<(Vec<u8>, PopEphemeral), String> {
        let eph = pop_generate_ephemeral();
        let nonce = pop_generate_nonce();
        let expires = Utc::now() + Duration::seconds(CHALLENGE_TTL_SECS);
        let conn = self
            .conn
            .lock()
            .map_err(|_| "db lock poisoned".to_string())?;
        conn.execute(
            "INSERT INTO challenges (dest_token, eph_secret, eph_pub, nonce, expires_at)
             VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(dest_token) DO UPDATE SET
               eph_secret=excluded.eph_secret,
               eph_pub=excluded.eph_pub,
               nonce=excluded.nonce,
               expires_at=excluded.expires_at",
            params![
                dest_token,
                eph.secret.as_slice(),
                eph.public.as_slice(),
                nonce.as_slice(),
                expires.to_rfc3339()
            ],
        )
        .map_err(|e| format!("insert challenge: {e}"))?;
        Ok((nonce.to_vec(), eph))
    }

    /// Take challenge (one-shot delete), verify PoP, return + delete non-expired blobs.
    pub fn pull_with_pop(
        &self,
        dest_token: &str,
        client_pub: &[u8; 32],
        proof: &[u8; POP_PROOF_LEN],
    ) -> Result<Vec<MailboxRow>, String> {
        let now = Utc::now().to_rfc3339();
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
                 WHERE dest_token = ?1 AND expires_at > ?2",
                params![dest_token, now],
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

        // One-shot: consume challenge before verify outcome is returned.
        tx.execute(
            "DELETE FROM challenges WHERE dest_token = ?1",
            params![dest_token],
        )
        .map_err(|e| format!("delete challenge: {e}"))?;

        let ok = pop_verify(&ch.eph_secret, client_pub, &ch.nonce, dest_token, proof)
            .map_err(|_| "pop verify error".to_string())?;
        if !ok {
            tx.commit().map_err(|e| format!("commit: {e}"))?;
            return Err("pop failed".into());
        }

        let mut stmt = tx
            .prepare(
                "SELECT id, blob FROM mailbox
                 WHERE dest_token = ?1 AND expires_at > ?2
                 ORDER BY created_at ASC",
            )
            .map_err(|e| format!("prepare pull: {e}"))?;
        let rows = stmt
            .query_map(params![dest_token, now], |row| {
                Ok(MailboxRow {
                    id: row.get(0)?,
                    blob: row.get(1)?,
                })
            })
            .map_err(|e| format!("query pull: {e}"))?;
        let mut items = Vec::new();
        for r in rows {
            items.push(r.map_err(|e| format!("row: {e}"))?);
        }
        drop(stmt);

        tx.execute(
            "DELETE FROM mailbox WHERE dest_token = ?1",
            params![dest_token],
        )
        .map_err(|e| format!("delete mailbox: {e}"))?;

        tx.commit().map_err(|e| format!("commit: {e}"))?;
        Ok(items)
    }
}
