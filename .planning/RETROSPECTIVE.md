# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v2.0 — Multi-Dialect: Flink SQL & Neutral Naming

**Shipped:** 2026-08-10
**Phases:** 5 (9-13) | **Plans:** 24 | **Tasks:** 61

### What Was Built
- 单方言 Doris 解析器 → 多方言 SQL SDK：Flink SQL 全链（release-pinned profiles `flink-2.3.0/2.1.3/1.20.5`、独立词法核心、grammar + 可恢复无损 CST、formatter、completion、analyzer、CLI/LSP）
- 产品命名中立化：`fathom-sql`/`fathom-lsp`/`fathom/sql` 模块/`fathom.*.v1` wire 契约（新增 `fathom.complete.v1`）+ `check_naming.py` 命名门禁
- 跨方言 release-pinned corpus + parity 门禁：110-fixture manifest、`diff_parity --frozen-only`、Native/JS/linear-Wasm 三目标字节级一致、全程离线
- 三宿主（Web/Monaco、VS Code、IntelliJ）per-dialect (dialect, profile) 二元组校验 + 真 extension-host/Gradle/Chromium 打包 smoke
- 24/24 v2 需求验证通过，Doris 冻结 baseline 零漂移，verifier 28/28，threats_open 0

### What Worked
- **冻结 baseline 纪律**（D-08/12）：任何共享改动先跑 `diff_parity --frozen-only`，CI 零 `--update` —— 整个 v2.0 期间 Doris 快照 455 个 0 漂移，杜绝静默回归
- **单一事实源纪律**（D-28）：补全候选只来自分类表、formatter 关键字改写只读 `classification_of` —— 无第二表，无列表漂移
- **显式选择 + no-guess**（D-01/02）：dialect/profile 全程显式，(dialect, profile) 二元组校验贯穿 CLI/wire/LSP/三宿主，无自动检测/静默回退
- **tracer-first 垂直切片**：每个 plan 先打通一条端到端路径再横向扩展，wave 依赖清晰（formatter/completion/analyzer → wire → hosts → smoke）
- **checkpoint:decision 门**：one-way 契约（`fathom.complete.v1`、选择模型）执行前显式确认

### What Was Inefficient
- **全工作区 native 测试被 E4219 阻塞**：`binding` 是 `foreign_library`，native 测试目标无法导入 —— 每个 plan 需显式排除 binding 包（既有约束，已知但反复踩）
- **代码评审落在验证之后**：verifier 28/28 通过后才跑 code-review，暴露 statement_id 硬编码（WR-01）、`is_incomplete` 谎报（WR-02）等本可提前抓到的缺陷 —— 建议 code-review 与 verification 并行或提前
- **auto-chain 单轮极长**：discuss→plan→execute→review→secure→milestone 全链在单会话内执行，context 消耗大、bash shell 偶发 wedged（改用 eval kernel 绕过）

### Patterns Established
- per-dialect `PROFILES_BY_DIALECT` 静态常量 + 服务端权威校验（纵深防御）
- `approved-changes.md` 注册表 + 单 `--update` 入口（快照变更须先登记）
- Flink 语句族 SyntaxKind 追加在 enum 末尾（Pitfall 1，保 frozen wire ordinal）
- wire 错误信封统一 `fathom.error.v1` + `FATHOM-SCHEMA-0XX`，dialect 只进 metadata（D-10）

### Key Lessons
1. 冻结 baseline + 零 `--update` 是跨重构安全的唯一可靠锚点 —— 它让每个 plan 敢动共享表
2. 补全/格式化的候选与改写必须只读单一关键字表，任何"专用表"都是漂移源
3. 文档级部分选择（只给 dialect 不给 profile）必须显式报错，绝不能静默落回 workspace 默认
4. code-review 应作为每 phase 的标准 gate，而非 milestone 收尾的补充

### Cost Observations
- Model mix: 100% sonnet（executor/verifier/reviewer/auditor 全部 inherit → sonnet）；orchestrator 主模型执行
- Sessions: 1（连续 auto-chain）
- Notable: 7 个 plan 每个 10-80 分钟；13-07 打包 smoke 最长（VS Code 真 extension-host 1h18m）

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | historical | 4 | 无损 CST 内核 + Doris 单方言 + 生态 |
| v2.0 | 1 | 5 | 多方言抽象 + Flink 全链 + 中立命名 + 冻结 parity 门禁 |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | 812 | high | 0 |
| v2.0 | 876 native / 597 js / 597 wasm | 28/28 must-haves | 0 |

### Top Lessons (Verified Across Milestones)

1. 冻结 baseline + 零 `--update` 是跨方言/跨命名重构的安全锚点（v1.0 → v2.0 全程 Doris 字节零漂移）
2. 显式 (dialect, profile) 选择 + no-guess 错误贯穿每一公共边界，防止静默回退
3. 单一事实源纪律（关键字表、UTF-16 转换器、catalog 接口）防止多实现漂移
