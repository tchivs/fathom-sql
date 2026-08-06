#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

assert.equal(process.argv.includes('--offline'), true, 'offline smoke must be explicit');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [manifestText, indexText, adapterText] = await Promise.all([
  readFile(resolve(root, 'package.json'), 'utf8'),
  readFile(resolve(root, 'index.html'), 'utf8'),
  readFile(resolve(root, 'src/monaco-adapter.ts'), 'utf8'),
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
assert.match(adapterText, /schema_version === 'fathom\.error\.v1'/, 'fathom.error.v1 error envelope');
assert.deepEqual(['2.1', '3.x', '4.x'].filter((profile) => profile !== 'Auto'), ['2.1', '3.x', '4.x']);
const refusal = { accepted: false, formatted: [], diagnostics: [{ code: 'FATHOM-FORMAT-001' }] };
const sourceBytes = new TextEncoder().encode('SELECT /* hint */');
assert.equal(refusal.accepted, false);
assert.equal(new TextDecoder().decode(sourceBytes), 'SELECT /* hint */');
assert.equal(refusal.formatted.length, 0, 'refusal cannot provide an edit');
assert.equal(refusal.diagnostics[0].code, 'FATHOM-FORMAT-001');
console.log('web offline smoke: local artifact/dialect/refusal contracts passed');
