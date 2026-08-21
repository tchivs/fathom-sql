///|
/// Token-level keyword rewrite (D-28): the classification table is the single
/// keyword authority (D-13/D-14, token.mbt:450-460) — the formatter keeps no
/// second keyword list. Every row's canonical word is UPPERCASE by
/// construction. Only SourceToken leaf bytes reach this function; trivia and
/// comments never do (D-36).
pub fn rewrite_keyword(context : @dialect.DialectContext, raw : Bytes) -> Bytes {
  match @dialect.classification_of(context, raw) {
    Some(entry) => entry.word
    None => raw
  }
}

///|
/// Case-selected keyword rewrite (D-26 keyword_case dimension): Upper renders
/// the canonical classification word (D-29), Lower renders its ASCII case-fold
/// (SQL keywords are ASCII; every classification word is uppercase by
/// construction). None is not a KeywordCase value, so every word is rewritten
/// to one of the two canonical spellings. Identifiers, quoted names, strings,
/// comments, and hints are never rewritten: classification_of only matches a
/// bare unquoted word, so any token whose raw bytes are not a plain word
/// (quoted `SELECT`, string literals, punctuation) passes through unchanged.
pub fn rewrite_keyword_case(
  context : @dialect.DialectContext,
  raw : Bytes,
  case : KeywordCase,
) -> Bytes {
  match case {
    KeywordCase::Upper => rewrite_keyword(context, raw)
    KeywordCase::Lower =>
      match @dialect.classification_of(context, raw) {
        Some(entry) => ascii_case_fold(entry.word)
        None => raw
      }
  }
}

///|
/// ASCII A-Z -> a-z byte-wise fold (the same helper shape as
/// keyword_test.mbt:38-47). Classification words are ASCII by construction.
fn ascii_case_fold(raw : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let mut index = 0
  while index < raw.length() {
    let byte = raw[index].to_int()
    let folded = if byte >= 65 && byte <= 90 { byte + 32 } else { byte }
    out.push(folded.to_byte())
    index = index + 1
  }
  Bytes::from_array(out)
}
