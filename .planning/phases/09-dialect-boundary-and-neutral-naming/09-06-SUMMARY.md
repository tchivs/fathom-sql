---
phase: 09-dialect-boundary-and-neutral-naming
plan: 06
subsystem: lsp
tags: [moonbit, lsp, dialect-selection, d-01, d-02, d-03, fathom-lsp, fathom-schema-007, fathom-parse-008, parity, baseline]

# Dependency graph
requires:
  - phase: 09-dialect-boundary-and-neutral-naming
    provides: "09-04: lsp/serve.mbt serve_stdio(initial_dialect, initial_profile) workspace-default seam; 09-05: @binding.validate_dialect_profile + FATHOM-SCHEMA-007 + fathom.parse.v1; 09-02: @api.parse_with_ids dialect-first signature + parser FATHOM-PARSE-008 flink route"
provides:
  - "LSP document-level DialectContext: Document.dialect/profile/selection_source/language_id; every parse/format/completion call runs under the document's own context"
  - "D-01 three-level selection resolution (document config > workspace default > languageId mapping) with structured config errors (FATHOM-SCHEMA-007 / -32602 / showMessage) — no implicit fallback (D-02)"
  - "D-03 dialect-switch reparse: didChangeConfiguration / workspace/configuration / didOpen / didChange re-resolve and re-parse the current revision; version+selection-guarded publication drops stale results"
  - "Neutral LSP identity: serverInfo fathom-lsp, diagnostic source fathom, FATHOM-LSP-001 fallback, FATHOM-* codes over publishDiagnostics"
  - "@api.parse_flink_not_implemented (additive): flink-selected documents parse to the FATHOM-PARSE-008 not-implemented route, never Doris"
  - "parity/fixtures/lsp-tracer.json migrated to fathom.parse.v1/fathom.format.v1 with the dialect field (09-05 deferral closed)"
affects: [09-07, 09-08, release-planning]

# Actuals (#2632) — pairs with the plan's `estimate` (40000 tokens) to calibrate future estimates.
actuals:
  tokens: 11316     # chars/4 over realized diff (41580 added + 3683 deleted chars)
  tasks: 4
  commits: 3        # 3 task commits (+ 1 final metadata commit)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "D-01 three-level precedence as one resolver: resolve_selection_with_source returns (selection, source) so a workspace-default change re-resolves only non-document-level documents (D-03)"
    - "Version+selection publication guard: publish_diagnostics_current drops any result whose version OR dialect/profile no longer matches the stored document — the concurrency contract for async parse results (probe DIALECT-01)"
    - "Closed-enum selection validation at the LSP boundary: unknown dialect rejected; doris profile via binding gate; flink accepted as a legal Phase 9 selection whose parse is the explicit not-implemented route (A1)"
    - "Settings all-or-nothing (T-09-19): any invalid entry in a fathom settings section rejects the whole update via window/showMessage"

key-files:
  created: [lsp/selection_test.mbt, lsp/selection_wbtest.mbt]
  modified: [lsp/handlers.mbt, lsp/documents.mbt, lsp/protocol_test.mbt, lsp/diagnostics_formatting_test.mbt, lsp/lifecycle_test.mbt, lsp/selection_test.mbt, parity/fixtures/lsp-tracer.json, api/api.mbt, approved-changes.md, deferred-items.md]

key-decisions:
  - "Task 1 auto-selected option-a (mode: yolo): locked D-01/D-02 precedence + A2 transport — document-level config rides didOpen/didChange textDocument extension fields, workspace default from initializationOptions OR serve_stdio args (conflict -> -32602), languageId mapping only from user config, missing everywhere -> single FATHOM-SCHEMA-007 config diagnostic"
  - "flink is a legal LSP selection in Phase 9 (A1): selection validation accepts {flink, any profile} (dialect closed-enum; doris profiles still gated); the parse routes through the new @api.parse_flink_not_implemented -> FATHOM-PARSE-008, and format/completion reject with the api unsupported-profile error (T-09-23, never Doris policy)"
  - "D-03 guard compares version AND selection: publish_diagnostics_current drops results whose version or dialect/profile differ from the stored document — catches both stale versions and stale-selection async results"
  - "Document-level config is sticky across edits: didChange without extension fields keeps the stored context; didChangeConfiguration re-resolves only documents whose selection_source != 'document'"
  - "workspace/configuration pull (option-c arm) correlates by pending request id; the server emits one request after 'initialized' and treats only the matching id as the settings response (uncorrelated -> -32601)"
  - "completion_test.mbt and parity/baseline_test.mbt needed no dialect-arg changes: completion_test exercises @completion.complete directly with 'doris' already, and the LSP homomorph callsites have passed the dialect argument since 09-02 (plan text stale)"

requirements-completed: [DIALECT-01, DIALECT-03, DIALECT-04]

coverage:
  - id: D1
    description: "D-01/D-02 explicit selection over LSP with structured config errors: resolve_selection precedence (document > workspace > mapping), initialize/didOpen/didChangeConfiguration error surface, no implicit languageId fallback (T-09-19/20/21)"
    requirement: DIALECT-01
    verification:
      - kind: unit
        ref: "lsp/selection_test.mbt (a)-(g): -32602 for missing/unknown/conflicting initialize, FATHOM-SCHEMA-007 config diagnostic for unresolvable documents, mapping + precedence tests; 32/32 lsp tests pass"
        status: pass
      - kind: unit
        ref: "grep gates: zero state.profile / 'unsupported Doris' / DORIS-LSP-001 / doris-lsp / source doris in lsp/"
        status: pass
    human_judgment: false
  - id: D2
    description: "D-03 dialect-switch reparse + stale-response guard; flink rejection over LSP (FATHOM-PARSE-008, never Doris)"
    requirement: DIALECT-03
    verification:
      - kind: unit
        ref: "selection_test (h): didChangeConfiguration doris->flink re-parses and publishes FATHOM-PARSE-008 'flink grammar is not yet implemented'; selection_wbtest (i): stale version + stale selection publications dropped by the guard; (j): flink format -> empty edit refusal, completion -> -32602"
        status: pass
      - kind: unit
        ref: "api/parse_flink_not_implemented + parser route: non-empty flink input yields the source-backed FATHOM-PARSE-008 statement (mirrors 09-02 export_smoke route)"
        status: pass
    human_judgment: false
  - id: D3
    description: "DIALECT-04/NAME-02/NAME-03 LSP surface: document context metadata, fathom-lsp identity, fathom.parse.v1 fixture, baseline gate green"
    requirement: DIALECT-04
    verification:
      - kind: unit
        ref: "diagnostics_formatting_test asserts source fathom + FATHOM-PARSE-* and absence of doris/DORIS-; serverInfo fathom-lsp; lsp-tracer.json fathom.parse.v1 + dialect doris"
        status: pass
      - kind: integration
        ref: "moon test --target native --package lsp --package api --package parity 268/268; baseline_diff 213 snapshots, 0 approved, 0 unexpected (exit 0); drift gate moon test --package parity 228/228 without --update"
        status: pass
    human_judgment: false

status: complete
---

# Phase 9 Plan 6: LSP Document Dialect Context — Selection Resolution, D-03 Switch/Stale Guard, Neutral Identity

**One-liner:** Delivered the LSP boundary of DIALECT-01/03/04 — per-document dialect/profile context resolved through the D-01 three-level precedence with structured config errors (FATHOM-SCHEMA-007 / -32602 / showMessage), dialect-switch reparse with a version+selection-guarded stale drop, flink rejection via the FATHOM-PARSE-008 not-implemented route, and the neutral fathom-lsp identity closing the 09-05 deferred LSP items.

## Accomplishments

- **Document-level DialectContext (D-03):** `Document` carries `dialect`/`profile`/`selection_source`/`language_id`; `DocumentStore::open`/`change` accept the resolved selection, `update_selection` rewrites contexts in place on settings changes, and `documents()` iterates for re-resolution. Every parse/format/completion call runs under the document's own context — the global `ServerState.profile` field is gone.
- **D-01 three-level resolution:** `resolve_selection_with_source` implements document-level explicit config (didOpen/didChange `textDocument` extension fields) > workspace/session default (`initializationOptions`/serve_stdio args) > user-configured languageId mapping, returning the winning source so workspace-default changes only re-resolve non-document-level documents. `initialize_selection` rejects missing/unknown/conflicting selections with neutral `-32602` messages (same-source serve_stdio-vs-initializationOptions conflict included).
- **D-02 no-guess rule:** an unresolvable document publishes exactly one `FATHOM-SCHEMA-007` config diagnostic (source fathom) naming the missing/unknown/conflicting item and is never parsed; languageId participates only through a configured mapping.
- **Settings push + pull (A2):** `workspace/didChangeConfiguration` stores the fathom section (`dialect`/`profile` default + `languageMapping`) with all-or-nothing validation (invalid -> `window/showMessage`); the optional `workspace/configuration` server-to-client pull is emitted once after `initialized` and correlated by pending request id.
- **D-03 switch + stale guard:** settings changes, didOpen, and didChange re-resolve and re-parse the current revision; `publish_diagnostics_current` drops any result whose stored version OR selection no longer matches — the concurrency contract for async parse results (probe DIALECT-01 truth).
- **Flink over LSP (T-09-23):** flink is a legal Phase 9 selection; its parse routes through the new additive `@api.parse_flink_not_implemented` to the 09-02 `FATHOM-PARSE-008` not-implemented route (never Doris), and formatting/completion return the structured api rejection (empty-edit refusal / `-32602`) — no Doris policy leak.
- **Neutral identity (NAME-03/NAME-02):** `serverInfo.name` fathom-lsp, diagnostic `source` fathom, `FATHOM-LSP-001` fallback, `FATHOM-*` codes; `parity/fixtures/lsp-tracer.json` migrated to `fathom.parse.v1`/`fathom.format.v1` + `"dialect":"doris"` (09-05 deferral closed); `DORIS-LSP-001`/`doris-lsp`/`source doris`/`state.profile`/`unsupported Doris` greps over lsp/ are all zero.
- **Smoke matrix:** `lsp/selection_test.mbt` (a)-(g) + push/pull/invalid-settings tests + (h)/(j); `lsp/selection_wbtest.mbt` (i) drives the stale guard white-box. protocol/diagnostics/lifecycle tests updated to the dialect-bearing initialize shape.

## Baseline Gate (D-08)

- Section 12 registered in `approved-changes.md` (lsp-tracer fixture schema swap, LSP homomorph dialect fields, A2 extension-field transport) and committed BEFORE the single approved `moon test --update --package parity` runs — both produced **zero snapshot byte changes** (the LSP homomorph callsites have passed `"doris"` since 09-02).
- Genuine drift gate `moon test --package parity` (no `--update`) green on every run (228/228).
- `scripts/baseline_diff.py --left <git archive HEAD:parity/__snapshot__> --right parity/__snapshot__ --approve approved-changes.md` → `ok: 213 snapshots, 0 approved diffs, 0 unexpected` (exit 0) after Tasks 2 and 4.
- Final sweep: `moon test --target native --package lsp --package api --package parity` 268/268.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added `@api.parse_flink_not_implemented` (api/api.mbt)**
- **Found during:** Task 2 (wiring parse_document's flink path).
- **Issue:** the plan's key_link mandates `parse_document` → `@api.parse_with_ids` for the document context, and the must-have truth requires flink documents to publish FATHOM-PARSE-008 — but `ParseOptions::new("flink", …)` returns `Err(UnknownProfile)` for every profile (Phase 9, A1), so the api facade has NO path that produces FATHOM-PARSE-008; the only route is the parser's direct entry with a constructed Flink `DialectContext`.
- **Fix:** added the additive public entry `parse_flink_not_implemented(raw, profile_id, mode_id)` which builds the flink context (mirroring the 09-02 route test context) and runs the shared `parse()` envelope — LSP stays a thin api adapter (no parser import), Doris paths untouched, baseline unaffected.
- **Files modified:** api/api.mbt
- **Commit:** 1d23a04

**2. [Rule 3 - Blocking] Selection validation accepts flink at the LSP selection level**
- **Found during:** Task 2/3 (test (h) reachability).
- **Issue:** `@binding.validate_dialect_profile` rejects ALL flink profiles (`UnsupportedProfile`), so a flink-selected document could never resolve — the plan's test (h) ("switching the document dialect from doris to flink re-parses and publishes FATHOM-PARSE-008") and A1/D-01 ("flink 作为合法 dialect 值全链可用") require flink to be a legal SELECTION whose parse is the explicit not-implemented route.
- **Fix:** `validate_selection` applies the closed-enum rule — unknown dialects rejected; doris profiles pass through the binding gate; flink + any profile accepted as a Phase 9 legal selection (the profile rides as document metadata; profile rejection remains the parse-boundary concern). T-09-19's closed-enum/no-guess intent preserved.
- **Files modified:** lsp/handlers.mbt
- **Commit:** 1d23a04 (validation), fdc1b28 (mapping/settings surface)

**3. [Plan text stale - no change needed] completion_test.mbt / parity/baseline_test.mbt dialect arguments**
- **Found during:** Task 4 (payload sweep).
- **Issue:** the plan says lsp/completion_test.mbt initialize payloads gain `"dialect":"doris"` and parity/baseline_test.mbt LSP homomorph callsites gain the dialect argument — but completion_test.mbt exercises `@completion.complete` directly (no LSP initialize flow, dialect already passed) and the LSP homomorph (`parse_json`/`format_json`/`lsp_json`) has passed `"doris"` since 09-02. Nothing to change; documented so the plan's checklist does not imply missed work.

### Deferred (owned by later waves)

- `web/scripts/offline-smoke.mjs` `DORIS-FORMAT-001` assertions → 09-07 (host sweep; file also carries another agent's uncommitted monaco WIP).
- `vscode/src/host-test.ts` + `vscode/README.md` `DORIS-PARSE-006` → 09-07 (hosts).
- Empty-flink-input silent-empty-document probe (WINDOWS.md #4, DIALECT-03 empty) — unchanged by this wave; flink LSP parses for non-empty input publish FATHOM-PARSE-008.

## Decisions Made

- Task 1 checkpoint:decision auto-selected **option-a** (mode: yolo, gate blocking — not blocking-human): locked D-01/D-02 precedence + A2 transport, per the plan's recommended option.
- The D-03 guard compares version AND selection (`current.version == document.version && current.dialect == document.dialect && current.profile == document.profile`) — a same-version stale-selection result is dropped as well as an old-version one.
- Document-level config is sticky: didChange without extension fields preserves the stored context; only workspace/language-sourced documents re-resolve on settings changes.
- The `workspace/configuration` pull response rides `params.fathom` with the matching pending id (plan's method-carrying harness convention); uncorrelated ids are `-32601`.

## Known Stubs

None. All document paths resolve or produce a structured config diagnostic; flink documents produce FATHOM-PARSE-008 (non-empty) per the Phase 9 contract; the flagged-unverified empty-flink probe is tracked in WINDOWS.md #4, not introduced here.

## Self-Check: PASSED

- Task commits verified in git: `1d23a04` (Task 2 tracer — document dialect selection + neutral identity), `fdc1b28` (Task 3 — selection resolution + structured errors), `b64403c` (Task 4 — switch reparse + stale guard).
- `09-06-SUMMARY.md` exists in the plan directory (self-check below).
- Final verification commands all green: `moon test --target native --package lsp --package api --package parity` 268/268, `moon test --package parity` 228/228 (no `--update`), `baseline_diff.py` 0 approved / 0 unexpected (exit 0), lsp/ identity greps zero matches.
