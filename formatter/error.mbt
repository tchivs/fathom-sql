///|
/// Formatter error and result transport. FormatError mirrors ParseError
/// (api.mbt:51-62); FormatDiagnostic mirrors PrimitiveDiagnostic exactly
/// (api.mbt:149-157) so CLI/LSP consumers share one diagnostic shape.
pub enum FormatError {
  UnknownKeywordCase(keyword_case_id~ : String)
  UnknownCommaStyle(comma_style_id~ : String)
  UnknownNewlineStyle(newline_style_id~ : String)
  InvalidIndent(value~ : Int)
  InvalidLineWidth(value~ : Int)
  InvalidSyntaxTree
} derive(Eq, @debug.Debug)

///|
/// Primitive-shaped formatting diagnostic (mirrors PrimitiveDiagnostic field
/// shape, api.mbt:149-157). `pub(all)` so the api facade can construct it
/// cross-package (moon 0.1.20260724: literal construction requires all-public).
pub(all) struct FormatDiagnostic {
  severity : String
  code : String
  message : String
  expected_class : String
  start_byte : Int
  end_byte : Int
  statement_id : UInt
}

///|
/// One format operation result. D-33 refusal contract: accepted=false with
/// empty output and a FATHOM-FORMAT-001 diagnostic — never partial bytes.
/// statement_offsets carries the per-statement output byte offset (research
/// Open Question 5, Phase 4 ECO-02 range edits).
pub(all) struct FormatResult {
  accepted : Bool
  output : Bytes
  diagnostics : Array[FormatDiagnostic]
  statement_offsets : Array[Int]
}
