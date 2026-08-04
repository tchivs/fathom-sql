<!-- GSD:generated -->
English: [English getting started](../GETTING-STARTED.md) | 简体中文
# 开始使用 Fathom

Fathom 是面向 Apache Doris SQL 的 MoonBit 解析器 SDK，为编辑器、格式化工具和自动化流水线提供保留源码字节、诊断和格式化能力。当前仓库提供库包和 `doris-sql/` native CLI 适配器，不提供需要启动的 HTTP 服务。

## 前置条件

- **Git**：用于获取源码。
- **MoonBit CLI**：需要与仓库清单兼容的 `moon 0.1.20260724 (5f1406a 2026-07-24)`。可用 `moon version` 检查；安装方式取决于操作系统和官方发行渠道。<!-- VERIFY: MoonBit CLI 的平台安装步骤和下载地址需以官方发行说明为准。 -->
- **Python 3**：仅在运行 `corpus/` 下的语料报告工具或差分工具时需要。解析器本身不需要 Python 运行时。
- **可选的 Python 依赖**：`corpus/requirements.txt` 固定了差分比较工具 `sqlglot==30.14.0`；只在使用该差分工具时安装。

仓库没有 Node.js 依赖、数据库、`.env` 文件或部署服务。MoonBit 模块身份和首选构建目标记录在根目录 `moon.mod` 中：模块名为 `fathom/doris-sql`，版本为 `0.1.0`，首选目标为 `native`。

## 安装步骤

1. 克隆仓库（当前工作副本未配置可验证的 Git 远程地址，请将占位符替换为实际仓库地址）：

   ```bash
   git clone <repository-url> Fathom
   cd Fathom
   ```

2. 确认 MoonBit CLI 版本：

   ```bash
   moon version
   ```

   输出应与前置条件中记录的版本线一致。仓库的各包通过 `moon.mod` 和各目录下的 `moon.pkg` 管理，不需要额外的运行时依赖下载。

3. （可选）为语料差分工具安装 Python 依赖：

   ```bash
   python3 -m pip install -r corpus/requirements.txt
   ```

## 首次运行

在项目根目录运行模块检查，即可完成一次可工作的构建验证：

```bash
moon check
```

该命令检查根包以及 `api`、`parser`、`lexer`、`syntax`、`printer`、`formatter`、`analyzer` 等库包。当前仓库的 `moon check` 已验证能够完成，可能会输出弃用、冗余修饰符或未使用项警告；这些警告不等同于检查失败。

Fathom 当前没有 HTTP 服务，但提供 `doris-sql/` native CLI 适配器；库调用方可在自己的 MoonBit package 中导入 `fathom/doris-sql/api`，CLI 入口位于 `doris-sql/main.mbt`，最短库用法见 [README.md](../../README.md) 的“使用示例”章节。

## 常见设置问题

### MoonBit 版本不匹配

如果 `moon version` 与 `moon.mod` 记录的工具链版本线不一致，先切换或安装匹配的 MoonBit CLI，再重新执行：

```bash
moon version
moon check
```

不要通过设置环境变量来替代版本切换；仓库没有环境变量配置入口。完整的解析 profile、模式、资源限制和格式化默认值见 [CONFIGURATION.md](CONFIGURATION.md)。

### 把库当作服务或 CLI 启动

仓库没有 HTTP 服务，但包含可执行的 `doris-sql` 包；需要运行 CLI 时使用该包的 `format` 入口，需要库 API 时在调用方的 MoonBit package 中导入 `fathom/doris-sql/api`。解析入口需要显式传入 Doris profile（`2.1`、`3.x` 或 `4.x`）和模式（`strict` 或 `editor`）。

### `moon test` 报告快照占位符或失败

测试命令是：

```bash
moon test
```

当前仓库未发现格式化测试中的 `PLACEHOLDER` 快照断言；如果 `moon test` 失败，应根据实际错误检查对应的测试文件和实现。这表示当前测试状态，而不是缺少安装依赖。首次确认环境时优先使用已验证的 `moon check`；需要处理测试失败时，先查看 [README.md](../../README.md) 的“验证与测试”说明以及 `test/` 中对应的测试文件。

### 语料报告检查缺少 Python 或发现报告过期

语料一致性检查使用 Python 3 标准库：

```bash
python3 corpus/tools/generate_corpus_report.py --check
```

如果提示找不到 `python3`，请安装 Python 3。如果提示 `CORPUS-REPORT.md` 相对 manifest/coverage 过期，应在审查变更后运行不带 `--check` 的脚本重新生成报告；如果运行差分比较工具，再确认已安装 `corpus/requirements.txt` 中固定的 `sqlglot==30.14.0`。

## 下一步

- 阅读 [README.md](../../README.md)，了解 `parse_with_ids`、`format_with_ids` 以及 `printer` 的基本用法。
- 阅读 [ARCHITECTURE.md](ARCHITECTURE.md)，了解 `source → lexer → parser → syntax` 的数据流和各包边界。
- 阅读 [CONFIGURATION.md](CONFIGURATION.md)，选择 Doris profile、解析模式、资源限制和格式化选项。
- 继续阅读 [DEVELOPMENT.md](DEVELOPMENT.md) 了解本地开发命令，并阅读 [TESTING.md](TESTING.md) 了解测试组织和运行方式。
