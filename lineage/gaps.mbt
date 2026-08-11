/// Gap derivation (D-06, SC2): honest reporting instead of fabricated edges.
///
/// Gaps are a strictly separate list from edges. Rules (Research Pattern 4,
/// Assumption A1):
///
/// | situation | gap code |
/// |-----------|----------|
/// | star/`table.*` item expanded to zero columns (no catalog column metadata; `expand_star` silently yields zero) | `requires-catalog` (self-checked in edges.mbt) |
/// | FROM/JOIN table reference unresolved and no catalog injected (cannot distinguish a missing table from an external view) | `requires-catalog` |
/// | FROM/JOIN table reference unresolved with a catalog injected | `unresolved-reference` |
/// | column/function reference unresolved (unknown-column/unknown-function/ambiguous-reference) | `unresolved-reference` (message preserved; ambiguous merged, Open Question 2) |
/// | statement body carries error/missing material | `requires-complete-parse` (D-33; reuses `has_error_missing`) |
///
/// `function-arity` and other analyzer codes are not lineage gaps and are
/// ignored here (no gap contract).

/// Maps analyzer diagnostics to lineage gaps (D-06 / Pattern 4).
///
/// `suppress_requires_catalog_tables` drops the unknown-table -> requires-
/// catalog gap when an unexpanded star in the same body already reported the
/// catalog need (the star gap is the single report for that body — avoids
/// noise on `SELECT * FROM t` without a catalog, Research Pattern 4).
fn map_diagnostic_gaps(
  diagnostics : Array[@analyzer.AnalysisDiagnostic],
  catalog_none : Bool,
  suppress_requires_catalog_tables : Bool,
) -> Array[LineageGap] {
  let gaps : Array[LineageGap] = []
  for diag in diagnostics {
    if diag.code == "requires-complete-parse" {
      gaps.push({
        code: GAP_REQUIRES_COMPLETE_PARSE,
        message: diag.message,
        start_byte: diag.start_byte,
        end_byte: diag.end_byte,
      })
    } else if diag.code == "unknown-table" {
      if catalog_none {
        // Cannot distinguish a missing table from an external view without
        // catalog metadata (A1): requires-catalog, not unresolved-reference.
        if !suppress_requires_catalog_tables {
          gaps.push({
            code: GAP_REQUIRES_CATALOG,
            message: diag.message,
            start_byte: diag.start_byte,
            end_byte: diag.end_byte,
          })
        }
      } else {
        gaps.push({
          code: GAP_UNRESOLVED_REFERENCE,
          message: diag.message,
          start_byte: diag.start_byte,
          end_byte: diag.end_byte,
        })
      }
    } else if diag.code == "unknown-column" || diag.code == "unknown-function" ||
      diag.code == "ambiguous-reference" {
      gaps.push({
        code: GAP_UNRESOLVED_REFERENCE,
        message: diag.message,
        start_byte: diag.start_byte,
        end_byte: diag.end_byte,
      })
    }
  }
  gaps
}
