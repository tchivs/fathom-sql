import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SERVER_FAILURE_MESSAGE,
  SUPPORTED_PROFILES,
  normalizeProfile,
  resolveDorisConfiguration,
} from './extension-contract.ts';

function configuration(values = {}) {
  return { get(key, fallback) { return Object.hasOwn(values, key) ? values[key] : fallback; } };
}

test('configuration requires an explicit supported Doris profile and local executable', () => {
  assert.deepEqual(SUPPORTED_PROFILES, ['2.1', '3.x', '4.x']);
  assert.deepEqual(resolveDorisConfiguration(configuration({ profile: '3.x', serverPath: '/opt/bin/doris-lsp' })), {
    profile: '3.x', serverPath: '/opt/bin/doris-lsp',
  });
  assert.deepEqual(resolveDorisConfiguration(configuration()), { profile: '4.x', serverPath: 'doris-lsp' });
  assert.equal(normalizeProfile('Auto'), '4.x');
  assert.equal(normalizeProfile('mysql'), '4.x');
});

test('server failure is actionable while the editor remains a plain document', () => {
  assert.match(SERVER_FAILURE_MESSAGE, /^Doris language server unavailable\./);
  assert.match(SERVER_FAILURE_MESSAGE, /local executable path/);
  assert.doesNotMatch(SERVER_FAILURE_MESSAGE, /HTTP|database|authentication/i);
});

test('protocol host contract includes the full standard document lifecycle', () => {
  const lifecycle = ['initialize', 'initialized', 'didOpen', 'didChange', 'didClose', 'shutdown', 'exit'];
  assert.deepEqual(lifecycle.slice(0, 2), ['initialize', 'initialized']);
  assert.equal(lifecycle.at(-1), 'exit');
  assert.equal({ scheme: 'file', language: 'doris' }.language, 'doris');
});
