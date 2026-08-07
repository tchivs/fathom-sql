---
phase: 10-flink-release-profiles-and-lexical-core
verified: 2026-08-07T12:30:00Z
status: passed
score: 7/7 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: null
  previous_score: null
  gaps_closed: []
  gaps_remaining: []
  regressions: []
---

# Phase 10: Flink Release Profiles and Lexical Core — Verification Report

**Phase Goal:** Users can select an auditable Flink release profile whose lexical behavior is independent from Doris and grounded in the matching Flink/Calcite contract.
**Verified:** 2026-08-07
**Status:** passed
**Re-verification:** No — initial verification
**Mode:** mvp (success criteria from ROADMAP.md are the contract)

## Goal Achievement

Goal-backward analysis: the phase goal requires (a) profile selection that is auditable (release-derived contract), (b) lexical behavior independent from Doris, and (c) grounding in the pinned Flink/Calcite contract. Each roadmap Success Criterion plus the flagged probe assumptions and the Doris baseline were verified against the actual codebase — not SUMMARY claims.

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | SC1 — User can select `flink-2.3.0` (primary) / `flink-2.1.3` / `flink-1.20.5` (regression) through API, CLI, and JS/Wasm selection path; an unsupported profile (`flink-9.9`, Doris-shaped `2.1`, adjacent `flink-2.3`/`flink-2.3.0-rc1`) is rejected explicitly — no silent default, no Doris profile borrowing. | ✓ VERIFIED | `dialect/flink.mbt` closed enum `FlinkProfile { V2_3_0; V2_1_3; V1_20_5 }` + exact-match `from_id`; `api/api.mbt:98-102` Flink arm rejects via `UnknownProfile`; `binding/schema.mbt:49-52` `validate_dialect_profile` flink arm; `fathom-sql/args.mbt:162-167` `is_valid_dialect_profile`; `fathom-sql/run.mbt:150-151` flink message. **Behavioral:** rebuilt CLI — `parse --dialect flink --profile flink-2.3.0` exits 0 with `fathom.parse.v1` envelope (dialect=flink, profile=flink-2.3.0, FATHOM-PARSE-008); `--profile 2.1` exits 2 with message listing flink-2.3.0/flink-2.1.3/flink-1.20.5. Tests: `api_requires_explicit_dialect_profile_and_mode` (api 269/269), `schema_profile_validation_is_exact_match` (parity 260/260), `dialect_selection_is_explicit_end_to_end` (binding wire). |
| 2 | SC2 — Each accepted profile reports its release source/tag/commit, Calcite version, parser configuration, and feature metadata; the 2.1.3 Calcite pin is extracted from that release, not inferred. | ✓ VERIFIED | `dialect/flink.mbt` `FlinkProfileMetadata`: calcite_version 1.36.0/1.34.0/1.32.0, parser_config `Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT`, exact_release, feature_introduction. `parity/fixtures/flink-lexical/manifest.tsv` 3 flink rows with source_archive_url/sha512/git_tag/git_commit. `scripts/extract_flink_lexical.py` reads pinned `flink-table/pom.xml` (`<calcite.version>`) + `PlannerContext.java` and **executed with exit 0**: "ok: 3 calcite pins verified against pinned release POMs (1.20.5=1.32.0, 2.1.3=1.34.0, 2.3.0=1.36.0), parser config verified … 3 flink manifest rows re-verified against manifest.tsv" (MN-03 manifest re-verify incl. sha512 re-hash). Wire: `binding/schema.mbt:222-244` `dialect_json("flink")` emits calcite_version/parser_config read only via `flink_profile_metadata()`. |
| 3 | SC3 — Flink input receives release-specific comment, quote, literal, operator, identifier, and reserved/non-reserved/contextual classification behavior with source trivia/spans preserved; conflict cases have explainable snapshots rather than Doris-policy leakage. | ✓ VERIFIED | `lexer/lexer.mbt` dialect branches: `#` Error under Flink vs Comment under Doris (FATHOM-PARSE-003), `//`+`--` SINGLE_LINE_COMMENT under Flink, `"` DOUBLE_QUOTE Symbol, backtick BTID double-escape, `'...'` no-backslash with `''` doubling, X/U&/N/E/_CHARSETNAME prefixed literals as single tokens (E gated by `FlinkProfile::supports_escape_literal` — absent under 1.20.5), `B` not a prefix, `||`/`=>`/`..` single symbols. `dialect/flink.mbt` `flink_classification_rows` (142 rows, release-grammar `source` per row); `dialect/classification.mbt` profile-aware filter (`introduced_profile` <= selected profile in release order 1.20.5 < 2.1.3 < 2.3.0). **Behavioral:** 26 flink-lexical conflict-matrix snapshots freeze per-dialect tokenization (hash-comment flink=FATHOM-PARSE-003+008 vs doris=FATHOM-PARSE-007; e-literal 2.3.0/2.1.3=one literal vs 1.20.5=Identifier+String; double-quote/slash-comment/backtick-escape differ per dialect; unknown-profile=FATHOM-SCHEMA-003). Lexer suite 17 behavior tests pass; `classification_is_dialect_independent_and_release_aware` asserts VARIANT/QUALIFY Reserved under 2.1.3/2.3.0 and None under 1.20.5. |
| 4 | Probe FLINK-01 adjacency — profile-id adjacency is exact-match only; lexical span adjacency (unterminated/edge spans) stays source-backed and bounded; reserved∩nonreserved overlap resolved explicitly, never silently. | ✓ VERIFIED | `FlinkProfile::from_id` exact-match (no prefix/suffix/version-compare) + api/CLI/schema tests asserting `flink-2.3`, `flink-2.3.0-rc1`, `2.1` rejected. Lexer `scan_flink_string`/`scan_flink_backtick`/`scan_comment` keep unterminated/EOF spans bounded (`lexer_terminates_unterminated_material`, `lexer_retains_unterminated_quote_and_progresses`, `flink_lexer_backtick_btid_escaping` lone-backtick path). Extract script reports overlap per release: "reserved∩nonreserved overlap: (none)" — explicit, not silent. |
| 5 | Probe FLINK-01 empty — empty Flink input keeps the Phase 9 single-router behavior; empty lexical constructs (`''`, `--\n`, unterminated `/*`, lone backtick) follow the shared scanner's unterminated/error discipline, never silent success; each profile has a non-empty row set. | ✓ VERIFIED | **Behavioral:** `printf '' | fathom-sql parse --dialect flink --profile flink-2.3.0` exits 0 with a valid empty `fathom.parse.v1` document (decision recorded in the 10-01 probe truth). Unterminated constructs produce `LEX_UNTERMINATED_COMMENT`/`LEX_UNTERMINATED_LITERAL` tokens with FATHOM-PARSE-003 surface. `flink_classification_rows_per_profile_are_non_empty` asserts non-empty + monotonic row growth per profile (1.20.5 < 2.1.3 < 2.3.0). |
| 6 | Probe FLINK-01 ordering — wire profile enumeration order stable (flink-2.3.0, flink-2.1.3, flink-1.20.5); token/snapshot emission order deterministic; classification lookup first-match-wins over the dialect's own rows. | ✓ VERIFIED | `binding/schema.mbt:222-223` iterates `["flink-2.3.0", "flink-2.1.3", "flink-1.20.5"]` for `dialect_json`; `:270-276` `capabilities_json` lists the three in order. Export smoke tests (`parity/export_smoke_test.mbt`) freeze the wire surface (parity 260/260). Scanner emits in source order; 26 snapshot files enumerate the matrix deterministically. `classification_of` scans rows in source order (first-match-wins); row audit tests freeze the stable row table. |
| 7 | Doris baseline zero-drift — the frozen 213-snapshot parity baseline is byte-identical; the flink-lexical group is an independent namespace; no `--update` used. | ✓ VERIFIED | `moon test --package parity` **260/260 passed without `--update`**; `git diff --name-only HEAD -- parity/__snapshot__/` shows no doris-named snapshot changed (flink-lexical group only, all committed). Register-before-update discipline confirmed via git log: wave-1 `952f8a4` (register) precedes `4c77f65` (snapshot freeze); wave-2 `f37a324` (register) precedes `03e70d2` (freeze). `classification_entries(doris) == 116` preserved (IN-03 fix derives from `doris_classification_rows.length()`). |

**Score:** 7/7 truths verified (0 present-behavior-unverified; 0 overrides).

### Deferred Items

None — Phase 11 (Flink grammar) is explicitly out of scope for Phase 10's lexical-only contract and is not a gap; valid Flink SQL correctly routes to FATHOM-PARSE-008 (not-implemented statement) by design.

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `dialect/flink.mbt` | FlinkProfile closed enum + FlinkProfileMetadata + from_id + supports_escape_literal + flink_classification_rows (142 rows) | ✓ VERIFIED | Substantive (metadata 1.36.0/1.34.0/1.32.0 + parser_config; rows with release-grammar source); wired (consumed by classification.mbt, api.mbt, lexer, schema.mbt). |
| `dialect/classification.mbt` | Profile-aware row selection (introduced_profile <= selected profile; Doris dialect-only) + independence test | ✓ VERIFIED | `flink_release_rank`/`flink_row_visible`; Doris stays dialect-only; 116-row count derived. |
| `lexer/lexer.mbt` | Dialect branches for `#`, `//`, `--`, `"`, backtick, `'...'`, prefixed literals, `||`/`=>`/`..` | ✓ VERIFIED | `scan_flink_string`/`scan_flink_escaped_string`/`scan_flink_backtick`/`symbol_width_flink`/`flink_prefixed_literal`; Doris arms byte-identical; 17 lexer tests pass. |
| `parity/flink_lexical_test.mbt` + 26 snapshots | Conflict-matrix fixture set + frozen per-dialect tokenization | ✓ VERIFIED | 26 `flink-lexical.*.json` files (hash-comment, double-quote, slash-comment, e-literal ×3 profiles, backtick-escape, unknown-profile flink-4x); parity 260/260 pass without `--update`. |
| `scripts/extract_flink_lexical.py` | Release-archive provenance validator/extractor | ✓ VERIFIED | Executed exit 0: pins, parser config, keyword counts (412/323, 430/324, 443/334), 142 inlined rows, manifest sha512 re-verify (MN-03). |
| `api/api.mbt` | Flink arm in ParseOptions::new; parse_flink_not_implemented gates via from_id + carries metadata | ✓ VERIFIED | `api_parse_flink_not_implemented_gates_profiles_and_carries_metadata` (MN-04 fix); FATHOM-PARSE-008 + FATHOM-SCHEMA-003 on unknown. api 269/269. |
| `fathom-sql/args.mbt` + `run.mbt` | Flink profile acceptance + exit-2 message | ✓ VERIFIED | Rebuilt CLI: flink-2.3.0 exit 0; `2.1` exit 2; MissingProfile lists both dialect sets (IN-01 fix). fathom-sql 16/16. |
| `binding/schema.mbt` + `exports.mbt` | validate_dialect_profile flink arm; dialect_json/capabilities_json flink entries | ✓ VERIFIED | calcite_version/parser_config only from FlinkProfileMetadata (T-09-18); `fathom_dialect_v1`/`fathom_capabilities_v1` exports; order flink-2.3.0/2.1.3/1.20.5. |
| `parity/fixtures/flink-lexical/manifest.tsv` | Per-profile provenance rows (url/sha512/tag/commit) | ✓ VERIFIED | 3 flink rows + doris-4.x docs row; re-verified by extract script (sha512 re-hash against archives). |
| `parity/fixtures/flink-lexical/flink-{v}-{reserved,nonreserved}.txt` | Six full per-release keyword lists | ✓ VERIFIED | Counts 443/334, 430/324, 412/323 (validated by extract script exit 0); provenance headers; committed. |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `FlinkProfileMetadata.calcite_version` | `parity/fixtures/flink-lexical/manifest.tsv` | `scripts/extract_flink_lexical.py` (reads pinned release POMs) | WIRED | Extract script exit 0; one source of truth, no hand-written pin; manifest re-verified (MN-03). |
| `binding/schema.mbt` dialect_json flink entries | `dialect/flink.mbt` FlinkProfileMetadata | `flink_profile_metadata()` accessor | WIRED | calcite_version/parser_config read only from metadata (T-09-18), never fabricated. |
| `parity/__snapshot__/flink-lexical.*` | `moon test --package parity` | D-08 byte gate (no `--update` in CI) | WIRED | 260/260 pass; Doris 213 snapshots byte-identical. |
| `dialect/flink.mbt` flink_classification_rows | `dialect/classification.mbt` classification_of | `classification_rows_for` profile-aware filter | WIRED | VARIANT/QUALIFY ABSENT under 1.20.5; Doris rows dialect-only. |
| `flink_classification_rows` source columns | `parity/fixtures/flink-lexical/flink-{v}-*.txt` | `scripts/extract_flink_lexical.py` inlined-row presence check | WIRED | All 142 words present in matching release lists (exit 0). |
| `api/api.mbt` parse_flink_not_implemented | `FlinkProfile::from_id` | Profile gate before parse | WIRED | MN-04: unknown → UnknownProfile/FATHOM-SCHEMA-003; metadata populated. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| --- | --- | --- | --- | --- |
| `dialect/flink.mbt` FlinkProfileMetadata | calcite_version/parser_config | Pinned release POMs via extract script (validated exit 0) | Yes | ✓ FLOWING |
| `binding/schema.mbt` dialect_json flink entries | calcite_version/parser_config | `flink_profile_metadata()` (metadata only) | Yes | ✓ FLOWING |
| `dialect/classification.mbt` classification_of | flink rows | `flink_classification_rows` (142 rows) filtered by introduced_profile <= profile | Yes | ✓ FLOWING |
| `parity/flink_lexical_test.mbt` snapshots | token stream / diagnostics | `fathom_parse_v1` over fixture bytes | Yes (26 frozen envelopes) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| SC1 profile selection + FATHOM-PARSE-008 | `echo 'SELECT 1 -- hi' \| fathom-sql parse --dialect flink --profile flink-2.3.0` | exit 0; envelope dialect=flink/profile=flink-2.3.0/exact_release=flink-2.3.0; FATHOM-PARSE-008 | ✓ PASS |
| SC1 unsupported profile rejection | `echo 'SELECT 1' \| fathom-sql parse --dialect flink --profile 2.1` | exit 2; message lists flink-2.3.0/flink-2.1.3/flink-1.20.5 | ✓ PASS |
| IN-01 MissingProfile message | `fathom-sql parse --dialect flink` (no --profile) | exit 2; lists both dialect profile sets | ✓ PASS |
| Probe empty input contract | `printf '' \| fathom-sql parse --dialect flink --profile flink-2.3.0` | exit 0; valid empty document | ✓ PASS |
| SC2 provenance extractor | `python3 scripts/extract_flink_lexical.py` | exit 0; ok-line (3 pins, parser config, keyword counts, 142 rows, 3 manifest rows re-verified) | ✓ PASS |
| Doris zero-drift | `moon test --package parity` (no --update) | 260/260 pass; `git diff --name-only HEAD -- parity/__snapshot__` no doris-named change | ✓ PASS |
| API suite | `moon test --target native --package api` | 269/269 pass | ✓ PASS |
| Lexer + dialect suites | `moon test --target native --package dialect --package lexer` | 25/25 pass | ✓ PASS |
| CLI suite | `moon test --target native --package fathom-sql` | 16/16 pass | ✓ PASS |

### Probe Execution

| Probe | Command | Result | Status |
| --- | --- | --- | --- |
| Provenance extractor/validator | `python3 scripts/extract_flink_lexical.py` | exit 0, ok-line (3 calcite pins, parser config, keyword counts 412/323/430/324/443/334, 142 inlined rows, 3 manifest rows re-verified) | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| FLINK-01 | 10-01/10-02/10-03 | Consumer can select pinned Flink release profiles with auditable source and parser contracts: flink-2.3.0 primary + flink-2.1.3/flink-1.20.5 regression; each profile records actual release Calcite version/config; unsupported profiles rejected explicitly. | ✓ SATISFIED | SC1+SC2+SC3 all verified; traceability table in REQUIREMENTS.md marks FLINK-01 Complete. |

No orphaned requirements — FLINK-01 is the only requirement mapped to Phase 10, and all three plans claim it.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| — | — | None — no TBD/FIXME/XXX/HACK/PLACEHOLDER markers in any Phase 10 modified source file | — | — |

### Human Verification Required

None. Every behavior-dependent truth has passing behavioral evidence: profile selection/rejection (API + CLI + binding tests), lexical tokenization (17 lexer unit tests + 26 parity snapshot tests + 4 conflict-assertion fixtures), classification (dialect + classification tests), provenance (extract script executed), and empty-input contract (direct CLI execution). No visual, real-time, external-service, or UX-quality behavior remains unexercised.

### Gaps Summary

No gaps found. The phase goal is achieved: profile selection is end-to-end and auditable (release-derived Calcite pins verified against pinned archives), Flink lexical behavior is dialect-routed and grounded in the pinned release grammar (every branch carries a Parser.jj token citation), keyword classification is release-aware with zero Doris leakage, conflict cases are frozen as 26 explainable snapshots, and the Doris 213-snapshot baseline stays byte-identical (260/260 parity without `--update`). Code review 7/7 findings addressed (MN-01 charsetname prefix, MN-02 documented deferral, MN-03 manifest re-verify, MN-04 LSP profile gate, IN-01 MissingProfile message, IN-02 snapshot rename, IN-03 derived Doris row count).

---

_Verified: 2026-08-07_
_Verifier: Claude (gsd-verifier)_
