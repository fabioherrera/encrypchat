//! Decoders must not let a remote number decide how much memory to reserve.
//!
//! "No panic" is the property the proptest module in `src/fuzz.rs` asserts. This file asserts
//! the other half of the same promise, and the one a test cannot see by looking at return
//! values: a decoder handed 40 bytes that *claim* to carry 4 GiB must allocate for the 40.
//! The failure mode is not a crash — the code is correct in every other sense — it is a phone
//! or a relay that dies of memory exhaustion on a packet an attacker sent for free.
//!
//! Measuring it needs a global allocator, which is why this lives in its own test binary: the
//! counters are process-wide, so every test here takes [`MEASURE`] and no other test shares
//! the process.

use std::alloc::{GlobalAlloc, Layout, System};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, MutexGuard};

use encrypchat_core::{
    decode_frame, decrypt, open_local, open_sealed, pop_verify, seal_local, seal_sender,
    Ciphertext, Identity, SEALED_MAGIC,
};

static LIVE: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);

struct Counting;

impl Counting {
    fn record(delta: usize) {
        let live = LIVE.fetch_add(delta, Ordering::Relaxed) + delta;
        PEAK.fetch_max(live, Ordering::Relaxed);
    }
}

unsafe impl GlobalAlloc for Counting {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let ptr = unsafe { System.alloc(layout) };
        if !ptr.is_null() {
            Self::record(layout.size());
        }
        ptr
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        LIVE.fetch_sub(layout.size(), Ordering::Relaxed);
        unsafe { System.dealloc(ptr, layout) }
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let out = unsafe { System.realloc(ptr, layout, new_size) };
        if !out.is_null() {
            LIVE.fetch_sub(layout.size(), Ordering::Relaxed);
            Self::record(new_size);
        }
        out
    }
}

#[global_allocator]
static ALLOC: Counting = Counting;

/// Only one measurement at a time: the counters belong to the process.
static MEASURE: Mutex<()> = Mutex::new(());

fn measure() -> MutexGuard<'static, ()> {
    MEASURE.lock().unwrap_or_else(|e| e.into_inner())
}

/// Peak live bytes reached while `f` runs, over the baseline at entry.
///
/// `f` runs once first and is not measured: the first call through a code path can pull in
/// one-off initialisation that has nothing to do with the input.
fn peak_extra_bytes<T>(mut f: impl FnMut() -> T) -> usize {
    let _guard = measure();
    drop(f());
    let base = LIVE.load(Ordering::Relaxed);
    PEAK.store(base, Ordering::Relaxed);
    let out = f();
    let peak = PEAK.load(Ordering::Relaxed);
    drop(out);
    peak.saturating_sub(base)
}

/// Room for the bookkeeping a decode does regardless of input: an error type, a token string,
/// a `Vec` that grows by doubling. Deliberately small — the point is that it does not scale
/// with a number the sender chose.
const SLACK: usize = 4 * 1024;

fn assert_bounded(what: &str, input_len: usize, peak: usize) {
    let budget = input_len * 2 + SLACK;
    assert!(
        peak <= budget,
        "{what}: {input_len} bytes of input caused {peak} bytes of allocation (budget {budget})"
    );
}

/// `ct_len` is a `u32` the peer chooses and the decoder must not believe. The frame below
/// claims 4 GiB of ciphertext and carries none.
#[test]
fn decode_frame_ignores_a_declared_length_it_cannot_back() {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"EC04");
    bytes.push(1);
    bytes.extend_from_slice(&[0u8; 16]);
    let token = Identity::from_secret_bytes([0x11; 32]).token();
    bytes.extend_from_slice(&(token.as_str().len() as u16).to_be_bytes());
    bytes.extend_from_slice(token.as_str().as_bytes());
    bytes.extend_from_slice(&u32::MAX.to_be_bytes());
    bytes.extend_from_slice(b"nope");

    let peak = peak_extra_bytes(|| decode_frame(&bytes));
    assert_bounded("decode_frame with a 4 GiB ct_len", bytes.len(), peak);
}

/// The same for the token field, whose `u16` is small enough to look harmless and large enough
/// to matter when every connection can send one.
#[test]
fn decode_frame_ignores_an_oversized_token_length() {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"EC04");
    bytes.push(1);
    bytes.extend_from_slice(&[0u8; 16]);
    bytes.extend_from_slice(&u16::MAX.to_be_bytes());
    bytes.extend_from_slice(b"ec_");
    bytes.extend_from_slice(&1u32.to_be_bytes());
    bytes.push(0);

    let peak = peak_extra_bytes(|| decode_frame(&bytes));
    assert_bounded("decode_frame with a 64 KiB token_len", bytes.len(), peak);
}

/// The relay route: a truncated `ECS1` blob is the cheapest thing an attacker can put in a
/// mailbox, and it must cost the recipient as little as it cost them.
#[test]
fn open_sealed_is_bounded_by_the_blob_it_was_given() {
    let bob = Identity::from_secret_bytes([0x22; 32]);
    let truncated = {
        let mut blob = Vec::from(*SEALED_MAGIC);
        blob.extend_from_slice(&[0xAB; 8]);
        blob
    };
    let peak = peak_extra_bytes(|| open_sealed(&bob, &truncated, None));
    assert_bounded("open_sealed on a truncated blob", truncated.len(), peak);

    // And a blob that does open allocates for its own payload, not for a multiple of it.
    let alice = Identity::from_secret_bytes([0x11; 32]);
    let sealed = seal_sender(&alice, &bob.public_identity(), &[7u8; 4096]).expect("seal");
    let peak = peak_extra_bytes(|| open_sealed(&bob, &sealed.blob, None));
    assert_bounded("open_sealed on a valid blob", sealed.blob.len(), peak);
}

/// The at-rest and legacy-payload decoders, which read a length-free format but still take a
/// slice whose tail is attacker-controlled.
#[test]
fn aead_decoders_are_bounded_by_their_input() {
    let short = [0u8; 5];
    let peak = peak_extra_bytes(|| open_local(&[3u8; 32], &short));
    assert_bounded("open_local on a stub", short.len(), peak);

    let sealed = seal_local(&[3u8; 32], &[9u8; 4096]).expect("seal");
    let peak = peak_extra_bytes(|| open_local(&[3u8; 32], &sealed));
    assert_bounded("open_local on a valid blob", sealed.len(), peak);

    let bob = Identity::from_secret_bytes([0x22; 32]);
    let garbage = Ciphertext::from_bytes(vec![0u8; 128]).expect("long enough");
    let peak = peak_extra_bytes(|| decrypt(&bob, &garbage));
    assert_bounded("decrypt on garbage", 128, peak);
}

/// Control. Every assertion above is of the form "this number stayed small", which is also
/// what a broken measurement reports. This one has to see a large allocation, or the other
/// four are decoration.
#[test]
fn the_measurement_notices_an_unbounded_allocation() {
    let peak = peak_extra_bytes(|| vec![0u8; 8 * 1024 * 1024]);
    assert!(
        peak >= 8 * 1024 * 1024,
        "the allocator hook missed an 8 MiB allocation (saw {peak})"
    );
}

/// The relay's own hot path, reached before anything about the caller is known.
#[test]
fn pop_verify_is_bounded_by_its_request() {
    let dest = Identity::from_secret_bytes([0x11; 32]).token();
    let nonce = vec![0u8; 64];
    let peak =
        peak_extra_bytes(|| pop_verify(&[1u8; 32], &[2u8; 32], &nonce, dest.as_str(), &[3u8; 32]));
    assert_bounded("pop_verify", nonce.len() + dest.as_str().len(), peak);
}
