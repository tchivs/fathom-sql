# Requirements: Fathom SQL Parser SDK

**Defined:** 2026-08-06
**Milestone:** v2.0 Multi-Dialect: Flink SQL & Neutral Naming
**Core Value:** 用户可以在同一套 MoonBit 无损 CST 内核上，对显式选择的 Doris 或 Flink SQL 进行高覆盖、精确诊断、无损 round-trip 和编辑器级工具链操作，而不依赖 Doris FE、Flink cluster、数据库或通用方言静默回退。

## v2.0 Requirements

Requirements for the v2.0 milestone. Each requirement maps to exactly one roadmap phase after roadmap creation.

### Dialect Contract

- [x] **DIALECT-01**: Consumer can explicitly select `doris` or `flink` and its profile through the public API, CLI, LSP, JS/Wasm facade, Web, VS Code, and IntelliJ; missing, unknown, or conflicting selection returns a structured configuration error with no automatic dialect detection or generic fallback.
- [x] **DIALECT-02**: Parser uses independent Doris and Flink lexical/keyword policies for reserved, non-reserved, and contextual words, quoted identifiers, comments, literals, operators, and feature metadata; no global union of dialect keyword rows can affect identifier acceptance.
- [x] **DIALECT-03**: Shared source, token, CST, Pratt, and recovery mechanics route statement and clause grammar explicitly by dialect; Doris-only syntax is rejected in Flink mode and Flink-only syntax is rejected in Doris mode with localized diagnostics rather than try-all parsing.
- [x] **DIALECT-04**: Parse, format, completion, LSP, and serialized results carry dialect, profile, and exact-release metadata; strict/editor mode, byte spans, statement identity, and structured `FATHOM-*` diagnostics remain stable across the public boundary.

### Flink SQL Language Coverage

- [x] **FLINK-01**: Consumer can select pinned Flink release profiles with auditable source and parser contracts: `flink-2.3.0` as the primary profile plus `flink-2.1.3` and `flink-1.20.5` regression profiles; each profile records its actual release Calcite version/config, and unsupported profiles are rejected explicitly.
- [x] **FLINK-02**: Consumer can parse Flink core queries and everyday statements including SELECT, CTE, JOIN, aggregation, set operations, expressions, types, INSERT, UPDATE, DELETE, EXPLAIN, SHOW, DESCRIBE, and ANALYZE with recoverable diagnostics.
- [x] **FLINK-03**: Consumer can parse Flink Catalog and DDL entry points including CREATE/ALTER/DROP CATALOG, DATABASE, TABLE, VIEW, and FUNCTION as structured CST statement families.
- [x] **FLINK-04**: Consumer can parse Flink CREATE TABLE physical, metadata, and computed columns; WATERMARK; PRIMARY KEY NOT ENFORCED; PARTITIONED BY; distribution; WITH connector options; LIKE; and AS forms while retaining token spelling, trivia, and spans.
- [x] **FLINK-05**: Consumer can parse Window TVF forms for TUMBLE, HOP, CUMULATE, and SESSION, including TABLE/DESCRIPTOR arguments, interval literals, named arguments, and window output columns.
- [x] **FLINK-06**: Consumer can inspect syntax-level MATCH_RECOGNIZE CST and diagnostics covering PATTERN, DEFINE, MEASURES, skip policy, pattern variables, and quantifiers; the SDK does not claim planner or execution equivalence.

### Lossless CST and Toolchain

- [x] **CST-01**: Consumer can parse Flink input in strict or editor mode into a recoverable lossless CST where comments, whitespace, newlines, unknown material, error nodes, missing nodes, skipped material, source bytes, and spans round-trip without loss.
- [ ] **TOOL-01**: Consumer can format supported Flink CST using the existing refusal-first contract: canonical formatting is separate from lossless replay, and trees containing unsafe error/missing/skipped material produce an explicit refusal without partial output.
- [ ] **TOOL-02**: Consumer can request bounded Flink syntax completion for keywords, DDL, WATERMARK, Window TVF, and MATCH_RECOGNIZE contexts and receive safe source-range edits based on the selected dialect/profile.
- [ ] **TOOL-03**: Consumer can run the syntax-only analyzer for Flink with an optional catalog to resolve supported table, column, and identifier references; parser validity is independent of catalog, connector, planner, or execution semantics.
- [ ] **TOOL-04**: Consumer can use the neutral CLI and Native LSP end to end for Flink, including `fathom-sql parse|format|lsp --dialect flink`, `fathom-lsp`, diagnostics, formatting, completion, UTF-16 positions, and document-level dialect selection.
- [ ] **TOOL-05**: Consumer can use the same dialect-aware API/schema/LSP from JS and linear Wasm, Web/Monaco, VS Code, and IntelliJ; hosts select Doris or Flink per file/session without maintaining a second parser implementation.

### Product Identity Neutralization

- [x] **NAME-01**: Consumer-facing module imports, Native binaries, and public exports complete a clean cutover to `fathom/sql`, `fathom-sql`, and `fathom-lsp`; no old public aliases remain.
- [x] **NAME-02**: Machine-readable wire contracts use `fathom.parse.v1`, `fathom.format.v1`, `fathom.error.v1`, and `fathom.capabilities.v1`, with `FATHOM-*` diagnostics and explicit dialect/profile fields.
- [x] **NAME-03**: VS Code, IntelliJ, Web/npm, CI/release assets, configuration keys, LSP server identity, README, and project documentation use neutral product naming; Doris remains only as a dialect/profile/corpus/provenance semantic identifier.
- [x] **NAME-04**: CI includes a naming inventory/allowlist gate that rejects product-level remnants of `doris-sql`, `doris-lsp`, `doris.*`, and `DORIS-*`; the allowlist is limited to Doris dialect semantics and provenance.

### Corpus and Parity Gates

- [x] **CORPUS-01**: Maintainer can inspect a release-pinned Flink corpus whose manifest records release/tag/commit, Calcite version/config, URL, heading, retrieval date, hash, expected status, and categories for positive, negative, recovery, known limitation, catalog prerequisite, and planner prerequisite cases.
- [ ] **PARITY-01**: Doris 2.1, 3.x, and 4.x valid/invalid/recovery/CST/span/diagnostic/formatter/completion behavior remains equal to a frozen baseline after dialect and naming refactors, unless an intentional change is explicitly recorded.
- [ ] **PARITY-02**: The same fixture produces byte-identical serialized results, diagnostics, spans, and lossless replay across Native, JavaScript, and linear-Wasm targets.
- [x] **PARITY-03**: CI and release checks run from pinned offline artifacts without Doris FE, Flink cluster, database, or network access, and coverage reports distinguish parser acceptance from engine semantic support across both dialects.

## Future Requirements

Deferred until the v2.0 parser and public contracts are stable:

- **FLINK-FUTURE-01**: Full Flink planner/catalog/type-inference/execution equivalence, connector validation, and stream/batch semantic checking.
- **TOOL-FUTURE-01**: Catalog-backed completion, hover, semantic tokens, symbols, and richer LSP intelligence beyond syntax-only candidates.
- **DIALECT-FUTURE-01**: Third-party dialect/plugin marketplace and open runtime dialect registry.
- **EDIT-FUTURE-01**: Benchmark-gated incremental CST reuse and broad structural refactors.
- **TARGET-FUTURE-01**: Wasm GC as a first-class compatibility promise.
- **CONVERT-FUTURE-01**: Explicit opt-in SQL conversion/transpilation between dialects, with source/target diagnostics and refusal rules.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Default automatic dialect detection or first-success parsing | SQL syntax is ambiguous across dialects; silent selection makes diagnostics and formatting untrustworthy. |
| Generic MySQL/ANSI fallback for unsupported Doris or Flink syntax | Generic acceptance does not prove engine acceptance and would undermine explicit dialect validity. |
| Formatter silently converting Doris SQL to Flink SQL or vice versa | Conversion can change connector options, quoted identifiers, watermarks, windows, and semantics; conversion must be a separate future API. |
| Flink planner, runtime, catalog, connector, or execution dependency | Breaks standalone Native/JS/Wasm and parser/analyzer separation. |
| Backward-compatibility aliases for old product names | The product is not formally released; this milestone intentionally performs a clean naming cutover. |
| Network-dependent corpus or CI execution | Release/source evidence must be pinned and checked into reproducible artifacts. |
| Unbounded recovery or formatter output on unsafe trees | Editor tolerance must not become false validity or destructive formatting. |

## Traceability

Populated during v2.0 roadmap creation. Every v2.0 requirement maps to exactly one phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DIALECT-01 | Phase 9 | Complete |
| DIALECT-02 | Phase 9 | Complete |
| DIALECT-03 | Phase 9 | Complete |
| DIALECT-04 | Phase 9 | Complete |
| FLINK-01 | Phase 10 | Complete |
| FLINK-02 | Phase 11 | Complete |
| FLINK-03 | Phase 11 | Complete |
| FLINK-04 | Phase 11 | Complete |
| FLINK-05 | Phase 11 | Complete |
| FLINK-06 | Phase 11 | Complete |
| CST-01 | Phase 11 | Complete |
| TOOL-01 | Phase 13 | Pending |
| TOOL-02 | Phase 13 | Pending |
| TOOL-03 | Phase 13 | Pending |
| TOOL-04 | Phase 13 | Pending |
| TOOL-05 | Phase 13 | Pending |
| NAME-01 | Phase 9 | Complete |
| NAME-02 | Phase 9 | Complete |
| NAME-03 | Phase 9 | Complete |
| NAME-04 | Phase 9 | Complete |
| CORPUS-01 | Phase 12 | Complete |
| PARITY-01 | Phase 12 | Pending |
| PARITY-02 | Phase 12 | Pending |
| PARITY-03 | Phase 12 | Complete |

**Coverage:**

- v2.0 requirements: 24 total
- Mapped to phases: 24 (Phases 9-13)
- Unmapped: 0

---
*Requirements defined: 2026-08-06*
*Last updated: 2026-08-06 after research synthesis*
