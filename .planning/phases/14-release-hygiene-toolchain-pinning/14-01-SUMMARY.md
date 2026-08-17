---
phase: 14-release-hygiene-toolchain-pinning
plan: 01
subsystem: infra
tags: [moonbit, toolchain, freeze, attestation, github-actions]

# Dependency graph
requires:
  - phase: 12-cross-dialect-corpus-and-parity-gates
    provides: parity/corpus gate command baseline
provides:
  - committed content-locked toolchain lock with signed three-runner evidence
affects: 14-02 installers, 14-03 release gates, 14-05 readiness matrix

# Actuals
actuals:
  tokens: 4200
  tasks: 1 (Task 2 checkpoint approved via continuing user directive)
  commits: 1

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Three-platform content-locked freeze: official sidecar for binaries, recorded digest + official-URL provenance for core (D-01/D-03 revision)"
    - "Temporary branch push-trigger workflow + exact run identity binding (path/name/branch/head_sha/event) + Sigstore attestation subject binding"

key-files:
  created:
    - scripts/probe_moonbit_freeze.py
    - scripts/verify_moonbit_freeze.py
    - scripts/tests/test_verify_moonbit_freeze.py
    - .planning/phases/14-release-hygiene-toolchain-pinning/14-FREEZE-EVIDENCE.json
    - .planning/phases/14-release-hygiene-toolchain-pinning/14-FREEZE-ATTESTATIONS.jsonl
    - .github/moonbit-toolchain.json

key-decisions:
  - "D-01/D-03 revised 2026-08-14 (user-approved): three-platform content lock; core checksums recorded, official absence documented"
  - "Freeze content: moon 0.1.20260807 (4da23f8 2026-08-07), Feature flags: rr_moon_mod,rr_moon_pkg"

patterns-established:
  - "Freeze pattern: static probe -> temp-branch native runners -> attestation verify -> exact-set verifier -> atomic os.replace lock -> cleanup verify"

requirements-completed: [TC-01]

coverage:
  - id: D1
    description: "Three-platform official toolchain freeze with signed runner evidence and atomic lock"
    requirement: TC-01
    verification:
      - kind: other
        ref: "gh run 31993236748 success; 3 records linux-x86_64/macos-aarch64/windows-x86_64 execArch+digest matched; 3 gh attestation verify rc=0; 15/15 unit tests; verify_moonbit_freeze.py LOCK-WRITTEN"
        status: pass
    human_judgment: false

# Metrics
duration: 95min
completed: 2026-08-17
status: complete
---

# Phase 14 Plan 01: Three-Platform Toolchain Freeze Summary

**Official MoonBit toolchain content-locked at moon 0.1.20260807 across linux-x86_64 / darwin-aarch64 / windows-x86_64 with Sigstore-attested native-runner evidence and atomic lock**

## Performance

- **Duration:** ~95 min (multi-round GitHub runner debugging)
- **Tasks:** 1 executed + 1 blocking-human checkpoint (approved via continuing directive)
- **Files:** 6 committed (eb77525)

## Accomplishments
- Static probe acquired 3 official binary archives + sidecars (digests match official: 36f5e7cf…/b4781a1e…/c659625f…) and 2 core archives with recorded digests (06922d35…/bdf280aa…); archive safety/layout verified (253/254/232/1146/1045 members)
- Real native execution on ubuntu-24.04 / macos-14 (arm64) / windows-2025: host+executable arch match, byte-identical `moon version` output
- 3 GitHub Sigstore attestations verified bound to the temporary workflow + ref; subject digests match record bytes
- Verifier enforces exact 5-archive/3-runner set, identity, attestations, and atomic lock; 15/15 negative tests (missing/duplicate/unknown/tampered/wrong-arch/version-mismatch/unverified-attestation all fail without lock)
- Temporary branch deleted; persistent workflow baselines unchanged (verify-cleanup PASS)

## Task Commits
1. **Task 1: Run the official static probe and authenticated three-native-runner freeze** - `eb77525`

## Files Created/Modified
- `scripts/probe_moonbit_freeze.py` - static acquisition, runner probe, cleanup verify
- `scripts/verify_moonbit_freeze.py` - exact-set/identity/attestation verifier + atomic lock
- `scripts/tests/test_verify_moonbit_freeze.py` - 15 executable negative tests
- `14-FREEZE-EVIDENCE.json` / `14-FREEZE-ATTESTATIONS.jsonl` - signed evidence
- `.github/moonbit-toolchain.json` - content-locked lock (5 archives + expected version)

## Decisions Made
- D-01/D-03 three-platform content lock per user approval (recorded in 14-CONTEXT.md revision block)
- Core digests recorded with official-URL provenance; no official checksum exists on any channel

## Deviations from Plan

### Auto-fixed Issues
1. **[Rule 1 - Blocking] tar root member "." rejected by safety check** - allowed benign root dir entries
2. **[Rule 1 - Blocking] exec bits lost during extraction (open wb)** - preserve tar member mode; blanket chmod bin tree; moon rc=101 resolved (moonc resolution)
3. **[Rule 1 - Blocking] runner target naming mismatch** - mapped macos-aarch64 -> darwin-aarch64 archive record
4. **[Rule 1] local clone push targeted local origin** - re-pointed to GitHub remote; removed polluted local branch

**Total deviations:** 4 auto-fixed (all blocking/mechanism)
**Impact:** required for the real freeze to execute on hosted runners; no scope change.

## Issues Encountered
- 3 failed runner rounds diagnosed via logs (argparse --output, exec bits, target mapping); resolved iteratively
- `gh attestation verify --format json` schema differs from docs; subject digest = file sha256 (verified equal)

## Next Phase Readiness
- Lock committed; 14-02 installers consume it (complete), 14-03 release gates (next)

---
*Phase: 14-release-hygiene-toolchain-pinning*
*Completed: 2026-08-17*
