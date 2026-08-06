/// Stable primitive exports for JavaScript ESM and linear Wasm hosts.
///
/// Every result is UTF-8 encoded JSON bytes. The only input bytes are the raw
/// SQL source; no MoonBit ADT, object handle, or host memory address crosses
/// this boundary. `fathom_parse_v1` and `fathom_format_v1` are the ABI surface
/// (dialect right after raw, consistent with ParseOptions::new and the CLI,
/// A4); the metadata exports let hosts negotiate profiles and capabilities
/// without parsing an SQL document first. `fathom_dialect_v1` replaces
/// `doris_profile_v1` in 09-05.

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
  let keyword_case_value = match @api.KeywordCase::from_id(keyword_case) {
    Some(value) => value
    None => return error_bytes("DORIS-FORMAT-002", "unsupported keyword case: \{keyword_case}")
  }
  let comma_style_value = match @api.CommaStyle::from_id(comma_style) {
    Some(value) => value
    None => return error_bytes("DORIS-FORMAT-003", "unsupported comma style: \{comma_style}")
  }
  let newline_style_value = match @api.NewlineStyle::from_id(newline_style) {
    Some(value) => value
    None => return error_bytes("DORIS-FORMAT-004", "unsupported newline style: \{newline_style}")
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
    Ok(result) => json_bytes(format_result_json(raw, result, profile))
    Err(error) => parse_error_bytes(error)
  }
}

#export_name("doris_profile_v1")
pub fn doris_profile_v1(profile : String) -> Bytes {
  json_bytes(profile_json(profile))
}

#export_name("doris_capabilities_v1")
pub fn doris_capabilities_v1() -> Bytes {
  json_bytes(capabilities_json())
}
