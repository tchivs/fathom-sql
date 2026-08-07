---
status: planned
created: 2026-08-07
scope: repository-identity
---

# GitHub 仓库重命名、README 链接与 v0.1.0 发布引用

## 目标

在不修改解析器、CST、方言或其他产品核心源代码、方言语义或历史归档的前提下，把 GitHub 仓库从 `tchivs/doris-sql-parser-sdk` 安全切换到与已落地公共身份一致的 `tchivs/fathom-sql`，并使本地 `origin`、根 README、JetBrains 发布链接消费者、现有标签/Release 的事实和后续发布工作流保持一致。外部 GitHub API 只有在认证可用且返回成功时才执行；认证失败不得伪造“已重命名”或“已发布”。

## 已核对事实与命名依据

- `moon.mod` 当前模块是 `fathom/sql`，可执行包和发布工作流使用 `fathom-sql` / `fathom-lsp`；README 与 `.planning/PROJECT.md` 的公共产品身份也是 Fathom。
- `.planning/PROJECT.md` 标题为 `Fathom SQL Parser SDK`，`.planning/ROADMAP.md` 明确把 `fathom-sql` 作为产品身份；因此 `fathom-sql` 比旧的 `doris-sql-parser-sdk` 更有直接证据支持。
- 当前 `origin` 为 `https://github.com/tchivs/doris-sql-parser-sdk.git`。本地 `git tag --list` 能看到 `v0.1.0` 与仅本地存在的历史标签 `v1.0`；`.planning/quick/260806-cuf-implement-the-approved-github-releases-n/SUMMARY.md` 记录的远端公开 Release 是非草稿 `v0.1.0`，但执行时仍必须用远端查询重新核对，不把本地 tag 或历史摘要当作远端事实。
- `.github/workflows/fathom-native-release.yml` 已按任意 `v*` tag 触发，workflow dispatch 也接受显式 tag，并把同名 tag 用于创建/更新 Release；因此 `v0.1.0` 必须保留，不删除、强推、改写或凭空改成新版本号。
- `README.md` 与 `README.zh-CN.md` 已有 Fathom 内容，但标题仍是 `# Fathom`，没有当前仓库 URL；JetBrains README 和 managed downloader 还硬编码旧仓库路径，命名 gate 还保留仅针对旧 URL 的 OQ8 allowlist。同步这些公开/运行时引用；Doris 作为 dialect/profile/corpus/provenance 的语义值，以及 `fathom/sql`、`fathom-sql` 等已落地标识不得被机械替换。

## 明确不触碰的范围

只允许本计划产生以下本地文件变更：

- `README.md`
- `README.zh-CN.md`
- `jetbrains/README.md`
- `jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt`
- `scripts/check_naming.py`（仅清理已失效的旧仓库 URL allowlist/说明）
- 本计划文件自身：`.planning/quick/260807-fhk-github-readme-tag-readme/PLAN.md`

不得修改其他源代码、`moon.mod`、`.github/workflows/*`、docs/、web/、vscode/、corpus/、历史归档或发布资产。`FathomNativeDownloader.kt` 是运行时下载器配置，虽非产品解析源代码，但必须同步，否则仓库重命名后 managed download 仍会请求旧仓库而失效。执行前后都必须保护当前用户/历史未提交内容：

- 已见用户/历史变更：`.github/workflows/jetbrains-plugin.yml`、`.planning/.omp-task-results.json`，以及未跟踪的 `.planning/milestones/v1.0-research/`、既有 quick 计划、`.planning/research/.cache/`、`jetbrains/.gradle/`、`jetbrains/.intellijPlatform/`、`jetbrains/build/`。
- 若重新检查发现上述允许文件已被用户修改，先停止该本地编辑步骤并报告冲突；不得覆盖、reset、clean 或 stash 用户内容。

## 执行任务（严格按顺序）

### 1. 重新建立安全边界并记录远端/标签基线

重新运行以下只读命令，保存原始输出到执行摘要；不得依赖计划生成时的旧状态：

```bash
git status --short
git remote -v
git tag --list 'v*'
git ls-remote --tags origin 'refs/tags/v0.1.0' 'refs/tags/v1.0'
```

确认五个允许的产品文件均不在 `git status --short` 的用户变更范围内，且当前远程仍是旧 URL。记录本地 `v1.0` 与远端 `v1.0` 是否存在的差异，但不因本地存在就推送或删除它。读取发布工作流中 tag 触发和 Release 上传逻辑作为 `v0.1.0` 兼容性依据；跳过 formatter、lint 和项目级测试。

### 2. 同步根 README 与本地发布链接消费者

在以下五个现行产品文件中做最小、针对性的修改，不进行全仓库机械替换：

- `README.md`：把第一层标题从 `# Fathom` 更新为有项目文件证据支持的 `# Fathom SQL Parser SDK`，并在现有产品简介附近加入文案为 `Repository` 的规范仓库链接 `https://github.com/tchivs/fathom-sql`。
- `README.zh-CN.md`：同步标题，并加入文案为 `GitHub 仓库` 的同一规范 URL。
- `jetbrains/README.md`：把 managed download 的仓库、Native release workflow 的仓库和 Marketplace homepage 三处 `tchivs/doris-sql-parser-sdk` 更新为 `tchivs/fathom-sql`；保留 `fathom-lsp-*` 资产名、`v*` tag 说明和其他版本/发布内容。
- `jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt`：只把 `DEFAULT_REPOSITORY` 更新为 `tchivs/fathom-sql`，确保仓库重命名后托管下载仍请求新仓库；不要改变资产名、manifest 校验、缓存、超时或 fallback 行为。
- `scripts/check_naming.py`：移除旧仓库 URL 的 `ALLOWLIST_CONTEXTS` 条目、相关旧 URL 文档说明和仅为该 allowlist 服务的逐行替换分支；命名 gate 仍保留对 `doris-sql` 产品表面的禁止规则，Doris 方言/语料语义仍按 D-05 保留。该脚本的旧 URL 不应再被当作合法产品引用。

保留现有 Fathom、`fathom/sql`、`fathom-sql`、`fathom-lsp`、Doris 方言/profile/corpus 内容和所有示例；不得改动历史归档或把 Doris 语义名称替换成 Fathom。

用以下本地检查确认修改边界和运行时链接（不运行 formatter、lint 或项目级测试）：

```bash
git diff --check
git diff --name-only -- README.md README.zh-CN.md jetbrains/README.md jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt scripts/check_naming.py
git diff -- README.md README.zh-CN.md jetbrains/README.md jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt scripts/check_naming.py
python3 scripts/check_naming.py
cd jetbrains && python3 scripts/source-smoke.py
cd .. && python3 -c 'from pathlib import Path; files=["README.md","README.zh-CN.md","jetbrains/README.md","jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt","scripts/check_naming.py"]; old="tchivs/doris-sql-parser-sdk"; new="tchivs/fathom-sql"; assert all(old not in Path(f).read_text(encoding="utf-8") for f in files); assert all(new in Path(f).read_text(encoding="utf-8") for f in files[:4]); print("repository URL references clean")'
```

另外对五个允许文件执行旧 URL 负向检查，并确认 `FathomNativeDownloader.kt` 与两个 README 各包含 `tchivs/fathom-sql`；若发现其他路径变化、旧 URL 残留或下载器新旧 URL 不一致，停止并报告，不覆盖用户工作。

### 3. 在认证可用时执行 GitHub 仓库 rename API

先检查认证和目标命名可用性，不打印 token：

```bash
gh auth status
gh api repos/tchivs/doris-sql-parser-sdk --jq '{full_name:nameWithOwner,name,html_url,default_branch}'
gh api repos/tchivs/fathom-sql --silent >/dev/null 2>&1; test $? -ne 0
```

仅当 `gh auth status` 成功、当前仓库仍为旧仓库且目标仓库查询确认不存在/不可用时，调用 GitHub REST rename：

```bash
gh api --method PATCH repos/tchivs/doris-sql-parser-sdk \
  -f name='fathom-sql' \
  --jq '{full_name:nameWithOwner,name,html_url}'
```

该 PATCH 返回 HTTP 成功且 `nameWithOwner` 为 `tchivs/fathom-sql` 后，才可记录“GitHub 仓库已重命名”。若 `gh` 不可用但已有具备仓库管理权限的 `GITHUB_TOKEN`，可用同一 PATCH 的 `curl` 等价调用；请求体只包含 `{"name":"fathom-sql"}`，Authorization 头来自环境变量，绝不把 token 写入文件、README、日志或提交。不得通过创建第二个同名仓库来代替 rename。

若认证缺失、权限不足、网络失败、目标名已占用或 API 返回非 2xx：

- 保留已完成的五个本地链接修正；
- 不修改 tag/release，不把失败写成成功；
- 保留旧 `origin`，避免在仓库尚未重命名时留下不可推送的新 URL；
- 在执行摘要记录 `gh auth status`/HTTP 状态和错误类别，给出可复核的重试命令；不要打印凭据。

### 4. 仅在 API 成功后更新本地 origin 并验证

API 成功后执行：

```bash
git remote set-url origin https://github.com/tchivs/fathom-sql.git
git remote -v
git ls-remote origin HEAD 'refs/tags/v0.1.0'
gh api repos/tchivs/fathom-sql --jq '{full_name:nameWithOwner,name,html_url,default_branch}'
```

确认 `origin` 的 fetch/push URL 都是 `https://github.com/tchivs/fathom-sql.git`，新仓库可读且 `v0.1.0` 远端 tag 仍可解析。不要把旧 URL 留在 README；GitHub 的旧 URL 重定向只作为迁移兼容事实，不作为新的规范链接。

### 5. 核对并保留 v0.1.0 tag/Release，不重写发布历史

重命名成功后以新仓库路径分别核对 tag 和 Release：

```bash
git ls-remote --tags origin 'refs/tags/v0.1.0'
gh release view v0.1.0 --repo tchivs/fathom-sql \
  --json tagName,isDraft,isPrerelease,url,assets
```

验收时应观察到 `v0.1.0` 仍指向原 tag，现有 Release（若远端基线确认存在）仍是同名版本；发布工作流的 `v*` 触发规则和 workflow-dispatch 的显式 tag 仍兼容。不得执行 `git push --force`、删除/重建 tag、删除 Release、`--clobber` 上传或重新运行发布 workflow。仅当远端查询发现事实与历史摘要不一致时，记录差异并停止任何创造/修改发布历史的动作；不凭空创建 `v1.0` 或修改版本号。未来需要发布新内容时，应使用新的版本 tag，并由单独发布任务明确授权。

## 失败与恢复策略

- **本地链接编辑失败或发现用户冲突**：不动外部 GitHub、origin、tag；报告冲突路径和保留的本地状态。
- **GitHub 认证/API 失败**：保留已完成的五个本地链接修正和旧 origin；摘要明确“本地完成、外部 rename 未完成”，用户重新认证后可从任务 3 继续。可验证替代方案是用户执行 `gh auth login`（具备目标仓库管理权限）后重跑任务 3，或使用同等权限的 REST PATCH；不能用本地命令伪造远端结果。
- **rename 成功但 origin 更新失败**：不做 tag 操作；手动重试 `git remote set-url origin https://github.com/tchivs/fathom-sql.git`，再执行任务 4 的只读验证。
- **tag/Release 核对失败或只读权限不足**：保留已成功的 rename/origin/五个本地链接修正，记录具体命令与失败事实；不删除、强推、重写或重建 `v0.1.0`。

## 验收标准

- `.planning/quick/260807-fhk-github-readme-tag-readme/PLAN.md` 存在且本计划的执行顺序、命令和停止条件完整。
- 本地允许的实现文件恰好限于 `README.md`、`README.zh-CN.md`、`jetbrains/README.md`、`jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt`、`scripts/check_naming.py`；两个根 README 标题为 `Fathom SQL Parser SDK` 并指向 `https://github.com/tchivs/fathom-sql`，JetBrains 文档/下载器均使用新仓库，旧 URL allowlist 已清理，未发生 Doris 语义值的机械替换。
- `FathomNativeDownloader.DEFAULT_REPOSITORY` 与 managed-download 文档均为 `tchivs/fathom-sql`，资产名、manifest 校验、缓存和 fallback 行为未被改动；针对性 source-smoke 与 naming gate 通过。
- 认证成功路径中，GitHub API 明确返回 `tchivs/fathom-sql`，本地 `origin` fetch/push 均为新 URL；认证失败路径中，旧 origin 保留且失败事实可复核。
- `v0.1.0` 远端 tag 与现有 Release 未删除、强推、重写或改版本号；发布工作流仍以 `v*` 和显式 tag 兼容它。仅本地的历史 `v1.0` 不被推送、删除或改写，任何远端事实差异均被记录而未擅自处理。
- `git diff --check` 通过；计划执行不调用 formatter、lint、`moon test`、`moon check`、Gradle 测试或其他项目级测试。

## 来源覆盖审计

| 来源 | 事实/要求 | 覆盖位置 |
|---|---|---|
| 用户目标 | GitHub rename、origin、双 README、tag/Release、认证失败替代方案 | 任务 2–5、失败与恢复策略 |
| 用户补充/运行时影响 | JetBrains downloader 与 README 的旧仓库 URL 必须同步，命名 gate allowlist 必须清理 | 任务 2、验收标准 |
| `.planning/PROJECT.md` / `ROADMAP.md` | 公共身份是 Fathom，模块/CLI 名为 `fathom/sql`、`fathom-sql`；标题证据为 Fathom SQL Parser SDK | 已核对事实、任务 2 |
| Phase 9 D-04/D-05/D-06 与 `09-07-SUMMARY.md` | 历史归档豁免；Doris 保留为方言语义；产品层 clean cutover 已完成 | 明确不触碰范围、任务 2 |
| 发布 quick SUMMARY 与 `.github/workflows/fathom-native-release.yml` | `v0.1.0` 已发布记录、`v*` 触发及同名 Release 逻辑 | 任务 1、任务 5 |
| 当前工作树/远程只读核对 | 用户未提交变更、旧 origin、本地 tag 事实 | 任务 1 与明确不触碰范围 |

## 执行限制

这是仓库身份与发布引用 quick task；不修改解析器、CST、方言或其他产品核心源代码，仅允许为修复仓库重命名后 managed download 的真实运行时引用而改动 `FathomNativeDownloader.DEFAULT_REPOSITORY`。执行期间跳过 formatter、lint、`moon test`、`moon check`、Gradle 测试以及其他项目级测试。所有“已重命名”“origin 已更新”“Release 仍存在”的结论必须来自对应命令输出，而不是计划文本或预期行为。
