---
phase: 18-js-sdk-npm-publication
plan: 01
subsystem: sdk
tags: [npm, javascript, esm, wasm, typescript]

# Dependency graph
requires:
  - phase: 15-product-versioning-binary-version
    provides: product version 1.0.0 for the package
provides:
  - buildable/verifiable @fathom/sql npm package
  - consumer smoke test and capability metadata
affects: 19 editor publication, 20 formal release (registry push)

# Actuals
actuals:
  tokens: 1900
  tasks: 2
  commits: 1

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Package build pipeline: moon build js+wasm -> copy artifacts -> regenerate capabilities.json from the built binding -> npm pack"

key-files:
  created:
    - npm/package.json, npm/index.mjs, npm/index.d.ts, npm/README.md, npm/build.mjs, npm/.gitignore
    - npm/smoke/package.json, npm/smoke/smoke.mjs
  modified: []

key-decisions:
  - "@fathom/sql 1.0.0 ESM with typed wrapper over the fathom.*.v1 byte exports"
  - "Actual npm publish is auth-gated (no credentials in this environment); dry-run verified, registry push recorded as the gate"

patterns-established:
  - "Consumer-verification pattern: pack tarball -> independent install -> node smoke asserting parse/format/fingerprint/capabilities"

requirements-completed: [NPM-01, NPM-02]

coverage:
  - id: D1
    description: "@fathom/sql 1.0.0 ESM package: binding.js + binding.wasm + typed wrapper + index.d.ts + capabilities.json; Node/browser usable"
    requirement: NPM-01
    verification:
      - kind: other
        ref: "node npm/build.mjs: built artifacts copied (binding.js 1.3MB, binding.wasm 441KB); index.mjs imports with parse/capabilities functions; npm pack -> fathom-sql-1.0.0.tgz (7 files)"
        status: pass
    human_judgment: false
  - id: D2
    description: "Consumer smoke: install tarball in npm/smoke, parse('SELECT 1', doris, 4.x, strict) valid + no diagnostics, deterministic fingerprint, format round-trip to 'SELECT 1\\n', capabilities with doris 2.1/3.x/4.x + flink profiles"
    requirement: NPM-02
    verification:
      - kind: other
        ref: "npm/smoke/smoke.mjs -> 'SMOKE PASS' (exit 0); capabilities.json has dialects/profiles/modes/targets/wasm_gc:false"
        status: pass
    human_judgment: false
  - id: D3
    description: "Publish verified via dry-run; real registry push gated on credentials"
    requirement: NPM-01
    verification:
      - kind: other
        ref: "npm publish --dry-run rc=0 '@fathom/sql@1.0.0'; npm whoami -> ENEEDAUTH (auth gate recorded)"
        status: pass
    human_judgment: true
    rationale: "Registry publication requires the user's npm credentials; the package is verified publishable but the push itself cannot be executed without a token"

# Metrics
duration: 40min
completed: 2026-08-17
status: complete
---

# Phase 18 Plan 01: JS SDK npm Publication Summary

**@fathom/sql 1.0.0 built, packed, installed by an independent consumer, and smoke-verified (parse/format/fingerprint/capabilities); the registry push is prepared and auth-gated**

## Performance

- **Duration:** ~40 min
- **Tasks:** 2
- **Files:** 8 committed

## Accomplishments
- `npm/` package: `@fathom/sql` 1.0.0 ESM (`"type": "module"`, exports map, engines node>=18, Apache-2.0), shipping built `binding.js` (1.3 MB) + `binding.wasm` (442 KB), typed ESM wrapper (`index.mjs`) over all eight `fathom.*.v1` byte exports with UTF-8 handling, TypeScript declarations (`index.d.ts`), generated `capabilities.json`, and a README
- Build pipeline (`npm/build.mjs`): moon build js+wasm binding (release) -> copy artifacts -> regenerate `capabilities.json` from the built binding -> `npm pack` (tarball 286 KB, 7 files)
- Consumer smoke (`npm/smoke/`): independent install of the tarball; `parse('SELECT 1', doris, 4.x, strict)` valid with zero diagnostics, deterministic `fingerprint`, `format` round-trip to `SELECT 1\n`, `capabilities` with doris 2.1/3.x/4.x and flink pinned profiles — SMOKE PASS
- `npm publish --dry-run` succeeded (`@fathom/sql@1.0.0`); the real registry push is auth-gated (`npm whoami` -> ENEEDAUTH) — recorded, not faked

## Task Commits
1. **Task 1: Scaffold @fathom/sql package and build pipeline** - included
2. **Task 2: Consumer smoke test and publish dry-run with auth gate** - included

## Files Created/Modified
- `npm/package.json`, `npm/index.mjs`, `npm/index.d.ts`, `npm/README.md`, `npm/build.mjs`, `npm/.gitignore`
- `npm/smoke/package.json`, `npm/smoke/smoke.mjs`
- Generated (gitignored): `binding.js`, `binding.wasm`, `capabilities.json`, `*.tgz`

## Decisions Made
- Followed plan (D-01..D-05); format envelope field is `formatted` (byte array) — d.ts and smoke reflect the real schema

## Deviations from Plan

### Auto-fixed Issues
1. **[Rule 1 - Blocking] format envelope field mismatch** - the real `fathom.format.v1` envelope uses `formatted` (byte array), not `output`; smoke + d.ts corrected to decode it

**Total deviations:** 1 auto-fixed (blocking)
**Impact:** required for the consumer smoke to pass; no scope change.

## Issues Encountered
- None beyond the envelope field fix

## Revision (2026-08-17): npm publish wired to CI

- `NPM_TOKEN` is configured in GitHub secrets; new `.github/workflows/npm-publish.yml` (tag `v*` trigger + `workflow_dispatch` with `dry_run` input) builds the binding via the lock-driven installer, packs, asserts the package version matches the release tag, and runs `npm publish --access public` using `secrets.NPM_TOKEN`. `npm/build.mjs` now resolves `moon` via PATH.
- The Phase 18 publish gate is thereby an executable CI path: it fires automatically at the `v1.0.0` tag (Phase 20) or on an explicit dispatch; `dry_run=true` validates without pushing to the registry.

## Next Phase Readiness
- Package ready to publish on providing `NPM_TOKEN` (or at Phase 20 formal release); next Phase 19 (VS Code extension publication)

---
*Phase: 18-js-sdk-npm-publication*
*Completed: 2026-08-17*
