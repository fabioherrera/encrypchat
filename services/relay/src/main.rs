//! Encrypchat blind relay binary.

use std::env;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use encrypchat_relay::{router, AppState, RelayConfig, Store};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let addr: SocketAddr = env::var("ENCRYPCHAT_RELAY_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8787".into())
        .parse()
        .expect("ENCRYPCHAT_RELAY_ADDR must be host:port");

    let db_path = env::var("ENCRYPCHAT_RELAY_DB")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("./data/relay.sqlite"));

    let store = Store::open(&db_path).unwrap_or_else(|e| {
        eprintln!("failed to open relay db {}: {e}", db_path.display());
        std::process::exit(1);
    });
    let store = Arc::new(store);
    let _ = store.purge_expired();

    // Background purge of expired mailbox/challenge rows.
    let purge_store = Arc::clone(&store);
    tokio::spawn(async move {
        let mut tick = tokio::time::interval(Duration::from_secs(60));
        loop {
            tick.tick().await;
            match purge_store.purge_expired() {
                Ok(n) if n > 0 => tracing::info!(purged = n, "expired rows removed"),
                Ok(_) => {}
                Err(e) => tracing::warn!(error = %e, "purge failed"),
            }
        }
    });

    let config = RelayConfig::from_env();
    tracing::info!(
        max_msgs = config.max_mailbox_msgs,
        max_bytes = config.max_mailbox_bytes,
        max_total_bytes = config.max_total_bytes,
        enqueue_rpm = config.enqueue_per_min,
        challenge_rpm = config.challenge_per_min,
        pull_lease_secs = config.pull_lease_secs,
        trusted_proxies = config.trusted_proxies.len(),
        "abuse limits"
    );
    // The client gives a pull 20 s before it gives up. Under that, the lease can expire while
    // the first response is still on the wire, and both delivery attempts get spent on the same
    // stalled connection — which is the failure the lease exists to survive.
    if config.pull_lease_secs < 20 {
        tracing::warn!(
            pull_lease_secs = config.pull_lease_secs,
            "pull lease is shorter than a client's pull timeout: delivered blobs may be \
             re-offered while the first response is still in flight"
        );
    }
    if config.trusted_proxies.is_empty() {
        // Not a warning: running with no proxy is a legitimate deployment. The loud complaint
        // is the one that fires when the traffic actually looks proxied (F-13).
        tracing::info!(
            "no trusted proxies configured: X-Forwarded-For is ignored and the rate limit \
             charges the connecting address. Behind cloudflared or Traefik, set \
             ENCRYPCHAT_RELAY_TRUSTED_PROXIES and limit at the proxy"
        );
    }
    match store.total_bytes() {
        Ok(used) => tracing::info!(used_bytes = used, "mailbox storage in use"),
        Err(e) => tracing::warn!(error = %e, "could not measure storage"),
    }
    let app = router(AppState::with_config(store, config));
    tracing::info!(%addr, db = %db_path.display(), "encrypchat_relay listening");
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|e| {
            eprintln!("bind {addr}: {e}");
            std::process::exit(1);
        });
    // Connect info is required: per-IP rate limiting reads the real peer address.
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .expect("server error");
}
