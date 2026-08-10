---
phase: 09-dialect-boundary-and-neutral-naming
verified: 2026-08-07T08:00:00Z
status: passed
score: 31/31 must-haves verified
behavior_unverified: 1 # empty-Flink-input invariant: behavior observed (silent empty diagnostics), deviates from the flagged probe assertion; decision tracked in WINDOWS.md #4
overrides_applied: 0
re_verification: # No previous VERIFICATION.md existed — initial verification
  previous_status: none
deferred:

  - truth: "Live-host VS Code/IntelliJ dialect-selection UX and config precedence in a real editor (probe NAME-03 unclassified)"
    addressed_in: "Phase 13"
    evidence: "Phase 13 SC4: 'User can use the same dialect-aware API/schema/LSP through JS/linear-Wasm, Web/Monaco, VS Code, and IntelliJ; each host selects Doris or Flink per file/session' and its Validation: 'real Web/Monaco/VS Code/IntelliJ artifact smoke; verify document revision/stale-response and selection-conflict cases'"
behavior_unverified_items:

  - truth: "Empty input under a Flink context produces the FATHOM-PARSE-008 not-implemented diagnostic — never a silent empty success (probe DIALECT-03 empty, flagged-unverified)"
    test: "Open an empty (zero-byte) document in fathom-lsp with a flink document-level selection and observe textDocument/publishDiagnostics"
    expected: "Observed behavior publishes an empty diagnostics array (silent empty success). The probe's asserted contract is FATHOM-PARSE-008 for empty Flink input. Human must decide: enforce FATHOM-PARSE-008 for the empty case (requires relaxing the single-router/no-empty-diff constraint) or accept the documented mutual-exclusion decision (WINDOWS.md #4, 09-02 decision: 'the single-router prohibition and the frozen Doris empty-document behavior are mutually exclusive for the empty case')."
    why_human: "The implementation consciously deviates from the flagged assumption with a documented trade-off (single parse_segment router grep gate vs frozen Doris empty-document baseline). Presence checks cannot adjudicate which contract should win; the deviation is tracked as open in WINDOWS.md #4."
human_verification:

  - test: "Decide the empty-Flink-input contract: open a zero-byte document with dialect=flink over LSP (or call parse_flink_not_implemented(b\"\", ...)) and confirm the intended behavior"
    expected: "Current code publishes an empty diagnostics array. The flagged probe (DIALECT-03 empty) asserted FATHOM-PARSE-008 'never a silent empty success'; the executor documented mutual exclusion with the single-router prohibition (WINDOWS.md #4, 09-02 decisions). Accept the documented deviation as the Phase 9 contract, or schedule enforcement in a later phase."
    why_human: "Both alternatives (silent-empty for Doris-parity vs FATHOM-PARSE-008 for no-silent-success) are defensible and mutually exclusive under the current single-router design; the decision was deliberately deferred out of the plan's acceptance criteria."
previous_status: none
---

# Phase 9: Dialect Boundary and Neutral Naming Verification Report

**Phase Goal:** Users can explicitly select Doris or Flink and its valid profile at every public boundary, while the SDK exposes one neutral product identity and preserves the shipped Doris behavior.
**Verified:** 2026-08-07
**Status:** human_needed (1 backstop abstention routed to human; 1 deferred to Phase 13)
**Re-verification:** No — initial verification

## Goal Achievement

Goal-backward: "explicit dialect/profile selection at every public boundary" + "one neutral product identity" + "preserves shipped Doris behavior" were each verified against the live codebase (built binaries, executed gates, run test suites), not against SUMMARY claims.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | **SC1** — Structured configuration error for missing/unknown/conflicting dialect/profile through API, CLI, LSP, JS/Wasm, Web, VS Code, IntelliJ; no entry point silently detects or falls back | ✓ VERIFIED | Live binary: `fathom-sql` no-args/missing `--dialect`/unknown dialect/flink+4.x all exit 2 with structured usage errors; `parse_with_ids` dialect-before-profile validation (api/api.mbt:79-100, UnknownDialect/ConflictingSelection); LSP: bare `fathom-lsp` initialize → `-32602`, unresolvable document → single FATHOM-SCHEMA-007 config diagnostic (lsp/handlers.mbt `config_diagnostic`), serve_stdio-vs-initializationOptions conflict → "conflicting dialect/profile selections"; JS/Wasm export tests assert fathom.error.v1 + FATHOM-SCHEMA-003/007; web `validateSelection` + MISSING_SELECTION; VS Code config keys "No default: missing selection is an explicit configuration error (D-02)" |
| 2 | **SC2** — Selected dialect controls independent keyword classification and explicit statement/clause route; Doris and Flink policies cannot change each other's acceptance/recovery | ✓ VERIFIED | `doris_classification_rows` = 116 rows (counted in dialect/doris.mbt:275-455) + `flink_classification_rows = []` (dialect/flink.mbt); all classification queries take DialectContext, zero parameterless public queries (verified in dialect/ and token/); `classification_is_dialect_independent_and_flink_rows_are_empty` test; single `parse_segment` router (parser/parser.mbt:3336) matching `context.dialect` → `parse_doris_segment` (v1 body) / `parse_flink_segment` (FATHOM-PARSE-008) |
| 3 | **SC3** — Parse/format/completion/LSP/serialized results expose dialect, profile, exact-release, strict/editor mode, byte spans, statement identity, stable FATHOM-* diagnostics | ✓ VERIFIED | Live CLI parse envelope: `{"schema_version":"fathom.parse.v1","dialect":"doris","profile":"4.x","exact_release":"4.x","feature_introduction":...,"mode":"strict","valid":true,...}`; format envelope fathom.format.v1 + dialect/exact_release; completion detail neutralized "SQL syntax keyword"; LSP diagnostics carry FATHOM-PARSE-008 + start_byte/end_byte (observed live); coordinates_test.mbt UTF-16/byte-span tests; FATHOM-PARSE-001..008 / FATHOM-FORMAT-001..007 / FATHOM-SCHEMA-001..007 / FATHOM-LSP-001 all emitted (binding/schema.mbt, formatter/format.mbt:132) |
| 4 | **SC4** — Public imports, binaries, exports, schemas, errors, LSP identity, editor settings, release assets, docs use neutral `fathom` naming; no old aliases; Doris only as dialect/profile/corpus/provenance value | ✓ VERIFIED | `moon.mod` name `fathom/sql`; 16 moon.pkg import prefixes `fathom/sql/*`; `fathom-sql` + `fathom-lsp` binaries build; four `fathom_*_v1` exports (#export_name == binding/moon.pkg js/wasm lists); four fathom.*.v1 schemas; `scripts/check_naming.py` exit 0 over 349 product files; controlled probe (forbidden pattern in non-exempt path) fails exit 1; my grep sweep found zero old names in product sources (only a stale `_build/` artifact); serverInfo.name "fathom-lsp" observed live |
| 5 | 09-01 — Every v1 Doris public behavior category frozen to bytes BEFORE any refactor (CST span, diagnostics, modes, formatter, completion, CLI, LSP, wire) | ✓ VERIFIED | `parity/baseline_test.mbt` = 213 `@test.T::snapshot` blocks; `parity/__snapshot__/` = 213 JSON files (1.9 MB); `moon test --package parity` (no --update) 228/228 on native, js, AND wasm — byte-level drift gate green |
| 6 | 09-01 — Frozen baseline enforceable: `moon test --package parity` fails on any byte difference; sha256 record pins corpus | ✓ VERIFIED | Parity gate green without --update; `sha256sum -c parity/baseline-hashes.txt` exit 0 (33 lines, all OK); CI parity-gate job additionally runs `sha256sum -c` (ci.yml:138-139, MI-04 fix 982264d applied) |
| 7 | 09-01 — Approved vs regression mechanically distinguishable | ✓ VERIFIED | `scripts/baseline_diff.py --left parity/__snapshot__ --right parity/__snapshot__ --approve approved-changes.md` → "ok: 213 snapshots, 0 approved diffs, 0 unexpected" exit 0; approved-changes.md register committed (15.6 KB) |
| 8 | 09-02 — Consumer parses SQL through explicit dialect+profile end-to-end; serialized output carries fathom.parse.v1 + dialect/profile/exact_release + FATHOM-PARSE-* | ✓ VERIFIED | Live CLI + parity/export_smoke_test.mbt `dialect_selection_is_explicit_end_to_end` (a): fathom_parse_v1(b"SELECT 1","doris","4.x","strict") → fathom.parse.v1, dialect doris, profile 4.x, valid true |
| 9 | 09-02 — Doris/Flink keyword classification independent; no parameterless public query | ✓ VERIFIED | Truth #2 evidence; token/token.mbt:24,45 `pub context : @dialect.DialectContext` |
| 10 | 09-02 — Statement/clause grammar routes explicitly by dialect; Flink never falls back (FATHOM-PARSE-008) | ✓ VERIFIED | `parse_flink_segment` (parser/parser.mbt:3405-3417) emits FATHOM-PARSE-008 "flink grammar is not yet implemented in this release"; live LSP flink document → FATHOM-PARSE-008 published (observed); no fallback path exists |
| 11 | 09-02 — Missing/unknown/conflicting selection → structured errors; validate_dialect_profile rejects all flink profiles in Phase 9; neutral messages | ✓ VERIFIED | binding/schema.mbt:40-48 (doris 2.1/3.x/4.x OK; flink → UnsupportedProfile; else UnknownDialect); live CLI flink message "flink has no released profiles yet (Phase 9)" (MI-02 fix); export_smoke asserts FATHOM-SCHEMA-003 + no "Doris" in flink error |
| 12 | 09-03 — Formatter dialect-aware end-to-end; Doris byte-identical; Flink-mode → structured unsupported-profile error | ✓ VERIFIED | `format_with_ids(raw, dialect_id, profile_id, ...)`; export_smoke `format_export_is_dialect_aware_with_neutral_wire_identity` (c): flink → fathom.error.v1 + FATHOM-SCHEMA-003, no `"accepted"`; baseline gate green (0 format snapshots changed bytes) |
| 13 | 09-03 — Completion dialect-aware; doris items only in doris mode; flink → structured error; neutral detail | ✓ VERIFIED | completion/completion.mbt:145 dialect-first; detail "SQL syntax keyword"; flink → UnknownProfile; lsp/completion_test `completion_is_dialect_aware_with_neutral_detail` (in 466/466 suite) |
| 14 | 09-03 — Wire identity complete: fathom_format_v1 export + moon.pkg sync; fathom.format.v1; FATHOM-FORMAT-001..007 | ✓ VERIFIED | binding/exports.mbt:37-38; binding/schema.mbt:4; formatter/format.mbt:132 FATHOM-FORMAT-001; FATHOM-FORMAT-002/003/004 at export boundary |
| 15 | 09-04 — Module identity neutral: moon.mod fathom/sql; all 16 moon.pkg prefixes; CLI package fathom-sql → fathom-sql.exe | ✓ VERIFIED | moon.mod `name = "fathom/sql"`; import prefixes verified in moon.pkg files; binary `_build/native/release/build/fathom-sql/fathom-sql.exe` built and executed |
| 16 | 09-04 — CLI D-11 contract: parse\|format\|lsp, --dialect/--profile required, exit 2 on missing/unknown, no default dialect | ✓ VERIFIED | Live binary matrix: no-args → 2, missing --dialect → 2, unknown dialect → 2, flink+4.x → 2, valid doris parse → 0 with fathom.parse.v1; fathom-sql/cli_test.mbt exit-code matrix in suite |
| 17 | 09-04 — CLI lsp subcommand and fathom-lsp binary run the SAME server loop via serve_stdio | ✓ VERIFIED | `lsp/serve.mbt:11 pub fn serve_stdio(initial_dialect, initial_profile)`; run.mbt:121 `@lsp.serve_stdio(Some(command.dialect), Some(command.profile))`; fathom-lsp/main.mbt `@lsp.serve_stdio(None, None)`; both binaries live-tested with LSP initialize handshake |
| 18 | 09-04 — Release packaging neutral: fathom-native-release.yml, fathom-lsp-{platform}, fathom-lsp-manifest.json, fathom-sql-intellij | ✓ VERIFIED | `.github/workflows/fathom-native-release.yml` (renamed from doris-native-release.yml); jetbrains-plugin.yml artifact fathom-sql-intellij; jetbrains/settings.gradle.kts rootProject.name = "fathom-sql-intellij" |
| 19 | 09-05 — Wire contract fully neutral and complete: four fathom.*.v1 schemas + four fathom_*_v1 exports in #export_name AND moon.pkg lists | ✓ VERIFIED | binding/exports.mbt:29-104 (all four #export_name); binding/moon.pkg js+wasm exports lists identical; parity/export_smoke_test `exports_are_primitive_and_versioned` asserts all four schema strings |
| 20 | 09-05 — validate_dialect_profile is the single gate; doris exactly 2.1/3.x/4.x; flink rejects all; UnknownDialect; FATHOM-SCHEMA-007 for ConflictingSelection | ✓ VERIFIED | binding/schema.mbt:40-48; schema_test.mbt matrix (2.1/3.x/4.x Ok, 5.x/flink UnsupportedProfile, mysql UnknownDialect); binding/schema.mbt:138-143 ConflictingSelection → FATHOM-SCHEMA-007 |
| 21 | 09-05 — fathom_dialect_v1 / fathom_capabilities_v1 return profile availability + version metadata | ✓ VERIFIED | export_smoke asserts fathom.dialect.v1 + "dialect":"doris" + "id":"4.x"; capabilities lists both dialect names; provenance from DorisProfile metadata via ParseOptions::profile_metadata (MI-01 fix: no fabricated fallback) |
| 22 | 09-05 — Every serialized result carries dialect/profile/exact_release + FATHOM-*; no doris.*.v1 / doris_*_v1 / DORIS-* in product files | ✓ VERIFIED | Naming gate exit 0 over 349 files; my repo-wide grep found zero old schema/export/code strings in product sources |
| 23 | 09-06 — LSP resolves explicit dialect+profile per document via D-01 three-level precedence (document > workspace > languageId mapping); missing everywhere → structured config error, no implicit fallback | ✓ VERIFIED | `resolve_selection_with_source` (lsp/handlers.mbt:296); `config_diagnostic` FATHOM-SCHEMA-007 (lsp/handlers.mbt:168-183); live: bare fathom-lsp initialize → -32602; document-level flink selection honored (observed); lsp/selection_test.mbt (a)-(g) in suite |
| 24 | 09-06 — Every document carries its own dialect/profile; no global profile string on ServerState | ✓ VERIFIED | Document.dialect/profile/selection_source/language_id (lsp/documents.mbt:10-22); ServerState.default_dialect/default_profile nullable (handlers.mbt:35-36); ServerState.profile removed (grep clean) |
| 25 | 09-06 — Switching dialect re-parses current revision; version+selection-guarded publication drops stale results | ✓ VERIFIED | `publish_diagnostics_current` checks version AND dialect AND profile (handlers.mbt:136-144); selection_wbtest (i) white-box stale-guard test in suite; selection_test (h) doris→flink switch re-parse |
| 26 | 09-06 — LSP identity neutral: serverInfo fathom-lsp, source fathom, FATHOM-LSP-001, FATHOM-* codes | ✓ VERIFIED | Live initialize response: `"serverInfo":{"name":"fathom-lsp","version":"0.1"}`; source "fathom" (handlers.mbt:96,151); FATHOM-LSP-001 fallback (handlers.mbt:178) |
| 27 | 09-06 — Flink-selected document produces explicit FATHOM-PARSE-008, never silent empty result or Doris acceptance | ✓ VERIFIED (non-empty input) | Live: didOpen `text: 'SELECT 1'` with dialect=flink → publishDiagnostics FATHOM-PARSE-008 "flink grammar is not yet implemented in this release" with byte span data |
| 28 | 09-07 — VS Code neutral identity + dialect-aware settings, no default dialect | ✓ VERIFIED | vscode/package.json: name fathom-sql-language-client, displayName "Fathom SQL Language Client", language id sql, fathom.dialect (enum doris/flink, NO default), fathom.profile (NO default), fathom.serverPath default fathom-lsp, fathom.restartLanguageServer; `npm run build` (tsc) exit 0; normalizeProfile '4.x' fallback deleted |
| 29 | 09-07 — Web/npm neutral identity with dialect selector; offline smoke builds and runs | ✓ VERIFIED | web/package.json `@fathom/sql-web-demo`; monaco-adapter calls `fathom_parse_v1(utf8Bytes(source), dialect, profile, 'editor')` (A4 order) + checks fathom.error.v1; `npm run build` offline smoke live → "local artifact/dialect/refusal contracts passed" exit 0 |
| 30 | 09-07 — IntelliJ neutral identity; fathom-lsp defaults; no default profile | ✓ VERIFIED | fathom.jetbrains.sql package; FathomSettings DEFAULT_EXECUTABLE "fathom-lsp" (DEFAULT_PROFILE deleted); plugin id fathom.sql; server id fathom-sql; artifact fathom-sql-intellij; initializationOptions {dialect, profile}; `python3 jetbrains/scripts/source-smoke.py` live → "SOURCE SMOKE PASSED" exit 0 |
| 31 | 09-07 — README/docs neutral titles with dialect+profile tables; CI naming gate runs on every push; final sweep zero hits | ✓ VERIFIED | check_naming.py exit 0 over 349 product files (README/docs included); naming-gate job in ci.yml:159+; controlled probe (temp .ts with "doris-lsp") → exit 1 "naming gate failed" |

**Score:** 31/31 truths verified (0 present-behavior-unverified among the hard must-haves; 1 backstop abstention routed to human below)

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Live-host VS Code/IntelliJ dialect-selection UX + config precedence verification (probe NAME-03 unclassified) | Phase 13 | Phase 13 SC4 "each host selects Doris or Flink per file/session" + Validation "real Web/Monaco/VS Code/IntelliJ artifact smoke; verify document revision/stale-response and selection-conflict cases" |

### Required Artifacts

| Artifact | Expected | Status | Details |
| -------- | -------- | ------ | ------- |
| `dialect/dialect.mbt` | Dialect enum + DialectContext | ✓ VERIFIED | Closed enum Doris\|Flink; DialectContext(dialect, profile_id, exact_release, feature_introduction); pub(all) |
| `dialect/classification.mbt` | KeywordEntry, context-routed queries | ✓ VERIFIED | classification_of/is_clause_keyword/is_reserved_word/is_unquoted_identifier/classification_entries all take DialectContext; no parameterless public query |
| `dialect/doris.mbt` | 116 rows verbatim + preserved D-05 names | ✓ VERIFIED | doris_classification_rows = 116 rows; DorisProfile/DorisFeature/ValidatedProfileContext/ProfileMetadata preserved |
| `dialect/flink.mbt` | FlinkProfile placeholder + empty rows | ✓ VERIFIED | `pub enum FlinkProfile {}`; `flink_classification_rows = []` (Phase 10 fills) |
| `parser/parser.mbt` | parse_segment router + FATHOM-PARSE-008 | ✓ VERIFIED | Router at :3336; parse_doris_segment = v1 body; parse_flink_segment → FATHOM-PARSE-008 source-backed node |
| `api/api.mbt` | ParseOptions::new(dialect, profile, mode), parse_with_ids, UnknownDialect/ConflictingSelection, ParseResult.dialect | ✓ VERIFIED | :79 dialect-first validation; :422 parse_with_ids; :49/:60 error variants; :366 parse with fathom.parse.v1 envelope |
| `binding/exports.mbt` + `schema.mbt` + `moon.pkg` | Four fathom_*_v1 exports + four fathom.*.v1 schemas + validate_dialect_profile | ✓ VERIFIED | #export_name at :29/:37/:98/:103; moon.pkg js/wasm exports synced; validate_dialect_profile :40-48 |
| `fathom-sql/` CLI | D-11 contract | ✓ VERIFIED | args.mbt UsageError + required --dialect/--profile; run.mbt exit 0/1/2; live exit-code matrix |
| `lsp/serve.mbt` + `fathom-lsp/` | Shared serve_stdio seam | ✓ VERIFIED | serve_stdio(:11); fathom-lsp/main.mbt calls serve_stdio(None, None); both binaries live-tested |
| `lsp/handlers.mbt` + `documents.mbt` | Document-level selection + stale guard + neutral identity | ✓ VERIFIED | resolve_selection_with_source; publish_diagnostics_current version+selection guard; serverInfo fathom-lsp |
| `scripts/check_naming.py` | NAME-04 forbidden/allowlist gate | ✓ VERIFIED | Exit 0 (349 files); probe fails exit 1; D-04 exemptions + D-05 allowlist; ROOT-relative exclusions (MI-03 fix) |
| `parity/baseline_test.mbt` + `__snapshot__/` + `baseline-hashes.txt` | Frozen v1 baseline | ✓ VERIFIED | 213 snapshot tests; 213 snapshot files; 33 sha256 lines all OK; no-update gate green |
| `scripts/baseline_diff.py` + `approved-changes.md` | Approved-vs-regression gate | ✓ VERIFIED | 0 approved / 0 unexpected exit 0; register committed |
| `vscode/`, `web/`, `jetbrains/` | Neutral host identities | ✓ VERIFIED | package.json/plugin.xml/gradle verified; vscode tsc build, web offline smoke, jetbrains source-smoke all live-pass |

### Key Link Verification

| From | To | Via | Status | Details |
| ---- | --- | --- | ------ | ------- |
| dialect/classification.mbt | token/token.mbt | Token.context : @dialect.DialectContext (dialect <- token dependency direction) | WIRED | token/token.mbt:24,45; token imports dialect |
| parser/parser.mbt | dialect/dialect.mbt | parse_segment matches context.dialect — single router | WIRED | :3345-3346 |
| api/api.mbt | dialect/dialect.mbt | ParseOptions holds DialectContext; dialect validated before profile | WIRED | :79-100 |
| binding/exports.mbt | binding/moon.pkg | #export_name == js/wasm exports lists | WIRED | Both lists identical (fathom_parse_v1/format_v1/dialect_v1/capabilities_v1) |
| fathom-sql/run.mbt | lsp/serve.mbt | run_lsp → @lsp.serve_stdio(Some(dialect), Some(profile)) | WIRED | :121; live handshake |
| lsp/handlers.mbt | api/api.mbt | parse_document_context → parse_with_ids(document.dialect, ...) / parse_flink_not_implemented | WIRED | :162-166; live P-008 publish |
| lsp/handlers.mbt | binding/schema.mbt | validate_selection via binding gate | WIRED | validate_selection + FATHOM-SCHEMA-007 |
| scripts/check_naming.py | .github/workflows/ci.yml | naming-gate job runs python3 scripts/check_naming.py | WIRED | ci.yml:159+; live exit 0/1 |
| web/src/monaco-adapter.ts | binding/exports.mbt | module.fathom_parse_v1(utf8Bytes(source), dialect, profile, 'editor') | WIRED | A4 order; offline smoke passes |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| -------- | ------------- | ------ | ------------------ | ------ |
| fathom_parse_v1 envelope | dialect/profile/exact_release | ParseOptions → DorisProfile.metadata() | Real metadata from profile tables (no fabrication; MI-01 fix removes silent V4_X) | ✓ FLOWING |
| LSP publishDiagnostics | FATHOM-PARSE-008 + byte spans | parse_flink_not_implemented → parser route | Source-backed node with start_byte/end_byte (observed live) | ✓ FLOWING |
| fathom_dialect_v1 | profiles + exact_release | ParseOptions::profile_metadata → DorisProfile metadata | Real 2.1/3.x/4.x rows with provenance | ✓ FLOWING |
| CLI parse stdout | fathom.parse.v1 envelope | @binding.parse_result_json → api parse result | Real serialized CST + diagnostics (live output) | ✓ FLOWING |
| doris_classification_rows | keyword acceptance | dialect/doris.mbt 116-row table | Byte-identical to v1 (baseline gate) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Baseline drift gate (no --update) | `moon test --package parity` | 228/228 pass (native) | ✓ PASS |
| Cross-target byte equality | `moon test --target js/wasm --package parity` | 228/228 each | ✓ PASS |
| Full CI-aligned native suite | `moon test --target native --package test parity lsp api source token lexer parser printer syntax completion analyzer formatter dialect fathom-sql` | 466/466 pass | ✓ PASS |
| Naming gate | `python3 scripts/check_naming.py` | `ok: 349 product files scanned, zero forbidden naming remnants`, exit 0 | ✓ PASS |
| Naming gate negative | temp `.ts` with "doris-lsp" | `naming gate failed: 1 problem(s)`, exit 1 | ✓ PASS (gate works) |
| Baseline diff self-check | `python3 scripts/baseline_diff.py --left parity/__snapshot__ --right parity/__snapshot__ --approve approved-changes.md` | `ok: 213 snapshots, 0 approved diffs, 0 unexpected`, exit 0 | ✓ PASS |
| Corpus provenance | `sha256sum -c parity/baseline-hashes.txt` | 33/33 OK, exit 0 | ✓ PASS |
| CLI D-11 matrix | `fathom-sql` no-args / missing --dialect / unknown dialect / flink+4.x / valid parse | exit 2/2/2/2/0 with correct messages | ✓ PASS |
| LSP initialize (serve_stdio defaults, no initializationOptions) | JSON-RPC initialize → `fathom-sql lsp --dialect doris --profile 4.x` | result + `serverInfo.name` "fathom-lsp" (MA-01 fix works) | ✓ PASS |
| LSP bare (no defaults) | `fathom-lsp` initialize | `-32602` "initialize requires initializationOptions..." | ✓ PASS (no silent fallback) |
| LSP flink document (non-empty) | didOpen `SELECT 1` dialect=flink | publishDiagnostics FATHOM-PARSE-008, source fathom | ✓ PASS |
| Web offline smoke | `npm run build` in web/ | `web offline smoke: local artifact/dialect/refusal contracts passed` | ✓ PASS |
| VS Code build | `npm run build` (tsc) in vscode/ | exit 0 | ✓ PASS |
| JetBrains source-smoke | `python3 jetbrains/scripts/source-smoke.py` | "SOURCE SMOKE PASSED" | ✓ PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` probes declared in this phase's plans; the phase's runnable gates (parity suite, baseline_diff.py, check_naming.py, smoke scripts) were executed directly above with live results. Step 7c: not applicable.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| ----------- | ----------- | ----------- | ------ | -------- |
| DIALECT-01 | 09-02/04/06/07 | Explicit dialect/profile selection at API/CLI/LSP/JS-Wasm/Web/VS Code/IntelliJ; structured errors; no auto-detection/fallback | ✓ SATISFIED | Truths 1, 8, 11, 16, 23, 28-30; live CLI/LSP matrices |
| DIALECT-02 | 09-02/03 | Independent Doris/Flink lexical/keyword policy; no global union | ✓ SATISFIED | Truths 2, 9, 12-13; 116-row + empty-row arrays; independence test |
| DIALECT-03 | 09-02/03/06 | Explicit statement/clause routing by dialect; no try-all; localized diagnostics | ✓ SATISFIED | Truths 10, 27; parse_segment router; FATHOM-PARSE-008 live; empty-input edge is a tracked human item (below), not a requirement-text violation |
| DIALECT-04 | 09-01/02/05/06 | Metadata + strict/editor mode + spans + statement identity + stable FATHOM-* across boundary | ✓ SATISFIED | Truths 3, 5-7, 19-22; 213 snapshot freeze; envelope fields live-verified |
| NAME-01 | 09-04/07 | Clean cutover to fathom/sql, fathom-sql, fathom-lsp; no old aliases | ✓ SATISFIED | Truths 4, 15, 17, 31; moon.mod + binaries + gate |
| NAME-02 | 09-02/03/05 | fathom.parse/format/error/capabilities.v1 + FATHOM-* + dialect fields | ✓ SATISFIED | Truths 14, 19-22; four schemas/exports verified |
| NAME-03 | 09-04/07 | VS Code/IntelliJ/Web/CI/assets/config/LSP/docs neutral naming; Doris only as dialect value | ✓ SATISFIED (static) | Truths 4, 18, 28-31; live-host UX deferred to Phase 13 (deferred list) |
| NAME-04 | 09-07 | CI naming inventory/allowlist gate rejects product remnants | ✓ SATISFIED | Truth 31; gate exit 0 + negative probe exit 1 + ci.yml job |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| — | — | TBD/FIXME/XXX debt markers in phase-modified product files | ℹ️ Info | None found in dialect/, api/, binding/, parser/, lsp/, fathom-sql/, fathom-lsp/ |
| dialect/flink.mbt | 1-8 | "placeholder" wording | ℹ️ Info | Intentional Phase 9 design: FlinkProfile empty enum + empty rows are the documented Phase 10 boundary, not stubs |
| parser/parser.mbt | 3417 | "flink grammar is not yet implemented in this release" | ℹ️ Info | The designed FATHOM-PARSE-008 explicit rejection (DIALECT-03/A1), not a stub |

No debt markers, no empty-implementation stubs, no hardcoded-empty data paths in the phase's product surface.

### Human Verification Required

1. **Empty-Flink-input contract (backstop probe DIALECT-03 empty, abstained)**
   - **Test:** Open a zero-byte document with a `flink` document-level selection in `fathom-lsp` (or call `parse_flink_not_implemented(b"", ...)`) and observe the published diagnostics.
   - **Expected:** Current behavior publishes an empty diagnostics array — a silent empty success. The flagged probe asserted FATHOM-PARSE-008 ("never a silent empty success"); the executor documented mutual exclusion with the single-router prohibition (09-02 decisions; WINDOWS.md #4 open deviation). Human must decide whether the documented deviation is the accepted Phase 9 contract or whether the empty case must also be FATHOM-PARSE-008 (a later-phase change).
   - **Why human:** Both alternatives are defensible and mutually exclusive under the current single-router design; presence checks cannot adjudicate the contract; the decision was deliberately deferred out of the plan's acceptance criteria (which cover non-empty Flink rejection only — that IS implemented).

### Gaps Summary

No blocking gaps. All 31 substantive must-have truths and all 8 requirement IDs (DIALECT-01..04, NAME-01..04) are satisfied with live codebase evidence: the baseline freeze is byte-enforced (228/228 no-update parity on native/js/wasm, sha256-pinned corpus, 0 unexpected diffs), explicit dialect/profile selection works at API/CLI/LSP/JS-Wasm/Web/VS Code/IntelliJ with structured errors and no silent fallback, Doris classification is structurally independent from the empty Flink table, Flink input is explicitly rejected with FATHOM-PARSE-008 (never Doris), and the naming gate exits 0 over 349 product files with a working negative probe. Code review findings 14/14 are fixed (all fix commits verified in git history; key fixes re-verified in code: MA-01 serve_stdio-default fallback live-tested, MI-01 profile() Option, MI-02 flink CLI message, MI-03 ROOT-relative exclusions + zero-scan hard fail, MI-04 sha256sum -c in CI, MI-06 flink format structured error).

Two backstop (flagged-assumption) items are surfaced per the honest-verifier protocol: (1) the empty-Flink-input behavior deviates from the flagged probe assertion and needs a human contract decision (behavior_unverified_items), and (2) live-host VS Code/IntelliJ UX verification is deferred to Phase 13 (deferred). Neither is a failed must-have; both are tracked.

---

_Verified: 2026-08-07_
_Verifier: Claude (gsd-verifier)_
