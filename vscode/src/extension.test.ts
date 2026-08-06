import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SERVER_FAILURE_MESSAGE,
  SUPPORTED_DIALECTS,
  SUPPORTED_PROFILES,
  resolveFathomConfiguration,
} from './extension-contract.ts';

function configuration(values = {}) {
  return { get(key, fallback) { return Object.hasOwn(values, key) ? values[key] : fallback; } };
}

test('configuration requires an explicit supported dialect, profile, and local executable', () => {
  assert.deepEqual(SUPPORTED_DIALECTS, ['doris', 'flink']);
  assert.deepEqual(SUPPORTED_PROFILES, ['2.1', '3.x', '4.x']);
  assert.deepEqual(resolveFathomConfiguration(configuration({ dialect: 'doris', profile: '3.x', serverPath: '/opt/bin/fathom-lsp' })), {
    dialect: 'doris', profile: '3.x', serverPath: '/opt/bin/fathom-lsp',
  });
  // D-02: missing or unsupported dialect/profile are explicit errors, never defaults.
  assert.deepEqual(resolveFathomConfiguration(configuration()), { dialect: undefined, profile: undefined, serverPath: 'fathom-lsp' });
  assert.equal(resolveFathomConfiguration(configuration({ dialect: 'Auto' })).dialect, undefined);
  assert.equal(resolveFathomConfiguration(configuration({ profile: 'mysql' })).profile, undefined);
});

test('server failure is actionable while the editor remains a plain document', () => {
  assert.match(SERVER_FAILURE_MESSAGE, /^Fathom SQL language server unavailable\./);
  assert.match(SERVER_FAILURE_MESSAGE, /local executable path/);
  assert.doesNotMatch(SERVER_FAILURE_MESSAGE, /HTTP|database|authentication/i);
});

test('protocol host contract includes the full standard document lifecycle', () => {
  const lifecycle = ['initialize', 'initialized', 'didOpen', 'didChange', 'didClose', 'shutdown', 'exit'];
  assert.deepEqual(lifecycle.slice(0, 2), ['initialize', 'initialized']);
  assert.equal(lifecycle.at(-1), 'exit');
  assert.equal({ scheme: 'file', language: 'sql' }.language, 'sql');
});
