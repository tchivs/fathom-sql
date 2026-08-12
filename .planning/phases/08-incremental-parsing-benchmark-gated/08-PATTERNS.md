# Phase 8: Incremental Parsing (Benchmark-Gated) — Pattern Map

**Mapped:** 2026-08-12
**Files analyzed:** 11（3 分支无关新建 + 1 证据文档 + 3 流程工件更新 + 4 分支 B contingency）
**Analogs found:** 10 / 11（唯一无直接 analog 的是 `bench/` 的 `@bench` attribute 用法 —— 仓库内零先例，标 verify-at-execution）

> 本映射基于对既有代码库的直接读源。所有代码摘录均来自当前仓库真实文件，行号已逐一定位。正文用中文，代码/路径/符号保留英文。
> 核心结论：**bench/ 是独立测试面（reversible, D-01）**，其 `moon.pkg`/入口/输入构造分别仿 `lint/`、`test/`、`corpus/` + `parity/baseline_test.mbt`；**incremental/ 是分支 B contingency**，复用的全部基础（`SourceText`/`Span`/`LineIndex`/`SyntaxNode`/`ParsedDocument`/`lex_with_limit`）已有仓库证据，唯缺 `Edit`/`Revision` 层（grep 零命中）。

---

## File Classification

| 新/修改文件 | Role | Data Flow | Closest Analog | Match Quality |
|------------|------|-----------|----------------|---------------|
| `bench/moon.pkg` | config（包依赖声明） | — | `lint/moon.pkg` / `fingerprint/moon.pkg`（library 依赖声明）+ `test/moon.pkg`（test import） | role-match（无 `@bench` 先例） |
| `bench/bench.mbt` | utility/harness（`@bench` 被测函数） | request-response（整文档 parse 延迟采样） | `test/source_test.mbt` `parse_editor`（test/source_test.mbt:1-5）+ `api/api.mbt:431` `@api.parse` 调用面 | partial（`@bench` attribute 无先例，函数体形状仿测试 helper） |
| `bench/build_editor_scale.mbt` | utility（合成输入构造） | transform（corpus 拼接 + 重复 → ≥100KB） | `parity/baseline_test.mbt` 内嵌 fixture bytes（baseline_test.mbt:7-9,38-39）+ `corpus/script-multi-statement.sql`（多语句文档形状） | role-match |
| `.planning/phases/08-…/08-BENCHMARK.md` | docs（门禁证据记录） | — | `corpus/CORPUS-REPORT.md`（结构化证据报告）+ `07-VERIFICATION.md`（证据逐项核对表） | partial（新文档类型；五要素由 D-03/Pitfall 4 明文） |
| `.planning/REQUIREMENTS.md` | docs/traceability（EDIT-01 状态更新） | — | 自身（REQUIREMENTS.md:34 EDIT-01 行 + Traceability 表） | exact |
| `.planning/ROADMAP.md` | docs（Phase 8 状态更新） | — | 自身（ROADMAP.md:114-125 Phase 8 Status 行） | exact |
| `.planning/STATE.md` | docs/traceability（决策/Deferred 记录） | — | 自身（STATE.md:269-281 Deferred Items 表） | exact |
| `incremental/moon.pkg`（分支 B） | config（包依赖声明） | — | `lineage/moon.pkg`（只 import 三个库：analyzer+syntax+debug）——incremental 只 import source+syntax+parser（D-04/D-21） | role-match |
| `incremental/edit.mbt`（分支 B） | model（Edit/Revision 类型 + span 重映射） | transform | `source/source.mbt` `Span`/`Span::checked`/`SourceText`（source.mbt:6-53）——无现成 Edit 类型，需新增 | partial（类型形状仿 Span 的 checked 构造 + enum error） |
| `incremental/incremental.mbt`（分支 B） | service（`parse_incremental` 库 API） | transform（bounded reparse + span-overlap invalidation） | `parser/parser.mbt:4275` `parse_with_limits_context`（Document 生产入口）+ `lexer/lexer.mbt:428` `lex_with_limit`（bounded relex） | partial |
| `incremental/incremental_test.mbt`（分支 B） | test（edit fixtures + SC2 不变量） | — | `parity/baseline_test.mbt`（`@test.T::snapshot` 机制 + `snapshot_test` helper）+ `test/source_test.mbt`（round-trip 断言） | exact |

---

## Pattern Assignments

### `bench/moon.pkg`（config，分支无关）

**Analog:** `lint/moon.pkg`（library 包依赖声明）+ `test/moon.pkg`（测试专用 import）

**既有 library 包依赖声明（lint/moon.pkg verbatim）：**
```moonbit
pkgtype(kind: "library")
import {
  "fathom/sql/syntax" @syntax,
  "fathom/sql/dialect" @dialect,
  "fathom/sql/source" @source,
  "fathom/sql/formatter" @formatter,
  "fathom/sql/analyzer" @analyzer,
  "moonbitlang/core/buffer" @buffer,
  "moonbitlang/core/debug" @debug,
}
```

**测试专用 import 面（test/moon.pkg verbatim，`for "test"` 块）：**
```moonbit
import {
  "moonbitlang/core/test" @mtest,
} for "test"
```

**`bench/moon.pkg` 应声明（D-01 被测面）：** `pkgtype(kind: "library")`（bench 是独立测试面，非 executable），import = `"fathom/sql/api" @api`（主测面）+ `"fathom/sql/parser" @parser`（辅测面）+ `"fathom/sql/source" @source`（输入构造）。**不 import** `incremental/`（永不；D-04 纪律）。`@bench` attribute 为工具链内置，无需 import。注意 `test/moon.pkg` 的 `options(targets: ...)` 模式（parity/moon.pkg）仅当 bench 需要 js/wasm 补充记录时才引入。

**Verify-at-execution（Pitfall 1）：** `@bench` + `moon bench --target native --output-json` 在 pinned `moon 0.1.20260724`（moon.mod:5-8）上的可用性仓库内无法确认——执行首步跑最小 `@bench` 探针；不可用则降级 `moon test` + 手动计时循环（08-BENCHMARK.md 注明）。

### `bench/bench.mbt`（utility/harness，分支无关）

**Analog:** `test/source_test.mbt:1-5` 的 `parse_editor` helper（黑盒测试经 `@api` 的既有调用形状）

**既有测试 helper（test/source_test.mbt:1-5 verbatim）：**
```moonbit
fn parse_editor(raw : Bytes) -> @api.ParseResult {
  match @api.parse_with_ids(raw, "doris", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
}
```

**被测入口（api/api.mbt:431，benchmark 主测面）：**
```moonbit
pub fn parse(raw : Bytes, options : ParseOptions) -> Result[ParseResult, ParseError]
```

**辅助被测面（parser/parser.mbt:4275，纯核心 CST）：**
```moonbit
pub fn parse_with_limits_context(
  source : @source.SourceText,
  context : @dialect.DialectContext,
  mode : ParseMode,
  limits : ParserLimits,
) -> ParsedDocument
```

**`bench/bench.mbt` 应仿：** 每个 `@bench fn` 无参、返回 `Unit`，函数体 = 构造输入 → `@api.parse(raw, options)`（`ParseOptions::new("doris", "4.x", "strict")` 或 `for_profile_with_metadata`，见 api/api.mbt:96-123/124）→ **`keep()` 消费结果防 DCE**（STACK.md:231 指定，精确语法 verify-at-execution）。一组规模梯度（25KB/50KB/100KB/200KB，D-02 第二判据超线性检测）各配一个 `@bench fn`，命名 `parse_full_<fixture>` / `parse_full_editor_scale`。`options.limits.max_bytes = 8MiB`（ParseLimits::default，api.mbt:22-31）确保 100KB 输入通过（research RQ2 已验证）。

### `bench/build_editor_scale.mbt`（utility，分支无关）

**Analog:** `parity/baseline_test.mbt:7-9` 的内嵌 fixture 纪律 + `corpus/script-multi-statement.sql` 的多语句文档形状

**仓库纪律（baseline_test.mbt:7-9 verbatim 节选）：**
```moonbit
/// Runtime never reads disk — raw bytes are embedded at authoring time from
/// corpus/doris-{2.1,3.x,4.x}/*.sql plus the manifest's inline rows
```
→ `bench/` 同样**不读磁盘**：corpus 语句在 authoring 时作为 bytes 字面量内嵌，运行时拼接/重复。

**输入素材（corpus/ 实测，research RQ2 [VERIFIED]）：** 全部 fixture 392B–1.1KB；`doris-4.x` 15 文件 ≈ 8.9KB，`doris-3.x`/`doris-2.1` 各 8 个；**全部拼接 < 25KB**，必须重复拼接才达 ≥100KB。多语句文档形状见 `corpus/doris-4.x/script-multi-statement.sql`（`CREATE TABLE t (a INT); INSERT INTO t VALUES (1); SELECT * FROM t;` 以分号分隔多语句）。复杂 SELECT+DDL 代表：`corpus/doris-4.x/select-industrial.sql`（`SELECT /*+ SET_VAR */ ... OVER (...) ... GROUP BY CUBE ... LIMIT ... OFFSET ... INTO OUTFILE`）+ `ddl-create-table.sql`。

**`build_editor_scale.mbt` 应仿：** 内嵌语句池（每条一个 `Bytes` 字面量，含注释头/空白/多语句/复杂 SELECT+DDL）→ 拼接 + 重复至目标规模，返回 `Bytes`。避免病态深嵌套（A4：`max_recursion_depth=128`，parser.mbt:38-45——深嵌套会触发 resource 诊断而非正常路径）。

### `.planning/phases/08-…/08-BENCHMARK.md`（docs，分支无关）

**Analog:** `corpus/CORPUS-REPORT.md`（结构化证据报告）+ `07-VERIFICATION.md`（逐项证据核对）。无直接同名先例——本文件是 SC1 明文要求的新证据类型。

**必须包含五要素（D-03 / Pitfall 4）：** fixture 清单（内嵌语句池来源）、输入规模（25/50/100/200KB）、median/p95 延迟（native；js/wasm 若可行补充）、门禁结论（D-02 阈值判定：≥100KB median > 50ms 或 O(n²) 迹象）、工具链记录（`moon bench --version` 输出 + 若降级的替代方法）。无数据落库不宣称"已评估"。

### `.planning/REQUIREMENTS.md` / `.planning/ROADMAP.md` / `.planning/STATE.md`（docs/traceability，分支无关）

**Analog:** 自身（既有 traceability 更新先例见 05-01-PLAN.md:25-26,60-66,98 与 STATE.md:269-281）

**EDIT-01 需求行（REQUIREMENTS.md:34 verbatim 节选，现为 `[ ]`）：**
```markdown
- [ ] **EDIT-01**: Editor can use bounded incremental parsing and targeted CST refactors without reparsing the full document — **only when `moon bench` benchmarks demonstrate ...** (print_lossless(parse_incremental(x)) == print_lossless(parse_full(x))).
```
- **分支 A（descope）：** 此行 `[ ]` → `[x]` 并追加 `— DESCOPED WITH EVIDENCE 2026-08-xx` + `08-BENCHMARK.md` 引用（SC1 明文允许）；Traceability 表（REQUIREMENTS.md:67-75）EDIT-01 行状态 → `Descoped with evidence`。
- **分支 B（实现）：** 行尾追加实现记录引用；Traceability 状态 → `Complete`。

**STATE.md Deferred Items 表（STATE.md:269-281，verbatim 表头）：**
```markdown
| Category | Item | Status |
|----------|------|--------|
| verification_override | ... | override_closeout |
```
- 分支 A：新增一行 `| descope_evidence | EDIT-01 incremental parsing — benchmark-gated descope | closed 2026-08-xx — 08-BENCHMARK.md (fixture/规模/median/p95/结论) |`（仿既有 `closed — Phase 5 CLOSE-01 formally verified` 状态措辞，05-01-PLAN.md:66）。
- 分支 B：新增决策记录行（仿 `Accumulated Context → Decisions` 的 D-编号格式）。

**ROADMAP.md Phase 8（ROADMAP.md:114-125）：** Status 行从 `Not started (gated)` 更新为 `Complete — descoped with evidence (see 08-BENCHMARK.md)`（分支 A）或 `Complete — incremental/ delivered`（分支 B）。**plan 首个 tracer 必须是 benchmark**（D-03），分支结果决定后续 plan 是 descope 记录还是增量实现。

---

### `incremental/moon.pkg`（config，分支 B contingency）

**Analog:** `lineage/moon.pkg`（最小依赖面 library——只 import 消费面）

**既有最小依赖声明（lineage/moon.pkg verbatim）：**
```moonbit
pkgtype(kind: "library")
import {
  "fathom/sql/analyzer" @analyzer,
  "fathom/sql/syntax" @syntax,
  "moonbitlang/core/debug" @debug,
}
```

**`incremental/moon.pkg` 应声明（D-04/D-21 单向纪律）：** `pkgtype(kind: "library")`，import = `"fathom/sql/source" @source` + `"fathom/sql/syntax" @syntax` + `"fathom/sql/parser" @parser`。**永不反向**（parser 永不 import incremental）；不 import api/lexer/dialect（`lex_with_limit` 经 parser 内部路径复用，不直接依赖 lexer 面）。测试用 `incremental_test.mbt` 另加 `for "test"` 的 `@mtest` import（仿 test/moon.pkg）。

### `incremental/edit.mbt`（model，分支 B contingency）

**Analog:** `source/source.mbt:6-53` 的 `Span`/`SpanError`/`SourceText`——类型形状 + `checked` 构造 + enum error 三件套

**既有 span 类型 + checked 构造（source/source.mbt:8-31 verbatim）：**
```moonbit
pub struct Span {
  pub start_byte : Int
  pub end_byte : Int
}

pub enum SpanError {
  OutOfBounds(start_byte~ : Int, end_byte~ : Int, source_length~ : Int)
  Reversed(start_byte~ : Int, end_byte~ : Int)
}

pub fn Span::checked(start_byte : Int, end_byte : Int, source_length : Int) -> Result[Span, SpanError] {
  if start_byte < 0 || end_byte < start_byte || end_byte > source_length {
    if end_byte < start_byte {
      Err(Reversed(start_byte~, end_byte~))
    } else {
      Err(OutOfBounds(start_byte~, end_byte~, source_length~))
    }
  } else {
    Ok({ start_byte: start_byte, end_byte: end_byte })
  }
}
```

**`edit.mbt` 应仿：** `Edit` 结构（`start_byte`/`end_byte`/`replacement : Bytes` 或等价）+ `EditError` enum + `Edit::checked` 构造（复用 `Span::checked` 边界校验——research 明确 `Span::checked` 已有受测实现，不手写越界检查）。**这是分支 B 的显式前置缺口**：`source/` 当前无任何 `Edit`/`Revision` 类型（grep 零命中，research [VERIFIED]）；放 `source/` 还是 `incremental/` 由依赖方向决定（Open Question 3）——仅增量消费则放 `incremental/`。

### `incremental/incremental.mbt`（service，分支 B contingency）

**Analog:** `parser/parser.mbt:4275` `parse_with_limits_context`（Document 生产入口）+ `lexer/lexer.mbt:428` `lex_with_limit`（bounded relex）+ `parser/parser.mbt:97-104` `ParsedDocument`（Document 形状）

**Document 形状（parser/parser.mbt:97-104 verbatim）：**
```moonbit
pub struct ParsedDocument {
  pub source : @source.SourceText
  pub mode : ParseMode
  pub root : @syntax.SyntaxNode
  pub diagnostics : Array[ParserDiagnostic]
  pub valid : Bool
  pub recovered : Bool
}
```
→ D-05 库 API `parse_incremental(prev : Document, edits : Array[Edit]) -> Document` 的 `Document` 直接复用此形状（或等价 `@syntax.SyntaxNode` + `@source.SourceText` 对）。

**Bounded relex 入口（lexer/lexer.mbt:428-430 verbatim）：**
```moonbit
pub fn lex_with_limit(source : @source.SourceText, context : @dialect.DialectContext, max_tokens : Int) -> @token.TokenStream
```
→ 对"编辑区间 + 必要词法上下文（引号字符串/注释/方言字面量）"重 lex 时复用，非整文档重 lex。

**`incremental.mbt` 应仿：** 顶层 `parse_incremental` 返回 `ParsedDocument` 形状；核心循环 = 编辑区间重 lex（`lex_with_limit`）+ 有界 re-parse + **span-overlap invalidation**（与编辑区间重叠的节点失效，绝不 "span unchanged ⇒ node valid"，Pitfall 5/D-04）；span 重映射基于 `SourceText::line_index`/byte-offset（source.mbt:33-53）。**SC2 硬不变量**：`print_lossless(parse_incremental(x)) == print_lossless(parse_full(x))` 对每个 edit fixture（`print_lossless(root : @syntax.SyntaxNode, source : @source.SourceText) -> Bytes`，printer/printer.mbt:28-31）。可选自检 `ParseResult::all_spans_in_bounds`（api.mbt:919，SC3 类校验）。

### `incremental/incremental_test.mbt`（test，分支 B contingency）

**Analog:** `parity/baseline_test.mbt:351-354`（`@test.T::snapshot` 机制 + helper）+ `test/source_test.mbt`（round-trip 断言）

**既有 snapshot helper（parity/baseline_test.mbt:351-354 verbatim）：**
```moonbit
fn snapshot_test(t : @test.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}
```
调用形状（baseline_test.mbt:359-361）：
```moonbit
test "parse 2.1-industrial strict" {
  let t = @test.Test("parse 2.1-industrial strict")
  snapshot_test(t, parse_json("2.1-industrial", "strict"), "2.1-industrial.2.1.strict.json")
}
```
快照命名约定：`<fixture>.<profile>.<mode>.json`（分支 B 可仿 `edit-<fixture>.doris-4.x.json`）；生成路径 `moon test --update --package incremental`，之后无 `--update` 时任何字节差异即失败。

**`incremental_test.mbt` 应仿：** 每个 edit fixture（insert/delete/replace，**含字符串字面量与注释内部**的编辑——Pitfall 5）构造 `(original, edited)` bytes 对 → `full = parse_full(edited)`（仿 test/source_test.mbt `parse_editor`）+ `inc = parse_incremental(parse_full(original), [edit])` → 断言 `print_lossless(inc.root, inc.source) == print_lossless(full.root, full.source)`（SC2）。白盒 shape 仿 source.mbt 内联 `test` 块 + 黑盒经 `@api` 两路均可。

---

## Shared Patterns

### 内嵌 fixture 纪律（Runtime never reads disk）
**Source:** `parity/baseline_test.mbt:7-9` + `test/corpus_test.mbt:9`
**Apply to:** `bench/build_editor_scale.mbt`、`incremental/incremental_test.mbt`
```moonbit
/// Runtime never reads disk — raw bytes are embedded at authoring time from
/// corpus/doris-{2.1,3.x,4.x}/*.sql
```
corpus 语句在 authoring 时内嵌为 bytes 字面量；bench 运行时不依赖磁盘文件（可复现基准）。

### 单向依赖纪律（D-21/D-04）
**Source:** `parser/parser.mbt`（被 import 面）+ `lineage/moon.pkg`（最小依赖面先例）
**Apply to:** `incremental/moon.pkg`、`bench/moon.pkg`
- `incremental/` 只 import `source` + `syntax` + `parser`，永不反向（parser 永不 import incremental）。
- `bench/` 只 import `api` + `parser` + `source`（被测面），不 import `incremental/`。
- `api/` 永不 import `incremental/`（分支 B 交付面是库 API，无 wire/CLI/LSP 新导出，D-05）。

### SC2 不变量比对（print_lossless Bytes 相等）
**Source:** `printer/printer.mbt:28-31`
**Apply to:** `incremental/incremental_test.mbt`（分支 B 每个 edit fixture）
```moonbit
pub fn print_lossless(root : @syntax.SyntaxNode, source : @source.SourceText) -> Bytes
```
增量输出与全量输出以 Bytes 相等为硬不变量（等效于无损 round-trip `print_lossless(parse(x)) == x` 的增量版）。

### 跨目标 parity 纪律（分支 B 若适用）
**Source:** `parity/moon.pkg`（executable + `options(targets:)`）+ `parity/parity_test.mbt`（`fixture_source`/`run_fixture` 模式）
**Apply to:** `incremental/incremental_test.mbt` + `08-BENCHMARK.md`
三目标（native/js/linear-wasm）字节一致（Phase 12 D-03/D-08 纪律）；bench 的 js/wasm 记录为"若可行补充"（D-01）。

### 证据驱动 descope（D-17 诚实 provenance）
**Source:** `05-01-PLAN.md:25-26,60-66,98`（REQUIREMENTS + STATE 更新先例）+ `STATE.md:269-281`（Deferred Items 表）
**Apply to:** `.planning/REQUIREMENTS.md` / `.planning/ROADMAP.md` / `.planning/STATE.md` / `08-BENCHMARK.md`
任何 A/B 结论都必须有可复现数据落库（fixture/规模/median/p95/结论五要素），绝不静默 descope。

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `bench/bench.mbt` 的 `@bench` attribute 用法 | harness | request-response | 仓库内**零 `@bench`/`moon bench`/`keep()` 先例**（grep 零命中，research Pitfall 1）；STACK.md:231 的核验针对官方文档非 pinned `moon 0.1.20260724`。planner 应把"执行首步 = 最小 `@bench` 探针"设为 Wave 0 第一动作；语法细节以探针结果为准 |
| `incremental/edit.mbt` 的 `Edit`/`Revision` 类型 | model | transform | `source/` 当前无任何 Edit/Revision 类型（grep 零命中）；类型形状仿 `Span`/`SpanError`（source.mbt:8-31）的 checked 构造 + enum error 模式 |
| `08-BENCHMARK.md` | docs | — | 仓库无既有 benchmark 证据文档；五要素（fixture/规模/median/p95/结论）由 D-03 + Pitfall 4 明文规定，结构仿 `CORPUS-REPORT.md`/`07-VERIFICATION.md` |

---

## Metadata

**Analog search scope:** `/opt/source/Fathom`（api/ parser/ source/ syntax/ printer/ lexer/ lint/ fingerprint/ lineage/ test/ parity/ corpus/ .planning/）
**Files scanned:** ~40（moon.pkg ×11、api.mbt、parser.mbt、source.mbt、syntax.mbt、printer.mbt、lexer.mbt、test/source_test.mbt、test/lint_test.mbt、parity/parity_test.mbt、parity/baseline_test.mbt、corpus/ 三目录、corpus/manifest.tsv、STATE.md、REQUIREMENTS.md、ROADMAP.md、06-PATTERNS.md、05-01-PLAN.md）
**Pattern extraction date:** 2026-08-12
**Verify-at-execution:** `@bench` attribute + `moon bench --target native --output-json` + `keep()` 在 pinned `moon 0.1.20260724`（moon.mod:5-8）上的可用性与精确语法（Pitfall 1 / Assumptions A1-A2）
