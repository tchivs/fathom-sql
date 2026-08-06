const DEFAULT_ARTIFACT_URL = new URL('../../_build/js/debug/build/binding/binding.js', import.meta.url);

export const DIALECTS = Object.freeze(['doris', 'flink']);
export const PROFILES = Object.freeze(['2.1', '3.x', '4.x']);
export const ARTIFACT_FAILURE = 'The local parser artifact could not be loaded. Reload the demo; no network or database connection is required.';
export const MISSING_SELECTION = 'Choose a dialect and a supported profile before parsing.';

const decoder = new TextDecoder();
const encoder = new TextEncoder();

function decodeResult(bytes) {
  let value;
  try {
    value = JSON.parse(decoder.decode(bytes));
  } catch {
    throw new Error('The local parser artifact returned an unreadable result.');
  }
  if (value && value.schema_version === 'fathom.error.v1') {
    const error = new Error(value.message || 'The local parser operation failed.');
    error.code = value.code;
    error.payload = value;
    throw error;
  }
  return value;
}

function bytes(value) {
  return value instanceof Uint8Array ? value : new Uint8Array(value);
}

export function utf8Bytes(source) {
  return encoder.encode(source);
}

export function decodeUtf8(value) {
  return decoder.decode(bytes(value));
}

export function byteToPosition(sourceBytes, byteOffset) {
  const raw = bytes(sourceBytes);
  const offset = Math.max(0, Math.min(byteOffset, raw.length));
  let line = 0;
  let character = 0;
  let index = 0;
  while (index < offset) {
    const first = raw[index];
    let width = 1;
    let codePoint = first;
    if (first >= 0xf0 && index + 3 < raw.length) {
      width = 4;
      codePoint = ((first & 7) << 18) | ((raw[index + 1] & 63) << 12) | ((raw[index + 2] & 63) << 6) | (raw[index + 3] & 63);
    } else if (first >= 0xe0 && index + 2 < raw.length) {
      width = 3;
      codePoint = ((first & 15) << 12) | ((raw[index + 1] & 63) << 6) | (raw[index + 2] & 63);
    } else if (first >= 0xc0 && index + 1 < raw.length) {
      width = 2;
      codePoint = ((first & 31) << 6) | (raw[index + 1] & 63);
    }
    if (index + width > offset) break;
    index += width;
    if (codePoint === 0x0a) {
      line += 1;
      character = 0;
    } else if (codePoint !== 0x0d) {
      character += codePoint > 0xffff ? 2 : 1;
    }
  }
  return { line, character };
}

export function diagnosticRange(sourceBytes, diagnostic) {
  return {
    start: byteToPosition(sourceBytes, diagnostic.start_byte ?? 0),
    end: byteToPosition(sourceBytes, diagnostic.end_byte ?? diagnostic.start_byte ?? 0),
  };
}

export class ParserAdapter {
  constructor(artifactUrl = DEFAULT_ARTIFACT_URL, importer = (url) => import(url.href)) {
    this.artifactUrl = artifactUrl;
    this.importer = importer;
    this.module = null;
  }

  async load() {
    if (!this.module) this.module = await this.importer(this.artifactUrl);
    return this.module;
  }

  // D-02: no implicit selection. Both dialect and profile must be chosen
  // explicitly; a missing or unsupported value is an error, never a default.
  validateSelection(dialect, profile) {
    if (!DIALECTS.includes(dialect) || !PROFILES.includes(profile)) {
      throw new Error(MISSING_SELECTION);
    }
  }

  async parse(source, dialect, profile) {
    this.validateSelection(dialect, profile);
    const module = await this.load();
    return decodeResult(module.fathom_parse_v1(utf8Bytes(source), dialect, profile, 'editor'));
  }

  async format(source, dialect, profile) {
    this.validateSelection(dialect, profile);
    const module = await this.load();
    const result = decodeResult(module.fathom_format_v1(
      utf8Bytes(source), dialect, profile, 'strict', 'upper', 2, 100, 'trailing', 'follow', true,
    ));
    return { ...result, output: result.formatted ? decodeUtf8(result.formatted) : '' };
  }
}

export { DEFAULT_ARTIFACT_URL };
