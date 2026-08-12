//! C ABI bridge for Flutter / native callers (Phase 4).
//!
//! All fallible entry points return `0` on success or a [`CoreError`] code.
//! Allocated buffers must be freed with [`encrypchat_free`].

use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use zeroize::Zeroizing;

use crate::api_version;
use crate::crypto::{decrypt, encrypt, Ciphertext};
use crate::error::CoreError;
use crate::identity::{Identity, PublicIdentity};
use crate::local_aead::{open_local, seal_local};
use crate::net::NodeHandle;
use crate::pop::{pop_proof, POP_PROOF_LEN};
use crate::sealed::{open_sealed, seal_sender, SEALED_MSG_ID_LEN};

fn write_cstr(out: *mut c_char, cap: usize, s: &str) -> Result<(), CoreError> {
    let needed = s.len().checked_add(1).ok_or(CoreError::BufferTooSmall)?;
    if cap < needed {
        return Err(CoreError::BufferTooSmall);
    }
    unsafe {
        ptr::copy_nonoverlapping(s.as_ptr(), out as *mut u8, s.len());
        *out.add(s.len()) = 0;
    }
    Ok(())
}

fn alloc_bytes(data: &[u8]) -> Result<*mut u8, CoreError> {
    let size = if data.is_empty() { 1 } else { data.len() };
    let ptr = unsafe { libc::malloc(size) as *mut u8 };
    if ptr.is_null() {
        return Err(CoreError::Internal);
    }
    if !data.is_empty() {
        unsafe {
            ptr::copy_nonoverlapping(data.as_ptr(), ptr, data.len());
        }
    }
    Ok(ptr)
}

fn run_ffi<F>(f: F) -> i32
where
    F: FnOnce() -> Result<(), CoreError>,
{
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => e.as_code(),
        Err(_) => CoreError::Internal.as_code(),
    }
}

fn run_ffi_code<F>(f: F) -> i32
where
    F: FnOnce() -> Result<i32, CoreError>,
{
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(code)) => code,
        Ok(Err(e)) => e.as_code(),
        Err(_) => CoreError::Internal.as_code(),
    }
}

/// Writes semver of the FFI surface, e.g. `"0.8.1"`.
///
/// # Safety
///
/// `out` must be null or valid for writes of `cap` bytes until this call returns; null is
/// rejected with `NullPointer` (7) before any write happens. Writes the version string plus
/// a NUL terminator (6 bytes for `"0.8.1"`); a smaller `cap` writes nothing and returns
/// `BufferTooSmall` (6). Nothing is allocated and no state is shared, so any thread may call
/// this concurrently.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_api_version(out: *mut c_char, cap: usize) -> i32 {
    run_ffi(|| {
        if out.is_null() {
            return Err(CoreError::NullPointer);
        }
        write_cstr(out, cap, api_version())
    })
}

/// Generate a new identity: 32-byte secret + token (`ec_` + 64 hex + NUL).
///
/// # Safety
///
/// `out_secret` must be valid for writes of exactly 32 bytes, `out_token` for writes of
/// `token_cap` bytes; both must stay valid for the whole call and must not overlap. Either
/// being null returns `NullPointer` (7). `token_cap` must be at least 68 (`ec_` + 64 hex +
/// NUL) or `BufferTooSmall` (6) is returned. Errors are clean: neither buffer is written, so
/// a failed call never leaves key material in `out_secret`. On success the caller owns both
/// buffers; nothing is allocated here. `out_secret` is long-term key material: keep it in OS
/// secure storage and never log it.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_identity_generate(
    out_secret: *mut u8,
    out_token: *mut c_char,
    token_cap: usize,
) -> i32 {
    run_ffi(|| {
        if out_secret.is_null() || out_token.is_null() {
            return Err(CoreError::NullPointer);
        }
        let id = Identity::generate();
        // Token first: `write_cstr` validates capacity before writing, so a too-small
        // `token_cap` aborts while both caller buffers are still untouched. Writing the
        // secret first would hand back fresh key material on an error path, and callers
        // do not zeroize buffers they believe were never filled.
        write_cstr(out_token, token_cap, id.token().as_str())?;
        let secret = Zeroizing::new(id.to_secret_bytes());
        ptr::copy_nonoverlapping(secret.as_ptr(), out_secret, 32);
        Ok(())
    })
}

/// Derive token from a 32-byte secret.
///
/// # Safety
///
/// `secret` must be valid for reads of exactly 32 bytes and `out_token` for writes of
/// `token_cap` bytes, both for the duration of the call, and the two regions must not
/// overlap. Either being null returns `NullPointer` (7). `token_cap` must be at least 68 or
/// `BufferTooSmall` (6) is returned with nothing written. The secret is copied into a stack
/// array and never retained; no allocation and no shared state, so any thread may call it.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_identity_token(
    secret: *const u8,
    out_token: *mut c_char,
    token_cap: usize,
) -> i32 {
    run_ffi(|| {
        if secret.is_null() || out_token.is_null() {
            return Err(CoreError::NullPointer);
        }
        let mut bytes = Zeroizing::new([0u8; 32]);
        ptr::copy_nonoverlapping(secret, bytes.as_mut_ptr(), 32);
        let id = Identity::from_secret_bytes(*bytes);
        write_cstr(out_token, token_cap, id.token().as_str())
    })
}

/// Derive X25519 public key from a 32-byte secret.
///
/// # Safety
///
/// `secret` must be valid for reads of exactly 32 bytes and `out_pub` for writes of exactly
/// 32 bytes; the regions must not overlap and both must stay valid for the whole call.
/// Either being null returns `NullPointer` (7). The caller keeps ownership of both buffers
/// and nothing is allocated. Callable from any thread.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_identity_public_key(
    secret: *const u8,
    out_pub: *mut u8,
) -> i32 {
    run_ffi(|| {
        if secret.is_null() || out_pub.is_null() {
            return Err(CoreError::NullPointer);
        }
        let mut bytes = Zeroizing::new([0u8; 32]);
        ptr::copy_nonoverlapping(secret, bytes.as_mut_ptr(), 32);
        let id = Identity::from_secret_bytes(*bytes);
        let pub_bytes = id.public_key_bytes();
        ptr::copy_nonoverlapping(pub_bytes.as_ptr(), out_pub, 32);
        Ok(())
    })
}

/// Encrypt plaintext for `recipient_pub`. Allocates ciphertext; caller frees with [`encrypchat_free`].
///
/// # Safety
///
/// `recipient_pub` must be valid for reads of exactly 32 bytes (X25519 public key).
/// `plaintext` must be valid for reads of `plaintext_len` bytes, or null when `plaintext_len`
/// is 0 — an empty plaintext is rejected with `EmptyPlaintext` (5). Both inputs are only read
/// during the call, so they may be freed once it returns. `out_ciphertext` must be a non-null
/// slot aligned for `*mut u8` and `out_len` a non-null slot aligned for `usize`; on success
/// they receive a `malloc`ed buffer (`eph_pub(32) || nonce(12) || ct+tag`) and its length, and
/// the caller takes ownership and must release it with exactly one [`encrypchat_free`]. On any
/// error neither out-slot is written, so the caller must not read or free them. A null
/// required pointer returns `NullPointer` (7). Callable from any thread.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_encrypt(
    recipient_pub: *const u8,
    plaintext: *const u8,
    plaintext_len: usize,
    out_ciphertext: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    run_ffi(|| {
        if recipient_pub.is_null()
            || out_ciphertext.is_null()
            || out_len.is_null()
            || (plaintext.is_null() && plaintext_len != 0)
        {
            return Err(CoreError::NullPointer);
        }
        let mut pub_bytes = [0u8; 32];
        ptr::copy_nonoverlapping(recipient_pub, pub_bytes.as_mut_ptr(), 32);
        let recipient = PublicIdentity::try_from_public_key_bytes(pub_bytes)?;
        let pt = if plaintext_len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(plaintext, plaintext_len)
        };
        let ct = encrypt(&recipient, pt)?;
        let bytes = ct.as_bytes();
        let ptr = alloc_bytes(bytes)?;
        *out_ciphertext = ptr;
        *out_len = bytes.len();
        Ok(())
    })
}

/// Decrypt ciphertext with recipient secret. Allocates plaintext; caller frees with [`encrypchat_free`].
///
/// # Safety
///
/// `secret` must be valid for reads of exactly 32 bytes. `ciphertext` must be valid for reads
/// of `ciphertext_len` bytes, or null when `ciphertext_len` is 0; anything shorter than 60
/// bytes (`eph_pub(32) || nonce(12) || tag(16)`) returns `CiphertextTooShort` (4). The
/// ciphertext is copied into an owned `Vec` before decryption, so the caller may free it once
/// the call returns. `out_plaintext` must be a non-null slot aligned for `*mut u8` and
/// `out_len` a non-null slot aligned for `usize`; on success they receive a `malloc`ed buffer
/// and its length that the caller owns and must release with exactly one [`encrypchat_free`].
/// On error (including AEAD failure, `DecryptionFailed` (3)) neither out-slot is written. A
/// null required pointer returns `NullPointer` (7). Callable from any thread.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_decrypt(
    secret: *const u8,
    ciphertext: *const u8,
    ciphertext_len: usize,
    out_plaintext: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    run_ffi(|| {
        if secret.is_null()
            || out_plaintext.is_null()
            || out_len.is_null()
            || (ciphertext.is_null() && ciphertext_len != 0)
        {
            return Err(CoreError::NullPointer);
        }
        let mut secret_bytes = Zeroizing::new([0u8; 32]);
        ptr::copy_nonoverlapping(secret, secret_bytes.as_mut_ptr(), 32);
        let id = Identity::from_secret_bytes(*secret_bytes);
        let ct_slice = if ciphertext_len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(ciphertext, ciphertext_len)
        };
        let ct = Ciphertext::from_bytes(ct_slice.to_vec())?;
        let pt = decrypt(&id, &ct)?;
        let ptr = alloc_bytes(&pt)?;
        *out_plaintext = ptr;
        *out_len = pt.len();
        Ok(())
    })
}

/// Seal plaintext for local DB storage with `db_key` (32 bytes).
///
/// # Safety
///
/// `key` must be valid for reads of exactly 32 bytes (the device `db_key`). `plaintext` must
/// be valid for reads of `plaintext_len` bytes, or null when `plaintext_len` is 0 — empty
/// input returns `EmptyPlaintext` (5). Both are only read during the call. `out` must be a
/// non-null slot aligned for `*mut u8` and `out_len` a non-null slot aligned for `usize`; on
/// success they receive a `malloc`ed buffer (`nonce(12) || ct+tag`) and its length, owned by
/// the caller and released with exactly one [`encrypchat_free`]. On error neither out-slot is
/// written. A null required pointer returns `NullPointer` (7). The key is secret material:
/// never log it. Callable from any thread.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_local_seal(
    key: *const u8,
    plaintext: *const u8,
    plaintext_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    run_ffi(|| {
        if key.is_null()
            || out.is_null()
            || out_len.is_null()
            || (plaintext.is_null() && plaintext_len != 0)
        {
            return Err(CoreError::NullPointer);
        }
        let mut key_bytes = Zeroizing::new([0u8; 32]);
        ptr::copy_nonoverlapping(key, key_bytes.as_mut_ptr(), 32);
        let pt = if plaintext_len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(plaintext, plaintext_len)
        };
        let sealed = seal_local(&key_bytes, pt)?;
        let ptr = alloc_bytes(&sealed)?;
        *out = ptr;
        *out_len = sealed.len();
        Ok(())
    })
}

/// Open a local-sealed blob with `db_key`.
///
/// # Safety
///
/// `key` must be valid for reads of exactly 32 bytes. `sealed` must be valid for reads of
/// `sealed_len` bytes, or null when `sealed_len` is 0; anything under 28 bytes
/// (`nonce(12) || tag(16)`) returns `CiphertextTooShort` (4). Inputs are only read during the
/// call. `out` must be a non-null slot aligned for `*mut u8` and `out_len` a non-null slot
/// aligned for `usize`; on success they receive a `malloc`ed plaintext buffer and its length
/// that the caller owns and must release with exactly one [`encrypchat_free`]. On error
/// (including a wrong key, `DecryptionFailed` (3)) neither out-slot is written. A null
/// required pointer returns `NullPointer` (7). Callable from any thread.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_local_open(
    key: *const u8,
    sealed: *const u8,
    sealed_len: usize,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    run_ffi(|| {
        if key.is_null()
            || out.is_null()
            || out_len.is_null()
            || (sealed.is_null() && sealed_len != 0)
        {
            return Err(CoreError::NullPointer);
        }
        let mut key_bytes = Zeroizing::new([0u8; 32]);
        ptr::copy_nonoverlapping(key, key_bytes.as_mut_ptr(), 32);
        let sealed_slice = if sealed_len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(sealed, sealed_len)
        };
        let pt = open_local(&key_bytes, sealed_slice)?;
        let ptr = alloc_bytes(&pt)?;
        *out = ptr;
        *out_len = pt.len();
        Ok(())
    })
}

/// Start a P2P node. On success writes an opaque handle; free with [`encrypchat_node_stop`].
///
/// # Safety
///
/// `secret` must be valid for reads of exactly 32 bytes and is copied into the node before the
/// call returns; the node holds that session-long copy in a zeroizing buffer wiped when
/// [`encrypchat_node_stop`] shuts the runtime down. The caller's own buffer is never modified and
/// stays the caller's to zeroize. `out_handle` must be a non-null slot aligned for `*mut NodeHandle`. Either
/// being null returns `NullPointer` (7). On success `*out_handle` receives a boxed handle that
/// the caller owns and must release with exactly one [`encrypchat_node_stop`]; it must never be
/// passed to [`encrypchat_free`], since it is not a `malloc` allocation. On error `*out_handle`
/// is left untouched. The call blocks up to 5 s while the embedded Tokio runtime binds its TCP
/// listener and returns `Internal` (255) if that times out.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_start(
    secret: *const u8,
    listen_port: u16,
    out_handle: *mut *mut NodeHandle,
) -> i32 {
    run_ffi(|| {
        if secret.is_null() || out_handle.is_null() {
            return Err(CoreError::NullPointer);
        }
        let mut secret_bytes = Zeroizing::new([0u8; 32]);
        ptr::copy_nonoverlapping(secret, secret_bytes.as_mut_ptr(), 32);
        let handle = NodeHandle::start(secret_bytes, listen_port)?;
        *out_handle = Box::into_raw(Box::new(handle));
        Ok(())
    })
}

/// Stop and free a node handle.
///
/// # Safety
///
/// `handle` must be null (no-op) or a pointer produced by [`encrypchat_node_start`] that has not
/// been stopped yet. This call takes ownership and drops it, so passing the same pointer twice,
/// or a pointer from any other source, is undefined behaviour. The caller must guarantee no
/// other thread is inside — or afterwards enters — any `encrypchat_node_*` call with this
/// handle: those entry points build a shared reference and cannot detect the teardown. Inbound
/// frames still queued and not drained by [`encrypchat_node_try_recv`] are dropped.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_stop(handle: *mut NodeHandle) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        let boxed = unsafe { Box::from_raw(handle) };
        boxed.stop();
    }));
}

/// Copy local token into `out_token` (NUL-terminated).
///
/// # Safety
///
/// `handle` must be null or a live handle from [`encrypchat_node_start`] that has not been passed
/// to [`encrypchat_node_stop`]; `out_token` must be valid for writes of `cap` bytes for the
/// duration of the call. Either being null returns `NullPointer` (7). `cap` must be at least 68
/// (`ec_` + 64 hex + NUL) or `BufferTooSmall` (6) is returned. `NodeHandle` is `Sync`, so
/// several threads may share one handle across the read-only `encrypchat_node_*` calls as long
/// as none of them stops it concurrently.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_local_token(
    handle: *mut NodeHandle,
    out_token: *mut c_char,
    cap: usize,
) -> i32 {
    run_ffi(|| {
        if handle.is_null() || out_token.is_null() {
            return Err(CoreError::NullPointer);
        }
        let node = unsafe { &*handle };
        write_cstr(out_token, cap, &node.local_token())
    })
}

/// Send opaque frame bytes to `token_cstr`. Fails with PeerOffline (8) if unknown.
///
/// # Safety
///
/// `handle` must be null or a live handle from [`encrypchat_node_start`]. `token_cstr` must point
/// to a NUL-terminated byte string that stays valid and unmodified for the whole call, with its
/// terminator inside the caller's allocation — no length cap is applied before scanning; contents
/// must be UTF-8 or `InvalidToken` (1) is returned. `frame` must be valid for reads of
/// `frame_len` bytes, or null when `frame_len` is 0. The frame is copied into an owned `Vec`
/// before transmission, so the caller may free it as soon as the call returns; frames over 16 MiB
/// are rejected with `InvalidFrame` (10). Blocks up to 15 s waiting for the peer ACK; unknown or
/// offline peers and ACK timeouts map to `PeerOffline` (8). A null required pointer returns
/// `NullPointer` (7).
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_send(
    handle: *mut NodeHandle,
    token_cstr: *const c_char,
    frame: *const u8,
    frame_len: usize,
) -> i32 {
    run_ffi(|| {
        if handle.is_null() || token_cstr.is_null() || (frame.is_null() && frame_len != 0) {
            return Err(CoreError::NullPointer);
        }
        let node = unsafe { &*handle };
        let token = unsafe { CStr::from_ptr(token_cstr) }
            .to_str()
            .map_err(|_| CoreError::InvalidToken)?;
        let bytes = if frame_len == 0 {
            Vec::new()
        } else {
            unsafe { slice::from_raw_parts(frame, frame_len) }.to_vec()
        };
        node.send_to_token(token, bytes)
    })
}

/// Non-blocking receive. `0` = message in `out`/`out_len`; `9` (Empty) = no message.
///
/// # Safety
///
/// `handle` must be null or a live handle from [`encrypchat_node_start`]; `out` must be a
/// non-null slot aligned for `*mut u8` and `out_len` a non-null slot aligned for `usize`, both
/// valid for the duration of the call. A null pointer returns `NullPointer` (7). On `0` the
/// out-slots hold a `malloc`ed frame and its length, owned by the caller and released with
/// exactly one [`encrypchat_free`]; on `Empty` (9) both slots are left untouched, so the caller
/// must only read them after a `0`. Non-blocking and safe to poll from any thread, but
/// concurrent pollers split the queue — each frame is delivered to exactly one caller.
///
/// Known gap: the frame leaves the inbound queue before its buffer is allocated, so if that
/// `malloc` fails the frame is lost and only `Internal` (255) surfaces. The sender was already
/// sent `MSG_ACK` at that point (the node withholds the ACK only when the queue itself is full),
/// so it considers the message delivered and will not retry. Treat `255` from this call as
/// possible message loss and re-sync at the application layer if that matters.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_try_recv(
    handle: *mut NodeHandle,
    out: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    run_ffi_code(|| {
        if handle.is_null() || out.is_null() || out_len.is_null() {
            return Err(CoreError::NullPointer);
        }
        let node = unsafe { &*handle };
        match node.try_recv() {
            Some(bytes) => {
                let ptr = alloc_bytes(&bytes)?;
                unsafe {
                    *out = ptr;
                    *out_len = bytes.len();
                }
                Ok(0)
            }
            None => Ok(CoreError::Empty.as_code()),
        }
    })
}

/// Replace the local blocklist with `count` tokens read from `tokens`.
///
/// Defence in depth behind the Dart-side block list: a blocked peer is refused a P2P session
/// after EH02, has any live session closed on its next frame, and cannot be sent to.
///
/// # Safety
///
/// `handle` must be null or a live handle from [`encrypchat_node_start`]. `tokens` must be an
/// array of `count` non-null, NUL-terminated UTF-8 C strings, each valid and unmodified for the
/// duration of the call; the array itself may be null when `count` is 0, which clears the list.
/// A null `handle`, a null array with a non-zero `count`, or a null entry returns `NullPointer`
/// (7). Entries are copied into owned Rust strings before the call returns, so the caller may
/// free the array and the strings immediately afterwards.
///
/// The set is **replaced**, never merged, so the caller can keep one source of truth and rewrite
/// it wholesale. Tokens are trimmed and lowercased before comparison; a malformed entry (bad
/// prefix, wrong length, non-hex, or non-UTF-8) returns `InvalidToken` (1) and leaves the
/// previous list untouched, so a partially-applied list can never happen. Callable from any
/// thread while the node runs, including concurrently with other `encrypchat_node_*` calls.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_set_blocked_tokens(
    handle: *mut NodeHandle,
    tokens: *const *const c_char,
    count: usize,
) -> i32 {
    run_ffi(|| {
        if handle.is_null() || (tokens.is_null() && count != 0) {
            return Err(CoreError::NullPointer);
        }
        let node = unsafe { &*handle };
        let mut list: Vec<&str> = Vec::with_capacity(count);
        if count != 0 {
            let raw = unsafe { slice::from_raw_parts(tokens, count) };
            for entry in raw {
                if entry.is_null() {
                    return Err(CoreError::NullPointer);
                }
                let token = unsafe { CStr::from_ptr(*entry) }
                    .to_str()
                    .map_err(|_| CoreError::InvalidToken)?;
                list.push(token);
            }
        }
        node.set_blocked_tokens(&list)
    })
}

/// Write discovered peer count to `out_count`.
///
/// # Safety
///
/// `handle` must be null or a live handle from [`encrypchat_node_start`] and `out_count` a
/// non-null slot aligned for `usize`, valid for the duration of the call; either being null
/// returns `NullPointer` (7). The count is queried from the node's command loop with a 2 s
/// budget; a timeout or a dead loop returns `Internal` (255) and leaves `out_count` untouched,
/// so a written `0` always means "no peers" and never "no answer". Nothing is allocated for
/// the caller.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_peer_count(
    handle: *mut NodeHandle,
    out_count: *mut usize,
) -> i32 {
    run_ffi(|| {
        if handle.is_null() || out_count.is_null() {
            return Err(CoreError::NullPointer);
        }
        let node = unsafe { &*handle };
        let count = node.known_peers()?.len();
        unsafe {
            *out_count = count;
        }
        Ok(())
    })
}

/// Copy first listen multiaddr (e.g. `/ip4/127.0.0.1/tcp/41234`) into `out`.
///
/// # Safety
///
/// `handle` must be null or a live handle from [`encrypchat_node_start`]; `out` must be valid for
/// writes of `cap` bytes for the duration of the call. Either being null returns `NullPointer`
/// (7). Writes the multiaddr plus a NUL terminator, so `cap` must cover it (64 bytes is enough
/// for `/ip4/A.B.C.D/tcp/PORT`) or `BufferTooSmall` (6) is returned with nothing written; a node
/// with no bound address yet returns `Internal` (255).
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_listen_addr(
    handle: *mut NodeHandle,
    out: *mut c_char,
    cap: usize,
) -> i32 {
    run_ffi(|| {
        if handle.is_null() || out.is_null() {
            return Err(CoreError::NullPointer);
        }
        let node = unsafe { &*handle };
        let addrs = node.listen_addrs();
        let s = addrs
            .first()
            .map(|a| a.to_string())
            .ok_or(CoreError::Internal)?;
        write_cstr(out, cap, &s)
    })
}

/// Dial a peer multiaddr (e.g. `/ip4/192.168.1.10/tcp/41234`). Maps peer via hello token.
///
/// # Safety
///
/// `handle` must be null or a live handle from [`encrypchat_node_start`]. `multiaddr_cstr` must
/// point to a NUL-terminated byte string, valid and unmodified for the whole call, with its
/// terminator inside the caller's allocation; the string is only read during the call. Either
/// being null returns `NullPointer` (7); non-UTF-8 input and addresses this build cannot resolve
/// to a socket (only `/ip4` or `/ip6` plus `/tcp`) return `Internal` (255). Blocks up to 10 s
/// while dialing and completing the EH02 handshake. Nothing is allocated for the caller.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_connect(
    handle: *mut NodeHandle,
    multiaddr_cstr: *const c_char,
) -> i32 {
    run_ffi(|| {
        if handle.is_null() || multiaddr_cstr.is_null() {
            return Err(CoreError::NullPointer);
        }
        let node = unsafe { &*handle };
        let raw = unsafe { CStr::from_ptr(multiaddr_cstr) }
            .to_str()
            .map_err(|_| CoreError::Internal)?;
        let addr: multiaddr::Multiaddr = raw.parse().map_err(|_| CoreError::Internal)?;
        node.connect_multiaddr(addr)
    })
}

/// Compute relay PoP proof: SHA-256(domain || ECDH(secret, eph_pub) || nonce || token).
///
/// `out_proof` must point to a 32-byte buffer. `token_cstr` is the destination token
/// (`ec_` + 64 hex). Used by Flutter before `POST /v1/pull`.
///
/// # Safety
///
/// `secret` and `eph_pub` must each be valid for reads of exactly 32 bytes and `out_proof` for
/// writes of exactly [`POP_PROOF_LEN`] (32) bytes. `nonce` must be valid for reads of `nonce_len`
/// bytes, or null when `nonce_len` is 0 as elsewhere in this module; either spelling of an empty
/// nonce is rejected with `AuthFailed` (11), since a proof over no challenge is worthless.
/// `token_cstr` must be a NUL-terminated UTF-8 string valid for the whole call, with its
/// terminator inside the caller's allocation; a malformed token returns `InvalidToken` (1). Any
/// other null pointer returns `NullPointer` (7). Inputs are only read during the call,
/// `out_proof` is written only on success, and nothing is allocated. `secret` is long-term key
/// material — do not log it. Callable from any thread.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_pop_proof(
    secret: *const u8,
    eph_pub: *const u8,
    nonce: *const u8,
    nonce_len: usize,
    token_cstr: *const c_char,
    out_proof: *mut u8,
) -> i32 {
    run_ffi(|| {
        if secret.is_null()
            || eph_pub.is_null()
            || token_cstr.is_null()
            || out_proof.is_null()
            || (nonce.is_null() && nonce_len != 0)
        {
            return Err(CoreError::NullPointer);
        }
        let mut secret_arr = Zeroizing::new([0u8; 32]);
        // `eph_arr` is the relay's ephemeral *public* key: not secret, left bare.
        let mut eph_arr = [0u8; 32];
        unsafe {
            ptr::copy_nonoverlapping(secret, secret_arr.as_mut_ptr(), 32);
            ptr::copy_nonoverlapping(eph_pub, eph_arr.as_mut_ptr(), 32);
        }
        let nonce_slice = if nonce_len == 0 {
            &[][..]
        } else {
            unsafe { slice::from_raw_parts(nonce, nonce_len) }
        };
        let token = unsafe { CStr::from_ptr(token_cstr) }
            .to_str()
            .map_err(|_| CoreError::InvalidToken)?;
        let proof = pop_proof(&secret_arr, &eph_arr, nonce_slice, token)?;
        unsafe {
            ptr::copy_nonoverlapping(proof.as_ptr(), out_proof, POP_PROOF_LEN);
        }
        Ok(())
    })
}

/// Seal `plaintext` for `recipient_pub` binding the sender to the content (relay path).
///
/// Produces an `ECS1` blob: the sender's identity is authenticated by a static-static
/// X25519 DH that only the recipient can verify, and travels encrypted, so the relay
/// learns no more than it does from a plain [`encrypchat_encrypt`] blob. Use this —
/// never [`encrypchat_encrypt`] — for anything enqueued on a relay, and stop putting a
/// `from` field in the payload: the authenticated sender comes out of
/// [`encrypchat_sealed_open`].
///
/// # Safety
///
/// `sender_secret` and `recipient_pub` must each be valid for reads of exactly 32 bytes.
/// `plaintext` must be valid for reads of `plaintext_len` bytes, or null when
/// `plaintext_len` is 0 — an empty plaintext is rejected with `EmptyPlaintext` (5). All
/// inputs are only read during the call. `out_blob` must be a non-null slot aligned for
/// `*mut u8`, `out_len` a non-null slot aligned for `usize`, `out_msg_id` valid for
/// writes of exactly 16 bytes and `out_sent_at` a non-null slot aligned for `u64`; none
/// of them may overlap the inputs. On success `*out_blob` receives a `malloc`ed buffer of
/// `136 + plaintext_len` bytes that the caller owns and must release with exactly one
/// [`encrypchat_free`], and the other three receive the message id and the Unix timestamp
/// bound inside the blob. On any error no out-slot is written. A null required pointer
/// returns `NullPointer` (7); a degenerate `recipient_pub` (small-order point) returns
/// `InvalidPublicKey` (2). `sender_secret` is long-term key material — never log it.
/// Callable from any thread.
// Eight parameters is the price of an out-parameter C ABI: the alternative is a struct
// whose layout the Dart binding would have to mirror exactly.
#[allow(clippy::too_many_arguments)]
#[no_mangle]
pub unsafe extern "C" fn encrypchat_sealed_seal(
    sender_secret: *const u8,
    recipient_pub: *const u8,
    plaintext: *const u8,
    plaintext_len: usize,
    out_blob: *mut *mut u8,
    out_len: *mut usize,
    out_msg_id: *mut u8,
    out_sent_at: *mut u64,
) -> i32 {
    run_ffi(|| {
        if sender_secret.is_null()
            || recipient_pub.is_null()
            || out_blob.is_null()
            || out_len.is_null()
            || out_msg_id.is_null()
            || out_sent_at.is_null()
            || (plaintext.is_null() && plaintext_len != 0)
        {
            return Err(CoreError::NullPointer);
        }
        let mut secret_bytes = Zeroizing::new([0u8; 32]);
        ptr::copy_nonoverlapping(sender_secret, secret_bytes.as_mut_ptr(), 32);
        let sender = Identity::from_secret_bytes(*secret_bytes);

        let mut pub_bytes = [0u8; 32];
        ptr::copy_nonoverlapping(recipient_pub, pub_bytes.as_mut_ptr(), 32);
        let recipient = PublicIdentity::try_from_public_key_bytes(pub_bytes)?;

        let pt = if plaintext_len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(plaintext, plaintext_len)
        };

        let sealed = seal_sender(&sender, &recipient, pt)?;
        let buf = alloc_bytes(&sealed.blob)?;
        ptr::copy_nonoverlapping(sealed.msg_id.as_ptr(), out_msg_id, SEALED_MSG_ID_LEN);
        *out_sent_at = sealed.sent_at_unix;
        *out_blob = buf;
        *out_len = sealed.blob.len();
        Ok(())
    })
}

/// Open an `ECS1` blob and recover the **authenticated** sender.
///
/// `now_unix_secs` is the caller's wall clock in seconds since the Unix epoch; pass `0`
/// to skip the freshness window entirely. With a clock, a blob whose bound `sent_at` is
/// more than 300 s in the future or more than 7 days (the relay's max TTL) in the past is
/// rejected with `Expired` (13) *after* its sender has been authenticated.
///
/// The blob is not replay-proof by itself: `out_msg_id` exists so the caller can drop a
/// duplicate, and the freshness window is what bounds how long that set of seen ids has
/// to live.
///
/// # Safety
///
/// `recipient_secret` must be valid for reads of exactly 32 bytes. `blob` must be valid
/// for reads of `blob_len` bytes, or null when `blob_len` is 0; input that does not start
/// with `ECS1` returns `InvalidFrame` (10) and a truncated `ECS1` blob (137 bytes is the
/// minimum) returns `CiphertextTooShort` (4). The blob is only read during the call.
/// `out_sender_pub` must be valid for writes of exactly 32 bytes, `out_sender_token` for
/// writes of `token_cap` bytes (at least 68, else `BufferTooSmall` (6)), `out_msg_id` for
/// writes of exactly 16 bytes, `out_sent_at_unix` must be a non-null slot aligned for
/// `u64`, `out_plaintext` a non-null slot aligned for `*mut u8` and `out_len` a non-null
/// slot aligned for `usize`; none may overlap. On success `*out_plaintext` holds a
/// `malloc`ed buffer the caller owns and must release with exactly one
/// [`encrypchat_free`]. On any error — including `BufferTooSmall`, where the internal
/// allocation is released before returning — no out-slot is written and nothing leaks. A
/// null required pointer returns `NullPointer` (7). Callable from any thread.
///
/// `DecryptionFailed` (3) means the blob is not addressed to this identity or its header
/// is corrupt; `AuthFailed` (11) means it *is* addressed to us but the sender binding does
/// not hold — a forged sender or a tampered body. Never fall back to a declared sender
/// after `AuthFailed`.
// Ten parameters for the same reason as `encrypchat_sealed_seal`.
#[allow(clippy::too_many_arguments)]
#[no_mangle]
pub unsafe extern "C" fn encrypchat_sealed_open(
    recipient_secret: *const u8,
    blob: *const u8,
    blob_len: usize,
    now_unix_secs: u64,
    out_sender_pub: *mut u8,
    out_sender_token: *mut c_char,
    token_cap: usize,
    out_msg_id: *mut u8,
    out_sent_at_unix: *mut u64,
    out_plaintext: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    run_ffi(|| {
        if recipient_secret.is_null()
            || out_sender_pub.is_null()
            || out_sender_token.is_null()
            || out_msg_id.is_null()
            || out_sent_at_unix.is_null()
            || out_plaintext.is_null()
            || out_len.is_null()
            || (blob.is_null() && blob_len != 0)
        {
            return Err(CoreError::NullPointer);
        }
        let mut secret_bytes = Zeroizing::new([0u8; 32]);
        ptr::copy_nonoverlapping(recipient_secret, secret_bytes.as_mut_ptr(), 32);
        let recipient = Identity::from_secret_bytes(*secret_bytes);

        let blob_slice = if blob_len == 0 {
            &[][..]
        } else {
            slice::from_raw_parts(blob, blob_len)
        };
        let now = if now_unix_secs == 0 {
            None
        } else {
            Some(now_unix_secs)
        };
        let opened = open_sealed(&recipient, blob_slice, now)?;

        // Allocate first, then the only other fallible write: a too-small token buffer
        // must not leave the caller with a buffer it does not know it owns.
        let buf = alloc_bytes(&opened.plaintext)?;
        if let Err(e) = write_cstr(out_sender_token, token_cap, opened.sender.token().as_str()) {
            libc::free(buf as *mut libc::c_void);
            return Err(e);
        }

        let sender_pub = opened.sender.public_key_bytes();
        ptr::copy_nonoverlapping(sender_pub.as_ptr(), out_sender_pub, 32);
        ptr::copy_nonoverlapping(opened.msg_id.as_ptr(), out_msg_id, SEALED_MSG_ID_LEN);
        *out_sent_at_unix = opened.sent_at_unix;
        *out_plaintext = buf;
        *out_len = opened.plaintext.len();
        Ok(())
    })
}

/// Free a buffer returned by encrypt/decrypt/seal/open/try_recv.
///
/// # Safety
///
/// `ptr` must be null (no-op) or the exact pointer written by [`encrypchat_encrypt`],
/// [`encrypchat_decrypt`], [`encrypchat_local_seal`], [`encrypchat_local_open`],
/// [`encrypchat_sealed_seal`], [`encrypchat_sealed_open`] or
/// [`encrypchat_node_try_recv`], passed exactly once and never dereferenced afterwards. Those
/// buffers come from `malloc`, so passing an interior offset, a pointer from another allocator,
/// or a [`NodeHandle`] (which needs [`encrypchat_node_stop`]) is undefined behaviour. The buffer
/// may be freed from a different thread than the one that produced it, but not while another
/// thread still reads it.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_free(ptr: *mut std::ffi::c_void) {
    if ptr.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        unsafe { libc::free(ptr) };
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    const TOKEN_CAP: usize = 68;

    #[test]
    fn api_version_writes_0_8_1() {
        let mut buf = [0u8; 16];
        let rc = unsafe { encrypchat_api_version(buf.as_mut_ptr() as *mut c_char, buf.len()) };
        assert_eq!(rc, 0);
        let s = unsafe { CStr::from_ptr(buf.as_ptr() as *const c_char) };
        assert_eq!(s.to_str().unwrap(), "0.8.1");
    }

    #[test]
    fn identity_generate_and_token() {
        let mut secret = [0u8; 32];
        let mut token_buf = [0u8; TOKEN_CAP];
        let rc = unsafe {
            encrypchat_identity_generate(
                secret.as_mut_ptr(),
                token_buf.as_mut_ptr() as *mut c_char,
                TOKEN_CAP,
            )
        };
        assert_eq!(rc, 0);
        assert!(secret.iter().any(|&b| b != 0));

        let generated = unsafe { CStr::from_ptr(token_buf.as_ptr() as *const c_char) }
            .to_str()
            .unwrap()
            .to_string();
        assert!(generated.starts_with("ec_"));
        assert_eq!(generated.len(), 3 + 64);

        let mut token2 = [0u8; TOKEN_CAP];
        let rc = unsafe {
            encrypchat_identity_token(
                secret.as_ptr(),
                token2.as_mut_ptr() as *mut c_char,
                TOKEN_CAP,
            )
        };
        assert_eq!(rc, 0);
        let derived = unsafe { CStr::from_ptr(token2.as_ptr() as *const c_char) }
            .to_str()
            .unwrap();
        assert_eq!(derived, generated);

        let mut pub_key = [0u8; 32];
        let rc = unsafe { encrypchat_identity_public_key(secret.as_ptr(), pub_key.as_mut_ptr()) };
        assert_eq!(rc, 0);
        assert!(pub_key.iter().any(|&b| b != 0));
    }

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let mut secret = [0u8; 32];
        let mut token_buf = [0u8; TOKEN_CAP];
        assert_eq!(
            unsafe {
                encrypchat_identity_generate(
                    secret.as_mut_ptr(),
                    token_buf.as_mut_ptr() as *mut c_char,
                    TOKEN_CAP,
                )
            },
            0
        );

        let mut pub_key = [0u8; 32];
        assert_eq!(
            unsafe { encrypchat_identity_public_key(secret.as_ptr(), pub_key.as_mut_ptr()) },
            0
        );

        let plaintext = b"hello ffi phase 4";
        let mut out_ct: *mut u8 = ptr::null_mut();
        let mut out_ct_len: usize = 0;
        let rc = unsafe {
            encrypchat_encrypt(
                pub_key.as_ptr(),
                plaintext.as_ptr(),
                plaintext.len(),
                &mut out_ct,
                &mut out_ct_len,
            )
        };
        assert_eq!(rc, 0);
        assert!(!out_ct.is_null());
        assert!(out_ct_len >= 32 + 12 + 16);

        let mut out_pt: *mut u8 = ptr::null_mut();
        let mut out_pt_len: usize = 0;
        let rc = unsafe {
            encrypchat_decrypt(
                secret.as_ptr(),
                out_ct,
                out_ct_len,
                &mut out_pt,
                &mut out_pt_len,
            )
        };
        assert_eq!(rc, 0);
        assert!(!out_pt.is_null());
        let recovered = unsafe { slice::from_raw_parts(out_pt, out_pt_len) };
        assert_eq!(recovered, plaintext);

        unsafe {
            encrypchat_free(out_ct as *mut _);
            encrypchat_free(out_pt as *mut _);
        }
    }

    #[test]
    fn local_seal_open_roundtrip() {
        let key = [0x42u8; 32];
        let plaintext = b"db body";
        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len: usize = 0;
        assert_eq!(
            unsafe {
                encrypchat_local_seal(
                    key.as_ptr(),
                    plaintext.as_ptr(),
                    plaintext.len(),
                    &mut out,
                    &mut out_len,
                )
            },
            0
        );
        let mut pt: *mut u8 = ptr::null_mut();
        let mut pt_len: usize = 0;
        assert_eq!(
            unsafe { encrypchat_local_open(key.as_ptr(), out, out_len, &mut pt, &mut pt_len) },
            0
        );
        let recovered = unsafe { slice::from_raw_parts(pt, pt_len) };
        assert_eq!(recovered, plaintext);
        unsafe {
            encrypchat_free(out as *mut _);
            encrypchat_free(pt as *mut _);
        }
    }

    #[test]
    fn null_pointer_rejected() {
        let rc = unsafe { encrypchat_api_version(ptr::null_mut(), 8) };
        assert_eq!(rc, CoreError::NullPointer.as_code());
    }

    #[test]
    fn buffer_too_small() {
        let mut secret = [0u8; 32];
        let mut tiny = [0u8; 4];
        let rc = unsafe {
            encrypchat_identity_generate(
                secret.as_mut_ptr(),
                tiny.as_mut_ptr() as *mut c_char,
                tiny.len(),
            )
        };
        assert_eq!(rc, CoreError::BufferTooSmall.as_code());
    }

    /// `BufferTooSmall` must be a clean failure: no key material may reach the caller on an
    /// error path, because a buffer the caller believes was never filled never gets zeroized.
    #[test]
    fn buffer_too_small_leaves_out_secret_untouched() {
        let mut secret = [0xA5u8; 32];
        let mut tiny = [0xA5u8; 8];
        let rc = unsafe {
            encrypchat_identity_generate(
                secret.as_mut_ptr(),
                tiny.as_mut_ptr() as *mut c_char,
                tiny.len(),
            )
        };
        assert_eq!(rc, CoreError::BufferTooSmall.as_code());
        assert_eq!(secret, [0xA5u8; 32], "secret buffer must survive intact");
        assert_eq!(tiny, [0xA5u8; 8], "token buffer must survive intact");
    }

    #[test]
    fn empty_plaintext_rejected() {
        let mut secret = [0u8; 32];
        let mut token_buf = [0u8; TOKEN_CAP];
        unsafe {
            encrypchat_identity_generate(
                secret.as_mut_ptr(),
                token_buf.as_mut_ptr() as *mut c_char,
                TOKEN_CAP,
            );
        }
        let mut pub_key = [0u8; 32];
        unsafe { encrypchat_identity_public_key(secret.as_ptr(), pub_key.as_mut_ptr()) };

        let mut out_ct: *mut u8 = ptr::null_mut();
        let mut out_ct_len: usize = 0;
        let rc = unsafe {
            encrypchat_encrypt(
                pub_key.as_ptr(),
                ptr::null(),
                0,
                &mut out_ct,
                &mut out_ct_len,
            )
        };
        assert_eq!(rc, CoreError::EmptyPlaintext.as_code());
    }

    #[test]
    fn try_recv_empty_before_start_messages() {
        let mut secret = [0u8; 32];
        let mut token_buf = [0u8; TOKEN_CAP];
        unsafe {
            encrypchat_identity_generate(
                secret.as_mut_ptr(),
                token_buf.as_mut_ptr() as *mut c_char,
                TOKEN_CAP,
            );
        }
        let mut handle: *mut NodeHandle = ptr::null_mut();
        let rc = unsafe { encrypchat_node_start(secret.as_ptr(), 0, &mut handle) };
        assert_eq!(rc, 0);
        assert!(!handle.is_null());

        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len: usize = 0;
        let rc = unsafe { encrypchat_node_try_recv(handle, &mut out, &mut out_len) };
        assert_eq!(rc, CoreError::Empty.as_code());

        let mut count: usize = 999;
        assert_eq!(unsafe { encrypchat_node_peer_count(handle, &mut count) }, 0);
        assert_eq!(count, 0);

        unsafe { encrypchat_node_stop(handle) };
    }

    #[test]
    fn set_blocked_tokens_ffi_contract() {
        let mut secret = [0u8; 32];
        let mut token_buf = [0u8; TOKEN_CAP];
        unsafe {
            encrypchat_identity_generate(
                secret.as_mut_ptr(),
                token_buf.as_mut_ptr() as *mut c_char,
                TOKEN_CAP,
            );
        }
        let mut handle: *mut NodeHandle = ptr::null_mut();
        assert_eq!(
            unsafe { encrypchat_node_start(secret.as_ptr(), 0, &mut handle) },
            0
        );

        let blocked = std::ffi::CString::new(Identity::generate().token().as_str()).unwrap();
        let bad = std::ffi::CString::new("nope").unwrap();

        // Empty list: a null array is legal when count is 0.
        assert_eq!(
            unsafe { encrypchat_node_set_blocked_tokens(handle, ptr::null(), 0) },
            0
        );

        let one = [blocked.as_ptr()];
        assert_eq!(
            unsafe { encrypchat_node_set_blocked_tokens(handle, one.as_ptr(), 1) },
            0
        );

        let with_bad = [blocked.as_ptr(), bad.as_ptr()];
        assert_eq!(
            unsafe { encrypchat_node_set_blocked_tokens(handle, with_bad.as_ptr(), 2) },
            CoreError::InvalidToken.as_code()
        );

        let with_null = [blocked.as_ptr(), ptr::null()];
        assert_eq!(
            unsafe { encrypchat_node_set_blocked_tokens(handle, with_null.as_ptr(), 2) },
            CoreError::NullPointer.as_code()
        );
        assert_eq!(
            unsafe { encrypchat_node_set_blocked_tokens(ptr::null_mut(), one.as_ptr(), 1) },
            CoreError::NullPointer.as_code()
        );
        assert_eq!(
            unsafe { encrypchat_node_set_blocked_tokens(handle, ptr::null(), 1) },
            CoreError::NullPointer.as_code()
        );

        unsafe { encrypchat_node_stop(handle) };
    }

    #[test]
    fn pop_proof_ffi_matches_rust() {
        let id = Identity::generate();
        let eph = crate::pop::pop_generate_ephemeral();
        let nonce = crate::pop::pop_generate_nonce();
        let token = id.token();
        let mut out = [0u8; 32];
        let token_c = std::ffi::CString::new(token.as_str()).unwrap();
        let rc = unsafe {
            encrypchat_pop_proof(
                id.to_secret_bytes().as_ptr(),
                eph.public.as_ptr(),
                nonce.as_ptr(),
                nonce.len(),
                token_c.as_ptr(),
                out.as_mut_ptr(),
            )
        };
        assert_eq!(rc, 0);
        let expected =
            pop_proof(&id.to_secret_bytes(), &eph.public, &nonce, token.as_str()).unwrap();
        assert_eq!(out, expected);
        assert!(crate::pop::pop_verify(
            &eph.secret,
            &id.public_key_bytes(),
            &nonce,
            token.as_str(),
            &out
        )
        .unwrap());
    }

    /// Helper mirroring the Dart binding: every out-parameter allocated, nothing shared.
    #[allow(clippy::type_complexity)]
    fn sealed_open_ffi(
        secret: &[u8; 32],
        blob: &[u8],
        now: u64,
    ) -> Result<(String, [u8; 32], [u8; 16], u64, Vec<u8>), i32> {
        let mut sender_pub = [0u8; 32];
        let mut token = [0u8; TOKEN_CAP];
        let mut msg_id = [0u8; 16];
        let mut sent_at: u64 = 0;
        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len: usize = 0;
        let rc = unsafe {
            encrypchat_sealed_open(
                secret.as_ptr(),
                blob.as_ptr(),
                blob.len(),
                now,
                sender_pub.as_mut_ptr(),
                token.as_mut_ptr() as *mut c_char,
                TOKEN_CAP,
                msg_id.as_mut_ptr(),
                &mut sent_at,
                &mut out,
                &mut out_len,
            )
        };
        if rc != 0 {
            return Err(rc);
        }
        let plaintext = unsafe { slice::from_raw_parts(out, out_len) }.to_vec();
        unsafe { encrypchat_free(out as *mut _) };
        let token = unsafe { CStr::from_ptr(token.as_ptr() as *const c_char) }
            .to_str()
            .unwrap()
            .to_string();
        Ok((token, sender_pub, msg_id, sent_at, plaintext))
    }

    fn sealed_seal_ffi(secret: &[u8; 32], recipient_pub: &[u8; 32], plaintext: &[u8]) -> Vec<u8> {
        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len: usize = 0;
        let mut msg_id = [0u8; 16];
        let mut sent_at: u64 = 0;
        let rc = unsafe {
            encrypchat_sealed_seal(
                secret.as_ptr(),
                recipient_pub.as_ptr(),
                plaintext.as_ptr(),
                plaintext.len(),
                &mut out,
                &mut out_len,
                msg_id.as_mut_ptr(),
                &mut sent_at,
            )
        };
        assert_eq!(rc, 0);
        assert!(sent_at > 0, "seal must bind a real timestamp");
        assert_ne!(msg_id, [0u8; 16]);
        let blob = unsafe { slice::from_raw_parts(out, out_len) }.to_vec();
        unsafe { encrypchat_free(out as *mut _) };
        blob
    }

    #[test]
    fn sealed_roundtrip_reports_authenticated_sender() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let blob = sealed_seal_ffi(
            &alice.to_secret_bytes(),
            &bob.public_key_bytes(),
            b"hola por relay",
        );

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let (token, sender_pub, _msg_id, sent_at, plaintext) =
            sealed_open_ffi(&bob.to_secret_bytes(), &blob, now).unwrap();
        assert_eq!(token, alice.token().as_str());
        assert_eq!(sender_pub, alice.public_key_bytes());
        assert_eq!(plaintext, b"hola por relay");
        assert!(sent_at.abs_diff(now) < 60);
    }

    /// The relay P0 seen from the caller's side: a forged sender must surface as
    /// `AuthFailed`, never as a successful open with a wrong token.
    #[test]
    fn sealed_forged_and_tampered_blobs_rejected() {
        let bob = Identity::generate();
        let mallory = Identity::generate();
        let alice = Identity::generate();

        let mut blob = sealed_seal_ffi(
            &mallory.to_secret_bytes(),
            &bob.public_key_bytes(),
            b"soy alice, mandame plata",
        );

        // Swapping in Alice's key where the sender identity lives cannot help: the
        // field is encrypted, so this only corrupts it.
        blob[48..80].copy_from_slice(&alice.public_key_bytes());
        assert_eq!(
            sealed_open_ffi(&bob.to_secret_bytes(), &blob, 0).unwrap_err(),
            CoreError::DecryptionFailed.as_code()
        );

        let mut tampered = sealed_seal_ffi(
            &alice.to_secret_bytes(),
            &bob.public_key_bytes(),
            b"nos vemos a las 8",
        );
        let last = tampered.len() - 1;
        tampered[last] ^= 0xff;
        assert_eq!(
            sealed_open_ffi(&bob.to_secret_bytes(), &tampered, 0).unwrap_err(),
            CoreError::AuthFailed.as_code()
        );
    }

    /// F-10 at the C ABI: the two calls that take a raw recipient key must refuse an alias,
    /// because whatever the caller stores next to that key is keyed by its token.
    #[test]
    fn non_canonical_recipient_key_rejected_by_the_abi() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let alias = crate::pubkey::test_vectors::high_bit_alias(&bob.public_key_bytes());

        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len: usize = 0;
        let rc = unsafe {
            encrypchat_encrypt(alias.as_ptr(), b"hola".as_ptr(), 4, &mut out, &mut out_len)
        };
        assert_eq!(rc, CoreError::InvalidPublicKey.as_code());
        assert!(out.is_null());

        let mut msg_id = [0u8; 16];
        let mut sent_at: u64 = 0;
        let rc = unsafe {
            encrypchat_sealed_seal(
                alice.to_secret_bytes().as_ptr(),
                alias.as_ptr(),
                b"hola".as_ptr(),
                4,
                &mut out,
                &mut out_len,
                msg_id.as_mut_ptr(),
                &mut sent_at,
            )
        };
        assert_eq!(rc, CoreError::InvalidPublicKey.as_code());
        assert!(out.is_null());

        // The canonical spelling of the same key is untouched.
        assert_eq!(
            unsafe {
                encrypchat_encrypt(
                    bob.public_key_bytes().as_ptr(),
                    b"hola".as_ptr(),
                    4,
                    &mut out,
                    &mut out_len,
                )
            },
            0
        );
        unsafe { encrypchat_free(out as *mut _) };
    }

    #[test]
    fn sealed_open_rejects_legacy_blob_and_small_token_buffer() {
        let alice = Identity::generate();
        let bob = Identity::generate();

        let legacy = crate::crypto::encrypt(&bob.public_identity(), b"v1").unwrap();
        assert_eq!(
            sealed_open_ffi(&bob.to_secret_bytes(), legacy.as_bytes(), 0).unwrap_err(),
            CoreError::InvalidFrame.as_code()
        );

        let blob = sealed_seal_ffi(&alice.to_secret_bytes(), &bob.public_key_bytes(), b"hola");
        let mut sender_pub = [0u8; 32];
        let mut token = [0u8; 8];
        let mut msg_id = [0u8; 16];
        let mut sent_at: u64 = 0;
        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len: usize = 0;
        let rc = unsafe {
            encrypchat_sealed_open(
                bob.to_secret_bytes().as_ptr(),
                blob.as_ptr(),
                blob.len(),
                0,
                sender_pub.as_mut_ptr(),
                token.as_mut_ptr() as *mut c_char,
                token.len(),
                msg_id.as_mut_ptr(),
                &mut sent_at,
                &mut out,
                &mut out_len,
            )
        };
        assert_eq!(rc, CoreError::BufferTooSmall.as_code());
        assert!(out.is_null(), "no buffer may be handed back on error");
        assert_eq!(out_len, 0);
        assert_eq!(sender_pub, [0u8; 32]);
    }

    #[test]
    fn sealed_null_and_empty_inputs_rejected() {
        let alice = Identity::generate();
        let bob = Identity::generate();
        let mut out: *mut u8 = ptr::null_mut();
        let mut out_len: usize = 0;
        let mut msg_id = [0u8; 16];
        let mut sent_at: u64 = 0;

        let rc = unsafe {
            encrypchat_sealed_seal(
                alice.to_secret_bytes().as_ptr(),
                bob.public_key_bytes().as_ptr(),
                ptr::null(),
                0,
                &mut out,
                &mut out_len,
                msg_id.as_mut_ptr(),
                &mut sent_at,
            )
        };
        assert_eq!(rc, CoreError::EmptyPlaintext.as_code());

        let rc = unsafe {
            encrypchat_sealed_seal(
                alice.to_secret_bytes().as_ptr(),
                bob.public_key_bytes().as_ptr(),
                b"x".as_ptr(),
                1,
                &mut out,
                &mut out_len,
                ptr::null_mut(),
                &mut sent_at,
            )
        };
        assert_eq!(rc, CoreError::NullPointer.as_code());
    }

    /// An empty nonce is an auth problem, not a null-pointer problem, and both spellings of
    /// "empty" (null + 0, or a real pointer + 0) must agree — the Dart binding sends the
    /// former because it maps empty lists to `nullptr`.
    #[test]
    fn pop_proof_empty_nonce_is_auth_failed() {
        let id = Identity::generate();
        let eph = crate::pop::pop_generate_ephemeral();
        let token_c = std::ffi::CString::new(id.token().as_str()).unwrap();
        let secret = id.to_secret_bytes();
        let empty: [u8; 0] = [];

        for nonce_ptr in [ptr::null(), empty.as_ptr()] {
            let mut out = [0u8; 32];
            let rc = unsafe {
                encrypchat_pop_proof(
                    secret.as_ptr(),
                    eph.public.as_ptr(),
                    nonce_ptr,
                    0,
                    token_c.as_ptr(),
                    out.as_mut_ptr(),
                )
            };
            assert_eq!(rc, CoreError::AuthFailed.as_code());
            assert_eq!(out, [0u8; 32], "no proof may be written on failure");
        }
    }
}
