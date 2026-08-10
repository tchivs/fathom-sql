/// LSP-facing coordinate facade. Binding owns the only byte/UTF-16
/// conversion; this module keeps source construction and whole-document ranges
/// at the protocol edge. Exactly ONE call site reaches binding's single
/// conversion (D-07, Don't Hand-Roll): both range helpers funnel through
/// `range_or_none` so no second UTF-16 converter can drift in.

pub fn source(raw : Bytes) -> @source.SourceText? {
  match @source.SourceText::new(raw) {
    Ok(source) => Some(source)
    Err(_) => None
  }
}

/// The single UTF-16 range conversion path (D-07): document-range and
/// diagnostic-range helpers both delegate here, so the LSP surface reuses
/// binding's converter exactly once — never a second converter.
fn range_or_none(source : @source.SourceText, start_byte : Int, end_byte : Int) -> @binding.Range? {
  match @binding.span_to_range(source, start_byte, end_byte) {
    Ok(range) => Some(range)
    Err(_) => None
  }
}

pub fn full_document_range(raw : Bytes) -> @binding.Range? {
  let source = match source(raw) {
    Some(source) => source
    None => return None
  }
  range_or_none(source, 0, raw.length())
}

pub fn diagnostic_range(raw : Bytes, start_byte : Int, end_byte : Int) -> @binding.Range? {
  let source = match source(raw) {
    Some(source) => source
    None => return None
  }
  range_or_none(source, start_byte, end_byte)
}
