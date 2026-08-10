# Phase 13: Toolchain and Editor Packaging — Pattern Map

**Mapped:** 2026-08-10
**Files analyzed:** 17 new/modified files (13 MoonBit/packaging + 4 host/test-harness groups)
**Analogs found:** 16 / 17 (the new `parity/flink_format_test.mbt` maps to the flink-grammar snapshot namespace; only the CI packaging-smoke job has a partial analog)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `formatter/layout.mbt` | formatter layout tables | transform (single-pass layout) | `layout.mbt` Doris `clause_breaks`/`statement_family`/`layout_statement` | exact |
| `formatter/format.mbt` | formatter refusal gate | request-response | `format.mbt` `find_first_unsafe` refusal wiring (D-33) | exact |
| `completion/completion.mbt` | service | request-response | `complete()` Doris branch + `profile_allows` + `completion_context` | exact |
| `dialect/flink.mbt` | config/data (classification table) | static lookup | existing 147-row `flink_classification_rows` + provenance test | exact |
| `analyzer/analyzer.mbt` | service (read-only syntax walk) | transform | `leading_prefix_end`/`target_table_name`/`resolve_table_references` Doris arms | exact |
| `api/api.mbt` | facade | request-response | `parse_flink` Flink-context construction + `format_with_ids` | exact |
| `lsp/handlers.mbt` | route/handler | request-response (LSP) | `formatting_result` + `completion_result` + `completion_item_json` | exact |
| `fathom-sql/run.mbt` | controller (CLI) | request-response | `run_format` (already calls `@api.format_with_ids`, no flink guard) | exact |
| `binding/exports.mbt` | provider (ABI export) | request-response | `fathom_format_v1` | exact |
| `binding/schema.mbt` | config/schema | transform | `format_result_json` + `validate_schema_version` + `validate_dialect_profile` | exact |
| `binding/moon.pkg` | config | n/a | existing js/wasm `exports` lists | exact |
| `web/src/monaco-adapter.ts` | adapter | request-response | `PROFILES` + `validateSelection` | exact |
| `web/scripts/offline-smoke.mjs` | test harness | n/a | flat-profile assert (same-commit update) | exact |
| `vscode/src/extension-contract.ts` + `extension.ts` | adapter/config | request-response | `SUPPORTED_PROFILES` + `resolveFathomConfiguration` | exact |
| `vscode/scripts/launch-smoke.mjs` + `host-verify.mjs` | test harness | n/a | flat-profile asserts + ECO-07 mode table | exact |
| `jetbrains/.../FathomSettings.kt` + `FathomSettingsConfigurable.kt` | config | n/a | `ALLOWED_PROFILES` + profile ComboBox | exact |
| `jetbrains/scripts/source-smoke.py` | test harness | n/a | `listOf("2.1","3.x","4.x")` assert (same-commit) | exact |
| `parity/flink_format_test.mbt` | test (NEW) | snapshot | `parity/flink_grammar_test.mbt` snapshot namespace | role-match |
| `parity/export_smoke_test.mbt` | test | n/a | `format_export_is_dialect_aware_with_neutral_wire_identity` | exact |
| `.github/workflows/ci.yml` | config/CI | pipeline | `linear-wasm-parity` / `parity-gate` job steps | partial |

## Pattern Assignments

### `formatter/layout.mbt` (formatter layout tables, transform)

**Analog:** `layout.mbt:171-218` (`clause_breaks`), `:273-292` (`statement_family`), `:857-873` (`layout_statement`), `:1-40` (`Layout` struct)

**Import / no-import convention:** layout.mbt is inside the `formatter` package and accesses `@syntax.SyntaxKind` qualified — the file already references `@syntax.SyntaxKind::Select` etc. New Flink families use the same qualified enum names from `syntax/syntax.mbt:38-62` (`ShowStatement`, `DescribeStatement`, `ExplainStatement`, `AnalyzeStatement`, `CreateCatalog`, `CreateDatabase`, `CreateFunction`, `DropCatalog`, `DropDatabase`, `DropTable`, `DropView`, `DropFunction`, `AlterTable`, `WatermarkClause`, `ComputedColumn`, `MetadataColumn`, `PrimaryKeyClause`, `TableLikeClause`, `WindowTvf`, `MatchRecognize`, `SetOption`, `UseStatement`).

**Core pattern — extend the per-family `clause_breaks` table (D-01):**
```moonbit
// layout.mbt:171-218 — each family is a match arm returning an Array[Bytes] of
// clause keywords that force a break. Doris Insert arm (layout.mbt:180-185):
@SyntaxKind::Insert => [
  b"INTO", b"VALUES", b"SELECT", b"PARTITION", b"WITH", b"LABEL",
]
// Flink families MUST get arms (e.g. CreateCatalog -> b"CREATE", b"CATALOG",
// b"WITH"; AlterTable -> b"ALTER", b"TABLE", b"ADD", b"DROP", b"RENAME",
// b"SET"; WindowTvf/MatchRecognize -> clause words from the parser forms). An
// uncovered family keeps `_ => []` — that is NOT a refusal today (Pitfall 1),
// so the completeness gate below is mandatory.
```

**Core pattern — `statement_family` is dialect-agnostic (reuse as-is):**
```moonbit
// layout.mbt:273-292 — returns the first non-Statement ChildNode kind under a
// Statement node. Reused unchanged; it already yields Flink families because
// the parser emits them as child kinds.
fn statement_family(node : @syntax.SyntaxNode) -> @syntax.SyntaxKind? { ... }
```

**Refusal channel — `Layout.failed` + `layout_statement` (D-01 gate hook):**
```moonbit
// layout.mbt:27-33 — the Layout struct carries `mut failed : SyntaxElement?`.
// layout.mbt:857-873 — layout_statement calls layout_sequence(...); a Flink
// covered-family gate should be checked BEFORE layout_sequence: if
// context.dialect is Flink && !flink_statement_covered(family) { out.failed =
// Some(first_child_of(node)); return }. The format.mbt loop (format.mbt:48-52)
// already converts any out.failed into a FATHOM-FORMAT-001 refusal with empty
// output.
```

### `formatter/format.mbt` (formatter refusal gate, request-response)

**Analog:** `format.mbt:8-30` (`format` refusal-first), `:70-93` (`find_first_unsafe`), `refuse.mbt:10-27` (`first_unsafe_element`), `error.mbt:29-41` (`FormatResult`)

**Core refusal contract (D-33) — reuse verbatim, do not fork:**
```moonbit
// format.mbt:11-24 — an unsafe tree yields accepted=false, empty output,
// exactly one FATHOM-FORMAT-001, never partial bytes:
match find_first_unsafe(root) {
  Some((element, statement_id)) => {
    let span = element.span()
    return {
      accepted: false, output: b"",
      diagnostics: [refusal_diagnostic(span, statement_id)],
      statement_offsets: [],
    }
  }
  None => ()
}
// The out.failed channel (format.mbt:48-52) feeds the same refusal path.
```
The new covered-family gate is a *programming-gap* refusal distinct from unsafe input: the planner should route uncovered Flink families through `out.failed` (see layout assignment) so `format()` produces the identical `FATHOM-FORMAT-001` shape. `FormatResult` (`error.mbt:29-41`) already carries `accepted/output/diagnostics/statement_offsets` — no new result type.

### `completion/completion.mbt` (service, request-response)

**Analog:** `completion.mbt:25` (`MAX_CANDIDATES`), `:57-65` (`profile_allows`), `:78-107` (`completion_context`), `:145-207` (`complete`)

**Core pattern — replace the Phase-9 Flink rejection with a real context (D-02):**
```moonbit
// completion.mbt:145-158 — complete() builds a DialectContext per dialect.
// The Doris arm (151-157) is the blueprint; the Flink arm currently returns
// Err(UnknownProfile(profile_id~)) and MUST mirror the Doris arm using
// @dialect.FlinkProfile::from_id + metadata() (see api/api.mbt:79-103):
@dialect.Dialect::Flink => {
  match @dialect.FlinkProfile::from_id(profile_id) {
    Some(profile) => {
      let metadata = profile.metadata()
      { dialect: dialect, profile_id: profile_id,
        exact_release: metadata.exact_release,
        feature_introduction: metadata.feature_introduction }
    }
    None => return Err(UnknownProfile(profile_id~))
  }
}
```

**Per-profile gating is already free (D-02) — extend `profile_allows`:**
```moonbit
// completion.mbt:57-65 — profile_allows currently `@dialect.Dialect::Flink =>
// false`. The classification pipeline ALREADY filters Flink rows by
// introduced_profile via flink_row_visible (classification.mbt:78-89), so the
// Flink arm can return true for entries whose introduced_profile the selected
// Flink profile includes — mirroring the Doris arm's match on entry.
// introduced_profile (57-64). No second candidate pool (D-28).
```

**Core pattern — extend `completion_context` with Flink arms (D-02):**
```moonbit
// completion.mbt:78-107 — the existing chain of word_is(last, ...) arms
// ("statement-start", "select", "from", ...). Add Flink arms keyed off the
// same last/previous token walk:
//   last==CREATE|DROP|ALTER         -> "ddl-header"
//   last==WATERMARK                 -> "watermark"
//   previous/last==PARTITIONED|BY   -> "partitioned-by"
//   last==FROM|JOIN at table pos    -> "window-tvf"   (TUMBLE/HOP/CUMULATE/SESSION)
//   inside MATCH_RECOGNIZE(...)     -> "match-recognize"
// Each arm then flows through the UNCHANGED context_accepts/context_preferred/
// prefix_matches pipeline and the two-pass MAX_CANDIDATES=32 loop
// (completion.mbt:182-205).
```

### `dialect/flink.mbt` (config/data — classification table, static lookup)

**Analog:** `flink.mbt:98-260` (the `flink_classification_rows` array), `:283-299` (provenance test)

**Core pattern — extend the single table, never a second list (D-02/D-28):**
```moonbit
// flink.mbt:98-99 — module-level `let flink_classification_rows :
// Array[KeywordEntry] = [ ... ]`. Every new row mirrors the exact 5-field
// KeywordEntry shape (classification.mbt:31-38) with provenance:
{ word: b"ALTER", classification: Reserved, introduced_profile: "flink-1.20.5",
  source: "flink-sql-parser Parser-release-1.20.5.tdd:NNN (ALTER)" }
// NonReserved additions are parse-neutral; Reserved additions change parse
// behavior and MUST be pre-declared in approved-changes.md (Pitfall 2) or the
// frozen flink-grammar/flink-lexical snapshots move.
```

**Test pattern — provenance audit (mirror `flink.mbt:283-299`):**
```moonbit
test "flink_classification_rows_source_references_release_grammar" {
  for row in flink_classification_rows {
    assert_true(row.source.contains("flink-sql-parser") &&
      (row.source.contains("Parser-release-") || row.source.contains("Parser-calcite-") ||
       row.source.contains("codegen/templates/Parser.jj")))
    assert_true(!row.source.contains("http"))
  }
}
```

### `analyzer/analyzer.mbt` (service — read-only syntax walk, transform)

**Analog:** `analyzer.mbt:168-220` (`leading_prefix_end`), `:241-260` (`target_table_name`), `:262-303` (`resolve_table_references`)

**Core pattern — add Flink arms to `leading_prefix_end` (D-03):**
```moonbit
// analyzer.mbt:168-220 — a positional skip over the statement's leading
// keyword tokens. Add arms for the Flink shapes the parser emits:
//   UPSERT INTO (parser maps UPSERT -> SyntaxKind::Insert, parser.mbt:4196)
//   INSERT OVERWRITE ... PARTITION (...) skip before the table name
//   CREATE [TEMPORARY] VIEW / CREATE CATALOG|DATABASE|FUNCTION leading words
@SyntaxKind::Insert => { ... } // extend with UPSERT/OVERWRITE/PARTITION arms
```

**Core pattern — extend the matched-kind set in `resolve_table_references` (D-03):**
```moonbit
// analyzer.mbt:276-283 — the body-kind match currently covers Insert|Update|
// Delete|Merge|CreateTable. Add CreateView (and the Flink DDL target-table
// families the ROADMAP scopes) so target_table_name runs for them:
@SyntaxKind::Insert | @SyntaxKind::Update | @SyntaxKind::Delete |
@SyntaxKind::Merge | @SyntaxKind::CreateTable | @SyntaxKind::CreateView => { ... }
// The no-catalog case (empty results, parser validity unchanged, ANLY-01) is
// already the behavior of `Catalog::table` returning None (analyzer.mbt:290-294).
```
Boundary note: `analyzer/moon.pkg` imports only `fathom/sql/syntax` (D-21); the new arms must not import parser/token/lexer/api/source.

### `api/api.mbt` (facade, request-response)

**Analog:** `api.mbt:79-103` (`ParseOptions::new` Flink arm), `:512-549` (`parse_flink`), `:566-640` (`format_text`/`format_with_ids`)

**Core pattern — Flink DialectContext construction (blueprint for the completion branch and any format guard):**
```moonbit
// api.mbt:92-103 — ParseOptions::new's Flink arm:
@dialect.Dialect::Flink => {
  let profile = match @dialect.FlinkProfile::from_id(profile_id) {
    Some(profile) => profile
    None => return Err(UnknownProfile(profile_id~))
  }
  let metadata = profile.metadata()
  { dialect: dialect, profile_id: profile_id,
    exact_release: metadata.exact_release,
    feature_introduction: metadata.feature_introduction }
}
```
`format_with_ids` (`api.mbt:620-630`) already routes any dialect through `ParseOptions::new` + `format_text`, so the formatter sees the Flink context and the covered-family gate in layout.mbt fires. No new format guard is needed in api.mbt — the refusal is core-side (D-01).

### `lsp/handlers.mbt` (route/handler, LSP request-response)

**Analog:** `handlers.mbt:421-458` (`formatting_result`), `:495-503` (`completion_item_json`), `:505-545` (`completion_result`)

**Core pattern — swap the flink rejection for the real path (D-07):**
```moonbit
// handlers.mbt:432-435 — DELETE the flink sentinel:
if document.dialect == "flink" {
  return [ error_response(id, -32603, "flink grammar is not yet implemented")]
}
// The remaining formatting_result body (436-458) already calls
// @api.format_with_ids and returns edits/diagnostics — flink flows through
// unchanged (refusal => empty edit array + published diagnostics).
```
```moonbit
// handlers.mbt:505-545 — completion_result currently maps any Err to
// -32602. Once complete() returns Ok for flink (D-02), the existing
// completion_item_json (495-503) emits the LSP textEdit:
{
  "label": ..., "kind": 14.0, "detail": ...,
  "textEdit": { "range": range_json(diagnostic_range(raw, start_byte, end_byte)),
                "newText": item.new_text }
}
// diagnostic_range (lsp/coordinates.mbt:26-33) delegates to
// @binding.span_to_range — the UTF-16 contract is shared, never re-derived.
```

### `fathom-sql/run.mbt` (controller/CLI, request-response)

**Analog:** `run.mbt:24-77` (`run_format`)

**Core pattern — flink format already reaches the core (D-07); only tests change:**
```moonbit
// run.mbt:63-71 — run_format calls @api.format_with_ids(input, command.dialect,
// command.profile, "strict", format_options) with NO flink guard. The D-39 exit
// mapping (0 accepted / 1 refusal / 2 usage) already handles flink. Add
// cli_test.mbt matrix cases only (flink-2.3.0 accepted => 0; a refused Flink
// tree => 1 with FATHOM-FORMAT-001 on stderr; unknown flink profile => 2).
```

### `binding/exports.mbt` (provider/ABI export, request-response)

**Analog:** `exports.mbt:30-36` (`fathom_parse_v1`), `:38-72` (`fathom_format_v1`), `:74-86` (`fathom_dialect_v1`/`fathom_capabilities_v1`)

**Core pattern — new primitive export `fathom_complete_v1` (D-04, blueprint `fathom_format_v1`):**
```moonbit
// A4 export order: raw first, dialect second. Return UTF-8 JSON Bytes.
#export_name("fathom_complete_v1")
pub fn fathom_complete_v1(raw : Bytes, dialect : String, profile : String, cursor_byte : Int) -> Bytes {
  match @completion.complete(raw, dialect, profile, cursor_byte) {
    Ok(result) => json_bytes(completion_result_json(result))
    Err(error) => json_bytes(completion_error_json(error))
  }
}
// json_bytes = @utf8.encode (exports.mbt:22-24); error_bytes/json helpers
// (exports.mbt:26-34) already exist. cursor_byte is bounds-checked in
// complete() (InvalidCursor, completion.mbt:159-162).
```

### `binding/schema.mbt` (config/schema, transform)

**Analog:** `schema.mbt:27-35` (`validate_schema_version`), `:64-78` (`validate_dialect_profile`), `:113-133` (`format_result_json`)

**Core pattern — new `fathom.complete.v1` envelope (D-04):**
```moonbit
// schema.mbt:113-133 — mirror format_result_json's envelope shape. The new
// completion_result_json MUST carry schema_version "fathom.complete.v1" and
// the item fields label/detail/start_byte/end_byte/new_text.
// register in validate_schema_version (schema.mbt:27-35) alongside the four
// existing namespaces (parse/format/error/capabilities).
```
`validate_dialect_profile` (`schema.mbt:64-78`) already accepts the three flink profiles — hosts keep using it as the authoritative server-side check (D-05 defense in depth).

### `binding/moon.pkg` (config)

**Analog:** `moon.pkg` `options(link: { "js": { "exports": [...] }, "wasm": { "exports": [...] } })`

**Core pattern — register the new export in BOTH link lists (D-04, Pitfall 3):**
```moonbit
// binding/moon.pkg — append "fathom_complete_v1" to the js AND wasm exports
// arrays. A missing entry compiles but the built artifact lacks the symbol.
```

### Hosts — (dialect, profile) pair validation (D-05)

**`web/src/monaco-adapter.ts`** — **Analog:** `monaco-adapter.ts:11-13` (`PROFILES`), `:88-95` (`validateSelection`). Replace the flat `PROFILES` with a per-dialect map and branch validation:
```ts
export const PROFILES_BY_DIALECT = Object.freeze({
  doris: ['2.1', '3.x', '4.x'],
  flink: ['flink-2.3.0', 'flink-2.1.3', 'flink-1.20.5'],
});
validateSelection(dialect, profile) {
  const allowed = PROFILES_BY_DIALECT[dialect];
  if (!DIALECTS.includes(dialect) || !allowed || !allowed.includes(profile)) {
    throw new Error(MISSING_SELECTION);
  }
}
```

**`vscode/src/extension-contract.ts`** — **Analog:** `extension-contract.ts:2-4` (`SUPPORTED_PROFILES`), `:9-17` (`resolveFathomConfiguration`). Replace `SUPPORTED_PROFILES` with a `PROFILES_BY_DIALECT` map and make `resolveFathomConfiguration` validate the (dialect, profile) pair; surface an explicit error, never coerce (D-05).

**`jetbrains/.../FathomSettings.kt` + `FathomSettingsConfigurable.kt`** — **Analog:** `FathomSettings.kt:57` (`ALLOWED_PROFILES: List<String> = listOf("2.1","3.x","4.x")`), `FathomSettingsConfigurable.kt:24-25` (profile ComboBox). Replace the flat list with a per-dialect map (e.g. `PROFILES_BY_DIALECT: Map<String, List<String>>`) and wire the profile ComboBox to repopulate when `dialectCombo` changes so flink values appear only for flink (D-05).

### Test harnesses — same-commit updates (D-05/D-08, same-commit rule)

- `web/scripts/offline-smoke.mjs:27` asserts the flat `['2.1','3.x','4.x']` list and must move to per-dialect assertions + add flink values.
- `vscode/scripts/launch-smoke.mjs` asserts `initializationOptions: { dialect, profile }` and the flat-profile contract — update in the same change set as `extension-contract.ts`.
- `vscode/scripts/host-verify.mjs:27-49` — ECO-07 mode table (`VSCODE_HOST_MODE`/`FATHOM_DIALECT`/`FATHOM_PROFILE` env) is the blueprint for a new `flink` mode (`FATHOM_DIALECT: 'flink'`, `FATHOM_PROFILE: 'flink-2.3.0'`).
- `jetbrains/scripts/source-smoke.py` requires `listOf("2.1","3.x","4.x")` verbatim — update alongside `FathomSettings.kt`.

### `parity/flink_format_test.mbt` (NEW test, snapshot)

**Analog:** `parity/flink_grammar_test.mbt:9-16` (namespace doc), `:647-679` (snapshot runner)

**Core pattern — new independent snapshot namespace (D-01):**
```moonbit
// flink_grammar_test.mbt:647-679 — the runner shape to replicate:
fn flink_grammar_snapshot_test(t : @test.Test, content : String, filename : String) -> Unit raise SnapshotError {
  t.write(content)
  t.snapshot(filename=filename)
}
test "flink-grammar select-cte-join-agg flink-2.3.0 strict" {
  let t = @test.Test("flink-grammar select-cte-join-agg flink-2.3.0 strict")
  flink_grammar_snapshot_test(t, flink_grammar_parse_json("select-cte-join-agg", "strict"),
    "flink-grammar.select-cte-join-agg.flink-2.3.0.strict.json")
}
// flink-format fixtures use the namespace flink-format.{fixture}.flink-2.3.0.strict.json
// via @binding.fathom_format_v1; assert per-fixture idempotence
// format(format(x))==format(x) + refusal assertions (oracle shape:
// test/formatter_test.mbt:1376-1433).
```

### `parity/export_smoke_test.mbt` (test)

**Analog:** `export_smoke_test.mbt:1-21` (`exports_are_primitive_and_versioned`), `:96-143` (`format_export_is_dialect_aware_with_neutral_wire_identity`)

**Core pattern — assert the new export round-trips and the envelope carries `fathom.complete.v1`:** follow the existing pattern of `let ok = @utf8.decode_lossy(@binding.fathom_complete_v1(...)[:])` and assert `ok.contains("fathom.complete.v1")` plus the item fields; add the unknown-profile error case asserting `fathom.error.v1`/`FATHOM-SCHEMA-003`.

### `.github/workflows/ci.yml` (config/CI, pipeline)

**Analog:** the `linear-wasm-parity` and `parity-gate` jobs in `ci.yml` (install MoonBit → `moon build/test` → python gate scripts)

**Core pattern — add a three-host packaging smoke job (D-08):** mirror the existing job structure (checkout → setup → run harness), reusing: web `offline-smoke.mjs`/Chromium assertions, VS Code `host-verify.mjs` (ECO-07, Xvfb :99), IntelliJ `gradlew test verifyPlugin buildPlugin` + LSP launch smoke. All offline (PARITY-03) — no `--update`, no network/FE/cluster/DB.

## Shared Patterns

### Refusal-first (D-33) — apply to formatter Flink gate
**Source:** `formatter/format.mbt:11-24` + `formatter/refuse.mbt:10-27` + `formatter/layout.mbt:27-33`
**Apply to:** `formatter/layout.mbt` (covered-family gate) — an uncovered Flink family routes through `out.failed` so `format()` emits `accepted=false`, empty output, exactly one `FATHOM-FORMAT-001`; parse diagnostics are never masked (T-03-01).

### Explicit (dialect, profile) selection — apply to hosts + wire
**Source:** `api/api.mbt:79-103` (`ParseOptions::new`), `binding/schema.mbt:64-78` (`validate_dialect_profile`), `completion/completion.mbt:145-158`
**Apply to:** all hosts (D-05) and `binding/exports.mbt` (D-04) — dialect first, then profile; unknown/unsupported selections are structured errors, never a silent default (D-01/D-02).

### UTF-16 coordinate conversion — apply to LSP completion textEdit
**Source:** `binding/coordinates.mbt` (`position_to_byte`/`byte_to_position`/`span_to_range`), surfaced by `lsp/coordinates.mbt:26-33` (`diagnostic_range`)
**Apply to:** `lsp/handlers.mbt` `completion_item_json` — the flink path reuses the same conversion; never a second converter (D-07).

### Wire envelope + ABI — apply to `fathom.complete.v1`
**Source:** `binding/schema.mbt:113-133` (`format_result_json`), `binding/exports.mbt:22-34` (`json_bytes`/`error_bytes`)
**Apply to:** `binding/schema.mbt` + `binding/exports.mbt` + `binding/moon.pkg` (all three in one task, Pitfall 3) + `docs/API.md` + `scripts/check_naming.py` inventory.

### Snapshot/golden discipline — apply to flink-format snapshots
**Source:** `parity/flink_grammar_test.mbt:647-679`; `scripts/baseline_diff.py`/`diff_parity.py` (no `--update` in CI)
**Apply to:** new `parity/flink_format_test.mbt` — the snapshot writer is a local `moon test --update` run whose change is pre-declared in `approved-changes.md` (D-08 single-use path); Doris baseline must run frozen before and after (PARITY-01).

### Same-commit rule for harness asserts — apply to all host changes
**Source:** `web/scripts/offline-smoke.mjs:27`, `vscode/scripts/launch-smoke.mjs`, `jetbrains/scripts/source-smoke.py` (`listOf("2.1","3.x","4.x")`)
**Apply to:** every host constant change — update the harness assertion in the same commit or the contract check fails fast (Pitfall 5).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `.github/workflows/ci.yml` three-host packaging smoke job | CI | pipeline | No existing single job chains web + VS Code + IntelliJ smokes; compose from the three existing harness entry points (D-08) |

## Metadata

**Analog search scope:** `formatter/`, `completion/`, `dialect/`, `analyzer/`, `api/`, `lsp/`, `fathom-sql/`, `binding/`, `syntax/`, `parity/`, `web/src` + `web/scripts`, `vscode/src` + `vscode/scripts`, `jetbrains/.../sql` + `jetbrains/scripts`, `.github/workflows/`
**Files scanned:** 30+ (all analog candidates read directly)
**Pattern extraction date:** 2026-08-10
