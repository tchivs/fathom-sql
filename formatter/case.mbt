/// Token-level keyword rewrite (D-28): the classification table is the single
/// keyword authority (D-13/D-14, token.mbt:450-460) — the formatter keeps no
/// second keyword list. Every row's canonical word is UPPERCASE by
/// construction. Only SourceToken leaf bytes reach this function; trivia and
/// comments never do (D-36).
pub fn rewrite_keyword(raw : Bytes) -> Bytes {
  match @token.classification_of(raw) {
    Some(entry) => entry.word
    None => raw
  }
}
