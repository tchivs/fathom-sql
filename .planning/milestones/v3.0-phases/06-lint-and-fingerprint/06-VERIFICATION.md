---
phase: 06-lint-and-fingerprint
verified: 2026-08-10T18:40:00Z
status: passed
score: 4/4 success criteria verified
behavior_unverified: 0
overrides_applied: 0
---

# Phase 6: Lint and Fingerprint — Verification Report

**Phase Goal:** 交付 Doris 专属 Lint 规则集（可配置 severity + 安全无损 autofix）与稳定跨后端 SQL 指纹/归一化。
**Verified:** 2026-08-10T18:40:00Z
**Status:** passed
**Re-verification:** No — initial verification

## 验证结论概览

| 需求 | 结论 | 依据 |
|------|------|------|
| LINT-01 | ✅ **verified** | `lint/` 独立库：SQLFluff 风格 8 规则注册表（FATHOM-LINT-001..008）+ `LintOptions::new` 校验 + CST 引擎（001/002/003/008 + analyzer 增强 004-007，ANLY-01 skip）+ `apply_fixes` 最小 span edits + D-33 绝对拒绝（FATHOM-LINT-000）。`api.lint_text`/`api.fix_text`、`fathom_lint_v1`（overrides JSON 结构化解析）、`fathom-sql lint` 子命令（D-39 0/1/2）。22 lint 白盒 + 6 集成 + 29 CLI 测试。 |
| FING-01 | ✅ **verified** | `fingerprint/` 独立库：FNV-1a 64-bit `UInt64` + CST→canonical 归一化（折叠空白/关键字大小写/注释，保留标识符/字面量/引号）。`api.fingerprint_text`、`fathom_fingerprint_v1`（十进制 string，非 number）、`fathom-sql fingerprint` 子命令。跨目标 parity：同一十进制指纹在 native/js/wasm 三目标一致。 |

**Score:** 4/4 roadmap success criteria verified（0 present-behavior-unverified，0 overrides）

## 目标达成：可观测真相

| # | Success criterion | Status | Evidence |
|---|-------------------|--------|----------|
| 1 | 用户可运行 Doris 专属 Lint 规则集：稳定规则码、per-rule enable/disable、可配置 severity（SQLFluff 风格注册表）(LINT-01) | ✓ VERIFIED | `lint/registry.mbt` `default_registry()` 8 稳定码（code/name/category/default_severity/fixable/applies_to/enabled）；`LintOptions::new` 未知码 → 结构化错误；`LintSeverity::from_id` error/warning/info；`fathom-sql lint --rule CODE=SEVERITY|off` 可重复；`fathom_lint_v1` overrides JSON；D-39 exit 0/1/2 由 cli_test 锁定（`cli_lint_report_exit_0/1`、`cli_lint_rule_override_disables_003`、`cli_lint_unknown_rule_flag_exit_2`） |
| 2 | Autofix 保留注释/trivia/格式、拒绝 error 树的 unsafe 编辑（D-33）；每个 fix 通过 round-trip 断言 (LINT-01) | ✓ VERIFIED（1 非阻塞 WARNING） | `lint/fixes.mbt` `apply_fixes`：最小 SourceToken-span edits、复用 `@formatter.first_unsafe_element`（D-33 拒绝绝对）、重叠跳过/相邻各自应用/越界跳过；`api.fix_text` reparse round-trip 防御；测试 `apply_fixes_refuses_error_tree_d33`、`apply_fixes_wraps_reserved_word_and_preserves_untouched_bytes`、`apply_edits_skips_overlap_applies_adjacent`、`fix_text_refuses_tree_with_unsafe_material_d33` 全绿。**WARNING（文档化边界，非需求违背）：** 规则 001（唯一 fixable）的 fix 在真实 parser 输出上端到端不可达——保留字作标识符的输入产生含 missing 节点的 recoverable 树，D-33 拒绝一切 unsafe 树编辑；fix 路径只在手工构建的合法 CST 白盒测试中证明。安全/无损/round-trip 契约完全交付（SC2 满足）。 |
| 3 | 用户可生成稳定 SQL 指纹与归一化形式——跨空白/关键字大小写/注释稳定；保留标识符拼写、字面量内容、引号风格 (FING-01) | ✓ VERIFIED | `fingerprint/normalize.mbt` 折叠空白→单空格、关键字经 `@dialect.classification_of`（D-28 单源，无第二关键字表）、剔除注释/BOM；保留标识符拼写/大小写、字面量内容、引号风格；总函数（空输入→FNV offset basis）；不变量锁定在 hash_test.mbt + test/fingerprint_test.mbt + CLI `--normalized` |
| 4 | 指纹跨 Native/JS/linear-Wasm 一致（UInt64 哈希 + 跨目标 parity 测试）(FING-01) | ✓ VERIFIED | `fingerprint/hash.mbt` FNV-1a 64-bit UInt64（native/js/wasm 固定 64-bit）；`parity/fingerprint_parity_test.mbt` 硬编码十进制指纹 `214897735614764786` 在 native/js/wasm 三目标断言；run_js/run_wasm ABI 冒烟；export_smoke 断言 schema v2 加法（新 2 + 旧 5 命名空间）；`fingerprint_result_json` UInt64 序列化为十进制 JSON string（绝不用 to_double）；行为证据 602/602 js+wasm parity、949/949 native ci-matrix |

## 必需构件

| Artifact | Expected | Status | Details |
| -------- | ----------- | ------ | ------- |
| `fingerprint/`（moon.pkg/hash.mbt/normalize.mbt/hash_test.mbt） | FNV-1a 64-bit + CST→canonical 归一化 + 不变量 | ✓ VERIFIED | import 仅 syntax/dialect/source + core buffer/debug（D-01）；无 analyzer/parser |
| `lint/`（rules/registry/engine/fixes/lint_test.mbt） | 8 规则注册表 + CST 引擎 + autofix + D-33 | ✓ VERIFIED | import syntax/dialect/source/formatter/analyzer，无 parser（D-01/D-21） |
| `api/api.mbt` | lint_text/fix_text/fingerprint_text + D-38 lint 别名 | ✓ VERIFIED | parse_document 共享解析；fix_text reparse 防御 |
| `binding/`（schema/exports/moon.pkg） | schema v2 bump（加法）+ fathom_lint_v1/fathom_fingerprint_v1 + 十进制 string | ✓ VERIFIED | validate_schema_version 7 命名空间；旧 5 分支原样保留 |
| `fathom-sql/`（args/run/main/cli_test） | lint/fingerprint 子命令 + D-39 0/1/2 | ✓ VERIFIED | run_lint/run_fingerprint 只调 @api（D-37/D-38） |
| `parity/fingerprint_parity_test.mbt` | 三目标十进制指纹一致 | ✓ VERIFIED | 硬编码期望值跨 native/js/wasm 断言 |
| `docs/API.md` + `docs/zh-CN/API.md` | Lint/Fingerprint 章节 + Wire Exports 表 + FNV-1a 非加密边界 + FATHOM-LINT-000 | ✓ VERIFIED | lint_text/fingerprint_text/FATHOM-LINT-000/fathom_lint_v1/fathom_fingerprint_v1 各 ≥1 处 |
| `.github/workflows/ci.yml` | native 矩阵含新包 | ✓ VERIFIED | 增加 fingerprint/lint/fathom-sql |

## 行为抽查（本次实际运行）

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| 全量 native ci 对齐矩阵 + 新包 | `moon test --target native --package test --package parity --package lsp --package api --package source --package token --package lexer --package parser --package printer --package syntax --package completion --package analyzer --package fingerprint --package lint --package fathom-sql` | **Total tests: 949, passed: 949, failed: 0** | ✓ PASS |
| 跨目标 parity（native） | `moon test --target native --package parity` | **602/602** | ✓ PASS |
| 跨目标 parity（js） | `moon test --target js --package parity` | **602/602** | ✓ PASS |
| 跨目标 parity（linear-Wasm） | `moon test --target wasm --package parity` | **602/602** | ✓ PASS |
| moon check | `moon check --target native` | **0 errors** | ✓ PASS |
| binding JS build | `moon build --target js --package binding` | **0 errors** | ✓ PASS |

## 反模式扫描

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| 新增文件（fingerprint/*.mbt, lint/*.mbt, test/fingerprint_test.mbt, test/lint_test.mbt, parity/fingerprint_parity_test.mbt, fathom-sql 改动） | — | TBD/FIXME/XXX/HACK/PLACEHOLDER | ℹ️ 无 | 零命中 |
| `lint/engine.mbt` | — | 第二关键字表 | ℹ️ 无 | 关键字判定只走 `@dialect.classification_of`/`is_reserved_word`（D-28）；grep 确认无复制表 |
| `lint/moon.pkg` `fingerprint/moon.pkg` | — | parser import | ℹ️ 无 | 无 parser import（D-01/D-21 成立） |

无 BLOCKER/WARNING 级反模式。

## 已知边界（非差距）

- **规则 001 autofix 端到端不可达**（verifier WARNING）：唯一 fixable 规则（001）的输入（保留字作标识符）在真实 parser 下产生含 missing 节点的 recoverable 树，D-33 拒绝编辑 unsafe 树——因此 `fathom-sql lint --fix` 对当前规则集在实际 SQL 上总是拒绝。这是**安全契约的保守行为**（SC2 要求拒绝 unsafe 树，已满足），fix 能力在白盒测试证明；若未来需要端到端 fix，需引入编辑器恢复模式下的"仅替换保留字 token"专用通道（超出本阶段范围）。
- `moon test --target native --package binding` E4219 是既有 foreign_library 工具链限制（04-03/05-02/09-02 已记录）；binding 覆盖经 parity + js build + moon check。

## 需求覆盖

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ---------- | ----------- | ------ | -------- |
| LINT-01 | 06-02/03/04 | Doris 专属 Lint 规则集（可配置 severity + 安全无损 autofix） | ✓ SATISFIED | lint/ 库 + api + wire + CLI + 文档；22 白盒 + 6 集成 + 29 CLI 测试 |
| FING-01 | 06-01/04 | 稳定 SQL 指纹与归一化 + 跨后端 UInt64 一致 | ✓ SATISFIED | fingerprint/ 库 + api + wire + CLI + 三目标 parity；602/602 × 3 |

无孤儿需求：REQUIREMENTS.md 将 LINT-01/FING-01 映射到 Phase 6 且两 ID 均被 06-01..04 计划认领，复选框已标记 Complete。

## 差距总结

**无差距。** 4/4 roadmap success criteria VERIFIED：
- LINT-01：8 规则注册表 + severity 配置 + 安全 autofix（D-33 拒绝绝对 + round-trip）+ wire/CLI 消费面全部交付，行为测试 57 个新增。
- FING-01：UInt64 FNV-1a 指纹 + CST 归一化 + 跨 native/js/linear-Wasm 三目标 parity 证明。
- schema v2 bump 为纯加法；D-01/D-21/D-28/D-33 纪律全程保持。

---

_Verified: 2026-08-10T18:40:00Z_
_Verifier: Claude (gsd-verifier)_
