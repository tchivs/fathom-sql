---
phase: 16-documentation-truthfulness-install-guide
plan: 01
subsystem: docs
tags: [readme, install-guide, license, documentation]

# Dependency graph
requires:
  - phase: 15-product-versioning-binary-version
    provides: fathom-lsp --version 1.0.0 contract used by the install guide
provides:
  - truthful README/GETTING-STARTED (en+zh)
  - install-from-Release guide and regenerated doc-verification records
affects: 17 changelog/disclosure, 20 post-release smoke

# Actuals
actuals:
  tokens: 1400
  tasks: 2
  commits: 1

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Doc truthfulness gate: executable python claim assertions + regenerated verify-*.json records (claims_failed=0)"

key-files:
  created: []
  modified:
    - README.md, README.zh-CN.md
    - docs/GETTING-STARTED.md, docs/zh-CN/GETTING-STARTED.md
    - .planning/tmp/verify-README.md.json, .planning/tmp/verify-GETTING-STARTED.md.json

key-decisions:
  - "Toolchain references in user docs now cite the Phase-14 content lock (moon 0.1.20260807 via .github/moonbit-toolchain.json)"
  - "Install guide documents the real release assets and manifest SHA-256 verification"

patterns-established:
  - "Verification records are regenerated per doc change and must show claims_failed=0"

requirements-completed: [DOC-01, DOC-02]

coverage:
  - id: D1
    description: "README/GETTING-STARTED (en+zh) stale and false claims fixed: LICENSE linked as Apache-2.0, no 0.1.20260724 references, no <repository-url> placeholder, real remote"
    requirement: DOC-01
    verification:
      - kind: other
        ref: "python assertions: 4 docs free of 0.1.20260724; en+zh README license section Apache-2.0 with LICENSE link; GETTING-STARTED real clone URL + pinned toolchain"
        status: pass
    human_judgment: false
  - id: D2
    description: "Install `fathom-lsp` from GitHub Release guide: per-platform assets, manifest SHA-256 verification, ~/.fathom/bin install, --version check"
    requirement: DOC-02
    verification:
      - kind: other
        ref: "python assertions: en+zh README contain asset table (3 platforms), fathom-lsp-manifest.json sha256 check, ~/.fathom/bin, fathom-lsp --version -> fathom-lsp 1.0.0"
        status: pass
    human_judgment: false
  - id: D3
    description: "Regenerated verify-README.md.json / verify-GETTING-STARTED.md.json with claims_failed=0"
    requirement: DOC-01
    verification:
      - kind: other
        ref: "json assertions: claims_passed == claims_checked > 0, claims_failed == 0"
        status: pass
    human_judgment: false

# Metrics
duration: 30min
completed: 2026-08-17
status: complete
---

# Phase 16 Plan 01: Documentation Truthfulness & Install Guide Summary

**README and GETTING-STARTED (en+zh) freed of false LICENSE claims, stale toolchain references and placeholders; a complete install-from-GitHub-Release guide with SHA-256 verification added; doc-verification records regenerated green**

## Performance

- **Duration:** ~30 min
- **Tasks:** 2
- **Files:** 6 committed

## Accomplishments
- Removed the false "no LICENSE file / to be confirmed" claim; README (en+zh) now declares Apache-2.0 with a `LICENSE` link
- Replaced all `moon 0.1.20260724` references and badges with the Phase-14 content lock (`moon 0.1.20260807` via `.github/moonbit-toolchain.json`)
- Removed the `<repository-url>` placeholder and the "no verifiable remote" sentence; GETTING-STARTED (en+zh) uses `git clone https://github.com/tchivs/fathom-sql.git`
- Added "Install `fathom-lsp` from GitHub Release" (en+zh): three-platform asset table, `fathom-lsp-manifest.json` SHA-256 verification snippet, `~/.fathom/bin` install with PATH, `fathom-lsp --version` → `fathom-lsp 1.0.0`
- Regenerated `.planning/tmp/verify-README.md.json` (7 claims) and `verify-GETTING-STARTED.md.json` (5 claims), all passed; docs-work-manifest unchanged

## Task Commits
1. **Task 1: Fix stale and false documentation claims (en+zh)** - included in this commit
2. **Task 2: Install-from-Release section and regenerated verification records** - included in this commit

## Files Created/Modified
- `README.md` / `README.zh-CN.md` - truthfulness fixes + install guide
- `docs/GETTING-STARTED.md` / `docs/zh-CN/GETTING-STARTED.md` - real remote, pinned toolchain, install pointer
- `.planning/tmp/verify-README.md.json` / `verify-GETTING-STARTED.md.json` - regenerated claim records

## Decisions Made
- Followed plan (D-01..D-06)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- None

## Next Phase Readiness
- Ready for Phase 17 (CHANGELOG + release disclosure); Phase 20 post-release smoke follows the new install guide

---
*Phase: 16-documentation-truthfulness-install-guide*
*Completed: 2026-08-17*
