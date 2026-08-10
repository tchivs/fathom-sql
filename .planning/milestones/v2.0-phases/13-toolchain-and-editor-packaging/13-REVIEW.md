---
phase: 13-toolchain-and-editor-packaging
reviewed: 2026-08-10T00:00:00Z
depth: standard
files_reviewed: 42
files_reviewed_list:
  - formatter/layout.mbt
  - formatter/format.mbt
  - formatter/refuse.mbt
  - completion/completion.mbt
  - completion/completion_test.mbt
  - dialect/flink.mbt
  - analyzer/analyzer.mbt
  - binding/exports.mbt
  - binding/schema.mbt
  - binding/moon.pkg
  - lsp/handlers.mbt
  - lsp/completion_test.mbt
  - lsp/selection_test.mbt
  - lsp/coordinates.mbt
  - fathom-sql/run.mbt
  - fathom-sql/cli_test.mbt
  - test/analyzer_test.mbt
  - parity/flink_format_test.mbt
  - parity/export_smoke_test.mbt
  - parity/run_js.mbt
  - parity/run_wasm.mbt
  - parity/moon.pkg
  - web/src/monaco-adapter.ts
  - web/src/main.ts
  - web/src/main.test.ts
  - web/scripts/offline-smoke.mjs
  - vscode/src/extension.ts
  - vscode/src/extension-contract.ts
  - vscode/src/extension.test.ts
  - vscode/src/host-test.ts
  - vscode/scripts/host-verify.mjs
  - vscode/scripts/launch-smoke.mjs
  - jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomSettings.kt
  - jetbrains/src/main/kotlin/fathom/jetbrains/sql/FathomSettingsConfigurable.kt
  - jetbrains/src/test/kotlin/fathom/jetbrains/sql/FathomSettingsTest.kt
  - jetbrains/src/test/kotlin/fathom/jetbrains/sql/FathomLanguageServerFactoryTest.kt
  - jetbrains/scripts/source-smoke.py
  - .github/workflows/ci.yml
  - .planning/phases/13-toolchain-and-editor-packaging/approved-changes.md
  - docs/API.md
  - docs/CONFIGURATION.md
  - docs/zh-CN/API.md
findings:
  critical: 0
  warning: 5
  info: 7
  total: 12
status: fixed
fix_resolution:
  fixed:
    - WR-01 (statement_id in layout-failure refusal)
    - WR-02 (completion is_incomplete)
    - WR-03 (statement_offsets doc/comment aligned to actual convention)
    - WR-04 (partial document selection -> structured error; regression test added)
    - IN-01 (stale 20->21 covered-family count)
    - IN-02 (API.md dialect-aware ParseOptions::new example)
    - IN-03 (zh-CN/API.md dialect-aware signatures + flink profiles)
    - IN-06 (IntelliJ isModified null-vs-empty)
  accepted_deferred:
    - WR-05 (unpinned MoonBit CI installer — pre-existing policy, pin risk; documented in ci.yml)
    - IN-04 (innerHTML pattern — currently safe, advisory)
    - IN-05 (PROFILES_BY_DIALECT duplication — intentional offline-first)
    - IN-07 (Web UTF-16 re-implementation — advisory, shared-vector follow-up)
---

# Phase 13: Code Review Report

**Reviewed:** 2026-08-10
**Depth:** standard
**Files Reviewed:** 42
**Status:** issues_found

## Summary

Reviewed the Phase 13 "Toolchain and Editor Packaging" changes: the Flink
covered-family formatter gate (D-01), single-table Flink completion (D-02),
analyzer Flink family extension (D-03), the `fathom.complete.v1` wire contract
(D-04), per-dialect host pair validation (D-05), the locked selection model
(D-06), real LSP flink format/completion with UTF-16 coordinates (D-07), and
the three-host packaging smoke + offline CI (D-08).

Overall the implementation is careful and well-tested. The Flink formatter
gate is **fail-safe**: any uncovered Flink family routes through
`Layout.failed` to exactly one `FATHOM-FORMAT-001` refusal with empty output —
never a silent Doris-layout single line (verified by the completeness probe in
`parity/flink_format_test.mbt`). The dialect/profile validation is consistent
across CLI, wire, LSP, and all three hosts, with no secret leakage, no
path-traversal in the host smokes, no `--update` in CI, and correct UTF-16
mapping (both byte→UTF-16 and UTF-16→byte, including the multibyte test
vector). No Critical findings.

The warnings below are correctness/robustness defects that should be fixed
before this code is treated as stable public contract: a refusal diagnostic
that mis-attributes the statement id on the layout-failure path, completion
that silently truncates at the candidate cap while claiming completeness, a
`statement_offsets` documented contract that does not match the emitted bytes,
a partial document-level selection that silently falls through to the
workspace default (D-02 no-guess gap), and an unpinned/checksum-less MoonBit
installer in CI that contradicts the project's own reproducibility policy.

## Findings

| ID | Severity | File:Line | Summary |
|----|----------|-----------|---------|
| WR-01 | Warning | formatter/format.mbt:50-58 | Layout-failure refusal hardcodes `statement_id: 0U` |
| WR-02 | Warning | completion/completion.mbt:298-322 | `is_incomplete` always false even when candidates are capped at 32 |
| WR-03 | Warning | formatter/format.mbt:33-41 | `statement_offsets` recorded before the inter-statement break materializes |
| WR-04 | Warning | lsp/handlers.mbt:242-255 | Partial document-level selection silently ignored → falls back to workspace default |
| WR-05 | Warning | .github/workflows/ci.yml:16,29 | Unpinned `latest` MoonBit install via `curl \| bash`, no checksum verification |
| IN-01 | Info | parity/flink_format_test.mbt:3,30 | "20 covered families" is stale (21 covered / 22 positive fixtures) |
| IN-02 | Info | docs/API.md:428 | Complete Example still uses pre-dialect 2-arg `ParseOptions::new("4.x","strict")` |
| IN-03 | Info | docs/zh-CN/API.md:67 | zh-CN constructor table documents the old 2-arg signature and omits flink profiles |
| IN-04 | Info | web/src/main.ts:147 | `innerHTML` with template literals (currently safe, avoid pattern) |
| IN-05 | Info | web monaco-adapter.ts:7, vscode extension-contract.ts:7, jetbrains FathomSettings.kt:64 | `PROFILES_BY_DIALECT` duplicated across hosts (intentional, drift-prone) |
| IN-06 | Info | jetbrains FathomSettingsConfigurable.kt:48-53 | `isModified` treats unset combo as modified on a fresh install |
| IN-07 | Info | web/src/monaco-adapter.ts:45-76 | Web re-implements UTF-16 conversion independently of binding (D-07 single-converter scope) |

## Warnings

### WR-01: Layout-failure refusal always reports `statement_id: 0U`

**File:** `formatter/format.mbt:50-58`
**Issue:** `format()` has two refusal paths. The pre-pass
(`find_first_unsafe`) computes the correct containing `statement_id`, but any
failure surfaced through `out.failed` — including the new Flink covered-family
gate in `layout_statement` (layout.mbt:949) and source-slice failures — is
converted with `refusal_diagnostic(span, 0U)`, hardcoding statement 0. On a
multi-statement Flink document where the *second* statement hits an uncovered
family, the resulting `FATHOM-FORMAT-001` claims the failure is in statement 0
while its span points at the second statement. `statement_id` is a documented
part of the `FormatDiagnostic` contract (API.md), so consumers locating the
offending statement by id will be misled.
**Fix:** Thread the current `statement_id` into the failure channel (e.g.
record `Some((element, statement_id))` in `Layout.failed` instead of
`Some(element)`), and emit it from the `out.failed` match arm instead of `0U`.

### WR-02: Completion `is_incomplete` is hardcoded `false` despite the 32-candidate cap

**File:** `completion/completion.mbt:298-322`
**Issue:** The two-pass candidate loop stops when `items.length() >=
MAX_CANDIDATES` (32), but the returned list is always `{ is_incomplete: false,
items }`. The current widest pool (flink statement-start) is 31 rows, so the
cap is not hit today; however the Flink classification table is designed to
grow per release (the 2.3.0 delta added rows this phase). Once any context's
matching pool exceeds 32, the result is silently truncated while advertising
`is_incomplete: false` — an LSP client will treat the truncated list as the
full candidate set and will not re-request.
**Fix:** Set `is_incomplete: items.length() >= MAX_CANDIDATES` (i.e. the loop
exited because the cap was reached, not because the pool was exhausted), and
add a regression test with a pool artificially larger than 32.

### WR-03: `statement_offsets` points at the inter-statement newline, not the statement start

**File:** `formatter/format.mbt:33-41`
**Issue:** The offset for each statement is pushed with
`statement_offsets.push(out.buf.length())` **before** `layout_statement`
runs. The previous iteration's `out.break_line()` (line 41) only sets a
*pending* break, which materializes when the next statement's first token is
emitted. So for statement N (N≥1) with no inter-statement trivia, the recorded
offset equals the position where the separating `\n` lands — the *end* of
statement N−1 — not the byte start of statement N as documented in API.md
("records the byte start of each statement in the final formatted output").
The parity oracle only asserts `0 <= offset <= output.length()`, so this
contract mismatch is untested.
**Fix:** Materialize the pending break before pushing (emit the separator into
the buffer, then record `out.buf.length()`), or compute the offset as
`out.buf.length() + newline.length()` for N≥1 and document which convention is
intended.

### WR-04: Partial document-level selection silently falls through to the workspace default

**File:** `lsp/handlers.mbt:242-255`
**Issue:** `selection_from_params` returns `None` when *either* the `dialect`
or `profile` extension field is absent. In `didOpen`/`didChange` resolution a
client that sends only `dialect: "flink"` (missing profile) therefore falls
through to the workspace/session default — which may be `doris` — instead of
surfacing a config error. This silently overrides an explicit user intent and
violates the D-02 "no implicit guess" rule: a flink document can end up parsed
and formatted under the doris default with no diagnostic. The same gap exists
in the `selection_from_value` path for the languageId mapping.
**Fix:** Distinguish "field absent" from "field present but invalid". When
exactly one of `dialect`/`profile` is present at document level, return a
structured selection error (e.g. `MissingProfile`-style message naming the
document) rather than `None`, so the no-guess rule holds for partial input.

### WR-05: CI installs an unpinned `latest` MoonBit toolchain via `curl | bash` with no checksum

**File:** `.github/workflows/ci.yml:16,29` (and the four other install sites:
54, 79, 134, 242)
**Issue:** `MOONBIT_INSTALL_VERSION: "latest"` combined with
`curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash` downloads and
executes an unpinned installer, and no binary/archive checksum is verified.
This contradicts the project's own policy in `research/STACK.md` ("pin the
exact `moon version` output in CI", "verify binary/archive checksums and pin
the resulting toolchain") and makes cross-target parity runs non-reproducible
and supply-chain-sensitive. The inline comment documents why `latest` is used
(the previously pinned archive is no longer served), but the policy gap
remains.
**Fix:** Pin the installer to a specific version (e.g.
`MOONBIT_INSTALL_VERSION: 0.1.20260724`) that the official download page still
serves, verify the installer script / archive SHA-256 before execution (fail
closed on mismatch), and record the resolved `moon version` as a CI artifact.
At minimum, fetch the script with `--proto https` and a checksum check instead
of a bare pipe to `bash`.

## Info

### IN-01: Stale "20 covered families" count

**File:** `parity/flink_format_test.mbt:3,30` (also `approved-changes.md:26`,
phase summary)
**Issue:** The docs/tests repeatedly say "20 covered statement families", but
`flink_statement_covered` enumerates **21** families and the fixture array has
**22** positive rows (two Select fixtures). The count drifted when the covered
set grew.
**Fix:** Update the docstrings to the actual number, or — better — derive the
count from the covered predicate instead of a hand-maintained literal.

### IN-02: API.md Complete Example uses the pre-dialect 2-arg constructor

**File:** `docs/API.md:428`
**Issue:** The Complete Example calls `@api.ParseOptions::new("4.x", "strict")`
(2 args, dialect omitted), while the constructor table at line 68 documents the
dialect-aware `ParseOptions::new(dialect_id, profile_id, mode_id)` (3 args).
The example will not compile against the current API and contradicts the
D-01/D-05 dialect-explicit contract this phase shipped.
**Fix:** Change the example to
`@api.ParseOptions::new("doris", "4.x", "strict")`.

### IN-03: zh-CN/API.md documents the old 2-arg signature and omits flink

**File:** `docs/zh-CN/API.md:67`
**Issue:** The zh-CN constructor table still reads
`ParseOptions::new(profile_id, mode_id)` accepting only `"2.1"/"3.x"/"4.x"`
and "strict"/"editor" — the pre-dialect API. The `dialect` dimension and the
pinned flink profiles added this phase are absent, and `parse_with_ids` is
described as `ParseOptions::new(profile_id, mode_id_value)`.
**Fix:** Align the zh-CN reference with the English version (3-arg signature,
`doris`/`flink`, flink release profiles).

### IN-04: `innerHTML` with template literals in the diagnostics renderer

**File:** `web/src/main.ts:147`
**Issue:** `button.innerHTML = \`...${glyph}...${label}...${text.start}...\``
is an XSS-adjacent pattern. It is currently safe because every interpolated
value is either a fixed string (`severityLabel` tuples) or a number derived
from byte offsets, and `message`/`code` are inserted via `textContent`
(MI-08). The pattern is fragile: any future interpolation of a
source/diagnostic-derived string would introduce a DOM XSS.
**Fix:** Build the row with `document.createElement`/`textContent` throughout
(or use `insertAdjacentHTML` with the fixed structure and set the dynamic
spans via `textContent`), and add a lint rule against `innerHTML`.

### IN-05: `PROFILES_BY_DIALECT` duplicated across the three hosts

**File:** `web/src/monaco-adapter.ts:7`, `vscode/src/extension-contract.ts:7`,
`jetbrains/.../FathomSettings.kt:64`
**Issue:** The per-dialect profile map is hand-maintained in three hosts plus
the server-side validators (`binding/schema.mbt`, `lsp/handlers.mbt`). The
duplication is an explicit offline-first decision (PARITY-03), but a new
released profile requires coordinated edits in five+ places with no
compile-time cross-check, and the smoke tests only regex-check a few literal
strings.
**Fix:** Acceptable as designed; consider a generated-shared-source approach or
a CI step that verifies the host maps equal the server's
`fathom_capabilities_v1` output.

### IN-06: IntelliJ `isModified` reports modified on a fresh install

**File:** `jetbrains/.../FathomSettingsConfigurable.kt:48-53`
**Issue:** On a fresh install the persisted state is `dialect=""`,
`profile=""`, and the combos have no selection (`selectedItem == null`).
`null != ""` is true, so `isModified()` returns true immediately, enabling
Apply; clicking Apply then throws a `ConfigurationException`
("Dialect must be one of..."). The D-02 no-default behavior is intentional,
but the UI should not offer to apply an invalid state.
**Fix:** Treat an unselected combo and an empty-string state as equal in
`isModified()` (e.g. normalize both to `null`/`""` before comparing), or
disable Apply until a valid pair is selected.

### IN-07: Web host re-implements UTF-16 conversion independently

**File:** `web/src/monaco-adapter.ts:45-76`
**Issue:** `byteToPosition` re-implements the UTF-8→UTF-16 conversion that the
binding's `byte_to_position` (binding/coordinates.mbt) already provides for
the LSP surface. The two implementations agree on valid UTF-8 at token
boundaries (verified), but diverge on edge inputs: a byte offset in the middle
of a multi-byte sequence and a lone CR are counted differently (MoonBit counts
the partial leading byte as one unit; the web version stops before it). This
is exactly the "second converter can drift" risk D-07 was meant to prevent,
scoped to the Monaco host.
**Fix:** Either route Monaco marker ranges through the same
`span_to_range`-produced values that the LSP uses (when available), or add a
shared test vector (including mid-character offsets and CRLF/lone-CR) asserted
against both implementations so drift is caught.

---

_Reviewed: 2026-08-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
