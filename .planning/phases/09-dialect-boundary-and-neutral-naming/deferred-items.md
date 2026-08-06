# Phase 09 Deferred Items

## 09-04

Items discovered during 09-04 execution that are out of scope for this
plan's tasks (pre-existing, not caused by 09-04 changes):

| Category | Item | Status |
|----------|------|--------|
| pre-existing | Bare `moon build --target native` (no --package) fails with `undefined reference to main` at link time. Verified pre-existing at de1aa8a (pre-rename HEAD) and at the 09-04 Task 2 commit; package-scoped builds (`--package fathom-sql`, `--package fathom-lsp`, `--package parity`, `--package test`, `--package api`) all pass. Likely a root/module default-target link quirk unrelated to the naming wave. 09-04 uses package-scoped builds for verification. | open — investigate in a later phase if bare builds are needed |

## 09-05

Wire-contract remnants deliberately left for their owning waves (plan
context + 09-03 deferral notes; the plan's acceptance grep documents these
exceptions). None are caused by a 09-05 bug — each is an explicitly owned
surface of a later plan:

| Category | Item | Owning wave | Status |
|----------|------|-------------|--------|
| deferred | `parity/fixtures/lsp-tracer.json` still carries `doris.parse.v1`/`doris.format.v1` (schema strings + the `dialect` field belong with the LSP output shape) | 09-06 (plan context) | open |
| deferred | `lsp/handlers.mbt:98` still emits `DORIS-LSP-001` (plus `source: "doris"`, `serverInfo.name: "doris-lsp"` at lines 99/174) | 09-06 (LSP identity) | open |
| deferred | `web/scripts/offline-smoke.mjs:21,26` still asserts `DORIS-FORMAT-001` in its refusal contract-copy smoke; file also carries another agent's uncommitted monaco 0.56.0 bump WIP, so it cannot be cleanly committed this wave | 09-07 (web host sweep) | open |
| deferred | `vscode/src/host-test.ts` + `vscode/README.md` still assert `DORIS-PARSE-006` (stale since 09-02 renamed the parser codes; host integration surface) | 09-07 (hosts) | open |
| exempt | `corpus/**` provenance rows keep `DORIS-PARSE`-referencing notes and `parity/baseline_test.mbt` embedded fixture bytes keep their verbatim corpus comment headers | D-04 provenance (plan grep exempt) | closed — intentional |
| n/a | `parity/coordinates_test.mbt` needed no migration — it has no `parse_with_ids`/`format_with_ids`/export callsites (already dialect-neutral) | — | closed |
