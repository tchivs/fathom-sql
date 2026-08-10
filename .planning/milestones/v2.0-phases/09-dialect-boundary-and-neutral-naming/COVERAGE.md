# Phase 9 API Coverage Declaration

**Checkpoint:** API Coverage Decision (opt-out never; detect then declare)
**Detector result:** `{"detected": true, "signals": [{"verb": "(surface)", "noun": "sdk", "snippet": "Phase 9 把已交付的单方言 Doris SDK 升级为显式多方言架构…"}]}`

## No external API integration:

The detector's `sdk` signal is a false positive: the repository **is** an SDK, and this phase refactors that SDK's own public surface. Phase 9 integrates **no external API / SDK / service** — every boundary it touches (api facade, binding exports, CLI, LSP, JS/Wasm exports, Web/Monaco, VS Code, IntelliJ) is an in-repo consumer of the same MoonBit core, and the phase adds **zero new external dependencies** (09-RESEARCH.md §Package Legitimacy Audit: N/A — 核心 parser 只用 `moonbitlang/core`; 命名 gate 脚本为 Python stdlib).

### What the phase touches instead of an external API (in-repo public-boundary surface)

| Public boundary | Change in Phase 9 | External dependency? |
|---|---|---|
| `api/` ParseOptions / ParseError / ParseResult | dialect dimension added (DIALECT-01/04) | No — in-repo |
| `binding/` exports (`fathom_*_v1`) + wire schemas (`fathom.*.v1`) | neutral rename + dialect param (NAME-02, D-06/D-09) | No — in-repo |
| `fathom-sql` CLI (was `doris-sql/`) | `--dialect/--profile` required, parse\|format\|lsp subcommands (D-11) | No — in-repo |
| Native LSP (`fathom-lsp`) | document-level dialect context + neutral identity (D-01/D-02/D-03, NAME-03) | No — LSP 3.17 is a protocol baseline, already in use, not a new integration |
| JS/linear-Wasm facade (`binding/moon.pkg` exports) | export rename + dialect param (A4) | No — same core build |
| Web/Monaco, VS Code, IntelliJ | config keys + neutral naming (NAME-03) | No — existing hosts, source-level rename only |
| `scripts/check_naming.py` | NEW CI gate (NAME-04) | No — Python stdlib, mirrors `corpus/tools/check_keywords.py` |
| `parity/` baseline snapshots | NEW byte-level freeze gate (D-07/D-08) | No — MoonBit `@test.T::snapshot` built-in |

### Conclusion

No external API/SDK/service integration exists in Phase 9 scope. No coverage matrix is required beyond this declaration; the full in-repo surface changes are tracked in the 7 PLAN.md files and their `must_haves`/`threat_model` sections.
