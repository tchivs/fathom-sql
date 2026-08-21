// Consumer smoke test (NPM-02): installs @fathom-sql/sql from the packed tarball
// and exercises parse/format/fingerprint/lint/capabilities/lineColumn end to end.
import assert from 'node:assert/strict';
import { parse, format, fingerprint, lint, capabilities, byteOffsetToLineColumn, lineColumnToByteOffset, withLineColumns } from '@fathom-sql/sql';

// parse: valid statement, no diagnostics
const parsed = parse('SELECT 1', 'doris', '4.x', 'strict');
assert.equal(parsed.valid, true, 'SELECT 1 must be valid');
assert.equal(parsed.diagnostics.length, 0, 'no diagnostics expected');

// fingerprint: deterministic non-empty fingerprint
const fp = fingerprint('SELECT 1', 'doris', '4.x', 'strict');
assert.ok(fp.fingerprint && fp.fingerprint.length > 0, 'fingerprint must be non-empty');
const fp2 = fingerprint('SELECT 1', 'doris', '4.x', 'strict');
assert.equal(fp.fingerprint, fp2.fingerprint, 'fingerprint must be deterministic');

// format: round-trips to uppercase canonical form
const fmt = format('select 1', 'doris', '4.x', 'strict', { keyword_case: 'upper' });
assert.equal(fmt.accepted, true, 'format must be accepted');
assert.equal(new TextDecoder().decode(new Uint8Array(fmt.formatted)), 'SELECT 1\n', 'canonical output');

// capabilities: doris + flink profiles recorded
const caps = capabilities();
const dialects = caps.dialects.map((d) => d.dialect ?? d.id ?? d);
assert.ok(dialects.includes('doris'), 'doris dialect present');
assert.ok(dialects.includes('flink'), 'flink dialect present');
const dorisInfo = caps.dialects.find((d) => (d.dialect ?? d.id) === 'doris');
const flinkInfo = caps.dialects.find((d) => (d.dialect ?? d.id) === 'flink');
const dProfiles = (dorisInfo?.profiles ?? []).map((p) => p.id ?? p);
const fProfiles = (flinkInfo?.profiles ?? []).map((p) => p.id ?? p);
for (const p of ['2.1', '3.x', '4.x']) assert.ok(dProfiles.includes(p), `doris profile ${p}`);
for (const p of ['flink-2.3.0', 'flink-2.1.3', 'flink-1.20.5']) assert.ok(fProfiles.includes(p), `flink profile ${p}`);

// byteOffsetToLineColumn: convert byte offset to 0-based line/column
const pos = byteOffsetToLineColumn('SELECT 1\nFROM t', 9); // offset 9 = start of "FROM"
assert.equal(pos.line, 1, 'line 1 for offset 9');
assert.equal(pos.column, 0, 'column 0 for offset 9');

// lineColumnToByteOffset: round-trip back
const offset = lineColumnToByteOffset('SELECT 1\nFROM t', 1, 0);
assert.equal(offset, 9, 'offset 9 for line 1 col 0');

// withLineColumns: attach positions to diagnostics
const errResult = parse('SELECT FROM', 'doris', '4.x', 'strict');
assert.ok(errResult.diagnostics.length > 0, 'should have diagnostics');
const positioned = withLineColumns('SELECT FROM', [...errResult.diagnostics]);
assert.ok(positioned[0].start_line !== undefined, 'start_line should be set');
assert.ok(positioned[0].start_column !== undefined, 'start_column should be set');

// lint: regression for issue #1 — lint() must not crash on any dialect/mode.
// fathom_lint_v1 expects (raw, dialect, profile, mode, overrides, fix); the
// wrapper must supply empty overrides + fix=false, not pass undefined.
for (const [d, p, m] of [
  ['flink', 'flink-1.20.5', 'editor'],
  ['flink', 'flink-1.20.5', 'strict'],
  ['doris', '4.x', 'editor'],
  ['doris', '4.x', 'strict'],
]) {
  const r = lint('SELECT 1', d, p, m);
  assert.equal(r.schema_version, 'fathom.lint.v1', `lint ${d}/${p}/${m} schema`);
  assert.equal(r.accepted, true, `lint ${d}/${p}/${m} accepted`);
  assert.ok(Array.isArray(r.findings), `lint ${d}/${p}/${m} findings array`);
}

console.log('SMOKE PASS: parse/format/fingerprint/lint/capabilities/lineColumn verified');
