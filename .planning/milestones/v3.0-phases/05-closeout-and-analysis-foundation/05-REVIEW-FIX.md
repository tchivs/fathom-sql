---
phase: 05-closeout-and-analysis-foundation
fixed_at: 2026-08-10T12:21:55Z
review_path: .planning/phases/05-closeout-and-analysis-foundation/05-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 5: Code Review Fix Report

**Fixed at:** 2026-08-10T12:21:55Z
**Source review:** `.planning/phases/05-closeout-and-analysis-foundation/05-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (1 CRITICAL + 6 WARNING)
- Fixed: 7
- Skipped: 0
- Verification: `moon test --target native --package analyzer --package test` → 191 passed, 0 failed

All fixes run inside the main checkout (`workflow.use_worktrees: false`), committed atomically per logical group. D-21 is preserved: the analyzer package still imports only `fathom/sql/syntax`; no parser/token/lexer/api/source imports were added and `parser/moon.pkg`/`syntax/syntax.mbt`/`parser/parser.mbt` were not touched. All spans remain flattened `start_byte`/`end_byte` Ints.

## Fixed Issues

### CR-01: `build_select_item` 尾随裸别名启发式把二元表达式右操作数误判为别名

**Files modified:** `analyzer/select_parser.mbt`
**Commit:** `240becb`
**Applied fix:** 新增 `is_infix_operator`/`has_top_level_operator`：仅当「去掉候选别名后的前缀」无 paren-depth-0 中缀运算符时才应用尾随裸别名。`SELECT price * qty` / `a + b` / `a >= b` 不再把右操作数当作别名，`price` 与 `qty` 都产出 Column binding 且无伪造 Alias；`count(*) x`、`(a + b) c` 等括号内运算符仍捕获隐式别名。

### WR-01: `expand_star` 的 db 限定 `db.t.*` 缺少 D-03 quoted 字节复核

**Files modified:** `analyzer/resolve.mbt`
**Commit:** `2c6baba`
**Applied fix:** `expand_star` n>=2 分支对 quoted 尾段表名做 `TableInfo.name` 字节复核（与 `resolve_table_name_ref` 一致）：`db.\`T\`.*` 对仅含 `db.t` 的 catalog 产出 `unknown-table`，`db.t.*` 正常展开。

### WR-02: `resolve_table_references` 对带引号 / db 限定目标表永不解析

**Files modified:** `analyzer/analyzer.mbt`
**Commit:** `a38814e`
**Applied fix:** `target_table_name` 改为按段返回 `(String, Bool)`（`identifier_text` 剥引号 + quoted 标志）；`resolve_table_references` 按段数分派：1 段 → `Catalog::table`，2+ 段 → 末两段 `Catalog::table_in_db`，quoted 尾段做字节复核。`INSERT INTO \`t\``、`INSERT INTO db.t` 均解析。

### WR-03: 窗口函数 `OVER (PARTITION BY ... ORDER BY ...)` 产生伪 `unknown-column` 诊断

**Files modified:** `analyzer/select_parser.mbt`
**Commit:** `240becb`
**Applied fix:** `collect_refs` 遇到 `OVER` 后整体跳过窗口规范（`OVER (...)` 用 `matching_paren_slices` 匹配括号；命名窗口 `OVER w` 跳过 `w`）。窗口体关键字与列不再进入名字解析。

### WR-04: 相关子查询未限定列跨块扁平化，导致伪 `ambiguous-reference` 误报

**Files modified:** `analyzer/resolve.mbt`
**Commit:** `2c6baba`
**Applied fix:** `ScopeEntry` 增加 `block` 字段（该 core 进入时 `outer.length()`）；`resolve_core`/`resolve_model`/`resolve_from_item`/`resolve_select_item`/`resolve_ref`/`resolve_token_refs` 线程化 block。未限定列先只搜当前块（歧义仅本块内判定），miss 再按外层块由内向外回退，每块恰好 1 命中才解析。

### WR-05: `SELECT * FROM (subquery)`（匿名子查询）星号不展开

**Files modified:** `analyzer/resolve.mbt`
**Commit:** `2c6baba`
**Applied fix:** `expand_star` 裸 `*` 分支移除 `entry.key != ""` 守卫，匿名子查询（key 为空）参与裸 `*` 展开；限定名/别名查找仍跳过空 key。

### WR-06: `ORDER BY`/`HAVING` 引用 SELECT 列表别名的常见模式产生伪 `unknown-column`

**Files modified:** `analyzer/resolve.mbt`, `analyzer/select_parser.mbt`
**Commit:** `2c6baba` (resolve), `ac67a44` (FROM clause-boundary)
**Applied fix:** 投影别名以 `ScopeKind::Alias` 条目在 SELECT 列表整体解析后推入 scope，对 ORDER BY/HAVING/QUALIFY/GROUP BY 可见；`resolve_ref` 未限定列先做别名优先（shadow 真实表列）。另修复顺带暴露的预存 bug：`FROM t ORDER BY a` 不再把 `ORDER` 误当表别名（`is_from_clause_boundary` 识别 GROUP/ORDER+BY 边界）。

## Tests Added

- `analyzer/analyzer_wbtest.mbt`: `wb build_select_item binary expr no bare alias`, `wb build_select_item bare alias still works`, `wb collect_refs over window skip`, `wb from order by not table alias`.
- `test/analyzer_anal01_test.mbt`: `analyzer-anal01 binary expr no fabricated alias`, `... window over partition no false unknown`, `... correlated subquery no false ambiguous`, `... anonymous subquery star expansion`, `... order-by projection alias`, `... db quoted star byte recheck`.
- `test/analyzer_test.mbt`: `doris_analyzer_resolve_quoted_and_db_qualified_targets`.
- New snapshots: `test/__snapshot__/analyzer.binary-expr-no-alias.doris-4.x.json`, `test/__snapshot__/analyzer.order-by-proj-alias.doris-4.x.json`.

## Verification

`moon test --target native --package analyzer --package test` → **191 passed, 0 failed** (ran in the main checkout after the fixes; pre-existing warnings only). 05-REVIEW.md updated: `status: resolved`, CR-01 and WR-01..WR-06 marked `[RESOLVED]` with per-finding resolution notes.

## Skipped Issues

None — all in-scope (BLOCKER + WARNING) findings were fixed. INFO findings (IN-01..IN-07) were left unchanged per assignment scope.

---

_Fixed: 2026-08-10T12:21:55Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
