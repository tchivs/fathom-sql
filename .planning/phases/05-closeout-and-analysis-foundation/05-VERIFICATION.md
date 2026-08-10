---
phase: 05-closeout-and-analysis-foundation
verified: 2026-08-10T12:33:14Z
status: passed
score: 13/13 must-haves verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 5: Closeout and Analysis Foundation — Verification Report

**Phase Goal:** 收尾 v1.0 两项遗留验证（人工 VS Code 宿主验证 CLOSE-01 + linear-Wasm CI 运行时执行 CLOSE-02），并把 `analyzer/` 从最小 catalog 边界（D-22）扩展为可用的 catalog 名字解析与类型诊断（ANAL-01）——Doris 表/列/函数/作用域的限定/非限定引用、别名、CTE、子查询、带 catalog 星号展开，大小写不敏感匹配遵循 Doris 语义并保留源码拼写与 span。
**Verified:** 2026-08-10T12:33:14Z
**Status:** passed
**Re-verification:** No — initial verification

## 验证结论概览

| 需求 | 结论 | 依据 |
|------|------|------|
| CLOSE-01 | ✅ **verified** | `vscode/scripts/host-verify.mjs` 真实存在并以 `@vscode/test-electron` 启动 4 个隔离 extension-host 模式；REQUIREMENTS.md CLOSE-01 行含 `[Phase 5 formalized]` + host-verify.mjs + 4 模式名；STATE.md Deferred Items ECO-07 行状态为 `closed — Phase 5 CLOSE-01 formally verified`。人工宿主验证已于 2026-08-06 完成并记录在仓库（VS Code 1.132.0，3 模式通过 + LogOutputChannel `{log:true}` bug 修复），D-07 明文不重跑。 |
| CLOSE-02 | ✅ **verified** | `.github/workflows/ci.yml` `linear-wasm-parity` job 存在且完整：`moon build --target wasm binding` + `moon build --target wasm parity` → `moon test --target wasm --package parity`（线性 Wasm 运行时执行）→ native/js 交叉核对 → `python3 scripts/compare_backends.py`（三目标字节 digest，CI 无 `--update`）；`scripts/compare_backends.py` 存在；REQUIREMENTS.md CLOSE-02 行含 `[Phase 5 formalized]` + job 名；STATE.md ci_recommendation 行为 `closed — Phase 5 CLOSE-02 formally verified`。 |
| ANAL-01 | ✅ **verified** | catalog 名字解析与类型诊断全部交付并有行为测试覆盖：`pub(open) trait Catalog`（table/table_in_db/function）、`StaticCatalog` db/函数注册表、`analyze` 端到端路径、完整 SELECT 模型、作用域栈、函数/元数、DML/CREATE VIEW 列级引用、五类诊断、case policy 文档。`moon test --target native --package analyzer --package test` **191/191 通过**；冻结 Doris parity baseline `moon test --target native --package parity` **597/597 通过**；`python3 scripts/diff_parity.py --frozen-only` **455 snapshots 0 差异**。 |

**Score:** 13/13 must-haves verified（0 present-behavior-unverified，0 gaps）

## 目标达成：可观测真相

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | CLOSE-01 证据已正式核实并记录：REQUIREMENTS.md 与 STATE.md 的 traceability 条目引用 `vscode/scripts/host-verify.mjs`（真 extension-host 4 隔离模式）与 2026-08-06 核实记录 | ✓ VERIFIED | `host-verify.mjs` 存在（4 模式 functional doris-4.x / profile doris-2.1 / flink flink-2.3.0 / fallback）；REQUIREMENTS.md:13 含 `[Phase 5 formalized]`；STATE.md:264 ECO-07 行 `closed — Phase 5 CLOSE-01 formally verified` |
| 2 | CLOSE-02 证据已正式核实并记录：traceability 引用 ci.yml `linear-wasm-parity` job 与 `scripts/compare_backends.py`（`moon test --target wasm --package parity`） | ✓ VERIFIED | ci.yml:69-122 job 完整（wasm build + wasm/native/js 三目标 parity + compare_backends.py 只读 digest）；`scripts/compare_backends.py` 存在；REQUIREMENTS.md:14 含 `[Phase 5 formalized]`；STATE.md:267 ci_recommendation 行 `closed` |
| 3 | D-05 one-way Catalog 契约一次定形：`table` + `table_in_db` + `function`；StaticCatalog 含 db_tables/functions 注册表；`resolve_table_references` 行为不变 | ✓ VERIFIED | analyzer.mbt `pub(open) trait Catalog` 三方法 + `StaticCatalog{db_tables, functions}` + with_db/with_function/lookup_in_db/lookup_function/lookup_exact；trait-dispatch helper 迁移（analyzer_test.mbt）；`git diff analyzer/moon.pkg parser/moon.pkg` 为空 |
| 4 | 端到端 tracer 打通：`analyze(node, source_bytes, catalog)` 对 `SELECT a, b FROM t` 返回 AnalysisResult，bindings 含 t(Table)、a(Column INT)、b(Column VARCHAR(10))，保留源码拼写与 start_byte/end_byte | ✓ VERIFIED | `test/analyzer_anal01_test.mbt#analyzer-anal01 select-basic doris-4.x` 断言 a@[7,8) b@[10,11) t@[17,18) + data_type；快照 `analyzer.select-basic.doris-4.x.json`；191/191 绿 |
| 5 | 未知表 `SELECT a FROM missing` 产出 code=unknown-table 的 AnalysisDiagnostic（独立通道），语法 valid 不变（ANLY-01） | ✓ VERIFIED | `analyzer-anal01 unknown-table diagnostic` 断言 code/message/span + `parsed.valid` 保持 true + 逐字段复解析相等；resolve.mbt:354-358 |
| 6 | 解析时 ASCII case-fold（D-03）：`lookup("T")` 命中 catalog "t"；quoted 标识符经 case-fold + `TableInfo.name` 字节复核精确匹配；binding 保留源码拼写 + span | ✓ VERIFIED | `analyzer_catalog_lookup_hits_and_misses`、`lookup_exact` 直测；`analyzer-anal01 quoted-exact generic`（catalog 含 "T" 命中、仅含 "t" 时 `` `T` `` → unknown-table、未加引号 t 折叠命中 "T"）；`db quoted star byte recheck`；resolve.mbt `resolve_table_with_quoted` |
| 7 | 完整 SELECT 子句切分：SELECT/FROM+JOIN/WHERE/GROUP BY/HAVING/QUALIFY/ORDER BY/LIMIT/WINDOW/UNION，括号深度感知，GROUP/ORDER 仅当后继 BY，字符串免疫 | ✓ VERIFIED | `analyzer_wbtest.mbt#wb clause_break full boundaries`、`wb clause_break group order two word`、`wb paren depth immune to strings`、`wb paren depth string literal not counted`、`wb paren depth limit returns none`；191/191 绿 |
| 8 | CTE（WITH）作用域与子查询作用域正确隔离：CTE 名可见且优先于 catalog 表，子查询退出即弹帧，同名内层优先 | ✓ VERIFIED | `analyzer-anal01 cte-scope`（c→Cte binding，体内 a→t 列）、`subquery-alias`（x.a→子查询输出列）、`correlated subquery no false ambiguous`（WR-04 block 作用域）集成测试全绿 |
| 9 | AS 别名、限定名 db.table.col（1/2/3 段）、带 catalog 的 `*`/`table.*` 星号展开正确解析 | ✓ VERIFIED | `as-alias`（投影/表别名）、`qualified-name`（`db.t.b` 经 table_in_db）、`star-expansion`（t.* 展开 a/b）、`anonymous subquery star expansion`、`order-by projection alias`（WR-06）集成测试全绿 |
| 10 | UNION 链集合运算按冻结 parser 接受面：只切 `UNION [ALL\|DISTINCT]`；EXCEPT 投影修饰符；INTERSECT 不虚构 | ✓ VERIFIED | `union-chain`（双 branch 各自解析）；`wb split union chain model`；select_parser.mbt Pitfall 2 实现 |
| 11 | 函数调用经 `Catalog::function` 解析：命中 → Function binding（return_type）；未命中 → unknown-function；实参数目不符 → function-arity | ✓ VERIFIED | `function basic`（abs→INT）、`function unknown`（nope→unknown-function）、`function arity`（concat 1 参→function-arity 且保留 Function binding）；resolve.mbt:532-560 |
| 12 | DML 列级引用（UPDATE SET/WHERE、DELETE WHERE、INSERT 列清单、MERGE SET）+ CREATE VIEW 体表引用 + 完整诊断集（unknown-table/column/function、ambiguous-reference、function-arity），独立通道（ANLY-01） | ✓ VERIFIED | `dml update columns`（t.a/t.b 绑定）、`create-view body`（体 t/a 绑定）、`ambiguous reference`（非限定 a 命中 t1/t2）、`unknown-column` 集成测试全绿；resolve.mbt 六类 code 全存在；`resolve_table_references` 行为不变（analyzer_test.mbt DML 走查断言） |
| 13 | docs/API.md §Optional Name-Resolution API 更新：analyze/AnalysisResult/Binding/FunctionInfo、Catalog 三方法、D-03 case policy、D-04 诊断范围、端点表 analyze 行；D-24「deferred to v2」表述移除 | ✓ VERIFIED | docs/API.md:276-368 含 `analyze`、`AnalysisResult`、`table_in_db`/`function`、**Case policy (D-03)** case-insensitive + quoted exact、**Type-diagnostic scope (D-04)** 五诊断 code；端点表:32 有 analyze 行；grep "deferred to v2" 为空 |

**Score:** 13/13 truths verified（0 present-behavior-unverified；0 overrides）

### 必需构件

| Artifact | Expected | Status | Details |
| -------- | ----------- | ------ | ------- |
| `analyzer/analyzer.mbt` | Catalog trait 三方法 + StaticCatalog db/functions 注册表 + case-fold + resolve_table_references | ✓ VERIFIED | `pub(open) trait Catalog` table/table_in_db/function；`StaticCatalog{db_tables,functions}` + lookup_in_db/lookup_function/lookup_exact；D-03 doc 注释更新；`target_table_name` 按段返回 quoted 标志（WR-02） |
| `analyzer/analysis.mbt` | FunctionInfo/BindingKind/Binding/AnalysisDiagnostic/AnalysisResult 公共记录（平铺 Int span） | ✓ VERIFIED | 全部 `pub(all)` + derive(Eq, Debug)；span 为 start_byte/end_byte Int，无 source import |
| `analyzer/select_model.mbt` | ClauseKind/SelectCore/SelectModel/CteDef/SelectItem/FromItem/NameRef/TokenSlice 全量模型 | ✓ VERIFIED | 全子句字段（select_list/from/joins/where_refs/group_by/having/qualify/order_by/limit/window/set_op）；NameRef 含 is_call/call_args（D-04） |
| `analyzer/select_parser.mbt` | source_tokens + 括号深度子句切分 + 限定名/别名/星号/函数调用识别 | ✓ VERIFIED | clause_kind_at 全边界；collect_refs 限定名 1..3 段 + star + call_args；GROUP/ORDER 二词；深度上限 128 bail |
| `analyzer/resolve.mbt` | analyze 入口 + 作用域栈 + catalog 查找 + binding/诊断 + DML/CREATE VIEW | ✓ VERIFIED | resolve_model/resolve_core/resolve_from_item/resolve_ref/expand_star；analyze_dml_body/analyze_create_view_body/analyze_select_tokens；六类诊断 code 全落地；Error/Missing → requires-complete-parse 不 panic |
| `analyzer/analyzer_wbtest.mbt` | analyzer 包内首个白盒测试 | ✓ VERIFIED | 9+ 用例：clause_break 边界/二词/字符串免疫/深度上限/限定名拆分/quoted 识别/case-fold |
| `test/analyzer_anal01_test.mbt` | parse→analyze 集成测试 + 快照 | ✓ VERIFIED | 16 个集成用例（select-basic/unknown-table/quoted-exact/cte-scope/subquery-alias/union-chain/as-alias/qualified-name/star-expansion/function basic/unknown/arity/unknown-column/dml/create-view/ambiguous/binary-expr/window/correlated/anon-star/order-by/db-quoted-star） |
| `test/analyzer_test.mbt` | ANLY-01 + D-05 trait-dispatch + D-03 断言 + resolve_table_references | ✓ VERIFIED | `analyzer_syntax_only_path_is_unchanged_by_catalog` 逐字段相等；trait-dispatch 三方法；lookup_exact quoted 直测；DML 走查 `["t","t4","t5"]` |
| `docs/API.md` | §Optional Name-Resolution API 更新 | ✓ VERIFIED | analyze/AnalysisResult/Binding/FunctionInfo、Catalog 三方法、case policy、D-04 诊断范围、端点表 analyze 行 |
| `vscode/scripts/host-verify.mjs` | CLOSE-01 证据脚本 | ✓ VERIFIED | 真实存在，4 隔离模式，`@vscode/test-electron` 启动 |
| `.github/workflows/ci.yml` `linear-wasm-parity` | CLOSE-02 证据 job | ✓ VERIFIED | wasm build + `moon test --target wasm --package parity` + native/js 交叉核对 + compare_backends.py |
| `scripts/compare_backends.py` | 三目标字节 digest | ✓ VERIFIED | 真实存在 |

### 关键链路验证

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| `analyze()` (resolve.mbt:1395) | Statement body 分派 | `analyze_body` 按 kind 走 Select/DML/CreateView | WIRED | Select→analyze_select_body；Insert/Update/Delete/Merge→analyze_dml_body；CreateView→analyze_create_view_body |
| analyze → catalog | `Catalog::table` / `table_in_db` / `function` | 泛型 `[T : Catalog]` case-fold 查找 + quoted 字节复核 | WIRED | resolve.mbt `resolve_table_with_quoted`/`resolve_table_name_ref`/resolve_ref 函数分支 |
| 集成测试 → 实际 parser | `@parser.parse_with_limits` + `@analyzer.analyze` | test 包导入 parser/source/dialect | WIRED | analyzer_anal01_test.mbt `analyze_sql` helper；191/191 绿 |
| 诊断 → 语法 valid 通道隔离 | AnalysisDiagnostic 独立通道 | ANLY-01 逐字段相等断言 | WIRED | analyzer_test.mbt `analyzer_syntax_only_path_is_unchanged_by_catalog` |
| CLOSE-01 记录 → 仓库证据 | REQUIREMENTS.md/STATE.md traceability | host-verify.mjs + 2026-08-06 记录行 | WIRED | 引用路径与文件内容精确对应，无虚构 |
| CLOSE-02 记录 → 仓库证据 | REQUIREMENTS.md/STATE.md traceability | ci.yml linear-wasm-parity job + compare_backends.py | WIRED | 引用路径与 job 实际步骤精确对应 |

### 数据流追踪（Level 4）

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| `analyze()` bindings | Binding.name/data_type/resolved_to | caller-injected StaticCatalog（TableInfo/ColumnInfo/FunctionInfo）+ 源码 token | ✓ 真实 catalog 数据流入 binding | ✓ FLOWING |
| `unknown-table` 诊断 | message/span | resolve 层未命中路径 + 源码 token span | ✓ 真实 span（如 missing@[7,15)） | ✓ FLOWING |
| `resolve_table_references` | target table 名 | catalog 查找（1 段 table / 2+ 段 table_in_db，WR-02） | ✓ 真实查询结果 | ✓ FLOWING |

### 行为抽查（本次实际运行）

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| analyzer + test 包全量（ANAL-01 全部集成/白盒/ANLY-01） | `moon test --target native --package analyzer --package test` | **Total tests: 191, passed: 191, failed: 0** | ✓ PASS |
| 冻结 Doris parity baseline（D-08 门禁） | `moon test --target native --package parity` | **Total tests: 597, passed: 597, failed: 0** | ✓ PASS |
| 冻结 baseline 快照零漂移（CI parity-gate 同款） | `python3 scripts/diff_parity.py --frozen-only` | **ok: 455 snapshots, 0 frozen-vs-current differences**（exit 0） | ✓ PASS |
| D-21 负门禁（analyzer/parser moon.pkg 未改） | `git diff --quiet analyzer/moon.pkg parser/moon.pkg` | 两者均 CLEAN | ✓ PASS |

### 探针执行

未发现本阶段声明或约定的 `scripts/*/tests/probe-*.sh` 探针。CLOSE-01（host-verify.mjs）与 CLOSE-02（linear-wasm-parity）按 D-07 明文不重跑，其证据在仓库内核实（见上）。**Step 7c: SKIPPED（无探针声明）**。

### 需求覆盖

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| CLOSE-01 | 05-01 | VS Code 扩展宿主验证证据正式核实并记录 | ✓ SATISFIED | REQUIREMENTS.md/STATE.md traceability + host-verify.mjs 在仓库；2026-08-06 记录行一致 |
| CLOSE-02 | 05-01 | linear-Wasm CI 运行时执行证据正式核实并记录 | ✓ SATISFIED | ci.yml linear-wasm-parity job + compare_backends.py 在仓库；STATE.md ci_recommendation closed |
| ANAL-01 | 05-02/03/04 | catalog 支撑的表/列/函数/作用域名字解析与类型诊断 + case-insensitive + span 保留 | ✓ SATISFIED | analyzer 全量实现 + 191/191 行为测试 + 快照；docs/API.md 同步 |

无孤儿需求：REQUIREMENTS.md 将 CLOSE-01/CLOSE-02/ANAL-01 全部映射到 Phase 5，且三个 ID 均被 05-01..05-04 计划认领。

### 反模式扫描

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| analyzer/*.mbt, test/analyzer_anal01_test.mbt, test/analyzer_test.mbt | — | TBD/FIXME/XXX/HACK/PLACEHOLDER | ℹ️ 无 | 零命中 |
| 生产代码（resolve.mbt/select_parser.mbt/select_model.mbt/analysis.mbt/analyzer.mbt） | — | `panic()` | ℹ️ 无 | 生产路径零 panic；`panic()` 仅出现在白盒测试断言（analyzer_wbtest.mbt） |
| `SelectCore.join/depth/set_op`、`FromItem.join/depth` | — | 结构字段当前未被 resolve 读取 | ℹ️ Info | 计划内结构字段（供 Lint/血缘消费），非功能 stub，不阻塞 ANAL-01；已在 05-03 SUMMARY Known Stubs 记录 |
| JOIN `ON`/`USING` 条件列解析 | — | 消费但未做名字解析 | ℹ️ Info | 计划验收范围外（05-04 明确顺延），歧义诊断仍由 SELECT 列表非限定列触发并已验证 |

无 BLOCKER/WARNING 级反模式。无未引用债务标记（TBD/FIXME/XXX 均为零）。

### 人工验证项

本阶段无**待决**（open）人工验证项；自动化检查全部通过。

- **CLOSE-01（已记录人工验证，无需再跑）**：VS Code 真 extension-host 验证本质上是人工/宿主验证项（需要一台装有 VS Code 的机器），但该验证已于 **2026-08-06** 完成并记录在仓库：`vscode/scripts/host-verify.mjs` 以 `@vscode/test-electron` 启动真实 extension host，3 模式通过（diagnostics/format/completion/4.x-merge、2.1 MERGE profile 传播、unavailable-server fallback），并修复客户端 `LogOutputChannel {log:true}` 需求 bug；后续 Phase 13 增加 flink 模式，脚本现为 4 隔离模式。Phase 5 的交付物是**正式核实并记录**这份证据（D-07 明文不重跑），该交付物已程序化核实（REQUIREMENTS.md/STATE.md traceability 与仓库证据精确对应）。**无需进一步人工操作。**

### 差距总结

**无差距。** 13/13 must-haves 全部 VERIFIED：
- CLOSE-01/CLOSE-02：D-07 record-only closeout 证据在仓库内正式化，引用路径与既有 2026-08-06 记录一致，无虚构、无重跑声明。
- ANAL-01：catalog 契约、end-to-end analyze、完整 SELECT 模型、作用域栈、函数/元数、DML/CREATE VIEW、完整诊断集、case policy 全部交付，并由 191 个行为测试 + 12 个快照 golden 锁定；D-21（analyzer 仅 import syntax）、ANLY-01（诊断独立通道）、冻结 Doris parity baseline（597/597 + 0 diff）全部保持绿色。

---

_Verified: 2026-08-10T12:33:14Z_
_Verifier: Claude (gsd-verifier)_
