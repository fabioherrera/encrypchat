//! Tokio TCP P2P node: dial by multiaddr, EH02 mutual handshake, encrypted length-prefixed
//! records.
//!
//! Phase 4 uses Tokio TCP (+ `inject_peer` / `connect_multiaddr` for tests and manual dial).
//! libp2p request-response was attempted but hit persistent `ConnectionClosed` races on
//! loopback dual-node tests; see `docs/phase-4.md`. LAN mDNS can be layered later.
//!
//! Networking carries E2EE ciphertext only — callers encrypt before [`NodeHandle::send_to_token`].
//! Peer offline / unknown → [`CoreError::PeerOffline`] (no relay).
//! Peer authenticity: **EH02** ([`crate::handshake`]) — a static-static Diffie-Hellman proof
//! that cannot be built from the victim's public key, unlike the EH01 it replaces.
//! Pre-auth exposure is bounded: [`HANDSHAKE_TIMEOUT`], [`MAX_PENDING_HANDSHAKES`]
//! concurrent unauthenticated connections, [`MAX_PREAUTH_LEN`] buffers.
//!
//! Once the handshake is done the whole transport is encrypted under a session key derived
//! from it ([`crate::transport`], F-15): the `EC04` header travels inside the AEAD, so an
//! observer sees a length prefix and opaque bytes rather than `sender_token`. What is left on
//! the wire is size above the padding floor, volume and timing. See `docs/threat-model.md` §6.2.
//!
//! Post-authentication exposure is bounded too, and in bytes rather than in messages
//! ([`InboundBudget`], F-9): an authenticated peer is one that generated a keypair, which
//! costs nothing, so what it can make the device hold has to be capped per connection
//! ([`MAX_INBOUND_BYTES_PER_PEER`]) and for the node as a whole ([`MAX_INBOUND_BYTES_TOTAL`]).

use std::collections::{HashMap, HashSet};
use std::net::SocketAddr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::mpsc::{self as std_mpsc, Receiver as StdReceiver, SyncSender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use multiaddr::{Multiaddr, Protocol};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};
use tokio::sync::{oneshot, Mutex as AsyncMutex, Semaphore};
use zeroize::Zeroizing;

use crate::error::CoreError;
use crate::frame::decode_frame;
use crate::handshake::{
    challenge_bytes, hello_bytes, initiator_proof, initiator_session_keys, new_nonce,
    parse_challenge, parse_hello, responder_proof, responder_session_keys, verify_initiator_proof,
    verify_responder_proof, Ephemeral, Transcript, EH02_CHALLENGE_LEN, EH02_HELLO_LEN,
    EH02_NONCE_LEN,
};
use crate::identity::Identity;
use crate::token::Token;
use crate::transport::{RecvCipher, SendCipher, PAD_FLOOR, TRANSPORT_OVERHEAD};

const MAX_FRAME_LEN: usize = 16 * 1024 * 1024;
const MSG_DATA: u8 = 1;
const MSG_ACK: u8 = 2;

/// Budget for a full EH02 exchange; on expiry the peer is treated as unauthenticated.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
/// Inbound connections allowed to sit in the handshake at once.
const MAX_PENDING_HANDSHAKES: usize = 32;
/// Buffer cap for anything read before the peer is authenticated. Post-handshake
/// data frames keep the [`MAX_FRAME_LEN`] budget.
const MAX_PREAUTH_LEN: usize = 4 * 1024;

/// Frames the caller may leave undrained. This is the *count* bound; it is what keeps a flood
/// of tiny records from becoming a flood of allocations, and it says nothing about size —
/// that is [`MAX_INBOUND_BYTES_TOTAL`]'s job.
const INBOUND_QUEUE_SLOTS: usize = 256;

/// Inbound bytes one connection may keep resident while the caller has not drained them.
///
/// Two maximum-sized frames: one being handed over and one arriving behind it, so a media
/// transfer never waits on itself. Anything smaller would stall back-to-back attachments;
/// anything larger buys nothing, because a peer only has one send in flight at a time
/// (`pending_ack`) and the caller drains the whole queue on every poll.
const MAX_INBOUND_BYTES_PER_PEER: usize = 2 * MAX_FRAME_LEN;

/// The same budget for the node as a whole, and the number that actually bounds the process.
///
/// A per-connection cap alone multiplies by the number of sessions an attacker opens, and
/// opening one only costs generating a keypair, so the global ceiling is the defensible one.
/// 64 MiB is sized for the smallest target rather than the largest: a low-end Android process
/// gets a couple of hundred MiB for *everything* — Dart heap, decoded images, the core — so
/// this is a share it can lose to undrained network data and survive. It is also only
/// reachable while the caller has stopped draining: the client polls every 400 ms and empties
/// the queue each time, so the steady-state occupancy of a healthy device is zero.
const MAX_INBOUND_BYTES_TOTAL: usize = 4 * MAX_FRAME_LEN;

/// A frame that does not fit must be able to fit *eventually*, or the connection would stall
/// to death on traffic the wire explicitly allows.
const _: () = assert!(MAX_INBOUND_BYTES_PER_PEER >= MAX_FRAME_LEN + TRANSPORT_OVERHEAD + PAD_FLOOR);
const _: () = assert!(MAX_INBOUND_BYTES_TOTAL >= MAX_INBOUND_BYTES_PER_PEER);

/// Records at or below one padded record are not charged against the budget.
///
/// Every ACK is exactly this size, and so is a short message — that is the point of the
/// padding floor. Charging them would let a backlog of *data* delay the ACKs of our own
/// sends, which is a way of turning one congested direction into two. What they can cost is
/// bounded by the count instead: [`INBOUND_QUEUE_SLOTS`] × this, about 133 KiB node-wide.
const INBOUND_FREE_RECORD_LEN: usize = PAD_FLOOR + TRANSPORT_OVERHEAD;

/// How long a connection may wait for room before it is dropped.
///
/// Half of the sender's own ACK budget (10 s in [`Command::Send`]), so a frame admitted after
/// waiting still has time to be acknowledged inside the window the sender is willing to wait.
/// Waiting longer would hold memory for a peer that already gave up.
const INBOUND_STALL_TIMEOUT: Duration = Duration::from_secs(5);

/// Re-check interval while a connection is waiting for room.
///
/// Polling rather than a notifier because the release happens in [`NodeHandle::try_recv`], on
/// the caller's own thread, which is not a runtime thread. This only runs on a connection that
/// is already saturated, and 25 ms is well under the 400 ms poll of the client.
const INBOUND_DRAIN_POLL: Duration = Duration::from_millis(25);

/// Stable peer handle for tests / dial bookkeeping (equals the Encrypchat token).
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct PeerId(String);

impl PeerId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for PeerId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

enum Command {
    Send {
        token: String,
        frame: Vec<u8>,
        reply: SyncSender<Result<(), CoreError>>,
    },
    KnownPeers {
        reply: SyncSender<Vec<String>>,
    },
    InjectPeer {
        token: String,
        addr: SocketAddr,
        reply: SyncSender<Result<(), CoreError>>,
    },
    Connect {
        addr: SocketAddr,
        reply: SyncSender<Result<(), CoreError>>,
    },
    Stop,
}

struct ReadyInfo {
    listen_addr: SocketAddr,
}

/// Resolves the caller blocked in [`NodeHandle::send_to_token`] once the peer ACKs.
type AckSender = oneshot::Sender<Result<(), CoreError>>;

/// Locally blocked tokens, shared with the node task and replaced wholesale by
/// [`NodeHandle::set_blocked_tokens`] while the node is running.
type BlockedTokens = Arc<Mutex<HashSet<String>>>;

/// Blocklist membership test for an already-authenticated token.
///
/// A poisoned lock fails closed (reports "blocked"): a safety control must not become a
/// no-op because something else panicked. The critical sections here only touch a
/// `HashSet`, so poisoning is not reachable in practice.
fn is_blocked(blocked: &BlockedTokens, token: &str) -> bool {
    match blocked.lock() {
        Ok(guard) => guard.contains(token),
        Err(_) => true,
    }
}

/// A frame waiting for [`NodeHandle::try_recv`], carrying the budget it is spending.
///
/// The permit is released when this is destructured on the way out, so "queued" and
/// "accounted" cannot drift: dropping the whole queue (node stop, disconnected caller) frees
/// exactly as much as draining it would.
struct InboundFrame {
    bytes: Vec<u8>,
    _permit: InboundPermit,
}

/// Node-wide inbound plumbing: the queue the caller drains, and the byte counter shared by
/// every connection feeding it.
#[derive(Clone)]
struct InboundSink {
    tx: SyncSender<InboundFrame>,
    queued_bytes: Arc<AtomicUsize>,
}

impl InboundSink {
    fn new(tx: SyncSender<InboundFrame>) -> Self {
        Self {
            tx,
            queued_bytes: Arc::new(AtomicUsize::new(0)),
        }
    }

    /// One connection's view: same queue and same global counter, plus a share counter that
    /// dies with the connection.
    fn for_connection(&self) -> ConnInbound {
        ConnInbound {
            tx: self.tx.clone(),
            budget: InboundBudget {
                total: Arc::clone(&self.queued_bytes),
                peer: Arc::new(AtomicUsize::new(0)),
            },
        }
    }
}

/// What a single reader loop is allowed to put in the queue.
struct ConnInbound {
    tx: SyncSender<InboundFrame>,
    budget: InboundBudget,
}

/// Two counters, both of which have to have room: the connection's share and the node's total.
///
/// A peer that reconnects gets a fresh `peer` counter, but whatever it left queued is still on
/// `total`, which is why the global one is the bound that matters (F-9).
struct InboundBudget {
    total: Arc<AtomicUsize>,
    peer: Arc<AtomicUsize>,
}

impl InboundBudget {
    /// Take `len` bytes from both counters, or neither.
    ///
    /// `fetch_update` and not load-then-add: two connections reserving at once must not both
    /// see the same free space and both take it.
    fn try_reserve(&self, len: usize) -> Option<InboundPermit> {
        let fits = |cap: usize| {
            move |cur: usize| {
                let next = cur.saturating_add(len);
                (next <= cap).then_some(next)
            }
        };
        self.total
            .fetch_update(
                Ordering::AcqRel,
                Ordering::Acquire,
                fits(MAX_INBOUND_BYTES_TOTAL),
            )
            .ok()?;
        if self
            .peer
            .fetch_update(
                Ordering::AcqRel,
                Ordering::Acquire,
                fits(MAX_INBOUND_BYTES_PER_PEER),
            )
            .is_err()
        {
            self.total.fetch_sub(len, Ordering::AcqRel);
            return None;
        }
        Some(InboundPermit {
            len,
            total: Arc::clone(&self.total),
            peer: Arc::clone(&self.peer),
        })
    }

    /// [`Self::try_reserve`], waiting up to `grace` for the caller to drain.
    ///
    /// Backpressure rather than dropping: nothing has been read off the socket yet, so the
    /// kernel window closes on the sender and an honest peer that briefly outran a busy UI
    /// gets its frame through instead of a silent loss. `None` means the wait ran out and the
    /// caller should close the connection.
    async fn reserve_within(&self, len: usize, grace: Duration) -> Option<InboundPermit> {
        let deadline = Instant::now() + grace;
        loop {
            if let Some(permit) = self.try_reserve(len) {
                return Some(permit);
            }
            if Instant::now() >= deadline {
                return None;
            }
            tokio::time::sleep(INBOUND_DRAIN_POLL).await;
        }
    }
}

/// Bytes reserved for one inbound frame, returned to both counters on drop.
struct InboundPermit {
    len: usize,
    total: Arc<AtomicUsize>,
    peer: Arc<AtomicUsize>,
}

impl Drop for InboundPermit {
    fn drop(&mut self) {
        self.total.fetch_sub(self.len, Ordering::AcqRel);
        self.peer.fetch_sub(self.len, Ordering::AcqRel);
    }
}

/// What one record on the wire costs against the budget. See [`INBOUND_FREE_RECORD_LEN`].
fn inbound_charge(record_len: usize) -> usize {
    if record_len > INBOUND_FREE_RECORD_LEN {
        record_len
    } else {
        0
    }
}

/// Socket half plus the sealing state of this direction.
///
/// They live behind the same mutex on purpose: the counter that becomes the AEAD nonce and
/// the bytes on the socket have to advance together, or two concurrent senders (a data frame
/// and an ACK) would swap places and the peer would reject both.
struct EncryptedWriter {
    half: tokio::net::tcp::OwnedWriteHalf,
    cipher: SendCipher,
}

impl EncryptedWriter {
    async fn send(&mut self, kind: u8, payload: &[u8]) -> Result<(), CoreError> {
        if payload.len() > MAX_FRAME_LEN {
            return Err(CoreError::InvalidFrame);
        }
        let record = self.cipher.seal(kind, payload)?;
        self.half
            .write_all(&record)
            .await
            .map_err(|_| CoreError::PeerOffline)?;
        self.half.flush().await.map_err(|_| CoreError::PeerOffline)
    }
}

struct PeerConn {
    writer: Arc<AsyncMutex<EncryptedWriter>>,
    /// At most one in-flight send ACK waiter per peer (Phase 4).
    pending_ack: Arc<AsyncMutex<Option<AckSender>>>,
}

#[derive(Clone, Copy)]
enum HandshakeRole {
    Dialer,
    Acceptor,
}

/// Running node handle with an embedded Tokio runtime (FFI-friendly).
pub struct NodeHandle {
    _rt: tokio::runtime::Runtime,
    local_token: String,
    peer_id: PeerId,
    listen_addrs: Arc<Mutex<Vec<Multiaddr>>>,
    cmd_tx: UnboundedSender<Command>,
    inbound_rx: Mutex<StdReceiver<InboundFrame>>,
    blocked: BlockedTokens,
}

impl NodeHandle {
    /// Start listening on TCP `listen_port` (0 = ephemeral). Binds `0.0.0.0` and
    /// advertises `127.0.0.1:<port>` for same-host dials (CI / inject_peer).
    ///
    /// The identity secret is kept in a single [`Zeroizing`] allocation shared with the node
    /// task, so the session-long copy is wiped when the runtime shuts down. Accepts a bare
    /// `[u8; 32]` or an already-wrapped secret.
    pub fn start(
        secret: impl Into<Zeroizing<[u8; 32]>>,
        listen_port: u16,
    ) -> Result<Self, CoreError> {
        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .thread_name("encrypchat-net")
            .build()
            .map_err(|_| CoreError::Internal)?;

        let secret = secret.into();
        let identity = Identity::from_secret_bytes(*secret);
        let local_token = identity.token().as_str().to_string();
        let peer_id = PeerId(local_token.clone());
        // One shared, zeroizing copy for the whole session; handshake tasks borrow it.
        let secret = Arc::new(secret);

        let (cmd_tx, cmd_rx) = unbounded_channel();
        let (inbound_tx, inbound_rx) = std_mpsc::sync_channel(INBOUND_QUEUE_SLOTS);
        let (ready_tx, ready_rx) = std_mpsc::sync_channel(1);
        let listen_addrs = Arc::new(Mutex::new(Vec::new()));
        let listen_addrs_task = Arc::clone(&listen_addrs);
        let blocked: BlockedTokens = Arc::new(Mutex::new(HashSet::new()));
        let blocked_task = Arc::clone(&blocked);

        rt.spawn(async move {
            let _ = run_node(
                secret,
                listen_port,
                cmd_rx,
                inbound_tx,
                ready_tx,
                listen_addrs_task,
                blocked_task,
            )
            .await;
        });

        let ready = ready_rx
            .recv_timeout(Duration::from_secs(5))
            .map_err(|_| CoreError::Internal)?;

        if let Ok(mut guard) = listen_addrs.lock() {
            *guard = vec![socket_to_multiaddr(ready.listen_addr)];
        }

        Ok(Self {
            _rt: rt,
            local_token,
            peer_id,
            listen_addrs,
            cmd_tx,
            inbound_rx: Mutex::new(inbound_rx),
            blocked,
        })
    }

    pub fn local_token(&self) -> String {
        self.local_token.clone()
    }

    /// Replace the blocklist with `tokens`.
    ///
    /// The whole set is swapped, so an empty slice clears it and there is no add/remove to
    /// keep in sync with the caller's own state. Entries are validated and normalised with
    /// [`Token::parse`] (trim + lowercase), so casing cannot be used as a bypass; a single
    /// malformed entry fails the call with [`CoreError::InvalidToken`] and leaves the
    /// previous set untouched rather than silently skipping it.
    ///
    /// Takes effect immediately: new sessions are refused after EH02, the next inbound
    /// frame from a live blocked session closes it, and sends are refused.
    pub fn set_blocked_tokens(&self, tokens: &[&str]) -> Result<(), CoreError> {
        let mut next = HashSet::with_capacity(tokens.len());
        for raw in tokens {
            next.insert(Token::parse(raw)?.as_str().to_string());
        }
        let mut guard = self.blocked.lock().map_err(|_| CoreError::Internal)?;
        *guard = next;
        Ok(())
    }

    pub fn peer_id(&self) -> PeerId {
        self.peer_id.clone()
    }

    pub fn listen_addrs(&self) -> Vec<Multiaddr> {
        self.listen_addrs
            .lock()
            .map(|g| g.clone())
            .unwrap_or_default()
    }

    /// Send an opaque wire frame to a discovered (or injected) peer token.
    pub fn send_to_token(&self, token: &str, frame: Vec<u8>) -> Result<(), CoreError> {
        // Defence in depth: the UI already withholds sends to blocked contacts. Normalise
        // first so a differently-cased token cannot slip past the set.
        if let Ok(parsed) = Token::parse(token) {
            if is_blocked(&self.blocked, parsed.as_str()) {
                return Err(CoreError::PeerBlocked);
            }
        }
        let (tx, rx) = std_mpsc::sync_channel(1);
        self.cmd_tx
            .send(Command::Send {
                token: token.to_string(),
                frame,
                reply: tx,
            })
            .map_err(|_| CoreError::Internal)?;
        rx.recv_timeout(Duration::from_secs(15))
            .map_err(|_| CoreError::PeerOffline)?
    }

    /// Non-blocking poll for an inbound frame.
    ///
    /// Taking a frame out is also what gives its bytes back to [`InboundBudget`], so a caller
    /// that stops polling is throttling its own peers rather than growing the queue.
    pub fn try_recv(&self) -> Option<Vec<u8>> {
        self.inbound_rx
            .lock()
            .ok()
            .and_then(|rx| rx.try_recv().ok())
            .map(|frame| frame.bytes)
    }

    /// Tokens of currently registered peers.
    ///
    /// A dead command loop and a 2 s query timeout both surface as
    /// [`CoreError::Internal`]; neither may be reported as "zero peers", or callers cannot
    /// tell an idle node from an unresponsive one.
    pub fn known_peers(&self) -> Result<Vec<String>, CoreError> {
        let (tx, rx) = std_mpsc::sync_channel(1);
        self.cmd_tx
            .send(Command::KnownPeers { reply: tx })
            .map_err(|_| CoreError::Internal)?;
        rx.recv_timeout(Duration::from_secs(2))
            .map_err(|_| CoreError::Internal)
    }

    /// Test / manual helper: map `token` → address and dial.
    pub fn inject_peer(
        &self,
        token: &str,
        _peer_id: PeerId,
        addr: Multiaddr,
    ) -> Result<(), CoreError> {
        let sock = multiaddr_to_socket(&addr).ok_or(CoreError::Internal)?;
        let (tx, rx) = std_mpsc::sync_channel(1);
        self.cmd_tx
            .send(Command::InjectPeer {
                token: token.to_string(),
                addr: sock,
                reply: tx,
            })
            .map_err(|_| CoreError::Internal)?;
        rx.recv_timeout(Duration::from_secs(10))
            .map_err(|_| CoreError::Internal)?
    }

    pub fn connect_multiaddr(&self, addr: Multiaddr) -> Result<(), CoreError> {
        let sock = multiaddr_to_socket(&addr).ok_or(CoreError::Internal)?;
        let (tx, rx) = std_mpsc::sync_channel(1);
        self.cmd_tx
            .send(Command::Connect {
                addr: sock,
                reply: tx,
            })
            .map_err(|_| CoreError::Internal)?;
        rx.recv_timeout(Duration::from_secs(10))
            .map_err(|_| CoreError::Internal)?
    }

    pub fn stop(self) {
        let _ = self.cmd_tx.send(Command::Stop);
        drop(self._rt);
    }
}

fn socket_to_multiaddr(addr: SocketAddr) -> Multiaddr {
    let mut ma = Multiaddr::empty();
    match addr {
        SocketAddr::V4(v4) => {
            ma.push(Protocol::Ip4(*v4.ip()));
            ma.push(Protocol::Tcp(v4.port()));
        }
        SocketAddr::V6(v6) => {
            ma.push(Protocol::Ip6(*v6.ip()));
            ma.push(Protocol::Tcp(v6.port()));
        }
    }
    ma
}

fn multiaddr_to_socket(addr: &Multiaddr) -> Option<SocketAddr> {
    let mut ip = None;
    let mut port = None;
    for p in addr.iter() {
        match p {
            Protocol::Ip4(v4) => ip = Some(std::net::IpAddr::V4(v4)),
            Protocol::Ip6(v6) => ip = Some(std::net::IpAddr::V6(v6)),
            Protocol::Tcp(p) => port = Some(p),
            _ => {}
        }
    }
    Some(SocketAddr::new(ip?, port?))
}

/// Read one encrypted record of an established session.
///
/// The length prefix is the only cleartext left on the wire, and it is bounded before a
/// single byte is allocated. Everything after it goes through the session cipher, so a
/// record that is not the next one of this session never reaches the caller.
///
/// The budget is charged on the *declared* length, before the body is read, so an
/// over-budget peer never gets the allocation in the first place; the returned permit covers
/// the record and the plaintext it yields, and lives until the caller drains it. Failing to
/// get one within [`INBOUND_STALL_TIMEOUT`] is reported as [`CoreError::PeerOffline`] — from
/// this node's point of view a peer it can no longer take data from is exactly that.
async fn read_msg(
    reader: &mut (impl AsyncReadExt + Unpin),
    cipher: &mut RecvCipher,
    budget: &InboundBudget,
) -> Result<(u8, Vec<u8>, InboundPermit), CoreError> {
    let mut len_buf = [0u8; 4];
    reader
        .read_exact(&mut len_buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    let len = u32::from_be_bytes(len_buf) as usize;
    if len == 0 || len > MAX_FRAME_LEN + TRANSPORT_OVERHEAD + PAD_FLOOR {
        return Err(CoreError::InvalidFrame);
    }
    let permit = budget
        .reserve_within(inbound_charge(len), INBOUND_STALL_TIMEOUT)
        .await
        .ok_or(CoreError::PeerOffline)?;
    let mut buf = vec![0u8; len];
    reader
        .read_exact(&mut buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    let (kind, payload) = cipher.open(&buf)?;
    Ok((kind, payload, permit))
}

async fn write_hello(
    writer: &mut (impl AsyncWriteExt + Unpin),
    eph_pub: &[u8; 32],
    nonce_i: &[u8; EH02_NONCE_LEN],
) -> Result<(), CoreError> {
    writer
        .write_all(&hello_bytes(eph_pub, nonce_i))
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer.flush().await.map_err(|_| CoreError::PeerOffline)?;
    Ok(())
}

async fn read_hello(
    reader: &mut (impl AsyncReadExt + Unpin),
) -> Result<([u8; 32], [u8; EH02_NONCE_LEN]), CoreError> {
    let mut buf = [0u8; EH02_HELLO_LEN];
    reader
        .read_exact(&mut buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    parse_hello(&buf)
}

async fn write_challenge(
    writer: &mut (impl AsyncWriteExt + Unpin),
    eph_pub: &[u8; 32],
    nonce_r: &[u8; EH02_NONCE_LEN],
) -> Result<(), CoreError> {
    writer
        .write_all(&challenge_bytes(eph_pub, nonce_r))
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer.flush().await.map_err(|_| CoreError::PeerOffline)?;
    Ok(())
}

async fn read_challenge(
    reader: &mut (impl AsyncReadExt + Unpin),
) -> Result<([u8; 32], [u8; EH02_NONCE_LEN]), CoreError> {
    let mut buf = [0u8; EH02_CHALLENGE_LEN];
    reader
        .read_exact(&mut buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    parse_challenge(&buf)
}

async fn write_proof(
    writer: &mut (impl AsyncWriteExt + Unpin),
    ciphertext: &[u8],
) -> Result<(), CoreError> {
    if ciphertext.is_empty() || ciphertext.len() > MAX_PREAUTH_LEN {
        return Err(CoreError::AuthFailed);
    }
    writer
        .write_all(&(ciphertext.len() as u32).to_be_bytes())
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer
        .write_all(ciphertext)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer.flush().await.map_err(|_| CoreError::PeerOffline)?;
    Ok(())
}

async fn read_proof(reader: &mut (impl AsyncReadExt + Unpin)) -> Result<Vec<u8>, CoreError> {
    let mut len_buf = [0u8; 4];
    reader
        .read_exact(&mut len_buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    let len = u32::from_be_bytes(len_buf) as usize;
    if len == 0 || len > MAX_PREAUTH_LEN {
        return Err(CoreError::AuthFailed);
    }
    let mut buf = vec![0u8; len];
    reader
        .read_exact(&mut buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    Ok(buf)
}

/// Name an authenticated peer.
///
/// Fallible because the key arrived from the wire: [`crate::handshake`] already refuses a
/// non-canonical one, and this is the second half of the same rule rather than a new check —
/// a peer must not be able to choose which of several tokens it is seen under (F-10).
fn token_of(pubkey: &[u8; 32]) -> Result<String, CoreError> {
    Ok(Token::from_public_key_bytes(pubkey)?.as_str().to_string())
}

/// Run EH02 and return the peer's **authenticated** token.
///
/// `blocked` is consulted by the acceptor between messages 3 and 4, which is the only place
/// it can be: the token is not trustworthy before message 3, and after message 4 the node
/// has already told a blocked peer who it is. [`register_peer`] checks it again — that is
/// the funnel for all three session paths, this one is what keeps a blocked peer from
/// learning the local identity.
async fn open_peer_session(
    stream: TcpStream,
    local_secret: &[u8; 32],
    expected_remote: Option<&str>,
    role: HandshakeRole,
    blocked: Option<&BlockedTokens>,
) -> Result<(String, PeerConn, tokio::net::tcp::OwnedReadHalf, RecvCipher), CoreError> {
    let local = Identity::from_secret_bytes(*local_secret);
    let local_secret_key = local.static_secret();

    let (mut reader, mut writer) = stream.into_split();

    // The ephemeral secret stays on this stack and dies with the handshake: that is what
    // makes the session key forward secret.
    let (remote_token, keys) = match role {
        HandshakeRole::Dialer => {
            let eph = Ephemeral::generate();
            let nonce_i = new_nonce();
            write_hello(&mut writer, &eph.public, &nonce_i).await?;
            let (responder_eph, nonce_r) = read_challenge(&mut reader).await?;

            let transcript = Transcript {
                initiator_eph: eph.public,
                responder_eph,
                nonce_i,
                nonce_r,
            };
            let proof = initiator_proof(&local_secret_key, &transcript)?;
            write_proof(&mut writer, &proof).await?;

            let their_proof = read_proof(&mut reader).await?;
            let remote_pub = verify_responder_proof(&local_secret_key, &transcript, &their_proof)?;
            let remote_token = token_of(&remote_pub)?;
            if let Some(expected) = expected_remote {
                if remote_token != expected {
                    return Err(CoreError::AuthFailed);
                }
            }
            let keys =
                initiator_session_keys(&local_secret_key, &eph.secret, &remote_pub, &transcript)?;
            (remote_token, keys)
        }
        HandshakeRole::Acceptor => {
            let (initiator_eph, nonce_i) = read_hello(&mut reader).await?;
            let eph = Ephemeral::generate();
            let nonce_r = new_nonce();
            write_challenge(&mut writer, &eph.public, &nonce_r).await?;

            let transcript = Transcript {
                initiator_eph,
                responder_eph: eph.public,
                nonce_i,
                nonce_r,
            };
            let their_proof = read_proof(&mut reader).await?;
            let remote_pub = verify_initiator_proof(&eph.secret, &transcript, &their_proof)?;
            let remote_token = token_of(&remote_pub)?;

            if let Some(expected) = expected_remote {
                if remote_token != expected {
                    return Err(CoreError::AuthFailed);
                }
            }
            if let Some(blocked) = blocked {
                if is_blocked(blocked, &remote_token) {
                    return Err(CoreError::PeerBlocked);
                }
            }

            let proof = responder_proof(&local_secret_key, &remote_pub, &transcript)?;
            write_proof(&mut writer, &proof).await?;
            let keys =
                responder_session_keys(&local_secret_key, &eph.secret, &remote_pub, &transcript)?;
            (remote_token, keys)
        }
    };

    let conn = PeerConn {
        writer: Arc::new(AsyncMutex::new(EncryptedWriter {
            half: writer,
            cipher: SendCipher::new(keys.send),
        })),
        pending_ack: Arc::new(AsyncMutex::new(None)),
    };
    Ok((remote_token, conn, reader, RecvCipher::new(keys.recv)))
}

/// [`open_peer_session`] under a wall-clock budget: a peer that stalls mid-EH02
/// is dropped as [`CoreError::AuthFailed`] instead of holding memory and fds.
async fn open_peer_session_within(
    budget: Duration,
    stream: TcpStream,
    local_secret: &[u8; 32],
    expected_remote: Option<&str>,
    role: HandshakeRole,
    blocked: Option<&BlockedTokens>,
) -> Result<(String, PeerConn, tokio::net::tcp::OwnedReadHalf, RecvCipher), CoreError> {
    match tokio::time::timeout(
        budget,
        open_peer_session(stream, local_secret, expected_remote, role, blocked),
    )
    .await
    {
        Ok(res) => res,
        Err(_) => Err(CoreError::AuthFailed),
    }
}

async fn reader_loop(
    mut reader: tokio::net::tcp::OwnedReadHalf,
    mut cipher: RecvCipher,
    conn: PeerConn,
    inbound: ConnInbound,
    authenticated_token: String,
    peers: Arc<AsyncMutex<HashMap<String, PeerConn>>>,
    blocked: BlockedTokens,
) {
    loop {
        match read_msg(&mut reader, &mut cipher, &inbound.budget).await {
            Ok((MSG_DATA, frame, permit)) => {
                // Blocked after the session was established: close instead of queueing.
                if is_blocked(&blocked, &authenticated_token) {
                    break;
                }
                match decode_frame(&frame) {
                    Ok(wf) if wf.sender_token == authenticated_token => {
                        let queued = InboundFrame {
                            bytes: frame,
                            _permit: permit,
                        };
                        if inbound.tx.try_send(queued).is_err() {
                            // Inbound queue full by count: the frame is gone (and its budget
                            // with it), so withhold the ACK rather than let the sender mark
                            // it delivered.
                            continue;
                        }
                        let mut w = conn.writer.lock().await;
                        if w.send(MSG_ACK, &[]).await.is_err() {
                            break;
                        }
                    }
                    // Spoofed sender_token or invalid frame: drop without ACK, disconnect.
                    _ => break,
                }
            }
            Ok((MSG_ACK, _, _)) => {
                if let Some(tx) = conn.pending_ack.lock().await.take() {
                    let _ = tx.send(Ok(()));
                }
            }
            Ok(_) | Err(_) => break,
        }
    }
    if let Some(tx) = conn.pending_ack.lock().await.take() {
        let _ = tx.send(Err(CoreError::PeerOffline));
    }
    // Unregister so reconnect / re-handshake is possible (pin-first while live only).
    let mut guard = peers.lock().await;
    if let Some(existing) = guard.get(&authenticated_token) {
        if Arc::ptr_eq(&existing.writer, &conn.writer) {
            guard.remove(&authenticated_token);
        }
    }
}

/// Pin-first while live: reject a new connection if `remote` is already registered.
/// `reader_loop` unregisters on exit so reconnect works after disconnect.
///
/// Single funnel for all three session paths (dial, inject, accept), so it is also where the
/// blocklist is enforced and where each connection is given its share of the inbound budget.
async fn register_peer(
    peers: &Arc<AsyncMutex<HashMap<String, PeerConn>>>,
    remote: String,
    conn: PeerConn,
    reader: tokio::net::tcp::OwnedReadHalf,
    cipher: RecvCipher,
    inbound: &InboundSink,
    blocked: &BlockedTokens,
) -> Result<(), CoreError> {
    // Authorisation happens here and not earlier because `remote` is only trustworthy once
    // EH02 proved key possession. A blocked peer therefore still costs a full handshake.
    if is_blocked(blocked, &remote) {
        // Dropping `conn` and `reader` closes the socket.
        return Err(CoreError::PeerBlocked);
    }
    {
        let mut guard = peers.lock().await;
        if guard.contains_key(&remote) {
            // Drop new connection; keep existing peer binding.
            return Ok(());
        }
        guard.insert(
            remote.clone(),
            PeerConn {
                writer: Arc::clone(&conn.writer),
                pending_ack: Arc::clone(&conn.pending_ack),
            },
        );
    }
    let peers = Arc::clone(peers);
    tokio::spawn(reader_loop(
        reader,
        cipher,
        conn,
        inbound.for_connection(),
        remote,
        peers,
        Arc::clone(blocked),
    ));
    Ok(())
}

async fn run_node(
    local_secret: Arc<Zeroizing<[u8; 32]>>,
    listen_port: u16,
    mut cmd_rx: UnboundedReceiver<Command>,
    inbound_tx: SyncSender<InboundFrame>,
    ready_tx: SyncSender<ReadyInfo>,
    listen_addrs_shared: Arc<Mutex<Vec<Multiaddr>>>,
    blocked: BlockedTokens,
) -> Result<(), CoreError> {
    let inbound = InboundSink::new(inbound_tx);
    let listener = TcpListener::bind(SocketAddr::from(([0, 0, 0, 0], listen_port)))
        .await
        .map_err(|_| CoreError::Internal)?;
    let listen_addr = listener.local_addr().map_err(|_| CoreError::Internal)?;
    // Advertise loopback so same-host inject/dial works when bound on 0.0.0.0.
    let advertise = SocketAddr::from(([127, 0, 0, 1], listen_addr.port()));
    if let Ok(mut guard) = listen_addrs_shared.lock() {
        *guard = vec![socket_to_multiaddr(advertise)];
    }
    let _ = ready_tx.send(ReadyInfo {
        listen_addr: advertise,
    });

    let peers: Arc<AsyncMutex<HashMap<String, PeerConn>>> =
        Arc::new(AsyncMutex::new(HashMap::new()));
    let handshake_slots = Arc::new(Semaphore::new(MAX_PENDING_HANDSHAKES));

    loop {
        tokio::select! {
            cmd = cmd_rx.recv() => {
                match cmd {
                    None | Some(Command::Stop) => break,
                    Some(Command::KnownPeers { reply }) => {
                        let guard = peers.lock().await;
                        let mut list: Vec<String> = guard.keys().cloned().collect();
                        list.sort();
                        let _ = reply.send(list);
                    }
                    Some(Command::Connect { addr, reply }) => {
                        let res = match TcpStream::connect(addr).await {
                            Ok(stream) => {
                                match open_peer_session_within(
                                    HANDSHAKE_TIMEOUT,
                                    stream,
                                    &local_secret,
                                    None,
                                    HandshakeRole::Dialer,
                                    None,
                                )
                                .await
                                {
                                    Ok((remote, conn, reader, cipher)) => {
                                        register_peer(
                                            &peers,
                                            remote,
                                            conn,
                                            reader,
                                            cipher,
                                            &inbound,
                                            &blocked,
                                        )
                                        .await
                                    }
                                    Err(e) => Err(e),
                                }
                            }
                            Err(_) => Err(CoreError::PeerOffline),
                        };
                        let _ = reply.send(res);
                    }
                    Some(Command::InjectPeer { token, addr, reply }) => {
                        let res = match TcpStream::connect(addr).await {
                            Ok(stream) => {
                                match open_peer_session_within(
                                    HANDSHAKE_TIMEOUT,
                                    stream,
                                    &local_secret,
                                    Some(&token),
                                    HandshakeRole::Dialer,
                                    None,
                                )
                                .await
                                {
                                    Ok((remote, conn, reader, cipher)) => {
                                        register_peer(
                                            &peers,
                                            remote,
                                            conn,
                                            reader,
                                            cipher,
                                            &inbound,
                                            &blocked,
                                        )
                                        .await
                                    }
                                    Err(e) => Err(e),
                                }
                            }
                            Err(_) => Err(CoreError::PeerOffline),
                        };
                        let _ = reply.send(res);
                    }
                    Some(Command::Send { token, frame, reply }) => {
                        let conn = {
                            let guard = peers.lock().await;
                            guard.get(&token).map(|c| PeerConn {
                                writer: Arc::clone(&c.writer),
                                pending_ack: Arc::clone(&c.pending_ack),
                            })
                        };
                        let Some(conn) = conn else {
                            let _ = reply.send(Err(CoreError::PeerOffline));
                            continue;
                        };

                        let (ack_tx, ack_rx) = oneshot::channel();
                        {
                            let mut pending = conn.pending_ack.lock().await;
                            if pending.is_some() {
                                let _ = reply.send(Err(CoreError::Internal));
                                continue;
                            }
                            *pending = Some(ack_tx);
                        }

                        let write_res = {
                            let mut w = conn.writer.lock().await;
                            w.send(MSG_DATA, &frame).await
                        };
                        if let Err(e) = write_res {
                            let _ = conn.pending_ack.lock().await.take();
                            let _ = reply.send(Err(e));
                            continue;
                        }

                        let ack_res = tokio::time::timeout(Duration::from_secs(10), ack_rx)
                            .await
                            .map_err(|_| CoreError::PeerOffline)
                            .and_then(|r| r.map_err(|_| CoreError::PeerOffline))
                            .and_then(|inner| inner);
                        let _ = reply.send(ack_res);
                    }
                }
            }
            accept = listener.accept() => {
                match accept {
                    Ok((stream, _)) => {
                        let Ok(permit) =
                            Arc::clone(&handshake_slots).try_acquire_owned()
                        else {
                            // Too many unauthenticated connections in flight: close now.
                            drop(stream);
                            continue;
                        };
                        let peers = Arc::clone(&peers);
                        let inbound = inbound.clone();
                        // Refcount bump, not a copy of the secret, per accepted connection.
                        let secret = Arc::clone(&local_secret);
                        let blocked = Arc::clone(&blocked);
                        tokio::spawn(async move {
                            let session = open_peer_session_within(
                                HANDSHAKE_TIMEOUT,
                                stream,
                                &secret,
                                None,
                                HandshakeRole::Acceptor,
                                Some(&blocked),
                            )
                            .await;
                            drop(permit);
                            if let Ok((remote, conn, reader, cipher)) = session {
                                // A blocked peer is refused here; the caller is remote, so
                                // there is nobody local to report the code to.
                                let _ = register_peer(
                                    &peers, remote, conn, reader, cipher, &inbound, &blocked,
                                )
                                .await;
                            }
                        });
                    }
                    Err(_) => break,
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::frame::WireFrame;
    use crate::handshake::{forged_initiator_proof, EH02_PROOF_LEN};
    use crate::identity::Identity;
    use crate::pubkey::test_vectors::high_bit_alias;
    use sha2::Digest;

    /// Man-in-the-middle plumbing for the wire test: forward one direction and keep a copy
    /// of every byte that crosses.
    async fn copy_and_log(
        mut from: tokio::net::tcp::OwnedReadHalf,
        mut to: tokio::net::tcp::OwnedWriteHalf,
        log: Arc<Mutex<Vec<u8>>>,
    ) {
        let mut buf = vec![0u8; 8192];
        while let Ok(n) = from.read(&mut buf).await {
            if n == 0 {
                break;
            }
            log.lock().unwrap().extend_from_slice(&buf[..n]);
            if to.write_all(&buf[..n]).await.is_err() {
                break;
            }
        }
    }

    /// Poll `cond` for up to one second. Used where the assertion is about something the
    /// node does asynchronously, so a fixed sleep would be either flaky or slow.
    fn wait_until(mut cond: impl FnMut() -> bool) -> bool {
        for _ in 0..40 {
            if cond() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(25));
        }
        false
    }

    #[test]
    fn two_nodes_inject_send_recv() {
        let alice_id = Identity::generate();
        let bob_id = Identity::generate();

        let alice = NodeHandle::start(alice_id.to_secret_bytes(), 0).expect("alice start");
        let bob = NodeHandle::start(bob_id.to_secret_bytes(), 0).expect("bob start");

        std::thread::sleep(Duration::from_millis(100));

        let bob_addr = bob
            .listen_addrs()
            .into_iter()
            .next()
            .expect("bob listen addr");

        alice
            .inject_peer(&bob.local_token(), bob.peer_id(), bob_addr)
            .expect("inject bob");

        let frame = WireFrame::new(alice.local_token(), vec![0xCA, 0xFE, 0x01])
            .unwrap()
            .encode()
            .unwrap();

        alice
            .send_to_token(&bob.local_token(), frame.clone())
            .expect("send");

        let mut got = None;
        for _ in 0..50 {
            if let Some(msg) = bob.try_recv() {
                got = Some(msg);
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        let got = got.expect("bob should receive frame");
        assert_eq!(got, frame);

        let missing = Identity::generate().token().as_str().to_string();
        let err = alice
            .send_to_token(&missing, frame)
            .expect_err("offline peer");
        assert!(matches!(err, CoreError::PeerOffline));

        alice.stop();
        bob.stop();
    }

    #[test]
    fn blocklist_refuses_dial_and_send_then_allows_after_unblock() {
        let alice = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("alice");
        let bob = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("bob");
        std::thread::sleep(Duration::from_millis(100));

        let bob_addr = bob
            .listen_addrs()
            .into_iter()
            .next()
            .expect("bob listen addr");
        let bob_token = bob.local_token();

        // Blocked with the node already running, not fixed at start().
        alice.set_blocked_tokens(&[&bob_token]).expect("block bob");

        // EH02 runs to completion and only then is the authenticated token refused: the
        // dialer is the one enforcing its own list here, so it learns who answered first.
        let err = alice
            .connect_multiaddr(bob_addr.clone())
            .expect_err("dial to a blocked token must fail");
        assert!(matches!(err, CoreError::PeerBlocked));
        assert!(alice.known_peers().expect("peers").is_empty());

        let frame = WireFrame::new(alice.local_token(), vec![0xCA, 0xFE, 0x02])
            .unwrap()
            .encode()
            .unwrap();
        let err = alice
            .send_to_token(&bob_token, frame.clone())
            .expect_err("send to a blocked token must fail");
        assert!(matches!(err, CoreError::PeerBlocked));

        // Hex casing is not a bypass: entries are normalised on the way in.
        let shouty = format!(
            "{}{}",
            Token::PREFIX,
            bob_token[Token::PREFIX.len()..].to_uppercase()
        );
        let err = alice
            .send_to_token(&shouty, frame.clone())
            .expect_err("casing must not bypass the blocklist");
        assert!(matches!(err, CoreError::PeerBlocked));

        // The same dial succeeds once unblocked, so the list caused the refusal.
        alice.set_blocked_tokens(&[]).expect("unblock");
        alice
            .connect_multiaddr(bob_addr)
            .expect("dial after unblock");
        assert_eq!(alice.known_peers().expect("peers"), vec![bob_token.clone()]);
        alice
            .send_to_token(&bob_token, frame)
            .expect("send after unblock");

        alice.stop();
        bob.stop();
    }

    #[test]
    fn blocked_peer_cannot_open_inbound_session() {
        let alice = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("alice");
        let bob = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("bob");
        std::thread::sleep(Duration::from_millis(100));

        let bob_addr = bob
            .listen_addrs()
            .into_iter()
            .next()
            .expect("bob listen addr");
        let alice_token = alice.local_token();

        bob.set_blocked_tokens(&[&alice_token])
            .expect("block alice");

        // Alice reaches the listener and proves her identity; Bob refuses between messages
        // 3 and 4, so she never learns his — and her own dial reports the refusal as a
        // handshake that did not complete.
        let _ = alice.connect_multiaddr(bob_addr.clone());
        std::thread::sleep(Duration::from_millis(300));
        assert!(
            bob.known_peers().expect("peers").is_empty(),
            "a blocked peer must not become a session on the accepting side"
        );

        // Redial after unblocking: proves the list, not the transport, refused her. Alice may
        // still be shedding the binding she made for the closed connection, so retry.
        bob.set_blocked_tokens(&[]).expect("unblock");
        let accepted = wait_until(|| {
            let _ = alice.connect_multiaddr(bob_addr.clone());
            bob.known_peers()
                .map(|peers| peers.contains(&alice_token))
                .unwrap_or(false)
        });
        assert!(accepted, "bob should accept alice again after unblocking");

        alice.stop();
        bob.stop();
    }

    #[test]
    fn blocking_a_live_session_stops_delivery() {
        let alice = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("alice");
        let bob = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("bob");
        std::thread::sleep(Duration::from_millis(100));

        let bob_addr = bob
            .listen_addrs()
            .into_iter()
            .next()
            .expect("bob listen addr");
        let alice_token = alice.local_token();
        let bob_token = bob.local_token();

        alice
            .inject_peer(&bob_token, bob.peer_id(), bob_addr)
            .expect("inject bob");
        let frame = WireFrame::new(alice_token.clone(), vec![0xCA, 0xFE, 0x03])
            .unwrap()
            .encode()
            .unwrap();
        alice
            .send_to_token(&bob_token, frame.clone())
            .expect("baseline send before blocking");
        assert!(
            wait_until(|| bob.try_recv().is_some()),
            "baseline frame should arrive"
        );

        // Blocking mid-conversation must land on the session that is already open.
        bob.set_blocked_tokens(&[&alice_token])
            .expect("block alice");
        assert!(
            alice.send_to_token(&bob_token, frame).is_err(),
            "a blocked peer must not ACK the frame"
        );
        assert!(bob.try_recv().is_none(), "frame must not reach the queue");
        assert!(
            wait_until(|| bob
                .known_peers()
                .map(|peers| peers.is_empty())
                .unwrap_or(false)),
            "bob should drop the session with a peer he just blocked"
        );

        alice.stop();
        bob.stop();
    }

    #[test]
    fn set_blocked_tokens_rejects_malformed_entry_without_partial_apply() {
        let node = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("node");
        let good = Identity::generate().token().as_str().to_string();

        node.set_blocked_tokens(&[&good]).expect("initial list");
        let err = node
            .set_blocked_tokens(&[&good, "not-a-token"])
            .expect_err("malformed entry must fail the call");
        assert!(matches!(err, CoreError::InvalidToken));
        assert!(
            is_blocked(&node.blocked, &good),
            "a rejected update must leave the previous list intact"
        );

        node.set_blocked_tokens(&[]).expect("clear");
        assert!(!is_blocked(&node.blocked, &good));

        node.stop();
    }

    #[test]
    fn inject_wrong_expected_token_fails() {
        let alice_id = Identity::generate();
        let bob_id = Identity::generate();
        let impostor = Identity::generate();

        let alice = NodeHandle::start(alice_id.to_secret_bytes(), 0).expect("alice start");
        let bob = NodeHandle::start(bob_id.to_secret_bytes(), 0).expect("bob start");

        std::thread::sleep(Duration::from_millis(100));

        let bob_addr = bob
            .listen_addrs()
            .into_iter()
            .next()
            .expect("bob listen addr");

        let err = alice
            .inject_peer(
                impostor.token().as_str(),
                PeerId(impostor.token().as_str().to_string()),
                bob_addr,
            )
            .expect_err("wrong expected token must fail");
        assert!(matches!(err, CoreError::AuthFailed));

        alice.stop();
        bob.stop();
    }

    /// F-1, over a real socket and built exactly as the audit describes the attack: Mallory
    /// has Alice's public key (contact card, or a previous cleartext EH01 offer) and nothing
    /// else. Under EH01 this handshake succeeded and Bob registered the session as Alice.
    #[test]
    fn attacker_with_only_the_public_key_fails_the_handshake() {
        let alice = Identity::generate();
        let mallory = Identity::generate();
        let bob_id = Identity::generate();

        let bob = NodeHandle::start(bob_id.to_secret_bytes(), 0).expect("bob start");
        std::thread::sleep(Duration::from_millis(100));
        let bob_addr = bob.listen_addrs().into_iter().next().expect("bob addr");
        let bob_sock = multiaddr_to_socket(&bob_addr).expect("socket");

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let stream = TcpStream::connect(bob_sock).await.unwrap();
            let (mut reader, mut writer) = stream.into_split();

            let eph = Ephemeral::generate();
            let nonce_i = new_nonce();
            write_hello(&mut writer, &eph.public, &nonce_i)
                .await
                .unwrap();
            let (responder_eph, nonce_r) = read_challenge(&mut reader).await.unwrap();

            let forged = forged_initiator_proof(
                &mallory.static_secret(),
                &alice.public_key_bytes(),
                &Transcript {
                    initiator_eph: eph.public,
                    responder_eph,
                    nonce_i,
                    nonce_r,
                },
            );
            write_proof(&mut writer, &forged).await.unwrap();

            let mut len = [0u8; 4];
            assert!(
                reader.read_exact(&mut len).await.is_err(),
                "bob must not answer an unproven identity"
            );
        });

        assert!(
            bob.known_peers().expect("peers").is_empty(),
            "a forged initiator must never become a session"
        );

        // Positive control: the same identity, this time with its private key, gets in.
        let alice_node = NodeHandle::start(alice.to_secret_bytes(), 0).expect("alice start");
        std::thread::sleep(Duration::from_millis(100));
        alice_node.connect_multiaddr(bob_addr).expect("real alice");
        assert!(
            wait_until(|| bob
                .known_peers()
                .map(|p| p.contains(&alice.token().as_str().to_string()))
                .unwrap_or(false)),
            "the real alice must still be able to connect"
        );

        alice_node.stop();
        bob.stop();
    }

    /// F-10, end to end and as the report describes it: Bob blocks Mallory, Mallory sets the
    /// high bit of the last byte of her *own* public key and dials again. Every
    /// Diffie-Hellman is unchanged, so her EH02 proof is genuinely valid — before the
    /// encoding check Bob authenticated her, derived a token nobody had blocked, and opened
    /// a session with the peer he had just refused.
    #[test]
    fn a_blocked_peer_cannot_return_under_an_alias_of_its_key() {
        let mallory = Identity::generate();
        let bob_id = Identity::generate();
        let bob = NodeHandle::start(bob_id.to_secret_bytes(), 0).expect("bob start");
        std::thread::sleep(Duration::from_millis(100));
        let bob_addr = bob.listen_addrs().into_iter().next().expect("bob addr");
        let bob_sock = multiaddr_to_socket(&bob_addr).expect("socket");

        bob.set_blocked_tokens(&[mallory.token().as_str()])
            .expect("block mallory");

        let alias = high_bit_alias(&mallory.public_key_bytes());
        let alias_token = format!("ec_{}", hex::encode(sha2::Sha256::digest(alias)));
        assert_ne!(
            alias_token,
            mallory.token().as_str(),
            "the alias must hash to something Bob has not blocked"
        );

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let stream = TcpStream::connect(bob_sock).await.unwrap();
            let (mut reader, mut writer) = stream.into_split();

            let eph = Ephemeral::generate();
            let nonce_i = new_nonce();
            write_hello(&mut writer, &eph.public, &nonce_i)
                .await
                .unwrap();
            let (responder_eph, nonce_r) = read_challenge(&mut reader).await.unwrap();

            // Her real secret, her own key spelled differently: not a forgery, an alias.
            let proof = forged_initiator_proof(
                &mallory.static_secret(),
                &alias,
                &Transcript {
                    initiator_eph: eph.public,
                    responder_eph,
                    nonce_i,
                    nonce_r,
                },
            );
            write_proof(&mut writer, &proof).await.unwrap();

            let mut len = [0u8; 4];
            assert!(
                reader.read_exact(&mut len).await.is_err(),
                "bob must not answer a peer that renamed itself"
            );
        });

        let peers = bob.known_peers().expect("peers");
        assert!(
            peers.is_empty(),
            "a blocked peer must not get back in under {alias_token}: {peers:?}"
        );

        // Control: unblocked and spelling her key canonically, she connects — so the
        // refusal above was the block plus the encoding, not a broken handshake.
        bob.set_blocked_tokens(&[]).expect("unblock");
        let mallory_node = NodeHandle::start(mallory.to_secret_bytes(), 0).expect("mallory start");
        std::thread::sleep(Duration::from_millis(100));
        mallory_node.connect_multiaddr(bob_addr).expect("dial");
        assert!(
            wait_until(|| bob
                .known_peers()
                .map(|p| p.contains(&mallory.token().as_str().to_string()))
                .unwrap_or(false)),
            "the canonical identity must still connect"
        );

        mallory_node.stop();
        bob.stop();
    }

    /// F-15, from the position of someone sniffing the wire: everything an established
    /// session sends must be opaque. The test proxies the whole TCP conversation and then
    /// looks for the things that used to be readable in it.
    #[test]
    fn nothing_identifying_is_readable_on_the_wire() {
        let alice_id = Identity::generate();
        let bob_id = Identity::generate();
        let alice = NodeHandle::start(alice_id.to_secret_bytes(), 0).expect("alice");
        let bob = NodeHandle::start(bob_id.to_secret_bytes(), 0).expect("bob");
        std::thread::sleep(Duration::from_millis(100));
        let bob_sock = multiaddr_to_socket(&bob.listen_addrs()[0]).expect("bob socket");

        let sniffed: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));
        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .unwrap();
        let proxy_addr = rt.block_on(async {
            let listener = TcpListener::bind(SocketAddr::from(([127, 0, 0, 1], 0)))
                .await
                .unwrap();
            let addr = listener.local_addr().unwrap();
            let sniffed = Arc::clone(&sniffed);
            tokio::spawn(async move {
                let (inbound, _) = listener.accept().await.unwrap();
                let outbound = TcpStream::connect(bob_sock).await.unwrap();
                let (client_rx, client_tx) = inbound.into_split();
                let (server_rx, server_tx) = outbound.into_split();
                let up = Arc::clone(&sniffed);
                let down = Arc::clone(&sniffed);
                tokio::join!(
                    copy_and_log(client_rx, server_tx, up),
                    copy_and_log(server_rx, client_tx, down),
                );
            });
            addr
        });

        alice
            .connect_multiaddr(socket_to_multiaddr(proxy_addr))
            .expect("dial through the proxy");
        let frame = WireFrame::new(alice.local_token(), b"cita a las 19".to_vec())
            .unwrap()
            .encode()
            .unwrap();
        alice
            .send_to_token(&bob.local_token(), frame.clone())
            .expect("send");
        assert!(
            wait_until(|| bob.try_recv().is_some()),
            "the frame must still arrive"
        );

        let bytes = sniffed.lock().unwrap().clone();
        // The one thing that *is* still recognisable, which also proves the proxy captured a
        // real conversation rather than nothing: the handshake magic. Protocol fingerprinting
        // is a declared residual, not an oversight.
        assert!(
            bytes.windows(4).any(|w| w == b"EH02"),
            "the proxy should have seen the handshake"
        );
        for (what, needle) in [
            ("alice token", alice.local_token().into_bytes()),
            ("bob token", bob.local_token().into_bytes()),
            ("alice pubkey", alice_id.public_key_bytes().to_vec()),
            ("bob pubkey", bob_id.public_key_bytes().to_vec()),
            ("frame magic", crate::frame::MAGIC.to_vec()),
            ("whole frame", frame.clone()),
        ] {
            assert!(
                !bytes.windows(needle.len()).any(|w| w == needle),
                "{what} must not be readable on the wire"
            );
        }

        alice.stop();
        bob.stop();
        rt.shutdown_background();
    }

    /// F-5: the listening side answers with ephemeral material only. A scanner that cannot
    /// prove an identity gets no token and no public key, and a passive observer of the
    /// exchange gets neither.
    #[test]
    fn responder_reveals_no_identity_before_the_peer_authenticates() {
        let bob_id = Identity::generate();
        let bob = NodeHandle::start(bob_id.to_secret_bytes(), 0).expect("bob start");
        std::thread::sleep(Duration::from_millis(100));
        let bob_sock = multiaddr_to_socket(&bob.listen_addrs()[0]).expect("socket");

        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let stream = TcpStream::connect(bob_sock).await.unwrap();
            let (mut reader, mut writer) = stream.into_split();

            write_hello(&mut writer, &Ephemeral::generate().public, &new_nonce())
                .await
                .unwrap();
            let mut challenge = [0u8; EH02_CHALLENGE_LEN];
            reader.read_exact(&mut challenge).await.unwrap();

            for needle in [
                bob_id.public_key_bytes().as_slice(),
                bob_id.token().as_str().as_bytes(),
            ] {
                assert!(
                    !challenge.windows(needle.len()).any(|w| w == needle),
                    "the challenge must not carry the responder identity"
                );
            }

            // An unproven peer gets nothing more, not even a rejection message.
            write_proof(&mut writer, &[0u8; EH02_PROOF_LEN])
                .await
                .unwrap();
            let mut len = [0u8; 4];
            assert!(reader.read_exact(&mut len).await.is_err());
        });

        bob.stop();
    }

    #[test]
    fn stalled_handshake_times_out() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let listener = TcpListener::bind(SocketAddr::from(([127, 0, 0, 1], 0)))
                .await
                .unwrap();
            let addr = listener.local_addr().unwrap();
            let bob_secret = Identity::generate().to_secret_bytes();

            let server = tokio::spawn(async move {
                let (stream, _) = listener.accept().await.unwrap();
                open_peer_session_within(
                    Duration::from_millis(150),
                    stream,
                    &bob_secret,
                    None,
                    HandshakeRole::Acceptor,
                    None,
                )
                .await
            });

            // Connect and never send the EH02 hello.
            let stalled = TcpStream::connect(addr).await.unwrap();
            let res = server.await.unwrap();
            assert!(matches!(res, Err(CoreError::AuthFailed)));
            drop(stalled);
        });
    }

    #[test]
    fn oversized_preauth_proof_len_rejected() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let listener = TcpListener::bind(SocketAddr::from(([127, 0, 0, 1], 0)))
                .await
                .unwrap();
            let addr = listener.local_addr().unwrap();

            let bob_secret = Identity::generate().to_secret_bytes();

            let server = tokio::spawn(async move {
                let (stream, _) = listener.accept().await.unwrap();
                open_peer_session_within(
                    HANDSHAKE_TIMEOUT,
                    stream,
                    &bob_secret,
                    None,
                    HandshakeRole::Acceptor,
                    None,
                )
                .await
            });

            let stream = TcpStream::connect(addr).await.unwrap();
            let (mut reader, mut writer) = stream.into_split();
            write_hello(&mut writer, &Ephemeral::generate().public, &new_nonce())
                .await
                .unwrap();
            let mut challenge = [0u8; EH02_CHALLENGE_LEN];
            reader.read_exact(&mut challenge).await.unwrap();
            // Declare a 8 MiB proof (valid post-handshake frame, not pre-auth) and
            // send no body: must be rejected on the length, before any allocation.
            let bogus_len = (8u32 * 1024 * 1024).to_be_bytes();
            writer.write_all(&bogus_len).await.unwrap();
            writer.flush().await.unwrap();

            let res = server.await.unwrap();
            assert!(matches!(res, Err(CoreError::AuthFailed)));
        });
    }

    /// A budget for the *test's* own side of a raw session: [`read_msg`] charges whoever is
    /// reading, and in the tests below that is us, not the node under test.
    fn test_budget() -> InboundBudget {
        InboundBudget {
            total: Arc::new(AtomicUsize::new(0)),
            peer: Arc::new(AtomicUsize::new(0)),
        }
    }

    /// F-9 stated in one place: the ceiling is in bytes, it is charged per connection *and*
    /// node-wide, and the only thing that gives it back is the caller draining. The two tests
    /// after this one are the same claim over a real socket.
    #[test]
    fn the_inbound_ceiling_is_bytes_per_connection_and_bytes_in_total() {
        let (tx, _rx) = std_mpsc::sync_channel(INBOUND_QUEUE_SLOTS);
        let sink = InboundSink::new(tx);
        let first = sink.for_connection();
        let second = sink.for_connection();
        let third = sink.for_connection();

        let mut held: Vec<InboundPermit> = Vec::new();
        while let Some(permit) = first.budget.try_reserve(MAX_FRAME_LEN) {
            held.push(permit);
        }
        assert_eq!(
            held.len() * MAX_FRAME_LEN,
            MAX_INBOUND_BYTES_PER_PEER,
            "one connection must stop at its own share"
        );

        // Opening more sessions costs an attacker a keypair, so the per-connection share must
        // not be a way of multiplying the total.
        while let Some(permit) = second.budget.try_reserve(MAX_FRAME_LEN) {
            held.push(permit);
        }
        assert_eq!(held.len() * MAX_FRAME_LEN, MAX_INBOUND_BYTES_TOTAL);
        assert!(
            third.budget.try_reserve(MAX_FRAME_LEN).is_none(),
            "a third session must not find bytes the node no longer has"
        );

        // A padded record is never charged: a saturated node still answers, and a backlog of
        // data in one direction does not delay the ACKs of our own sends.
        assert!(third
            .budget
            .try_reserve(inbound_charge(INBOUND_FREE_RECORD_LEN))
            .is_some());

        // Draining is what frees it, not a clock.
        drop(held);
        assert!(third.budget.try_reserve(MAX_FRAME_LEN).is_some());
    }

    /// F-9, over a real socket and built as the report describes the attack: finishing the
    /// handshake costs only generating a keypair, and the peer that finished it then pushes
    /// frames as fast as the socket takes them while nobody polls the queue. Bounded by
    /// message count, that was 256 × 16 MiB the device had to hold.
    #[test]
    fn a_flooding_peer_gets_its_share_and_no_more() {
        const FLOOD_FRAME: usize = 4 * 1024 * 1024;

        let bob = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("bob start");
        std::thread::sleep(Duration::from_millis(100));
        let bob_addr = bob.listen_addrs().into_iter().next().expect("bob addr");
        let bob_sock = multiaddr_to_socket(&bob_addr).expect("socket");

        let mallory = Identity::generate();
        let flood = WireFrame::new(
            mallory.token().as_str().to_string(),
            vec![0x41; FLOOD_FRAME],
        )
        .unwrap()
        .encode()
        .unwrap();

        let rt = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .unwrap();
        let acked = rt.block_on(async move {
            let stream = TcpStream::connect(bob_sock).await.unwrap();
            let (_bob_token, conn, mut reader, mut cipher) = open_peer_session(
                stream,
                &mallory.to_secret_bytes(),
                None,
                HandshakeRole::Dialer,
                None,
            )
            .await
            .expect("mallory authenticates like anybody else");

            // Several times the whole node ceiling, and without waiting for ACKs: what is
            // under test is how much of it bob decides to keep.
            let writer = Arc::clone(&conn.writer);
            let pump = tokio::spawn(async move {
                for _ in 0..(2 * MAX_INBOUND_BYTES_TOTAL / FLOOD_FRAME) {
                    let mut w = writer.lock().await;
                    if w.send(MSG_DATA, &flood).await.is_err() {
                        break;
                    }
                }
            });

            // Bob only ACKs what he managed to queue, so counting ACKs measures what he is
            // holding. Reading until the error rather than polling with a timeout: a read
            // cancelled halfway through a record would desync this side of the session and
            // the count would be measuring the test instead of the node.
            let budget = test_budget();
            let acked = tokio::time::timeout(Duration::from_secs(60), async {
                let mut acked = 0usize;
                loop {
                    match read_msg(&mut reader, &mut cipher, &budget).await {
                        Ok((MSG_ACK, _, _)) => acked += 1,
                        Ok(_) => {}
                        // Bob stopped being able to read from us and closed: the throttle
                        // becoming a disconnect is the other half of the fix.
                        Err(_) => break acked,
                    }
                }
            })
            .await
            .expect("bob must close a session he cannot read from, not hold it open");
            pump.abort();
            acked
        });

        assert!(acked > 0, "the session must work before it is throttled");
        assert!(
            acked * FLOOD_FRAME <= MAX_INBOUND_BYTES_PER_PEER,
            "bob acknowledged {acked} frames of 4 MiB, past the per-connection ceiling"
        );

        // The flood must be a problem for the flooder alone: a peer arriving after it still
        // gets a session and still gets delivery, and bob's command loop still answers.
        let alice = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("alice");
        std::thread::sleep(Duration::from_millis(100));
        alice
            .connect_multiaddr(bob_addr)
            .expect("bob still accepts connections");
        let hello = WireFrame::new(alice.local_token(), b"unaffected".to_vec())
            .unwrap()
            .encode()
            .unwrap();
        alice
            .send_to_token(&bob.local_token(), hello.clone())
            .expect("an honest peer must not pay for somebody else's flood");
        assert_eq!(
            bob.known_peers().expect("bob answers while flooded"),
            vec![alice.local_token()]
        );

        let mut drained: Vec<Vec<u8>> = Vec::new();
        assert!(
            wait_until(|| {
                while let Some(frame) = bob.try_recv() {
                    drained.push(frame);
                }
                drained.contains(&hello)
            }),
            "the honest frame must come out of the queue the flooder filled"
        );

        alice.stop();
        bob.stop();
        rt.shutdown_background();
    }

    /// The other half of the fix: a ceiling nobody normal ever touches. Short frames are not
    /// charged at all, media-sized ones are, and a `send_to_token` throttled by the budget
    /// would not return an error — it would sit there and then fail on its own ACK timeout.
    #[test]
    fn ordinary_traffic_never_meets_the_inbound_ceiling() {
        const MEDIA_FRAME: usize = 4 * 1024 * 1024;

        let alice = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("alice");
        let bob = NodeHandle::start(Identity::generate().to_secret_bytes(), 0).expect("bob");
        std::thread::sleep(Duration::from_millis(100));
        let bob_addr = bob.listen_addrs().into_iter().next().expect("bob addr");
        let bob_token = bob.local_token();
        alice
            .inject_peer(&bob_token, bob.peer_id(), bob_addr)
            .expect("inject bob");

        let media = WireFrame::new(alice.local_token(), vec![0xB1; MEDIA_FRAME])
            .unwrap()
            .encode()
            .unwrap();
        let mut sent = 0usize;

        // A conversation nobody is reading: chat frames sit below the padding floor, so the
        // budget never even looks at them.
        for i in 0..40u8 {
            let frame = WireFrame::new(alice.local_token(), vec![i; 64])
                .unwrap()
                .encode()
                .unwrap();
            alice
                .send_to_token(&bob_token, frame)
                .expect("short frames are not charged");
            sent += 1;
        }
        for _ in 0..2 {
            alice
                .send_to_token(&bob_token, media.clone())
                .expect("media below the per-connection share goes straight through");
            sent += 1;
        }

        let mut drained = 0usize;
        assert!(
            wait_until(|| {
                while bob.try_recv().is_some() {
                    drained += 1;
                }
                drained == sent
            }),
            "everything sent must arrive: {drained} of {sent}"
        );

        // And the budget is a rate, not a quota: the same traffic works again once drained.
        for _ in 0..2 {
            alice
                .send_to_token(&bob_token, media.clone())
                .expect("draining gives the bytes back");
        }

        alice.stop();
        bob.stop();
    }

    #[test]
    fn stalled_connections_do_not_block_node() {
        let alice_id = Identity::generate();
        let bob_id = Identity::generate();

        let alice = NodeHandle::start(alice_id.to_secret_bytes(), 0).expect("alice start");
        let bob = NodeHandle::start(bob_id.to_secret_bytes(), 0).expect("bob start");

        std::thread::sleep(Duration::from_millis(100));

        let bob_addr = bob
            .listen_addrs()
            .into_iter()
            .next()
            .expect("bob listen addr");
        let bob_sock = multiaddr_to_socket(&bob_addr).expect("bob socket");

        // Hold silent connections open: they must neither be authenticated nor
        // starve the accept loop.
        let mut stalled = Vec::new();
        for _ in 0..(MAX_PENDING_HANDSHAKES / 4) {
            if let Ok(s) = std::net::TcpStream::connect(bob_sock) {
                stalled.push(s);
            }
        }
        assert!(!stalled.is_empty());
        assert!(bob
            .known_peers()
            .expect("bob command loop answers while handshakes are pending")
            .is_empty());

        alice
            .inject_peer(&bob.local_token(), bob.peer_id(), bob_addr)
            .expect("inject bob while stalled peers are pending");

        let frame = WireFrame::new(alice.local_token(), vec![0xCA, 0xFE, 0x02])
            .unwrap()
            .encode()
            .unwrap();
        alice
            .send_to_token(&bob.local_token(), frame.clone())
            .expect("send");

        let mut got = None;
        for _ in 0..50 {
            if let Some(msg) = bob.try_recv() {
                got = Some(msg);
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        assert_eq!(got.expect("bob should receive frame"), frame);

        drop(stalled);
        alice.stop();
        bob.stop();
    }
}
