---
phase: 01-core-kernel
reviewed: 2026-08-03T17:07:46Z
depth: deep
files_reviewed: 40
files_reviewed_list:
  - moon.mod
  - moon.pkg
  - source/moon.pkg
  - source/source.mbt
  - token/moon.pkg
  - token/token.mbt
  - lexer/moon.pkg
  - lexer/lexer.mbt
  - syntax/moon.pkg
  - syntax/syntax.mbt
  - parser/moon.pkg
  - parser/parser.mbt
  - api/moon.pkg
  - api/api.mbt
  - printer/moon.pkg
  - printer/printer.mbt
  - test/moon.pkg
  - test/source_test.mbt
  - test/parser_test.mbt
  - test/recovery_test.mbt
  - corpus/manifest.tsv
  - corpus/coverage.tsv
  - corpus/differential.tsv
  - corpus/doris-2.1/select-industrial.sql
  - corpus/doris-3.x/select-industrial.sql
  - corpus/doris-4.x/select-industrial.sql
  - .planning/PROJECT.md
  - .planning/REQUIREMENTS.md
  - .planning/ROADMAP.md
  - .planning/phases/01-core-kernel/01-CONTEXT.md
  - .planning/phases/01-core-kernel/01-RESEARCH.md
  - .planning/phases/01-core-kernel/01-01-PLAN.md
  - .planning/phases/01-core-kernel/01-02-PLAN.md
  - .planning/phases/01-core-kernel/01-03-PLAN.md
  - .planning/phases/01-core-kernel/01-04-PLAN.md
  - .planning/phases/01-core-kernel/01-01-SUMMARY.md
  - .planning/phases/01-core-kernel/01-02-SUMMARY.md
  - .planning/phases/01-core-kernel/01-03-SUMMARY.md
  - .planning/phases/01-core-kernel/01-04-SUMMARY.md
  - .claude/CLAUDE.md
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 1: Code Review Report

**Reviewed:** 2026-08-03T17:07:46Z  
**Depth:** deep  
**Files Reviewed:** 40  
**Status:** clean

## Summary

本次最终 deep review 复核当前主树完整 40-file scope，覆盖 source/token/lexer/syntax/parser/api/printer、全部测试、三份工业 SELECT corpus、manifest/coverage/differential，以及 Phase 1 的 requirements、roadmap、context、research、plans、summaries 和 review-fix iteration 13。最新提交 `d6f5b76`（T-01-14）及此前 UInt clean-cutover 提交 `27b6d63` 均已按当前源码和回归断言复核。

未发现可证实的 Critical、Warning 或 Info finding。frontmatter active counts 均为零，历史 CR-01..CR-09、WR-01..WR-38、T-01-06 和 T-01-14 均已闭合；工具链标签、离线 provenance、磁盘 corpus 未被测试加载和 accepted low-risk log 等明确边界不计为 active code-review finding，因此报告标记为 `clean`。

## Historical Findings Status

- **CR-01..CR-09 CLOSED：** source/lexer/parser/API 保留 invalid UTF-8 与 unterminated lexical material，并维持 source/max-byte/token/recursion/recovery/diagnostic bounds、JOIN 条件、clause/UNION boundary、GROUPING 空列表及 QUALIFY/TABLET profile gate。
- **WR-01..WR-10 CLOSED：** recovery budget、trivia/semicolon segmentation、LineIndex/span 校验、root-only replay、syntax constructors、feature metadata/gates 和空 segment 处理均已复核。
- **WR-11..WR-18 CLOSED：** projection alias、NATURAL directional JOIN、feature-event ownership、RHS/window validity propagation、TABLET contextual alias lookahead、identifier-after-dot、NULLS/frame required components 均已复核。
- **WR-19..WR-23 CLOSED：** required-symbol diagnostics、released reserved classification、numeric lexical errors、non-empty segment identity 和 low-level negative-limit span safety 均有当前实现与测试证据。
- **WR-24..WR-31 CLOSED：** TABLET/TABLESAMPLE/SAMPLE value-unit/repeatable productions、wildcard context、required option payload/list constraints、window ordering、resource span identity、`* EXCEPT`、以及 COUNT wildcard argument state 均已复核。
- **WR-32..WR-38 CLOSED：** SQL `NULL`/`TRUE`/`FALSE` operands、invalid quoted/comment token caps、WINDOW/GROUPING SETS trailing commas、`WITH RECURSIVE` diagnostic、DISTINCT/DISTINCTROW `EXCEPT` restriction 和 singular SAMPLE/TABLESAMPLE values 均有修复与回归覆盖。
- **T-01-06 CLOSED（`27b6d63`）：** `ParserDiagnostic` 与 `PrimitiveDiagnostic` 的 `statement_id` 均为 `UInt`；snapshot-local counters 使用 `0U`/`1U`，strict/editor、replay、span、resource、lexical、semicolon trivia 和 reset cases 已覆盖。实现/API 中不再有 signed `statement_id : Int` 或负值比较。
- **T-01-14 CLOSED（`d6f5b76`）：** `ProfileMetadata` 保存 canonical exact release 与受控 feature-introduction；`ParseOptions::from_manifest`、`parse_with_metadata` 和 `for_profile_with_metadata` 在进入 parser 前拒绝 unknown profile、metadata mismatch 和 unsupported introduction，并把 validated profile context 传入 feature gates。embedded 2.1/3.x/4.x fixtures 覆盖 valid、recovery、invalid-encoding、strict/editor、diagnostic/span 和 exact replay。
- **T-01-01、T-01-02、T-01-03、T-01-05、T-01-07、T-01-09、T-01-10、T-01-11、T-01-12、T-01-15 MITIGATED：** 当前 source-backed span、progress guards、byte/token/recursion/recovery/diagnostic caps、explicit profiles、strict/editor shared CST、invalid-byte retention 和 replay tests 保持有效。
- **T-01-08、T-01-13、T-01-SC ACCEPTED（non-blocking）：** parser core 无 secrets store、external I/O、FE/DB/network 或 third-party runtime trust boundary；低风险 accepted disposition 仍待 security auditor 的正式 `SECURITY.md` log，不构成当前 review blocker。
- **T-01-04 和 T-01-16 NON-BLOCKING BOUNDARY：** observed MoonBit executable `0.1.20260724 (5f1406a 2026-07-24)` 与 `moon.mod` 注释中的 official v0.10.5 line label 不一致；manifest revision 为 `unavailable-offline`/`known-gap`。两者均已诚实披露，未被伪造为 reproducible evidence，也未被本 review 计为 active finding。

## Metadata-Aware and Grammar Review

- **Metadata-aware route：** `parse_with_metadata` 先经 `ParseOptions::from_manifest` 校验 profile/exact release/feature introduction/mode，再进入 `parse`；validated context 同时驱动 parser profile gates 和 `ParseResult` metadata fields。`for_profile_with_metadata` 对 caller-supplied `ProfileMetadata` 做全字段 canonical validation，legacy `parse_with_ids` 保持 canonical profile path，不存在绕过校验的 fallback。
- **Embedded fixture links：** `test/parser_test.mbt` 的 `EmbeddedManifestFixture` 通过 metadata-aware API 检查 valid 状态、profile/release/introduction 回传、all-spans-in-bounds、diagnostic namespace 和 byte-exact replay，并覆盖 2.1、3.x、4.x、invalid encoding 与 editor recovery；mismatch/unknown/unsupported rows 在 parse 前被拒绝。
- **Industrial grammar：** 当前 parser 保持单一 recursive-descent SELECT/query 路径和 centralized Pratt expression path，覆盖 CTE/subquery、hints、projection modifiers、table references、PARTITION/TABLET/SAMPLE/TABLESAMPLE、JOIN variants、predicates/functions、windows、GROUPING SETS/ROLLUP/CUBE、HAVING、ORDER/LIMIT、INTO OUTFILE 和 UNION chains；released profile gates 对 QUALIFY/TABLET 保持 source-backed `DORIS-PARSE-006`。
- **Strict/editor、recovery/resource、spans/replay：** 两种 mode 共享 CST/diagnostic shape；MISSING/ERROR/SKIPPED 节点、progress/recovery guards、有限 byte/token/recursion/recovery/diagnostic budgets、invalid lexical material 与 source-backed spans/replay 均有当前实现和回归断言。

## Known Boundaries (non-active)

- `corpus/manifest.tsv` 与三个磁盘 `select-industrial.sql` fixture 已纳入 40-file 静态审查，但 MoonBit test runtime 使用 deterministic embedded rows，不读取 filesystem fixture；因此本报告只确认 metadata-aware embedded links，不宣称 disk-manifest execution。
- manifest 的 `pinned_source_revision=unavailable-offline`/`provenance_status=known-gap` 保留为真实 provenance gap；FE/Nereids 与 SQLGlot differential rows 是 advisory、offline not-run，不能扩大 public acceptance。
- exact release/introduction metadata 现在通过 metadata-aware API 进入 profile context 和 feature gates；disk TSV 本身仍是静态 Git data，未被 runtime loader 自动消费。
- inherited acceptance gates 不是本 reviewer 本轮执行：主会话报告 `moon check --target native` **0 errors / 116 warnings**、release build **0 errors / 109 warnings**、`moon test` **93 passed / 0 failed**。warnings 与 toolchain/provenance 边界均不改变 active finding counts。

## Narrative Findings (AI reviewer)

未发现当前可复现的 active finding。复核重点包括 metadata-aware validation/propagation、UInt statement identity clean-cutover、wildcard context、strict/editor parity、recovery/CST/diagnostic/span/replay invariants、resource limits、reserved/contextual words、released-profile gates、industrial SELECT grammar、corpus metadata links 和历史 CR/WR/T disposition。当前 source、tests、plans/summaries 与修复记录相互一致；已知边界已单独披露且未被伪装成实现完成度。

## Verification Boundary

本报告依据当前主树静态源码、最新 token/api/parser/tests、commit `d6f5b76` diff、UInt 修复、corpus TSV/fixtures、plans/summaries、requirements、阶段上下文和 `01-REVIEW-FIX.md` iteration 13 完成。reviewer 未运行 formatter、linter 或 project-wide/full suite，也未将继承命令冒充本轮执行；没有改动源码、测试、计划或 config。继承自主会话的 gates 仅作为 evidence boundary：`moon check --target native` 0 errors/116 warnings，release build 0 errors/109 warnings，`moon test` 93/93。

未发现外部 I/O、FE、数据库、网络或 runtime-specific parser 依赖，亦未发现可证实的 security blocker。未宣称完整官方示例枚举、FE 执行语义、catalog-required 行为、formatter snapshots、differential pass 或磁盘 corpus loader execution；这些限制分别由 corpus known-gap/advisory、toolchain boundary 和 embedded-fixture boundary 明确保留。

---

_Reviewed: 2026-08-03T17:07:46Z_  
_Reviewer: Claude (gsd-code-reviewer)  
_Depth: deep_
