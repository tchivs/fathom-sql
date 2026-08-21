// @fathom-sql/sql build pipeline: build the binding for js+wasm, copy artifacts
// into the package root, regenerate capabilities.json, and produce the
// publish tarball. Run from the repository root: `node npm/build.mjs`.
import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const npmDir = resolve(root, 'npm');

function moon(...args) {
  execFileSync('moon', args, { cwd: root, stdio: 'inherit' });
}

console.log('[build] moon build --target js binding (release)');
moon('build', '--target', 'js', '--release', 'binding');
console.log('[build] moon build --target wasm binding (release)');
moon('build', '--target', 'wasm', '--release', 'binding');

const jsOut = resolve(root, '_build/js/release/build/binding/binding.js');
const wasmOut = resolve(root, '_build/wasm/release/build/binding/binding.wasm');
copyFileSync(jsOut, resolve(npmDir, 'binding.js'));
copyFileSync(wasmOut, resolve(npmDir, 'binding.wasm'));
console.log('[build] artifacts copied to npm/');

// Regenerate capabilities.json from the built binding.
const caps = await import(jsOut + '?t=' + Date.now()).catch(async () => {
  // binding.js may be a large ESM module; import via dynamic path with cache-bust.
  return import(`file://${jsOut}?t=${Date.now()}`);
});
const envelope = JSON.parse(new TextDecoder().decode(caps.fathom_capabilities_v1()));
writeFileSync(resolve(npmDir, 'capabilities.json'), JSON.stringify(envelope, null, 2) + '\n');
console.log('[build] capabilities.json written');

// Pack the tarball (used by the smoke consumer).
execFileSync('npm', ['pack'], { cwd: npmDir, stdio: 'inherit' });
console.log('[build] npm pack complete');
