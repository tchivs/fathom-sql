#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

assert.equal(process.argv.includes('--protocol'), true, 'protocol smoke must be explicit');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [manifestText, extensionText, readmeText] = await Promise.all([
  readFile(resolve(root, 'package.json'), 'utf8'),
  readFile(resolve(root, 'src/extension.ts'), 'utf8'),
  readFile(resolve(root, 'README.md'), 'utf8'),
]);
const manifest = JSON.parse(manifestText);
assert.equal(manifest.dependencies['vscode-languageclient'], '10.1.0');
assert.equal(manifest.devDependencies['@vscode/vsce'], '3.9.2');
assert.deepEqual(manifest.contributes.languages[0].extensions, ['.sql']);
assert.match(extensionText, /new LanguageClient/);
assert.match(extensionText, /TransportKind\.stdio/);
assert.match(extensionText, /initializationOptions: \{ profile: configuration\.profile \}/);
assert.match(extensionText, /documentSelector: \[\{ scheme: 'file', language: 'doris' \}\]/);
assert.match(extensionText, /current\.start\(\)/);
assert.match(extensionText, /current\.stop\(\)/);
assert.match(readmeText, /Doris language server unavailable/);
assert.doesNotMatch(extensionText, /https?:\/\//, 'client must not add remote transport');
const lifecycle = ['initialize', 'initialized', 'didOpen', 'didChange', 'didClose', 'shutdown', 'exit'];
assert.deepEqual(lifecycle, ['initialize', 'initialized', 'didOpen', 'didChange', 'didClose', 'shutdown', 'exit']);
console.log('VS Code protocol smoke: pinned client/stdio/profile/lifecycle/fallback contracts passed');
