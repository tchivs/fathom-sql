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

test "initialize_uses_serve_stdio_defaults_without_initialization_options" {
  // MA-01: a bare LSP client (no initializationOptions at all) initializes
  // successfully when serve_stdio provided the workspace defaults — the
  // 09-06 option-a contract "workspace default comes from initializationOptions
  // OR serve_stdio args" holds for `fathom-sql lsp --dialect doris --profile
  // 4.x`.
  let state = ServerState::new()
  state.default_dialect = Some("doris")
  state.default_profile = Some("4.x")
  let responses = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"))
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("\"capabilities\""))
  assert_true(state.initialized)
  assert_eq(state.default_dialect, Some("doris"))
  assert_eq(state.default_profile, Some("4.x"))
}

test "initialize_without_any_source_returns_missing_selection_error" {
  // MA-01: with neither initializationOptions nor serve_stdio defaults the
  // initialize still fails with the MissingSelection-class -32602.
  let state = ServerState::new()
  let responses = handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"))
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("-32602"))
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

test "did_change_configuration_dialect_switch_reparses_flink" {
  // (h) D-03: a workspace-default dialect switch re-parses the current
  // revision under the new context and publishes the flink not-implemented
  // diagnostics (FATHOM-PARSE-008) — never Doris acceptance, never a silent
  // empty result.
  let state = ServerState::new()
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}")))
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///switch.sql\",\"version\":1,\"text\":\"SELECT 1\"}}}")
  let opened = handle_message(state, open)
  assert_eq(opened.length(), 1)
  assert_true(!@utf8.decode_lossy(opened[0]).contains("FATHOM-PARSE-008"))
  let config = message("{\"jsonrpc\":\"2.0\",\"method\":\"workspace/didChangeConfiguration\",\"params\":{\"settings\":{\"fathom\":{\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}}")
  let switched = handle_message(state, config)
  assert_eq(switched.length(), 1)
  let body = @utf8.decode_lossy(switched[0])
  assert_true(body.contains("publishDiagnostics"))
  assert_true(body.contains("FATHOM-PARSE-008"))
  assert_true(body.contains("\"source\":\"fathom\""))
  assert_true(body.contains("flink grammar is not yet implemented in this release"))
  let document = match state.docs.get("file:///switch.sql") {
    Some(document) => document
    None => panic()
  }
  assert_eq(document.dialect, "flink")
  assert_eq(document.profile, "flink-2.3.0")
  assert_eq(document.selection_source, "workspace")
}

test "flink_document_format_and_completion_reject_without_doris_policy" {
  // (j) T-09-23: a flink-selected document's parse publishes FATHOM-PARSE-008,
  // while formatting and completion return the structured rejection (the api
  // unsupported-profile error) — no Doris policy leak on any surface.
  let state = ServerState::new()
  state.initialized = true
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink.sql\",\"version\":1,\"text\":\"SELECT 1\",\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}")
  let opened = handle_message(state, open)
  assert_eq(opened.length(), 1)
  let parse_body = @utf8.decode_lossy(opened[0])
  assert_true(parse_body.contains("FATHOM-PARSE-008"))
  assert_true(parse_body.contains("\"source\":\"fathom\""))
  let format = message("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink.sql\"}}}")
  let edits = handle_message(state, format)
  assert_eq(edits.length(), 1)
  let format_body = @utf8.decode_lossy(edits[0])
  // MI-06: flink formatting is a structured -32603 not-implemented error,
  // never a silent empty edit array.
  assert_true(format_body.contains("-32603"))
  assert_true(format_body.contains("flink grammar is not yet implemented"))
  assert_true(!format_body.contains("\"result\""))
  let completion = message("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink.sql\",\"version\":1},\"position\":{\"line\":0,\"character\":7}}}")
  let completion_responses = handle_message(state, completion)
  assert_eq(completion_responses.length(), 1)
  assert_true(@utf8.decode_lossy(completion_responses[0]).contains("-32602"))
}
