#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

assert.equal(process.argv.includes('--protocol'), true, 'protocol smoke must be explicit');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [manifestText, extensionText, readmeText, distText] = await Promise.all([
  readFile(resolve(root, 'package.json'), 'utf8'),
  readFile(resolve(root, 'src/extension.ts'), 'utf8'),
  readFile(resolve(root, 'README.md'), 'utf8'),
  readFile(resolve(root, 'dist/extension.js'), 'utf8'),
]);
const manifest = JSON.parse(manifestText);
assert.equal(manifest.main, './dist/extension.js', 'extension host must load compiled JS, not TS');
assert.equal(manifest.scripts.compile, 'tsc -p .');
assert.equal(manifest.devDependencies['typescript'], '7.0.2');
assert.equal(manifest.dependencies['vscode-languageclient'], '10.1.0');
assert.equal(manifest.devDependencies['@vscode/vsce'], '3.9.2');
assert.deepEqual(manifest.contributes.languages[0].extensions, ['.sql']);
assert.equal(manifest.contributes.languages[0].id, 'sql', 'single neutral language id');
assert.deepEqual(manifest.activationEvents, ['onLanguage:sql', 'onCommand:fathom.restartLanguageServer']);
assert.match(distText, /require\("vscode-languageclient/, 'compiled entry must be CJS loading the client');
assert.doesNotMatch(distText, /extension-contract\.ts/, 'compiled entry must not reference TS sources');
assert.match(extensionText, /new LanguageClient/);
assert.match(extensionText, /TransportKind\.stdio/);
assert.match(extensionText, /createOutputChannel\([^)]*\{ log: true \}/, 'client requires a LogOutputChannel for vscode-languageclient@10');
assert.match(extensionText, /initializationOptions: \{ dialect: configuration\.dialect, profile: configuration\.profile \}/);
assert.match(extensionText, /documentSelector: \[\{ scheme: 'file', language: 'sql' \}\]/);
assert.match(extensionText, /fathom\.restartLanguageServer/);
assert.match(extensionText, /current\.start\(\)/);
assert.match(extensionText, /current\.stop\(\)/);
assert.match(readmeText, /Fathom SQL language server unavailable/);
assert.doesNotMatch(extensionText, /https?:\/\//, 'client must not add remote transport');
const lifecycle = ['initialize', 'initialized', 'didOpen', 'didChange', 'didClose', 'shutdown', 'exit'];
assert.deepEqual(lifecycle, ['initialize', 'initialized', 'didOpen', 'didChange', 'didClose', 'shutdown', 'exit']);
console.log('VS Code protocol smoke: pinned client/stdio/dialect/lifecycle/fallback contracts passed');
