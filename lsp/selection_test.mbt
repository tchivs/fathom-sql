// D-01/D-02/D-03 selection-resolution smoke matrix: structured config errors
// for missing/unknown/conflicting selections, the languageId-mapping level,
// document-level precedence, and the settings push/pull arms. Mirrors
// protocol_test.mbt (black-box, pub surface only); the `message` helper is
// shared from protocol_test.mbt's test target.

test "initialize_without_dialect_returns_structured_error" {
  // (a) D-02: a missing selection at initialize is a structured -32602 error,
  // never a languageId-derived guess.
  let state = ServerState::new()
  let responses = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"profile\":\"4.x\"}}}"))
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("-32602"))
  assert_true(body.contains("dialect"))
  assert_true(!state.initialized)
}

test "initialize_with_unknown_dialect_returns_structured_error" {
  // (b) unknown dialect -> -32602 naming the dialect.
  let state = ServerState::new()
  let responses = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"mysql\",\"profile\":\"4.x\"}}}"))
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("-32602"))
  assert_true(body.contains("unknown dialect"))
  assert_true(body.contains("mysql"))
  assert_true(!state.initialized)
}

test "initialize_with_unknown_doris_profile_returns_structured_error" {
  // (c) unknown profile for a known dialect -> -32602.
  let state = ServerState::new()
  let responses = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"5.x\"}}}"))
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("-32602"))
  assert_true(body.contains("unsupported profile"))
  assert_true(!state.initialized)
}

test "initialize_conflicting_workspace_sources_returns_structured_error" {
  // (d) D-01 same-source conflict: serve_stdio workspace default vs
  // initializationOptions -> -32602 naming the conflict.
  let state = ServerState::new()
  state.default_dialect = Some("doris")
  state.default_profile = Some("4.x")
  let responses = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}"))
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("-32602"))
  assert_true(body.contains("conflicting"))
  assert_true(!state.initialized)
}

test "did_open_without_any_selection_publishes_config_error" {
  // (e) D-02 no-guess rule: a document with no selection anywhere gets exactly
  // one FATHOM-SCHEMA-007 config diagnostic naming the missing selection — no
  // silent empty diagnostics, no languageId guess, and the document is not
  // parsed or stored.
  let state = ServerState::new()
  state.initialized = true
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///nonselect.sql\",\"version\":1,\"text\":\"SELECT 1\",\"languageId\":\"sql\"}}}")
  let responses = handle_message(state, open)
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("publishDiagnostics"))
  assert_true(body.contains("FATHOM-SCHEMA-007"))
  assert_true(body.contains("\"source\":\"fathom\""))
  assert_true(body.contains("missing dialect selection"))
  assert_true(!body.contains("FATHOM-PARSE-"))
  assert_true(state.docs.get("file:///nonselect.sql").is_none())
}

test "did_open_resolves_through_configured_language_mapping" {
  // (f) D-02: languageId participates ONLY through a user-configured mapping
  // (workspace/didChangeConfiguration languageMapping). With no document-level
  // config and no workspace default, the mapping resolves the document.
  let state = ServerState::new()
  state.initialized = true
  let config = message("{\"jsonrpc\":\"2.0\",\"method\":\"workspace/didChangeConfiguration\",\"params\":{\"settings\":{\"fathom\":{\"languageMapping\":{\"sql\":{\"dialect\":\"doris\",\"profile\":\"3.x\"}}}}}}")
  assert_eq(handle_message(state, config).length(), 0)
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///mapped.sql\",\"version\":1,\"text\":\"SELECT 1\",\"languageId\":\"sql\"}}}")
  let responses = handle_message(state, open)
  assert_eq(responses.length(), 1)
  assert_true(@utf8.decode_lossy(responses[0]).contains("publishDiagnostics"))
  let document = match state.docs.get("file:///mapped.sql") {
    Some(document) => document
    None => panic()
  }
  assert_eq(document.dialect, "doris")
  assert_eq(document.profile, "3.x")
  assert_eq(document.selection_source, "language")
}

test "did_open_document_level_config_overrides_workspace_default" {
  // (g) D-01 precedence: document-level explicit config beats the workspace
  // default.
  let state = ServerState::new()
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}")))
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///explicit.sql\",\"version\":1,\"text\":\"SELECT 1\",\"dialect\":\"doris\",\"profile\":\"2.1\"}}}")
  let responses = handle_message(state, open)
  assert_eq(responses.length(), 1)
  assert_true(@utf8.decode_lossy(responses[0]).contains("publishDiagnostics"))
  let document = match state.docs.get("file:///explicit.sql") {
    Some(document) => document
    None => panic()
  }
  assert_eq(document.dialect, "doris")
  assert_eq(document.profile, "2.1")
  assert_eq(document.selection_source, "document")
}

test "did_open_with_unknown_document_dialect_publishes_config_error" {
  // Unknown document-level dialect -> FATHOM-SCHEMA-007 naming the dialect;
  // the document is not parsed or stored.
  let state = ServerState::new()
  state.initialized = true
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///unknown.sql\",\"version\":1,\"text\":\"SELECT 1\",\"dialect\":\"mysql\",\"profile\":\"4.x\"}}}")
  let responses = handle_message(state, open)
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("FATHOM-SCHEMA-007"))
  assert_true(body.contains("unknown dialect: mysql"))
  assert_true(state.docs.get("file:///unknown.sql").is_none())
}

test "did_change_configuration_with_invalid_settings_rejects_all_or_nothing" {
  // T-09-19: an invalid fathom settings section is rejected wholesale via
  // window/showMessage; the previous defaults stay in effect.
  let state = ServerState::new()
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}")))
  let config = message("{\"jsonrpc\":\"2.0\",\"method\":\"workspace/didChangeConfiguration\",\"params\":{\"settings\":{\"fathom\":{\"dialect\":\"mysql\",\"profile\":\"4.x\"}}}}")
  let responses = handle_message(state, config)
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("window/showMessage"))
  assert_true(body.contains("unknown dialect: mysql"))
  assert_eq(state.default_dialect, Some("doris"))
  assert_eq(state.default_profile, Some("4.x"))
}

test "workspace_configuration_pull_applies_settings_by_correlated_id" {
  // A2 option-c arm: after "initialized" the server requests the fathom
  // section once; the correlated workspace/configuration response applies the
  // settings, and an uncorrelated id is method-not-found.
  let state = ServerState::new()
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}")))
  let after_init = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\"}"))
  assert_eq(after_init.length(), 1)
  assert_true(@utf8.decode_lossy(after_init[0]).contains("workspace/configuration"))
  let response = message("{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"workspace/configuration\",\"params\":{\"fathom\":{\"dialect\":\"doris\",\"profile\":\"2.1\"}}}")
  let applied = handle_message(state, response)
  assert_eq(applied.length(), 0)
  assert_eq(state.default_dialect, Some("doris"))
  assert_eq(state.default_profile, Some("2.1"))
  // A second uncorrelated workspace/configuration id is not treated as the
  // settings response.
  let uncorrelated = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"workspace/configuration\",\"params\":{}}"))
  assert_eq(uncorrelated.length(), 1)
  assert_true(@utf8.decode_lossy(uncorrelated[0]).contains("-32601"))
}
