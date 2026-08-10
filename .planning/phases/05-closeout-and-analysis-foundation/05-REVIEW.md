---
phase: 05-closeout-and-analysis-foundation
reviewed: 2026-08-10T00:00:00Z
depth: deep
files_reviewed: 9
files_reviewed_list:
  - analyzer/analyzer.mbt
  - analyzer/analysis.mbt
  - analyzer/select_model.mbt
  - analyzer/select_parser.mbt
  - analyzer/resolve.mbt
  - analyzer/analyzer_wbtest.mbt
  - test/analyzer_test.mbt
  - test/analyzer_anal01_test.mbt
  - docs/API.md
findings:
  critical: 1
  warning: 6
  info: 7
  total: 14
status: resolved
fix_summary:
  critical_fixed: 1
  warning_fixed: 6
  info_fixed: 0
  note: "CR-01 and WR-01..WR-06 fixed by gsd-code-fixer (Phase5CodeFix); INFO items left for a later phase. See 05-REVIEW-FIX.md."
---

# Phase 5: Code Review Report

**Reviewed:** 2026-08-10
**Depth:** deep
**Files Reviewed:** 9
**Status:** issues_found

## Summary

本次评审针对 Phase 5「Closeout and Analysis Foundation」的 analyzer 源码变更（`analyzer/` 五个实现文件 + 白盒测试 + `test/` 两个集成测试 + `docs/API.md`），以 deep 深度交叉核对 `parser.mbt` 的 CST 构造（`segment_children_for_events`）、`syntax.mbt` 只读视图、`analyzer/moon.pkg` 的 D-21 负门禁，以及 05-01~05-04 计划中的验收承诺。

**已确认达成的关键契约：**
- **D-21 边界成立**：`analyzer/moon.pkg` 仅 import `fathom/sql/syntax`；全包代码（含 `analyzer_wbtest.mbt`）无 `@source`/`@parser`/`@lexer`/`@api` 依赖（仅注释提及）；`parser/moon.pkg` 未反向依赖 analyzer。span 全部平铺为 `start_byte`/`end_byte` Int，无 `@source.Span` import。
- **ANLY-01 成立**：analyzer 诊断走独立 `AnalysisDiagnostic` 通道；`test/analyzer_test.mbt` 的字节一致性断言（同 bytes 带/不带 catalog parse 逐字段相等）覆盖。
- **quoted 精确匹配主路径成立**：泛型 resolve 路径只经 `Catalog::table`/`table_in_db`（case-fold）+ `TableInfo.name` 字节复核；`StaticCatalog::lookup_exact` 仅定义/直测，非 trait 方法，未进入泛型路径。
- **括号深度/字符串免疫**：`clause_kind_at`/`source_tokens` 只对整 token 字节判定，`'FROM'`/`'('` 等字符串不触发边界或失衡，白盒测试覆盖。

**主要问题集中区：** 扁平 token 二次解析的启发式（尾随裸别名误判、窗口函数关键字误收集）、匿名子查询 `*` 展开缺口、db 限定/带引号目标表在 `resolve_table_references` 中的解析失败、以及作用域扁平化导致的相关子查询歧义误报。其中 1 项为 BLOCKER（常见算术表达式产生错误绑定），6 项 WARNING，7 项 INFO。

> 说明：评审期间 `_bash` 持久 shell 持续挂起（环境问题，05-04-SUMMARY 亦记录），无法独立重跑 `moon test`；测试结论以 `05-04-SUMMARY.md` 记录的「180/180 通过」与代码静态核对为准。以下发现均为直接读码 + 逐路径 trace 所得。

## Critical Issues

### CR-01: `build_select_item` 尾随裸别名启发式把二元表达式右操作数误判为别名 **[RESOLVED]**

**File:** `analyzer/select_parser.mbt:300-310`
**Issue:** 尾随裸别名判断只看「最后 token 是标识符且前一个 token 不是 `.`」，未排除运算符结尾的表达式。对常见 SQL `SELECT price * qty FROM orders` / `SELECT a + b FROM t` / `SELECT a >= b FROM t`，token 流 `[price, *, qty]` 会把 `qty` 误判为 AS 别名，`body_tokens` 被截成 `[price, *]`。后果：
1. `qty` 作为列引用被丢弃，不再产生 Column binding（即使 `qty` 是表列）；
2. 产生一个伪造的 `Alias(qty)` binding（`resolved_to` 取 `price` 的列名）；
3. `SELECT a + b FROM t` 中 `b` 若恰非表列，本应报 `unknown-column` 却被静默当作别名"解析"。

该启发式无法区分 `a b`（隐式别名）与 `a + b`（二元表达式），是扁平 token 二次解析的固有歧义，但当前实现无任何运算符排除，命中非常常见的模式。05-03 计划承诺「AS 别名捕获」与「每个 binding 保留源码拼写」，此行为直接违背名字解析正确性。

**Fix:** 仅当「去掉候选别名后」的 body 是合法点分限定名（奇数位标识符、偶数位 `.`）时才应用尾随裸别名。示例：

```moonbit
/// tokens 是否为点分标识符（偶数位为 `.`，奇数位为标识符）。
fn is_dotted_name(tokens : Array[TokenSlice]) -> Bool {
  if tokens.length() == 0 { return false }
  for i in 0..<tokens.length() {
    if i % 2 == 0 {
      if !is_identifier_token(tokens[i].bytes) { return false }
    } else if tokens[i].bytes != b"." {
      return false
    }
  }
  true
}

// 在 build_select_item 中：
if as_index < 0 && body_tokens.length() >= 2 {
  let last = body_tokens[body_tokens.length() - 1]
  if is_identifier_token(last.bytes) && last.bytes != b"*" &&
    is_dotted_name(/* body_tokens[0 ..< len-1] 的切片 */) {
    // 仅此时才把 last 当作隐式别名
  }
}
```

建议同时补集成用例：`SELECT price * qty FROM orders`（两列均为表列）应产出两个 Column binding 且无 Alias。

**Resolution (05-REVIEW-FIX):** 尾随裸别名仅在「去掉候选别名后的前缀」无 paren-depth-0 中缀运算符时才应用（`has_top_level_operator`，运算符含 `* + - / %`、比较符、`AND/OR/LIKE/IN/IS/BETWEEN`）。`SELECT price * qty` / `a + b` / `a >= b` 不再把右操作数当作别名；`count(*) x`、`(a + b) c` 等括号内运算符仍正常捕获隐式别名。集成用例 `analyzer-anal01 binary expr no fabricated alias doris-4.x` 断言两个 Column binding 且无 Alias binding。

## Warnings

### WR-01: `expand_star` 的 db 限定 `db.t.*` 缺少 D-03 quoted 字节复核 **[RESOLVED]**

**File:** `analyzer/resolve.mbt:421-434`
**Issue:** 单段限定 `t.*`（n==1）走 `resolve_table_with_quoted`，对 quoted 表名做了 `TableInfo.name` 字节复核（D-03）；但 n>=2 的 `db.\`T\`.*` 直接 `Catalog::table_in_db(catalog, db_text, table_text)`，未校验 `table_quoted && info.name != table_text`。因此 `SELECT db.\`T\`.* FROM db.t`（catalog 仅有 `db.t`）会被静默解析成功，与 `resolve_table_name_ref`（第 200-202 行）和 `resolve_ref` n>=3 分支（第 660-661 行）的 quoted 语义不一致，违反 D-03 精确匹配契约。

**Fix:** 在 `expand_star` n>=2 分支补上与 `resolve_table_name_ref` 相同的复核：

```moonbit
Some(info) => {
  let table_quoted = is_quoted(ref.parts[1].bytes)
  if table_quoted && info.name != table_text {
    diagnostics.push({ code: "unknown-table", message: "table not found in catalog: \{db_text}.\{table_text}", start_byte: ref.start_byte, end_byte: ref.end_byte })
  } else {
    emit_star_columns(/* ... */)
  }
}
```

**Resolution (05-REVIEW-FIX):** `expand_star` n>=2 分支已补上与 `resolve_table_name_ref` 相同的 quoted 字节复核；`db.\`T\`.*` 对仅含 `db.t` 的 catalog 会产出 `unknown-table`，`db.t.*` 正常展开。集成用例 `analyzer-anal01 db quoted star byte recheck doris-4.x` 覆盖正反两例。

### WR-02: `resolve_table_references` 对带引号 / db 限定目标表永不解析 **[RESOLVED]**

**File:** `analyzer/analyzer.mbt:357-371, 400-404`
**Issue:** `target_table_name` 直接用 `utf8_to_string(name)` 返回原始 token 字节，未走 `identifier_text` 剥引号；且 2+ 段限定名拼成 `db.t` 后只调 `Catalog::table(catalog, name)`，从不走 `Catalog::table_in_db`。后果：`INSERT INTO \`t\` VALUES (1)`（quoted）与 `INSERT INTO db.t VALUES (1)`（db 限定）在 `resolve_table_references` 下永不命中，即使 catalog 存在。这与同阶段 `analyze`/`resolve_dml_target` 路径（经 `resolve_table_name_ref` 正确处理 quoted + table_in_db）行为不一致，且违背 D-03/D-05 承诺的「DML/DDL 目标表解析」。

**Fix:** `target_table_name` 对每个段用 `identifier_text` 剥引号；`resolve_table_references` 对 2+ 段走 `Catalog::table_in_db`：

```moonbit
// target_table_name 内：
let mut name = utf8_to_string(tokens[position])  // 或 identifier_text(tokens[position])
// resolve_table_references 内：按段数分派
match name.split(".") { /* 1 段 → Catalog::table；2+ 段 → 末两段 table_in_db */ }
```

**Resolution (05-REVIEW-FIX):** `target_table_name` 现对每段用 `identifier_text` 剥引号并返回 `(String, Bool)` 段列表（含 quoted 标志）；`resolve_table_references` 按段数分派：1 段 → `Catalog::table`，2+ 段 → 末两段 `Catalog::table_in_db`，quoted 尾段做 D-03 字节复核。`INSERT INTO \`t\`` 与 `INSERT INTO db.t` 均解析；quoted `\`T\`` 对仅含 `t` 的 catalog 不命中。用例 `doris_analyzer_resolve_quoted_and_db_qualified_targets` 覆盖。

### WR-03: 窗口函数 `OVER (PARTITION BY ... ORDER BY ...)` 产生伪 `unknown-column` 诊断 **[RESOLVED]**

**File:** `analyzer/select_parser.mbt:60-100`
**Issue:** `is_reserved_word` 未包含窗口规范关键字（`PARTITION`，且 `ORDER` 因 Pitfall 2 被有意排除）。`collect_refs` 对 `SUM(x) OVER (PARTITION BY y ORDER BY z)` 会收集 `PARTITION`、`ORDER` 为标识符引用（`OVER` 本身在保留集内被跳过，但其后的窗口体暴露）。随后 `resolve_ref` 在可见表有列时对它们报 `unknown-column`。这是非常常见的窗口查询模式，会产生大量伪诊断，损害 analyzer 的可信度。

**Fix:** 在 `collect_refs` 中遇到 `OVER` 后跳过整个窗口规范（`(` 到匹配 `)`），或把 `PARTITION`（连同 `ROWS`/`RANGE`/`PRECEDING`/`FOLLOWING` 等窗口关键字）加入 `is_reserved_word`：

```moonbit
// collect_refs 主循环中，处理 `(` 之前先识别 OVER 窗口：
if bytes_equal_ci(bytes, b"OVER") && i + 1 < length && tokens[i + 1].bytes == b"(" {
  let close = matching_paren(tokens, i + 1)
  i = (if close < length { close + 1 } else { length })
  continue
}
```

**Resolution (05-REVIEW-FIX):** `collect_refs` 遇到 `OVER` 后整体跳过窗口规范（`OVER (...)` 用 `matching_paren_slices` 匹配括号；命名窗口 `OVER w` 直接跳过 `w`）。`SUM(x) OVER (PARTITION BY y ORDER BY z)` 不再收集 `PARTITION/y/ORDER/z`。白盒用例 `wb collect_refs over window skip` 与集成用例 `analyzer-anal01 window over partition no false unknown doris-4.x` 覆盖。

### WR-04: 相关子查询未限定列跨块扁平化，导致伪 `ambiguous-reference` 误报 **[RESOLVED]**

**File:** `analyzer/resolve.mbt:543-580, 800-850`
**Issue:** `resolve_model` 对子查询用 `outer.copy()` 作为基座（为支持相关列），但 `resolve_ref` 的未限定列搜索把外层条目与内层条目同等对待并做歧义计数。`SELECT a FROM t1, (SELECT a FROM t2) x`（t1、t2 都有列 `a`）时，内层 `SELECT a` 会同时命中 t2.a 与 t1.a → 误报 `ambiguous-reference`。SQL 语义中内层块只先解析自己的 FROM，未命中才回退外层相关列。计划 05-03 承诺「外层同名表不被穿透」，当前实现仅在列名不重叠时成立。

**Fix:** 为查询块标记作用域边界（`ScopeEntry` 增加 `block` 序号或在内层搜索时先限定到内块条目），未限定列先只搜当前块，miss 再回退外层；歧义判定也只在同一块内做。

**Resolution (05-REVIEW-FIX):** `ScopeEntry` 增加 `block` 字段（取该 core 进入时 `outer.length()`）。`resolve_core`/`resolve_model`/`resolve_from_item`/`resolve_select_item` 线程化 block。`resolve_ref` 未限定列搜索顺序：当前块（block == current）→ 命中则解析/歧义只在本块内判定；miss 则按外层块由内向外回退（每块恰好 1 命中才解析，>1 报歧义）。相关子查询 `SELECT a FROM t2` 在内层先命中 `t2.a`，不再与 `t1.a` 冲突。用例 `analyzer-anal01 correlated subquery no false ambiguous doris-4.x` 覆盖。

### WR-05: `SELECT * FROM (subquery)`（匿名子查询）星号不展开 **[RESOLVED]**

**File:** `analyzer/resolve.mbt:388-391`
**Issue:** `expand_star` 的裸 `*` 分支跳过 `entry.key == ""` 的条目，而匿名子查询（`FROM (SELECT ...)` 无别名）恰好以空 key 入栈（第 250-256 行）。因此 `SELECT * FROM (SELECT a FROM t)` 的 `*` 不产生任何列绑定，投影列信息丢失（命名子查询 `(...) x` 则正常展开）。`key != ""` 的守卫本意是「跳过匿名条目以支持限定名查找」（见 find_scope_entry 注释），但误伤了裸 `*` 展开。

**Fix:** 裸 `*` 展开应包含匿名子查询条目；仅「限定名/别名查找」跳过空 key：

```moonbit
None => {
  for entry in scope {
    // 匿名子查询（key==""）也参与裸 * 展开
    emit_star_columns(entry, star_start, star_end, bindings, out)
  }
}
```

**Resolution (05-REVIEW-FIX):** `expand_star` 裸 `*` 分支移除 `entry.key != ""` 守卫，匿名子查询（key 为空、kind=Subquery）参与裸 `*` 展开；限定名/别名查找仍跳过空 key。用例 `analyzer-anal01 anonymous subquery star expansion doris-4.x` 覆盖。

（若担心空 scope 条目，可用 `is_subquery`/kind 判断而不用 key 判空。）

### WR-06: `ORDER BY`/`HAVING` 引用 SELECT 列表别名的常见模式产生伪 `unknown-column` **[RESOLVED]**

**File:** `analyzer/resolve.mbt:746-760, 800-850`
**Issue:** `resolve_core` 按 FROM → SELECT 列表 → WHERE → GROUP BY → HAVING → QUALIFY → ORDER BY 顺序解析，SELECT 列表别名只写入 `bindings`，从不进入作用域。`SELECT a AS x FROM t ORDER BY x` 中 `ORDER BY x` 的 `x` 在任意表列中未命中且作用域有可见列 → 误报 `unknown-column`。Doris/SQL 标准允许 ORDER BY（及部分 HAVING）引用投影别名，这是高频写法。

**Fix:** 将 SELECT 列表别名以 `ScopeKind::Alias` 条目推入作用域（在解析 FROM 之后、解析 ORDER BY 等后续子句之前），使别名对 ORDER BY/HAVING/QUALIFY 可见；别名解析顺序在真实表列之前。

**Resolution (05-REVIEW-FIX):** `resolve_select_item` 将投影别名以 `ScopeKind::Alias` 作用域条目收集到 `alias_entries`；`resolve_core` 在整个 SELECT 列表解析完后统一推入 scope（避免 select 项互相看见别名），再解析 WHERE/GROUP BY/HAVING/QUALIFY/ORDER BY。`resolve_ref` 未限定列搜索先做别名优先（innermost alias 命中即解析，shadow 真实表列）。顺带修复了 `FROM t ORDER BY a` 把 `ORDER` 误当表别名的预存 bug（`is_from_clause_boundary` 识别 GROUP/ORDER+BY 边界）。用例 `analyzer-anal01 order-by projection alias doris-4.x` 与白盒 `wb from order by not table alias` 覆盖。

## Info

### IN-01: `ScopeEntry.is_quoted` 字段从未被读取（死字段）

**File:** `analyzer/resolve.mbt:40`
**Issue:** `is_quoted` 在多处被写入（245/255/321/336/409/431/848/1042 行），但 `find_scope_entry`/`find_scope_entry_kind` 只用调用方传入的 `quoted` 标志与 `entry.key` 匹配，从不读取条目的 `is_quoted`。该字段无任何行为影响，属于死字段，且暗示「quoted 别名应精确匹配」的意图未真正落地（`FROM t AS "Y"` 后 unquoted `Y` 仍可 case-fold 命中）。
**Fix:** 删除字段，或让 `find_scope_entry` 在匹配时同时参考条目 `is_quoted`（quoted 别名/表名只允许精确匹配）。

### IN-02: `resolve_ref` n>=3 分支对 n>3 静默忽略多余段，且与 `resolve_table_name_ref` 的 last-two 语义不一致

**File:** `analyzer/resolve.mbt:651-687`
**Issue:** 4 段引用（如 `catalog.db.t.col`）在 `resolve_ref` 中取 `parts[0]/parts[1]` 作 db.table、`parts[2]` 作列，忽略 `parts[3]`；而 `resolve_table_name_ref`（第 196-197 行）对表引用取「末两段」作 db.table。两者对 4 段名字的解析不一致，且 4 段列引用超出两级模型时静默 `return None`（无诊断）。
**Fix:** 明确 n>3 的处理策略（支持末三段 `db.table.col`，或对超界段数产出 `requires-complete-parse`/`unsupported` 诊断而非静默忽略）。

### IN-03: 2 段函数调用 `db.f(x)` 未处理，静默返回 None

**File:** `analyzer/resolve.mbt:496-536`
**Issue:** `is_call` 分支仅处理 `parts.length() == 1`，db 限定函数调用 `db.f(x)` 直接 `return None`，既无 Function binding 也无诊断。Doris 支持 db 限定的函数。
**Fix:** 对 2 段调用按 `Catalog::function` 解析第二段（或按 catalog 的 db 作用域函数扩展），未命中时报 `unknown-function`。

### IN-04: `join_strings`/`split_comma` 往返会错分含逗号的 quoted CTE 列名

**File:** `analyzer/select_parser.mbt: parse_cte_prefix`（`(c1, c2)` 捕获）；`analyzer/resolve.mbt:765-790`（`apply_cte_aliases`/`split_comma`）
**Issue:** CTE 列名别名表先 `join_strings(parts, ",")` 再 `split_comma(list)` 往返；若某列是 quoted 标识符且内含逗号（如 `` WITH c(`a,b`) AS ... ``），往返会把一个列名错分成两个。
**Fix:** 用结构化 `Array[String]` 直接传递列名列表，避免字符串往返。

### IN-05: `utf8_to_string` 未校验 UTF-8 连续字节

**File:** `analyzer/analyzer.mbt:111-145`
**Issue:** 2/3/4 字节分支只检查首字节范围与剩余长度，不校验后续字节是否为 0x80-0xBF 连续字节。畸形 UTF-8 标识符会解出垃圾字符（不崩溃）。鉴于 D-21 禁止引入 `@encoding/utf8` 而自实现，属可接受的稳健性妥协。
**Fix:** 对每个分支增加连续字节校验，非法即落入 `0xFFFD`。

### IN-06: JOIN `ON`/`USING` 条件不参与名字解析

**File:** `analyzer/select_parser.mbt: parse_from`（ON/USING 消费段）
**Issue:** `SELECT a FROM t1 JOIN t2 ON t1.id = t2.id` 中 `t1.id`/`t2.id` 不产生 binding。此行为已在 `05-04-SUMMARY.md`「Known Stubs / Intentional Gaps」中明确记录为计划外（D-02 JOIN 条件列解析顺延），故列为 INFO 供后续阶段跟踪，而非缺陷。
**Fix:** 后续计划将 ON/USING 条件并入 `collect_refs`/`resolve_token_refs`。

### IN-07: 无别名且多引用表达式不产出 output 列，影响子查询列派生

**File:** `analyzer/resolve.mbt:746-753`
**Issue:** `resolve_select_item` 的 `None` 分支仅当 `resolved_refs.length() == 1 && item.refs.length() == 1` 才向 output 推列。`SELECT a + b FROM t`（修复 CR-01 后）无别名、多 ref → 不产出 output 列，导致以它为体的子查询/CTE 列派生为空（`SELECT * FROM (SELECT a + b FROM t) x` 中 `x` 无列）。
**Fix:** 对无别名表达式为 output 生成占位列（如以表达式首 token 文本或空名 + 推导类型），或至少在文档中记录该限制。

---

_Reviewed: 2026-08-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
