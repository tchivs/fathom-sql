# Phase 3: Formatting and Safe Edits — Pattern Map

**Mapped:** 2026-08-04
**Files analyzed:** 16 new/modified file groups (D-25..D-40 deliverables)
**Analogs found:** 14 / 16 with concrete codebase analogs; 2 are greenfield (executable CLI package FFI/main, corpus format goldens — both probe-verified in 03-RESEARCH.md)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `formatter/moon.pkg` | config / package manifest | configuration | `printer/moon.pkg` — library manifest with explicit import list (source/syntax/token/lexer/api) | exact — role-match (imports differ; formatter imports only source/token/syntax, D-27) |
| `formatter/options.mbt` | model / config | transform: 6 config dimensions → validated `FormatOptions` | `api/api.mbt` `ParseLimits::default`/`new` (19-43) + `ParseOptions::new` + accessors (64-118) | exact — same constructor/accessor convention (D-25) |
| `formatter/error.mbt` | model / error transport | transform: refusal/validation → structured result | `api/api.mbt` `ParseError` enum with named fields `derive(Eq, @debug.Debug)` (51-62) + `PrimitiveDiagnostic` shape (149-157) | exact |
| `formatter/refuse.mbt` | utility / service | transform: CST walk → first unsafe element | `printer/printer.mbt` `append_node`/`append_element` recursive leaf-walk (5-34) + `syntax/syntax.mbt` `is_error`/`is_skipped`/`is_missing` (123-137) | role-match — same walk, opposite purpose (read-only scan vs emit) |
| `formatter/case.mbt` | utility / transform | transform: raw token bytes → canonical keyword bytes | `token/token.mbt` `classification_of` (450-460) + `ClassificationEntry.word` (281-287) — direct consumer, no analog needed | exact — the table IS the pattern (D-28, research "Don't Hand-Roll") |
| `formatter/layout.mbt` | service / transform | transform: ordered leaf sequence → canonical bytes (measure-then-break, comment attachment, newline policy) | `printer/printer.mbt` `append_element` (5-19) + `source/source.mbt` `slice` (75-81) + `source/source.mbt` LineIndex CRLF handling (31-45) | role-match — printer is lossless replay; layout is canonical rewrite over the same leaf walk |
| `formatter/format.mbt` | service / API entry | request-response: CST + source + options → `FormatResult` | `api/api.mbt` `parse` entry (250-300): validate → source → core call → primitive result | role-match |
| `api/api.mbt` | API / facade | request-response | itself — `parse`/`parse_with_metadata`/`parse_with_ids` (250-329), `ParseResult`/`PrimitiveDiagnostic` serialization | exact — extend in place (`format_text` mirrors `parse`, one internal parse, same primitive-result style) |
| `doris-sql/moon.pkg` | config / package manifest | configuration | no analog — first executable package; probe-verified `pkgtype(kind: "executable")` DSL in RESEARCH Common Operation 1 | research-only |
| `doris-sql/ffi.mbt` | utility / IO boundary | file-I/O (native only): fopen/fread/fclose/read/write/exit | no analog — probe-verified `extern "c"` + `#borrow` pattern (RESEARCH Common Operations 1-2); `@utf8.encode` for libc strings | research-only |
| `doris-sql/args.mbt` | utility | transform: argv → `Command \| UsageError` | `api/api.mbt` `ParseOptions::new` string→enum match + `Unknown*` error (64-84) | role-match — same "string id → enum, else structured error" convention |
| `doris-sql/run.mbt` | service / pure core | request-response: command + stdin bytes → `CliOutcome { exit_code, stdout, stderr }` | `api/api.mbt` `parse` (250-300) — pure fn returning a result struct; moon-test-driven | role-match |
| `doris-sql/main.mbt` | entry | request-response: argv → stdin/file bytes → run_format → IO → exit | no analog — first executable `fn main`; probe-verified `@env.args()` + `println`/`write(2, …)`/`exit_process` wiring (RESEARCH Common Operation 1) | research-only |
| `test/formatter_test.mbt` | test | golden/property: corpus idempotence + reparse + refusal + layout goldens | `test/parser_test.mbt` `EmbeddedManifestFixture` + `metadata_fixture_replay_ok` (463-505) + `test/corpus_test.mbt` embedded `Array[EmbeddedManifestFixture]` (9-…) | exact — same embedded-fixture + oracle-helper convention (STATE.md: runtime tests do not load the disk) |
| `test/moon.pkg` | config / package manifest | configuration | `test/moon.pkg` itself — extend import list with `"fathom/doris-sql/formatter"` | exact — extend in place (02-PATTERNS: "test/moon.pkg import list is the template for any new test package") |
| `test/*.snap` (format goldens) | fixture data / golden storage | batch: formatted output snapshots per corpus fixture | no committed analog yet; MoonBit built-in snapshots (`moon test --update`) per STACK.md — planner decides file layout (inline goldens in formatter_test.mbt are also acceptable) | research-only |

**Modification-only packages with unchanged boundaries:** `printer/printer.mbt` MUST NOT be touched (D-27, `print_lossless` contract unchanged). `parser/moon.pkg` imports only source/token/lexer/syntax — formatter MUST NOT be added there. `formatter/moon.pkg` imports only `source`, `token`, `syntax` (one-way, NO api/parser/printer — research Architecture Patterns).

---

## Pattern Assignments

### `formatter/options.mbt` (model / config, transform) — D-25..D-31, D-32

**Analog:** `api/api.mbt` `ParseLimits` + `ParseOptions` (constructor/accessor convention)

**Options struct + default + new + accessors pattern** (api.mbt:19-43, 64-84, 104-118) — `FormatOptions` mirrors this exactly, with 6 fields per D-26:
```moonbit
// api/api.mbt:19-43 — struct + default() + new() with all fields explicit
pub fn ParseLimits::default() -> ParseLimits {
  let limits = @parser.ParserLimits::default()
  { max_bytes: limits.max_bytes, max_tokens: limits.max_tokens, /* ... */ }
}
pub fn ParseLimits::new(max_bytes : Int, max_tokens : Int, max_recursion_depth : Int,
  max_recovery_steps : Int, max_diagnostics : Int) -> ParseLimits {
  { max_bytes: max_bytes, /* ... all named fields ... */ }
}
```
```moonbit
// api/api.mbt:64-84 — new() validates string ids and returns Err(Unknown*) on bad input
pub fn ParseOptions::new(profile_id : String, mode_id : String) -> Result[ParseOptions, ParseError] {
  let profile = match @token.DorisProfile::from_id(profile_id) {
    Some(profile) => profile
    None => return Err(UnknownProfile(profile_id~))
  }
  let mode = match mode_id {
    "strict" => ParseMode::Strict
    "editor" => ParseMode::Editor
    _ => return Err(UnknownMode(mode_id~))
  }
  Ok({ profile_context: @token.ValidatedProfileContext::canonical(profile), mode: mode, limits: ParseLimits::default() })
}
```
```moonbit
// api/api.mbt:104-118 — read accessors (no pub fields on the options struct)
pub fn ParseOptions::profile(self : ParseOptions) -> @token.DorisProfile { self.profile_context.profile() }
pub fn ParseOptions::mode(self : ParseOptions) -> ParseMode { self.mode }
pub fn ParseOptions::limits(self : ParseOptions) -> ParseLimits { self.limits }
```

**Guidance for the planner (per 03-RESEARCH Pattern structure + D-26):**
- `FormatOptions` gets exactly 6 fields: keyword case, indent, line width, comma style, newline style, trailing newline — mirror `ParseOptions`' private fields + accessor methods.
- `FormatOptions::default()` → UPPERCASE / 2 spaces / 100 columns / trailing comma / FollowInput / trailing newline on (D-29..D-32).
- `FormatOptions::new(...)` validates (negative indent, non-positive line width → `Err(FormatError::Invalid*)`, mirroring `ParseError::InvalidLimit` api.mbt:57-58); unknown enum string ids → `Err(FormatError::Unknown*)` mirroring `UnknownProfile`/`UnknownMode` (ASVS V5, RESEARCH Security Domain).
- `KeywordCase`/`CommaStyle`/`NewlineStyle` enums mirror `ParseMode` (api.mbt:3-6): `pub(all) enum ... derive(Eq, @debug.Debug)` with `mode_id`-style String mapping (api.mbt:242-248).

### `formatter/error.mbt` (model, error transport) — D-33, D-35, D-39

**Analog:** `api/api.mbt` `ParseError` enum + `PrimitiveDiagnostic`

**Named-field error enum pattern** (api.mbt:51-62):
```moonbit
pub enum ParseError {
  UnknownProfile(profile_id~ : String)
  UnknownMode(mode_id~ : String)
  InputTooLarge(requested_bytes~ : Int, max_bytes~ : Int)
  InvalidLimit(limit_name~ : String, value~ : Int)
  InvalidSyntaxTree
} derive(Eq, @debug.Debug)
```
**Diagnostic struct shape — mirror `PrimitiveDiagnostic` exactly** (api.mbt:149-157); `DORIS-FORMAT-001` is a new stable code in a new namespace (DORIS-PARSE-001..007 taken):
```moonbit
pub struct PrimitiveDiagnostic {
  pub severity : String
  pub code : String
  pub message : String
  pub expected_class : String
  pub start_byte : Int
  pub end_byte : Int
  pub statement_id : UInt
}
```
**Result struct pattern** — `FormatResult { accepted : Bool, output : Bytes, diagnostics : Array[FormatDiagnostic] }` mirrors `ParseResult` (api.mbt:159-171, `valid`/`recovered`/`source_bytes`/`diagnostics` fields) with `accepted: false, output: b"", diagnostics: [FormatDiagnostic]` on refusal (D-33). Refusal message: `"refusing to format a tree containing error/missing/skipped material"`, `expected_class: "format"`, span of first offending node (RESEARCH Pattern 5).

### `formatter/refuse.mbt` (utility, transform) — D-33

**Analog:** `printer/printer.mbt` recursive leaf walk + `syntax/syntax.mbt` error predicates

**Recursive element walk pattern** (printer.mbt:5-34) — same shape, read-only (return verdict instead of emitting bytes):
```moonbit
// printer/printer.mbt:5-34 — the walk the refusal scan copies
fn append_element(element : @syntax.SyntaxElement, source : @source.SourceText, output : Bytes) -> Bytes {
  match element {
    @syntax.SyntaxElement::ChildNode(node) => append_node(node, source, output)
    @syntax.SyntaxElement::Leaf(leaf) => match source.slice(leaf.span) {
      Some(bytes) => output + bytes
      None => output
    }
  }
}
fn append_node(node : @syntax.SyntaxNode, source : @source.SourceText, output : Bytes) -> Bytes {
  let mut result = output
  for child in node.children() { result = append_element(child, source, result) }
  result
}
```
**Error predicates to test** (syntax.mbt:123-137) — `SyntaxNode::is_missing`/`is_error`/`is_skipped`; leaf kinds `SourceError`/`SourceSkipped` (syntax.mbt:30-37). RESEARCH Common Operation 4 gives the exact recursive scan: `for child in root.children()` matching `SyntaxElement::ChildNode(node)` → `node.is_error() || node.is_skipped() || node.is_missing() || recurse`, `SyntaxElement::Leaf(leaf)` → `leaf.kind is SourceError || leaf.kind is SourceSkipped`; return `Some(child)` at first hit.

### `formatter/case.mbt` (utility, transform) — D-28, D-29

**Analog:** `token/token.mbt` `classification_of` — the single source of truth (D-13/D-14); NO second keyword list (research "Don't Hand-Roll")

**Case-insensitive table lookup + canonical spelling** (token.mbt:281-287, 450-460):
```moonbit
pub struct ClassificationEntry {
  pub word : Bytes
  pub classification : ClassificationKind
  pub introduced_profile : String
  pub source : String
} derive(Eq, @debug.Debug)

/// Case-insensitive lookup of a word's classification row (D-13/D-14).
pub fn classification_of(raw : Bytes) -> ClassificationEntry? {
  let mut index = 0
  while index < classification_rows.length() {
    let entry = classification_rows[index]
    if token_bytes_equal_ci(raw, entry.word) { return Some(entry) }
    index = index + 1
  }
  None
}
```
**Rewrite rule** (RESEARCH Common Operation 3): `match @token.classification_of(raw) { Some(entry) => entry.word, None => raw }` — every row's `word` is UPPERCASE by construction; only `SourceToken` leaves are passed here, trivia/hints never (D-36). `classification_of` is profile-independent (token.mbt:450 has no profile parameter, Assumption A7).

### `formatter/layout.mbt` (service, transform) — D-30..D-36

**Analog:** `printer/printer.mbt` leaf walk (structure) + `source/source.mbt` slice/LineIndex (byte access)

**Core emission loop is the printer's leaf walk, with a `Layout` state replacing the `output` accumulator** — printer.mbt:5-34 (excerpt above); the buffer accumulator is `@buffer.Buffer` (`write_bytes`/`to_bytes`, probe-verified linear; RESEARCH Pattern 2 sketch):
```moonbit
// RESEARCH Pattern 2 sketch — Layout struct + emit/break_line (probe-verified @buffer.Buffer)
struct Layout {
  buf : @buffer.Buffer
  mut column : Int
  indent_level : Int
  newline : Bytes        // "\n" or "\r\n" (Pattern 4)
  options : FormatOptions
}
fn Layout::emit(self : Layout, text : Bytes) -> Unit {
  self.buf.write_bytes(text)
  self.column = self.column + text.length()
}
fn Layout::break_line(self : Layout) -> Unit {
  self.buf.write_bytes(self.newline)
  self.buf.write_bytes(@utf8.encode(" ".repeat(self.options.indent() * self.indent_level)))
  self.column = self.options.indent() * self.indent_level
}
```
**Byte access + CRLF conventions** (source.mbt:31-45, 75-81) — `build_line_index` already treats `\r\n` as ONE break (byte 13 + next byte 10 → single `starts.push`), the model for `detect_newline` (RESEARCH Pattern 4):
```moonbit
// source/source.mbt:31-45 — CRLF-as-one-break convention to reuse
if byte == 13 {
  if index + 1 < length && bytes[index + 1].to_int() == 10 { index = index + 1 }
  starts.push(index + 1)
} else if byte == 10 { starts.push(index + 1) }
```
```moonbit
// source/source.mbt:75-81 — the ONLY way layout reads token bytes
pub fn SourceText::slice(self : SourceText, span : Span) -> Bytes? {
  if span.start_byte < 0 || span.start_byte > span.end_byte || span.end_byte > self.byte_length() {
    None
  } else { Some(self.bytes[span.start_byte:span.end_byte].to_owned()) }
}
```
**Clause-keyword matching** — case-insensitive byte equality mirrors the parser's own `bytes_equal_ci` (parser.mbt:140-160) and public `@token.is_clause_keyword` (token.mbt:474-484) for the base SELECT-clause set; per-statement-kind clause tables (RESEARCH Pattern 1) are the one place grammar knowledge is duplicated — keep them in ONE file with a comment linking each keyword to the parser's `consume_word` usage (research Pitfall 7). Do NOT re-read spans; measure-then-break uses summed leaf `text_len()`/`span.length()` (syntax.mbt:144-158).

### `formatter/format.mbt` (service / API entry, request-response) — D-33..D-36

**Analog:** `api/api.mbt` `parse` entry structure (250-300): validate → build source → call core → serialize primitive result

**Entry-shape pattern** (api.mbt:250-278) — `format(root, source, options)` copies the validate-then-act skeleton (refusal scan replaces `validate_limits`; `@buffer.Buffer` accumulation replaces `primitive_node` serialization):
```moonbit
pub fn parse(raw : Bytes, options : ParseOptions) -> Result[ParseResult, ParseError] {
  let limits = options.limits
  match validate_limits(limits) { Ok(_) => (); Err(error) => return Err(error) }
  let source = match @source.SourceText::new_with_limit(raw, limits.max_bytes) {
    Ok(source) => source
    Err(@source.SourceError::InputTooLarge(requested_bytes~, max_bytes~)) => return Err(InputTooLarge(requested_bytes~, max_bytes~))
  }
  // ... parser_mode / parser_limits mapping, then the core call
  let parsed = @parser.parse_with_limits_context(source, options.profile_context, parser_mode, parser_limits)
  if !parsed.root.is_valid(source.byte_length()) { return Err(InvalidSyntaxTree) }
  // ... diagnostics serialization via primitive_diagnostic (api.mbt:230-240)
}
```
The formatter entry must never panic: every `source.slice` failure becomes a refusal diagnostic, not a crash (RESEARCH Pattern 5).

### `api/api.mbt` (API / facade, request-response) — D-37, D-38, D-35

**Analog:** itself — extend in place. Add `format_text(raw : Bytes, parse_options : ParseOptions, format_options : FormatOptions) -> Result[FormatResult, ParseError]` mirroring `parse` (api.mbt:250-300): one internal parse via `@parser.parse_with_limits_context`, format the in-memory `SyntaxNode`, return primitive-shaped diagnostics (api.mbt:230-240 `primitive_diagnostic` is the serialization template). Re-export `FormatOptions`/`FormatResult` from `formatter/` per research Open Question 3 — api is the shared Phase 4 LSP core entry (D-38). Convenience wrappers `format_with_ids`/`format_with_metadata` mirror `parse_with_ids` (api.mbt:317-329) / `parse_with_metadata` (api.mbt:302-315).

### `doris-sql/moon.pkg` (config, configuration) — D-37, D-40

**Analog:** probe-verified in RESEARCH Common Operation 1 (no in-repo executable exists). `pkgtype(kind: "executable")`; package dir name `doris-sql/` → binary literally `doris-sql.exe` (probe-verified). Imports: `"fathom/doris-sql/api" @api`, `"moonbitlang/core/env" @env`, `"moonbitlang/core/buffer" @buffer`, `"moonbitlang/core/encoding/utf8" @utf8`. Build: `moon build --target native --release`; dev: `moon run doris-sql -- args`; `moon test` runs test blocks inside the executable package (probe-verified) — this is what makes D-40's moon-test-driven CLI tests possible.

### `doris-sql/ffi.mbt` (utility, file-I/O) — D-37..D-39

**Analog:** none in repo — RESEARCH probe-verified pattern (Common Operations 1-2). `#borrow(param)` BEFORE each `extern "c"` declaration is mandatory on moon 0.1.20260724 (`unannotated_ffi` build error otherwise); all libc strings must be `@utf8.encode(path)` → `Bytes` (native `String` is UTF-16, moonbit.h:321); no `@ffi` package, no core `fs`, no `eprintln` on this toolchain:
```moonbit
#cfg(any(target="native", target="llvm"))
#borrow(ptr)
extern "c" fn read_fd(fd : Int, ptr : Bytes, count : Int) -> Int = "read"
#cfg(any(target="native", target="llvm"))
#borrow(ptr)
extern "c" fn write_fd(fd : Int, ptr : Bytes, count : Int) -> Int = "write"
#cfg(any(target="native", target="llvm"))
extern "c" fn exit_process(code : Int) = "exit"
```
File read: `open_file(@utf8.encode(path), b"rb") -> Int64` (fopen), loop `read_file_chunk(buf, 1, 4096, handle)` (fread) into `@buffer.Buffer`, `fclose`. stdin: `read_fd(0, chunk, 4096)` loop. stderr: `write_fd(2, …)` (no eprintln).

### `doris-sql/args.mbt` (utility, transform) — D-39, D-26

**Analog (role-match):** `api/api.mbt` `ParseOptions::new` string→enum mapping with `Unknown*` errors (64-84). Hand-rolled parsing (recommended over `@argparse`, which owns help/exit behavior — RESEARCH Standard Stack): map each `@env.args()` entry to a `Command` or `UsageError`; `--profile` required (exit 2 otherwise, per CORE-01 + research Open Question 2). Optional flag surface: `--keyword-case upper|lower`, `--indent N`, `--line-width N`, `--comma-style trailing|leading`, `--newline-style follow|lf|crlf`, `--no-trailing-newline`, positional `file|-`.

### `doris-sql/run.mbt` (service, request-response) — D-37..D-40

**Analog (role-match):** `api/api.mbt` `parse` — pure function returning a result struct. Signature `run_format(command : Command, stdin_bytes : Bytes) -> CliOutcome { exit_code : Int, stdout : Bytes, stderr : Bytes }`; `fn main` (main.mbt) is the ONLY place IO/exit wiring happens: argv → stdin/file bytes → `run_format` → `println` stdout, `write_fd(2, …)` stderr, `exit_process(exit_code)`. Exit mapping: 0 = accepted (stdout = formatted SQL); 1 = parse failure (any `DORIS-PARSE-*`) or refusal (`DORIS-FORMAT-001`, stdout empty); 2 = usage error (stderr message only). Research Open Question 4: statement-per-line layout with `;` at end of line, one newline between statements (confirm against 4.x script fixture goldens).

### `doris-sql/main.mbt` (entry, request-response) — D-37, D-39

**Analog:** none in repo — RESEARCH Common Operation 1 wiring (probe-verified): `@env.args()` (arg[0] = exe path), `print(outcome.stdout.to_string())`, `write_fd(2, outcome.stderr, outcome.stderr.length())`, `exit_process(outcome.exit_code)`. Keep it a thin wrapper; all logic in `run_format` so `moon test` covers D-40.

### `test/formatter_test.mbt` (test, golden/property) — D-33..D-36, D-40

**Analog:** `test/parser_test.mbt` `EmbeddedManifestFixture` + `metadata_fixture_replay_ok` (463-505) + `test/corpus_test.mbt` embedded array (9-…)

**Embedded fixture struct + oracle helper pattern** (parser_test.mbt:463-496) — `FormatterFixture` extends this with `expected_golden : Bytes`:
```moonbit
struct EmbeddedManifestFixture {
  fixture_id : String
  profile : String
  exact_release : String
  feature_introduction : String
  raw : Bytes
  mode : String
  expected_valid : Bool
}
fn metadata_fixture_replay_ok(fixture : EmbeddedManifestFixture) -> Bool {
  let result = match @api.parse_with_metadata(fixture.raw, fixture.profile, fixture.exact_release,
    fixture.feature_introduction, fixture.mode) {
    Ok(result) => result
    Err(_) => return false
  }
  if @printer.print_result(result) != fixture.raw || result.valid != fixture.expected_valid ||
    !result.all_spans_in_bounds() || result.profile != fixture.profile ||
    result.exact_release != fixture.exact_release ||
    result.feature_introduction != fixture.feature_introduction {
    return false
  }
  for diagnostic in result.diagnostics {
    if !diagnostic.code.has_prefix("DORIS-PARSE-") || diagnostic.start_byte > diagnostic.end_byte { return false }
  }
  true
}
```
**Fixture array convention** (corpus_test.mbt:9-…): `let dml_ddl_corpus_fixtures : Array[EmbeddedManifestFixture] = [ { fixture_id: "4.x-insert-values", profile: "4.x", ..., raw: b"INSERT INTO test VALUES (1, 2);\n...", mode: "strict", expected_valid: true }, ... ]` — committed per statement family, one-fixture-one-oracle.

**Formatter oracle assertions (RESEARCH Pattern 6):** for `expected_valid: true` fixtures — (1) `format(format(x)) == format(x)` byte-exact (`Bytes` `==`, no trim — research Pitfall 6, mirrors `print_result(result) == raw` parser_test.mbt:15-16); (2) `parse(format(x))` succeeds with zero diagnostics (D-35); (3) golden snapshot of formatted output (`moon test --update`, reviewed — research Pitfall 7). For malformed/version-negative fixtures — `format` returns `accepted: false` with a `DORIS-FORMAT-001` diagnostic (the malformed-input half of D-34). CRLF fixtures assert byte-level `\r\n` preservation (Pitfall 3).

**CLI tests (D-40):** moon test blocks in the `doris-sql/` package drive the pure `run_format` directly (probe-verified executable-package tests): file input (via FFI helper → bytes → run_format), stdin input, exit 0/1/2, refusal path, CRLF preservation, `--profile` required (2), bad option value (2).

### `test/moon.pkg` (config, configuration)

**Analog:** itself — extend the import list (02-PATTERNS: "test/moon.pkg import list is the template for any new test package"):
```moonbit
import {
  "fathom/doris-sql/analyzer" @analyzer,
  "fathom/doris-sql/api" @api,
  "fathom/doris-sql/parser" @parser,
  "fathom/doris-sql/printer" @printer,
  "fathom/doris-sql/source" @source,
  "fathom/doris-sql/token" @token,
  // + "fathom/doris-sql/formatter" @formatter
}
```

### `formatter/moon.pkg` (config, configuration)

**Analog:** `printer/moon.pkg` — library manifest with explicit import list; formatter's list is a strict subset per D-27 one-way dependency (research Architecture Patterns: NO api/parser/printer):
```moonbit
pkgtype(kind: "library")
import {
  "fathom/doris-sql/source" @source,
  "fathom/doris-sql/token" @token,
  "fathom/doris-sql/syntax" @syntax,
}
```

---

## Shared Patterns

### Options constructor + accessor convention
**Source:** `api/api.mbt:19-118` (`ParseLimits::default`/`new`, `ParseOptions::new`, read accessors)
**Apply to:** `formatter/options.mbt` (FormatOptions, D-25), CLI arg validation
**Excerpt:** see `formatter/options.mbt` section above.

### Named-field error enum + primitive diagnostic serialization
**Source:** `api/api.mbt:51-62` (`ParseError`), `api/api.mbt:149-157` (`PrimitiveDiagnostic`), `api/api.mbt:230-240` (`primitive_diagnostic` converter)
**Apply to:** `formatter/error.mbt` (FormatError/FormatDiagnostic/FormatResult), `api.format_text`
**Excerpt:** see `formatter/error.mbt` section above.

### Recursive SyntaxElement leaf walk
**Source:** `printer/printer.mbt:5-34` (`append_element`/`append_node`); predicates `syntax/syntax.mbt:123-137`
**Apply to:** `formatter/refuse.mbt` (read-only scan), `formatter/layout.mbt` (canonical emission), `formatter/format.mbt` (statement iteration for per-statement offsets, research Open Question 5)
**Excerpt:** see `formatter/refuse.mbt` section above.

### Keyword classification as the single authority
**Source:** `token/token.mbt:281-287, 450-460` (`ClassificationEntry`/`classification_of`); `token/token.mbt:474-484` (`is_clause_keyword`); parser's `bytes_equal_ci` (parser.mbt:140-160) for clause matching
**Apply to:** `formatter/case.mbt` (case rewriting), `formatter/layout.mbt` (clause tables). Never introduce a second keyword list (research "Don't Hand-Roll").
**Excerpt:** see `formatter/case.mbt` section above.

### Byte-exact equality as the replay/idempotence oracle
**Source:** `test/parser_test.mbt:15-16` (`@printer.print_result(result) == raw`) and the `metadata_fixture_replay_ok` full-output compare (parser_test.mbt:476-478)
**Apply to:** `test/formatter_test.mbt` (D-34 idempotence `format(format(x)) == format(x)` with no trimming; D-35 reparse gate)
**Excerpt:** see `test/formatter_test.mbt` section above.

### Embedded fixture + oracle-helper test contract
**Source:** `test/parser_test.mbt:463-505`, `test/corpus_test.mbt:9-…`
**Apply to:** `test/formatter_test.mbt` — runtime tests never read the disk (STATE.md convention)
**Excerpt:** see `test/formatter_test.mbt` section above.

### `extern "c"` FFI with `#borrow` + `@utf8.encode` (native-only)
**Source:** 03-RESEARCH Common Operations 1-2 (probe-verified on moon 0.1.20260724)
**Apply to:** `doris-sql/ffi.mbt` only — MUST never enter core packages (Wasm/JS targets, CLAUDE.md single-core constraint)
**Excerpt:** see `doris-sql/ffi.mbt` section above.

---

## No Analog Found

Files with no close match in the codebase (planner should use 03-RESEARCH.md probe-verified patterns instead):

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `doris-sql/moon.pkg` | config | configuration | First executable package in the repo; `pkgtype(kind: "executable")` probe-verified in RESEARCH Common Operation 1 |
| `doris-sql/ffi.mbt` | utility | file-I/O | No FFI exists in repo; libc `extern "c"` + `#borrow` + `@utf8.encode` probe-verified (RESEARCH Common Operations 1-2) |
| `doris-sql/main.mbt` | entry | request-response | First `fn main` in the repo; `@env.args()`/`println`/`write_fd(2,…)`/`exit_process` wiring probe-verified (RESEARCH Common Operation 1) |
| `test/*.snap` format goldens | fixture data | batch | No committed snapshot files yet; MoonBit built-in snapshots per STACK.md (`moon test --update`); planner may keep goldens inline in formatter_test.mbt instead |

## Metadata

**Analog search scope:** `/opt/source/Fathom/{api,printer,syntax,token,source,parser,test,corpus}` + `.planning/phases/01-core-kernel/01-PATTERNS.md` + `.planning/phases/02-doris-completeness-and-corpus/02-PATTERNS.md`
**Files scanned:** 12 source files + 5 package manifests + 2 corpus fixtures + 2 prior-phase PATTERNS
**Pattern extraction date:** 2026-08-04
**Key verification anchors:** `api/api.mbt:19-118, 149-157, 230-300, 302-329`; `printer/printer.mbt:5-42`; `syntax/syntax.mbt:3-37, 92-137`; `token/token.mbt:271-287, 450-484, 499-523`; `parser/parser.mbt:33-103, 140-160, 3114-3213`; `source/source.mbt:7-28, 31-45, 61-81`; `test/parser_test.mbt:1-19, 463-505`; `test/corpus_test.mbt:9-…`; `test/recovery_test.mbt:1-24`; `moon.mod` (name `fathom/doris-sql`, `preferred_target = "native"`); `printer/moon.pkg`, `parser/moon.pkg`, `api/moon.pkg`, `test/moon.pkg`.
