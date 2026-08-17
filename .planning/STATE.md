---
gsd_state_version: 1.0
milestone: v4.0
milestone_name: Release Readiness
current_phase: 14
current_phase_name: Release Hygiene & Toolchain Pinning
status: completed
stopped_at: Phase 14 complete — HYG + TC tracks delivered (5/5 plans)
last_updated: "2026-08-17T05:00:00Z"
last_activity: 2026-08-17
last_activity_desc: Phase 14 all five plans complete — freeze, installers, release gates, hygiene, readiness
progress:
  total_phases: 7
  completed_phases: 1
  total_plans: 5
  completed_plans: 5
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-08-06)

**Core value:** 用户可以在同一套 MoonBit 无损 CST 内核上，对显式选择的 Doris 或 Flink SQL 进行高覆盖、精确诊断、无损 round-trip 和编辑器级工具链操作，而不依赖 Doris FE、Flink cluster、数据库或通用方言静默回退。
**Current focus:** Phase 14 — Release Hygiene & Toolchain Pinning

## Current Position

Phase: 14 (Release Hygiene & Toolchain Pinning) — COMPLETE (5/5 plans)
Plan: 14-01 freeze, 14-02 installers, 14-03 release gates, 14-04 hygiene, 14-05 readiness — all done
Status: HYG-01/02/03 and TC-01/02 complete; three-platform content lock (D-01/D-03 revision 2026-08-14)
Last activity: 2026-08-17 — Phase 14 all plans complete; release dry-run proven

## Performance Metrics

**Velocity:**

- Total plans completed: 54
- Average duration: N/A
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Core Kernel | 4 | 4 | historical |
| 2. Doris Completeness and Corpus | 6 | 6 | historical |
| 3. Formatting and Safe Edits | 4 | 4 | historical |
| 4. Ecosystem and Multi-Target Delivery | 5 | 5 | historical |
| 9. Dialect Boundary and Neutral Naming | 0 | TBD | N/A |
| 10. Flink Release Profiles and Lexical Core | 0 | TBD | N/A |
| 11. Flink Grammar and Recoverable CST | 0 | TBD | N/A |
| 12. Cross-Dialect Corpus and Parity Gates | 0 | TBD | N/A |
| 13. Toolchain and Editor Packaging | 0 | TBD | N/A |
| 9 | 7 | - | - |
| 10 | 3 | - | - |
| 11 | 4 | - | - |
| 12 | 3 | - | - |
| 13 | 7 | - | - |
| 5 | 4 | - | - |
| 7 | 5 | - | - |
| 8 | 2 | - | - |

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
| Phase quick-260805-e28 Palign-the-jetbrains-plugin-wrapper-and-docs | 5min | 3 tasks | 3 files |
| Phase 09 P01 | 35 min | 3 tasks | 219 files |
| Phase 09-dialect-boundary-and-neutral-naming P02 | 33 | 3 tasks | 163 files |
| Phase 09 P03 | 25 | 2 tasks | 140 files |
| Phase 09 P09-04 | 34 | 3 tasks | 35 files |
| Phase 09 P05 | 38 | 2 tasks | 25 files |
| Phase 09-dialect-boundary-and-neutral-naming P06 | 8 | 4 tasks | 12 files |
| Phase 09-dialect-boundary-and-neutral-naming P07 | unknown | 4 tasks | 47 files |
| Phase 10-flink-release-profiles-and-lexical-core P01 | 1.5 | 4 tasks | 15 files |
| Phase 10-flink-release-profiles-and-lexical-core P02 | 10 | 2 tasks | 27 files |
| Phase 10-flink-release-profiles-and-lexical-core P03 | 75 | 3 tasks | 9 files |
| Phase 11-flink-grammar-and-recoverable-cst P01 | 92 | 4 tasks | 45 files |
| Phase 11-flink-grammar-and-recoverable-cst P02 | 95 | 3 tasks | 65 files |
| Phase 11 P03 | 3.5h | 4 tasks | 70 files |
| Phase 11-flink-grammar-and-recoverable-cst P04 | 120 | 3 tasks | 8 files |
| Phase 12-cross-dialect-corpus-and-parity-gates P01 | 22min | 3 tasks | 118 files |
| Phase 12-cross-dialect-corpus-and-parity-gates P02 | 4min | 3 tasks | 3 files |
| Phase 12-cross-dialect-corpus-and-parity-gates P03 | 7min | 3 tasks | 2 files |
| Phase 05 P01 | 15min | 2 tasks | 2 files |
| Phase 05-02 P02 | 40min | 3 tasks | 9 files |
| Phase 05-03 P03 | 45min | 3 tasks | 11 files |
| Phase 05 P04 | 50min | 3 tasks | 8 files |
| Phase 07-column-lineage P01 | 42 | 2 tasks | 5 files |
| Phase 07 P03 | 39 | 2 tasks | 11 files |
| Phase 14 P04 | 12 min | 2 tasks | 2 files |
| Phase 14 P05 | 55 | 3 tasks | 11 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Phase 14, 14-05]: 用户批准 2026-08-14 拆分执行 — HYG waves 4-5 完成；TC-01/02 因官方 MoonBit 渠道缺 darwin-x86_64 工件/静态版本渠道/core 校验和（全部 403 实测）按 D-01/D-03 fail-closed 阻塞，matrix 如实记录 BLOCKED，不伪造 TC 成功。
- [Phase 14, 14-05]: 14-05 交付 = quick 重复 PLAN 删除（canonical SUMMARY 字节不变，SHA-256 逐行相等）+ 精确五文件 v1.0-research archive commit（e63eec5）+ NUL-safe porcelain-v1/-z 状态分类器（snapshot/pre/post-matrix 模式）与唯一 readiness matrix；post-matrix 分类器证明最终树仅剩两个 allowlisted `.omp-*` runtime 文件（D-11/D-12/D-13）。
- [Phase 14, 14-05]: 计划 Task-1 verify 单行脚本 digest 解析方向反转（hash->path 字典），按正确 path->hash 语义验证并记录偏差；matrix 的 pre-matrix 观察行修正为"permitted-by-mode、当时未出现"（4bb92fd）。
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
- [Phase ?]: User approved pinned host dependencies: monaco-editor@0.55.1 (installed offline from the npm cache), vscode-languageclient@10.1.0, and @vscode/vsce@3.9.2 release-only.
- [Phase ?]: Align the JetBrains wrapper and README to Gradle 9.0.0, the official minimum for IntelliJ Platform Gradle Plugin 2.x, while retaining plugin 2.9.0, Kotlin 2.2.0, and LSP4IJ 0.20.1.
- [Phase ?]: D-07 baseline freeze scope: FULL public behavior locked (all nine output categories byte-level; baseline is the Phase 12 PARITY-01 comparison basis, one-way)
- [Phase ?]: D-08 snapshot gate: parity/baseline_test.mbt 213 snapshots + baseline_diff.py + approved-changes.md register; moon test --update only with a pre-committed register entry
- [Phase ?]: Embedded-raw provenance: baseline_test.mbt embeds exact corpus .sql bytes; baseline-hashes.txt pins them; verified byte-identical for all 44 fixtures
- [Phase ?]: Cross-target equality: shared cross-target snapshot file verified byte-identical on native/js/wasm; CI enforces native+linear-wasm
- [Phase ?]: Adopted D-09/D-10 wire identity + A4 export order (Task 1 checkpoint option-a): fathom.*.v1 namespaces, FATHOM-* codes with dialect in fields, fathom_parse_v1(raw, dialect, profile, mode)
- [Phase ?]: UnknownProfile message is dialect-neutral (unsupported profile: {id}) because the same error serves flink rejection
- [Phase ?]: ParsedDocument.profile/profile_metadata removed: dead metadata not honestly derivable for Flink contexts
- [Phase ?]: Dialect-first validation at the fathom_format_v1 export boundary: ParseOptions::new before option parsing, flink -> FATHOM-SCHEMA-003 for any option set (T-09-10)
- [Phase ?]: format_result_json carries dialect/profile/exact_release metadata mirroring the parse envelope (DIALECT-04, D-09); exact_release derived from ParseOptions at each callsite
- [Phase ?]: Export-level format assertions live in parity/export_smoke_test.mbt (test package cannot import binding: foreign_library E4219 on native test targets); refusal is a FATHOM-FORMAT-001 diagnostic inside the fathom.format.v1 envelope, not fathom.error.v1
- [Phase ?]: Rule 3: parity/run_js.mbt + run_wasm.mbt migrated to fathom_*_v1 with dialect arg — js/wasm parity builds were broken since 09-02 (native-only gate could not compile target-scoped runners)
- [Phase ?]: Task 1 auto-selected option-a: full clean cutover per D-06 (one-way door, no compat aliases); module version stays 0.1.0 (release-planning decision)
- [Phase ?]: Command gains subcommand field (parse|format|lsp) in addition to the plan's dialect field - dispatch requires it
- [Phase ?]: CLI import surface grows to api/lsp/binding + core: run_parse serializes via @binding.parse_result_json (fathom.parse.v1), run_lsp calls @lsp.serve_stdio (single server loop, T-09-15)
- [Phase ?]: Parity CLI homomorph needs no byte change - it already passes 'doris' (now sourced from Command.dialect); approved-changes.md section 10 documents the CLI contract (usage text, Command.dialect, exit-2 matrix)
- [Phase ?]: LSP serverInfo.name/source and parity fixtures stay untouched this wave (09-05/09-06 own them); bare moon build --target native link failure is pre-existing (deferred-items.md)
- [Phase ?]: UnknownDialect serializes to FATHOM-SCHEMA-007 (with ConflictingSelection, OQ3) — the 09-05 code mapping distinguishes dialect errors from UnsupportedProfile (stays 003)
- [Phase ?]: validate_schema_version accepts exactly the four fathom.*.v1 namespaces (parse/format/error/capabilities, D-09); fathom.dialect.v1 is a metadata-query schema, not a result envelope
- [Phase ?]: fathom_dialect_v1(dialect) under fathom.dialect.v1 returns per-dialect profiles with exact_release/feature_introduction from DorisProfile metadata only (T-09-18 provenance); flink empty profile set in Phase 9 (A1); unknown dialect -> FATHOM-SCHEMA-007 error envelope
- [Phase ?]: fathom_capabilities_v1() under fathom.capabilities.v1 returns the global dialect list with per-dialect profile availability (doris 2.1/3.x/4.x, flink empty)
- [Phase ?]: Parity test callsites migrated in the Task 1 commit (Rule 3 — the export rename blocks parity compilation; same-commit rule Pitfall 8); web facade wire references + docs/README code strings migrated per 09-03 deferral; lsp-tracer.json + lsp identity + vscode host assertions + offline-smoke.mjs deferred to 09-06/09-07 (deferred-items.md)
- [Phase ?]: LSP D-01 selection transport locked (option-a): document-level config rides didOpen/didChange extension fields, workspace default from initializationOptions/serve_stdio, languageId mapping only when user-configured; missing everywhere -> FATHOM-SCHEMA-007
- [Phase ?]: flink is a legal LSP selection in Phase 9 (A1): parse routes via new @api.parse_flink_not_implemented -> FATHOM-PARSE-008, never Doris; format/completion reject with the api unsupported-profile error
- [Phase ?]: D-03 publication guard compares version AND selection (dialect/profile) against the stored document; stale async results dropped on either mismatch
- [Phase ?]: Task 1 auto-selected option-a: full host cutover per D-06 (fathom.* config keys, sql language id, fathom-sql-language-client/@fathom/sql-web-demo/fathom-sql-intellij package names, fathom.sql plugin id, FathomSettings/fathom.xml state, no default dialect D-02)
- [Phase ?]: The ci.yml naming-gate job comment carries no literal forbidden patterns because ci.yml is itself a scanned product file; check_naming.py self-exempts as the inventory carrier
- [Phase ?]: Final-sweep stragglers outside the explicit file lists (dialect/doris.mbt, lsp/diagnostics_formatting_test.mbt) fixed with 2-line changes each to reach zero product-file hits; 406/406 native suite + intact parity baseline confirm no behavior change
- [Phase ?]: D-01 FlinkProfile closed enum (V2_3_0|V2_1_3|V1_20_5) + FlinkProfileMetadata (id/release_family/exact_release/calcite_version/parser_config/feature_introduction); exact-match from_id only (flink-2.3.0|flink-2.1.3|flink-1.20.5), no Doris profile borrowing
- [Phase ?]: D-02 Calcite pins (1.36.0/1.34.0/1.32.0) and parser config (Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT) extracted from sha512-verified pinned release archives (scripts/extract_flink_lexical.py + parity manifest), never hand-written
- [Phase ?]: D-05 unknown/unsupported flink profiles reuse FATHOM-SCHEMA-003/007 family; no FATHOM-FLINK-* namespace minted; dialect rides in metadata fields
- [Phase ?]: TokenKind unchanged: Flink prefixed literals (X/U&/N/E'..') map to StringLiteral (minimal-extension bias documented in lexer.mbt); token/token.mbt untouched
- [Phase ?]: E'..' availability gate lives on FlinkProfile::supports_escape_literal (flink-2.3.0/2.1.3 true, flink-1.20.5 false) — policy authority in dialect/, grounded in Parser-calcite-1.36.0.jj:8721/1.34.0:8469/absent-in-1.32.0
- [Phase ?]: unknown-profile fixture freezes a Doris-shaped id (4.x) under flink (Pitfall 6 — no profile-id borrowing); FATHOM-SCHEMA-003 envelope is mode-independent
- [Phase ?]: flink_classification_rows scoped to production/conflict words (142 rows) with release-grammar source per row; full 443/430/412-word lists committed as six parity fixture attachments and validated by scripts/extract_flink_lexical.py (Open Question 3 RESOLVED)
- [Phase ?]: Flink classification is profile-aware in release order flink-1.20.5 < flink-2.1.3 < flink-2.3.0: VARIANT/QUALIFY (introduced flink-2.1.3) are Reserved under 2.3.0/2.1.3 and ABSENT under flink-1.20.5; Doris selection stays dialect-only with the 116-row table byte-identical (T-10-12/13/15)
- [Phase ?]: D-04 locked (auto-selected option-a): mint FATHOM-PARSE-009 'syntax is not supported in the selected dialect' for construct-level dialect-gate rejection; 007 stays whole-statement unsupported; dialect rides in envelope metadata (D-10)
- [Phase ?]: D-02 locked (auto-selected option-a): coarse per-statement-family SyntaxKind variants appended at the enum end + snake_case kind_id wire strings; sub-type detail rides in metadata/spans
- [Phase ?]: D-06: FATHOM-PARSE-008 retired and vacant (never reused); valid Flink SQL routes through real parse_flink_segment grammar; genuinely-unsupported whole statements route through FATHOM-PARSE-007
- [Phase ?]: MATCH_RECOGNIZE + MATCH_NUMBER/MEASURES/PATTERN/DEFINE are Calcite-base reserved tokens present in all three pinned releases (Pitfall 9); introduced_profile flink-1.20.5 makes them Reserved under every Flink profile; extract_flink_grammar.py owns their provenance validation
- [Phase ?]: Flink precedence arm adds only || CONCAT (A3); => (NAMED_ARGUMENT_ASSIGNMENT) consumption deferred to 11-02 (function-call argument layer)
- [Phase ?]: Flink DML/aux slice implemented as one cohesive change set (two atomic commits: implementation+register+manifest, then snapshot goldens) rather than three per-task commits; dispatch arms, is_flink_insert_boundary, and expression-layer gates are one interleaved change set
- [Phase ?]: Doris-side rejection of Flink-only DML forms (INSERT OVERWRITE/UPSERT/ON CONFLICT) relies on the frozen baseline (007/001/002, valid=false) — the plan's Doris-parser-untouched hard gate takes precedence over the aspirational 009 phrasing; the named-arg => case IS a real 009 under Doris via the shared expression argument layer
- [Phase ?]: MERGE under Flink stays on the unsupported path (FATHOM-PARSE-007) per [ASSUMED] A1 — no parse_flink_merge arm in this wave
- [Phase ?]: Doris-side 009 gates for Flink-only CREATE TABLE forms (T-11-16) required surgical frozen-Doris-parser edits; each gate fires only on Flink-only shapes (WATERMARK/PRIMARY KEY/UNIQUE/computed AS-without-paren/METADATA/PARTITIONED BY/WITH/DISTRIBUTED INTO/LIKE feature list) so the frozen 213-snapshot baseline stays byte-identical
- [Phase ?]: CREATE CATALOG/DATABASE/FUNCTION under Doris route to FATHOM-PARSE-007 via a new is_doris_create_form gate in parse_doris_segment's CREATE arm (whole-statement unsupported, D-04 §9); the frozen parser previously emitted a spurious 002
- [Phase ?]: CREATE VIEW and plain CREATE TABLE LIKE / AS SELECT are shared syntax (the frozen Doris parser accepts them), so only the genuinely Flink-only variants are gated: FUNCTION/DROP/ALTER families → 007 under Doris, LIKE feature list and WITH-before-AS CTAS → 009
- [Phase ?]: Flink INTERVAL literal parsing (INTERVAL '5' SECOND) added to the shared expression prefix layer gated to Flink, so Doris expression behavior stays byte-identical (Pitfall 7, A4)
- [Phase ?]: Window TVF rides the generic table-function-call path (no dedicated dispatch): TUMBLE/HOP/SESSION/DESCRIPTOR non-reserved, CUMULATE no keyword token (A2)
- [Phase ?]: MATCH_RECOGNIZE is an independent sub-language with its own sync points (is_flink_match_recognize_boundary) so unclosed PATTERN/DEFINE recovers at the boundary or ';' under the shared budget (Pitfall 4/8)
- [Phase ?]: SUBSET/PERMUTE/{- -} parse structurally, classified known-limitation; no pattern-variable column-scope validation (Pitfall 6, FLINK-06)
- [Phase ?]: TVF positional args validated in order (table/descriptor/size/offset); named => args recognized without reordering
- [Phase ?]: Window TVF + MATCH_RECOGNIZE are Flink-only: FATHOM-PARSE-009 gate at the table-ref point under Doris (T-11-22/T-11-23); no planner/execution equivalence (FLINK-05/06)
- [Phase ?]: D-06 offline gate form: single-entry verify_corpus.py --check with fixture_sha256 resident hash; extract_* stay local (Task 1 auto-selected option-a)
- [Phase ?]: 6-category semantics frozen at fixture level: generic SQL acceptance != Flink engine support; catalog/planner/known-limitation never engine-supported
- [Phase ?]: Snapshot segment rule (dialect-correct): flink {id}.{profile}.{mode}.json, doris {id}.doris-{profile}.{mode}.json, unknown-profile {id}.flink-4x.{mode}.json
- [Phase ?]: D-02 additive migration: old per-area manifests kept; unified manifest adds columns/rows only, never renames fixture_id or snapshot filenames
- [Phase ?]: fixture_sha256 over committed .sql bytes is the resident CI-checkable hash; archive sha512 present-verify / absent-archive-not-present
- [Phase ?]: 12-02 Task 1 auto-selected option-a: wrapper diff_parity.py reusing the baseline_diff approved-vs-unexpected engine (D-03 one-way door); --frozen-only upgrades the CI proof from self-comparison to regeneration, --approve gives a readable local report, zero behavior change to the classification engine.
- [Phase ?]: 12-02 --frozen-only compares the FULL regenerated tree vs committed (all 433 snapshots) and FAILS on ANY difference, consulting NO register — an empty/forged register cannot mask drift (non-vacuous regeneration proof, T-12-02-02/05).
- [Phase ?]: 12-02 lifecycle robustness: shutil.move (not os.rename) for cross-device temp dirs; post-update parity/__snapshot__ existence guard catches moon's warn-only exit-0 for a nonexistent package (exit 2 + restore).
- [Phase ?]: 12-02 Phase 12 register pre-declares NO active snapshot rows: 12-01 migration is data-only, 12-02 harness and 12-03 CI wiring change zero snapshot bytes; the machine-readable skeleton is #-commented so it documents the format without approving anything.
- [Phase ?]: 12-03 Task 1 auto-selected option-a (D-05 one-way door): merge js runtime into linear-wasm-parity + stdlib compare_backends.py with rc + snapshot-tree sha256 digest proof (wasm cannot stdout-dump, A8); separate js job or per-fixture dump rejected (no added contract value).
- [Phase ?]: 12-03 failing-fixture naming via content hash: moon prints expected snapshot bytes (the '-' side), not filenames; compare_backends.py maps sha256(content) -> filename over the committed tree, with the failed-test label as fallback.
- [Phase ?]: 12-03 compare_backends.py reads one shared committed tree: the deterministic sha256 tree digest is verified unchanged before/after the run (read-only violation = exit 1), closing the PARITY-03 concurrency backstop for the aggregate + CI jobs.
- [Phase ?]: 12-03 CI wiring: js runtime step + compare_backends.py aggregate in linear-wasm-parity, diff_parity.py --frozen-only in parity-gate, verify_corpus.py --check in corpus (keep extended report --check); no --update in any run line; only network step is the MoonBit installer curl.
- [Phase ?]: CLOSE-01/CLOSE-02 upgraded to Phase 5 formalized records (D-07): evidence cited from in-repo host-verify.mjs + ci.yml linear-wasm-parity job + compare_backends.py + 2026-08-06 STATE.md records; no re-run, no new code
- [Phase ?]: D-05 one-way Catalog contract frozen (option-a): table + table_in_db(db,name) + function(name); StaticCatalog gains db_tables/functions registries with parsing-time ASCII case-fold lookup (D-03) and StaticCatalog-only lookup_exact exact-match primitive (never on the generic resolve path)
- [Phase ?]: analyze() end-to-end tracer (D-01/D-04/D-06): SELECT bodies re-parsed from the flat token-leaf CST via source_tokens + paren-depth clause split; bindings carry flattened start_byte/end_byte spans; analyzer diagnostics live on an independent channel (ANLY-01); quoted identifiers resolve via Catalog::table case-fold + byte-exact TableInfo.name re-check
- [Phase ?]: 05-03 full SELECT analysis model (D-01/D-02/D-03/D-05): analyzer re-parser splits every clause (SELECT list/FROM+JOIN/WHERE/GROUP BY/HAVING/QUALIFY/WINDOW/ORDER BY/LIMIT/UNION) with paren-depth awareness (GROUP/ORDER only break on a following BY); scope stack resolves CTE/subquery frames (inner-first shadowing, CTE beats catalog tables), aliases, qualified names (1=col/table, 2=alias.col|db.table, 3=db.table.col via table_in_db), and star expansion over resolved tables; UNION chains split only (EXCEPT is a projection modifier, INTERSECT not accepted — Pitfall 2); quoted identifiers stay case-exact via Catalog::table case-fold + TableInfo.name byte re-check (never StaticCatalog::lookup_exact on the generic path)
- [Phase ?]: 05-04 final ANAL-01 slice (D-02/D-04/D-06): function-call resolution + arity via Catalog::function (Function binding + unknown-function/function-arity), DML/CREATE VIEW column-level refs (UPDATE SET/WHERE, DELETE WHERE, INSERT column lists, MERGE SET; resolve_table_references untouched), complete analyzer diagnostic set (unknown-table/column/function, ambiguous-reference, function-arity) on the independent channel (ANLY-01), and docs/API.md public-surface update; NameRef gained call_args for depth-0 arg counting; CREATE VIEW body re-parsed from the AS-tail token slice (flat CST, no nested Select node); unknown-column gated on scope exposing columns
- [Phase ?]: pub(all) on the 8 select-model types suffices for cross-package read access (probe-verified on moon 0.1.20260724); no field-level pub needed
- [Phase ?]: split_select_model returns Some empty model (branches=[]) for an empty token stream — total function, no panic, no fabricated content
- [Phase ?]: Pitfall 3 option (a): SelectItem.except_cols captures * EXCEPT (...) slices; expand_star skips excluded columns (D-03 matching) so excluded columns never fabricate an edge (SC2)
- [Phase ?]: insert_body_location returns a plain tuple ((Int, Int)?, Int)? because named-tuple type syntax is not accepted by moon 0.1.20260724 (parse error); field semantics documented
- [Phase ?]: Flink gate (D-08): api.lineage_text rejects a flink selection AFTER a successful parse with Err(UnknownProfile(profile_id)) — structured FATHOM-SCHEMA-family ParseError, never a silent Ok(empty); the explicit 'lineage is Doris-only' message is deferred to the wire/CLI boundary (07-04)
- [Phase ?]: api.lineage_text optional catalog: @analyzer.StaticCatalog? maps Some(c) → derive_lineage(..., c) and None → derive_lineage_without_catalog(...) — the toolchain cannot spell trait objects, so the concrete optional StaticCatalog is the api surface (07-02 generic design respected)
- [Phase ?]: D-38 re-exports make api the shared core entry: @api.LineageResult / LineageEdge / LineageGap / StaticCatalog so binding (07-04) builds its envelope without importing lineage/ directly
- [Phase ?]: Task 1 executed as TDD (plan tdd=true): RED commit added 5 failing inline api tests (unbound lineage_text), GREEN commit implemented lineage_text + type re-exports — the api package's test convention is inline test blocks in api/api.mbt

### Pending Todos

From `.planning/todos/pending/` — ideas captured during sessions.

None yet.

## Blockers/Concerns

Non-blocking boundaries retained in phase artifacts:

- Disk `corpus/manifest.tsv` and three SQL fixtures are static/embedded-contract inputs; runtime tests do not load the files. Broader manifest-driven golden execution is deferred to Phase 2.
- `moon.mod` records observed `moon 0.1.20260724` while its policy comment names official v0.10.5; the mismatch is disclosed in review/security artifacts.
- Corpus revisions remain `unavailable-offline`/`known-gap`; no SHA is fabricated.

## Deferred Items

Items acknowledged and deferred at milestone close on 2026-08-05:

| Category | Item | Status |
|----------|------|--------|
| verification_override | Phase 01 VERIFICATION gaps_found (historical 9/11; disk-manifest gap closed by Phase 2 corpus_test.mbt embedded oracle; moon.mod label + unavailable-offline provenance remain documented boundaries) | override_closeout |
| verification_override | Phase 04 ECO-07 human-hosted VS Code launch (04-04 Task 4, blocking-human; requires a machine with VS Code) | **closed — Phase 5 CLOSE-01 formally verified** — installed VS Code 1.132.0 + @vscode/test-electron host harness (vscode/scripts/host-verify.mjs); 3 real-extension-host modes passed (diagnostics/format/completion/4.x-merge; 2.1 MERGE DORIS-PARSE-006 profile propagation; unavailable-server fallback). Fixed real bug: client requires LogOutputChannel `{log:true}` (plain channel crashed startup). |
| verification_override | Phase 04 ECO-06 rendered Monaco UI checkpoints (executor-documented 23/23 Chromium assertions; not independently reproducible in verifier env) | verified_by_executor |
| differential | FE/Nereids differential script execution (D-20 manual; Java FE offline-unavailable) | deferred |
| ci_recommendation | linear-Wasm runtime execution parity step before release | **closed — Phase 5 CLOSE-02 formally verified** — CI workflow `.github/workflows/` added with `moon build --target wasm` + parity fixture execution step (CLOSE-02) |
| descope_evidence | EDIT-01 incremental parsing — benchmark-gated descope | closed 2026-08-12 — 08-BENCHMARK.md (≥100KB median 27.47ms, linear, branch A) |

Known verification overrides: 5 (see STATE.md Deferred Items). Closeout type: override_closeout.

## Session Continuity

Last session: 2026-08-14T08:36:00Z
Stopped at: Phase 14 14-05 completed — HYG-01/02/03 complete, TC-01/02 blocked (official MoonBit channel); ready for Phase 15 when TC unblocks
Resume file: .planning/phases/14-release-hygiene-toolchain-pinning/14-RELEASE-READINESS.md

## Quick Tasks Completed

| Date | Task | Status |
|------|------|--------|
| 2026-08-06 | GitHub Releases Native `doris-lsp` delivery and JetBrains managed downloader | Complete |
| 2026-08-07 | Rename GitHub repository to `tchivs/fathom-sql`; sync README, JetBrains release links, and naming gate | Complete |

## Operator Next Steps

- Start the next milestone with /gsd-new-milestone
