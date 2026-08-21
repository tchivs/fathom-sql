///|
/// Native LSP Content-Length framing. Header and body limits are checked before
/// allocation; stdout contains only framed JSON-RPC payloads.
pub const MAX_FRAME_BYTES : Int = 8 * 1024 * 1024

///|
pub const MAX_HEADER_BYTES : Int = 16 * 1024

///|
pub enum FrameError {
  MissingHeader
  InvalidHeader
  MissingContentLength
  InvalidContentLength
  FrameTooLarge(length~ : Int)
  TruncatedFrame
} derive(Eq, @debug.Debug)

///|
fn header_end(bytes : Bytes) -> Int? {
  if bytes.length() < 4 {
    return None
  }
  let mut index = 0
  while index + 3 < bytes.length() {
    if bytes[index].to_int() == 13 &&
      bytes[index + 1].to_int() == 10 &&
      bytes[index + 2].to_int() == 13 &&
      bytes[index + 3].to_int() == 10 {
      return Some(index)
    }
    index = index + 1
  }
  None
}

///|
fn decimal(bytes : Bytes, start : Int, end : Int) -> Int? {
  if start >= end {
    return None
  }
  let mut index = start
  let mut value = 0
  while index < end {
    let digit = bytes[index].to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    if value > MAX_FRAME_BYTES / 10 {
      return None
    }
    value = value * 10 + digit
    index = index + 1
  }
  Some(value)
}

///|
fn content_length(header : Bytes) -> Result[Int, FrameError] {
  let mut line_start = 0
  let mut found : Int? = None
  let length = header.length()
  while line_start < length {
    let mut line_end = line_start
    while line_end < length &&
          !(line_end + 1 < length &&
          header[line_end].to_int() == 13 &&
          header[line_end + 1].to_int() == 10) {
      line_end = line_end + 1
    }
    let prefix = b"Content-Length: "
    if line_end - line_start >= prefix.length() {
      let mut same = true
      let mut index = 0
      while index < prefix.length() {
        if header[line_start + index].to_int() != prefix[index].to_int() {
          same = false
        }
        index = index + 1
      }
      if same {
        found = decimal(header, line_start + prefix.length(), line_end)
      }
    }
    if line_end + 1 >= length {
      break
    }
    line_start = line_end + 2
  }
  match found {
    Some(length) => Ok(length)
    None => Err(MissingContentLength)
  }
}

///|
pub fn decode_frame(frame : Bytes) -> Result[Bytes, FrameError] {
  guard frame.length() <= MAX_HEADER_BYTES + MAX_FRAME_BYTES + 4 else {
    return Err(FrameTooLarge(length=frame.length()))
  }
  let separator = match header_end(frame) {
    Some(value) => value
    None => return Err(MissingHeader)
  }
  if separator > MAX_HEADER_BYTES {
    return Err(InvalidHeader)
  }
  let header = frame[0:separator].to_owned()
  let body_start = separator + 4
  let body_length = match content_length(header) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if body_length < 0 || body_length > MAX_FRAME_BYTES {
    return Err(FrameTooLarge(length=body_length))
  }
  if frame.length() != body_start + body_length {
    return Err(TruncatedFrame)
  }
  Ok(frame[body_start:body_start + body_length].to_owned())
}

///|
pub fn frame(body : Bytes) -> Bytes {
  @utf8.encode("Content-Length: \{body.length()}\r\n\r\n") + body
}

///|
#cfg(any(target="native", target="llvm"))
#borrow(ptr)
extern "c" fn read_fd(fd : Int, ptr : Bytes, count : Int) -> Int = "read"

///|
#cfg(any(target="native", target="llvm"))
#borrow(ptr)
extern "c" fn write_fd(fd : Int, ptr : Bytes, count : Int) -> Int = "write"

///|
fn read_exact(count : Int, prefix : Bytes, prefix_n : Int) -> Bytes? {
  let out = @buffer.Buffer::Buffer(size_hint=count)
  let mut remaining = count
  if prefix_n > 0 {
    let take = if prefix_n < count { prefix_n } else { count }
    out.write_bytes(prefix[0:take])
    remaining = count - take
  }
  let chunk = Bytes::new(4096)
  while remaining > 0 {
    let request = if remaining < 4096 { remaining } else { 4096 }
    let got = read_fd(0, chunk, request)
    if got <= 0 {
      return None
    }
    out.write_bytes(chunk[0:got])
    remaining = remaining - got
  }
  Some(out.to_bytes())
}

///|
/// End offset (exclusive) of the first `\r\n\r\n` in `bytes`, or `None`.
fn first_terminator_end(bytes : Bytes) -> Int? {
  let mut e = 4
  while e <= bytes.length() {
    if bytes[e - 4].to_int() == 13 &&
      bytes[e - 3].to_int() == 10 &&
      bytes[e - 2].to_int() == 13 &&
      bytes[e - 1].to_int() == 10 {
      return Some(e)
    }
    e = e + 1
  }
  None
}

///|
/// End offset (exclusive) of the first header terminator given the bytes read
/// in previous chunks (`head`) and the latest chunk read, including a
/// terminator that straddles the head/chunk boundary; `None` if no terminator
/// is complete yet. This mirrors the original byte-at-a-time detection: the
/// first terminator wins, so a header is never over-consumed into the body.
fn header_end_in(head : Bytes, chunk : Bytes) -> Int? {
  let h = head.length()
  let terminator = b"\r\n\r\n"
  // Terminator split across the boundary: head provides k bytes, chunk 4-k.
  let mut k = 1
  while k < 4 {
    if h >= k && chunk.length() >= 4 - k {
      if head[h - k:h].to_owned() == terminator[0:k].to_owned() &&
        chunk[0:4 - k].to_owned() == terminator[k:4].to_owned() {
        return Some(h + 4 - k)
      }
    }
    k = k + 1
  }
  // Terminator fully inside the chunk.
  let mut c = 0
  while c + 3 < chunk.length() {
    if chunk[c].to_int() == 13 &&
      chunk[c + 1].to_int() == 10 &&
      chunk[c + 2].to_int() == 13 &&
      chunk[c + 3].to_int() == 10 {
      return Some(h + c + 4)
    }
    c = c + 1
  }
  None
}

///|
/// Pushback for bytes read from stdin past the end of the current frame.
/// Chunked header reads can over-read into the body and, under client
/// pipelining, into the next frame; those bytes must survive across
/// `read_frame` calls exactly as the original byte-at-a-time reader left
/// them in the pipe.
pub struct FrameSource {
  pub mut pending : Bytes
}

///|
pub fn FrameSource::new() -> FrameSource {
  { pending: Bytes::new(0) }
}

///|
pub fn read_frame(source : FrameSource) -> Result[Bytes?, FrameError] {
  let header = @buffer.Buffer::Buffer(size_hint=256)
  let mut total = 0
  let mut leftover = Bytes::new(0)
  let mut leftover_n = 0
  let mut found = false
  // Bytes pushed back from the previous frame's over-read begin the next
  // frame; they may already contain a complete header (plus a body prefix).
  if source.pending.length() > 0 {
    let pend = source.pending
    source.pending = Bytes::new(0)
    match first_terminator_end(pend) {
      Some(e) => {
        header.write_bytes(pend[0:e])
        total = e
        leftover = pend[e:pend.length()].to_owned()
        leftover_n = pend.length() - e
        found = true
      }
      None => {
        header.write_bytes(pend)
        total = pend.length()
      }
    }
  }
  let chunk = Bytes::new(4096)
  while !found {
    if total > MAX_HEADER_BYTES {
      break
    }
    // Never read past the historical byte-at-a-time boundary (16 KB + 1).
    let allowed = MAX_HEADER_BYTES + 1 - total
    let request = if allowed < chunk.length() {
      allowed
    } else {
      chunk.length()
    }
    if request <= 0 {
      break
    }
    let got = read_fd(0, chunk, request)
    if got <= 0 {
      return Ok(None)
    }
    let head = header.to_bytes()
    match header_end_in(head, chunk[0:got].to_owned()) {
      Some(end) => {
        let consumed = end - total
        header.write_bytes(chunk[0:consumed])
        leftover = chunk[consumed:got].to_owned()
        leftover_n = got - consumed
        found = true
      }
      None => {
        header.write_bytes(chunk[0:got])
        total = total + got
      }
    }
  }
  if !found {
    return Err(InvalidHeader)
  }
  let header_bytes = header.to_bytes()
  let separator = header_bytes.length() - 4
  let body_length = match content_length(header_bytes[0:separator].to_owned()) {
    Ok(value) => value
    Err(error) => {
      if leftover_n > 0 {
        source.pending = leftover[0:leftover_n].to_owned()
      }
      return Err(error)
    }
  }
  if body_length < 0 || body_length > MAX_FRAME_BYTES {
    if leftover_n > 0 {
      source.pending = leftover[0:leftover_n].to_owned()
    }
    return Err(FrameTooLarge(length=body_length))
  }
  if leftover_n > body_length {
    source.pending = leftover[body_length:leftover_n].to_owned()
  }
  match read_exact(body_length, leftover, leftover_n) {
    Some(body) => Ok(Some(body))
    None => Err(TruncatedFrame)
  }
}

///|
/// Write `output` through `write` (called with a slice starting at the resume
/// offset), so a partial write can never re-send the frame prefix.
pub fn write_all(output : Bytes, write : (Bytes, Int) -> Int) -> Unit {
  let mut offset = 0
  while offset < output.length() {
    // Slicing copies the remainder, which is acceptable at this frequency.
    // Passing the whole buffer here would re-send bytes [0, offset) again.
    let written = write(output[offset:].to_owned(), output.length() - offset)
    if written <= 0 {
      return
    }
    offset = offset + written
  }
}

///|
pub fn write_frame(body : Bytes) -> Unit {
  let output = frame(body)
  write_all(output, fn(bytes, count) { write_fd(1, bytes, count) })
}
