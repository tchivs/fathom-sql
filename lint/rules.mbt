/// Lint rule metadata and result records (LINT-01, D-02/D-04/D-06).
///
/// The registry is a PUBLIC contract: rule codes (FATHOM-LINT-0xx) freeze on
/// release (D-02 costly). Rule judgment logic lives in engine.mbt; the
/// registry only declares metadata. Analyzer-backed rules (004-007) are
/// enabled in the registry but only fire when a caller injects an
/// `AnalysisResult` (ANLY-01 — no catalog => silent skip).

/// Configurable per-rule severity (SQLFluff-style, D-04).
pub(all) enum LintSeverity {
  Error
  Warning
  Info
} derive(Eq, @debug.Debug)

/// String-id -> severity (mirror of KeywordCase::from_id, formatter/options.mbt
/// shape). Unknown ids return None so CLI/config errors surface as exit 2.
pub fn LintSeverity::from_id(id : String) -> LintSeverity? {
  match id {
    "error" => Some(Error)
    "warning" => Some(Warning)
    "info" => Some(Info)
    _ => None
  }
}

/// Per-rule enable/disable + severity override (D-04).
pub(all) enum RuleSetting {
  Disabled
  Severity(LintSeverity)
} derive(Eq, @debug.Debug)

/// One registry row (D-02): stable code, name, category, default severity,
/// fixable flag, profile applicability, enabled-by-default.
pub(all) struct LintRule {
  pub code : String
  pub name : String
  pub category : String
  pub default_severity : LintSeverity
  pub fixable : Bool
  pub applies_to : String
  pub enabled : Bool
} derive(Eq, @debug.Debug)

/// A minimal span edit produced by a fixable rule (D-03). Only ever replaces a
/// `SourceToken` leaf span; trivia are separate leaves and never touched.
pub(all) struct LintEdit {
  pub start_byte : Int
  pub end_byte : Int
  pub new_text : Bytes
} derive(Eq, @debug.Debug)

/// One lint finding. `severity` is the serialized string ("error"/"warning"/
/// "info"); `fix` is the candidate edit for fixable rules, None otherwise.
pub(all) struct LintFinding {
  pub code : String
  pub severity : String
  pub message : String
  pub start_byte : Int
  pub end_byte : Int
  pub statement_id : UInt
  pub fix : LintEdit?
} derive(Eq, @debug.Debug)
