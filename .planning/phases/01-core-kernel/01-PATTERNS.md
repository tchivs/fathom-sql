# Phase 1: Core Kernel - Pattern Map

**Mapped:** 2026-08-03  
**Files analyzed:** 24 planned artifact paths  
**Analogs found:** 0 / 24

## Scope and Evidence

这是一个绿地 Phase 1。仓库根目录当前只有 `.planning/` 与 `.claude/`；`01-CONTEXT.md` 也明确记录没有应用源码、包清单或既有 parser 实现（`.planning/phases/01-core-kernel/01-CONTEXT.md:59-71`）。因此以下 `Closest Analog` **全部是 `No Analog Found`**，绝不把研究中的示例伪装成已有代码。

研究文档给出的 Phase 1 具体布局是根目录 `moon.mod`，以及 `source/`、`token/`、`lexer/`、`syntax/`、`parser/`、`api/`、`printer/`、`test/` 和三个 released corpus 目录（`.planning/phases/01-core-kernel/01-RESEARCH.md:149-189`）。下文将这些路径映射到已核验的研究模式；研究中的 MoonBit 片段是设计示意，不是 repository analog。

## File Classification

| New/Modified File or Artifact | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `moon.mod` | config / module manifest | configuration | **No Analog Found** — MoonBit module DSL research pattern | research-only |
| `moon.pkg` | config / root library package manifest | configuration | **No Analog Found** — MoonBit package DSL research pattern | research-only |
| `source/moon.pkg` | config / package manifest | configuration | **No Analog Found** — source package boundary pattern | research-only |
| `source/source.mbt` | model + coordinate utility | transform: UTF-8 bytes → immutable snapshot/index | **No Analog Found** — `SourceText`/`Span`/`LineIndex` pattern | research-only |
| `token/moon.pkg` | config / package manifest | configuration | **No Analog Found** — token package boundary pattern | research-only |
| `token/token.mbt` | model / language metadata | transform: raw lexeme → profile-aware token metadata | **No Analog Found** — versioned token/trivia metadata pattern | research-only |
| `lexer/moon.pkg` | config / package manifest | configuration | **No Analog Found** — lexer package boundary pattern | research-only |
| `lexer/lexer.mbt` | lexer / utility | transform: source snapshot → ordered token stream | **No Analog Found** — trivia-preserving scanner pattern | research-only |
| `syntax/moon.pkg` | config / package manifest | configuration | **No Analog Found** — syntax package boundary pattern | research-only |
| `syntax/syntax.mbt` | model / CST | transform: builder events/tokens → immutable lossless CST | **No Analog Found** — source-backed immutable CST pattern | research-only |
| `parser/moon.pkg` | config / package manifest | configuration | **No Analog Found** — parser package boundary pattern | research-only |
| `parser/parser.mbt` | parser / service | request-response: tokens + profile + mode → CST + diagnostics | **No Analog Found** — recursive descent + Pratt + bounded recovery pattern | research-only |
| `api/moon.pkg` | config / public package manifest | configuration | **No Analog Found** — stable facade boundary pattern | research-only |
| `api/api.mbt` | API / facade | request-response: primitive parse options → versioned primitive result | **No Analog Found** — serialized primitive result pattern | research-only |
| `printer/moon.pkg` | config / package manifest | configuration | **No Analog Found** — printer package boundary pattern | research-only |
| `printer/printer.mbt` | utility / printer | transform: immutable CST + source snapshot → exact source bytes | **No Analog Found** — lossless replay pattern | research-only |
| `test/moon.pkg` | config / test package manifest | configuration | **No Analog Found** — MoonBit test-package pattern | research-only |
| `test/source_test.mbt` | test | invariant/property: source and coordinate model | **No Analog Found** — centralized-coordinate test pattern | research-only |
| `test/lexer_test.mbt` | test (not-created artifact) | golden/property checks are replaced by inline source/token/lexer package tests | **No Analog Found** — no repository test exists; inline package tests are the planned replacement | research-only / not created |
| `test/parser_test.mbt` | test | golden/request-response: released SELECT examples → strict CST/result | **No Analog Found** — recursive-descent/Pratt grammar-slice test pattern | research-only |
| `test/recovery_test.mbt` | test | recovery/property: malformed input → bounded editor CST/diagnostics | **No Analog Found** — progress-or-error and strict/editor recovery test pattern | research-only |
| `corpus/doris-2.1/**` | fixture data / corpus storage | batch: released 2.1 docs → versioned goldens | **No Analog Found** — released-document fixture pattern | research-only |
| `corpus/doris-3.x/**` | fixture data / corpus storage | batch: released 3.x docs → versioned goldens | **No Analog Found** — released-document fixture pattern | research-only |
| `corpus/doris-4.x/**` | fixture data / corpus storage | batch: released 4.x docs → versioned goldens | **No Analog Found** — released-document fixture pattern | research-only |

**Classification note:** `corpus/.../**` denotes fixture files below the explicitly named directories; upstream research does not prescribe individual fixture filenames. The planner must choose names while retaining the provenance and status fields described below. No runtime file I/O belongs in the core; corpus data is Git-tracked test input.

## Pattern Assignments

### `moon.mod` (config, configuration)

**Analog:** **No Analog Found.** The repository has no manifest. Use the current MoonBit DSL documented by research, not a deprecated JSON manifest.

**Verified research pattern:** `.planning/phases/01-core-kernel/01-RESEARCH.md:345-361` shows the starting shape with `name`, `version`, and `preferred_target`; `.planning/research/STACK.md:14-18` requires the current `moon.mod`/`moon.pkg` DSL and rejects `moon.mod.json`.

```moonbit
// Research example only; values are placeholders, not locked project values.
name = "yourname/doris-sql"
version = "0.1.0"
preferred_target = "native"
```

**Planner action:** Create the module manifest with the chosen project identity and a pinned toolchain/dependency policy. Do not copy the placeholder name/version as if they were decided. Keep the parser core backend-neutral and dependency-light.

---

### `moon.pkg` (config, configuration)

**Analog:** **No Analog Found.** No package manifest exists in the repository.

**Verified research pattern:** `.planning/phases/01-core-kernel/01-RESEARCH.md:345-361` gives the current package DSL and uses a library package for the core. `.planning/research/STACK.md:14-18,61-68` keeps package kinds and backend-specific exports at boundaries.

```moonbit
// Research example only.
pkgtype(kind: "library")
```

**Planner action:** Make the root/core package a library. Do not add CLI, LSP, JS, Wasm, filesystem, network, database, or FE dependencies in this phase.

---

### `source/moon.pkg` (config, configuration)
### `token/moon.pkg` (config, configuration)
### `lexer/moon.pkg` (config, configuration)
### `syntax/moon.pkg` (config, configuration)
### `parser/moon.pkg` (config, configuration)
### `api/moon.pkg` (config, configuration)
### `printer/moon.pkg` (config, configuration)

**Analog:** **No Analog Found** for every package manifest above. These are new package boundaries, not copies of existing manifests.

**Verified research pattern:** The Phase 1 layout and one-way dependency direction are specified at `.planning/phases/01-core-kernel/01-RESEARCH.md:149-189`; the component boundaries and interfaces are described at `.planning/research/ARCHITECTURE.md:50-63,321-330`.

**Planner action:** Configure only the imports needed by the dependency chain:

```text
source → token → lexer/parser → syntax → api/printer
```

The research text names `source`, `token`, `lexer`, `syntax`, `parser`, `api`, and `printer` as the Phase 1 package layout. Keep parser independent from analyzer, FE, catalog, filesystem, network, and host-specific packages (`01-RESEARCH.md:187-189`). The exact MoonBit package syntax remains to be checked against the pinned toolchain; do not infer it from a repository analog.

---

### `source/source.mbt` (model + coordinate utility, transform)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** Centralized coordinates, `.planning/phases/01-core-kernel/01-RESEARCH.md:225-231`; architecture responsibility map, `.planning/research/ARCHITECTURE.md:52-69`.

**Required responsibilities:**
- Own one immutable UTF-8 `SourceText` snapshot.
- Define half-open canonical byte `Span` values; enforce `0 <= start <= end <= source.byte_length`.
- Build one `LineIndex` from line starts for byte-to-line/column conversion.
- Keep UTF-16 conversion in a later host/LSP adapter, never as a second parser coordinate system.
- Preserve source ownership for every source-backed CST/token leaf without copying the complete source into each node.

**Research contract excerpt:**

```text
SourceText owns immutable UTF-8 bytes
Span = [start_byte, end_byte)
LineIndex converts byte offsets to line/column
host adapter derives LSP UTF-16 positions
```

The required invariant is that slicing a span returns exactly the original bytes and that valid line-index boundaries round-trip (`01-RESEARCH.md:225-231`). Include revision/edit primitives only if needed to establish the immutable snapshot contract; incremental parsing is not a Phase 1 deliverable.

---

### `token/token.mbt` (model / language metadata, transform)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** The token package is explicitly responsible for `TokenKind`, keyword/profile tables, `Token`, and `TokenStream` (`01-RESEARCH.md:159-161`). The lexer/parser boundary requires ordered tokens with raw text, trivia, and recovery tokens (`.planning/research/ARCHITECTURE.md:54-57,321-327`).

**Required responsibilities:**
- Represent raw spelling and source span for every token.
- Represent comments, whitespace, newlines, literals, unknown/error material, and contextual keyword candidates without normalization.
- Centralize version/profile metadata for released Doris 2.1, 3.x, and 4.x.
- Keep reserved/non-reserved/contextual classification auditable and context-sensitive; do not import a global MySQL keyword table as the acceptance rule.

**Research constraint:** `.planning/research/PITFALLS.md:45-73` requires a versioned keyword matrix containing spelling, case policy, category, contexts, quoting, introduction version, and source URL. The lexer should retain raw candidates; the parser decides contextual acceptance.

---

### `lexer/lexer.mbt` (lexer / utility, transform)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** Trivia-preserving scanner in `.planning/phases/01-core-kernel/01-RESEARCH.md:161-164` and `.planning/research/ARCHITECTURE.md:54-57,165-170`.

**Required responsibilities:**
- Scan the immutable source without mutating or rescanning it later in the parser.
- Emit an ordered `TokenStream` containing raw lexemes, comments, whitespace/newline trivia, literals, contextual candidates, and unknown/error tokens.
- Preserve CRLF/LF, BOM, non-ASCII bytes, quoted spelling, and unterminated literal/comment material.
- Make every lexical recovery path consume input or terminate with a retained error token; never silently drop bytes.

**Research flow:**

```text
SourceText + LineIndex
        → trivia-preserving lexer
        → Token { kind, raw text, span }
```

This is a transform pipeline, not a runtime I/O service. Profile-aware classification must remain explicit, and current/dev syntax must not leak into released profiles (`01-RESEARCH.md:287-299`).

---

### `syntax/syntax.mbt` (model / CST, transform)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** Source-backed immutable CST (`01-RESEARCH.md:191-223`) and immutable lossless syntax model (`.planning/research/ARCHITECTURE.md:174-194`).

**Required responsibilities:**
- Make the immutable lossless CST the source of truth.
- Store immutable nodes and source-backed token/trivia leaves with spans/text lengths.
- Preserve ordered trivia, unknown/error/skipped source ranges, and token spelling.
- Represent `ERROR`, `SKIPPED`, and zero-width `MISSING` nodes explicitly and printably.
- Keep diagnostics as a side channel; optionally expose typed semantic-less views later with CST backreferences.

**Research model excerpt (illustrative, not existing code):**

```moonbit
struct Span { start_byte : Int, end_byte : Int }
enum LeafText { SourceSlice(Span), Synthetic(String) }
struct Token { kind : TokenKind, text : LeafText, span : Span }
struct GreenNode { kind : SyntaxKind, children : Array[GreenChild], text_len : Int }
```

The exact MoonBit representation and builder/event mechanics are planner discretion, but source-backed immutability and byte-complete replay are locked (`01-RESEARCH.md:216-223`).

---

### `parser/parser.mbt` (parser / service, request-response)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** Handwritten recursive descent plus Pratt expressions (`01-RESEARCH.md:233-257`) with parser-to-tree isolation through a narrow builder/events boundary (`.planning/research/ARCHITECTURE.md:196-203`).

**Required responsibilities:**
- Require an explicit Doris profile and parse options; never silently fall back to generic MySQL.
- Use explicit functions for document/statement/SELECT/CTE/FROM/JOIN/GROUP/HAVING/ORDER/LIMIT regions.
- Use one centralized Pratt precedence/associativity table for expressions.
- Build the same CST shape in strict and editor modes.
- Emit structured diagnostics and preserve statement identity/spans.

**Research flow excerpt:**

```text
parse_document
  → parse_statement_list
     → parse_with_clause (optional)
     → parse_select
        → hints / projection / select list
        → FROM + table references + joins
        → WHERE
        → GROUP BY + grouping sets/ROLLUP/CUBE
        → HAVING → ORDER BY → LIMIT
     → parse_set_operation

parse_expression(min_precedence)
  → prefix operand
  → consume operators at the precedence threshold
  → parse RHS with associativity adjustment
```

The parser must not import analyzer, FE, filesystem, network, or host-specific packages (`01-RESEARCH.md:233-257` and `:187-189`). Official released SELECT documentation, not generic SQL behavior, is the acceptance authority.

---

### `api/api.mbt` (API / facade, request-response)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** CST-first derived views and primitive serialized boundary (`01-RESEARCH.md:265-269`), with the proposed primitive result skeleton at `01-RESEARCH.md:377-397`.

**Required responsibilities:**
- Expose a required profile (`doris-2.1`, `doris-3.x`, or `doris-4.x`) and explicit mode (`strict` or `editor`).
- Return versioned primitive fields rather than exposing MoonBit internal ADTs as a foreign ABI.
- Include validity/recovery status, source byte length, node kinds/spans/text lengths, and machine-readable diagnostics.
- Keep diagnostic records separate from CST ownership while attaching severity, stable code, message, expected syntax class, source span, and statement identity.
- Preserve the parser/analyzer boundary: syntax parsing works without catalog metadata.

**Research skeleton (planning shape, not frozen schema):**

```text
ParseOptions { profile, mode, limits }
ParseResult {
  schema_version, profile, valid, recovered, source_byte_length,
  root { kind, start_byte, end_byte, text_len, children },
  diagnostics [{ severity, code, message, expected_class,
                 start_byte, end_byte, statement_id }]
}
```

The schema fields and encodings require a focused API review before ecosystem wrappers; do not treat this sketch as an existing or final wire contract (`01-RESEARCH.md:377-397`).

---

### `printer/printer.mbt` (utility / printer, transform)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** Exact replay is a structural leaf walk (`.planning/research/ARCHITECTURE.md:104-131`), and Phase 1 explicitly has exact replay only; configurable canonical formatting is later (`01-RESEARCH.md:171-176`).

**Required responsibilities:**
- Implement `print_lossless` by concatenating source-backed leaves in source order.
- Preserve comments, whitespace, newline style, token spelling, unknown/error/skipped material, and malformed fragments.
- Ensure zero-width synthetic missing nodes add no bytes.
- Make the invariant byte-level, not `trim`- or normalized-string-based:

```text
parsed = parse(source, profile, mode)
replayed = print_lossless(parsed.document)
assert bytes(replayed) == bytes(source)
```

Do not add a canonical formatter, style options, or “repair” behavior in this phase. Exact replay must work for valid, unknown, incomplete, and malformed input (`01-RESEARCH.md:415-424`).

---

### `test/moon.pkg` (config, configuration)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** MoonBit inline, white-box, black-box, and snapshot test boundaries in `.planning/research/STACK.md:83-93` and `.planning/phases/01-core-kernel/01-RESEARCH.md:86-93`.

**Planner action:** Configure deterministic access to the core packages and module-root-relative corpus fixtures. Do not add a frontend, Node, FE, database, or network test dependency. The research warns that MoonBit test paths resolve relative to the module root; centralize fixture loading rather than depending on a package's current working directory (`STACK.md:87-93`).

---

### `test/source_test.mbt` (test, invariant/property)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** Centralized coordinate invariants in `01-RESEARCH.md:225-231` and lossless source pitfalls in `.planning/research/PITFALLS.md:109-137`.

**Required first-slice checks:**
- Half-open byte span bounds and exact source slicing.
- Empty source, trailing newline/no trailing newline, LF, CRLF, mixed line endings, BOM, non-ASCII identifiers/comments, and emoji comments.
- Byte-to-line/column boundary behavior through one `LineIndex`.
- Source-backed ownership without copying the entire source into every node.

UTF-16 assertions belong only to the centralized adapter contract; Phase 1 must preserve the byte coordinate source of truth.

---

### `test/lexer_test.mbt` (not-created test artifact; inline replacement)

**Analog:** **No Analog Found.** This greenfield repository has no lexer-test analog, and Phase 1 deliberately does not create a separate `test/lexer_test.mbt` file.

**Replacement contract:** The lexical checks formerly described by this path are implemented as inline package tests in `source/source.mbt`, `token/token.mbt`, and `lexer/lexer.mbt` under Plan 01-01. Plans and executors must treat `test/lexer_test.mbt` as a pattern-map entry only, not a file to create or modify.

**Required inline checks:**
- Raw spelling and spans for identifiers, literals, quoted identifiers, comments, whitespace, newlines, and unknown/error tokens.
- CRLF/BOM/non-ASCII/unterminated literal and comment retention, including pre-allocation `max_bytes` rejection and invalid UTF-8 runs.
- Versioned 2.1/3.x/4.x keyword candidates and context-sensitive identifier acceptance.
- Paired cases for a word as keyword, unquoted identifier, quoted identifier, string, function name, alias, and property key.

Inline tests must prove lexical output preserves bytes; token-kind-only assertions are insufficient.

---

### `test/parser_test.mbt` (test, golden/request-response)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** Recursive-descent/Pratt industrial SELECT slice (`01-RESEARCH.md:233-257`) and the versioned official-document golden policy (`01-RESEARCH.md:28-30,37-41`).

**Required first-slice checks:**
- Released 2.1, 3.x, and 4.x fixtures with explicit profile selection.
- SELECT projections, hints, FROM/table references, joins, subqueries, CTEs, predicates, windows, grouping sets/ROLLUP/CUBE, HAVING, ORDER/LIMIT, and set operations as the selected slice allows.
- Strict result validity, CST traversal shape, diagnostics, statement identity, and exact replay together.
- Negative/version-invalid cases proving there is no silent generic-dialect fallback.

A parse-success assertion alone is not enough; pair every golden with byte equality and relevant span/trivia checks (`.planning/research/PITFALLS.md:205-233`).

---

### `test/recovery_test.mbt` (test, recovery/property)

**Analog:** **No Analog Found.**

**Closest verified research pattern:** Progress-or-error and layered synchronization (`01-RESEARCH.md:259-263`; `.planning/research/ARCHITECTURE.md:165-172`).

**Required first-slice checks:**
- Incomplete prefixes such as `SELECT`, trailing comma, missing operand, open parenthesis, unterminated string/comment, and malformed CTE.
- Every parser routine advances, returns a valid node, or emits an explicit error/missing node; no loop or stack exhaustion.
- Clause synchronization and statement synchronization at delimiters/EOF preserve later input and skipped source text.
- Strict mode reports `valid = false`; editor mode may return a usable tree with explicit `MISSING`, `ERROR`, and `SKIPPED` nodes using the same diagnostics schema.
- Diagnostic count, recovery steps, recursion depth, and retained source are bounded.
- `print_lossless(parse(malformed))` remains byte-exact.

Use the research skeleton as the invariant, not as a literal implementation:

```text
start = cursor.position
node = rule()
if cursor.position == start:
  if at_end or in(sync_set): return MissingOrError(expected_kind)
  return ErrorNode(consume_one())
return node
```

---

### `corpus/doris-2.1/**` (fixture data, batch)
### `corpus/doris-3.x/**` (fixture data, batch)
### `corpus/doris-4.x/**` (fixture data, batch)

**Analog:** **No Analog Found** for all three fixture trees. No repository corpus or fixture manifest exists.

**Closest verified research pattern:** Git-tracked official-Doris fixtures grouped by release family (`01-RESEARCH.md:90-93,183-187`; `.planning/research/STACK.md:83-104`). Released official documentation is the public grammar authority; FE/Nereids and SQLGlot are advisory differential references only (`01-CONTEXT.md:28-30`, `01-RESEARCH.md:287-305`).

**Required metadata for every fixture:**
- release family/profile (`doris-2.1`, `doris-3.x`, or `doris-4.x`);
- exact official documentation URL;
- retrieval date and pinned source revision/commit;
- page path/heading and code-fence language/line range where available;
- statement category/feature;
- expected support status and parse mode;
- whether it is `parse-only`, `requires-session`, `requires-catalog`, `executable`, `expected-error`, or `not-sql`.

**Required gates:** Every supported fixture gets strict parsing, byte-exact lossless replay, and relevant diagnostic/recovery expectations. Include malformed/recovery cases and keyword/context boundaries from the first slice. Do not let moving `dev/current` documentation overwrite a released corpus; `dev` is discovery-only and is not a Phase 1 profile (`PITFALLS.md:13-41,77-105`).

The planner may choose a manifest filename and fixture filename convention because upstream research does not name them. That choice must preserve the fields above and produce reviewable version/category coverage rather than an unqualified compatibility claim.

## Shared Patterns

### 1. Canonical byte spans and centralized `LineIndex`

**Apply to:** `source/source.mbt`, `token/token.mbt`, `lexer/lexer.mbt`, `syntax/syntax.mbt`, `parser/parser.mbt`, `api/api.mbt`, `printer/printer.mbt`, and all tests.

**Sources:** `01-CONTEXT.md:16-18`; `01-RESEARCH.md:225-231`; `.planning/research/ARCHITECTURE.md:65-69`.

**Contract:** One immutable UTF-8 source snapshot owns canonical half-open byte spans. Every token, CST node, and diagnostic references those spans. Line/column and later LSP UTF-16 conversion flow through the one `LineIndex` adapter. No package may invent a second offset unit or ad-hoc Unicode arithmetic.

### 2. Immutable source-backed trivia and CST

**Apply to:** `token/token.mbt`, `lexer/lexer.mbt`, `syntax/syntax.mbt`, `parser/parser.mbt`, `printer/printer.mbt`, and replay/golden tests.

**Sources:** `01-CONTEXT.md:24-26`; `01-RESEARCH.md:191-223`; `.planning/research/ARCHITECTURE.md:174-194`.

**Contract:** Source-backed leaves retain every byte, including comments, whitespace, newlines, spelling, unknown/error/skipped material, and malformed text. Nodes carry span/text length; synthetic missing nodes are zero-width. The CST is source of truth; any typed semantic-less view keeps backreferences and cannot replace it.

### 3. Strict/editor recovery over one tree

**Apply to:** `parser/parser.mbt`, `api/api.mbt`, `printer/printer.mbt`, `test/parser_test.mbt`, and `test/recovery_test.mbt`.

**Sources:** `01-CONTEXT.md:20-22`; `01-RESEARCH.md:259-269`; `.planning/research/ARCHITECTURE.md:165-172`.

**Contract:** Strict mode reports invalidity and never promotes recovered input to valid. Editor mode returns the same CST shape with explicit `MISSING`, `ERROR`, and `SKIPPED` nodes plus the same diagnostics records. Every routine obeys progress-or-error; synchronization is layered at delimiter/clause/statement boundaries; recovery work and diagnostic volume are capped.

### 4. Released version profiles, not generic MySQL/current fallback

**Apply to:** `token/token.mbt`, `lexer/lexer.mbt`, `parser/parser.mbt`, `api/api.mbt`, inline tests in those packages (the not-created `test/lexer_test.mbt` replacement), `test/parser_test.mbt`, and all corpus fixtures.

**Sources:** `01-CONTEXT.md:28-30`; `01-RESEARCH.md:287-305`; `.planning/research/PITFALLS.md:13-73`.

**Contract:** Parse entry points require an explicit Doris 2.1, 3.x, or 4.x profile. Released official documentation and pinned fixtures define public support. Current/dev docs are discovery input only. FE/Nereids and SQLGlot can explain disagreements but cannot silently widen the grammar or replace the public corpus. Keyword categories remain versioned and contextual.

### 5. First-slice golden, replay, and recovery gates

**Apply to:** all `test/*.mbt` files and `corpus/doris-*/**`.

**Sources:** `01-CONTEXT.md:28-30`; `01-RESEARCH.md:86-93,415-424`; `.planning/research/PITFALLS.md:205-233`.

**Contract:** The first grammar slice must test, separately and together: byte-exact `print_lossless(parse(input)) == input`; source/token/trivia/span invariants; normalized CST/diagnostic goldens; strict validity versus editor recoverability; version acceptance/rejection; and malformed/incomplete input. Snapshot updates require human review and fixture provenance; snapshot-only or parse-success-only tests are not sufficient.

### 6. Pure offline core and one-way package dependencies

**Apply to:** all core package manifests and implementation files except fixture storage.

**Sources:** `01-RESEARCH.md:61-73,149-189`; `.planning/research/ARCHITECTURE.md:48-63,321-338`; `.planning/PROJECT.md:43-50`.

**Contract:** Source, token, lexer, parser, syntax, API, exact printer, diagnostics, and tests are pure/synchronous and do not require Doris FE, a database, catalog metadata, filesystem, network, Node, or a runtime-specific parser. Native/JS/Wasm wrappers, LSP, CLI, analyzer, and frontend surfaces remain later-phase adapters.

## No Analog Found

The repository contains no source tree, package manifest, parser, tests, fixtures, or established code conventions. Therefore **all 24 entries in the classification table are no-analog artifacts**. The planner should use the cited research contracts rather than copy an imagined local implementation.

| Artifact group | No Analog Found reason | Research fallback |
|---|---|---|
| `moon.mod`, all `moon.pkg` files | No MoonBit module/package exists | Current MoonBit DSL and one-way package layout (`01-RESEARCH.md:149-189,345-361`) |
| `source/source.mbt` | No source/coordinate model exists | `SourceText`/`Span`/`LineIndex` (`01-RESEARCH.md:225-231`) |
| `token/token.mbt`, `lexer/lexer.mbt` | No token stream or scanner exists | Versioned token metadata and trivia-preserving lexer (`01-RESEARCH.md:61-70,149-164`; `PITFALLS.md:45-73`) |
| `syntax/syntax.mbt` | No CST/tree implementation exists | Immutable source-backed CST (`01-RESEARCH.md:191-223`; `ARCHITECTURE.md:174-194`) |
| `parser/parser.mbt` | No parser implementation exists | Recursive descent + Pratt + progress/recovery (`01-RESEARCH.md:233-263`) |
| `api/api.mbt` | No public parse/result API exists | Primitive versioned result boundary (`01-RESEARCH.md:265-269,377-397`) |
| `printer/printer.mbt` | No printer exists | Exact leaf replay only in Phase 1 (`ARCHITECTURE.md:104-131`; `01-RESEARCH.md:415-424`) |
| `test/*.mbt` | No tests or snapshots exist | MoonBit inline/white-box/black-box/snapshot tests plus byte/recovery gates (`STACK.md:83-93`; `01-RESEARCH.md:343-424`) |
| `corpus/doris-2.1/**`, `corpus/doris-3.x/**`, `corpus/doris-4.x/**` | No official fixture corpus exists | Pinned released-doc manifest and classified goldens (`01-RESEARCH.md:301-305`; `PITFALLS.md:77-105`) |

## Explicitly Excluded Research Paths

These paths appear in broader architecture research but are **not Phase 1 artifacts** and must not be added to this pattern map as planned files:

- `ast/` and `analyzer/`: optional semantic-less lowering/catalog analysis is outside this Phase 1 parser-kernel slice; retain only the CST-first boundary (`01-CONTEXT.md:24-26`; `REQUIREMENTS.md:34-36`).
- `cmd/doris-sql/` and `cmd/doris-lsp/`: Native CLI/LSP are later ecosystem work (`ROADMAP.md:54-64`; `01-CONTEXT.md:6-10,85-88`).
- `bindings/js/`, Wasm/JS wrapper packages, browser/Monaco, and VS Code files: later adapters only; no backend-specific parser fork (`01-UI-SPEC.md:17-21`; `STACK.md:44-59`).
- `src/` alternative top-level layout from `.planning/research/ARCHITECTURE.md:71-102`: the phase-specific research gives the root package layout used above; directory naming may be adjusted by the planner, but dependency direction and responsibilities must not change.
- `corpus/dev/`: research mentions it as a discovery/nightly grouping, but Phase 1 public profiles and concrete structure are released `2.1`, `3.x`, and `4.x`; current/dev syntax is not silently accepted (`01-RESEARCH.md:27-30,183-189`; `PITFALLS.md:13-41`).
- Any UI, design-system, frontend, formatting-options, LSP, CLI, database, network, or FE artifacts: the approved UI gate is descriptive only and explicitly introduces no frontend package or browser dependency (`01-UI-SPEC.md:11-21`).

## Metadata

**Analog search scope:** repository root and all phase/research inputs named in `01-CONTEXT.md`; no application source or manifest was present.  
**Files scanned:** 24 planned artifact paths; 0 repository analog files.  
**Research sources scanned:** `01-CONTEXT.md`, `01-RESEARCH.md`, `PROJECT.md`, `ROADMAP.md`, `REQUIREMENTS.md`, `STATE.md`, `CLAUDE.md`, `SUMMARY.md`, `STACK.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `FEATURES.md`, `01-UI-SPEC.md`, `01-DISCUSSION-LOG.md`, and `config.json`.  
**Pattern extraction date:** 2026-08-03  
**Authority note:** Research excerpts and line references are the only analogs available; all MoonBit snippets marked “research example” or “illustrative” are not existing code and require validation against the pinned toolchain.
