# Phase 9 Approved Baseline Changes (D-08 register)

This register pre-declares every intentional byte change the Phase 9 waves
(09-02..09-07) are allowed to make to the frozen v1 baseline
(`parity/__snapshot__`, D-07). The register is the D-08 approval path's
whitelist: `scripts/baseline_diff.py` groups any snapshot diff into
**approved** (matches this register) vs **unexpected** (exit non-zero).

**Rule:** `moon test --update --package parity` is NEVER run without a
matching entry in this register already committed (single-use approval
path — research Pitfall 3/7). Any diff NOT in this register is a
regression and must be fixed, not absorbed.

## 1. Wire schema namespaces (D-09)

| Old (v1 baseline) | New (approved) |
|--------------------|----------------|
| `doris.parse.v1` | `fathom.parse.v1` |
| `doris.format.v1` | `fathom.format.v1` |
| `doris.error.v1` | `fathom.error.v1` |
| `doris.profile.v1` | `fathom.dialect.v1` |
| `doris.capabilities.v1` | `fathom.capabilities.v1` |

## 2. Diagnostic codes (D-10)

All four families move from `DORIS-` to `FATHOM-` prefixes; dialect is
never encoded into the code prefix (it is carried by metadata fields):

| Family | Old range | New range |
|--------|-----------|-----------|
| PARSE | `DORIS-PARSE-001/002/003/004/006/007` | `FATHOM-PARSE-001/002/003/004/006/007` |
| FORMAT | `DORIS-FORMAT-001..007` | `FATHOM-FORMAT-001..007` |
| SCHEMA | `DORIS-SCHEMA-001..006` | `FATHOM-SCHEMA-001..006` |
| LSP | `DORIS-LSP-001` | `FATHOM-LSP-001` |

Notes:

- **`DORIS-PARSE-005` stays vacant** — it has no use in the v1 codebase
  (verified by grep during research) and is not minted in either prefix.
- **`FATHOM-PARSE-008` is minted** for the Flink not-implemented path
  (09-02): any snapshot gain containing `FATHOM-PARSE-008` is approved
  only where this register's 09-02 entry explicitly names the fixture.
- **`FATHOM-SCHEMA-007` is minted by 09-05** (UnknownDialect +
  ConflictingSelection — see section 11): the v1 baseline range
  `DORIS-SCHEMA-001..006` covers the original mappings; 007 is the new
  dialect-selection code the 09-05 code mapping adds.

## 3. New fields (DIALECT-04)

- `ParseResult.dialect` (and the serialized parse envelope's `dialect`
  field).
- `dialect`, `profile`, and `exact_release` metadata fields on results
  and diagnostics wherever the schema gains them.

## 4. Export renames (NAME-01)

| Old export | New export | Signature |
|-----------|------------|-----------|
| `doris_parse_v1` | `fathom_parse_v1` | adds `dialect` parameter |
| `doris_format_v1` | `fathom_format_v1` | adds `dialect` parameter |
| `doris_profile_v1` | `fathom_dialect_v1` | adds `dialect` parameter |
| `doris_capabilities_v1` | `fathom_capabilities_v1` | unchanged shape |

## 5. CLI / LSP identity strings (NAME-01/03)

- CLI usage text: `doris-sql ...` -> `fathom-sql parse|format|lsp
  --dialect <doris|flink> --profile <id>` (D-11).
- LSP `serverInfo.name`: `doris-lsp` -> `fathom-lsp`.
- LSP diagnostic `source`: `doris` -> `fathom`.

## 6. Snapshot scope (D-07 full-freeze auditability)

- **parse snapshots**: the FULL 44-fixture x {strict, editor} matrix (88
  files) — never trimmed.
- **format snapshots**: the FULL expected-valid matrix (35 files).
- **CLI homomorph snapshots**: the FULL expected-valid matrix (35 files).
- **completion snapshots**: the representative subset below (27 files) —
  one fixture per profile per statement class, enumerated explicitly.
- **LSP homomorph snapshots**: the same representative subset below (27
  files) — the editor-mode parse envelope plus the strict format envelope
  per fixture (the parity/fixtures/lsp-tracer.json pattern).
- No snapshot beyond the enumerated subset is trimmed; the subset scope
  above is what keeps the D-07 full-freeze claim auditable (T-09-04).

### Completion/LSP representative subset (enumerated)

- 2.1 (select, dml-insert, dml-update, dml-delete, ddl-create-table,
  ddl-create-view, ddl-create-index): `2.1-industrial`,
  `2.1-insert-values`, `2.1-update`, `2.1-delete`, `2.1-create-table`,
  `2.1-create-view`, `2.1-create-index`
- 3.x: `3.x-industrial`, `3.x-insert-values`, `3.x-update`, `3.x-delete`,
  `3.x-create-table`, `3.x-create-view`, `3.x-create-index`
- 4.x (adds dml-merge, dml-insert-overwrite, ddl-create-materialized-view,
  ddl-create-table-ctas, ddl-create-table-like, script):
  `4.x-industrial`, `4.x-insert-values`, `4.x-update`, `4.x-delete`,
  `4.x-merge`, `4.x-insert-overwrite`, `4.x-create-table`,
  `4.x-create-view`, `4.x-create-index`,
  `4.x-create-materialized-view`, `4.x-create-table-ctas`,
  `4.x-create-table-like`, `4.x-script-multi-statement`

## 7. Baseline provenance (T-09-03)

`parity/baseline-hashes.txt` pins `corpus/manifest.tsv`,
`corpus/keywords.tsv`, and every `corpus/doris-{2.1,3.x,4.x}/*.sql`.
Any corpus file change is an unapproved baseline diff (the embedded raw
bytes in `parity/baseline_test.mbt` must change together with the corpus
file, and both are gated).

## 8. Usage rules

1. `moon test --update --package parity` requires a matching committed
   register entry BEFORE the update (single-use approval path).
2. Any snapshot diff not explained by sections 1-5 is an unexpected
   regression: `scripts/baseline_diff.py` exits 1, and the diff must be
   reverted (never absorbed by another `--update`).

## 9. 09-03 (format/completion dialect-awareness)

The format and completion wire surfaces move to the neutral identity in
this plan. Sections 1-3 already approve the schema-namespace swap
(`doris.format.v1` -> `fathom.format.v1`), the `FATHOM-FORMAT-*` code
family, and the `dialect`/`exact_release` fields; the one NEW byte change
this plan mints is the completion item detail string (research row 27):

| Old (v1 baseline) | New (approved) |
|--------------------|----------------|
| completion item `detail`: `Doris syntax keyword` | `SQL syntax keyword` (dialect-neutral; affects the 27 completion snapshots) |

Machine-readable pattern (the format half of sections 1-3 is already
registered above):

---

## Machine-Readable Approved Patterns

Parsed by `scripts/baseline_diff.py` (`--approve` argument). Line forms:

- `key:<key>: <old> -> <new>` — a JSON string value under `<key>` may
  change from `<old>` to `<new>`.
- `prefix: <old> -> <new>` — any JSON string value may change from
  `<old><suffix>` to `<new><suffix>`.
- `field: <name>` — the key `<name>` may appear where it was absent.

```
key:schema_version: doris.parse.v1 -> fathom.parse.v1
key:schema_version: doris.format.v1 -> fathom.format.v1
key:schema_version: doris.error.v1 -> fathom.error.v1
key:schema_version: doris.profile.v1 -> fathom.dialect.v1
key:schema_version: doris.capabilities.v1 -> fathom.capabilities.v1
prefix: DORIS- -> FATHOM-
prefix: doris_parse_v1 -> fathom_parse_v1
prefix: doris_format_v1 -> fathom_format_v1
prefix: doris_profile_v1 -> fathom_dialect_v1
prefix: doris_capabilities_v1 -> fathom_capabilities_v1
prefix: doris-lsp -> fathom-lsp
prefix: doris-sql -> fathom-sql
prefix: doris -> fathom
key:detail: Doris syntax keyword -> SQL syntax keyword
field: dialect
field: exact_release
field: profile
```

The trailing generic `prefix: doris -> fathom` covers the D-06 neutral
product naming replacement (LSP `source`, `serverInfo.name`, and any
remaining product-layer `doris` token) and is the catch-all that keeps
any stray `DORIS-`/`doris.*` remnant unapproved (it only rewrites
`doris` -> `fathom`; nothing else).

## 10. 09-04 (module rename + CLI cutover)

The module/import rename (`fathom/doris-sql` -> `fathom/sql`) changes no
behavior bytes — it is verified by the unchanged parity suite (228/228
before and after). The CLI cutover (D-11) changes the CLI contract
surface, which the parity CLI homomorph (baseline_test.mbt
`cli_format_json`) mirrors via the same `format_with_ids` call chain;
since the homomorph already passes `"doris"` as the dialect argument
(now sourced from `Command.dialect`), no homomorph snapshot bytes
change. Registered as the D-08 approval path for the new CLI surface:

| Old (v1 baseline) | New (approved) |
|--------------------|----------------|
| CLI usage text: `usage: doris-sql format --profile <2.1|3.x|4.x> ...` | `usage: fathom-sql parse|format|lsp --dialect <doris|flink> --profile <id> ...` (D-11) |
| `Command` shape: `profile` only (format-only CLI) | `Command` gains `subcommand` (parse\|format\|lsp) and `dialect`; `--dialect` and `--profile` REQUIRED for every subcommand |
| CLI exit matrix: usage errors exit 2 | adds `MissingDialect`/`UnknownDialect` -> exit 2; `--dialect flink --profile <id>` -> exit 2 (flink rejects every profile in Phase 9, A1/OQ1); `fathom-sql parse` stdout carries the `fathom.parse.v1` envelope |
| CLI package dir / binary | `doris-sql/` -> `fathom-sql/` (binary `fathom-sql.exe`); LSP executable `lsp/` (main.mbt) -> library `lsp/` (serve_stdio) + new `fathom-lsp/` executable |
| Release workflow | `doris-native-release.yml` -> `fathom-native-release.yml`; assets `fathom-lsp-{platform}`; manifest `fathom-lsp-manifest.json`; JetBrains artifact `fathom-sql-intellij` |

Machine-readable additions (homomorph snapshots are expected byte-identical;
these approve the CLI-facing shape in case any future snapshot captures it):

key:usage_text: doris-sql format --profile <2.1|3.x|4.x> -> fathom-sql parse|format|lsp --dialect <doris|flink> --profile <id>
field: subcommand
field: dialect

## 11. 09-05 (wire-contract completion: fathom_dialect_v1/capabilities + code mapping)

The parse/format halves were neutralized in 09-02/09-03; this plan closes the
dialect/capabilities/error surface and the parity package. Sections 1-4
already approve the profile/capabilities schema-namespace swap
(`doris.profile.v1` -> `fathom.dialect.v1`, `doris.capabilities.v1` ->
`fathom.capabilities.v1`) and the export renames (`doris_profile_v1` ->
`fathom_dialect_v1`, `doris_capabilities_v1` -> `fathom_capabilities_v1`).
The NEW bytes this plan mints:

1. **`FATHOM-SCHEMA-007` (code mapping, OQ3):** `UnknownDialect` AND
   `ConflictingSelection` serialize to `FATHOM-SCHEMA-007`. 09-02's interim
   mapping put `UnknownDialect` on `FATHOM-SCHEMA-003` alongside
   `UnsupportedProfile`; the 09-05 code mapping moves it to 007 so
   dialect-selection errors are distinguishable from profile errors
   (`UnsupportedProfile` stays 003). Any snapshot byte containing
   `FATHOM-SCHEMA-007` for an unknown-dialect or conflicting-selection
   error is approved.
2. **`fathom.dialect.v1` envelope (was `doris.profile.v1`):** fields
   `schema_version`, `dialect`, `source_transport`, `profiles`
   (`id`/`exact_release`/`feature_introduction` sourced only from
   `DorisProfile` metadata — T-09-18 provenance), `modes`. flink: empty
   `profiles` array (Phase 9, A1).
3. **`fathom.capabilities.v1` envelope (was `doris.capabilities.v1`):** adds
   `dialects` (per-dialect `profiles` availability: doris 2.1/3.x/4.x,
   flink empty); keeps `parse_schema`/`format_schema`/`source_transport`/
   `modes`/`targets`/`wasm_gc`.
4. **parity/fixtures/target-matrix.json:** schema assertions
   `doris.parse.v1`/`doris.format.v1` -> `fathom.parse.v1`/`fathom.format.v1`,
   `doris.error.v1` -> `fathom.error.v1`, plus the `dialect` field.
5. **Web facade wire references (09-03 deferral):** monaco-adapter + main.test
   export symbols `doris_parse_v1`/`doris_format_v1` -> `fathom_*_v1` with the
   `dialect` argument, schema strings -> `fathom.*.v1`; docs/README
   `DORIS-PARSE-*`/`DORIS-FORMAT-*`/`doris.parse.v1` -> `FATHOM-*`/
   `fathom.parse.v1` (D-09/D-10 code/namespace renames, prose unchanged).

Machine-readable additions (the two metadata schema_version transitions are
already registered in section 1; these approve the new envelope fields in
case any future snapshot captures them):

field: dialects
field: profiles

## 12. 09-06 (LSP document-level dialect context: selection resolution + neutral identity)

This plan delivers the LSP boundary of the D-01/D-02/D-03 selection contract:
document-level DialectContext on the LSP state machine, three-level selection
resolution with structured config errors, dialect-switch reparse with
version-guarded publication, and the neutral LSP identity. Sections 1-5
already approve every byte class this plan touches (schema namespaces,
FATHOM-* codes, `serverInfo.name` doris-lsp -> fathom-lsp, LSP diagnostic
`source` doris -> fathom, and the `dialect`/`profile`/`exact_release`
fields). The NEW bytes this plan mints:

1. **parity/fixtures/lsp-tracer.json (09-05 deferral, row 80):** the trace
   fixture moves to the fathom wire identity — `doris.parse.v1` ->
   `fathom.parse.v1`, `doris.format.v1` -> `fathom.format.v1` (section 1
   key rules), plus the `"dialect":"doris"` field (section 3 `field:
   dialect`). The `"profile":"4.x"`/`"mode":"editor"` fields stay.
2. **LSP homomorph snapshot bytes:** the `*.lsp.json` snapshots may gain
   `dialect`/`profile` fields and any remaining `doris` -> `fathom` identity
   tokens where the frozen parse/format envelopes carry them (sections 1-5
   cover the code/schema/identity strings; `field: dialect`/`field: profile`
   cover the metadata fields). Expected byte-identical in practice — the
   homomorph callsites have passed `"doris"` since 09-02 — but registered as
   the approval path for any snapshot drift the single approved `--update`
   captures.
3. **Document-level config extension fields (A2 transport):** didOpen/didChange
   `textDocument` objects may carry `"dialect"`/`"profile"` extension fields;
   `workspace/didChangeConfiguration` settings carry the fathom section
   `{ dialect?, profile?, languageMapping? }`. No frozen snapshot captures
   these transport shapes; registered for auditability of the LSP contract.

Machine-readable additions (all transitions below already exist in sections
1-5; re-listed so the 09-06 update's diff classification is self-contained):

key:schema_version: doris.parse.v1 -> fathom.parse.v1
key:schema_version: doris.format.v1 -> fathom.format.v1
prefix: doris-lsp -> fathom-lsp
prefix: doris -> fathom
field: dialect
field: profile
