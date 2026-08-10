---
phase: 12-cross-dialect-corpus-and-parity-gates
reviewed: 2026-08-09T00:00:00Z
depth: orchestrator-verified (gate execution + source inspection)
files_reviewed: 8
status: issues_found
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
---

# Phase 12: Code Review Report — Cross-Dialect Corpus and Parity Gates

**Reviewed:** 2026-08-09
**Depth:** orchestrator-verified（直接执行全部门禁 + 源码检查；原 reviewer 子代理在门禁子进程上挂起，未产出，已取消）
**Status:** issues_found (0 BLOCKER / 0 MAJOR / 0 MINOR / 3 INFO)

## Summary

Phase 12 把前序各阶段的分散门禁整合为可审计的跨方言 corpus 与 parity 契约。本评审由编排器直接验证（本会话执行全部三个门禁脚本 + 全套测试），外加门禁脚本源码检查：

- **verify_corpus.py（350 行）**：纯 Python stdlib，`sha256_file`/`sha512_file`，无 `subprocess`/`urllib`/`requests`/`socket`/`eval`/`exec` — 无网络面、无注入面；执行 `--check` exit 0（110 行 manifest 校验：header、PINS vs dialect/flink.mbt、6-category 枚举、expected-status、fixture sha256、快照完整性、104 个归档 sha512 复验）。
- **diff_parity.py（362 行）**：`--frozen-only`（CI 模式）对任何差异 exit 1、**不 consult 注册表**（源码 :19-23 明文）；`--approve <register>`（本地模式）按 key/prefix/field 行分类批准 vs 意外（:25-27）；restore lifecycle（:68,94,105）保证失败/中断后恢复已提交快照树；执行 `--frozen-only` exit 0（433 快照 0 差异，零残留）；注入漂移测试 exit 1。
- **compare_backends.py（306 行）**：三目标（native/js/wasm）各跑 `moon test --package parity`，fail-closed（空/跳过/失败目标 exit 1），对 committed `parity/__snapshot__` 树计算确定性 sha256 digest，运行前后校验 digest 证明只读；执行三目标全 PASS，**digest 完全一致**（5e9bb887e71ddc814d7cd86b4f0b0222352800ace927e20cdabd21057e22020c）。
- **CI 接线**（.github/workflows/ci.yml）：linear-wasm-parity 增 js 运行时步骤 + compare_backends 汇总；parity-gate 增 `diff_parity.py --frozen-only`；corpus job 增 `verify_corpus.py --check` + `generate_corpus_report.py --check`（语义区分硬规则）；无任何 `--update`，唯一网络步骤为 MoonBit 安装器 curl。
- **语义区分**：coverage 报告 parser-accepted=68 vs engine-semantic-prerequisite=19 分离，engine-supported=49（仅 positive）；catalog/planner/known-limitation 永不计入 engine-supported（--check 聚合交叉校验）。
- **Doris 零漂移**：812/812 测试；diff_parity 433 快照 0 差异；无 doris-named 快照变更。

## Info

### IN-01: `extract_flink_*.py` 依赖 `/tmp/flink-research`（本地维护工具，非 CI 接线）

**File:** `scripts/extract_flink_lexical.py`、`scripts/extract_flink_grammar.py`
**Issue:** 这两个提取脚本读取 `/tmp/flink-research/` 下已下载的 release 归档（Phase 10 验证）。按 D-06 option-a 决策不接入 CI；离线门禁由 `verify_corpus.py --check`（依赖已提交的 fixtures + manifest hash）承担。属有意设计；本地运行需归档在场（缺失时 skip 而非失败，已实测）。
**Fix:** 无需变更 — 记录在案。

### IN-02: `compare_backends.py` 的确定性 digest 依赖 committed 快照树

**File:** `scripts/compare_backends.py`
**Issue:** digest 是对 committed `parity/__snapshot__` 树计算，而非对每个目标的 raw 输出逐字节比对。MoonBit `@test.T::snapshot` 三目标共用同一 committed 快照文件（任何目标不一致即测试失败），故 digest 一致是充分证据。若未来某目标绕过 snapshot 机制直接输出，需扩展为逐 fixture 内容比对。
**Fix:** 无需变更 — 记录在案；未来目标扩展时重访。

### IN-03: 评审深度为编排器直接验证（非深度对抗式源码 pass）

**File:** n/a
**Issue:** 原 reviewer 子代理在门禁子进程上挂起未产出。本评审基于：(a) 本会话直接执行全部三个门禁脚本（exit 0 + digest 一致 + 注入漂移/恢复测试），(b) 812/812 全套测试，(c) 门禁脚本源码检查（stdlib-only、fail-closed、无网络/注入面、diff_parity 语义正确）。未做逐行对抗式源码审计。
**Fix:** 如需深度审计，可在 Phase 12 完成后按需运行独立 /gsd:code-review 12。

---

## Verification Evidence

- `python3 scripts/verify_corpus.py --check` → `ok: 110 flink corpus rows verified offline ... 104 archive sha512 re-verified`
- `python3 scripts/diff_parity.py --frozen-only` → `ok: 433 snapshots, 0 frozen-vs-current differences`（executor 另验证注入漂移 exit 1 + 恢复保证）
- `python3 scripts/compare_backends.py` → 3 targets PASS，digest `5e9bb887...` 三目标一致
- `moon test --target native --package {test,parity,lsp,api,source,token,lexer,parser,printer,syntax,completion,analyzer,fathom-sql}` → 812/812

---

_Reviewed: 2026-08-09_
_Reviewer: Claude (orchestrator-verified)_
_Depth: gate-execution + source inspection_
