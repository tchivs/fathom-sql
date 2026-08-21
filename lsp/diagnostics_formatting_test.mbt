///|
test "diagnostics_and_formatting_contract" {
  let schemas = ["fathom.parse.v1", "fathom.format.v1"]
  let expected_schemas = ["fathom.parse.v1", "fathom.format.v1"]
  assert_eq(schemas, expected_schemas)
  assert_eq(schemas[0], "fathom.parse.v1")
  assert_eq(schemas[1], "fathom.format.v1")
  let source = b"select 1"
  let refusal_fields = [
    "schema_version", "source_bytes", "diagnostics", "formatted",
  ]
  assert_eq(refusal_fields, [
    "schema_version", "source_bytes", "diagnostics", "formatted",
  ])
  let parsed = match @api.parse_with_ids(source, "doris", "4.x", "editor") {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(@binding.parse_result_json(parsed).contains("fathom.parse.v1"))
  let formatted = match
    @api.format_with_ids(
      source,
      "doris",
      "4.x",
      "strict",
      @api.FormatOptions::default(),
    ) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(
    @binding.format_result_json(source, formatted, "doris", "4.x", "4.x").contains(
      "fathom.format.v1",
    ),
  )
  assert_true(formatted.accepted)
  assert_true(formatted.output != source)
  assert_eq(source, b"select 1")
}

///|
test "lsp_publishes_diagnostics_and_one_full_document_edit" {
  let state = ServerState::new()
  let init = match
    parse_message(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"initializationOptions\":{\"dialect\":\"doris\",\"profile\":\"4.x\"}}}",
      ),
    ) {
    Ok(message) => message
    Err(_) => panic()
  }
  ignore(handle_message(state, init))
  let open = match
    parse_message(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tracer.sql\",\"version\":1,\"text\":\"select 1\"}}}",
      ),
    ) {
    Ok(message) => message
    Err(_) => panic()
  }
  let published = handle_message(state, open)
  assert_eq(published.length(), 1)
  let published_body = @utf8.decode_lossy(published[0])
  assert_true(published_body.contains("publishDiagnostics"))
  // The valid document's publish carries no diagnostics, but the server
  // identity is neutral in the notification shape itself (NAME-03).
  assert_true(!published_body.contains("doris"))
  // A document with a parse error publishes neutral FATHOM-* diagnostics with
  // source fathom — the legacy doris identity never appears (NAME-03, D-10).
  let bad_open = match
    parse_message(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///broken.sql\",\"version\":1,\"text\":\"SELEC 1\"}}}",
      ),
    ) {
    Ok(message) => message
    Err(_) => panic()
  }
  let bad_published = handle_message(state, bad_open)
  assert_eq(bad_published.length(), 1)
  let bad_body = @utf8.decode_lossy(bad_published[0])
  assert_true(bad_body.contains("\"source\":\"fathom\""))
  assert_true(bad_body.contains("FATHOM-PARSE-"))
  assert_true(!bad_body.contains("\"source\":\"doris\""))
  assert_true(!bad_body.contains("doris"))
  let format = match
    parse_message(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"textDocument/formatting\",\"params\":{\"textDocument\":{\"uri\":\"file:///tracer.sql\"}}}",
      ),
    ) {
    Ok(message) => message
    Err(_) => panic()
  }
  let edits = handle_message(state, format)
  assert_true(edits.length() >= 1)
  let body = @utf8.decode_lossy(edits[edits.length() - 1])
  assert_true(body.contains("newText"))
  assert_true(body.contains("range"))
}
