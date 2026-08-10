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

test "did_change_with_invalid_document_selection_advances_store" {
  // MI-07: an invalid document-level selection on didChange still advances
  // the stored version+text (the previous selection persists) so later
  // requests carrying this version are not stale; only the config diagnostic
  // is published — no version/text desync.
  let state = ServerState::new()
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}")))
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///invalid-change.sql\",\"version\":1,\"text\":\"SELECT 1\"}}}")
  ignore(handle_message(state, open))
  let change = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///invalid-change.sql\",\"version\":2,\"dialect\":\"mysql\",\"profile\":\"4.x\"},\"contentChanges\":[{\"text\":\"SELECT 2\"}]}}")
  let responses = handle_message(state, change)
  assert_eq(responses.length(), 1)
  let body = @utf8.decode_lossy(responses[0])
  assert_true(body.contains("publishDiagnostics"))
  assert_true(body.contains("FATHOM-SCHEMA-007"))
  assert_true(body.contains("unknown dialect: mysql"))
  let document = match state.docs.get("file:///invalid-change.sql") {
    Some(document) => document
    None => panic()
  }
  assert_eq(document.version, 2)
  assert_eq(document.text, @utf8.encode("SELECT 2"))
  assert_eq(document.dialect, "doris")
  assert_eq(document.profile, "4.x")
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
  // IN-04a: the pull uses the session-unique server request id (1), not a
  // hardcoded 0.
  assert_true(@utf8.decode_lossy(after_init[0]).contains("\"id\":1"))
  let response = message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"workspace/configuration\",\"params\":{\"fathom\":{\"dialect\":\"doris\",\"profile\":\"2.1\"}}}")
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
  // revision under the new context. Phase 11 retires FATHOM-PARSE-008: a
  // valid `SELECT 1` parses through the real Flink grammar and publishes an
  // EMPTY diagnostics array — never Doris acceptance and never the old
  // not-implemented diagnostic.
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
  assert_true(body.contains("\"diagnostics\":[]"))
  assert_true(!body.contains("FATHOM-PARSE-008"))
  let document = match state.docs.get("file:///switch.sql") {
    Some(document) => document
    None => panic()
  }
  assert_eq(document.dialect, "flink")
  assert_eq(document.profile, "flink-2.3.0")
  assert_eq(document.selection_source, "workspace")
}

test "flink_document_format_returns_real_edit_and_completion_returns_real_results" {
  // (j) T-09-23 / 13-02 / D-07: a flink-selected document's valid SELECT
  // parses through the real Flink grammar (empty diagnostics — FATHOM-PARSE-008
  // retired, D-06). Formatting is REAL (13-05, D-07): `SELECT 1` formats to
  // "SELECT 1\n" and returns a textEdit with newText — never the -32603
  // not-implemented sentinel. Completion returns real results through the
  // shared completion core (D-02, 13-02) — no Doris policy leak on any
  // surface.
  let state = ServerState::new()
  state.initialized = true
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink.sql\",\"version\":1,\"text\":\"SELECT 1\",\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}")
  let opened = handle_message(state, open)
  assert_eq(opened.length(), 1)
  let parse_body = @utf8.decode_lossy(opened[0])
  assert_true(!parse_body.contains("FATHOM-PARSE-008"))
  assert_true(parse_body.contains("\"diagnostics\":[]"))
  let format = message("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink.sql\"}}}")
  let edits = handle_message(state, format)
  assert_eq(edits.length(), 1)
  let format_body = @utf8.decode_lossy(edits[0])
  // D-07: flink formatting is a real edit array (newText), never -32603.
  assert_true(!format_body.contains("-32603"))
  assert_true(!format_body.contains("not yet implemented"))
  assert_true(format_body.contains("\"result\""))
  assert_true(format_body.contains("\"newText\""))
  let completion = message("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink.sql\",\"version\":1},\"position\":{\"line\":0,\"character\":7}}}")
  let completion_responses = handle_message(state, completion)
  assert_eq(completion_responses.length(), 1)
  // 13-02 (D-02): flink completion now returns real results through the
  // shared completion core — the -32602 rejection is gone. The response is a
  // completion list (echoed id + "result"), never a rejection and never a
  // Doris fallback.
  let completion_body = @utf8.decode_lossy(completion_responses[0])
  assert_true(!completion_body.contains("-32602"))
  assert_true(completion_body.contains("\"result\""))
  assert_true(completion_body.contains("\"isIncomplete\""))
}

test "flink_document_override_beats_workspace_default" {
  // D-06 / D-07: a workspace default of doris-4.x with a flink-selected
  // document (didOpen extension fields) — the document's diagnostics, format,
  // and completion all use flink-2.3.0, never the doris default (D-01
  // document-level precedence; per-file override for flink files).
  let state = ServerState::new()
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}")))
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///override.sql\",\"version\":1,\"text\":\"SELECT 1\",\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}")
  let opened = handle_message(state, open)
  assert_eq(opened.length(), 1)
  let document = match state.docs.get("file:///override.sql") {
    Some(document) => document
    None => panic()
  }
  assert_eq(document.dialect, "flink")
  assert_eq(document.profile, "flink-2.3.0")
  assert_eq(document.selection_source, "document")
  // Formatting uses the flink path (real edit), never a doris layout.
  let format = message("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///override.sql\"}}}")
  let format_responses = handle_message(state, format)
  assert_eq(format_responses.length(), 1)
  let format_body = @utf8.decode_lossy(format_responses[0])
  assert_true(format_body.contains("\"result\""))
  assert_true(format_body.contains("\"newText\""))
  // Completion uses the flink-2.3.0 candidate pool.
  let completion = message("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///override.sql\",\"version\":1},\"position\":{\"line\":0,\"character\":7}}}")
  let completion_responses = handle_message(state, completion)
  assert_eq(completion_responses.length(), 1)
  let completion_body = @utf8.decode_lossy(completion_responses[0])
  assert_true(completion_body.contains("\"items\""))
}

test "flink_profile_switch_reparses" {
  // D-06 / D-03: a didChange profile switch (flink-2.3.0 -> flink-1.20.5) on a
  // flink-selected document re-parses under the new profile; the stored
  // selection advances and only the newest selection's diagnostics publish.
  let state = ServerState::new()
  state.initialized = true
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///switch-profile.sql\",\"version\":1,\"text\":\"SELECT 1\",\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}")
  assert_eq(handle_message(state, open).length(), 1)
  let change = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///switch-profile.sql\",\"version\":2,\"dialect\":\"flink\",\"profile\":\"flink-1.20.5\"},\"contentChanges\":[{\"text\":\"SELECT 1\"}]}}")
  let changed = handle_message(state, change)
  assert_eq(changed.length(), 1)
  let document = match state.docs.get("file:///switch-profile.sql") {
    Some(document) => document
    None => panic()
  }
  assert_eq(document.version, 2)
  assert_eq(document.dialect, "flink")
  assert_eq(document.profile, "flink-1.20.5")
  assert_eq(document.selection_source, "document")
  // The re-parse under flink-1.20.5 publishes clean diagnostics (SELECT 1 is
  // valid in every flink release profile).
  assert_true(@utf8.decode_lossy(changed[0]).contains("publishDiagnostics"))
  assert_true(@utf8.decode_lossy(changed[0]).contains("\"diagnostics\":[]"))
}

test "flink_format_refusal_publishes_diagnostics_empty_array" {
  // D-07 / D-33: an unsafe flink tree's formatting publishes diagnostics
  // (FATHOM-FORMAT-001 refusal, parse diagnostics never masked) PLUS an empty
  // edit array — never partial output and never the -32603 not-implemented
  // sentinel (Pitfall 4: the three response shapes are distinguishable).
  let state = ServerState::new()
  state.initialized = true
  let open = message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink-refuse.sql\",\"version\":1,\"text\":\"SELECT a, b FROM t WHERE\",\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"}}}")
  ignore(handle_message(state, open))
  let format = message("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///flink-refuse.sql\"}}}")
  let responses = handle_message(state, format)
  assert_eq(responses.length(), 2)
  let diag_body = @utf8.decode_lossy(responses[0])
  assert_true(diag_body.contains("publishDiagnostics"))
  assert_true(diag_body.contains("FATHOM-FORMAT-001"))
  let result_body = @utf8.decode_lossy(responses[1])
  assert_true(result_body.contains("\"result\":[]"))
  assert_true(!result_body.contains("-32603"))
}
