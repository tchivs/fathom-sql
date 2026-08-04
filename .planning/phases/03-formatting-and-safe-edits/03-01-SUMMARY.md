---
phase: 03-formatting-and-safe-edits
plan: 01
subsystem: api
tags: [moonbit, formatter, lossless-cst, idempotence, keyword-case]

# Dependency graph
requires:
  - phase: 02-doris-completeness-and-corpus
    provides: lossless CST (syntax/), keyword classification table (token/), ParseOptions/ParseError/PrimitiveDiagnostic api shapes
provides:
  - formatter/ package: FormatOptions (six locked fields + defaults), FormatError/FormatDiagnostic/FormatResult, first_unsafe_element refusal, rewrite_keyword, layout engine, format entry
  - api.format_text / format_with_ids / format_with_metadata shared core entry (D-38) with parse diagnostics prepended
  - DORIS-FORMAT-001 diagnostic namespace
  - test/formatter_test.mbt embedded fixture harness (goldens, idempotence, reparse, refusal, CRLF, determinism, statement_offsets)
affects: [03-02 (layout expansion), 03-03 (option combinations), 03-04 (CLI), Phase 4 LSP formatting]

# Actuals (#2632) — pairs with the plan's estimate (70000 tokens) on the same scale.
actuals:
  tokens: 11213    # 44853 diff chars / 4 over the two task commits
  tasks: 2
  commits: 2

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Token-sequence-preserving rewriter over flat-leaf CST (same tokens, same order; only keyword spelling and inter-token whitespace change)"
    - "Measure-then-break list layout (break decision reads only the token sequence -> idempotence by construction)"
    - "Comment attachment rule: newline in original trivia run -> comment on its own line; line comments force a break after"
    - "Refusal-first format entry: first_unsafe_element scan before any layout; slice failures become refusal diagnostics, never panics"
    - "Pending-separator emission state (pending_space/pending_break) materialized on the next emit"

key-files:
  created:
    - formatter/moon.pkg
    - formatter/options.mbt
    - formatter/error.mbt
    - formatter/refuse.mbt
    - formatter/case.mbt
    - formatter/layout.mbt
    - formatter/format.mbt
    - test/formatter_test.mbt
  modified:
    - api/api.mbt
    - api/moon.pkg
    - test/moon.pkg

key-decisions:
  - "formatter/ consumes only source/token/syntax + core buffer (D-27 one-way); printer/ untouched; print_lossless stays the lossless contract (add-alongside)"
  - "Keyword case rewriting consumes @token.classification_of only; no second keyword list in formatter/ (D-28, T-03-07)"
  - "Refusal is absolute (D-33): error/missing/skipped material -> accepted=false, empty output, exactly one DORIS-FORMAT-001; parse diagnostics converted and prepended so they are never masked (T-03-01)"
  - "api.format_text is the shared Phase 4 LSP core entry (D-38); formatter type re-exports via MoonBit type aliases (verified on moon 0.1.20260724)"
  - "statement_offsets records the buffer length before each statement's layout; the inter-statement separator newline is emitted as part of the following statement's layout (pending break), so the offset points at the separator byte"
  - "Select-list measure-then-break measures non-trivia leaf lengths + one canonical space per trivia run + \", \" per comma — invariant to input whitespace, hence idempotent across passes"

patterns-established:
  - "Pattern 1: per-kind clause tables (Select table this plan; other families in 03-02) — the only grammar knowledge duplicated outside parser/, gated by the D-35 reparse oracle"
  - "Pattern 2: measure-then-break select list (one item per line at indent+1, comma at end of item line, no last-item comma per A1)"
  - "Pattern 3: comment/hint attachment = newline in original trivia; comment bytes always verbatim (D-36)"
  - "Pattern 4: detect_newline (FollowInput = first CRLF wins, CRLF-as-one-break) + finalize_output (normalize tail to exactly one newline; empty stays empty)"
  - "Pattern 5: refusal with DORIS-FORMAT-001, span of the first offending element"
  - "Pattern 6: FormatterFixture embedded harness mirroring metadata_fixture_replay_ok (golden, byte-exact idempotence, zero-diagnostic reparse, refusal)"

requirements-completed: [FMT-01, FMT-02, FMT-03]

# Coverage metadata (#1602) — one entry per shipped deliverable.
coverage:
  - id: D1
    description: "formatter/ library package with the D-27 one-way import boundary (source/token/syntax + core buffer; no api/parser/printer/lexer)"
    requirement: FMT-02
    verification:
      - kind: unit
        ref: "verify command: negative greps over formatter/moon.pkg + moon check --target native"
        status: pass
    human_judgment: false
  - id: D2
    description: "FormatOptions with exactly six locked fields (D-26), defaults (D-29..D-32), validating new() (ASVS V5), six accessors, and from_id string-id mapping"
    requirement: FMT-02
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_options_default_and_validation"
        status: pass
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_from_id_maps_cli_string_ids"
        status: pass
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_options_error_propagation_never_reaches_api"
        status: pass
    human_judgment: false
  - id: D3
    description: "Absolute refusal path (D-33): error trees return accepted=false, empty output, exactly one DORIS-FORMAT-001 diagnostic; parse diagnostics never masked (T-03-01)"
    requirement: FMT-03
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_refusal_never_masks_parse_diagnostics"
        status: pass
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_tracer_fixtures_hit_goldens_and_oracles (expected_error fixtures)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Keyword-case rewrite via the classification table (D-28/D-29): goldens prove keyword uppercasing with comment/hint bytes verbatim (D-36)"
    requirement: FMT-01
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_tracer_fixtures_hit_goldens_and_oracles (4.x-select-comments-hint golden)"
        status: pass
    human_judgment: false
  - id: D5
    description: "Idempotence and reparse contracts (D-34/D-35): byte-exact format(format(x)) == format(x) and zero-diagnostic reparse on every accepted fixture; CRLF byte preservation; empty input -> empty output"
    requirement: FMT-03
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_tracer_fixtures_hit_goldens_and_oracles (idempotence + reparse oracles, 4.x-crlf, 4.x-empty)"
        status: pass
    human_judgment: false
  - id: D6
    description: "api.format_text / format_with_ids / format_with_metadata shared core entry (D-38) with statement_offsets and determinism backstop"
    requirement: FMT-01
    verification:
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_statement_offsets_index_into_output"
        status: pass
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_metadata_and_ids_agree_on_output"
        status: pass
      - kind: unit
        ref: "test/formatter_test.mbt#formatter_determinism_pure_function_backstop"
        status: pass
    human_judgment: false

# Metrics
duration: 41min
completed: 2026-08-04
status: complete
---

# Phase 3 Plan 1: Formatter Core Tracer Summary

**formatter/ package (options/error/refuse/case/layout/format) plus api.format_text / format_with_ids / format_with_metadata shared entry: token-sequence-preserving canonical formatter over the lossless CST with six-field FormatOptions, absolute DORIS-FORMAT-001 refusal, byte-exact idempotence, and comment/hint preservation**

## Performance

- **Duration:** 41 min
- **Started:** 2026-08-04T10:35:00Z
- **Completed:** 2026-08-04T11:16:00Z
- **Tasks:** 2
- **Files modified:** 11 (7 created, 3 modified, 1 test file created)

## Accomplishments
- Formatter core as a token-sequence-preserving rewriter over the Phase 1/2 lossless CST (D-27 add-alongside): same tokens in the same order; only keyword spelling and inter-token whitespace change.
- Six-field `FormatOptions` (D-25/D-26) with defaults (D-29..D-32) and validating `new()` (ASVS V5) — negative indent and non-positive line width fail construction.
- Absolute refusal (D-33): `first_unsafe_element` gates every layout call; error trees return `accepted=false`, empty output, exactly one `DORIS-FORMAT-001` diagnostic with the offending span; parse diagnostics are converted and prepended so the refusal never masks parse errors (T-03-01).
- Keyword case rewriting through the single classification authority (`@token.classification_of`, D-28) — no second keyword list (T-03-07).
- Comment/hint attachment rule (D-36): comments emitted verbatim; newline in the original trivia run puts a comment on its own line; line comments force a break after; hints (`/*+ ... */`) are lexer trivia and are preserved byte-for-byte in goldens.
- Measure-then-break select list (idempotent by construction), clause-break table for Select, CRLF-as-one-break `detect_newline`, and normalize-to-exactly-one trailing newline (`finalize_output`).
- `api.format_text` shared core entry (D-38): one internal parse mirroring `parse`, formatter type re-exports via MoonBit type aliases (verified on moon 0.1.20260724), `statement_offsets` for Phase 4 range edits.

## Task Commits

Each task was committed atomically:

1. **Task 1: formatter package + api.format_text end-to-end tracer slice** - `a8a1558` (feat)
2. **Task 2: from_id helpers, format_with_metadata, and api-level contract tests** - `7fd4158` (feat)

**Plan metadata:** (final metadata commit records SUMMARY/STATE/ROADMAP)

## Files Created/Modified
- `formatter/moon.pkg` - library manifest; imports exactly source/token/syntax + core buffer/debug/utf8 (D-27 one-way)
- `formatter/options.mbt` - KeywordCase/CommaStyle/NewlineStyle enums, FormatOptions (6 private fields), default()/new(), six accessors, from_id helpers
- `formatter/error.mbt` - FormatError enum, FormatDiagnostic (mirrors PrimitiveDiagnostic), FormatResult { accepted, output, diagnostics, statement_offsets }
- `formatter/refuse.mbt` - first_unsafe_element recursive scan (Error/Skipped/Missing nodes, SourceError/SourceSkipped leaves)
- `formatter/case.mbt` - rewrite_keyword via @token.classification_of (single keyword authority)
- `formatter/layout.mbt` - Layout state (buffer/column/indent/pending separators), emit/emit_token/space/break_line/break_line_at, detect_newline, finalize_output, clause_breaks, statement_family, select_list_info, layout_sequence, layout_select_items, layout_statement
- `formatter/format.mbt` - pub format(root, source, options) with refusal-first entry, statement_offsets population, document-trivia handling, never panics
- `api/api.mbt` - format_text/format_with_ids/format_with_metadata, parse-diagnostic conversion, formatter type re-exports
- `api/moon.pkg` - added "fathom/doris-sql/formatter" @formatter import
- `test/moon.pkg` - added formatter import
- `test/formatter_test.mbt` - FormatterFixture harness + 8 tests (goldens, idempotence, reparse, refusal, defaults/validation, from_id, offsets, metadata-agreement, determinism)

## Decisions Made
- Type re-export mechanism for the api facade is MoonBit `pub type X = Y` aliases (probe-verified on moon 0.1.20260724; `pub struct` cross-package literal construction required switching FormatDiagnostic/FormatResult to `pub(all)`).
- `statement_offsets` records the buffer length before each statement's layout; the inter-statement separator newline is emitted as part of the following statement's layout (pending break), so the second statement's offset points at the separator byte — the plan's acceptance (first 0, second strictly greater, both index into output) holds.
- Select-list measurement is invariant to input whitespace (non-trivia lengths + one space per trivia run + ", " per comma) so the break decision cannot flip between passes.
- FollowInput newline style = first CRLF in the document wins (flagged assumption A2); trailing newline = normalize-to-exactly-one, empty output stays empty (flagged assumption A3).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] FormatResult/FormatDiagnostic not constructible cross-package**
- **Found during:** Task 1 (api facade compile)
- **Issue:** moon 0.1.20260724 rejects struct literal construction of a `pub struct` from another package ("Cannot create values of the read-only type"), so api.format_text could not build the result/diagnostic values.
- **Fix:** Declared FormatDiagnostic and FormatResult as `pub(all)` (all fields were already pub; visibility widened for cross-package literal construction). FormatOptions stays `pub struct` with private fields + accessors by design.
- **Files modified:** formatter/error.mbt
- **Verification:** moon check --target native passes; format_text composes results cross-package.
- **Committed in:** a8a1558 (Task 1 commit)

**2. [Rule 1 - Bug] Bytes slice returns BytesView, not Bytes**
- **Found during:** Task 1 (layout compile)
- **Issue:** `output[0:end]` slices to BytesView; `+` needs Bytes.
- **Fix:** `.to_owned()` on the finalize_output slices.
- **Files modified:** formatter/layout.mbt
- **Verification:** moon check passes; finalize_output tests green (trailing-newline oracle in fixtures).
- **Committed in:** a8a1558 (Task 1 commit)

**3. [Rule 1 - Bug] @buffer.Buffer::new does not exist on this toolchain**
- **Found during:** Task 1 (layout compile)
- **Issue:** The buffer constructor is `Buffer::Buffer(size_hint? : Int)` (no `new`).
- **Fix:** Use `@buffer.Buffer::Buffer(size_hint=1024)`.
- **Files modified:** formatter/layout.mbt
- **Verification:** moon check passes; layout accumulation verified by goldens.
- **Committed in:** a8a1558 (Task 1 commit)

**4. [Rule 1 - Bug] Statement-offset test expected a semicolon the input never had**
- **Found during:** Task 2 (test run)
- **Issue:** The two-statement fixture is `b"select 1; select 2"` — statement 2 has no trailing `;`, so the output is `"SELECT 1;\nSELECT 2\n"`, not `"SELECT 1;\nSELECT 2;\n"`.
- **Fix:** Corrected the expected literal and locked the offset semantic (second offset = len("SELECT 1;"), pointing at the separator byte).
- **Files modified:** test/formatter_test.mbt
- **Verification:** full suite 174/174 passes.
- **Committed in:** 7fd4158 (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (4 Rule 1 bugs)
**Impact on plan:** All auto-fixes were compile/contract corrections within the planned surface; no scope creep, no architectural change. The formatter design (pending-separator emission, measure-then-break, refusal-first) executed exactly as planned.

## Issues Encountered
- The tracer feedback gate re-ran the full Task 1 verify post-commit (auto mode): moon test 169/169, moon check --target native, D-27 negative import gates, and the printer-untouched gate all passed on the committed state before expansion to Task 2.
- Pre-existing repo warnings (redundant_modifier, core_package_not_imported in api.mbt) are out of scope per the scope boundary; new code adds none.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The tracer slice proves the full raw-bytes -> parse -> formatter.format -> FormatResult path with keyword case, comment/hint preservation, byte-exact idempotence, zero-diagnostic reparse, refusal, CRLF, and statement_offsets.
- 03-02 can expand the layout: per-family clause tables, blank-line policy between statements, and the full statement surface (INSERT/UPDATE/DELETE/MERGE/CREATE).
- 03-03 can drive option combinations (Lf/Crlf overrides, keyword-case Lower, comma styles) through the from_id helpers and FormatOptions validation.
- 03-04 CLI consumes api.format_with_ids + from_id mappings directly.

## Self-Check: PASSED
- All 10 key files exist on disk (verified `[ -f ]`).
- Both task commits exist in git history: `a8a1558`, `7fd4158`.
- Final acceptance re-run: `moon test` 174/174 passed; `moon check --target native` passed; D-27 negative import gates passed; `printer/` untouched; no FFI/IO in formatter/ or api/.
- No stubs, skipped tests, or unrun verifies — the broken-windows ledger needs no entries.

---
*Phase: 03-formatting-and-safe-edits*
*Completed: 2026-08-04*
