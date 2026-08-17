# Phase 14: Release Hygiene & Toolchain Pinning - Context

**Gathered:** 2026-08-13
**Status:** Ready for planning

<domain>
## Phase Boundary

本阶段把当前开发树转为可重复、可审计、可阻断发布的基线：提交既有 JetBrains CI action 升级；建立 MoonBit 生成接口与 `.planning` 杂项策略；为普通 CI 与 Native release 使用同一可获取的精确 MoonBit 版本；让发布管线在上传任何资产前运行完整 Native/JS/linear-Wasm、冻结 baseline、命名与离线 corpus 门禁，并把每个平台的精确工具链证据随工件发布。

本阶段不定义产品 semver 或实现二进制 `--version`（Phase 15），不修订安装文档（Phase 16），不撰写 changelog/disclosure（Phase 17），不发布 npm/编辑器市场包（Phases 18–19），也不创建正式 `v1.0.0` release（Phase 20）。

**Requirements:** HYG-01, HYG-02, HYG-03, TC-01, TC-02

</domain>

<decisions>
## Implementation Decisions

### Toolchain Identity and Acquisition
- **D-01（2026-08-14 修订，用户批准）:** 普通 CI 与 release CI 使用同一个精确 MoonBit 版本，以官方 CDN 内容锁定快照获取。2026-08-14 实测官方分发面（cli.moonbitlang.com 及 .cn 镜像、latest/nightly/pre-release/bleeding 通道、GitHub Releases）均无 `darwin-x86_64` 工件、无任何静态版本化渠道、无 core 官方校验和（全部 403/404）。冻结目标因此修订为官方实际分发的三平台 `linux-x86_64` / `darwin-aarch64` / `windows-x86_64`：二进制以 `binaries/latest` 快照的官方 `.sha256` sidecar 校验，并冻结字节摘要锁定内容（上游漂移即 fail，绝不静默跟随）；macOS Intel 不作为发布目标（GitHub 2027 秋退役 Intel runner）。历史本地 `0.1.20260724` 归档仍不得作为 pin。— **Reversibility:** costly — 更换 compiler pin 会使全部平台工件与 parity 证据重新生成并重新验证。
- **D-02:** 工具链安装复用一个仓库内的统一 CI 安装入口或等价单一配置源，避免 `ci.yml` 与 `fathom-native-release.yml` 各自漂移；Unix 与 Windows 可以保留平台专属解包步骤，但必须消费相同版本常量与验证规则。
- **D-03（2026-08-14 修订，用户批准）:** 只使用官方工件，并在执行构建前验证校验和和精确 `moon version` 输出；下载失败、checksum 不符或报告版本不符均立即失败。二进制归档使用官方 `.sha256` sidecar（三平台均存在）；core 归档官方在任何通道都不提供校验和（实测 403/404），改为冻结时记录 SHA-256 + 官方 URL + 审计声明（记录式校验，属文档化放宽）；`latest` 快照按 D-01 内容锁定，禁止静默跟随漂移。— **Reversibility:** one-way — 这是 1.0 发布供应链与可重复构建承诺，再次放宽需要公开修改发布安全政策。

### Release Gate Topology
- **D-04:** `fathom-native-release.yml` 增加独立、fail-closed 的 `release-gates` job；最终 publish job 必须通过显式 `needs` 依赖它和全部平台 build。门禁不依赖另一个 workflow 的历史成功状态，也不在各平台 build 中重复运行。
- **D-05:** release gate 复用现有真实命令，至少覆盖：Native/JS/linear-Wasm `parity` 测试、`scripts/compare_backends.py`、`scripts/diff_parity.py --frozen-only`、`scripts/check_naming.py`、`scripts/verify_corpus.py --check`、`corpus/tools/generate_corpus_report.py --check`、`corpus/tools/check_keywords.py corpus/keywords.tsv`。不得使用 `--update`、`continue-on-error` 或空结果容错。— **Reversibility:** one-way — 这些门禁是发布资格契约，删除或旁路会降低已承诺的 1.0 保证。
- **D-06:** tag 与 `workflow_dispatch` 两条发布路径运行完全相同的门禁；不提供 skip/bypass 输入。正式 `v1.0.0` tag 与 GitHub Release 的创建仍留给 Phase 20。

### Toolchain Evidence in Release Artifacts
- **D-07:** 每个平台 build 生成结构相同、机器可读的 `moon-toolchain.json`（或同等稳定名称），至少记录请求的精确版本、完整 `moon version` 原始输出、runner OS/arch 与目标平台；该记录与对应 Native binary 放入同一上传 artifact。
- **D-08:** publish job 下载三个平台记录，验证全部存在、请求版本一致、报告版本符合 pin，并生成一个聚合工具链清单作为最终 release asset。日志输出仅作诊断，不满足 TC-01 的“记录到发布工件”。
- **D-09:** 缺少工具链记录、requested/reported 不一致或跨平台版本不一致均阻断发布；不允许警告后继续。— **Reversibility:** one-way — 发布消费者和后续复现流程将依赖该证据格式；破坏性改动需版本化迁移。

### Working-Tree Hygiene
- **D-10:** `.gitignore` 使用仓库级 `pkg.generated.mbti` 规则覆盖任意 MoonBit package 的 `moon info` 生成接口，而不是只列 `fathom-sql/pkg.generated.mbti`；若存在已跟踪副本，规划必须显式解除跟踪。保留源代码接口文件与其他手写 `.mbti`（如有）。
- **D-11:** `.planning/research/.cache/` 是可再生缓存：删除并加入忽略。两个历史 quick 目录保留已提交的 `SUMMARY.md`，删除未跟踪、重复且不属于 canonical artifact 的 `PLAN.md`。不得删除已提交的历史总结。
- **D-12:** `.planning/milestones/v1.0-research/` 包含完整研究集且被后续上下文引用：作为正式 milestone archive 提交，不作为 stray 删除。— **Reversibility:** costly — 删除会破坏已有阶段上下文的 canonical refs 和历史审计链。
- **D-13:** `.planning/.omp-next-action.json` 与 `.planning/.omp-task-results.json` 是运行时状态，不属于发布产品变更；Phase 14 计划不得把会话漂移混入发布提交。对工作树使用显式 allowlist 和 fail-closed 状态检查，绝不运行 `git clean`、reset 或 stash 去吞掉未知用户工作。
- **D-14:** HYG-01 的 JetBrains action 变更按当前工作树原样收口：`actions/checkout@v7`、`actions/setup-java@v5`、`actions/upload-artifact@v7`。不顺手改 Gradle、Kotlin、IDE 兼容范围或插件发布逻辑。

### Claude's Discretion
`--auto` 模式下四个灰区均采用上述推荐方案。研究者/规划者可决定统一安装入口的文件名、JSON 字段附加项、release-gates job 内步骤拆分与具体可获取版本，但不得改变 D-01..D-14 的边界或失败语义。

### Decision Revisions (2026-08-14, user-approved)
- 依据：官方分发面实测（2026-08-14）——`binaries/latest|nightly|pre-release|bleeding/moonbit-darwin-x86_64.tar.gz(.sha256)` 全部 403、`.cn` 镜像 404；`cores/core-*.sha256` 全部 403（S3 AccessDenied）；versioned 键 `0.1.20240520%2Bb1f30d5e1`/`0.1.20260807`/`0.1.20260807%2B4da23f8` 全部 403；S3 listing 拒绝；moonbitlang/moon 与 core Releases 均为 0；moonbit-compiler Releases 仅 wasm 资产；官方 setup action 仅接受 latest/nightly。可用官方 sidecar：linux-x86_64=`36f5e7cf…`、darwin-aarch64=`b4781a1e…`、windows-x86_64=`c659625f…`。
- 修订内容：D-01（三平台内容锁定）与 D-03（core 记录式校验）如上；D-04/D-08 平台计数同步为三。
- 批准：用户在 blocking-human 决策中明确选择「批准修订 D-01/D-03：三平台内容锁定」。


</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Scope and Requirements
- `.planning/ROADMAP.md` §Phase 14 — phase goal, five success criteria, and dependency ordering.
- `.planning/REQUIREMENTS.md` §§TC/HYG — TC-01/02 and HYG-01/02/03 are the complete Phase 14 requirement set.
- `.planning/PROJECT.md` §Current Milestone: v4.0 Release Readiness — release-readiness boundary and product constraints.

### Prior Locked Gate Decisions
- `.planning/milestones/v2.0-phases/12-cross-dialect-corpus-and-parity-gates/12-CONTEXT.md` — D-03..D-07: frozen Doris baseline, three-target byte parity, offline corpus checks, fail-visible conflicts.
- `.planning/milestones/v2.0-phases/13-toolchain-and-editor-packaging/13-CONTEXT.md` — D-08 and existing host/release packaging constraints; names the current parity and naming integration points.
- `.planning/milestones/v3.0-phases/08-incremental-parsing-benchmark-gated/08-CONTEXT.md` — records the observed historical MoonBit executable and evidence-first gate discipline.

### Current CI and Toolchain Surfaces
- `.github/workflows/fathom-native-release.yml` — four-platform Native build, current floating `latest`, linear-Wasm parity job, SHA-256 manifest and GitHub Release upload path.
- `.github/workflows/ci.yml` — authoritative existing commands for three-target parity, frozen diff, naming, corpus, and host packaging gates; currently also floats `latest`.
- `.github/workflows/jetbrains-plugin.yml` — existing HYG-01 action upgrades to commit without widening scope.
- `moon.mod` — historical observed `moon 0.1.20260724 (5f1406a 2026-07-24)` record; this is provenance, not automatically a currently downloadable release pin.
- `.gitignore` — current generated/build-output policy; missing repository-wide `pkg.generated.mbti` and planning-cache rules.

### Gate Implementations and Data
- `scripts/compare_backends.py` — aggregate Native/JS/linear-Wasm parity proof.
- `scripts/diff_parity.py` — frozen-vs-current regeneration proof; release invocation is `--frozen-only`.
- `scripts/check_naming.py` — neutral product naming inventory gate.
- `scripts/verify_corpus.py` — offline Flink manifest, pins, category, hash and snapshot verifier.
- `corpus/tools/generate_corpus_report.py` — checked-in corpus report freshness/consistency gate.
- `corpus/tools/check_keywords.py` — keyword classification validation.
- `parity/` — shared parity package and committed snapshots consumed by all three targets.

### Planning Artifacts Requiring Classification
- `.planning/milestones/v1.0-research/` — valuable historical research archive; retain and commit.
- `.planning/quick/260805-df9-add-a-kotlin-gradle-jetbrains-intellij-p/SUMMARY.md` — canonical completed quick-task summary; keep while removing the untracked duplicate plan.
- `.planning/quick/260805-e28-align-the-jetbrains-plugin-wrapper-and-d/SUMMARY.md` — canonical completed quick-task summary; keep while removing the untracked duplicate plan.

No external ADR or SPEC exists for Phase 14; requirements and prior locked contexts above are authoritative.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.github/workflows/ci.yml`: already contains every TC-02 command with fail-closed semantics; the release workflow should reuse this command set rather than invent a second gate definition.
- `.github/workflows/fathom-native-release.yml`: already has the four-platform build matrix, per-platform artifact names, a final aggregation job, and SHA-256 manifest generation—the right insertion points for per-platform and aggregate toolchain evidence.
- `scripts/compare_backends.py`, `scripts/diff_parity.py`, `scripts/check_naming.py`, `scripts/verify_corpus.py`: stable local gate executables requiring no new runtime service.
- `parity/__snapshot__/`, `parity/baseline-hashes.txt`, and corpus manifests/reports: checked-in offline evidence backing the release gate.

### Established Patterns
- Release and corpus checks are offline at execution time after tool bootstrap; no Doris FE, Flink cluster, database, or snapshot updates.
- Frozen changes fail closed; deliberate snapshot changes require explicit prior approval rather than mass update.
- Cross-target truth is byte equality across Native, JavaScript, and linear Wasm.
- Platform artifacts are aggregated only after required jobs complete; `needs` is the publication barrier.
- Unexpected working-tree changes are user work: classify explicitly, never erase through broad cleanup commands.

### Integration Points
- A shared exact MoonBit pin/acquisition mechanism must feed all install steps in `.github/workflows/ci.yml` and `.github/workflows/fathom-native-release.yml`.
- Per-platform toolchain evidence is created immediately after install/version validation and copied into each `dist/` payload.
- `release-gates` runs on Ubuntu before `release`; `release.needs` includes `build` and `release-gates`.
- `.gitignore` receives generic generated-interface and research-cache rules.
- Phase 14 planning must separate canonical archives from disposable cache/duplicate plan/runtime-state files before committing.

</code_context>

<specifics>
## Specific Ideas

- Current local evidence: `moon version` reports `moon 0.1.20260724 (5f1406a 2026-07-24)` with `rr_moon_mod,rr_moon_pkg`; this exact archive has already been documented as unavailable from the installer, so it is historical provenance until research proves an official cross-platform acquisition path.
- Current non-build release gates were exercised during discussion: 110 Flink corpus rows verified offline, 104 archive SHA-512 values reverified, `CORPUS-REPORT.md` current, and 655 product files passed the naming scan.
- Current hygiene inventory is concrete: JetBrains action bump, one untracked `fathom-sql/pkg.generated.mbti`, `.planning/research/.cache/`, two duplicate untracked quick `PLAN.md` files, and a staged five-file `v1.0-research` archive.

</specifics>

<deferred>
## Deferred Ideas

- Product semver source and `fathom-sql`/`fathom-lsp --version` behavior → Phase 15.
- README/GETTING-STARTED release installation instructions → Phase 16.
- CHANGELOG and release boundary disclosure → Phase 17.
- npm and editor marketplace publishing → Phases 18–19.
- Creating the formal `v1.0.0` tag/GitHub Release and downloading published assets for post-release smoke → Phase 20.

</deferred>

---

*Phase: 14-Release Hygiene & Toolchain Pinning*
*Context gathered: 2026-08-13*
