/**
 * Type declarations for @fathom-sql/sql.
 *
 * Every API returns the raw JSON envelope decoded from the corresponding
 * `fathom.*.v1` wire namespace. Envelope fields beyond the documented core
 * are accessible via index signatures.
 */

export type Dialect = 'doris' | 'flink';
export type DorisProfile = '2.1' | '3.x' | '4.x';
export type FlinkProfile = 'flink-2.3.0' | 'flink-2.1.3' | 'flink-1.20.5';
export type Profile = DorisProfile | FlinkProfile;
export type Mode = 'strict' | 'editor';
export type Raw = string | Uint8Array;

export interface Envelope {
  schema_version: string;
  [key: string]: unknown;
}

/** fathom.parse.v1 */
export interface ParseEnvelope extends Envelope {
  valid: boolean;
  diagnostics: unknown[];
}

/** fathom.format.v1 — formatted output is a byte array in the `formatted` field */
export interface FormatEnvelope extends Envelope {
  accepted: boolean;
  formatted: number[];
  diagnostics: unknown[];
}

/** fathom.fingerprint.v1 */
export interface FingerprintEnvelope extends Envelope {
  fingerprint: string;
}

export interface FormatOptions {
  keyword_case?: 'upper' | 'lower';
  indent?: number;
  line_width?: number;
  comma_style?: 'trailing' | 'leading';
  newline_style?: 'follow' | 'lf' | 'crlf';
  trailing_newline?: boolean;
}

export interface CapabilitiesEnvelope extends Envelope {
  dialects: unknown[];
}

export function parse(raw: Raw, dialect: Dialect, profile: Profile, mode?: Mode): ParseEnvelope;
export function format(raw: Raw, dialect: Dialect, profile: Profile, mode?: Mode, options?: FormatOptions): FormatEnvelope;
export function complete(raw: Raw, dialect: Dialect, profile: Profile, cursorByte: number): Envelope;
export function lint(raw: Raw, dialect: Dialect, profile: Profile, mode?: Mode): Envelope;
export function fingerprint(raw: Raw, dialect: Dialect, profile: Profile, mode?: Mode): FingerprintEnvelope;
export function lineage(raw: Raw, dialect: Dialect, profile: Profile, mode?: Mode): Envelope;
export function capabilities(): CapabilitiesEnvelope;
export function dialect(d: Dialect): Envelope;

/** 0-based line/column position (Unicode code points, not UTF-16 units) */
export interface LineColumn {
  line: number;
  column: number;
}

/** Diagnostic with attached line/column positions */
export interface PositionedDiagnostic {
  start_byte: number;
  end_byte: number;
  start_line: number;
  start_column: number;
  end_line: number;
  end_column: number;
  [key: string]: unknown;
}

/** Convert a UTF-8 byte offset to a 0-based { line, column } position. */
export function byteOffsetToLineColumn(raw: Raw, byteOffset: number): LineColumn;

/** Convert a 0-based { line, column } position to a UTF-8 byte offset. */
export function lineColumnToByteOffset(raw: Raw, line: number, column: number): number;

/**
 * Attach 0-based start_line/start_column/end_line/end_column to each diagnostic
 * by converting start_byte/end_byte. Mutates and returns the same array.
 */
export function withLineColumns<T extends { start_byte?: number; end_byte?: number }>(raw: Raw, diagnostics: T[]): (T & PositionedDiagnostic)[];
