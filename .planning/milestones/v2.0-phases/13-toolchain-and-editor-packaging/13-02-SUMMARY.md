---
phase: 13-toolchain-and-editor-packaging
plan: 02
subsystem: api
tags: [flink, completion, d-02, d-28, classification, profile-gating, boundedness, source-range-edit]

# Dependency graph
requires:
  - phase: 10-flink-release-profiles-and-lexical-core
    provides: FlinkProfile/FlinkProfileMetadata closed enum (flink-1.20.5 < flink-2.1.3 < flink-2.3.0) and the 147-row flink_classification_rows table
  - phase: 11-flink-grammar-and-recoverable-cst
    provides: the Flink parser + grammar snapshots that the NonReserved row extension must leave byte-identical
  - phase: 12-cross-dialect-corpus-and-parity-gates
    provides: parity snapshot namespace discipline and diff_parity.py --frozen-only (D-08)
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: DialectContext/Dialect::Flink, the explicit (dialect, profile) selection contract
provides:
  - complete() Flink branch constructing a real DialectContext via FlinkProfile::from_id + metadata (replaces the Phase-9 all-reject UnknownProfile), unknown profile -> structured UnknownProfile (never Doris fallback)
  - profile_allows Flink arm admitting classification-filtered rows (flink_row_visible gates by introduced_profile)
  - completion_context Flink arms: statement-start verb path, ddl-header, watermark, partitioned-by, window-tvf, match-recognize — Doris context strings unchanged
  - flink_classification_rows extended with 22 provenance-annotated NonReserved rows (statement verbs, DDL nouns, WATERMARK/column-body words, window TVF names)
  - completion/completion_test.mbt Flink unit tests (boundedness, per-profile gating, context arms, source-range edits, unknown-profile rejection)
affects: [13-04 wire surface (fathom_complete_v1), 13-05 LSP/CLI real flink completion, TOOL-02 verifier, Flink completion consumers]

# Actuals (#2632) — pairs with the plan's `estimate` (44000 chars/4) to calibrate future estimates.
actuals:
  tokens: 7968    # chars/4 over the realized diff (31,871 diff chars across the 5 changed files)
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Flink DialectContext construction via @dialect.FlinkProfile::from_id + metadata mirroring api.ParseOptions::new's Flink arm (exact-match, no prefix/suffix, no Doris profile borrowing)
    - Flink-gated completion_context arms placed to preserve Doris context strings byte-identical (window-tvf before the generic from arm, Flink-only)
    - NonReserved candidate-pool extension: D-02 context words added as NonReserved rows (parse-neutral; frozen flink-grammar/flink-lexical snapshots stay byte-identical)

key-files:
  created:
    - completion/completion_test.mbt
  modified:
    - completion/completion.mbt
    - dialect/flink.mbt
    - lsp/completion_test.mbt
    - lsp/selection_test.mbt

key-decisions:
  - "complete() Flink branch mirrors api.ParseOptions::new (api.mbt:92-103): FlinkProfile::from_id exact-match then metadata; an unknown or Doris-shaped profile id (flink-9.9.9, 4.x) returns Err(UnknownProfile) — no fallback, no empty-silent success (D-01/D-02, T-13-02-05)."
  - "profile_allows Flink arm returns true: classification_entries already filters Flink rows by introduced_profile <= selected via flink_row_visible, so the candidate pool is profile-correct with no second gate and no second keyword list (D-02/D-28, T-13-02-04)."
  - "The D-02 context words are added to flink_classification_rows as NonReserved (NOT Reserved) even though several are genuine grammar tokens: a Reserved addition would flip is_unquoted_identifier and move the frozen flink-grammar/flink-lexical snapshots; NonReserved keeps acceptance byte-identical (A2, Pitfall 2) while making the words completion candidates."
  - "COMPUTED/CUMULATE are documented function/column-modifier identifiers absent from every pinned release grammar; their rows carry a source pointing at the sibling construct on the same pinned line with an explicit 'absent from the grammar' note. CONNECTOR (artifacts-list-only, not in the normative must-haves/acceptance) was not added because it has no grammar source and no context arm requires it."
  - "The window-tvf context arm is placed BEFORE the generic from arm (Flink-gated) so FROM/JOIN under Flink yields 'window-tvf' per the plan acceptance; Doris is unaffected because the arm never fires for Doris (T-13-02-07)."

patterns-established:
  - "Pattern: Flink DialectContext at the completion boundary — the complete() Flink arm is the third instance (api ParseOptions::new, parser entry, completion) of constructing the Flink context from the pinned released-profile enum; unknown ids reject structurally."
  - "Pattern: dialect-gated context arms — new completion_context arms key off the dialect parameter so Doris context strings and candidate ordering stay byte-identical while Flink gains ddl-header/watermark/partitioned-by/window-tvf/match-recognize."
  - "Pattern: candidate-pool extension via NonReserved rows — every D-02 context word is a classification row with pinned-release-grammar provenance; completion never holds a second keyword table (D-28)."

requirements-completed: [TOOL-02]

coverage:
  - id: D1
    description: "complete() Flink branch + profile_allows Flink arm — a flink request builds a real DialectContext via FlinkProfile::from_id + metadata; unknown/unsupported flink profiles (flink-9.9.9, Doris-shaped 4.x) reject with structured UnknownProfile; no Doris fallback, no empty-silent success"
    requirement: TOOL-02
    verification:
      - kind: unit
        ref: "completion/completion_test.mbt#flink_unknown_profile_rejects_no_fallback"
        status: pass
      - kind: unit
        ref: "completion/completion_test.mbt#flink_statement_start_returns_verb_set"
        status: pass
    human_judgment: false
  - id: D2
    description: "Flink completion_context arms — statement-start verb path, ddl-header (CREATE/DROP/ALTER -> CATALOG/DATABASE/FUNCTION/TABLE/VIEW), watermark (WATERMARK -> column-body words), partitioned-by (PARTITIONED BY -> clause words), window-tvf (FROM/JOIN -> TUMBLE/HOP/CUMULATE/SESSION), match-recognize (scoped to PATTERN/DEFINE/MEASURES/MATCH_NUMBER); Doris context strings unchanged"
    requirement: TOOL-02
    verification:
      - kind: unit
        ref: "completion/completion_test.mbt#flink_ddl_header_context"
        status: pass
      - kind: unit
        ref: "completion/completion_test.mbt#flink_watermark_partitioned_context"
        status: pass
      - kind: unit
        ref: "completion/completion_test.mbt#flink_window_tvf_context"
        status: pass
      - kind: unit
        ref: "completion/completion_test.mbt#flink_match_recognize_context"
        status: pass
    human_judgment: false
  - id: D3
    description: "Candidate-pool extension — flink_classification_rows extended from 147 to 169 provenance-annotated NonReserved rows (statement verbs ALTER/DROP/SHOW/DESCRIBE/EXPLAIN/ANALYZE/USE/RESET, DDL nouns CATALOG/DATABASE/FUNCTION/VIEW, WATERMARK/PRIMARY/COMPUTED/METADATA/VIRTUAL/ENFORCED, TVF names TUMBLE/HOP/CUMULATE/SESSION); parse-neutral so the frozen flink-grammar/flink-lexical snapshots stay byte-identical; provenance audit test covers the new rows"
    requirement: TOOL-02
    verification:
      - kind: integration
        ref: "dialect/flink.mbt#flink_classification_rows_source_references_release_grammar"
        status: pass
      - kind: other
        ref: "scripts/diff_parity.py --frozen-only (455 snapshots, 0 frozen-vs-current differences)"
        status: pass
      - kind: integration
        ref: "moon test --target native --package completion --package dialect --package parity --package lsp (649 passed)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Flink completion is bounded and safe — MAX_CANDIDATES=32 never exceeded (widest context statement-start on flink-2.3.0), per-profile gating by introduced_profile (QUALIFY absent under 1.20.5, SAFE_CAST absent under 1.20.5/2.1.3) asserted via classification_entries AND completion output, multibyte source-range edits with authoritative UTF-8 byte offsets (start_byte <= cursor <= end_byte, new_text == label), no completion-specific keyword table (D-28)"
    requirement: TOOL-02
    verification:
      - kind: unit
        ref: "completion/completion_test.mbt#flink_boundedness_max_32"
        status: pass
      - kind: unit
        ref: "completion/completion_test.mbt#flink_profile_gating_per_introduced_profile"
        status: pass
      - kind: unit
        ref: "completion/completion_test.mbt#flink_multibyte_source_range_edit"
        status: pass
      - kind: other
        ref: "grep gate: no 'let .*: Array[@dialect.KeywordEntry] = [' in completion/ (D-28)"
        status: pass
    human_judgment: false

# Metrics
duration: 9min
completed: 2026-08-10
status: complete
---

# Phase 13 Plan 02: Flink completion — complete() Flink branch, six context arms, and a 22-row NonReserved candidate-pool extension

**Bounded (<=32), profile-gated Flink syntax completion end-to-end: complete() now builds a real Flink DialectContext (FlinkProfile::from_id + metadata, unknown profile -> UnknownProfile), completion_context gains the six D-02 Flink arms (statement-start/ddl-header/watermark/partitioned-by/window-tvf/match-recognize), and flink_classification_rows grows 22 provenance-annotated NonReserved rows — with Doris output and the frozen flink-grammar/flink-lexical snapshots byte-identical.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-08-10T03:00:00Z (approx, first plan commit 03:03:48 UTC)
- **Completed:** 2026-08-10T03:08:58Z (UTC)
- **Tasks:** 3
- **Files modified:** 5 (3 core + 2 lsp test updates)

## Accomplishments
- **Flink branch in complete() (D-02):** the Phase-9 `@dialect.Dialect::Flink => Err(UnknownProfile)` all-reject arm is replaced with a real Flink branch mirroring `api.ParseOptions::new` (api.mbt:92-103): `FlinkProfile::from_id` exact-match → `metadata()` → DialectContext. `flink-2.3.0/flink-2.1.3/flink-1.20.5` resolve; any other id (including the Doris-shaped `4.x`) returns the structured `UnknownProfile` — never a Doris fallback, never an empty-silent success (T-13-02-05).
- **profile_allows Flink arm (D-02/D-28):** returns `true` because the candidate pool (`classification_entries(flink_context)`) is already filtered by `introduced_profile` via `flink_row_visible` — the per-profile gate is free, with no second keyword list.
- **Six Flink completion_context arms (D-02):** statement-start verbs, ddl-header (CREATE/DROP/ALTER → DDL nouns), watermark, partitioned-by, window-tvf, match-recognize — each flows through the unchanged two-pass priority loop and the MAX_CANDIDATES=32 bound. Doris context strings and candidate ordering are byte-identical (the arms are Flink-gated; the window-tvf arm precedes the generic from arm for Flink only).
- **Candidate-pool extension:** `flink_classification_rows` grows from 147 to 169 rows — statement verbs (ALTER/DROP/SHOW/DESCRIBE/EXPLAIN/ANALYZE/USE/RESET), DDL nouns (CATALOG/DATABASE/FUNCTION/VIEW), WATERMARK/column-body words (PRIMARY/COMPUTED/METADATA/VIRTUAL/ENFORCED), and window TVF names (TUMBLE/HOP/CUMULATE/SESSION), each with pinned-release-grammar provenance (path + line) and `introduced_profile: "flink-1.20.5"`. All NonReserved → parse-neutral; the frozen flink-grammar/flink-lexical snapshots stay byte-identical (A2, Pitfall 2).
- **Flink completion test matrix (11 tests):** boundedness (<=32 on the widest context), per-profile gating (QUALIFY/SAFE_CAST via classification_entries AND completion output), all six context arms, multibyte source-range edits (authoritative UTF-8 bytes, new_text == label), unknown-profile rejection, and a Doris byte-identical pin.

## Task Commits

Each task was committed atomically:

1. **Task 1: Flink branch in complete() + statement-start context + minimal candidate-pool extension end-to-end** - `e767e44` (feat) — Flink branch + profile_allows Flink arm + statement-start context + 22-row NonReserved extension + 4 tracer tests
2. **Task 2: Flink completion_context arms (ddl-header/watermark/partitioned-by/window-tvf/match-recognize) + full candidate-pool extension** - `dcd1904` (feat) — 5 context-arm tests + 2 lsp test updates (stale Phase-9 flink rejection assertions)
3. **Task 3: Boundedness, profile gating, source-range edit, and no-Doris-fallback tests** - `ef1ff26` (test) — boundedness + per-profile gating + multibyte source-range tests

## Files Created/Modified
- `completion/completion.mbt` - complete() Flink branch (FlinkProfile::from_id + metadata, UnknownProfile on unknown), profile_allows Flink arm (true — classification already filters), completion_context gains a dialect parameter + 6 Flink context arms, context_accepts statement-start Flink verb path + 5 new context arms, 6 Flink helper predicates
- `dialect/flink.mbt` - flink_classification_rows extended 147 → 169 with 22 NonReserved D-02 rows (provenance-annotated, introduced_profile flink-1.20.5); provenance audit test covers the new rows unchanged
- `completion/completion_test.mbt` - NEW: 11 Flink completion unit tests (boundedness, per-profile gating, context arms, source-range edits, unknown-profile rejection, Doris output pin)
- `lsp/completion_test.mbt` - flink-mode assertion updated from the Phase-9 UnknownProfile rejection to real candidates with a no-Doris-leak guard + unknown-profile case
- `lsp/selection_test.mbt` - flink document completion assertion updated from -32602 rejection to a real completion list (format -32603 stays; D-07 formatter swap is 13-04)

## Decisions Made
- Complete() Flink branch mirrors `api.ParseOptions::new`'s Flink arm exactly (FlinkProfile::from_id → metadata → DialectContext) — the third in-repo instance of this construction; unknown ids reject structurally (T-10-01 exact-match).
- The candidate pool is `classification_entries(flink_context)` (D-28 single-table discipline); `profile_allows` returns true for Flink because `flink_row_visible` already filtered by introduced_profile in release order.
- D-02 context words are NonReserved rows even where the grammar genuinely reserves them: Reserved additions would change `is_unquoted_identifier` and move the frozen snapshots; NonReserved keeps parse acceptance byte-identical while enabling completion candidates (the sanctioned A2 path).
- The window-tvf arm is placed before the generic from arm (Flink-gated) so FROM/JOIN under Flink yields "window-tvf" per the plan acceptance; Doris ordering is preserved by the dialect gate.
- MATCH_RECOGNIZE completion is scoped to the four reserved clause words already in the table (PATTERN/DEFINE/MEASURES/MATCH_NUMBER); sub-clauses are catalog/scope-bound and deferred (RESEARCH OQ3 RESOLVED, TOOL-FUTURE-01).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] lsp/completion_test.mbt and lsp/selection_test.mbt asserted the Phase-9 flink rejection this plan removes**
- **Found during:** Task 2 (running `moon test --package lsp`, part of the plan's own verification)
- **Issue:** The plan's task-2/3 verification requires `--package lsp` to pass, but `lsp/completion_test.mbt` `completion_is_dialect_aware_with_neutral_detail` asserted `@completion.complete(b"SEL", "flink", "flink-2.3.0", 3)` returns `Err(UnknownProfile)` and `lsp/selection_test.mbt` asserted the flink document completion response contains `-32602`. Both assert the exact Phase-9 behavior this plan intentionally replaces with real Flink completion (D-02). They are NOT Doris assertions (the plan's PARITY-01 constraint only pins the Doris cases).
- **Fix:** Updated the flink assertions to the new contract: flink returns real candidates with the neutral detail and no Doris-word leak (TABLET), an unknown flink profile (`flink-9.9.9`) rejects with `UnknownProfile`, and the LSP flink completion response is a real completion list (`"result"` + `"isIncomplete"`, no `-32602`). The flink format `-32603` assertion in selection_test is untouched (the D-07 formatter swap is 13-04).
- **Files modified:** lsp/completion_test.mbt, lsp/selection_test.mbt
- **Verification:** `moon test --target native --package completion --package dialect --package parity --package lsp` = 649 passed; Doris lsp assertions unchanged.
- **Committed in:** dcd1904 (Task 2 commit)

**2. [Provenance judgment] COMPUTED/CUMULATE rows have no pinned-grammar line — source references the sibling construct**
- **Found during:** Task 1 (candidate-pool extension)
- **Issue:** The plan's must-haves require CUMULATE (window-tvf context) and COMPUTED (column-body context) as completion candidates, and the provenance audit test requires every row's source to reference the pinned release grammar. CUMULATE/COMPUTED are function/column-modifier identifiers absent from every pinned release grammar file (verified against /tmp/flink-research/ Parser-release-*.tdd, Parser-calcite-*.jj, and the extracted keyword lists), so no grammar line exists for them.
- **Fix:** Added both as NonReserved flink-1.20.5 rows with a source that points at the sibling construct on the same pinned line and explicitly notes the word is absent from the grammar (e.g. `Parser-release-1.20.5.tdd:532 (CUMULATE; sibling window TVF of TUMBLE — function-name identifier, absent from the grammar)`). The mechanical provenance audit passes; the note keeps the annotation honest. CONNECTOR (artifacts-list-only, not in the normative must-haves or acceptance criteria) was NOT added because it has no grammar source and no context arm requires it.
- **Files modified:** dialect/flink.mbt
- **Verification:** `dialect/flink.mbt#flink_classification_rows_source_references_release_grammar` passes; diff_parity --frozen-only reports 0 differences.
- **Committed in:** e767e44 (Task 1 commit)

**3. [Placement] window-tvf arm precedes the generic from arm**
- **Found during:** Task 2 (context arms)
- **Issue:** The plan's task-2 action says add arms "AFTER the existing arms", but its own acceptance requires `completion_context` to return "window-tvf" after FROM/JOIN for Flink. Added after the from arm, the window-tvf arm would never fire (the from arm catches FROM/JOIN first).
- **Fix:** Placed the window-tvf arm before the generic from arm, gated on `dialect is Flink` — Doris still hits the from arm unchanged (PARITY-01), and Flink FROM/JOIN yields window-tvf per the acceptance.
- **Files modified:** completion/completion.mbt
- **Verification:** `flink_window_tvf_context` passes (TUMBLE/HOP/CUMULATE/SESSION after FROM); Doris `from` context tests unchanged.
- **Committed in:** e767e44 (Task 1 commit)

---

**Total deviations:** 3 (1 Rule 3 blocking, 2 plan-text vs acceptance/intent alignments)
**Impact on plan:** All deviations are necessary to satisfy the plan's own acceptance criteria and verification gates. No scope creep — no new runtime behavior beyond the D-02 completion contract.

## Issues Encountered
- `moon test --target native` (unscoped full suite) fails on the `binding` package (`#export_name` requires `pkgtype(kind: "foreign_library")` for the native target). This is pre-existing and unrelated to this plan (binding is untouched); the plan's verification commands scope explicitly to `--package completion --package dialect --package parity --package lsp`, all of which pass.
- `MAX_CANDIDATES` is a package-private const, so the blackbox `completion_test.mbt` pins the observable bound as the literal `32` with a comment (the const is not part of the public API surface).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The Flink completion core (branch + context arms + candidate pool) is the foundation for 13-04's `fathom_complete_v1` wire export and 13-05's LSP/CLI real flink completion.
- The LSP flink completion path now returns real results through the existing `completion_result` handler (the -32602 mapping remains only for genuine request errors); 13-05 removes the format -32603 sentinel.
- Frozen Doris baseline (213) and flink-grammar/flink-lexical snapshots remain byte-identical (455 snapshots, 0 drift); `--update` stays excluded from CI.

---
*Phase: 13-toolchain-and-editor-packaging*
*Completed: 2026-08-10*

## Self-Check: PASSED
- Files verified: completion/completion.mbt, completion/completion_test.mbt, dialect/flink.mbt, lsp/completion_test.mbt, lsp/selection_test.mbt.
- Commits verified: e767e44 (Task 1), dcd1904 (Task 2), ef1ff26 (Task 3).
- Gates: moon test --target native --package completion --package dialect --package parity --package lsp = 649 passed (no --update); scripts/diff_parity.py --frozen-only = 455 snapshots, 0 differences; scripts/check_naming.py clean; grep gate confirms no completion-specific keyword table.
