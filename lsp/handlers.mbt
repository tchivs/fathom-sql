/// LSP lifecycle and editor handlers. All parsing/formatting is delegated to the
/// shared api facade; this module only maps primitive results to LSP values.

pub(all) struct ServerState {
  pub mut docs :  DocumentStore
  pub mut profile : String
  pub mut initialized : Bool
  pub mut shutdown : Bool
  pub mut exited : Bool
}

pub fn ServerState::new() -> ServerState {
  { docs:  DocumentStore::new(), profile: "", initialized: false, shutdown: false, exited: false }
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
    "source": Json::string("doris"),
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

fn parse_document(state : ServerState, document :  Document) -> Bytes {
  let diagnostics = match @api.parse_with_ids(document.text, state.profile, "editor") {
    Ok(result) => parse_diagnostics_json(document.text, result)
    Err(_) => Json::array([{ 
      "range": { "start": { "line": Json::number(0.0), "character": Json::number(0.0) }, "end": { "line": Json::number(0.0), "character": Json::number(0.0) } },
      "severity": Json::number(1.0),
      "code": Json::string("DORIS-LSP-001"),
      "source": Json::string("doris"),
      "message": Json::string("document could not be parsed"),
    }])
  }
  publish_diagnostics(document.uri, document.version, document.text, diagnostics)
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

fn initialize_profile(params : Json) -> String? {
  let options = match  object_field(params, "initializationOptions") {
    Some(options) => options
    None => return None
  }
   string_field(options, "profile")
}

fn initialize_result() -> Json {
  {
    "capabilities": {
      "textDocumentSync": Json::number(1.0),
      "documentFormattingProvider": Json::boolean(true),
      "completionProvider": { "triggerCharacters": Json::array([Json::string(" "), Json::string(".")]) },
      "positionEncoding": Json::array([Json::string("utf-16")]),
    },
    "serverInfo": { "name": Json::string("doris-lsp"), "version": Json::string("0.1") },
  }
}

fn formatting_result(state : ServerState, uri : String, id :  RpcId) -> Array[Bytes] {
  let document = match state.docs.get(uri) {
    Some(document) => document
    None => return [ response(id, Json::array([]))]
  }
  let result = match @api.format_with_ids(document.text, state.profile, "strict", @api.FormatOptions::default()) {
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
  let result = match @completion.complete(document.text, state.profile, cursor_byte) {
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


pub fn handle_message(state : ServerState, message :  RpcMessage) -> Array[Bytes] {
  match message.method {
    "initialize" => {
      let id = match message.id {
        Some(id) => id
        None => return []
      }
      if state.initialized { return [ error_response(id, -32600, "server is already initialized")] }
      let params = match message.params {
        Some(params) => params
        None => return [ error_response(id, -32602, "initialize requires initializationOptions.profile")]
      }
      let profile = match initialize_profile(params) {
        Some(profile) => profile
        None => return [ error_response(id, -32602, "initialize requires initializationOptions.profile")]
      }
      match @binding.validate_profile(profile) {
        Ok(_) => {
          state.profile = profile
          state.initialized = true
          [ response(id, initialize_result())]
        }
        Err(_) => [ error_response(id, -32602, "unsupported Doris profile")]
      }
    }
    "initialized" => []
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
                if state.docs.open(uri, version, text) {
                  match state.docs.get(uri) {
                    Some(document) => [parse_document(state, document)]
                    None => []
                  }
                } else {
                  match message.id { Some(id) => [error_response(id, -32602, "didOpen version is stale")]; None => [] }
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
                if state.docs.change(uri, version, text) {
                  match state.docs.get(uri) {
                    Some(document) => [parse_document(state, document)]
                    None => []
                  }
                } else {
                  match message.id { Some(id) => [error_response(id, -32602, "didChange version is stale or document is not open")]; None => [] }
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
