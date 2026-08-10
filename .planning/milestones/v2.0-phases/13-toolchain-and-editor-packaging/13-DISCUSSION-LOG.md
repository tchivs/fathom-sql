# Phase 13: Toolchain and Editor Packaging - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-10
**Phase:** 13-toolchain-and-editor-packaging
**Areas discussed:** Flink formatter scope, Flink completion sourcing, Flink analyzer scope, completion wire contract, host per-dialect profiles, per-file/session dialect selection, host packaging smoke depth
**Mode:** `--auto` — all gray areas auto-selected; each resolved with the recommended option (no interactive user input)

---

## Flink Formatter Scope (TOOL-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Full coverage | Layout every Flink statement family the Phase 11 parser produces; unhandled families treated as unsafe → `FATHOM-FORMAT-001` refusal (D-33) | ✓ |
| Pragmatic subset | Query family + common DDL first; other valid Flink families explicitly refused | |
| Verbatim pass-through | Unhandled families emitted losslessly but non-canonically | |

**User's choice:** `--auto` → Full coverage (recommended default)
**Notes:** Formatter output is a public contract — full parser-scope coverage avoids a formatter that refuses common Flink statements. Refusal-first, idempotence, and Doris zero-drift preserved.

## Flink Completion Sourcing (TOOL-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Classification-table reuse | Single candidate pool from `dialect/flink.mbt` + `introduced_profile` per-profile gating; Flink contexts added | ✓ |
| Curated completion table | Separate Flink-specific completion keyword list | |
| Structure-aware | CST-walking completion | |

**User's choice:** `--auto` → Classification-table reuse (recommended default)
**Notes:** Matches D-28 "no second keyword list" discipline. Bounded (32), syntax-only, source-range edits unchanged.

## Flink Analyzer Scope (TOOL-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Extend existing walk | Same `resolve_table_references` walk extended to Flink statement families; table-level scope aligned with Doris; column/identifier resolution deferred to v2 (D-24) | ✓ |
| New Flink entry | Separate analyzer entry with a dialect parameter | |
| Full reference resolution | Column/identifier resolution for Flink in this phase | |

**User's choice:** `--auto` → Extend existing walk (recommended default)
**Notes:** Analyzer stays dialect-neutral via syntax read views (D-21); catalog optional; parser validity unchanged (ANLY-01).

## Completion Wire Contract (TOOL-05 / binding)

| Option | Description | Selected |
|--------|-------------|----------|
| Add `fathom_complete_v1` | New `fathom.complete.v1` envelope mirroring parse/format; JS/Wasm hosts get the same completion | ✓ |
| LSP-only | No wire export; Web hosts implement their own completion | |

**User's choice:** `--auto` → Add `fathom_complete_v1` (recommended default)
**Notes:** New stable wire contract beyond NAME-02's four namespaces — must be explicitly registered in schema/docs/naming gate.

## Host Per-Dialect Profiles (TOOL-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Static (dialect, profile) pairs | Web/VS Code/IntelliJ keep static constants but validate as (dialect, profile); flink profiles appear per dialect | ✓ |
| Dynamic fetch | Hosts query `fathom.dialect.v1`/`fathom.capabilities.v1` at runtime | |
| Shared JSON | One cross-host definition file | |

**User's choice:** `--auto` → Static (dialect, profile) pairs (recommended default)
**Notes:** Offline-first, matches existing static pattern; server remains authoritative (defense in depth).

## Per-File vs Per-Session Selection (TOOL-04/05)

| Option | Description | Selected |
|--------|-------------|----------|
| Keep locked model | Session default (initializationOptions / config / FathomSettings) + per-file LSP didOpen/didChange override (already implemented); hosts now accept flink values | ✓ |
| Session-only | No per-file override | |

**User's choice:** `--auto` → Keep locked model (recommended default)
**Notes:** Selection transport is a locked LSP contract (D-01/D-02/D-03); no auto-detection or extension guessing.

## LSP/CLI Integration Surface (TOOL-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Real paths | LSP flink format → `@api.format_with_ids`; completion → `@completion.complete`; CLI format honors D-39 exit codes; UTF-16 via binding coordinates | ✓ |
| Keep rejections | Continue structured not-implemented / rejection for flink | |

**User's choice:** `--auto` → Real paths (recommended default)
**Notes:** LSP behavior contract (error vs empty array vs real result) is a host dependency surface — Doris behavior stays byte-identical.

## Host Packaging Smoke Depth (research flags)

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse existing harnesses | VS Code real extension-host verify; IntelliJ Gradle build + LSP launch; Web Chromium smoke; CI final packaging job | ✓ |
| Build-and-launch only | Compile + server starts, no behavioral assertions | |
| CI artifact smoke only | Packaging-level verification only | |

**User's choice:** `--auto` → Reuse existing harnesses (recommended default)
**Notes:** Each host acceptance: open flink file → select flink → receive diagnostics (format/completion where supported). Fully offline.

---

## Claude's Discretion

`--auto` mode: all gray areas resolved by Claude per the established decision chain (D-01..D-08 in CONTEXT.md); no user freeform input.

## Deferred Ideas

- Full ANAL-01 column/identifier resolution + type diagnostics → v2 (D-24)
- Catalog-aware completion (tables/columns, hover, semantic tokens) → TOOL-FUTURE-01
- Auto dialect detection (even opt-in) → future phase
- Explicit cross-dialect transpile → CONVERT-FUTURE-01
- Wasm GC as first-class target → TARGET-FUTURE-01
- Dynamic host profile fetch → revisited only with multi-dialect growth (D-05 chose static pairs)
