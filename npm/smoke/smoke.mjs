// Consumer smoke test (NPM-02): installs @fathom/sql from the packed tarball
// and exercises parse/format/fingerprint/capabilities end to end.
import assert from 'node:assert/strict';
import { parse, format, fingerprint, capabilities } from '@fathom/sql';

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
const doris = caps.dialects.find((d) => (d.dialect ?? d.id) === 'doris');
const flink = caps.dialects.find((d) => (d.dialect ?? d.id) === 'flink');
const dorisProfiles = (doris.profiles ?? []).map((p) => p.id ?? p);
const flinkProfiles = (flink.profiles ?? []).map((p) => p.id ?? p);
for (const p of ['2.1', '3.x', '4.x']) assert.ok(dorisProfiles.includes(p), `doris profile ${p}`);
for (const p of ['flink-2.3.0', 'flink-2.1.3', 'flink-1.20.5']) assert.ok(flinkProfiles.includes(p), `flink profile ${p}`);

console.log('SMOKE PASS: parse/format/fingerprint/capabilities verified');
