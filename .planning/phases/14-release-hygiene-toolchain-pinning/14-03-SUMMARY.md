---
phase: 14-release-hygiene-toolchain-pinning
plan: 03
subsystem: infra
tags: [release, gates, evidence, github-actions, moonbit]

# Dependency graph
requires:
  - phase: 14-release-hygiene-toolchain-pinning
    provides: 14-01 lock + 14-02 shared installers
provides:
  - three-platform release DAG with per-platform evidence and fail-closed aggregation
  - pre-merge dry-run proof of the full qualification matrix
affects: 14-05 readiness matrix, Phase 20 formal release

# Actuals
actuals:
  tokens: 4200
  tasks: 2
  commits: 10

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Release DAG: build (evidence) + release-gates (nine commands once) -> release (needs both, validate, aggregate, publish)"
    - "Pre-merge dry-run: same-path legacy registration mapping, numeric-ID dispatch, content-step identity binding, artifact/evidence validation, publication absence, ref cleanup"

key-files:
  created:
    - scripts/validate_toolchain_evidence.py
    - scripts/tests/test_validate_toolchain_evidence.py
    - scripts/tests/fixtures/toolchain-evidence/
    - scripts/run_phase14_release_dry_run.py
  modified:
    - .github/workflows/fathom-native-release.yml

key-decisions:
  - "release job explicitly needs [build, release-gates]; contents:write only there; dry_run input skips only the final GitHub Release steps"

patterns-established:
  - "Fail-closed aggregation: exact three-record set + requested/reported/lock identity + per-record digests before any manifest/upload"

requirements-completed: [TC-01, TC-02]

coverage:
  - id: D1
    description: "Three-platform release workflow: lock-driven installers, per-platform moon-toolchain.json evidence beside binaries, independent nine-command release-gates, publication needs both"
    requirement: TC-02
    verification:
      - kind: other
        ref: "pre-merge dry-run run 31995140506: 5/5 jobs success; nine gate steps (Native/JavaScript/linear-Wasm parity, compare_backends, diff_parity, check_naming, verify_corpus, corpus report, keywords) all success; publication absent for phase14-dry-run"
        status: pass
    human_judgment: false
  - id: D2
    description: "Fail-closed aggregate evidence validator with deterministic fixtures"
    requirement: TC-01
    verification:
      - kind: unit
        ref: "scripts/tests/test_validate_toolchain_evidence.py: valid aggregate + 7 defect cases (missing/duplicate/unknown/malformed/requested/reported/digest mismatch) all fail closed"
        status: pass
    human_judgment: false
  - id: D3
    description: "Dry-run driver proves exact proposed workflow bytes at legacy registration path, identity via content steps, real artifact download and aggregate validation, no GitHub Release, ref cleanup"
    requirement: TC-01
    verification:
      - kind: other
        ref: "scripts/run_phase14_release_dry_run.py run 31995140506 -> DRYRUN-PASS; temp branch phase14-release-dry-run-20260817123735-d01de194 deleted"
        status: pass
    human_judgment: false

# Metrics
duration: 90min
completed: 2026-08-17
status: complete
---

# Phase 14 Plan 03: Release Gates and Evidence Summary

**Three-platform release DAG with per-platform toolchain evidence, independent nine-command qualification job, and a pre-merge dry-run proving the full matrix end-to-end without publishing**

## Performance

- **Duration:** ~90 min (multi-round dry-run debugging)
- **Tasks:** 2
- **Files:** 5 created/modified (+ fixtures)

## Accomplishments
- `fathom-native-release.yml`: 3-platform matrix uses the shared lock-driven installers and writes `dist/moon-toolchain.json` beside each binary; independent Ubuntu `release-gates` job runs the exact nine commands once (named steps); `release` job requires `[build, release-gates]`, validates evidence before any manifest/upload, writes aggregate `moon-toolchain-manifest.json`, `contents:write` only there, `dry_run` input skips only the final Release steps
- `validate_toolchain_evidence.py`: exact three-record set, requested/reported/lock identity, binary/core digest + URL binding; 1 valid + 7 defect fixtures; all fail closed with no output
- Dry-run driver: same-path mapping of proposed bytes onto the registered legacy workflow (ID 328270211), numeric-ID dispatch with tag+dry_run, content-step identity binding, real artifact download, aggregate validation against the committed lock, publication absence proof, temp branch deletion
- Real run 31995140506: 5/5 jobs success; nine gate steps success; evidence aggregated; no Release created

## Task Commits
1. **Task 1: Wire verified three-platform evidence and one complete release-gates job** - `cf286ba` (+driver fixes `9234c09`/`4296f76`/`2e8faa61`)
2. **Task 2: Behavior-test aggregate evidence and harden publication prerequisites** - `dcc8942` (+validator naming fix)

## Files Created/Modified
- `.github/workflows/fathom-native-release.yml` - release DAG
- `scripts/validate_toolchain_evidence.py` + tests + fixtures - fail-closed aggregation
- `scripts/run_phase14_release_dry_run.py` - pre-merge live proof driver

## Decisions Made
- Followed plan (three-platform revision); dry-run identity bound by executed content steps (registration name stays legacy until default-branch cutover)

## Deviations from Plan

### Auto-fixed Issues
1. **[Rule 1 - Blocking] installers skipped core bundle** - added `moon -C lib/core bundle --all/--wasm-gc` before PATH publication (moon check/build requires bundled stdlib)
2. **[Rule 1] release job had no checkout** - added actions/checkout@v7 for the validator
3. **[Rule 1] observer targetPlatform used archive naming (darwin-aarch64)** - mapped to runner naming (macos-aarch64)
4. **[Rule 1] validator lock lookup naming/URL** - archive-name binary lookup + per-record coreUrl matching
5. **[Rule 1] manifest/upload paths for non-merged artifact dirs** - subdir paths
6. **[Rule 1] workflowName check too strict** - content-step identity binding (registered name is legacy until cutover)

**Total deviations:** 6 auto-fixed (all blocking/mechanism)
**Impact:** required for the real dry-run; no scope change.

## Issues Encountered
- 6 dry-run rounds diagnosed via job logs; each fixed and re-proven in a fresh run

## Next Phase Readiness
- Release DAG proven end-to-end (dry-run); Phase 20 owns the formal v1.0.0 tag/Release; default-branch cutover will register the new Fathom path and drop the legacy path

---
*Phase: 14-release-hygiene-toolchain-pinning*
*Completed: 2026-08-17*
