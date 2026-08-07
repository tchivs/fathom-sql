---
phase: 10-flink-release-profiles-and-lexical-core
fixed_at: 2026-08-07T00:00:00Z
review_path: .planning/phases/10-flink-release-profiles-and-lexical-core/10-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 6
skipped: 1
status: partial
---

# Phase 10: Code Review Fix Report

**Fixed at:** 2026-08-07
**Source review:** `.planning/phases/10-flink-release-profiles-and-lexical-core/10-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7
- Fixed: 6 (MN-01, MN-03, MN-04, IN-01, IN-02, IN-03)
- Skipped: 1 (MN-02 — documented deferral, no code change)

## Fixed Issues

### MN-01: `_CHARSETNAME` prefix of `PREFIXED_STRING_LITERAL` is not implemented

**Files modified:** `lexer/lexer.mbt`
**Commit:** fa5cbf1
**Applied fix:** Implemented the `_CHARSETNAME` alternative of `PREFIXED_STRING_LITERAL` in `flink_prefixed_literal`: after a single `_`, the CHARSETNAME run is scanned with the exact pinned grammar charset (`[A-Za-z0-9]` start, then `[A-Za-z0-9:._-]*` per `#CHARSETNAME` Parser.jj:8784), requiring an immediate `'` before `scan_flink_string`. Added `is_charsetname_start`/`is_charsetname_continue` helpers (the `_` char is excluded from the CHARSETNAME *start* set but allowed in continuation). A bare `_'..'` stays Identifier+String (correct — CHARSETNAME requires ≥1 char). Added `flink_lexer_charsetname_prefixed_literal` verifying `_UTF8'abc'` and `_latin-1:win'x'` lex as one StringLiteral under flink while the Doris path stays Identifier+String. Lexer suite 17/17.

### MN-02: Numeric-adjacent `..` (DOUBLE_PERIOD) is swallowed by the shared number scanner

**Files modified:** `parity/flink_lexical_test.mbt`
**Commit:** 9d5c1a3
**Applied fix:** Documented deferral — no code change. Added a "KNOWN DIVERGENCE (MN-02)" note to the flink-lexical test header (the conflict matrix) recording that `N..N` tokenizes as one `LEX_INVALID_NUMBER` error under flink while Calcite would split it, and that the decision will be revisited when Flink grammar lands (Phase 11).

### MN-03: `extract_flink_lexical.py` does not re-verify the committed `manifest.tsv` checksums/provenance

**Files modified:** `scripts/extract_flink_lexical.py`
**Commit:** ec4da59
**Applied fix:** Added a manifest verification pass (`parse_manifest`/`validate_manifest`, stdlib-only with `hashlib.sha512`): parses `parity/fixtures/flink-lexical/manifest.tsv`, asserts every flink row's `calcite_version`/`parser_config` equal `CALCITE_PINS`/`PARSER_CONFIG`, and when the release archive is present under the research root re-hashes the archive and compares it to the manifest `sha512` column (3/3 rows verified). Verified a tampered manifest (wrong calcite_version or sha512) exits 1 via the negative test; `python3 scripts/extract_flink_lexical.py` exits 0.

### MN-04: LSP document path still bypasses Phase-10 Flink profile validation/metadata

**Files modified:** `api/api.mbt`, `lsp/handlers.mbt`
**Commit:** 3eb0ce3
**Applied fix:** `parse_flink_not_implemented` now gates `profile_id` through `FlinkProfile::from_id` — unknown profiles (e.g. Doris-shaped `4.x`) return `Err(UnknownProfile)` (FATHOM-SCHEMA-003 at the wire), and known profiles populate `exact_release`/`feature_introduction` from `FlinkProfileMetadata` instead of the raw profile string / empty string. Stale doc comment rewritten. `lsp/validate_selection` now routes flink profiles through the shared `@binding.validate_dialect_profile` gate (single validation gate), so `flink`+`4.x` is rejected at the LSP selection boundary. Added `api_parse_flink_not_implemented_gates_profiles_and_carries_metadata`. api+lsp suites 304/304; valid flink selections still produce explicit FATHOM-PARSE-008.

### IN-01: `MissingProfile` CLI usage message advertises Doris-only values

**Files modified:** `fathom-sql/run.mbt`
**Commit:** e527447
**Applied fix:** `MissingProfile` message is now neutral and lists both dialect profile value sets: `missing required flag: --profile <doris 2.1|3.x|4.x | flink flink-2.3.0|flink-2.1.3|flink-1.20.5>`. fathom-sql suite 16/16 (the existing assertion checks only the `missing required flag: --profile` prefix).

### IN-02: `unknown-profile` snapshot filename uses the `doris-4.x` slot for a *flink* rejection

**Files modified:** `parity/__snapshot__/flink-lexical.unknown-profile.flink-4x.{strict,editor}.json` (renamed), `parity/__snapshot__/flink-lexical.unknown-profile.doris-4x.{strict,editor}.json` (removed), `parity/flink_lexical_test.mbt`, `approved-changes.md`
**Commit:** 2634dd8 (rename) + 916816a (superseded-file removal)
**Applied fix:** Renamed the two frozen snapshots from `flink-lexical.unknown-profile.doris-4x.{strict,editor}.json` to `flink-lexical.unknown-profile.flink-4x.{strict,editor}.json` (content byte-identical), updated the register entry in approved-changes.md and the test names/fixture comment. `moon test --package parity` without `--update` stays green (260/260) — the rename does not ripple into snapshot content hashes.

### IN-03: `classification_entries(doris).length() == 116` is a brittle hard-coded pin

**Files modified:** `dialect/classification.mbt`
**Commit:** f18e5c7
**Applied fix:** The independence test now derives the Doris row count from `doris_classification_rows.length()` instead of the literal 116, keeping the semantic independence assertions (VARIANT not Doris-reserved, SELECT is) as the real checks. dialect suite 8/8.

## Skipped Issues

None — all in-scope findings were either fixed or documented (MN-02's deferral is recorded, not skipped).

---

_Fixed: 2026-08-07_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
