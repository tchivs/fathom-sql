# Fathom SQL Parser SDK — Release Notes & Boundary Disclosure

> **Please read this document before downloading release assets.** It states
> the honest boundaries of the 1.0.0 release so consumers can decide whether
> the SDK fits their use case.

## 1. Flink coverage is syntax-level

The SDK's Flink SQL support is **syntax-level only**. It provides lexical and
grammar coverage, structured diagnostics, and formatting for Flink SQL
constructs, but it performs **no planning, catalog resolution, type checking,
or execution equivalence** for the Flink engine. There is no Flink runtime or
planner dependency; do not expect the SDK to validate semantics the Flink
engine would enforce.

## 2. Wasm GC is not first-class

The official web/JS surface advertises **linear Wasm and JavaScript**.
Wasm GC is not a first-class compatibility target and is not part of the
supported release matrix.

## 3. Corpus provenance has gaps

Some corpus fixture revisions are recorded as `unavailable-offline` /
`known-gap`: their authoritative upstream state could not be verified in the
offline environment. No SHA-256 or provenance value is fabricated for those
records; they are disclosed rather than invented.

## 4. Documented verification overrides

This release carries **5 documented verification overrides** (historically
deferred or closed-by-record items). They are enumerated in
`.planning/STATE.md` → Deferred Items (known verification overrides). None of
them hides a known product defect; each records an honest boundary of
verification coverage.

## 5. Toolchain version policy

- The release toolchain is **content-locked** to `moon 0.1.20260807` via
  `.github/moonbit-toolchain.json`, with official SHA-256 sidecar
  verification for the binary archives on all three release platforms
  (Linux x86_64, macOS Apple Silicon, Windows x86_64).
- **Core (stdlib) digests are recorded** — the official MoonBit distribution
  publishes no checksum for the core archives, so digests are computed at
  freeze time and documented (see `docs/VERSIONING.md` and the Phase 14
  decision records).
- **macOS Intel is not a release target** — the official MoonBit channel
  ships no Intel-macOS build (verified across all official channels,
  2026-08-14); ARM64 binaries cannot run on Intel hardware.
- Product version `1.0.0` is decoupled from the `moon.mod` module version
  `0.1.0` (see `docs/VERSIONING.md`).

## Further reading

- Semver policy: `docs/VERSIONING.md`
- Install `fathom-lsp` from GitHub Release: README "Install `fathom-lsp` from
  GitHub Release"
- API reference: `docs/API.md`
