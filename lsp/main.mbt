/// Native executable entrypoint. All process IO stays here; handlers remain
/// pure with respect to transport and call the backend-neutral api facade.

fn main {
  let state =  ServerState::new()
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
