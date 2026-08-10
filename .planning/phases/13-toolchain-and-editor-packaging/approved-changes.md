# Phase 13 Approved Baseline Changes (D-08 register)

This register pre-declares every intentional byte change Phase 13 waves
(13-01..13-07) are allowed to make to the frozen parity snapshot surface
(`parity/__snapshot__`, D-07/D-08). Phase 13 propagates the Phase 10/11 Flink
grammar/CST and Phase 12 corpus/parity gates through the neutral toolchain
surfaces (formatter TOOL-01, completion TOOL-02, analyzer TOOL-03, CLI/LSP
TOOL-04, hosts TOOL-05). The register is the D-08 approval path's whitelist
that `scripts/diff_parity.py --approve <this file>` classifies against.

**Rule:** `moon test --update --package parity` is NEVER run without a
matching entry in this register already committed (single-use approval path —
research Pitfall 1/7). Any diff NOT in this register is a regression and must
be fixed, not absorbed. **Doris 213-snapshot zero-drift is a HARD gate:** the
Doris baseline namespaces (`.2.1`/`.3.x`/`.4.x` and the shared Doris rows)
stay byte-identical (PARITY-01); the only snapshot changes Phase 13 may make
are explicitly pre-declared below and materialized by a single approved
`--update`. The `--update` flag is NEVER added to any CI job (Pitfall 1) — CI
runs `moon test --package parity` (no `--update`) and
`scripts/diff_parity.py --frozen-only`, both of which fail on ANY byte drift.

## 1. 13-01: Flink canonical formatter (TOOL-01 / D-01)

Wave 13-01 adds a NEW **`flink-format.{fixture}.flink-2.3.0.strict.json`**
snapshot group under `parity/__snapshot__/` that freezes the Flink
canonical-formatting contract for the 20 covered statement families
(refusal-first, D-33, idempotence D-34, zero-diagnostic reparse D-35). The
namespace is INDEPENDENT (Pitfall 7): it never overlaps the Doris 213
baseline, the `flink-grammar` group, or the `flink-lexical` group.

**Covered-family gate behavior.** `formatter/layout.mbt` gains
`flink_statement_covered(family)` + a dialect-conditional gate in
`layout_statement`: under a Flink context, any statement family NOT in the
covered table routes through `Layout.failed` → exactly one `FATHOM-FORMAT-001`
with empty output (never a silent Doris-layout single line, D-01/D-33,
Pitfall 1). The gate is dialect-conditional and never fires for Doris.

Expected snapshot-surface effect:

| Wave | Deliverable | Expected snapshot-surface effect |
|------|-------------|----------------------------------|
| 13-01 | Flink covered-family gate + per-family clause_breaks arms + flink-format snapshot namespace + refusal/idempotence oracle | **Additive only.** New `flink-format.*.json` files appear; the Doris 213 baseline and the flink-grammar/flink-lexical groups stay byte-identical. The single sanctioned `moon test --update --package parity` run creates ONLY `flink-format.*` files. |

## 2. Machine-Readable Approved Patterns

Parsed by `scripts/baseline_diff.py` / `scripts/diff_parity.py` (`--approve`
argument). Line forms:

- `key:<key>: <old> -> <new>` — a JSON string value under `<key>` may change
  from `<old>` to `<new>`.
- `prefix: <old> -> <new>` — any JSON string value may change from
  `<old><suffix>` to `<new><suffix>`.
- `field: <name>` — the key `<name>` may appear where it was absent.

Active row for 13-01 (a new snapshot file whose name starts with
`flink-format.` may be created by the sanctioned update run):

```
prefix: (absent) -> flink-format.
```

An intentional Phase 13 snapshot change MUST replace the matching commented
template with an active (uncommented) row AND commit it before the single
approved `moon test --update --package parity` run (Section 1).
