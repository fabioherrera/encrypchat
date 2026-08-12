//! Canonical X25519 public-key encodings (closes F-10 alias identities).
//!
//! ## Why an encoding check is an *identity* control
//!
//! An Encrypchat token is `SHA-256` of the 32 public-key bytes, so the token is only a
//! stable name for a peer if each key has exactly one encoding. X25519 does not give that
//! for free. Per RFC 7748 the u-coordinate is reduced mod `p = 2^255 - 19` and bit 255 is
//! masked off before every Diffie-Hellman, so `S`, `S | (1 << 255)` and any `S + k·p` that
//! still fits in 32 bytes are **the same key** to the curve and *different* keys to a hash.
//!
//! The consequence was a blocklist bypass: a blocked peer sets the high bit of the last byte
//! of its own public key, every DH still matches so the EH02 proof and the `ECS1` sender
//! binding both verify, and it arrives under a token nobody has blocked. Rejecting the alias
//! at the door is what makes "identity = token" true.
//!
//! ## What this does not cover
//!
//! Canonical is not the same as safe. The all-zero key is canonically encoded and still
//! degenerate; small-order points are rejected separately by
//! [`crate::sealed::contributory`], which checks the shared secret rather than the encoding.
//! Both checks are needed and neither implies the other.

use crate::error::CoreError;

/// Length of an X25519 public key.
pub(crate) const PUBLIC_KEY_LEN: usize = 32;

/// `p = 2^255 - 19`, little-endian, as public keys are encoded.
const FIELD_ORDER_LE: [u8; PUBLIC_KEY_LEN] = [
    0xed, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f,
];

/// True when `bytes` is *the* encoding of its u-coordinate rather than one of its aliases.
///
/// The test is the whole 256-bit little-endian value against `p`, which subsumes the masked
/// bit 255: `p` has its top bit clear, so anything with bit 255 set is already `>= p`.
///
/// Branchless, by borrow propagation. The input is public, so this is hygiene rather than a
/// requirement — but a data-dependent early exit here would be a timing signal about a value
/// we are about to reject anyway, and the loop costs nothing.
pub(crate) fn is_canonical_public_key(bytes: &[u8; PUBLIC_KEY_LEN]) -> bool {
    let mut borrow: u16 = 0;
    for i in 0..PUBLIC_KEY_LEN {
        // Underflow sets bit 15: the operands are bytes, so the result of a borrowing
        // subtraction is either in `0..=255` or wrapped into `0xff00..=0xffff`.
        let diff = (bytes[i] as u16)
            .wrapping_sub(FIELD_ORDER_LE[i] as u16)
            .wrapping_sub(borrow);
        borrow = (diff >> 15) & 1;
    }
    // A borrow out of the top byte means `bytes < p`.
    borrow == 1
}

/// [`is_canonical_public_key`] as a guard: [`CoreError::InvalidPublicKey`] on an alias.
pub(crate) fn ensure_canonical_public_key(bytes: &[u8; PUBLIC_KEY_LEN]) -> Result<(), CoreError> {
    if is_canonical_public_key(bytes) {
        Ok(())
    } else {
        Err(CoreError::InvalidPublicKey)
    }
}

#[cfg(test)]
pub(crate) mod test_vectors {
    use super::{FIELD_ORDER_LE, PUBLIC_KEY_LEN};

    /// `p` itself: a non-reduced spelling of `u = 0`, and the smallest one.
    pub(crate) const NON_REDUCED_ZERO: [u8; PUBLIC_KEY_LEN] = FIELD_ORDER_LE;

    /// `2^255 - 1`, the largest non-reduced encoding: `u = 18`.
    pub(crate) fn non_reduced_max() -> [u8; PUBLIC_KEY_LEN] {
        let mut bytes = [0xffu8; PUBLIC_KEY_LEN];
        bytes[PUBLIC_KEY_LEN - 1] = 0x7f;
        bytes
    }

    /// The same key with bit 255 set: masked off before every Diffie-Hellman, so it is the
    /// alias an attacker reaches for first.
    pub(crate) fn high_bit_alias(key: &[u8; PUBLIC_KEY_LEN]) -> [u8; PUBLIC_KEY_LEN] {
        let mut alias = *key;
        alias[PUBLIC_KEY_LEN - 1] |= 0x80;
        alias
    }
}

#[cfg(test)]
mod tests {
    use super::test_vectors::{high_bit_alias, non_reduced_max, NON_REDUCED_ZERO};
    use super::*;
    use crate::identity::Identity;

    #[test]
    fn real_keys_are_canonical() {
        // Whatever the secret, an X25519 public key comes out reduced with bit 255 clear —
        // which is why deriving a token from a key we generated ourselves cannot fail.
        for _ in 0..64 {
            let key = Identity::generate().public_key_bytes();
            assert!(is_canonical_public_key(&key), "{}", hex::encode(key));
        }
    }

    #[test]
    fn boundary_values() {
        let mut p_minus_one = NON_REDUCED_ZERO;
        p_minus_one[0] = 0xec;

        for canonical in [[0u8; 32], [1u8; 32], p_minus_one] {
            assert!(is_canonical_public_key(&canonical));
        }
        for alias in [
            NON_REDUCED_ZERO,
            non_reduced_max(),
            [0xffu8; 32],
            high_bit_alias(&[0u8; 32]),
        ] {
            assert!(!is_canonical_public_key(&alias), "{}", hex::encode(alias));
        }
    }

    #[test]
    fn high_bit_is_rejected_whatever_the_rest_of_the_key_is() {
        for _ in 0..64 {
            let key = Identity::generate().public_key_bytes();
            assert!(!is_canonical_public_key(&high_bit_alias(&key)));
        }
    }

    /// The branchless comparison against an obvious one, over the values most likely to
    /// expose a borrow bug: `p` with one byte nudged either way, plus random keys.
    #[test]
    fn matches_a_naive_comparison() {
        fn naive_less_than_p(bytes: &[u8; 32]) -> bool {
            for i in (0..32).rev() {
                if bytes[i] != FIELD_ORDER_LE[i] {
                    return bytes[i] < FIELD_ORDER_LE[i];
                }
            }
            false
        }

        let mut cases: Vec<[u8; 32]> = vec![[0u8; 32], [0xffu8; 32], FIELD_ORDER_LE];
        for i in 0..32 {
            for delta in [1u8, 0xff] {
                let mut nudged = FIELD_ORDER_LE;
                nudged[i] = nudged[i].wrapping_add(delta);
                cases.push(nudged);
            }
        }
        for _ in 0..256 {
            let key = Identity::generate().public_key_bytes();
            cases.push(key);
            cases.push(high_bit_alias(&key));
        }

        for case in cases {
            assert_eq!(
                is_canonical_public_key(&case),
                naive_less_than_p(&case),
                "{}",
                hex::encode(case)
            );
        }
    }

    #[test]
    fn guard_reports_invalid_public_key() {
        assert!(matches!(
            ensure_canonical_public_key(&NON_REDUCED_ZERO),
            Err(CoreError::InvalidPublicKey)
        ));
        assert!(ensure_canonical_public_key(&[0u8; 32]).is_ok());
    }
}
