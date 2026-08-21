# Requirements: Fathom SQL Parser SDK — v4.0 Release Readiness

**Defined:** 2026-08-13
**Milestone:** v4.0 Release Readiness
**Core Value:** 用户可以对显式选择的 Doris 或 Flink SQL 进行高覆盖、精确诊断且无损 round-trip 的解析与编辑，而不依赖 Doris FE、Flink cluster、数据库、商业闭源 GSP 或通用方言静默回退。

## v4.0 Requirements

Requirements for the v4.0 milestone (Release Readiness — formal 1.0 product release). Each maps to exactly one roadmap phase. Scope confirmed 2026-08-13: 19 requirements across 8 categories, derived from the release-blocker audit of the v3.0 close-out state.

### TC — Toolchain & Reproducibility

- [x] **TC-01**: Release pipeline builds the native release artifacts with a pinned MoonBit toolchain version (release workflow no longer uses `latest`), and records the exact toolchain version into the release artifacts — so a 1.0.0 release binary is reproducible
- [x] **TC-02**: Release CI runs the full release gate matrix before publishing (native/js/wasm three-target parity, `diff_parity --frozen-only`, `check_naming`, corpus `--check`); any failure blocks the release

### HYG — Hygiene

- [x] **HYG-01**: Uncommitted CI changes are committed (`jetbrains-plugin.yml` action bumps: checkout v4→v7, setup-java v4→v5, upload-artifact v4→v7); the working tree is clean before release
- [x] **HYG-02**: Generated-file policy: `fathom-sql/pkg.generated.mbti` and similar `moon info` outputs are covered by `.gitignore`, no longer left untracked in the working tree
- [x] **HYG-03**: `.planning` strays (`research/.cache`, quick-task plan dirs, untracked `milestones/v1.0-research/`) are cleaned or archived and do not enter release commits

### DOC — Documentation

- [x] **DOC-01**: README/GETTING-STARTED stale claims are corrected (Apache-2.0 LICENSE exists and is linked; remote is `tchivs/fathom-sql`); placeholder/contradictory text is removed
- [x] **DOC-02**: README gains an "Install `fathom-lsp` from GitHub Release" section (per-platform assets, SHA-256 verification, install location, version verification command)

### VER — Versioning

- [x] **VER-01**: Product semver policy is defined and recorded (first public version 1.0.0; `fathom.*.v1` wire-contract stability commitment; breaking changes require a contract-version bump)
- [x] **VER-02**: Release binaries report their version via `--version` (`fathom-sql` and `fathom-lsp`), matching the release tag
- [x] **VER-03**: Repository gains a CHANGELOG.md with a 1.0.0 entry covering user-visible changes since the v0.1.0 release
- [x] **VER-04**: A `v1.0.0` tag triggers the `fathom-native-release` pipeline, producing 4-platform release assets plus a SHA-256 manifest

### NPM — JavaScript SDK

- [x] **NPM-01**: `@fathom-sql/sql` is published to npm (binding.js/binding.wasm + TypeScript type declarations); consumers can `npm install` and call parse/format/complete/fingerprint/lineage/lint APIs from Node or browsers
- [x] **NPM-02**: The npm package ships a minimal smoke test (loads in Node and round-trips an example SQL document) and records dialect/profile capability metadata

### VSC — VS Code Extension

- [x] **VSC-01**: VS Code extension is published to Open VSX (and/or VS Code Marketplace) so users install from the marketplace, not from source
- [x] **VSC-02**: Extension README is updated to release-version install instructions (fathom-lsp acquisition and `fathom.serverPath` configuration)

### JBR — IntelliJ Plugin

- [x] **JBR-01**: IntelliJ plugin is published to the JetBrains Marketplace (automated or semi-automated publish job) so users install from the IDE plugin market
- [x] **JBR-02**: Plugin README/compatibility matrix is updated (supported IDE versions, fathom-lsp acquisition)

### DIS — Disclosure

- [x] **DIS-01**: A release-disclosure document (RELEASE-NOTES.md or equivalent) honestly states: Flink coverage is syntax-level (no planner/catalog/type/execution equivalence), Wasm GC is not first-class, corpus provenance has `unavailable-offline` gaps, 5 documented verification overrides, and the toolchain version policy
- [x] **DIS-02**: GitHub Release notes reference the disclosure document so consumers see the boundaries before download

## Future Requirements

Deferred beyond v4.0. Tracked but not in the current roadmap.

### Cross-Dialect / Toolchain Futures

- **FLINK-FUTURE-01**: Flink planner/catalog/type/execution equivalence (runtime-aware analysis)
- **DIALECT-FUTURE-01**: Third-party dialect registry / plugin marketplace
- **CONVERT-FUTURE-01**: Explicit opt-in dialect-to-dialect transpilation
- **EDIT-FUTURE-01**: Benchmark-gated incremental CST / structural editor refactors (EDIT-01 descope holds unless a real latency bottleneck is measured)
- **TARGET-FUTURE-01**: Wasm GC as a first-class supported backend
- **TOOL-FUTURE-01**: Catalog-backed completion, hover, semantic tokens, symbols, richer LSP intelligence

## Out of Scope

| Feature | Reason |
|---------|--------|
| Flink planner/catalog/type/execution semantics | Requires Flink runtime/planner; the SDK is parser-and-toolchain only — disclosed in DIS-01 |
| Full Doris FE semantic/type/EXPLAIN replacement | Requires engine runtime, catalog, session, privilege, optimizer semantics |
| Wasm GC as a first-class backend | Documented optional artifact; JS ESM + linear Wasm are the shipped web surfaces |
| Auto-detection or silent fallback of dialect/profile | Product principle (D-01/02): selection is always explicit, errors are structured |
| Transpilation between dialects | Explicit opt-in future (CONVERT-FUTURE-01); not promised in 1.0 |
| Dependency on Doris FE / Flink cluster / database at runtime | Core independence constraint; offline, self-contained distribution |

## Traceability

Which phases cover which requirements. Populated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TC-01 | Phase 14 | Done |
| TC-02 | Phase 14 | Done |
| HYG-01 | Phase 14 | Done |
| HYG-02 | Phase 14 | Done |
| HYG-03 | Phase 14 | Done |
| DOC-01 | Phase 16 | Done |
| DOC-02 | Phase 16 | Done |
| VER-01 | Phase 15 | Done |
| VER-02 | Phase 15 | Done |
| VER-03 | Phase 17 | Done |
| VER-04 | Phase 20 | Done |
| NPM-01 | Phase 18 | Done |
| NPM-02 | Phase 18 | Done |
| VSC-01 | Phase 19 | Done |
| VSC-02 | Phase 19 | Done |
| JBR-01 | Phase 19 | Done |
| JBR-02 | Phase 19 | Done |
| DIS-01 | Phase 17 | Done |
| DIS-02 | Phase 17 | Done |

**Coverage:**
- v4.0 requirements: 19 total
- Mapped to phases: 19
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-13*
*Last updated: 2026-08-21 — v4.0 complete, all 19 requirements done*
