---
phase: 20-formal-1-0-0-release-verification
plan: 01
subsystem: release
tags: [release, tag, verification, smoke]

# Dependency graph
requires:
  - phase: 14-release-hygiene-toolchain-pinning
    provides: three-platform release pipeline and content lock
  - phase: 15-product-versioning-binary-version
    provides: --version 1.0.0 contract
  - phase: 17-changelog-release-disclosure
    provides: RELEASE-NOTES.md disclosure wiring
provides:
  - v1.0.0 GitHub Release (assets + manifests + disclosure notes)
  - post-release smoke evidence
affects: milestone v4.0 completion

# Actuals
actuals:
  tokens: 2400
  tasks: 2
  commits: 6 (incl. refreeze + naming fix)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Content-lock drift handling: latest moved -> installer failed closed as designed -> re-freeze (3 attested runners) -> new lock -> re-tag"

key-files:
  created:
    - .planning/phases/20-formal-1-0-0-release-verification/20-FREEZE-EVIDENCE.json
    - .planning/phases/20-formal-1-0-0-release-verification/20-FREEZE-ATTESTATIONS.jsonl
  modified:
    - .github/moonbit-toolchain.json (re-frozen to moon 0.1.20260819)
    - README.md, README.zh-CN.md, docs/GETTING-STARTED.md, docs/zh-CN/GETTING-STARTED.md, CHANGELOG.md, RELEASE-NOTES.md (toolchain version sync)
    - npm/smoke/smoke.mjs (naming-gate identifiers)
    - .github/workflows/vsce-publish.yml (idempotency)

key-decisions:
  - "v1.0.0 tagged at the release commit; three-platform assets per the D-01/D-03 revision"
  - "npm publish blocked on token bypass-2FA (E403) — user action; everything else shipped"

patterns-established:
  - "Release = tag -> pipelines -> manifest SHA-256 smoke against the live asset"

requirements-completed: [VER-04]

coverage:
  - id: D1
    description: "v1.0.0 tag triggers fathom-native-release: 3 platform builds + nine-command release-gates + release job with dual manifests and disclosure notes"
    requirement: VER-04
    verification:
      - kind: other
        ref: "gh run 32343439589 success (5/5 jobs); gh release view v1.0.0 assets = fathom-lsp-{linux-x86_64,macos-aarch64,windows-x86_64.exe} + fathom-lsp-manifest.json + moon-toolchain-manifest.json; body = RELEASE-NOTES.md disclosure"
        status: pass
    human_judgment: false
  - id: D2
    description: "Post-release smoke: downloaded linux asset, SHA-256 matches manifest, runs and reports fathom-lsp 1.0.0"
    requirement: VER-04
    verification:
      - kind: other
        ref: "SHA-256 OK 06b642a6...; SMOKE PASS: fathom-lsp --version = fathom-lsp 1.0.0 (exit 0)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Drift handling: official latest moved (0.1.20260807 -> 0.1.20260819); lock failed closed; re-freeze with 3 attested runners; docs synced"
    requirement: VER-04
    verification:
      - kind: other
        ref: "re-freeze run 32343037561 success (3 runners, attestations OK); new lock expectedMoonVersion moon 0.1.20260819 (fc2a4ee); check_naming green (705 files)"
        status: pass
    human_judgment: false
  - id: D4
    description: "npm @fathom/sql@1.0.0 publication blocked on token bypass-2FA (E403); vsce fathom-sql.sql 1.0.0 already live"
    requirement: VER-04
    verification:
      - kind: other
        ref: "npm view @fathom/sql@1.0.0 -> E404 (not published; tag run E403 bypass-2FA); marketplace gallery confirms fathom-sql.sql 1.0.0"
        status: pass
    human_judgment: true
    rationale: "npm registry push requires the user to regenerate NPM_TOKEN with bypass-2FA; the release itself is complete"

# Metrics
duration: 3h (incl. drift re-freeze rounds)
completed: 2026-08-20
status: complete
---

# Phase 20 Plan 01: Formal 1.0.0 Release & Verification Summary

**v1.0.0 tagged and released: three-platform assets + SHA-256 manifests + disclosure notes live on GitHub, post-release smoke passes (fathom-lsp --version 1.0.0); npm publication blocked on a token 2FA setting; toolchain re-frozen after official drift**

## Performance

- **Duration:** ~3h (two drift-driven re-freeze rounds)
- **Tasks:** 2
- **Commits:** 6 (refreeze + naming fix + idempotency + close-out)

## Accomplishments
- `v1.0.0` annotated tag on master; `fathom-native-release` run 32343439589 **success** — 3 builds (linux-x86_64/macos-aarch64/windows-x86_64) with per-platform toolchain evidence, nine-command release-gates, release job writing `fathom-lsp-manifest.json` + `moon-toolchain-manifest.json` and creating the GitHub Release with `RELEASE-NOTES.md` as the body (disclosure visible before download)
- Release assets verified: `fathom-lsp-linux-x86_64`, `fathom-lsp-macos-aarch64`, `fathom-lsp-windows-x86_64.exe` + both manifests
- **Post-release smoke PASS**: downloaded the linux asset, SHA-256 matched the manifest (`06b642a6...`), executed it — `fathom-lsp --version` printed `fathom-lsp 1.0.0` (exit 0)
- **Drift handling (designed fail-closed)**: official `latest` moved between the 2026-08-17 freeze and the release (sidecars changed: `36f5e7cf→0e81deb3`, `b4781a1e→4197777e`, `c659625f→a4c9af8b`); the lock-driven installer refused the mismatch as designed; re-froze against the new `latest` (`moon 0.1.20260819 (fc2a4ee)`) with 3 attested runners (run 32343037561) and synced all docs
- **Naming gate caught a regression**: `npm/smoke/smoke.mjs` `doris.profiles` tripped the `doris\.profile` legacy-key rule — renamed identifiers, gate green (705 files)
- `vsce-publish.yml` made idempotent; `fathom-sql.sql` 1.0.0 confirmed live on the VS Code Marketplace (published in Phase 19)

## Task Commits
1. **Task 1: vsce idempotency and v1.0.0 tag creation** - included
2. **Task 2: Release verification and post-release smoke** - included
Plus: refreeze commit, doc version sync, naming fix, idempotency.

## Files Created/Modified
- `20-FREEZE-EVIDENCE.json` / `20-FREEZE-ATTESTATIONS.jsonl` - re-freeze evidence
- `.github/moonbit-toolchain.json` - re-frozen lock (0.1.20260819)
- 6 docs - toolchain version sync
- `npm/smoke/smoke.mjs` - naming-gate identifiers
- `.github/workflows/vsce-publish.yml` - idempotency

## Decisions Made
- Followed plan (D-01..D-05); re-freeze was the mandated response to content-lock drift (D-01/D-03)

## Deviations from Plan

### Auto-fixed Issues
1. **[Rule 1 - Blocking] toolchain drift** - latest advanced upstream; re-froze to 0.1.20260819 with full attestation pipeline; old frozen bytes no longer obtainable (moving alias)
2. **[Rule 1 - Blocking] naming gate on npm smoke** - `doris.profiles` renamed
3. **[Rule 1] vsce tag runs reported head_branch=master (GitHub quirk)** - no action needed; idempotent skip added

**Total deviations:** 3 auto-fixed
**Impact:** required for a real, honest release; the drift re-freeze is the documented cost of content-locking a moving alias.

## Issues Encountered
- npm publish E403: the configured `NPM_TOKEN` lacks bypass-2FA for the `@fathom` scope — **user action required** (regenerate a granular token with "Bypass 2FA for packages in this scope" enabled, or disable 2FA on the publish token); once provided, the tag-triggered `npm-publish.yml` publishes `@fathom/sql@1.0.0` automatically (or via dispatch)

## Next Phase Readiness
- Milestone v4.0 (Release Readiness) complete: 7/7 phases; VS Code extension live, GitHub Release live, npm pending token fix, Open VSX pending OVSX_TOKEN

---
*Phase: 20-formal-1-0-0-release-verification*
*Completed: 2026-08-20*
