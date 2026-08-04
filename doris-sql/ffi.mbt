/// Native-only libc FFI for the doris-sql CLI (D-37). This is the ONLY file in
/// the module allowed to touch libc — formatter/ and api/ stay backend-neutral
/// (Wasm/JS targets, CLAUDE.md single-core constraint).
///
/// Toolchain rules (probe-verified on moon 0.1.20260724, 03-RESEARCH Common
/// Operations 1-2):
/// - Native String is UTF-16 (moonbit_string_t = uint16_t*), so every libc
///   string is an @utf8.encode'd Bytes — raw Strings must never reach fopen.
/// - #borrow(param) on pointer FFI params is mandatory (unannotated_ffi build
///   error otherwise) and must precede the extern declaration.
/// - There is no @ffi package and no core fs package on this toolchain; these
///   POSIX symbols are the only available IO surface.

#cfg(any(target="native", target="llvm"))
#borrow(ptr)
pub extern "c" fn read_fd(fd : Int, ptr : Bytes, count : Int) -> Int = "read"

#cfg(any(target="native", target="llvm"))
#borrow(ptr)
pub extern "c" fn write_fd(fd : Int, ptr : Bytes, count : Int) -> Int = "write"

#cfg(any(target="native", target="llvm"))
pub extern "c" fn exit_process(code : Int) = "exit"

#cfg(any(target="native", target="llvm"))
#borrow(path, mode)
pub extern "c" fn open_file(path : Bytes, mode : Bytes) -> Int64 = "fopen"

#cfg(any(target="native", target="llvm"))
#borrow(ptr)
pub extern "c" fn read_file_chunk(ptr : Bytes, size : Int, count : Int, handle : Int64) -> Int = "fread"

#cfg(any(target="native", target="llvm"))
#borrow(ptr)
pub extern "c" fn write_file_chunk(ptr : Bytes, size : Int, count : Int, handle : Int64) -> Int = "fwrite"

#cfg(any(target="native", target="llvm"))
pub extern "c" fn close_file(handle : Int64) -> Int = "fclose"

/// Read a whole file into bytes; None when fopen fails (missing/unreadable).
/// Bounded chunked reads (4096 bytes), stops at EOF. fopen returns 0L on
/// failure — that maps to None -> CLI exit 2 (T-03-19 mitigation).
///
/// CR-01 (memory safety): fopen scans the path for a NUL terminator, so the
/// buffer must be NUL-terminated. @utf8.encode allocates exactly the encoded
/// length with no terminator (core/encoding/utf8/encode_nonjs.mbt:116-134),
/// so an unterminated buffer would make fopen read past the heap allocation
/// — undefined behavior. The explicit b"\x00" makes the over-read impossible.
pub fn read_file(path : String) -> Bytes? {
  let path_bytes = @utf8.encode(path) + b"\x00"
  let handle = open_file(path_bytes, b"rb")
  if handle == 0L { return None }
  let out = @buffer.Buffer::Buffer(size_hint=4096)
  let chunk = Bytes::new(4096)
  let mut more = true
  while more {
    let got = read_file_chunk(chunk, 1, 4096, handle)
    if got <= 0 {
      more = false
    } else {
      out.write_bytes(chunk[0:got])
      if got < 4096 { more = false }
    }
  }
  ignore(close_file(handle))
  Some(out.to_bytes())
}

/// Read all of stdin (fd 0) into bytes; bounded chunked reads, EOF stops.
pub fn read_stdin() -> Bytes {
  let out = @buffer.Buffer::Buffer(size_hint=4096)
  let chunk = Bytes::new(4096)
  let mut more = true
  while more {
    let got = read_fd(0, chunk, 4096)
    if got <= 0 {
      more = false
    } else {
      out.write_bytes(chunk[0:got])
      if got < 4096 { more = false }
    }
  }
  out.to_bytes()
}
