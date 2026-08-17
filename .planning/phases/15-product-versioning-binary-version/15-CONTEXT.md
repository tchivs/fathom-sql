# Phase 15: Product Versioning & Binary `--version` - Context

**Gathered:** 2026-08-17
**Status:** Ready for planning
**Mode:** auto（灰区全部采用推荐方案，见 Claude's Discretion）

<domain>
## Phase Boundary

本阶段为 Fathom SQL Parser SDK 定义产品 semver 策略（VER-01），并为两个发布二进制 `fathom-sql` 与 `fathom-lsp` 实现 `--version` 版本报告（VER-02），输出与发布 tag 一致的产品版本字符串，退出码 0，且测试覆盖。

本阶段不写 CHANGELOG（VER-03 → Phase 17），不创建 `v1.0.0` tag 或 GitHub Release（VER-04 → Phase 20），不发布 npm/编辑器市场包（Phases 18–19），不修订安装文档（Phase 16）。

**Requirements:** VER-01, VER-02

## Prior Locked Context
- Phase 13 决策：`moon.mod` 的 module version 保持 `0.1.0`（release-planning 决策）——产品版本与模块版本**解耦**。
- Phase 14 决策：wire 命名空间 `fathom.*.v1`（parse/format/error/dialect/capabilities/complete/lint/fingerprint）为稳定契约；D-01/D-03 三平台内容锁定工具链（moon 0.1.20260807）。
- CLI 约定（D-38/D-39/D-11）：`fathom-sql` 手写参数解析；usage 错误退出码 2、拒绝 1、成功 0；`--dialect/--profile` 必填；`--help` 在 main 中先于 parse_args 处理。
- `fathom-lsp` 独立入口：`fathom-lsp/main.mbt` 直接调用 `@lsp.serve_stdio(None, None)`，无参数处理。

</domain>

<decisions>
## Implementation Decisions

### Version Source and Identity
- **D-01（版本源）:** 产品版本使用**单一编译期常量**，位于新共享包 `version/version.mbt`：`pub fn product_version() -> String` 返回 `"1.0.0"`，`pub fn product_name(binary : String) -> String` 可拼接二进制名。`fathom-sql` 与 `fathom-lsp` 两个 executable 包都 import 该包，杜绝双常量漂移。moon.mod 的 `0.1.0` 保持不动（Phase 13 决策，模块版本与产品版本解耦）。— **Reversibility:** costly — 产品 semver 是外部契约，bump 需走 VERSIONING.md 流程。
- **D-02（输出格式）:** `--version` 输出单行 `<binary-name> <product_version>`（如 `fathom-sql 1.0.0`、`fathom-lsp 1.0.0`），带尾部换行，退出码 0。产品版本字符串不含 `v` 前缀（tag 为 `v1.0.0`，二进制报告 `1.0.0`）。
- **D-03（CLI/LSP 集成）:** `fathom-sql`：`main.mbt` 在 parse_args **之前**检查裸 `--version`（首个且唯一参数）→ 打印 + exit 0；与 `--help` 同级。`fathom-lsp`：`main.mbt` 检查 `--version` → 打印 + exit 0，否则维持现有 serve_stdio 行为。— **Reversibility:** one-way — 参数表面是 CLI 契约，删除需版本化迁移。

### Policy and Verification
- **D-04（VER-01 策略记录）:** 新增 `docs/VERSIONING.md`（英文），记录：semver 策略（首个公开版本 1.0.0）；`fathom.*.v1` wire 契约稳定性承诺（已发布的 v1 命名空间在 1.x 内不破坏性变更）；破坏性变更必须 bump 契约版本（如 `.v2`）并走迁移；版本 bump 流程（改 `version/version.mbt` → 更新 tag → Phase 17 CHANGELOG）；模块版本 `moon.mod 0.1.0` 与产品版本解耦的说明。
- **D-05（tag 一致性可执行验证）:** `fathom-native-release.yml` 每个 build job 增加一步：构建后用 `--version` 运行产物并断言输出含 `RELEASE_TAG`（去掉 `v` 前缀）；workflow_dispatch 用 `inputs.tag`，tag 触发用 `github.ref_name`。使 VER-02 的"与发布 tag 一致"成为 CI 中真实执行的断言（Phase 20 冒烟同样引用）。
- **D-06（测试）:** `version` 包内联测试（product_version 精确值）；`fathom-sql/cli_test.mbt` 黑盒测试：`--version` 退出码 0 + 精确输出；fathom-lsp 的 `--version` 由 release workflow 断言覆盖（二进制级），本地以共享常量单测兜底。— **Reversibility:** one-way — `--version` 输出是外部 CLI 契约。
- **D-07（退出码）:** `--version` 成功退出 0，纳入 D-39 语义（0 成功 / 1 拒绝 / 2 usage）；未知 flag 仍退出 2。

### Claude's Discretion
`--auto` 模式下上述灰区全部采用推荐方案。规划者可决定版本包内部结构、测试文件命名与 workflow 断言步骤细节，但不得改变 D-01..D-07 的边界或失败语义。

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/ROADMAP.md` §Phase 15 — goal、VER-01/02、成功标准。
- `.planning/REQUIREMENTS.md` §VER — VER-01/02 原文。
- `.planning/PROJECT.md` §Current Milestone: v4.0 Release Readiness — REL-VERSION 目标。
- `.planning/phases/14-release-hygiene-toolchain-pinning/14-CONTEXT.md` — D-01/D-03 三平台工具链；wire 契约与 release DAG 现状。
- `.planning/phases/13-toolchain-and-editor-packaging/13-CONTEXT.md` — module version `0.1.0` 决策（release-planning）。
- `fathom-sql/args.mbt`、`fathom-sql/main.mbt`、`fathom-sql/run.mbt` — CLI 参数/入口/退出码现状（D-39）。
- `fathom-lsp/main.mbt` — 独立 LSP 入口现状。
- `moon.mod` — module version `0.1.0`（保持）。
- `.github/workflows/fathom-native-release.yml` — 三平台 build + release-gates + release（D-05 断言插入点）。
- `docs/API.md` — wire 契约文档（`fathom.*.v1` 命名空间清单）。
- `fathom-sql/cli_test.mbt` — 黑盒 CLI 测试现状（新增 `--version` 用例）。

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `fathom-sql/main.mbt` 已有 `--help` 前置处理模式（main 内先检查再 parse_args），`--version` 复用同一结构。
- `fathom-sql/cli_test.mbt` 黑盒测试模式（构造 Command / 调用 run_* 断言退出码与输出）。
- release workflow build job 已有产物构建与 `dist/` 输出；`RELEASE_TAG` env 已在 release job，dispatch 时 `inputs.tag` 全局可用。
- D-39 退出码语义已文档化（0/1/2），`--version` 归入 0。

### Established Patterns
- 单一来源常量：`binding/schema.mbt` 的 SCHEMA_VERSION 常量族；版本常量同样单源。
- 手写参数解析 + 命名错误枚举（UsageError），不引入 @argparse。
- 黑盒测试放 executable 包的 `_test.mbt`（moon 0.1.20260724 需 pub(all) 构造）。

### Integration Points
- `fathom-sql/main.mbt`：parse_args 前插入 `--version` 分支。
- `fathom-lsp/main.mbt`：serve_stdio 前插入 `--version` 分支。
- 新包 `version/`：`version/moon.pkg` + `version/version.mbt`（两 executable 共享）。
- release workflow build job：构建产物后加 `--version` 断言步骤。

</code_context>

<specifics>
## Specific Ideas

- 二进制名硬编码为 "fathom-sql" / "fathom-lsp"（与 09-03 产品改名后的包名一致），不读 argv[0]（可移植性/确定性）。
- `product_version()` 常量值 "1.0.0" 是首个公开版本；Phase 20 打 `v1.0.0` tag 时 release workflow 断言自动校验一致性。
- `--version` 与 `--help` 互斥处理：`fathom-sql --version` 精确匹配（无子命令、无其他 flag）；其余路径维持现状。

</specifics>

<deferred>
## Deferred Ideas

- CHANGELOG.md 与 1.0.0 条目（VER-03）→ Phase 17。
- `v1.0.0` tag 触发 release 管线（VER-04）→ Phase 20。
- 安装文档中的版本验证命令（DOC-02）→ Phase 16（引用 Phase 15 的 `--version`）。
- npm/编辑器市场包版本号 → Phases 18–19。

</deferred>

---

*Phase: 15-Product Versioning & Binary `--version`*
*Context gathered: 2026-08-17*
