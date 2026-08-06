/// Backend-neutral, syntax-only completion over the parser's token and profile
/// tables. No catalog, analyzer, filesystem, or host runtime is consulted.

pub(all) struct CompletionItem {
  pub label : String
  pub detail : String
  pub start_byte : Int
  pub end_byte : Int
  pub new_text : String
}

pub(all) struct CompletionList {
  pub is_incomplete : Bool
  pub items : Array[CompletionItem]
}

pub enum CompletionError {
  UnknownDialect(dialect_id~ : String)
  UnknownProfile(profile_id~ : String)
  InvalidCursor(cursor~ : Int, source_length~ : Int)
  InvalidSource
  InputTooLarge
} derive(Eq, @debug.Debug)

const MAX_CANDIDATES : Int = 32

fn bytes_equal_ci(left : Bytes, right : Bytes) -> Bool {
  if left.length() > right.length() { return false }
  let mut index = 0
  while index < left.length() {
    let left_byte = left[index].to_int()
    let right_byte = right[index].to_int()
    let folded_left = if left_byte >= 97 && left_byte <= 122 { left_byte - 32 } else { left_byte }
    let folded_right = if right_byte >= 97 && right_byte <= 122 { right_byte - 32 } else { right_byte }
    if folded_left != folded_right { return false }
    index = index + 1
  }
  true
}

fn word_is(word : Bytes, expected : Bytes) -> Bool {
  word.length() == expected.length() && bytes_equal_ci(word, expected)
}

/// The dialect dimension of candidate gating (DIALECT-02): Doris rows are
/// gated by the Doris profile (D-15), Flink has no rows and no profiles in
/// Phase 9 — nothing is allowed.
fn profile_allows(context : @dialect.DialectContext, entry : @dialect.KeywordEntry) -> Bool {
  match context.dialect {
    @dialect.Dialect::Doris => {
      match @dialect.DorisProfile::from_id(context.profile_id) {
        Some(profile) => {
          match entry.introduced_profile {
            "2.1" => true
            "3.x" => match profile { @dialect.DorisProfile::V2_1 => false; _ => true }
            "4.x" => profile is @dialect.DorisProfile::V4_X
            _ => false
          }
        }
        None => false
      }
    }
    @dialect.Dialect::Flink => false
  }
}

fn source_word(source : @source.SourceText, token : @token.Token) -> Bytes? {
  source.slice(token.span)
}

fn significant(token : @token.Token) -> Bool {
  !token.is_trivia() && token.kind is @token.TokenKind::Identifier
}

fn completion_context(source : @source.SourceText, stream : @token.TokenStream, anchor : Int) -> String {
  let mut last : Bytes = b""
  let mut previous : Bytes = b""
  for token in stream.tokens {
    if token.span.end_byte > anchor || token.is_trivia() { continue }
    let raw = match source_word(source, token) { Some(raw) => raw; None => continue }
    if raw == b";" {
      last = b""
      previous = b""
    } else if significant(token) || token.kind is @token.TokenKind::Symbol {
      previous = last
      last = raw
    }
  }
  if last.length() == 0 { "statement-start" }
  else if word_is(last, b"SELECT") { "select" }
  else if word_is(last, b"FROM") || word_is(last, b"JOIN") { "from" }
  else if word_is(last, b"WHERE") { "where" }
  else if word_is(last, b"BY") && word_is(previous, b"GROUP") { "group-by" }
  else if word_is(last, b"BY") && word_is(previous, b"ORDER") { "order-by" }
  else if word_is(last, b"ON") { "join-on" }
  else if word_is(last, b"GROUP") { "group-by" }
  else if word_is(last, b"ORDER") { "order-by" }
  else { "general" }
}

fn context_accepts(context : String, dialect_context : @dialect.DialectContext, word : Bytes) -> Bool {
  match context {
    "select" => (@dialect.is_clause_keyword(dialect_context, word) && !word_is(word, b"SELECT") && !word_is(word, b"WITH") && !word_is(word, b"JOIN")) || word_is(word, b"DISTINCT") || word_is(word, b"ALL")
    "from" => word_is(word, b"JOIN") || word_is(word, b"WHERE") || word_is(word, b"GROUP") ||
      word_is(word, b"ORDER") || word_is(word, b"LIMIT") || word_is(word, b"UNION") || word_is(word, b"ON")
    "where" => word_is(word, b"AND") || word_is(word, b"OR") || word_is(word, b"GROUP") ||
      word_is(word, b"HAVING") || word_is(word, b"ORDER") || word_is(word, b"LIMIT") || word_is(word, b"QUALIFY")
    "group-by" => word_is(word, b"HAVING") || word_is(word, b"ORDER") || word_is(word, b"LIMIT") || word_is(word, b"QUALIFY")
    "order-by" => word_is(word, b"ASC") || word_is(word, b"DESC") || word_is(word, b"LIMIT")
    "join-on" => word_is(word, b"ON") || word_is(word, b"USING") || word_is(word, b"JOIN") ||
      word_is(word, b"WHERE") || word_is(word, b"GROUP") || word_is(word, b"ORDER")
    _ => @dialect.is_clause_keyword(dialect_context, word)
  }
}

fn context_preferred(context : String, word : Bytes) -> Bool {
  match context {
    "select" => word_is(word, b"FROM")
    "from" => word_is(word, b"JOIN")
    "where" => word_is(word, b"AND")
    _ => false
  }
}

fn prefix_matches(word : Bytes, prefix : Bytes) -> Bool {
  bytes_equal_ci(prefix, word)
}
// Candidate ordering is a stable two-pass preference over classification rows.

fn cursor_replacement(source : @source.SourceText, stream : @token.TokenStream, cursor : Int) -> (Int, Bytes) {
  for token in stream.tokens {
    if token.kind is @token.TokenKind::Identifier && cursor > token.span.start_byte && cursor <= token.span.end_byte {
      let prefix = match source.span(token.span.start_byte, cursor) {
        Ok(span) => match source.slice(span) { Some(raw) => raw; None => b"" }
        Err(_) => b""
      }
      return (token.span.start_byte, prefix)
    }
  }
  (cursor, b"")
}

/// Return bounded syntax-only candidates for an editor snapshot at a UTF-8
/// byte cursor. The LSP adapter converts the resulting byte range to UTF-16.
pub fn complete(raw : Bytes, dialect_id : String, profile_id : String, cursor_byte : Int) -> Result[CompletionList, CompletionError] {
  // Explicit dialect selection first (DIALECT-01, Pitfall 6), then the
  // profile for that dialect; flink profiles are all rejected in Phase 9.
  let dialect = match dialect_id {
    "doris" => @dialect.Dialect::Doris
    "flink" => @dialect.Dialect::Flink
    _ => return Err(UnknownDialect(dialect_id~))
  }
  let dialect_context : @dialect.DialectContext = match dialect {
    @dialect.Dialect::Doris => {
      match @dialect.DorisProfile::from_id(profile_id) {
        Some(profile) => {
          let metadata = profile.metadata()
          { dialect: dialect, profile_id: profile_id, exact_release: metadata.exact_release, feature_introduction: metadata.feature_introduction }
        }
        None => return Err(UnknownProfile(profile_id~))
      }
    }
    @dialect.Dialect::Flink => return Err(UnknownProfile(profile_id~))
  }
  if cursor_byte < 0 || cursor_byte > raw.length() {
    return Err(InvalidCursor(cursor=cursor_byte, source_length=raw.length()))
  }
  let source = match @source.SourceText::new(raw) {
    Ok(source) => source
    Err(_) => return Err(InputTooLarge)
  }
  // Parse in editor mode so completion observes the same bounded recovery path
  // as diagnostics. Candidate selection itself remains token/context based.
  ignore(@api.parse_with_ids(raw, dialect_id, profile_id, "editor"))
  let stream = @lexer.lex(source, dialect_context)
  let (replacement_start, prefix) = cursor_replacement(source, stream, cursor_byte)
  let context = completion_context(source, stream, replacement_start)
  let items : Array[CompletionItem] = []
  let entries = @dialect.classification_entries(dialect_context)
  let mut priority = 0
  while priority < 2 && items.length() < MAX_CANDIDATES {
    let mut index = 0
    while index < entries.length() && items.length() < MAX_CANDIDATES {
      let entry = entries[index]
      let preferred = context_preferred(context, entry.word)
      let in_priority = (priority == 0 && preferred) || (priority == 1 && !preferred)
      if in_priority && profile_allows(dialect_context, entry) && context_accepts(context, dialect_context, entry.word) &&
        prefix_matches(entry.word, prefix) {
        let label = @utf8.decode_lossy(entry.word)
        items.push({
          label: label,
          detail: "Doris syntax keyword",
          start_byte: replacement_start,
          end_byte: cursor_byte,
          new_text: label,
        })
      }
      index = index + 1
    }
    priority = priority + 1
  }
  Ok({ is_incomplete: false, items: items })
}
