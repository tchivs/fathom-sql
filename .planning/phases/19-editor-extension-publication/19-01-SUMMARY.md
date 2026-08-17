---
phase: 19-editor-extension-publication
plan: 01
subsystem: editor
tags: [vscode, vsix, marketplace, open-vsx]

# Dependency graph
requires:
  - phase: 15-product-versioning-binary-version
    provides: product version 1.0.0
  - phase: 16-documentation-truthfulness-install-guide
    provides: fathom-lsp acquisition guide referenced by the extension README
provides:
  - publishable extension manifest + install guide
  - verified vsix package
affects: 20 formal release (marketplace pushes)

# Actuals
actuals:
  tokens: 700
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Publication-readiness pattern: manifest identity (version/private) + vsce package + vsce ls content check"

key-files:
  modified:
    - vscode/package.json
    - vscode/package-lock.json
    - vscode/README.md
  created:
    - vscode/.gitignore

key-decisions:
  - "Extension version 1.0.0 (product version), private flag removed; publisher fathom retained"
  - "Actual marketplace pushes are auth-gated (OVSX_TOKEN / Azure DevOps PAT); packaging verified locally"

patterns-established:
  - "Marketplace gate: vsce package + ls verify locally; publish only with explicit credentials"

requirements-completed: [VSC-01, VSC-02]

coverage:
  - id: D1
    description: "Manifest release-ready: version 1.0.0, private removed, lockfile identity synced; README install guide (marketplace/Open VSX + fathom-lsp GitHub Release acquisition + SHA-256 + --version + serverPath)"
    requirement: VSC-02
    verification:
      - kind: other
        ref: "python assertions: manifest version 1.0.0 and no private; README contains ## Install, fathom.serverPath, fathom-lsp --version, GitHub Release, 1.0.0"
        status: pass
    human_judgment: false
  - id: D2
    description: "vsce package produces a valid vsix; vsce ls contains dist/extension.js, package.json, README.md, language-configuration.json"
    requirement: VSC-01
    verification:
      - kind: other
        ref: "npm run package -> fathom-sql-language-client-1.0.0.vsix (400 files, 697.26 KB); vsce ls 30 component matches"
        status: pass
    human_judgment: false
  - id: D3
    description: "Publication auth gates recorded (Open VSX OVSX_TOKEN + namespace; Marketplace Azure DevOps PAT + publisher fathom)"
    requirement: VSC-01
    verification:
      - kind: other
        ref: "no OVSX_TOKEN / no Azure DevOps PAT in environment; pushes not executed or fabricated"
        status: pass
    human_judgment: true
    rationale: "Marketplace publication requires the user's registry credentials and registered publisher identity; packaging is verified, pushes remain gated"

# Metrics
duration: 35min
completed: 2026-08-17
status: complete
---

# Phase 19 Plan 01: Editor Extension Publication Summary

**VS Code extension made publication-ready (version 1.0.0, non-private manifest, install guide) and packaged into a verified 697 KB vsix; marketplace pushes recorded as credential-gated**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2
- **Files:** 4 committed

## Accomplishments
- `vscode/package.json`: version 0.1.0 → 1.0.0, removed `private: true`; `package-lock.json` identity/version synced (stale `doris-sql-language-client` name corrected)
- `vscode/README.md`: new `## Install` section — marketplace/Open VSX install, `fathom-lsp` acquisition from GitHub Release (asset table + `fathom-lsp-manifest.json` SHA-256 + `~/.fathom/bin`), `fathom-lsp --version` → `fathom-lsp 1.0.0`, `fathom.serverPath` + required dialect/profile settings
- `npm run package` produced `fathom-sql-language-client-1.0.0.vsix` (400 files, 697.26 KB); `vsce ls` verified `dist/extension.js` + manifest + README + language-configuration
- Marketplace pushes not executed: Open VSX (OVSX_TOKEN + `fathom` namespace) and VS Code Marketplace (Azure DevOps PAT + publisher registration) recorded as auth gates

## Task Commits
1. **Task 1: Release-version manifest and install guide** - `b58b3de`
2. **Task 2: Package verification and publication auth gates** - `b58b3de` + `60a808d` (lock sync, gitignore)

## Files Created/Modified
- `vscode/package.json` / `package-lock.json` / `README.md` / `.gitignore` (new)

## Decisions Made
- Followed plan (D-01..D-04)

## Deviations from Plan

None - plan executed exactly as written (lockfile identity also corrected as part of manifest release-readiness).

## Issues Encountered
- None

## Next Phase Readiness
- vsix ready to publish on providing OVSX_TOKEN / Azure DevOps PAT (or at Phase 20 formal release); next Phase 20 (Formal 1.0.0 Release & Verification)

---
*Phase: 19-editor-extension-publication*
*Completed: 2026-08-17*
