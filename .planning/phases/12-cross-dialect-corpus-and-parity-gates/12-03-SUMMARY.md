---
phase: 12-cross-dialect-corpus-and-parity-gates
plan: 03
subsystem: corpus-parity-gates
tags: [parity, cross-backend, three-target, ci-wiring, offline-gates, python-stdlib, PARITY-02, PARITY-03]

# Dependency graph
requires:
  - phase: 12-cross-dialect-corpus-and-parity-gates (12-01)
    provides: scripts/verify_corpus.py + corpus/flink-coverage.tsv + extended generate_corpus_report.py (offline corpus gate + semantic-distinction coverage report)
  - phase: 12-cross-dialect-corpus-and-parity-gates (12-02)
    provides: scripts/diff_parity.py --frozen-only regeneration harness (D-03 frozen-vs-current proof)
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: Doris baseline freeze (213 snapshots) + approved-changes register + baseline_diff engine
provides:
  - scripts/compare_backends.py — three-target byte-parity aggregate reporter (Python stdlib): runs `moon test --target {native,js,wasm} --package parity`, captures per-target rc + test stats, NAMES failing fixtures by content-hash mapping of the moon snapshot-diff expected bytes, computes a deterministic sha256 tree digest over the committed parity/__snapshot__ tree, and fails closed (exit 1) on any skipped/failed target, empty/missing tree, or tree change during the run (non-empty guard, Pitfall 8)
  - .github/workflows/ci.yml — wired offline gates + three-target matrix: `moon test --target js --package parity` runtime step + `python3 scripts/compare_backends.py` aggregate step in linear-wasm-parity; `python3 scripts/diff_parity.py --frozen-only` in parity-gate; `python3 scripts/verify_corpus.py --check` in corpus (keep the extended report --check); NO --update in any run line; the only network step remains the MoonBit installer curl
affects:
  - 13-toolchain-and-editor-packaging (three-target byte parity and the offline gates become standing release contracts)

# Actuals (#2632) — pairs with the plan's `estimate` (34000 tokens).
# Same estimateTokens scale (chars/4 over the realized diff), never a harness token count.
actuals:
  tokens: 3190
  tasks: 3
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "content-hash failing-fixture mapping: moon test does not print snapshot filenames, so compare_backends.py builds a sha256(content)->filename index over the committed snapshot tree and maps each snapshot-diff expected byte string ('-' side) back to the snapshot file that produced it — the honest name of a failing fixture"
    - "rc + deterministic tree-digest byte-parity proof (D-05, A8): linear-wasm cannot stdout-dump (parity/run_wasm.mbt), so the three-target proof is per-target moon rc + an identical sha256 tree digest over the shared committed parity/__snapshot__ tree"
    - "read-only gate guarantee (D-06/PARITY-03 concurrency backstop): the tree digest is verified unchanged before/after the run — an interrupted or parallel gate cannot half-write state or fabricate a pass"

key-files:
  created:
    - scripts/compare_backends.py
  modified:
    - .github/workflows/ci.yml

key-decisions:
  - "Task 1 (D-05 one-way door, auto-selected option-a per RESEARCH A10/§7.2): merge the js runtime step into the existing linear-wasm-parity job (one checkout/install, matrix semantics) + a new stdlib compare_backends.py with the rc + snapshot-tree sha256 digest proof (wasm cannot stdout-dump); a separate js job or per-fixture dump entry was rejected as higher CI surface for no added contract value."
  - "Failing-fixture naming via content hash: moon prints the expected snapshot bytes (the '-' side of the Diff), not the filename — the content->filename index over the committed tree is the honest mapping, with the failed-test label as a fallback identifier."
  - "compare_backends.py reads one shared committed tree: the digest is computed over the same parity/__snapshot__ that every target's snapshot assertions compare against, and is verified unchanged after the run (read-only violation = exit 1)."
  - "No --update anywhere in CI (Pitfall 1); the only network step remains the MoonBit installer curl (D-06, Pitfall 5) — all wired gate steps are Python stdlib over committed artifacts."

requirements-completed: [PARITY-02, PARITY-03]

coverage:
  - id: D1
    description: "scripts/compare_backends.py — three-target byte-parity aggregate: runs `moon test --target {native,js,wasm} --package parity`, captures per-target rc + Total tests/passed/failed stats, computes a deterministic sha256 tree digest over the committed parity/__snapshot__ tree, and reports per-target pass/fail + failing-fixture list + the identical cross-target digest; exits 0 only when all targets pass AND the tree is non-empty AND the digest is identical across targets (PARITY-02, D-05)."
    requirement: PARITY-02
    verification:
      - kind: integration
        ref: "python3 scripts/compare_backends.py on the clean tree -> exit 0, native/js/wasm all PASS 570/570, snapshot-tree sha256 digest identical across targets (5e9bb8…); git status --short parity/__snapshot__ empty after the run"
        status: pass
      - kind: integration
        ref: "injected byte drift in cross-target.4.x-industrial.strict.json -> exit 1 naming 'failing fixture: cross-target.4.x-industrial.strict.json' on all three targets with the digest reflecting the modified tree; reverted -> exit 0 again"
        status: pass
      - kind: integration
        ref: "empty/missing snapshot tree (--snapshot-dir /tmp/empty-snap, /tmp/no-such-dir-xyz) -> exit 1 with an error line (non-empty guard, Pitfall 8); unknown target 'bogus' -> exit 1"
        status: pass
    human_judgment: false
  - id: D2
    description: "CI three-target runtime matrix includes JavaScript — linear-wasm-parity executes `moon test --target js --package parity` in addition to wasm and native, closing the Research §4.5 js-runtime gap so a js-only byte regression cannot silently diverge."
    requirement: PARITY-02
    verification:
      - kind: integration
        ref: ".github/workflows/ci.yml linear-wasm-parity job contains the js runtime step, the compare_backends.py aggregate step, and the Set up Python step (added)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Offline gate pipeline wired from pinned local artifacts only — corpus job runs `python3 scripts/verify_corpus.py --check` (keep the extended generate_corpus_report.py --check), parity-gate job runs `python3 scripts/diff_parity.py --frozen-only`; NO --update in any run line and the only network step remains the MoonBit installer curl (PARITY-03, D-06, Pitfall 5)."
    requirement: PARITY-03
    verification:
      - kind: integration
        ref: "ci.yml grep: no 'run:.*--update' line; the only curl occurrences are the 4 MoonBit installer bootstraps; no pip/wget/ls-remote/npm install anywhere"
        status: pass
      - kind: integration
        ref: "all wired commands pass locally on the current tree: verify_corpus.py --check (110 rows), diff_parity.py --frozen-only (433 snapshots, 0 differences), compare_backends.py (3 targets pass, identical digest), generate_corpus_report.py --check (current and consistent)"
        status: pass
    human_judgment: false
  - id: D4
    description: "A maintainer can inspect a three-target aggregate parity report — compare_backends.py reports per-target pass/fail, the failing-fixture list (snapshot filenames), and the identical snapshot-tree digest; it fails closed (exit 1) when any target is skipped/failed or the tree is empty/changed (Pitfall 8, T-12-03-01)."
    requirement: PARITY-02
    verification:
      - kind: integration
        ref: "per-target report lines + failing-fixture lines observed in drift test; empty-tree guard exit 1; skip path (moon not found) exits 1 by construction"
        status: pass
    human_judgment: false
  - id: D5
    description: "The coverage report's semantic distinction (parser acceptance vs engine prerequisite) is CI-enforced for both dialects via the existing extended generate_corpus_report.py --check (wired step kept in the corpus job after verify_corpus.py --check)."
    requirement: PARITY-03
    verification:
      - kind: integration
        ref: "python3 corpus/tools/generate_corpus_report.py --check -> 'ok: CORPUS-REPORT.md is current and consistent' (the 12-01 prerequisite hard rule + manifest aggregation cross-check remain active in the corpus job)"
        status: pass
    human_judgment: false

# Metrics
duration: 7min
completed: 2026-08-09
status: complete
---

# Phase 12 Plan 03: Cross-Backend Parity + Offline CI Gates Summary

**`scripts/compare_backends.py` proves the D-05 three-target byte parity with a per-target `moon test` rc + a deterministic sha256 tree digest over the committed snapshot tree (naming failing fixtures by content-hash mapping, failing closed on any skip/fail/empty-tree), and CI now runs the full three-target matrix including a js runtime parity step — with the offline gates (`verify_corpus.py --check`, `diff_parity.py --frozen-only`, the extended coverage report `--check`) wired in with no `--update` and no new network access.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-08-09T12:43:05Z
- **Completed:** 2026-08-09T12:49:35Z
- **Tasks:** 3 (1 auto-selected decision + 2 executed)
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- **`scripts/compare_backends.py`** (306 lines, Python stdlib) — the D-05 three-target byte-parity aggregate:
  - Runs `moon test --target {native,js,wasm} --package parity` (default; optional `--targets` override), captures each target's exit code + `Total tests/passed/failed` stats.
  - **Failing-fixture naming:** moon does not print snapshot filenames, so the script builds a `sha256(content) -> [filenames]` index over the committed snapshot tree and maps each snapshot-diff expected byte string (the `-` side of the Diff) back to the snapshot file that produced it; the failed-test label is the fallback identifier. Verified by injecting a byte drift into `cross-target.4.x-industrial.strict.json` — all three targets report `failing fixture: cross-target.4.x-industrial.strict.json`.
  - **Byte-parity proof:** a deterministic sha256 tree digest over the committed `parity/__snapshot__` tree (433 files) is reported identically for all three targets (wasm cannot stdout-dump, A8). The digest is verified unchanged before/after the run — a target that wrote snapshots fails the run (read-only guarantee / PARITY-03 concurrency backstop).
  - **Non-empty guard (Pitfall 8):** missing or empty snapshot tree → exit 1 with an error line; skipped/failed target → exit 1; unknown target → exit 1. Clean tree → exit 0.
- **`.github/workflows/ci.yml`** — wired offline gates + three-target matrix:
  - `linear-wasm-parity` job: added the `Set up Python` step, the `moon test --target js --package parity` runtime step (closes the Research §4.5 js-runtime gap), and the final `python3 scripts/compare_backends.py` aggregate step.
  - `parity-gate` job: added `python3 scripts/diff_parity.py --frozen-only` after the baseline_diff self-check and baseline-hashes pin — the D-03 regenerated frozen-vs-current proof (registers never consulted; temp `--update` lifecycle leaves the committed tree untouched).
  - `corpus` job: added `python3 scripts/verify_corpus.py --check` before the extended `generate_corpus_report.py --check` (offline D-06 gate + the parser-acceptance vs engine-prerequisite hard rule).
  - No `--update` in any run line (Pitfall 1); the only network step remains the MoonBit installer curl (D-06, Pitfall 5); every wired gate is Python stdlib over committed artifacts.

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm the cross-backend parity contract and CI matrix form (D-05 one-way door)** — auto-selected option-a (merge js runtime into linear-wasm-parity + `compare_backends.py` with rc+digest proof) under `_auto_chain_active=true` / `mode=yolo` (no commit — decision only).
2. **Task 2: Implement scripts/compare_backends.py — three-target byte-parity aggregate report** — `a6e62ad` (feat(12-03): three-target byte-parity aggregate reporter (compare_backends.py))
3. **Task 3: Wire the offline gates and the three-target matrix into CI** — `d1d79bd` (chore(12-03): wire offline gates and three-target matrix into CI)

## Files Created/Modified
- `scripts/compare_backends.py` - Three-target byte-parity aggregate reporter (rc + stats + failing-fixture content-hash naming + deterministic snapshot-tree sha256 digest + non-empty guard + read-only guarantee)
- `.github/workflows/ci.yml` - js runtime step + compare_backends.py aggregate in linear-wasm-parity; diff_parity.py --frozen-only in parity-gate; verify_corpus.py --check in corpus job

## Decisions Made
- **Task 1 (auto-selected option-a):** merge the js runtime parity step into the existing `linear-wasm-parity` job (one checkout/install, matrix semantics per RESEARCH A10/§7.2) rather than a separate `js-parity` job; `compare_backends.py` proves byte parity via per-target `moon test` rc + a deterministic snapshot-tree sha256 digest (wasm cannot stdout-dump, A8) — a per-fixture explicit dump entry would exceed the snapshot mechanism for no added contract value.
- **Failing-fixture naming via content hash:** moon prints the expected snapshot bytes, not filenames; the `sha256(content)->filename` index over the committed tree is the honest mapping, with the failed-test label as a fallback identifier.
- **Read-only gate guarantee:** the digest is computed over the same shared committed tree every target's snapshot assertions compare against, and is verified unchanged before/after the run — an interrupted or parallel gate run cannot half-write state or fabricate a pass (PARITY-03 concurrency backstop).

## Deviations from Plan

No Rule 1-3 deviations were required — the plan executed as written. One implementation note:

**Implementation note (moon output does not name snapshots):** the plan's Task 2 action said to "extract the failing snapshot filenames from the moon output". A probe showed `moon test` prints the failed-test label and the expected snapshot bytes (the `-` side of the Diff) but never the `.json` filename. `compare_backends.py` therefore maps the expected bytes back to the snapshot filename via a content->filename index over the committed tree — the acceptance criterion (a failing fixture named in the report, proven by the injected-drift test) is met.

## Issues Encountered
- **`cp` alias overwrite prompt during drift testing:** an early restore of the injected-drift snapshot hit an interactive `cp: overwrite?` alias prompt, leaving the modified file in the tree; the follow-up `compare_backends.py` run correctly FAILED on it (naming the drifted fixture), and a `git checkout -- <file>` restored the committed bytes. No residue after the fix.

## Threat Surface Scan

No new network endpoints, auth paths, file-access patterns, or trust-boundary schema changes were introduced beyond the plan's `<threat_model>`. `compare_backends.py` invokes the existing `moon` CLI via subprocess over the committed snapshot tree (read-only, digest-verified) and reads only `parity/__snapshot__`; the CI additions are Python stdlib steps over committed artifacts (T-12-03-01..06; SC: zero new runtime dependencies). No new trust-boundary surface to flag.

## Known Stubs

None — `compare_backends.py` is fully functional and all wired CI steps are runnable; no placeholders.

## Next Phase Readiness
- **Phase 13 (Toolchain and Editor Packaging)** inherits a standing three-target byte-parity matrix (native/js/wasm 570/570 with an identical snapshot-tree digest) and the offline release-gate pipeline (verify_corpus --check, diff_parity --frozen-only, coverage report --check) as release contracts.
- **Deferred/known gaps (unchanged from 12-01/12-02):** `extract_flink_*` remain local maintainer tools (need `/tmp/flink-research/`); the flagged-unverified probes (PARITY-02 unclassified, PARITY-03 concurrency) are documented in the plan's must_haves as flagged for manual review — the authored byte-identity and read-only contracts enforce them in full.

---
*Phase: 12-cross-dialect-corpus-and-parity-gates*
*Completed: 2026-08-09*

## Self-Check: PASSED

All 3 deliverables exist (scripts/compare_backends.py, .github/workflows/ci.yml, 12-03-SUMMARY.md) and both task commits (a6e62ad, d1d79bd) are present in git history.
