# Doris SQL Parser SDK — AI 上下文

> 本文件由 `/init` 生成，供 AI 助手快速建立项目全景认知。根级简明，模块级详尽。

## 项目概述

**Fathom SQL Parser SDK** 是面向 Apache Doris 与 Flink SQL 的开源解析基础设施。
核心使用 [MoonBit](https://docs.moonbitlang.com/) 手写递归下降 Parser + Pratt 表达式解析，
从同一份代码编译 Native CLI/LSP 与 Wasm/JS SDK 三后端。

**核心差异化**：无损 CST（Concrete Syntax Tree）—— 保留注释、空白、换行和源码位置，
使格式化、诊断与编辑器能力可 round-trip 而不破坏用户源码。

| 维度 | 值 |
|---|---|
| 语言 | MoonBit v0.1.20260724（v0.10.5 文档线） |
| 后端 | Native / JS (ESM) / Wasm（线性） |
| 方言 | Doris (2.1/3.x/4.x)、Flink (flink-1.20.5/2.1.3/2.3.0) |
| 模块名 | `fathom/sql` |
| 产品版本 | 1.0.4 |
| 源码规模 | 96 .mbt 文件，~53K 行 |
| 模块数 | 23 MoonBit 包 + npm/vscode/jetbrains/web 生态层 |

## 架构图

```mermaid
graph TD
    subgraph "MoonBit 核心 (同一代码库 → 三后端)"
        SOURCE[source<br/>源码文本 & Span]
        TOKEN[token<br/>词法 Token]
        LEXER[lexer<br/>词法分析器]
        SYNTAX[syntax<br/>无损 CST 节点]
        DIALECT[dialect<br/>方言策略 & 关键字]
        PARSER[parser<br/>递归下降 + Pratt]
        PRINTER[printer<br/>无损回放]
        FORMATTER[formatter<br/>格式化引擎]
        ANALYZER[analyzer<br/>名称解析 & Catalog]
        LINT[lint<br/>规则引擎]
        FINGERPRINT[fingerprint<br/>SQL 指纹]
        LINEAGE[lineage<br/>列级血缘]
        COMPLETION[completion<br/>补全]
        API[api<br/>统一公开门面]
        BINDING[binding<br/>FFI 导出层]
        LSP[lsp<br/>LSP 服务器]
    end

    subgraph "Native 可执行"
        CLI[fathom-sql<br/>CLI 工具]
        LSPBIN[fathom-lsp<br/>独立 LSP]
        VERSION[version<br/>版本标识]
    end

    subgraph "生态层"
        NPM[npm<br/>@fathom-sql/sql]
        VSCODE[vscode<br/>VS Code 扩展]
        JETBRAINS[jetbrains<br/>IDEA 插件]
        WEB[web<br/>Monaco 演示]
    end

    subgraph "质量保证"
        TEST[test<br/>黑盒集成测试]
        PARITY[parity<br/>跨后端一致性]
        BENCH[benchmarks<br/>性能基准]
        CORPUS[corpus<br/>Doris/Flink 语料库]
    end

    SOURCE --> TOKEN & LEXER & SYNTAX & PRINTER
    DIALECT --> TOKEN & LEXER & PARSER
    LEXER --> PARSER
    PARSER --> SYNTAX
    SYNTAX --> PRINTER & FORMATTER & ANALYZER & LINT & FINGERPRINT & LINEAGE & COMPLETION
    ANALYZER --> LINT & LINEAGE
    FORMATTER --> LINT
    API --> SOURCE & PARSER & SYNTAX & FORMATTER & DIALECT & FINGERPRINT & LINT & ANALYZER & LINEAGE
    BINDING --> API & SOURCE & COMPLETION & ANALYZER
    LSP --> API & BINDING & COMPLETION & SOURCE
    CLI --> API & BINDING & LSP & VERSION
    LSPBIN --> LSP & VERSION
    NPM --> BINDING
    VSCODE --> LSPBIN
    JETBRAINS --> LSPBIN
    WEB --> NPM
    TEST & PARITY --> API & BINDING & PARSER
    CORPUS --> TEST & PARITY
    BENCH --> API & PARSER
```

## 模块索引

### 核心解析管线

| 模块 | 职责 | 源行数 | 关键文件 |
|---|---|---|---|
| [source](./source/CLAUDE.md) | 不可变源码快照、Span、字节坐标 | 257 | `source.mbt` |
| [token](./token/CLAUDE.md) | Token 数据结构、Trivia 分类 | 71 | `token.mbt` |
| [lexer](./lexer/CLAUDE.md) | 同步源码回退词法分析器 | 1,549 | `lexer.mbt` |
| [syntax](./syntax/CLAUDE.md) | 无损 CST 节点与元素 | 380 | `syntax.mbt` |
| [dialect](./dialect/CLAUDE.md) | 方言枚举、关键字分类、Profile 元数据 | 2,708 | `dialect.mbt` `doris.mbt` `flink.mbt` |
| [parser](./parser/CLAUDE.md) | 递归下降 + Pratt 表达式解析器 | 11,451 | `parser.mbt` `flink_grammar.mbt` |

### 输出与分析

| 模块 | 职责 | 源行数 | 关键文件 |
|---|---|---|---|
| [printer](./printer/CLAUDE.md) | 无损字节回放 | 184 | `printer.mbt` |
| [formatter](./formatter/CLAUDE.md) | 格式化引擎（拒绝优先） | 1,518 | `format.mbt` `layout.mbt` `options.mbt` |
| [analyzer](./analyzer/CLAUDE.md) | 名称解析、Catalog 接口 | 3,734 | `analyzer.mbt` `resolve.mbt` `select_model.mbt` |
| [lint](./lint/CLAUDE.md) | Lint 规则引擎与自动修复 | 880 | `engine.mbt` `rules.mbt` `registry.mbt` `fixes.mbt` |
| [fingerprint](./fingerprint/CLAUDE.md) | SQL 规范化指纹 | 179 | `normalize.mbt` `hash.mbt` |
| [lineage](./lineage/CLAUDE.md) | 列级血缘推导 | 1,630 | `edges.mbt` `model.mbt` `views.mbt` |
| [completion](./completion/CLAUDE.md) | 语法补全 | 494 | `completion.mbt` |

### 公开接口与适配器

| 模块 | 职责 | 源行数 | 关键文件 |
|---|---|---|---|
| [api](./api/CLAUDE.md) | 统一公开门面（Parse/Format/Lint/...） | 1,374 | `api.mbt` |
| [binding](./binding/CLAUDE.md) | FFI 导出（JS ESM + Wasm） | 1,357 | `exports.mbt` `schema.mbt` `json.mbt` |
| [lsp](./lsp/CLAUDE.md) | LSP 3.17 stdio 服务器 | 2,031 | `handlers.mbt` `serve.mbt` `framing.mbt` `protocol.mbt` |

### Native 可执行

| 模块 | 职责 | 源行数 | 关键文件 |
|---|---|---|---|
| [fathom-sql](./fathom-sql/CLAUDE.md) | CLI 工具（parse/format/lsp） | 976 | `main.mbt` `run.mbt` `args.mbt` `ffi.mbt` |
| [fathom-lsp](./fathom-lsp/CLAUDE.md) | 独立 LSP 服务器 | 14 | `main.mbt` |
| [version](./version/CLAUDE.md) | 产品版本标识 | 52 | `version.mbt` |

### 质量与语料

| 模块 | 职责 | 源行数 | 关键文件 |
|---|---|---|---|
| [test](./test/CLAUDE.md) | 黑盒集成测试（15 个测试文件） | — | `*_test.mbt` |
| [parity-tests](./parity-tests/CLAUDE.md) | 跨后端一致性验证 | — | `*_test.mbt` |
| [benchmarks](./benchmarks/CLAUDE.md) | 性能基准 | 236 | `bench.mbt` |
| [corpus](./corpus/CLAUDE.md) | Doris/Flink 语料库与覆盖报告 | — | `doris-*/` `requirements.txt` |

### 生态层

| 模块 | 职责 | 语言 |
|---|---|---|
| [npm](./npm/CLAUDE.md) | `@fathom-sql/sql` npm 包（JS/TS 包装） | JS/TS |
| [vscode](./vscode/CLAUDE.md) | VS Code 语言客户端扩展 | TS |
| [jetbrains](./jetbrains/CLAUDE.md) | IntelliJ IDEA 插件 | Kotlin/Gradle |
| [web](./web/CLAUDE.md) | Monaco 编辑器离线演示 | TS |

## 全局规范

### 构建

```bash
moon check                              # 类型检查全部包
moon build --target native --release    # 构建 Native CLI
moon build --target js --release binding    # 构建 JS binding
moon build --target wasm --release binding  # 构建 Wasm binding
moon test                               # 运行所有测试
moon test --enable-coverage             # 覆盖率
moon fmt                                # 格式化
node npm/build.mjs                      # 构建 npm 包
```

### 依赖方向（严格分层）

```
source          ← 无依赖（基石）
  ↑
token / syntax / dialect    ← 仅依赖 source
  ↑
lexer          ← source + token + dialect
  ↑
parser         ← source + token + lexer + syntax + dialect
  ↑
printer / formatter / analyzer / lint / fingerprint / lineage / completion
  ↑
api            ← 聚合所有核心包
  ↑
binding / lsp  ← api + 适配
  ↑
fathom-sql / fathom-lsp  ← 可执行入口
```

**禁止**：parser 不得 import analyzer（D-21 Pitfall 7）；source/syntax 不得依赖 dialect；
binding 是唯一的 FFI 边界。

### 关键不变量

1. **无损 round-trip**：`print_lossless(parse(input)) == input` — 每个源字节都被 Token/Trivia span 覆盖
2. **格式化幂等**：`format(format(x)) == format(x)`
3. **方言隔离**：Flink 请求绝不回退到 Doris 语法（DIALECT-03）
4. **无元数据降级**：无 Catalog 时仍支持纯前端语法校验
5. **关键字单一来源**：所有关键字判断通过 `@dialect.classification_of`，禁止第二张表

### Conventional Commits

提交信息遵循 [Conventional Commits](https://www.conventionalcommits.org/) 格式。
自动关闭 issue 需在 message 中包含 `Fixes #N` / `Closes #N` / `Resolves #N`。
详见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

### CI

CI 在 push/PR 时执行（`.github/workflows/ci.yml`）：
- `moon fmt --check` — 格式检查
- `moon check --target native` — Native 类型检查
- `moon check --target js` + `--target wasm` — 跨后端检查
- `moon test --target native` — 测试
- 跨后端一致性验证（parity）

### 交付渠道

1. **npm** `@fathom-sql/sql` — JS ESM + Wasm + TypeScript 类型
2. **VS Code** 扩展 — 语言客户端，连接 Native LSP
3. **JetBrains** 插件 — IDEA 语言服务器集成
4. **Native CLI** `fathom-sql` — 命令行 parse/format/lsp
5. **Web** — Monaco 演示页

## 详细文档

| 文档 | 路径 | 内容 |
|---|---|---|
| API 参考 | [docs/API.md](./docs/API.md) | 公开 API 签名与用法（[中文](./docs/zh-CN/API.md)） |
| 系统架构 | [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | 组件图与分层管线详解（[中文](./docs/zh-CN/ARCHITECTURE.md)） |
| 开发指南 | [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md) | 本地开发、构建、语料维护（[中文](./docs/zh-CN/DEVELOPMENT.md)） |
| 测试指南 | [docs/TESTING.md](./docs/TESTING.md) | 测试框架、运行方式、覆盖策略（[中文](./docs/zh-CN/TESTING.md)） |
| 版本策略 | [docs/VERSIONING.md](./docs/VERSIONING.md) | 产品 semver 与 release tag 规范 |
| 入门指南 | [docs/GETTING-STARTED.md](./docs/GETTING-STARTED.md) | 环境搭建与快速上手（[中文](./docs/zh-CN/GETTING-STARTED.md)） |
| 配置说明 | [docs/CONFIGURATION.md](./docs/CONFIGURATION.md) | 环境变量与配置文件（[中文](./docs/zh-CN/CONFIGURATION.md)） |
| 贡献指南 | [CONTRIBUTING.md](./CONTRIBUTING.md) | 提交规范与 issue 自动关闭 |
| 变更日志 | [CHANGELOG.md](./CHANGELOG.md) | 用户可见变更记录 |
| 语料报告 | [corpus/CORPUS-REPORT.md](./corpus/CORPUS-REPORT.md) | Doris/Flink 语法覆盖率 |
