//! Per-IP token bucket for abuse control.
//!
//! In-memory and per-process: it bounds a direct flood against one relay, not a
//! distributed one. Behind a reverse proxy every request shares the proxy IP, so
//! the proxy must do its own limiting (`X-Forwarded-For` is spoofable and is
//! deliberately not trusted here).

use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Above this many tracked IPs, buckets idle for [`IDLE_EVICT`] are dropped.
const MAX_TRACKED_IPS: usize = 4096;
const IDLE_EVICT: Duration = Duration::from_secs(60);

struct Bucket {
    tokens: f64,
    last: Instant,
}

pub struct RateLimiter {
    burst: f64,
    refill_per_sec: f64,
    buckets: Mutex<HashMap<IpAddr, Bucket>>,
}

impl RateLimiter {
    /// Budget of `rpm` requests per minute, burstable up to `rpm`.
    pub fn per_minute(rpm: u32) -> Self {
        let burst = rpm.max(1) as f64;
        Self {
            burst,
            refill_per_sec: burst / 60.0,
            buckets: Mutex::new(HashMap::new()),
        }
    }

    /// `true` when the request fits the budget (consumes one token).
    pub fn allow(&self, ip: IpAddr) -> bool {
        self.allow_at(ip, Instant::now())
    }

    fn allow_at(&self, ip: IpAddr, now: Instant) -> bool {
        // Fail open: a poisoned lock must not lock every client out of the relay.
        let Ok(mut buckets) = self.buckets.lock() else {
            return true;
        };
        if buckets.len() > MAX_TRACKED_IPS {
            buckets.retain(|_, b| now.saturating_duration_since(b.last) < IDLE_EVICT);
        }
        let bucket = buckets.entry(ip).or_insert(Bucket {
            tokens: self.burst,
            last: now,
        });
        let elapsed = now.saturating_duration_since(bucket.last).as_secs_f64();
        bucket.last = now;
        bucket.tokens = (bucket.tokens + elapsed * self.refill_per_sec).min(self.burst);
        if bucket.tokens >= 1.0 {
            bucket.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::Ipv4Addr;

    fn ip(last: u8) -> IpAddr {
        IpAddr::V4(Ipv4Addr::new(10, 0, 0, last))
    }

    #[test]
    fn burst_then_denied() {
        let rl = RateLimiter::per_minute(3);
        let now = Instant::now();
        assert!(rl.allow_at(ip(1), now));
        assert!(rl.allow_at(ip(1), now));
        assert!(rl.allow_at(ip(1), now));
        assert!(!rl.allow_at(ip(1), now));
    }

    #[test]
    fn refills_over_time() {
        let rl = RateLimiter::per_minute(60);
        let start = Instant::now();
        for _ in 0..60 {
            assert!(rl.allow_at(ip(2), start));
        }
        assert!(!rl.allow_at(ip(2), start));
        // 60/min → one token per second.
        assert!(rl.allow_at(ip(2), start + Duration::from_secs(2)));
    }

    #[test]
    fn buckets_are_per_ip() {
        let rl = RateLimiter::per_minute(1);
        let now = Instant::now();
        assert!(rl.allow_at(ip(3), now));
        assert!(!rl.allow_at(ip(3), now));
        assert!(rl.allow_at(ip(4), now));
    }
}
