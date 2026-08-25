<!-- GSD:generated -->
English: [README.md](README.md) | 简体中文

[![GitHub Release](https://img.shields.io/github/v/release/tchivs/fathom-sql?include_prereleases&label=Release)](https://github.com/tchivs/fathom-sql/releases)
[![npm version](https://img.shields.io/npm/v/@fathom-sql/sql?label=npm)](https://www.npmjs.com/package/@fathom-sql/sql)
[![VS Code Marketplace](https://img.shields.io/badge/VS%20Code-fathom--sql.sql%20v1.0.4-0078d4?logo=visualstudiocode&logoColor=white)](https://marketplace.visualstudio.com/items?itemName=fathom-sql.sql)
[![CI](https://github.com/tchivs/fathom-sql/actions/workflows/ci.yml/badge.svg)](https://github.com/tchivs/fathom-sql/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/tchivs/fathom-sql?color=blue)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260819-2f80ed)](https://www.moonbitlang.com/)
[![Targets](https://img.shields.io/badge/targets-native%20%7C%20js%20%7C%20wasm-555555)](moon.mod)
[![Doris](https://img.shields.io/badge/Doris-2.1%20%7C%203.x%20%7C%204.x-blue)](https://doris.apache.org/)
[![Flink](https://img.shields.io/badge/Flink-1.20.5%20%7C%202.1.3%20%7C%202.3.0-blue)](https://flink.apache.org/)
[![Last Commit](https://img.shields.io/github/last-commit/tchivs/fathom-sql)](https://github.com/tchivs/fathom-sql/commits)
[![Repo Size](https://img.shields.io/github/repo-size/tchivs/fathom-sql)](https://github.com/tchivs/fathom-sql)
[![Stars](https://img.shields.io/github/stars/tchivs/fathom-sql?style=social)](https://github.com/tchivs/fathom-sql/stargazers)

# Fathom SQL Parser SDK

Fathom 是面向 Apache Doris 和 Flink SQL 的 MoonBit 解析器 SDK，为编辑器、Web 工具和自动化流水线提供带源码保真度的解析、诊断、格式化与工具链能力。**GitHub 仓库：** https://github.com/tchivs/fathom-sql


## 特性

- **双方言解析**：Doris profile `2.1`、`3.x`、`4.x` 及 Flink profile `flink-2.3.0`、`flink-2.1.3`、`flink-1.20.5`——按方言做版本感知的关键字分类与特性引入门控。
- **两种解析模式**：`strict` 用于严格校验，`editor` 用于半成品 SQL 的错误恢复。
- **无损语法树**：解析结果保留 token、trivia、错误和跳过内容的字节范围；源代码中的注释、空白、换行、BOM、Unicode 以及非法字节都可通过打印器重放。
- **结构化诊断**：诊断包含稳定的 `FATHOM-PARSE-*` code、消息、严重级别、字节范围和 statement id。
- **CST 格式化**：格式化器支持关键字大小写、缩进、行宽、逗号风格、换行风格和尾部换行策略；遇到错误树时拒绝输出部分结果。
- **SQL 指纹**：确定性的内容归一化指纹，用于查询缓存与去重。
- **列级血缘**：通过调用方注入的 `Catalog` 追踪 DML/DDL 的输入/输出列（仅 Doris）。
- **可选名字解析**：`analyzer` 包通过调用方注入的 `Catalog` 解析 DML/DDL 目标表，不把元数据依赖带入语法解析。
- **五渠道分发**：npm SDK 供 Node/浏览器、VS Code 扩展、JetBrains 插件（即将上线）、GitHub Releases 预编译 `fathom-lsp` 二进制、MoonBit 库直接导入——均源自同一 MoonBit 核心。

## 安装

Fathom 提供五种安装渠道，按你的使用场景选择：

| 渠道 | 产物 | 目标用户 | 链接 |
|---|---|---|---|
| **npm SDK** | `@fathom-sql/sql` | Node.js / 浏览器 / Bundler | [![npm](https://img.shields.io/npm/v/@fathom-sql/sql?label=%20)](https://www.npmjs.com/package/@fathom-sql/sql) [npm/README.md](npm/README.md) |
| **VS Code 扩展** | `fathom-sql.sql` | VS Code / Cursor / Windsurf | [![Marketplace](https://img.shields.io/badge/install-fathom--sql.sql-0078d4?logo=visualstudiocode&logoColor=white)](https://marketplace.visualstudio.com/items?itemName=fathom-sql.sql) [vscode/README.md](vscode/README.md) |
| **JetBrains 插件** | `fathom-sql-intellij` | IntelliJ IDEA / PyCharm / DataGrip | [jetbrains/README.md](jetbrains/README.md)（Marketplace 待发布） |
| **LSP 二进制** | `fathom-lsp` | 任何支持 LSP 的编辑器 / CLI / CI | [![GitHub Release](https://img.shields.io/github/v/release/tchivs/fathom-sql?label=%20)](https://github.com/tchivs/fathom-sql/releases) [↓ 见下文](#从-github-release-安装-fathom-lsp) |
| **MoonBit 库** | `fathom/sql/*` | MoonBit 包消费者 | [↑ 从源码构建](#moonbit-库) |

### npm SDK（Node.js / 浏览器）

```bash
npm install @fathom-sql/sql
```

完整 JS API 参考和使用示例：[npm/README.md](npm/README.md)

```js
import { parse, format, fingerprint, withLineColumns } from '@fathom-sql/sql';

const result = parse('SELECT 1', 'doris', '4.x', 'strict');
console.log(result.valid);          // true

const fmt = format('select 1', 'doris', '4.x', 'strict', { keyword_case: 'upper' });
console.log(new TextDecoder().decode(new Uint8Array(fmt.formatted)));  // "SELECT 1\n"
```

### VS Code 扩展

从 [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=fathom-sql.sql) 安装（搜索 "Fathom SQL Language Client"），然后：

1. 从 [GitHub Releases](https://github.com/tchivs/fathom-sql/releases) 下载 `fathom-lsp`（见[下文](#从-github-release-安装-fathom-lsp)）
2. 设置 `fathom.serverPath` 指向二进制路径
3. 设置 `fathom.dialect`（`doris` 或 `flink`）和 `fathom.profile`（如 `4.x`）

详情：[vscode/README.md](vscode/README.md)

### JetBrains 插件（IntelliJ IDEA / PyCharm / DataGrip）

从源码构建或等待 Marketplace 发布：

```bash
cd jetbrains
./gradlew buildPlugin   # → build/distributions/fathom-sql-intellij-*.zip
```

通过 **Settings → Plugins → ⚙ → Install Plugin from Disk** 安装。需要 [LSP4IJ](https://plugins.jetbrains.com/plugin/23257-lsp4ij) 0.20.1+。

详情：[jetbrains/README.md](jetbrains/README.md)

### LSP 二进制（任意编辑器 / CLI / CI）

三平台预编译 `fathom-lsp` 二进制，带 SHA-256 校验。见[↓ 从 GitHub Release 安装](#从-github-release-安装-fathom-lsp)。

### MoonBit 库

克隆仓库并用 MoonBit 工具链（`moon 0.1.20260819`，内容锁定）从源码构建：

```bash
git clone https://github.com/tchivs/fathom-sql.git
cd fathom-sql
moon version   # 确认：moon 0.1.20260819 (fc2a4ee 2026-08-19)
moon check
```

在自己的 MoonBit package 中导入 `fathom/sql/api`，即可调用 `parse_with_ids` 或 `format_with_ids`（示例见下文 [使用示例](#使用示例)）。

## 快速开始（MoonBit 库）

[安装](#安装)完成后（方式 3，MoonBit 库），导入 `fathom/sql/api` 并调用 `parse_with_ids` 或 `format_with_ids`：

## 使用示例

### 解析有效 SQL

`api` facade 接收原始 `Bytes`，返回包含 primitive CST、profile 元数据和诊断数组的 `ParseResult`：

```moonbit
import {
  "fathom/sql/api" @api,
}

let parsed = @api.parse_with_ids(b"SELECT 1", "doris", "4.x", "strict")
match parsed {
  Ok(result) => {
    // result.valid == true
    // result.diagnostics.length() == 0
    println(result.root.kind) // document
  }
  Err(error) => {
    println(error.to_string())
  }
}
```

`ParseResult` 还提供 `statement(statement_id)`、`statement_diagnostics(statement_id)` 和 `all_spans_in_bounds()`，方便按语句消费 CST 与诊断。

### 编辑器模式下恢复半成品 SQL

对于尚未输入完成的表达式，可以使用 `editor` 模式保留输入并生成恢复节点与诊断：

```moonbit
import {
  "fathom/sql/api" @api,
  "fathom/sql/printer" @printer,
}

let parsed = @api.parse_with_ids(b"SELECT 1 +", "doris", "4.x", "editor")
match parsed {
  Ok(result) => {
    // result.valid == false
    // result.recovered == true
    // result.root 中包含 missing 或 error 节点
    // @printer.print_result(result) 仍可重放原始字节 b"SELECT 1 +"
    println(result.diagnostics[0].code) // FATHOM-PARSE-002
  }
  Err(error) => {
    println(error.to_string())
  }
}
```

### 格式化并保留注释与换行策略

默认格式化选项为大写关键字、2 个空格缩进、100 列行宽、跟随输入换行风格并追加尾部换行：

```moonbit
import {
  "fathom/sql/api" @api,
  "fathom/sql/formatter" @formatter,
}

let options = @formatter.FormatOptions::default()
let formatted = @api.format_with_ids(
  b"select 1; select 2",
  "doris",
  "4.x",
  "strict",
  options,
)
match formatted {
  Ok(result) => {
    // result.accepted == true
    // result.output == b"SELECT 1;\nSELECT 2\n"
    println(result.output.to_string())
  }
  Err(error) => {
    println(error.to_string())
  }
}
```

格式化结果包含 `accepted`、输出字节、格式化/解析诊断以及 statement offsets。对于错误、缺失或跳过节点，格式化器会返回拒绝结果和空输出，而不会产生部分格式化文本。

## 包结构

```text
api/        面向调用方的 parse/format facade、选项、结果和诊断类型
token/      token 类型、关键字分类和方言 profile 元数据
lexer/      Dialect 感知的词法分析
parser/     手写递归下降文档解析器与 Pratt 表达式解析路径
syntax/     无损 CST 节点、叶子和错误/缺失结构
printer/    从 CST 或 ParseResult 精确重放源字节
formatter/  基于 CST 的格式化布局与安全拒绝逻辑
analyzer/   基于调用方 Catalog 的最小名字解析层
test/       MoonBit 行为测试、格式化测试和 corpus 测试
corpus/     按 Doris 版本组织的 SQL fixture、manifest 与覆盖报告
```

公共调用通常从 `api` 开始；需要直接操作 CST、源码快照或分析器时，再分别使用对应包。`analyzer` 不参与 parser 的语法有效性和诊断结果。

## 验证与测试

- `moon check`：已验证可完成模块检查（当前工具链会报告若干弃用/未使用警告）。
- `moon test`：运行测试包和 corpus 测试；测试/快照状态应以本地命令输出为准，失败时查看 `test/` 中对应的测试文件。
- `python3 corpus/tools/generate_corpus_report.py --check`：检查 `corpus/manifest.tsv`、覆盖率与报告的一致性。

Doris SQL 的支持范围以 `corpus/manifest.tsv`、`corpus/coverage.tsv` 和 `corpus/CORPUS-REPORT.md` 中按 profile 标注的 fixture 与预期错误为准，不应将单个 parser reference 的接受结果当作公开兼容性承诺。

## 从 GitHub Release 安装 `fathom-lsp`

预编译的 `fathom-lsp` 二进制随每个 GitHub Release 发布
（<https://github.com/tchivs/fathom-sql/releases>）。选择与所需版本匹配的 release tag（例如 `v1.0.4`；二进制通过 `--version` 报告 `fathom-lsp 1.0.4`）。

### 各平台资产

| 平台 | 资产 |
|----------|-------|
| Linux x86_64 | `fathom-lsp-linux-x86_64` |
| macOS（Apple Silicon） | `fathom-lsp-macos-aarch64` |
| Windows x86_64 | `fathom-lsp-windows-x86_64.exe` |

### 校验 SHA-256

从同一 release 下载 `fathom-lsp-manifest.json`，并将资产摘要与其中 `assets` 条目（各平台 `sha256`）比对：

```bash
# Linux/macOS
curl -fLO https://github.com/tchivs/fathom-sql/releases/download/v1.0.4/fathom-lsp-linux-x86_64
curl -fLO https://github.com/tchivs/fathom-sql/releases/download/v1.0.4/fathom-lsp-manifest.json
python3 - <<'PY'
import hashlib, json
m = json.load(open("fathom-lsp-manifest.json"))
a = m["assets"]["linux-x86_64"]
got = hashlib.sha256(open(a["name"], "rb").read()).hexdigest()
assert got == a["sha256"], f"MISMATCH {got} != {a['sha256']}"
print("SHA-256 OK")
PY
```

### 安装

```bash
mkdir -p ~/.fathom/bin
mv fathom-lsp-linux-x86_64 ~/.fathom/bin/fathom-lsp
chmod +x ~/.fathom/bin/fathom-lsp
export PATH="$HOME/.fathom/bin:$PATH"   # 将本行加入你的 shell 配置文件
```

Windows 上将 `fathom-lsp-windows-x86_64.exe` 移入所选目录并加入 `PATH`（PowerShell：`Move-Item`）。

### 验证安装

```bash
fathom-lsp --version   # 输出：fathom-lsp 1.0.4
```

## 许可证

本项目采用 [Apache-2.0](LICENSE) 许可证。
