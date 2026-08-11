/// FNV-1a 64-bit pure hash (D-07): canonical bytes -> UInt64.
///
/// Cross-target stability: `UInt64` is fixed 64-bit on Native, JS, and linear
/// Wasm (STACK.md verified — `Int` is 32-bit on Wasm/C and `number` on JS),
/// which is exactly why FING-01 fingerprints MUST be UInt64-based.
///
/// FNV-1a is a NON-cryptographic hash — it is a cache/diff/CI identifier
/// only, never a MAC / tamper-proof / collision-resistant primitive
/// (RESEARCH Security Domain; prohibitions in 06-01-PLAN).
///
/// Probe conclusion (A1 / Open Question 1, verified 2026-08-10 via
/// `moon check --target native` + `moon test --target native`):
///   - UInt64 literal suffix is `UL` (e.g. `0xcbf29ce484222325UL`).
///   - The infix XOR operator is `^`; `lxor` is the promoted method name
///     (first-class value), not an infix token.
///   - `Byte::to_uint64()` zero-extends a byte; `Int::to_uint64` exists but is
///     deprecated — use the byte method here.
///   - `*` on UInt64 is 64-bit wrapping multiplication (no overflow panic on
///     the FNV prime); the FNV-1a vector `fnv1a64(b"a")` matches the public
///     reference value, so the wrap arithmetic is byte-correct.
const FNV1A_OFFSET_BASIS : UInt64 = 0xcbf29ce484222325UL
const FNV1A_PRIME : UInt64 = 0x100000001b3UL

/// FNV-1a 64-bit over the input bytes. Empty input returns the offset basis.
pub fn fnv1a64(bytes : Bytes) -> UInt64 {
  let mut hash : UInt64 = FNV1A_OFFSET_BASIS
  let mut index = 0
  while index < bytes.length() {
    hash = (hash ^ bytes[index].to_uint64()) * FNV1A_PRIME
    index = index + 1
  }
  hash
}
