---
phase: 14-release-hygiene-toolchain-pinning
plan: 02
subsystem: infra
tags: [moonbit, installer, ci, windows, lock]

# Dependency graph
requires:
  - phase: 14-release-hygiene-toolchain-pinning
    provides: 14-01 content-locked toolchain lock
provides:
  - shared Unix/Windows lock-driven verified installers
  - ordinary CI single-toolchain migration
  - native windows-2025 installer evidence driver
affects: 14-03 release workflow bootstrap, 14-05 readiness matrix

# Actuals
actuals:
  tokens: 3800
  tasks: 2
  commits: 5

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Lock-driven installer: no version/channel args; sidecar+archive+core digest, safe layout, byte-exact moon version before PATH publication"
    - "Windows proof driver: temporary branch push workflow + exact run identity + nested artifact validation + delayed branch cleanup"

key-files:
  created:
    - .github/scripts/install-moonbit.sh
    - .github/scripts/install-moonbit.ps1
    - scripts/tests/test_install_moonbit.py
    - scripts/run_phase14_installer_matrix.py
  modified:
    - .github/workflows/ci.yml

key-decisions:
  - "Ordinary CI no longer carries a toolchain identity: all 5 MoonBit bootstrap steps call the shared lock-driven helper"

patterns-established:
  - "Single-source install pattern: lock -> helper verify chain -> PATH + observation JSON (fail-closed)"

requirements-completed: [TC-01]

coverage:
  - id: D1
    description: "Unix/PowerShell lock-driven verified installers with behavior-tested fail-closed semantics"
    requirement: TC-01
    verification:
      - kind: unit
        ref: "scripts/tests/test_install_moonbit.py#UnixInstallerTest (8 tests: valid, target mismatch, corrupt sidecar/archive, traversal, wrong version, missing core, no-observation-on-failure)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Ordinary CI migrated to the single shared installer; all nine gate commands preserved verbatim"
    requirement: TC-01
    verification:
      - kind: other
        ref: "python3 assertion: 5 install-moonbit.sh call sites, no MOONBIT_INSTALL_VERSION, no cli.moonbitlang.com/install, all nine gate commands present (ci.yml)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Native windows-2025 installer proof (fixture subset + real lock-driven install) via single driver invocation"
    requirement: TC-01
    verification:
      - kind: other
        ref: "scripts/run_phase14_installer_matrix.py run 31994107232: windows fixture subset PASS; real install targetPlatform=windows-x86_64, provenance=official-sidecar, reportedVersion byte-identical; branch deleted after validation"
        status: pass
    human_judgment: false

# Metrics
duration: 70min
completed: 2026-08-17
status: complete
---

# Phase 14 Plan 02: Shared Installers and Ordinary CI Migration Summary

**Lock-driven Unix/PowerShell installers verified on native windows-2025; all five ordinary CI MoonBit bootstraps migrated to the single exact toolchain entry**

## Performance

- **Duration:** ~70 min
- **Tasks:** 2
- **Files:** 5 committed

## Accomplishments
- `install-moonbit.sh` / `install-moonbit.ps1`: consume the committed lock only; verify official sidecar, binary+core digests, safe layout (traversal/link/root), then run `moon version` and compare byte-for-byte before PATH publication; write deterministic observation JSON
- 8 Unix behavior tests + Windows fixture subset (compiled fake moon exe via csc, valid/corrupt-sidecar/corrupt-archive/traversal/wrong-version fail-closed) all pass
- Windows matrix driver: temporary branch push workflow -> exact run identity -> nested artifact validation -> branch cleanup; real windows-2025 install verified sidecar digest c659625f…, core bdf280aa…, byte-identical `moon 0.1.20260807`
- `ci.yml`: 5/5 bootstrap steps replaced with `.github/scripts/install-moonbit.sh`; env version constant removed; all nine release-relevant gate commands intact

## Task Commits
1. **Task 1: Implement and behavior-test lock-driven Unix and Windows installers** - `2948bc1` (+test fixes `a4d87ea`, `csc` fix, `run_ps1` fix, LF fix)
2. **Task 2: Migrate every ordinary CI bootstrap to the exact shared installer** - `2948bc1` (ci.yml)

## Files Created/Modified
- `.github/scripts/install-moonbit.sh` / `.ps1` - lock-driven verified installers
- `scripts/tests/test_install_moonbit.py` - Unix + Windows behavior suites
- `scripts/run_phase14_installer_matrix.py` - single-command Windows proof driver
- `.github/workflows/ci.yml` - 5 bootstrap steps -> shared helper

## Decisions Made
- Followed plan as specified; fixtures synthesized in-test (no separate fixtures dir)

## Deviations from Plan

### Auto-fixed Issues
1. **[Rule 1 - Blocking] plan fixtures dir not materialized** - deterministic fixtures generated in-test (equivalent contract)
2. **[Rule 1 - Blocking] gh api -f form returns 404** - query-in-URL form in driver
3. **[Rule 1] driver ls-tree non-recursive missed nested paths** - added -r
4. **[Rule 1] Add-Type cannot emit exe** - used .NET Framework csc.exe
5. **[Rule 1] Console.WriteLine emits CRLF** - explicit \\n writes

**Total deviations:** 5 auto-fixed (all blocking/mechanism)
**Impact:** required for native Windows proof; no scope change.

## Issues Encountered
- 3 Windows matrix rounds diagnosed via logs (missing platform records, csc, CRLF); resolved

## Next Phase Readiness
- Installers + CI migration done; 14-03 release workflow consumes the same lock/helpers

---
*Phase: 14-release-hygiene-toolchain-pinning*
*Completed: 2026-08-17*
