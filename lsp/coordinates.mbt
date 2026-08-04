/// LSP-facing coordinate facade. Binding owns the only byte/UTF-16
/// conversion; this module keeps source construction and whole-document ranges
/// at the protocol edge.

pub fn source(raw : Bytes) -> @source.SourceText? {
  match @source.SourceText::new(raw) {
    Ok(source) => Some(source)
    Err(_) => None
  }
}

pub fn full_document_range(raw : Bytes) -> @binding.Range? {
  let source = match source(raw) {
    Some(source) => source
    None => return None
  }
  match @binding.span_to_range(source, 0, raw.length()) {
    Ok(range) => Some(range)
    Err(_) => None
  }
}

pub fn diagnostic_range(raw : Bytes, start_byte : Int, end_byte : Int) -> @binding.Range? {
  let source = match source(raw) {
    Some(source) => source
    None => return None
  }
  match @binding.span_to_range(source, start_byte, end_byte) {
    Ok(range) => Some(range)
    Err(_) => None
  }
}
