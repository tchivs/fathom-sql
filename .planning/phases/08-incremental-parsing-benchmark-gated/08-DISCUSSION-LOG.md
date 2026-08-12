# Phase 8: Incremental Parsing (Benchmark-Gated) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-11
**Phase:** 8-Incremental Parsing (Benchmark-Gated)
**Areas discussed:** Benchmark gate execution, bottleneck threshold, gate-result branch, incremental scope (contingency), delivery surface (contingency)

**Mode:** `--auto` — 全部灰区由 Claude 依据既有决策链自动选择推荐项，无用户交互。

---

## 基准门禁执行

| Option | Description | Selected |
|--------|-------------|----------|
| bench/ 包 + corpus + editor-scale 合成 | 新建 `bench/` 包（`@bench`），测量整文档 parse 延迟（native median/p95），输入来自 corpus + 合成 ≥100KB editor-scale 文档；`moon bench --target native --output-json` | ✓ |
| 仅现有小文件 | 只用 corpus 小文件，无 editor-scale 合成 | |
| 跳过 benchmark | 直接假设 descope | |

**User's choice:** bench/ 包 + editor-scale 合成（推荐默认）— 研究指定 `@bench`+`moon bench`；SC1 要求 "benchmarks demonstrate"。
**Notes:** js/wasm 若可行补充记录；门禁先行，绝不先实现后补测量。

## 瓶颈阈值

| Option | Description | Selected |
|--------|-------------|----------|
| 50ms median（editor-scale）或超线性 | ≥100KB 文档 reparse median > 50ms（编辑器响应预算），或延迟对规模超线性增长 → 判为瓶颈 | ✓ |
| >16ms | 更严苛帧预算 | |
| >500ms | 更宽松 | |

**User's choice:** 50ms median / 超线性（推荐默认）— 对齐 ARCHITECTURE "full-document parse is often adequate for short SQL files" 规模假设；可辩护的编辑器响应预算。

## 门禁结果分支

| Option | Description | Selected |
|--------|-------------|----------|
| 证据驱动分支 | 分支 A：reparse 足够快 → descope EDIT-01 并记录 `08-BENCHMARK.md` 证据（REQUIREMENTS/ROADMAP/STATE 更新，零增量代码）；分支 B：明显瓶颈 → 实现 `incremental/` | ✓ |
| 无条件实现 | 不做门禁直接实现 | |
| 无条件 descope | 不做门禁直接放弃 | |

**User's choice:** 证据驱动分支（推荐默认）— SC1 明文允许 "descoped with the benchmark evidence documented"；plan 首个 tracer 必为 benchmark。

## 增量解析实现边界（分支 B contingency）

| Option | Description | Selected |
|--------|-------------|----------|
| 本地 CST 复用 | `incremental/` 只 import source+syntax+parser；bounded reparse（编辑区间+词法上下文）；span-overlap invalidation；`print_lossless(parse_incremental(x)) == print_lossless(parse_full(x))` 每个 edit fixture | ✓ |
| 全增量引擎 | tree-sitter 式 lexer+parser 引擎 | |

**User's choice:** 本地 CST 复用（推荐默认）— STACK.md 反面明文；Pitfall 5 span-overlap 预防。

## 交付面（分支 B contingency）

| Option | Description | Selected |
|--------|-------------|----------|
| 库 API + 快照 + parity | `parse_incremental(prev, edits)` 库面 + `_test.mbt` 快照 + 三目标 parity；无 wire/CLI/LSP 新面 | ✓ |
| wire + CLI | 新增导出与子命令 | |

**User's choice:** 库 API（推荐默认）— 内部优化，LSP 由 TOOL-FUTURE 后续消费。

---

## Claude's Discretion

`--auto` 模式全部灰区由 Claude 依据既有决策链选择推荐项（研究 SUMMARY/ARCHITECTURE/STACK/PITFALLS 的 EDIT-01 门禁设计、Pitfall 5/6、ARCHITECTURE 规模假设、REQUIREMENTS SC1/SC2/SC3），无用户自由输入。

## Deferred Ideas

- 增量分析/血缘/Lint 消费 → TOOL-FUTURE-01
- LSP 增量同步消费 → TOOL-FUTURE-01
- 跨库结构化重构 → EDIT-02
- tree-sitter 式全增量引擎 → 反面（本地 CST 复用）
