<!-- GSD:generated -->
English: [README.md](README.md) | 简体中文
[![MoonBit](https://img.shields.io/badge/MoonBit-0.1.20260724-2f80ed)](https://www.moonbitlang.com/)
[![Target](https://img.shields.io/badge/target-native-555555)](moon.mod)
[![Docs](https://img.shields.io/badge/docs-English%20%7C%20zh--CN-007ec6)](docs/zh-CN/ARCHITECTURE.md)

# Fathom

Fathom 是面向 Apache Doris SQL 的 MoonBit 解析器 SDK，为编辑器、格式化工具和自动化流水线提供带源码保真度的解析、诊断与格式化能力。

## 特性

- **版本感知解析**：支持 `2.1`、`3.x`、`4.x` 三个 Doris profile，并通过 profile 元数据校验版本与特性引入信息。
- **两种解析模式**：`strict` 用于严格校验，`editor` 用于半成品 SQL 的错误恢复。
- **无损语法树**：解析结果保留 token、trivia、错误和跳过内容的字节范围；源代码中的注释、空白、换行、BOM、Unicode 以及非法字节都可通过打印器重放。
- **结构化诊断**：诊断包含稳定的 `DORIS-PARSE-*` code、消息、严重级别、字节范围和 statement id。
- **CST 格式化**：格式化器支持关键字大小写、缩进、行宽、逗号风格、换行风格和尾部换行策略；遇到错误树时拒绝输出部分结果。
- **可选名字解析**：`analyzer` 包通过调用方注入的 `Catalog` 解析 DML/DDL 目标表，不把元数据依赖带入语法解析。
- **库与 CLI**：核心解析能力以 MoonBit library packages 提供，`fathom-sql/` 包含 native CLI 适配器；仓库没有部署服务。

## 安装

本仓库不包含 Node.js package 清单或其他运行时依赖；模块元数据位于 `moon.mod`，当前记录的 MoonBit CLI 版本为 `moon 0.1.20260724`。请先安装与该版本线兼容的 MoonBit CLI（安装来源不在仓库内）。<!-- VERIFY: MoonBit CLI 的平台安装方式需以外部官方发行说明为准。 -->

在仓库根目录执行检查：

```bash
moon version
moon check
```

模块没有需要额外下载的 MoonBit 依赖；`moon check` 会构建当前模块及其库包。

## 快速开始

1. 安装 MoonBit CLI，并确认版本：

   ```bash
   moon version
   ```

2. 检查库代码：

   ```bash
   moon check
   ```

3. 在自己的 MoonBit package 中导入 `fathom/sql/api`，然后调用 `parse_with_ids` 或 `format_with_ids`（示例见下文）。

## 使用示例

### 解析有效 SQL

`api` facade 接收原始 `Bytes`，返回包含 primitive CST、profile 元数据和诊断数组的 `ParseResult`：

```moonbit
import {
  "fathom/sql/api" @api,
}

let parsed = @api.parse_with_ids(b"SELECT 1", "4.x", "strict")
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

let parsed = @api.parse_with_ids(b"SELECT 1 +", "4.x", "editor")
match parsed {
  Ok(result) => {
    // result.valid == false
    // result.recovered == true
    // result.root 中包含 missing 或 error 节点
    // @printer.print_result(result) 仍可重放原始字节 b"SELECT 1 +"
    println(result.diagnostics[0].code) // DORIS-PARSE-002
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
source/     源码快照、字节 Span 与行索引
lexer/      Doris profile 感知的词法分析
token/      token 类型、关键字分类和 Doris profile 元数据
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

## 许可证

仓库当前未包含 `LICENSE` 文件，许可证类型及链接待确认。
