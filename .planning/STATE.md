---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 02
current_phase_name: Doris Completeness and Corpus
status: executing
stopped_at: Completed 02-03-PLAN.md
last_updated: "2026-08-04T04:48:17.781Z"
last_activity: 2026-08-04
last_activity_desc: Phase 02 execution started
progress:
  total_phases: 2
  completed_phases: 1
  total_plans: 10
  completed_plans: 7
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-03)

**Core value:** 用户可以对 Doris SQL 进行高覆盖、精确诊断且无损 round-trip 的解析与编辑，而不依赖 Doris FE、商业闭源 GSP 或薄弱的方言适配。
**Current focus:** Phase 02 — Doris Completeness and Corpus

## Current Position

Phase: 02 (Doris Completeness and Corpus) — EXECUTING
Plan: 4 of 6
Status: Ready to execute
Last activity: 2026-08-04 — Phase 02 execution started

Progress: [███████░░░] 70%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: N/A
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Core Kernel | 0 | TBD | N/A |
| 2. Doris Completeness and Corpus | 0 | TBD | N/A |
| 3. Formatting and Safe Edits | 0 | TBD | N/A |
| 4. Ecosystem and Multi-Target Delivery | 0 | TBD | N/A |

**Recent Trend:**

- Last 5 plans: None yet
- Trend: Stable

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 14 | 2 tasks | 8 files |
| Phase 01 P02 | 25 | 2 tasks | 8 files |
| Phase 01 P03 | 48 | 2 tasks | 8 files |
| Phase 01 P04 | 5 | 2 tasks | 9 files |
| Phase 02 P02-01 | 9 | 3 tasks | 7 files |
| Phase 02 P02-02 | 9 | 3 tasks | 6 files |
| Phase 02 P03 | 11 | 3 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 1]: Establish lossless CST, explicit Doris profiles, structured diagnostics, and bounded recovery before expanding grammar.
- [Phase 2]: Use released official Doris documentation as the versioned corpus authority and keep the optional analyzer separate from syntax parsing.
- [Phase 3]: Keep exact replay and configurable canonical formatting as distinct consumer operations.
- [Phase 4]: Expose one MoonBit core through stable serialized Native, JavaScript, and Wasm contracts.
- [Phase ?]: 核心采用 raw-byte SourceText、checked half-open Span 与集中式 LineIndex；默认 max_bytes 为 8 MiB。
- [Phase ?]: Doris profile 强制限定为 2.1、3.x、4.x，未知值不回退 generic MySQL。
- [Phase ?]: ParseLimits 通过 API 构造器转换为 parser-owned limits，保持依赖方向与跨包不变性
- [Phase ?]: DORIS-PARSE-003 用于 encoding/unterminated lexical material，DORIS-PARSE-004 保留给单一 resource diagnostic
- [Phase ?]: 资源上限后的完整输入保留为 root source snapshot，CST 使用 source-backed SKIPPED remainder
- [Phase ?]: 工业 SELECT 采用统一递归下降查询路径与集中 Pratt 优先级表，profile 严格限定 2.1/3.x/4.x。
- [Phase ?]: 官方 revision 无法从离线 GitHub API 核验时保留 unavailable-offline + known-gap，不伪造 commit。
- [Phase ?]: Unknown statement starters emit DORIS-PARSE-007 unsupported-statement diagnostics; DORIS-PARSE-001 stays reserved for trailing tokens inside recognized statements
- [Phase ?]: DML sync words live in per-family predicates only; the shared is_clause_keyword set is untouched (research Pitfall 3)
- [Phase ?]: Multi-char comparison operators (<=, >=, <>, !=, <=>) scan as single lexer symbols so DELETE form-1 op lists and SELECT comparisons parse
- [Phase ?]: DDL order per D-10 shipped: CREATE TABLE full body (keys/aggregation/distribution/buckets/partitions/dynamic AUTO partitions/properties) then VIEW/CTAS/LIKE then INDEX/sync-MV; ORDER BY gated at 4.x (docs since 4.1.0), BUCKETS AUTO assumed 3.x and AUTO PARTITION BY assumed 2.1 (FLAGGED for 02-04)
- [Phase ?]: Non-reserved DDL grammar words (BUCKETS/PROPERTIES/COMMENT/AGGREGATE/ENGINE) stay unquoted-usable identifiers; shared clause/reserved sets untouched; ORDER/ROLLUP remain reserved (official list + Phase 1 SELECT contract)
- [Phase ?]: CREATE ASYNC MATERIALIZED VIEW is an explicit DORIS-PARSE-007 unsupported statement with a source-backed error node (FLAGGED-A2); sync MV body rejects JOIN/HAVING/LIMIT/LATERAL VIEW/subquery with localized expected_class sync materialized view body
- [Phase ?]: Phase 1 words absent from the official reserved list stay Reserved to preserve byte-for-byte Phase 1 classification behavior, with source notes documenting absence from the official list
- [Phase ?]: TABLET stays Contextual per Phase 1 behavior and D-14 although listed in the official reserved keywords
- [Phase ?]: DEFAULT is Reserved (official list) and also a value-expression operand, so VALUES (1, DEFAULT) and SET c = DEFAULT keep parsing (02-01 tests green)
- [Phase ?]: DISTRIBUTED/OVERWRITE classified Reserved per official-list authority (D-13) despite the plan text's loose non-reserved parenthetical
- [Phase ?]: MERGE is Reserved with introduced_profile 4.x per D-09; word-level introduced_profile is audit metadata - only DorisFeature gates reject version-invalid syntax
- [Phase ?]: VIEW classified NonReserved (absent from the official reserved list per D-13 authority)

### Pending Todos

From `.planning/todos/pending/` — ideas captured during sessions.

None yet.

## Blockers/Concerns

Non-blocking boundaries retained in phase artifacts:

- Disk `corpus/manifest.tsv` and three SQL fixtures are static/embedded-contract inputs; runtime tests do not load the files. Broader manifest-driven golden execution is deferred to Phase 2.
- `moon.mod` records observed `moon 0.1.20260724` while its policy comment names official v0.10.5; the mismatch is disclosed in review/security artifacts.
- Corpus revisions remain `unavailable-offline`/`known-gap`; no SHA is fabricated.

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-08-04T04:48:17.760Z
Stopped at: Completed 02-03-PLAN.md
Resume file: None
