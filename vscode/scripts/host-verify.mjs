#!/usr/bin/env node
// ECO-07 host checkpoint runner: launches real VS Code extension hosts via
// @vscode/test-electron against the local fathom-lsp executable (Xvfb :99).
// Runs three isolated modes: functional (doris 4.x), profile (doris 2.1 gate),
// fallback (bad path).
import { runTests } from '@vscode/test-electron';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdtempSync, existsSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const extensionDevelopmentPath = root;
const extensionTestsPath = resolve(root, 'dist/host-test.js');
const lspPath = process.env.FATHOM_LSP_PATH || '/opt/source/Fathom/_build/native/debug/build/fathom-lsp/fathom-lsp.exe';
const workspaceDir = process.env.FATHOM_WORKSPACE || '/tmp/fathom-host-workspace';

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
  { mode: 'functional', env: { VSCODE_HOST_MODE: 'functional', FATHOM_LSP_PATH: lspPath, FATHOM_DIALECT: 'doris', FATHOM_PROFILE: '4.x' } },
  { mode: 'profile', env: { VSCODE_HOST_MODE: 'profile', FATHOM_LSP_PATH: lspPath, FATHOM_DIALECT: 'doris', FATHOM_PROFILE: '2.1' } },
  { mode: 'fallback', env: { VSCODE_HOST_MODE: 'fallback', FATHOM_LSP_PATH: lspPath, FATHOM_DIALECT: 'doris', FATHOM_PROFILE: '4.x' } },
];

for (const { mode, env } of modes) {
  await runMode(mode, env);
}

console.log('ECO-07 host checkpoint: all three modes passed in real VS Code.');
