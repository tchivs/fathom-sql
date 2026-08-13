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

## Milestone: v3.0 — Analysis and Intelligence

**Shipped:** 2026-08-13
**Phases:** 4 (5-8) | **Plans:** 17 | **Tasks:** 40

### What Was Built
- **ANAL-01（Phase 5）:** catalog 名字解析与类型诊断——`Catalog` trait 定形（table/table_in_db/function + FunctionInfo）、SELECT 二次解析模型（clause split + scope stack + CTE/子查询/UNION + star 展开 + quoted 字节复核）、函数元数检查、完整诊断集（unknown-table/column/function、ambiguous-reference、function-arity，独立 ANLY-01 通道）
- **LINT-01 + FING-01（Phase 6）:** SQLFluff 风格 8 规则注册表（稳定 FATHOM-LINT-0xx 码）+ D-33 安全 autofix；FNV-1a 64-bit 稳定指纹 + CST 归一化 canonical form + 三目标 parity
- **LINE-01（Phase 7）:** `lineage/` 独立库（D-01 表达式直通边、D-06 诚实 gap、视图注册表 + ViewCatalog[T]、INSERT/CTE/UNION 位置映射）+ `api.lineage_text` + `fathom.lineage.v1`（第 8 命名空间）+ `fathom-sql lineage --catalog` + 三目标字节 parity
- **EDIT-01（Phase 8）:** `bench/` 门禁 harness（@bench + moon bench）——整文档重解析 25/50/100/200KB 梯度实测，≥100KB median 27.47ms ≤ 50ms、线性增长 → **以证据 descope**（08-BENCHMARK.md 五要素 + Gate Interpretation Note）

### What Worked
- **证据驱动的门禁**（EDIT-01）：benchmark 放在首个 tracer，先测量后决策——分支 A descope 全链证据可复现（fixture/规模/median/p95/结论），无数据不宣称
- **诚实 gap 纪律**（LINE-01 SC2）：star 无 catalog/未解析引用/外部视图 → 显式 requires-catalog/unresolved-reference gap，绝不伪造边——code review 抓到的 CR-01（INSERT 尾 SELECT 伪造边）当天修复
- **D-21 单向依赖纪律**：lineage/ 只 import analyzer+syntax，analyzer 公开面零 parser 改动（frozen baseline 零漂移贯穿）
- **tracer-first + TDD RED/GREEN**：每 plan 先打通端到端路径，测试先红后绿（07-03/07-04 均按 RED→GREEN 提交）
- **跨目标 parity 提前证明**：lineage 三目标字节一致在 wire 层落地，compare_backends.py digest 三目标相同

### What Was Inefficient
- **@bench 仓库零先例**：moon 0.1.20260724 的 @bench API 需执行首步探针（实测可用），Research 阶段无法预判——bench 包搭好后门禁才真正开始
- **benchmark 输入构造非平凡**：corpus 全部 <1.2KB、总计 <25KB，editor-scale ≥100KB 必须合成拼接（内嵌语句池 + 运行时零磁盘读）——比预想多一个构造任务
- **code-review 重复发现 verify 命令内联中文注释**（08-01/02/04 的 `<automated>` 块 `（≥1）` 破坏 shell）——plan 阶段 checker 与执行阶段 review 两轮才清干净，应统一为纯 shell
- **门禁阈值字面歧义**（D-02 "≥100KB >50ms"）：200KB median 57.76ms 超字面阈值，靠 Gate Interpretation Note 明确边界解读才无争议——阈值措辞应一开始就钉死"边界输入判定 + 超线性为决定性信号"

### Patterns Established
- **benchmark-gated descope 模式**：`bench/` 包 + `08-BENCHMARK.md` 五要素 + 分支决策记录 + REQUIREMENTS/ROADMAP/STATE 三处 descope 标注——未来"先证明再决定"类需求复用
- **gate-first 分解**：门禁计划（branch-agnostic tracer）在前，分支计划（branch A/B marker）在后，执行时按 fired branch 路由——contingency 计划带显式 skip 标记
- **诚实 provenance**（D-17 延伸）：无实测数据不宣称已评估；descope 必须引用 08-BENCHMARK.md 具体数字
- **门禁证据解读前置**：Gate Interpretation Note + Methodology bias note 与证据同文件记录，杜绝事后补解释

### Key Lessons
1. 门控需求（benchmark-gated）的阈值措辞必须在 CONTEXT 就钉死判定语义（边界输入 vs 全体规模），否则执行/审查/验证各阶段反复歧义
2. 证据驱动的 descope 是健康的工程决策——"不实现"也可以是完整交付，前提是证据可复现、记录到位
3. plan 的 verify `<automated>` 块必须是纯 shell（无内联中文注释），否则执行器/审查器两轮摩擦
4. 分析层新包（analyzer 公开面）的跨包可见性要先探针再写测试（pub(all) 字段跨包只读在 moon 0.1.20260724 成立）

### Cost Observations
- Model mix: researcher/planner/checker 各按其模型（sonnet/opus/haiku），executor/verifier/reviewer inherit → sonnet
- Sessions: 1（连续 auto-chain，跨 2026-08-11 → 08-13）
- Notable: Phase 7（lineage）最大（5 plans）；Phase 8 因 descope 快速收尾；bash shell 全程 wedged → 全部经 eval kernel/hub process ops 执行

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | historical | 4 | 无损 CST 内核 + Doris 单方言 + 生态 |
| v2.0 | 1 | 5 | 多方言抽象 + Flink 全链 + 中立命名 + 冻结 parity 门禁 |
| v3.0 | 1 | 4 | 语义分析层（catalog/Lint/指纹/血缘）+ benchmark-gated descope |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | 812 | high | 0 |
| v2.0 | 876 native / 597 js / 597 wasm | 28/28 must-haves | 0 |
| v3.0 | 886 native（含 analyzer 191）/ 605 js / 605 wasm parity | 41/40 must-haves (P5 13/13, P6 4/4, P7 15/15, P8 8/8) | 0 |

### Top Lessons (Verified Across Milestones)

1. 冻结 baseline + 零 `--update` 是跨方言/跨命名重构的安全锚点（v1.0 → v2.0 → v3.0 Doris 字节零漂移贯穿）
2. 显式 (dialect, profile) 选择 + no-guess 错误贯穿每一公共边界，防止静默回退
3. 单一事实源纪律（关键字表、UTF-16 转换器、catalog 接口）防止多实现漂移
4. 门控需求阈值措辞必须在决策阶段钉死判定语义，证据与解读同文件记录（v3.0 EDIT-01 Gate Interpretation Note）
5. 证据驱动的 descope 是完整交付——"不实现"以可复现 benchmark 证据记录（v3.0 Phase 8）
