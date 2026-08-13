# Phase 8: Incremental Parsing (Benchmark-Gated) - Context

**Gathered:** 2026-08-11
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段交付 **EDIT-01（基准门控的增量解析）**：**仅当** `moon bench` 证明整文档重解析对 editor-scale 文档是可测的延迟瓶颈时，交付有界增量解析与定向 CST 重构；**否则以证据 descope 并记录**（ROADMAP Phase 8 SC1 明文）。无论结果如何，本阶段都产出**可复现的 benchmark 证据**与明确的决策记录。

**Requirements:** EDIT-01（`.planning/REQUIREMENTS.md` §Incremental Editing）

**不在范围：** tree-sitter 式全增量引擎（本地 CST 复用，D-02）、增量分析/血缘/Lint（EDIT-01 只覆盖 parse+CST）、LSP 增量同步消费（`incremental/` 就绪后由 TOOL-FUTURE 后续消费）、wire/CLI 新导出（本阶段为库面内部优化）、跨库重构（EDIT-02）。

</domain>

<decisions>
## Implementation Decisions

### 基准门禁执行（EDIT-01 门禁本体）
- **D-01:** 新建 `bench/` MoonBit 包（`@bench` attribute），测量**整文档重解析延迟**：以仓库 `corpus/` 既有 Doris fixture 为基础，**合成/拼接 editor-scale 文档**（≥100KB 目标，覆盖典型编辑会话规模；含注释/空白/多语句/复杂 SELECT+DDL），记录 native 的 median/p95 延迟与输入规模关系。命令：`moon bench --target native --output-json`（`--target js`/`wasm` 若可行补充记录）。**门禁先行**——任何增量解析实现决策必须以 benchmark 数据为据，绝不先实现后补测量（研究 Pitfall 6 / EDIT-01 gated）。**Reversibility:** reversible — bench/ 包是独立测试面。
- **D-02:** "Measurable latency bottleneck" 判定阈值（EDIT-01 门禁）：**editor-scale 文档（≥100KB）整文档重解析 median > 50ms**（编辑器交互响应预算的可辩护上界；对齐 ARCHITECTURE "full-document parse is often adequate for short SQL files" 的规模假设），**或** 观察到延迟对输入规模呈超线性增长（O(n²) 迹象）。低于阈值 → 判为"reparse 足够快"，**descope EDIT-01 并记录证据**。**Reversibility:** one-way — 阈值决定 EDIT-01 去留；若后续需回改需重跑 benchmark 并迁移记录。

### 门禁结果分支
- **D-03:** 门禁结果走**证据驱动分支**：
  - **分支 A（descope）**——reparse 足够快：在 `08-BENCHMARK.md` 记录 benchmark 证据（fixture、规模、median/p95、结论），更新 REQUIREMENTS.md/ROADMAP/STATE 将 EDIT-01 标记为 **descoped with evidence**（SC1 允许："or the requirement is descoped with the benchmark evidence documented"），**不写任何增量解析代码**。
  - **分支 B（实现）**——reparse 明显瓶颈：新建 `incremental/` 包（D-04），实现有界增量解析 + 定向 CST 重构，并以 `print_lossless(parse_incremental(x)) == print_lossless(parse_full(x))` 为硬不变量（SC2/SC3）。
  - **本阶段 plan 必须把 benchmark 放在首个 tracer**，让结果决定后续 plan 是 descope 记录还是增量实现。**Reversibility:** one-way — descope 决策记录在 REQUIREMENTS/ROADMAP；改回需新证据。

### 增量解析实现边界（分支 B contingency，D-04）
- **D-04:** 若实现：`incremental/` 独立库，**只 import source + syntax + parser**（复用既有无损 CST 与 source revisions/LineIndex 基础，D-21 纪律延续）；**bounded reparse**——对编辑区间 + 必要词法上下文（引号字符串/注释/方言字面量）重 lex/re-parse，span-overlap invalidation（与编辑区间重叠的节点失效，绝不 "span unchanged ⇒ node valid" 假设，Pitfall 5）；**不做 tree-sitter 式全增量引擎**（本地 CST 复用，STACK.md 反面）。**Reversibility:** one-way — `incremental/` 是新的公共库边界；若后续改为全增量引擎需迁移。

### 交付面（分支 B contingency，D-05）
- **D-05:** 若实现：交付面为**库 API**（`parse_incremental(prev : Document, edits : Array[Edit]) -> Document` 或等价）+ `_test.mbt` 快照（每个 edit fixture 断言 `print_lossless(incremental) == print_lossless(full)`）+ parity（三目标字节一致，若适用）。**不新增 wire 导出/CLI/LSP 面**（内部优化，LSP 在 TOOL-FUTURE 消费）。**Reversibility:** costly — 库 API 形状发布后影响调用方。

### Claude's Discretion
（`--auto` 模式：全部灰区由 Claude 依据既有决策链——研究 SUMMARY/ARCHITECTURE/STACK/PITFALLS 的 EDIT-01 门禁设计（`@bench`+`moon bench`、Pitfall 5 span-overlap、Pitfall 6 免过早复杂）、ARCHITECTURE "full-document reparse is often adequate" 规模假设、REQUIREMENTS SC1/SC2/SC3——选择推荐项；D-01..D-05 覆盖全部灰区，无 "you decide"。）

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 需求与路线图
- `.planning/ROADMAP.md` §Phase 8 — Goal / Success Criteria（SC1：`moon bench` 证明瓶颈或证据 descope；SC2：`print_lossless(parse_incremental(x)) == print_lossless(parse_full(x))` 每个 edit fixture；SC3：span-overlap invalidation、无 stale spans/trivia）
- `.planning/REQUIREMENTS.md` §Incremental Editing — EDIT-01 全文（benchmark-gated：only when `moon bench` demonstrates measurable latency bottleneck；`print_lossless(parse_incremental(x)) == print_lossless(parse_full(x))`）
- `.planning/PROJECT.md` — Core Value、Constraints、Key Decisions（无损 CST 是核心差异化；增量解析不得破坏 round-trip）

### 研究（设计依据）
- `.planning/milestones/v1.0-research/SUMMARY.md` §Stack/Features/Architecture/Pitfalls — EDIT-01（VERY HIGH, benchmark-gated）：`@bench` + `moon bench --target native|js|wasm|all`；复用 source revisions + LineIndex；span-overlap invalidation；`parse_incremental == parse_full` invariant；`incremental/` 仅当 benchmarks 通过；**先 benchmark 后实现**
- `.planning/milestones/v1.0-research/ARCHITECTURE.md` §Guiding Boundaries/Data Flow/Phase Ordering — 无损 CST 设计为后续增量复用（green tree、immutable、source revisions）；"A full-document parse is often adequate for short SQL files" 规模假设；EDIT-01 在 Phase D（benchmark first）
- `.planning/milestones/v1.0-research/PITFALLS.md` §Pitfall 5/V3 — 增量 span invalidation/trivia 漂移（span-overlap 失效，验证 `print_lossless` 不变）；§EDIT-01 gated——仅当整文档重解析可测地失败
- `.planning/milestones/v1.0-research/STACK.md` §Benchmarks/Verdict — `@bench` attribute + `moon bench` CLI（native|js|wasm，JSON summaries）；tree-sitter 反面（本地 CST 复用）；零新增运行时依赖

### 现状代码（扩展依据）
- `source/source.mbt` — `SourceText`/`@source.Span`/`LineIndex`/版本化编辑基础（ARCHITECTURE 坐标模型；增量解析的坐标基础）
- `syntax/syntax.mbt` — 无损 CST（green/red 视图、trivia、span）
- `parser/parser.mbt` — 整文档递归下降 + Pratt 入口（`parse_with_limits_context` 等；基准门禁的被测对象）
- `api/api.mbt` `parse_document` — 现有解析入口（`@api.parse_text` 等；benchmark harness 复用）
- `corpus/` — 官方文档 fixture（benchmark 输入来源）
- 既有 `_build/`、`moon.mod` — 工具链 pin（moon 0.1.20260724）

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `source/source.mbt` `@source.Span` + `LineIndex` + source revisions：增量解析的坐标与版本基础（研究明文，ARCHITECTURE:54-67）
- `syntax/syntax.mbt` 无损 CST（immutable green tree + red/cursor views，trivia 保留）：增量复用的结构基础
- `parser/parser.mbt` 整文档解析入口：benchmark 被测对象（现状即"整文档重解析"）
- `api/api.mbt` `parse_document`：benchmark harness 可直接调用的解析路径
- `corpus/` Doris fixture：benchmark 输入的官方来源

### Established Patterns
- D-21 单向依赖纪律：新 `incremental/`（若实现）只 import source+syntax+parser，永不反向；parser 永不 import incremental
- 无损 round-trip 硬不变量：`print_lossless(parse(x)) == x`——增量解析必须保持（SC2 等价）
- 快照/golden + 三目标 parity 纪律（Phase 12 D-03/D-08）：增量输出字节一致
- 证据驱动 descope（D-17 诚实 provenance）：benchmark 数据 + 决策记录，不静默放弃
- `@bench` attribute + `moon bench`（STACK.md 核实）：基准门禁机制

### Integration Points
- 新 `bench/` 包（`@bench`）：整文档解析延迟测量，输入来自 `corpus/` + 合成 editor-scale 文档
- `incremental/` 包（仅当分支 B）：bounded reparse + span-overlap invalidation，复用 source/syntax/parser
- REQUIREMENTS.md/ROADMAP.md/STATE.md：EDIT-01 descope（分支 A）或实现记录（分支 B）
- `08-BENCHMARK.md`：benchmark 证据与门禁结论

</code_context>

<specifics>
## Specific Ideas

既有边界意图（延续 v3.0 研究链，本阶段 `--auto` 无逐条新输入）：
- EDIT-01 是 v3.0 最后一个分析需求，**explicitly benchmark-gated**（REQUIREMENTS 明文）；研究一致警告"premature incremental parsing complexity"（Pitfall 6）与 "often adequate for short SQL files"（ARCHITECTURE）
- `@bench` + `moon bench --target native|js|wasm|all` 是研究指定的门禁机制（SUMMARY §Stack）
- 若实现：复用 source revisions + LineIndex，span-overlap invalidation，`print_lossless(parse_incremental(x)) == print_lossless(parse_full(x))` 每个 edit fixture（Pitfall 5 预防）
- 诚实 descope：以可复现 benchmark 证据记录（SC1 "or the requirement is descoped with the benchmark evidence documented"），绝不静默放弃

</specifics>

<deferred>
## Deferred Ideas

- 增量分析/血缘/Lint 的增量消费 → TOOL-FUTURE-01（incremental/ 就绪后）
- LSP 增量文档同步消费 → TOOL-FUTURE-01
- 跨库/跨文件结构化重构（broad renames with cross-file updates）→ EDIT-02（未来）
- tree-sitter 式全增量引擎 → 反面（本地 CST 复用，STACK.md）

---

*Phase: 8-Incremental Parsing (Benchmark-Gated)*
*Context gathered: 2026-08-11*
