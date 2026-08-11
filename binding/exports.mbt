/// Stable primitive exports for JavaScript ESM and linear Wasm hosts.
///
/// Every result is UTF-8 encoded JSON bytes. The only input bytes are the raw
/// SQL source; no MoonBit ADT, object handle, or host memory address crosses
/// this boundary. `fathom_parse_v1`, `fathom_format_v1`, and
/// `fathom_complete_v1` are the ABI surface (dialect right after raw,
/// consistent with ParseOptions::new and the CLI, A4); the metadata exports
/// let hosts negotiate dialects, profiles, and capabilities without parsing
/// an SQL document first. `fathom_dialect_v1` reports a dialect's available
/// profiles with release metadata under fathom.dialect.v1;
/// `fathom_capabilities_v1` reports the global dialect list with per-dialect
/// profile availability under fathom.capabilities.v1.

fn json_bytes(value : String) -> Bytes {
  @utf8.encode(value)
}

fn error_bytes(code : String, message : String) -> Bytes {
  json_bytes(error_json(code, message))
}

fn parse_error_bytes(error : @api.ParseError) -> Bytes {
  json_bytes(parse_error_json(error))
}

fn format_error_bytes(error : @api.FormatError) -> Bytes {
  json_bytes(format_error_json(error))
}

#export_name("fathom_parse_v1")
pub fn fathom_parse_v1(raw : Bytes, dialect : String, profile : String, mode : String) -> Bytes {
  match @api.parse_with_ids(raw, dialect, profile, mode) {
    Ok(result) => json_bytes(parse_result_json(result))
    Err(error) => parse_error_bytes(error)
  }
}

#export_name("fathom_format_v1")
pub fn fathom_format_v1(
  raw : Bytes,
  dialect : String,
  profile : String,
  mode : String,
  keyword_case : String,
  indent : Int,
  line_width : Int,
  comma_style : String,
  newline_style : String,
  trailing_newline : Bool,
) -> Bytes {
  // Dialect/profile validated FIRST (Pitfall 6, T-09-10): a flink request is
  // accepted only for the three pinned release profiles; unknown flink
  // profiles reject with the structured unsupported-profile error before any
  // option parsing or formatting — never a Doris-policy format of a flink
  // request. The ParseOptions also supplies the exact_release metadata for the
  // result envelope (DIALECT-04).
  let selection = match @api.ParseOptions::new(dialect, profile, mode) {
    Ok(options) => options
    Err(error) => return parse_error_bytes(error)
  }
  let keyword_case_value = match @api.KeywordCase::from_id(keyword_case) {
    Some(value) => value
    None => return error_bytes("FATHOM-FORMAT-002", "unsupported keyword case: \{keyword_case}")
  }
  let comma_style_value = match @api.CommaStyle::from_id(comma_style) {
    Some(value) => value
    None => return error_bytes("FATHOM-FORMAT-003", "unsupported comma style: \{comma_style}")
  }
  let newline_style_value = match @api.NewlineStyle::from_id(newline_style) {
    Some(value) => value
    None => return error_bytes("FATHOM-FORMAT-004", "unsupported newline style: \{newline_style}")
  }
  let options = match @api.FormatOptions::new(
    keyword_case_value,
    indent,
    line_width,
    comma_style_value,
    newline_style_value,
    trailing_newline,
  ) {
    Ok(options) => options
    Err(error) => return format_error_bytes(error)
  }
  match @api.format_with_ids(raw, dialect, profile, mode, options) {
    Ok(result) => {
      json_bytes(
        format_result_json(
          raw,
          result,
          dialect,
          profile,
          selection.exact_release(),
        ),
      )
    }
    Err(error) => parse_error_bytes(error)
  }
}

#export_name("fathom_complete_v1")
pub fn fathom_complete_v1(
  raw : Bytes,
  dialect : String,
  profile : String,
  cursor_byte : Int,
) -> Bytes {
  // A4 export order: raw first, dialect second, profile third, cursor fourth
  // (mirror fathom_parse_v1/fathom_format_v1, TOOL-05 D-04). Dialect/profile
  // errors map to the fathom.error.v1 envelope (UnknownDialect ->
  // FATHOM-SCHEMA-007, UnknownProfile -> FATHOM-SCHEMA-003) before any
  // completion work — never a Doris fallback and never an empty-silent
  // success (Pitfall 6). The cursor is bounds-checked ONCE in the core
  // (@completion.complete InvalidCursor) — the export never duplicates the
  // check (single-source, T-13-04-03).
  match @completion.complete(raw, dialect, profile, cursor_byte) {
    Ok(result) => json_bytes(completion_result_json(result, dialect, profile))
    Err(error) => json_bytes(completion_error_json(error))
  }
}

#export_name("fathom_fingerprint_v1")
pub fn fathom_fingerprint_v1(
  raw : Bytes,
  dialect : String,
  profile : String,
  mode : String,
) -> Bytes {
  // Dialect/profile validated FIRST (Pitfall 6, T-09-10): unknown dialect /
  // unsupported profile map to the fathom.error.v1 envelope
  // (UnknownDialect -> FATHOM-SCHEMA-007, UnknownProfile -> FATHOM-SCHEMA-003)
  // before any fingerprint work. The ParseOptions supplies exact_release for
  // the result envelope (D-09).
  let selection = match @api.ParseOptions::new(dialect, profile, mode) {
    Ok(options) => options
    Err(error) => return parse_error_bytes(error)
  }
  match @api.fingerprint_text(raw, selection) {
    Ok(result) => {
      json_bytes(
        fingerprint_result_json(
          raw,
          result,
          dialect,
          profile,
          selection.exact_release(),
        ),
      )
    }
    Err(error) => parse_error_bytes(error)
  }
}

#export_name("fathom_lineage_v1")
pub fn fathom_lineage_v1(
  raw : Bytes,
  dialect : String,
  profile : String,
  mode : String,
  catalog_json : Bytes,
) -> Bytes {
  // Dialect/profile validated FIRST (Pitfall 6, T-09-10): unknown dialect /
  // unsupported profile map to the fathom.error.v1 envelope (UnknownDialect ->
  // FATHOM-SCHEMA-007, UnknownProfile -> FATHOM-SCHEMA-003) before any lineage
  // work. ParseOptions also supplies exact_release for the envelope (D-09).
  let selection = match @api.ParseOptions::new(dialect, profile, mode) {
    Ok(options) => options
    Err(error) => return parse_error_bytes(error)
  }
  // Flink gate (D-08, T-07-04-01): lineage is Doris-only this phase. A valid
  // flink selection returns a structured FATHOM-SCHEMA-003 error envelope with
  // the explicit "lineage is Doris-only" message — NEVER a silent empty result
  // and never a Doris-policy lineage of a flink request.
  if selection.dialect_id() == "flink" {
    return error_bytes("FATHOM-SCHEMA-003", "lineage is Doris-only")
  }
  // Catalog JSON (D-05, T-07-04-02): empty bytes / "{}" -> no catalog (every
  // star/external view reports an honest gap, SC2); any malformed or
  // shape-invalid catalog is a structured FATHOM-SCHEMA-004 error — never a
  // silent fallback to the no-catalog behavior (T-06-03-01, ASVS V5).
  let catalog = match parse_catalog_json(catalog_json) {
    Ok(catalog) => catalog
    Err(message) => return error_bytes("FATHOM-SCHEMA-004", message)
  }
  match @api.lineage_text(raw, selection, catalog) {
    Ok(result) => {
      json_bytes(
        lineage_result_json(raw, result, dialect, profile, selection.exact_release()),
      )
    }
    Err(error) => parse_error_bytes(error)
  }
}

/// Parse the wire `overrides` argument: a UTF-8 JSON array of
/// `{"code": "...", "setting": "off|error|warning|info"}` objects. An empty
/// array / empty bytes is the default registry. Malformed JSON, non-array
/// input, missing fields, or an unknown severity is a structured error — never
/// a silent fallback to the default registry (T-06-03-01, ASVS V5).
fn parse_overrides(overrides : Bytes) -> Result[Array[@api.RuleOverride], String] {
  if overrides.length() == 0 {
    return Ok([])
  }
  let text = try {
    @utf8.decode(overrides)
  } catch {
    _ => return Err("invalid UTF-8 in lint overrides")
  }
  let value = try {
    @json.parse(text)
  } catch {
    _ => return Err("malformed JSON in lint overrides")
  }
  match value {
    Json::Array(items) => {
      let out : Array[@api.RuleOverride] = []
      for item in items {
        let obj = match item {
          Json::Object(obj) => obj
          _ => return Err("lint override must be an object")
        }
        let code = match obj.get("code") {
          Some(Json::String(s)) => s
          _ => return Err("lint override missing string code")
        }
        let setting = match obj.get("setting") {
          Some(Json::String(s)) => s
          _ => return Err("lint override missing string setting")
        }
        let parsed_setting = if setting == "off" {
          @api.RuleSetting::Disabled
        } else {
          match @api.LintSeverity::from_id(setting) {
            Some(severity) => @api.RuleSetting::Severity(severity)
            None => return Err("invalid lint severity: \{setting}")
          }
        }
        out.push({ code: code, setting: parsed_setting })
      }
      Ok(out)
    }
    _ => Err("lint overrides must be a JSON array")
  }
}

#export_name("fathom_lint_v1")
pub fn fathom_lint_v1(
  raw : Bytes,
  dialect : String,
  profile : String,
  mode : String,
  overrides : Bytes,
  fix : Bool,
) -> Bytes {
  // Dialect/profile validated FIRST (Pitfall 6, T-09-10): unknown dialect /
  // unsupported profile map to the fathom.error.v1 envelope before any lint
  // work. ParseOptions also supplies exact_release for the envelope (D-09).
  let selection = match @api.ParseOptions::new(dialect, profile, mode) {
    Ok(options) => options
    Err(error) => return parse_error_bytes(error)
  }
  let rule_overrides = match parse_overrides(overrides) {
    Ok(value) => value
    Err(message) => return error_bytes("FATHOM-SCHEMA-004", message)
  }
  let lint_options = match @api.LintOptions::new(rule_overrides) {
    Ok(options) => options
    Err(_) => return error_bytes("FATHOM-SCHEMA-004", "unknown rule code in lint overrides")
  }
  let result = if fix {
    @api.fix_text(raw, selection, lint_options)
  } else {
    @api.lint_text(raw, selection, lint_options)
  }
  match result {
    Ok(result) => {
      json_bytes(
        lint_result_json(raw, result, dialect, profile, selection.exact_release()),
      )
    }
    Err(error) => parse_error_bytes(error)
  }
}

#export_name("fathom_dialect_v1")
pub fn fathom_dialect_v1(dialect : String) -> Bytes {
  json_bytes(dialect_json(dialect))
}

#export_name("fathom_capabilities_v1")
pub fn fathom_capabilities_v1() -> Bytes {
  json_bytes(capabilities_json())
}
