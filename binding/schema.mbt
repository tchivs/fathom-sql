/// Public wire-schema contract for parser and formatter results.

pub const PARSE_SCHEMA_VERSION : String = "doris.parse.v1"
pub const FORMAT_SCHEMA_VERSION : String = "doris.format.v1"
pub const SOURCE_TRANSPORT : String = "inline-root-v1"

pub enum SchemaError {
  UnsupportedSchemaVersion(version~ : String)
  UnsupportedSourceTransport(transport~ : String)
  UnsupportedProfile(profile~ : String)
  UnsupportedMode(mode~ : String)
} derive(Eq, @debug.Debug)

pub fn validate_schema_version(version : String) -> Result[Unit, SchemaError] {
  match version {
    PARSE_SCHEMA_VERSION | FORMAT_SCHEMA_VERSION => Ok(())
    _ => Err(UnsupportedSchemaVersion(version~))
  }
}

pub fn validate_source_transport(transport : String) -> Result[Unit, SchemaError] {
  if transport == SOURCE_TRANSPORT {
    Ok(())
  } else {
    Err(UnsupportedSourceTransport(transport~))
  }
}

pub fn validate_profile(profile : String) -> Result[Unit, SchemaError] {
  match profile {
    "2.1" | "3.x" | "4.x" => Ok(())
    _ => Err(UnsupportedProfile(profile~))
  }
}

pub fn validate_mode(mode : String) -> Result[Unit, SchemaError] {
  match mode {
    "strict" | "editor" => Ok(())
    _ => Err(UnsupportedMode(mode~))
  }
}

pub fn schema_error_code(error : SchemaError) -> String {
  match error {
    UnsupportedSchemaVersion(_) => "DORIS-SCHEMA-001"
    UnsupportedSourceTransport(_) => "DORIS-SCHEMA-002"
    UnsupportedProfile(_) => "DORIS-SCHEMA-003"
    UnsupportedMode(_) => "DORIS-SCHEMA-004"
  }
}

pub fn schema_error_message(error : SchemaError) -> String {
  match error {
    UnsupportedSchemaVersion(version~) => "unsupported schema version: \{version}"
    UnsupportedSourceTransport(transport~) => "unsupported source transport: \{transport}"
    UnsupportedProfile(profile~) => "unsupported Doris profile: \{profile}"
    UnsupportedMode(mode~) => "unsupported parse mode: \{mode}"
  }
}

pub fn schema_error_json(error : SchemaError) -> String {
  stringify({
    "schema_version": Json::string("doris.error.v1"),
    "code": Json::string(schema_error_code(error)),
    "message": Json::string(schema_error_message(error)),
  })
}

pub fn parse_result_json(result : @api.ParseResult) -> String {
  stringify({
    "schema_version": Json::string(PARSE_SCHEMA_VERSION),
    "source_transport": Json::string(result.source_transport),
    "profile": Json::string(result.profile),
    "exact_release": Json::string(result.exact_release),
    "feature_introduction": Json::string(result.feature_introduction),
    "mode": Json::string(result.mode),
    "valid": Json::boolean(result.valid),
    "recovered": Json::boolean(result.recovered),
    "source_bytes": byte_array_json(result.source_bytes),
    "source_byte_length": Json::number(result.source_byte_length.to_double()),
    "root": node_json(result.root),
    "diagnostics": diagnostics_json(result.diagnostics),
  })
}

pub fn format_result_json(source : Bytes, result : @api.FormatResult, profile : String) -> String {
  stringify({
    "schema_version": Json::string(FORMAT_SCHEMA_VERSION),
    "source_transport": Json::string(SOURCE_TRANSPORT),
    "profile": Json::string(profile),
    "source_bytes": byte_array_json(source),
    "source_byte_length": Json::number(source.length().to_double()),
    "accepted": Json::boolean(result.accepted),
    "formatted": byte_array_json(result.output),
    "diagnostics": format_diagnostics_json(result.diagnostics),
    "statement_offsets": offsets_json(result.statement_offsets),
  })
}
