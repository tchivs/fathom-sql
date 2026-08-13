# Phase 14: Release Hygiene & Toolchain Pinning - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-13
**Phase:** 14-Release Hygiene & Toolchain Pinning
**Areas discussed:** Toolchain identity and acquisition, Release gate topology, Toolchain evidence in artifacts, Working-tree hygiene policy

---

## Toolchain Identity and Acquisition

| Option | Description | Selected |
|--------|-------------|----------|
| Keep historical `0.1.20260724` | Preserve local provenance even though the historical installer archive is documented unavailable | |
| Pin a currently obtainable exact stable version | Verify one official exact release works on every release runner, then use it in CI and release | ✓ |
| Continue `latest` and record output | Preserve current bootstrap but only log the moving compiler | |

**User's choice:** `[auto]` Selected the recommended current, obtainable, exact stable version shared by ordinary and release CI.
**Notes:** Official versioned artifacts, checksums, and exact version assertion are required; the concrete version remains a research task because availability must be verified across Linux/macOS/Windows.

---

## Release Gate Topology

| Option | Description | Selected |
|--------|-------------|----------|
| Duplicate gates in every platform build | Run parity/corpus/naming four times | |
| Dedicated required `release-gates` job | Run the complete gate once and make publishing explicitly depend on it | ✓ |
| Trust ordinary CI history | Publish based on a separate workflow's previous result | |

**User's choice:** `[auto]` Selected a dedicated fail-closed release gate with no manual bypass.
**Notes:** Reuse the existing CI commands, including all three parity targets, aggregate comparison, frozen diff, naming, and complete offline corpus checks.

---

## Toolchain Evidence in Artifacts

| Option | Description | Selected |
|--------|-------------|----------|
| Workflow log only | Leave `moon version` in ephemeral Actions logs | |
| One global text file | Record only the release-gate runner's version | |
| Per-platform machine-readable evidence | Ship one record per platform and a verified aggregate release record | ✓ |

**User's choice:** `[auto]` Selected per-platform `moon-toolchain.json` plus an aggregate release asset.
**Notes:** Missing, mismatched, or cross-platform-inconsistent evidence blocks publication.

---

## Working-Tree Hygiene Policy

| Option | Description | Selected |
|--------|-------------|----------|
| Delete all strays | Remove cache, quick artifacts, and historical research together | |
| Archive everything | Keep cache and duplicate plans as history | |
| Classify canonical vs generated/runtime | Ignore/delete cache and duplicate plans; preserve summaries and archive valuable research | ✓ |

**User's choice:** `[auto]` Selected classification-based cleanup with explicit status allowlists.
**Notes:** Ignore `pkg.generated.mbti` repository-wide; delete/ignore research cache; keep committed quick summaries, delete duplicate untracked plans; commit v1.0 research archive; exclude `.omp-*` runtime drift. Never use broad clean/reset/stash.

---

## Claude's Discretion

- Exact obtainable MoonBit release after official cross-platform availability and checksum research.
- Shared installer/configuration file name and non-contract JSON metadata fields.
- Internal step boundaries inside `release-gates` so long as all required commands remain fail-closed.

## Deferred Ideas

- Version reporting and semver → Phase 15.
- Install documentation → Phase 16.
- Changelog/disclosure → Phase 17.
- Registry/marketplace publishing → Phases 18–19.
- Formal release and post-publish smoke → Phase 20.
