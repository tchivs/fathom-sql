/// LSP lifecycle and editor handlers. All parsing/formatting is delegated to the
/// shared api facade; this module only maps primitive results to LSP values.

pub(all) struct ServerState {
  pub mut docs : @documents.DocumentStore
  pub mut profile : String
  pub mut initialized : Bool
  pub mut shutdown : Bool
  pub mut exited : Bool
}

pub fn ServerState::new() -> ServerState {
  { docs: @documents.DocumentStore::new(), profile: "", initialized: false, shutdown: false, exited: false }
}

fn severity_value(severity : String) -> Int {
  match severity {
    "error" => 1
    "warning" => 2
    "info" => 3
    _ => 4
  }
}

fn position_json(position : @binding.Position) -> @json.Json {
  {
    "line": @json.Json::number(position.line.to_double()),
    "character": @json.Json::number(position.character.to_double()),
  }
}

fn range_json(range : @binding.Range) -> @json.Json {
  { "start": position_json(range.start), "end": position_json(range.end) }
}

fn diagnostic_json(raw : Bytes, severity : String, code : String, message : String, start_byte : Int, end_byte : Int) -> @json.Json {
  let range = match @coordinates.diagnostic_range(raw, start_byte, end_byte) {
    Some(range) => range
    None => { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } }
  }
  {
    "range": range_json(range),
    "severity": @json.Json::number(severity_value(severity).to_double()),
    "code": @json.Json::string(code),
    "source": @json.Json::string("doris"),
    "message": @json.Json::string(message),
    "data": {
      "start_byte": @json.Json::number(start_byte.to_double()),
      "end_byte": @json.Json::number(end_byte.to_double()),
    },
  }
}

fn parse_diagnostics_json(raw : Bytes, result : @api.ParseResult) -> @json.Json {
  let values : Array[@json.Json] = []
  for diagnostic in result.diagnostics {
    values.push(diagnostic_json(raw, diagnostic.severity, diagnostic.code, diagnostic.message, diagnostic.start_byte, diagnostic.end_byte))
  }
  @json.Json::array(values)
}

fn format_diagnostics_json(raw : Bytes, diagnostics : Array[@api.FormatDiagnostic]) -> @json.Json {
  let values : Array[@json.Json] = []
  for diagnostic in diagnostics {
    values.push(diagnostic_json(raw, diagnostic.severity, diagnostic.code, diagnostic.message, diagnostic.start_byte, diagnostic.end_byte))
  }
  @json.Json::array(values)
}

fn publish_diagnostics(uri : String, version : Int, raw : Bytes, diagnostics : @json.Json) -> Bytes {
  @protocol.notification("textDocument/publishDiagnostics", {
    "uri": @json.Json::string(uri),
    "version": @json.Json::number(version.to_double()),
    "diagnostics": diagnostics,
  })
}

fn parse_document(state : ServerState, document : @documents.Document) -> Bytes {
  let diagnostics = match @api.parse_with_ids(document.text, state.profile, "editor") {
    Ok(result) => parse_diagnostics_json(document.text, result)
    Err(_) => @json.Json::array([{ 
      "range": { "start": { "line": @json.Json::number(0.0), "character": @json.Json::number(0.0) }, "end": { "line": @json.Json::number(0.0), "character": @json.Json::number(0.0) } },
      "severity": @json.Json::number(1.0),
      "code": @json.Json::string("DORIS-LSP-001"),
      "source": @json.Json::string("doris"),
      "message": @json.Json::string("document could not be parsed"),
    }])
  }
  publish_diagnostics(document.uri, document.version, document.text, diagnostics)
}

fn document_from_params(params : @json.Json, key : String) -> (String, Int, Bytes)? {
  let document = match @protocol.object_field(params, key) {
    Some(document) => document
    None => return None
  }
  let uri = match @protocol.string_field(document, "uri") {
    Some(uri) => uri
    None => return None
  }
  let version = match @protocol.int_field(document, "version") {
    Some(version) => version
    None => return None
  }
  let text = match @protocol.string_field(document, "text") {
    Some(text) => text
    None => return None
  }
  Some((uri, version, @utf8.encode(text)))
}
fn uri_from_params(params : @json.Json, key : String) -> String? {
  let document = match @protocol.object_field(params, key) {
    Some(document) => document
    None => return None
  }
  @protocol.string_field(document, "uri")
}

fn changed_document(params : @json.Json) -> (String, Int, Bytes)? {
  let document = match @protocol.object_field(params, "textDocument") {
    Some(document) => document
    None => return None
  }
  let uri = match @protocol.string_field(document, "uri") {
    Some(uri) => uri
    None => return None
  }
  let version = match @protocol.int_field(document, "version") {
    Some(version) => version
    None => return None
  }
  let changes = match @protocol.array_field(params, "contentChanges") {
    Some(changes) => changes
    None => return None
  }
  if changes.length() == 0 { return None }
  let text = match @protocol.string_field(changes[0], "text") {
    Some(text) => text
    None => return None
  }
  Some((uri, version, @utf8.encode(text)))
}

fn initialize_profile(params : @json.Json) -> String? {
  let options = match @protocol.object_field(params, "initializationOptions") {
    Some(options) => options
    None => return None
  }
  @protocol.string_field(options, "profile")
}

fn initialize_result() -> @json.Json {
  {
    "capabilities": {
      "textDocumentSync": @json.Json::number(1.0),
      "documentFormattingProvider": @json.Json::boolean(true),
      "positionEncoding": @json.Json::array([@json.Json::string("utf-16")]),
    },
    "serverInfo": { "name": @json.Json::string("doris-lsp"), "version": @json.Json::string("0.1") },
  }
}

fn formatting_result(state : ServerState, uri : String, id : @protocol.RpcId) -> Array[Bytes] {
  let document = match state.docs.get(uri) {
    Some(document) => document
    None => return [@protocol.response(id, @json.Json::array([]))]
  }
  let result = match @api.format_with_ids(document.text, state.profile, "strict", @api.FormatOptions::default()) {
    Ok(result) => result
    Err(_) => return [@protocol.response(id, @json.Json::array([]))]
  }
  let mut responses : Array[Bytes] = []
  if result.diagnostics.length() > 0 {
    responses.push(publish_diagnostics(document.uri, document.version, document.text, format_diagnostics_json(document.text, result.diagnostics)))
  }
  if !result.accepted {
    responses.push(@protocol.response(id, @json.Json::array([])))
    return responses
  }
  if result.output == document.text {
    responses.push(@protocol.response(id, @json.Json::array([])))
    return responses
  }
  let range = match @coordinates.full_document_range(document.text) {
    Some(range) => range
    None => {
      responses.push(@protocol.error_response(id, -32603, "unable to compute UTF-16 document range"))
      return responses
    }
  }
  let edit = {
    "range": range_json(range),
    "newText": @json.Json::string(@utf8.decode_lossy(result.output)),
  }
  responses.push(@protocol.response(id, @json.Json::array([edit])))
  responses
}

pub fn handle_message(state : ServerState, message : @protocol.RpcMessage) -> Array[Bytes] {
  match message.method {
    "initialize" => {
      let id = match message.id {
        Some(id) => id
        None => return []
      }
      if state.initialized { return [@protocol.error_response(id, -32600, "server is already initialized")] }
      let params = match message.params {
        Some(params) => params
        None => return [@protocol.error_response(id, -32602, "initialize requires initializationOptions.profile")]
      }
      let profile = match initialize_profile(params) {
        Some(profile) => profile
        None => return [@protocol.error_response(id, -32602, "initialize requires initializationOptions.profile")]
      }
      match @binding.validate_profile(profile) {
        Ok(_) => {
          state.profile = profile
          state.initialized = true
          [@protocol.response(id, initialize_result())]
        }
        Err(_) => [@protocol.error_response(id, -32602, "unsupported Doris profile")]
      }
    }
    "initialized" => []
    "shutdown" => {
      let id = match message.id {
        Some(id) => id
        None => return []
      }
      if !state.initialized { return [@protocol.error_response(id, -32600, "server is not initialized")] }
      state.shutdown = true
      [@protocol.response(id, @json.Json::Null)]
    }
    "exit" => {
      state.exited = true
      []
    }
    "textDocument/didOpen" => {
      if !state.initialized || state.shutdown { return [] }
      let params = match message.params {
        Some(params) => params
        None => return []
      }
      let (uri, version, text) = match document_from_params(params, "textDocument") {
        Some(value) => value
        None => return []
      }
      if state.docs.open(uri, version, text) {
        match state.docs.get(uri) {
          Some(document) => [parse_document(state, document)]
          None => []
        }
      } else { [] }
    }
    "textDocument/didChange" => {
      if !state.initialized || state.shutdown { return [] }
      let params = match message.params {
        Some(params) => params
        None => return []
      }
      let (uri, version, text) = match changed_document(params) {
        Some(value) => value
        None => return []
      }
      if state.docs.change(uri, version, text) {
        match state.docs.get(uri) {
          Some(document) => [parse_document(state, document)]
          None => []
        }
      } else { [] }
    }
    "textDocument/didClose" => {
      match message.params {
        Some(params) => match uri_from_params(params, "textDocument") {
          Some(uri) => ignore(state.docs.close(uri))
          None => ()
        }
        None => ()
      }
      []
    }
    "textDocument/formatting" => {
      let id = match message.id {
        Some(id) => id
        None => return []
      }
      if !state.initialized || state.shutdown { return [@protocol.error_response(id, -32600, "server is not ready")] }
      let params = match message.params {
        Some(params) => params
        None => return [@protocol.response(id, @json.Json::array([]))]
      }
      let uri = match uri_from_params(params, "textDocument") {
        Some(uri) => uri
        None => return [@protocol.response(id, @json.Json::array([]))]
      }
      formatting_result(state, uri, id)
    }
    _ => match message.id {
      Some(id) => [@protocol.error_response(id, -32601, "method not found")]
      None => []
    }
  }
}
