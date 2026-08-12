//! Tokio TCP P2P node: dial by multiaddr, EH01 authenticated hello, length-prefixed frames.
//!
//! Phase 4 uses Tokio TCP (+ `inject_peer` / `connect_multiaddr` for tests and manual dial).
//! libp2p request-response was attempted but hit persistent `ConnectionClosed` races on
//! loopback dual-node tests; see `docs/phase-4.md`. LAN mDNS can be layered later.
//!
//! Networking carries E2EE ciphertext only — callers encrypt before [`NodeHandle::send_to_token`].
//! Peer offline / unknown → [`CoreError::PeerOffline`] (no relay).
//! Hello authenticity: EH01 offer + E2EE proof of nonce/token possession.
//! Pre-auth exposure is bounded: [`HANDSHAKE_TIMEOUT`], [`MAX_PENDING_HANDSHAKES`]
//! concurrent unauthenticated connections, [`MAX_PREAUTH_LEN`] buffers.

use std::collections::{HashMap, HashSet};
use std::net::SocketAddr;
use std::sync::mpsc::{self as std_mpsc, Receiver as StdReceiver, SyncSender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use multiaddr::{Multiaddr, Protocol};
use rand::rngs::OsRng;
use rand::RngCore;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};
use tokio::sync::{oneshot, Mutex as AsyncMutex, Semaphore};
use zeroize::Zeroizing;

use crate::crypto::{decrypt, encrypt, Ciphertext};
use crate::error::CoreError;
use crate::frame::decode_frame;
use crate::identity::{Identity, PublicIdentity};
use crate::token::Token;

const MAX_FRAME_LEN: usize = 16 * 1024 * 1024;
const MAX_TOKEN_LEN: usize = 256;
const MSG_DATA: u8 = 1;
const MSG_ACK: u8 = 2;

/// Budget for a full EH01 exchange; on expiry the peer is treated as unauthenticated.
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(5);
/// Inbound connections allowed to sit in the handshake at once.
const MAX_PENDING_HANDSHAKES: usize = 32;
/// Buffer cap for anything read before the peer is authenticated. Post-handshake
/// data frames keep the [`MAX_FRAME_LEN`] budget.
const MAX_PREAUTH_LEN: usize = 4 * 1024;

const HELLO_MAGIC: &[u8; 4] = b"EH01";
const HELLO_VERSION: u8 = 1;
const HELLO_NONCE_LEN: usize = 32;
const HELLO_PUBKEY_LEN: usize = 32;

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

struct PeerConn {
    writer: Arc<AsyncMutex<tokio::net::tcp::OwnedWriteHalf>>,
    /// At most one in-flight send ACK waiter per peer (Phase 4).
    pending_ack: Arc<AsyncMutex<Option<AckSender>>>,
}

#[derive(Clone, Copy)]
enum HandshakeRole {
    Dialer,
    Acceptor,
}

struct HelloOffer {
    token: String,
    pubkey: [u8; HELLO_PUBKEY_LEN],
    nonce: [u8; HELLO_NONCE_LEN],
}

/// Running node handle with an embedded Tokio runtime (FFI-friendly).
pub struct NodeHandle {
    _rt: tokio::runtime::Runtime,
    local_token: String,
    peer_id: PeerId,
    listen_addrs: Arc<Mutex<Vec<Multiaddr>>>,
    cmd_tx: UnboundedSender<Command>,
    inbound_rx: Mutex<StdReceiver<Vec<u8>>>,
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
        let (inbound_tx, inbound_rx) = std_mpsc::sync_channel(256);
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
    /// Takes effect immediately: new sessions are refused after EH01, the next inbound
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
    pub fn try_recv(&self) -> Option<Vec<u8>> {
        self.inbound_rx
            .lock()
            .ok()
            .and_then(|rx| rx.try_recv().ok())
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

async fn write_msg(
    writer: &mut (impl AsyncWriteExt + Unpin),
    kind: u8,
    payload: &[u8],
) -> Result<(), CoreError> {
    if payload.len() > MAX_FRAME_LEN {
        return Err(CoreError::InvalidFrame);
    }
    let len = (1 + payload.len()) as u32;
    writer
        .write_all(&len.to_be_bytes())
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer
        .write_all(&[kind])
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer
        .write_all(payload)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer.flush().await.map_err(|_| CoreError::PeerOffline)?;
    Ok(())
}

async fn read_msg(reader: &mut (impl AsyncReadExt + Unpin)) -> Result<(u8, Vec<u8>), CoreError> {
    let mut len_buf = [0u8; 4];
    reader
        .read_exact(&mut len_buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    let len = u32::from_be_bytes(len_buf) as usize;
    if len == 0 || len > MAX_FRAME_LEN + 1 {
        return Err(CoreError::InvalidFrame);
    }
    let mut buf = vec![0u8; len];
    reader
        .read_exact(&mut buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    let kind = buf[0];
    Ok((kind, buf[1..].to_vec()))
}

async fn write_offer(
    writer: &mut (impl AsyncWriteExt + Unpin),
    token: &str,
    pubkey: &[u8; HELLO_PUBKEY_LEN],
    nonce: &[u8; HELLO_NONCE_LEN],
) -> Result<(), CoreError> {
    let token_bytes = token.as_bytes();
    if token_bytes.is_empty() || token_bytes.len() > MAX_TOKEN_LEN {
        return Err(CoreError::InvalidToken);
    }
    writer
        .write_all(HELLO_MAGIC)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer
        .write_all(&[HELLO_VERSION])
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer
        .write_all(&(token_bytes.len() as u16).to_be_bytes())
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer
        .write_all(token_bytes)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer
        .write_all(pubkey)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer
        .write_all(nonce)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    writer.flush().await.map_err(|_| CoreError::PeerOffline)?;
    Ok(())
}

async fn read_offer(reader: &mut (impl AsyncReadExt + Unpin)) -> Result<HelloOffer, CoreError> {
    let mut magic = [0u8; 4];
    reader
        .read_exact(&mut magic)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    if &magic != HELLO_MAGIC {
        return Err(CoreError::AuthFailed);
    }
    let mut ver = [0u8; 1];
    reader
        .read_exact(&mut ver)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    if ver[0] != HELLO_VERSION {
        return Err(CoreError::AuthFailed);
    }
    let mut len_buf = [0u8; 2];
    reader
        .read_exact(&mut len_buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    let token_len = u16::from_be_bytes(len_buf) as usize;
    if token_len == 0 || token_len > MAX_TOKEN_LEN {
        return Err(CoreError::AuthFailed);
    }
    let mut token_buf = vec![0u8; token_len];
    reader
        .read_exact(&mut token_buf)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    let token_raw = String::from_utf8(token_buf).map_err(|_| CoreError::AuthFailed)?;
    let token = Token::parse(&token_raw)
        .map_err(|_| CoreError::AuthFailed)?
        .as_str()
        .to_string();

    let mut pubkey = [0u8; HELLO_PUBKEY_LEN];
    reader
        .read_exact(&mut pubkey)
        .await
        .map_err(|_| CoreError::PeerOffline)?;
    let mut nonce = [0u8; HELLO_NONCE_LEN];
    reader
        .read_exact(&mut nonce)
        .await
        .map_err(|_| CoreError::PeerOffline)?;

    let derived = Token::from_public_key_bytes(&pubkey);
    if derived.as_str() != token {
        return Err(CoreError::AuthFailed);
    }

    Ok(HelloOffer {
        token,
        pubkey,
        nonce,
    })
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

fn build_proof_plaintext(
    local_nonce: &[u8; 32],
    peer_nonce: &[u8; 32],
    local_token: &str,
) -> Vec<u8> {
    let mut pt = Vec::with_capacity(64 + local_token.len());
    pt.extend_from_slice(local_nonce);
    pt.extend_from_slice(peer_nonce);
    pt.extend_from_slice(local_token.as_bytes());
    pt
}

fn verify_proof(
    local: &Identity,
    local_nonce: &[u8; 32],
    peer_offer: &HelloOffer,
    ciphertext: &[u8],
    expected_remote: Option<&str>,
) -> Result<String, CoreError> {
    let ct = Ciphertext::from_bytes(ciphertext.to_vec()).map_err(|_| CoreError::AuthFailed)?;
    let pt = decrypt(local, &ct).map_err(|_| CoreError::AuthFailed)?;
    if pt.len() < 64 {
        return Err(CoreError::AuthFailed);
    }
    // peer_nonce || local_nonce || peer_token
    if &pt[0..32] != peer_offer.nonce.as_slice() {
        return Err(CoreError::AuthFailed);
    }
    if &pt[32..64] != local_nonce.as_slice() {
        return Err(CoreError::AuthFailed);
    }
    let peer_token_raw = std::str::from_utf8(&pt[64..]).map_err(|_| CoreError::AuthFailed)?;
    let peer_token = Token::parse(peer_token_raw)
        .map_err(|_| CoreError::AuthFailed)?
        .as_str()
        .to_string();

    let derived = PublicIdentity::from_public_key_bytes(peer_offer.pubkey);
    if derived.token().as_str() != peer_token {
        return Err(CoreError::AuthFailed);
    }
    if peer_token != peer_offer.token {
        return Err(CoreError::AuthFailed);
    }
    if let Some(expected) = expected_remote {
        if peer_token != expected {
            return Err(CoreError::AuthFailed);
        }
    }
    Ok(peer_token)
}

async fn open_peer_session(
    stream: TcpStream,
    local_secret: &[u8; 32],
    expected_remote: Option<&str>,
    role: HandshakeRole,
) -> Result<(String, PeerConn, tokio::net::tcp::OwnedReadHalf), CoreError> {
    let local = Identity::from_secret_bytes(*local_secret);
    let local_token = local.token().as_str().to_string();
    let local_pubkey = local.public_key_bytes();
    let mut local_nonce = [0u8; HELLO_NONCE_LEN];
    OsRng.fill_bytes(&mut local_nonce);

    let (mut reader, mut writer) = stream.into_split();

    let peer_offer = match role {
        HandshakeRole::Dialer => {
            write_offer(&mut writer, &local_token, &local_pubkey, &local_nonce).await?;
            let peer_offer = read_offer(&mut reader).await?;
            let peer_pub = PublicIdentity::from_public_key_bytes(peer_offer.pubkey);
            let proof_pt = build_proof_plaintext(&local_nonce, &peer_offer.nonce, &local_token);
            let proof_ct = encrypt(&peer_pub, &proof_pt).map_err(|_| CoreError::AuthFailed)?;
            write_proof(&mut writer, proof_ct.as_bytes()).await?;
            let their_proof = read_proof(&mut reader).await?;
            let remote_token = verify_proof(
                &local,
                &local_nonce,
                &peer_offer,
                &their_proof,
                expected_remote,
            )?;
            (remote_token, peer_offer)
        }
        HandshakeRole::Acceptor => {
            let peer_offer = read_offer(&mut reader).await?;
            write_offer(&mut writer, &local_token, &local_pubkey, &local_nonce).await?;
            let their_proof = read_proof(&mut reader).await?;
            let remote_token = verify_proof(
                &local,
                &local_nonce,
                &peer_offer,
                &their_proof,
                expected_remote,
            )?;
            let peer_pub = PublicIdentity::from_public_key_bytes(peer_offer.pubkey);
            let proof_pt = build_proof_plaintext(&local_nonce, &peer_offer.nonce, &local_token);
            let proof_ct = encrypt(&peer_pub, &proof_pt).map_err(|_| CoreError::AuthFailed)?;
            write_proof(&mut writer, proof_ct.as_bytes()).await?;
            (remote_token, peer_offer)
        }
    };

    let (remote_token, _peer_offer) = peer_offer;
    let conn = PeerConn {
        writer: Arc::new(AsyncMutex::new(writer)),
        pending_ack: Arc::new(AsyncMutex::new(None)),
    };
    Ok((remote_token, conn, reader))
}

/// [`open_peer_session`] under a wall-clock budget: a peer that stalls mid-EH01
/// is dropped as [`CoreError::AuthFailed`] instead of holding memory and fds.
async fn open_peer_session_within(
    budget: Duration,
    stream: TcpStream,
    local_secret: &[u8; 32],
    expected_remote: Option<&str>,
    role: HandshakeRole,
) -> Result<(String, PeerConn, tokio::net::tcp::OwnedReadHalf), CoreError> {
    match tokio::time::timeout(
        budget,
        open_peer_session(stream, local_secret, expected_remote, role),
    )
    .await
    {
        Ok(res) => res,
        Err(_) => Err(CoreError::AuthFailed),
    }
}

async fn reader_loop(
    mut reader: tokio::net::tcp::OwnedReadHalf,
    conn: PeerConn,
    inbound_tx: SyncSender<Vec<u8>>,
    authenticated_token: String,
    peers: Arc<AsyncMutex<HashMap<String, PeerConn>>>,
    blocked: BlockedTokens,
) {
    loop {
        match read_msg(&mut reader).await {
            Ok((MSG_DATA, frame)) => {
                // Blocked after the session was established: close instead of queueing.
                if is_blocked(&blocked, &authenticated_token) {
                    break;
                }
                match decode_frame(&frame) {
                    Ok(wf) if wf.sender_token == authenticated_token => {
                        if inbound_tx.try_send(frame).is_err() {
                            // Inbound queue full: the frame is gone, so withhold the
                            // ACK rather than let the sender mark it delivered.
                            continue;
                        }
                        let mut w = conn.writer.lock().await;
                        if write_msg(&mut *w, MSG_ACK, &[]).await.is_err() {
                            break;
                        }
                    }
                    // Spoofed sender_token or invalid frame: drop without ACK, disconnect.
                    _ => break,
                }
            }
            Ok((MSG_ACK, _)) => {
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
/// blocklist is enforced.
async fn register_peer(
    peers: &Arc<AsyncMutex<HashMap<String, PeerConn>>>,
    remote: String,
    conn: PeerConn,
    reader: tokio::net::tcp::OwnedReadHalf,
    inbound_tx: SyncSender<Vec<u8>>,
    blocked: &BlockedTokens,
) -> Result<(), CoreError> {
    // Authorisation happens here and not earlier because `remote` is only trustworthy once
    // EH01 proved key possession. A blocked peer therefore still costs a full handshake.
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
        conn,
        inbound_tx,
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
    inbound_tx: SyncSender<Vec<u8>>,
    ready_tx: SyncSender<ReadyInfo>,
    listen_addrs_shared: Arc<Mutex<Vec<Multiaddr>>>,
    blocked: BlockedTokens,
) -> Result<(), CoreError> {
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
                                )
                                .await
                                {
                                    Ok((remote, conn, reader)) => {
                                        register_peer(
                                            &peers,
                                            remote,
                                            conn,
                                            reader,
                                            inbound_tx.clone(),
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
                                )
                                .await
                                {
                                    Ok((remote, conn, reader)) => {
                                        register_peer(
                                            &peers,
                                            remote,
                                            conn,
                                            reader,
                                            inbound_tx.clone(),
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
                            write_msg(&mut *w, MSG_DATA, &frame).await
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
                        let inbound = inbound_tx.clone();
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
                            )
                            .await;
                            drop(permit);
                            if let Ok((remote, conn, reader)) = session {
                                // A blocked peer is refused here; the caller is remote, so
                                // there is nobody local to report the code to.
                                let _ = register_peer(
                                    &peers, remote, conn, reader, inbound, &blocked,
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
    use crate::identity::Identity;

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

        // EH01 runs to completion and only then is the authenticated token refused.
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

        // Alice reaches the listener and finishes the handshake; the rejection is on Bob's
        // side, so her own dial can still report success.
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

    #[test]
    fn offer_token_pubkey_mismatch_fails() {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let listener = TcpListener::bind(SocketAddr::from(([127, 0, 0, 1], 0)))
                .await
                .unwrap();
            let addr = listener.local_addr().unwrap();

            let bob = Identity::generate();
            let alice = Identity::generate();
            let bob_secret = bob.to_secret_bytes();

            let server = tokio::spawn(async move {
                let (stream, _) = listener.accept().await.unwrap();
                open_peer_session(stream, &bob_secret, None, HandshakeRole::Acceptor).await
            });

            let stream = TcpStream::connect(addr).await.unwrap();
            let (mut _reader, mut writer) = stream.into_split();
            let mut nonce = [0u8; 32];
            OsRng.fill_bytes(&mut nonce);
            // Claim alice's token but present bob's pubkey → mismatch.
            write_offer(
                &mut writer,
                alice.token().as_str(),
                &bob.public_key_bytes(),
                &nonce,
            )
            .await
            .unwrap();

            let res = server.await.unwrap();
            assert!(matches!(res, Err(CoreError::AuthFailed)));
        });
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
                )
                .await
            });

            // Connect and never send EH01.
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
            let alice = Identity::generate();

            let server = tokio::spawn(async move {
                let (stream, _) = listener.accept().await.unwrap();
                open_peer_session_within(
                    HANDSHAKE_TIMEOUT,
                    stream,
                    &bob_secret,
                    None,
                    HandshakeRole::Acceptor,
                )
                .await
            });

            let stream = TcpStream::connect(addr).await.unwrap();
            let (mut _reader, mut writer) = stream.into_split();
            let mut nonce = [0u8; 32];
            OsRng.fill_bytes(&mut nonce);
            write_offer(
                &mut writer,
                alice.token().as_str(),
                &alice.public_key_bytes(),
                &nonce,
            )
            .await
            .unwrap();
            // Declare a 8 MiB proof (valid post-handshake frame, not pre-auth) and
            // send no body: must be rejected on the length, before any allocation.
            let bogus_len = (8u32 * 1024 * 1024).to_be_bytes();
            writer.write_all(&bogus_len).await.unwrap();
            writer.flush().await.unwrap();

            let res = server.await.unwrap();
            assert!(matches!(res, Err(CoreError::AuthFailed)));
        });
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
