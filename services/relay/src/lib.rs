//! Encrypchat blind relay — opaque ciphertext mailbox (Phase 5).
//!
//! Stores destination token + TTL + ciphertext blob only. Pull requires X25519
//! ECDH proof-of-possession via [`encrypchat_core::pop`]. Never decrypts content.

use axum::http::HeaderName;

mod api;
mod client_ip;
mod hub;
mod limit;
mod store;
mod turn;
mod ws;

pub use api::{router, AppState};
pub use client_ip::TrustedProxies;
pub use limit::RateLimiter;
pub use store::{EnqueueError, MailboxQuota, Store};
pub use turn::TurnConfig;

/// Max opaque blob size accepted by enqueue (8 MiB). Large enough for a phone photo, which is
/// what stopped crossing networks at the old 256 KiB ceiling.
pub const MAX_BLOB_BYTES: usize = 8 * 1024 * 1024;

/// Max request body: one blob in base64 inside its JSON envelope.
pub const MAX_REQUEST_BYTES: usize = MAX_BLOB_BYTES / 3 * 4 + 64 * 1024;

/// Max TTL clamp (7 days).
pub const MAX_TTL_SECS: u64 = 7 * 24 * 3600;

/// Default TTL when client omits or sends zero.
pub const DEFAULT_TTL_SECS: u64 = 86_400;

/// Challenge lifetime (2 minutes).
pub const CHALLENGE_TTL_SECS: i64 = 120;

/// How long a delivered blob stays hidden before it is offered a second and last time.
///
/// Three times the client's own pull timeout (20 s). The two delivery attempts are only worth
/// having if they are independent failure trials, and they are independent only once the first
/// response has definitively arrived or definitively timed out — a lease shorter than that
/// timeout can burn both attempts on the same stalled connection. The rest is margin for the
/// client to commit the batch it just received and for two devices' clocks to disagree.
///
/// Longer buys nothing: the number of duplicate transmissions is one either way (see
/// `store.rs`), so a longer lease only delays recovery and holds the bytes on disk longer.
pub const DEFAULT_PULL_LEASE_SECS: i64 = 60;

/// Live challenges kept before the oldest are trimmed. Global on purpose: a per-token ceiling
/// is the F-8 weapon, whichever way it is resolved (see `store.rs`).
pub const MAX_LIVE_CHALLENGES: usize = 50_000;

/// Live bytes across every mailbox (1 GiB). Reaching it refuses new blobs; nothing already
/// accepted is evicted to make room.
pub const DEFAULT_MAX_TOTAL_BYTES: usize = 1024 * 1024 * 1024;

/// Pending blobs kept per destination token.
pub const DEFAULT_MAX_MAILBOX_MSGS: usize = 200;

/// Pending bytes kept per destination token (32 MiB): a few photos while the recipient is away.
pub const DEFAULT_MAX_MAILBOX_BYTES: usize = 32 * 1024 * 1024;

/// Enqueue budget per client IP, per minute. Call signaling goes through here too, and setting
/// up one call sends a burst of ICE candidates.
pub const DEFAULT_ENQUEUE_PER_MIN: u32 = 240;

/// TURN credentials issued per client IP, per minute. Each one can spend relay bandwidth that
/// the operator pays for, and a token is free to mint, so this is the real ceiling.
pub const DEFAULT_TURN_PER_MIN: u32 = 6;

/// Live sockets per client IP. A household shares one address.
pub const DEFAULT_MAX_WS_PER_IP: usize = 32;

/// Live sockets across the relay.
pub const DEFAULT_MAX_WS_TOTAL: usize = 20_000;

/// Challenge (and pull) budget per client IP, per minute.
///
/// 120 leaves room for several devices behind one CGNAT/home NAT (each app
/// polls about 8 times a minute). 30 made 3–4 phones on the same public IP
/// start seeing `429`.
pub const DEFAULT_CHALLENGE_PER_MIN: u32 = 120;

/// Abuse limits. Every field is overridable by env var (see `README.md`).
#[derive(Debug, Clone)]
pub struct RelayConfig {
    pub max_mailbox_msgs: usize,
    pub max_mailbox_bytes: usize,
    pub max_total_bytes: usize,
    pub enqueue_per_min: u32,
    pub challenge_per_min: u32,
    /// Seconds a delivered blob stays hidden before its second and last delivery.
    pub pull_lease_secs: i64,
    /// Addresses whose `X-Forwarded-For` is believed. Empty means the header is ignored,
    /// which is the only safe default: without it, any client could pick its own bucket.
    pub trusted_proxies: TrustedProxies,
    /// Single-value client address header set by the edge, such as `cf-connecting-ip`.
    /// Believed only from a trusted proxy, and only when the edge overwrites it on every request.
    pub real_ip_header: Option<HeaderName>,
    pub turn_per_min: u32,
    pub max_ws_per_ip: usize,
    pub max_ws_total: usize,
    /// Cloudflare Realtime TURN. Without it calls fall back to STUN alone.
    pub turn: Option<TurnConfig>,
}

impl Default for RelayConfig {
    fn default() -> Self {
        Self {
            max_mailbox_msgs: DEFAULT_MAX_MAILBOX_MSGS,
            max_mailbox_bytes: DEFAULT_MAX_MAILBOX_BYTES,
            max_total_bytes: DEFAULT_MAX_TOTAL_BYTES,
            enqueue_per_min: DEFAULT_ENQUEUE_PER_MIN,
            challenge_per_min: DEFAULT_CHALLENGE_PER_MIN,
            pull_lease_secs: DEFAULT_PULL_LEASE_SECS,
            trusted_proxies: TrustedProxies::default(),
            real_ip_header: None,
            turn_per_min: DEFAULT_TURN_PER_MIN,
            max_ws_per_ip: DEFAULT_MAX_WS_PER_IP,
            max_ws_total: DEFAULT_MAX_WS_TOTAL,
            turn: None,
        }
    }
}

impl RelayConfig {
    pub fn from_env() -> Self {
        let d = Self::default();
        Self {
            max_mailbox_msgs: env_num("ENCRYPCHAT_RELAY_MAX_MSGS", d.max_mailbox_msgs),
            max_mailbox_bytes: env_num("ENCRYPCHAT_RELAY_MAX_BYTES", d.max_mailbox_bytes),
            max_total_bytes: env_num("ENCRYPCHAT_RELAY_MAX_TOTAL_BYTES", d.max_total_bytes),
            enqueue_per_min: env_num("ENCRYPCHAT_RELAY_ENQUEUE_RPM", d.enqueue_per_min),
            challenge_per_min: env_num("ENCRYPCHAT_RELAY_CHALLENGE_RPM", d.challenge_per_min),
            // A lease of zero (or a negative one) is expired the moment it is written, which
            // would turn the first delivery into the last and quietly restore the at-most-once
            // behaviour this setting exists to fix.
            pull_lease_secs: env_num("ENCRYPCHAT_RELAY_PULL_LEASE_SECS", d.pull_lease_secs).max(1),
            trusted_proxies: env_proxies("ENCRYPCHAT_RELAY_TRUSTED_PROXIES"),
            real_ip_header: env_header("ENCRYPCHAT_RELAY_REAL_IP_HEADER"),
            turn_per_min: env_num("ENCRYPCHAT_RELAY_TURN_RPM", d.turn_per_min),
            max_ws_per_ip: env_num("ENCRYPCHAT_RELAY_MAX_WS_PER_IP", d.max_ws_per_ip),
            max_ws_total: env_num("ENCRYPCHAT_RELAY_MAX_WS_TOTAL", d.max_ws_total),
            turn: env_turn(),
        }
    }

    pub fn mailbox_quota(&self) -> MailboxQuota {
        MailboxQuota {
            max_msgs: self.max_mailbox_msgs,
            max_bytes: self.max_mailbox_bytes,
            max_total_bytes: self.max_total_bytes,
        }
    }
}

/// A malformed proxy list is not silently ignored down to "trust nothing": that would look
/// configured while behaving like the bug F-13 describes. It refuses to start.
fn env_proxies(key: &str) -> TrustedProxies {
    match std::env::var(key) {
        Ok(raw) => TrustedProxies::parse(&raw).unwrap_or_else(|e| {
            eprintln!("{key}: {e}");
            std::process::exit(1);
        }),
        Err(_) => TrustedProxies::default(),
    }
}

/// Same rule as [`env_proxies`]: a value that looks configured must not silently do nothing.
fn env_header(key: &str) -> Option<HeaderName> {
    let raw = std::env::var(key).ok()?;
    let raw = raw.trim();
    if raw.is_empty() {
        return None;
    }
    match raw.parse() {
        Ok(name) => Some(name),
        Err(_) => {
            eprintln!("{key}: invalid header name `{raw}`");
            std::process::exit(1);
        }
    }
}

/// Half a TURN configuration refuses to start: it would look configured while every call quietly
/// lost its relay.
fn env_turn() -> Option<TurnConfig> {
    let read = |key: &str| {
        std::env::var(key)
            .ok()
            .map(|v| v.trim().to_string())
            .filter(|v| !v.is_empty())
    };
    match (
        read("ENCRYPCHAT_RELAY_TURN_KEY_ID"),
        read("ENCRYPCHAT_RELAY_TURN_API_TOKEN"),
    ) {
        (Some(key_id), Some(api_token)) => Some(TurnConfig::new(key_id, api_token)),
        (None, None) => None,
        _ => {
            eprintln!(
                "ENCRYPCHAT_RELAY_TURN_KEY_ID and ENCRYPCHAT_RELAY_TURN_API_TOKEN go together"
            );
            std::process::exit(1);
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
