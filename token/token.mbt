/// Explicit released Doris profile metadata and source-backed lexical leaves.

pub(all) enum DorisProfile {
  V2_1
  V3_X
  V4_X
} derive(Eq, @debug.Debug)

pub struct ProfileMetadata {
  pub id : String
  pub release_family : String
  pub exact_release : String
  pub feature_introduction : String
  // Kept as the compact, parser-facing label for existing consumers.
  pub introduced_features : String
}

pub enum ProfileMetadataError {
  UnknownProfile(profile_id~ : String)
  ProfileMetadataMismatch(
    profile_id~ : String,
    expected_release~ : String,
    actual_release~ : String,
    expected_feature_introduction~ : String,
    actual_feature_introduction~ : String,
  )
  UnsupportedFeatureIntroduction(feature_introduction~ : String)
} derive(Eq, @debug.Debug)

pub struct ValidatedProfileContext {
  profile : DorisProfile
  metadata : ProfileMetadata
}

pub fn ValidatedProfileContext::canonical(profile : DorisProfile) -> ValidatedProfileContext {
  { profile: profile, metadata: profile.metadata() }
}

pub fn ValidatedProfileContext::profile(self : ValidatedProfileContext) -> DorisProfile {
  self.profile
}

pub fn ValidatedProfileContext::metadata(self : ValidatedProfileContext) -> ProfileMetadata {
  self.metadata
}

pub fn ValidatedProfileContext::supports(
  self : ValidatedProfileContext,
  feature : DorisFeature,
) -> Bool {
  self.profile.supports(feature) &&
    self.metadata.feature_introduction == self.profile.metadata().feature_introduction
}

pub fn ProfileMetadata::for_manifest(
  profile_id : String,
  exact_release : String,
  feature_introduction : String,
) -> Result[ValidatedProfileContext, ProfileMetadataError] {
  let profile = match DorisProfile::from_id(profile_id) {
    Some(profile) => profile
    None => return Err(UnknownProfile(profile_id~))
  }
  let metadata = profile.metadata()
  if feature_introduction != "2.1 baseline SELECT" &&
    feature_introduction != "2.1 baseline; 3.x window and QUALIFY" &&
    feature_introduction != "2.1 baseline; 4.x released SELECT" {
    return Err(UnsupportedFeatureIntroduction(feature_introduction=feature_introduction))
  }
  if exact_release != metadata.exact_release || feature_introduction != metadata.feature_introduction {
    return Err(ProfileMetadataMismatch(
      profile_id=profile_id,
      expected_release=metadata.exact_release,
      actual_release=exact_release,
      expected_feature_introduction=metadata.feature_introduction,
      actual_feature_introduction=feature_introduction,
    ))
  }
  Ok({ profile: profile, metadata: metadata })
}

pub fn DorisProfile::validate_metadata(
  self : DorisProfile,
  metadata : ProfileMetadata,
) -> Result[ValidatedProfileContext, ProfileMetadataError] {
  if metadata.feature_introduction != "2.1 baseline SELECT" &&
    metadata.feature_introduction != "2.1 baseline; 3.x window and QUALIFY" &&
    metadata.feature_introduction != "2.1 baseline; 4.x released SELECT" {
    return Err(UnsupportedFeatureIntroduction(feature_introduction=metadata.feature_introduction))
  }
  let expected = self.metadata()
  if metadata.id != expected.id || metadata.release_family != expected.release_family ||
    metadata.exact_release != expected.exact_release ||
    metadata.feature_introduction != expected.feature_introduction ||
    metadata.introduced_features != expected.introduced_features {
    return Err(ProfileMetadataMismatch(
      profile_id=expected.id,
      expected_release=expected.exact_release,
      actual_release=metadata.exact_release,
      expected_feature_introduction=expected.feature_introduction,
      actual_feature_introduction=metadata.feature_introduction,
    ))
  }
  Ok({ profile: self, metadata: expected })
}
 
 pub fn DorisProfile::metadata(self : DorisProfile) -> ProfileMetadata {
   match self {
    V2_1 => {
      id: "2.1",
      release_family: "2.1",
      exact_release: "2.1",
      feature_introduction: "2.1 baseline SELECT",
      introduced_features: "baseline",
    }
    V3_X => {
      id: "3.x",
      release_family: "3.x",
      exact_release: "3.x",
      feature_introduction: "2.1 baseline; 3.x window and QUALIFY",
      introduced_features: "3.x-released",
    }
    V4_X => {
      id: "4.x",
      release_family: "4.x",
      exact_release: "4.x",
      feature_introduction: "2.1 baseline; 4.x released SELECT",
      introduced_features: "4.x-released",
    }
   }
 }

pub(all) enum DorisFeature {
  Qualify
  Tablet
  PartitionStar
  MergeInto
  OrderByClause
  BucketsAuto
  AutoPartitionBy
} derive(Eq, @debug.Debug)

pub struct FeatureMetadata {
  pub name : String
  pub keyword : Bytes
  pub introduced_profile : String
  pub diagnostic_code : String
  pub recovery_kind : String
  pub diagnostic_message : String
}

pub fn DorisFeature::metadata(self : DorisFeature) -> FeatureMetadata {
  match self {
    Qualify => {
      name: "QUALIFY",
      keyword: b"QUALIFY",
      introduced_profile: "3.x",
      diagnostic_code: "DORIS-PARSE-006",
      recovery_kind: "error",
      diagnostic_message: "feature QUALIFY is unavailable in the selected released profile",
    }
    Tablet => {
      name: "TABLET",
      keyword: b"TABLET",
      introduced_profile: "3.x",
      diagnostic_code: "DORIS-PARSE-006",
      recovery_kind: "error",
      diagnostic_message: "feature TABLET is unavailable in the selected released profile",
    }
    PartitionStar => {
      name: "PARTITION (*)",
      keyword: b"PARTITION",
      introduced_profile: "2.1",
      diagnostic_code: "DORIS-PARSE-006",
      recovery_kind: "error",
      diagnostic_message: "feature PARTITION (*) is unavailable in the selected released profile",
    }
    MergeInto => {
      name: "MERGE",
      keyword: b"MERGE",
      introduced_profile: "4.x",
      diagnostic_code: "DORIS-PARSE-006",
      recovery_kind: "error",
      diagnostic_message: "feature MERGE is unavailable in the selected released profile",
    }
    OrderByClause => {
      name: "CREATE TABLE ORDER BY",
      keyword: b"ORDER",
      introduced_profile: "4.x",
      diagnostic_code: "DORIS-PARSE-006",
      recovery_kind: "error",
      diagnostic_message: "feature CREATE TABLE ORDER BY is unavailable in the selected released profile (docs note: since 4.1.0)",
    }
    BucketsAuto => {
      name: "BUCKETS AUTO",
      keyword: b"BUCKETS",
      introduced_profile: "3.x",
      diagnostic_code: "DORIS-PARSE-006",
      recovery_kind: "error",
      diagnostic_message: "feature BUCKETS AUTO is unavailable in the selected released profile (assumed introduction: 3.x)",
    }
    AutoPartitionBy => {
      name: "AUTO PARTITION BY",
      keyword: b"AUTO",
      introduced_profile: "2.1",
      diagnostic_code: "DORIS-PARSE-006",
      recovery_kind: "error",
      diagnostic_message: "feature AUTO PARTITION BY is unavailable in the selected released profile (assumed introduction: 2.1)",
    }
  }
}

fn profile_rank(profile : DorisProfile) -> Int {
  match profile {
    V2_1 => 0
    V3_X => 1
    V4_X => 2
  }
}

fn introduced_rank(profile_id : String) -> Int? {
  match profile_id {
    "2.1" => Some(0)
    "3.x" => Some(1)
    "4.x" => Some(2)
    _ => None
  }
}

pub fn DorisProfile::supports(self : DorisProfile, feature : DorisFeature) -> Bool {
  match introduced_rank(feature.metadata().introduced_profile) {
    Some(required) => profile_rank(self) >= required
    None => false
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

fn token_bytes_equal_ci(actual : Bytes, expected : Bytes) -> Bool {
  if actual.length() != expected.length() {
    false
  } else {
    let mut index = 0
    let mut equal = true
    while index < actual.length() {
      let left = actual[index].to_int()
      let right = expected[index].to_int()
      let folded_left = if left >= 97 && left <= 122 { left - 32 } else { left }
      let folded_right = if right >= 97 && right <= 122 { right - 32 } else { right }
      if folded_left != folded_right { equal = false }
      index = index + 1
    }
    equal
  }
}

/// Released-profile clause boundaries shared by parser contexts.
pub fn is_clause_keyword(raw : Bytes) -> Bool {
  token_bytes_equal_ci(raw, b"SELECT") || token_bytes_equal_ci(raw, b"WITH") ||
    token_bytes_equal_ci(raw, b"FROM") || token_bytes_equal_ci(raw, b"WHERE") ||
    token_bytes_equal_ci(raw, b"GROUP") || token_bytes_equal_ci(raw, b"HAVING") ||
    token_bytes_equal_ci(raw, b"ORDER") || token_bytes_equal_ci(raw, b"LIMIT") ||
    token_bytes_equal_ci(raw, b"JOIN") || token_bytes_equal_ci(raw, b"UNION") ||
    token_bytes_equal_ci(raw, b"QUALIFY") || token_bytes_equal_ci(raw, b"WINDOW") ||
    token_bytes_equal_ci(raw, b"INTO") || token_bytes_equal_ci(raw, b"ON") ||
    token_bytes_equal_ci(raw, b"USING")
}

/// Released-profile reserved and operator words. TABLET remains contextual.
pub fn is_reserved_word(raw : Bytes) -> Bool {
  is_clause_keyword(raw) ||
    token_bytes_equal_ci(raw, b"AS") || token_bytes_equal_ci(raw, b"AND") ||
    token_bytes_equal_ci(raw, b"OR") || token_bytes_equal_ci(raw, b"NOT") ||
    token_bytes_equal_ci(raw, b"IN") || token_bytes_equal_ci(raw, b"LIKE") ||
    token_bytes_equal_ci(raw, b"REGEXP") || token_bytes_equal_ci(raw, b"IS") ||
    token_bytes_equal_ci(raw, b"NULL") || token_bytes_equal_ci(raw, b"TRUE") ||
    token_bytes_equal_ci(raw, b"FALSE") || token_bytes_equal_ci(raw, b"RECURSIVE") ||
    token_bytes_equal_ci(raw, b"BY") || token_bytes_equal_ci(raw, b"GROUPING") ||
    token_bytes_equal_ci(raw, b"SETS") || token_bytes_equal_ci(raw, b"ROLLUP") ||
    token_bytes_equal_ci(raw, b"CUBE") || token_bytes_equal_ci(raw, b"ALL") ||
    token_bytes_equal_ci(raw, b"DISTINCT") || token_bytes_equal_ci(raw, b"DISTINCTROW") ||
    token_bytes_equal_ci(raw, b"EXCEPT") || token_bytes_equal_ci(raw, b"INNER") ||
    token_bytes_equal_ci(raw, b"LEFT") || token_bytes_equal_ci(raw, b"RIGHT") ||
    token_bytes_equal_ci(raw, b"FULL") || token_bytes_equal_ci(raw, b"CROSS") ||
    token_bytes_equal_ci(raw, b"NATURAL") || token_bytes_equal_ci(raw, b"OUTER") ||
    token_bytes_equal_ci(raw, b"PARTITION") || token_bytes_equal_ci(raw, b"SAMPLE") ||
    token_bytes_equal_ci(raw, b"TABLESAMPLE") || token_bytes_equal_ci(raw, b"OVER") ||
    token_bytes_equal_ci(raw, b"ASC") || token_bytes_equal_ci(raw, b"DESC") ||
    token_bytes_equal_ci(raw, b"NULLS") || token_bytes_equal_ci(raw, b"FIRST") ||
    token_bytes_equal_ci(raw, b"LAST") || token_bytes_equal_ci(raw, b"ROWS") ||
    token_bytes_equal_ci(raw, b"RANGE") || token_bytes_equal_ci(raw, b"GROUPS") ||
    token_bytes_equal_ci(raw, b"BETWEEN") || token_bytes_equal_ci(raw, b"CURRENT") ||
    token_bytes_equal_ci(raw, b"ROW") || token_bytes_equal_ci(raw, b"UNBOUNDED") ||
    token_bytes_equal_ci(raw, b"PRECEDING") || token_bytes_equal_ci(raw, b"FOLLOWING") ||
    token_bytes_equal_ci(raw, b"OFFSET") || token_bytes_equal_ci(raw, b"OUTFILE")
}

pub fn is_unquoted_identifier(raw : Bytes) -> Bool {
  !is_reserved_word(raw)
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
  let qualify = DorisFeature::Qualify.metadata()
  let tablet = DorisFeature::Tablet.metadata()
  assert_eq(qualify.name, "QUALIFY")
  assert_eq(qualify.keyword, b"QUALIFY")
  assert_eq(qualify.introduced_profile, "3.x")
  assert_eq(qualify.diagnostic_code, "DORIS-PARSE-006")
  assert_eq(qualify.recovery_kind, "error")
  assert_eq(qualify.diagnostic_message, "feature QUALIFY is unavailable in the selected released profile")
  assert_eq(tablet.name, "TABLET")
  assert_eq(tablet.keyword, b"TABLET")
  assert_eq(tablet.introduced_profile, "3.x")
  assert_eq(tablet.diagnostic_code, "DORIS-PARSE-006")
  assert_eq(tablet.recovery_kind, "error")
  assert_true(!V2_1.supports(DorisFeature::Qualify))
  assert_true(V3_X.supports(DorisFeature::Qualify))
  assert_true(!V2_1.supports(DorisFeature::Tablet))
  assert_true(V3_X.supports(DorisFeature::Tablet))
  assert_true(V4_X.supports(DorisFeature::Tablet))
}
test "released_identifier_classification_is_case_insensitive_and_contextual" {
  for raw in [b"SELECT", b"with", b"As", b"AND", b"or", b"FROM", b"window"] {
    assert_true(is_reserved_word(raw))
    assert_true(!is_unquoted_identifier(raw))
  }
  assert_true(is_clause_keyword(b"SeLeCt"))
  assert_true(is_clause_keyword(b"FrOm"))
  assert_true(!is_clause_keyword(b"AND"))
  assert_true(!is_reserved_word(b"tablet"))
  assert_true(is_unquoted_identifier(b"tablet"))
  assert_true(is_unquoted_identifier(b"user_name"))
}