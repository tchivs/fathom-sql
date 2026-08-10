---
phase: 09-dialect-boundary-and-neutral-naming
plan: 01
subsystem: parity
tags: [baseline, snapshot, parity, d-07, d-08, approved-changes, ci]
dependency_graph:
  requires: []
  provides:
    - "parity/__snapshot__ -> 09-02..09-07 (every refactor wave diffs against this baseline)"
    - "parity/baseline-hashes.txt -> corpus provenance (manifest.tsv, keywords.tsv, doris-{2.1,3.x,4.x}/*.sql)"
    - "scripts/baseline_diff.py + approved-changes.md -> D-08 mechanical approved-vs-regression gate"
    - "ci.yml parity-gate job -> byte-level gate on every push"
    - "parity/__snapshot__ + cross-target snapshot -> Phase 12 PARITY-01 comparison basis"
  affects:
    - parity/moon.pkg (imports for baseline suite)
    - .github/workflows/ci.yml (new parity-gate job)
tech-stack:
  added:
    - "@test.T::snapshot (moonbitlang/core/test) — official byte-level snapshot mechanism"
    - "python3 stdlib baseline_diff.py (zero new dependencies)"
  patterns:
    - "embedded-oracle pattern from test/corpus_test.mbt (runtime never reads disk)"
    - "check_keywords.py stdlib validation loop shape (problems list, non-zero exit, ok: line)"
key-files:
  created:
    - parity/baseline_test.mbt (213 snapshot tests over the full corpus x profile x mode matrix)
    - parity/__snapshot__/ (213 frozen v1 JSON snapshots)
    - parity/baseline-hashes.txt (33 sha256 lines pinning corpus provenance)
    - scripts/baseline_diff.py (approved-vs-unexpected snapshot shape-diff reporter)
    - .planning/phases/09-dialect-boundary-and-neutral-naming/approved-changes.md (D-08 register)
  modified:
    - parity/moon.pkg (completion + core/test imports)
    - .github/workflows/ci.yml (parity-gate job)
decisions:
  - "D-07 baseline freeze scope: FULL public behavior (Task 1 checkpoint, option-a auto-selected in yolo mode)"
  - "Embedded raws = exact committed corpus .sql file bytes (incl. provenance comment headers; 4.x-industrial keeps its TABLET (1001) and trailing recovery sections) + manifest inline rows — baseline hashes pin the exact same bytes (T-09-03 provenance integrity)"
  - "LSP homomorph = per-fixture editor parse envelope + strict format envelope (lsp-tracer.json pattern), covering the same enumerated 27-fixture representative subset as completion"
  - "Cross-target equality = one shared snapshot filename (cross-target.4.x-industrial.strict.json) written by every target; native/js/wasm all verified byte-identical, CI enforces native+wasm"
metrics:
  duration: 35 min
  completed_date: 2026-08-06
  tasks: 3
  commits: 2
  files: 219
status: complete
actuals:
  tokens: 402357  # chars/4 over the realized diff incl. the 1.9MB generated snapshot corpus; estimate 32000 assumed hand-written snapshots
  tasks: 3
  commits: 2
---

# Phase 09 Plan 01: Doris v1 Baseline Freeze (D-07/D-08 gate) Summary

Frozen the shipped v1 Doris behavior to bytes BEFORE any dialect/naming refactor: 213 `@test.T::snapshot` files over the full 44-fixture corpus x {strict, editor} parse matrix plus format (35), CLI homomorph (35), completion (27) and LSP homomorph (27) subsets and a cross-target byte-equality snapshot; committed corpus sha256 provenance; the approved-change register + stdlib diff tool + CI parity gate that make every later wave's diff mechanically distinguishable as approved (D-09/D-10) vs regression.

## Task Commits

| Task | Name | Commit | Key files |
| ---- | ---- | ------ | --------- |
| 1 | Confirm D-07 baseline freeze scope (one-way door) | (checkpoint:decision — option-a auto-selected in auto mode) | — |
| 2 | Freeze the v1 baseline — snapshot every fixture x profile x mode | c9a857b | parity/baseline_test.mbt, parity/__snapshot__/ (213 files), parity/baseline-hashes.txt, parity/moon.pkg |
| 3 | Approved-change register + baseline diff tooling + CI parity gate | 3eafc0e | approved-changes.md, scripts/baseline_diff.py, .github/workflows/ci.yml |

## Deviations from Plan

None — the plan executed as written. Two execution notes (not deviations):

1. **Corpus file bytes embedded verbatim.** The plan says to embed raw bytes from `corpus/doris-{2.1,3.x,4.x}/*.sql`; those files carry provenance comment headers (and the 4.x-industrial file carries the `TABLET (1001)` clause plus the trailing `SELECT k +` recovery section). The baseline therefore freezes v1 behavior on the REAL committed files — 4.x-industrial parses with DORIS-PARSE-001/002 recovery diagnostics and its format envelope is a DORIS-FORMAT-001 refusal — matching the sha256-pinned corpus exactly. Every embedded literal was machine-verified byte-identical to its hashed file.
2. **The 67KB baseline_test.mbt was generated deterministically** from the corpus files (escaping `\n`, `\"`, `\xff`, etc.) rather than hand-transcribed, to eliminate byte-drift risk against the very files it freezes; the generated content was then placed in the repo and byte-verified.

## Decisions Made

- **D-07 full freeze (Task 1 checkpoint, option-a):** all nine output categories (corpus, CST shape/span, diagnostics code/span/statement_id, strict/editor modes, formatter output, completion, CLI exit/stdout, LSP protocol output, wire schema) frozen byte-level. The baseline is the Phase 12 PARITY-01 comparison basis (one-way).
- **Embedded-raw provenance link:** baseline-hashes.txt pins exactly the bytes embedded in baseline_test.mbt (verified programmatically for all 44 fixtures), so a corpus edit is caught both by the hash file and by the snapshot gate.
- **LSP homomorph subset:** the editor-mode parse envelope plus strict format envelope per fixture (the parity/fixtures/lsp-tracer.json pattern), enumerated in approved-changes.md item 6 alongside the completion subset (27 fixtures, one per profile per statement class). The full parse/format/CLI matrix is never trimmed (D-07 auditability, T-09-04).
- **Cross-target equality mechanism:** one shared snapshot file (`cross-target.4.x-industrial.strict.json`) that every target build of the parity suite must reproduce; verified byte-identical on native, js, and wasm (225/225 on each). CI enforces native + linear-Wasm.

## Verification

- `moon test --package parity` (no `--update`): 225/225 pass on native, js, and wasm targets — any later byte difference fails.
- `test -s parity/baseline-hashes.txt && test -d parity/__snapshot__`: pass.
- `python3 scripts/baseline_diff.py --left parity/__snapshot__ --right parity/__snapshot__ --approve <register>`: `ok: 213 snapshots, 0 approved diffs, 0 unexpected`, exit 0; `python3 -m py_compile scripts/baseline_diff.py`: pass.
- Classifier negative test: an unapproved diagnostic message rewrite is reported as `error: ... unexpected diff` with exit 1, while schema-namespace/code-prefix/new-field changes are grouped as approved.
- ci.yml parity-gate job contains no `--update` flag (occurrences are prose comments only).

## Threat Surface

No new security-relevant surface beyond the plan's threat model: the parity test is a local MoonBit test, baseline_diff.py is Python stdlib with no network/filesystem writes, and the CI job runs the existing toolchain. No `## Threat Flags` entries.

## Known Stubs

None. Every snapshot is real serialized v1 output; no placeholder content.

## Self-Check: PASSED

- `parity/baseline_test.mbt` exists (67,773 bytes, 213 test blocks) — FOUND
- `parity/__snapshot__/` exists with 213 `.json` files (1.9 MB) — FOUND
- `parity/baseline-hashes.txt` exists (33 sha256 lines, `sha256sum -c` all OK) — FOUND
- `scripts/baseline_diff.py` exists, py_compile clean, self-diff exit 0 — FOUND
- `.planning/phases/09-dialect-boundary-and-neutral-naming/approved-changes.md` exists — FOUND
- ci.yml contains the `parity-gate` job (moon test without --update + baseline_diff self-diff) — FOUND
- Commits c9a857b and 3eafc0e exist in `git log` — FOUND
- Embedded raws byte-match the hashed corpus files (44/44 verified programmatically) — PASSED
