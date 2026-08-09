# Phase 11 Approved Baseline Changes (D-08 register)

This register pre-declares every intentional byte/behavior change the Phase 11
waves (11-01..11-05) are allowed to make to the frozen v1 baseline
(`parity/__snapshot__`, D-07/D-08) and to the stable diagnostic-code contract
(D-04). Phase 11 lands the real Flink statement grammar (D-06) over the Phase
10 lexical core; the register is the approval path's whitelist for the
flink-grammar snapshot group and the registered flink-lexical re-generation.

**Rule:** `moon test --update --package parity` is NEVER run without a
matching entry in this register already committed (single-use approval path —
research Pitfall 3/7). Any diff NOT in this register is a regression and must
be fixed, not absorbed. **Doris 213-snapshot zero-drift is a HARD gate:** any
shared parser/CST change keeps the Doris 213 snapshots byte-identical; the
only snapshot changes this phase may make are the new `flink-grammar.*` group
and the registered `flink-lexical.*` re-generation (D-05/D-08, Pitfall 1/7).

## 1. FATHOM-PARSE-008 retirement (D-06, one-way)

Phase 10 minted `FATHOM-PARSE-008` ("flink grammar is not yet implemented in
this release") for the `parse_flink_segment` not-implemented route. Phase 11
replaces that route with the real Flink grammar (D-04/D-06). The code is
**retired and stays vacant — never reused** (the same vacancy convention as
`DORIS-PARSE-005`). Consumers that observed 008 in Phase 9/10 must expect the
real-grammar behavior from Phase 11 onward:

| Retired code | Disposition |
|--------------|-------------|
| `FATHOM-PARSE-008` | Vacant. No valid Flink statement produces it; the code is never reused. The Phase 10 flink-lexical assertions/snapshots that froze the not-implemented route are re-generated to the real-grammar expectations (item 4). Genuinely-unsupported whole statements route through `FATHOM-PARSE-007` (`unsupported_statement`); the phase-11 parser test, api flink entry, export smoke tests, formatter test, and LSP selection tests are updated in the same commit. |

## 2. FATHOM-PARSE-009 minting (D-04, one-way)

The bidirectional dialect-negative gate (SC4): Flink-only constructs in Doris
mode and Doris-only constructs in Flink mode are rejected with a
construct-level diagnostic. `FATHOM-PARSE-007` ("unsupported statement in the
selected profile") stays reserved for whole-statement unsupported; the new code
is for a clause/construct that is valid only in the other dialect:

| New code | Message | Meaning |
|----------|---------|---------|
| `FATHOM-PARSE-009` | "syntax is not supported in the selected dialect" | Construct-level dialect-gate rejection (D-04). Dialect identity rides in the parse envelope metadata (D-10), never in the code prefix. |

The `add_dialect_gate_diagnostic` helper emits 009 at every Doris-only
construct point in the Flink SELECT path (INTO OUTFILE, QUALIFY,
PARTITION/TABLET/SAMPLE/TABLESAMPLE/REPEATABLE table options) and every
Flink-only construct point in the Doris path (WATERMARK, computed/metadata
columns, PRIMARY KEY NOT ENFORCED, DISTRIBUTED ... INTO n BUCKETS,
PARTITIONED BY, WITH connector options, LIKE/AS, INSERT OVERWRITE/UPSERT/
ON CONFLICT, MATCH_RECOGNIZE, Window TVF — as each lands in 11-02..05).

## 3. flink-grammar snapshot group (D-05, Pitfall 7)

Phase 11 mints an **independent** snapshot namespace under
`parity/__snapshot__/` with the filename shape
`flink-grammar.{fixture}.{profile}.{strict,editor}.json`. The group is
disjoint from the Doris 213-snapshot baseline AND from the flink-lexical
group: a flink-grammar file can never collide with either.

Wave 1 (11-01) mints the FLINK-02 core-query fixtures (positive SELECT with
CTE+JOIN+aggregation, incomplete SELECT recovery, and the set-operation
positives UNION [ALL] / INTERSECT / EXCEPT, both strict and editor modes):

| New snapshot file | Meaning |
|-------------------|---------|
| `flink-grammar.select-cte-join-agg.flink-2.3.0.{strict,editor}.json` | `WITH o AS (...) SELECT u.name, SUM(o.amount) AS total FROM o JOIN users u ON ... GROUP BY u.name` under flink-2.3.0: real Select CST, valid=true |
| `flink-grammar.select-incomplete.flink-2.3.0.{strict,editor}.json` | `SELECT a, b FROM t WHERE` under flink-2.3.0: bounded Missing/Error node, print_lossless round-trip |
| `flink-grammar.set-union-all.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 UNION ALL SELECT a FROM t2` (CompoundQuery, Parser-calcite-1.36.0.jj:3395) |
| `flink-grammar.set-intersect.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 INTERSECT SELECT a FROM t2` |
| `flink-grammar.set-except.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 EXCEPT SELECT a FROM t2` |
| `flink-grammar.set-intersect-all.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 INTERSECT ALL SELECT a FROM t2` |
| `flink-grammar.set-except-all.flink-2.3.0.{strict,editor}.json` | `SELECT a FROM t1 EXCEPT ALL SELECT a FROM t2` |

The fixtures live under `parity/fixtures/flink-grammar/` with a provenance
`manifest.tsv` recording the pinned release archive (url/sha512/tag/commit)
and the grammar production line references (RESEARCH §5, D-05 — never
folklore).

## 4. flink-lexical snapshot re-generation (D-06, registered)

The Phase 10 flink-lexical group froze the FATHOM-PARSE-008 not-implemented
route for the flink rows. Phase 11 replaces that route with the real grammar,
so the flink-side flink-lexical snapshots that carried 008 are re-generated to
the real-grammar expectations in the same approved-change. The Doris-side rows
of the flink-lexical group are byte-identical (Doris unchanged):

| Changed file group | Meaning |
|--------------------|---------|
| `flink-lexical.hash-comment.flink-2.3.0.{strict,editor}.json` | `a # comment` now routes to FATHOM-PARSE-007 (unsupported statement) + FATHOM-PARSE-003 (`#` lexical error) — no 008 |
| `flink-lexical.double-quote.flink-2.3.0.{strict,editor}.json` | `SELECT "a" FROM t` now parses to a select node with a FATHOM-PARSE-002 expression error on the DOUBLE_QUOTE symbol — no 008 |
| `flink-lexical.slash-comment.flink-2.3.0.{strict,editor}.json` | `SELECT a // comment` is now valid=true (real SELECT + SINGLE_LINE_COMMENT trivia) — no 008 |
| `flink-lexical.e-literal.flink-2.3.0.{strict,editor}.json` / `.flink-2.1.3.` / `.flink-1.20.5.` | E-literal SELECT rows now parse to real select nodes (2.3.0/2.1.3 valid; 1.20.5 has the E-identifier + string error) — no 008 |
| `flink-lexical.backtick-escape.flink-2.3.0.{strict,editor}.json` | `` SELECT `a``b` `` is now valid=true (BTID quoted identifier) — no 008 |
| `flink-lexical.unknown-profile.flink-4x.{strict,editor}.json` | UNCHANGED — the FATHOM-SCHEMA-003 selection rejection envelope never reaches the parser |

## 5. Doris 213-snapshot zero-drift confirmation

The Doris 213 baseline snapshots are byte-identical after every Phase 11 wave.
Any shared parser/CST change is re-run against `moon test --package parity`
(no `--update`) BEFORE landing; `git diff --name-only -- parity/__snapshot__`
shows only `flink-grammar.*` and the registered `flink-lexical.*` re-generation
after the approved `--update`, never a doris-named file.

Machine-readable patterns (baseline_diff.py `--approve`):

```
field: dialect-gate
code: FATHOM-PARSE-009
```
