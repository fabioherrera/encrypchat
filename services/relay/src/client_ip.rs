//! Which address the rate limiter should charge (F-13).
//!
//! The repo's own deployment puts the relay behind cloudflared and Traefik, so every request
//! arrives from the proxy's address. A per-IP limiter then charges every user to the same
//! bucket: one attacker exhausts it and everyone else gets `429`. The anti-abuse control
//! becomes the most efficient denial of service available against the relay.
//!
//! There are two easy mistakes here and this module avoids both. Trusting
//! `X-Forwarded-For` blindly lets any client claim any address, which turns a per-IP limit
//! into no limit at all. Ignoring it entirely is what produced the bug above. So the header is
//! honoured **only** when the connection itself comes from an address the operator listed as a
//! proxy, and only as far back as that list reaches.

use std::net::{IpAddr, SocketAddr};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Mutex;

use axum::http::HeaderMap;

const XFF: &str = "x-forwarded-for";

/// Requests observed before deciding whether the deployment looks proxied.
const PROXY_SAMPLE: usize = 100;

/// Operator-declared proxies, as addresses or CIDR blocks.
#[derive(Debug, Default, Clone)]
pub struct TrustedProxies {
    nets: Vec<(IpAddr, u8)>,
}

impl TrustedProxies {
    /// Parse a comma-separated list of addresses or CIDR blocks
    /// (`127.0.0.1, 172.18.0.0/16, ::1`). An empty string means "trust nothing".
    pub fn parse(raw: &str) -> Result<Self, String> {
        let mut nets = Vec::new();
        for entry in raw.split(',') {
            let entry = entry.trim();
            if entry.is_empty() {
                continue;
            }
            let (addr, prefix) = match entry.split_once('/') {
                Some((addr, len)) => {
                    let addr: IpAddr = addr
                        .trim()
                        .parse()
                        .map_err(|_| format!("invalid address in `{entry}`"))?;
                    let len: u8 = len
                        .trim()
                        .parse()
                        .map_err(|_| format!("invalid prefix in `{entry}`"))?;
                    let max = if addr.is_ipv4() { 32 } else { 128 };
                    if len > max {
                        return Err(format!("prefix /{len} is too long for `{entry}`"));
                    }
                    (addr, len)
                }
                None => {
                    let addr: IpAddr = entry
                        .parse()
                        .map_err(|_| format!("invalid address `{entry}`"))?;
                    let len = if addr.is_ipv4() { 32 } else { 128 };
                    (addr, len)
                }
            };
            nets.push((canonical(addr), prefix));
        }
        Ok(Self { nets })
    }

    pub fn is_empty(&self) -> bool {
        self.nets.is_empty()
    }

    pub fn len(&self) -> usize {
        self.nets.len()
    }

    pub fn contains(&self, ip: IpAddr) -> bool {
        let ip = canonical(ip);
        self.nets.iter().any(|(net, prefix)| match (ip, net) {
            (IpAddr::V4(a), IpAddr::V4(b)) => prefix_eq(&a.octets(), &b.octets(), *prefix),
            (IpAddr::V6(a), IpAddr::V6(b)) => prefix_eq(&a.octets(), &b.octets(), *prefix),
            _ => false,
        })
    }
}

/// Treat `::ffff:1.2.3.4` as `1.2.3.4`, so an operator who wrote the IPv4 form still matches a
/// dual-stack listener.
fn canonical(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
            Some(v4) => IpAddr::V4(v4),
            None => IpAddr::V6(v6),
        },
        v4 => v4,
    }
}

fn prefix_eq(a: &[u8], b: &[u8], prefix: u8) -> bool {
    let full = (prefix / 8) as usize;
    if a[..full] != b[..full] {
        return false;
    }
    match prefix % 8 {
        0 => true,
        rem => {
            let mask = 0xffu8 << (8 - rem);
            a[full] & mask == b[full] & mask
        }
    }
}

/// The address to charge for this request.
///
/// Walks `X-Forwarded-For` from the right, skipping entries that are themselves trusted
/// proxies, and stops at the first address the operator has not vouched for. Anything the
/// list does not cover — a missing header, garbage, or a chain that is trusted all the way
/// down — falls back to the peer address, which is the only value a client cannot choose.
pub fn client_ip(peer: SocketAddr, headers: &HeaderMap, trusted: &TrustedProxies) -> IpAddr {
    let peer_ip = peer.ip();
    if trusted.is_empty() || !trusted.contains(peer_ip) {
        return peer_ip;
    }
    let hops: Vec<&str> = headers
        .get_all(XFF)
        .iter()
        .filter_map(|v| v.to_str().ok())
        .flat_map(|v| v.split(','))
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();
    for hop in hops.iter().rev() {
        // A bracketed or port-suffixed entry is not standard but proxies emit it anyway.
        let candidate = hop.trim_start_matches('[').split(']').next().unwrap_or(hop);
        let Ok(ip) = candidate.parse::<IpAddr>() else {
            // Garbage in the chain: everything to its left is unverifiable too.
            return peer_ip;
        };
        if !trusted.contains(ip) {
            return ip;
        }
    }
    peer_ip
}

/// Notices the deployment where every request shares one address.
///
/// A paragraph in a README does not stop anyone from running the relay behind a proxy without
/// configuring it; a log line that fires on the running system does. It samples the first
/// [`PROXY_SAMPLE`] requests and complains once — loudly — if they all came from the same
/// address and no proxy was declared, because that is exactly the shape of the bug: a limiter
/// that looks configured and protects nobody.
#[derive(Debug)]
pub struct ProxyWatch {
    seen: Mutex<Vec<IpAddr>>,
    count: AtomicUsize,
    warned: AtomicBool,
    enabled: bool,
}

impl ProxyWatch {
    pub fn new(trusted_configured: bool) -> Self {
        Self {
            seen: Mutex::new(Vec::new()),
            count: AtomicUsize::new(0),
            warned: AtomicBool::new(false),
            // Nothing to warn about once the operator has told us where the proxy is.
            enabled: !trusted_configured,
        }
    }

    pub fn observe(&self, ip: IpAddr) {
        if !self.enabled || self.warned.load(Ordering::Relaxed) {
            return;
        }
        let n = self.count.fetch_add(1, Ordering::Relaxed) + 1;
        {
            let Ok(mut seen) = self.seen.lock() else {
                return;
            };
            if seen.len() < 4 && !seen.contains(&ip) {
                seen.push(ip);
            }
            if n < PROXY_SAMPLE || seen.len() != 1 {
                return;
            }
        }
        if self.warned.swap(true, Ordering::Relaxed) {
            return;
        }
        tracing::warn!(
            source = %ip,
            requests = n,
            "every request so far arrived from one address: if that is a reverse proxy, the \
             per-IP rate limit is charging all users to one bucket and one client can lock \
             everyone out. Set ENCRYPCHAT_RELAY_TRUSTED_PROXIES and rate-limit at the proxy \
             (see services/relay/README.md)"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    fn peer(s: &str) -> SocketAddr {
        SocketAddr::new(ip(s), 4444)
    }

    fn xff(values: &[&str]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for v in values {
            h.append(XFF, HeaderValue::from_str(v).unwrap());
        }
        h
    }

    #[test]
    fn parses_addresses_and_cidr() {
        let t = TrustedProxies::parse("127.0.0.1, 172.18.0.0/16 , ::1").unwrap();
        assert_eq!(t.len(), 3);
        assert!(t.contains(ip("127.0.0.1")));
        assert!(t.contains(ip("172.18.5.9")));
        assert!(!t.contains(ip("172.19.5.9")));
        assert!(t.contains(ip("::1")));
        assert!(!t.contains(ip("10.0.0.1")));

        assert!(TrustedProxies::parse("").unwrap().is_empty());
        assert!(TrustedProxies::parse("nonsense").is_err());
        assert!(TrustedProxies::parse("10.0.0.0/33").is_err());
    }

    #[test]
    fn non_byte_aligned_prefix() {
        let t = TrustedProxies::parse("10.1.2.0/23").unwrap();
        assert!(t.contains(ip("10.1.2.7")));
        assert!(t.contains(ip("10.1.3.7")));
        assert!(!t.contains(ip("10.1.4.7")));
    }

    #[test]
    fn ipv4_mapped_matches_ipv4_rule() {
        let t = TrustedProxies::parse("127.0.0.1").unwrap();
        assert!(t.contains(ip("::ffff:127.0.0.1")));
    }

    /// The mistake that must not happen: a header from an untrusted peer is worthless.
    #[test]
    fn header_ignored_when_peer_is_not_a_trusted_proxy() {
        let t = TrustedProxies::parse("10.0.0.1").unwrap();
        let h = xff(&["203.0.113.9"]);
        assert_eq!(client_ip(peer("198.51.100.7"), &h, &t), ip("198.51.100.7"));

        // And with no list at all, nothing is honoured.
        let none = TrustedProxies::default();
        assert_eq!(client_ip(peer("10.0.0.1"), &h, &none), ip("10.0.0.1"));
    }

    #[test]
    fn takes_the_last_untrusted_hop() {
        let t = TrustedProxies::parse("10.0.0.1, 10.0.0.2").unwrap();

        // Single proxy: the client is the only entry.
        assert_eq!(
            client_ip(peer("10.0.0.1"), &xff(&["203.0.113.9"]), &t),
            ip("203.0.113.9")
        );

        // Two proxies in the chain: skip the one we trust, charge the client.
        assert_eq!(
            client_ip(peer("10.0.0.1"), &xff(&["203.0.113.9, 10.0.0.2"]), &t),
            ip("203.0.113.9")
        );

        // A client that forges hops to its left cannot shed the entry the proxy appended.
        assert_eq!(
            client_ip(
                peer("10.0.0.1"),
                &xff(&["1.1.1.1, 2.2.2.2, 203.0.113.9"]),
                &t
            ),
            ip("203.0.113.9")
        );

        // Split across two header instances, as some proxies emit them.
        assert_eq!(
            client_ip(peer("10.0.0.1"), &xff(&["203.0.113.9", "10.0.0.2"]), &t),
            ip("203.0.113.9")
        );
    }

    #[test]
    fn falls_back_to_peer_on_missing_or_broken_chain() {
        let t = TrustedProxies::parse("10.0.0.1").unwrap();
        assert_eq!(
            client_ip(peer("10.0.0.1"), &HeaderMap::new(), &t),
            ip("10.0.0.1")
        );
        assert_eq!(
            client_ip(peer("10.0.0.1"), &xff(&["not-an-ip"]), &t),
            ip("10.0.0.1")
        );
        // Chain trusted all the way down: nobody left to charge but the peer.
        assert_eq!(
            client_ip(peer("10.0.0.1"), &xff(&["10.0.0.1"]), &t),
            ip("10.0.0.1")
        );
    }

    #[test]
    fn proxy_watch_fires_once_for_a_single_source() {
        let watch = ProxyWatch::new(false);
        for _ in 0..PROXY_SAMPLE + 10 {
            watch.observe(ip("10.0.0.1"));
        }
        assert!(watch.warned.load(Ordering::Relaxed));
    }

    #[test]
    fn proxy_watch_stays_quiet_when_sources_vary_or_proxy_is_configured() {
        let varied = ProxyWatch::new(false);
        for i in 0..PROXY_SAMPLE + 10 {
            varied.observe(ip(&format!("10.0.0.{}", i % 3 + 1)));
        }
        assert!(!varied.warned.load(Ordering::Relaxed));

        let configured = ProxyWatch::new(true);
        for _ in 0..PROXY_SAMPLE + 10 {
            configured.observe(ip("10.0.0.1"));
        }
        assert!(!configured.warned.load(Ordering::Relaxed));
    }
}
