---
phase: 10-flink-release-profiles-and-lexical-core
reviewed: 2026-08-07T00:00:00Z
depth: deep
files_reviewed: 22
files_reviewed_list:
  - api/api.mbt
  - binding/exports.mbt
  - binding/schema.mbt
  - dialect/classification.mbt
  - dialect/flink.mbt
  - fathom-sql/args.mbt
  - fathom-sql/cli_test.mbt
  - fathom-sql/run.mbt
  - lexer/lexer.mbt
  - parity/export_smoke_test.mbt
  - parity/flink_lexical_test.mbt
  - parity/parity_test.mbt
  - parity/schema_test.mbt
  - parity/fixtures/flink-lexical/manifest.tsv
  - parity/fixtures/flink-lexical/flink-1.20.5-nonreserved.txt
  - parity/fixtures/flink-lexical/flink-1.20.5-reserved.txt
  - parity/fixtures/flink-lexical/flink-2.1.3-nonreserved.txt
  - parity/fixtures/flink-lexical/flink-2.1.3-reserved.txt
  - parity/fixtures/flink-lexical/flink-2.3.0-nonreserved.txt
  - parity/fixtures/flink-lexical/flink-2.3.0-reserved.txt
  - scripts/extract_flink_lexical.py
  - test/formatter_test.mbt
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 10: Code Review Report — Flink Release Profiles and Lexical Core

**Reviewed:** 2026-08-07
**Depth:** deep
**Files Reviewed:** 22 source/data files (plus cross-referenced `parser/parser.mbt`, `token/token.mbt`, `lsp/`, `api` call-chain)
**Status:** issues_found (0 BLOCKER / 0 MAJOR / 4 MINOR / 3 INFO)

## Summary

Phase 10 unlocks the three pinned Flink release profiles (`flink-2.3.0`, `flink-2.1.3`, `flink-1.20.5`) end-to-end: `FlinkProfile`/`FlinkProfileMetadata` with release-derived Calcite pins and parser config, profile-aware keyword classification (`introduced_profile <= selected profile`), Flink lexical branches in the shared scanner, a provenance extractor/validator, frozen conflict-matrix snapshots, and CLI/wire profile acceptance.

I reviewed every changed source file and, critically, **grounded the correctness claims directly against the pinned release archives** present under `/tmp/flink-research/src/`:

- **Calcite pins verified against the real POMs** (`flink-table/pom.xml`): 2.3.0→`1.36.0`, 2.1.3→`1.34.0`, 1.20.5→`1.32.0` — all three match `FlinkProfileMetadata`.
- **Every Flink lexical branch verified against `codegen/templates/Parser.jj` in each pinned release**: `#` is absent from all token sets (Flink Error token is correct); `SINGLE_LINE_COMMENT ("//"|"--")` (:8901/8696/8291); `DOUBLE_QUOTE "\""` (:8858/8592/8187); `QUOTED_STRING` with `''` doubling and no backslash escape (:8776/8510/8107); `C_STYLE_ESCAPED_STRING_LITERAL` present in 2.3.0 (:8782) and 2.1.3 (:8516), **absent in 1.20.5** (E-literal gate correct); `BINARY_STRING_LITERAL ["x","X"]` (:8769/8503/8100); `UNICODE_STRING_LITERAL "U" "&"` (:8780/8514/8111); `PREFIXED_STRING_LITERAL ("_" <CHARSETNAME> | "N")` (:8778/8512/8109); `BACK_QUOTED_IDENTIFIER` double-backtick, no backslash escape, no embedded newline (:9014); `CONCAT "||"`, `NAMED_ARGUMENT_ASSIGNMENT "=>"`, `DOUBLE_PERIOD ".."` (:8854-8856). `B` correctly has **no** `BIT_STRING_LITERAL` token in any release.
- **Doris zero-drift confirmed**: the pre-change `--`/`#` branch (verified via `git show 8f561a5:lexer/lexer.mbt`) is byte-identical to the current Doris arm; every new Flink branch is gated on `context.dialect is Dialect::Flink`. The full parity suite (260 tests, including the 213-snapshot Doris baseline) passes **without** `--update`.
- **Snapshot discipline confirmed**: the approved-changes register was committed (`952f8a4`) before the wave-1 snapshot freeze (`4c77f65`), and the register was extended (`f37a324`) before the wave-2 freeze (`03e70d2`).
- **Profile-aware classification verified**: release order `flink-1.20.5 < flink-2.1.3 < flink-2.3.0`; VARIANT/QUALIFY reserved under 2.1.3+ and `None` under 1.20.5; 2.3.0-delta words (SAFE_CAST etc.) absent under 2.1.3/1.20.5; Doris rows (116) unaffected.
- **Extract script security**: no subprocess, no shell/eval, no TOCTOU (files opened directly and read), no path traversal risk (fixed relative paths under an env-configurable root). `python3 scripts/extract_flink_lexical.py` exits 0 with 3 pins, parser config, keyword counts, and all 142 inlined rows verified; the VARIANT token line cross-check matches the archives exactly (2.3.0→8640, 2.1.3→8374).
- **Test evidence**: `moon test --target native --package lexer` 16/16, `--package dialect --package api` 276/276, `--package parity` 260/260, `--package fathom-sql` 16/16, `--package test` 146/146 — all green.

No BLOCKER or MAJOR findings. The four MINOR findings are genuine (but edge-case) divergences from the pinned grammar or provenance/consistency gaps; none affect Doris behavior, and none are reachable in a way that changes accepted Flink grammar (which arrives in Phase 11).

## Critical Issues

None.

## Warnings

### MN-01: `_CHARSETNAME` prefix of `PREFIXED_STRING_LITERAL` is not implemented

**File:** `lexer/lexer.mbt:363-364` (inside `flink_prefixed_literal`, :336-373)

**Issue:** The pinned grammar token is `< PREFIXED_STRING_LITERAL: ("_" <CHARSETNAME> | "N") <QUOTED_STRING> >` (verified at `flink-2.3.0/.../Parser.jj:8778`, `2.1.3:8512`, `1.20.5:8109`). The code comment documents the `_CHARSETNAME` alternative but implements **only** the `N` prefix. Under a Flink context, a legal charset-qualified literal such as `_UTF8'abc'` therefore lexes as `Identifier("_UTF8")` + `StringLiteral("'abc'")` — two tokens — instead of one literal token as the pinned grammar dictates. The identifier scanner consumes `_UTF8` as one identifier (`is_ascii_letter` includes byte 0x5F), so `id_end - start == 1` never holds for the `_` form and `flink_prefixed_literal` returns `None`.

**Why MINOR:** the construct is rare in Flink, Flink grammar is not implemented until Phase 11 (every Flink parse is the FATHOM-PARSE-008 rejection), and the divergence is confined to the frozen lexical-token layer. It is still a real gap in the phase's stated contract ("Flink literal-prefix detection at an identifier boundary (D-03)").

**Fix:** extend `flink_prefixed_literal` to handle the `_` form: after a single `_` identifier char, if the identifier continues with a `CHARSETNAME`-shaped run (`[A-Za-z0-9]` start, then `[A-Za-z0-9:._-]*`, per `#CHARSETNAME` at :8784) immediately followed by `'`, consume the whole prefixed literal with `scan_flink_string`:
```moonbit
// _CHARSETNAME'..' PREFIXED_STRING_LITERAL (Parser.jj:8778).
if first == 95 { // '_'
  // scan CHARSETNAME run from start+1, then require ' at the end
  let mut cursor = start + 1
  while cursor < id_end && (is_ascii_letter(bytes[cursor].to_int()) ||
    is_ascii_digit(bytes[cursor].to_int())) { cursor = cursor + 1 }
  // allow trailing ':','.','-','_' characters inside CHARSETNAME
  ...
  if cursor < length && bytes[cursor].to_int() == 39 {
    let (end, code) = scan_flink_string(bytes, cursor)
    return Some((end, code))
  }
}
```

**Fixed:** commit fa5cbf1 — implemented the `_CHARSETNAME` alternative in `flink_prefixed_literal` (lexer/lexer.mbt) with `is_charsetname_start`/`is_charsetname_continue` helpers; added the `flink_lexer_charsetname_prefixed_literal` lexical test (`_UTF8'abc'` → one StringLiteral under flink, Identifier+String under doris).

### MN-02: Numeric-adjacent `..` (DOUBLE_PERIOD) is swallowed by the shared number scanner

**File:** `lexer/lexer.mbt:103-145` (`scan_number`) interacting with `symbol_width_flink` (:380-395)

**Issue:** Phase 10 adds `DOUBLE_PERIOD ".."` as a Flink symbol (`symbol_width_flink`, :383-389), but for input like `1..2` the shared number scanner runs first and consumes the entire run as one `LEX_INVALID_NUMBER` Error token. The real Calcite token manager (JavaCC longest-match) would produce `DECIMAL_NUMERIC_LITERAL("1.")` + `DECIMAL_NUMERIC_LITERAL(".2")` (regex `(["0"-"9"])+(".")?(["0"-"9"])*` at :8754). So the new Flink `..` token is unreachable whenever a `.` is adjacent to a digit. This is not a Phase-10 regression for Doris (identical pre-existing behavior, pinned by `lexer_accepts_decimal_and_scientific_numbers_but_rejects_repeated_dots`), but it means the frozen Flink lexical behavior diverges from the pinned grammar for `N..N`.

**Why MINOR:** `DOUBLE_PERIOD` has **no grammar production** in any pinned template (verified: only the token definition at :8856 references it), so `N..N` is not parseable Flink anyway; the divergence is tokenization-only for an invalid construct. If Phase 11 introduces grammar that uses `..` adjacent to numbers, this must be revisited.

**Fix:** defer — when Flink grammar lands, decide whether `N..N` should be split (`1.` + `.2` per Calcite) or treated as a number error. Document the choice in the flink-lexical conflict matrix; no change is warranted while `..` has no production.

**Fixed:** commit 9d5c1a3 — documented the deferral in the `parity/flink_lexical_test.mbt` header (flink-lexical conflict matrix); no code change.

### MN-03: `extract_flink_lexical.py` does not re-verify the committed `manifest.tsv` checksums/provenance

**File:** `scripts/extract_flink_lexical.py:356-465` (`main`), vs. `parity/fixtures/flink-lexical/manifest.tsv`

**Issue:** The docstring claims the metadata is "taken ONLY from the sha512-verified pinned release archives (D-02)". The script re-verifies the three `calcite.version` POM pins, the vanilla `calcite-core` dependency, and the `PlannerContext.java` parser-config lines — all genuinely against the archives — but it **never reads `manifest.tsv`** and never re-hashes the archives against the manifest's `sha512` column. The manifest is the committed provenance record for url/sha512/tag/commit, yet nothing mechanically cross-checks it against either the code values (`FlinkProfileMetadata`, `CALCITE_PINS`) or the actual archive bytes. A tampered manifest (e.g. an altered sha512 or calcite_version) would pass every committed gate.

**Why MINOR:** dev/research-only tooling; archives are never shipped; a wrong-archive swap would still be caught for the calcite pin and parser-config lines. The gap is provenance auditability, not a runtime/security flaw (no TOCTOU, no injection — verified).

**Fix:** add a manifest verification pass in `main` that (a) parses `manifest.tsv`, (b) asserts each flink row's `calcite_version`/`parser_config` equal `CALCITE_PINS`/`PARSER_CONFIG`, and (c) when the archive is present, computes `sha512` of the archive/source-tree and compares it to the `sha512` column — exiting 1 on mismatch.

**Fixed:** commit ec4da59 — added `parse_manifest`/`validate_manifest` to scripts/extract_flink_lexical.py (stdlib-only, `hashlib.sha512`); the script now re-verifies calcite_version/parser_config against `CALCITE_PINS`/`PARSER_CONFIG` and re-hashes each present archive against the manifest `sha512` column (3/3 rows verified; tampered manifest exits 1).

### MN-04: LSP document path still bypasses Phase-10 Flink profile validation/metadata

**File:** `api/api.mbt:489-511` (`parse_flink_not_implemented`); cross-ref `lsp/` `validate_selection` (Phase 9, `09-06`)

**Issue:** `parse_flink_not_implemented` accepts **any** `profile_id` (no `FlinkProfile::from_id` gate) and hardcodes `exact_release: profile_id`, `feature_introduction: ""`. Over the LSP document path, a flink document — e.g. `flink` + `flink-2.3.0` — therefore parses to FATHOM-PARSE-008 with `feature_introduction: ""` and, worse, `flink` + `4.x` (a selection the CLI and wire now reject with FATHOM-SCHEMA-003) is still silently accepted as a legal LSP selection. The doc comment is also stale ("Phase 9 has no Flink grammar", "feature-introduction metadata is empty until Phase 10 pins real Flink profiles"). For the same selection, CLI and LSP now emit different `feature_introduction` in the envelope.

**Why MINOR:** LSP is out of Phase-10's file scope and still emits the correct explicit FATHOM-PARSE-008 (never a Doris fallback); the inconsistency is metadata/validation surface, not grammar acceptance. It does undermine the phase's "unlocked with auditable metadata" claim at the LSP boundary.

**Fix:** route the LSP flink document path through `FlinkProfile::from_id` (reject unknown profiles with FATHOM-SCHEMA-003 at the selection boundary, matching `validate_dialect_profile`), and populate `feature_introduction`/`exact_release` from `FlinkProfileMetadata`. Update the doc comment. This belongs to a Phase-10 follow-up or Phase 11 LSP work.

**Fixed:** commit 3eb0ce3 — `parse_flink_not_implemented` now gates `profile_id` through `FlinkProfile::from_id` (unknown → `UnknownProfile`/FATHOM-SCHEMA-003) and populates `exact_release`/`feature_introduction` from `FlinkProfileMetadata`; stale doc comment rewritten; `lsp/validate_selection` now routes flink profiles through the shared `@binding.validate_dialect_profile` gate (single validation gate), so `flink`+`4.x` is rejected at the LSP selection boundary; added `api_parse_flink_not_implemented_gates_profiles_and_carries_metadata` test.

## Info

### IN-01: `MissingProfile` CLI usage message advertises Doris-only values

**File:** `fathom-sql/run.mbt:199`

**Issue:** `usage_error_message(MissingProfile)` prints `missing required flag: --profile <2.1|3.x|4.x>`. Now that flink is a valid profile surface, a flink user who omits `--profile` is shown only Doris values — the same MI-02 anti-pattern the phase fixed for the UnknownProfile message.

**Fix:** make the message neutral, e.g. `missing required flag: --profile <doris 2.1|3.x|4.x | flink flink-2.3.0|flink-2.1.3|flink-1.20.5>`, or route on the already-parsed `--dialect` value.

**Fixed:** commit e527447 — `MissingProfile` message now lists both dialect profile value sets.

### IN-02: `unknown-profile` snapshot filename uses the `doris-4.x` slot for a *flink* rejection

**File:** `parity/flink_lexical_test.mbt:111-118, 362-385`; snapshot `flink-lexical.unknown-profile.doris-4.x.strict.json`

**Issue:** the fixture's `dialect` is `"flink"` and `profile` is `"4.x"`, but the frozen filename embeds `doris-4.x`. The register documents this ("Filename uses the doris-4.x profile slot from the register"), so it is intentional — but a consumer reading the snapshot tree would infer the wrong dialect for the rejection envelope.

**Fix:** rename to `flink-lexical.unknown-profile.flink-4x.{strict,editor}.json` (or `...unknown-profile.flink-unknown.{...}.json`) and update the register entry, or leave as-is and document the naming convention in the test header.

**Fixed:** commit 2634dd8 (rename) + 916816a (superseded-file removal) — renamed the two snapshots to `flink-lexical.unknown-profile.flink-4x.{strict,editor}.json` (content byte-identical), updated the register entry in approved-changes.md and the test names/fixture comment; `moon test --package parity` without `--update` stays green (260/260).

### IN-03: `classification_entries(doris).length() == 116` is a brittle hard-coded pin

**File:** `dialect/classification.mbt:190` (`classification_is_dialect_independent_and_release_aware`)

**Issue:** the independence test pins the exact Doris row count (116). Any future Doris keyword-row addition breaks the test without necessarily being a dialect-independence regression. The pin does serve as a zero-drift guard today, so the risk is low.

**Fix:** optionally derive the expected count from `doris_classification_rows.length()` instead of a literal, keeping the semantic assertions (VARIANT not Doris-reserved, SELECT is) as the real independence checks.

**Fixed:** commit f18e5c7 — `classification_is_dialect_independent_and_release_aware` now derives the Doris row count from `doris_classification_rows.length()` instead of the literal 116.

---

## Verification Evidence

- `python3 scripts/extract_flink_lexical.py` → exit 0, "ok: 3 calcite pins verified … 142 inlined flink rows present".
- `grep <calcite.version>` on `/tmp/flink-research/src/flink-{2.3.0,2.1.3,1.20.5}/flink-table/pom.xml` → `1.36.0 / 1.34.0 / 1.32.0`.
- `Parser.jj` token definitions in each pinned archive matched every Flink lexical branch (see Summary).
- `git show 8f561a5:lexer/lexer.mbt` confirms the Doris `--`/`#` arm is byte-identical to HEAD.
- `moon test --target native --package {lexer,dialect,api,parity,fathom-sql,test}` → 16/16, 276/276, 260/260, 16/16, 146/146 green, no `--update`.

---

_Reviewed: 2026-08-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_
