---
phase: 13-toolchain-and-editor-packaging
plan: 07
subsystem: packaging (three-host final smoke + CI job)
tags: [flink, d-08, tool-05, packaging, ci, host-verify, offline, three-host, eco-07, parity-03]

# Dependency graph
requires:
  - phase: 13-toolchain-and-editor-packaging
    provides: 13-06 Web/VS Code/IntelliJ (dialect, profile) pair validation — PROFILES_BY_DIALECT (doris 2.1/3.x/4.x; flink flink-2.3.0/2.1.3/1.20.5) and the flink values the smokes select
  - phase: 13-toolchain-and-editor-packaging
    provides: 13-05 LSP flink format/completion real paths — flink format is no longer -32603 and completion no longer -32602, so the host smokes assert real edits/items
  - phase: 13-toolchain-and-editor-packaging
    provides: 13-04 fathom_complete_v1 export + fathom.complete.v1 envelope — the Web host's completion surface (built binding.js exports it)
  - phase: 12-cross-dialect-corpus-and-parity-gates
    provides: offline-first discipline (PARITY-03) — the packaging smokes never touch network/FE/cluster/DB at runtime
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: the locked selection transport (workspace default + per-file didOpen/didChange override) and the neutral naming gate (NAME-04)
provides:
  - VS Code real extension-host flink mode (ECO-07): host-verify.mjs modes array gains a flink row (VSCODE_HOST_MODE=flink, FATHOM_DIALECT=flink, FATHOM_PROFILE=flink-2.3.0); host-test.ts runFlink() asserts flink diagnostics (invalid -> FATHOM-PARSE-*, valid -> zero), real formatting (never -32603), real completion (never -32602)
  - IntelliJ Gradle LSP-launch smoke: FathomLanguageServerFactoryTest.kt asserts initializationOptions carries {dialect: flink, profile: flink-2.3.0} and a settings-accepted flink pair flows through the factory
  - Web Chromium flink selection flow: offline-smoke.mjs asserts the profile dropdown repopulates per dialect (flink values only under flink), flink parse reaches fathom.parse.v1, flink completion reaches fathom.complete.v1, and the BUILT binding.js exports fathom_complete_v1
  - CI host-packaging-smoke job in .github/workflows/ci.yml: Web offline-smoke + VS Code host-verify (xvfb-run) + IntelliJ gradlew test/verifyPlugin/buildPlugin — all fail-closed, no --update, smokes fully offline
  - docs/CONFIGURATION.md: per-host flink selection (VS Code/IntelliJ/Web/CLI), (dialect, profile) pair validity table, per-file LSP override, pinned flink profile metadata
affects: [TOOL-05 verifier, gsd-ship (WINDOWS.md unrun-verify entry for jetbrains verifyPlugin), future host packaging work]

# Actuals (#2632) — pairs with the plan's `estimate` (38000 chars/4) to calibrate future estimates.
actuals:
  tokens: 5339    # chars/4 over the realized diff (21,358 diff chars across the 6 changed files)
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - ECO-07 flink mode = one extra row in the host-verify.mjs modes array (VSCODE_HOST_MODE=flink + FATHOM_DIALECT/FATHOM_PROFILE) + a runFlink() branch in host-test.ts that opens a flink file and asserts diagnostics/format/completion through the real LSP — no second parser, no special harness
    - Gradle-level LSP-launch smoke = a plain Kotlin/JUnit test over the static FathomLanguageServerFactory.initializationOptions(dialect, profile) — proves the flink selection reaches the LSP wire offline without booting an IDE
    - CI host-packaging-smoke = one fail-closed job composing the three existing host harnesses (web offline-smoke, vscode host-verify under xvfb-run, jetbrains gradlew) with the MoonBit installer as the only network-bearing bootstrap; no --update anywhere

key-files:
  created:
    - jetbrains/src/test/kotlin/fathom/jetbrains/sql/FathomLanguageServerFactoryTest.kt
  modified:
    - vscode/scripts/host-verify.mjs
    - vscode/src/host-test.ts
    - web/scripts/offline-smoke.mjs
    - .github/workflows/ci.yml
    - docs/CONFIGURATION.md

key-decisions:
  - "D-08 (reversible) three-host packaging smoke depth: reuse the existing harnesses — VS Code real extension-host (ECO-07 host-verify.mjs), IntelliJ Gradle + LSP launch smoke (FathomLanguageServerFactoryTest over initializationOptions), Web Chromium smoke (offline-smoke.mjs) — each host's flink acceptance is open flink file -> select flink dialect/profile -> receive diagnostics (format/completion at supported points), all offline."
  - "CI host-packaging-smoke job is fail-closed (non-continue-on-error per step, Pitfall 8) and never writes snapshots (no --update, Pitfall 1). The only network-bearing bootstrap is the MoonBit installer curl; npm ci / gradle dependency resolution restore from the pinned action caches when warm and a cold-cache fetch is a build-time dependency restore, never a smoke runtime call."
  - "The CI job builds the native fathom-lsp AND the JS binding before the smokes (moon build --target native fathom-lsp + moon build --target js binding) so the Web smoke's built-artifact assertion (fathom_complete_v1 in binding.js) and the VS Code host's FATHOM_LSP_PATH both resolve to real, current artifacts."

patterns-established:
  - "Pattern: a host smoke that must assert a BUILT artifact (the Web binding.js) belongs in the same CI job that builds that artifact — otherwise a fresh checkout has no artifact to assert against (T-13-07-05)."
  - "Pattern: fail-closed host steps = plain `run:` blocks with no continue-on-error and no shell `|| true`; a skipped or silently-passed host reds the job (Pitfall 8, ECO-07 precedent)."
  - "Pattern: an offline-unrunnable CI task (IntelliJ verifyPlugin needs the uncached IDE distribution) is recorded in the broken-windows ledger as unrun-verify so /gsd-ship sees it; the offline-capable tasks (test/buildPlugin) validate the same deliverable locally."

requirements-completed: [TOOL-05]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "VS Code real extension-host flink mode (ECO-07) — host-verify.mjs modes array gains a flink row (VSCODE_HOST_MODE=flink, FATHOM_DIALECT=flink, FATHOM_PROFILE=flink-2.3.0); host-test.ts runFlink() asserts invalid flink -> FATHOM-PARSE-* diagnostic (UTF-16 range, fathom source), valid flink -> zero diagnostics, Format Document returns a real edit/empty array (never -32603), completion returns real items (never -32602)"
    requirement: TOOL-05
    verification:
      - kind: other
        ref: "cd vscode && npm run build && xvfb-run -a node scripts/host-verify.mjs — HOST-FUNCTIONAL / HOST-PROFILE / HOST-FLINK / HOST-FALLBACK all pass (real VS Code extension host)"
        status: pass
    human_judgment: false
  - id: D2
    description: "IntelliJ Gradle LSP-launch smoke — FathomLanguageServerFactoryTest.kt asserts initializationOptions('flink','flink-2.3.0') == {dialect: flink, profile: flink-2.3.0}, a settings-accepted flink pair flows through the factory, and the doris baseline pair stays byte-identical"
    requirement: TOOL-05
    verification:
      - kind: other
        ref: "cd jetbrains && JAVA_HOME=<jdk21> ./gradlew --offline test buildPlugin — BUILD SUCCESSFUL (new test class runs green)"
        status: pass
      - kind: other
        ref: "cd jetbrains && python3 scripts/source-smoke.py — SOURCE SMOKE PASSED"
        status: pass
    human_judgment: false
  - id: D3
    description: "Web Chromium flink selection flow — offline-smoke.mjs asserts repopulateProfileOptions reads PROFILES_BY_DIALECT[dialect] (flink values only under flink), flink parse reaches fathom.parse.v1, flink completion reaches fathom.complete.v1, and the BUILT binding.js exports fathom_complete_v1"
    requirement: TOOL-05
    verification:
      - kind: other
        ref: "cd web && npm run build — web offline smoke: local artifact/dialect/refusal contracts passed"
        status: pass
    human_judgment: false
  - id: D4
    description: "CI host-packaging-smoke job — Web offline-smoke + VS Code host-verify (xvfb-run, FATHOM_LSP_PATH from the built fathom-lsp) + IntelliJ gradlew test/verifyPlugin/buildPlugin, all fail-closed; no --update in any run line; the MoonBit installer is the only network-bearing bootstrap"
    requirement: TOOL-05
    verification:
      - kind: other
        ref: "python3 -c yaml.safe_load(ci.yml) — YAML-OK jobs include host-packaging-smoke; grep -nE 'run:.*--update' ci.yml returns nothing; grep -q host-packaging-smoke ci.yml passes"
        status: pass
    human_judgment: false
  - id: D5
    description: "docs/CONFIGURATION.md — (dialect, profile) pair validity table (doris 2.1/3.x/4.x; flink flink-2.3.0/2.1.3/1.20.5), per-host flink selection (VS Code fathom.dialect/fathom.profile, IntelliJ FathomSettings, Web demo selectors, CLI --dialect --profile), per-file LSP override, and the pinned flink profile metadata rows"
    requirement: TOOL-05
    verification:
      - kind: other
        ref: "python3 scripts/check_naming.py — ok: 602 product files scanned, zero forbidden naming remnants (docs scanned)"
        status: pass
    human_judgment: false

# Metrics
duration: 55min
completed: 2026-08-10
status: complete
---

# Phase 13 Plan 07: Three-host final packaging smoke + CI job (TOOL-05/D-08)

**The three-host packaging smoke is closed out per D-08: the VS Code real extension-host verifies a flink file's diagnostics/format/completion through the actual LSP (ECO-07 flink mode), the IntelliJ Gradle LSP-launch smoke proves a flink {dialect, profile} pair reaches the LSP wire, the Web Chromium smoke asserts the flink selection flow (profile dropdown, fathom.parse.v1, fathom.complete.v1 in the built binding.js), and CI gains a fail-closed host-packaging-smoke job with no --update — all offline, with the Doris parity and naming gates green.**

## Performance

- **Duration:** 55 min
- **Started:** 2026-08-10T04:23Z
- **Completed:** 2026-08-10T05:18Z
- **Tasks:** 3 (1 tracer + 2 auto)
- **Commits:** 3 atomic task commits + 1 docs/metadata commit
- **Files modified:** 6 (5 host/CI/doc files + 1 new JetBrains test)

## Accomplishments
- **VS Code real extension-host flink mode (Task 1 tracer, ECO-07):** `vscode/scripts/host-verify.mjs` modes array gains a flink row — `{ mode: 'flink', env: { VSCODE_HOST_MODE: 'flink', FATHOM_LSP_PATH: lspPath, FATHOM_DIALECT: 'flink', FATHOM_PROFILE: 'flink-2.3.0' } }` — mirroring the existing functional/profile/fallback rows. `vscode/src/host-test.ts` adds `runFlink()`: opens a `.sql` file, resolves the `fathom.dialect=flink`/`fathom.profile=flink-2.3.0` selection, and asserts (a) invalid flink SQL reports a `FATHOM-PARSE-*` diagnostic with a stable code + UTF-16 range from source `fathom`, (b) valid flink SQL produces zero diagnostics (real Flink grammar, not Doris), (c) Format Document returns a real edit/empty array — never `-32603`, (d) completion returns real items including `SELECT` — never `-32602`. All four modes (functional/profile/flink/fallback) pass in a real VS Code extension host under Xvfb.
- **IntelliJ Gradle LSP-launch smoke (Task 2):** `jetbrains/.../FathomLanguageServerFactoryTest.kt` (new) asserts `initializationOptions("flink", "flink-2.3.0")` carries exactly `{dialect: "flink", profile: "flink-2.3.0"}`, that a settings-accepted flink pair (via `FathomSettings.normalizeDialect`/`normalizeProfile`) flows through the same static function the connection provider calls, and that the doris baseline pair stays byte-identical. The factory source already builds `initializationOptions(configuration.dialect, configuration.profile)` — verified, no change needed.
- **Web Chromium flink selection flow (Task 2):** `web/scripts/offline-smoke.mjs` now reads `src/main.ts` and the built `_build/js/debug/build/binding/binding.js` and asserts: the profile dropdown repopulates per dialect (`repopulateProfileOptions` reads `PROFILES_BY_DIALECT[dialect]`, so flink values appear only under flink), flink parse reaches `fathom.parse.v1` with the selected dialect, flink completion reaches `fathom.complete.v1`, and the built artifact actually exports `fathom_complete_v1` (T-13-07-05 stale-artifact guard).
- **CI three-host packaging smoke job (Task 3):** `.github/workflows/ci.yml` gains `host-packaging-smoke` — checkout → MoonBit installer (the only network-bearing bootstrap) → `moon build --target native fathom-lsp` + `moon build --target js binding` → a locate step that resolves the built binary path → setup Node/Python/JDK 21 → Web offline-smoke, VS Code `host-verify` under `xvfb-run -a` (with `FATHOM_LSP_PATH`), and IntelliJ `./gradlew --no-daemon test verifyPlugin buildPlugin`. Every host step is fail-closed (no continue-on-error, Pitfall 8); no `--update` in any run line (Pitfall 1); the smokes are fully offline (PARITY-03).
- **docs/CONFIGURATION.md (Task 3):** documents the (dialect, profile) pair validity table (doris 2.1/3.x/4.x; flink flink-2.3.0/2.1.3/1.20.5), per-host flink selection (VS Code `fathom.dialect`/`fathom.profile`, IntelliJ `FathomSettings`, Web demo selectors, CLI `--dialect --profile`), the per-file LSP override (didOpen/didChange extension fields; document > workspace/session), and the pinned flink profile metadata rows. The stale "Flink profiles are rejected until pinned" line is corrected.

## Task Commits

1. **Task 1 (tracer): VS Code real extension-host flink mode end-to-end (ECO-07 pattern)** - `40ca189` (feat) — host-verify.mjs flink mode row + host-test.ts runFlink() assertions; `npm run build` + `host-verify` all four modes + parity 597/597 pass
2. **Task 2: IntelliJ Gradle + LSP launch smoke with flink + Web Chromium flink smoke** - `3d0a52f` (feat) — FathomLanguageServerFactoryTest.kt + offline-smoke.mjs flink selection flow assertions; web smoke + gradle test/buildPlugin + source-smoke + check_naming pass
3. **Task 3: CI three-host packaging smoke job + docs/CONFIGURATION.md flink selection** - `8a92e59` (feat) — ci.yml host-packaging-smoke job + CONFIGURATION.md per-host flink selection; full gate stack green
4. **Plan metadata commit** - `(follows)` — 13-07-SUMMARY.md + WINDOWS.md ledger entry

## Files Created/Modified
- `vscode/scripts/host-verify.mjs` - flink mode row (`VSCODE_HOST_MODE=flink`, `FATHOM_DIALECT=flink`, `FATHOM_PROFILE=flink-2.3.0`); header + final message updated to four modes
- `vscode/src/host-test.ts` - `runFlink()`: flink diagnostics (invalid FATHOM-PARSE-*, valid zero), real format (never -32603), real completion (never -32602); wired into `run()` dispatch
- `jetbrains/src/test/kotlin/fathom/jetbrains/sql/FathomLanguageServerFactoryTest.kt` (new) - Gradle LSP-launch smoke: flink initializationOptions map, settings→factory flow, doris baseline
- `web/scripts/offline-smoke.mjs` - flink profile dropdown repopulation, flink parse/complete wire, built binding.js `fathom_complete_v1` export
- `.github/workflows/ci.yml` - `host-packaging-smoke` job (Web + VS Code + IntelliJ, fail-closed, no --update)
- `docs/CONFIGURATION.md` - (dialect, profile) validity table, per-host flink selection, per-file LSP override, flink profile metadata; corrected the stale "Flink profiles rejected until pinned" line

## Decisions Made
- **D-08 (reversible) executed as planned:** the three host harnesses (ECO-07 host-verify, IntelliJ Gradle LSP-launch, Web Chromium offline-smoke) each assert the flink flow (open flink file → select flink → diagnostics, format/completion at supported points) — cross-host behavioral identity is asserted per-host, not as a single diff (the plan's flagged-unverified probe boundary, documented in must_haves).
- **CI job composition:** the packaging job reuses the existing harness entry points exactly — the same commands a maintainer runs locally — so a local green run predicts CI green (modulo the network-enabled verifyPlugin IDE download).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The local `fathom-lsp` binary was stale — predated 13-05's removal of the -32603 flink-format sentinel**
- **Found during:** Task 1 (flink host-verify verification)
- **Issue:** The `_build/native/debug/build/fathom-lsp/fathom-lsp.exe` artifact was built Aug 9, before 13-05 (commit 09d38c8) replaced the flink `-32603 not-implemented` format path with the real `@api.format_with_ids`. The flink mode's Format Document assertion failed because the stale server returned `-32603`. The flink diagnostics assertions (invalid → FATHOM-PARSE-*, valid → zero) passed, proving the flink selection reached the server.
- **Fix:** Rebuilt the native LSP (`moon build --target native fathom-lsp`); the binary is now current (Aug 10). This is an artifact rebuild, not a source change. The CI job builds the binary before the smokes, so CI cannot hit this staleness.
- **Files modified:** none (environment/artifact rebuild only)
- **Verification:** re-ran host-verify — all four modes pass.
- **Committed in:** 40ca189 (Task 1; no file change, documented here)

**2. [Rule 3 - Blocking] JetBrains `verifyPlugin` cannot run in this offline environment**
- **Found during:** Task 2 (IntelliJ verification)
- **Issue:** `./gradlew verifyPlugin` requires downloading the uncached IntelliJ IDEA distribution (`idea:idea:2026.1.4`); `--offline` fails with "No cached version ... available for offline mode", and the non-offline run hung for 1800s (terminated) because the JetBrains repository is unreachable from this environment.
- **Fix:** Ran the offline-capable tasks — `./gradlew --offline test buildPlugin` → BUILD SUCCESSFUL (the new `FathomLanguageServerFactoryTest` runs green, validating the flink LSP-launch smoke) and `python3 scripts/source-smoke.py` → PASSED. `verifyPlugin` is covered by the CI `host-packaging-smoke` job (and the existing `jetbrains-plugin.yml`) in a network-enabled environment. Recorded as an `unrun-verify` entry in `.planning/WINDOWS.md` (id 5).
- **Files modified:** none (environment/toolchain only)
- **Verification:** `./gradlew --offline test buildPlugin` → BUILD SUCCESSFUL in 1m 4s.
- **Committed in:** 3d0a52f (Task 2; no file change, documented here)

**3. [Rule 3 - Blocking] The Web smoke must assert the BUILT JS artifact, so the CI job must build it**
- **Found during:** Task 3 (CI job design)
- **Issue:** The offline-smoke now reads `_build/js/debug/build/binding/binding.js` to prove `fathom_complete_v1` is exported. On a fresh CI checkout this artifact does not exist (no existing CI job builds the JS binding — only `moon check --target js`), so the smoke would fail.
- **Fix:** The `host-packaging-smoke` job builds both the native `fathom-lsp` and the JS `binding` before the smokes (`moon build --target native fathom-lsp` + `moon build --target js binding`).
- **Files modified:** .github/workflows/ci.yml
- **Verification:** `python3 -c yaml.safe_load(ci.yml)` valid; the web smoke passes locally against the built artifact.
- **Committed in:** 8a92e59 (Task 3)

**4. [Housekeeping] The plan's Task 2 `<verify>` line could not be run end-to-end offline**
- **Found during:** Task 2
- **Issue:** The verify line `cd jetbrains && ./gradlew test verifyPlugin buildPlugin` requires the uncached IDE download (see deviation 2).
- **Fix:** Split verification — `test` + `buildPlugin` run offline (green), `verifyPlugin` deferred to CI and recorded in the ledger.
- **Files modified:** none
- **Committed in:** 3d0a52f (Task 2)

---

**Total deviations:** 3 auto-fixed (all Rule 3 blocking) + 1 housekeeping.
**Impact on plan:** All auto-fixes were necessary to run the plan's own verification commands offline and to make the CI job correct on a fresh checkout. No scope creep; no core MoonBit change was needed.

## Issues Encountered
- **Environment shell wedge:** the harness's persistent bash shell became unresponsive after an early `moon version` invocation; all subsequent shell work ran through a hub-started interactive bash process. No repo impact.
- **Intermittent network:** `update.code.visualstudio.com` DNS resolution failed on the second host-verify run, and the JetBrains repo was unreachable — both are this environment's proxy/network behavior, not repo defects. The host-verify falls back to the already-installed VS Code version, which is why it still passed.
- **verifyPlugin offline:** see deviation 2. The IDE download for plugin verification is a build-time dependency, not a smoke runtime call.

## Known Stubs
None — all three host smokes assert real artifacts (the built `fathom-lsp`, the built `binding.js`, the real LSP surface). No placeholder or mock data was introduced.

## Threat Surface
No new security-relevant surface: the added CI job runs the same harnesses a maintainer runs locally; the only new network-bearing bootstrap is the MoonBit installer curl (already the established pattern in every other ci.yml job); no new endpoints, auth paths, or trust-boundary schema changes.

## Next Phase Readiness
- The flagged-unverified probe (TOOL-05 cross-host parity) boundary stands as documented in the plan: each host asserts the flink flow per-host; a single cross-host behavioral diff is out of scope (recorded in the plan's must_haves).
- `verifyPlugin` coverage is live in CI (host-packaging-smoke + jetbrains-plugin.yml); the local offline environment cannot run it without the cached IDE distribution.
- Frozen snapshots: no MoonBit core, parity snapshot, or approved-changes file moved; parity 597/597, frozen diff 0 differences, cross-backend digest identical.

## Self-Check: PASSED
- FOUND: .planning/phases/13-toolchain-and-editor-packaging/13-07-SUMMARY.md
- FOUND: vscode/scripts/host-verify.mjs (flink mode row)
- FOUND: vscode/src/host-test.ts (runFlink)
- FOUND: jetbrains/src/test/kotlin/fathom/jetbrains/sql/FathomLanguageServerFactoryTest.kt
- FOUND: web/scripts/offline-smoke.mjs (flink selection flow)
- FOUND: .github/workflows/ci.yml (host-packaging-smoke)
- FOUND: docs/CONFIGURATION.md (per-host flink selection)
- FOUND: commits 40ca189, 3d0a52f, 8a92e59
