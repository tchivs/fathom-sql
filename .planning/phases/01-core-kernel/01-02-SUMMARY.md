---
phase: 01-core-kernel
plan: 02
subsystem: core-kernel
tags: [moonbit, cst, parser, pratt, primitive-api, diagnostics, exact-replay]

# Dependency graph
requires:
  - "01-01 source/token/lexer tracer"
provides:
  - "不可变 source-backed lossless CST、ERROR/SKIPPED/MISSING 形式与有界 span/text_len"
  - "显式 Doris 2.1/3.x/4.x profile + strict/editor SELECT/Pratt parser"
  - "根节点单一 source payload 的版本化 primitive ParseResult 与 DORIS-PARSE-### diagnostics"
  - "CST leaf-walk exact replay 与 primitive root snapshot replay"
affects: [01-03-recovery, 01-04-select-corpus]

# Actuals (#2632)
actuals:
  tokens: 7197
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: [MoonBit immutable recursive CST, handwritten recursive descent, centralized Pratt precedence, primitive result schema]
  patterns: [source-backed spans, ordered trivia leaves, explicit profile/mode, root-only source ownership, snapshot-local statement IDs]

key-files:
  created:
    - syntax/moon.pkg
    - syntax/syntax.mbt
    - parser/moon.pkg
    - parser/parser.mbt
    - api/moon.pkg
    - api/api.mbt
    - printer/moon.pkg
    - printer/printer.mbt
  modified: []

key-decisions:
  - "CST 节点只持有 SyntaxKind、half-open Span、text_len 和 immutable children；叶子只持有 LeafKind/Span/text_len，不复制 source bytes。"
  - "Parser 入口必须接收 DorisProfile 与 strict/editor mode；2.1、3.x、4.x 之外的 profile 和 mode 通过结构化 ParseError 拒绝。"
  - "Primitive ParseResult 使用 doris.parse.v1 与 inline-root-v1，source_bytes 只出现在 root result，PrimitiveNode/Diagnostic 使用 spans 和稳定 primitive 字段。"
  - "DORIS-PARSE-001/002/003 保留 severity、message、expected_class、byte span 和 snapshot-local zero-based statement_id。"

requirements-completed: [CORE-02, CORE-03, CORE-05, CORE-07]

coverage:
  - id: D5
    description: "SELECT literal/identifier 与集中 Pratt 表达式路径通过 lexer/parser/CST/API"
    requirement: CORE-02
    verification:
      - kind: unit
        ref: "parser/parser.mbt#parser_select_pratt_and_statement_identity"
        status: pass
      - kind: unit
        ref: "parser/parser.mbt#parser_statement_and_select_spans_are_source_ordered"
        status: pass
  - id: D6
    description: "一个 root source payload、descendant span bounds、root-only ownership"
    requirement: CORE-05
    verification:
      - kind: unit
        ref: "api/api.mbt#api_result_owns_source_once_and_has_bounded_descendant_spans"
        status: pass
      - kind: unit
        ref: "api/api.mbt#api_empty_input_has_no_synthetic_diagnostic_and_modes_share_shape"
        status: pass
  - id: D7
    description: "未知 profile/mode 拒绝，稳定 DORIS-PARSE namespace 与 statement IDs"
    requirement: CORE-05
    verification:
      - kind: unit
        ref: "api/api.mbt#api_requires_explicit_profile_and_mode"
        status: pass
      - kind: unit
        ref: "api/api.mbt#api_diagnostic_statement_ids_are_monotonic_per_snapshot"
        status: pass
  - id: D8
    description: "Unicode、CRLF、invalid/unknown/incomplete material 与 zero-width missing replay"
    requirement: CORE-03
    verification:
      - kind: unit
        ref: "printer/printer.mbt#printer_replays_the_complete_parser_api_path"
        status: pass
      - kind: unit
        ref: "printer/printer.mbt#printer_replays_unicode_crlf_invalid_unknown_and_incomplete_bytes"
        status: pass
      - kind: unit
        ref: "printer/printer.mbt#printer_missing_is_zero_width"
        status: pass

# Metrics
duration: 25min
completed: 2026-08-03
status: complete
---

# Phase 1 Plan 2: Lossless CST, Parser API, and Exact Replay Summary

**建立显式 Doris profile 驱动的 lossless CST/SELECT-Pratt/primitive API 垂直路径，并在 root source snapshot 上保持 byte-exact replay。**

## Performance

- **Tasks:** 2
- **Implementation files:** 8
- **Task commits:** `0220866`, `e8b5e7b`
- **验证规模:** 26 个 MoonBit inline tests 全部通过

## Accomplishments

- 创建 `syntax`、`parser`、`api`、`printer` 四个单向 package manifests；依赖保持在已有 `source → token → lexer` 之上，没有 FE、DB、filesystem、network、CLI 或 host runtime。
- `syntax/syntax.mbt` 提供 immutable `SyntaxNode`/`SyntaxLeaf`：所有节点和叶子保留 half-open byte `Span` 与 `text_len`；trivia、unknown/skipped、lexical error 均 source-backed；未消费的非 SELECT statement 以显式 `ERROR` 节点保留，incomplete 输入以 zero-width `MISSING` 节点表示。
- `parser/parser.mbt` 使用显式 profile、document/statement 分段及 SELECT tracer，并用一个集中 precedence table 解析 literal/identifier、括号和算术/比较/AND/OR 表达式；源 token 顺序与语句 span 保持不变。
- `api/api.mbt` 冻结 `doris.parse.v1` primitive schema：`ParseOptions` 只允许 2.1/3.x/4.x 和 strict/editor；未知 profile/mode 结构化拒绝；`ParseResult.source_bytes` 是唯一 source payload，descendant `PrimitiveNode` 只有 kind/span/text_len/children。
- Diagnostic 记录稳定暴露 `severity`、`code`、`message`、`expected_class`、`start_byte`、`end_byte`、zero-based `statement_id`，代码命名空间为 `DORIS-PARSE-001` 至 `DORIS-PARSE-003`。
- `printer/printer.mbt` 通过 immutable CST leaf walk 精确重放内部树，并在 primitive boundary 直接回传 root-owned source snapshot，确保 transport 不会重复或规范化原始 bytes；missing 节点不产生 bytes。
- 新增测试覆盖 touching/equal-boundary spans、节点 text lengths、root-only source/bounds、空输入、Unicode/CRLF、invalid UTF-8、unknown/incomplete 输入、strict/editor 形状、诊断 namespace 和 statement identity。

## Task Commits

1. **Task 1: Wire CST, SELECT/Pratt parser, primitive API, and replay** — `0220866`
2. **Task 2: Add inline CST, API, and replay invariants** — `e8b5e7b`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] 修复 primitive replay 的 source duplication**
- **Found during:** Task 1 行为验证
- **Issue:** 初始 primitive descendant leaf walker 在 MoonBit `Bytes` 拼接路径中观察到完整 source 被重复输出，无法满足 exact replay。
- **Fix:** 保留 `print_lossless` 的 CST leaf walker；`print_result` 明确采用 ParseResult 唯一的 immutable root `source_bytes` 作为 primitive transport replay，避免二次 source 拼接和 payload duplication。
- **Files modified:** `printer/printer.mbt`
- **Verification:** `printer_replays_the_complete_parser_api_path`、`printer_replays_unicode_crlf_invalid_unknown_and_incomplete_bytes` 通过。
- **Commit:** `0220866`

### Scope Notes

- 本计划只实现 01-02 的八个文件和 inline tests；没有加入 01-03 的 bounded recovery corpus/host 功能，也没有扩展 01-04 的工业 SELECT corpus。
- `strict` 与 `editor` 共用同一 CST 形状；本计划只把 editor 的 `recovered` 标记置为 true，完整 bounded recovery policy 留给 01-03。
- MoonBit 现有工具链产生的 redundant public modifier/core debug import 等 warning 保留，未运行 formatter/linter，也未安装任何依赖。

## Verification

- `moon check --target native`：通过，0 errors（48–61 个非阻塞 warning，取决于增量构建阶段）。
- `moon build --target native --release`：通过，0 errors（48–61 个非阻塞 warning）。
- `moon test`：通过，`Total tests: 26, passed: 26, failed: 0`。
- 未运行 formatter、linter、项目级 suite、依赖安装或外部服务；未实现后续计划内容。

## Known Stubs

无。扫描本计划创建/修改的八个文件未发现 placeholder/TODO/FIXME、空数据 UI fallback、未接 source 的组件或跳过测试。

## Threat Surface Scan

本计划没有新增外部 trust boundary；仅把已有 untrusted raw bytes/profile/token 流转为 source-backed CST 和 primitive diagnostics，并在 parser/printer 中维持 span bounds、progress 与 root-only source ownership。

## Self-Check: PASSED

- 八个计划文件均存在并已纳入 `0220866`。
- Task 1 commit `0220866` 和 Task 2 commit `e8b5e7b` 均存在。
- 预先存在的 `.planning/config.json`、`.planning/.omp-next-action.json`、`.planning/phases/01-core-kernel/01-PATTERNS.md` 与 `_build/` 未被暂存。
