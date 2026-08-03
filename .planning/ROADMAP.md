# Roadmap: Doris SQL Parser SDK

## Overview

The MVP progresses from a source-faithful, recoverable Doris parsing kernel to versioned Doris grammar and corpus coverage, then adds safe formatting and finally exposes the same MoonBit implementation through Native, LSP, Wasm/JavaScript, Web/Monaco, and VS Code integrations. Each phase delivers a usable consumer capability while preserving the explicit Doris profile, lossless CST, offline operation, and stable cross-target contracts that distinguish this SDK.

## Phases

- [ ] **Phase 1: Core Kernel** - Establish versioned, lossless, recoverable parsing for industrial Doris SELECT and expressions.
- [ ] **Phase 2: Doris Completeness and Corpus** - Expand Doris DML/DDL and make official, versioned corpus coverage auditable.
- [ ] **Phase 3: Formatting and Safe Edits** - Provide exact replay, configurable canonical formatting, and a safe formatting CLI.
- [ ] **Phase 4: Ecosystem and Multi-Target Delivery** - Deliver Native LSP, stable Wasm/JavaScript APIs, and editor/web integrations.

## Phase Details

### Phase 1: Core Kernel

**Goal**: Consumers can parse an explicitly selected Doris 2.1, 3.x, or 4.x profile into a lossless, recoverable CST with precise diagnostics and industrial SELECT/expression coverage, entirely offline.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, CORE-07
**Success Criteria** (what must be TRUE):

  1. Consumer can choose a Doris version profile and parse documented SELECT, JOIN, CTE, window, grouping, set-operation, hint, and expression forms without silent generic-dialect fallback.
  2. Consumer can traverse a CST whose replay preserves original bytes, token spelling, comments, whitespace, newlines, unknown/error material, and source spans for parsed fragments.
  3. Editor can submit incomplete or malformed SQL and receive a bounded recoverable CST with explicit missing/error/skipped nodes plus machine-readable, statement-linked diagnostics.
  4. Application can run parsing and diagnostics offline without Doris FE, a database connection, or a runtime-specific parser implementation.

**Plans:** 1/4 plans executed
Plans:
**Wave 1**

- [x] 01-01-PLAN.md — establish the pinned source, token, and lexer tracer

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 01-02-PLAN.md — build the lossless CST, parser API, and exact replay path

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 01-03-PLAN.md — add bounded strict/editor recovery and stable diagnostics

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 01-04-PLAN.md — cover industrial SELECT and versioned corpus fixtures

**UI hint**: yes

### Phase 2: Doris Completeness and Corpus

**Goal**: Users can parse version-supported Doris scripts and warehouse-specific DML/DDL with localized errors, while maintainers and consumers can inspect reproducible coverage and the syntax-only/analyzer boundary.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: DORIS-01, DORIS-02, DORIS-03, DORIS-04, CORP-01, CORP-02, CORP-03, CORP-04, ANLY-01
**Success Criteria** (what must be TRUE):

  1. User can parse semicolon-separated scripts containing supported INSERT variants, UPDATE, DELETE, MERGE, tables, views, CTAS/LIKE, keys, distribution, buckets, partitions, properties, indexes, and materialized views under the selected Doris profile.
  2. Parser preserves statement boundaries, localizes an invalid statement's diagnostic, and continues to retain and report later statements in the same document.
  3. Consumer can use an auditable versioned keyword classification so valid non-reserved or contextual words remain usable as identifiers without accepting version-invalid syntax silently.
  4. Project publishes reproducible official-document fixture manifests, golden/recovery results, version/category coverage and failure reports, plus recorded FE/SQLGlot differential disagreements and resolutions.
  5. Consumer can perform syntax checks without catalog metadata and can optionally supply table/column metadata through a separate analyzer interface without coupling parsing to FE execution semantics.

**Plans**: TBD

### Phase 3: Formatting and Safe Edits

**Goal**: Users can choose exact source replay or a deterministic, configurable, comment-preserving canonical rendering and invoke it safely from the `doris-sql format` command.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: FMT-01, FMT-02, FMT-03, FMT-04
**Success Criteria** (what must be TRUE):

  1. Consumer can request canonical output distinct from exact lossless replay, with documented behavior across supported Doris syntax.
  2. User can configure keyword case, indentation, line width, comma style, newline style, and trailing-newline policy while comments and hints remain attached to their intended source regions.
  3. Formatter output is deterministic and idempotent, reparses successfully for supported input, and reports or refuses unsafe transformations for unrecoverable/error trees.
  4. User can run `doris-sql format` on a file or standard input to receive formatted SQL and diagnostics, with a non-zero status for invalid input under the selected profile.

**Plans**: TBD

### Phase 4: Ecosystem and Multi-Target Delivery

**Goal**: Editors, web applications, and automation can use one versioned Doris parser through Native LSP/CLI and stable Wasm/JavaScript facades with consistent results across targets.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: ECO-01, ECO-02, ECO-03, ECO-04, ECO-05, ECO-06, ECO-07
**Success Criteria** (what must be TRUE):

  1. Editor can connect to a Native LSP server for lifecycle, document synchronization, versioned documents, diagnostics, comment-preserving formatting edits, and syntax-aware completion on incomplete SQL without Doris FE.
  2. Web application can parse selected Doris profiles and obtain stable CST and diagnostic results through Wasm/JavaScript without exposing internal MoonBit ADTs or backend-specific types.
  3. Native, JavaScript, and linear-Wasm targets expose the same versioned serialized CST/trivia/span/diagnostic/profile schema and pass shared parity fixtures, including documented byte-to-line/UTF-16 coordinates.
  4. Project provides a working offline Web/Monaco demonstration and a VS Code extension that surfaces Doris diagnostics and formatting through the standard LSP client protocol.

**Plans**: TBD
**UI hint**: yes

## Dependency and Ordering Rationale

1. Phase 1 owns source bytes, spans, trivia, CST shape, diagnostics, recovery, and the SELECT vertical slice; every later consumer promise depends on these contracts.
2. Phase 2 expands grammar only after fidelity and recovery are observable, using official released-document fixtures and version gates to prevent MySQL shortcuts, current/dev drift, and false acceptance.
3. Phase 3 separates exact replay from policy-driven formatting; it relies on stable CST ownership and broad Doris syntax so formatting cannot conceal parser lossiness.
4. Phase 4 freezes the serialized and coordinate contracts before wrappers and editor adapters, proving one parser implementation across Native, JavaScript, and Wasm rather than maintaining backend forks.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Core Kernel | 1/4 | In Progress|  |
| 2. Doris Completeness and Corpus | 0/TBD | Not started | - |
| 3. Formatting and Safe Edits | 0/TBD | Not started | - |
| 4. Ecosystem and Multi-Target Delivery | 0/TBD | Not started | - |

**Coverage:** 27/27 v1 requirements mapped; 0 unmapped; each requirement assigned to exactly one phase.
