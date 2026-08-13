# Roadmap: Fathom SQL Parser SDK

## Overview

v1.0 shipped the lossless CST core, Doris DML/DDL + corpus, configurable formatting + CLI, and Native LSP / JS-Wasm facade / Web-Monaco / VS Code integration (27/27 requirements). v2.0 (redefined 2026-08-06) turned the single-dialect Doris parser into a multi-dialect SQL SDK: a dialect abstraction layer, a Flink SQL dialect across the whole toolchain, and product-neutral naming (binaries/schema/error codes/extensions/docs). v3.0 (Analysis and Intelligence, 2026-08-13) delivered catalog-backed analysis (ANAL-01), Doris lint (LINT-01), stable fingerprints (FING-01), column lineage (LINE-01), and benchmark-gated incremental parsing — EDIT-01 descoped with `moon bench` evidence.

## Milestones

- ✅ **v1.0 — Doris SQL Parser SDK MVP** — Phases 1-4 (shipped 2026-08-05)
- ✅ **v2.0 — Multi-Dialect: Flink SQL & Neutral Naming** — Phases 9-13 (shipped 2026-08-10)
- ✅ **v3.0 — Analysis and Intelligence** — Phases 5-8 (shipped 2026-08-13)

## Phases

<details>
<summary>✅ v1.0 — Doris SQL Parser SDK MVP (Phases 1-4) — SHIPPED 2026-08-05</summary>

- **Archive:** [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) · [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md) · [v1.0-MILESTONE-AUDIT.md](v1.0-MILESTONE-AUDIT.md)
- **Status:** SHIPPED (override_closeout — 5 documented verification overrides in STATE.md Deferred Items)

- [x] Phase 1: Core Kernel — lossless CST, SELECT/Pratt expressions, round-trip
- [x] Phase 2: Doris Completeness and Corpus — DML/DDL + versioned corpus
- [x] Phase 3: Formatting and Safe Edits — CST printer + format CLI
- [x] Phase 4: Ecosystem and Multi-Target Delivery — Native LSP / JS-Wasm / Web / VS Code

</details>

<details>
<summary>✅ v2.0 — Multi-Dialect: Flink SQL & Neutral Naming (Phases 9-13) — SHIPPED 2026-08-10</summary>

- **Archive:** [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) · [v2.0-phases](milestones/v2.0-phases/)
- **Status:** SHIPPED (verified_closeout — artifact audit clear, all 5 phases verified, 24/24 requirements complete, threats_open 0)

- [x] Phase 9: Dialect Boundary and Neutral Naming (7 plans)
- [x] Phase 10: Flink Release Profiles and Lexical Core (3 plans)
- [x] Phase 11: Flink Grammar and Recoverable CST (4 plans)
- [x] Phase 12: Cross-Dialect Corpus and Parity Gates (3 plans)
- [x] Phase 13: Toolchain and Editor Packaging (7 plans; verified 28/28)

</details>

<details>
<summary>✅ v3.0 — Analysis and Intelligence (Phases 5-8) — SHIPPED 2026-08-13</summary>

- **Archive:** [v3.0-ROADMAP.md](milestones/v3.0-ROADMAP.md) · [v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md) · [v3.0-phases](milestones/v3.0-phases/)
- **Research:** [v1.0-research/SUMMARY.md](milestones/v1.0-research/SUMMARY.md) — v1/v2 analysis-feature research (archived 2026-08-06)
- **Status:** SHIPPED (verified_closeout — artifact audit clear; 6/7 requirements delivered, EDIT-01 descoped with benchmark evidence)

- [x] Phase 5: Closeout and Analysis Foundation (4 plans) — CLOSE-01/02 verified, ANAL-01 delivered
- [x] Phase 6: Lint and Fingerprint (4 plans) — LINT-01 + FING-01 delivered
- [x] Phase 7: Column Lineage (5 plans) — LINE-01 delivered
- [x] Phase 8: Incremental Parsing (Benchmark-Gated) (4 plans, 2 executed) — EDIT-01 DESCoped with `moon bench` evidence

</details>

## Backlog

No unmapped v2.0 requirements remain: all 24 active requirements map exactly once to Phases 9-13. Post-v2 candidates remain deliberately outside this roadmap: `FLINK-FUTURE-01` (planner/catalog/type/execution equivalence), `TOOL-FUTURE-01` (semantic editor intelligence), `DIALECT-FUTURE-01` (third-party dialect registry), `EDIT-FUTURE-01` (benchmark-gated incremental CST/refactors), `TARGET-FUTURE-01` (Wasm GC first-class support), and `CONVERT-FUTURE-01` (explicit opt-in transpilation). The deferred v3.0 analysis requirements remain archived below and are not v2.0 mappings.

## Dependency and Ordering Rationale

1. **Phase 9 first** — every lexer, parser route, public schema, host, and naming surface needs one explicit immutable dialect/profile context; freezing the Doris baseline before refactoring prevents new tests from hiding regressions.
2. **Phase 10 before grammar** — Flink release/source/Calcite pins and lexical policy determine what “supported” means; the 2.1.3 Calcite gap and quote/comment/literal behavior must be resolved before accepting grammar.
3. **Phase 11 after lexical contract** — shared source/token/CST/Pratt/recovery mechanics can then route to separate Flink productions for core SQL, DDL, Window TVF, and MATCH_RECOGNIZE without a Doris fallback; the frozen Doris baseline remains a hard gate.
4. **Phase 12 after parser behavior** — pinned corpus metadata, acceptance/recovery categories, Doris parity, and Native/JS/linear-Wasm comparisons need stable CST and serialized results; this is a release gate, not cleanup.
5. **Phase 13 last** — formatter/completion/analyzer and CLI/LSP/Web/VS Code/IntelliJ adapters consume the stable dialect-aware API/schema. Real host and ABI smoke tests validate that no adapter silently chooses a dialect or maintains a second parser.

**Execution order:** Phase 9 → Phase 10 → Phase 11 → Phase 12 → Phase 13. No phase may replace explicit selection with automatic detection, generic MySQL fallback, Flink runtime/planner dependencies, default transpilation, or an unbenchmarked incremental parser.

## Next Milestone

v3.0 (deferred analysis layer) starts only after v2.0 Multi-Dialect completes. Its historical Phase 5-8 structure and requirements remain below, with the original archive link [milestones/v3.0-REQUIREMENTS.md](milestones/v3.0-REQUIREMENTS.md); none of `CLOSE-01/02`, `ANAL-01`, `LINT-01`, `LINE-01`, `FING-01`, or `EDIT-01` is mapped to v2.0.

**Coverage (v2.0):** 24/24 requirements mapped exactly once — Phase 9: 8, Phase 10: 1, Phase 11: 6, Phase 12: 4, Phase 13: 5.
