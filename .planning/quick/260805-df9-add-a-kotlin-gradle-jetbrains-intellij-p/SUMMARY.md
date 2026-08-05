---
phase: quick-260805-df9
plan: jetbrains-intellij-plugin
subsystem: tooling
status: complete
tags: [kotlin, gradle, intellij, lsp4ij, doris-lsp]

requires:
  - phase: 04-ecosystem-and-multi-target-delivery
    provides: Native doris-lsp executable and explicit Doris profile contract
provides:
  - Kotlin/Gradle IntelliJ plugin scaffold with pinned IntelliJ, Kotlin, JDK, and LSP4IJ versions
  - Application settings for local doris-lsp executable and 2.1/3.x/4.x profile selection
  - LSP4IJ stdio process factory passing initializationOptions.profile on new connections
  - Deterministic source wiring smoke and task-local build verification evidence
affects: [intellij, lsp, editor-integration]

actuals:
  tokens: 17795
  tasks: 3
  commits: 3

tech-stack:
  added: [IntelliJ Platform Gradle Plugin 2.9.0, Kotlin JVM 2.2.0, Gradle 8.14 wrapper, LSP4IJ 0.20.1]
  patterns: [application PersistentStateComponent, LSP4IJ OSProcessStreamConnectionProvider, source-level contract smoke]

key-files:
  created:
    - jetbrains/build.gradle.kts
    - jetbrains/settings.gradle.kts
    - jetbrains/gradle/wrapper/gradle-wrapper.jar
    - jetbrains/src/main/resources/META-INF/plugin.xml
    - jetbrains/src/main/kotlin/fathom/jetbrains/doris/DorisSettings.kt
    - jetbrains/src/main/kotlin/fathom/jetbrains/doris/DorisSettingsConfigurable.kt
    - jetbrains/src/main/kotlin/fathom/jetbrains/doris/DorisLanguageServerFactory.kt
    - jetbrains/src/test/kotlin/fathom/jetbrains/doris/DorisSettingsTest.kt
    - jetbrains/scripts/source-smoke.py
    - jetbrains/README.md
  modified: []

key-decisions:
  - "Use LSP4IJ 0.20.1 as the only LSP API/runtime provider; no independently declared LSP4J dependency."
  - "Read settings into an immutable connection snapshot so apply changes affect only the next server start/restart."
  - "Keep SQL integration as LSP4IJ *.sql filename mapping without registering a second parser or IntelliJ language."

requirements-completed: []

coverage:
  - id: D1
    description: "Pinned Gradle IntelliJ plugin scaffold and plugin.xml wiring for Doris SQL LSP4IJ server"
    verification:
      - kind: unit
        ref: "python3 scripts/source-smoke.py"
        status: pass
    human_judgment: false
  - id: D2
    description: "Persistent executable/profile settings, UI validation, and profile initialization propagation"
    verification:
      - kind: unit
        ref: "DorisSettingsTest.kt (Gradle test task not runnable: missing plugin artifact)"
        status: unknown
      - kind: unit
        ref: "python3 scripts/source-smoke.py"
        status: pass
    human_judgment: true
    rationale: "Kotlin tests could not execute because the pinned IntelliJ Platform Gradle Plugin was unavailable from the configured network and offline cache."
  - id: D3
    description: "Checked-in Gradle wrapper and documented plugin installation/build workflow"
    verification:
      - kind: other
        ref: "unzip -l gradle/wrapper/gradle-wrapper.jar; wrapper properties inspection"
        status: pass
    human_judgment: false

# Metrics
duration: 25min
completed: 2026-08-05
---

# Quick Task 260805-df9: JetBrains IntelliJ Plugin Summary

**Kotlin/Gradle IntelliJ plugin for Doris SQL using LSP4IJ stdio and explicit profile settings**

## Performance

- **Duration:** approximately 25 minutes
- **Started:** 2026-08-05T00:00:00Z (execution session start was not captured by the quick-task runner)
- **Completed:** 2026-08-05
- **Tasks:** 3
- **Files added:** 14 plugin files plus this summary/state artifact

## Accomplishments

- Added a standalone IntelliJ Platform Gradle project pinned to IntelliJ Platform Gradle Plugin `2.9.0`, Kotlin JVM `2.2.0`, IntelliJ IDEA Community `2025.2`, JDK 21, LSP4IJ `0.20.1`, and a checked-in Gradle 8.14 wrapper.
- Registered the `doris` LSP4IJ server, `*.sql` filename mapping with language id `doris`, and an application-level Doris SQL settings configurable.
- Implemented persisted executable/profile settings with defaults `doris-lsp`/`4.x`, strict profiles `2.1`, `3.x`, `4.x`, UI validation, and immutable per-connection snapshots.
- Implemented `LanguageServerFactory` using `GeneralCommandLine` and `OSProcessStreamConnectionProvider`; each new connection returns `mapOf("profile" to profile)` initialization options.
- Added Kotlin tests for defaults, profile/path validation, invalid persisted values, initialization key propagation, and next-connection configuration semantics.
- Added deterministic Python source smoke and installation/build documentation.

## Task Commits

1. **Task 1: Gradle IntelliJ plugin scaffold and declarations** - `7c272a8`
2. **Task 2: Settings UI, persistence, and LSP4IJ stdio factory** - `d709384`
3. **Task 3: Deterministic source wiring smoke** - `eda1f2c`

## Verification Evidence

- `cd jetbrains && python3 scripts/source-smoke.py` — **PASS**: plugin wiring, settings propagation, stdio provider, and dependency boundaries.
- `cd jetbrains && ./gradlew --no-daemon tasks --all` — **BLOCKED by environment** before project evaluation: Gradle could not resolve `org.jetbrains.intellij.platform:intellij-platform-gradle-plugin:2.9.0` because `plugins.gradle.org` DNS/network access failed.
- `cd jetbrains && ./gradlew --no-daemon compileKotlin compileTestKotlin` — **BLOCKED by the same exact coordinate/network failure** (`plugins.gradle.org`).
- `cd jetbrains && ./gradlew --no-daemon clean test verifyPlugin buildPlugin` — **BLOCKED**: both `plugins.gradle.org` and `repo.maven.apache.org` could not resolve the pinned `org.jetbrains.intellij.platform:intellij-platform-gradle-plugin:2.9.0` artifact.
- `cd jetbrains && ./gradlew --offline --no-daemon test verifyPlugin buildPlugin` — **BLOCKED** with exact cache evidence: `No cached version of org.jetbrains.intellij.platform:intellij-platform-gradle-plugin:2.9.0 available for offline mode.`
- Wrapper archive and properties inspected successfully; `gradle-wrapper.jar` is present and points to `gradle-8.14-bin.zip`.

No build claim is made: Kotlin tests, `verifyPlugin`, and `buildPlugin` were not runnable without the pinned Gradle plugin artifact.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Generated Gradle wrapper independently of project plugin resolution**
- **Found during:** Task 1
- **Issue:** `gradle wrapper` evaluated the plugin build before the wrapper existed and failed because the environment could not resolve `org.jetbrains.intellij.platform:intellij-platform-gradle-plugin:2.9.0`.
- **Fix:** Generated the standard Gradle 8.14 wrapper from a temporary wrapper-only Gradle build, then checked in the generated scripts, properties, and jar. No dependency/version was changed.
- **Files modified:** `jetbrains/gradlew`, `jetbrains/gradlew.bat`, `jetbrains/gradle/wrapper/*`
- **Verification:** wrapper archive listing and properties inspection; wrapper launches and reaches the pinned dependency resolution failure.
- **Committed in:** `7c272a8`

**2. [Rule 1 - Bug] Corrected source smoke false positives for standard wrapper metadata**
- **Found during:** Task 3
- **Issue:** The initial forbidden-surface scan treated standard Gradle wrapper URLs and the plugin descriptor vendor URL as remote runtime fallbacks.
- **Fix:** Kept explicit XML/build/source contract checks and excluded wrapper scripts, plugin.xml, README, and the smoke script from the generic fallback-text scan.
- **Files modified:** `jetbrains/scripts/source-smoke.py`
- **Verification:** `python3 scripts/source-smoke.py` passes.
- **Committed in:** `eda1f2c`

**Total deviations:** 2 auto-fixed (Rule 3: 1, Rule 1: 1). Both were necessary to complete the planned deliverable without weakening pinned dependencies or allowing forbidden runtime fallbacks.

## Issues Encountered

The configured environment exposes JDK 8 by default, while the project requires JDK 21. All Gradle checks were invoked with `JAVA_HOME=/opt/data/jdks/ms-21.0.9`. The build remained blocked earlier at plugin resolution because DNS/network access to Gradle/Maven repositories was unavailable and the pinned plugin was not cached. No dependency was deleted, downgraded, made dynamic, or replaced.

## User Setup Required

None for source setup. At runtime, install the generated plugin ZIP and the LSP4IJ `0.20.1` plugin as described in `jetbrains/README.md`, then configure the local `doris-lsp` executable path and profile in IntelliJ Settings.

## Next Phase Readiness

The source and descriptor are complete and committed. Re-run the exact Gradle commands from `jetbrains/README.md` in an environment with repository access (or with the pinned IntelliJ Platform plugin, SDK, Kotlin, and LSP4IJ artifacts cached) to execute Kotlin tests, `verifyPlugin`, and `buildPlugin` and confirm ZIP output.

## Self-Check: PASSED

- `jetbrains/gradlew` and `jetbrains/gradle/wrapper/gradle-wrapper.jar` exist.
- Commits `7c272a8`, `d709384`, and `eda1f2c` exist in repository history.
- `python3 jetbrains/scripts/source-smoke.py` passed after all implementation commits.
- No generated `jetbrains/.gradle/` state remains untracked.
