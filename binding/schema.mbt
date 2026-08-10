/// Public wire-schema contract for parser and formatter results.

pub const PARSE_SCHEMA_VERSION : String = "fathom.parse.v1"
pub const FORMAT_SCHEMA_VERSION : String = "fathom.format.v1"
pub const COMPLETE_SCHEMA_VERSION : String = "fathom.complete.v1"
pub const SOURCE_TRANSPORT : String = "inline-root-v1"

pub enum SchemaError {
  UnsupportedSchemaVersion(version~ : String)
  UnsupportedSourceTransport(transport~ : String)
  UnknownDialect(dialect~ : String)
  UnsupportedProfile(profile~ : String)
  UnsupportedMode(mode~ : String)
} derive(Eq, @debug.Debug)

/// Accepts exactly the five fathom.*.v1 result/error envelope namespaces
/// (D-09, D-04): parse, format, complete, error, capabilities.
/// fathom.dialect.v1 is a metadata-query schema served by fathom_dialect_v1,
/// not a result envelope. fathom.complete.v1 is the D-04 completion envelope.
pub fn validate_schema_version(version : String) -> Result[Unit, SchemaError] {
  match version {
    PARSE_SCHEMA_VERSION |
    FORMAT_SCHEMA_VERSION |
    COMPLETE_SCHEMA_VERSION |
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
/// validated per dialect. flink accepts exactly the three pinned release
/// profiles (Phase 10, D-01) — no Doris fallback, no silent default; unknown
/// flink profiles reject with UnsupportedProfile (FATHOM-SCHEMA-003), and
/// unknown dialects return UnknownDialect (FATHOM-SCHEMA-007) (D-05 — no
/// FATHOM-FLINK-* namespace, dialect rides in metadata fields).
pub fn validate_dialect_profile(dialect : String, profile : String) -> Result[Unit, SchemaError] {
  match dialect {
    "doris" => match profile {
      "2.1" | "3.x" | "4.x" => Ok(())
      _ => Err(UnsupportedProfile(profile~))
    }
    "flink" => match profile {
      "flink-2.3.0" | "flink-2.1.3" | "flink-1.20.5" => Ok(())
      _ => Err(UnsupportedProfile(profile~))
    }
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

/// Serialized completion result envelope (TOOL-05 D-04): the
/// fathom.complete.v1 envelope carries the same dialect/profile selection
/// metadata as the parse/format envelopes (D-09) plus the bounded completion
/// items. Item text is dialect-neutral (D-10/D-28): the detail is always
/// "SQL syntax keyword" and no dialect name appears in item content — the
/// dialect rides in the envelope metadata, never in items.
pub fn completion_result_json(
  result : @completion.CompletionList,
  dialect : String,
  profile : String,
) -> String {
  let items : Array[Json] = []
  for item in result.items {
    items.push(Json::object({
      "label": Json::string(item.label),
      "detail": Json::string(item.detail),
      "start_byte": Json::number(item.start_byte.to_double()),
      "end_byte": Json::number(item.end_byte.to_double()),
      "new_text": Json::string(item.new_text),
    }))
  }
  stringify({
    "schema_version": Json::string(COMPLETE_SCHEMA_VERSION),
    "source_transport": Json::string(SOURCE_TRANSPORT),
    "dialect": Json::string(dialect),
    "profile": Json::string(profile),
    "is_incomplete": Json::boolean(result.is_incomplete),
    "items": Json::array(items),
  })
}

/// Serialized completion error envelope (TOOL-05 D-04): dialect/profile
/// errors reuse the parse/format FATHOM-SCHEMA codes (UnknownDialect ->
/// FATHOM-SCHEMA-007, UnknownProfile -> FATHOM-SCHEMA-003); completion-local
/// errors (invalid cursor / invalid source / over-limit input) use the
/// FATHOM-COMPLETE code family. Always the fathom.error.v1 envelope — never a
/// panic and never an unreadable result (T-13-04-08).
pub fn completion_error_json(error : @completion.CompletionError) -> String {
  let code = match error {
    @completion.CompletionError::UnknownDialect(_) => "FATHOM-SCHEMA-007"
    @completion.CompletionError::UnknownProfile(_) => "FATHOM-SCHEMA-003"
    @completion.CompletionError::InvalidCursor(..) => "FATHOM-COMPLETE-001"
    @completion.CompletionError::InvalidSource => "FATHOM-COMPLETE-002"
    @completion.CompletionError::InputTooLarge => "FATHOM-COMPLETE-003"
  }
  let message = match error {
    @completion.CompletionError::UnknownDialect(dialect_id~) => "unknown dialect: \{dialect_id}"
    @completion.CompletionError::UnknownProfile(profile_id~) => "unsupported profile: \{profile_id}"
    @completion.CompletionError::InvalidCursor(cursor~, source_length~) => "invalid cursor \{cursor}: source length is \{source_length}"
    @completion.CompletionError::InvalidSource => "invalid source: input could not be parsed as SQL"
    @completion.CompletionError::InputTooLarge => "input too large: exceeds the 8 MiB source limit"
  }
  error_json(code, message)
}

/// Per-dialect profile availability under fathom.dialect.v1 (OQ4): the
/// dialect's released profiles with exact_release/feature_introduction taken
/// ONLY from dialect profile metadata (T-09-18 provenance discipline — nothing
/// fabricated). flink reports its three pinned release profiles
/// (flink-2.3.0/2.1.3/1.20.5) with calcite_version/parser_config read only
/// from FlinkProfileMetadata (D-02); an unknown dialect is a structured
/// UnknownDialect error (FATHOM-SCHEMA-007).
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
      let profiles = ["flink-2.3.0", "flink-2.1.3", "flink-1.20.5"]
      let entries : Array[Json] = []
      for profile in profiles {
        let selection = match @api.ParseOptions::new("flink", profile, "strict") {
          Ok(selection) => selection
          Err(error) => return parse_error_json(error)
        }
        let metadata = selection.flink_profile_metadata()
        entries.push(Json::object({
          "id": Json::string(profile),
          "exact_release": Json::string(metadata.exact_release),
          "calcite_version": Json::string(metadata.calcite_version),
          "parser_config": Json::string(metadata.parser_config),
          "feature_introduction": Json::string(metadata.feature_introduction),
        }))
      }
      stringify({
        "schema_version": Json::string("fathom.dialect.v1"),
        "dialect": Json::string("flink"),
        "source_transport": Json::string(SOURCE_TRANSPORT),
        "profiles": Json::array(entries),
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
        "profiles": Json::array([
          Json::string("flink-2.3.0"),
          Json::string("flink-2.1.3"),
          Json::string("flink-1.20.5"),
        ]),
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
