/// Stable primitive exports for JavaScript ESM and linear Wasm hosts.
///
/// Every result is UTF-8 encoded JSON bytes. The only input bytes are the raw
/// SQL source; no MoonBit ADT, object handle, or host memory address crosses
/// this boundary. `doris_parse_v1` and `doris_format_v1` are the ABI surface;
/// the metadata exports let hosts negotiate profiles and capabilities without
/// parsing an SQL document first.

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

#export_name("doris_parse_v1")
pub fn doris_parse_v1(raw : Bytes, profile : String, mode : String) -> Bytes {
  match @api.parse_with_ids(raw, profile, mode) {
    Ok(result) => json_bytes(parse_result_json(result))
    Err(error) => parse_error_bytes(error)
  }
}

#export_name("doris_format_v1")
pub fn doris_format_v1(
  raw : Bytes,
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
  match @api.format_with_ids(raw, profile, mode, options) {
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
