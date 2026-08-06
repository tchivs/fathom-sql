/// Standalone LSP server entrypoint: starts the shared stdio loop with no
/// workspace defaults (the CLI `lsp` subcommand passes its parsed
/// --dialect/--profile instead). One serve_stdio implementation is the only
/// stdio entry in the module (T-09-15).
fn main {
  @lsp.serve_stdio(None, None)
}
