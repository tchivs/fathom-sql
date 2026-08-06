#!/usr/bin/env node
// ECO-07 host checkpoint runner: launches real VS Code extension hosts via
// @vscode/test-electron against the local doris-lsp executable (Xvfb :99).
// Runs three isolated modes: functional (4.x), profile (2.1 gate), fallback (bad path).
import { runTests } from '@vscode/test-electron';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdtempSync, existsSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const extensionDevelopmentPath = root;
const extensionTestsPath = resolve(root, 'dist/host-test.js');
const lspPath = process.env.DORIS_LSP_PATH || '/opt/source/Fathom/_build/native/debug/build/lsp/lsp.exe';
const workspaceDir = process.env.DORIS_WORKSPACE || '/tmp/doris-host-workspace';

if (!existsSync(extensionTestsPath)) {
  console.error(`Missing compiled test: ${extensionTestsPath}. Run 'npm run compile' first.`);
  process.exit(1);
}
mkdirSync(workspaceDir, { recursive: true });

async function runMode(mode, env) {
  const userDataDir = mkdtempSync(join(tmpdir(), `vscode-host-${mode}-`));
  await runTests({
    extensionDevelopmentPath,
    extensionTestsPath,
    extensionTestsEnv: { ...env },
    launchArgs: [workspaceDir, '--disable-extensions', '--user-data-dir', userDataDir],
  });
  console.log(`HOST-MODE ${mode}: extension host exited cleanly`);
}

const modes = [
  { mode: 'functional', env: { VSCODE_HOST_MODE: 'functional', DORIS_LSP_PATH: lspPath, DORIS_PROFILE: '4.x' } },
  { mode: 'profile', env: { VSCODE_HOST_MODE: 'profile', DORIS_LSP_PATH: lspPath, DORIS_PROFILE: '2.1' } },
  { mode: 'fallback', env: { VSCODE_HOST_MODE: 'fallback', DORIS_LSP_PATH: lspPath, DORIS_PROFILE: '4.x' } },
];

for (const { mode, env } of modes) {
  await runMode(mode, env);
}

console.log('ECO-07 host checkpoint: all three modes passed in real VS Code.');
