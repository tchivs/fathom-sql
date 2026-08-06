// White-box companion to selection_test.mbt: the D-03 stale-response guard
// (test i) exercises the internal version-guarded publication path directly,
// which the black-box surface cannot trigger in a synchronous server.

fn message(text : String) -> RpcMessage {
  match parse_message(@utf8.encode(text)) {
    Ok(value) => value
    Err(_) => panic()
  }
}

test "stale_publication_attempt_is_dropped_by_version_guard" {
  // (i) D-03: a publication computed for a document revision older than the
  // stored version is dropped — the response stream contains no
  // publishDiagnostics for the stale version.
  let state = ServerState::new()
  state.initialized = true
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///stale.sql\",\"version\":2,\"text\":\"SELECT 1\",\"dialect\":\"doris\",\"profile\":\"4.x\"}}}")))
  let stale = ({
    uri: "file:///stale.sql",
    version: 1,
    text: @utf8.encode("SELECT 1"),
    dialect: "doris",
    profile: "4.x",
    selection_source: "document",
    language_id: None,
  } : Document)
  let dropped = parse_document(state, stale)
  assert_eq(dropped.length(), 0)
  // A current-version publication still flows through the same guard.
  let current = match state.docs.get("file:///stale.sql") {
    Some(document) => document
    None => panic()
  }
  let fresh = parse_document(state, current)
  assert_eq(fresh.length(), 1)
  assert_true(@utf8.decode_lossy(fresh[0]).contains("publishDiagnostics"))
  // A stale result under an old SELECTION (dialect switch) is equally dropped:
  // the stored document is flink, the stale result was computed as doris.
  ignore(handle_message(state, message("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///stale.sql\",\"version\":3,\"text\":\"SELECT 1\",\"dialect\":\"flink\",\"profile\":\"flink-2.3.0\"},\"contentChanges\":[{\"text\":\"SELECT 1\"}]}}")))
  let stale_doris = ({
    uri: "file:///stale.sql",
    version: 3,
    text: @utf8.encode("SELECT 1"),
    dialect: "doris",
    profile: "4.x",
    selection_source: "document",
    language_id: None,
  } : Document)
  assert_eq(parse_document(state, stale_doris).length(), 0)
}
