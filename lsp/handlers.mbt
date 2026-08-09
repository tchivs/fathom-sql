/// LSP lifecycle and editor handlers. All parsing/formatting is delegated to the
/// shared api facade; this module only maps primitive results to LSP values.
///
/// Dialect selection (D-01/D-02/D-03): every document carries its own resolved
/// dialect/profile context (Document.dialect/profile), resolved through the
/// three-level precedence — document-level explicit config (didOpen/didChange
/// extension fields) > workspace/session explicit default (serve_stdio args /
/// initializationOptions) > user-configured languageId mapping. A missing,
/// unknown, or conflicting selection is a structured config error
/// (FATHOM-SCHEMA-007 over publishDiagnostics, -32602 over initialize) — never
/// an implicit languageId fallback.

/// One explicit dialect+profile selection (D-01). `dialect` is the closed-enum
/// id ("doris" | "flink"); `profile` is the released-profile id (2.1/3.x/4.x
/// for doris; flink-2.3.0/2.1.3/1.20.5 for flink, Phase 10 D-01 — the parse is
/// the explicit not-implemented route).
pub struct DialectSelection {
  pub dialect : String
  pub profile : String
} derive(Eq, @debug.Debug)

/// Structured selection-resolution failures (D-01/D-02): missing at every
/// level, unknown dialect, unknown profile, or same-priority-source conflict.
pub enum SelectionError {
  MissingSelection
  UnknownDialect(dialect_id~ : String)
  UnknownProfile(profile_id~ : String)
  ConflictingSelection(source_a~ : String, source_b~ : String)
} derive(Eq, @debug.Debug)

pub(all) struct ServerState {
  pub mut docs :  DocumentStore
  // Workspace/session explicit defaults (D-01 seam): set by serve_stdio from
  // the CLI's --dialect/--profile, or by initialize's initializationOptions.
  pub mut default_dialect : String?
  pub mut default_profile : String?
  // User-configured languageId -> selection table (D-02): participates ONLY
  // when a client supplies it via the fathom settings section
  // (workspace/didChangeConfiguration or workspace/configuration).
  pub mut language_mapping : Map[String, DialectSelection]?
  // Optional workspace/configuration pull correlation: the pending
  // server-to-client request id awaiting the settings response.
  pub mut pending_config_request : RpcId?
  // Monotonically increasing id source for server-initiated requests
  // (IN-04a): every server->client request gets a session-unique id so a
  // future second server request cannot collide with the configuration pull.
  pub mut next_server_request_id : Int
  pub mut initialized : Bool
  pub mut shutdown : Bool
  pub mut exited : Bool
}

pub fn ServerState::new() -> ServerState {
  {
    docs:  DocumentStore::new(),
    default_dialect: None,
    default_profile: None,
    language_mapping: None,
    pending_config_request: None,
    next_server_request_id: 1,
    initialized: false,
    shutdown: false,
    exited: false,
  }
}

fn severity_value(severity : String) -> Int {
  match severity {
    "error" => 1
    "warning" => 2
    "info" => 3
    _ => 4
  }
}

fn position_json(position : @binding.Position) -> Json {
  {
    "line": Json::number(position.line.to_double()),
    "character": Json::number(position.character.to_double()),
  }
}

fn range_json(range : @binding.Range) -> Json {
  { "start": position_json(range.start), "end": position_json(range.end) }
}

fn diagnostic_json(raw : Bytes, severity : String, code : String, message : String, start_byte : Int, end_byte : Int) -> Json {
  let range = match  diagnostic_range(raw, start_byte, end_byte) {
    Some(range) => range
    None => { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }
  }
  {
    "range": range_json(range),
    "severity": Json::number(severity_value(severity).to_double()),
    "code": Json::string(code),
    "source": Json::string("fathom"),
    "message": Json::string(message),
    "data": {
      "start_byte": Json::number(start_byte.to_double()),
      "end_byte": Json::number(end_byte.to_double()),
    },
  }
}

fn parse_diagnostics_json(raw : Bytes, result : @api.ParseResult) -> Json {
  let values : Array[Json] = []
  for diagnostic in result.diagnostics {
    values.push(diagnostic_json(raw, diagnostic.severity, diagnostic.code, diagnostic.message, diagnostic.start_byte, diagnostic.end_byte))
  }
  Json::array(values)
}

fn format_diagnostics_json(raw : Bytes, diagnostics : Array[@api.FormatDiagnostic]) -> Json {
  let values : Array[Json] = []
  for diagnostic in diagnostics {
    values.push(diagnostic_json(raw, diagnostic.severity, diagnostic.code, diagnostic.message, diagnostic.start_byte, diagnostic.end_byte))
  }
  Json::array(values)
}

fn publish_diagnostics(uri : String, version : Int, raw : Bytes, diagnostics : Json) -> Bytes {
   notification("textDocument/publishDiagnostics", {
    "uri": Json::string(uri),
    "version": Json::number(version.to_double()),
    "diagnostics": diagnostics,
  })
}

/// D-03 publication guard: publish diagnostics for `document` only when the
/// current stored document still matches on version AND selection. A stale
/// async result computed under an old version or an old dialect/profile
/// context is dropped — the publish path never overwrites newer diagnostics
/// or an old selection's diagnostics over the current context.
fn publish_diagnostics_current(state : ServerState, document :  Document, diagnostics : Json) -> Array[Bytes] {
  match state.docs.get(document.uri) {
    Some(current) if current.version == document.version && current.dialect == document.dialect && current.profile == document.profile => {
      [publish_diagnostics(document.uri, document.version, document.text, diagnostics)]
    }
    _ => []
  }
}

/// D-02 no-guess rule: an unresolvable document selection publishes exactly
/// one structured config diagnostic (FATHOM-SCHEMA-007) and the document is
/// NOT parsed — no silent empty diagnostics, no languageId guess.
fn config_diagnostic(uri : String, version : Int, message : String) -> Bytes {
  let diagnostic : Json = {
    "range": { "start": { "line": Json::number(0.0), "character": Json::number(0.0) }, "end": { "line": Json::number(0.0), "character": Json::number(0.0) } },
    "severity": Json::number(1.0),
    "code": Json::string("FATHOM-SCHEMA-007"),
    "source": Json::string("fathom"),
    "message": Json::string(message),
  }
   notification("textDocument/publishDiagnostics", {
    "uri": Json::string(uri),
    "version": Json::number(version.to_double()),
    "diagnostics": Json::array([diagnostic]),
  })
}

/// Parse under the document's own dialect/profile context. flink documents
/// route through @api.parse_flink, which since Phase 11 (D-06) runs the real
/// Flink grammar — FATHOM-PARSE-008 is retired — never a Doris parse
/// (DIALECT-03, T-09-23).
fn parse_document_context(document :  Document) -> Result[@api.ParseResult, @api.ParseError] {
  if document.dialect == "flink" {
    @api.parse_flink(document.text, document.profile, "editor")
  } else {
    @api.parse_with_ids(document.text, document.dialect, document.profile, "editor")
  }
}

fn parse_document(state : ServerState, document :  Document) -> Array[Bytes] {
  let diagnostics = match parse_document_context(document) {
    Ok(result) => parse_diagnostics_json(document.text, result)
    Err(_) => Json::array([{
      "range": { "start": { "line": Json::number(0.0), "character": Json::number(0.0) }, "end": { "line": Json::number(0.0), "character": Json::number(0.0) } },
      "severity": Json::number(1.0),
      "code": Json::string("FATHOM-LSP-001"),
      "source": Json::string("fathom"),
      "message": Json::string("document could not be parsed"),
    }])
  }
  publish_diagnostics_current(state, document, diagnostics)
}

fn document_from_params(params : Json, key : String) -> (String, Int, Bytes)? {
  let document = match  object_field(params, key) {
    Some(document) => document
    None => return None
  }
  let uri = match  string_field(document, "uri") {
    Some(uri) => uri
    None => return None
  }
  let version = match int_field(document, "version") {
    Some(version) if version >= 0 => version
    _ => return None
  }
  let text = match  string_field(document, "text") {
    Some(text) => text
    None => return None
  }
  Some((uri, version, @utf8.encode(text)))
}
fn uri_from_params(params : Json, key : String) -> String? {
  let document = match  object_field(params, key) {
    Some(document) => document
    None => return None
  }
   string_field(document, "uri")
}

fn changed_document(params : Json) -> (String, Int, Bytes)? {
  let document = match  object_field(params, "textDocument") {
    Some(document) => document
    None => return None
  }
  let uri = match  string_field(document, "uri") {
    Some(uri) => uri
    None => return None
  }
  let version = match int_field(document, "version") {
    Some(version) => if version >= 0 { version } else { return None }
    None => return None
  }
  let changes = match array_field(params, "contentChanges") {
    Some(changes) if changes.length() == 1 => changes
    _ => return None
  }
  if has_field(changes[0], "range") { return None }
  let text = match string_field(changes[0], "text") {
    Some(text) => text
    None => return None
  }
  Some((uri, version, @utf8.encode(text)))
}

/// Document-level explicit config from the didOpen/didChange textDocument
/// extension fields (D-01 level 1, A2 transport). Absent fields mean the
/// client did not assert a document-level selection.
fn selection_from_params(params : Json) -> DialectSelection? {
  let document = match  object_field(params, "textDocument") {
    Some(document) => document
    None => return None
  }
  let dialect = match  string_field(document, "dialect") {
    Some(dialect) => dialect
    None => return None
  }
  let profile = match  string_field(document, "profile") {
    Some(profile) => profile
    None => return None
  }
  Some({ dialect: dialect, profile: profile })
}

fn language_id_from_params(params : Json, key : String) -> String? {
  let document = match  object_field(params, key) {
    Some(document) => document
    None => return None
  }
   string_field(document, "languageId")
}

/// Closed-enum selection validation (T-09-19, D-01): unknown dialects are
/// rejected, and every profile must pass the shared binding gate
/// (`validate_dialect_profile`) — doris accepts exactly 2.1/3.x/4.x and flink
/// accepts exactly the three pinned release profiles (flink-2.3.0/2.1.3/
/// 1.20.5, Phase 10 D-01). An unknown flink profile (e.g. the Doris-shaped
/// `4.x`) is therefore rejected here at the selection boundary, matching the
/// CLI/wire; a valid flink selection's parse runs the real Flink grammar
/// (FATHOM-PARSE-008 retired, D-06).
fn validate_selection(selection : DialectSelection) -> Result[DialectSelection, SelectionError] {
  match @binding.validate_dialect_profile(selection.dialect, selection.profile) {
    Ok(_) => Ok(selection)
    Err(@binding.SchemaError::UnknownDialect(dialect~)) => Err(UnknownDialect(dialect_id= dialect))
    Err(@binding.SchemaError::UnsupportedProfile(profile~)) => Err(UnknownProfile(profile_id= profile))
    Err(_) => Err(UnknownProfile(profile_id= selection.profile))
  }
}

fn selection_error_message(error : SelectionError) -> String {
  match error {
    MissingSelection => "missing dialect selection: no document-level config, workspace default, or language mapping provides a dialect"
    UnknownDialect(dialect_id~) => "unknown dialect: \{dialect_id}"
    UnknownProfile(profile_id~) => "unsupported profile: \{profile_id}"
    ConflictingSelection(source_a~, source_b~) => "conflicting dialect/profile selections: \{source_a} vs \{source_b}"
  }
}

/// D-01 three-level precedence: document-level explicit config >
/// workspace/session explicit default > user-configured languageId mapping.
/// The returned source names which level produced the selection so a
/// workspace-default change re-resolves only documents that were not set at
/// document level (D-03).
fn resolve_selection_with_source(state : ServerState, params : Json, language_id : String?) -> Result[(DialectSelection, String), SelectionError] {
  // (1) document-level explicit config (didOpen/didChange extension fields)
  match selection_from_params(params) {
    Some(selection) => {
      let validated = match validate_selection(selection) {
        Ok(selection) => selection
        Err(error) => return Err(error)
      }
      return Ok((validated, "document"))
    }
    None => ()
  }
  // (2) workspace/session explicit default
  match (state.default_dialect, state.default_profile) {
    (Some(dialect), Some(profile)) => {
      let selection = { dialect: dialect, profile: profile }
      return Ok((selection, "workspace"))
    }
    _ => ()
  }
  // (3) user-configured languageId mapping (D-02: only when configured)
  match language_id {
    Some(language_id) => match state.language_mapping {
      Some(mapping) => match mapping.get(language_id) {
        Some(selection) => {
          let validated = match validate_selection(selection) {
            Ok(selection) => selection
            Err(error) => return Err(error)
          }
          return Ok((validated, "language"))
        }
        None => ()
      }
      None => ()
    }
    None => ()
  }
  Err(MissingSelection)
}

fn resolve_selection(state : ServerState, params : Json, language_id : String?) -> Result[DialectSelection, SelectionError] {
  match resolve_selection_with_source(state, params, language_id) {
    Ok((selection, _source)) => Ok(selection)
    Err(error) => Err(error)
  }
}

/// initialize selection intake (D-01): reads initializationOptions
/// { dialect, profile }, validates the closed-enum selection, and stores the
/// workspace/session explicit default. A same-source conflict with the
/// serve_stdio-provided default is a structured -32602 error. When
/// initializationOptions is absent entirely (a bare LSP client such as
/// neovim/lsp-mode connecting to `fathom-sql lsp --dialect doris --profile
/// 4.x`), the serve_stdio workspace defaults — already validated by the CLI —
/// are adopted (MA-01, 09-06 option-a: workspace default comes from
/// initializationOptions OR serve_stdio args). MissingSelection is returned
/// only when BOTH sources are empty.
fn initialize_selection(state : ServerState, params : Json?) -> Result[DialectSelection, String] {
  let options = match params {
    Some(params) =>  object_field(params, "initializationOptions")
    None => None
  }
  match options {
    None => {
      // Fall back to the serve_stdio workspace/session defaults (D-01 seam).
      match (state.default_dialect, state.default_profile) {
        (Some(dialect), Some(profile)) => {
          let selection = { dialect: dialect, profile: profile }
          let validated = match validate_selection(selection) {
            Ok(selection) => selection
            Err(error) => return Err(selection_error_message(error))
          }
          state.default_dialect = Some(validated.dialect)
          state.default_profile = Some(validated.profile)
          Ok(validated)
        }
        _ => Err("initialize requires initializationOptions.dialect and initializationOptions.profile")
      }
    }
    Some(options) => {
      let dialect = match  string_field(options, "dialect") {
        Some(dialect) => dialect
        None => return Err("initialize requires initializationOptions.dialect")
      }
      let profile = match  string_field(options, "profile") {
        Some(profile) => profile
        None => return Err("initialize requires initializationOptions.profile")
      }
      // Same-source conflict (D-01): serve_stdio workspace defaults and
      // initializationOptions are both workspace/session sources.
      match (state.default_dialect, state.default_profile) {
        (Some(default_dialect), Some(default_profile)) if default_dialect != dialect || default_profile != profile => {
          return Err("conflicting dialect/profile selections: \{default_dialect}/\{default_profile} vs \{dialect}/\{profile}")
        }
        _ => ()
      }
      let selection = { dialect: dialect, profile: profile }
      let validated = match validate_selection(selection) {
        Ok(selection) => selection
        Err(error) => return Err(selection_error_message(error))
      }
      state.default_dialect = Some(validated.dialect)
      state.default_profile = Some(validated.profile)
      Ok(validated)
    }
  }
}

fn initialize_result() -> Json {
  {
    "capabilities": {
      "textDocumentSync": Json::number(1.0),
      "documentFormattingProvider": Json::boolean(true),
      "completionProvider": { "triggerCharacters": Json::array([Json::string(" "), Json::string(".")]) },
      "positionEncoding": Json::string("utf-16"),
    },
    "serverInfo": { "name": Json::string("fathom-lsp"), "version": Json::string("0.1") },
  }
}

fn formatting_result(state : ServerState, uri : String, id :  RpcId) -> Array[Bytes] {
  let document = match state.docs.get(uri) {
    Some(document) => document
    None => return [ response(id, Json::array([]))]
  }
  // T-09-23 flink surface (MI-06): formatting a flink-selected document is a
  // structured not-implemented error, never a silent empty edit array — a
  // host must be able to distinguish "nothing to format" from "formatting is
  // not supported for this dialect". The message mirrors the pre-Phase-11
  // parse-path FATHOM-PARSE-008 diagnostic text; the LSP formatting surface
  // change for real Flink trees is scheduled with the toolchain wave (Phase
  // 13, TOOL-01..03), outside this wave's scope.
  if document.dialect == "flink" {
    return [ error_response(id, -32603, "flink grammar is not yet implemented")]
  }
  let result = match @api.format_with_ids(document.text, document.dialect, document.profile, "strict", @api.FormatOptions::default()) {
    Ok(result) => result
    Err(_) => return [ response(id, Json::array([]))]
  }
  let responses : Array[Bytes] = []
  if result.diagnostics.length() > 0 {
    responses.push(publish_diagnostics(document.uri, document.version, document.text, format_diagnostics_json(document.text, result.diagnostics)))
  }
  if !result.accepted {
    responses.push( response(id, Json::array([])))
    return responses
  }
  if result.output == document.text {
    responses.push( response(id, Json::array([])))
    return responses
  }
  let range = match  full_document_range(document.text) {
    Some(range) => range
    None => {
      responses.push( error_response(id, -32603, "unable to compute UTF-16 document range"))
      return responses
    }
  }
  let edit = {
    "range": range_json(range),
    "newText": Json::string(@utf8.decode_lossy(result.output)),
  }
  responses.push( response(id, Json::array([edit])))
  responses
}

fn completion_request(params : Json) -> (String, @binding.Position, Int?)? {
  let text_document = match object_field(params, "textDocument") {
    Some(value) => value
    None => return None
  }
  let uri = match string_field(text_document, "uri") {
    Some(uri) => uri
    None => return None
  }
  let position = match object_field(params, "position") {
    Some(value) => value
    None => return None
  }
  let line = match int_field(position, "line") {
    Some(value) if value >= 0 => value
    _ => return None
  }
  let character = match int_field(position, "character") {
    Some(value) if value >= 0 => value
    _ => return None
  }
  let version = if has_field(text_document, "version") {
    match int_field(text_document, "version") {
      Some(value) if value >= 0 => Some(value)
      _ => return None
    }
  } else {
    None
  }
  Some((uri, { line: line, character: character }, version))
}

fn completion_item_json(raw : Bytes, item : @completion.CompletionItem) -> Json? {
  let range = match diagnostic_range(raw, item.start_byte, item.end_byte) {
    Some(range) => range
    None => return None
  }
  Some({
    "label": Json::string(item.label),
    "kind": Json::number(14.0),
    "detail": Json::string(item.detail),
    "textEdit": {
      "range": range_json(range),
      "newText": Json::string(item.new_text),
    },
  })
}

fn completion_result(state : ServerState, params : Json, id : RpcId) -> Array[Bytes] {
  let (uri, position, requested_version) = match completion_request(params) {
    Some(value) => value
    None => return [error_response(id, -32602, "completion requires textDocument and UTF-16 position")]
  }
  let document = match state.docs.get(uri) {
    Some(document) => document
    None => return [error_response(id, -32602, "completion document is not open")]
  }
  match requested_version {
    Some(version) if version != document.version => return [error_response(id, -32602, "completion document version is stale")]
    _ => ()
  }
  let source = match source(document.text) {
    Some(source) => source
    None => return [error_response(id, -32602, "completion source is invalid")]
  }
  let cursor_byte = match @binding.position_to_byte(source, position) {
    Ok(offset) => offset
    Err(_) => return [error_response(id, -32602, "completion position is outside the current document")]
  }
  let result = match @completion.complete(document.text, document.dialect, document.profile, cursor_byte) {
    Ok(result) => result
    Err(_) => return [error_response(id, -32602, "completion request could not be evaluated")]
  }
  let values : Array[Json] = []
  for item in result.items {
    match completion_item_json(document.text, item) {
      Some(value) => values.push(value)
      None => return [error_response(id, -32603, "unable to map completion range")]
    }
  }
  [response(id, {
    "isIncomplete": Json::boolean(result.is_incomplete),
    "items": Json::array(values),
  })]
}

/// One languageId mapping entry: { <languageId>: { dialect, profile } }.
fn selection_from_value(value : Json) -> DialectSelection? {
  let dialect = match  string_field(value, "dialect") {
    Some(dialect) => dialect
    None => return None
  }
  let profile = match  string_field(value, "profile") {
    Some(profile) => profile
    None => return None
  }
  Some({ dialect: dialect, profile: profile })
}

/// Parse the user-configured languageId -> selection table (D-02): every
/// entry is validated; any invalid entry rejects the whole settings update
/// (all-or-nothing, T-09-19).
fn language_mapping_from_json(mapping : Json) -> Result[Map[String, DialectSelection], String] {
  let table : Map[String, DialectSelection] = Map([])
  match mapping {
    Object(entries) => {
      let keys = entries.keys()
      for language_id in keys {
        let value = match entries.get(language_id) {
          Some(value) => value
          None => continue
        }
        let selection = match selection_from_value(value) {
          Some(selection) => selection
          None => return Err("language mapping entry for \{language_id} requires dialect and profile")
        }
        let validated = match validate_selection(selection) {
          Ok(selection) => selection
          Err(error) => return Err(selection_error_message(error))
        }
        table[language_id] = validated
      }
      Ok(table)
    }
    _ => Err("fathom settings languageMapping must be an object")
  }
}

/// Apply a fathom settings section { dialect?, profile?, languageMapping? }
/// (workspace/didChangeConfiguration or the workspace/configuration pull):
/// validate every selection up front, then store the workspace/session
/// default and the languageId mapping. On error nothing is applied and the
/// message is returned for a structured surface (showMessage / -32602).
fn apply_settings(state : ServerState, section : Json) -> Result[Unit, String] {
  let new_default = match (string_field(section, "dialect"), string_field(section, "profile")) {
    (None, None) => None
    (Some(dialect), Some(profile)) => {
      let selection = match validate_selection({ dialect: dialect, profile: profile }) {
        Ok(selection) => selection
        Err(error) => return Err(selection_error_message(error))
      }
      Some(selection)
    }
    _ => return Err("fathom settings require both dialect and profile or neither")
  }
  let new_mapping = match object_field(section, "languageMapping") {
    Some(mapping) => match language_mapping_from_json(mapping) {
      Ok(table) => Some(table)
      Err(message) => return Err(message)
    }
    None => state.language_mapping
  }
  match new_default {
    Some(selection) => {
      state.default_dialect = Some(selection.dialect)
      state.default_profile = Some(selection.profile)
    }
    None => ()
  }
  state.language_mapping = new_mapping
  Ok(())
}

/// D-03 re-resolution of one document under the CURRENT workspace default /
/// language mapping. Document-level explicit config persists unchanged; a
/// document that no longer resolves to any selection yields MissingSelection.
fn re_resolve_document(state : ServerState, document :  Document) -> Result[(DialectSelection, String), SelectionError] {
  // (2) workspace/session explicit default (possibly changed)
  match (state.default_dialect, state.default_profile) {
    (Some(dialect), Some(profile)) => {
      let selection = { dialect: dialect, profile: profile }
      return Ok((selection, "workspace"))
    }
    _ => ()
  }
  // (3) user-configured languageId mapping (possibly changed)
  match document.language_id {
    Some(language_id) => match state.language_mapping {
      Some(mapping) => match mapping.get(language_id) {
        Some(selection) => {
          let validated = match validate_selection(selection) {
            Ok(selection) => selection
            Err(error) => return Err(error)
          }
          return Ok((validated, "language"))
        }
        None => ()
      }
      None => ()
    }
    None => ()
  }
  Err(MissingSelection)
}

/// D-03 re-resolution on a settings change: every open document whose
/// selection did NOT come from document-level explicit config is re-resolved
/// under the new workspace default / language mapping, its stored context
/// updated, and the CURRENT stored revision re-parsed and published through
/// the version guard (dialect-switch reparse — stale results are dropped, and
/// a document that became unresolvable gets the FATHOM-SCHEMA-007 config
/// diagnostic at its current version, D-02).
fn re_resolve_open_documents(state : ServerState) -> Array[Bytes] {
  let responses : Array[Bytes] = []
  for document in state.docs.documents() {
    if document.selection_source == "document" { continue }
    match re_resolve_document(state, document) {
      Ok((selection, source)) => {
        ignore(state.docs.update_selection(document.uri, selection.dialect, selection.profile, source))
        match state.docs.get(document.uri) {
          Some(current) => {
            for response in parse_document(state, current) { responses.push(response) }
          }
          None => ()
        }
      }
      Err(error) => {
        responses.push(config_diagnostic(document.uri, document.version, selection_error_message(error)))
      }
    }
  }
  responses
}

/// The optional workspace/configuration pull (A2, option-c arm): the server
/// may request the fathom settings section once after "initialized"; the
/// correlated response applies like didChangeConfiguration. The id is the
/// session-unique server request id minted by the caller (IN-04a) so the
/// request JSON and the pending correlation can never diverge.
fn config_request(id : Int) -> Bytes {
  let value : Json = {
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double()),
    "method": Json::string("workspace/configuration"),
    "params": { "items": Json::array([{ "section": Json::string("fathom") }]) },
  }
  @utf8.encode(value.stringify())
}

fn show_message(message_type : Int, message : String) -> Bytes {
   notification("window/showMessage", {
    "type": Json::number(message_type.to_double()),
    "message": Json::string(message),
  })
}

pub fn handle_message(state : ServerState, message :  RpcMessage) -> Array[Bytes] {
  match message.method {
    "initialize" => {
      let id = match message.id {
        Some(id) => id
        None => return []
      }
      if state.initialized { return [ error_response(id, -32600, "server is already initialized")] }
      match initialize_selection(state, message.params) {
        Ok(_) => {
          state.initialized = true
          [ response(id, initialize_result())]
        }
        Err(message) => [ error_response(id, -32602, message)]
      }
    }
    "initialized" => {
      // Optional workspace/configuration pull (A2): the server may request
      // the fathom settings section once; the correlated response updates
      // the workspace default + language mapping like didChangeConfiguration.
      if state.pending_config_request.is_none() {
        let id = state.next_server_request_id
        state.next_server_request_id = id + 1
        state.pending_config_request = Some(RpcId::IntId(value=id))
        [config_request(id)]
      } else {
        []
      }
    }
    "shutdown" => {
      let id = match message.id {
        Some(id) => id
        None => return []
      }
      if !state.initialized { return [ error_response(id, -32600, "server is not initialized")] }
      state.shutdown = true
      [ response(id, null)]
    }
    "exit" => {
      state.exited = true
      []
    }
    "textDocument/didOpen" => {
      if !state.initialized || state.shutdown {
        match message.id { Some(id) => [error_response(id, -32600, "server is not ready")]; None => [] }
      } else {
        match message.params {
          Some(params) => {
            match document_from_params(params, "textDocument") {
              Some((uri, version, text)) => {
                match resolve_selection_with_source(state, params, language_id_from_params(params, "textDocument")) {
                  Ok((selection, source)) => {
                    if state.docs.open(uri, version, text, selection.dialect, selection.profile, source, language_id_from_params(params, "textDocument")) {
                      match state.docs.get(uri) {
                        Some(document) => parse_document(state, document)
                        None => []
                      }
                    } else {
                      match message.id { Some(id) => [error_response(id, -32602, "didOpen version is stale")]; None => [] }
                    }
                  }
                  Err(error) => [config_diagnostic(uri, version, selection_error_message(error))]
                }
              }
              None => match message.id { Some(id) => [error_response(id, -32602, "didOpen requires uri, version, and text")]; None => [] }
            }
          }
          None => match message.id { Some(id) => [error_response(id, -32602, "didOpen requires textDocument")]; None => [] }
        }
      }
    }
    "textDocument/didChange" => {
      if !state.initialized || state.shutdown {
        match message.id { Some(id) => [error_response(id, -32600, "server is not ready")]; None => [] }
      } else {
        match message.params {
          Some(params) => {
            match changed_document(params) {
              Some((uri, version, text)) => {
                match state.docs.get(uri) {
                  None => match message.id { Some(id) => [error_response(id, -32602, "didChange version is stale or document is not open")]; None => [] }
                  Some(current) => {
                    // Document-level extension fields win; otherwise the
                    // stored context persists across edits (D-03).
                    let resolved = match selection_from_params(params) {
                      Some(selection) => match validate_selection(selection) {
                        Ok(selection) => Ok((selection, "document"))
                        Err(error) => Err(error)
                      }
                      None => Ok(({ dialect: current.dialect, profile: current.profile }, current.selection_source))
                    }
                    match resolved {
                      Ok((selection, source)) => {
                        if state.docs.change(uri, version, text, selection.dialect, selection.profile, source, current.language_id) {
                          match state.docs.get(uri) {
                            Some(document) => parse_document(state, document)
                            None => []
                          }
                        } else {
                          match message.id { Some(id) => [error_response(id, -32602, "didChange version is stale or document is not open")]; None => [] }
                        }
                      }
                      Err(error) => {
                        // MI-07: an invalid document-level selection still
                        // advances the stored version+text (the previous
                        // selection persists) so a later valid didChange or a
                        // completion/formatting request carrying this version
                        // is not judged stale against the old text. Only the
                        // config diagnostic is published — no parse
                        // diagnostics under the invalid selection.
                        if state.docs.change(uri, version, text, current.dialect, current.profile, current.selection_source, current.language_id) {
                          [config_diagnostic(uri, version, selection_error_message(error))]
                        } else {
                          match message.id { Some(id) => [error_response(id, -32602, "didChange version is stale or document is not open")]; None => [] }
                        }
                      }
                    }
                  }
                }
              }
              None => match message.id { Some(id) => [error_response(id, -32602, "didChange requires a full-content change")]; None => [] }
            }
          }
          None => match message.id { Some(id) => [error_response(id, -32602, "didChange requires textDocument and contentChanges")]; None => [] }
        }
      }
    }
    "textDocument/didClose" => {
      let result = match message.params {
        Some(params) => match uri_from_params(params, "textDocument") {
          Some(uri) => { ignore(state.docs.close(uri)); None }
          None => Some("didClose requires textDocument.uri")
        }
        None => Some("didClose requires textDocument.uri")
      }
      match (result, message.id) {
        (Some(message), Some(id)) => [error_response(id, -32602, message)]
        _ => []
      }
    }
    "workspace/didChangeConfiguration" => {
      // Push arm (primary, A2): the client's settings payload carries the
      // fathom section { dialect?, profile?, languageMapping? } under
      // params.settings.fathom (VS Code's standard push shape).
      let section = match message.params {
        Some(params) => match object_field(params, "settings") {
          Some(settings) => object_field(settings, "fathom")
          None => None
        }
        None => None
      }
      match section {
        None => []
        Some(section) => match apply_settings(state, section) {
          Ok(_) => re_resolve_open_documents(state)
          Err(message) => [show_message(1, message)]
        }
      }
    }
    "workspace/configuration" => {
      // Pull arm (optional, A2): the correlated response to the server's
      // workspace/configuration request (pending_config_request) carries the
      // fathom section under params.fathom. Uncorrelated requests are
      // method-not-found (the server does not answer client pulls).
      let id = match message.id {
        Some(id) => id
        None => return []
      }
      match state.pending_config_request {
        Some(pending) if id == pending => {
          state.pending_config_request = None
          let section = match message.params {
            Some(params) => object_field(params, "fathom")
            None => None
          }
          match section {
            None => [show_message(1, "workspace/configuration response is missing the fathom section")]
            Some(section) => match apply_settings(state, section) {
              Ok(_) => re_resolve_open_documents(state)
              Err(message) => [show_message(1, message)]
            }
          }
        }
        _ => [ error_response(id, -32601, "method not found")]
      }
    }
    "textDocument/completion" => {
      let id = match message.id {
        Some(id) => id
        None => return []
      }
      if !state.initialized || state.shutdown { return [error_response(id, -32600, "server is not ready")] }
      let params = match message.params {
        Some(params) => params
        None => return [error_response(id, -32602, "completion requires params")]
      }
      completion_result(state, params, id)
    }
    "textDocument/formatting" => {
      let id = match message.id {
        Some(id) => id
        None => return []
      }
      if !state.initialized || state.shutdown { return [error_response(id, -32600, "server is not ready")] }
      let params = match message.params {
        Some(params) => params
        None => return [error_response(id, -32602, "formatting requires textDocument")]
      }
      let uri = match uri_from_params(params, "textDocument") {
        Some(uri) => uri
        None => return [error_response(id, -32602, "formatting requires textDocument.uri")]
      }
      formatting_result(state, uri, id)
    }
    _ => match message.id {
      Some(id) => [ error_response(id, -32601, "method not found")]
      None => []
    }
  }
}
