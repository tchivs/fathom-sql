/// Lossless token data structures. The dialect/profile/keyword policy moved to
/// the dialect/ package (D-05 keeps the Doris type names; their home is now
/// dialect/doris.mbt). Tokens carry the immutable DialectContext they were
/// lexed under (research migration rows 8-9); classification queries are
/// imported from dialect by callers — token re-exports nothing (Pitfall 1).

pub(all) enum TokenKind {
  Whitespace
  Newline
  Comment
  Bom
  Identifier
  Number
  Quoted
  StringLiteral
  Symbol
  Unknown
  Error
}

pub(all) struct Token {
  pub kind : TokenKind
  pub span : @source.Span
  pub context : @dialect.DialectContext
  pub diagnostic_code : String?
}

pub fn Token::raw(self : Token, source : @source.SourceText) -> Bytes? {
  source.slice(self.span)
}

pub fn Token::is_trivia(self : Token) -> Bool {
  match self.kind {
    Whitespace | Newline | Comment => true
    _ => false
  }
}

pub fn Token::is_error(self : Token) -> Bool {
  self.kind is Error
}

pub(all) struct TokenStream {
  pub source : @source.SourceText
  pub context : @dialect.DialectContext
  pub tokens : Array[Token]
  pub truncated_at : Int?
}

pub fn TokenStream::length(self : TokenStream) -> Int {
  self.tokens.length()
}

pub fn TokenStream::at(self : TokenStream, index : Int) -> Token? {
  self.tokens.get(index)
}

pub fn TokenStream::raw(self : TokenStream, index : Int) -> Bytes? {
  match self.at(index) {
    Some(token) => token.raw(self.source)
    None => None
  }
}
