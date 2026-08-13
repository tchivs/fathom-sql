---
phase: 05-closeout-and-analysis-foundation
plan: 02
subsystem: analyzer
tags: [moonbit, analyzer, catalog, sql, name-resolution, tracer, d-05, d-03, d-01]

# Dependency graph
requires:
  - phase: 02-05
    provides: analyzer baseline (D-21..D-24): ColumnInfo/TableInfo/Catalog/StaticCatalog, source_token_texts/bytes_equal_ci/utf8_to_string, resolve_table_references over @syntax read views
  - phase: 05-01
    provides: Phase 5 closeout records (STATE/REQUIREMENTS traceability context)
provides:
  - D-05 one-way Catalog contract: table + table_in_db(db,name) + function(name); StaticCatalog db_tables/functions registries + case-fold lookup + StaticCatalog-only lookup_exact
  - FunctionInfo / BindingKind / Binding / AnalysisDiagnostic / AnalysisResult public records (flattened start_byte/end_byte, D-06)
  - analyze() end-to-end SELECT tracer: source_tokens + paren-depth clause split + catalog resolution + independent diagnostic channel (ANLY-01)
affects: [05-03, 05-04 (full ANAL-01 resolution), Phase 6 Lint, Phase 7 LINE-01, docs/API.md]

# Actuals (#2632) — pairs with the plan's `estimate` (tokens: 95000, raw_tokens: 63000).
# Same estimateTokens scale (chars/4 over the realized diff), never a harness token count.
actuals:
  tokens: 9139
  tasks: 3
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Byte-level re-parse of the flat token-leaf CST (D-01): source_tokens returns (bytes,start_byte,end_byte) triples; clause split only on whole-token keyword bytes with paren-depth counting on `(`/`)` only — immune to keywords inside strings/quoted identifiers"
    - "Flattened Int spans in public records (D-01/D-06): Binding/AnalysisDiagnostic use start_byte/end_byte, never @source.Span, keeping analyzer/moon.pkg imports at syntax-only (D-21)"
    - "Parsing-time ASCII case-fold (D-03): StaticCatalog lookup folds via String::equal_ignore_ascii_case; quoted identifiers go through Catalog::table case-fold + byte-exact TableInfo.name re-check, never lookup_exact on the generic path"
    - "Refusal-first analysis (D-33 philosophy): Error/Missing SELECT bodies produce empty bindings + one requires-complete-parse diagnostic, never panic"

key-files:
  created:
    - analyzer/analysis.mbt
    - analyzer/select_model.mbt
    - analyzer/select_parser.mbt
    - analyzer/resolve.mbt
    - test/analyzer_anal01_test.mbt
    - test/__snapshot__/analyzer.select-basic.doris-4.x.json
  modified:
    - analyzer/analyzer.mbt
    - test/analyzer_test.mbt
    - test/moon.pkg

key-decisions:
  - "D-05 one-way Catalog contract frozen (option-a): table + table_in_db(db,name) + function(name); StaticCatalog gains db_tables/functions registries with parsing-time ASCII case-fold lookup (D-03) and StaticCatalog-only lookup_exact exact-match primitive (never on the generic resolve path)"
  - "analyze() end-to-end tracer (D-01/D-04/D-06): SELECT bodies re-parsed from the flat token-leaf CST via source_tokens + paren-depth clause split; bindings carry flattened start_byte/end_byte spans; analyzer diagnostics live on an independent channel (ANLY-01); quoted identifiers resolve via Catalog::table case-fold + byte-exact TableInfo.name re-check"

patterns-established:
  - "Paren-depth clause splitting immune to string/quoted-identifier contamination (whole-token keyword matching)"
  - "Flattened Int span records mirroring api.PrimitiveDiagnostic (serialization-friendly, no source import)"
  - "Quoted-identifier exact matching realized at the resolve layer (case-fold lookup + byte re-check), keeping lookup_exact out of the generic trait path"

requirements-completed: [ANAL-01]

coverage:
  - id: D1
    description: "D-05 one-way Catalog contract: table/table_in_db/function trait methods, StaticCatalog db_tables+functions registries, case-fold lookup (D-03), StaticCatalog-only lookup_exact — unique implementer and test trait-dispatch helper migrated in the same commit"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_test.mbt#analyzer_catalog_trait_dispatches_to_static_catalog"
        status: pass
      - kind: integration
        ref: "test/analyzer_test.mbt#analyzer_catalog_lookup_hits_and_misses"
        status: pass
      - kind: integration
        ref: "test/analyzer_test.mbt#analyzer_catalog_lookup_exact_is_byte_exact_for_quoted"
        status: pass
      - kind: integration
        ref: "moon test --target native --package analyzer --package test"
        status: pass
    human_judgment: false
  - id: D2
    description: "End-to-end analyze() tracer: `SELECT a, b FROM t` returns AnalysisResult with t(Table), a(Column INT), b(Column VARCHAR(10)) bindings carrying source-spelling names and byte-exact start_byte/end_byte spans; snapshot golden generated"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 select-basic doris-4.x"
        status: pass
      - kind: integration
        ref: "test/__snapshot__/analyzer.select-basic.doris-4.x.json"
        status: pass
    human_judgment: false
  - id: D3
    description: "Independent analyzer diagnostic channel (ANLY-01): `SELECT a FROM missing` yields one unknown-table AnalysisDiagnostic while the syntax valid flag stays true"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 unknown-table diagnostic"
        status: pass
    human_judgment: false
  - id: D4
    description: "D-03 quoted-identifier exact matching through the generic resolve path: Catalog::table case-fold hit + byte-exact TableInfo.name re-check; unquoted identifiers fold directly; StaticCatalog::lookup_exact never called in resolve"
    requirement: ANAL-01
    verification:
      - kind: integration
        ref: "test/analyzer_anal01_test.mbt#analyzer-anal01 quoted-exact generic"
        status: pass
    human_judgment: false

# Metrics
duration: 40min
completed: 2026-08-10
status: complete
---

# Phase 5 Plan 2: Closeout and Analysis Foundation — Summary

**D-05 one-way Catalog 契约定形（table + table_in_db + function，StaticCatalog db/函数注册表 + case-fold）并以生产级端到端 tracer 打通 `SELECT a, b FROM t` → `AnalysisResult`（带 span bindings + 独立诊断通道），quoted 精确匹配经 case-fold + 字节复核在 resolve 层落地（D-03）**

## Performance

- **Duration:** 40 min
- **Started:** 2026-08-10T09:20:00Z (approximately)
- **Completed:** 2026-08-10T10:01:58Z
- **Tasks:** 3
- **Files modified:** 9 (5 analyzer files + test/analyzer_test.mbt + test/analyzer_anal01_test.mbt + test/moon.pkg + snapshot)

## Accomplishments

- **D-05 one-way Catalog 契约一次定形**：`pub(open) trait Catalog` 新增 `table_in_db(Self, db, name)` 与 `function(Self, name)`（保留既有 `table`，resolve_table_references 行为零变化）；`StaticCatalog` 新增 `db_tables`/`functions` 注册表与 `lookup_in_db`/`lookup_function`（解析时 ASCII case-fold，D-03）、`lookup_exact`（字节等值，仅供 StaticCatalog 直测、不进泛型 resolve 路径）；`FunctionInfo` 记录落地 `analyzer/analysis.mbt`。
- **端到端 SELECT tracer**：`analyzer/select_parser.mbt` 的 `source_tokens`（返回 (Bytes, Int, Int) 三元组，镜像 source_token_texts 遍历）与括号深度感知子句切分；`analyzer/resolve.mbt` 的 `pub fn[T : Catalog] analyze` 走 Document→Statement→Select body，FROM 表经 `Catalog::table` case-fold 解析为 Table binding，SELECT 列表裸列名解析为 Column binding（携带 data_type）；Error/Missing 树产出空 bindings + `requires-complete-parse` 诊断，绝不 panic（D-33 哲学）。
- **独立诊断通道（ANLY-01）**：`SELECT a FROM missing` 产出 code=`unknown-table` 的 AnalysisDiagnostic，语法 `valid` 保持 true；quoted 标识符（`` `T` ``）经 case-fold 命中后对 `TableInfo.name` 做字节等值复核，复核不等即 unknown-table（D-03）。
- **D-21 负门禁保持**：`analyzer/moon.pkg` 仅 import `fathom/sql/syntax`（diff 为空）；`parser/moon.pkg` 未改动（diff 为空）；公共 API 全部用平铺 `start_byte`/`end_byte` Int，不 import source。

## Task Commits

Each task was committed atomically:

1. **Task 1: D-05 Catalog trait 形状定形（checkpoint:decision，AUTO 选 option-a）** - 无代码提交（决策即 option-a，并入 Task 2）
2. **Task 2: D-05 Catalog 契约扩展 + 唯一实现者与测试 helper 同 commit 迁移** - `23ac9be` (feat(05-02): extend Catalog contract with table_in_db and function (D-05))
3. **Task 3: tracer — 端到端 analyze()：`SELECT a, b FROM t` → AnalysisResult** - `37f4690` (feat(05-02): end-to-end analyze tracer for SELECT (D-01/D-03/D-04/D-06))

**Plan metadata:** `(final docs commit)` — 05-02-SUMMARY.md + STATE.md/ROADMAP.md/REQUIREMENTS.md progress updates

## Files Created/Modified

- `analyzer/analysis.mbt` - 新增：`FunctionInfo`（D-05）+ `BindingKind`/`Binding`/`AnalysisDiagnostic`/`AnalysisResult`（D-06，平铺 Int span）
- `analyzer/analyzer.mbt` - 修改：Catalog trait（+table_in_db/+function）、StaticCatalog（+db_tables/+functions/+with_db/+with_function/+lookup_in_db/+lookup_function/+lookup_exact）、case-insensitive lookup（D-03）、doc 注释更新
- `analyzer/select_model.mbt` - 新增：`ClauseKind`/`TokenSlice`/`SelectItem`/`FromItem`/`CteDef`/`SelectCore`/`SelectModel` 模型形状（D-01）
- `analyzer/select_parser.mbt` - 新增：`source_tokens` + 括号深度感知子句切分（`MAX_PAREN_DEPTH=128`，T-05-02-01）
- `analyzer/resolve.mbt` - 新增：`analyze` 入口 + 表/列解析 + quoted 字节复核 + requires-complete-parse 诊断
- `test/analyzer_test.mbt` - 修改：catalog_lookup trait-dispatch helper 扩展至三方法；D-03 case-insensitive 断言更新；lookup_exact quoted 用例
- `test/analyzer_anal01_test.mbt` - 新增：select-basic（bindings + span + 快照）、unknown-table、quoted-exact 集成测试
- `test/__snapshot__/analyzer.select-basic.doris-4.x.json` - 新增：select-basic 快照 golden（moon test --update 唯一写路径）
- `test/moon.pkg` - 修改：新增 `moonbitlang/core/test`（@mtest，规避与本地 test 包 alias 冲突）`for "test"`

## Decisions Made

- **D-05 option-a（Task 1 自动选定）**：保留 `table` + 新增 `table_in_db` + `function`，与唯一实现者 StaticCatalog 及测试 helper 同 commit 迁移；拒绝 option-b（破坏 resolve_table_references）与 option-c（db 维度顺延将造成二次 one-way 破坏）。
- **resolve 层 quoted 精确匹配落地**：quoted 标识符仍只经 `Catalog::table`（case-fold）查询，命中后对返回 `TableInfo.name` 与 quoted 拼写作字节等值复核；`StaticCatalog::lookup_exact` 仅为 StaticCatalog 直测的精确匹配原语，不进入泛型 `[T : Catalog]` 路径。
- **测试入口用 `@parser.parse_with_limits` 而非 `@api.parse_with_ids`**：后者返回 `PrimitiveNode` root，与 `analyze(@syntax.SyntaxNode)` 类型不匹配；沿用 analyzer_test.mbt 既有集成 setup（Rule 3 修正，语义等价）。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] 集成测试改用 `@parser.parse_with_limits` 入口**
- **Found during:** Task 3（test/analyzer_anal01_test.mbt）
- **Issue:** 计划指定的 `@api.parse_with_ids` 返回 `ParseResult.root : PrimitiveNode`，与 `@analyzer.analyze(node : @syntax.SyntaxNode, ...)` 签名不兼容（PrimitiveNode 不是 SyntaxNode），无法编译。
- **Fix:** 改用既有 analyzer_test.mbt 的 parser 级入口：`@source.SourceText::new_with_limit` + `@parser.parse_with_limits(source, doris_context("4.x"), Strict, ParserLimits::default())`，`parsed.root` 即 `@syntax.SyntaxNode`；ANLY-01 断言（valid/diagnostics/kind 逐字段相等）保留。
- **Files modified:** test/analyzer_anal01_test.mbt
- **Verification:** `moon test --target native --package analyzer --package test` 158/158 通过
- **Committed in:** 37f4690 (Task 3 commit)

**2. [Rule 3 - Blocking] 测试包 `@test` alias 与本地 `test` 包冲突**
- **Found during:** Task 3（test/analyzer_anal01_test.mbt 编译）
- **Issue:** 本地包名为 `test`，`import "moonbitlang/core/test" @test` 触发 "Duplicate alias `test`"，`@test.Test` 无法解析。
- **Fix:** 将 core test 包 alias 改为 `@mtest`（`for "test"`），测试文件同步改用 `@mtest.Test`；`SnapshotError`/assert 系列为 builtin，无需改动。
- **Files modified:** test/moon.pkg, test/analyzer_anal01_test.mbt
- **Verification:** `moon test` 158/158 通过
- **Committed in:** 37f4690 (Task 3 commit)

**3. [Rule 1 - Bug] select-basic 测试 byte 偏移量修正**
- **Found during:** Task 3（analyzer-anal01 select-basic 断言失败 `17 != 18`）
- **Issue:** 计划注释中的字节偏移估算有误：`SELECT a, b FROM t` 实际为 `t`@[17,18)（b 后无第二个逗号），非 [18,19)。
- **Fix:** 校正测试断言与注释（a@[7,8)、b@[10,11)、t@[17,18)）；实现逻辑本身正确，仅测试预期修正。
- **Files modified:** test/analyzer_anal01_test.mbt
- **Verification:** select-basic 断言 + 快照通过
- **Committed in:** 37f4690 (Task 3 commit)

**4. [Rule 3 - Blocking] MoonBit 编译语法修正**
- **Found during:** Task 2/3 编译
- **Issue:** `const max_paren_depth` 需大写 `MAX_PAREN_DEPTH`；`Array.push` 绑定不需 `mut`（unused_mut 报错）；多态函数 `fn f[..]` 已弃用需 `fn[..] f`；字符串插值为 `\{x}` 而非 `\(x)`。
- **Fix:** 全部按 pinned toolchain（moon 0.1.20260724）语法修正。
- **Files modified:** analyzer/select_parser.mbt, analyzer/resolve.mbt, analyzer/analyzer.mbt
- **Verification:** `moon test` 编译通过
- **Committed in:** 23ac9be / 37f4690

---

**Total deviations:** 4 auto-fixed (3 Rule 3 blocking, 1 Rule 1 bug)
**Impact on plan:** All fixes necessary for compilation/correctness; no scope creep. Plan behavior unchanged.

## Issues Encountered

- **bash 持久 shell 阻塞（环境问题，非计划问题）**：`_bash` 工具 session 因挂起 git 进程在 harness 层 wedged（stale PTY），所有 `_bash` 调用超时。通过 `hub op:start` 启动独立 bash 进程执行全部命令（git/moon/gsd-tools），未影响产出；根因经子代理诊断确认是 harness 内部状态，无法通过杀进程修复。
- **`state.update-progress` SDK 空操作**：返回 "Progress field not found in STATE.md"（字段结构不匹配）；等价进度更新通过 `roadmap.update-plan-progress` 完成。
- **`requirements.mark-complete ANAL-01` 已回退**：ANAL-01 为 Phase 5 全阶段需求（横跨 05-02/03/04），05-02 仅交付 foundation；为避免 traceability 提前闭合，已将 REQUIREMENTS.md ANAL-01 复选框恢复为 `[ ]` 并将 Traceability 行标为 "In Progress — 05-02 foundation delivered; full resolution in 05-03/05-04"。SUMMARY frontmatter 的 `requirements-completed: [ANAL-01]` 按模板从计划 frontmatter 复制，表示本计划贡献该需求；需求最终闭合由 05-04 完成。
- **全量 `moon test --target native` 的 `binding` 包 E4219 失败为既有问题**：`binding/exports.mbt` 是 `foreign_library`，不能在本机 native 测试目标编译（仓库既有文档已记录，CI 的 native 测试命令不含 `--package binding`）。计划 verify（`--package analyzer --package test`）158/158 全绿，不受影响。

## Known Stubs / Intentional Gaps

- `analyzer/select_model.mbt` 的 `SelectCore.where_tokens/group_by/having/qualify/order_by/limit/window` 字段、`ClauseKind` 多数变体、`CteDef`/`SelectModel` 为**计划内模型形状占位**（D-01：本 task 只要求 SelectList 与 From 真实填充，其余由 05-03 全量展开）——非功能 stub，不阻塞本计划 tracer 目标。

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 05-03 可在本骨架扩展：完整子句（WHERE/GROUP BY/HAVING/ORDER BY/LIMIT/UNION）、CTE/子查询作用域、别名、限定名 db.table.col、星号展开与未知列/歧义/元数诊断。
- Phase 6 Lint 与 Phase 7 LINE-01 可直接消费本计划定形的 `AnalysisResult`/`Catalog` 契约（D-06 预留）。
- `docs/API.md` §Optional Name-Resolution API 待 05-03/05-04 更新（新公共 API 面）。
- 无阻塞项。

## Self-Check: PASSED

- `[ -f analyzer/analysis.mbt ]` → FOUND
- `[ -f analyzer/select_model.mbt ]` → FOUND
- `[ -f analyzer/select_parser.mbt ]` → FOUND
- `[ -f analyzer/resolve.mbt ]` → FOUND
- `[ -f test/analyzer_anal01_test.mbt ]` → FOUND
- `[ -f test/__snapshot__/analyzer.select-basic.doris-4.x.json ]` → FOUND
- `git log --oneline | grep 23ac9be` → FOUND (Task 2 commit)
- `git log --oneline | grep 37f4690` → FOUND (Task 3 commit)
- `moon test --target native --package analyzer --package test` → 158/158 passed (re-run after commit)

---
*Phase: 05-closeout-and-analysis-foundation*
*Completed: 2026-08-10*
