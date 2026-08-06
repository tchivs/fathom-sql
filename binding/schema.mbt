/// Public wire-schema contract for parser and formatter results.

pub const PARSE_SCHEMA_VERSION : String = "fathom.parse.v1"
pub const FORMAT_SCHEMA_VERSION : String = "fathom.format.v1"
pub const SOURCE_TRANSPORT : String = "inline-root-v1"

pub enum SchemaError {
  UnsupportedSchemaVersion(version~ : String)
  UnsupportedSourceTransport(transport~ : String)
  UnknownDialect(dialect~ : String)
  UnsupportedProfile(profile~ : String)
  UnsupportedMode(mode~ : String)
} derive(Eq, @debug.Debug)

/// Accepts exactly the four fathom.*.v1 result/error envelope namespaces
/// (D-09): parse, format, error, capabilities. fathom.dialect.v1 is a
/// metadata-query schema served by fathom_dialect_v1, not a result envelope.
pub fn validate_schema_version(version : String) -> Result[Unit, SchemaError] {
  match version {
    PARSE_SCHEMA_VERSION |
    FORMAT_SCHEMA_VERSION |
    "fathom.error.v1" |
    "fathom.capabilities.v1" => Ok(())
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

/// Explicit dialect+profile selection validation (Pitfall 6, D-11): the
/// dialect is validated FIRST (unknown -> UnknownDialect), then the profile is
/// validated per dialect. flink is a legal dialect whose profiles are ALL
/// rejected until Phase 10 (A1/OQ1) — no Doris fallback, no silent default.
pub fn validate_dialect_profile(dialect : String, profile : String) -> Result[Unit, SchemaError] {
  match dialect {
    "doris" => match profile {
      "2.1" | "3.x" | "4.x" => Ok(())
      _ => Err(UnsupportedProfile(profile~))
    }
    "flink" => Err(UnsupportedProfile(profile~))
    _ => Err(UnknownDialect(dialect~))
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
    UnsupportedSchemaVersion(_) => "FATHOM-SCHEMA-001"
    UnsupportedSourceTransport(_) => "FATHOM-SCHEMA-002"
    UnsupportedProfile(_) => "FATHOM-SCHEMA-003"
    UnsupportedMode(_) => "FATHOM-SCHEMA-004"
    UnknownDialect(_) => "FATHOM-SCHEMA-007"
  }
}

pub fn schema_error_message(error : SchemaError) -> String {
  match error {
    UnsupportedSchemaVersion(version~) => "unsupported schema version: \{version}"
    UnsupportedSourceTransport(transport~) => "unsupported source transport: \{transport}"
    UnknownDialect(dialect~) => "unknown dialect: \{dialect}"
    UnsupportedProfile(profile~) => "unsupported profile: \{profile}"
    UnsupportedMode(mode~) => "unsupported parse mode: \{mode}"
  }
}

pub fn schema_error_json(error : SchemaError) -> String {
  stringify({
    "schema_version": Json::string("fathom.error.v1"),
    "code": Json::string(schema_error_code(error)),
    "message": Json::string(schema_error_message(error)),
  })
}

pub fn parse_result_json(result : @api.ParseResult) -> String {
  stringify({
    "schema_version": Json::string(PARSE_SCHEMA_VERSION),
    "source_transport": Json::string(result.source_transport),
    "dialect": Json::string(result.dialect),
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

/// Serialized format result envelope (DIALECT-04): carries the same
/// dialect/profile/exact_release metadata as the parse envelope so consumers
/// never guess which selection produced the formatted bytes (D-09).
pub fn format_result_json(
  source : Bytes,
  result : @api.FormatResult,
  dialect : String,
  profile : String,
  exact_release : String,
) -> String {
  stringify({
    "schema_version": Json::string(FORMAT_SCHEMA_VERSION),
    "source_transport": Json::string(SOURCE_TRANSPORT),
    "dialect": Json::string(dialect),
    "profile": Json::string(profile),
    "exact_release": Json::string(exact_release),
    "source_bytes": byte_array_json(source),
    "source_byte_length": Json::number(source.length().to_double()),
    "accepted": Json::boolean(result.accepted),
    "formatted": byte_array_json(result.output),
    "diagnostics": format_diagnostics_json(result.diagnostics),
    "statement_offsets": offsets_json(result.statement_offsets),
  })
}
pub fn error_json(code : String, message : String) -> String {
  stringify({
    "schema_version": Json::string("fathom.error.v1"),
    "code": Json::string(code),
    "message": Json::string(message),
  })
}

pub fn parse_error_json(error : @api.ParseError) -> String {
  let code = match error {
    @api.ParseError::UnknownDialect(_) => "FATHOM-SCHEMA-007"
    @api.ParseError::UnknownProfile(_) => "FATHOM-SCHEMA-003"
    @api.ParseError::UnknownMode(_) => "FATHOM-SCHEMA-004"
    @api.ParseError::ProfileMetadataMismatch(..) => "FATHOM-SCHEMA-005"
    @api.ParseError::UnsupportedFeatureIntroduction(_) => "FATHOM-SCHEMA-006"
    @api.ParseError::ConflictingSelection(..) => "FATHOM-SCHEMA-007"
    @api.ParseError::InputTooLarge(..) => "FATHOM-PARSE-001"
    @api.ParseError::InvalidLimit(..) => "FATHOM-PARSE-002"
    @api.ParseError::InvalidSyntaxTree => "FATHOM-PARSE-003"
  }
  let message = match error {
    @api.ParseError::UnknownDialect(dialect_id~) => "unknown dialect: \{dialect_id}"
    @api.ParseError::UnknownProfile(profile_id~) => "unsupported profile: \{profile_id}"
    @api.ParseError::UnknownMode(mode_id~) => "unsupported parse mode: \{mode_id}"
    @api.ParseError::ProfileMetadataMismatch(profile_id~, expected_release~, actual_release~, expected_feature_introduction~, actual_feature_introduction~) => {
      "profile metadata mismatch for \{profile_id}: expected release \{expected_release}/\{expected_feature_introduction}, got \{actual_release}/\{actual_feature_introduction}"
    }
    @api.ParseError::UnsupportedFeatureIntroduction(feature_introduction~) => "unsupported feature introduction: \{feature_introduction}"
    @api.ParseError::ConflictingSelection(selection_a~, selection_b~) => "conflicting dialect/profile selections: \{selection_a} vs \{selection_b}"
    @api.ParseError::InputTooLarge(requested_bytes~, max_bytes~) => "input too large: \{requested_bytes} bytes (limit \{max_bytes})"
    @api.ParseError::InvalidLimit(limit_name~, value~) => "invalid parser limit \{limit_name}: \{value}"
    @api.ParseError::InvalidSyntaxTree => "parser produced an invalid syntax tree"
  }
  error_json(code, message)
}

pub fn format_error_json(error : @api.FormatError) -> String {
  let message = match error {
    @api.FormatError::UnknownKeywordCase(keyword_case_id~) => "unsupported keyword case: " + keyword_case_id
    @api.FormatError::UnknownCommaStyle(comma_style_id~) => "unsupported comma style: " + comma_style_id
    @api.FormatError::UnknownNewlineStyle(newline_style_id~) => "unsupported newline style: " + newline_style_id
    @api.FormatError::InvalidIndent(value~) => "invalid indent: " + value.to_string()
    @api.FormatError::InvalidLineWidth(value~) => "invalid line width: " + value.to_string()
    @api.FormatError::InvalidSyntaxTree => "formatter received an invalid syntax tree"
  }
  let code = match error {
    @api.FormatError::UnknownKeywordCase(_) => "FATHOM-FORMAT-002"
    @api.FormatError::UnknownCommaStyle(_) => "FATHOM-FORMAT-003"
    @api.FormatError::UnknownNewlineStyle(_) => "FATHOM-FORMAT-004"
    @api.FormatError::InvalidIndent(_) => "FATHOM-FORMAT-005"
    @api.FormatError::InvalidLineWidth(_) => "FATHOM-FORMAT-006"
    @api.FormatError::InvalidSyntaxTree => "FATHOM-FORMAT-007"
  }
  error_json(code, message)
}

/// Per-dialect profile availability under fathom.dialect.v1 (OQ4): the
/// dialect's released profiles with exact_release/feature_introduction taken
/// ONLY from DorisProfile metadata (T-09-18 provenance discipline — nothing
/// fabricated). flink is a legal dialect whose profile set is empty until
/// Phase 10 (A1); an unknown dialect is a structured UnknownDialect error
/// (FATHOM-SCHEMA-007).
pub fn dialect_json(dialect : String) -> String {
  match dialect {
    "doris" => {
      let profiles = ["2.1", "3.x", "4.x"]
      let entries : Array[Json] = []
      for profile in profiles {
        let selection = match @api.ParseOptions::new("doris", profile, "strict") {
          Ok(selection) => selection
          Err(error) => return parse_error_json(error)
        }
        let metadata = selection.profile_metadata()
        entries.push(Json::object({
          "id": Json::string(profile),
          "exact_release": Json::string(metadata.exact_release),
          "feature_introduction": Json::string(metadata.feature_introduction),
        }))
      }
      stringify({
        "schema_version": Json::string("fathom.dialect.v1"),
        "dialect": Json::string("doris"),
        "source_transport": Json::string(SOURCE_TRANSPORT),
        "profiles": Json::array(entries),
        "modes": Json::array([Json::string("strict"), Json::string("editor")]),
      })
    }
    "flink" => {
      stringify({
        "schema_version": Json::string("fathom.dialect.v1"),
        "dialect": Json::string("flink"),
        "source_transport": Json::string(SOURCE_TRANSPORT),
        "profiles": Json::array([]),
        "modes": Json::array([Json::string("strict"), Json::string("editor")]),
      })
    }
    _ => schema_error_json(UnknownDialect(dialect= dialect))
  }
}

/// Global negotiation metadata under fathom.capabilities.v1 (OQ4): the
/// dialect list with per-dialect profile availability, the supported schema
/// namespaces, source transport, modes, and targets.
pub fn capabilities_json() -> String {
  stringify({
    "schema_version": Json::string("fathom.capabilities.v1"),
    "parse_schema": Json::string(PARSE_SCHEMA_VERSION),
    "format_schema": Json::string(FORMAT_SCHEMA_VERSION),
    "source_transport": Json::string(SOURCE_TRANSPORT),
    "dialects": Json::array([
      Json::object({
        "dialect": Json::string("doris"),
        "profiles": Json::array([
          Json::string("2.1"),
          Json::string("3.x"),
          Json::string("4.x"),
        ]),
      }),
      Json::object({
        "dialect": Json::string("flink"),
        "profiles": Json::array([]),
      }),
    ]),
    "modes": Json::array([Json::string("strict"), Json::string("editor")]),
    "targets": Json::array([
      Json::string("native"),
      Json::string("js-esm"),
      Json::string("wasm-linear"),
    ]),
    "wasm_gc": Json::boolean(false),
  })
}
