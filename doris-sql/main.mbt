/// Thin IO/argv wiring only (D-37/D-38): argv -> stdin/file bytes ->
/// run_format -> stdout/stderr/exit. Every decision lives in the pure
/// run_format; this file only moves bytes between the OS and the CLI core.
/// stdout is written with write_fd(1, ...) — byte-exact and unbuffered, so
/// exit_process never drops pending output (CRLF and non-UTF-8 string
/// literals pass through untouched).
fn main {
  let args = @env.args()
  // arg[0] is the executable path; drop it.
  let rest : Array[String] = []
  for i in 1 ..< args.length() {
    rest.push(args[i])
  }
  // --help wins over every other argument: usage on stdout, exit 0.
  if rest.contains("--help") {
    let usage = @utf8.encode(usage_text())
    ignore(write_fd(1, usage, usage.length()))
    exit_process(0)
  }
  let command = match parse_args(rest) {
    Ok(command) => command
    Err(error) => {
      let message = @utf8.encode(usage_error_message(error))
      ignore(write_fd(2, message, message.length()))
      exit_process(2)
      panic() // unreachable — exit_process terminates
    }
  }
  // WR-01: only read stdin when the invocation selects stdin (no file, or
  // "-"). A file-mode invocation must not block on an open stdin that never
  // delivers EOF (interactive terminal, CI with a live stdin pipe, a parent
  // holding fd 0) — read_stdin would hang before the file is ever touched.
  let stdin_bytes = match command.file {
    Some(path) if path != "-" => b""
    _ => read_stdin()
  }
  let outcome = run_format(command, stdin_bytes)
  if outcome.stdout.length() > 0 {
    ignore(write_fd(1, outcome.stdout, outcome.stdout.length()))
  }
  if outcome.stderr.length() > 0 {
    ignore(write_fd(2, outcome.stderr, outcome.stderr.length()))
  }
  exit_process(outcome.exit_code)
}
