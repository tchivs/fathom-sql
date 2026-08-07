# Phase 10: Flink Release Profiles and Lexical Core - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-07
**Phase:** 10-flink-release-profiles-and-lexical-core
**Areas discussed:** FlinkProfile 模型, Calcite pin 提取, 词法 fixture 化, 错误面与诊断, 词法作用域, baseline 关系
**Mode:** --auto（用户以「继续」延续 Phase 9 的 auto 链；所有灰区自动选择推荐项，单次通过）

---

## FlinkProfile 模型

| Option | Description | Selected |
|--------|-------------|----------|
| 闭合枚举 + metadata（DorisProfile 同构） | FlinkProfile::V2_3_0/V2_1_3/V1_20_5 + FlinkProfileMetadata（calcite_version/parser_config），经 validate_dialect_profile 统一校验 | ✓ |
| string-keyed 软校验 | 不引入类型，直接按字符串校验 | |

**User's choice:** 推荐项（闭合枚举 + metadata）— D-01
**Notes:** 延续 D-05（Phase 9 已定 FlinkProfile 类型名）与 CORE-01 显式校验传统；id 形态 `flink-<version>` 与 Doris `2.1/3.x/4.x` 完全独立。

## Calcite pin 提取

| Option | Description | Selected |
|--------|-------------|----------|
| 钉住 release 源码归档 + POM 提取 | 下载校验和匹配的 flink-*-src.tgz，读 release POM 的 Calcite 依赖与 parser 配置，脚本/测试固化为 metadata | ✓ |
| 手写常量 | 由维护者直接填写 calcite 版本 | |

**User's choice:** 推荐项（release 提取）— D-02
**Notes:** SC2 明文要求 2.1.3 的精确 pin 从该 release 提取而非推断；Validation 要求读取每个 release 的 parser 配置/POM。

## 词法 fixture 化

| Option | Description | Selected |
|--------|-------------|----------|
| 可执行 release fixture + parity 快照组 | SQL 输入 + 期望分类快照进入 parity/ flink-lexical 组，D-08 门禁复用 | ✓ |
| 仅手写测试期望 | 不下载/钉住 release 事实源 | |

**User's choice:** 推荐项（fixture 化）— D-03/D-04
**Notes:** Research flags 明文要求用可执行 release fixture 核验双引号/`#`/`//`/X/U&/B 行为而非 Calcite folklore。

## 错误面与诊断

| Option | Description | Selected |
|--------|-------------|----------|
| 复用 FATHOM-SCHEMA-* profile 错误族 | 与 Doris unknown profile 同族；dialect 不进 code 前缀（D-10） | ✓ |
| 新增 FATHOM-FLINK-* 命名空间 | 为 flink 单开错误码族 | |

**User's choice:** 推荐项（复用 SCHEMA 错误族）— D-05
**Notes:** D-10（Phase 9）已定诊断 code 为稳定公共契约且 dialect 不编码进前缀。

## 词法作用域

| Option | Description | Selected |
|--------|-------------|----------|
| 全量文档化集合（release grammar 核验） | 注释（--、/* */、# 按 release）、引号（'、"、` 按 Flink 配置）、X/U&/B/E 字面量、运算符 token 集、标识符大小写/unicode | ✓ |
| 子集先行 | 推迟生僻字面量 | |

**User's choice:** 推荐项（全量集合 + release 核验）— D-03
**Notes:** SC3 明文点名 X/U&/B；冲突矩阵覆盖 comment/quote/literal/identifier/operator/unknown-profile × 双方言。

## baseline 关系

| Option | Description | Selected |
|--------|-------------|----------|
| flink-lexical 快照组并入 parity/，Doris 组零漂移 | 同门禁、分组独立；Doris 字节变更须注册批准 | ✓ |
| 独立 flink corpus 目录 + 独立 gate | 与既有门禁分离 | |

**User's choice:** 推荐项（同门禁分组）— D-04
**Notes:** D-07/D-08（Phase 9）已冻结 Doris baseline 并建立注册表批准制；Flink 快照沿用同制。

## Claude's Discretion

无 — 所有灰区均由既有决策链（Phase 9 D-01..D-11 + 本阶段 D-01..D-06）明确覆盖。

## Deferred Ideas

- Flink grammar（FLINK-02..05）→ Phase 11
- Flink 工具链 → Phase 13
- 全量 Flink corpus/parity → Phase 12
- 自动方言检测 → 未来阶段
- transpile → CONVERT-FUTURE-01
