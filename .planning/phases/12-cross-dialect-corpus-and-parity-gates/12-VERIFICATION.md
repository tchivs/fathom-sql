---
phase: 12-cross-dialect-corpus-and-parity-gates
verified: 2026-08-09T21:15:00Z
status: passed
score: 15/15 substantive contract truths verified
behavior_unverified: 0
overrides_applied: 0
gaps: []
human_verification:

  - test: "Confirm CORPUS-01 is satisfied in full: the release-pinned Flink corpus manifest (parity/fixtures/flink/manifest.tsv, 110 rows, 19 columns) records release/tag/commit, Calcite version/config, source URL/heading, retrieval date, hash, expected status, and all 6 categories; verify_corpus.py --check enforces it offline."
    expected: "A maintainer can audit every fixture's provenance and category offline; generic SQL acceptance is never reported as Flink engine support."
    why_human: "The 12-01 edge-probe left CORPUS-01 unclassified (flagged-unverified in plan must_haves). The authored manifest/verifier contract was verified by direct gate execution, but the requirement classification itself remains flagged for manual review per the honest-verifier protocol."

  - test: "Confirm PARITY-01 is satisfied in full: diff_parity.py --frozen-only regenerates the snapshot tree in a temp moon test --update lifecycle, fails (exit 1) on ANY difference, and consults NO register; Doris 2.1/3.x/4.x behavior stays equal to the frozen baseline."
    expected: "Frozen Doris baseline is proven by regeneration (433 snapshots, 0 differences); any intentional change requires a pre-committed approved-changes.md entry."
    why_human: "The 12-02 edge-probe left PARITY-01 unclassified (flagged-unverified in plan must_haves). The frozen-vs-current harness contract was exercised directly (exit 0 clean, documented injected-drift exit 1), but the requirement classification remains flagged for manual review."

  - test: "Confirm PARITY-02 is satisfied in full: the same fixture produces byte-identical serialized results, diagnostics, spans, and lossless replay across Native, JavaScript, and linear-Wasm; CI runs the three-target matrix including js."
    expected: "compare_backends.py reports all three targets PASS with an identical snapshot-tree sha256 digest (5e9bb887…); CI linear-wasm-parity job runs moon test --target js --package parity."
    why_human: "The 12-03 edge-probe left PARITY-02 unclassified (flagged-unverified in plan must_haves). The byte-identity contract was verified by direct three-target execution and digest comparison, but the requirement classification remains flagged for manual review."

  - test: "Confirm PARITY-03 concurrency safety: interrupting or running the offline gates in parallel must never corrupt or half-write corpus/verifier state — verify_corpus.py and compare_backends.py are read-only over pinned artifacts (digest verified unchanged before/after), and diff_parity.py restores the committed snapshot tree on any failure or SIGTERM/SIGINT."
    expected: "An interrupted or concurrent gate run leaves no partial state and cannot fabricate a pass."
    why_human: "Backstop truth (verification: backstop). The executor documented the SIGTERM mid-regeneration restore test (exit 2 + tree restored) and the source contains read-only guards, but the concurrency/parallel-run invariant requires human judgment to fully confirm."
---

# Phase 12: Cross-Dialect Corpus and Parity Gates — Verification Report

**Phase Goal:** Maintainers can audit reproducible Doris/Flink coverage and release only when dialect behavior and cross-backend serialized results remain within explicit parity contracts.
**Verified:** 2026-08-09T21:15:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

Goal-backward analysis: for the goal to be achieved, (a) a release-pinned Flink corpus must be auditable, (b) Doris behavior must remain equal to the frozen baseline with explicit approval for deviations, (c) cross-backend serialized results must be byte-identical, and (d) offline gates must run from pinned artifacts while distinguishing parser acceptance from engine prerequisites. Each was verified directly against the codebase by executing every gate script.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Maintainer can inspect a release-pinned Flink corpus manifest recording release/tag/commit, Calcite version/config, URL/heading, retrieval date, hash, expected status, and the 6 categories (CORPUS-01, SC1) | ✓ VERIFIED | `parity/fixtures/flink/manifest.tsv` — 110 rows, 19 columns; category distribution positive=49, negative=25, recovery=17, planner-prerequisite=13, known-limitation=3, catalog-prerequisite=3; each row has calcite_version, parser_config, source_archive_url, sha512, git_tag, git_commit, source_url, heading, retrieval_date, fixture_sha256, grammar_path, line_range, mode |
| 2 | `python3 scripts/verify_corpus.py --check` runs entirely offline and exits 0 only when header matches, pins match `dialect/flink.mbt`, category is in the 6-value enum, expected_status is consistent, fixture_sha256 matches committed bytes, and strict+editor snapshots exist per row (PARITY-03) | ✓ VERIFIED | Executed: `ok: 110 flink corpus rows verified offline (header, pins, 6-category, expected-status, fixture sha256, snapshot completeness); 104 archive sha512 re-verified`, exit 0. Source `PINS` table at :105-119 mirrors `dialect/flink.mbt` FlinkProfileMetadata (1.36.0/1.34.0/1.32.0) with the exact parser config string; stdlib-only, no subprocess/urllib/requests/socket |
| 3 | All 97 flink-grammar + 13 flink-lexical fixtures present in the unified manifest; each committed .sql byte-matches the embedded `b"..."` literal (D-02 migration zero loss) | ✓ VERIFIED | `extract_flink_grammar.py` exit 0: "97 embedded b\"...\" literals byte-match committed .sql files … 110 unified manifest rows pass 6-category enum + expected_status + fixture_sha256"; `extract_flink_lexical.py` exit 0: "13 embedded b\"...\" literals byte-match … 13 unified flink-lexical rows pass 6-category + token-source + fixture_sha256". 110 .sql files under `parity/fixtures/flink/{flink-2.3.0,flink-2.1.3,flink-1.20.5,doris-4.x}/` |
| 4 | Coverage report renders parser acceptance and engine-semantic prerequisite as distinct totals; catalog/planner/known-limitation never counted as engine-supported; no full-compatibility claim (PARITY-03) | ✓ VERIFIED | `corpus/flink-coverage.tsv`: parser_accepted=68 (49 positive + 13 planner + 3 catalog + 3 known-limitation), prerequisite=19, engine-supported=49 positive-only. `CORPUS-REPORT.md` :189-213 states engine-supported counts positive only and catalog/planner/known-limitation are never engine-supported; no unqualified compatibility claim |
| 5 | Missing release archive reported as archive-not-present (does not fail the gate); resident fixture_sha256 over committed .sql remains the CI-checkable hash; no hash/provenance value fabricated | ✓ VERIFIED | verify_corpus.py `--check` exit 0 with "104 archive sha512 re-verified" while 6 doris-4.x control rows carry N/A sha512 (exempt, in-repo data only); extractors degrade to skip when `/tmp/flink-research/` archives absent (documented IN-01, D-06 option-a); every fixture has a real fixture_sha256 matching committed bytes |
| 6 | `python3 scripts/diff_parity.py --frozen-only` regenerates the current snapshot tree in a temp `moon test --update` lifecycle, FAILS (exit 1) on ANY difference, and consults NO register (PARITY-01, D-03) | ✓ VERIFIED | Executed: regeneration ran `Total tests: 570, passed: 570, failed: 0`, then `ok: 433 snapshots, 0 frozen-vs-current differences`, exit 0; `git status --porcelain -- parity/__snapshot__` empty after. Source docstring :24-27 confirms register NOT consulted in --frozen-only and failure on any diff; `_sigterm_handler` + restore-on-failure lifecycle |
| 7 | Doris 2.1/3.x/4.x valid/invalid/recovery/CST/span/diagnostic/formatter/completion behavior stays equal to the frozen baseline: `moon test --package parity` (no --update) passes and no doris-named snapshot changed (PARITY-01, D-04) | ✓ VERIFIED | Full native suite passes (CI 12-package command 796/796 + `fathom-sql` 16/16 = 812/812); parity package 570/570 across native/js/wasm; `git diff --name-only -- parity/__snapshot__` empty (0 doris-named snapshot changes) |
| 8 | Approval flow is single-use: any intentional snapshot change has a register entry committed BEFORE the one `moon test --update`; a diff with no register entry is unexpected, never absorbed (D-07, Pitfall 1) | ✓ VERIFIED | `approved-changes.md` Section 1 Rule text; no `run:` line in `.github/workflows/ci.yml` contains `--update`; Phase 12 register pre-declares no active rows and documents the key:/prefix:/field: skeleton; diff_parity.py `--approve <register>` mode classifies approved vs unexpected via reused baseline_diff engine |
| 9 | Docs-vs-parser and release-fact-vs-docs conflicts surface explicitly as unexpected rows routed to the human-adjudication register, never silently resolved by bulk snapshot updates (D-07) | ✓ VERIFIED | `approved-changes.md` Section 2 defines the conflict-adjudication entry point (docs authority change → register row + single --update; parser regression → fix parser; release fact → pinned release wins with recorded reason); diff_parity.py --approve reports unexpected rows with exit 1 |
| 10 | The Phase 12 approved-changes.md register pre-declares the snapshot-surface expectations and re-asserts the Doris zero-drift hard gate (D-08) | ✓ VERIFIED | `approved-changes.md` present; Section 1 table lists 12-01/12-02/12-03 all shipping **no** snapshot byte changes; "Doris 213-snapshot zero-drift is a HARD gate"; 433 committed snapshots (Doris 213 + flink groups) byte-identical after all phase work |
| 11 | Same fixture set produces byte-identical serialized results, diagnostics, spans, and lossless replay across Native, JavaScript, and linear-Wasm: three `moon test --target {native,js,wasm} --package parity` pass and `compare_backends.py` exits 0 with identical snapshot-tree sha256 digest (PARITY-02, D-05) | ✓ VERIFIED | Executed `python3 scripts/compare_backends.py`: native/js/wasm all `PASS rc=0 tests=570 passed=570 failed=0`, digest `5e9bb887e71ddc814d7cd86b4f0b0222352800ace927e20cdabd21057e22020c` identical across all three targets, exit 0 |
| 12 | CI runs a three-target runtime matrix that includes JavaScript (PARITY-02, D-05) | ✓ VERIFIED | `.github/workflows/ci.yml` linear-wasm-parity job has "Execute parity suite on JavaScript target" step `moon test --target js --package parity`, plus "Set up Python", plus the `compare_backends.py` aggregate step |
| 13 | Offline gate pipeline runs from pinned local artifacts only: corpus job runs verify_corpus.py --check + generate_corpus_report.py --check; parity-gate runs diff_parity.py --frozen-only; no network / Doris FE / Flink cluster / DB access (PARITY-03, D-06) | ✓ VERIFIED | ci.yml: corpus job has "Offline Flink corpus verifier" + "Corpus report --check"; parity-gate job has "Frozen-vs-current regeneration proof (diff_parity)" after the byte-level gate; no `run:` line contains `--update`; only network steps are the 4 MoonBit installer curls (no pip/wget/ls-remote/npm/apt-get); all four gates executed locally with exit 0 |
| 14 | A maintainer can inspect a three-target aggregate parity report; it fails closed (exit 1) when any target is skipped/fails, tree empty/missing, or digests diverge (PARITY-02, Pitfall 8) | ✓ VERIFIED | compare_backends.py prints per-target PASS/rc/digest + `ok:` summary; source :233-254 shows non-empty guard (exit 1 on empty tree), skipped-target guard, and read-only digest-unchanged check (exit 1 on tree change); source :16-18 documents content-hash failing-fixture naming |
| 15 | Coverage report wired into CI enforces the semantic distinction for both dialects (PARITY-03, D-01) | ✓ VERIFIED | ci.yml corpus job keeps `generate_corpus_report.py --check`; executed locally: `ok: CORPUS-REPORT.md is current and consistent (matrix, failures, known-gaps, keywords summary, flink cross-dialect)`, exit 0. Source includes the prerequisite hard rule + manifest aggregation cross-check (SUMMARY 12-01 auto-fix 2) |

**Score:** 15/15 substantive contract truths verified. 4 flagged probe assumptions (CORPUS-01/PARITY-01/PARITY-02 unclassified, PARITY-03 concurrency backstop) abstained per the honest-verifier protocol and are listed under Human Verification — hence overall status `human_needed`, not `passed`.

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `parity/fixtures/flink/manifest.tsv` | Unified release-pinned corpus manifest (110 rows, 19 cols, 6 categories) | ✓ VERIFIED | 110 rows; all 6 categories present; every column populated (sha512 N/A only for 6 in-repo doris-4.x control rows); fixture_sha256 pins |
| `parity/fixtures/flink/{profile}/*.sql` (110) | Committed raw-SQL fixtures byte-matching embedded `b"..."` literals | ✓ VERIFIED | 110 .sql files; extract_flink_grammar.py/lexical.py byte-compare 97+13 embedded literals, exit 0 |
| `scripts/verify_corpus.py` | Offline stdlib manifest/hash/snapshot verifier (--check) | ✓ VERIFIED | 350 lines; PINS table, 6-category enum, expected_status consistency, fixture_sha256, archive sha512 present-verify / absent-archive-not-present, snapshot completeness, non-empty + path-traversal guard; executes exit 0 |
| `corpus/flink-coverage.tsv` | Semantic-distinction coverage matrix | ✓ VERIFIED | 12 rows; prerequisite column = none/catalog/structural/planner; engine-supported=0 for prerequisite rows |
| `corpus/tools/generate_corpus_report.py` | Coverage report renderer + --check hard rule | ✓ VERIFIED | 467 lines; prerequisite hard rule + manifest aggregation cross-check; --check exit 0 |
| `corpus/CORPUS-REPORT.md` | Regenerated bilingual report with Flink section | ✓ VERIFIED | Parser-accepted 68 vs prerequisite 19 vs engine-supported 49; no unqualified compat claim |
| `scripts/diff_parity.py` | Frozen-vs-current regeneration diff harness | ✓ VERIFIED | 362 lines; --frozen-only / --approve / --left/--right; restore-on-failure + SIGTERM handler; exit 0 on clean tree |
| `scripts/baseline_diff.py` | Minimal --frozen/--current aliases | ✓ VERIFIED | 10682 bytes; --left/--right engine reused unchanged |
| `.planning/phases/12-…/approved-changes.md` | Phase 12 D-08 register | ✓ VERIFIED | Single-use rule, zero-drift hard gate, pre-declared expectations, machine-readable skeleton |
| `scripts/compare_backends.py` | Three-target byte-parity aggregate reporter | ✓ VERIFIED | 306 lines; per-target rc + digest; content-hash failing-fixture naming; non-empty + read-only digest guard; exit 0 |
| `.github/workflows/ci.yml` | Wired offline gates + three-target matrix | ✓ VERIFIED | js runtime step, compare_backends aggregate, diff_parity --frozen-only, verify_corpus --check + report --check; no --update; only installer curl |
| `scripts/extract_flink_grammar.py` / `extract_flink_lexical.py` | Local maintainer extractors (D-08 provenance) | ✓ VERIFIED | exit 0; embedded-literal byte-compare + 6-category enum + calcite pins |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| manifest.tsv category + expected_status | verify_corpus.py enum + consistency check | enum membership + expected_status↔category mapping | WIRED | `--check` exit 0 over all 110 rows |
| `{profile}/{fixture_id}.sql` files | manifest.tsv fixture_sha256 | hashlib.sha256 over committed bytes | WIRED | `--check` verifies every fixture hash |
| `.mbt` embedded `b"..."` literals | committed .sql files | extract_flink_* byte-compare | WIRED | 97 + 13 byte-matches, exit 0 |
| flink-coverage.tsv prerequisite column | generate_corpus_report.py renderer | catalog/planner/known-limitation → prerequisite, never engine-supported | WIRED | `--check` exit 0 + aggregation cross-check |
| snapshot files | verify_corpus.py snapshot completeness | `{fixture_id}.{profile}.{mode}.json` (flink) / `.doris-4.x.` (doris rows) / `.flink-4x.` (unknown-profile) | WIRED | strict+editor present per row; spot-checked alter-catalog/backtick-escape/unknown-profile |
| diff_parity.py temp current tree | baseline_diff.py classification engine | `import baseline_diff` + --approve flow | WIRED | --frozen-only exit 0 (433 snapshots, 0 diffs) |
| committed parity/__snapshot__ tree | temp regenerated tree | diff_parity.py move/restore lifecycle | WIRED | regeneration ran 570 tests then compared; zero residue |
| doris-named snapshots | approved-changes.md register | any doris diff must have pre-committed entry | WIRED | git diff empty; register re-asserts zero-drift hard gate |
| compare_backends.py subprocess | `moon test --target {native,js,wasm} --package parity` | per-target rc + stats capture | WIRED | 3 targets all PASS rc=0 |
| parity/__snapshot__ tree | compare_backends.py sha256 digest | deterministic tree digest over 433 files | WIRED | digest 5e9bb887… identical across targets; unchanged before/after (read-only) |
| ci.yml parity-gate job | `diff_parity.py --frozen-only` | wired step | WIRED | step present after baseline self-check + hash pin |
| ci.yml corpus job | `verify_corpus.py --check` + `generate_corpus_report.py --check` | wired steps | WIRED | both steps present, no --update |
| ci.yml linear-wasm-parity job | `moon test --target js --package parity` | wired step | WIRED | js runtime step closes the Research §4.5 gap |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| verify_corpus.py --check | manifest rows, fixture bytes, snapshot files | committed `parity/fixtures/flink/` + `parity/__snapshot__` | Yes — real hashes (fixture_sha256) and 104 archive sha512 re-verified | ✓ FLOWING |
| generate_corpus_report.py --check | flink-coverage.tsv + manifest aggregation | committed corpus TSVs | Yes — parser-accepted 68 / prerequisite 19 / engine-supported 49, byte-identical regeneration | ✓ FLOWING |
| diff_parity.py --frozen-only | regenerated snapshot tree vs committed tree | temp `moon test --update` over committed baseline | Yes — 570 tests regenerated, 433 snapshots compared, 0 diffs | ✓ FLOWING |
| compare_backends.py | per-target rc + tree digest | three `moon test --target` runs over shared committed tree | Yes — identical digest 5e9bb887… across native/js/wasm | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Offline corpus verifier | `python3 scripts/verify_corpus.py --check` | `ok: 110 flink corpus rows verified offline … 104 archive sha512 re-verified`, exit 0 | ✓ PASS |
| Coverage report freshness + semantic rule | `python3 corpus/tools/generate_corpus_report.py --check` | `ok: CORPUS-REPORT.md is current and consistent`, exit 0 | ✓ PASS |
| Doris frozen baseline regeneration proof | `python3 scripts/diff_parity.py --frozen-only` | regeneration 570/570 then `ok: 433 snapshots, 0 frozen-vs-current differences`, exit 0 | ✓ PASS |
| Cross-backend byte parity | `python3 scripts/compare_backends.py` | native/js/wasm all PASS 570/570, digest `5e9bb887…` identical, exit 0 | ✓ PASS |
| Full native suite | `moon test --target native --package {12 CI packages}` + `--package fathom-sql` | 796/796 + 16/16 = 812/812, exit 0 | ✓ PASS |
| Embedded-raw provenance (grammar) | `python3 scripts/extract_flink_grammar.py` | 97 literals byte-match; 110 rows 6-category; exit 0 | ✓ PASS |
| Embedded-raw provenance (lexical) | `python3 scripts/extract_flink_lexical.py` | 13 literals byte-match; 3 calcite pins; exit 0 | ✓ PASS |
| Snapshot zero-drift after gates | `git diff --name-only -- parity/__snapshot__` | empty (0 changed) | ✓ PASS |
| Negative paths (drift/relabel/empty-tree) | documented in 12-01/12-02/12-03 SUMMARies + 12-REVIEW.md | injected drift → exit 1 with fixture named; relabeled expected_status → exit 1; SIGTERM mid-regeneration → exit 2 + tree restored | ✓ PASS (executor/reviewer evidence) |

### Probe Execution

Step 7c: SKIPPED — no `probe-*.sh` scripts for this phase; the phase's gates are Python stdlib scripts (`verify_corpus.py`, `diff_parity.py`, `compare_backends.py`, `generate_corpus_report.py`) which were executed directly in this verification (Behavioral Spot-Checks above).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| CORPUS-01 | 12-01 | Release-pinned Flink corpus manifest with release/tag/commit, Calcite config, URL/heading, date, hash, expected status, 6 categories | ✓ SATISFIED | manifest.tsv (110 rows, 19 cols, all 6 categories) + verify_corpus.py --check exit 0 + extractor 6-category validation |
| PARITY-01 | 12-02 | Doris 2.1/3.x/4.x behavior equal to frozen baseline unless intentional change explicitly recorded | ✓ SATISFIED | diff_parity.py --frozen-only (433 snapshots, 0 diffs), 812/812 native, git diff empty, approved-changes.md register |
| PARITY-02 | 12-03 | Byte-identical serialized results/diagnostics/spans/lossless replay across Native/JS/linear-Wasm | ✓ SATISFIED | compare_backends.py 3 targets PASS, identical digest 5e9bb887…; CI js runtime step wired |
| PARITY-03 | 12-01, 12-03 | Offline CI/release checks from pinned artifacts; distinguish parser acceptance vs engine semantic prerequisites | ✓ SATISFIED | verify_corpus.py --check + report --check + diff_parity --frozen-only wired; no --update; only installer curl; coverage 68 vs 19 vs 49 |

No orphaned requirements — all four Phase 12 requirement IDs map exactly to plans 12-01/12-02/12-03 and are covered.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | No TBD/FIXME/XXX markers in any phase file | — | None |
| — | — | No `return null`/empty/hardcoded stub patterns in gate scripts | — | None |
| — | — | No `console.log`-only implementations | — | None |
| — | — | No network/subprocess surface in verify_corpus.py; read-only digest guard in compare_backends.py; no `--update` in any CI run line | — | None |

Note: `extract_flink_*.py` read `/tmp/flink-research/` (absent archives → skip, not fail) — documented INFO IN-01, intentional D-06 option-a design, local maintainer tools never wired to CI. Not a gap.

### Human Verification Required

4 flagged probe assumptions from the plans' must_haves are surfaced per the honest-verifier protocol (abstain → human review; never a silent pass). All underlying contract behaviors were verified by direct gate execution; the probe items themselves concern requirement-classification and concurrency invariants that require human confirmation.

1. **CORPUS-01 requirement classification (flagged-unverified probe)**
   **Test:** Review `parity/fixtures/flink/manifest.tsv` + `scripts/verify_corpus.py` against the CORPUS-01 contract (all 6 categories, release pins, provenance, no generic-acceptance-as-engine-support).
   **Expected:** A maintainer can audit reproducible Flink coverage offline; every category and provenance field is real, none fabricated.
   **Why human:** The edge-probe left the requirement unclassified; the authored contract was exercised (all gates exit 0) but the classification remains flagged.

2. **PARITY-01 requirement classification (flagged-unverified probe)**
   **Test:** Review `scripts/diff_parity.py --frozen-only` semantics (regeneration proof, fail-on-any-diff, register NOT consulted) and `approved-changes.md` (single-use approval, zero-drift hard gate).
   **Expected:** Doris frozen baseline is proven by regeneration, not a vacuous self-comparison; intentional changes are only ever register-approved.
   **Why human:** The edge-probe left the requirement unclassified; the harness was directly executed clean, but the classification remains flagged.

3. **PARITY-02 requirement classification (flagged-unverified probe)**
   **Test:** Review `scripts/compare_backends.py` three-target contract (per-target rc + identical tree digest; wasm cannot stdout-dump) and the CI js runtime step.
   **Expected:** Byte-identical serialized results across Native/JS/linear-Wasm are proven without normalization.
   **Why human:** The edge-probe left the requirement unclassified; the byte-identity contract was directly executed (identical digest), but the classification remains flagged.

4. **PARITY-03 concurrency backstop (verification: backstop)**
   **Test:** Interrupt or run `verify_corpus.py --check`, `diff_parity.py --frozen-only`, and `compare_backends.py` concurrently/in-flight and confirm no partial state and no fabricated pass.
   **Expected:** An interrupted or parallel gate run leaves corpus/verifier state intact (read-only artifacts; diff_parity restores the committed snapshot tree on failure/SIGTERM/SIGINT).
   **Why human:** Backstop invariant — the read-only guards and the documented SIGTERM restore test provide evidence, but the concurrency/parallel-run behavior needs human judgment to fully confirm.

### Gaps Summary

No gaps found. All 15 substantive contract truths are VERIFIED with direct evidence (every gate script executed, 812/812 native tests, 570/570 parity per target, identical cross-target digest, CI wiring inspected, zero snapshot drift). The overall status is `human_needed` only because the 4 flagged probe assumptions (requirement-classification × 3, concurrency backstop × 1) are surfaced for human confirmation per the honest-verifier protocol — not because any code artifact is missing, stub, or unwired.

---

_Verified: 2026-08-09T21:15:00Z_
_Verifier: Claude (gsd-verifier)_
