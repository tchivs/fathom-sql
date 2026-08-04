/// Native LSP Content-Length framing. Header and body limits are checked before
/// allocation; stdout contains only framed JSON-RPC payloads.

pub const MAX_FRAME_BYTES : Int = 8 * 1024 * 1024
pub const MAX_HEADER_BYTES : Int = 16 * 1024

pub enum FrameError {
  MissingHeader
  InvalidHeader
  MissingContentLength
  InvalidContentLength
  FrameTooLarge(length~ : Int)
  TruncatedFrame
} derive(Eq, @debug.Debug)

fn header_end(bytes : Bytes) -> Int? {
  if bytes.length() < 4 { return None }
  let mut index = 0
  while index + 3 < bytes.length() {
    if bytes[index].to_int() == 13 && bytes[index + 1].to_int() == 10 && bytes[index + 2].to_int() == 13 && bytes[index + 3].to_int() == 10 {
      return Some(index)
    }
    index = index + 1
  }
  None
}

fn decimal(bytes : Bytes, start : Int, end : Int) -> Int? {
  if start >= end { return None }
  let mut index = start
  let mut value = 0
  while index < end {
    let digit = bytes[index].to_int() - 48
    if digit < 0 || digit > 9 { return None }
    if value > (MAX_FRAME_BYTES / 10) { return None }
    value = value * 10 + digit
    index = index + 1
  }
  Some(value)
}

fn content_length(header : Bytes) -> Result[Int, FrameError] {
  let mut line_start = 0
  let mut found : Int? = None
  let length = header.length()
  while line_start < length {
    let mut line_end = line_start
    while line_end < length && !(line_end + 1 < length && header[line_end].to_int() == 13 && header[line_end + 1].to_int() == 10) {
      line_end = line_end + 1
    }
    let prefix = b"Content-Length: "
    if line_end - line_start >= prefix.length() {
      let mut same = true
      let mut index = 0
      while index < prefix.length() {
        if header[line_start + index].to_int() != prefix[index].to_int() { same = false }
        index = index + 1
      }
      if same {
        found = decimal(header, line_start + prefix.length(), line_end)
      }
    }
    if line_end + 1 >= length { break }
    line_start = line_end + 2
  }
  match found {
    Some(length) => Ok(length)
    None => Err(MissingContentLength)
  }
}

pub fn decode_frame(frame : Bytes) -> Result[Bytes, FrameError] {
  guard frame.length() <= MAX_HEADER_BYTES + MAX_FRAME_BYTES + 4 else {
    return Err(FrameTooLarge(length=frame.length()))
  }
  let separator = match header_end(frame) {
    Some(value) => value
    None => return Err(MissingHeader)
  }
  if separator > MAX_HEADER_BYTES { return Err(InvalidHeader) }
  let header = frame[0:separator].to_owned()
  let body_start = separator + 4
  let body_length = match content_length(header) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if body_length < 0 || body_length > MAX_FRAME_BYTES {
    return Err(FrameTooLarge(length=body_length))
  }
  if frame.length() != body_start + body_length { return Err(TruncatedFrame) }
  Ok(frame[body_start:body_start + body_length].to_owned())
}

pub fn frame(body : Bytes) -> Bytes {
  @utf8.encode("Content-Length: \{body.length()}\r\n\r\n") + body
}

#cfg(any(target="native", target="llvm"))
#borrow(ptr)
extern "c" fn read_fd(fd : Int, ptr : Bytes, count : Int) -> Int = "read"

#cfg(any(target="native", target="llvm"))
#borrow(ptr)
extern "c" fn write_fd(fd : Int, ptr : Bytes, count : Int) -> Int = "write"

fn read_exact(count : Int) -> Bytes? {
  let out = @buffer.Buffer::Buffer(size_hint=count)
  let chunk = Bytes::new(4096)
  let mut remaining = count
  while remaining > 0 {
    let request = if remaining < 4096 { remaining } else { 4096 }
    let got = read_fd(0, chunk, request)
    if got <= 0 { return None }
    out.write_bytes(chunk[0:got])
    remaining = remaining - got
  }
  Some(out.to_bytes())
}

pub fn read_frame() -> Result[Bytes?, FrameError] {
  let header = @buffer.Buffer::Buffer(size_hint=256)
  let one = Bytes::new(1)
  let mut found = false
  while !found && header.to_bytes().length() <= MAX_HEADER_BYTES {
    let got = read_fd(0, one, 1)
    if got <= 0 { return Ok(None) }
    header.write_bytes(one[0:1])
    let bytes = header.to_bytes()
    let length = bytes.length()
    if length >= 4 && bytes[length - 4].to_int() == 13 && bytes[length - 3].to_int() == 10 && bytes[length - 2].to_int() == 13 && bytes[length - 1].to_int() == 10 {
      found = true
    }
  }
  if !found { return Err(InvalidHeader) }
  let header_bytes = header.to_bytes()
  let separator = header_bytes.length() - 4
  let body_length = match content_length(header_bytes[0:separator].to_owned()) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if body_length < 0 || body_length > MAX_FRAME_BYTES { return Err(FrameTooLarge(length=body_length)) }
  match read_exact(body_length) {
    Some(body) => Ok(Some(body))
    None => Err(TruncatedFrame)
  }
}

pub fn write_frame(body : Bytes) -> Unit {
  let output = frame(body)
  let mut offset = 0
  while offset < output.length() {
    let written = write_fd(1, output, output.length() - offset)
    if written <= 0 { return }
    offset = offset + written
  }
}
