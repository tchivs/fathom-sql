# Changelog

All notable user-visible changes to the Fathom SQL Parser SDK are documented
in this file. The prior public baseline is the `v0.1.0` release; this
changelog covers the changes shipped in `1.0.0`.

## [1.0.0] - 2026-08-17

### Added

- **Lossless CST core**: source-fidelity parsing that preserves byte spans,
  comments, whitespace, and trivia; the printer replays original bytes
  (`print_lossless`) or configured formatting without data loss.
- **Doris profile-aware parsing**: `2.1`, `3.x`, and `4.x` profiles with
  version and feature-introduction validation through profile metadata; two
  modes — `strict` (strict validation) and `editor` (error recovery for
  incomplete SQL).
- **Structured diagnostics**: stable `FATHOM-PARSE-*` codes with messages,
  severities, byte ranges, and statement IDs.
- **CST formatting**: keyword case, indentation, line width, comma style,
  newline style, and trailing-newline policy; refusal (no partial output) on
  error trees.
- **Native CLI**: `fathom-sql` subcommands `parse`, `format`, `lsp`, `lint`,
  `fingerprint`, and `lineage` with explicit `--dialect`/`--profile`
  selection and a documented exit-code contract (0 accepted / 1 refusal /
  2 usage).
- **Multi-dialect abstraction**: a dialect layer with syntax-level Flink SQL
  support alongside Doris; product-neutral wire identity.
- **Catalog-injected analysis**: optional name resolution and lineage through
  a caller-provided `Catalog`; no metadata dependency for pure syntax checks.
- **Stable wire contracts**: `fathom.*.v1` namespaces for parse, format,
  error, dialect, capabilities, completion, lint, and fingerprint.
- **JavaScript and linear-Wasm facades**: browser/Node integration surface
  plus editor integrations (VS Code, IntelliJ, Monaco web demo).
- **Three-platform native release assets**: Linux x86_64, macOS (Apple
  Silicon), and Windows x86_64 binaries with SHA-256 manifests; the MoonBit
  toolchain is content-locked (`moon 0.1.20260807`) with official sidecar
  verification.
- **Product versioning**: `fathom-sql --version` and `fathom-lsp --version`
  report `1.0.0` (exit 0); see `docs/VERSIONING.md` for the semver policy.
- **Install guide**: prebuilt `fathom-lsp` install from GitHub Release with
  SHA-256 verification (see README).

### Changed

- Wire contracts migrated to the neutral `fathom.*.v1` naming (previously
  `doris.*.v1`).
- Release toolchain no longer floats `latest`; builds are reproducible from
  the committed toolchain lock.
- macOS Intel is no longer a release target (the official MoonBit channel
  ships no Intel-macOS build); see `RELEASE-NOTES.md`.

### Fixed

- Stale and false documentation claims (LICENSE status, toolchain version,
  repository placeholders) corrected.
- CLI exit-code and usage semantics made explicit and tested.
