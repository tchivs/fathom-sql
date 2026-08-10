---
phase: 13-toolchain-and-editor-packaging
plan: 06
subsystem: hosts
tags: [flink, d-05, d-06, toot-05, hosts, web, vscode, intellij, profiles-by-dialect, monaco, fathom-complete-v1]

# Dependency graph
requires:
  - phase: 13-toolchain-and-editor-packaging
    provides: 13-04 fathom_complete_v1 wire export (raw, dialect, profile, cursor_byte) + fathom.complete.v1 envelope — the Web host calls this export for the completion surface (D-04)
  - phase: 13-toolchain-and-editor-packaging
    provides: 13-05 LSP flink format/completion real paths — VS Code/IntelliJ hosts exercise real flink format/completion over the shared LSP surface (D-07)
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: the locked selection transport (document-level didOpen/didChange extension fields + initializationOptions/serve_stdio workspace default, D-01), the D-02 no-default/no-coercion rule, and the D-06 decision chain
  - phase: 12-cross-dialect-corpus-and-parity-gates
    provides: offline-first discipline (PARITY-03) — hosts must keep static constants, no runtime pull, no cross-host JSON
provides:
  - Web/Monaco host: PROFILES_BY_DIALECT (doris -> 2.1/3.x/4.x; flink -> flink-2.3.0/2.1.3/1.20.5) replaces the flat PROFILES list; validateSelection rejects cross-dialect pairs with MISSING_SELECTION; ParserAdapter.complete() calls fathom_complete_v1 (A4); the profile dropdown repopulates on dialect change so flink values appear only under flink
  - VS Code host: PROFILES_BY_DIALECT replaces SUPPORTED_PROFILES; resolveFathomConfiguration returns undefined for a missing/unsupported/cross-dialect profile; initializationOptions {dialect, profile} unchanged; the missing-selection error lists per-dialect values
  - IntelliJ host: PROFILES_BY_DIALECT map replaces ALLOWED_PROFILES; normalizeProfile(dialect, value) validates against the selected dialect's list; the profile ComboBox repopulates when dialectCombo changes
  - all three harness assertions (web offline-smoke.mjs, vscode launch-smoke.mjs, jetbrains source-smoke.py) updated to the per-dialect pairs in the SAME commit as the host constants (Pitfall 5)
affects: [TOOL-05 verifier, 13-07 packaging smoke (cross-host behavioral parity for flink files), TOOL-FUTURE-01 catalog-aware completion]

# Actuals (#2632) — pairs with the plan's `estimate` (42000 chars/4) to calibrate future estimates.
actuals:
  tokens: 7761    # chars/4 over the realized diff (31,045 diff chars across the 14 changed files)
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Per-dialect (dialect, profile) pair validation = a static frozen map PROFILES_BY_DIALECT per host (never a runtime pull / cross-host JSON) + a validateSelection/normalizeProfile branch that reads the selected dialect's list — the server (binding.validate_dialect_profile / LSP validate_selection) stays authoritative (defense in depth, D-05)
    - Same-commit rule (Pitfall 5): every host constant change updates its harness assertion in the SAME commit — offline-smoke/launch-smoke/source-smoke plus the host unit tests (web main.test.ts, vscode extension.test.ts, jetbrains FathomSettingsTest.kt) stop pinning the old flat list
    - Host completion surface = the same wire export as JS/linear-Wasm: ParserAdapter.complete calls fathom_complete_v1(utf8Bytes(source), dialect, profile, cursorByte) (A4) and decodes the fathom.complete.v1 envelope — no second parser (D-04, TOOL-05)

key-files:
  created: []
  modified:
    - web/src/monaco-adapter.ts
    - web/src/main.ts
    - web/src/main.test.ts
    - web/scripts/offline-smoke.mjs
    - web/package.json
    - vscode/src/extension-contract.ts
    - vscode/src/extension.ts
    - vscode/src/extension.test.ts
    - vscode/scripts/launch-smoke.mjs
    - jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomSettings.kt
    - jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomSettingsConfigurable.kt
    - jetbrains/src/test/kotlin/fathom/jetbrains/sql/FathomSettingsTest.kt
    - jetbrains/scripts/source-smoke.py
    - .gitignore

key-decisions:
  - "D-06 one-way door (Task 1, auto-selected option-a under auto_advance): confirm the locked selection transport stays unchanged — workspace/session default (LSP initializationOptions / CLI --dialect --profile / VS Code fathom.dialect / IntelliJ FathomSettings) + per-file LSP didOpen/didChange extension-field override; NO auto-detection and NO extension-based guessing; Phase 13 only lets the flink profile values pass each host's static validation."
  - "D-05 (reversible): hosts validate (dialect, profile) pairs statically with a per-dialect map — doris -> 2.1/3.x/4.x, flink -> flink-2.3.0/2.1.3/1.20.5 — and the profile dropdown/ComboBox repopulates on dialect change; a cross-dialect value is an explicit MISSING_SELECTION / config error, never a coerced default (D-02)."
  - "Server-authoritative validation: hosts are defense-in-depth only; binding.validate_dialect_profile / LSP validate_selection remains the final gate — a host accepting a value the server rejects is a server-side error, never a silent fallback."

patterns-established:
  - "Pattern: host (dialect, profile) validation = Object.freeze({ doris: [...], flink: [...] }) (TS) / mapOf(\"doris\" to [...], \"flink\" to [...]) (Kotlin) + a single validateSelection/normalizeProfile branch keyed on the selected dialect; static per-host constants only (offline-first, PARITY-03)."
  - "Pattern: harness same-commit — the assertion text mirrors the constant's exact shape (PROFILES_BY_DIALECT = Object.freeze({ doris: [...], flink: [...] })), so a stale flat-list assert fails fast after the legitimate D-05 change."

requirements-completed: [TOOL-05]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "Web/Monaco host — PROFILES_BY_DIALECT (doris 2.1/3.x/4.x; flink flink-2.3.0/2.1.3/1.20.5) replaces the flat PROFILES list; validateSelection rejects cross-dialect pairs (flink+'2.1', doris+'flink-2.3.0') with MISSING_SELECTION; ParserAdapter.complete() calls fathom_complete_v1 (A4) and decodes the fathom.complete.v1 envelope; main.ts profile dropdown repopulates on dialect change"
    requirement: TOOL-05
    verification:
      - kind: unit
        ref: "web/src/main.test.ts#adapter validates (dialect, profile) pairs per dialect — cross-dialect profiles rejected (D-05)"
        status: pass
      - kind: unit
        ref: "web/src/main.test.ts#adapter complete() calls fathom_complete_v1 with the A4 args and decodes the envelope (D-04)"
        status: pass
      - kind: other
        ref: "cd web && npm test && npm run build"
        status: pass
    human_judgment: false
  - id: D2
    description: "VS Code host — PROFILES_BY_DIALECT replaces SUPPORTED_PROFILES; resolveFathomConfiguration returns undefined for a missing/unsupported/cross-dialect profile and the configured profile for a valid pair; initializationOptions {dialect, profile} unchanged; the missing-selection error lists per-dialect values"
    requirement: TOOL-05
    verification:
      - kind: unit
        ref: "vscode/src/extension.test.ts#configuration requires an explicit supported dialect, profile, and local executable"
        status: pass
      - kind: other
        ref: "cd vscode && npm run build && node scripts/launch-smoke.mjs --protocol"
        status: pass
    human_judgment: false
  - id: D3
    description: "IntelliJ host — PROFILES_BY_DIALECT map replaces ALLOWED_PROFILES; normalizeProfile(dialect, value) validates against the selected dialect's list (flink+'2.1'->null, flink+'flink-2.3.0'->'flink-2.3.0'); the profile ComboBox repopulates when dialectCombo changes"
    requirement: TOOL-05
    verification:
      - kind: unit
        ref: "jetbrains/src/test/kotlin/fathom/jetbrains/sql/FathomSettingsTest.kt#onlyReleasedDialectsAndPerDialectProfilesAreAccepted"
        status: pass
      - kind: unit
        ref: "jetbrains/src/test/kotlin/fathom/jetbrains/sql/FathomSettingsTest.kt#updateRejectsCrossDialectProfilePairs"
        status: pass
      - kind: other
        ref: "cd jetbrains && JAVA_HOME=<jdk21> ./gradlew compileKotlin test && python3 scripts/source-smoke.py"
        status: pass
    human_judgment: false
  - id: D4
    description: "D-06 one-way door — confirm the locked selection transport stays unchanged (workspace/session default + per-file LSP didOpen/didChange override, no auto-detection, no extension guessing); only flink values pass host validation; recorded for the host tasks that proceeded with the confirmed model"
    requirement: TOOL-05
    verification: []
    human_judgment: true
    rationale: "D-06 is a one-way public-LSP-contract decision gate (checkpoint:decision). The selection was auto-selected (option-a, the D-06-locked model) under auto_advance; the transport JSON shape is frozen and the choice itself is a product contract that the 13-07 packaging smoke re-verifies cross-host."

# Metrics
duration: 24min
completed: 2026-08-10
status: complete
---

# Phase 13 Plan 06: Web/VS Code/IntelliJ (dialect, profile) pair validation (TOOL-05/D-05/D-06)

**All three editor hosts (Web/Monaco, VS Code, IntelliJ) now validate the (dialect, profile) pair instead of a flat profile list — doris → 2.1/3.x/4.x, flink → flink-2.3.0/2.1.3/1.20.5 — with the profile dropdown/ComboBox repopulating on dialect change, the Web host gaining the fathom_complete_v1 completion surface, and all three harness assertions updated to the per-dialect pairs in the same commit (D-05, Pitfall 5); the locked D-06 selection transport (workspace default + per-file override, no auto-detection) is unchanged.**

## Performance

- **Duration:** 24 min
- **Started:** 2026-08-10T03:47Z
- **Completed:** 2026-08-10T04:11Z
- **Tasks:** 3 executed + 1 checkpoint decision
- **Files modified:** 14 (13 host/harness files + .gitignore housekeeping)

## Accomplishments
- **Web/Monaco host (Task 2 tracer):** `PROFILES_BY_DIALECT` (doris 2.1/3.x/4.x; flink flink-2.3.0/2.1.3/1.20.5) replaces the flat `PROFILES` list; `validateSelection` rejects cross-dialect pairs (`flink`+`2.1`, `doris`+`flink-2.3.0`) with `MISSING_SELECTION`; `ParserAdapter.complete()` calls `fathom_complete_v1(utf8Bytes(source), dialect, profile, cursorByte)` (A4, D-04) and decodes the `fathom.complete.v1` envelope; `main.ts` repopulates the profile dropdown on dialect change so flink values appear only under flink.
- **VS Code host (Task 3):** `PROFILES_BY_DIALECT` replaces `SUPPORTED_PROFILES`; `resolveFathomConfiguration` returns `undefined` for a missing/unsupported/cross-dialect profile (explicit config error, D-02) and the configured profile for a valid pair; `initializationOptions {dialect, profile}` stays byte-identical; the missing-selection error now lists per-dialect values (`doris: 2.1|3.x|4.x; flink: flink-2.3.0|flink-2.1.3|flink-1.20.5`).
- **IntelliJ host (Task 4):** `PROFILES_BY_DIALECT: Map<String, List<String>>` replaces `ALLOWED_PROFILES`; `normalizeProfile(dialect, value)` validates against the selected dialect's list; the profile ComboBox repopulates when `dialectCombo` changes; `apply()`/`reset()` use the per-dialect normalize.
- **Same-commit rule (Pitfall 5):** web `offline-smoke.mjs`, vscode `launch-smoke.mjs`, jetbrains `source-smoke.py` — plus the host unit tests (`main.test.ts`, `extension.test.ts`, `FathomSettingsTest.kt`) — all assert the per-dialect pairs + flink values in the SAME commits as the host constants; no stale flat list remains.
- **Server remains authoritative:** hosts are defense-in-depth only; `binding.validate_dialect_profile` / LSP `validate_selection` stays the final gate — no coercion, no fallback (T-13-06-01/02/07 mitigated).

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm the selection transport stays unchanged — D-06 one-way door** - `(auto-resolved option-a, no commit)` — decision checkpoint auto-selected "keep the locked selection transport unchanged; only let flink values pass host validation" under auto_advance (D-06 locked)
2. **Task 2: Web/Monaco host — (dialect, profile) pairs + fathom_complete_v1 + profile dropdown end-to-end** - `25d8dea` (feat) — PROFILES_BY_DIALECT + validateSelection pair check + complete() + dropdown repopulation + main.test.ts + offline-smoke + package.json test script
3. **Task 3: VS Code host — PROFILES_BY_DIALECT + pair validation + launch-smoke same-commit** - `3e645fb` (feat) — PROFILES_BY_DIALECT + resolveFathomConfiguration pair validation + per-dialect error message + extension.test.ts + launch-smoke
4. **Task 4: IntelliJ host — per-dialect ALLOWED_PROFILES + ComboBox switch + source-smoke same-commit** - `c72bd5e` (feat) — PROFILES_BY_DIALECT map + normalizeProfile(dialect, value) + ComboBox repopulation + FathomSettingsTest + source-smoke + .gitignore housekeeping

**Plan metadata:** `(summary commit follows)`

## Files Created/Modified
- `web/src/monaco-adapter.ts` - `PROFILES_BY_DIALECT` frozen per-dialect map; `validateSelection` per-dialect pair check; `ParserAdapter.complete()` calling `fathom_complete_v1` (A4)
- `web/src/main.ts` - profile dropdown repopulation via `repopulateProfileOptions(dialect)` on dialect change
- `web/src/main.test.ts` - pair-validation (cross-dialect rejection) + complete() A4 assertions; `fathom_complete_v1` in the fake artifact
- `web/scripts/offline-smoke.mjs` - per-dialect pair + flink value assertions, flat-list-removed negative assertion, `fathom_complete_v1` A4 assertion
- `web/package.json` - `"test": "node --test"` script (required by the plan's `npm test` verify)
- `vscode/src/extension-contract.ts` - `PROFILES_BY_DIALECT`; `resolveFathomConfiguration` pair validation returning `undefined` for cross-dialect profiles
- `vscode/src/extension.ts` - import/re-export updates; missing-selection error lists per-dialect values; `initializationOptions` unchanged
- `vscode/src/extension.test.ts` - per-dialect map + cross-dialect rejection assertions
- `vscode/scripts/launch-smoke.mjs` - per-dialect pair + flink value assertions; reads `extension-contract.ts`
- `jetbrains/.../FathomSettings.kt` - `PROFILES_BY_DIALECT: Map<String, List<String>>`; `normalizeProfile(dialect, value)`; `loadState`/`update` call sites pass the dialect
- `jetbrains/.../FathomSettingsConfigurable.kt` - profile ComboBox repopulation on `dialectCombo` change; `apply()`/`reset()` per-dialect normalize
- `jetbrains/.../FathomSettingsTest.kt` - per-dialect map + cross-dialect rejection + `updateRejectsCrossDialectProfilePairs`
- `jetbrains/scripts/source-smoke.py` - per-dialect map + `normalizeProfile(dialect, value)` signature assertions; flat `ALLOWED_PROFILES` forbidden
- `.gitignore` - ignore jetbrains Gradle/IntelliJ build outputs (`build/`, `.gradle/`, `.intellijPlatform/`)

## Decisions Made
- **D-06 one-way (Task 1, auto-selected option-a):** keep the locked selection transport byte-for-byte — workspace/session default (initializationOptions / CLI / VS Code fathom.dialect / IntelliJ FathomSettings) + per-file didOpen/didChange override; no auto-detection, no extension guessing (D-01). Phase 13 only lets flink values pass host validation.
- **D-05 (reversible):** each host keeps a static per-dialect `PROFILES_BY_DIALECT` map (no dynamic pull, no shared cross-host JSON — offline-first, PARITY-03); the profile dropdown/ComboBox repopulates on dialect change; a cross-dialect value is an explicit error, never a coerced default (D-02).
- **Server-authoritative validation:** host pair validation is defense in depth; the server re-validates every selection.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] web/package.json had no `test` script, so the plan's `cd web && npm test` verify could not run**
- **Found during:** Task 2 (Web tracer verification)
- **Issue:** The plan's `<verify>` runs `npm test`, but web/package.json defined only `start` and `build`. `npm test` failed with "Missing script: test".
- **Fix:** Added `"test": "node --test"` (Node 25's built-in runner discovers `main.test.ts`).
- **Files modified:** web/package.json
- **Verification:** `npm test` runs 6 tests, all pass.
- **Committed in:** 25d8dea (Task 2 commit)

**2. [Rule 3 - Blocking] Host unit tests pinned the removed flat-list constants**
- **Found during:** Tasks 3 and 4 (VS Code + IntelliJ host changes)
- **Issue:** `vscode/src/extension.test.ts` imported `SUPPORTED_PROFILES` and `jetbrains/.../FathomSettingsTest.kt` asserted `ALLOWED_PROFILES = listOf("2.1","3.x","4.x")` and the single-arg `normalizeProfile(value)` — both broken by the D-05 constant change (Pitfall 5 applied to the unit tests, not just the smoke harnesses).
- **Fix:** Updated both test files to the per-dialect contract — `PROFILES_BY_DIALECT` deep-equal, `normalizeProfile(dialect, value)` assertions, cross-dialect rejection, and a new `updateRejectsCrossDialectProfilePairs` test.
- **Files modified:** vscode/src/extension.test.ts, jetbrains/src/test/kotlin/fathom/jetbrains/sql/FathomSettingsTest.kt
- **Verification:** `node --test src/extension.test.ts` (3/3 pass); `./gradlew test` → FathomSettingsTest 7/7 pass, 0 failures.
- **Committed in:** 3e645fb (Task 3), c72bd5e (Task 4)

**3. [Rule 3 - Blocking] launch-smoke `SUPPORTED_PROFILES` assertion matched a doc comment**
- **Found during:** Task 3 (VS Code launch-smoke verification)
- **Issue:** My first `assert.doesNotMatch(contractText, /SUPPORTED_PROFILES/, ...)` failed because the word still appears in a D-05 explanatory comment ("the flat SUPPORTED_PROFILES list is replaced...").
- **Fix:** Narrowed the assertion to the constant declaration: `/SUPPORTED_PROFILES\s*=\s*Object\.freeze/`.
- **Files modified:** vscode/scripts/launch-smoke.mjs
- **Verification:** `node scripts/launch-smoke.mjs --protocol` passes.
- **Committed in:** 3e645fb (Task 3)

**4. [Rule 3 - Blocking] jetbrains Gradle required JVM 17+ but the environment defaulted to JDK 8**
- **Found during:** Task 4 (IntelliJ verification)
- **Issue:** `./gradlew` failed with "Gradle requires JVM 17 or later... currently configured to use JVM 8" (`JAVA_HOME=/opt/bigdata/jdk1.8`).
- **Fix:** Ran the Gradle build with JDK 21 (`/usr/lib/jvm/java-21-openjdk-21.0.9.0.10-2.el9.alma.1.x86_64`), which matches the CI JDK pinned in `.github/workflows/jetbrains-plugin.yml` (`temurin` 21).
- **Files modified:** none (environment/toolchain only)
- **Verification:** `./gradlew compileKotlin test` → BUILD SUCCESSFUL, FathomSettingsTest 7/7 pass.
- **Committed in:** c72bd5e (Task 4; no file change, documented here)

**5. [Housekeeping] jetbrains build outputs were untracked and not gitignored**
- **Found during:** Task 4 (post-build git status)
- **Issue:** `jetbrains/build/`, `jetbrains/.gradle/`, `jetbrains/.intellijPlatform/` were untracked generated artifacts not covered by `.gitignore` (unlike `_build/`, `node_modules/`, `vscode/dist/`).
- **Fix:** Added the three jetbrains build directories to the root `.gitignore`.
- **Files modified:** .gitignore
- **Verification:** `git status --short` no longer lists them as untracked.
- **Committed in:** c72bd5e (Task 4)

---

**Total deviations:** 4 auto-fixed (all Rule 3 blocking) + 1 housekeeping.
**Impact on plan:** All auto-fixes were necessary to run the plan's own verification commands and to keep the repo's test suite green after the D-05 constant changes. No scope creep; the same-commit rule (Pitfall 5) was extended to the host unit tests as well as the smoke harnesses.

## Issues Encountered
- **launch-smoke `--protocol` flag:** the plan's `<verify>` wrote `node scripts/launch-smoke.mjs`, but the harness (a Phase 9 contract) requires the explicit `--protocol` flag: `assert.equal(process.argv.includes('--protocol'), true, 'protocol smoke must be explicit')`. Verified with `node scripts/launch-smoke.mjs --protocol` — passes.
- **Environment JDK:** the shell default `JAVA_HOME` points at JDK 8; Gradle 9.6.1 needs JVM 17+. Used the CI-pinned JDK 21 for the IntelliJ build. No repo change required.
- **IntelliJ Platform Gradle plugin auto-detect:** the plugin logged "Invalid Java installation found at '/opt/data/jdks/jdk-24.0.2+12' (IntelliJ) auto-detected" but the build completed successfully; this is a toolchain auto-detect notice, not a failure.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- **13-07 packaging smoke:** the plan's flagged-unverified probe (TOOL-05 host parity) — cross-host behavioral parity for a flink file (open flink file → select flink dialect/profile → receive diagnostics, format/completion at supported points) — is deferred to 13-07. This plan delivers the host-side (dialect, profile) pair validation + flink values passing each host's static validation; 13-07 exercises the real per-file override on flink files across Web/VS Code/IntelliJ.
- **Frozen snapshots:** no MoonBit core, parity snapshot, or approved-changes file moved; the Doris baseline (213) and flink-grammar/flink-lexical snapshots remain byte-identical.
- **Server-authoritative gate:** the LSP `validate_selection` and `binding.validate_dialect_profile` paths already accept the three flink profiles (13-05/10-04); hosts now let the same values pass statically.

---
*Phase: 13-toolchain-and-editor-packaging*
*Completed: 2026-08-10*

## Self-Check: PASSED
- FOUND: .planning/phases/13-toolchain-and-editor-packaging/13-06-SUMMARY.md
- FOUND: web/src/monaco-adapter.ts
- FOUND: vscode/src/extension-contract.ts
- FOUND: jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomSettings.kt
- FOUND: commits 25d8dea, 3e645fb, c72bd5e
