---
phase: 01-core-kernel
plan: 01
subsystem: core-kernel
tags: [moonbit, source-bytes, spans, line-index, doris-profile, lexer, trivia]

# Dependency graph
requires: []
provides:
  - "受限 raw-byte SourceText、checked half-open Span 与集中式 LineIndex"
  - "显式且仅有 2.1、3.x、4.x 的 DorisProfile 与版本元数据"
  - "保留 trivia、literal、unknown、invalid UTF-8/error bytes 的推进式 lexer"
affects: [01-02-cst-parser]

# Actuals (#2632)
actuals:
  tokens: 4931
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: [MoonBit 0.1.20260724 (5f1406a 2026-07-24)]
  patterns: [immutable source-backed byte spans, centralized line index, explicit profile metadata, progressing lossless lexer]

key-files:
  created: [moon.mod, moon.pkg, source/moon.pkg, source/source.mbt, token/moon.pkg, token/token.mbt, lexer/moon.pkg, lexer/lexer.mbt]
  modified: []

key-decisions:
  - "核心坐标统一使用原始 UTF-8 byte offset；LineIndex 只负责 byte-to-line/column，UTF-16 留给后续 host adapter。"
  - "DorisProfile 只能由 2.1、3.x、4.x 枚举值构造；字符串入口对 mysql/未知值返回 None，不做 generic fallback。"
  - "SourceText 在构造 LineIndex 前检查 max_bytes；默认 8 MiB，超限返回结构化 InputTooLarge。"
  - "MoonBit 当前 DSL 不接受计划给出的 # 注释标记，因此使用合法的 // moon version: 标记逐行保存同样的 verbatim 输出。"

patterns-established:
  - "source → token → lexer 的单向包依赖；核心没有 FE、数据库、文件系统、网络或 host 依赖。"
  - "Token 只保存 source-backed Span、profile 和稳定 diagnostic_code；raw spelling 通过 TokenStream 的 SourceText 切片恢复。"
  - "所有 lexer 分支推进 cursor；unterminated literal/comment 与 invalid UTF-8 都保留原始 span。"

requirements-completed: [CORE-01, CORE-02, CORE-03, CORE-07]

coverage:
  - id: D1
    description: "显式 Doris 2.1/3.x/4.x profile 与版本元数据，未知/mysql profile 拒绝"
    requirement: CORE-01
    verification:
      - kind: unit
        ref: "token/token.mbt#profiles_are_explicit_and_have_no_generic_fallback"
        status: pass
      - kind: unit
        ref: "token/token.mbt#profile_metadata_is_stable_and_complete"
        status: pass
    human_judgment: false
  - id: D2
    description: "raw bytes、checked spans、line starts 和 max_bytes 限制"
    requirement: CORE-02
    verification:
      - kind: unit
        ref: "source/source.mbt#source_rejects_before_snapshot_and_checks_spans"
        status: pass
      - kind: unit
        ref: "source/source.mbt#source_limits_and_adjacent_empty_spans"
        status: pass
      - kind: unit
        ref: "source/source.mbt#line_index_handles_lf_crlf_mixed_and_bom"
        status: pass
    human_judgment: false
  - id: D3
    description: "token order、trivia/literal spelling、invalid UTF-8 与 unterminated material 的 byte-exact replay"
    requirement: CORE-03
    verification:
      - kind: unit
        ref: "lexer/lexer.mbt#lexer_preserves_trivia_literals_and_invalid_bytes"
        status: pass
      - kind: unit
        ref: "lexer/lexer.mbt#lexer_replays_every_source_byte_and_keeps_unicode"
        status: pass
      - kind: unit
        ref: "lexer/lexer.mbt#lexer_retains_unterminated_quote_and_progresses"
        status: pass
    human_judgment: false
  - id: D4
    description: "纯同步离线 source/token/lexer 包及 caller-owned reentrant 状态"
    requirement: CORE-07
    verification:
      - kind: other
        ref: "moon check --target native"
        status: pass
      - kind: unit
        ref: "lexer/lexer.mbt#lexer_calls_are_reentrant_without_shared_state"
        status: pass
    human_judgment: false

# Metrics
duration: 14min
completed: 2026-08-03
status: complete
---

# Phase 1 Plan 1: Core Kernel Source Token Lexer Summary

**Pinned MoonBit source/token/lexer tracer with bounded raw-byte ownership, explicit Doris profiles, and invalid-byte-preserving lexical recovery**

## Performance

- **Duration:** 14 min
- **Started:** 2026-08-03T10:34:11Z (existing execution-state timestamp)
- **Completed:** 2026-08-03T10:47:54Z
- **Tasks:** 2
- **Files modified/created:** 8 implementation/manifest files

## Accomplishments

- 创建当前 MoonBit DSL 的 module/package scaffold，并在 `moon.mod` 合法注释中逐行记录本地 `moon version` verbatim 输出。
- 实现单一 raw-byte `SourceText`、checked half-open `Span`、集中式 `LineIndex`，默认 8 MiB 并在快照/行索引构造前返回 `InputTooLarge`。
- 实现仅接受 2.1、3.x、4.x 的 Doris profile 元数据和 source-backed token/trivia 模型。
- 实现所有扫描路径均推进的 lexer，保留 BOM、空白、LF/CRLF、注释、quoted/string literal、数字、identifier、unknown 及 invalid UTF-8/error bytes；错误码稳定为 `LEX_INVALID_UTF8`、`LEX_UNTERMINATED_COMMENT`、`LEX_UNTERMINATED_LITERAL`。
- 添加 12 个确定性 inline tests，覆盖边界 span、空输入、行尾、Unicode/emoji、profile、byte replay、invalid encoding、unterminated 输入和无共享状态。

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire pinned scaffold, source snapshot, profiles, and lexer** - `1d81533` (`feat`)
2. **Task 2: Exercise source and lexical edge invariants inline** - `f10bc07` (`test`)

## Files Created/Modified

- `moon.mod` - 当前 DSL module 声明、native 偏好及 pinned version metadata。
- `moon.pkg` - 根 library package。
- `source/moon.pkg` - source package manifest。
- `source/source.mbt` - SourceText、Span、SourceError、LineIndex 及 source tests。
- `token/moon.pkg` - token 对 source 的单向依赖 manifest。
- `token/token.mbt` - profile、metadata、TokenKind、Token、TokenStream 及 profile tests。
- `lexer/moon.pkg` - lexer 对 source/token 的单向依赖 manifest。
- `lexer/lexer.mbt` - 推进式 trivia-preserving lexer 及 lexical invariant tests。

## Decisions Made

- 保持 byte offset 为核心坐标；不在本计划引入 UTF-16、CST、parser 或 host adapter。
- 采用枚举强制显式 profile，拒绝未知和 generic MySQL fallback。
- 令 token 通过 source snapshot + Span 恢复 raw bytes，避免每个 token 复制完整 source。

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] 计划的 `# moon version:` 标记不是当前 MoonBit DSL 的合法注释**
- **Found during:** Task 1 scaffold verification
- **Issue:** `# moon version:` 会导致 `moon check` 在 `moon.mod` 解析阶段失败（Lexing error）；当前 DSL 合法注释形式是 `//`。
- **Fix:** 使用 `// moon version:` 逐行保存完全相同的两行版本输出及中间空行，并以对应 `sed` 规则进行 byte-for-byte 比较。
- **Files modified:** `moon.mod`
- **Verification:** `moon version > /tmp/fathom-moon-version`、`sed -n 's#^// moon version: ##p' moon.mod > /tmp/fathom-moon-recorded`、`cmp -s` 通过；`moon check --target native` 通过。
- **Committed in:** `1d81533`

**Total deviations:** 1 auto-fixed (Rule 3 blocking syntax correction)
**Impact on plan:** 仅调整注释语法以满足当前工具链；版本内容、顺序、空行和 pinned policy 均保留，没有引入依赖或扩大范围。

## Issues Encountered

- 当前工具链实际输出为 `moon 0.1.20260724 (5f1406a 2026-07-24)`，与文档标题 v0.10.5 不同；按计划记录实际 verbatim 输出并在 metadata 中标明 pinned official v0.10.5 line policy，没有伪造升级或安装依赖。
- `cmp -s` 直接比较 Bash process substitution 在本环境返回 `Illegal seek`；改用临时文件完成同一 byte-for-byte 比较，结果通过。
- MoonBit check 报告 14 个非阻塞 warning（redundant public modifiers、未显式 import debug）；计划要求跳过 lint/formatter，未将 warning 伪装为错误，也未引入额外依赖。

## Verification

- `moon version`：通过；记录文件与命令输出经临时文件 `cmp -s` 比较一致。
- `moon check --target native`：通过，0 errors（14 warnings）。
- `moon test`：通过，`Total tests: 12, passed: 12, failed: 0`。
- 未运行 formatter、linter、项目级大套件或包安装；核心实现未引入 FE、数据库、文件系统、网络、CLI、LSP、Wasm/JS host 依赖。

## Next Phase Readiness

Wave 1 的 source/token/lexer 原始字节契约已可供 01-02 CST/parser 计划消费：所有 token span 有界且有序，raw bytes 可从一个 SourceText 恢复，profile 必须显式选择，invalid UTF-8 和 unterminated lexical material 有稳定保留形式。

---
*Phase: 01-core-kernel*
*Completed: 2026-08-03*


## Self-Check: PASSED

- SUMMARY 文件存在。
- 任务提交 `1d81533`、`f10bc07` 与 SUMMARY 提交 `84f5955` 均可在 git 历史中找到。