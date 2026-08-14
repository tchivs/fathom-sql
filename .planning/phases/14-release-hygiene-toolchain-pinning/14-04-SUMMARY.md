---
phase: 14-release-hygiene-toolchain-pinning
plan: 04
subsystem: infra
tags: [github-actions, gitignore, hygiene, jetbrains]

# Dependency graph
requires:
  - phase: 13-toolchain-and-editor-packaging
    provides: JetBrains plugin wrapper workflow baseline
provides:
  - exact three-action JetBrains workflow delta commit
  - repository-wide generated-interface and research-cache ignore policy
affects: 14-05 final readiness classification, release hygiene audit

# Actuals
actuals:
  tokens: 480
  tasks: 2
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Byte-transform proof: parent workflow bytes + exactly three action replacements == committed bytes; single-path commit via diff-tree assertion"
    - "Ignore provenance proof: git check-ignore -v --no-index parsing source/line/pattern, plus handwritten/.omp-* negative cases"

key-files:
  created: []
  modified:
    - .github/workflows/jetbrains-plugin.yml
    - .gitignore

key-decisions:
  - "Executed ahead of TC waves per user-approved 2026-08-14 split: official MoonBit channel lacks darwin-x86_64/static version channel/core checksums, so TC-01/02 freeze is fail-closed blocked; HYG work is file-disjoint and proceeds."
  - "D-14 exact delta proven by byte transform (v4->v7, v4->v5, v4->v7), no other YAML byte changed."

patterns-established:
  - "Hygiene proof pattern: expected-file construction from parent blob, byte equality, then diff-tree single-path assertion"
  - "check-ignore provenance: split record once at TAB, rsplit source:line:pattern, assert exact pattern and pathname"

requirements-completed: [HYG-01, HYG-02, HYG-03]

coverage:
  - id: D1
    description: "JetBrains workflow committed with exactly the D-14 action bumps (checkout@v7, setup-java@v5, upload-artifact@v7) and no other byte change"
    requirement: HYG-01
    verification:
      - kind: other
        ref: "python3 byte proof: git show HEAD^/HEAD .github/workflows/jetbrains-plugin.yml; parent replaced with three exact bumps == commit bytes; git diff-tree --name-only -r HEAD == single path (commit 8cc3f9d)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Repository-wide pkg.generated.mbti ignore and .planning/research/.cache/ ignore with exact provenance"
    requirement: HYG-02
    verification:
      - kind: other
        ref: "git check-ignore -v --no-index probe/pkg.generated.mbti -> .gitignore:15:pkg.generated.mbti; .planning/research/.cache/probe.json -> .gitignore:18:.planning/research/.cache/; negatives probe/handwritten.mbti + .planning/.omp-*.json unignored (commit ff966c1)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Observed generated interface and research cache removed as local untracked hygiene"
    requirement: HYG-03
    verification:
      - kind: other
        ref: "test ! -e fathom-sql/pkg.generated.mbti && test ! -e .planning/research/.cache/ (post ff966c1)"
        status: pass
    human_judgment: false

# Metrics
duration: 12min
completed: 2026-08-14
status: complete
---

# Phase 14 Plan 04: Hygiene Close-out Summary

**JetBrains workflow committed with byte-proven three-action delta (checkout@v7, setup-java@v5, upload-artifact@v7); generated interface and research cache hidden by exact `.gitignore` rules and removed locally**

## Performance

- **Duration:** 12 min
- **Started:** 2026-08-14T07:21:00Z
- **Completed:** 2026-08-14T07:33:43Z
- **Tasks:** 2
- **Files modified:** 2 (plus SUMMARY/STATE/ROADMAP bookkeeping)

## Accomplishments
- Committed `.github/workflows/jetbrains-plugin.yml` as a single-path commit whose bytes equal the parent blob with exactly the three D-14 action replacements (1195 -> 1195 bytes, 3-line delta)
- Added repository basename rule `pkg.generated.mbti` and exact `.planning/research/.cache/` rule to `.gitignore`; provenance proven via `check-ignore -v` (`.gitignore:15` / `.gitignore:18`) with handwritten `.mbti` and all `.omp-*` runtime paths as unignored negatives
- Removed untracked `fathom-sql/pkg.generated.mbti` and `.planning/research/.cache/` as local hygiene (no Git deletion delta, per D-11 classification)
- Executed ahead of TC waves per the user-approved 2026-08-14 split (HYG file-disjoint from toolchain work); quick duplicates, five-file archive, and final readiness classifier remain exclusively owned by 14-05

## Task Commits

1. **Task 1: Prove and commit the exact JetBrains action-only delta** - `8cc3f9d` (ci: bump JetBrains actions to checkout@v7, setup-java@v5, upload-artifact@v7)
2. **Task 2: Enforce exact generated-interface and research-cache hygiene** - `ff966c1` (chore: ignore generated MoonBit interfaces and research cache)

**Plan metadata:** `001edd6` (docs: create phase plan)

## Files Created/Modified
- `.github/workflows/jetbrains-plugin.yml` - only delta: three action version bumps, proven byte-identical to parent transform
- `.gitignore` - `pkg.generated.mbti` basename rule + `.planning/research/.cache/` rule

## Decisions Made
- Followed plan as specified (D-14 byte proof, D-10/D-11 exact rules, D-13 path-specific commits); only orchestration-level split decision is recorded in STATE/ROADMAP

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- None (toolchain freeze blocker documented at phase level, not this plan)

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Ready for 14-05 (quick duplicate deletion, five-file archive commit, final porcelain classifier/readiness matrix)
- TC waves 14-01..14-03 remain fail-closed blocked on official MoonBit channel evidence (see ROADMAP note)

---
*Phase: 14-release-hygiene-toolchain-pinning*
*Completed: 2026-08-14*
