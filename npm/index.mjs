// @fathom-sql/sql — typed ESM wrapper over the MoonBit-built binding.
// The binding exports the fathom.*.v1 byte functions (raw bytes in, JSON
// bytes out); this module provides UTF-8 handling and typed call sites.
import * as binding from './binding.js';

const enc = new TextEncoder();
const dec = new TextDecoder();

function bytes(raw) {
  if (typeof raw === 'string') return enc.encode(raw);
  if (raw instanceof Uint8Array) return raw;
  throw new TypeError('raw must be a string or Uint8Array');
}

function call(fn, ...args) {
  return JSON.parse(dec.decode(fn(...args)));
}

/**
 * Parse SQL and return the fathom.parse.v1 envelope.
 * @param {string|Uint8Array} raw
 * @param {'doris'|'flink'} dialect
 * @param {string} profile - doris: 2.1|3.x|4.x; flink: flink-2.3.0|flink-2.1.3|flink-1.20.5
 * @param {'strict'|'editor'} [mode]
 */
export function parse(raw, dialect, profile, mode = 'strict') {
  return call(binding.fathom_parse_v1, bytes(raw), dialect, profile, mode);
}

/**
 * Format SQL and return the fathom.format.v1 envelope.
 * @param {string|Uint8Array} raw
 * @param {'doris'|'flink'} dialect
 * @param {string} profile
 * @param {'strict'|'editor'} [mode]
 * @param {{keyword_case?: 'upper'|'lower', indent?: number, line_width?: number, comma_style?: 'trailing'|'leading', newline_style?: 'follow'|'lf'|'crlf', trailing_newline?: boolean}} [options]
 */
export function format(raw, dialect, profile, mode = 'strict', options = {}) {
  const {
    keyword_case = 'upper',
    indent = 2,
    line_width = 100,
    comma_style = 'trailing',
    newline_style = 'follow',
    trailing_newline = true,
  } = options;
  return call(
    binding.fathom_format_v1,
    bytes(raw), dialect, profile, mode,
    keyword_case, indent, line_width, comma_style, newline_style, trailing_newline,
  );
}

/**
 * Complete SQL at a cursor and return the fathom.complete.v1 envelope.
 * @param {string|Uint8Array} raw
 * @param {'doris'|'flink'} dialect
 * @param {string} profile
 * @param {number} cursorByte
 */
export function complete(raw, dialect, profile, cursorByte) {
  return call(binding.fathom_complete_v1, bytes(raw), dialect, profile, cursorByte);
}

/**
 * Lint SQL and return the fathom.lint.v1 envelope.
 */
export function lint(raw, dialect, profile, mode = 'strict') {
  return call(binding.fathom_lint_v1, bytes(raw), dialect, profile, mode, new Uint8Array(), false);
}

/**
 * Fingerprint SQL and return the fathom.fingerprint.v1 envelope.
 */
export function fingerprint(raw, dialect, profile, mode = 'strict') {
  return call(binding.fathom_fingerprint_v1, bytes(raw), dialect, profile, mode);
}

/**
 * Derive lineage and return the fathom.lineage.v1 envelope.
 */
export function lineage(raw, dialect, profile, mode = 'strict') {
  return call(binding.fathom_lineage_v1, bytes(raw), dialect, profile, mode);
}

/**
 * Global capability metadata under fathom.capabilities.v1.
 */
export function capabilities() {
  return call(binding.fathom_capabilities_v1);
}

/**
 * Per-dialect metadata under fathom.dialect.v1.
 * @param {'doris'|'flink'} dialect
 */
export function dialect(d) {
  return call(binding.fathom_dialect_v1, d);
}

/**
 * Convert a UTF-8 byte offset in source text to a 0-based { line, column } position.
 * Line and column counts Unicode code points (useful for editor display).
 * @param {string|Uint8Array} raw - the original source text
 * @param {number} byteOffset - UTF-8 byte offset
 * @returns {{line: number, column: number}}
 */
export function byteOffsetToLineColumn(raw, byteOffset) {
  const text = typeof raw === 'string' ? raw : dec.decode(bytes(raw));
  let line = 0;
  let col = 0;
  // Walk byte-by-byte through the UTF-8 encoded text to find the position.
  const encoded = enc.encode(text);
  const clamped = Math.min(byteOffset, encoded.length);
  for (let i = 0; i < clamped; i++) {
    // Decode the byte to determine if it's a newline or part of a multi-byte char.
    const byte = encoded[i];
    if (byte === 0x0a) { // \n
      line++;
      col = 0;
    } else if ((byte & 0xc0) !== 0x80) {
      // Start of a UTF-8 code point (not a continuation byte)
      col++;
    }
  }
  return { line, column: col };
}

/**
 * Convert a 0-based { line, column } position to a UTF-8 byte offset.
 * @param {string|Uint8Array} raw - the original source text
 * @param {number} line - 0-based line number
 * @param {number} column - 0-based column (code points)
 * @returns {number} byte offset
 */
export function lineColumnToByteOffset(raw, line, column) {
  const text = typeof raw === 'string' ? raw : dec.decode(bytes(raw));
  const encoded = enc.encode(text);
  let currentLine = 0;
  let currentCol = 0;
  for (let i = 0; i < encoded.length; i++) {
    if (currentLine === line && currentCol === column) {
      return i;
    }
    const byte = encoded[i];
    if (byte === 0x0a) {
      currentLine++;
      currentCol = 0;
    } else if ((byte & 0xc0) !== 0x80) {
      currentCol++;
    }
  }
  // If pointing past end, return the encoded length
  if (currentLine === line && currentCol === column) {
    return encoded.length;
  }
  return encoded.length;
}

/**
 * Attach 0-based { line, column } positions to each diagnostic by converting
 * the start_byte/end_byte fields. Returns the same diagnostics array with
 * added start_line, start_column, end_line, end_column fields.
 * @param {string|Uint8Array} raw - the original source text
 * @param {Array} diagnostics - diagnostics array from parse/lint
 * @returns {Array} the same array with position fields added in-place
 */
export function withLineColumns(raw, diagnostics) {
  for (const d of diagnostics) {
    const start = byteOffsetToLineColumn(raw, d.start_byte ?? 0);
    const end = byteOffsetToLineColumn(raw, d.end_byte ?? d.start_byte ?? 0);
    d.start_line = start.line;
    d.start_column = start.column;
    d.end_line = end.line;
    d.end_column = end.column;
  }
  return diagnostics;
}
