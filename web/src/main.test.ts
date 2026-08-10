import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ARTIFACT_FAILURE,
  MISSING_SELECTION,
  ParserAdapter,
  byteToPosition,
  diagnosticRange,
  utf8Bytes,
} from './monaco-adapter.ts';

const encoder = new TextEncoder();
const jsonBytes = (value) => encoder.encode(JSON.stringify(value));

function fakeArtifact(calls) {
  return {
    fathom_parse_v1(raw, dialect, profile, mode) {
      calls.push({ operation: 'parse', raw: [...raw], dialect, profile, mode });
      return jsonBytes({
        schema_version: 'fathom.parse.v1', dialect, profile, mode, valid: true, recovered: false,
        source_bytes: [...raw], source_byte_length: raw.length, root: { kind: 'document', start_byte: 0, end_byte: raw.length, children: [] }, diagnostics: [],
      });
    },
    fathom_format_v1(raw, dialect, profile, mode) {
      calls.push({ operation: 'format', raw: [...raw], dialect, profile, mode });
      return jsonBytes({
        schema_version: 'fathom.format.v1', dialect, profile, accepted: true,
        source_bytes: [...raw], source_byte_length: raw.length, formatted: [...encoder.encode('SELECT 1;\n')], diagnostics: [], statement_offsets: [0],
      });
    },
    fathom_complete_v1(raw, dialect, profile, cursorByte) {
      calls.push({ operation: 'complete', raw: [...raw], dialect, profile, cursorByte });
      return jsonBytes({
        schema_version: 'fathom.complete.v1', dialect, profile, is_incomplete: false,
        items: [{ label: 'FROM', detail: 'SQL syntax keyword', start_byte: 7, end_byte: 9, new_text: 'FROM' }],
      });
    },
  };
}

test('adapter loads one relative artifact and propagates explicit dialect/profile/source', async () => {
  const calls = [];
  const artifact = fakeArtifact(calls);
  const relativeUrl = new URL('../../_build/js/debug/build/binding/binding.js', import.meta.url);
  const adapter = new ParserAdapter(relativeUrl, async (url) => {
    assert.equal(url.protocol, 'file:');
    assert.equal(url.pathname.endsWith('/_build/js/debug/build/binding/binding.js'), true);
    return artifact;
  });
  const source = 'SELECT 1';
  const result = await adapter.parse(source, 'doris', '3.x');
  assert.equal(result.schema_version, 'fathom.parse.v1');
  assert.equal(result.dialect, 'doris');
  assert.equal(result.profile, '3.x');
  assert.deepEqual(result.source_bytes, [...utf8Bytes(source)]);
  const formatted = await adapter.format(source, 'doris', '3.x');
  assert.equal(formatted.output, 'SELECT 1;\n');
  assert.deepEqual(calls.map((call) => call.operation), ['parse', 'format']);
  assert.equal(calls[0].mode, 'editor');
  assert.equal(calls[1].mode, 'strict');
  assert.equal(calls[0].dialect, 'doris');
  assert.equal(calls[1].dialect, 'doris');
  assert.equal(calls[0].profile, '3.x');
});

test('adapter rejects a missing or unsupported selection before artifact calls (D-02)', async () => {
  const adapter = new ParserAdapter(new URL('file:///local/binding.js'), async () => { throw new Error('must not load'); });
  await assert.rejects(() => adapter.parse('SELECT 1', '', ''), new RegExp(MISSING_SELECTION));
  await assert.rejects(() => adapter.parse('SELECT 1', 'Auto', '2.1'), new RegExp(MISSING_SELECTION));
  await assert.rejects(() => adapter.format('SELECT 1', 'doris', 'mysql'), new RegExp(MISSING_SELECTION));
});

test('adapter validates (dialect, profile) pairs per dialect — cross-dialect profiles rejected (D-05)', async () => {
  const adapter = new ParserAdapter(new URL('file:///local/binding.js'), async () => { throw new Error('must not load'); });
  await assert.rejects(() => adapter.parse('SELECT 1', 'flink', '2.1'), new RegExp(MISSING_SELECTION));
  await assert.rejects(() => adapter.parse('SELECT 1', 'doris', 'flink-2.3.0'), new RegExp(MISSING_SELECTION));
  await assert.rejects(() => adapter.format('SELECT 1', 'flink', '4.x'), new RegExp(MISSING_SELECTION));
  await assert.rejects(() => adapter.complete('SELECT FRO', 'doris', 'flink-1.20.5', 9), new RegExp(MISSING_SELECTION));
});

test('adapter complete() calls fathom_complete_v1 with the A4 args and decodes the envelope (D-04)', async () => {
  const calls = [];
  const artifact = fakeArtifact(calls);
  const relativeUrl = new URL('../../_build/js/debug/build/binding/binding.js', import.meta.url);
  const adapter = new ParserAdapter(relativeUrl, async (url) => {
    assert.equal(url.protocol, 'file:');
    return artifact;
  });
  const source = 'SELECT FRO';
  const result = await adapter.complete(source, 'flink', 'flink-2.3.0', 9);
  assert.equal(result.schema_version, 'fathom.complete.v1');
  assert.equal(result.dialect, 'flink');
  assert.equal(result.profile, 'flink-2.3.0');
  assert.equal(result.items[0].label, 'FROM');
  assert.equal(calls[0].operation, 'complete');
  assert.equal(calls[0].dialect, 'flink');
  assert.equal(calls[0].profile, 'flink-2.3.0');
  assert.equal(calls[0].cursorByte, 9);
  assert.deepEqual(calls[0].raw, [...utf8Bytes(source)]);
});

test('UTF-16 diagnostic ranges are derived from authoritative UTF-8 bytes', () => {
  const source = '🙂\r\nSELECT 名称';
  const raw = utf8Bytes(source);
  assert.deepEqual(byteToPosition(raw, 4), { line: 0, character: 2 });
  assert.deepEqual(byteToPosition(raw, 6), { line: 1, character: 0 });
  const diagnostic = diagnosticRange(raw, { start_byte: 13, end_byte: raw.length });
  assert.deepEqual(diagnostic.start, { line: 1, character: 7 });
  assert.deepEqual(diagnostic.end, { line: 1, character: 9 });
});

test('artifact failure copy is actionable and local-only', () => {
  assert.equal(new URL('../../_build/js/debug/build/binding/binding.js', import.meta.url).protocol, 'file:');
  assert.match(ARTIFACT_FAILURE, /Reload the demo/);
  assert.match(ARTIFACT_FAILURE, /no network or database connection/);
});
