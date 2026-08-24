/// Single source of product version identity (VER-01/D-01).
///
/// `moon.mod`'s module version stays `0.1.0` (Phase 13 release-planning
/// decision); the product semver is decoupled from the module version and
/// lives here only. Both release binaries report this constant via
/// `--version` (VER-02/D-02). Bumping the product version requires editing
/// `product_version()` and following docs/VERSIONING.md (tag + CHANGELOG).

///|
/// Product semver, no `v` prefix (the release tag is `v1.0.3`; the binary
/// reports `1.0.3`).
pub fn product_version() -> String {
  "1.0.3"
}

///|
/// Single-line `--version` output: `<name> <product_version>\n`.
pub fn version_line(name : String) -> String {
  name + " " + product_version() + "\n"
}

///|
/// Native-only helper for the standalone LSP binary: writes the version line
/// unbuffered to fd 1 and exits 0 (VER-02/D-02/D-07). Kept out of js/wasm
/// via #cfg — the version package is never part of the binding surface.
#cfg(any(target="native", target="llvm"))
pub fn print_and_exit(name : String) -> Unit {
  let line = version_line(name)
  let bytes = @utf8.encode(line)
  ignore(write_fd(1, bytes, bytes.length()))
  exit_process(0)
}

///|
#cfg(any(target="native", target="llvm"))
#borrow(ptr)
extern "c" fn write_fd(fd : Int, ptr : Bytes, count : Int) -> Int = "write"

///|
#cfg(any(target="native", target="llvm"))
extern "c" fn exit_process(code : Int) = "exit"

///|
test "product_version_is_1_0_2" {
  assert_eq(product_version(), "1.0.3")
}

///|
test "version_line_format" {
  assert_eq(version_line("fathom-sql"), "fathom-sql 1.0.3\n")
  assert_eq(version_line("fathom-lsp"), "fathom-lsp 1.0.3\n")
}
