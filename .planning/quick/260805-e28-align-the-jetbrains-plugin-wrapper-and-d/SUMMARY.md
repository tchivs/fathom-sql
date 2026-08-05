---
phase: quick-260805-e28
plan: align-the-jetbrains-plugin-wrapper-and-docs
subsystem: tooling
status: complete
tags: [kotlin, gradle, intellij, lsp4ij]

requires:
  - phase: 04-ecosystem-and-multi-target-delivery
    provides: JetBrains plugin scaffold and pinned dependency declarations
provides:
  - Gradle 9.0.0 wrapper distribution pin for the JetBrains plugin
  - README build-version documentation aligned with the wrapper
affects: [intellij, build-tooling, documentation]

tech-stack:
  added: []
  patterns: [task-local source smoke verification]

key-files:
  created:
    - .planning/quick/260805-e28-align-the-jetbrains-plugin-wrapper-and-d/SUMMARY.md
  modified:
    - jetbrains/gradle/wrapper/gradle-wrapper.properties
    - jetbrains/README.md

decisions:
  - "Use Gradle 9.0.0 because the current official IntelliJ Platform Gradle Plugin 2.x documentation identifies it as the minimum supported Gradle version."
  - "Preserve IntelliJ Platform Gradle Plugin 2.9.0, Kotlin JVM 2.2.0, LSP4IJ 0.20.1, IntelliJ IDEA 2025.2, and JDK 21 unchanged."

metrics:
  duration: 5min
  completed: 2026-08-05
---

# Quick Task 260805-e28: JetBrains Gradle Wrapper/README Alignment Summary

**JetBrains plugin wrapper and build documentation now consistently use Gradle 9.0.0.**

## Changes

- Changed only `jetbrains/gradle/wrapper/gradle-wrapper.properties` `distributionUrl` from `gradle-8.14-bin.zip` to `gradle-9.0.0-bin.zip`.
- Changed only the README build-version wording from `Gradle 8.14` to `Gradle 9.0.0`.
- Retained IntelliJ Platform Gradle Plugin `2.9.0`, Kotlin JVM `2.2.0`, LSP4IJ `0.20.1`, IntelliJ IDEA Community `2025.2`, and JDK 21 unchanged.
- No plugin source, dependency declarations, formatter output, linter output, or project-wide test artifacts were changed.

## Verification Evidence

- `cd jetbrains && python3 scripts/source-smoke.py` — **PASS**: `SOURCE SMOKE PASSED: plugin wiring, settings propagation, stdio provider, and dependency boundaries`.
- Target-file diff inspection — **PASS**: exactly two implementation files changed, with one line changed in each.
- `git diff --check -- jetbrains/README.md jetbrains/gradle/wrapper/gradle-wrapper.properties` — **PASS**.
- No Gradle build was run or claimed. The pinned IntelliJ Platform Gradle Plugin artifact remains unavailable in this environment.

## Task Commit

- `f53b04f` — `fix(quick-260805-e28): align JetBrains Gradle wrapper`

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Self-Check: PASSED

- Both target files exist with the requested Gradle 9.0.0 values.
- Commit `f53b04f` exists and contains only the two implementation files.
- The designated source smoke check passed.
- No Gradle build success is asserted.
