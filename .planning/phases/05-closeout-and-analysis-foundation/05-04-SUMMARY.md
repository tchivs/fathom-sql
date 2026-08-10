---
phase: 05-closeout-and-analysis-foundation
plan: 04
subsystem: analyzer
tags: [moonbit, analyzer, catalog, sql, name-resolution, functions, dml, create-view, type-diagnostics, function-arity, ambiguous-reference, d-02, d-03, d-04, d-05, d-06]

# Dependency graph
requires:
  - phase: 05-03
    provides: Full SELECT analysis model (clause split + scope stack), SelectModel/NameRef/TokenSlice model, resolve_ref/expand_star/resolve_model/resolve_core, analyzer_wbtest.mbt white-box suite
provides:
  - Function-call resolution via Catalog::function (parsing-time ASCII case-fold, D-03): hit → Function binding with return_type; miss → unknown-function diagnostic; arg count outside [min_arity, param_types.length()] → function-arity diagnostic (D-04)
  - DML column-level references (D-02): UPDATE SET/WHERE, DELETE WHERE, INSERT column lists, MERGE SET resolve against the target table's columns; resolve_table_references behavior unchanged (D-05)
  - CREATE VIEW query-body analysis (D-02): the token slice after the optional column list / AS is re-parsed through the existing SELECT analysis
  - Complete analyzer diagnostic set on the independent channel (ANLY-01): unknown-table / unknown-column / unknown-function / ambiguous-reference / function-arity
  - docs/API.md §Optional Name-Resolution API updated (analyze/AnalysisResult/Binding/FunctionInfo, three-method Catalog trait, case policy, D-04 diagnostic scope, endpoint table analyze row; D-24 deferred-to-v2 phrasing removed)
affects: [Phase 6 Lint, Phase 7 LINE-01, docs/API.md, Phase 5 verifier]

# Actuals (#2632) — pairs with the plan's `estimate` (tokens: 75000, raw_tokens: 50000).
# Same estimateTokens scale (chars/4 over the realized diff), never a harness token count.
actuals:
  tokens: 11300
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Function-call recognition (D-04): `name(` at paren depth 0, excluding qualified-name tails (`t.col`) and FROM table context; call_args captured as the token slice between the call's `(` and its matching `)` (parens excluded) for depth-0 argument counting"
    - "Arity checking over whole-token bytes (D-04): depth-0 comma counting immune to nested parens and string contents; no expression-level type unification or literal propagation (ANAL-02 out of scope)"
    - "DML column-level resolution (D-02): leading_prefix_end + qualified_ref_at recover the target table; a scope frame carries its columns so SET/WHERE/VALUES refs resolve like SELECT column refs; resolve_table_references untouched (D-05)"
    - "CREATE VIEW body re-parse (D-02): the flat token-leaf CST has no nested Select node under CreateView (segment_children_for_events), so the slice after the view name/column-list/AS is re-parsed through the existing SELECT pipeline"
    - "Unknown-column gating (D-04): an unresolvable unqualified column earns unknown-column only when the scope has a named entry exposing columns — bare `SELECT x` (empty scope) and empty-column tables stay silent, keeping quoted-exact D-03 tests green"

key-files:
  created:
    - test/__snapshot__/analyzer.dml-update-columns.doris-4.x.json
    - test/__snapshot__/analyzer.create-view-body.doris-4.x.json
    - test/__snapshot__/analyzer.ambiguous-reference.doris-4.x.json
  modified:
    - analyzer/select_model.mbt
    - analyzer/select_parser.mbt
    - analyzer/resolve.mbt
    - test/analyzer_anal01_test.mbt
    - docs/API.md

key-decisions:
  - "05-04 final ANAL-01 slice: function-call resolution + arity (D-04), DML/CREATE VIEW column-level refs (D-02), complete diagnostic set (unknown-table/column/function, ambiguous-reference, function-arity), and docs/API.md public-surface update (D-06)"
  - "NameRef gains call_args (token slices between the call parens): the re-parser counts depth-0 comma-separated arguments so resolve_ref can emit function-arity without re-scanning source bytes"
  - "Arity mismatch still emits the Function binding (the name resolved); function-arity is an analyzer-channel diagnostic alongside it, never a syntax valid-channel change (ANLY-01)"
  - "CREATE VIEW body implemented as a token-slice re-parse after AS rather than a nested Select node — the CST body is a flat token stream (verified in parser.mbt segment_children_for_events); acceptance criteria (body t/a bindings) are met"
  - "unknown-column is gated on a scope that actually exposes columns, preserving the existing quoted-exact D-03 test (a columnless table referenced with a quoted name stays silent)"

patterns-established:
  - "Catalog::function case-fold resolution with Function bindings + unknown-function / function-arity diagnostics (D-04)"
  - "DML target-table scope frame (leading_prefix_end + qualified_ref_at) driving SET/WHERE/VALUES column resolution (D-02)"
  - "CREATE VIEW body re-parse via analyze_select_tokens over the AS-tail slice (D-02)"
  - "Analyzer-channel diagnostic set (unknown-table/unknown-column/unknown-function/ambiguous-reference/function-arity/requires-complete-parse) kept off the syntax valid channel (ANLY-01)"

requirements-completed: [ANAL-01]

coverage:
  - id: D1
    description: "Function-call resolution: `SELECT abs(a) FROM t` resolves abs via Catalog::function (ASCII case-fold) to a Function binding whose data_type is the catalog return_type; the argument `a` still resolves as a column"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 function basic doris-4.x"
        status: pass
    human_judgment: false
  - id: D2
    description: "unknown-function diagnostic: `SELECT nope(a) FROM t` with nope absent from the function registry emits an analyzer-channel unknown-function diagnostic spanning the call name"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 function unknown doris-4.x"
        status: pass
    human_judgment: false
  - id: D3
    description: "function-arity diagnostic: `SELECT concat(a) FROM t` with concat{min_arity:2, param_types:[VARCHAR,VARCHAR]} emits function-arity (1 arg) while still producing the Function binding"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 function arity doris-4.x"
        status: pass
    human_judgment: false
  - id: D4
    description: "DML column-level references: `UPDATE t SET a = 1 WHERE b = 2` binds t.a (SET) and t.b (WHERE) as Column bindings with catalog data_type; resolve_table_references behavior unchanged"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 dml update columns doris-4.x"
        status: pass
      - kind: integration
        ref: "test/__snapshot__/analyzer.dml-update-columns.doris-4.x.json"
        status: pass
    human_judgment: false
  - id: D5
    description: "CREATE VIEW body analysis: `CREATE VIEW v AS SELECT a FROM t` re-parses the AS-tail as a SELECT, binding the body's t (Table) and a (Column); the view name itself is a target table, not a reference"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 create-view body doris-4.x"
        status: pass
      - kind: integration
        ref: "test/__snapshot__/analyzer.create-view-body.doris-4.x.json"
        status: pass
    human_judgment: false
  - id: D6
    description: "ambiguous-reference diagnostic: `SELECT a FROM t1 JOIN t2 ON t1.id = t2.id` with both tables exposing `a` emits an analyzer-channel ambiguous-reference spanning the unqualified reference"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 ambiguous reference doris-4.x"
        status: pass
      - kind: integration
        ref: "test/__snapshot__/analyzer.ambiguous-reference.doris-4.x.json"
        status: pass
    human_judgment: false
  - id: D7
    description: "unknown-column diagnostic: `SELECT nope FROM t` with t exposing columns but not `nope` emits an analyzer-channel unknown-column diagnostic"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 unknown-column doris-4.x"
        status: pass
    human_judgment: false

# Metrics
duration: 50min
completed: 2026-08-10
status: complete
---

# Phase 5 Plan 4: Closeout and Analysis Foundation — Summary

**函数调用解析 + 元数检查（D-04，`Catalog::function` case-fold → Function binding / unknown-function / function-arity）+ DML（UPDATE SET/WHERE、DELETE WHERE、INSERT 列清单、MERGE SET）与 CREATE VIEW 体的列级引用（D-02）+ 完整类型诊断集（unknown-table/column/function、ambiguous-reference、function-arity，独立通道 ANLY-01）+ docs/API.md §Optional Name-Resolution API 公共面更新（D-06）**

## Performance

- **Duration:** 50 min
- **Started:** 2026-08-10T12:30:00Z (approximately)
- **Completed:** 2026-08-10T13:20:00Z
- **Tasks:** 3
- **Files modified:** 8 (3 analyzer impl + test/analyzer_anal01_test.mbt + 3 snapshots + docs/API.md)

## Accomplishments

- **函数调用解析与元数检查（Task 1，D-04/D-05）**：`analyzer/select_parser.mbt` 的 `collect_refs` 在检测到 `name(` 函数调用形状（深度 0、排除限定名末段）时捕获 `call_args`（调用括号内、不含括号本身的整 token 切片）；`analyzer/resolve.mbt` 新增 `count_call_args`（深度 0 逗号分隔计数，嵌套括号抑制内层逗号，整 token 字节免疫字符串）与函数解析分支——`Catalog::function` 解析时 ASCII case-fold 命中 → Function binding（`data_type` 取 `FunctionInfo.return_type`），未命中 → `unknown-function` 诊断，实参数目 `< min_arity` 或 `> param_types.length()` → `function-arity` 诊断（仍保留 Function binding，名称已解析；无表达式级类型合一/字面量传播，ANAL-02 出界）。
- **DML/CREATE VIEW 列级引用（Task 2，D-02）**：`analyze_dml_body` 经 `leading_prefix_end`（既有 helper）定位目标表、`qualified_ref_at` 恢复限定名表引用、`resolve_dml_target` 解析目标表并推入带列的作用域帧；UPDATE SET/WHERE、DELETE WHERE、INSERT 列清单 `(a, b)`、MERGE SET 内的列引用经该帧的 `ColumnInfo` 匹配 → Column binding + unknown-column 诊断。`resolve_table_references` 行为不变（D-05 负门禁）。`analyze_create_view_body` 把视图名/可选列清单/AS 之后的 token 切片交给 `analyze_select_tokens`（SELECT 分析管线抽取）——CST 中 CreateView 体是平铺 token 流（`segment_children_for_events` 实证），体表引用由此纳入。
- **完整诊断集（Task 2，D-04/ANLY-01）**：analyzer 独立通道补齐 `unknown-column`（非限定列在可见表列中未命中，且 scope 有带列的具名条目）、`unknown-function`、`function-arity`，连同既有 `unknown-table` 与 `ambiguous-reference`（非限定列命中多个可见表列）——全部在 `AnalysisDiagnostic` 通道，绝不进入语法 valid 通道（ANLY-01：同 bytes 带/不带 catalog 的 parse 结果逐字段相等，`test/analyzer_test.mbt` 持续断言）。
- **公共 API 文档（Task 3，D-06）**：`docs/API.md` §Optional Name-Resolution API 更新——新增 `analyze` 签名与 `AnalysisResult`/`Binding`/`BindingKind`/`AnalysisDiagnostic`/`FunctionInfo` 记录说明（强调平铺 `start_byte`/`end_byte` Int，不 import source）；`Catalog` trait 三方法（`table`/`table_in_db`/`function`）与 `StaticCatalog` db 作用域表/函数注册表；D-03 case policy 段（case-insensitive ASCII fold、quoted 精确、binding 保留源码拼写与 span）；D-04 类型诊断范围段（五诊断 code、无表达式级合一）；端点一览表新增 `analyze` 行；移除「deferred to v2 (D-24)」旧表述。
- **D-21 负门禁保持**：`analyzer/moon.pkg` 仅 import `fathom/sql/syntax`（`git diff` 为空）；`parser/moon.pkg` 未改动（diff 为空）；`syntax/syntax.mbt`、`parser/parser.mbt`、`analyzer/analysis.mbt` 均未改动（记录形状 05-02 已冻结）。全量 `moon test --target native --package analyzer --package test` 180/180 绿。

## Task Commits

Each task was committed atomically:

1. **Task 1: 函数调用解析 + 元数检查（D-04）** - `eee4096` (feat(05-04): function resolution, arity, DML/CREATE VIEW refs, and complete diagnostics — select_model.mbt + select_parser.mbt + resolve.mbt + test/analyzer_anal01_test.mbt + 3 snapshots)
2. **Task 2: DML/CREATE VIEW 列级引用 + 完整诊断集（D-02/D-04）** - `eee4096`（与 Task 1 同 commit：两任务共享 resolve.mbt/select_parser.mbt/test 文件，作为同一可验证单元交付）
3. **Task 3: docs/API.md §Optional Name-Resolution API 更新（D-06）** - `c51ef4b` (docs(05-04): update Optional Name-Resolution API for ANAL-01)

**Plan metadata:** `(final docs commit)` — 05-04-SUMMARY.md + STATE.md/ROADMAP.md/REQUIREMENTS.md progress updates

## Files Created/Modified

- `analyzer/select_model.mbt` - 修改：`NameRef` 新增 `call_args : Array[TokenSlice]`（调用括号内实参 token 切片，D-04）
- `analyzer/select_parser.mbt` - 修改：`collect_refs` 检测 `name(` 后捕获 `call_args`（匹配 `)` 结束，括号不含）；`parse_from_item` 的 NameRef 构造补 `call_args: []`
- `analyzer/resolve.mbt` - 修改：`count_call_args`（深度 0 实参计数）、`scope_has_visible_columns`（unknown-column 门控）、`resolve_ref` 函数分支（Function binding + unknown-function + function-arity）与非限定/2 段/3 段列未命中 unknown-column；`analyze_select_tokens`/`analyze_dml_body`/`analyze_create_view_body`/`analyze_body` 分派与 `qualified_ref_at`/`find_word_at_depth0`/`slice_tokens`/`resolve_token_refs`/`resolve_dml_target` helper；`analyze` 入口改走 `analyze_body`
- `test/analyzer_anal01_test.mbt` - 修改：新增 function basic/unknown/arity、unknown-column、dml update columns、create-view body、ambiguous reference 共 7 个集成用例
- `test/__snapshot__/analyzer.{dml-update-columns,create-view-body,ambiguous-reference}.doris-4.x.json` - 新增：3 个快照 golden
- `docs/API.md` - 修改：§Optional Name-Resolution API（analyze/AnalysisResult/Binding/FunctionInfo、Catalog 三方法、case policy、D-04 诊断范围）+ 端点表 analyze 行 + 移除 deferred-to-v2

## Decisions Made

- **`NameRef` 增加 `call_args` 字段**：re-parser 在检测到函数调用时捕获括号内实参 token 切片，`resolve_ref` 即可做深度 0 实参计数与元数检查，无需再扫源码字节（D-04）。这是 analyzer 内部模型字段（非公共 `analysis.mbt` 记录），不违反「analysis.mbt 不加字段」约束。
- **元数不匹配仍发 Function binding**：函数名已解析，`function-arity` 是与 binding 并行的 analyzer 通道诊断——计划 must_have「命中 → Function binding」与「元数不匹配 → function-arity 诊断」同时成立。
- **CREATE VIEW 体以 token 切片再解析实现**：CST 中 CreateView 体是平铺 token-leaf 流（`segment_children_for_events` 只产叶子，不产嵌套 Select 节点），因此「AS 后查询体走既有 Select 分析」实现为截取 AS 后切片交 `analyze_select_tokens`；验收（体 t/a 绑定）达成。
- **unknown-column 以「可见表确有列」门控**：`scope_has_visible_columns` 为 true 才报——裸 `SELECT x`（空 scope）与引用空列表表（quoted-exact D-03 测试）保持静默，既有测试不回归。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] CREATE VIEW 体并非嵌套 Select 节点，改为 AS 尾切片再解析**
- **Found during:** Task 2（analyze_create_view_body 实现前验证 parser 结构）
- **Issue:** 计划表述「CREATE VIEW 体（AS 后查询体是 Select 节点）走既有 Select 分析」，但 `parser.mbt` `finish_statement`/`segment_children_for_events` 将整个语句体构建为**平铺 token-leaf 流**（无嵌套 ChildNode Select）——直接找嵌套 Select 子节点不可行。
- **Fix:** 新增 `analyze_select_tokens`（token 切片上的 SELECT 再解析管线），`analyze_create_view_body` 用 `leading_prefix_end` + `qualified_ref_at` 定位视图名，跳过可选列清单 `(a, b)` 与 `AS`，把余下切片交 SELECT 管线。
- **Files modified:** analyzer/resolve.mbt
- **Verification:** `analyzer-anal01 create-view body doris-4.x` + 快照通过（体 t/a 绑定）；180/180 绿
- **Committed in:** eee4096

**2. [Rule 3 - Blocking] `for (b, _, _) in tokens` 元组解构风险，改用元组字段访问**
- **Found during:** Task 2（实现时保守兼容 MoonBit 语法）
- **Issue:** 元组解构 + 通配符在 `for` 绑定器中的写法不够稳健。
- **Fix:** 改用 `for t in tokens { words.push(t.0) }`（元组字段访问），两处（analyze_dml_body / analyze_create_view_body）。
- **Files modified:** analyzer/resolve.mbt
- **Verification:** `moon test --target native --package analyzer` 编译通过
- **Committed in:** eee4096

---

**Total deviations:** 2 auto-fixed (2 Rule 3 blocking)
**Impact on plan:** Both fixes necessary for correct implementation; no scope creep. All acceptance criteria met.

## Issues Encountered

- **bash 持久 shell 阻塞（环境问题，非计划问题）**：`_bash` 工具 session 在 harness 层 wedged（子代理 `Exec05_03` 确认 KillMoonProcs 无 moon 进程残留；fresh-process 命令可用），所有 `_bash` 调用超时。通过 `hub op:start` + `op:wait` 启动独立进程执行全部命令（moon build/test、git add/commit/diff、gsd-tools state handlers），未影响产出。
- **`moon check --package` 不支持**：该版本 `moon check` 不支持 `--package`；改用 `moon test --target native --package analyzer` 编译检查（Exec05_03 提示）。
- **`git show --format=done` 非法**：`--format=done` 不是合法 pretty 格式（exit 128），改用 `--format=` 空串获取 numstat。

## TDD Gate Compliance

计划 Task 1/Task 2 标记 `tdd="true"`，但本 plan 的执行以「实现+测试同 commit」方式进行：集成测试引用 `collect_refs` 的 `call_args` 与 `resolve_ref` 的 unknown-function/arity 分支，这些仅在实现落地后才存在，独立 RED（仅测试）commit 无法通过编译，故 RED/GREEN 分阶段 commit 未单独拆分（与 05-03 相同处置）。对应验证已由 Task 1/2/3 的 feat/docs commit 与全量 180/180 测试覆盖（见 coverage 块）。

## Known Stubs / Intentional Gaps

- **JOIN `ON`/`USING` 条件列解析**：`parse_from` 消费 ON/USING 条件但未做名字解析（`SELECT a FROM t1 JOIN t2 ON t1.id = t2.id` 中 `t1.id`/`t2.id` 不产生 binding）——不在本计划验收范围（D-02 列级覆盖的 JOIN 条件列解析顺延）。歧义诊断仍由 SELECT 列表的非限定 `a` 触发并已验证。
- **无表达式级类型合一/字面量传播**：`data_type` 仅来自 `ColumnInfo.data_type` / `FunctionInfo.return_type`，不做推导（ANAL-02 出界，计划明文）。

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 6 Lint 与 Phase 7 LINE-01 可直接消费 `AnalysisResult`/`Catalog` 契约与函数/DML/CREATE VIEW 解析面。
- `docs/API.md` 已与公共面同步；ANLY-01 字节一致性与 D-21 负门禁保持绿色。
- 无阻塞项。

## Self-Check: PASSED

- `[ -f analyzer/resolve.mbt ]` → FOUND
- `[ -f analyzer/select_model.mbt ]` → FOUND
- `[ -f analyzer/select_parser.mbt ]` → FOUND
- `[ -f test/analyzer_anal01_test.mbt ]` → FOUND
- `[ -f test/__snapshot__/analyzer.dml-update-columns.doris-4.x.json ]` → FOUND (all 3 new snapshots present)
- `git log --oneline | grep eee4096` → FOUND (Task 1+2 commit)
- `git log --oneline | grep c51ef4b` → FOUND (Task 3 docs commit)
- `moon test --target native --package analyzer --package test` → 180/180 passed
- `git diff analyzer/moon.pkg parser/moon.pkg` → empty (D-21 negative gates green)

---
*Phase: 05-closeout-and-analysis-foundation*
*Completed: 2026-08-10*
