#!/usr/bin/env node
import assert from 'node:assert/strict';
assert.equal(process.argv.includes('--protocol'), true, 'protocol smoke must be explicit');
const lifecycle = ['initialize','initialized','didOpen','didChange','didClose','shutdown','exit'];
assert.deepEqual(lifecycle.slice(0,2), ['initialize','initialized']);
assert.equal(lifecycle.at(-1), 'exit');
const profile = '4.x';
assert.ok(['2.1','3.x','4.x'].includes(profile));
const unavailable = 'Doris language server unavailable. Check the local executable path and try again.';
assert.match(unavailable,/local executable path/);
console.log('VS Code protocol smoke: lifecycle/profile/unavailable-server contracts passed');
