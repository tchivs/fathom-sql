/// Native executable entrypoint. All process IO stays here; handlers remain
/// pure with respect to transport and call the backend-neutral api facade.

fn main {
  let mut state = @handlers.ServerState::new()
  let mut running = true
  while running {
    match @framing.read_frame() {
      Ok(Some(body)) => {
        match @protocol.parse_message(body) {
          Ok(message) => {
            let responses = @handlers.handle_message(state, message)
            for response in responses {
              @framing.write_frame(response)
            }
            running = !state.exited
          }
          Err(message) => @framing.write_frame(@framing.frame(@protocol.error_response(@protocol.RpcId::Null, -32700, message)))
        }
      }
      Ok(None) => running = false
      Err(_) => @framing.write_frame(@framing.frame(@protocol.error_response(@protocol.RpcId::Null, -32700, "malformed Content-Length frame")))
    }
  }
}
