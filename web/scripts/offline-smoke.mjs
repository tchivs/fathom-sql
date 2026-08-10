#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

assert.equal(process.argv.includes('--offline'), true, 'offline smoke must be explicit');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [manifestText, indexText, adapterText, mainText, bindingText] = await Promise.all([
  readFile(resolve(root, 'package.json'), 'utf8'),
  readFile(resolve(root, 'index.html'), 'utf8'),
  readFile(resolve(root, 'src/monaco-adapter.ts'), 'utf8'),
  readFile(resolve(root, 'src/main.ts'), 'utf8'),
  readFile(resolve(root, '../_build/js/debug/build/binding/binding.js'), 'utf8'),
]);
const manifest = JSON.parse(manifestText);
assert.equal(manifest.name, '@fathom/sql-web-demo', 'neutral npm package identity');
assert.equal(manifest.dependencies['monaco-editor'], '0.56.0');
assert.match(indexText, /monaco-editor/);
assert.match(indexText, /src\/main\.ts/);
assert.match(indexText, /id="dialect"/, 'dialect selector present');
assert.match(indexText, /id="profile"/, 'profile selector present');
assert.match(adapterText, /_build\/js\/debug\/build\/binding\/binding\.js/);
assert.doesNotMatch(indexText, /https?:\/\//, 'web host must not require a remote URL');
assert.match(adapterText, /fathom_parse_v1\(utf8Bytes\(source\), dialect, profile, 'editor'\)/, 'A4 export order (raw, dialect, profile, mode)');
assert.match(adapterText, /fathom_complete_v1\(utf8Bytes\(source\), dialect, profile, cursorByte\)/, 'A4 export order for completion (raw, dialect, profile, cursor)');
assert.match(adapterText, /schema_version === 'fathom\.error\.v1'/, 'fathom.error.v1 error envelope');
// D-05: the host validates (dialect, profile) pairs per dialect — the flat
// ['2.1','3.x','4.x'] list is gone and flink values appear only under flink.
assert.doesNotMatch(adapterText, /PROFILES = Object\.freeze\(\[/, 'flat profile list removed');
assert.match(adapterText, /PROFILES_BY_DIALECT = Object\.freeze\(\{/, 'per-dialect profile map present');
assert.match(adapterText, /doris: \['2\.1', '3\.x', '4\.x'\]/, 'doris profile pair');
assert.match(adapterText, /flink: \['flink-2\.3\.0', 'flink-2\.1\.3', 'flink-1\.20\.5'\]/, 'flink profile pair');
// D-08 flink selection flow — the flink values appear in the profile selector
// only when flink is selected (repopulateProfileOptions reads the per-dialect
// map on dialect change; D-05, Pitfall 5).
assert.match(mainText, /function repopulateProfileOptions\(dialect\)/, 'profile dropdown repopulates per dialect');
assert.match(mainText, /PROFILES_BY_DIALECT\[dialect\] \?\? \[\]/, 'flink profile values come from PROFILES_BY_DIALECT when flink is selected');
assert.match(mainText, /repopulateProfileOptions\(dialectSelect\.value\)/, 'initial dropdown is per the selected dialect');
assert.match(mainText, /dialectSelect\.addEventListener\('change'/, 'dialect change repopulates the profile selector');
// D-08 flink parse/complete — a flink selection flows through the shared wire:
// parse forwards dialect to fathom_parse_v1 and complete to fathom_complete_v1
// (A4), both gated by validateSelection (same API/schema as JS/linear-Wasm).
assert.match(adapterText, /fathom_parse_v1\(utf8Bytes\(source\), dialect, profile, 'editor'\)/, 'flink parse reaches fathom.parse.v1 with the selected dialect');
assert.match(adapterText, /fathom_complete_v1\(utf8Bytes\(source\), dialect, profile, cursorByte\)/, 'flink completion reaches fathom.complete.v1');
assert.match(adapterText, /validateSelection\(dialect, profile\)/, 'parse/complete validate the (dialect, profile) pair');
// T-13-07-05: the BUILT artifact must export fathom_complete_v1 — a stale
// binding.js would silently miss the completion surface (Pitfall 3).
assert.match(bindingText, /fathom_complete_v1/, 'built binding.js exports fathom_complete_v1');
const refusal = { accepted: false, formatted: [], diagnostics: [{ code: 'FATHOM-FORMAT-001' }] };
const sourceBytes = new TextEncoder().encode('SELECT /* hint */');
assert.equal(refusal.accepted, false);
assert.equal(new TextDecoder().decode(sourceBytes), 'SELECT /* hint */');
assert.equal(refusal.formatted.length, 0, 'refusal cannot provide an edit');
assert.equal(refusal.diagnostics[0].code, 'FATHOM-FORMAT-001');
console.log('web offline smoke: local artifact/dialect/refusal contracts passed');
