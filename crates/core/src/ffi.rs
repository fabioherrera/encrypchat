//! C ABI bridge for Flutter / native callers (Phase 3).
//!
//! All fallible entry points return `0` on success or a [`CoreError`] code.
//! Allocated buffers from encrypt/decrypt must be freed with [`encrypchat_free`].

use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use crate::crypto::{decrypt, encrypt, Ciphertext};
use crate::error::CoreError;
use crate::identity::{Identity, PublicIdentity};
use crate::api_version;

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

/// Writes semver of the FFI surface, e.g. `"0.3.0"`.
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

/// Free a buffer returned by encrypt/decrypt (or any `malloc`-compatible pointer).
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
    fn api_version_writes_0_3_0() {
        let mut buf = [0u8; 16];
        let rc = unsafe {
            encrypchat_api_version(buf.as_mut_ptr() as *mut c_char, buf.len())
        };
        assert_eq!(rc, 0);
        let s = unsafe { CStr::from_ptr(buf.as_ptr() as *const c_char) };
        assert_eq!(s.to_str().unwrap(), "0.3.0");
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

        let plaintext = b"hello ffi phase 3";
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
}
