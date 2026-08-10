---
phase: 11-flink-grammar-and-recoverable-cst
reviewed: 2026-08-09T00:00:00Z
depth: deep
files_reviewed: 8
files_reviewed_list:
  - parser/parser.mbt
  - parser/flink_grammar.mbt
  - syntax/syntax.mbt
  - api/api.mbt
  - dialect/flink.mbt
  - parity/flink_grammar_test.mbt
  - parity/fixtures/flink-grammar/manifest.tsv
  - scripts/extract_flink_grammar.py
findings:
  critical: 4
  warning: 8
  info: 4
  total: 16
status: issues_found
---

# Phase 11: Code Review Report

**Reviewed:** 2026-08-09
**Depth:** deep（跨文件调用链 + 实证复现）
**Files Reviewed:** 8
**Status:** issues_found

## Summary

Phase 11 实现了 Flink 语句级 grammar（query/DML/aux/DDL/CREATE TABLE/TVF/MATCH_RECOGNIZE）并退役 FATHOM-PARSE-008，整体结构扎实：方言策略表（`precedence(context, cursor)`）、Flink 独立类型/DDL 生产、双向负门禁（FATHOM-PARSE-009/007）、fixture + manifest 溯源（D-05）与 extract_flink_grammar.py 校验器均按计划落地；快照组覆盖 90+ fixture × strict/editor，正例（全量 MATCH_RECOGNIZE、TVF named-arg、WITH-CTE UPDATE）经实证 valid=true。

但存在 **4 个 BLOCKER**：两个可导致**解析进程栈溢出崩溃（SIGSEGV）**的无界递归向量（`parse_flink_data_type` 嵌套 `<` 泛型、MATCH_RECOGNIZE 嵌套 `{- ... -}` PatternExclude）；一个**Doris 零漂移回归**（`is_flink_only_column_start` 无条件把列名 `watermark` 判为 Flink 子句，合法 Doris `CREATE TABLE t (watermark INT)` 被 FATHOM-PARSE-009 拒绝）；以及 `with_prefix_verb` 在 `WITH <name>`（缺 AS/语句尾）输入上的**数组越界 abort**（PanicError/SIGABRT，双方言同现，违背 recoverable-CST 有界恢复承诺）。

另有 4 个 MAJOR 语法缺口（声明 in-scope 却未实现/错误拒绝：`ROW<...>` 类型整体失效、SUBSET 仅接受 PATTERN 之前的非标准位置、`watermark`/`constraint`/`interval` 等非保留字列名被劫持、`TIMESTAMP(p) WITH [LOCAL] TIME ZONE` 与 `AT TIME ZONE` 缺失）。所有关键结论均通过 `fathom-sql parse` CLI 在 native 构建上实证复现（见各 finding 的 `[REPRO]`）。

`scripts/extract_flink_grammar.py` 安全检查通过：仅读文件、无 `subprocess`/shell、路径经 `os.path.join` 拼接、无注入面。

## Blockers (Critical)

### CR-01: `parse_flink_data_type` 嵌套 `<` 泛型无界递归 → 栈溢出 SIGSEGV

**File:** `parser/flink_grammar.mbt:611-616`（`parse_flink_data_type` 的 `< ... >` 泛型分支）
**Issue:** `parse_flink_data_type` 进入时仅调用 `depth_allowed`（基于 `parenthesis_depth`，只统计 `(`/`)`），而嵌套泛型 `ARRAY<ARRAY<...>>` 用 `<`/`>` 推进，**不增加括号深度**。`<` 分支内的 `parse_flink_data_type(cursor, ...)` 递归无任何深度/步数上限。攻击者/编辑输入 `CREATE TABLE t (a ARRAY<ARRAY<...INT...>>)` 可触发 O(嵌套深度) 递归，超过原生栈后 **SIGSEGV**（进程崩溃，而非返回可恢复 CST）。
**[REPRO]** `python3 -c "print('CREATE TABLE t (a ' + 'ARRAY<'*150000 + 'INT' + '>'*150000 + ')')" | fathom-sql parse --dialect flink --profile flink-2.3.0 -` → `EXIT 139`（SIGSEGV）。token 数约 30 万，低于默认 `max_tokens=1_000_000`，故限流不生效。
**Fix:** 给泛型递归增加深度计数并在入口检查（如把 `depth_allowed` 扩展为同时统计 `<` 深度，或传入 `depth+1` 并比对 `max_recursion_depth`）：
```moonbit
// parse_flink_data_type 增加 depth 参数；< 分支内：
valid = parse_flink_data_type(cursor, state, source, statement_id, depth + 1) && valid
// 入口：
if depth > state.limits.max_recursion_depth || !depth_allowed(...) { resource_diagnostic(...); return false }
```

**Fixed:** commit `217055c` — `parse_flink_data_type` now threads an explicit `depth` counter honoring `max_recursion_depth`; on exceeding the limit it emits `FATHOM-PARSE-004` and returns false (recoverable CST). Repro `ARRAY<...>` ×150000 exits 0 with `valid:false` + one resource diagnostic, never SIGSEGV.

### CR-02: MATCH_RECOGNIZE 嵌套 `{- ... -}` PatternExclude 无界递归 → 栈溢出 SIGSEGV

**File:** `parser/flink_grammar.mbt:2346-2363`（`parse_pattern_primary` 的 `{` PatternExclude 分支）
**Issue:** `{- ... -}` 排除体的内层内容经 `parse_pattern_factor` → `parse_pattern_primary` 递归解析；`{`/`-` 符号**不增加括号深度**，`depth_allowed` 无法约束。嵌套 `{- {- {- ... A -} -} -}` 可无限递归 → 原生栈溢出。
**[REPRO]** `python3 -c "print('SELECT * FROM t MATCH_RECOGNIZE (PATTERN (' + '{- '*60000 + 'A' + ' -}'*60000 + ') DEFINE A AS A.x = 1)')" | fathom-sql parse --dialect flink --profile flink-2.3.0 -` → `EXIT 139`（SIGSEGV）。
**Fix:** 与 CR-01 相同——给 pattern 递归（`parse_pattern_expr`/`parse_pattern_concat`/`parse_pattern_factor`/`parse_pattern_primary`）增加显式深度参数并受 `max_recursion_depth` 约束，或每次递归前调用 `depth_allowed` 风格的预算检查。

**Fixed:** commit `e3cd867` — the four pattern functions thread an explicit `depth` counter honoring `max_recursion_depth`; on exceeding the limit they emit `FATHOM-PARSE-004` and return false (recoverable CST). Repro `{- ...` ×60000 exits 0 with `valid:false` + one resource diagnostic, never SIGSEGV.

### CR-03: Doris 零漂移回归 — 合法列名 `watermark` 被 FATHOM-PARSE-009 拒绝

**File:** `parser/parser.mbt:3087-3097`（`is_flink_only_column_start`）、`:3116-3126`（Doris `parse_create_table_body` 门禁分支）
**Issue:** `is_flink_only_column_start` 对 `WATERMARK` **无条件**返回 true。`watermark` 不在 Doris reserved 行（`dialect/doris.mbt` 无该行），因此 `CREATE TABLE t (watermark INT)` 是合法 Doris 语句（`watermark` 是普通标识符）。D-04 门禁本意是拒绝 Flink `WATERMARK FOR ...` 子句，却把“列名为 watermark”一并拒绝，**破坏了 Doris 接受面**（phase 承诺 Doris 213 快照基线字节不变，但该输入无快照覆盖，属未捕获回归）。
**[REPRO]** `fathom-sql parse --dialect doris --profile 4.x` 输入 `CREATE TABLE t (watermark INT)` → `valid: false`，diagnostics `[('FATHOM-PARSE-009','syntax is not supported in the selected dialect')]`。
**Fix:** 门禁应仅在 WATERMARK 是子句形态（后随 `FOR`）时触发；否则放行给 `parse_column_definition`：
```moonbit
Some(raw) if bytes_equal_ci(raw, b"WATERMARK") =>
  peek_raw(cursor, 1) is Some(next) && bytes_equal_ci(next, b"FOR")
```

**Fixed:** commit `c0ae0b2` — the WATERMARK gate now fires only when followed by `FOR`; a bare `watermark` column parses as an ordinary identifier. Repro `CREATE TABLE t (watermark INT)` under doris-4.x is `valid:true` with zero diagnostics.

### CR-04: `with_prefix_verb` 数组越界 abort — `WITH <name>` 半成品输入崩溃（双方言）

**File:** `parser/parser.mbt:1898-1901`（`with_prefix_verb` 的 `has_column_list` 读取）
**Issue:** 循环内 `i = i + 1` 跳过 CTE 名后**未重新检查 `i >= length`** 就执行 `stream.raw(indices[i])`。`match` 的 scrutinee `indices[i]` 在 guard `i < length` 判定前即求值，guard 形同虚设。输入 `WITH t`（两个显著 token，无 AS/语句尾）时 `i == indices.length()` → `Array::at` 越界 → **PanicError abort**（退出码 134/SIGABRT）。该函数被 `parse_flink_segment`（新增 Flink WITH-UPDATE/DELETE 分支）与 Doris 段共用，`WITH t` 在两种方言下都崩溃——直接违背 recoverable-CST 对半成品编辑输入“有界恢复、绝不崩溃”的承诺。
**[REPRO]** `printf 'WITH t' | fathom-sql parse --dialect flink --profile flink-2.3.0 -` → `PanicError ... at @fathom/sql/parser.with_prefix_verb (parser.mbt:1898)`，`EXIT 134`；Doris 侧同现。
**Fix:** 跳过 CTE 名后立即补 `if i >= length { return None }`，并将 `has_column_list` 的 guard 移到索引读取之前（用 `indices.get(i)` 取代 `indices[i]`）：
```moonbit
i = i + 1
if i >= length { return None }
let has_column_list = match indices.get(i).map(index => stream.raw(index)).flatten() {
  Some(raw) => raw == b"("
  None => false
}
```

**Fixed:** commit `7dbf792` — `with_prefix_verb` bails with `None` when `i >= length` after skipping the CTE name and reads via guarded `indices.get(i)`; the dead guard is removed (IN-03). Repro `WITH t` under both dialects exits 0 with a recoverable unsupported-statement diagnostic, never SIGABRT.

## Warnings (Major)

### MJ-01: `ROW<...>` 类型整体失效（声明 in-scope 但全部被拒）+ 字段类型参数化缺陷

**File:** `parser/flink_grammar.mbt:587-625`（`parse_flink_data_type`）
**Issue:** 研究/计划明确 `ROW<f1 T1, f2 T2>`（`Parser.tdd:764` ExtendedSqlRowTypeName）为 in-scope，但实现**完全无法解析 ROW**：`ROW` 在 Flink reserved 行（`dialect/flink.mbt:150`），`is_identifier_candidate(ROW)` 为 false → 进入即报 `expected Flink data type`。即使假设 ROW 可作类型名，泛型元素循环的“trailing identifier”设计（`:617-619`，先按类型消费字段名、再按字段名消费类型标识符）在字段类型带 `(p,s)`/`<...>` 时会把后缀悬空（`ROW<f1 DECIMAL(10,2)>` 的 `(10,2)` 无法消费）。
**[REPRO]** `CREATE TABLE t (a ROW<f1 INT, f2 STRING>)` / `ROW<INT, STRING>` / `ROW<f1 DECIMAL(10,2)>` 全部 `valid: false`（`expected Flink data type` + `expected closing table body parenthesis`）；对照 `ARRAY<DECIMAL(10,2)>` 与 `MAP<STRING, INT>` 均为 `valid: true`。
**Fix:** `parse_flink_data_type` 显式接受保留字类型名（`ROW`，以及未来 `INTERVAL`），并在泛型元素内先消费字段名、再解析字段类型（复用 `parse_flink_data_type` 解析类型含 `(p,s)`/`<...>` 后缀）；或对 ROW 元素走独立分支。

**Fixed:** commit `91e8abe` — `ROW` is accepted explicitly as a data-type name and ROW generic elements parse as `[field_name] type` via `parse_flink_row_element` (field name = identifier followed by a word token). `ROW<f1 INT, f2 STRING>` / `ROW<INT, STRING>` / `ROW<f1 DECIMAL(10,2)>` all parse `valid:true` with zero diagnostics; `ARRAY<DECIMAL(10,2)>` / `MAP<STRING, INT>` regressions still pass.

### MJ-02: MATCH_RECOGNIZE `SUBSET` 仅接受 PATTERN 之前的非标准位置

**File:** `parser/flink_grammar.mbt:2033-2052`（pre-pattern 循环内）、`:1987-1991`（DEFINE 必需检查）
**Issue:** `SUBSET` 被放在 pre-PATTERN 子句循环里，而 Calcite `MatchRecognize` 生产中 `subsetList` 位于 `PATTERN`/`WITHIN` 之后、`DEFINE` 之前。标准写法 `PATTERN (A B) SUBSET U = (A, B) DEFINE ...` 解析失败（报 `expected DEFINE clause`）。fixture `match-recognize-subset` 用的 `SUBSET U = (...) PATTERN ...` 是**非标准顺序**，其 snapshot 只是冻结了实现的错误行为。
**[REPRO]** `SELECT * FROM t MATCH_RECOGNIZE (PATTERN (A B) SUBSET U = (A, B) DEFINE A AS A.x = 1, B AS B.x = 2)` → `valid: false`（`expected DEFINE clause in MATCH_RECOGNIZE` + 尾部 001）。
**Fix:** 将 SUBSET 分支移到 PATTERN/WITHIN 之后、DEFINE 检查之前（按 `Parser.jj:3182` 顺序），并更新 fixture 为标准顺序 SQL。

**Fixed:** commit `5033eb6` — SUBSET is parsed by `parse_flink_match_recognize_subset` after PATTERN/WITHIN and before DEFINE; the `match-recognize-subset` fixture is rewritten to standard order and its snapshots re-frozen (registered in approved-changes.md §8, single approved parity `--update`). The standard form parses `valid:true`; the pre-PATTERN position is rejected.

### MJ-03: Flink 非保留字被无条件劫持为子句/约束起始 — `watermark`/`constraint`/`interval` 列名被拒

**File:** `parser/flink_grammar.mbt:1227-1231`（`parse_flink_create_table_body` WATERMARK 分发）、`:1259-1268`（`is_flink_table_constraint_start` CONSTRAINT）、`parser/parser.mbt:1069-1073`（`is_flink_interval_literal`）
**Issue:** WATERMARK、CONSTRAINT、INTERVAL 均不在 Flink reserved 行，是合法非保留字。实现却把它们无条件当作子句/字面量起始：
- `CREATE TABLE t (watermark INT)` → 报 `expected FOR after WATERMARK`（真实 Flink 允许 `watermark` 作列名）；
- `CREATE TABLE t (constraint INT)` → 报 `expected PRIMARY KEY or UNIQUE in table constraint`；
- `SELECT interval FROM t` → 报 `expected interval value after INTERVAL`（Doris 下同一输入 `valid: true`）。
**[REPRO]** 三个输入均在 flink-2.3.0 下 `valid: false`。
**Fix:** 与 CR-03 同族：WATERMARK 门禁须 `peek == FOR`、CONSTRAINT 门禁须 `peek` 后确实是约束形态、INTERVAL 仅在其后跟字面量（`'...'`/数字）时按区间字面量解析，否则回落为标识符操作数。

**Fixed:** commit `4f09d1c` — WATERMARK gate requires following `FOR`; CONSTRAINT gate requires `CONSTRAINT <name> (PRIMARY KEY|UNIQUE)` (two tokens ahead); INTERVAL is an interval literal only when followed by a string/number value, else an identifier operand. `CREATE TABLE t (watermark INT)`, `(constraint INT)`, and `SELECT interval FROM t` all parse `valid:true` under flink-2.3.0; WATERMARK FOR / CONSTRAINT c PRIMARY KEY / `INTERVAL '5' SECOND` regressions still pass. The `tvf-incomplete-interval` goldens re-freeze this gate outcome (registered §8).

### MJ-04: 声明 in-scope 的 `TIMESTAMP(p) WITH [LOCAL] TIME ZONE` 类型与 `AT TIME ZONE` 运算符未实现

**File:** `parser/flink_grammar.mbt:587-630`（`parse_flink_data_type`）、`parser/parser.mbt`（Pratt 无 `AT TIME ZONE`）
**Issue:** 研究 §7.2/§7.1 把 `TIMESTAMP(p) WITH [LOCAL] TIME ZONE` 与 `AT TIME ZONE` 列为 in-scope，但：`parse_flink_data_type` 消费 `(p)` 后不处理 `WITH [LOCAL] TIME ZONE` 后缀（`WITH` 被误当表级 connector 选项子句）；`precedence` 表无 `AT TIME ZONE`，表达式 `ts AT TIME ZONE 'UTC'` 无法解析。无 fixture 覆盖。
**[REPRO]** `CREATE TABLE t (a TIMESTAMP(3) WITH LOCAL TIME ZONE)` → `valid: false`（`expected ( after table WITH connector options` 等）；`SELECT ts AT TIME ZONE 'UTC'` → 解析失败（AT 后无法消费）。
**Fix:** 在 `parse_flink_data_type` 的类型后缀增加 `[ WITH [LOCAL] TIME ZONE ]` 分支；在 Flink precedence 分支为 `AT` 加二元优先级（Calcite `SqlStdOperatorTable.AT_TIME_ZONE`，A3 级），并在 RHS 消费 `TIME ZONE` 限定。

**Fixed:** commit `1ac1438` — `parse_flink_data_type` consumes the `[ WITH [LOCAL] TIME ZONE ]` suffix; `precedence_flink` adds `AT` at precedence 3 and the binary-operator loop consumes the `TIME ZONE` qualifier before the RHS. `CREATE TABLE t (a TIMESTAMP(3) WITH LOCAL TIME ZONE)` and `SELECT ts AT TIME ZONE 'UTC'` parse `valid:true` with zero diagnostics.

## Warnings (Minor)

### MN-01: `ANALYZE TABLE t COMPUTE STATISTICS`（真实 Flink 形式）未处理 → 尾部 001

**File:** `parser/flink_grammar.mbt:493-510`（`parse_flink_analyze`）
**Issue:** 真实 Flink `ANALYZE TABLE t [PARTITION(...)] COMPUTE STATISTICS [NOSCAN]` 的 `COMPUTE STATISTICS` 尾部未消费，落入 `finish_statement` 的 trailing 001 报错。
**Fix:** 在 `parse_flink_analyze` 增加 `[COMPUTE STATISTICS [NOSCAN]]` 可选尾（`parserImpls.ftl:3413-3443` 核验后实现）。

**Fixed:** commit `c7945d6` — `parse_flink_analyze` consumes the optional `COMPUTE STATISTICS [NOSCAN]` tail after the optional PARTITION spec. `ANALYZE TABLE t COMPUTE STATISTICS [NOSCAN]` and `ANALYZE TABLE t PARTITION (dt='1') COMPUTE STATISTICS NOSCAN` parse `valid:true` with zero diagnostics.

### MN-02: MATCH_RECOGNIZE pre-PATTERN 子句循环允许任意顺序/重复（过度接受）

**File:** `parser/flink_grammar.mbt:2007-2053`
**Issue:** pre-pattern 循环对 PARTITION BY / ORDER BY / MEASURES / ONE|ALL ROWS / AFTER MATCH / SUBSET 无限重复、任意乱序接受（如 `MEASURES ... ORDER BY ...` 也 valid），偏离钉住 grammar 的固定子句顺序，属语法过度接受。
**Fix:** 按 `Parser.jj:3091-3154` 的固定顺序解析，遇到非当前子句即终止（保留 PATTERN/DEFINE 作为同步点）。

**Fixed:** commit `5033eb6` (with MJ-02) — the pre-PATTERN clauses parse in the pinned fixed order (PARTITION BY → ORDER BY → MEASURES → ONE|ALL ROWS PER MATCH → AFTER MATCH SKIP), each optional and at most once; out-of-order/repeated clauses surface at the PATTERN requirement / trailing-token check.

### MN-03: TVF 命名参数名未校验（`data`/`timecol`/`size`）

**File:** `parser/flink_grammar.mbt:1790-1810`（`parse_flink_tvf_argument`）
**Issue:** `TUMBLE(foo => bar, ...)` 等任意命名参数名均被接受（只要凑满 3 个参数），不做参数名白名单校验。语法级可接受，但与“TVF 命名参数”语义不符。
**Fix:** 在 named-arg 分支按 TVF 名（TUMBLE/HOP/CUMULATE/SESSION）校验参数名集合（`DATA`/`TIMECOL`/`SIZE`/`OFFSET` 等），未知名报 FATHOM-PARSE-002。

**Fixed:** commit `f8dcd6b` — the TVF name threads through `parse_flink_tvf_arguments`/`parse_flink_tvf_argument`; named arguments are validated per TVF (`DATA`/`TIMECOL`/`SIZE`/`OFFSET` and `SLIDE`/`STEP`/`GAP` where applicable). `TUMBLE(data => ..., timecol => ..., size => ...)` stays valid; `TUMBLE(foo => ...)` emits a localized `FATHOM-PARSE-002`.

### MN-04: `SHOW COLUMNS FROM t FROM db` 双 scope 形式未处理

**File:** `parser/flink_grammar.mbt:410-489`（`parse_flink_show`）
**Issue:** `SHOW COLUMNS (FROM|IN) table [(FROM|IN) database]` 的第二个 scope（database）未消费，会落入 trailing 001。
**Fix:** 对 COLUMNS 分支追加可选的第二个 `[FROM|IN name]`。

**Fixed:** commit `6de3f16` — `parse_flink_show` tracks the COLUMNS target and parses the optional second `[FROM|IN database]` scope. `SHOW COLUMNS FROM t FROM db` parses `valid:true` with zero diagnostics; `SHOW COLUMNS IN t` and `SHOW TABLES FROM db1 LIKE '%'` regressions still pass.

## Info

### IN-01: `parse_flink_not_implemented` 名称陈旧

**File:** `api/api.mbt:503`
**Issue:** 该入口现已跑真实 Flink grammar，函数名仍叫 `not_implemented`（docstring 已说明退役语义）。建议改名（如 `parse_flink`）并同步调用方，避免误导。

**Fixed:** commit `d0bc5d8` — renamed `parse_flink_not_implemented` → `parse_flink`; the LSP document-path caller (`lsp/handlers.mbt`) and api test calls are updated.

### IN-02: `argument_list_has_arrow` 每个函数调用 O(n) 前扫（双方言共用）

**File:** `parser/parser.mbt:714-745`
**Issue:** `parse_expression_postfix` 对**每个**函数调用的参数表先做一次 `argument_list_has_arrow` 前扫（到匹配 `)`），嵌套函数调用场景下整体 O(n²)。当前对合法 Doris 输入行为中性（仅 `= >` 深度 0 序列会改道），但属共享热路径，值得关注。

**Accepted:** no code change — recorded as accepted (pre-existing shared hot path, behavior-neutral on valid Doris input). 

### IN-03: `with_prefix_verb` 的 `if i < length` guard 失效（与 CR-04 同根）

**File:** `parser/parser.mbt:1898-1900`
**Issue:** `match stream.raw(indices[i])` 的 scrutinee 在 guard 前求值，`Some(raw) if i < length` 实际从不拦截越界。属 CR-04 的代码气味来源，修复 CR-04 时一并删除该无效 guard。

**Fixed:** commit `7dbf792` (with CR-04) — the dead `if i < length` guard is removed; the bound is enforced by the explicit `i >= length` bail and the guarded `indices.get(i)` read.

### IN-04: 全项目 native 构建链接触发 `undefined reference to main`

**Issue:** `moon build --target native`（不带 `--package`）因包含无 main 的库包而链接失败（`/usr/bin/ld: undefined reference to main`）。需按包构建（`--package fathom-sql`）。非源码缺陷，但 CI 若用全项目 native build 会误报失败。

**Accepted:** no code change — recorded as accepted (pre-existing build-configuration note; per-package build is the documented pattern).

---

## 复审关注项核对

- **Flink grammar 正确性（钉住 release）**：正例主干正确（full MATCH_RECOGNIZE/TVF/named-arg/WITH-CTE UPDATE 实证 valid）；但 `ROW<...>`（MJ-01）、`SUBSET` 位置（MJ-02）、`WITH [LOCAL] TIME ZONE`/`AT TIME ZONE`（MJ-04）与 pinned grammar/研究声明不符。
- **可恢复 CST 有界性**：**不满足** — CR-01/CR-02 栈溢出崩溃、CR-04 abort；其余 incomplete/recovery fixture 均实现有界恢复与 `print_lossless(parse(x))==x`。
- **Doris 零漂移**：**被破坏** — CR-03（`watermark` 列名回归）；其余共享改动（`precedence` 策略表、`argument_list_has_arrow`、interval/expression-prefix 门禁）对合法 Doris 输入实证无行为变化。
- **双向负门禁**：方向正确（Flink-only/Doris-only 双向 009，整句 007），但 WATERMARK/CONSTRAINT/INTERVAL 门禁过宽（CR-03/MJ-03）。
- **MATCH_RECOGNIZE 语法级**：无 planner/执行逻辑渗入；pattern 变量作用域不校验（符合 Pitfall 6）。
- **安全**：`extract_flink_grammar.py` 无注入面；解析器递归深度存在两个未封顶向量（CR-01/CR-02）。

---

_Reviewed: 2026-08-09_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
