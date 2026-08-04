# Requirements: Doris SQL Parser SDK

**Defined:** 2026-08-03
**Core Value:** 用户可以对 Doris SQL 进行高覆盖、精确诊断且无损 round-trip 的解析与编辑，而不依赖 Doris FE、商业闭源 GSP 或薄弱的方言适配。

## v1 Requirements

Requirements for the initial four-milestone release. Each maps to exactly one roadmap phase.

### Core Parsing

- [x] **CORE-01**: Consumer can select an explicit Doris version profile (2.1, 3.x, or 4.x) when parsing SQL, and the parser never silently falls back to a generic MySQL dialect.
- [x] **CORE-02**: Consumer can traverse a lossless CST that retains source bytes, token spelling, comments, whitespace, newlines, trivia, and source spans for every parsed fragment.
- [x] **CORE-03**: Consumer can replay an unchanged parsed document byte-for-byte, including comments, casing, quoting, whitespace, newline style, unknown text, and error material.
- [x] **CORE-04**: User can parse documented Doris SELECT statements and expressions covering joins, subqueries, CTEs, windows, predicates, functions, set operations, grouping sets/ROLLUP/CUBE, hints, and Doris-specific SELECT clauses.
- [x] **CORE-05**: Consumer receives machine-readable diagnostics containing severity, stable code, message, expected syntax class, source span, and statement identity.
- [x] **CORE-06**: Editor can parse incomplete or malformed SQL into a bounded recoverable CST with explicit missing/error/skipped nodes while retaining diagnostics for invalid syntax.
- [x] **CORE-07**: Application can use the parser core offline without starting Doris FE, a database connection, or a runtime-specific parser implementation.

### Doris Coverage

- [x] **DORIS-01**: User can parse version-supported DML statements including INSERT, INSERT OVERWRITE, UPDATE, DELETE, and supported MERGE forms in semicolon-separated scripts.
- [x] **DORIS-02**: User can parse version-supported Doris DDL including tables, views, CTAS/LIKE, keys, aggregation semantics, distribution, buckets, partitions, dynamic partitions, properties, indexes, and materialized views.
- [x] **DORIS-03**: Parser preserves statement boundaries and reports a localized diagnostic when one statement in a multi-statement document is invalid, without discarding later statements.
- [x] **DORIS-04**: Parser applies an auditable, versioned classification of reserved, non-reserved, and contextual Doris/MySQL-compatible keywords, allowing valid non-reserved words as identifiers.

### Corpus and Validation

- [x] **CORP-01**: Project maintains a reproducible official-Doris-document corpus manifest whose fixtures record release family, source URL, retrieval/source revision, statement category, and expected support status.
- [x] **CORP-02**: Every supported corpus fixture has golden coverage for strict parsing, lossless replay, formatting where applicable, and malformed or recovery cases without relying on undocumented current/dev syntax.
- [x] **CORP-03**: Project publishes parse coverage and failure reports by Doris version and statement category, including known gaps instead of an unqualified full-compatibility claim.
- [x] **CORP-04**: Project can run differential checks against feasible Doris FE/Nereids and SQLGlot references, recording disagreements and their version-specific resolution without making either implementation the public contract.

### Analysis Boundary

- [x] **ANLY-01**: Consumer can perform syntax parsing and diagnostics without catalog metadata, while an optional analyzer interface can accept catalog table/column metadata without coupling the parser to FE execution semantics.

### Formatting and Safe Edits

- [x] **FMT-01**: Consumer can request a deterministic canonical rendering distinct from exact lossless replay, with documented handling for supported Doris syntax.
- [x] **FMT-02**: User can configure formatter keyword case, indentation, line width, comma style, newline style, and trailing-newline policy while comments and hints remain attached to the intended source regions.
- [x] **FMT-03**: Formatter produces idempotent output (`format(format(sql)) == format(sql)`), reparses its output successfully for supported input, and refuses or reports unsafe transformations on unrecoverable/error trees.
- [x] **FMT-04**: User can run `doris-sql format` against a file or standard input and receive formatted SQL, diagnostics, and a non-zero status for invalid input according to the selected profile.

### Ecosystem Delivery

- [ ] **ECO-01**: Editor can connect to a Native Doris LSP server that implements lifecycle, document synchronization, versioned documents, and diagnostics without a live Doris FE.
- [ ] **ECO-02**: LSP client can request comment-preserving formatting for a document and receive ranges/edits using a documented byte-to-line/UTF-16 coordinate conversion policy.
- [ ] **ECO-03**: LSP client can receive syntax-aware completion suggestions for Doris keywords, clauses, and parser-known contexts while the SQL document is incomplete.
- [ ] **ECO-04**: Web application can use a Wasm/JavaScript SDK to parse the same Doris profiles and obtain the stable CST/diagnostic results without exposing internal MoonBit ADT or backend-specific types.
- [ ] **ECO-05**: Native, JavaScript, and linear-Wasm targets expose a versioned serialized schema for CST nodes, trivia, spans, diagnostics, and profile selection with parity fixtures across targets.
- [ ] **ECO-06**: Project provides a working Web/Monaco demonstration that uses the Wasm/JavaScript SDK for Doris diagnostics and formatting without a database connection.
- [ ] **ECO-07**: Project provides a VS Code extension that connects to the Native LSP using the standard client protocol and exposes Doris diagnostics and formatting.

## v2 Requirements

Deferred until the four-milestone release has stable CST, parser, formatter, and cross-target contracts.

### Analysis and Intelligence

- **ANAL-01**: User receives catalog-backed name resolution and type diagnostics for Doris tables, columns, functions, and scopes.
- **LINT-01**: User can run a Doris-specific lint rule set with configurable severity and safe autofixes.
- **LINE-01**: User can inspect column-level data lineage across supported queries and views.
- **FING-01**: User can generate stable SQL fingerprints and normalized forms for supported Doris statements.
- **EDIT-01**: Editor can use bounded incremental parsing and targeted CST refactors without reparsing the full document when benchmarks justify the complexity.

## Out of Scope

Explicit exclusions for the initial project scope.

| Feature | Reason |
|---------|--------|
| Full semantic/type/execution replacement for Doris FE, including optimizer behavior and `EXPLAIN` equivalence | Requires engine runtime, catalog, session, privilege, and optimizer semantics; it is not the parser SDK's core value. |
| Embedding Doris FE or requiring a database at runtime | Breaks standalone Native/Wasm/JS portability, offline editor use, startup, and dependency boundaries. |
| Multi-dialect support, automatic dialect detection, and silent MySQL fallback | Creates ambiguous or unsafe acceptance; the product is explicitly Doris-profile driven. |
| Compatibility with undocumented closed-source GSP behavior or redistribution of its implementation/data | GSP is commercial and its public corpus claims are not an open compatibility contract. |
| Template-language parsing, database execution, and optimizer rewriting | These require separate language/runtime contracts and would expand the project beyond a Doris SQL syntax/editor SDK. |

## Traceability

Traceability is populated by the MVP roadmap. Each v1 requirement maps to exactly one phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CORE-01 | Phase 1: Core Kernel | Complete |
| CORE-02 | Phase 1: Core Kernel | Complete |
| CORE-03 | Phase 1: Core Kernel | Complete |
| CORE-04 | Phase 1: Core Kernel | Complete |
| CORE-05 | Phase 1: Core Kernel | Complete |
| CORE-06 | Phase 1: Core Kernel | Complete |
| CORE-07 | Phase 1: Core Kernel | Complete |
| DORIS-01 | Phase 2: Doris Completeness and Corpus | Complete |
| DORIS-02 | Phase 2: Doris Completeness and Corpus | Complete |
| DORIS-03 | Phase 2: Doris Completeness and Corpus | Complete |
| DORIS-04 | Phase 2: Doris Completeness and Corpus | Complete |
| CORP-01 | Phase 2: Doris Completeness and Corpus | Complete |
| CORP-02 | Phase 2: Doris Completeness and Corpus | Complete |
| CORP-03 | Phase 2: Doris Completeness and Corpus | Complete |
| CORP-04 | Phase 2: Doris Completeness and Corpus | Complete |
| ANLY-01 | Phase 2: Doris Completeness and Corpus | Complete |
| FMT-01 | Phase 3: Formatting and Safe Edits | Complete |
| FMT-02 | Phase 3: Formatting and Safe Edits | Complete |
| FMT-03 | Phase 3: Formatting and Safe Edits | Complete |
| FMT-04 | Phase 3: Formatting and Safe Edits | Complete |
| ECO-01 | Phase 4: Ecosystem and Multi-Target Delivery | Pending |
| ECO-02 | Phase 4: Ecosystem and Multi-Target Delivery | Pending |
| ECO-03 | Phase 4: Ecosystem and Multi-Target Delivery | Pending |
| ECO-04 | Phase 4: Ecosystem and Multi-Target Delivery | Pending |
| ECO-05 | Phase 4: Ecosystem and Multi-Target Delivery | Pending |
| ECO-06 | Phase 4: Ecosystem and Multi-Target Delivery | Pending |
| ECO-07 | Phase 4: Ecosystem and Multi-Target Delivery | Pending |

**Coverage after roadmap:**

- v1 requirements: 27 total
- Mapped to phases: 27
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-03*
*Last updated: 2026-08-03 after MVP roadmap creation*
