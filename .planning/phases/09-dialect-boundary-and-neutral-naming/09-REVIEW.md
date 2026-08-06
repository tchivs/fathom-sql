---
phase: 09-dialect-boundary-and-neutral-naming
reviewed: 2026-08-07T04:30:00Z
depth: deep
files_reviewed: 36
files_reviewed_list:
  - dialect/dialect.mbt
  - dialect/classification.mbt
  - dialect/doris.mbt
  - dialect/flink.mbt
  - token/token.mbt
  - lexer/lexer.mbt
  - parser/parser.mbt
  - api/api.mbt
  - binding/schema.mbt
  - binding/exports.mbt
  - completion/completion.mbt
  - formatter/format.mbt
  - formatter/case.mbt
  - lsp/documents.mbt
  - lsp/handlers.mbt
  - lsp/serve.mbt
  - fathom-sql/args.mbt
  - fathom-sql/main.mbt
  - fathom-sql/run.mbt
  - fathom-lsp/main.mbt
  - parity/baseline_test.mbt
  - parity/export_smoke_test.mbt
  - parity/schema_test.mbt
  - parity/parity_test.mbt
  - parity/run_native.mbt
  - scripts/check_naming.py
  - scripts/baseline_diff.py
  - vscode/src/extension.ts
  - vscode/src/extension-contract.ts
  - web/src/main.ts
  - web/src/monaco-adapter.ts
  - jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomLanguageServerFactory.kt
  - jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomSettings.kt
  - jetbrains/scripts/source-smoke.py
  - .github/workflows/ci.yml
  - .github/workflows/fathom-native-release.yml
findings:
  critical: 0
  warning: 9
  info: 4
  total: 13
status: issues_found
---

# Phase 9: Dialect Boundary and Neutral Naming — Code Review Report

**Reviewed:** 2026-08-07T04:30:00Z
**Depth:** deep
**Files Reviewed:** 36
**Status:** issues_found

## Summary

本次评审覆盖 Phase 9 全部 27 个 commit 的产品层变更（c99ebad..HEAD）：dialect/ 新层
（Dialect/DialectContext 闭合枚举 + 116 行 Doris 分类表迁移 + 空 Flink 表）、
`parse_with_ids(raw, dialect_id, profile_id, mode_id)` 签名迁移、fathom.*.v1 wire
schema 与 fathom_*_v1 export 更名、LSP document-level DialectContext 与 D-03
stale-response 防护、fathom-sql CLI（--dialect/--profile 必选、exit 2 矩阵）、
`scripts/check_naming.py` 命名门禁与 `scripts/baseline_diff.py` 基线 diff 门禁，
以及 vscode/web/jetbrains 宿主 cutover。

整体质量高：方言路由（parse_segment 单一分支点、parse_flink_segment 显式
FATHOM-PARSE-008、无 Doris fallback）、分类表隔离（两套独立 module-level 数组、
无全局 union）、CLI exit 矩阵（Missing/Unknown/Conflicting → 2，无默认方言）、
wire schema 字段（dialect/profile/exact_release/feature_introduction）均与
D-01..D-11 决策及 approved-changes.md register 一致；命名门禁与 baseline_diff
自检在提交树上均通过（`ok: 349 product files scanned` / `ok: 213 snapshots,
0 unexpected`），快照中无遗留 `DORIS-*`/`doris.*.v1`/`doris-sql` 产物层痕迹。

发现 1 个 MAJOR（LSP initialize 与 serve_stdio CLI 工作区默认的契约缺口）、
8 个 MINOR、4 个 INFO。无 BLOCKER（无数据丢失/安全漏洞/崩溃路径；脚本与 LSP
输入处理均无注入面）。多数 MINOR 集中在基线/门禁工具的“纸面承诺 vs 实际执行”
缝隙与死代码，不影响 Phase 9 交付行为的正确性。

## Major Issues

### MA-01: LSP initialize 无条件要求 initializationOptions，serve_stdio 的 CLI 工作区默认路径不可用

**File:** `lsp/handlers.mbt:342-345`
**Issue:** `initialize_selection` 对 `initializationOptions` 的读取是无条件的：

```moonbit
let options = match object_field(params, "initializationOptions") {
  Some(options) => options
  None => return Err("initialize requires initializationOptions.dialect and initializationOptions.profile")
}
```

即使 `ServerState.default_dialect/default_profile` 已由 `serve_stdio(Some(dialect),
Some(profile))`（`fathom-sql lsp --dialect doris --profile 4.x`，run.mbt `run_lsp`）
设置，缺少 initializationOptions 的 initialize 请求仍被 -32602 拒绝，server 永不
进入 initialized。这与 09-06-PLAN.md option-a 的明文契约冲突：“workspace default
comes from initializationOptions OR serve_stdio args”（两者任一即可）；serve.mbt
注释也声明 CLI 参数作为 workspace 默认注入。当前只有发送 initializationOptions 的
宿主（VS Code、JetBrains LSP4IJ）可用；任何裸 LSP 客户端（neovim/lsp-mode、
手写 stdio 客户端）连接 `fathom-sql lsp` 均初始化失败。selection_test.mbt 只覆盖
“无默认 + 缺参”和“默认 + 冲突参数”两种情况，恰好漏掉“有 serve_stdio 默认 + 无
initializationOptions”这一设计路径。
**Fix:** 当 `initializationOptions` 缺失时，回退校验并采用 `state.default_dialect/
default_profile`（已由 CLI 校验过）；仅当两个来源都为空时才返回 MissingSelection
类错误；并补充一个 serve_stdio 默认 + 空 initializationOptions 的测试用例。
**Fixed:** commit 5ec137b

## Minor Issues

### MI-01: `ParseOptions::profile()` 对非 Doris context 静默回退 V4_X

**File:** `api/api.mbt:201-205`
**Issue:** `profile()` 在 `DorisProfile::from_id(self.dialect_context.profile_id)` 返回
None 时静默返回 `V4_X`。`DialectContext` 是 `pub(all)` 的，可在任何包直接构造
Flink/无效 profile 的 context（如 `parse_flink_not_implemented` 内部构造的
ParseOptions）；此时 `profile()`/`profile_metadata()` 报告 `4.x`，违背 D-01
“绝不静默默认”原则。当前所有公共构造器都强制 Doris 合法 profile，此回退实际不可达，
属潜在 footgun。
**Fix:** 改为返回 `DorisProfile?`/`Option`，或在非 Doris context 上显式 panic/报错，
避免一个本应不存在的值被静默捏造。
**Fixed:** commit b4e0ffb

### MI-02: CLI 对 flink 的 profile 拒绝消息具有误导性

**File:** `fathom-sql/run.mbt:146-147`（及 `args.mbt:193`）
**Issue:** `--dialect flink --profile <id>` 的 exit 2 消息是
`unknown --profile value: <id> (expected 2.1, 3.x, or 4.x)`。对 flink 方言而言，
“期望 2.1/3.x/4.x”暗示这些值可用——但 flink 在 Phase 9 拒绝**所有** profile
（A1/OQ1），用户照提示改传 `--profile 4.x` 仍会 exit 2。注册表 09-04 条目明确记录
“flink rejects every profile”，消息应如实说明。
**Fix:** `parse_error_outcome`/`usage_error_message` 在 dialect 为 flink 时输出
“flink has no released profiles yet (Phase 9)”，doris 分支保持现有文本。
**Fixed:** commit 2adbf24

### MI-03: `check_naming.py` 目录排除匹配绝对路径父目录 —— 静默零扫描盲区

**File:** `scripts/check_naming.py:89`
**Issue:**
```python
if any(part in EXCLUDED_DIRS or part in BUILD_OUTPUT_DIRS for part in path.parts):
    return False
```
`path.parts` 包含仓库根目录之上的父路径分量。若仓库被 checkout 到任意名为
`build`/`dist`/`.git`/`node_modules`/`_build` 等目录之下（如
`~/build/Fathom`、`/home/dist/Fathom`），**所有**文件都被判为不可扫描，门禁输出
`ok: 0 product files scanned` 并以 exit 0 通过——静默放行，比误报更危险
（NAME-04 门禁形同虚设且无人察觉）。当前 CI checkout 路径
（`/home/runner/work/Fathom/Fathom`）与本机路径恰好不触发，问题被掩盖。
`jetbrains/scripts/source-smoke.py` 的 `"build" in path.parts` 同类。
**Fix:** 用 `rel.split("/")`（相对 ROOT 的分量）做排除判断，并给“0 files scanned”
输出一个显式失败/警告分支。
**Fixed:** commit 667711b

### MI-04: `parity/baseline-hashes.txt` 没有任何 CI/测试执行验证 —— T-09-03 仅纸面

**File:** `.github/workflows/ci.yml`（parity-gate job）、`parity/baseline-hashes.txt`
**Issue:** 注册表 §7 与 09-01-SUMMARY 声称 baseline-hashes.txt “pins” 33 个 corpus
文件（T-09-03 缓解“哈希被篡改/缺失”），但全仓没有任何自动化步骤执行
`sha256sum -c parity/baseline-hashes.txt`：CI parity-gate 只跑 `moon test --package
parity` 与 baseline_diff 自检；baseline_test.mbt 明确“Runtime never reads disk”。
一旦 corpus `.sql` 被修改（不影响 keywords/manifest，绕过 corpus job 检查）并同步
更新 baseline_test.mbt 内嵌字节与快照（经 register 批准路径），哈希文件会过期而
CI 不失败——provenance 承诺无强制力。09-01-SUMMARY 中的 “sha256sum -c all OK”
是一次性人工验证，未固化为 gate。
**Fix:** 在 parity-gate job 增加 `sha256sum -c parity/baseline-hashes.txt`（或
`corpus` job），任何 corpus 漂移即 CI 失败。
**Fixed:** commit 982264d

### MI-05: `3.x-unsupported-profile` fixture 元数据与其快照矛盾；`expected_valid` 为死字段

**File:** `parity/baseline_test.mbt:88-93`（fixture 定义）、`:23`（字段声明）
**Issue:** fixture `3.x-unsupported-profile`（raw `SELECT k FROM t QUALIFY k > 0`,
profile `3.x`）声明 `expected_valid: false`，但其冻结快照
`3.x-unsupported-profile.3.x.strict.json` 为 `valid: true`、零诊断（QUALIFY 由
DorisFeature::Qualify 在 3.x 引入，V3_X.supports 为 true，合法）。fixture 名与
元数据像是 2.1 时代负例（QUALIFY 在 2.1 下 FATHOM-PARSE-006）在冻结时被改 profile
后残留的旧标签。`expected_valid` 字段全仓无任何读取点，纯文档性元数据——矛盾不会
触发失败，但对后续 Phase 12 PARITY-01 基线工作是误导。
**Fix:** 将 fixture 改回 profile `2.1`（保留负例语义与命名）或更新名称/`expected_valid`
为 `true`；若字段确无用可删除。
**Fixed:** commit 4a14eaa（快照改名先按 D-08 单次批准路径注册于 3fd5a39）

### MI-06: LSP 对 flink 文档的 formatting 静默返回空 edits

**File:** `lsp/handlers.mbt:385-393`（`formatting_result` 的 `Err(_) => [response(id, [])]`）
**Issue:** flink 文档的 `textDocument/formatting` 走 `format_with_ids` → `ParseOptions::new`
拒绝 flink → 静默返回空 edit 数组，客户端无法区分“无变更可格式化”与“该方言不支持
格式化”；not-implemented 状态只能靠 didOpen/didChange 时发布的 FATHOM-PARSE-008
诊断间接可见。selection_test.mbt (j) 断言了该行为，属有意设计，但与 parse 路径的
显式 FATHOM-PARSE-008 暴露程度不一致，容易让宿主把“格式化未执行”误报为“已是最佳
格式”。
**Fix:** 对 flink 文档返回结构化错误响应（如 -32603 + “flink grammar is not yet
implemented”）或在空响应前补发一次 FATHOM-PARSE-008 诊断。
**Fixed:** commit 686968f

### MI-07: didChange 携带无效文档级选择时文档版本与文本失步

**File:** `lsp/handlers.mbt`（`textDocument/didChange` 的 `Err(error)` 分支）
**Issue:** 客户端 didChange v2 带无效 document-level 选择 → 只发布 config 诊断，
store 中文本/版本停留在 v1。随后客户端发 v3（合法选择）时 `docs.change` 因
3 > 1 仍接受，最终收敛；但中间任何带 version=2 的 completion/formatting 请求会被
判定 stale，且若客户端在 v2 之后、v3 之前请求 completion（携带 v2），用户看到的是
v1 文本的补全结果与 v2 版本号错配。属边界健壮性问题。
**Fix:** 无效选择时仍以新版本+新文本更新 store（保留旧选择），仅不发布 parse
诊断；或明确返回错误让客户端重开文档。
**Fixed:** commit feec1dd

### MI-08: web 演示用 `innerHTML` 插值 `diagnostic.code`

**File:** `web/src/main.ts:132`
**Issue:** `button.innerHTML = ...<code>${diagnostic.code}</code>...` 将诊断 code 插值进
innerHTML。code 当前来源于解析器稳定常量（FATHOM-PARSE-* 等），非用户可控，不可利用；
但属于应避免的注入形态（防御纵深：若未来 code 携带方言/来源字符串则成 XSS 面）。
消息文本已正确走 textContent。
**Fix:** 用 DOM API/textContent 构建 `<code>` 节点（与 `.diagnostic-message` 一致）。
**Fixed:** commit 810b8ae

## Info

### IN-01: `UsageError::MissingFile` 为死代码

**File:** `fathom-sql/args.mbt`（枚举定义）、`fathom-sql/run.mbt:79,102`
**Issue:** 文件读取失败走 `usage_error("cannot read file: {path}")`，从未构造
`MissingFile` 变体（`usage_error_message` 中的 `MissingFile => "cannot read file\n"`
不可达）。删除该变体或让 run 路径使用它。
**Fixed:** commit 91ceab4

### IN-02: `parse_int_arg` 的幅度上界注释夸大

**File:** `fathom-sql/args.mbt`（`parse_int_arg`）
**Issue:** 上界检查 `if number > 100000000 { return None }` 在乘法前执行，最终接受约
1e9 以内的值；64 位 Int 下无溢出，但注释 “keeps the accumulator far below Int
overflow” 与实际边界不符。无害，可收紧或修正注释。
**Fixed:** commit df24a03

### IN-03: 命名门禁 `EMBEDDED_FIXTURE_FILES` 豁免面宽于设计意图

**File:** `scripts/check_naming.py:129-132`
**Issue:** 对 `parity/baseline_test.mbt` 与 `test/formatter_test.mbt` 整体豁免
DORIS- 模式（非仅内嵌 fixture 字面量区间）。实际已存在一例：baseline_test.mbt:295
冻结 fixture 注释含 “DORIS-PARSE diagnostics (Phase 1 recovery patterns)”——属
冻结字节可接受，但该豁免使得这两个文件内任何新增 DORIS- 文本（注释、消息）都静默
通过。建议豁免缩窄到 fixture 字面量 span 或在文件头注明约束。
**Fixed:** commit 1400a0d

### IN-04: `config_request()` 硬编码请求 id 0；`target/` 未纳入命名门禁排除

**File:** `lsp/handlers.mbt`（`config_request`）、`scripts/check_naming.py:79-83`
**Issue:** (a) workspace/configuration 拉取请求 id 固定为 0——当前 server 每会话仅发起
一次拉取，安全但脆弱，未来新增第二个 server 主动请求会冲突。(b) MoonBit 构建产物目录
`target/` 既不在 .gitignore 也不在 EXCLUDED_DIRS/BUILD_OUTPUT_DIRS；开发机本地
`moon build` 后生成的 `target/**/*.js` 会被命名门禁扫描，可能对生成物误报（CI 是
fresh checkout 无此问题）。建议把 `target/` 加入排除集。
**Fixed:** commit 5fb9382 (a) / commit b1ba615 (b)

---

_Reviewed: 2026-08-07T04:30:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
