# Product Versioning Policy (VER-01)

This document is the recorded product semver policy for the Fathom SQL Parser
SDK. It is the contract behind `VER-01` and governs how release binaries
report their version (`VER-02`).

## Version scheme

- The product follows [Semantic Versioning](https://semver.org/) with the
  format `MAJOR.MINOR.PATCH` (e.g. `1.0.0`).
- The first public version is **1.0.0**, published as the `v1.0.0` tag.
- Release binaries report the version string without the leading `v`:
  `fathom-sql --version` prints `fathom-sql 1.0.2`, and
  `fathom-lsp --version` prints `fathom-lsp 1.0.2`, both with exit code 0.
- The single source of the version is `version/version.mbt`
  (`product_version()`). Binaries never carry a second constant.

## Wire-contract stability commitment

- The `fathom.*.v1` wire namespaces (`fathom.parse.v1`, `fathom.format.v1`,
  `fathom.error.v1`, `fathom.dialect.v1`, `fathom.capabilities.v1`,
  `fathom.complete.v1`, `fathom.lint.v1`, `fathom.fingerprint.v1`) are stable
  contracts for the entire 1.x line.
- Backwards-compatible additive changes (new fields, new optional exports) are
  allowed within a `.v1` namespace as long as existing consumers keep working.
- **Breaking changes** (renaming/removing fields or exports, changing
  semantics, changing error codes) require a **contract-version bump** (e.g.
  `fathom.parse.v2`) and a documented migration note. The old namespace is
  retained alongside the new one for at least one minor release.

## Version bump process

1. Edit `product_version()` in `version/version.mbt` to the new semver.
2. Create the matching `vX.Y.Z` tag for the release (Phase 20 owns the formal
   release event; the release workflow asserts the binary `--version` matches
   the tag on every platform).
3. Record user-visible changes in `CHANGELOG.md` (Phase 17 owns the
   changelog process).
4. A breaking wire change additionally bumps the affected `fathom.*.v1`
   namespace to `.v2` and adds the migration note.

## Module vs product version

- `moon.mod`'s module version stays `0.1.0` (Phase 13 release-planning
  decision). The module version is an internal build identity and is
  **decoupled** from the product semver reported by release binaries.
