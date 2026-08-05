---
phase: 02-doris-completeness-and-corpus
verified: 2026-08-04T06:52:33Z
status: passed
human_acceptance: "User accepted on 2026-08-04 during autonomous run: FE/Nereids differential is a D-20 documented manual maintainer operation (requires Java-built Doris FE, offline-unavailable); 11/11 must-haves verified by the verifier. Accepted as passed without further manual execution."
score: 11/11 must-haves verified
behavior_unverified: 0
overrides_applied: 0
inherited_phase1_context:
  - "Phase 1 verification (01-VERIFICATION.md) was gaps_found with 3 retained boundaries: (a) disk manifest/fixtures not consumed by the test runtime, (b) moon.mod observed-version vs v0.10.5 label mismatch, (c) manifest revisions unavailable-offline. Boundary (a) is the Phase 2 closure target verified below; (b) and (c) are carried as documented, non-blocking boundaries."
local_commands_run:
  - "moon test (166 passed / 0 failed)"
  - "moon check --target native (0 errors, 136 warnings)"
  - "moon version (moon 0.1.20260724 (5f1406a 2026-07-24))"
  - "python3 corpus/tools/check_keywords.py corpus/keywords.tsv (ok: 116 keyword rows, 62 production words covered)"
  - "python3 corpus/tools/generate_corpus_report.py --check (ok: CORPUS-REPORT.md is current and consistent)"
  - "bash -n corpus/tools/fe_nereids_diff.sh (syntax OK)"
  - "python3 -c 'import sqlglot; print(sqlglot.__version__)' (30.14.0 installed)"
  - "static reads/greps of parser, token, syntax, api, analyzer, lexer, tests, corpus TSVs/report/tools, plans/summaries/review"
not_run:
  - "corpus/tools/sqlglot_diff.py (regenerates corpus/differential.tsv; the verifier's no-edit constraint forbids file writes — differential.tsv verified statically instead)"
  - "corpus/tools/fe_nereids_diff.sh (requires a built Apache Doris FE, offline-unavailable; documented manual-only per D-20)"
  - "network/FE/database services; independent re-read of the Doris docs pages (A2/A3 authority claims were verified at execution time by the executor)"
human_verification:
  - test: "Run corpus/tools/fe_nereids_diff.sh against a built Apache Doris FE (FE_VERSION pinned to the fixture release family) and confirm it appends/updates fe_nereids_observation rows in corpus/differential.tsv via NereidsParser.parseSQL without touching sqlglot rows and without cluster access."
    expected: "fe_nereids_observation becomes accepted/rejected per fixture with advisory_only=true preserved on every row; the released-docs manifest remains the sole acceptance authority (D-07/D-20)."
    why_human: "The script requires a Java-built Doris FE that is offline-unavailable; the phase contract explicitly defers its execution to a maintainer with a built FE (02-06 SUMMARY marks this human_judgment: true). All code evidence (script contents, syntax check, merge/append logic, differential.tsv rows) is verified; only the real-world Java probe remains."
---

# Phase 2: Doris Completeness and Corpus Verification Report

**Phase Goal:** Users can parse version-supported Doris scripts and warehouse-specific DML/DDL with localized errors, while maintainers and consumers can inspect reproducible coverage and the syntax-only/analyzer boundary.
**Verified:** 2026-08-04T06:52:33Z
**Status:** HUMAN NEEDED (11/11 must-haves verified; 1 documented manual item remains — FE/Nereids differential execution)
**Re-verification:** No — initial verification of Phase 2 (carries Phase 1 gap-closure context; see frontmatter).

**Method:** Goal-backward source audit. All six PLANs and SUMMARYs, REQUIREMENTS.md, ROADMAP Phase 2 section, 01-VERIFICATION.md, 02-REVIEW.md and 02-REVIEW-FIX.md were read as leads, not proof. Every must-have was then verified against the actual source, tests, and corpus artifacts, with behavioral evidence obtained by running the gates: `moon test` (166/166 pass), `moon check --target native` (0 errors, 136 warnings), `check_keywords.py` (ok), `generate_corpus_report.py --check` (ok), `bash -n fe_nereids_diff.sh` (ok). No file was edited.

## Observable Truths

| # | Truth (from PLANs / roadmap SCs) | Status | Evidence |
|---|---|---|---|
| 1 | DORIS-01: INSERT (VALUES rows incl. DEFAULT/multi-row, INSERT…SELECT, OVERWRITE incl. legacy literal `table` form, PARTITION list, PARTITION (*), WITH LABEL, hints), UPDATE, DELETE (both documented forms), and 4.x-gated MERGE parse under explicit profiles with lossless replay and localized statement diagnostics. | ✓ VERIFIED | `parser/parser.mbt` keyword-first dispatch (parse_segment 3317-3394: SELECT/WITH-lookahead/INSERT/UPDATE/DELETE/MERGE/CREATE arms + unsupported default); `parse_insert` (1487), `parse_update` (1612), `parse_delete` (1665), `parse_merge` (1724). MERGE gate: `feature_allowed` → `add_feature_diagnostic` DORIS-PARSE-006 with `version_invalid_node` substitution (1739-1745, 347-368, 3257-3270); DorisFeature::MergeInto introduced_profile "4.x" (token.mbt:180-184). Tests: `test/dml_test.mbt` (25 tests: insert values/select/overwrite/partition-star, update/delete forms, merge under 4.x + 006 negatives under 2.1/3.x, unsupported starters → one DORIS-PARSE-007 each). Behavioral: 166/166 suite pass. |
| 2 | DORIS-03: multi-statement scripts preserve statement boundaries, localize an invalid statement's diagnostic with its statement_id, and retain/parse later statements. | ✓ VERIFIED | Segmentation loop in `parse_with_limits_context` (3438-3501): ';'-split, `has_statement_content` skips trivia-only segments, monotonic `statement_id` 0U/1U…; `finish_statement` wraps each segment. Tests: `doris03_insert_script_localizes_bad_statement` (3 statements, bad at id 1U DORIS-PARSE-007, byte-exact replay), `doris03_dml_script_localizes_bad_statement`, `doris03_merge_and_unsupported_keep_later_statements`, `dml_recovery_never_swallows_later_statements` (2 statements), `unclosed_paren_dml_recovery_is_bounded_by_recovery_steps` (max_recovery_steps 4, ≤8 diagnostics), `insert_statement_flood_stays_bounded_and_replays` (50 statements). Behavioral: passing suite. |
| 3 | DORIS-02: CREATE TABLE full body (columns, keys/aggregation, distribution, buckets, partitions incl. AUTO PARTITION BY, properties), CREATE VIEW, CTAS, CREATE TABLE LIKE, CREATE INDEX, sync + async CREATE MATERIALIZED VIEW parse with version gates; malformed DDL recovers without swallowing later statements. | ✓ VERIFIED | `parse_create` (1857) with TABLE/VIEW/INDEX/MATERIALIZED VIEW arms; `parse_create_table` (2411, full body incl. ENGINE/keys/ORDER BY/partitions/ROLLUP/PROPERTIES/LIKE/CTAS), `parse_create_view` (2255), `parse_create_index` (1917), `parse_create_materialized_view` (2000, sync restricted body with localized expected_class "sync materialized view body" rejection of JOIN/HAVING/LIMIT/LATERAL/subquery + async BUILD/REFRESH/ON SCHEDULE clause stack — A2 closed). Gates: OrderByClause "4.x" (since 4.1.0), BucketsAuto "2.1" and AutoPartitionBy "2.1" (A3-corrected; token.mbt:188-209). Tests: `test/ddl_test.mbt` (28 tests) incl. full-body replay, ORDER BY gated below 4.x, BUCKETS AUTO accepted by all profiles, partition variants, VIEW/CTAS/LIKE/INDEX/MV, async-MV acceptance + malformed recovery, `doris03_mixed_ddl_dml_select_script_keeps_statement_ids`, `create_table_deep_parens_stay_bounded`, `create_table_property_flood_parses_losslessly`. |
| 4 | DORIS-04: data-driven three-layer keyword classification (Reserved/NonReserved/Contextual) with per-row introduced_profile/source; auditable corpus/keywords.tsv mirror enforced by an embedded correspondence test; valid non-reserved/contextual words usable as unquoted identifiers; version-invalid use emits DORIS-PARSE-006. | ✓ VERIFIED | `token/token.mbt`: `ClassificationKind`/`ClassificationEntry` (271-286), 116-row `classification_rows` table (307-447), `classification_of` (450), table-backed `is_reserved_word` (485), `is_clause_keyword` unchanged (471). `corpus/keywords.tsv`: 116 rows + header (117 lines), word/classification/introduced_profile/source. `corpus/tools/check_keywords.py` RUN: "ok: 116 keyword rows, 62 production words covered" (exit 0). Tests: `test/keyword_test.mbt` (9 tests) incl. `classification_table_mirrors_embedded_tsv_rows`, `phase1_reserved_answers_are_preserved_by_the_table`, `version_invalid_keyword_use_emits_006_through_feature_gates`, `full_classification_table_audit_across_profiles`, plus `dml_keywords_do_not_leak_into_shared_clause_set` (dml_test.mbt:324-328). |
| 5 | CORP-01: corpus/manifest.tsv DML/DDL rows with full provenance (profile, exact_release, feature_introduction, official_url, retrieval_date, pinned_source_revision, page_heading, code_fence, category, support_status, parse_mode, classification, provenance_status); revisions never fabricated (unavailable-offline + known-gap only). | ✓ VERIFIED | `corpus/manifest.tsv`: 44 rows (14 migrated Phase 1 SELECT rows + 30 new DML/DDL rows) — verified by direct read: every row carries official_url, retrieval_date 2026-08-03/04, pinned_source_revision "unavailable-offline", provenance_status known-gap with reason; 2.1-merge/3.x-merge are expected-error version negatives; 4.x-merge supported. ProfileMetadata canonical strings extended to DML/DDL and allowlists accept exactly the three new strings (`token/token.mbt:55-90` for_manifest/validate_metadata); no stale canonical strings remain in source/tests/corpus (grep scan clean). |
| 6 | CORP-02: every supported and negative fixture is executable through the embedded replay oracle: parse_with_metadata → print_result == raw, all_spans_in_bounds, expected_valid, DORIS-PARSE- prefix on diagnostics. | ✓ VERIFIED | `test/corpus_test.mbt`: `dml_ddl_corpus_fixtures` = 30 embedded oracle entries mirroring the 30 new manifest rows (incl. 2.1/3.x MERGE version negatives with expected_valid=false and the editor-mode malformed-recovery golden); `dml_ddl_corpus_oracle_replays_every_manifest_fixture` runs each through `metadata_fixture_replay_ok` (test/parser_test.mbt:473-499 asserts byte-exact replay, expected_valid, all_spans_in_bounds, profile/exact_release/feature_introduction round-trip, DORIS-PARSE- prefix, span ordering); `script_multi_statement_fixture_keeps_statement_ids` asserts 5 statements + DORIS-PARSE-007 at id 1U. Behavioral: passing suite. |
| 7 | CORP-03: coverage.tsv + generated CORPUS-REPORT.md present a version×category matrix, failure list, and known-gaps section; deterministic --check fails on stale/inconsistent state; no unqualified full-compatibility claim. | ✓ VERIFIED | `corpus/coverage.tsv`: 41 rows (profile, category, fixture_count, supported_count, expected_error_count, known_gap, coverage_note) incl. `all/known-gaps` row. `corpus/tools/generate_corpus_report.py --check` RUN: "ok: CORPUS-REPORT.md is current and consistent (matrix, failures, known-gaps, keywords summary)" (exit 0) — enforces one-fixture-one-row and the no-claim scan. `corpus/CORPUS-REPORT.md` read: 40-row matrix, 9-row failure list (expected-error), provenance/coverage/flagged known-gaps sections, keyword summary (84 reserved + 6 non-reserved + 26 contextual = 116; by profile 2.1:112, 3.x:2, 4.x:2), no "full compatibility"/"100%" claims. |
| 8 | CORP-04: local pinned-SQLGlot differential runner records one advisory row per manifest fixture with version-specific resolutions; FE/Nereids remains a documented manual script; neither reference can widen acceptance (advisory_only=true everywhere). | ✓ VERIFIED (FE script execution deferred to human) | `corpus/tools/sqlglot_diff.py` read: lazy import (A8 fallback), PINNED "30.14.0", read='doris' + ErrorLevel.RAISE, deterministic regeneration, preserves fe_nereids_observation. `corpus/requirements.txt`: `sqlglot==30.14.0`. `corpus/differential.tsv`: 44 rows, all `advisory_only=true` (col 7 scan: 0 violations), `public_contract=released-docs`, `sqlglot_version=30.14.0` (unique value), 21 accepted / 11 rejected / 12 not-run-offline (matches 02-06 SUMMARY), version-specific resolutions incl. ParseError details and Command-fallback flags. `corpus/tools/fe_nereids_diff.sh`: MANUAL ONLY header, parser-only NereidsParser.parseSQL, never CI, merge-by-fixture_id; `bash -n` PASS. sqlglot 30.14.0 import confirmed installed. Script NOT executed by the verifier (it rewrites differential.tsv; no-edit constraint) — static + installed-version verification only. FE script execution is the human item below. |
| 9 | ANLY-01: syntax parsing and diagnostics require no catalog metadata; an optional analyzer package accepts catalog table/column metadata with zero parser coupling; consumers fetch statement nodes and diagnostics by statement_id. | ✓ VERIFIED | `analyzer/moon.pkg` imports ONLY `fathom/doris-sql/syntax`; `parser/moon.pkg` import list is exactly source/token/lexer/syntax — no analyzer reference (negative gate, read directly). `analyzer/analyzer.mbt`: ColumnInfo/TableInfo, `pub(open) trait Catalog`, StaticCatalog::new/lookup, `resolve_table_references` over syntax read views + caller source bytes. `api/api.mbt`: `ParseResult::statement` (348) and `statement_diagnostics` (365) by statement_id. Tests: `test/analyzer_test.mbt` (9 tests) — catalog hit/miss/empty, trait dispatch, `analyzer_syntax_only_path_is_unchanged_by_catalog`, accessor isolation on `insert; bad; select` (nodes insert/error/select at ids 0/1/2, diagnostics isolated by id), resolver end-to-end (resolves t/t4/t5, excludes absent t2/t3, kind coverage Insert/Update/Delete/Merge/CreateTable). |
| 10 | Phase 1 gap closure: corpus_test.mbt embedded replay oracle executes every new manifest fixture row (disk manifest/fixtures remain the audit record — the documented narrowing option from 01-VERIFICATION.md). | ✓ VERIFIED (via documented narrowing) | Phase 1's gap "runtime test does not consume corpus/manifest.tsv" is addressed exactly as 01-VERIFICATION.md suggested: 02-04's must-haves explicitly define the executable contract as the embedded replay oracle mirroring manifest rows (plan key_link "corpus/manifest.tsv → test/corpus_test.mbt via embedded replay oracle entries mirror manifest rows"), and `test/corpus_test.mbt` delivers 30 entries executed through `parse_with_metadata`. Residual: manifest↔oracle correspondence is maintained manually (no test loads the TSV and compares fixture_ids) — documented design (Phase 1 precedent), not a defect. |
| 11 | Security (CR-01/WR-01/WR-02 fixed) + ParseLimits enforced: deep generic nesting is bounded with DORIS-PARSE-004; bare CREATE forms and malformed type params produce localized diagnostics; regression tests committed. | ✓ VERIFIED | `parse_type_params` (parser.mbt:2673-2756) threads `depth : Int` with `depth > state.limits.max_recursion_depth → resource_diagnostic (DORIS-PARSE-004)` at entry, `depth + 1` at both `(…)` and `<…>` recursion sites; WR-02 struct_style gate; `parse_create` `None =>` arm emits DORIS-PARSE-002 (1906-1910, WR-01). `api/api.mbt` ParseLimits (max_bytes/max_tokens/max_recursion_depth/max_recovery_steps/max_diagnostics) validated and propagated to parser limits (146-160, 275-292). Regression tests in `test/ddl_test.mbt`: `create_table_deep_generic_nesting_stays_bounded` (140 levels → !valid + DORIS-PARSE-004 + replay; 100 levels → valid; custom limit 2 fails at 4 levels), `bare_create_forms_report_incomplete_statement`, `malformed_type_params_report_trailing_garbage`. Fix commits present in git history: c288f44 (CR-01), af05b40 (WR-01), b5e1605 (WR-02). Review's crash-scale evidence (~100k-deep chain terminates with one DORIS-PARSE-004, no SIGSEGV) is inherited from 02-REVIEW-FIX.md; the 140-level regression test exercises the same bound behaviorally and passes. |
| 12 | Lossless invariant: print_lossless(parse(x)) == x asserted for all new DML/DDL statements (byte-exact replay + span bounds). | ✓ VERIFIED | Every DML/DDL/corpus test asserts `@printer.print_result(result) == raw` and `all_spans_in_bounds()` (dml_test, ddl_test, corpus_test via metadata_fixture_replay_ok, analyzer_test resolver input); per-family replay assertions cover INSERT/UPDATE/DELETE/MERGE, all CREATE forms, async MV, scripts, malformed/recovery inputs. Behavioral: 166/166 suite pass (including Phase 1 fixtures unchanged). |

**Score:** 11/11 truths verified (0 present-but-behavior-unverified; 0 overrides).

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | --------- | ------ | ------- |
| `parser/parser.mbt` | keyword-first dispatch + DML/DDL parsers + unsupported path + depth guard | ✓ VERIFIED | Dispatch arms, parse_insert/update/delete/merge/create (+table/view/index/mv), unsupported_statement (DORIS-PARSE-007), parse_type_params depth guard. |
| `token/token.mbt` | DorisFeature gates, ClassificationKind table, canonical metadata allowlists | ✓ VERIFIED | MergeInto 4.x, OrderByClause 4.x, BucketsAuto/AutoPartitionBy 2.1, PartitionStar 2.1; 116 classification rows; for_manifest/validate_metadata exact-match. |
| `syntax/syntax.mbt` | New SyntaxKind variants | ✓ VERIFIED | Insert/Update/Delete/Merge/ValueList/CreateTable/CreateView/CreateIndex/CreateMaterializedView/ColumnDefinition/KeyClause/DistributionClause/PartitionClause/PropertyList. |
| `api/api.mbt` | kind_id arms + statement accessors + ParseLimits | ✓ VERIFIED | All new kinds mapped; `ParseResult::statement`/`statement_diagnostics`; ParseLimits validation. |
| `analyzer/` (moon.pkg, analyzer.mbt) | Independent analyzer, syntax-only import | ✓ VERIFIED | imports only syntax; Catalog/StaticCatalog/resolve_table_references. |
| `parser/moon.pkg` | Negative gate: no analyzer import | ✓ VERIFIED | Imports exactly source/token/lexer/syntax. |
| `corpus/manifest.tsv` | 44 rows with provenance, no fabricated revisions | ✓ VERIFIED | All rows unavailable-offline + known-gap; 30 new DML/DDL rows. |
| `corpus/coverage.tsv` | 41 rows, one-fixture-one-row | ✓ VERIFIED | Generator --check enforces invariant (passed). |
| `corpus/CORPUS-REPORT.md` | Matrix + failures + known-gaps, no claims | ✓ VERIFIED | Generated, current, --check passes. |
| `corpus/keywords.tsv` | 116-row audit mirror | ✓ VERIFIED | check_keywords.py ok (116 rows, 62 production words). |
| `corpus/differential.tsv` | 44 advisory rows | ✓ VERIFIED | all advisory_only=true, sqlglot_version=30.14.0, 21/11/12 split. |
| `corpus/tools/` (check_keywords.py, generate_corpus_report.py, sqlglot_diff.py, fe_nereids_diff.sh, README.md) | Enforcement + differential tooling | ✓ VERIFIED | check/report tools executed OK; differential scripts verified statically + syntax check. |
| `test/dml_test.mbt`, `ddl_test.mbt`, `keyword_test.mbt`, `corpus_test.mbt`, `analyzer_test.mbt` | Executable behavior per family | ✓ VERIFIED | 25/28/9/2/9 tests; behavioral evidence from `moon test` 166/166. |
| `corpus/doris-{2.1,3.x,4.x}/*.sql` | Versioned fixtures with provenance headers, no pollution | ✓ VERIFIED | Spot-checked `dml-merge.sql` (Source/Retrieved/Code fence headers, clean SQL, no mysql> prompts/output blocks). |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| parser.mbt dispatch | family parsers | keyword-first first-significant-token match | WIRED | SELECT/WITH/INSERT/UPDATE/DELETE/MERGE/CREATE arms; default → unsupported_statement. |
| parser.mbt | token.mbt feature gates | feature_allowed → supports(feature) → DORIS-PARSE-006 + version_invalid_node | WIRED | MERGE gate path 1739-1745; substitution 3257-3270. |
| parser.mbt | syntax.mbt | SyntaxNode::new / finish_statement wrappers | WIRED | Statement wrapper per segment; span invariants asserted. |
| api.mbt | syntax.mbt | exhaustive kind_id match | WIRED | Compile-forced arms for every new kind. |
| api.mbt | parser.mbt | statement accessors walk root.children + filter diagnostics by statement_id | WIRED | id-th Statement child walk (non-statement children never consume ids — documented deviation). |
| analyzer/ | syntax/ | resolve_table_references read-only walk + injected Catalog | WIRED | Only import is syntax; caller supplies source bytes. |
| parser/moon.pkg | analyzer/ | NEGATIVE gate | WIRED | No analyzer reference in parser/moon.pkg (read directly). |
| corpus/manifest.tsv | test/corpus_test.mbt | embedded oracle mirrors rows (fixture_id/profile/release/introduction/raw/mode/expected_valid) | WIRED (manual correspondence) | 30 entries ↔ 30 new rows; correspondence not machine-loaded (documented design). |
| corpus/manifest.tsv | token.mbt | canonical feature_introduction strings | WIRED | All rows carry one of the three allowlisted strings. |
| corpus/coverage.tsv + CORPUS-REPORT.md | generator --check | content-hash stale detection + one-fixture-one-row + claim scan | WIRED | --check passed on committed state. |
| corpus/tools/sqlglot_diff.py | corpus/manifest.tsv + differential.tsv | manifest-driven fixture resolution → advisory row per fixture | WIRED | 44 rows consistent with 44 manifest rows; pinned 30.14.0. |
| test/corpus_test.mbt | printer.mbt | print_result == raw per oracle entry | WIRED | metadata_fixture_replay_ok asserts byte-exact replay. |

### Behavioral Spot-Checks (run by this verifier)

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Full test suite incl. all DML/DDL/keyword/corpus/analyzer/recovery tests | `moon test` | Total tests: 166, passed: 166, failed: 0 | ✓ PASS |
| Type-check of the whole tree | `moon check --target native` | 0 errors, 136 warnings (pre-existing) | ✓ PASS |
| Keywords TSV integrity + production-word coverage | `python3 corpus/tools/check_keywords.py corpus/keywords.tsv` | ok: 116 keyword rows, 62 production words covered | ✓ PASS |
| Report currency + invariants + claim scan | `python3 corpus/tools/generate_corpus_report.py --check` | ok: CORPUS-REPORT.md is current and consistent | ✓ PASS |
| FE script syntax | `bash -n corpus/tools/fe_nereids_diff.sh` | exit 0 | ✓ PASS |
| Pinned sqlglot availability | `python3 -c "import sqlglot; print(sqlglot.__version__)"` | 30.14.0 | ✓ PASS |
| Toolchain identity | `moon version` | moon 0.1.20260724 (5f1406a 2026-07-24) — matches moon.mod record | ✓ PASS |

Behavior-dependent truths (DORIS-03 statement survival, CR-01 boundedness, MERGE gating, lossless replay) are all exercised by deterministic tests within the passing 166/166 suite — none is left PRESENT_BEHAVIOR_UNVERIFIED.

### Probe Execution

No probe scripts were declared in the six PLANs/SUMMARYs and no conventional `scripts/*/tests/probe-*.sh` exists in the repo (Phase 1 precedent: probes were not used; the plans use `moon test`/`moon check`/Python checks as their verify steps, all of which this verifier executed). Not applicable.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| DORIS-01 | 02-01 | Version-supported DML (INSERT/OVERWRITE/UPDATE/DELETE/MERGE) in scripts | ✓ SATISFIED | dispatch + parsers + dml_test (25) |
| DORIS-02 | 02-02 | DDL: tables/views/CTAS/LIKE/keys/distribution/buckets/partitions/properties/indexes/MVs | ✓ SATISFIED | parse_create family + ddl_test (28) |
| DORIS-03 | 02-01 | Statement boundaries + localized diagnostics, later statements retained | ✓ SATISFIED | segmentation loop + doris03 tests |
| DORIS-04 | 02-03 | Auditable versioned three-layer keyword classification | ✓ SATISFIED | classification table + keywords.tsv + check_keywords.py + keyword_test (9) |
| CORP-01 | 02-04 | Reproducible manifest with provenance and expected support | ✓ SATISFIED | manifest.tsv 44 rows, no fabricated revisions |
| CORP-02 | 02-04 | Golden coverage: strict/replay/recovery per fixture | ✓ SATISFIED | embedded oracle 30 entries + helper assertions |
| CORP-03 | 02-04 | Coverage/failure reports by version/category incl. known gaps | ✓ SATISFIED | coverage.tsv + CORPUS-REPORT.md + --check pass |
| CORP-04 | 02-06 | Differential vs SQLGlot (local) and FE/Nereids (manual), disagreements recorded | ✓ SATISFIED | sqlglot_diff.py + differential.tsv 44 rows + fe_nereids_diff.sh (manual, human item) |
| ANLY-01 | 02-05 | Catalog-free syntax parsing + optional analyzer without parser coupling | ✓ SATISFIED | analyzer package + negative gate + accessors + analyzer_test (9) |

All 9 requirement IDs are claimed by exactly one plan each and satisfied by implementation evidence; no requirement is orphaned. (FMT-01..04 and ECO-01..07 map to Phases 3-4 and are out of scope for this phase.)

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
| ---- | ------- | -------- | ------ |
| (none in Phase 2 modified files) | TODO/FIXME/XXX/HACK/PLACEHOLDER markers | — | Grep scan of parser/token/api/analyzer/corpus-tools found zero debt markers. |
| `token/token.mbt` is_clause_keyword (IN-06) | hand-maintained word list duplicates the classification table | ℹ️ Info (open review finding) | Future word additions could drift recovery boundaries; review-marked Info, deferred out of fix scope. |
| `analyzer/analyzer.mbt` utf8_to_string (IN-02) | no continuation-byte validation | ℹ️ Info (open review finding) | Unreachable through the normal lexer path; defense-in-depth gap if callers bypass the lexer. |
| `parser/parser.mbt` feature_events (IN-04) | events accumulate across statements in shared RecoveryState | ℹ️ Info (open review finding) | Exact-span matching makes cross-statement substitution impossible today; hygiene issue for future span-sharing refactors. |
| `parser/parser.mbt` create_form_kind (IN-01) | unknown CREATE forms default to CreateTable kind + double diagnostic | ℹ️ Info (open review finding) | Cosmetic kind/diagnostic redundancy on out-of-scope CREATE forms (e.g. CREATE DATABASE). |
| `parser/parser.mbt:1170` (IN-03) | `valid = true && valid` no-op | ℹ️ Info (open review finding) | Dead code; harmless. |

02-REVIEW.md status is `clean` (0 critical / 0 warning / 6 info); 02-REVIEW-FIX.md records CR-01, WR-01, WR-02 as fixed with regression tests — all confirmed in current source and git history.

### Human Verification Required

### 1. FE/Nereids differential script execution against a built Doris FE

**Test:** Run `corpus/tools/fe_nereids_diff.sh` with `FE_VERSION` pinned to the fixture release family and a built Apache Doris FE (Java) available (`FE_CLASSPATH` or `DORIS_SRC`).
**Expected:** The script appends/updates `fe_nereids_observation` (accepted/rejected) rows per fixture in `corpus/differential.tsv` via parser-only `NereidsParser.parseSQL`, preserves `advisory_only=true` on every row, never connects to a cluster, and the released-docs manifest remains the sole acceptance authority (D-07/D-20). `python3 corpus/tools/generate_corpus_report.py --check` stays green.
**Why human:** Requires a Java-built Apache Doris FE that is offline-unavailable; the phase contract (D-20) deliberately defers this to a maintainer with a built FE. All script-side evidence is verified (contents, `bash -n`, merge-by-fixture_id logic, current `not-run-offline` rows); only the real-world Java probe remains.

### Observations (non-blocking, informational)

1. **MVP-mode discrepancy (process):** ROADMAP.md marks Phase 2 `mode: mvp`, but the phase goal is a compound outcome statement, not a canonical user story ("As a …, I want to …, so that …"). The plans themselves use user-story objectives. Verification was completed with the standard goal-backward methodology per the orchestrator's assignment; the workflow should either convert the goal to a user story or drop the mvp flag. No phase-impact.
2. **Phase 1 boundaries carried (not regressions):** moon.mod records observed `moon 0.1.20260724` under the "official v0.10.5 line" policy comment (toolchain identity policy unresolved, matches Phase 1); manifest `pinned_source_revision` remains `unavailable-offline`/`known-gap` (honest, never fabricated).
3. **Docs-authority provenance:** the A2/A3 closures (async MV documented in 2.1/3.x/4.x; BUCKETS AUTO / AUTO PARTITION BY in the 2.1 grammar) were verified by the executor against the docs site at execution time; the resulting code behavior is consistent and test-covered, but this verifier could not independently re-read the Doris docs offline.
4. **sqlglot_diff.py not re-run by the verifier:** it rewrites `corpus/differential.tsv`; under the no-edit constraint the committed 44 rows were verified statically and sqlglot 30.14.0 presence confirmed. The 02-06 SUMMARY's claim that the script regenerates the same rows deterministically is corroborated by the report `--check` (which hashes report-vs-data consistency) but the script's byte-idempotence was not re-executed here.

## Gaps Summary

No gaps. All 11 must-haves are verified with code-level and behavioral evidence; the single human verification item (FE/Nereids script execution) is a documented manual step, not a defect. Status `human_needed` (not `passed`) solely because that external-reference run is a human verification item per the framework; the orchestrator may treat it as an accepted manual boundary (D-20) if the roadmap's "recorded differential disagreements" wording is read at the phase's documented scope.

---

_Verified: 2026-08-04T06:52:33Z_
_Verifier: Claude (gsd-verifier)_
_Status: HUMAN NEEDED — 11/11 must-haves verified; 1 documented manual item (FE/Nereids differential execution)._
