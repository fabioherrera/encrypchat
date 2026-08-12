//! C ABI bridge for Flutter / native callers (Phase 4).
//!
//! All fallible entry points return `0` on success or a [`CoreError`] code.
//! Allocated buffers must be freed with [`encrypchat_free`].

use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use crate::api_version;
use crate::crypto::{decrypt, encrypt, Ciphertext};
use crate::error::CoreError;
use crate::identity::{Identity, PublicIdentity};
use crate::local_aead::{open_local, seal_local};
use crate::net::NodeHandle;

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

/// Writes semver of the FFI surface, e.g. `"0.5.0"`.
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
        let secret = id.to_secret_bytes();
        ptr::copy_nonoverlapping(secret.as_ptr(), out_secret, 32);
        write_cstr(out_token, token_cap, id.token().as_str())
    })
}

/// Derive token from a 32-byte secret.
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
        let mut bytes = [0u8; 32];
        ptr::copy_nonoverlapping(secret, bytes.as_mut_ptr(), 32);
        let id = Identity::from_secret_bytes(bytes);
        write_cstr(out_token, token_cap, id.token().as_str())
    })
}

/// Derive X25519 public key from a 32-byte secret.
#[no_mangle]
pub unsafe extern "C" fn encrypchat_identity_public_key(
    secret: *const u8,
    out_pub: *mut u8,
) -> i32 {
    run_ffi(|| {
        if secret.is_null() || out_pub.is_null() {
            return Err(CoreError::NullPointer);
        }
        let mut bytes = [0u8; 32];
        ptr::copy_nonoverlapping(secret, bytes.as_mut_ptr(), 32);
        let id = Identity::from_secret_bytes(bytes);
        let pub_bytes = id.public_key_bytes();
        ptr::copy_nonoverlapping(pub_bytes.as_ptr(), out_pub, 32);
        Ok(())
    })
}

/// Encrypt plaintext for `recipient_pub`. Allocates ciphertext; caller frees with [`encrypchat_free`].
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
        let recipient = PublicIdentity::from_public_key_bytes(pub_bytes);
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
        let mut secret_bytes = [0u8; 32];
        ptr::copy_nonoverlapping(secret, secret_bytes.as_mut_ptr(), 32);
        let id = Identity::from_secret_bytes(secret_bytes);
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
        let mut key_bytes = [0u8; 32];
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
        let mut key_bytes = [0u8; 32];
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
        let mut secret_bytes = [0u8; 32];
        ptr::copy_nonoverlapping(secret, secret_bytes.as_mut_ptr(), 32);
        let handle = NodeHandle::start(secret_bytes, listen_port)?;
        *out_handle = Box::into_raw(Box::new(handle));
        Ok(())
    })
}

/// Stop and free a node handle.
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
#[no_mangle]
pub unsafe extern "C" fn encrypchat_node_send(
    handle: *mut NodeHandle,
    token_cstr: *const c_char,
    frame: *const u8,
    frame_len: usize,
) -> i32 {
    run_ffi(|| {
        if handle.is_null()
            || token_cstr.is_null()
            || (frame.is_null() && frame_len != 0)
        {
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

/// Write discovered peer count to `out_count`.
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
        unsafe {
            *out_count = node.known_peers().len();
        }
        Ok(())
    })
}

/// Copy first listen multiaddr (e.g. `/ip4/127.0.0.1/tcp/41234`) into `out`.
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

/// Free a buffer returned by encrypt/decrypt/seal/open/try_recv.
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
    fn api_version_writes_0_5_0() {
        let mut buf = [0u8; 16];
        let rc = unsafe { encrypchat_api_version(buf.as_mut_ptr() as *mut c_char, buf.len()) };
        assert_eq!(rc, 0);
        let s = unsafe { CStr::from_ptr(buf.as_ptr() as *const c_char) };
        assert_eq!(s.to_str().unwrap(), "0.5.0");
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
        assert_eq!(
            unsafe { encrypchat_node_peer_count(handle, &mut count) },
            0
        );
        assert_eq!(count, 0);

        unsafe { encrypchat_node_stop(handle) };
    }
}
