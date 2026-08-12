//! Encrypchat blind relay — opaque ciphertext mailbox (Phase 5).
//!
//! Stores destination token + TTL + ciphertext blob only. Pull requires X25519
//! ECDH proof-of-possession via [`encrypchat_core::pop`]. Never decrypts content.

mod api;
mod limit;
mod store;

pub use api::{router, AppState};
pub use limit::RateLimiter;
pub use store::{EnqueueError, MailboxQuota, Store};

/// Max opaque blob size accepted by enqueue (256 KiB).
pub const MAX_BLOB_BYTES: usize = 256 * 1024;

/// Max TTL clamp (7 days).
pub const MAX_TTL_SECS: u64 = 7 * 24 * 3600;

/// Default TTL when client omits or sends zero.
pub const DEFAULT_TTL_SECS: u64 = 86_400;

/// Challenge lifetime (2 minutes).
pub const CHALLENGE_TTL_SECS: i64 = 120;

/// Pending blobs kept per destination token.
pub const DEFAULT_MAX_MAILBOX_MSGS: usize = 200;

/// Pending bytes kept per destination token (8 MiB).
pub const DEFAULT_MAX_MAILBOX_BYTES: usize = 8 * 1024 * 1024;

/// Enqueue budget per client IP, per minute.
pub const DEFAULT_ENQUEUE_PER_MIN: u32 = 60;

/// Challenge (and pull) budget per client IP, per minute.
pub const DEFAULT_CHALLENGE_PER_MIN: u32 = 30;

/// Abuse limits. Every field is overridable by env var (see `README.md`).
#[derive(Debug, Clone)]
pub struct RelayConfig {
    pub max_mailbox_msgs: usize,
    pub max_mailbox_bytes: usize,
    pub enqueue_per_min: u32,
    pub challenge_per_min: u32,
}

impl Default for RelayConfig {
    fn default() -> Self {
        Self {
            max_mailbox_msgs: DEFAULT_MAX_MAILBOX_MSGS,
            max_mailbox_bytes: DEFAULT_MAX_MAILBOX_BYTES,
            enqueue_per_min: DEFAULT_ENQUEUE_PER_MIN,
            challenge_per_min: DEFAULT_CHALLENGE_PER_MIN,
        }
    }
}

impl RelayConfig {
    pub fn from_env() -> Self {
        let d = Self::default();
        Self {
            max_mailbox_msgs: env_num("ENCRYPCHAT_RELAY_MAX_MSGS", d.max_mailbox_msgs),
            max_mailbox_bytes: env_num("ENCRYPCHAT_RELAY_MAX_BYTES", d.max_mailbox_bytes),
            enqueue_per_min: env_num("ENCRYPCHAT_RELAY_ENQUEUE_RPM", d.enqueue_per_min),
            challenge_per_min: env_num("ENCRYPCHAT_RELAY_CHALLENGE_RPM", d.challenge_per_min),
        }
    }

    pub fn mailbox_quota(&self) -> MailboxQuota {
        MailboxQuota {
            max_msgs: self.max_mailbox_msgs,
            max_bytes: self.max_mailbox_bytes,
        }
    }
}

fn env_num<T: std::str::FromStr>(key: &str, default: T) -> T {
    match std::env::var(key) {
        Ok(raw) => match raw.trim().parse::<T>() {
            Ok(v) => v,
            Err(_) => {
                tracing::warn!(var = key, "invalid value, using default");
                default
            }
        },
        Err(_) => default,
    }
}
