# Phase 12 Approved Baseline Changes (D-08 register)

This register pre-declares every intentional byte change Phase 12 waves
(12-01..12-03) are allowed to make to the frozen v1 baseline
(`parity/__snapshot__`, D-07/D-08). Phase 12 integrates the Phase 9 Doris
baseline gate, the Phase 10/11 Flink fixtures, and the cross-dialect corpus
contract into an auditable parity harness (PARITY-01); the register is the
D-08 approval path's whitelist that `scripts/diff_parity.py --approve <this
file>` classifies against.

**Rule:** `moon test --update --package parity` is NEVER run without a
matching entry in this register already committed (single-use approval path —
research Pitfall 1/7). Any diff NOT in this register is a regression and must
be fixed, not absorbed. **Doris 213-snapshot zero-drift is a HARD gate:** any
shared parser/CST/corpus change keeps the Doris 213 snapshots byte-identical
(D-04); the only snapshot changes this phase may make are explicitly
pre-declared below and materialized by a single approved `--update`. The
`--update` flag is NEVER added to any CI job (Pitfall 1) — CI runs
`scripts/diff_parity.py --frozen-only`, which regenerates the current tree and
fails on ANY difference without consulting this register.

## 1. Pre-declared Phase 12 snapshot-surface expectations

Phase 12 waves ship **no** `parity/__snapshot__` byte changes. The snapshot
surface is frozen; every Phase 12 deliverable is a harness, data migration, or
CI wiring that must leave the 433 committed snapshots (Doris 213 + flink
groups) byte-identical:

| Wave | Deliverable | Expected snapshot-surface effect |
|------|-------------|----------------------------------|
| 12-01 | Unified Flink corpus manifest + offline verifier | **None.** The D-02 migration is data-only under `parity/fixtures/flink/` (unified manifest + committed `.sql` files). It must NOT touch `parity/__snapshot__`; a snapshot change caused by the migration would itself be a regression (verified: `git diff --name-only -- parity/__snapshot__` empty after 12-01). |
| 12-02 | `scripts/diff_parity.py` frozen-vs-current harness | **None.** The harness only proves frozenness by regenerating the current tree in a temp directory and comparing; it never writes committed snapshots (move/restore lifecycle, zero working-tree residue). |
| 12-03 | CI wiring (`diff_parity.py --frozen-only`, verify_corpus.py --check, js runtime parity) | **None.** CI jobs run read-only gates; `--update` never appears in CI. |

Any future Phase 12 change that DOES alter a snapshot is a two-step contract:
(1) commit a `key:`/`prefix:`/`field:` row in this register naming the exact
transition, THEN (2) run the single `moon test --update --package parity`.
A diff with no committed register entry is unexpected and must be fixed or
adjudicated, never absorbed (D-07, Pitfall 1).

## 2. Conflict adjudication entry point (D-07)

Docs-vs-parser and release-fact-vs-docs conflicts surface in the
`diff_parity.py` report as **unexpected** rows and are routed here for human
adjudication — they are NEVER resolved by a silent bulk `--update`:

- **docs 权威方变更**（Doris 4.x 文档新增/变更语法）→ 追加注册行 + 单次 `--update`，记录理由；
- **parser 回归** → 修 parser，不动快照；
- **release 事实（Calcite/Flink pinned 行为）与 docs 不一致** → 以钉住 release 为准，注册行记录理由（D-07 三方裁决，RESEARCH §6.3/§9）。

## 3. Machine-Readable Approved Patterns

Parsed by `scripts/baseline_diff.py` / `scripts/diff_parity.py` (`--approve`
argument). Line forms:

- `key:<key>: <old> -> <new>` — a JSON string value under `<key>` may change
  from `<old>` to `<new>`.
- `prefix: <old> -> <new>` — any JSON string value may change from
  `<old><suffix>` to `<new><suffix>`.
- `field: <name>` — the key `<name>` may appear where it was absent.

Phase 12 currently pre-declares **no active rows** — the skeleton below is
commented so it documents the format without classifying anything as approved:

```
# key:schema_version: fathom.parse.v1 -> fathom.next.v1
# prefix: FATHOM-PARSE-0 -> FATHOM-PARSE-1
# field: new_envelope_field
```

An intentional Phase 12 snapshot change MUST replace the matching commented
template with an active (uncommented) row AND commit it before the single
approved `moon test --update --package parity` run (Section 1).
