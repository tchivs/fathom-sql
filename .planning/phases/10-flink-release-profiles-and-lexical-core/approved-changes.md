# Phase 10 Approved Baseline Changes (D-04 register)

This register pre-declares every intentional byte change the Phase 10 waves
(10-01..10-03) are allowed to make to the frozen v1 baseline
(`parity/__snapshot__`, D-07). The register is the D-08 approval path's
whitelist for the flink-lexical group: `scripts/baseline_diff.py` groups any
snapshot diff into **approved** (matches this register) vs **unexpected**
(exit non-zero).

**Rule:** `moon test --update --package parity` is NEVER run without a
matching entry in this register already committed (single-use approval path —
research Pitfall 3/7). Any diff NOT in this register is a regression and must
be fixed, not absorbed.

## 1. flink-lexical snapshot group (D-04, Pitfall 7)

Phase 10 mints an **independent** snapshot namespace under
`parity/__snapshot__/` with the filename shape
`flink-lexical.{fixture}.{profile}.{mode}.json`. The group is disjoint from
the Doris 213-snapshot baseline: a flink-lexical file can never collide with a
Doris baseline file, and vice versa.

Wave 1 mints exactly four files:

| New snapshot file | Meaning |
|-------------------|---------|
| `flink-lexical.hash-comment.flink-2.3.0.strict.json` | `a # comment` under flink-2.3.0 strict: FATHOM-PARSE-008 (statement not-implemented) + FATHOM-PARSE-003 (`#` lexical error) |
| `flink-lexical.hash-comment.flink-2.3.0.editor.json` | same input under flink-2.3.0 editor |
| `flink-lexical.hash-comment.doris-4.x.strict.json` | `a # comment` under doris-4.x strict: `#` is a comment, bare `a` is the existing FATHOM-PARSE-007 unsupported statement |
| `flink-lexical.hash-comment.doris-4.x.editor.json` | same input under doris-4.x editor |

The `hash-comment` fixture is the D-06 core conflict: the same raw bytes
tokenize differently per dialect (Flink `#` = lexical error; Doris `#` = line
comment). Each path is frozen independently so the difference is explainable by
its snapshot — no silent borrowing of either dialect's policy.

Machine-readable patterns (baseline_diff.py `--approve`):

```
field: calcite_version
field: parser_config
```

No `prefix:`/`key:` transition applies — the four files are **new files** in
the flink-lexical namespace, not byte changes to existing Doris snapshots.

## 2. Doris baseline zero-drift (D-07/D-08 continuation)

The Doris 213-snapshot baseline is **byte-identical** in Phase 10. The
flink-lexical group is additive only: no existing snapshot filename changes,
no Doris-named snapshot byte changes. `git diff --name-only -- parity/__snapshot__`
after the wave-1 approved `--update` must list only the four new
`flink-lexical.hash-comment.*.json` files.

## 3. Wire metadata fields (fathom.dialect.v1 / fathom.capabilities.v1)

Phase 10 unlocks the flink profile surface on the wire: `fathom_dialect_v1`
flink entries gain `calcite_version`/`parser_config`/`exact_release`/
`feature_introduction` fields (sourced only from `FlinkProfileMetadata`,
T-09-18 provenance), and `fathom_capabilities_v1` lists the three flink
profiles. No frozen parity snapshot captures these envelopes; registered for
auditability of the wire contract.

## 4. Usage rules

1. `moon test --update --package parity` requires a matching committed
   register entry BEFORE the update (single-use approval path).
2. Any snapshot diff not explained by section 1-3 is an unexpected regression:
   `scripts/baseline_diff.py` exits 1, and the diff must be reverted (never
   absorbed by another `--update`).
