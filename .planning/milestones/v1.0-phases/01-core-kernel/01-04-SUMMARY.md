---
phase: 01-core-kernel
plan: 04
subsystem: core-kernel
status: complete
tags: [moonbit, doris-select, profiles, corpus, exact-replay]

# Dependency graph
requires:
  - phase: 01-core-kernel/01-03
    provides: bounded recovery, stable diagnostics, strict/editor CST, exact replay
provides:
  - profile-gated industrial SELECT recursive descent and centralized Pratt expressions
  - released 2.1/3.x/4.x SELECT fixtures with manifest, coverage, and advisory differential records
  - offline inline manifest-loader contract and exact replay/version/recovery assertions
affects: [CORE-01, CORE-02, CORE-03, CORE-04, CORE-05, CORE-06, CORE-07]

# Actuals (#2632)
actuals:
  tokens: 13300
  tasks: 2
  commits: 4

# Tech tracking
tech-stack:
  added: []
  patterns: [recursive-descent SELECT clauses, centralized Pratt precedence, explicit released-profile gates, offline corpus metadata]

key-files:
  created:
    - corpus/manifest.tsv
    - corpus/coverage.tsv
    - corpus/differential.tsv
    - corpus/doris-2.1/select-industrial.sql
    - corpus/doris-3.x/select-industrial.sql
    - corpus/doris-4.x/select-industrial.sql
  modified:
    - parser/parser.mbt
    - test/parser_test.mbt

decisions:
  - "公开 profile 仍严格限定为 2.1、3.x、4.x；QUALIFY 在 2.1 选择下产生 DORIS-PARSE-006，不通过通用方言回退。"
  - "工业 SELECT 使用一个递归下降查询路径和一个 Pratt 表达式优先级表；CST 继续使用源 token/span 叶子，回放仍由根 source snapshot 提供。"
  - "TSV 以 released 官方 URL、页面标题、SQL fence、日期和显式 known-gap provenance status 记录来源；GitHub revision API 返回空结果时不伪造 SHA。"
  - "MoonBit 测试采用确定性的 inline manifest-loader contract，不在 parser core 引入文件系统或网络服务。"

# Metrics
duration: 5min
completed: 2026-08-03

# Summary
工业 SELECT 解析切片已覆盖 CTE/subquery、hints、projection modifiers、table references、PARTITION/TABLET/SAMPLE、JOIN variants、Pratt predicates/functions、window specifications、GROUPING SETS/ROLLUP/CUBE、HAVING、ORDER/LIMIT、INTO OUTFILE 和 UNION chains。版本入口继续只接受 2.1、3.x、4.x；版本无效特性使用稳定 `DORIS-PARSE-006` 诊断，并保持严格/编辑器结果、statement id、span 和字节回放契约。

三个 released-family fixture 目录已建立。`manifest.tsv` 每行包含 profile、exact release/minor、feature introduction、官方 URL、retrieval date、pinned revision 字段、page heading、SQL code fence、category、support status、parse mode、classification 和 provenance status；覆盖 supported、malformed/recovery、invalid-encoding、unsupported-version、contextual-keyword 与 CORE-04 boundary rows。`coverage.tsv` 明确按 profile/category 的支持数和 known gaps，`differential.tsv` 明确 FE/Nereids 与 SQLGlot 仅 advisory、离线未运行且不能扩大 public acceptance。

## Task Commits

1. **Task 1: Expand profile-gated industrial SELECT and Pratt expressions** — `de9f1e3`
2. **Task 2: Establish released fixture manifest, goldens, and coverage links** — `6c6cc3b`
3. **Task 2 correction: keep recovery fixture parser-negative** — `9f8f9ba`
4. **Task 1 follow-up: accept released projection modifiers** — `fb3666a`

## Verification

- `moon test` — **41 passed, 0 failed**。
- `moon check --target native` — 通过，0 errors。
- `moon build --target native --release` — 通过，0 errors。
- `moon test test/parser_test.mbt` — 8 passed, 0 failed；包含工业 SELECT、profile gate、manifest metadata、projection modifiers、strict/editor、invalid encoding、span 与 replay assertions。
- `moon test test/recovery_test.mbt -i 1` — 1 passed，确认深度/bytes cap 不循环并保留 source-backed replay。

## Coverage and Known Gaps

- 已覆盖：三 released profile、CTE/subquery、hints、projection modifiers、table refs/options、JOIN、predicates/functions、windows、grouping extensions、HAVING/ORDER/LIMIT、Doris SELECT clause、set-operation chains、contextual quoted identifiers、malformed/recovery、invalid UTF-8、strict/editor 和 exact replay。
- 官方页面 URL、页面标题 `SELECT`、SQL code fence 和检索日期已由页面读取结果核验。
- `apache/doris-website` GitHub commits API 对尝试的 versioned SELECT paths 返回空数组；因此 manifest 的 `pinned_source_revision=unavailable-offline` 与 `provenance_status=known-gap` 是明确已知缺口，不是伪造的 commit。后续取得可核验 commit SHA 后，只需更新 TSV provenance，不应改变 parser acceptance。
- corpus fixture 测试不读取文件系统；MoonBit runtime 使用 inline deterministic loader contract。磁盘 fixture、manifest、coverage、differential 均为 Git 数据，parser core 无网络/FE/DB/catalog 依赖。
- 未宣称完整官方示例枚举、FE 执行语义、catalog-required 行为、formatter 快照或 differential pass；这些在 coverage/differential 中显式标为 gap/advisory。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 深度恢复后的尾随 delimiter 不前进**
- **Found during:** Task 1 tracer verification。
- **Issue:** 资源上限返回后，`recover_expression` 对 `)`/`,` 等同步 delimiter 有意不消费；parse-segment 尾随循环若未显式前进会重复观察同一 token，导致深嵌套输入无法终止。
- **Fix:** 尾随恢复调用记录 cursor position，在恢复无进展时消费一个 token；同时保留 missing/error 节点和原始 bytes。
- **Files modified:** `parser/parser.mbt`
- **Commit:** `de9f1e3`

**2. [Rule 1 - Bug] Released ALL EXCEPT projection was rejected as an empty projection**
- **Found during:** final projection modifier acceptance probe。
- **Issue:** Official SELECT grammar permits `ALL EXCEPT (...)` without a separate select expression; the generic empty-list diagnostic incorrectly rejected it。
- **Fix:** Treat a balanced `ALL EXCEPT` modifier as a complete projection and add `DISTINCTROW` handling。
- **Files modified:** `parser/parser.mbt`, `test/parser_test.mbt`
- **Commit:** `fb3666a`

**Total deviations:** 2 auto-fixed Rule 1 bugs；无架构变更，无后续 phase 实现。

## Auth Gates

None。

## Known Stubs

None。`unavailable-offline` 只出现在 provenance 字段并由 `known-gap` 明确解释，不是 UI/parser fallback 或空数据 stub。

## Threat Surface Scan

| Flag | File | Description |
|------|------|-------------|
| threat_flag: provenance-gap | `corpus/manifest.tsv` | Official website revision API returned an empty result; rows retain explicit known-gap metadata instead of an unverifiable SHA. |

No new runtime trust boundary was introduced. Parser remains synchronous/offline; profile gate, recovery limits, source-backed spans, and advisory differential separation remain active.

## Self-Check: PASSED

- `parser/parser.mbt` and `test/parser_test.mbt` exist and are present in `de9f1e3`/`fb3666a` history.
- All six corpus artifacts exist and are present in `6c6cc3b`/`9f8f9ba` history.
- Task commits `de9f1e3`, `6c6cc3b`, `9f8f9ba`, and `fb3666a` are present.
- Final `moon test` reports 41 passed and 0 failed.
- Native check and release build both report 0 errors.
- Pre-existing `.planning/config.json`, `.planning/.omp-checkpoint.json`, `.planning/.omp-next-action.json`, `.planning/phases/01-core-kernel/01-PATTERNS.md`, and `_build/` were not staged.

---
*Phase: 01-core-kernel*
*Plan: 04 completed: 2026-08-03*
