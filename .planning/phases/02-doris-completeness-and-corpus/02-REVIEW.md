---
phase: 02-doris-completeness-and-corpus
reviewed: 2026-08-04T00:00:00Z
depth: standard
files_reviewed: 24
files_reviewed_list:
  - parser/parser.mbt
  - token/token.mbt
  - lexer/lexer.mbt
  - syntax/syntax.mbt
  - api/api.mbt
  - analyzer/analyzer.mbt
  - test/analyzer_test.mbt
  - test/corpus_test.mbt
  - test/ddl_test.mbt
  - test/dml_test.mbt
  - test/keyword_test.mbt
  - test/parser_test.mbt
  - test/recovery_test.mbt
  - corpus/tools/check_keywords.py
  - corpus/tools/generate_corpus_report.py
  - corpus/tools/sqlglot_diff.py
  - corpus/tools/fe_nereids_diff.sh
  - corpus/manifest.tsv
  - corpus/coverage.tsv
  - corpus/differential.tsv
  - corpus/keywords.tsv
  - corpus/tools/README.md
  - corpus/requirements.txt
  - corpus/doris-{2.1,3.x,4.x}/*.sql (28 fixture files)
findings:
  critical: 0
  warning: 0
  info: 6
  total: 6
status: clean
---

# Phase 2: Code Review Report

**Reviewed:** 2026-08-04
**Depth:** standard
**Files Reviewed:** 24 (plus 28 corpus fixtures)
**Status:** clean — CR-01/WR-01/WR-02 fixed (see Resolutions); only Info findings remain open.

## Summary

Reviewed the Phase 02 changes: keyword-first statement dispatch with new
INSERT/UPDATE/DELETE/MERGE parsers, the CREATE TABLE/VIEW/INDEX/MATERIALIZED
VIEW family, the data-driven three-layer keyword classification table, the
new analyzer package, and the corpus/tooling wave (manifest/coverage/
differential/keywords TSVs, Python generators, FE differential script).

Verification performed:
- `moon test` on the reviewed tree: **163/163 tests pass**.
- `python3 corpus/tools/generate_corpus_report.py --check`: passes (report
  byte-current, one-fixture-one-row invariant holds, no compatibility claims).
- `python3 corpus/tools/check_keywords.py corpus/keywords.tsv`: passes
  (116 rows, all 62 production words covered).
- `sqlglot_diff.py` regeneration in a scratch copy: deterministic, idempotent,
  byte-identical rows; every row `advisory_only=true`; `fe_nereids_observation`
  preserved; sqlglot 30.14.0 matches the pinned version.
- Adversarial reproductions in a scratch copy of the repo (no source changes
  to the reviewed tree): one **Critical** native stack-overflow crash and two
  **Warning** correctness defects confirmed.

Overall the phase is high quality: limits are enforced on the recovery loops
(max_recovery_steps consumed per token), statement-level recovery is bounded,
the corpus artifacts are honest (unavailable-offline provenance markers,
no fabricated revisions, advisory-only differential), and the classification
table/TSV parity is test-enforced. The findings below are the defects that
survived adversarial review.

## Critical Issues

### CR-01: Unbounded recursion in `parse_type_params` — native stack overflow (SIGSEGV) on untrusted SQL

**File:** `parser/parser.mbt:2671-2680` (recursion), entry `parse_column_type` at `parser/parser.mbt:2633`
**Issue:** `parse_type_params` recurses without any depth guard: after an
identifier it re-enters itself for a nested `( ... )` (line 2671-2674) or
`< ... >` (line 2675-2680). There is no `depth` parameter, no
`depth_allowed`/`parenthesis_depth` check (and generic `<` brackets never
register in `parenthesis_depth` at all), so neither `max_recursion_depth`
(default 128) nor any other limit binds this recursion. An adversarial input
that is well within the default `ParserLimits` (max_bytes 8 MiB, max_tokens
1,000,000) crashes the native parser process:

```sql
CREATE TABLE t (c ARRAY<ARRAY<ARRAY< ... ARRAY<INT> ... >>>)
```

Reproduced in a scratch copy of the repo: a ~100k-deep chain (~1.4 MB,
~600k tokens — under both default limits) makes the native test executable
exit with **signal 11 (SIGSEGV)** — stack overflow. The same input at ~70k
depth is silently *accepted as valid*. The `DECIMAL(DECIMAL(...))` paren
chain is unbounded in the same way (smaller frames, crashes at higher depth).
This violates the phase's explicit security requirement ("no stack overflow
risk from deep nesting in new clause parsers") and the ParseLimits contract
that `max_recursion_depth` bounds all parser recursion. A parser SDK whose
declared contract is bounded resource use on untrusted SQL must not crash.

**Fix:** Thread a `depth : Int` through `parse_type_params` (mirroring
`parse_expression_context`) and bail before recursing when
`depth > state.limits.max_recursion_depth` (emitting the DORIS-PARSE-004
resource diagnostic, or returning false with the existing `depth_allowed`
pattern). Apply the same guard to the `(` and `<` recursion sites:

**Resolution:** fixed in commit `c288f44` (`fix(02-01)`) — `depth : Int` threaded
through `parse_type_params` with the `depth > max_recursion_depth` guard at entry,
bounded for both `( ... )` and `< ... >` recursion. Regression test
`create_table_deep_generic_nesting_stays_bounded` (140 levels fail with
DORIS-PARSE-004; 100 levels still parse; custom limit 2 fails at 4 nested levels).
The ~100k-deep crash input now terminates with a single DORIS-PARSE-004 instead of
SIGSEGV.

```moonbit
fn parse_type_params(
  cursor : Cursor,
  state : RecoveryState,
  source : @source.SourceText,
  statement_id : UInt,
  depth : Int,
) -> Bool {
  ...
  Some(_) if is_identifier_candidate(cursor) => {
    any = true
    advance(cursor)
    if consume_symbol(cursor, b"(") {
      if depth >= state.limits.max_recursion_depth {
        resource_diagnostic(state, current_span, statement_id)
        valid = false
      } else {
        valid = parse_type_params(cursor, state, source, statement_id, depth + 1) && valid
      }
      valid = expect_symbol(cursor, b")", ...) && valid
    }
    ...
  }
```

## Warnings

### WR-01: Bare `CREATE` (and `CREATE TEMPORARY` / `CREATE EXTERNAL`) is accepted as a valid statement with zero diagnostics

**File:** `parser/parser.mbt:1902` (`None => ()` arm of the `raw_at` match in `parse_create`)
**Issue:** When the input ends right after the CREATE verb (or after a
TEMPORARY/EXTERNAL modifier), the match falls into `None => ()` — no
diagnostic is emitted, `valid` stays `true`, and `finish_statement` produces
a `CreateTable` node with no error. Reproduced: `parse(b"CREATE", "4.x",
"strict")` → `valid = true`, `diagnostics.length() == 0`; same for
`CREATE TEMPORARY` and `CREATE EXTERNAL`. (The `;`-terminated form
`CREATE; SELECT 1` is correctly flagged, which makes the bare-EOF behavior
an inconsistency, not a design choice.) An incomplete statement silently
passing the `valid` gate corrupts the SDK's core diagnostic promise for
editors and CI gates — every other statement family (SELECT, INSERT, UPDATE,
DELETE, MERGE, and `CREATE TABLE`/`VIEW`/`INDEX`) correctly reports
DORIS-PARSE-002 in this situation.

**Fix:** Emit the same diagnostic as the `Some(_)` arm when the statement
ends early:

```moonbit
None => {
  let at = match token_at(cursor) { Some(token) => token.span.start_byte; None => source.byte_length() }
  add_diagnostic(state, "DORIS-PARSE-002", "expected TABLE, VIEW, INDEX, or MATERIALIZED VIEW after CREATE", "create-form", make_span(source, at, at), statement_id)
  valid = false
}
```

**Resolution:** fixed in commit `af05b40` (`fix(02-02)`) — the `None => ()` arm now
emits the same DORIS-PARSE-002 diagnostic and sets `valid = false`; `finish_statement`
pushes the Missing node. Regression test `bare_create_forms_report_incomplete_statement`
covers `CREATE`, `CREATE TEMPORARY`, and `CREATE EXTERNAL` in strict and editor modes.

### WR-02: `parse_type_params` struct-field heuristic silently accepts malformed column types as valid

**File:** `parser/parser.mbt:2686-2689`
**Issue:** The "STRUCT-style field type" branch consumes an arbitrary second
identifier after any type parameter with no grammar context, so malformed
types parse as **valid with zero diagnostics**. Reproduced:
`CREATE TABLE t (c ARRAY<INT FOO>)` and
`CREATE TABLE t (c MAP<STRING, INT EXTRA>)` both return `valid = true`,
`diagnostics.length() == 0`. Doris would reject both; the parser's
"precise diagnostics" core value is undermined, and the acceptance is
silent (no recovery, no error node).

**Fix:** Restrict the extra-identifier consumption to STRUCT field lists
(e.g., only when the enclosing type is STRUCT/STRUCT-style and the token is
followed by a type word or `,`/`)`), or drop the heuristic until STRUCT field
types are modeled explicitly.

**Resolution:** fixed in commit `b5e1605` (`fix(02-03)`) — the field heuristic is
gated on `struct_style`, derived from the enclosing type name (STRUCT, propagated
through nested `< ... >` recursion); non-STRUCT generics no longer consume a second
identifier, so `ARRAY<INT FOO>` and `MAP<STRING, INT EXTRA>` fail with diagnostics
while `STRUCT<a INT, b STRING>` and nested STRUCT lists stay valid. Regression test
`malformed_type_params_report_trailing_garbage`.

## Info

### IN-01: Unknown CREATE forms get a misleading node kind and a double diagnostic

**File:** `parser/parser.mbt:1833-1854` (`create_form_kind`), `parser/parser.mbt:1887-1901` (`parse_create` `Some(_)` arm)
**Issue:** `create_form_kind` defaults to `CreateTable` for any CREATE form it
does not recognize (e.g. `CREATE DATABASE foo` produces a `create_table`
statement node), and `parse_create` adds DORIS-PARSE-002 at the offending
token without consuming it, so `finish_statement` then emits a second
DORIS-PARSE-001 "unexpected tokens" diagnostic for the same defect.
**Fix:** Add an explicit fallback kind (e.g. `Error`) for unrecognized
CREATE forms and consume past the offending tokens in `parse_create`.

### IN-02: Analyzer UTF-8 decoder does not validate continuation bytes

**File:** `analyzer/analyzer.mbt:110-140`
**Issue:** The hand-rolled `utf8_to_string` checks only the lead byte of 3-
and 4-byte sequences and never verifies that the following bytes are
continuation bytes (0x80–0xBF), so malformed sequences would decode to
garbage characters instead of U+FFFD. Today this is unreachable through the
normal parse path because the lexer splits invalid UTF-8 into separate
Error tokens, but the function is a public surface and the defense-in-depth
gap is real if callers ever pass source bytes not produced by the lexer.
**Fix:** Validate `second`/`third`/`fourth` are continuation bytes (and reject
overlong encodings/surrogates), mirroring `lexer.mbt:utf8_width`.

### IN-03: No-op `valid = true && valid` in the EXCEPT-ALL branch

**File:** `parser/parser.mbt:1170`
**Issue:** In `parse_select_core`, the `has_except` + FROM case executes
`valid = true && valid`, which is a literal no-op. It reads as if it should
reset or re-derive validity, but it just preserves the current value. Dead,
misleading code.
**Fix:** Remove the statement (the `else` branch already covers the case), or
replace it with the intended expression.

### IN-04: `feature_events` accumulates across statements in the shared `RecoveryState`

**File:** `parser/parser.mbt:114-121` (`RecoveryState`), `parser/parser.mbt:3458-3464` (`segment_children_for_events` usage in `parse_with_limits_context`)
**Issue:** `feature_events` is never reset between `parse_segment` calls, so
every statement's `segment_children_for_events` scans events recorded by
earlier statements. Exact-span matching makes cross-statement substitution
impossible today (segments are disjoint), but the state leaks across
statements and any future span-sharing refactor (e.g. shared template nodes)
would silently substitute wrong nodes.
**Fix:** Create a fresh events array per statement (pass it into
`finish_statement`), or clear it at the top of each `parse_segment`.

### IN-05: `fe_nereids_diff.sh` has fragile row handling for malformed input

**File:** `corpus/tools/fe_nereids_diff.sh:96-131`
**Issue:** (a) A trailing empty line in `manifest.tsv` would produce an
iteration with empty fields and append a corrupt row (empty `fixture_id`)
to `differential.tsv` — the honesty-critical artifact; (b) `fixture_id` is
interpolated unescaped into a `grep` pattern (safe today: ids are
alphanumeric+dash); (c) `category="${fields[9]}"` couples to the exact
column position, silently producing `not-run-offline` for every row if the
manifest header is ever reordered. Manual-only script, so low impact, but the
failure modes are silent.
**Fix:** Skip lines with fewer than 10 fields, quote/validate `fixture_id`
before matching, and look up `category` by header name.

### IN-06: `is_clause_keyword` hardcodes a word list that duplicates the classification table

**File:** `token/token.mbt:448-465` (approx.)
**Issue:** The shared clause/recovery-boundary predicate is a hand-maintained
byte list while the D-13/D-14 authority is the data-driven
`classification_rows` table. The two are asserted equal only for the
DML/DDL exclusion direction (`dml_keywords_do_not_leak_into_shared_clause_set`);
any future word added to one list without the other silently changes SELECT
recovery boundaries. The D-13 single-source-of-truth claim is only
partially realized.
**Fix:** Derive `is_clause_keyword` from a `clause` classification column
(or a dedicated table-backed set) instead of a second literal list.

---

## Resolutions (gsd-code-fixer)

Applied 2026-08-04; each fix committed atomically with regression tests added to
`test/ddl_test.mbt`. Verified: `moon test` 166/166 pass; `moon check --target native`
0 errors; the ~100k-deep CR-01 crash input (native) terminates with DORIS-PARSE-004
instead of SIGSEGV; lossless round-trip (`print_lossless(parse(x)) == x`) preserved
for all accepted inputs in the suite.

- **CR-01** — fixed in `c288f44` (`fix(02-01)`): `parse_type_params` recursion is
  bounded by a `depth : Int` counter mirroring `parse_expression_context`, emitting
  the DORIS-PARSE-004 resource diagnostic when `depth > max_recursion_depth`; both
  `( ... )` and `< ... >` recursion sites are covered.
- **WR-01** — fixed in `af05b40` (`fix(02-02)`): bare `CREATE` / `CREATE TEMPORARY` /
  `CREATE EXTERNAL` now emit DORIS-PARSE-002 and fail validity; the Missing node is
  pushed by `finish_statement`, matching every other statement family.
- **WR-02** — fixed in `b5e1605` (`fix(02-03)`): the STRUCT-style field heuristic is
  gated on the enclosing type being STRUCT (propagated through nested generics);
  trailing garbage in non-STRUCT type params now produces a diagnostic.

Info findings IN-01..IN-06 remain open (out of scope for this fix pass).

_Reviewed: 2026-08-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Fixed: 2026-08-04_
_Fixer: Claude (gsd-code-fixer)_
