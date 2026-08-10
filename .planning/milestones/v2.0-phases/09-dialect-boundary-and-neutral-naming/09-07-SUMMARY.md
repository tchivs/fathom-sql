---
phase: 09-dialect-boundary-and-neutral-naming
plan: 07
subsystem: naming
tags: [vscode, jetbrains, web, naming-gate, check_naming.py, d-02, d-04, d-05, d-06, name-03, name-04, fathom]

# Dependency graph
requires:
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: "09-06: LSP selection contract — initializationOptions {dialect, profile}, fathom-lsp identity, FATHOM-SCHEMA-007 config errors; 09-04: module/CLI/binary cutover (fathom/sql, fathom-sql, fathom-lsp) + release asset names; 09-05: @binding fathom_*_v1 exports with the A4 parameter order (fathom_parse_v1(raw, dialect, profile, mode))"
provides:
  - "Neutral host identities per NAME-03: VS Code (fathom-sql-language-client, displayName 'Fathom SQL Language Client', language id sql, fathom.dialect/fathom.profile/fathom.serverPath keys, fathom.restartLanguageServer command, initializationOptions {dialect, profile}), Web/npm (@fathom/sql-web-demo, neutral titles + dialect selector, fathom_parse_v1 A4 calls, fathom.error.v1), IntelliJ (fathom.jetbrains.sql package, Fathom* classes, FathomSettings/fathom.xml, fathom.sql plugin id, fathom-sql server id, fathom-sql-intellij artifact, fathom-lsp-{platform} assets, updated source-smoke contracts)"
  - "No default dialect anywhere (D-02): VS Code/IntelliJ/Web never default a dialect; missing selection surfaces an explicit error — normalizeProfile '4.x' fallback and DEFAULT_PROFILE deleted, not adjusted"
  - "NAME-04 naming inventory gate: scripts/check_naming.py (stdlib-only, mirror of corpus/tools/check_keywords.py) with the FORBIDDEN/allowlist matrix (D-04 path exemptions, D-05 dialect-semantics patterns) wired as the naming-gate job in .github/workflows/ci.yml"
  - "Neutral README + docs titles with dialect+profile tables; Doris remains only as a dialect/profile/corpus/provenance semantic identifier"
  - "Closed 09-05 deferred host assertions: web/scripts/offline-smoke.mjs DORIS-FORMAT-001 -> FATHOM-FORMAT-001, vscode/src/host-test.ts + vscode/README.md DORIS-PARSE-006 -> FATHOM-PARSE-006 (deferred-items.md rows closed)"
affects: [phase-10, phase-11, phase-12, phase-13, release-planning]

# Actuals (#2632) — pairs with the plan's `estimate` (40000 tokens) to calibrate future estimates.
actuals:
  tokens: 19558     # chars/4 over the realized diff (49381 added + 28852 deleted = 78233 chars across the 5 task commits)
  tasks: 4          # Task 1 checkpoint:decision (no code) + Tasks 2-4
  commits: 5        # 5 task commits (+ 1 final metadata commit)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual-dimension naming gate (Pitfall 4): mode (FORBIDDEN regex list) x file-scope (product-file scan root, ALLOWLIST_PATHS D-04 exemptions, ALLOWLIST_PATTERNS D-05 dialect semantics) — only forbidden product-surface patterns fail, so Dialect::Doris/DorisProfile/doris-as-value/provenance survive a mechanical rename"
    - "Self-exempting inventory script: scripts/check_naming.py carries the forbidden patterns it enforces and exempts itself, mirroring corpus/tools/check_keywords.py (stdlib problems loop, nonzero exit, ok line)"
    - "Sweep-straggler loop: the final repository-wide sweep fixes every reported product-file hit outside the plan's explicit file lists (dialect/doris.mbt, lsp/diagnostics_formatting_test.mbt) until the gate exits 0 with zero hits"
    - "CI enforcement point: naming-gate job (actions/checkout@v7, actions/setup-python@v6, python3 scripts/check_naming.py) runs on every push/PR — the mechanical rejection surface for NAME-04"

key-files:
  created: [scripts/check_naming.py]
  modified: [.github/workflows/ci.yml, vscode/package.json, vscode/src/extension.ts, vscode/src/extension-contract.ts, vscode/README.md, vscode/scripts/host-verify.mjs, vscode/scripts/launch-smoke.mjs, vscode/src/host-test.ts, web/package.json, web/index.html, web/src/monaco-adapter.ts, web/src/main.ts, web/src/main.test.ts, web/scripts/offline-smoke.mjs, web/scripts/serve.mjs, jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomLanguageServerFactory.kt, jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomSettings.kt, jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomSettingsConfigurable.kt, jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomNativeDownloader.kt, jetbrains/build.gradle.kts, jetbrains/settings.gradle.kts, jetbrains/src/main/resources/META-INF/plugin.xml, jetbrains/scripts/source-smoke.py, jetbrains/README.md, jetbrains/gradle/wrapper/gradle-wrapper.properties, README.md, README.zh-CN.md, docs/*.md, docs/zh-CN/*.md, dialect/doris.mbt, lsp/diagnostics_formatting_test.mbt]

key-decisions:
  - "Task 1 checkpoint:decision auto-selected option-a (recommended/locked): full host cutover per D-06 — fathom.* config keys, single neutral 'sql' language id, fathom-sql-language-client / @fathom/sql-web-demo / fathom-sql-intellij package names, fathom.sql plugin id, FathomSettings/fathom.xml state, no default dialect (D-02)"
  - "The naming-gate job comment is written without literal forbidden patterns so ci.yml (a scanned product file) does not self-flag; the gate's own script carries the inventory and self-exempts (e7f6f69)"
  - "Sweep stragglers outside the explicit file lists (dialect/doris.mbt, lsp/diagnostics_formatting_test.mbt) are fixed to reach the zero-hit final sweep, per Task 4's 'fix EVERY remaining product-file hit' mandate — 2 lines each, no parser/selection-logic behavior change (406/406 native suite + parity baseline intact)"

requirements-completed: [DIALECT-01, NAME-01, NAME-03, NAME-04]

coverage:
  - id: D1
    description: "VS Code host cutover — neutral identity fathom-sql-language-client / 'Fathom SQL Language Client', language id sql, fathom.dialect/fathom.profile/fathom.serverPath config keys (no dialect/profile defaults, serverPath default fathom-lsp), fathom.restartLanguageServer command, initializationOptions {dialect, profile} per the 09-06 LSP contract, explicit error when fathom.dialect is unset"
    requirement: NAME-03
    verification:
      - kind: unit
        ref: "cd vscode && npm run build (tsc) passes; vscode extension.test.ts assertions (executor-run)"
        status: pass
      - kind: integration
        ref: "grep gate over vscode/ product files: zero occurrences of old extension name, old config keys, old command, old language id (executor-run)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Web/npm host cutover — @fathom/sql-web-demo with neutral description, neutral index.html titles + unpreselected dialect/profile selectors, monaco-adapter calling fathom_parse_v1(raw, dialect, profile, mode) with the A4 order and matching fathom.error.v1"
    requirement: NAME-03
    verification:
      - kind: unit
        ref: "cd web && npm run build (offline smoke) passes; web main.test.ts 4/4 (executor-run)"
        status: pass
      - kind: integration
        ref: "grep gate over web/ product files: zero occurrences of old package name / old schema strings (executor-run)"
        status: pass
    human_judgment: false
  - id: D3
    description: "JetBrains host cutover — fathom.jetbrains.sql package with FathomLanguageServerFactory/FathomSettings/FathomSettingsConfigurable/FathomNativeDownloader classes, FathomSettings/fathom.xml state, DEFAULT_EXECUTABLE fathom-lsp with no default profile (D-02), fathom.sql plugin id, fathom-sql server id, fathom-sql-intellij artifact, fathom-lsp-{platform} + fathom-lsp-manifest.json assets, updated source-smoke contracts"
    requirement: NAME-03
    verification:
      - kind: integration
        ref: "python3 jetbrains/scripts/source-smoke.py exits 0 (offline stdlib contract checker, executor-run); grep gate over jetbrains/ product files: zero old package/class/state/asset names"
        status: pass
    human_judgment: false
  - id: D4
    description: "NAME-04 naming inventory gate — scripts/check_naming.py (stdlib-only FORBIDDEN/allowlist matrix with D-04 path exemptions and D-05 dialect-semantics allowlist) plus the naming-gate job in .github/workflows/ci.yml running python3 scripts/check_naming.py on every push/PR, and the final repository-wide sweep clean"
    requirement: NAME-04
    verification:
      - kind: integration
        ref: "python3 scripts/check_naming.py exits 0 over 349 product files with the ok line; controlled probe (temporary product file with a forbidden pattern in a non-exempt path) fails with exit 1; python3 -m py_compile scripts/check_naming.py clean (all executor-run)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Neutral README/docs titles — README.md/README.zh-CN.md and docs/**/docs/zh-CN/** carry neutral product titles with dialect+profile tables; Doris appears only as a dialect/profile/corpus/provenance value (D-05)"
    requirement: NAME-03
    verification:
      - kind: integration
        ref: "final repository-wide sweep exit 0 covers README/docs with zero product-name remnants (executor-run)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Probe NAME-03 unclassified: live VS Code/IntelliJ dialect-selection UX and config precedence in a real editor (research OQ6/A2/A3) — the local proof is the repository-wide sweep plus web offline smoke plus jetbrains source-smoke; real-host UX verification is Phase 13"
    verification:
      - kind: other
        ref: "plan truth flagged-unverified: sweep + smokes green locally; real-editor host verification deferred to Phase 13"
        status: unknown
    human_judgment: true
    rationale: "Requires a real editor host (VS Code/IntelliJ) to exercise the dialect-selection UX end to end; automation cannot substitute for live-host verification, which the plan explicitly defers to Phase 13."

# Metrics
duration: unknown
completed: 2026-08-07
status: complete
---

# Phase 9 Plan 7: Neutral Host Cutover and Naming Gate — VS Code/Web/IntelliJ Identities, check_naming.py Gate, Clean Repository Sweep

**One-liner:** Completed the NAME-03 host cutover to the neutral fathom identity across VS Code (fathom.* config keys, sql language id, fathom-sql-language-client), Web/npm (@fathom/sql-web-demo, fathom_parse_v1 A4 calls), and IntelliJ (fathom.jetbrains.sql, fathom.sql plugin id, fathom-lsp defaults) with explicit dialect selection and no defaults anywhere (D-02), and shipped the NAME-04 scripts/check_naming.py inventory gate wired into CI — final repository-wide sweep clean over 349 product files with the controlled probe correctly failing.

## Performance

- **Duration:** unknown — the executor session was not timestamped (provider stream error terminated it before SUMMARY creation); this close-out run completed 2026-08-07. All verification numbers below are the executor's recorded results.
- **Started:** 2026-08-07 (wave 7 execution)
- **Completed:** 2026-08-07 (close-out run)
- **Tasks:** 4 (Task 1 = checkpoint:decision, Tasks 2-4 = implementation)
- **Commits:** 5 task commits + 1 final metadata commit
- **Files modified:** 47 unique files across the 5 task commits

## Accomplishments

- **VS Code + Web host cutover (1d54da4):** vscode/package.json is now `fathom-sql-language-client` with displayName "Fathom SQL Language Client", language id `sql` with `.sql` extensions, configuration keys `fathom.dialect` (enum doris/flink, NO default), `fathom.profile` (enum 2.1/3.x/4.x, NO default), `fathom.serverPath` (default `fathom-lsp`), and command `fathom.restartLanguageServer`; extension.ts reads `getConfiguration('fathom')` and forwards `initializationOptions {dialect, profile}` exactly matching the 09-06 LSP contract, surfacing an explicit error (no guessed dialect) when fathom.dialect is unset; extension-contract.ts exports SUPPORTED_DIALECTS and the normalizeProfile '4.x' fallback is deleted. Web is `@fathom/sql-web-demo` with neutral index.html titles + unpreselected dialect/profile selectors; monaco-adapter calls `fathom_parse_v1(utf8Bytes(source), dialect, profile, 'editor')` / `fathom_format_v1` in the A4 order and matches `fathom.error.v1`. This commit also closed the 09-05 deferred host assertions: offline-smoke.mjs `DORIS-FORMAT-001` → `FATHOM-FORMAT-001`, host-test.ts + vscode/README.md `DORIS-PARSE-006` → `FATHOM-PARSE-006`.
- **JetBrains host cutover (18d77d2):** kotlin sources moved to `fathom.jetbrains.sql` with FathomLanguageServerFactory/FathomSettings/FathomSettingsConfigurable/FathomNativeDownloader; initializationOptions is `mapOf("dialect" to dialect, "profile" to profile)`; FathomSettings uses `@State(name = "FathomSettings", storages = [Storage("fathom.xml")])` with `DEFAULT_EXECUTABLE = "fathom-lsp"` and the old DEFAULT_PROFILE constant deleted (D-02); plugin.xml declares plugin id `fathom.sql` and server id `fathom-sql`; settings.gradle.kts rootProject.name is `fathom-sql-intellij`; the downloader targets `fathom-lsp-{platform}` + `fathom-lsp-manifest.json`; jetbrains/scripts/source-smoke.py's require() contracts updated to the neutral names as the JetBrains-side naming gate.
- **Naming gate + neutral docs (75b6b7f):** scripts/check_naming.py — Python-stdlib-only forbidden/allowlist inventory gate (mirror of corpus/tools/check_keywords.py): FORBIDDEN regex list over product files, ALLOWLIST_PATHS (D-04 exemptions: corpus provenance, milestones archives, historical segments), ALLOWLIST_PATTERNS (D-05 dialect semantics), problems loop with nonzero exit and an ok line; .github/workflows/ci.yml gains the `naming-gate` job ("neutral naming inventory gate (NAME-04)") running `python3 scripts/check_naming.py` on every push/PR; README/README.zh-CN and docs/** + docs/zh-CN/** carry neutral product titles with dialect+profile tables.
- **Final repository-wide sweep (861d44e):** two stragglers outside the explicit file lists (dialect/doris.mbt, lsp/diagnostics_formatting_test.mbt — 2 lines each) fixed to reach zero product-file hits; gate exits 0 over 349 product files.
- **Gate self-flag fix (e7f6f69):** the ci.yml naming-gate job comment was reworded so its prose no longer embeds literal forbidden patterns (ci.yml is a scanned product file).
- **Verification matrix (executor-recorded):** web tests 4/4; vscode tsc build pass; jetbrains source-smoke pass; MoonBit native suite 406/406 with the parity baseline intact (no `--update`); `python3 scripts/check_naming.py` exit 0 over 349 product files; controlled probe (temporary product file with a forbidden pattern in a non-exempt path) correctly fails with exit 1; `py_compile` clean.

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm the D-06 host naming cutover surface** - no commit (checkpoint:decision, auto-selected option-a — full host cutover per D-06 + research A3/OQ6, the recommended/locked option)
2. **Task 2: VS Code + Web host cutover** - `1d54da4` (feat)
3. **Task 3: JetBrains host cutover** - `18d77d2` (feat)
4. **Task 4: README/docs neutral titles + check_naming.py + ci.yml naming-gate job + final sweep** - `75b6b7f` (feat), `861d44e` (chore: naming sweep clean), `e7f6f69` (chore: reword ci naming-gate comment to avoid self-flagged literals)

**Plan metadata:** `docs(09-07)` final metadata commit (SUMMARY + STATE + ROADMAP + REQUIREMENTS + deferred-items closure log).

## Files Created/Modified

- `scripts/check_naming.py` - NEW: NAME-04 stdlib-only forbidden/allowlist inventory gate (D-04 path exemptions, D-05 dialect-semantics allowlist), problems loop, nonzero exit, ok line
- `.github/workflows/ci.yml` - naming-gate job running `python3 scripts/check_naming.py`; job comment reworded to avoid self-flagged literals
- `vscode/package.json` - `fathom-sql-language-client`, "Fathom SQL Language Client", language id sql, fathom.* config keys
- `vscode/src/extension.ts`, `vscode/src/extension-contract.ts` - fathom.* key reads, initializationOptions {dialect, profile}, SUPPORTED_DIALECTS, no '4.x' fallback
- `vscode/README.md`, `vscode/scripts/host-verify.mjs`, `vscode/scripts/launch-smoke.mjs`, `vscode/src/host-test.ts` - neutral identity + FATHOM-PARSE-006 assertions (09-05 deferral closed)
- `web/package.json`, `web/index.html`, `web/src/monaco-adapter.ts`, `web/src/main.ts`, `web/src/main.test.ts`, `web/scripts/offline-smoke.mjs`, `web/scripts/serve.mjs` - @fathom/sql-web-demo, dialect selector, fathom_parse_v1 A4 order, FATHOM-FORMAT-001 (09-05 deferral closed)
- `jetbrains/src/main/kotlin/fathom/jetbrains/sql/*.kt` (4 Fathom* sources) + `jetbrains/src/test/kotlin/...` - fathom.jetbrains.sql package, FathomSettings/fathom.xml, no default profile
- `jetbrains/build.gradle.kts`, `jetbrains/settings.gradle.kts`, `jetbrains/src/main/resources/META-INF/plugin.xml`, `jetbrains/gradle/wrapper/gradle-wrapper.properties`, `jetbrains/README.md` - fathom-sql-intellij artifact, fathom.sql plugin id, fathom-sql server id, neutral changeNotes
- `jetbrains/scripts/source-smoke.py` - require() contracts updated to neutral names (JetBrains-side naming gate)
- `README.md`, `README.zh-CN.md`, `docs/*.md` (7), `docs/zh-CN/*.md` (7) - neutral product titles, dialect+profile tables
- `dialect/doris.mbt`, `lsp/diagnostics_formatting_test.mbt` - sweep stragglers (2 lines each; no behavior change)

## Decisions Made

- Task 1 checkpoint:decision auto-selected **option-a** (mode: yolo; the plan's recommended/locked option): full host cutover per D-06 — fathom.* config keys, single neutral `sql` language id (OQ6), fathom-sql-language-client / @fathom/sql-web-demo / fathom-sql-intellij package names, fathom.sql plugin id, FathomSettings/fathom.xml state, no-default-dialect rule (D-02). Options b (keep old language id) and c (default dialect) rejected as D-06/D-02 violations.
- The ci.yml naming-gate job comment is written without literal forbidden patterns — ci.yml is itself a scanned product file, so the gate comment must not self-flag (e7f6f69).
- Sweep stragglers in dialect/doris.mbt and lsp/diagnostics_formatting_test.mbt are fixed per Task 4's "fix EVERY remaining product-file hit" mandate; both are 2-line changes and the 406/406 native suite + intact parity baseline confirm no parser or selection-logic behavior change.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ci.yml naming-gate comment self-flagged the gate**
- **Found during:** Task 4 (final repository-wide sweep)
- **Issue:** the naming-gate job comment in .github/workflows/ci.yml embedded literal legacy product-name patterns (the very strings check_naming.py rejects); since ci.yml is a scanned product file, the gate flagged its own job's comment.
- **Fix:** reworded the comment to describe the gate without literal forbidden patterns.
- **Files modified:** .github/workflows/ci.yml
- **Verification:** python3 scripts/check_naming.py exit 0 over 349 product files.
- **Committed in:** e7f6f69 (separate chore commit)

**2. [Rule 1 - Bug] Final sweep flagged two stragglers outside the explicit Task 2-4 file lists**
- **Found during:** Task 4 (final repository-wide sweep)
- **Issue:** dialect/doris.mbt and lsp/diagnostics_formatting_test.mbt still carried product-name remnants; the plan's Task 4 action explicitly mandates fixing "EVERY remaining product-file hit the sweep reports, including stragglers outside the explicit file lists above". The plan's verification note ("do not touch parser core / LSP selection logic") is scoped to behavior: these are 2-line naming fixes, not logic changes.
- **Fix:** removed the remnant literals in both files (4 added / 4 deleted lines total).
- **Files modified:** dialect/doris.mbt, lsp/diagnostics_formatting_test.mbt
- **Verification:** sweep exit 0 with zero product-file hits; MoonBit native suite 406/406 with parity baseline intact (no --update).
- **Committed in:** 861d44e (chore: naming sweep clean)

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs surfaced by the sweep/gate itself)
**Impact on plan:** Both auto-fixes were required for the plan's own acceptance criteria (gate exits 0, zero product-file hits) and caused no behavior change. No scope creep.

## Issues Encountered

- The executor session terminated on a provider stream error immediately after committing e7f6f69, before writing 09-07-SUMMARY.md and updating STATE/ROADMAP. This close-out run completed the SUMMARY, the final metadata commit, and the tracking updates; all task work and verification had already been committed and recorded (5 commits listed above).

## User Setup Required

None - no external service configuration required (the naming gate is pure CI; the JetBrains gradle build remains CI-verified via jetbrains-plugin.yml on temurin 21, per the plan's local-JDK constraint).

## Next Phase Readiness

- Phase 9 is now 7/7 plans complete: explicit dialect/profile context (09-01..09-05), LSP selection contract (09-06), and the neutral host cutover + naming gate (09-07) — Phase 10 (Flink Release Profiles and Lexical Core) can proceed against a naming-gated repository.
- Live-editor verification of the dialect-selection UX and config precedence in real VS Code/IntelliJ hosts remains deferred to Phase 13 per the plan's flagged-unverified probe (research OQ6/A2/A3); local proof is the sweep + offline smokes.
- The naming gate now mechanically enforces the 09-04 module/binary names AND this plan's host identities on every push — a regression in either wave fails CI.

## Self-Check: PASSED

- Task commits verified in git: `1d54da4` (Task 2), `18d77d2` (Task 3), `75b6b7f` + `861d44e` + `e7f6f69` (Task 4).
- `09-07-SUMMARY.md` exists in the plan directory.
- Final metadata commit verified in git (see commit list in the completion report).

---
*Phase: 09-dialect-boundary-and-neutral-naming*
*Completed: 2026-08-07*
