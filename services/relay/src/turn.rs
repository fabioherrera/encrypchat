//! Short-lived TURN credentials from Cloudflare Realtime.
//!
//! The API token stays on the relay: only an authenticated socket can ask, and only the relay
//! ever talks to Cloudflare, so a request names no user and no client address.

use std::fmt;
use std::time::Duration;

use serde_json::{json, Value};

const DEFAULT_API_BASE: &str = "https://rtc.live.cloudflare.com";

/// Lifetime of issued credentials. Must outlast the longest call, because a credential that
/// expires mid-relay drops the media.
const CREDENTIAL_TTL_SECS: u64 = 4 * 3600;

#[derive(Clone)]
pub struct TurnConfig {
    pub key_id: String,
    pub api_token: String,
    pub api_base: String,
}

impl fmt::Debug for TurnConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("TurnConfig")
            .field("key_id", &self.key_id)
            .field("api_token", &"<redacted>")
            .field("api_base", &self.api_base)
            .finish()
    }
}

impl TurnConfig {
    pub fn new(key_id: String, api_token: String) -> Self {
        Self {
            key_id,
            api_token,
            api_base: DEFAULT_API_BASE.to_string(),
        }
    }
}

pub struct TurnClient {
    http: reqwest::Client,
    config: TurnConfig,
}

impl TurnClient {
    pub fn new(config: TurnConfig) -> Result<Self, String> {
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .map_err(|e| format!("turn client: {e}"))?;
        Ok(Self { http, config })
    }

    pub async fn ice_servers(&self) -> Result<Value, String> {
        let url = format!(
            "{}/v1/turn/keys/{}/credentials/generate-ice-servers",
            self.config.api_base.trim_end_matches('/'),
            self.config.key_id
        );
        let res = self
            .http
            .post(url)
            .bearer_auth(&self.config.api_token)
            .json(&json!({ "ttl": CREDENTIAL_TTL_SECS }))
            .send()
            .await
            .map_err(|e| format!("turn request: {}", e.without_url()))?;
        let status = res.status();
        if !status.is_success() {
            return Err(format!("turn request: HTTP {status}"));
        }
        let body: Value = res
            .json()
            .await
            .map_err(|e| format!("turn response: {}", e.without_url()))?;
        let mut servers = body
            .get("iceServers")
            .filter(|v| v.is_array())
            .cloned()
            .ok_or_else(|| "turn response: no iceServers".to_string())?;
        strip_port_53(&mut servers);
        Ok(servers)
    }
}

/// Cloudflare documents port 53 as blocked on many clients. It only adds a candidate that times
/// out, so it is dropped here rather than on every client.
fn strip_port_53(servers: &mut Value) {
    let Some(list) = servers.as_array_mut() else {
        return;
    };
    for server in list {
        if let Some(urls) = server.get_mut("urls").and_then(Value::as_array_mut) {
            urls.retain(|u| {
                !u.as_str()
                    .is_some_and(|s| s.contains(":53?") || s.ends_with(":53"))
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_never_prints_the_token() {
        let c = TurnConfig::new("key".into(), "very-secret".into());
        assert!(!format!("{c:?}").contains("very-secret"));
    }

    #[test]
    fn port_53_is_dropped_and_the_rest_kept() {
        let mut s = json!([{ "urls": [
            "turn:turn.cloudflare.com:53?transport=udp",
            "turn:turn.cloudflare.com:3478?transport=udp",
            "stun:stun.cloudflare.com:53"
        ]}]);
        strip_port_53(&mut s);
        assert_eq!(
            s,
            json!([{ "urls": ["turn:turn.cloudflare.com:3478?transport=udp"] }])
        );
    }
}
