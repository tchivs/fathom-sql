<!-- GSD:project-start source:PROJECT.md -->

## Project

**Doris SQL Parser SDK**

Doris SQL Parser SDK 是一个面向 Apache Doris SQL 的开源基础设施项目，提供独立、完整、可嵌入的解析与工具链能力。它以官方文档语法和示例为覆盖基准，使用 MoonBit 构建同一套核心代码，并输出 Native CLI/LSP 与 WebAssembly/JavaScript SDK，服务编辑器、Web 工具和自动化流水线。

项目的核心差异化是无损 CST：解析树保留注释、空白、换行和源码位置，使格式化、诊断与编辑器能力能够 round-trip 而不破坏用户源码；在此基础上逐步提供格式化、Lint、列级血缘和 SQL 指纹等分析能力。

**Core Value:** 用户可以对 Doris SQL 进行高覆盖、精确诊断且无损 round-trip 的解析与编辑，而不依赖 Doris FE、商业闭源 GSP 或薄弱的方言适配。

### Constraints

- **语言与后端**: 核心解析器使用 MoonBit，并从同一份代码编译 Native 与 Wasm/JS — 避免为 Web、LSP 和 CLI 维护多套解析实现。
- **源码保真**: CST 节点必须保留 Span 与 trivia；格式化和后续编辑不能丢失注释、空白或换行 — 这是区别于现有薄方言方案的核心价值。
- **解析策略**: 采用手写递归下降 Parser，表达式采用 Pratt parsing；错误恢复至少支持语句级 panic-mode 与子句级尽力恢复 — IDE 场景必须能处理半成品 SQL。
- **覆盖基准**: 以官方文档为语法权威和可执行语料，按 Doris 版本维护关键字分类与语法示例 — 避免仅以不完整 g4 或薄方言为准。
- **语义边界**: Parser 只负责语法，Analyzer 通过可选 catalog 注入名字解析 — 无元数据时仍必须支持纯前端语法校验。
- **交付顺序**: 先把 SELECT 与表达式做到工业级，再横向扩展 DML/DDL、格式化和生态集成 — 不以初期全覆盖牺牲错误恢复、性能和测试质量。

<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->

## Technology Stack

## Recommended Stack

### Core Framework

| Technology | Version / evidence date | Purpose | Why |
|------------|-------------------------|---------|-----|
| MoonBit toolchain (`moon`, `moonc`) | Current official documentation is **MoonBit v0.10.5** (verified 2026-08-03); pin the exact `moon version` output in CI rather than tracking `latest` silently | The single implementation language and build system | The official documentation lists `wasm`, `wasm-gc`, `js`, and `native` backends and explicitly supports mixed-backend modules. This directly satisfies one parser implementation for Native CLI/LSP and Web SDKs. Native debug/release backend details are still evolving, so reproducible builds must record the toolchain version and compiler mode. |
| Moon module/package DSL (`moon.mod`, `moon.pkg`) | New format documented in v0.10.5; `moon.mod.json` and `moon.pkg.json` are deprecated since v0.10.4 and scheduled for removal | Module metadata, dependencies, package kinds, backend link options | Use the new DSL from the first commit. It supports `preferred_target`, package imports, test imports, `pkgtype(kind: "executable")`, and backend-specific linking without carrying a deprecated configuration format. |
| `moonbitlang/core` | `0.1.20260728+5e7afb0c0` is the current successful Mooncakes version observed on 2026-08-03 | Strings, arrays, bytes, immutable data structures, basic utilities | Use the standard library as the only mandatory runtime dependency of the parser core. Pin the observed version in the module lock/CI and update deliberately; do not make parser correctness depend on experimental extension packages. |
| `moonbitlang/x` | `0.4.47` observed on 2026-08-03; official registry describes it as experimental | Optional JSON/time/utility support at adapters and test tooling boundaries | Keep it out of the lexer/CST/parser dependency path. It can be evaluated for JSON and LSP adapters, but the core should use only stable core packages or a deliberately small local protocol codec. |
| Handwritten MoonBit lexer + recursive-descent parser + Pratt expression parser | Project decision; no external version | Doris SQL tokenization, lossless CST construction, expression precedence, recovery | This is the only option that preserves explicit control over trivia, spans, incomplete editor input, and Doris-specific grammar while keeping all backends on the same implementation. Represent source positions as backend-neutral integer offsets/spans and retain every trivia token in the CST. |

### Database

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| None in the parser SDK | N/A | The parser, CST, diagnostics, and formatter are pure in-process components | A database would add runtime state and deployment coupling without helping syntax parsing. Persisted corpus fixtures, version metadata, and golden snapshots belong in Git and CI artifacts, not in the SDK runtime. |

### Infrastructure

| Technology | Version / evidence | Purpose | Why |
|------------|--------------------|---------|-----|
| Git + GitHub Actions (or an equivalent CI runner) | Current project infrastructure choice; pin MoonBit toolchain in CI | Source control, Doris corpus provenance, multi-target build/test matrix, release artifacts | The official MoonBit installer requires Git, and MoonBit provides command-line build/test/coverage commands suitable for a matrix. Keep CI jobs deterministic by recording `moon version`, target, dependency versions, and fixture provenance. |
| Official MoonBit installer + SHA-256 verification | Installer/checksum instructions verified on the official download page 2026-08-03 | Install the compiler in developer and CI environments | Use the official installer for bootstrap, then verify binary/archive checksums and pin the resulting toolchain. Do not rely on an unrecorded floating `latest` for release artifacts. |
| npm-compatible package publication for generated JS (adapter layer only) | Ecosystem convention; exact package registry is a release decision | Distribute ESM JS and TypeScript-facing metadata for browser/Monaco consumers | Keep npm packaging outside MoonBit parser-core. The generated JS artifact is the deliverable; a thin package wrapper can provide exports, types, and browser examples without introducing Node into Native or Wasm builds. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `moonbitlang/core` | `0.1.20260728+5e7afb0c0` observed 2026-08-03 | Stable standard data/text/collection primitives | Always; this is the parser core’s baseline dependency. |
| `moonbitlang/x` | `0.4.47` observed 2026-08-03; marked experimental | Optional JSON or utility support in adapters/tests | Only after evaluating its target behavior and API stability; never make lexer/CST correctness depend on it. |
| LSP 3.17 message schema | 3.17 specification baseline | Native LSP protocol types and method names | At the LSP adapter boundary; implement only the methods required by the current editor workflow first. |

### Backend and Public-API Boundary

| Target | Recommendation | Configuration/publishing choice | Confidence |
|--------|----------------|----------------------------------|------------|
| Native | First-class release target for `doris-sql` CLI and `doris-sql lsp` | Put the CLI/LSP entry point in an executable package using `pkgtype(kind: "executable")`; use `moon build --target native --release`. The official package docs expose native C compiler/link flags, so keep the initial CLI free of native libraries and use the default compiler. | HIGH for capability; MEDIUM for the exact release layout |
| JavaScript | Primary browser/Monaco integration target | Export a small wrapper package as a `foreign_library`; use `#export_name` on stable, non-generic wrapper functions and `options(link: { "js": { "format": "esm", "exports": [...] } })`. Prefer ESM as the default; CJS and IIFE remain available for consumers that need them. | HIGH |
| WebAssembly (linear Wasm) | Portable binary target for hosts that do not want the JS backend | Build with `--target wasm`, expose only explicit wrapper functions, and avoid host-dependent `println`/`env` behavior. Use UTF-8/bytes or serialized results at the host boundary rather than depending on internal MoonBit object layout. | HIGH for documented capability; MEDIUM for final host ABI until a smoke test is added |
| Wasm GC | Optional evaluation target, not the first compatibility promise | The official docs support `wasm-gc` and an optional JS String Builtin configuration. Enable it only after the ordinary Wasm and JS wrappers work; its reference-type/string-host assumptions should be tested in the exact browser/runtime matrix before release. | HIGH for capability; MEDIUM for deployment choice |

- `parse_text` → serialized diagnostics/CST view or a documented byte buffer;
- `format_text` → formatted source text;
- `version`/capability metadata → strings and integers.

### Parser/CST Libraries and Data Model

| Choice | Recommendation | Rationale |
|--------|----------------|-----------|
| Lexer/CST runtime | Build a small local MoonBit core module; do not introduce a parser-generator runtime | No stable official MoonBit lossless-CST package was verified in the current official documentation/registry sources. A local implementation avoids an unverified dependency and can encode the product’s required invariant: every source byte is covered by token/trivia spans and printing the lossless tree reproduces the original input. |
| CST representation | Immutable node/token structures plus source spans, with trivia retained as first-class token data | Supports precise diagnostics, comment/whitespace preservation, formatter edits, and later editor features. Keep span units documented (prefer byte offsets for slicing/ABI; derive line/column indexes in a source map) and avoid copying source text into every node. |
| AST/analyzer | Separate optional analyzer package over CST-derived semantic nodes | Parser remains usable without a catalog, while table/column metadata can be injected later. Do not pull Doris FE execution semantics or catalog resolution into the parser core. |
| Pretty printer | A local CST-aware printer with a lossless mode and configurable formatting mode | Lossless mode must emit original trivia; configured formatting can change whitespace while retaining comments and unknown/error nodes. Make idempotence (`format(format(x)) == format(x)`) a tested contract. |

### LSP and CLI Integration

| Technology | Version / evidence | Recommendation | Why |
|------------|--------------------|----------------|-----|
| Language Server Protocol | Implement the documented **LSP 3.17** baseline; check the current specification before shipping | Implement the Native server as a thin JSON-RPC-over-stdio adapter around the parser/diagnostic core. Start with initialize, shutdown/exit, `textDocument/didOpen`, `didChange`, `didClose`, diagnostics, and document formatting; add completion/hover only when the parser data supports them. | LSP is the interoperability contract, not a parser dependency. Keeping transport and protocol code at the edge preserves one core implementation and avoids requiring Node for the Native distribution. |
| JSON-RPC/LSP codec | Small adapter using stable MoonBit primitives; evaluate `moonbitlang/x` JSON only at the edge | Do not make an experimental JSON package part of the core parser. Validate message framing, malformed input handling, and UTF-16 position conversion separately. | LSP uses strict message framing and editor positions; this is a boundary concern with different failure and resource limits from SQL parsing. |
| CLI | MoonBit executable package | `doris-sql parse`, `doris-sql format`, and `doris-sql lsp` should call the same core APIs. Keep file/stdin handling, exit codes, and diagnostics rendering outside the parser package. | A native CLI is the simplest smoke-testable consumer and is explicitly in project scope. |
| Browser/Monaco | Generated ESM JavaScript wrapper first; Wasm wrapper as an additional artifact | Let the JS host own editor integration and worker/thread scheduling. The MoonBit adapter receives text and returns diagnostics/edits in a stable schema; do not embed a Node-only LSP server in the browser package. | This keeps Web API ergonomics separate from the Native LSP transport while preserving the same parser. |

### Testing, Golden Corpus, and CI

| Technology/tool | Version / evidence | Use |
|-----------------|--------------------|-----|
| MoonBit built-in tests | Current v0.10.5 docs | Use inline `test` blocks for invariants, `_wbtest.mbt` for internal parser tests, and `_test.mbt` for the public API. MoonBit runs black-box and white-box tests through `moon test`. |
| Built-in snapshots | Current v0.10.5 docs | Use `debug_inspect`/JSON snapshots for normalized CST/diagnostic views and `@test.T::snapshot` for whole-process output. `moon test --update` is the supported update path. Keep large Doris corpus files in version-controlled fixture directories and make snapshot names include the Doris version/feature. |
| Golden corpus harness | Local repository data + MoonBit test runner | Maintain fixtures grouped by `doris-2.1`, `doris-3.x`, `doris-4.x`, and `dev`; each fixture records source URL, documentation version, expected parse status, and expected round-trip/diagnostic result. Test the key invariant `print_lossless(parse(input)) == input`, then separately snapshot formatting and diagnostics. |
| Coverage | `moon test --enable-coverage`; `moon coverage report` | MoonBit’s official coverage is branch coverage and can emit summary, HTML, Coveralls JSON, and Cobertura. Use it for implementation coverage, but report SQL feature/corpus coverage separately: branch coverage alone cannot prove Doris grammar coverage. |
| Cross-backend CI | Moon commands plus the pinned installer | Run `moon check/build --target native`, `js`, `wasm` (and `wasm-gc` when enabled), then run the same small fixture suite through each public wrapper. Compare serialized diagnostics and round-trip outputs byte-for-byte. Record toolchain version and target in artifacts. |

### Doris SQL Coverage Source

| Source | Recommended use | Verification |
|--------|-----------------|--------------|
| Apache Doris official SQL manual (`dev`) | Discovery and current syntax tracking only | The current site labels `dev` as an unreleased version. Its SQL manual is organized into basic elements, functions, and statements. |
| Versioned Doris docs | Reproducible corpus tags | The official current overview links versioned documentation for 2.1, 3.x, and 4.x; the release-note index also exposes 2.1, 3.0/3.1, and 4.0/4.1 lines. Pin the URL/version and retrieval date in corpus metadata. |
| `apache/doris-website` | Corpus extraction source and documentation-change review | Official Apache repository containing the docs, release notes, and doc tooling. Prefer a pinned commit or release branch when generating a corpus; do not treat the moving `master` site as a permanent fixture. |
| `apache/doris` FE/Nereids parser source | Differential oracle and gap investigation | The official source contains `NereidsParser` and related parser helpers under `fe/fe-core/.../nereids/parser`. It can explain Doris acceptance behavior, but the SDK remains independent and must not require FE/Java services. |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Implementation language | MoonBit | Rust, TypeScript, Python | The project requires one MoonBit implementation compiling to Native and Wasm/JS. Other languages could have stronger parser ecosystems, but would violate the stated single-core direction or require a second implementation/FFI layer. |
| Parser engine | Handwritten recursive descent + Pratt | ANTLR/g4 or another generated parser | Generated grammars can accelerate initial syntax coverage, but they reduce direct control over error recovery, incomplete SQL, and trivia-preserving CST behavior. They also introduce generator/runtime/version coordination that is unnecessary for the chosen MoonBit core. Use Doris grammar/source as reference, not the runtime. |
| Incremental parser | Lossless local CST designed for later incremental reuse | Tree-sitter | Tree-sitter is a strong independent option for incremental parsing, but adopting it would add a native/Wasm runtime and grammar boundary before the Doris coverage oracle and lossless printer contracts are stable. Reconsider only if profiling demonstrates that the local design cannot meet editor latency. |
| Existing SQL library | Local Doris parser | sqlglot or a generic SQL AST library | Generic AST libraries are useful comparison baselines, but they are not the lossless MoonBit CST requested here and would leave comments/trivia or Doris-specific constructs outside the core contract. |
| Doris reference | Versioned official docs plus FE differential checks | Depend on Doris FE at runtime | Runtime FE dependence contradicts independent SDK distribution, browser use, and the parser/analyzer separation. |
| LSP implementation | Native MoonBit stdio adapter | `vscode-languageserver-node` | The Node implementation is a good protocol reference, but it adds Node packaging/runtime to a Native-first SDK and would duplicate the transport layer. |
| Web target | JS ESM plus portable Wasm | Wasm GC only or JS-only | JS ESM gives the most direct browser/Monaco surface; linear Wasm preserves a portable host option. Wasm GC is documented but should be an explicitly tested optional artifact, while JS-only would fail the Wasm requirement. |
| Package configuration | `moon.mod`/`moon.pkg` | `moon.mod.json`/`moon.pkg.json` | Official docs mark the JSON formats deprecated in v0.10.4 and scheduled for removal. |

## Installation and Setup

# Install the MoonBit CLI/toolchain according to the official installer.

# Pin/update dependencies intentionally rather than accepting accidental upgrades.

# Optional edge-only utilities; keep this out of parser-core until evaluated.

# moon add moonbitlang/x@0.4.47

# Development and release checks for the shared implementation.

# Built-in tests, snapshots, and branch coverage.

## Versioning and Reproducibility Policy

## Sources

### MoonBit (official)

- [MoonBit Documentation home — v0.10.5](https://docs.moonbitlang.com/en/latest/) — supported backends and mixed-backend modules (HIGH).
- [Foreign Function Interface — v0.10.5](https://docs.moonbitlang.com/en/latest/language/ffi.html) — backend list, host dependencies, FFI types/ABI, and portability warnings (HIGH).
- [Module Configuration — v0.10.5](https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html) — `moon.mod`, dependencies, versions, and preferred targets (HIGH).
- [Package Configuration — v0.10.5](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html) — `moon.pkg`, package kinds, `#export_name`, JS/native/Wasm link options (HIGH).
- [Command-Line Help — v0.10.5](https://docs.moonbitlang.com/en/latest/toolchain/moon/commands.html) — build/check/test targets and commands (HIGH).
- [Writing Tests — v0.10.5](https://docs.moonbitlang.com/en/latest/language/tests.html) — unit, black-box/white-box, and snapshot tests (HIGH).
- [Measuring code coverage — v0.10.5](https://docs.moonbitlang.com/en/latest/toolchain/moon/coverage.html) — branch coverage and report formats (HIGH).
- [WebAssembly Integration — v0.10.5](https://docs.moonbitlang.com/en/latest/toolchain/wasm/index.html) — component model and custom import/export guidance (HIGH).
- [Use and publish packages — v0.10.5](https://docs.moonbitlang.com/en/latest/toolchain/moon/package-manage-tour.html) — `moon new`, `moon add`, Mooncakes, and package layout (HIGH).
- [Official MoonBit download page](https://www.moonbitlang.com/download/) — installer and SHA-256 verification guidance (HIGH).
- [Mooncakes `moonbitlang/core` manifest](https://mooncakes.io/api/v0/manifest/moonbitlang/core) — observed current version and checksum metadata (HIGH, checked 2026-08-03).
- [Mooncakes `moonbitlang/x` manifest](https://mooncakes.io/api/v0/manifest/moonbitlang/x) — observed current experimental extension version (HIGH, checked 2026-08-03).
- [Moon build system source repository](https://github.com/moonbitlang/moon) — official build-system/package-manager source (HIGH).

### Doris and protocol standards (official)

- [Apache Doris current overview](https://doris.apache.org/docs/dev/getting-started/what-is-apache-doris/) — current page labels itself unreleased and links 2.1/3.x/4.x docs (HIGH, last updated 2026-05-17 in page metadata).
- [Apache Doris SQL manual index](https://doris.apache.org/docs/dev/sql-manual/) — official basic-element, function, and statement sections (HIGH).
- [Apache Doris release-notes index](https://doris.apache.org/docs/dev/releasenotes/) — official version families including 2.1, 3.x, and 4.x (HIGH).
- [Apache Doris website source](https://github.com/apache/doris-website) — official documentation repository and versioned corpus source (HIGH).
- [Apache Doris FE Nereids parser directory](https://github.com/apache/doris/tree/master/fe/fe-core/src/main/java/org/apache/doris/nereids/parser) — official parser/differential reference source (HIGH).
- [Language Server Protocol 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) — protocol baseline and message contracts (HIGH).
- [Microsoft Language Server Protocol repository](https://github.com/microsoft/language-server-protocol) — official protocol source and specification repository (HIGH).
- [Microsoft vscode-languageserver-node repository](https://github.com/microsoft/vscode-languageserver-node) — official Node implementation, consulted as an interoperability reference rather than adopted dependency (HIGH).

## Confidence Notes and Open Verification

- **HIGH:** MoonBit target list, module/package syntax, export attributes, JS formats, test/snapshot/coverage commands, and Mooncakes versions are directly verified against current official docs or the official registry API.
- **HIGH:** Doris versioned documentation layout, unreleased `dev` warning, release-note families, website repository, and FE parser location are directly verified against official Apache sources.
- **MEDIUM:** The recommendation to expose serialized primitive wrappers rather than CST objects is a conservative design response to the official FFI ABI warning; final signatures require a small cross-target prototype.
- **MEDIUM:** The recommendation to implement a native LSP adapter in MoonBit is compatible with the official protocol but is not evidence that a ready-made MoonBit LSP framework exists. Validate framing, UTF-16 positions, cancellation, and incremental document updates during the LSP phase.
- **Open:** Confirm the exact production browser/runtime matrix for linear Wasm versus Wasm GC, and confirm whether the chosen JSON codec meets size, Unicode, and malformed-input requirements before making it a public dependency.

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
