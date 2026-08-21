# vscode

> [根级 CLAUDE.md](../CLAUDE.md) › vscode

## 职责

标准 VS Code 语言客户端扩展，连接本地 `fathom-lsp` 二进制（stdio 传输）。
不内嵌任何解析逻辑，仅作为 LSP 客户端转发 `dialect` / `profile` 初始化选项。
强制显式方言/profile 选择（D-02/D-05）——缺失或不匹配时拒绝启动服务器。

## 关键文件

- `src/extension.ts` — 扩展入口 `activate`/`deactivate`；创建 `LanguageClient`，处理重启命令与状态栏
- `src/extension-contract.ts` — 契约常量与 `resolveFathomConfiguration`：`SUPPORTED_DIALECTS`、`PROFILES_BY_DIALECT`、`SERVER_FAILURE_MESSAGE`
- `language-configuration.json` — SQL 语言括号/注释配置
- `src/extension.test.ts` — 入口与契约的单元测试

## 公开接口

| 符号 | 说明 |
|---|---|
| `activate(context)` | 扩展激活入口；读取配置并启动 LSP 客户端 |
| `deactivate()` | 停止客户端并清理状态栏 |
| `createServerOptions(serverPath)` | 构造 stdio `ServerOptions`（run/debug 同一本地命令） |
| `resolveFathomConfiguration(configuration)` | 读取 `dialect`/`profile`/`serverPath`，无效则返回 `undefined` |
| `PROFILES_BY_DIALECT` | 按 dialect 分组的 profile 常量映射 |
| `fathom.restartLanguageServer` | 命令：重启语言服务器 |

## 依赖

- `vscode-languageclient` 10.1.0 — LSP 客户端库
- 外部二进制 `fathom-lsp`（由 `fathom.serverPath` 指定，默认 `fathom-lsp`）

## 测试

`npm test` 运行 `src/extension.test.ts`；`npm run host-verify` 编译后执行宿主环境校验脚本。
构建：`npm run build` → `tsc`；打包：`npm run package` → `vsce package`。

## 注意事项

- 配置 `fathom.dialect`（`doris`/`flink`）与 `fathom.profile` 无默认值；缺失时扩展显示错误并不启动服务器
- profile 必须与 dialect 配对（如 flink → `flink-2.3.0`）；跨方言 profile 被拒绝，不强制回退
- 仅支持 `file` scheme 的 `sql` 文档；不使用远程服务器，无网络回退
