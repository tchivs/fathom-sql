///|
/// Standalone LSP server entrypoint: starts the shared stdio loop with no
/// workspace defaults (the CLI `lsp` subcommand passes its parsed
/// --dialect/--profile instead). One serve_stdio implementation is the only
/// stdio entry in the module (T-09-15).
fn main {
  let args = @env.args()
  // Standalone --version (VER-02/D-02): sole flag -> print and exit 0 before
  // entering the server loop (which would otherwise block on stdin forever).
  if args.length() == 2 && args[1] == "--version" {
    @version.print_and_exit("fathom-lsp")
  }
  @lsp.serve_stdio(None, None)
}
