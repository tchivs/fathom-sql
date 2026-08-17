// @fathom/sql — typed ESM wrapper over the MoonBit-built binding.
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
  return call(binding.fathom_lint_v1, bytes(raw), dialect, profile, mode);
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
