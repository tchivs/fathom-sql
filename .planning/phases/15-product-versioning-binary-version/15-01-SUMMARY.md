---
phase: 15-product-versioning-binary-version
plan: 01
subsystem: infra
tags: [versioning, semver, cli, lsp]

# Dependency graph
requires:
  - phase: 14-release-hygiene-toolchain-pinning
    provides: three-platform release DAG and dry-run driver
provides:
  - single-source product version constant (1.0.0)
  - `--version` on both release binaries with release-tag consistency assertion
  - recorded semver policy (VER-01)
affects: 16 install guide (version verify command), 17 changelog, 20 formal release

# Actuals
actuals:
  tokens: 900
  tasks: 2
  commits: 3 (incl. context doc)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-source version identity: shared version/ package imported by both executables; no second constant"
    - "Release-tag consistency as a real CI gate: build job runs the produced binary --version and compares against RELEASE_TAG"

key-files:
  created:
    - version/moon.pkg
    - version/version.mbt
    - docs/VERSIONING.md
  modified:
    - fathom-sql/moon.pkg, fathom-sql/run.mbt, fathom-sql/main.mbt, fathom-sql/cli_test.mbt
    - fathom-lsp/moon.pkg, fathom-lsp/main.mbt
    - .github/workflows/fathom-native-release.yml
    - scripts/run_phase14_release_dry_run.py

key-decisions:
  - "Product version 1.0.0 single-sourced in version/version.mbt; moon.mod 0.1.0 stays decoupled (Phase 13)"
  - "`--version` output `<name> 1.0.0`, exit 0, only when --version is the sole argument; other paths unchanged"

patterns-established:
  - "Version identity: one constant -> both binaries -> CI assertion vs tag"

requirements-completed: [VER-01, VER-02]

coverage:
  - id: D1
    description: "Single-source product version 1.0.0 with --version on fathom-sql and fathom-lsp (exit 0, exact output)"
    requirement: VER-02
    verification:
      - kind: unit
        ref: "moon test --target native --package version (2/2) + --package fathom-sql (38/38 incl. cli_version_exit_0_exact_output)"
        status: pass
      - kind: other
        ref: "real binary runs: fathom-sql.exe --version -> 'fathom-sql 1.0.0' rc=0; fathom-lsp.exe --version -> 'fathom-lsp 1.0.0' rc=0; fathom-sql parse --version -> rc=2"
        status: pass
    human_judgment: false
  - id: D2
    description: "Recorded semver policy covering first public 1.0.0, fathom.*.v1 stability, contract-version bump, module/product decoupling"
    requirement: VER-01
    verification:
      - kind: other
        ref: "docs/VERSIONING.md (committed c1c1eb6): semver scheme, wire-contract stability commitment, version bump process, module vs product version"
        status: pass
    human_judgment: false
  - id: D3
    description: "Release pipeline asserts produced binaries report the release tag version on every platform"
    requirement: VER-02
    verification:
      - kind: other
        ref: "fathom-native-release.yml build job: RELEASE_TAG env + 'Assert --version matches release tag' step (count==1, matrix covers all platforms); dry-run driver now dispatches tag=v1.0.0"
        status: pass
    human_judgment: false

# Metrics
duration: 45min
completed: 2026-08-17
status: complete
---

# Phase 15 Plan 01: Product Versioning & `--version` Summary

**Single-source product version 1.0.0 reported by both release binaries via `--version` (exit 0) with a release-pipeline assertion that the binaries match the tag, plus a recorded semver policy**

## Performance

- **Duration:** ~45 min
- **Tasks:** 2
- **Files:** 8 (+1 policy doc)

## Accomplishments
- `version/version.mbt`: `product_version() == "1.0.0"`, `version_line(name)` and native-only `print_and_exit`; imported by both executables (single source, no second constant)
- `fathom-sql --version` / `fathom-lsp --version` print `fathom-sql 1.0.0` / `fathom-lsp 1.0.0` and exit 0; non-bare `--version` still exits 2 (D-39 preserved)
- `docs/VERSIONING.md`: VER-01 semver policy (first public 1.0.0; `fathom.*.v1` wire-contract stability; breaking changes bump contract version; moon.mod 0.1.0 decoupled)
- Release workflow: build jobs assert the produced binary `--version` contains `RELEASE_TAG` (minus `v`) on every platform and both trigger paths; dry-run driver dispatches `tag=v1.0.0` with `dry_run=true` and checks no Release is created

## Task Commits
1. **Task 1: Single-source version package, both binary entries, and semver policy doc** - `c1c1eb6`
2. **Task 2: Version tests and release-tag consistency assertion** - `0c7494f`

**Plan metadata:** `b214e89` (docs: capture product versioning context)

## Files Created/Modified
- `version/version.mbt` / `version/moon.pkg` - single-source version + native exit helper
- `fathom-sql/run.mbt` (`run_version`), `fathom-sql/main.mbt` (`--version` branch), `fathom-lsp/main.mbt` (`@version.print_and_exit`), both `moon.pkg` imports
- `fathom-sql/cli_test.mbt` - `cli_version_exit_0_exact_output`
- `docs/VERSIONING.md` - semver policy
- `.github/workflows/fathom-native-release.yml` - RELEASE_TAG + assertion step
- `scripts/run_phase14_release_dry_run.py` - tag=v1.0.0 dispatch

## Decisions Made
- Followed plan (D-01..D-07); product/module version decoupling kept per Phase 13

## Deviations from Plan

None - plan executed exactly as written (after incorporating the plan checker's three warnings: moon.pkg imports, all-platform .exe naming in build outputs, single-step matrix assertion count).

## Issues Encountered
- None

## Next Phase Readiness
- Ready for Phase 16 (install guide references `fathom-lsp --version`); Phase 20 formal release uses the asserted tag path

---
*Phase: 15-product-versioning-binary-version*
*Completed: 2026-08-17*
