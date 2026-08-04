---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 04
current_phase_name: Ecosystem and Multi-Target Delivery
status: planning
stopped_at: Completed 04-04-PLAN.md
last_updated: "2026-08-04T16:26:23.257Z"
last_activity: 2026-08-04
last_activity_desc: Phase 03 complete, transitioned to Phase 04
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 20
  completed_plans: 19
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-03)

**Core value:** 用户可以对 Doris SQL 进行高覆盖、精确诊断且无损 round-trip 的解析与编辑，而不依赖 Doris FE、商业闭源 GSP 或薄弱的方言适配。
**Current focus:** Phase 4 — Ecosystem and Multi-Target Delivery

## Current Position

Phase: 04 — Ecosystem and Multi-Target Delivery
Plan: Not started
Status: Ready to plan
Last activity: 2026-08-04 — Phase 03 complete, transitioned to Phase 04

Progress: [██████████] 95%

## Performance Metrics

**Velocity:**

- Total plans completed: 10
- Average duration: N/A
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Core Kernel | 0 | TBD | N/A |
| 2. Doris Completeness and Corpus | 0 | TBD | N/A |
| 3. Formatting and Safe Edits | 0 | TBD | N/A |
| 4. Ecosystem and Multi-Target Delivery | 0 | TBD | N/A |
| 02 | 6 | - | - |
| 03 | 4 | - | - |

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
| Phase 02 P02-05 | 15 | 3 tasks | 5 files |
| Phase 02 P02-04 | 90 | 3 tasks | 40 files |
| Phase 02 P06 | 35 | 2 tasks | 5 files |
| Phase 03 P01 | 41 | 2 tasks | 11 files |
| Phase 03 P03-02 | 29 | 3 tasks | 3 files |
| Phase 03-formatting-and-safe-edits P03 | 63min | 3 tasks | 3 files |
| Phase 03 P03-04 | 58 | 2 tasks | 6 files |
| Phase 04 P03 | implementation session | 3 tasks | 10 files |
| Phase 04 P04 | implementation session | 3 tasks | 18 files |

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
- [Phase ?]: D-21 add-alongside: analyzer/ is an independent library importing only fathom/doris-sql/syntax; parser core import list unchanged and enforced by a negative gate
- [Phase ?]: D-22 minimal catalog: ColumnInfo/TableInfo records, open Catalog trait, StaticCatalog with case-sensitive keys (documented), last-wins on duplicates
- [Phase ?]: D-23 statement entry: ParseResult::statement(statement_id) returns the id-th Statement node; statement_diagnostics filters by statement_id preserving source order
- [Phase ?]: D-24 scope: analyzer ships interface + docs + minimal implementation; full ANAL-01 name resolution and type diagnostics are v2
- [Phase ?]: A2 closed: async materialized views are supported under every released profile per the 2.1/3.x/4.x docs (CREATE MATERIALIZED VIEW with BUILD/REFRESH clauses); no deferral remains
- [Phase ?]: A3 verified: the released 2.1 CREATE TABLE grammar documents BUCKETS AUTO and AUTO PARTITION BY; DorisFeature::BucketsAuto moved 3.x to 2.1
- [Phase ?]: Bare CREATE MATERIALIZED VIEW [AS] query keeps the sync restricted body; the async form is selected by ASYNC/IF NOT EXISTS or async clauses
- [Phase ?]: differential.tsv is regenerated deterministically by sqlglot_diff.py: one row per manifest fixture; existing fe_nereids_observation values are preserved by fixture_id so manual FE runs are never clobbered
- [Phase ?]: sqlglot acceptance uses error_level=RAISE; Command-fallback acceptances are flagged in the resolution; no-file fixtures record not-run-offline, observations are never fabricated (A8)
- [Phase ?]: FE script records fe_nereids_observation by merge (update-by-fixture_id, append only unknown ids), parser-only NereidsParser.parseSQL, never cluster-connected (T-02-53), FE_VERSION pinned per manual run (D-20)
- [Phase ?]: formatter/ consumes only source/token/syntax + core buffer (D-27 one-way); printer/ untouched; print_lossless stays the lossless contract
- [Phase ?]: Keyword case rewriting consumes @token.classification_of only; no second keyword list in formatter/ (D-28)
- [Phase ?]: Refusal is absolute (D-33): error/missing/skipped material -> accepted=false, empty output, exactly one DORIS-FORMAT-001; parse diagnostics prepended, never masked (T-03-01)
- [Phase ?]: api.format_text is the shared Phase 4 LSP core entry (D-38); formatter types re-exported via MoonBit type aliases
- [Phase ?]: statement_offsets records the buffer length before each statement layout; the inter-statement separator newline is part of the following statement's layout, so the offset points at the separator byte
- [Phase ?]: Select-list measure-then-break measures non-trivia lengths + one space per trivia run + ', ' per comma - invariant to input whitespace, idempotent across passes
- [Phase ?]: Literal Pattern-1 clause-break rule: a table keyword breaks whenever it is not the statement's first token (INSERT\nINTO t, DELETE\nFROM t, CREATE\nTABLE t); goldens lock the terse documented forms
- [Phase ?]: Zero-space-before-paren canonical convention: FROM(, WHERE(, VALUES(, KEY( attach the paren directly (inherited from 03-01 emit_token)
- [Phase ?]: Empirical trailing-comma gate (A1/Open Q1): 4.x strict probe accepts a last-item comma only in PROPERTIES and partition-definition lists; those two contexts emit it (D-35-asserted), all others emit none; probe record committed in a test comment
- [Phase ?]: List flat measure simulates the exact emission rules (pending space / zero-space / no-space-after-'(') so fit decisions are a pure function of the token sequence - idempotence by construction; an input trailing comma at split depth is read as trailing (not an item separator, not measured)
- [Phase ?]: Comment attachment breaks to the current LINE indent (line_indent), and document-leading comments never force a leading space/break when they are the first output bytes
- [Phase ?]: Lower keyword case is the ASCII case-fold of the classification-table canonical word; quoted names, strings, comments, and hints pass through unchanged (D-28/D-36)
- [Phase ?]: The 4.x-industrial corpus row drops the TABLET (1001) clause (parser gap: TABLET only on unaliased table refs, probe-verified) so the manifest's supported status and the D-35 reparse gate hold
- [Phase ?]: A run-newline comment opening a broken-list item keeps the pending item break (item indent) instead of clobbering it with the stale line_indent - fixes hint placement flip-flop between format passes
- [Phase ?]: doris-sql format CLI is a thin executable package (D-37/D-38): pure run_format -> CliOutcome maps @api.format_with_ids results to exact D-39 exit codes 0/1/2; --profile required (CORE-01, exit 2 otherwise); byte-exact unbuffered stdout via write_fd(1) so exit_process drops nothing
- [Phase ?]: CLI toolchain adaptations on moon 0.1.20260724: Result[Command, UsageError] instead of union types; black-box _test.mbt modules require pub(all) structs and pub FFI externs; hand-rolled int parsing keeps the CLI dependency surface at api/env/buffer/utf8/debug
- [Phase ?]: Expose doris_parse_v1, doris_format_v1, doris_profile_v1, and doris_capabilities_v1 as primitive UTF-8 JSON Bytes exports.
- [Phase ?]: Use inline-root-v1 JSON byte arrays for exact source transport and advertise only linear Wasm, not Wasm GC.
- [Phase ?]: User approved pinned host dependencies: monaco-editor@0.56.0, vscode-languageclient@10.1.0, and @vscode/vsce@3.9.2 release-only.

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

Last session: 2026-08-04T16:26:23.231Z
Stopped at: Completed 04-04-PLAN.md
Resume file: None
