---
phase: 10-flink-release-profiles-and-lexical-core
plan: 01
subsystem: api
tags: [flink, calcite, release-profiles, provenance, lexical, moonbit, snapshot]

# Dependency graph
requires:
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: "Dialect/DialectContext closed enum, per-dialect keyword rows, FATHOM-PARSE-008 Flink route, fathom.parse.v1/fathom.dialect.v1/fathom.capabilities.v1 wire identity, validate_dialect_profile gate"
provides:
  - "FlinkProfile closed enum (V2_3_0|V2_1_3|V1_20_5) + FlinkProfileMetadata (id/release_family/exact_release/calcite_version/parser_config/feature_introduction) with exact-match from_id (D-01)"
  - "flink-2.3.0/2.1.3/1.20.5 selection unlocked end-to-end through api ParseOptions::new, binding validate_dialect_profile, fathom.dialect.v1/capabilities, and the CLI; unsupported flink profiles still reject via FATHOM-SCHEMA-003/007 (D-05)"
  - "D-02 provenance mechanism: scripts/extract_flink_lexical.py validates the three calcite pins (1.36.0/1.34.0/1.32.0) + parser config from sha512-verified pinned release archives; parity/fixtures/flink-lexical/manifest.tsv records url/sha512/git_tag/git_commit"
  - "D-04 flink-lexical snapshot namespace: hash-comment conflict frozen x {flink-2.3.0,doris-4.x} x {strict,editor}; Doris 213-snapshot baseline byte-identical"
  - "Lexer '#' dialect branch: Flink Error token (FATHOM-PARSE-003 through the parser) vs Doris Comment token byte-identically"
affects: [10-02, 10-03, 11-flink-grammar-and-recoverable-cst, 12-cross-dialect-corpus-and-parity-gates]

# Actuals (#2632) — pairs with the plan's `estimate` (44000) to calibrate future estimates.
actuals:
  tokens: 14582
  tasks: 4
  commits: 3

# Tech tracking
tech-stack:
  added:
    - "FlinkProfile/FlinkProfileMetadata (dialect/flink.mbt, zero new dependencies)"
    - "scripts/extract_flink_lexical.py (Python stdlib provenance extractor/validator)"
  patterns:
    - "Closed enum + release-derived metadata (D-01, DorisProfile-isomorphic)"
    - "Release-archive provenance: extract -> metadata -> manifest, one source of truth (D-02)"
    - "Independent flink-lexical snapshot namespace under the D-08 parity gate (D-04)"

key-files:
  created:
    - "scripts/extract_flink_lexical.py"
    - "parity/fixtures/flink-lexical/manifest.tsv"
    - "parity/flink_lexical_test.mbt"
    - "parity/__snapshot__/flink-lexical.hash-comment.{flink-2.3.0,doris-4.x}.{strict,editor}.json"
    - ".planning/phases/10-flink-release-profiles-and-lexical-core/approved-changes.md"
  modified:
    - "dialect/flink.mbt (FlinkProfile enum + FlinkProfileMetadata + metadata/from_id)"
    - "api/api.mbt (ParseOptions::new flink arm, flink_profile/flink_profile_metadata/exact_release accessors)"
    - "binding/schema.mbt (validate_dialect_profile flink arm, dialect_json/capabilities_json flink entries)"
    - "binding/exports.mbt (format envelope exact_release source)"
    - "fathom-sql/args.mbt + run.mbt + cli_test.mbt (flink profile acceptance + message)"
    - "lexer/lexer.mbt (# dialect branch + test)"
    - "test/formatter_test.mbt, parity/export_smoke_test.mbt, parity/schema_test.mbt, parity/parity_test.mbt (flink acceptance + adjacency matrix)"

key-decisions:
  - "D-01 FlinkProfile closed enum (V2_3_0|V2_1_3|V1_20_5) + FlinkProfileMetadata (id/release_family/exact_release/calcite_version/parser_config/feature_introduction); exact-match from_id only, no Doris profile borrowing"
  - "D-02 Calcite pins (1.36.0/1.34.0/1.32.0) and parser config (Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT) extracted from sha512-verified pinned release archives (extract script + manifest), never hand-written"
  - "D-05 unknown/unsupported flink profiles reuse FATHOM-SCHEMA-003/007 family; no FATHOM-FLINK-* namespace minted; dialect rides in metadata fields"

patterns-established:
  - "Pattern 1: FlinkProfile closed enum + FlinkProfileMetadata, DorisProfile-isomorphic (D-01)"
  - "Pattern 2: validate_dialect_profile flink arm unlocks the pinned profiles; unknown flink profile still -> FATHOM-SCHEMA-003 (D-05)"
  - "Pattern 3: lexer branches by context.dialect; Doris arm byte-identical (DIALECT-02)"
  - "Pattern 4: parity/ flink-lexical independent snapshot namespace + approved-changes register (D-04)"
  - "Pattern 5: research-time extract pipeline (release archive -> POM/grammar -> metadata/manifest), Python stdlib only"

requirements-completed: [FLINK-01]

coverage:
  - id: D1
    description: "FlinkProfile closed enum + FlinkProfileMetadata with release-derived calcite_version/parser_config; exact-match from_id (flink-2.3.0/2.1.3/1.20.5); selection unlock through ParseOptions::new"
    requirement: FLINK-01
    verification:
      - kind: unit
        ref: "api/api.mbt#api_requires_explicit_dialect_profile_and_mode"
        status: pass
      - kind: integration
        ref: "moon test --target native --package api --package dialect --package fathom-sql --package lexer --package parser (276 passed)"
        status: pass
    human_judgment: false
  - id: D2
    description: "flink profile metadata on the wire: fathom.dialect.v1 flink entries with calcite_version/parser_config, fathom.capabilities.v1 lists the three flink profiles; validate_dialect_profile flink arm; unknown flink profile -> FATHOM-SCHEMA-003"
    requirement: FLINK-01
    verification:
      - kind: integration
        ref: "parity/parity_test.mbt#parity_capabilities_exclude_wasm_gc_and_expose_linear_wasm + parity/schema_test.mbt + parity/export_smoke_test.mbt"
        status: pass
    human_judgment: false
  - id: D3
    description: "End-to-end CLI flink parse: fathom.parse.v1 envelope with dialect=flink/profile=flink-2.3.0/exact_release and FATHOM-PARSE-008; unknown profile exit 2 with message listing released values"
    requirement: FLINK-01
    verification:
      - kind: e2e
        ref: "fathom-sql parse --dialect flink --profile flink-2.3.0 (exit 0, FATHOM-PARSE-008); --profile 2.1 (exit 2)"
        status: pass
    human_judgment: false
  - id: D4
    description: "Lexer '#' dialect branch: Error token under Flink (FATHOM-PARSE-003 via parser), Comment under Doris byte-identically; D-06 hash-comment conflict snapshots frozen"
    requirement: FLINK-01
    verification:
      - kind: unit
        ref: "lexer/lexer.mbt#lexer_routes_hash_comment_by_dialect_flink_error_doris_comment"
        status: pass
      - kind: integration
        ref: "parity/flink_lexical_test.mbt (flink-lexical.hash-comment.* snapshots)"
        status: pass
    human_judgment: false
  - id: D5
    description: "D-02 provenance: extract_flink_lexical.py validates the three calcite pins + parser config against pinned release archives; parity manifest records url/sha512/git_tag/git_commit; Doris baseline byte-identical"
    requirement: FLINK-01
    verification:
      - kind: other
        ref: "python3 scripts/extract_flink_lexical.py (exit 0, ok line); wrong pin exit 1"
        status: pass
      - kind: integration
        ref: "moon test --package parity (233 passed, no --update); git diff --name-only -- parity/__snapshot__ shows only flink-lexical.* files"
        status: pass
    human_judgment: false

# Metrics
duration: 35min
completed: 2026-08-07
status: complete
---

# Phase 10 Plan 1: Flink Release Profiles and Lexical Core — Summary

**Flink release profile identity and selection unlock (flink-2.3.0/2.1.3/1.20.5) with audit-gated Calcite provenance and an independent flink-lexical snapshot namespace**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-08-07T10:30:00Z
- **Completed:** 2026-08-07T11:03:00Z
- **Tasks:** 4 (2 checkpoint decisions auto-selected + tracer + provenance/auto)
- **Files modified:** 20 (12 modified, 8 created)

## Accomplishments
- **FlinkProfile + FlinkProfileMetadata (D-01):** `FlinkProfile { V2_3_0 | V2_1_3 | V1_20_5 }` with `metadata()` returning `id`/`release_family`/`exact_release`/`calcite_version`/`parser_config`/`feature_introduction` and exact-match `from_id` — no prefix/suffix/version-compare, no Doris profile borrowing (`flink-2.3`, `flink-2.3.0-rc1`, `2.1` all rejected).
- **End-to-end selection unlock:** `ParseOptions::new("flink", "flink-2.3.0", ...)` Ok; `validate_dialect_profile` flink arm; `fathom.dialect.v1("flink")` returns three profile entries with `calcite_version` 1.36.0/1.34.0/1.32.0 and the identical parser config; `fathom.capabilities_v1()` lists the three flink profiles; the CLI parses flink input to the `fathom.parse.v1` envelope with `FATHOM-PARSE-008`, and unknown flink profiles exit 2 with the released-value message (D-05: no FATHOM-FLINK-* namespace, FATHOM-SCHEMA-003/007 reused).
- **`#` lexical dialect branch (DIALECT-02/03/06):** under a Flink context `#` is an Error token (FATHOM-PARSE-003 lexical diagnostic with correct span); under Doris it stays a Comment token byte-identically.
- **D-02 provenance mechanism:** `scripts/extract_flink_lexical.py` (Python stdlib, check_keywords.py shape) reads the pinned release POMs/`PlannerContext.java` from `/tmp/flink-research/` and validates the three calcite pins + parser config (exit 1 on any mismatch); `parity/fixtures/flink-lexical/manifest.tsv` records the release URL/sha512/git_tag/git_commit per profile.
- **D-04 flink-lexical snapshot namespace:** the hash-comment conflict is frozen x {flink-2.3.0, doris-4.x} x {strict, editor} with an independent `flink-lexical.*` naming (Pitfall 7); the Doris 213-snapshot baseline is byte-identical (verified `git diff --name-only -- parity/__snapshot__` shows only the four new flink-lexical files).

## Task Commits

Each task was committed atomically:

1. **Task 1: Confirm D-02 Calcite-pin provenance contract (checkpoint decision)** — auto-selected option-a (release-archive extraction per D-02)
2. **Task 2: Confirm D-05 error-family contract (checkpoint decision)** — auto-selected option-a (reuse FATHOM-SCHEMA-003/007)
3. **Task 3 (tracer): End-to-end flink selection + lexical route** - `aa280db` (feat)
4. **Task 4: Provenance extractor + manifest + snapshot gate** - `952f8a4` (feat: extractor/manifest/test/register) + `4c77f65` (test: snapshots)

**Plan metadata:** pending final docs commit

## Files Created/Modified
- `dialect/flink.mbt` - FlinkProfile enum + FlinkProfileMetadata + metadata()/from_id (replaces Phase 9 placeholder)
- `api/api.mbt` - ParseOptions::new flink arm; flink_profile/flink_profile_metadata/exact_release accessors; test updated
- `binding/schema.mbt` - validate_dialect_profile flink arm; fathom.dialect.v1 flink entries (calcite_version/parser_config); capabilities flink profiles
- `binding/exports.mbt` - fathom_format_v1 uses dialect-agnostic exact_release (no profile_metadata panic on flink)
- `fathom-sql/args.mbt`, `fathom-sql/run.mbt`, `fathom-sql/cli_test.mbt` - flink profile acceptance; message lists flink-2.3.0|flink-2.1.3|flink-1.20.5; tests
- `lexer/lexer.mbt` - `#` branch (Flink Error vs Doris Comment) + test
- `test/formatter_test.mbt` - flink format refusal (FATHOM-FORMAT-001) + unknown-profile rejection
- `parity/export_smoke_test.mbt`, `parity/schema_test.mbt`, `parity/parity_test.mbt` - flink acceptance + adjacency matrix
- `scripts/extract_flink_lexical.py` - D-02 provenance extractor/validator
- `parity/fixtures/flink-lexical/manifest.tsv` - per-profile provenance rows
- `parity/flink_lexical_test.mbt` - flink-lexical snapshot tests + dialect-independence assertion
- `parity/__snapshot__/flink-lexical.hash-comment.{flink-2.3.0,doris-4.x}.{strict,editor}.json` - generated golden snapshots
- `.planning/phases/10-flink-release-profiles-and-lexical-core/approved-changes.md` - Phase 10 D-08 register

## Decisions Made
- **D-01 (locked):** FlinkProfile closed enum + FlinkProfileMetadata, DorisProfile-isomorphic; exact-match from_id only.
- **D-02 (locked, one-way):** Calcite pins and parser config come only from the sha512-verified pinned release archives; extract script + manifest make re-verification mechanical.
- **D-05 (locked, one-way):** unknown/unsupported flink profiles reuse the FATHOM-SCHEMA-* family (FATHOM-SCHEMA-003 UnsupportedProfile, FATHOM-SCHEMA-007 UnknownDialect); no FATHOM-FLINK-* namespace; dialect expressed only in metadata fields.

## Deviations from Plan

None - plan executed exactly as written. Both checkpoint:decision gates auto-selected the recommended locked option (D-02 release-archive extraction; D-05 reuse FATHOM-SCHEMA family) per the auto-advance mode.

## Issues Encountered
- **`moon build --target native --release` full build link failure (`undefined reference to main`)**: pre-existing project quirk — the `binding` package is a `foreign_library` that `moon build` tries to link as a native executable. Not caused by this plan; the CLI/`fathom-lsp`/`parity` executables build individually (`moon build --target native --release --package <name>`), and the binding wire surface is fully exercised by the parity package tests (233 passed).
- **`moon test --target native --package binding` fails**: `#export_name` is only legal in a foreign_library; binding is not native-testable. Pre-existing; the plan's verify block lists `--package binding` but the binding surface is covered via `--package parity` (233 tests including schema/export smoke).
- **Duplicate `snapshot_test` in the parity package**: `parity/flink_lexical_test.mbt` initially reused the name already defined in `parity/baseline_test.mbt`; renamed to `flink_snapshot_test`.
- **Lexer test token index**: the `#` token is at index 2 (after identifier + whitespace), not index 1; corrected in the test.

## Known Stubs

None. `flink_classification_rows` remains `[]` by design this wave (filled in 10-03); `flink-2.3.0` parse routes to FATHOM-PARSE-008 as the explicit not-implemented statement per the plan.

## Next Phase Readiness
- Wave 2 (10-02) can build the Flink lexical core (quoting, literals, operators, identifiers) on the unlocked flink profile selection and the established flink-lexical snapshot namespace.
- Wave 3 (10-03) fills `flink_classification_rows` per release, following the manifest provenance pattern.
- The `#` conflict matrix entry and the D-02/D-04 mechanisms are the reusable patterns for the remaining lexical conflicts (double-quote, `//`, X/U&/B/E literals, QUALIFY/VARIANT version sensitivity).

## Self-Check: PASSED

- Files verified: 10-01-SUMMARY.md, manifest.tsv, extract_flink_lexical.py, flink_lexical_test.mbt
- Commits verified: aa280db, 952f8a4, 4c77f65
- Doris baseline: `moon test --package parity` 233/233 without --update; `git diff --name-only -- parity/__snapshot__` shows only the four new flink-lexical files

---
*Phase: 10-flink-release-profiles-and-lexical-core*
*Completed: 2026-08-07*
