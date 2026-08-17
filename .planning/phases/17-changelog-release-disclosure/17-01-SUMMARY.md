---
phase: 17-changelog-release-disclosure
plan: 01
subsystem: docs
tags: [changelog, release-notes, disclosure]

# Dependency graph
requires:
  - phase: 14-release-hygiene-toolchain-pinning
    provides: toolchain/content-lock facts for the disclosure
  - phase: 15-product-versioning-binary-version
    provides: product version policy for VERSIONING references
provides:
  - CHANGELOG.md 1.0.0 entry
  - RELEASE-NOTES.md boundary disclosure
  - release workflow notes-file wiring
affects: 20 formal release (notes content)

# Actuals
actuals:
  tokens: 900
  tasks: 2
  commits: 1

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Release notes as disclosure: gh release create --notes-file RELEASE-NOTES.md"

key-files:
  created:
    - CHANGELOG.md
    - RELEASE-NOTES.md
  modified:
    - .github/workflows/fathom-native-release.yml

key-decisions:
  - "Release notes present the disclosure document itself so boundaries are visible before download"

patterns-established:
  - "Consumer-boundary honesty: every known limitation is disclosed in RELEASE-NOTES.md"

requirements-completed: [VER-03, DIS-01, DIS-02]

coverage:
  - id: D1
    description: "CHANGELOG.md 1.0.0 entry covering user-visible changes since v0.1.0 (CST core, Doris profiles, CLI, dialect abstraction, wire contracts, three-platform assets, --version)"
    requirement: VER-03
    verification:
      - kind: other
        ref: "assert '## [1.0.0]' in CHANGELOG.md; content sections Added/Changed/Fixed covering all named capabilities"
        status: pass
    human_judgment: false
  - id: D2
    description: "RELEASE-NOTES.md with the five boundary disclosures (Flink syntax-level, Wasm GC, corpus gaps, 5 overrides, toolchain policy)"
    requirement: DIS-01
    verification:
      - kind: other
        ref: "assert all five keywords present (Flink/Wasm GC/unavailable-offline/verification overrides/0.1.20260807/Intel)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Release workflow uses --notes-file RELEASE-NOTES.md instead of --generate-notes"
    requirement: DIS-02
    verification:
      - kind: other
        ref: "assert --notes-file RELEASE-NOTES.md in workflow and --generate-notes absent"
        status: pass
    human_judgment: false

# Metrics
duration: 25min
completed: 2026-08-17
status: complete
---

# Phase 17 Plan 01: Changelog & Release Disclosure Summary

**CHANGELOG 1.0.0 entry and a five-boundary release disclosure committed; the release pipeline now publishes the disclosure as the Release notes**

## Performance

- **Duration:** ~25 min
- **Tasks:** 2
- **Files:** 3 committed

## Accomplishments
- `CHANGELOG.md`: Keep-a-Changelog-style `## [1.0.0]` entry covering user-visible changes since the v0.1.0 baseline (lossless CST, Doris profiles + strict/editor modes, FATHOM-* diagnostics, formatting, CLI subcommands, multi-dialect abstraction with syntax-level Flink, catalog analysis, fathom.*.v1 contracts, JS/linear-Wasm facades, three-platform release assets, `--version`, install guide), with Added/Changed/Fixed sections
- `RELEASE-NOTES.md`: honest five-boundary disclosure (Flink syntax-level only; Wasm GC not first-class; corpus `unavailable-offline` gaps with no fabricated hashes; 5 documented verification overrides; toolchain content-lock policy incl. macOS Intel non-target and product/module version decoupling) with a "read before downloading assets" lead
- Release workflow: `gh release create --notes-file RELEASE-NOTES.md` replaces `--generate-notes`, so published Release notes present the disclosure before download

## Task Commits
1. **Task 1: CHANGELOG 1.0.0 entry and release disclosure document** - included
2. **Task 2: Release notes wiring and executable verification** - included

## Files Created/Modified
- `CHANGELOG.md` / `RELEASE-NOTES.md` - new
- `.github/workflows/fathom-native-release.yml` - notes-file wiring

## Decisions Made
- Followed plan (D-01..D-04)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- None

## Next Phase Readiness
- Phase 20 formal release will publish notes from RELEASE-NOTES.md; Phases 18–19 (npm/editor publication) proceed independently

---
*Phase: 17-changelog-release-disclosure*
*Completed: 2026-08-17*
