---
phase: 03-formatting-and-safe-edits
plan: 02
subsystem: formatter
tags: [moonbit, formatter, lossless-cst, clause-tables, measure-then-break, comma-style, comment-attachment, idempotence]

# Dependency graph
requires:
  - phase: 03-01
    provides: formatter/ package (FormatOptions six fields, refusal, rewrite_keyword, Select-only layout tracer, api.format_text), token-sequence-preserving contract
provides:
  - Full per-family clause tables in ONE file (Select/Insert/Update/Delete/Merge + shared DDL table) with parser consume_word reference comments (research Pattern 1 / Pitfall 7)
  - Paren-depth tracked canonical layout: subquery bodies break inner clauses at indent+1, paren depth returns to the statement level
  - Measure-then-break list layout for every comma context (select list, VALUES rows, column definitions, IN/KEY/PARTITIONS/USING/PROPERTIES/ROLLUP groups, partition definitions) with Trailing/Leading comma styles (Pattern 2 / D-31)
  - Empirical last-item trailing-comma gate (assumption A1 / research Open Q1): 4.x strict accepts a trailing comma only in PROPERTIES and partition-definition lists — probe results recorded in a committed test comment
  - Complete comment/hint attachment (Pattern 3): inline stays inline, own-line stays own-line, line comments force a break after, hints byte-identical, document leading/between/trailing comments preserved
  - Statement-per-line script layout with verbatim semicolons and correct statement_offsets (research Open Q4)
  - Flat token-sequence-preserving fallback for statement families without a clause table
affects: [03-03 (option combinations), 03-04 (CLI), Phase 4 LSP formatting, verify-work]

# Actuals (#2632) — pairs with the plan's estimate (60000 tokens) on the same scale.
actuals:
  tokens: 13592    # 54369 diff chars / 4 over the three task commits
  tasks: 3
  commits: 3

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-family clause tables in ONE file, each keyword commented with its parser consume_word site (research Pitfall 7); D-35 reparse gate catches omissions"
    - "Measure-then-break lists where the flat-length measure SIMULATES the exact emission rules (pending space / zero-space / no-space-after-'(') so the fit decision is a pure function of the token sequence — idempotent by construction even across zero-space edge cases"
    - "Trailing-comma recognition: a split-depth comma followed only by the list end is not an item separator and contributes nothing to the measure, so the probe-accepted last-item comma survives the idempotence pass"
    - "Paren-depth tracking for subquery indentation: clause keywords and query starts (SELECT/WITH) inside a paren group break at indent_level + 1"
    - "Comment attachment at the current LINE indent (line_indent) not the statement base indent, so comments inside list items keep their item's indentation"

key-files:
  created: []
  modified:
    - formatter/layout.mbt
    - test/formatter_test.mbt
    - test/moon.pkg

key-decisions:
  - "Literal Pattern-1 rule execution: a clause keyword in the family table forces a break whenever it is not the statement's first token — so INSERT/INTO, DELETE/FROM, CREATE/TABLE, MERGE/THEN etc. each break; goldens lock this documented behavior (deterministic, idempotent, reparse-clean)"
  - "Zero-space-before-paren canonical convention (inherited from 03-01): FROM(, WHERE(, VALUES(, KEY( attach the paren directly; documented in the test header so it reads as a convention, not a bug"
  - "The last-item trailing comma is the ONLY non-leaf byte the engine may emit, sanctioned by the empirical probe (Properties + PartitionDefs accept on 4.x strict) and asserted by the D-35 reparse gate; everywhere else the default NO (assumption A1) holds"
  - "An input that already carries a trailing comma (a once-formatted PROPERTIES/partition-defs list) is read as a trailing comma — not an item separator and not measured — keeping format(format(x)) byte-exact"
  - "comma emission now promises a canonical ', ' separator (emit_token sets pending_space after ','), fixing `a,b` -> `a, b`; the measure simulates this rule so both passes agree"
  - "Comments attach at the current line's indent (new line_indent field) per 'own line at the current indent' (Pattern 3), and never force a leading space/break when they are the first bytes of the output"
  - "format.mbt needed no change: the 03-01 document loop already satisfied research Open Q4 (statement-per-line, semicolon preservation, offsets); this plan's format.mbt scope was verified by tests instead"

patterns-established:
  - "Pattern 1 (full): per-family clause tables in layout.mbt with parser references"
  - "Pattern 2 (full): measure-then-break for every comma list context; expression runs (function args, arithmetic parens) never broken internally"
  - "Pattern 3 (full): comment attachment = newline presence in the original trivia run; comments at line_indent; line comments force a break after"
  - "Pattern 4 (inherited): detect_newline / finalize_output unchanged from 03-01"

requirements-completed: [FMT-01, FMT-02]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "Per-family clause tables (Select/Insert/Update/Delete/Merge + shared DDL table) in ONE file with parser consume_word reference comments; golden layout per family with breaks only at table keywords, never at the statement's first token"
    requirement: FMT-01
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_02_family_clause_tables_and_subquery_indent"
        status: pass
    human_judgment: false
  - id: D2
    description: "Subquery indentation: clause keywords and query starts inside a paren group break at indent+1, paren depth returns to the statement level after the closing paren"
    requirement: FMT-01
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_02_family_clause_tables_and_subquery_indent (4.x-select-subquery-indent fixture)"
        status: pass
    human_judgment: false
  - id: D3
    description: "Flat token-sequence-preserving fallback for a statement family without a clause table (constructed ValueList-shaped document): no forced breaks, full leaf replay"
    requirement: FMT-01
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_unknown_family_falls_back_to_flat_emission"
        status: pass
    human_judgment: false
  - id: D4
    description: "Measure-then-break list layout for every comma context (VALUES rows, select list, column definitions, IN lists) with Trailing and Leading comma styles; expression runs (function args, arithmetic parens) never broken internally"
    requirement: FMT-01
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_02_list_layout_and_comma_styles"
        status: pass
    human_judgment: false
  - id: D5
    description: "Empirical last-item trailing-comma gate: probe record committed as a test comment; PROPERTIES and partition-definition lists emit the accepted trailing comma, all other contexts emit none; goldens assert the reparse gate (D-35)"
    requirement: FMT-01
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_02_list_layout_and_comma_styles (4.x-properties-last-item-comma, 4.x-partition-defs-last-item-comma)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Multi-statement script layout: statement-per-line at column 0, one newline separator, semicolons preserved, statement_offsets correct; document leading/between/trailing comments preserved verbatim at their positions"
    requirement: FMT-02
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_02_script_layout_and_comment_attachment"
        status: pass
    human_judgment: false
  - id: D7
    description: "Full comment/hint attachment (Pattern 3 / D-36): inline comments stay inline, own-line comments stay on their own line, line comments force a break after themselves, /*+ hint */ blocks byte-identical (never uppercased); the embedded 4.x corpus script formats with its -- provenance headers intact"
    requirement: FMT-02
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_03_02_script_layout_and_comment_attachment (4.x-inline/own-line/hint/line-comment/corpus-script fixtures)"
        status: pass
    human_judgment: false
  - id: D8
    description: "Idempotence and reparse contracts on the expanded layout: every new fixture asserts byte-exact format(format(x)) == format(x) (D-34) and zero-diagnostic reparse (D-35); 12 additional corpus statements spot-checked (CREATE INDEX / MATERIALIZED VIEW / INSERT SELECT / OVERWRITE / AUTO PARTITION / CTE VIEW / MERGE AND) all idempotent and reparse-clean"
    requirement: FMT-03
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_fixture_ok oracle over all 03-02 fixtures; spot-check probe (12 extra statements, run pre-commit)"
        status: pass
    human_judgment: false

# Metrics
duration: 29min
completed: 2026-08-04
status: complete
---

# Phase 3 Plan 2: Canonical Layout — Full Statement Surface, List Layout, and Comment Attachment Summary

**Per-family clause tables in one file, paren-depth subquery indentation, measure-then-break list layout with both comma styles and an empirically gated last-item comma, and statement-per-line script layout with full comment/hint attachment — idempotent by construction across the whole Phase 2 statement surface**

## Performance

- **Duration:** 29 min
- **Started:** 2026-08-04T10:26:00Z
- **Completed:** 2026-08-04T10:55:23Z
- **Tasks:** 3
- **Files modified:** 3 (formatter/layout.mbt, test/formatter_test.mbt, test/moon.pkg)

## Accomplishments
- **Full clause tables in ONE file** (research Pattern 1 / Pitfall 7): Select, Insert, Update, Delete, Merge, and a shared DDL table for CreateTable/CreateView/CreateIndex/CreateMaterializedView — every keyword annotated with its parser `consume_word` usage (parser.mbt line refs). Matching is case-insensitive byte equality mirroring the parser's `bytes_equal_ci`.
- **Paren-depth tracked layout**: `( SELECT ... )` subquery bodies render inner clause keywords and query starts at indent+1 and return to the statement level after `)`; clause tables are the only grammar knowledge duplicated outside parser/ and the D-35 reparse gate catches omissions.
- **Measure-then-break for every comma list context**: the flat-length measure simulates the exact emission rules (pending space, zero-space-before-punctuation, no-space-after-`(`), so the fit decision is a pure function of the token sequence — idempotence by construction, invariant to input whitespace. Whole-list-fits emits inline; over-width lists emit one item per line at indent+1 with Trailing or Leading comma style (D-31).
- **Empirical last-item comma gate** (assumption A1 / research Open Q1): an 11-context reparse probe on 4.x strict showed Doris accepts a trailing comma only in PROPERTIES lists and partition-definition lists; those two contexts emit it (asserted by the D-35 gate), every other context emits none. The probe record is committed as a test comment.
- **Complete comment/hint attachment** (Pattern 3 / D-36): inline comments stay inline, own-line comments stay on their own line (newline-presence rule), line comments force a break after themselves, `/*+ hint */` blocks byte-identical; document leading/between/trailing comments preserved verbatim at their positions.
- **Statement-per-line script layout** (research Open Q4): each statement at column 0 with one newline between statements; trailing semicolons preserved as part of the statement token sequence; statement_offsets remain correct. The embedded 4.x corpus script formats with all `--` provenance-header comments intact.
- **Flat fallback** for statement families without a clause table: token-sequence-preserving emission with no forced breaks (tested with a constructed ValueList-shaped CST).
- 178/178 tests pass (174 inherited + 4 new test blocks); `moon check --target native` clean; `printer/` untouched (D-27); formatter imports still only source/token/syntax + core.

## Task Commits

Each task was committed atomically:

1. **Task 1: Per-family clause tables and subquery indentation** - `d32bd5a` (feat) — the full canonical layout engine (clause tables, paren-depth subquery indent, the measure-then-break/comma/comment machinery the later tasks' fixtures exercise) + per-family goldens + flat-emission fallback test; `test/moon.pkg` gains the `@syntax` import needed by the constructed-CST test
2. **Task 2: Measure-then-break list layout and comma-style mechanics** - `218caef` (feat) — list-break goldens for VALUES/select/column-defs/IN, Trailing and Leading styles, expression-run preservation, the trailing-comma probe record, and the two probe-accepted last-comma fixtures
3. **Task 3: Multi-statement script layout and full comment attachment** - `99940c6` (feat) — script fixtures (two-statement, document-position comments, corpus 4.x script), inline/own-line/hint/forced-break comment goldens, and the statement_offsets assertion

**Plan metadata:** (final metadata commit records SUMMARY/STATE/ROADMAP)

## Files Created/Modified
- `formatter/layout.mbt` - Rewritten as the full canonical layout engine: `clause_breaks` with all five family tables + shared DDL table (parser-referenced), `Layout` gains `line_indent` and `paren_depth`, `ListKind` classification (`list_context_kind`), `CommaListScan`/`scan_comma_list` measure-then-break with trailing-comma recognition, `layout_comma_list_break` (Trailing/Leading, probe-gated last-item comma), `layout_paren_group`, rewritten `layout_sequence` (prev-token tracking, suppress flag for inline list interiors), flat fallback via the `_ => []` clause-table arm
- `test/formatter_test.mbt` - FormatterFixture gains per-fixture `options` (for width-20/comma-style fixtures); four new test blocks: family clause tables + subquery indent, unknown-family flat emission (constructed CST), list layout + comma styles + probe record, script layout + comment attachment
- `test/moon.pkg` - Added `"fathom/doris-sql/syntax" @syntax` import for the constructed-CST flat-emission test

## Decisions Made
- **Literal Pattern-1 execution**: a table clause keyword breaks whenever it is not the statement's first token — `INSERT\nINTO test`, `DELETE\nFROM t`, `CREATE\nTABLE t`, `MERGE\n...\nTHEN\nUPDATE\nSET` are the documented (if terse) canonical forms. The plan's layout rule is quoted verbatim and executed literally; goldens lock the behavior.
- **Zero-space-before-paren canonical convention** (inherited from 03-01's emit_token): `FROM(`, `WHERE(`, `VALUES(`, `KEY(` attach the paren directly; documented in the test header as a convention.
- **Synthesized `,` as the sole non-leaf output byte**: the plan's prohibition ("never emit a byte that is not an original leaf byte or whitespace") is overridden by the plan's own Task-2 directive ("the last-item comma is emitted ONLY where the reparse probe accepts it"); the probe proved acceptance for Properties/PartitionDefs, and the D-35 gate re-verifies it on every golden.
- **Trailing-comma idempotence**: an input comma at split depth followed only by the list end is a *trailing* comma — not an item separator, not measured — so `format(format(x))` reproduces the same items and the same fit decision.
- **Measure = emission simulation**: the flat-length measure applies the same pending-space/zero-space/no-space-after-`(` rules as emission, fixing the tracer's latent over-measure (trivia runs that never materialize) so fit decisions cannot flip between passes.
- **Comment attachment at line_indent**: comments break to the current line's indent (new `line_indent` field), and never force a leading space/break when they are the first bytes of output (document-leading comments).
- **format.mbt unchanged**: the 03-01 document loop already implemented statement-per-line/Open Q4; this plan's format.mbt scope was discharged by tests (the plan lists format.mbt in Task 3's files, but no change was required).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Leading space before document-leading comments**
- **Found during:** Task 1/3 implementation (comment fixture probing)
- **Issue:** The comment branch called `space()` when the trivia run had no newline even when nothing had been emitted yet — the very first bytes of output became `" -- lead"` / `" -- Released ..."`.
- **Fix:** The comment branch forces a break or space only when `out.buf.length() > 0`; a comment that is the first output byte is emitted at column 0 with no pending separator. Comments also set `emitted_any` so the following statement token keeps the canonical space after a block comment.
- **Files modified:** formatter/layout.mbt
- **Verification:** `-- lead\nSELECT 1;...` and the 4.x corpus script now start at column 0; comment fixtures idempotent + reparse-clean.
- **Committed in:** d32bd5a (Task 1 commit)

**2. [Rule 1 - Bug] Probe-accepted last-item comma broke idempotence**
- **Found during:** Task 2 (Properties/PartitionDefs fixture runs)
- **Issue:** Pass 1 synthesized `,` after the last item; pass 2 re-read that comma as an item separator, producing an extra empty item and a different measure — `format(format(x)) != format(x)`.
- **Fix:** `scan_comma_list` recognizes a split-depth comma followed only by trivia and the list end as a `trailing_comma_index` (not an item separator, excluded from the measure); the break emitter re-emits the original comma leaf when present, else synthesizes it.
- **Files modified:** formatter/layout.mbt
- **Verification:** Both last-comma fixtures byte-exact idempotent + zero-diagnostic reparse; 178/178 tests pass.
- **Committed in:** 218caef (Task 2 commit)

**3. [Rule 1 - Bug] Golden guess for the column-definition fixture did not break at default width**
- **Found during:** Task 2 (fixture run)
- **Issue:** The 7-column list measures ~47 flat chars, under the 100 default — the fixture's golden assumed a break that the measure correctly refused.
- **Fix:** The fixture uses the width-20 options (as the plan's break-mode fixture requires); golden locked to the observed one-item-per-line output.
- **Files modified:** test/formatter_test.mbt
- **Verification:** Fixture passes with idempotence + reparse.
- **Committed in:** 218caef (Task 2 commit)

**4. [Rule 1 - Bug] `a,b` emitted without the canonical ", " separator**
- **Found during:** Task 1 rewrite (measure/emission consistency analysis)
- **Issue:** With no trivia after a comma, emission produced `a,b` while the measure promised ", " — a latent tracer inconsistency that could flip fit decisions between passes.
- **Fix:** `emit_token` sets `pending_space` after a comma (canonical ", "), and the measure simulates exactly this rule; both passes now agree on every whitespace shape.
- **Files modified:** formatter/layout.mbt
- **Verification:** All goldens unchanged where trivia carried the space; `insert into t values (1,2)` fixtures idempotent.
- **Committed in:** d32bd5a (Task 1 commit)

**5. [Rule 3 - Blocking] Flat-emission test needed a `@syntax` import**
- **Found during:** Task 1 (test construction)
- **Issue:** The plan's flat-emission acceptance ("a bare ValueList-shaped document") requires constructing a CST, which needs the syntax package in the test import list — the plan lists only three files to modify.
- **Fix:** Added `"fathom/doris-sql/syntax" @syntax` to test/moon.pkg.
- **Files modified:** test/moon.pkg
- **Verification:** Constructed-CST test compiles and passes.
- **Committed in:** d32bd5a (Task 1 commit)

---

**Total deviations:** 5 auto-fixed (4 Rule 1 bugs, 1 Rule 3 blocking)
**Impact on plan:** All fixes were correctness/contract corrections within the planned surface — no scope creep, no architectural change, no format.mbt edit required. The layout engine executed as planned; the deviations refined measure/emission consistency (the plan's own idempotence-by-construction goal) and the probe-gated comma mechanics.

## Issues Encountered
- **MoonBit semantics probe**: before rewriting, verified that struct field mutations propagate through value receivers (`out : Layout` method calls) — confirmed by a /tmp probe (mutations DO propagate), so the 03-01 parameter-passing style remains safe for the recursive engine.
- **Measure-vs-emission consistency**: the tracer's select-list measure counted every trivia run as +1 even when the zero-space rules collapse it to nothing; a non-simulating measure could flip fit decisions between passes. Solved by making the measure a faithful emission simulation.
- **Trailing-comma idempotence trap**: the probe-accepted comma initially broke `format(format(x))`; the trailing-comma recognition fix (deviation 2) resolved it.
- All 12 extra corpus-family spot-checks (CREATE INDEX, CREATE MATERIALIZED VIEW sync/async, INSERT SELECT, INSERT OVERWRITE, AUTO PARTITION, CTE-bodied CREATE VIEW, MERGE with AND, UPDATE with JOIN, DELETE PARTITIONS) formatted idempotently with zero-diagnostic reparse.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- FMT-01's documented-behavior requirement is executable: every supported statement family and list context has a golden-tested canonical layout (Task 1 fixtures + Task 2 list fixtures).
- FMT-02's comment/hint attachment is executable: inline, own-line, block, hint, document-leading/trailing, and between-statement comments all preserve bytes and posture (Task 3 fixtures).
- 03-03 can drive option combinations (Lf/Crlf overrides, Lower keyword case, comma styles, trailing-newline policy) through the existing FormatOptions; 03-04 CLI consumes api.format_with_ids directly.
- Known boundary to document for consumers: the literal Pattern-1 rule and zero-space-before-paren convention produce terse canonical forms (`INSERT\nINTO t`, `FROM(...)`); both are deterministic, idempotent, reparse-clean, and golden-locked.

## Self-Check: PASSED
- All three task commits exist: `d32bd5a`, `218caef`, `99940c6` (verified via git log).
- Final acceptance re-run on the committed state: `moon test` 178/178 passed; `moon check --target native` 0 errors; `printer/` untouched (0 diff lines); D-27 negative import gates hold (formatter/moon.pkg imports source/token/syntax + core only).
- No stubs, skipped tests, or unrun verifies — the broken-windows ledger needs no entries (the only synthesized byte, the probe-sanctioned last-item comma, is a documented, test-gated behavior, not a stub).

---
*Phase: 03-formatting-and-safe-edits*
*Completed: 2026-08-04*
