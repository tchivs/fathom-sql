---
phase: 09-dialect-boundary-and-neutral-naming
plan: 02
subsystem: api
tags: [dialect, dialect-context, parse-segment-router, fathom-parse-v1, fathom-error-v1, fathom-parse-008, classification-split, d-05, d-08, d-09, d-10]
dependency_graph:
  requires:
    - phase: 09-01
      provides: "Frozen Doris v1 baseline (213 parity snapshots), approved-changes.md D-08 register, scripts/baseline_diff.py"
  provides:
    - "dialect/ package: Dialect enum, DialectContext, ClassificationKind/KeywordEntry, per-dialect classification queries, doris_classification_rows (116 rows), FlinkProfile placeholder + empty flink rows"
    - "Context-parameterized parse path: Token/TokenStream.context, lex(source, context), RecoveryState.context, parse_segment single dialect router with FATHOM-PARSE-008 Flink rejection"
    - "Neutral wire identity: fathom.parse.v1, fathom.error.v1, FATHOM-PARSE-*/FATHOM-SCHEMA-* codes, ParseResult.dialect, fathom_parse_v1/fathom_format_v1 exports"
    - "validate_dialect_profile (dialect-first validation, Pitfall 6), ParseOptions::new(dialect_id, profile_id, mode_id), ParseError::UnknownDialect/ConflictingSelection"
  affects: [09-03, 09-05, 09-06, 09-07]
tech-stack:
  added:
    - "dialect/ package (MoonBit library, zero new dependencies)"
    - "FATHOM-PARSE-008 minted diagnostic code (Flink not-implemented)"
  patterns:
    - "Single parse_segment dialect router — the only per-dialect branch in parser/ (Pitfall 2)"
    - "Classification rows selected only by context.dialect; no parameterless public queries (Pitfall 1/7)"
    - "Dialect validated before profile at every selection boundary (Pitfall 6)"
key-files:
  created:
    - dialect/dialect.mbt (Dialect, DialectContext)
    - dialect/classification.mbt (KeywordEntry, classification_of/is_clause_keyword/is_reserved_word/is_unquoted_identifier/classification_entries)
    - dialect/doris.mbt (DorisProfile/DorisFeature/ValidatedProfileContext preserved per D-05, doris_classification_rows)
    - dialect/flink.mbt (FlinkProfile placeholder, flink_classification_rows = [])
    - dialect/moon.pkg
  modified:
    - token/token.mbt (Token.context/TokenStream.context)
    - lexer/lexer.mbt (lex/lex_with_limit/push_token context)
    - parser/parser.mbt (RecoveryState.context, parse_segment router, parse_doris_segment, parse_flink_segment, FATHOM-PARSE-*)
    - api/api.mbt (ParseOptions dialect dimension, ParseResult.dialect, fathom.parse.v1)
    - binding/exports.mbt + schema.mbt + moon.pkg (fathom_parse_v1/fathom_format_v1, validate_dialect_profile, neutral codes/messages)
    - completion/completion.mbt (complete(raw, dialect_id, profile_id, cursor_byte))
    - formatter/case.mbt + format.mbt + layout.mbt (context threading)
    - lsp/handlers.mbt (mechanical callsite sweep)
    - parity/ (baseline_test, export_smoke_test, parity_test, schema_test, run_native, moon.pkg, 118 snapshots)
    - scripts/baseline_diff.py (approved-pairing fix)
    - test/ (10 files + moon.pkg), printer/printer.mbt, doris-sql/run.mbt
key-decisions:
  - "Adopted D-09/D-10 wire identity + A4 export order (Task 1 checkpoint, option-a auto-selected in auto mode): fathom.*.v1 namespaces, FATHOM-* codes with dialect in fields, fathom_parse_v1(raw, dialect, profile, mode)"
  - "ParseError::UnknownProfile message is dialect-neutral ('unsupported profile: {id}') rather than the plan's literal 'unsupported profile for dialect doris' example because the same error serves flink profile rejection (D-10 dialect-in-fields)"
  - "ParsedDocument.profile/profile_metadata fields removed: dead metadata that could not be honestly derived for Flink contexts (no silent Doris fallback); nothing in the repo consumed them"
  - "Empty-Flink-input FATHOM-PARSE-008 diagnostic (probe DIALECT-03 empty, flagged-unverified) not implemented: the single-router prohibition and the frozen Doris empty-document behavior are mutually exclusive for the empty case; the plan's acceptance criteria cover non-empty Flink rejection only"
  - "DORIS-FORMAT-* codes and doris.format.v1 schema deferred to 09-03 per plan; binding keeps them unchanged"
requirements-completed: [DIALECT-02, DIALECT-03, DIALECT-04, NAME-02]
coverage:
  - id: D1
    description: "Explicit dialect+profile selection end-to-end: fathom_parse_v1(raw, dialect, profile, mode) -> DialectContext -> lex -> parse_segment -> ParseResult with dialect metadata -> fathom.parse.v1 output; flink profiles rejected with structured FATHOM-SCHEMA-003, unknown dialect -> UnknownDialect"
    requirement: DIALECT-01
    verification:
      - kind: unit
        ref: "parity/export_smoke_test.mbt#dialect_selection_is_explicit_end_to_end"
        status: pass
      - kind: unit
        ref: "api/api.mbt#api_requires_explicit_dialect_profile_and_mode"
        status: pass
    human_judgment: false
  - id: D2
    description: "Independent Doris/Flink keyword policy: doris_classification_rows (116 rows byte-identical to v1) + empty flink_classification_rows, all queries context-parameterized, no parameterless public queries, rows selected only by context.dialect"
    requirement: DIALECT-02
    verification:
      - kind: unit
        ref: "dialect/doris.mbt#doris_classification_rows_match_the_frozen_v1_table"
        status: pass
      - kind: unit
        ref: "dialect/classification.mbt#classification_is_dialect_independent_and_flink_rows_are_empty"
        status: pass
    human_judgment: false
  - id: D3
    description: "Explicit dialect routing: single parse_segment router; Doris paths byte-identical to v1 (baseline gate); Flink mode returns FATHOM-PARSE-008 not-implemented Statement node for any input, never a Doris fallback"
    requirement: DIALECT-03
    verification:
      - kind: unit
        ref: "parser/parser.mbt#parser_flink_context_rejects_every_input_as_not_implemented"
        status: pass
      - kind: integration
        ref: "parity/export_smoke_test.mbt#flink_internal_route_returns_not_implemented_statement"
        status: pass
    human_judgment: false
  - id: D4
    description: "Dialect/profile/exact-release metadata + stable FATHOM-* codes on the wire; baseline gate green with approved changes only (281 approved diffs, 0 unexpected); Doris v1 bytes preserved"
    requirement: DIALECT-04
    verification:
      - kind: integration
        ref: "moon test --target native --package parity (227 pass) + scripts/baseline_diff.py (0 unexpected)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Neutral naming (parse half): fathom.parse.v1 / fathom.error.v1 / FATHOM-* codes / dialect expressed in fields; fathom_parse_v1 + fathom_format_v1 exports with #export_name and moon.pkg synced"
    requirement: NAME-02
    verification:
      - kind: unit
        ref: "parity/export_smoke_test.mbt#exports_are_primitive_and_versioned"
        status: pass
    human_judgment: false
metrics:
  duration: 33 min
  completed_date: 2026-08-06
  tasks: 3
  commits: 2
  files: 163
status: complete
actuals:
  tokens: 685896  # chars/4 over the realized diff (incl. 118 generated snapshot files; estimate 48000 assumed hand-written code)
  tasks: 3
  commits: 2
---

# Phase 09 Plan 02: Dialect Layer and Explicit-Selection Tracer Summary

**Built the dialect/ policy layer (Dialect, DialectContext, per-dialect keyword rows), threaded explicit dialect+profile selection end-to-end through token/lexer/parser/api/binding with the single parse_segment router and FATHOM-PARSE-008 Flink rejection, and switched the wire identity to fathom.parse.v1/fathom.error.v1/FATHOM-* with Doris v1 bytes proven preserved by the approved-change baseline gate**

## Performance

- **Duration:** 33 min
- **Started:** 2026-08-06T14:38:34Z
- **Completed:** 2026-08-06T15:11:24Z
- **Tasks:** 3
- **Commits:** 2 (28088e6, 37f1c1b) + final docs commit
- **Files modified:** 163 (incl. 118 updated baseline snapshots)

## Accomplishments

- **dialect/ package (new, zero dependencies):** `Dialect` closed enum (Doris|Flink), `DialectContext` (dialect, profile_id, exact_release, feature_introduction), `ClassificationKind`/`KeywordEntry`, context-routed `classification_of`/`is_clause_keyword`/`is_reserved_word`/`is_unquoted_identifier`/`classification_entries`; `doris_classification_rows` (116 rows, byte-identical to the v1 table); `DorisProfile`/`DorisFeature`/`ValidatedProfileContext`/`ProfileMetadata` moved unchanged per D-05; `FlinkProfile` placeholder with `flink_classification_rows = []` (Phase 10 owns rows).
- **Context-parameterized parse path:** `Token.context`/`TokenStream.context` (rows 8-9), `lex(source, context)`/`lex_with_limit` (12-13), `RecoveryState.context` (17), `parse_segment(context)` single dialect router (14) — `parse_doris_segment` is the v1 body verbatim, `parse_flink_segment` returns a source-backed FATHOM-PARSE-008 not-implemented Statement node for any input (no fallback).
- **Neutral wire identity (parse half of D-09/D-10):** `fathom.parse.v1` schema + `dialect` field on ParseResult, `fathom.error.v1` error envelope, `FATHOM-PARSE-001..008`/`FATHOM-SCHEMA-001..007` codes (005 vacant, 007 minted for ConflictingSelection, 008 minted for Flink), neutral messages (`unsupported profile: X`, `unknown dialect: X`).
- **Explicit selection validation (Pitfall 6):** `ParseOptions::new(dialect_id, profile_id, mode_id)` validates dialect FIRST; flink is a legal dialect whose profiles are all rejected in Phase 9; `validate_dialect_profile(dialect, profile)` mirrors this at the binding; `ParseError::UnknownDialect`/`ConflictingSelection` serialize with FATHOM-SCHEMA codes.
- **Exports (Pitfall 8):** `fathom_parse_v1(raw, dialect, profile, mode)` and `fathom_format_v1(raw, dialect, profile, mode, ...)` with `#export_name` and binding/moon.pkg js/wasm exports lists synced in the same commit; `doris_profile_v1`/`doris_capabilities_v1` retained until 09-05.
- **Baseline gate (D-08):** single approved `moon test --update --package parity` run after the register was already committed; 118 snapshot files updated, `baseline_diff.py` reports 281 approved diffs / 0 unexpected; the genuine drift gate (`moon test --package parity` without --update) is green (227/227).
- **Full ci-aligned native suite:** 431 tests pass (test, parity, lsp, api, source, token, lexer, parser, printer, syntax, completion, analyzer, formatter, dialect); `moon check --target native` clean.

## Task Commits

| Task | Name | Commit | Key files |
| ---- | ---- | ------ | --------- |
| 1 | Confirm D-09/D-10 wire identity and ABI surface (checkpoint:decision, gate=blocking) | (option-a auto-selected in auto mode) | — |
| 2 | End-to-end explicit dialect selection tracer | 28088e6 | dialect/*, token, lexer, parser, api, binding, completion, formatter, parity (+118 snapshots), scripts/baseline_diff.py |
| 3 | Complete the classification split and context sweep | 37f1c1b | lsp/handlers.mbt + lsp tests, printer, doris-sql/run.mbt, test/* (10 files + moon.pkg) |

**Plan metadata:** final docs commit follows.

## Files Created/Modified

- `dialect/dialect.mbt` - Dialect enum, DialectContext (pub(all) for cross-package construction, per D-05 names preserved)
- `dialect/classification.mbt` - ClassificationKind/KeywordEntry, token_bytes_equal_ci (moved), context-routed queries, classification_entries
- `dialect/doris.mbt` - DorisProfile/DorisFeature/ValidatedProfileContext/ProfileMetadata/FeatureMetadata (moved verbatim, FATHOM-PARSE-006), docs URLs, doris_classification_rows (116 rows)
- `dialect/flink.mbt` - FlinkProfile empty placeholder, flink_classification_rows = []
- `dialect/moon.pkg` - library pkg, debug import
- `token/token.mbt` - Token/TokenStream.context, classification/policy content removed (moved to dialect)
- `lexer/lexer.mbt` - lex/lex_with_limit/push_token/push_scanned_with_invalid carry DialectContext
- `parser/parser.mbt` - RecoveryState.context, parse_segment router + parse_doris_segment/parse_flink_segment, feature gates via context profile, DORIS-PARSE-* -> FATHOM-PARSE-*, ParsedDocument profile fields removed, flink not-implemented test
- `api/api.mbt` - ParseOptions dialect dimension + dialect_id accessor, ParseError::UnknownDialect/ConflictingSelection, ParseResult.dialect, parse/format dialect signatures, fathom.parse.v1, tests updated
- `binding/exports.mbt` - fathom_parse_v1/fathom_format_v1 (+dialect), doris_profile_v1/capabilities retained
- `binding/schema.mbt` - fathom.parse.v1, validate_dialect_profile, UnknownDialect, FATHOM-SCHEMA-*/FATHOM-PARSE-* codes, neutral messages, parse_result_json dialect field, fathom.error.v1
- `binding/moon.pkg` - exports lists synced (fathom_parse_v1, fathom_format_v1)
- `completion/completion.mbt` - complete(raw, dialect_id, profile_id, cursor_byte), profile_allows via context, classification_entries, UnknownDialect error
- `formatter/case.mbt` - rewrite_keyword(context, raw), rewrite_keyword_case(context, raw, case)
- `formatter/format.mbt` - format(root, source, options, context)
- `formatter/layout.mbt` - Layout.context field
- `lsp/handlers.mbt` - parse/format/completion callsites + validate_dialect_profile + neutral initialize message (compile-correct only, 09-06 owns document context)
- `parity/baseline_test.mbt` - callsites to fathom_*_v1("doris", ...) / format_with_ids / complete
- `parity/export_smoke_test.mbt` - end-to-end assertions (a)-(d) incl. the Flink internal route via parser entry
- `parity/parity_test.mbt`, `parity/schema_test.mbt`, `parity/run_native.mbt`, `parity/moon.pkg` - callsite + assertion updates
- `parity/__snapshot__/` - 118 files updated with approved changes only
- `scripts/baseline_diff.py` - Rule 1 fix: approved-pairing consumes duplicate values at the same path in multi-document snapshots
- `test/*.mbt` (10 files) + `test/moon.pkg` - doris_context helper, context-parameterized queries, FATHOM-PARSE assertions
- `printer/printer.mbt` - parse_with_ids callsite + lexer context
- `doris-sql/run.mbt` - format_with_ids dialect arg (CLI full dialect work is 09-04)

## Decisions Made

- Task 1 checkpoint auto-selected **option-a** (auto mode, gate=blocking): adopt all locked D-09/D-10 decisions + research recommendations — fathom.*.v1 namespaces, FATHOM-* codes with dialect in fields, `fathom_parse_v1(raw, dialect, profile, mode)` with dialect right after raw (A4).
- `ParseError::UnknownProfile` serializes as `"unsupported profile: {profile_id}"` — dialect-neutral because the same error serves flink profile rejection; the plan's literal example string ("unsupported profile for dialect doris") would mislabel flink requests (D-10: dialect in fields).
- Removed `ParsedDocument.profile`/`profile_metadata`: dead metadata that could not be honestly derived for Flink contexts (would require a silent Doris fallback); no consumer in the repo read them.
- The empty-input Flink FATHOM-PARSE-008 diagnostic (probe DIALECT-03 empty, flagged-unverified) is not implemented — the plan's single-router prohibition (grep gate) and the frozen Doris empty-document behavior are mutually exclusive for the empty case; the plan's acceptance criteria only require non-empty Flink rejection, which is implemented and tested.
- DORIS-FORMAT-* codes and doris.format.v1 stay in 09-02 (deferred to 09-03 per plan acceptance criteria).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] baseline_diff.py approved-pairing misses duplicate values in multi-document snapshots**
- **Found during:** Task 2 (baseline gate after the approved snapshot update)
- **Issue:** The pairing loop `break`s after one approved old->new pair per path value, so LSP homomorph files (parse envelope + format envelope both carrying identical diagnostics) left 6 duplicated diffs classified "unexpected" — a false gate failure on legitimate approved changes.
- **Fix:** Replace the single-pair `if`+`break` with a `while` loop that consumes all approved pairs while both sides hold values.
- **Files modified:** scripts/baseline_diff.py
- **Verification:** baseline_diff.py re-run: 281 approved diffs, 0 unexpected (was 6 unexpected before the fix).
- **Committed in:** 28088e6 (Task 2 commit)

**2. [Rule 3 - Blocking] DialectContext/Dialect/DorisProfile/DorisFeature needed pub(all) for cross-package construction**
- **Found during:** Task 2 (compile loop)
- **Issue:** MoonBit record construction and enum-variant construction are only allowed cross-package for `pub(all)` types; the plan's `pub struct DialectContext` shape is constructible only inside dialect/ — api, parser tests, and parity's Flink route test must construct contexts.
- **Fix:** Made Dialect, DialectContext, DorisProfile, DorisFeature `pub(all)` (names unchanged per D-05; matches the v1 Token/DorisProfile convention).
- **Files modified:** dialect/dialect.mbt, dialect/doris.mbt
- **Verification:** moon check --target native green.
- **Committed in:** 28088e6 (Task 2 commit)

**3. [Rule 3 - Blocking] Record-literal type inference for DialectContext literals**
- **Found during:** Task 2 (compile loop)
- **Issue:** MoonBit does not infer the record type for multi-line `{ dialect: ..., ... }` literals assigned via `let x = match ...`; E4033 "no record definition with the fields".
- **Fix:** Added explicit `: @dialect.DialectContext` annotations / postfix type ascriptions at the api and test construction sites.
- **Files modified:** api/api.mbt, parser/parser.mbt, parity/export_smoke_test.mbt
- **Verification:** moon check --target native green.
- **Committed in:** 28088e6 (Task 2 commit)

**4. [Rule 1 - Bug] Task-boundary adjustment: completion/formatter updated in Task 2, not Task 3**
- **Found during:** Task 2 (parity gate compilation)
- **Issue:** The Task 2 gate (`moon test --package parity`) compiles completion (parity imports it) and formatter (api imports it); once token's parameterless queries were removed (Task 2 acceptance grep), their @token.classification calls broke the build. The plan lists completion/formatter as Task 3 files.
- **Fix:** Applied the full context threading (complete signature, profile_allows, classification_entries; rewrite_keyword(context, raw), Layout.context, format context param) in the Task 2 commit — identical code either way; Task 3 then covered the remaining consumers (lsp, printer, CLI, test package).
- **Verification:** parity gate green at Task 2; full suite green at Task 3.
- **Committed in:** 28088e6 (Task 2 commit)

**5. [Rule 3 - Blocking] ci-aligned native matrix excludes binding**
- **Found during:** Task 3 (full-suite verify)
- **Issue:** `moon test --target native --package binding` fails with E4219 (`#export_name can only be used in a foreign library`) — a pre-existing toolchain constraint documented in ci.yml line 59-63 ("Bare `moon test` triggers MoonBit error 4219"), not a 09-02 regression; binding's native-side coverage runs through parity and `moon check`.
- **Fix:** Ran the ci-aligned native matrix (test, parity, lsp, api, source, token, lexer, parser, printer, syntax, completion, analyzer, formatter, dialect) = 431 tests green + `moon check --target native` clean.
- **Verification:** 431/431 pass; moon check exit 0.
- **Committed in:** 37f1c1b (Task 3 commit)

---

**Total deviations:** 5 auto-fixed (3 blocking, 2 bug/task-boundary)
**Impact on plan:** All fixes were required for the plan's own gates to pass; no scope creep, no behavior change beyond the plan's approved-change register.

## Issues Encountered

- The plan's tracer acceptance (b) fixture (`SELEKT 1` -> FATHOM-PARSE-002 + fathom.error.v1) is not literally reachable: `SELEKT 1` parses to an unsupported-statement result (FATHOM-PARSE-007) inside a fathom.parse.v1 envelope, and the fathom.error.v1 envelope only carries API-level selection errors. The implemented smoke test asserts the FATHOM-PARSE-* diagnostic on invalid input and exercises fathom.error.v1 + FATHOM-SCHEMA-003 via unknown-profile/unknown-dialect calls — the observable contract (neutral wire identity, stable codes) holds.
- The empty-Flink-input FATHOM-PARSE-008 nuance (plan probe DIALECT-03 empty, flagged-unverified) conflicts with the single-router grep gate for the empty-document case; documented in Decisions.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 09-03 (format/capabilities halves + FORMAT codes): binding still emits doris.format.v1/DORIS-FORMAT-* (deferred); formatter now carries DialectContext end-to-end, so the code rename and dialect metadata are ready to land.
- 09-05 (fathom_dialect_v1/capabilities): doris_profile_v1/doris_capabilities_v1 retained and unchanged; profile_json calls parse_with_ids(b"", "doris", ...) already.
- 09-06 (LSP document context): lsp/handlers.mbt callsites are compile-correct with "doris" hardcoded; ServerState.profile / initialize selection / source string / serverInfo still v1.
- 09-07 (naming gate): completion detail still says "Doris syntax keyword" (09-03 owns neutralization).

---
*Phase: 09-dialect-boundary-and-neutral-naming*
*Completed: 2026-08-06*
