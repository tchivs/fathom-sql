# jetbrains

> [根级 CLAUDE.md](../CLAUDE.md) › jetbrains

## 职责

IntelliJ IDEA 插件，基于 LSP4IJ 启动本地 `fathom-lsp` 语言服务器。
支持两种二进制来源：用户配置的 `executablePath`，或从 GitHub Releases 自动下载并校验。
强制显式 dialect/profile 选择（D-02/D-05），设置持久化于 `fathom.xml`。

## 关键文件

- `src/main/kotlin/fathom/jetbrains/sql/FathomLanguageServerFactory.kt` — `LanguageServerFactory` 实现，构造 `OSProcessStreamConnectionProvider` 并注入 `initializationOptions`
- `src/main/kotlin/fathom/jetbrains/sql/FathomSettings.kt` — 应用级 `PersistentStateComponent`，校验 dialect/profile 配对，持久化到 `fathom.xml`
- `src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt` — 从 GitHub Releases 下载平台二进制，SHA-256 校验，带 24h TTL 缓存
- `src/main/kotlin/fathom/jetbrains/sql/FathomSettingsConfigurable.kt` — IDE 设置面板 UI
- `build.gradle.kts` — Gradle 构建，依赖 LSP4IJ 0.20.1

## 公开接口

| 符号 | 说明 |
|---|---|
| `FathomLanguageServerFactory` | LSP4IJ 工厂；`createConnectionProvider` 启动 fathom-lsp 进程 |
| `FathomSettings` | 设置服务；`getInstance()`、`snapshot()`、`update()` |
| `FathomSettings.Configuration` | 不可变快照：`executablePath`/`dialect`/`profile`/`useGitHubReleases` |
| `FathomNativePlatform.detect()` | 按 OS/arch 识别平台（linux-x86_64/macos-x86_64/macos-aarch64/windows-x86_64） |

## 依赖

- IntelliJ Platform IC 2025.2（`sinceBuild = "252"`）
- `com.redhat.devtools.lsp4ij` 0.20.1 — LSP 服务器集成框架
- Kotlin 2.4.10，JVM 21 toolchain
- 外部二进制 `fathom-lsp`（GitHub Releases，仓库 `tchivs/fathom-sql`）

## 测试

`./gradlew test`（JUnit Platform）。测试文件位于 `src/test/kotlin/fathom/jetbrains/sql/`：
- `FathomLanguageServerFactoryTest.kt` — 工厂与可执行路径解析
- `FathomSettingsTest.kt` — 设置校验与持久化
- `FathomNativeDownloaderTest.kt` — 下载器、SHA-256 校验与缓存

Plugin Verifier 校验 `252`–`261.*` 兼容性。

## 注意事项

- 下载器仅接受 `https://github.com` 且路径匹配仓库 `releases/download/` 的资产 URL
- 二进制与元数据（`latest.json`）写入用户缓存目录；元数据路径做 `normalize()` 防路径穿越
- `useGitHubReleases=false` 时直接使用 `executablePath`；下载失败时回退到配置路径并记录警告
- dialect/profile 无默认值；空值或跨方言组合在 `FathomSettings.loadState`/`update` 中被拒绝
