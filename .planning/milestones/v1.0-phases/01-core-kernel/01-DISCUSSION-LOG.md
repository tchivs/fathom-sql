# Phase 1: Core Kernel - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-03
**Phase:** 1-Core Kernel
**Areas discussed:** Source coordinates and public spans, Recovery contract, CST and AST boundary, Version profiles and validation gates

---

## Source coordinates and public spans

| Option | Description | Selected |
|--------|-------------|----------|
| Canonical byte spans plus derived line/column/UTF-16 positions | Immutable UTF-8 source snapshot with a centralized LineIndex for editor conversions | ✓ |
| UTF-16 positions as primary internal spans | Optimizes directly for LSP but complicates exact source slicing and non-ASCII handling | |
| Line/column or code-point positions only | Human-readable but insufficient for stable slicing and foreign-backend contracts | |

**User's choice:** `[--auto]` selected the recommended canonical byte-span contract.
**Notes:** Public/host adapters derive UTF-16 positions; the parser core remains byte- and source-backed.

| Option | Description | Selected |
|--------|-------------|----------|
| Primitive serialized schema with byte spans | Stable fields cross Native, JavaScript, and Wasm; host adapters derive editor coordinates | ✓ |
| Export internal MoonBit CST/ADT objects | Shorter initial wrapper but exposes unstable ABI details | |
| Formatted text and line/column diagnostics only | Hides the lossless CST and weakens editor integrations | |

**User's choice:** `[--auto]` selected the recommended serialized primitive boundary.
**Notes:** Schema versioning is a later ecosystem concern, but Phase 1 must avoid locking internal ADT layout into the public API.

---

## Recovery contract

| Option | Description | Selected |
|--------|-------------|----------|
| Dual strict/editor modes over one recoverable CST | Strict mode reports invalidity; editor mode preserves missing/error/skipped nodes and diagnostics | ✓ |
| Permissive best-effort AST with diagnostics side channel | Risks false acceptance and loses lossless CST guarantees | |
| Strict-only parser first | Conflicts with the Phase 1 editor recovery requirement and postpones a core invariant | |

**User's choice:** `[--auto]` selected the recommended dual-mode contract.
**Notes:** Strictness is a validity/result-mode distinction, not a second parser implementation.

| Option | Description | Selected |
|--------|-------------|----------|
| Clause recovery plus statement panic-mode, progress guarantees, and resource caps | Synchronizes at known boundaries and bounds malformed-input work | ✓ |
| Recover until a token looks syntactically valid | Can cascade errors and accept arbitrary unsupported text | |
| Abort at first syntax error | Produces poor editor behavior and cannot satisfy recoverable CST acceptance | |

**User's choice:** `[--auto]` selected bounded clause/statement recovery.
**Notes:** Every parser path must consume input or emit an explicit error node; diagnostics and recursion/work are bounded.

---

## CST and AST boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Lossless CST first, typed AST projection second, analyzer separate | CST retains source truth; semantic-less views can be ergonomic without replacing it | ✓ |
| Typed AST as public source with token side channel | Makes comment-preserving edits fragile and splits source ownership | |
| Raw token stream as public source | Pushes tree construction burden to every consumer | |

**User's choice:** `[--auto]` selected the recommended CST-first boundary.
**Notes:** Optional catalog-backed analysis remains outside the parser core.

| Option | Description | Selected |
|--------|-------------|----------|
| Immutable source-backed leaves with spans and explicit error/missing nodes | Supports replay, recovery, and later formatting without copying the whole source | ✓ |
| Mutable nodes containing copied token strings | Risks divergent source ownership and avoidable memory use | |
| Normalized nodes with comments in a global list | Makes trivia attachment and local edits ambiguous | |

**User's choice:** `[--auto]` selected immutable source-backed ownership.
**Notes:** Concrete green/red or event-builder mechanics remain planner discretion.

---

## Version profiles and validation gates

| Option | Description | Selected |
|--------|-------------|----------|
| Released versioned docs as contract; FE/SQLGlot as differential references | Explicit 2.1, 3.x, 4.x profiles; current/dev is discovery-only | ✓ |
| Doris FE/Nereids grammar as SDK contract | Couples the public API to FE internals and version/runtime assumptions | |
| Latest/current docs as permissive superset | Makes release compatibility and coverage claims unauditable | |

**User's choice:** `[--auto]` selected released official documentation as the grammar authority.
**Notes:** Differential results are recorded for investigation, not treated as the SDK contract.

| Option | Description | Selected |
|--------|-------------|----------|
| Round-trip/property, golden, negative/recovery, and version fixtures from first slice | Protects source fidelity and recovery before grammar breadth grows | ✓ |
| Only parser-function unit tests until broad coverage | Can miss byte loss, version leakage, and malformed-input cascades | |
| FE acceptance primary, replay tests later | Defers the project's central differentiator and makes lossiness expensive to repair | |

**User's choice:** `[--auto]` selected invariant and corpus gates from the first slice.
**Notes:** FE/SQLGlot differential checks remain advisory evidence; official versioned fixtures define public support.

---

## Claude's Discretion

- Parser decomposition, event/builder mechanics, concrete MoonBit structures, and performance tuning may be chosen during research/planning if they preserve the locked coordinate, CST, recovery, version, and validation contracts.

## Deferred Ideas

None. Later-phase formatting, CLI, LSP, Wasm/JavaScript, DML/DDL, lint, lineage, and fingerprint work stays outside this discussion.
