//! Live doorbells for connected mailboxes.
//!
//! A socket never carries a blob. It only says "go pull", so delivery, the lease and proof of
//! possession stay on the one path the rest of the relay already defends. Holding only a counter
//! per token means a burst of signals coalesces into one wake, and nothing here outlives the
//! connections that asked for it.

use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::{Arc, Mutex};

use tokio::sync::watch;

#[derive(Default)]
pub struct Hub {
    bells: Mutex<HashMap<String, watch::Sender<u64>>>,
    sockets: Mutex<Sockets>,
}

#[derive(Default)]
struct Sockets {
    total: usize,
    per_ip: HashMap<IpAddr, usize>,
}

/// A subscription to one mailbox. Dropping the last one forgets the token.
pub struct Doorbell {
    hub: Arc<Hub>,
    token: String,
    rx: Option<watch::Receiver<u64>>,
}

impl Doorbell {
    pub async fn rung(&mut self) -> bool {
        match self.rx.as_mut() {
            Some(rx) => rx.changed().await.is_ok(),
            None => false,
        }
    }
}

impl Drop for Doorbell {
    fn drop(&mut self) {
        self.rx = None;
        if let Ok(mut bells) = self.hub.bells.lock() {
            if bells
                .get(&self.token)
                .is_some_and(|tx| tx.receiver_count() == 0)
            {
                bells.remove(&self.token);
            }
        }
    }
}

/// One admitted socket. Dropping it gives the slot back.
pub struct SocketSlot {
    hub: Arc<Hub>,
    ip: IpAddr,
}

impl Drop for SocketSlot {
    fn drop(&mut self) {
        if let Ok(mut sockets) = self.hub.sockets.lock() {
            sockets.total = sockets.total.saturating_sub(1);
            if let Some(n) = sockets.per_ip.get_mut(&self.ip) {
                *n = n.saturating_sub(1);
                if *n == 0 {
                    sockets.per_ip.remove(&self.ip);
                }
            }
        }
    }
}

impl Hub {
    pub fn subscribe(self: &Arc<Self>, token: &str) -> Doorbell {
        let rx = self.bells.lock().ok().map(|mut bells| {
            bells
                .entry(token.to_string())
                .or_insert_with(|| watch::channel(0).0)
                .subscribe()
        });
        Doorbell {
            hub: Arc::clone(self),
            token: token.to_string(),
            rx,
        }
    }

    pub fn ring(&self, token: &str) {
        if let Ok(bells) = self.bells.lock() {
            if let Some(tx) = bells.get(token) {
                tx.send_modify(|n| *n = n.wrapping_add(1));
            }
        }
    }

    /// Admits a socket unless this address or the whole relay is at its ceiling.
    pub fn admit(
        self: &Arc<Self>,
        ip: IpAddr,
        max_per_ip: usize,
        max_total: usize,
    ) -> Option<SocketSlot> {
        let mut sockets = self.sockets.lock().ok()?;
        let held = sockets.per_ip.get(&ip).copied().unwrap_or(0);
        if held >= max_per_ip || sockets.total >= max_total {
            return None;
        }
        sockets.per_ip.insert(ip, held + 1);
        sockets.total += 1;
        Some(SocketSlot {
            hub: Arc::clone(self),
            ip,
        })
    }

    #[cfg(test)]
    fn tracked_tokens(&self) -> usize {
        self.bells.lock().map(|b| b.len()).unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn a_burst_coalesces_and_every_device_hears_it() {
        let hub = Arc::new(Hub::default());
        let mut a = hub.subscribe("t");
        let mut b = hub.subscribe("t");
        hub.ring("t");
        hub.ring("t");
        assert!(a.rung().await);
        assert!(b.rung().await);
        let again = tokio::time::timeout(std::time::Duration::from_millis(20), a.rung()).await;
        assert!(again.is_err(), "two rings before a read count as one");
    }

    #[test]
    fn the_last_doorbell_forgets_the_token() {
        let hub = Arc::new(Hub::default());
        let a = hub.subscribe("t");
        let b = hub.subscribe("t");
        drop(a);
        assert_eq!(hub.tracked_tokens(), 1);
        drop(b);
        assert_eq!(hub.tracked_tokens(), 0);
    }

    #[test]
    fn ceilings_hold_and_slots_come_back() {
        let hub = Arc::new(Hub::default());
        let ip: IpAddr = "203.0.113.1".parse().unwrap();
        let other: IpAddr = "203.0.113.2".parse().unwrap();
        let first = hub.admit(ip, 1, 2).expect("first");
        assert!(hub.admit(ip, 1, 2).is_none(), "per-address ceiling");
        let _second = hub.admit(other, 1, 2).expect("other address");
        assert!(
            hub.admit("203.0.113.3".parse().unwrap(), 1, 2).is_none(),
            "global ceiling"
        );
        drop(first);
        assert!(hub.admit(ip, 1, 2).is_some(), "slot returned");
    }
}
