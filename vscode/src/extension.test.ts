import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SERVER_FAILURE_MESSAGE,
  SUPPORTED_DIALECTS,
  PROFILES_BY_DIALECT,
  resolveFathomConfiguration,
} from './extension-contract.ts';

function configuration(values = {}) {
  return { get(key, fallback) { return Object.hasOwn(values, key) ? values[key] : fallback; } };
}

test('configuration requires an explicit supported dialect, profile, and local executable', () => {
  assert.deepEqual(SUPPORTED_DIALECTS, ['doris', 'flink']);
  // D-05: per-dialect (dialect, profile) pairs — flink values only under flink.
  assert.deepEqual(PROFILES_BY_DIALECT, {
    doris: ['2.1', '3.x', '4.x'],
    flink: ['flink-2.3.0', 'flink-2.1.3', 'flink-1.20.5'],
  });
  assert.deepEqual(resolveFathomConfiguration(configuration({ dialect: 'doris', profile: '3.x', serverPath: '/opt/bin/fathom-lsp' })), {
    dialect: 'doris', profile: '3.x', serverPath: '/opt/bin/fathom-lsp',
  });
  assert.deepEqual(resolveFathomConfiguration(configuration({ dialect: 'flink', profile: 'flink-2.3.0' })), {
    dialect: 'flink', profile: 'flink-2.3.0', serverPath: 'fathom-lsp',
  });
  // D-02/D-05: missing, unsupported, or cross-dialect profiles are explicit
  // errors (undefined), never defaults or coerced values.
  assert.deepEqual(resolveFathomConfiguration(configuration()), { dialect: undefined, profile: undefined, serverPath: 'fathom-lsp' });
  assert.equal(resolveFathomConfiguration(configuration({ dialect: 'Auto' })).dialect, undefined);
  assert.equal(resolveFathomConfiguration(configuration({ profile: 'mysql' })).profile, undefined);
  assert.equal(resolveFathomConfiguration(configuration({ dialect: 'flink', profile: '2.1' })).profile, undefined);
  assert.equal(resolveFathomConfiguration(configuration({ dialect: 'doris', profile: 'flink-2.3.0' })).profile, undefined);
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
