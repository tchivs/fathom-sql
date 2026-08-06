---
phase: 09-dialect-boundary-and-neutral-naming
plan: 04
subsystem: core
tags: [moonbit, module-rename, cli, lsp, d-06, d-11, neutral-naming, fathom-sql, fathom-lsp]

# Dependency graph
requires:
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: "09-02/09-03: dialect layer (Dialect/DialectContext), fathom.parse.v1/fathom.format.v1 wire identity, dialect-aware format/completion paths"
provides:
  - "fathom/sql module identity: moon.mod name + all 16 moon.pkg import prefixes, docs import examples"
  - "fathom-sql CLI: parse|format|lsp subcommands with mandatory --dialect <doris|flink> + --profile <id>, exit 2 on missing/unknown (D-11)"
  - "lsp/ library with pub serve_stdio(initial_dialect, initial_profile) — single stdio server loop; ServerState.default_dialect/default_profile fields"
  - "fathom-lsp standalone executable calling serve_stdio(None, None)"
  - "Neutral release assets: fathom-native-release.yml, fathom-lsp-{platform}, fathom-lsp-manifest.json, fathom-sql-intellij"
  - "Parity baseline preserved byte-identical (213 snapshots, 0 unexpected diffs)"
affects: [09-05, 09-06, 09-07, release-planning]

# Actuals (#2632) — pairs with the plan's `estimate` to calibrate future estimates.
actuals:
  tokens: 10284    # chars/4 over realized diff (25601 added + 15537 deleted chars)
  tasks: 3
  commits: 3       # 2 task commits + 1 final metadata commit

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Atomic module rename: moon.mod + all moon.pkg import prefixes in one commit (Pitfall 8)"
    - "Single stdio server seam: serve_stdio is the only LSP loop entry; CLI lsp and fathom-lsp are thin callers"
    - "D-08 register-first discipline: approved-change entries recorded before the single parity --update"

key-files:
  created: [lsp/serve.mbt, fathom-lsp/moon.pkg, fathom-lsp/main.mbt, .planning/phases/09-dialect-boundary-and-neutral-naming/deferred-items.md]
  modified: [moon.mod, 16 moon.pkg files, fathom-sql/args.mbt, fathom-sql/run.mbt, fathom-sql/main.mbt, fathom-sql/cli_test.mbt, fathom-sql/moon.pkg, fathom-sql/ffi.mbt, lsp/handlers.mbt, lsp/moon.pkg, parity/baseline_test.mbt, README.md, README.zh-CN.md, docs/API.md, docs/GETTING-STARTED.md, .github/workflows/fathom-native-release.yml, .github/workflows/jetbrains-plugin.yml, jetbrains/scripts/source-smoke.py, approved-changes.md]
  renamed: [doris-sql/ -> fathom-sql/, .github/workflows/doris-native-release.yml -> fathom-native-release.yml, lsp/main.mbt deleted (moved into serve.mbt)]

key-decisions:
  - "Auto-selected Task 1 option-a (full clean cutover per D-06, one-way door) under auto mode — no compat aliases, module version stays 0.1.0"
  - "Command gains a subcommand field in addition to the plan's dialect field — parse|format|lsp dispatch requires it"
  - "CLI import surface grows to api/lsp/binding + core (D-37 constraint updated in moon.pkg comment): run_parse serializes via @binding.parse_result_json, run_lsp calls @lsp.serve_stdio"
  - "Parity CLI homomorph needs no byte change — it already passes 'doris' as dialect (now sourced from Command.dialect); register entry documents the CLI contract"
  - "LSP serverInfo.name/source strings left untouched (09-06 owns them); parity fixtures owned by 09-05/09-06"

patterns-established:
  - "Pattern 1: Module rename lands as one atomic commit; the grep gate (zero old prefix in moon.pkg/.mbt) is the acceptance check"
  - "Pattern 2: serve_stdio(initial_dialect, initial_profile) stores workspace defaults on ServerState; 09-06 consumes them"

requirements-completed: [NAME-01, DIALECT-01]

coverage:
  - id: D1
    description: "fathom/sql module identity — moon.mod name, all 16 moon.pkg import prefixes, docs import examples; zero old module/CLI names in product moon.pkg/.mbt files"
    requirement: NAME-01
    verification:
      - kind: unit
        ref: "moon check --target native (0 errors)"
        status: pass
      - kind: other
        ref: "grep gate: zero 'fathom/doris-sql' in moon.pkg/.mbt product files"
        status: pass
      - kind: integration
        ref: "moon test --package parity 228/228 (behavior bytes unchanged)"
        status: pass
    human_judgment: false
  - id: D2
    description: "fathom-sql CLI with the D-11 contract: parse|format|lsp subcommands, --dialect/--profile required, exit 2 on missing/unknown/flink-profile, no default dialect"
    requirement: DIALECT-01
    verification:
      - kind: unit
        ref: "fathom-sql/cli_test.mbt D-11 exit-code matrix (moon test --package fathom-sql 16/16)"
        status: pass
      - kind: e2e
        ref: "binary smoke: missing --dialect -> 2, unknown dialect -> 2, flink+4.x -> 2, parse -> 0 + fathom.parse.v1"
        status: pass
    human_judgment: false
  - id: D3
    description: "Shared LSP server loop — lsp/serve.mbt serve_stdio; CLI lsp subcommand and standalone fathom-lsp binary run the same loop with dialect/profile defaults vs None"
    requirement: NAME-01
    verification:
      - kind: e2e
        ref: "LSP initialize handshake smoke on fathom-sql lsp --dialect doris --profile 4.x and on fathom-lsp (both respond)"
        status: pass
      - kind: integration
        ref: "lsp package tests within moon test --target native --package lsp (part of 417/417)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Neutral release assets — fathom-native-release.yml with fathom-lsp-{platform} assets + fathom-lsp-manifest.json; jetbrains-plugin.yml artifact fathom-sql-intellij"
    requirement: NAME-03
    verification:
      - kind: manual_procedural
        ref: "file inspection: .github/workflows/fathom-native-release.yml asset names and build path _build/native/release/build/fathom-lsp/fathom-lsp.exe; jetbrains-plugin.yml artifact name"
        status: pass
      - kind: other
        ref: "jetbrains/scripts/source-smoke.py native-workflow contract passes (SOURCE SMOKE PASSED)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Doris behavior bytes preserved — parity baseline byte-identical after the single approved snapshot update"
    requirement: NAME-01
    verification:
      - kind: integration
        ref: "scripts/baseline_diff.py --left git archive HEAD:parity/__snapshot__: 213 snapshots, 0 approved diffs, 0 unexpected"
        status: pass
      - kind: integration
        ref: "moon test --package parity 228/228 (no --update)"
        status: pass
    human_judgment: false

# Metrics
duration: 34min
completed: 2026-08-06
status: complete
---

# Phase 09 Plan 04: Module Rename and CLI Dialect Cutover Summary

**Atomic D-06 clean cutover: fathom/sql module identity across all 16 moon.pkg imports, fathom-sql CLI with the mandatory --dialect/--profile D-11 contract (parse|format|lsp, exit 2), the shared serve_stdio LSP seam with the new fathom-lsp binary, and neutral release assets — parity baseline byte-identical.**

## Performance

- **Duration:** 34 min
- **Started:** 2026-08-06T15:45:36Z
- **Completed:** 2026-08-06T16:19:00Z
- **Tasks:** 3 (Task 1 checkpoint auto-selected under auto mode)
- **Files modified:** 35 (two commits; renames counted once)

## Accomplishments
- `moon.mod` name is `fathom/sql`; all 16 moon.pkg import prefixes are `fathom/sql/<pkg>` with aliases unchanged; `analyzer/moon.pkg` still imports exactly `fathom/sql/syntax` (D-21 negative gate); README/README.zh-CN/docs/API.md/docs/GETTING-STARTED.md import examples and CLI paths updated — zero old `fathom/doris-sql` prefix remains in any moon.pkg/.mbt product file.
- `doris-sql/` git-mv'd to `fathom-sql/` (binary `fathom-sql.exe` follows the package dir, verified in `_build/native/release/build/fathom-sql/`); CLI now implements the full D-11 surface: `parse|format|lsp` subcommands, `--dialect <doris|flink>` and `--profile <id>` REQUIRED for every subcommand, `UsageError::MissingDialect`/`UnknownDialect`, `is_valid_dialect_profile` (doris 2.1/3.x/4.x; flink rejects every profile in Phase 9), and exit 0/1/2 semantics verified on the real binary.
- `lsp/` became a library: the stdio loop moved from `lsp/main.mbt` (deleted) into `pub fn serve_stdio(initial_dialect : String?, initial_profile : String?)` in `lsp/serve.mbt`; `ServerState` gained `default_dialect`/`default_profile` (consumed by 09-06). The CLI `lsp` subcommand passes the parsed `--dialect/--profile`; the new standalone `fathom-lsp/` executable calls `serve_stdio(None, None)`. Both entry points smoke-verified with an LSP initialize handshake.
- Release surface is neutral: `fathom-native-release.yml` (Fathom Native Release) builds `fathom-lsp` and ships `fathom-lsp-{platform}` assets + `fathom-lsp-manifest.json`; JetBrains artifact is `fathom-sql-intellij`.
- Parity baseline untouched: the single approved `moon test --update --package parity` produced ZERO snapshot diffs; `baseline_diff.py --left <committed reference>` reports 213 snapshots, 0 approved, 0 unexpected; `moon test --package parity` 228/228; full native suite 417/417 (incl. cli_test 16/16).

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm D-06 clean cutover scope (one-way door)** - auto-selected option-a under auto mode (no commit)
2. **Task 2: Module identity rename — moon.mod, 16 moon.pkg import prefixes, docs import examples** - `021cd69` (feat)
3. **Task 3: CLI cutover — git mv, --dialect/--profile contract, parse|format|lsp subcommands, serve seam, release assets** - `213be31` (feat)

**Plan metadata:** (final commit captures SUMMARY/STATE/ROADMAP)

## Files Created/Modified
- `moon.mod` - name `fathom/sql` (version 0.1.0, toolchain header comments untouched)
- `moon.pkg`, `api/token/lexer/parser/syntax/source/printer/formatter/completion/analyzer/binding/lsp/parity/test/moon.pkg` - import prefixes `fathom/doris-sql/<pkg>` -> `fathom/sql/<pkg>` (aliases unchanged)
- `fathom-sql/args.mbt` (renamed from doris-sql/) - UsageError + MissingDialect/UnknownDialect; parse|format|lsp; `--dialect`/`--profile` required; `is_valid_dialect_profile`; `Command` gains `subcommand` + `dialect`
- `fathom-sql/run.mbt` - `run_parse` (fathom.parse.v1 envelope via @binding), `run_format` (dialect-aware), `run_lsp` (serve_stdio); new usage text; exit 0/1/2
- `fathom-sql/main.mbt` - subcommand dispatch; lsp subcommand never pre-reads stdin
- `fathom-sql/cli_test.mbt` - D-11 exit-code matrix (missing/unknown dialect, flink profile rejection, parse smoke, subcommand surface)
- `fathom-sql/moon.pkg`, `fathom-sql/ffi.mbt` - import surface + comment updates
- `lsp/serve.mbt` (new) - `pub fn serve_stdio` — the single stdio server loop
- `lsp/handlers.mbt` - ServerState gains `default_dialect`/`default_profile` (None defaults; handler logic untouched)
- `lsp/moon.pkg` - executable -> library; `lsp/main.mbt` deleted
- `fathom-lsp/moon.pkg` + `fathom-lsp/main.mbt` (new) - standalone executable calling `serve_stdio(None, None)`
- `parity/baseline_test.mbt` - CLI homomorph comment reflects Command.dialect threading
- `README.md`, `README.zh-CN.md`, `docs/API.md`, `docs/GETTING-STARTED.md` - import examples / CLI path strings
- `.github/workflows/fathom-native-release.yml` (renamed) - Fathom Native Release; fathom-lsp-{platform} assets; fathom-lsp-manifest.json; build path `_build/native/release/build/fathom-lsp/fathom-lsp.exe`
- `.github/workflows/jetbrains-plugin.yml` - artifact `fathom-sql-intellij` (staged via index plumbing to avoid pulling in another workstream's uncommitted action-version bumps)
- `jetbrains/scripts/source-smoke.py` - native-workflow path + manifest regex updated (Rule 1 fix)
- `.planning/phases/09-dialect-boundary-and-neutral-naming/approved-changes.md` - section 10 register (CLI usage text, Command.dialect, exit-2 matrix)
- `.planning/phases/09-dialect-boundary-and-neutral-naming/deferred-items.md` (new) - pre-existing bare-build failure log

## Decisions Made
- **Task 1 auto-selection (option-a):** Full clean cutover per D-06 — no backward-compat aliases, one-way door. Module version stays 0.1.0 (release-planning decision, research OQ7). Auto mode (`auto_advance=true`) selected the first option; the checkpoint did not block.
- **Command.subcommand field:** the plan specified `Command.dialect`; dispatch also requires the subcommand — added `pub subcommand : String` (parse|format|lsp), set by parse_args.
- **CLI import surface:** run_parse needs `@binding.parse_result_json` and run_lsp needs `@lsp.serve_stdio`, so the CLI imports api + lsp + binding + core env/buffer/utf8/debug. The old D-37 comment ("api + env/buffer/utf8/debug only") was updated to reflect the new seam.
- **Parity homomorph:** already passed `"doris"` as dialect, so no homomorph snapshot bytes change; the register documents the CLI contract (usage text, Command.dialect, exit-2 matrix) as the D-08 approval path. The single `--update` produced no diffs.
- **Deferred naming surfaces (explicitly out of this wave):** LSP `serverInfo.name` "doris-lsp" and diagnostic `source` "doris" -> 09-06; parity/fixtures/target-matrix.json -> 09-05; parity/fixtures/lsp-tracer.json -> 09-06; docs prose (docs/ARCHITECTURE.md, docs/CONFIGURATION.md, docs/zh-CN/*) -> 09-07.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] jetbrains/scripts/source-smoke.py broken by the workflow/manifest rename**
- **Found during:** Task 3 (release workflow cutover)
- **Issue:** The git mv of `doris-native-release.yml` -> `fathom-native-release.yml` and the manifest rename to `fathom-lsp-manifest.json` directly broke two source-smoke checks (`native_workflow_path` pointed at the old file; the manifest regex required `doris-lsp-manifest.json`). The jetbrains-plugin.yml CI job runs this script, so the rename would have red CI.
- **Fix:** Updated the two checks to `fathom-native-release.yml` and `fathom-lsp-manifest.json`. The rest of source-smoke's contract (DEFAULT_EXECUTABLE "doris-lsp" etc.) stays for 09-07's host cutover.
- **Files modified:** jetbrains/scripts/source-smoke.py
- **Verification:** `python3 scripts/source-smoke.py` -> "SOURCE SMOKE PASSED"
- **Committed in:** 213be31 (Task 3 commit)

**2. [Rule 3 - Blocking] Bare `moon build --target native` link failure — pre-existing, not caused by this wave**
- **Found during:** Task 3 verification (the plan's verify block includes the bare build)
- **Issue:** `moon build --target native` (no --package) fails with `undefined reference to main` at link time. Proven pre-existing: it fails identically at de1aa8a (pre-wave HEAD) in a detached worktree. Package-scoped builds (`--package fathom-sql`, `fathom-lsp`, `parity`, `test`, `api`) all pass.
- **Fix:** Not fixed (out of scope — pre-existing, unrelated surface). Verification uses package-scoped builds; logged to `deferred-items.md` in the phase directory.
- **Files modified:** .planning/phases/09-dialect-boundary-and-neutral-naming/deferred-items.md
- **Verification:** package-scoped builds + 417/417 suite green

---

**Total deviations:** 2 auto-fixed (1 bug, 1 pre-existing logged as deferred)
**Impact on plan:** Fix 1 was required to keep CI green after the rename. Fix 2 is a pre-existing toolchain/build-surface issue outside the naming wave; no scope creep.

## Issues Encountered
- **D-08 register timing:** the approved-changes.md register entry (section 10) was written to the working tree before the single `moon test --update --package parity`, and is committed with the plan's final metadata commit. The `--update` produced zero snapshot diffs (nothing to absorb), so the register-first gate's intent (no unapproved absorption) is fully honored.
- **Selective staging:** `.github/workflows/jetbrains-plugin.yml` carries another workstream's uncommitted action-version bumps (checkout@v7/setup-java@v5/upload-artifact@v7). The artifact-name change was staged via `git update-index --cacheinfo` from the index version so the Task 3 commit contains only the `fathom-sql-intellij` rename; the other hunks remain unstaged for their owner.
- **Pre-existing bare-build failure:** documented above; package-scoped builds are the verification path.

## Known Stubs

None — `serve_stdio` is fully wired (both entry points smoke-tested), the CLI exit-code matrix runs, and no placeholder/empty-value code paths were introduced. The `ServerState.default_dialect/default_profile` fields are stored but not yet consumed — that is the intended 09-06 seam (selection resolution), not a stub.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- 09-05 (wire-contract remainder) can proceed: binding/moon.pkg js/wasm exports lists still carry `doris_profile_v1`/`doris_capabilities_v1` (export renames belong to 09-05 per the wave plan); parity/fixtures/target-matrix.json and the parity test files are its checklist.
- 09-06 (LSP selection resolution) consumes `ServerState.default_dialect`/`default_profile` and owns `serverInfo.name`/`source` + lsp-tracer.json.
- 09-07 (hosts + docs) owns the remaining docs prose (docs/ARCHITECTURE.md, docs/CONFIGURATION.md, docs/zh-CN/*), jetbrains source-smoke full contract, and the NAME-04 gate script.
- The D-06 one-way door is closed: no old product alias exists in any committed product file.

---
*Phase: 09-dialect-boundary-and-neutral-naming*
*Completed: 2026-08-06*

## Self-Check: PASSED

- All created files verified present (SUMMARY, deferred-items, serve.mbt, fathom-lsp/*, fathom-sql/args.mbt)
- Both task commits verified in git history (021cd69, 213be31)

## Self-Check: PASSED

- All created files verified present (SUMMARY, deferred-items, serve.mbt, fathom-lsp/*, fathom-sql/args.mbt)
- Both task commits verified in git history (021cd69, 213be31)
