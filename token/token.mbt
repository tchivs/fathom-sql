/// Explicit released Doris profile metadata and source-backed lexical leaves.

pub(all) enum DorisProfile {
  V2_1
  V3_X
  V4_X
} derive(Eq, @debug.Debug)

pub struct ProfileMetadata {
  pub id : String
  pub release_family : String
  pub introduced_features : String
}

pub fn DorisProfile::metadata(self : DorisProfile) -> ProfileMetadata {
  match self {
    V2_1 => { id: "2.1", release_family: "2.1", introduced_features: "baseline" }
    V3_X => { id: "3.x", release_family: "3.x", introduced_features: "3.x-released" }
    V4_X => { id: "4.x", release_family: "4.x", introduced_features: "4.x-released" }
  }
}

pub(all) enum DorisFeature {
  Qualify
  Tablet
} derive(Eq, @debug.Debug)

pub struct FeatureMetadata {
  pub name : String
  pub introduced_profile : String
}

pub fn DorisFeature::metadata(self : DorisFeature) -> FeatureMetadata {
  match self {
    Qualify => { name: "QUALIFY", introduced_profile: "3.x" }
    Tablet => { name: "TABLET", introduced_profile: "3.x" }
  }
}

pub fn DorisProfile::supports(self : DorisProfile, feature : DorisFeature) -> Bool {
  match self {
    V2_1 => match feature { Qualify => false; Tablet => false }
    V3_X => true
    V4_X => true
  }
}

pub fn DorisProfile::id(self : DorisProfile) -> String {
  self.metadata().id
}

pub fn DorisProfile::from_id(id : String) -> DorisProfile? {
  match id {
    "2.1" => Some(V2_1)
    "3.x" => Some(V3_X)
    "4.x" => Some(V4_X)
    _ => None
  }
}

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
  pub profile : DorisProfile
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
  pub profile : DorisProfile
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

test "profiles_are_explicit_and_have_no_generic_fallback" {
  assert_eq(DorisProfile::from_id("2.1"), Some(V2_1))
  assert_eq(DorisProfile::from_id("3.x"), Some(V3_X))
  assert_eq(DorisProfile::from_id("4.x"), Some(V4_X))
  assert_true(DorisProfile::from_id("mysql") is None)
  assert_eq(V2_1.metadata().id, "2.1")
  assert_eq(V3_X.metadata().release_family, "3.x")
  assert_eq(V4_X.metadata().introduced_features, "4.x-released")
}
test "profile_metadata_is_stable_and_complete" {
  let profiles = [V2_1, V3_X, V4_X]
  assert_eq(profiles.length(), 3)
  assert_eq(profiles.map(p => p.id()), ["2.1", "3.x", "4.x"])
  assert_eq(V2_1.metadata().introduced_features, "baseline")
  assert_eq(V3_X.metadata().introduced_features, "3.x-released")
  assert_eq(V4_X.metadata().introduced_features, "4.x-released")
}


test "released_feature_metadata_and_profile_gates_are_stable" {
  assert_eq(DorisFeature::Qualify.metadata().name, "QUALIFY")
  assert_eq(DorisFeature::Tablet.metadata().introduced_profile, "3.x")
  assert_true(!V2_1.supports(DorisFeature::Qualify))
  assert_true(V3_X.supports(DorisFeature::Qualify))
  assert_true(V4_X.supports(DorisFeature::Tablet))
}