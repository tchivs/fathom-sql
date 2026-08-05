# Phase 3: Formatting and Safe Edits - Context

**Gathered:** 2026-08-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 3 delivers deterministic, configurable canonical formatting distinct from exact lossless replay: a `FormatOptions`-driven formatter over the lossless CST that preserves comments, hints, and trivia while rewriting keyword case, indentation, line width, comma style, newline style, and trailing-newline policy — plus a safe `doris-sql format` CLI over file/stdin with documented exit codes. Unsafe transformations on error trees are refused with structured errors; idempotence and reparseability are tested contracts.

</domain>

<decisions>
## Implementation Decisions

### 格式化 API 与配置形态
- **D-25:** 配置形态为 `FormatOptions` 结构体(new 构造器 + 字段),沿用 Phase 1 `ParseOptions` 模式,不做字符串/JSON 配置解析。
- **D-26:** 配置字段仅限 FMT-02 的 6 项:keyword case、indent、line width、comma style、newline style、trailing newline;不增加额外配置项。
- **D-27:** 独立 `formatter/` moon 包消费无损 CST;`printer/` 保持纯无损 replay 不动,`print_lossless` 契约不变。
- **D-28:** keyword case 在 token 级实现:只重拼写关键字 token 文本,trivia、注释、提示词(hint)文本原样保留。

### 默认格式与策略
- **D-29:** 默认 keyword case 为 UPPERCASE(SQL 惯例,与 Doris 文档示例一致)。
- **D-30:** 默认缩进 2 空格,默认行宽 100 列。
- **D-31:** 默认 comma 风格为 trailing comma(多行列表)。
- **D-32:** 换行风格跟随输入(`\r\n` 输入保留 `\r\n`,默认 `\n`);trailing newline 默认补齐一个(输入无 trailing newline 时补,有则保留)。

### 安全与幂等契约 (FMT-03)
- **D-33:** 含 error/missing/skipped 节点的树**拒绝格式化**:返回结构化错误(含诊断),绝不对 error 树静默输出格式化结果。
- **D-34:** `format(format(x)) == format(x)` 对全部 corpus fixtures 与畸形/恢复输入测试,作为 CI 契约。
- **D-35:** 对支持输入,格式化输出必须重新解析成功且无新增诊断,测试断言。
- **D-36:** trivia/hint 为 token 级保留;格式器只重排 token 间空白与换行,永不移动注释文本。

### CLI 交付 (FMT-04)
- **D-37:** `doris-sql format` 为 native 可执行薄层(文件/stdin 输入),调用 api core,不在 CLI 实现格式逻辑。
- **D-38:** CLI 只做 IO/参数解析/退出码;格式与诊断逻辑全在 core;与 Phase 4 LSP 共享同一 core 入口。
- **D-39:** exit codes:0=成功;1=解析失败或格式化拒绝;2=用法错误。
- **D-40:** CLI 通过 moon test 集成测试驱动(覆盖文件/stdin/退出码/拒绝路径),非仅手工验证。

### Claude's Discretion
- 具体格式化算法(换行决策、子句缩进层级)、formatter 内部函数分解、CLI 参数细节(如 `--keyword-case` 覆盖、`--no-trailing-newline`)由 planner 决定,前提是上述 D-25..D-40 契约被保留。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project and scope
- `.planning/PROJECT.md` — core value, MoonBit constraint, lossless CST decision, formatter scope.
- `.planning/REQUIREMENTS.md` § Formatting and Safe Edits — locked FMT-01..FMT-04 acceptance requirements for this phase.
- `.planning/ROADMAP.md` § Phase 3: Formatting and Safe Edits — phase goal, dependencies, requirements, and success criteria.
- `.planning/STATE.md` — current project position and accumulated cross-phase decisions.

### Prior phase context
- `.planning/phases/02-doris-completeness-and-corpus/02-CONTEXT.md` — locked D-09..D-24 (DML/DDL surface the formatter must handle; corpus fixtures it must format).
- `.planning/phases/01-core-kernel/01-CONTEXT.md` — locked D-01..D-08 (byte coordinates, dual mode, lossless CST, print_lossless contract).
- Prior PATTERNS.md / RESEARCH.md / SUMMARY.md files in `phases/01-core-kernel/` and `phases/02-doris-completeness-and-corpus/` — module conventions, corpus shapes, test conventions.

### Existing code (delivered by Phases 1-2)
- `printer/printer.mbt` — `print_lossless` exact replay (MUST NOT be altered by formatter work).
- `syntax/syntax.mbt` — lossless CST node/leaf model (formatter input).
- `token/token.mbt` — keyword classification (`is_reserved_word` etc.), `introduced_profile` gating.
- `api/api.mbt` — `parse`/`ParseResult` boundary; `FormatOptions`-style additions land here or in `formatter/`.
- `corpus/` — manifest.tsv (44 rows), coverage.tsv, keywords.tsv, fixture SQL files (formatter idempotence corpus).
- `test/` — existing test conventions (parse_strict/parse_editor helpers, oracle tests).

### Research and technical evidence
- `.planning/research/SUMMARY.md`, `PITFALLS.md`, `ARCHITECTURE.md`, `FEATURES.md` — formatter-related contracts (idempotence, comment attachment, error-tree refusal).
- `.planning/research/STACK.md` — MoonBit v0.10.5 evidence; executable package conventions for CLI (`pkgtype(kind: "executable")`, `moon build --target native --release`).

No separate SPEC.md or ADR exists for Phase 3; the project, research, and prior-phase documents above are the canonical requirements and evidence.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `print_lossless`(printer.mbt)与 lossless CST 模型(syntax.mbt):formatter 的输入与验证底座。
- `ParseResult`/`PrimitiveNode`/`PrimitiveDiagnostic`(api.mbt):CLI 诊断输出可直接复用。
- `ParseOptions` 构造器模式:FormatOptions 直接照搬。
- corpus manifest + 44 fixtures:幂等与重解析契约的测试语料。
- MoonBit executable 包:CLI 用 `pkgtype(kind: "executable")`(moon.pkg DSL),参考 STACK.md。

### Established Patterns
- 构造器 + `default()` + 字段访问器(ParseLimits/ParseOptions 先例)。
- 每任务 verify 命令(moon test)与 oracle 测试(print_result==raw)。
- 提交原子化:每任务一个 commit,feat(03-xx) 前缀。

### Integration Points
- 新 `formatter/` 包依赖 `syntax/`(+`token/` 做 case 判定),禁止反向依赖。
- CLI 可执行包依赖 `api/`(或 `formatter/`),提供 `doris-sql format`。
- api 层可能新增 `format_text`(若 planner 决定放 api);否则 CLI 直连 formatter。
- Phase 4 LSP 将复用同一 format core(格式化 edits 需求 ECO-02)。

</code_context>

<specifics>
## Specific Ideas

- 保持项目差异化:`format(format(x)) == format(x)` 与 `parse(format(x))` 无新诊断是核心契约,任何格式化策略不得破坏注释/提示词附着。
- 格式器输出的新行/缩进必须保持 CST span 语义——格式化结果重新 parse 后仍是合法 CST。
- CLI 是 Phase 4 LSP/Web 的探路者:保持薄层、core 共享。
- 拒绝路径必须结构化:CLI 非零退出 + stderr 诊断,方便自动化消费。

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within the Phase 3 boundary. LSP formatting edits, Wasm/JS format facade, and editor integrations remain in Phase 4; comment-aware reflow (moving comments between positions) and incremental formatting remain v2.

</deferred>

---

*Phase: 3-Formatting and Safe Edits*
*Context gathered: 2026-08-04*
