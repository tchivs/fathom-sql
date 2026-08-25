/// Doris dialect policy: released profile metadata, feature gates, and the
/// Doris keyword rows. All Doris type names are preserved verbatim per D-05
/// (DorisProfile/DorisFeature/ValidatedProfileContext/ProfileMetadata/
/// FeatureMetadata) — only their file location moves from token/ to dialect/
/// (09-RESEARCH.md §4.1). The feature-gate diagnostic code is FATHOM-PARSE-006
/// (D-10: legacy code prefixes -> FATHOM-).

///|
/// Explicit released Doris profile metadata and source-backed lexical leaves.
pub(all) enum DorisProfile {
  V2_1
  V3_X
  V4_X
} derive(Eq, @debug.Debug)

///|
pub struct ProfileMetadata {
  id : String
  release_family : String
  exact_release : String
  feature_introduction : String
  // Kept as the compact, parser-facing label for existing consumers.
  introduced_features : String
}

///|
pub enum ProfileMetadataError {
  UnknownProfile(profile_id~ : String)
  ProfileMetadataMismatch(
    profile_id~ : String,
    expected_release~ : String,
    actual_release~ : String,
    expected_feature_introduction~ : String,
    actual_feature_introduction~ : String
  )
  UnsupportedFeatureIntroduction(feature_introduction~ : String)
} derive(Eq, @debug.Debug)

///|
pub struct ValidatedProfileContext {
  profile : DorisProfile
  metadata : ProfileMetadata
}

///|
pub fn ValidatedProfileContext::canonical(
  profile : DorisProfile,
) -> ValidatedProfileContext {
  { profile, metadata: profile.metadata() }
}

///|
pub fn ValidatedProfileContext::profile(
  self : ValidatedProfileContext,
) -> DorisProfile {
  self.profile
}

///|
pub fn ValidatedProfileContext::metadata(
  self : ValidatedProfileContext,
) -> ProfileMetadata {
  self.metadata
}

///|
pub fn ValidatedProfileContext::supports(
  self : ValidatedProfileContext,
  feature : DorisFeature,
) -> Bool {
  self.profile.supports(feature) &&
  self.metadata.feature_introduction ==
  self.profile.metadata().feature_introduction
}

///|
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
  if feature_introduction != "2.1 baseline SELECT; DML/DDL released" &&
    feature_introduction !=
    "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY" &&
    feature_introduction !=
    "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT" {
    return Err(UnsupportedFeatureIntroduction(feature_introduction~))
  }
  if exact_release != metadata.exact_release ||
    feature_introduction != metadata.feature_introduction {
    return Err(
      ProfileMetadataMismatch(
        profile_id~,
        expected_release=metadata.exact_release,
        actual_release=exact_release,
        expected_feature_introduction=metadata.feature_introduction,
        actual_feature_introduction=feature_introduction,
      ),
    )
  }
  Ok({ profile, metadata })
}

///|
pub fn DorisProfile::validate_metadata(
  self : DorisProfile,
  metadata : ProfileMetadata,
) -> Result[ValidatedProfileContext, ProfileMetadataError] {
  if metadata.feature_introduction != "2.1 baseline SELECT; DML/DDL released" &&
    metadata.feature_introduction !=
    "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY" &&
    metadata.feature_introduction !=
    "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT" {
    return Err(
      UnsupportedFeatureIntroduction(
        feature_introduction=metadata.feature_introduction,
      ),
    )
  }
  let expected = self.metadata()
  if metadata.id != expected.id ||
    metadata.release_family != expected.release_family ||
    metadata.exact_release != expected.exact_release ||
    metadata.feature_introduction != expected.feature_introduction ||
    metadata.introduced_features != expected.introduced_features {
    return Err(
      ProfileMetadataMismatch(
        profile_id=expected.id,
        expected_release=expected.exact_release,
        actual_release=metadata.exact_release,
        expected_feature_introduction=expected.feature_introduction,
        actual_feature_introduction=metadata.feature_introduction,
      ),
    )
  }
  Ok({ profile: self, metadata: expected })
}

///|
pub fn DorisProfile::metadata(self : DorisProfile) -> ProfileMetadata {
  match self {
    V2_1 =>
      {
        id: "2.1",
        release_family: "2.1",
        exact_release: "2.1",
        feature_introduction: "2.1 baseline SELECT; DML/DDL released",
        introduced_features: "baseline",
      }
    V3_X =>
      {
        id: "3.x",
        release_family: "3.x",
        exact_release: "3.x",
        feature_introduction: "2.1 baseline SELECT; DML/DDL released; 3.x window and QUALIFY",
        introduced_features: "3.x-released",
      }
    V4_X =>
      {
        id: "4.x",
        release_family: "4.x",
        exact_release: "4.x",
        feature_introduction: "2.1 baseline SELECT; DML/DDL released; 4.x released SELECT",
        introduced_features: "4.x-released",
      }
  }
}

///|
pub(all) enum DorisFeature {
  Qualify
  Tablet
  PartitionStar
  MergeInto
  OrderByClause
  BucketsAuto
  AutoPartitionBy
} derive(Eq, @debug.Debug)

///|
pub struct FeatureMetadata {
  name : String
  keyword : Bytes
  introduced_profile : String
  diagnostic_code : String
  recovery_kind : String
  diagnostic_message : String
}

///|
pub fn DorisFeature::metadata(self : DorisFeature) -> FeatureMetadata {
  match self {
    Qualify =>
      {
        name: "QUALIFY",
        keyword: b"QUALIFY",
        introduced_profile: "3.x",
        diagnostic_code: "FATHOM-PARSE-006",
        recovery_kind: "error",
        diagnostic_message: "feature QUALIFY is unavailable in the selected released profile",
      }
    Tablet =>
      {
        name: "TABLET",
        keyword: b"TABLET",
        introduced_profile: "3.x",
        diagnostic_code: "FATHOM-PARSE-006",
        recovery_kind: "error",
        diagnostic_message: "feature TABLET is unavailable in the selected released profile",
      }
    PartitionStar =>
      {
        name: "PARTITION (*)",
        keyword: b"PARTITION",
        introduced_profile: "2.1",
        diagnostic_code: "FATHOM-PARSE-006",
        recovery_kind: "error",
        diagnostic_message: "feature PARTITION (*) is unavailable in the selected released profile",
      }
    MergeInto =>
      {
        name: "MERGE",
        keyword: b"MERGE",
        introduced_profile: "4.x",
        diagnostic_code: "FATHOM-PARSE-006",
        recovery_kind: "error",
        diagnostic_message: "feature MERGE is unavailable in the selected released profile",
      }
    OrderByClause =>
      {
        name: "CREATE TABLE ORDER BY",
        keyword: b"ORDER",
        introduced_profile: "4.x",
        diagnostic_code: "FATHOM-PARSE-006",
        recovery_kind: "error",
        diagnostic_message: "feature CREATE TABLE ORDER BY is unavailable in the selected released profile (docs note: since 4.1.0)",
      }
    BucketsAuto =>
      {
        name: "BUCKETS AUTO",
        keyword: b"BUCKETS",
        introduced_profile: "2.1",
        diagnostic_code: "FATHOM-PARSE-006",
        recovery_kind: "error",
        diagnostic_message: "feature BUCKETS AUTO is unavailable in the selected released profile (documented since 2.1 per the released CREATE TABLE grammar)",
      }
    AutoPartitionBy =>
      {
        name: "AUTO PARTITION BY",
        keyword: b"AUTO",
        introduced_profile: "2.1",
        diagnostic_code: "FATHOM-PARSE-006",
        recovery_kind: "error",
        diagnostic_message: "feature AUTO PARTITION BY is unavailable in the selected released profile (documented since 2.1 per the released CREATE TABLE grammar)",
      }
  }
}

///|
fn profile_rank(profile : DorisProfile) -> Int {
  match profile {
    V2_1 => 0
    V3_X => 1
    V4_X => 2
  }
}

///|
fn introduced_rank(profile_id : String) -> Int? {
  match profile_id {
    "2.1" => Some(0)
    "3.x" => Some(1)
    "4.x" => Some(2)
    _ => None
  }
}

///|
pub fn DorisProfile::supports(
  self : DorisProfile,
  feature : DorisFeature,
) -> Bool {
  match introduced_rank(feature.metadata().introduced_profile) {
    Some(required) => profile_rank(self) >= required
    None => false
  }
}

///|
pub fn DorisProfile::id(self : DorisProfile) -> String {
  self.metadata().id
}

///|
pub fn DorisProfile::from_id(id : String) -> DorisProfile? {
  match id {
    "2.1" => Some(V2_1)
    "3.x" => Some(V3_X)
    "4.x" => Some(V4_X)
    _ => None
  }
}

///|
let reserved_keywords_url = "https://doris.apache.org/docs/4.x/sql-manual/basic-element/reserved-keywords/"

///|
let select_docs_url = "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-query/SELECT/"

///|
let insert_docs_url = "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/"

///|
let merge_docs_url = "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/MERGE-INTO/"

///|
let create_table_docs_url = "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/table/CREATE-TABLE/"

///|
let create_view_docs_url = "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/view/CREATE-VIEW/"

///|
let create_mv_docs_url = "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/sync-materialized-view/CREATE-MATERIALIZED-VIEW/"

///|
let async_mv_docs_url = "https://doris.apache.org/docs/4.x/sql-manual/sql-statements/table-and-view/async-materialized-view/CREATE-ASYNC-MATERIALIZED-VIEW/"

///|
/// The word-level classification gate and the DorisFeature production gate are
/// distinct layers (D-14/D-15): classification_of / is_reserved_word gate
/// identifier acceptance (a reserved word requires backticks), while
/// DorisFeature + ValidatedProfileContext::supports gate production
/// availability and emit FATHOM-PARSE-006. A word can be reserved since 2.1
/// while a clause using it is feature-gated (ORDER -> DorisFeature::
/// OrderByClause "4.x" for CREATE TABLE ORDER BY), and MERGE carries "4.x"
/// introduced_profile metadata AND a DorisFeature row. introduced_profile on a
/// row is audit metadata; only DorisFeature gates reject version-invalid
/// syntax.
let doris_classification_rows : Array[KeywordEntry] = [
  // Phase 1 reserved words, re-encoded with byte-identical answers. The
  // official reserved-keyword list (identical across 2.1/3.x/4.x) is the
  // classification authority (D-13); words absent from it but reserved by the
  // Phase 1 clause/operator contract (QUALIFY, WINDOW, RECURSIVE, GROUPING,
  // ROLLUP, DISTINCTROW, SAMPLE, OVER, NULLS, FIRST, LAST, GROUPS, OFFSET)
  // stay reserved so is_reserved_word / is_unquoted_identifier behavior is
  // preserved exactly.
  {
    word: b"SELECT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"WITH",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"FROM",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"WHERE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"GROUP",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"HAVING",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"ORDER",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"LIMIT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"JOIN",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"UNION",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"QUALIFY",
    classification: Reserved,
    introduced_profile: "3.x",
    source: select_docs_url +
    " (QUALIFY clause; DorisFeature::Qualify 3.x; absent from the official reserved list)",
  },
  {
    word: b"WINDOW",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"INTO",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"ON",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"USING",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"AS",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"AND",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"OR",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"NOT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"IN",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"LIKE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"REGEXP",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"IS",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"NULL",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"TRUE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"FALSE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"RECURSIVE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"BY",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"GROUPING",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"SETS",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"ROLLUP",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"CUBE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"ALL",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"DISTINCT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"DISTINCTROW",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"EXCEPT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"INNER",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"LEFT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"RIGHT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"FULL",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"CROSS",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"NATURAL",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"OUTER",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"PARTITION",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"SAMPLE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"TABLESAMPLE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"OVER",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"ASC",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"DESC",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"NULLS",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"FIRST",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"LAST",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"ROWS",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"RANGE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"GROUPS",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"BETWEEN",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"CURRENT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"ROW",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"UNBOUNDED",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"PRECEDING",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"FOLLOWING",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"OFFSET",
    classification: Reserved,
    introduced_profile: "2.1",
    source: select_docs_url +
    " (Phase 1 clause/recovery word; absent from the official reserved list)",
  },
  {
    word: b"OUTFILE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  // TABLET stays contextual per Phase 1 behavior and D-14, even though the
  // official reserved list contains it; the TABLET clause is 3.x-gated via
  // DorisFeature::Tablet.
  {
    word: b"TABLET",
    classification: Contextual,
    introduced_profile: "3.x",
    source: select_docs_url +
    " (TABLET clause; DorisFeature::Tablet 3.x; contextual per D-14 although listed in the official reserved keywords)",
  },
  // DML/DDL production words from 02-01/02-02 (D-09..D-12, D-13 authority).
  // Words on the official reserved list are Reserved; ordinary grammar words
  // absent from it are NonReserved (usable as unquoted identifiers, Pitfall
  // 2); clause-only words are Contextual. MERGE is Reserved with a "4.x"
  // introduced_profile per D-09 (4.x-doc-only statement) plus a DorisFeature
  // row; MATCHED is a 4.x clause-only word (MERGE). introduced_profile here is
  // word-level audit metadata — production availability is enforced by
  // DorisFeature gates (D-15).
  {
    word: b"INSERT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"UPDATE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"DELETE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"OVERWRITE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"VALUES",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"SET",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"WHEN",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"THEN",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"DEFAULT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"CREATE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"ALTER",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"DROP",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"TRUNCATE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"LOAD",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"EXPORT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"GRANT",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"REVOKE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"TABLE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"INDEX",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"IF",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"EXISTS",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"KEY",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"DUPLICATE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"UNIQUE",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"DISTRIBUTED",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"AUTO",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"LIST",
    classification: Reserved,
    introduced_profile: "2.1",
    source: reserved_keywords_url,
  },
  {
    word: b"MERGE",
    classification: Reserved,
    introduced_profile: "4.x",
    source: merge_docs_url +
    " (4.x-doc-only statement per D-09; not in the official reserved list; DorisFeature::MergeInto 4.x)",
  },
  {
    word: b"BUCKETS",
    classification: NonReserved,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (DISTRIBUTED BY ... BUCKETS clause; absent from the official reserved list)",
  },
  {
    word: b"PROPERTIES",
    classification: NonReserved,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (PROPERTIES clause; absent from the official reserved list)",
  },
  {
    word: b"COMMENT",
    classification: NonReserved,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (COMMENT clause; absent from the official reserved list)",
  },
  {
    word: b"AGGREGATE",
    classification: NonReserved,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (AGGREGATE key model; absent from the official reserved list)",
  },
  {
    word: b"ENGINE",
    classification: NonReserved,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (ENGINE = clause; absent from the official reserved list)",
  },
  {
    word: b"VIEW",
    classification: NonReserved,
    introduced_profile: "2.1",
    source: create_view_docs_url +
    " (CREATE VIEW statement; absent from the official reserved list)",
  },
  {
    word: b"MATCHED",
    classification: Contextual,
    introduced_profile: "4.x",
    source: merge_docs_url +
    " (WHEN MATCHED clause; absent from the official reserved list)",
  },
  {
    word: b"LABEL",
    classification: Contextual,
    introduced_profile: "2.1",
    source: insert_docs_url +
    " (WITH LABEL clause; absent from the official reserved list)",
  },
  {
    word: b"HASH",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (DISTRIBUTED BY HASH clause; absent from the official reserved list)",
  },
  {
    word: b"RANDOM",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (DISTRIBUTED BY RANDOM clause; absent from the official reserved list)",
  },
  {
    word: b"LESS",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (VALUES LESS THAN clause; absent from the official reserved list)",
  },
  {
    word: b"THAN",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (VALUES LESS THAN clause; absent from the official reserved list)",
  },
  {
    word: b"PARTITIONS",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (partition-list clause; absent from the official reserved list)",
  },
  {
    word: b"TEMPORARY",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (CREATE TEMPORARY TABLE modifier; absent from the official reserved list)",
  },
  {
    word: b"EXTERNAL",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (CREATE EXTERNAL TABLE modifier; absent from the official reserved list)",
  },
  {
    word: b"MATERIALIZED",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_mv_docs_url +
    " (CREATE MATERIALIZED VIEW word; absent from the official reserved list)",
  },
  {
    word: b"AUTO_INCREMENT",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (column option; absent from the official reserved list)",
  },
  {
    word: b"CURRENT_TIMESTAMP",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (DEFAULT/ON UPDATE value; absent from the official reserved list)",
  },
  {
    word: b"GENERATED",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (generated-column word; absent from the official reserved list)",
  },
  {
    word: b"ALWAYS",
    classification: Contextual,
    introduced_profile: "2.1",
    source: create_table_docs_url +
    " (generated-column word; absent from the official reserved list)",
  },
  // Async materialized view clause words (02-04 A2 closure): the released
  // 2.1/3.x/4.x "CREATE ASYNC MATERIALIZED VIEW" pages document CREATE
  // MATERIALIZED VIEW with BUILD/REFRESH clauses; these words are absent from
  // the official reserved list and are clause-only (Contextual), so they stay
  // usable as unquoted identifiers (Pitfall 2).
  {
    word: b"ASYNC",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (async materialized view prefix; absent from the official reserved list)",
  },
  {
    word: b"BUILD",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (BUILD IMMEDIATE/DEFERRED clause; absent from the official reserved list)",
  },
  {
    word: b"REFRESH",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (REFRESH COMPLETE/AUTO clause; absent from the official reserved list)",
  },
  {
    word: b"IMMEDIATE",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (BUILD IMMEDIATE mode; absent from the official reserved list)",
  },
  {
    word: b"DEFERRED",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (BUILD DEFERRED mode; absent from the official reserved list)",
  },
  {
    word: b"COMPLETE",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (REFRESH COMPLETE method; absent from the official reserved list)",
  },
  {
    word: b"MANUAL",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (ON MANUAL trigger; absent from the official reserved list)",
  },
  {
    word: b"SCHEDULE",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (ON SCHEDULE trigger; absent from the official reserved list)",
  },
  {
    word: b"EVERY",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (ON SCHEDULE EVERY interval; absent from the official reserved list)",
  },
  {
    word: b"STARTS",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (STARTS start-time clause; absent from the official reserved list)",
  },
  {
    word: b"COMMIT",
    classification: Contextual,
    introduced_profile: "2.1",
    source: async_mv_docs_url +
    " (ON COMMIT trigger; absent from the official reserved list)",
  },
]

///|
test "profiles_are_explicit_and_have_no_generic_fallback" {
  assert_eq(DorisProfile::from_id("2.1"), Some(V2_1))
  assert_eq(DorisProfile::from_id("3.x"), Some(V3_X))
  assert_eq(DorisProfile::from_id("4.x"), Some(V4_X))
  assert_true(DorisProfile::from_id("mysql") is None)
  assert_eq(V2_1.metadata().id, "2.1")
  assert_eq(V3_X.metadata().release_family, "3.x")
  assert_eq(V4_X.metadata().introduced_features, "4.x-released")
}

///|
test "profile_metadata_is_stable_and_complete" {
  let profiles = [V2_1, V3_X, V4_X]
  assert_eq(profiles.length(), 3)
  assert_eq(profiles.map(p => p.id()), ["2.1", "3.x", "4.x"])
  assert_eq(V2_1.metadata().introduced_features, "baseline")
  assert_eq(V3_X.metadata().introduced_features, "3.x-released")
  assert_eq(V4_X.metadata().introduced_features, "4.x-released")
}

///|
test "released_feature_metadata_and_profile_gates_are_stable" {
  let qualify = DorisFeature::Qualify.metadata()
  let tablet = DorisFeature::Tablet.metadata()
  assert_eq(qualify.name, "QUALIFY")
  assert_eq(qualify.keyword, b"QUALIFY")
  assert_eq(qualify.introduced_profile, "3.x")
  assert_eq(qualify.diagnostic_code, "FATHOM-PARSE-006")
  assert_eq(qualify.recovery_kind, "error")
  assert_eq(
    qualify.diagnostic_message,
    "feature QUALIFY is unavailable in the selected released profile",
  )
  assert_eq(tablet.name, "TABLET")
  assert_eq(tablet.keyword, b"TABLET")
  assert_eq(tablet.introduced_profile, "3.x")
  assert_eq(tablet.diagnostic_code, "FATHOM-PARSE-006")
  assert_eq(tablet.recovery_kind, "error")
  assert_true(!V2_1.supports(DorisFeature::Qualify))
  assert_true(V3_X.supports(DorisFeature::Qualify))
  assert_true(!V2_1.supports(DorisFeature::Tablet))
  assert_true(V3_X.supports(DorisFeature::Tablet))
  assert_true(V4_X.supports(DorisFeature::Tablet))
}

///|
test "doris_classification_rows_match_the_frozen_v1_table" {
  // 116 rows, content byte-identical to the v1 classification_rows (D-08:
  // the baseline gate pins acceptance; this test pins the row inventory).
  let rows = doris_classification_rows
  assert_eq(rows.length(), 116)
  let spot = [
    b"SELECT", b"WITH", b"QUALIFY", b"TABLET", b"DISTRIBUTED", b"MERGE", b"VIEW",
    b"DEFAULT", b"BUCKETS", b"PROPERTIES",
  ]
  for word in spot {
    let found = classification_of(doris_test_context(), word)
    assert_true(found is Some(_))
  }
}
