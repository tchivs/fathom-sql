# Roadmap: Doris SQL Parser SDK

## Overview

The MVP progresses from a source-faithful, recoverable Doris parsing kernel to versioned Doris grammar and corpus coverage, then adds safe formatting and finally exposes the same MoonBit implementation through Native, LSP, Wasm/JavaScript, Web/Monaco, and VS Code integrations. Each phase delivers a usable consumer capability while preserving the explicit Doris profile, lossless CST, offline operation, and stable cross-target contracts that distinguish this SDK.

## Milestones

### ✅ v1.0: milestone — SHIPPED 2026-08-05

Doris SQL Parser SDK 首个可发布里程碑:无损 CST 内核、SELECT/DML/DDL 覆盖、版本化官方语料库、可配置格式化与 CLI、Native LSP / JS-Wasm facade / Web-Monaco / VS Code 集成。27/27 v1 需求验证通过,全部离线可用。

- **Archive:** [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) · [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md) · [v1.0-MILESTONE-AUDIT.md](v1.0-MILESTONE-AUDIT.md)
- **Status:** SHIPPED (override_closeout — 5 documented verification overrides in STATE.md Deferred Items)

<details>
<summary>v1.0 Phase Details (archived)</summary>

### Phase 1: Core Kernel

**Goal**: Consumers can parse an explicitly selected Doris 2.1, 3.x, or 4.x profile into a lossless, recoverable CST with precise diagnostics and industrial SELECT/expression coverage, entirely offline.
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: CORE-01..CORE-07
**Status:** Complete 2026-08-03 (4/4 plans)

### Phase 2: Doris Completeness and Corpus

**Goal**: Users can parse version-supported Doris scripts and warehouse-specific DML/DDL with localized errors, while maintainers and consumers can inspect reproducible coverage and the syntax-only/analyzer boundary.
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: DORIS-01..04, CORP-01..04, ANLY-01
**Status:** Complete 2026-08-04 (6/6 plans)

### Phase 3: Formatting and Safe Edits

**Goal**: Users can choose exact source replay or a deterministic, configurable, comment-preserving canonical rendering and invoke it safely from the `doris-sql format` command.
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: FMT-01..04
**Status:** Complete 2026-08-04 (4/4 plans)

### Phase 4: Ecosystem and Multi-Target Delivery

**Goal**: Editors, web applications, and automation can use one versioned Doris parser through Native LSP/CLI and stable Wasm/JavaScript facades with consistent results across targets.
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: ECO-01..07
**Status:** Complete 2026-08-05 (5/5 plans)

</details>

## Backlog

(No backlog items — all v1 requirements shipped.)

## Dependency and Ordering Rationale

1. Phase 1 owns source bytes, spans, trivia, CST shape, diagnostics, recovery, and the SELECT vertical slice; every later consumer promise depends on these contracts.
2. Phase 2 expands grammar only after fidelity and recovery are observable, using official released-document fixtures and version gates to prevent MySQL shortcuts, current/dev drift, and false acceptance.
3. Phase 3 separates exact replay from policy-driven formatting; it relies on stable CST ownership and broad Doris syntax so formatting cannot conceal parser lossiness.
4. Phase 4 freezes the serialized and coordinate contracts before wrappers and editor adapters, proving one parser implementation across Native, JavaScript, and Wasm rather than maintaining backend forks.

## Next Milestone

v2.0 — start with `/gsd-new-milestone` (fresh REQUIREMENTS.md + ROADMAP.md). Candidate v2 scope: ANAL-01 catalog-backed name resolution, LINT-01 Doris lint rules, LINE-01 column-level lineage, FING-01 SQL fingerprints, EDIT-01 incremental parsing (see archived v1.0-REQUIREMENTS.md § v2 Requirements).

**Coverage (v1.0):** 27/27 v1 requirements shipped; 0 unmapped.
