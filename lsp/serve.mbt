/// The single stdio server loop (D-01 seam, T-09-15): the ONLY stdio entry in
/// the module. Both the fathom-sql CLI `lsp` subcommand and the standalone
/// fathom-lsp executable call this; there is no second server main. Process IO
/// stays here; handlers remain pure with respect to transport and call the
/// backend-neutral api facade.
///
/// `initial_dialect`/`initial_profile` are stored as workspace/session
/// explicit defaults on ServerState (D-01); the standalone fathom-lsp binary
/// passes None (no default — missing selection is a configuration error per
/// D-02 once the 09-06 resolution logic consumes these fields).
pub fn serve_stdio(initial_dialect : String?, initial_profile : String?) -> Unit {
  let state =  ServerState::new()
  state.default_dialect = initial_dialect
  state.default_profile = initial_profile
  let source = FrameSource::new()
  let mut running = true
  while running {
    match  read_frame(source) {
      Ok(Some(body)) => {
        match  parse_message(body) {
          Ok(message) => {
            let responses =  handle_message(state, message)
            for response in responses {
               write_frame(response)
            }
            running = !state.exited
          }
          Err(message) =>  write_frame(error_response(RpcId::NullId, -32700, message))
        }
      }
      Ok(None) => running = false
      Err(_) =>  write_frame(error_response(RpcId::NullId, -32700, "malformed Content-Length frame"))
    }
  }
}
