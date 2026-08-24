# Changelog

All notable user-visible changes to the Fathom SQL Parser SDK are documented
in this file. The prior public baseline is the `v0.1.0` release.

## [1.0.2] - 2026-08-21

### Changed

- **README five-channel install table**: npm SDK, VS Code extension, JetBrains
  plugin, LSP binary, and MoonBit library — each with badge, link, and
  quick-start snippet (en + zh-CN).
- **README badge header**: 12 dynamic shields.io badges (release, npm, VS Code
  Marketplace, CI, license, MoonBit, targets, Doris, Flink, last-commit,
  repo-size, stars).
- **CI fixes**: `moon fmt` compliance (120 files reformatted); corrected
  `approved-changes.md` path in `ci.yml`; added `--offline` flag to web smoke;
  `moon check --target js/wasm` now scoped to cross-platform packages (excludes
  native-only C FFI in `lsp/` and `fathom-sql/`).
- **Sub-channel README unification**: npm, VS Code, JetBrains, and web READMEs
  now carry consistent badge headers (channel-relevant badges + Doris/Flink/
  MoonBit) and `> Part of Fathom SQL Parser SDK` back-links to the root README.
  New `web/README.md` created.
- **453 MoonBit compiler warnings eliminated** (496→43): reserved-keyword
  renames (`ref`→`name_ref`, `alias`→`alias_name`, `method`→`method_name`;
  171 warnings; JSON-RPC wire keys preserved), missing `debug`/`buffer` imports
  in 5 `moon.pkg` files (48 warnings), test-target import separation (20
  warnings), `priv` on internal types, duplicate test name, redundant modifier.
- **AI context docs**: root `CLAUDE.md` (project overview + Mermaid architecture
  diagram + 28-module index) and 27 module-level `CLAUDE.md` files (breadcrumb
  navigation, responsibilities, public APIs, dependencies, tests, design
  constraints). GSD `Conventions`/`Architecture` placeholders populated.

### Fixed

- JetBrains `source-smoke.py` excluded `CLAUDE.md` from its forbidden-URL scan
  (shields.io badge URLs were falsely flagged as "remote fallback").

## [1.0.1] - 2026-08-21

### Added

- **Position helper functions**: `byteOffsetToLineColumn(raw, byteOffset)`,
  `lineColumnToByteOffset(raw, line, column)`, and
  `withLineColumns(raw, diagnostics)` — pure-JS utilities that convert
  between UTF-8 byte offsets (returned by diagnostics) and 0-based
  `{ line, column }` positions for editor highlighting. Column counts
  Unicode code points, not UTF-16 units.
- **npm package renamed**: `@fathom/sql` → `@fathom-sql/sql` (org
  `fathom-sql`); npm-publish workflow's version assertion now trusts the
  manifest on `workflow_dispatch` (previously compared against
  `GITHUB_REF_NAME=master` and failed).
- **CONTRIBUTING.md**: commit message conventions (Conventional Commits) and
  GitHub auto-close-issue keyword rules (`Fixes #N`).

### Fixed

- npm version-assertion bug on `workflow_dispatch` (compared tag-derived
  version against `master` instead of trusting the manifest).
- npm README completely rewritten with features, Node/browser examples, API
  table, TypeScript types, and GitHub links.
- **`lint()` crash (issue #1)**: the npm wrapper called
  `fathom_lint_v1` with only 4 of its 6 arguments, leaving `overrides`
  `undefined`; the binding then threw
  `TypeError: Cannot read properties of undefined (reading 'length')` on
  every call, for every dialect/profile/mode. The wrapper now passes empty
  overrides (`new Uint8Array()`) and `fix=false`, matching the documented
  `lint(raw, dialect, profile, mode?)` public signature. Smoke test gained
  a regression case covering flink/doris × strict/editor.

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
  toolchain is content-locked (`moon 0.1.20260819`) with official sidecar
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
