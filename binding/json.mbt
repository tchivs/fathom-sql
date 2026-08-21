///|
/// Versioned primitive serialization helpers for the Native/JS/Wasm boundary.
///
/// The schema deliberately carries source bytes once at the envelope root. CST
/// nodes contain only primitive fields and half-open UTF-8 byte spans; clients
/// must not infer editor coordinates from statement_offsets.
fn byte_array_json(bytes : Bytes) -> Json {
  let values : Array[Json] = []
  for byte in bytes {
    values.push(Json::number(byte.to_int().to_double()))
  }
  Json::array(values)
}

///|
fn node_json(node : @api.PrimitiveNode) -> Json {
  let children : Array[Json] = []
  for child in node.children {
    children.push(node_json(child))
  }
  {
    "kind": Json::string(node.kind),
    "start_byte": Json::number(node.start_byte.to_double()),
    "end_byte": Json::number(node.end_byte.to_double()),
    "text_len": Json::number(node.text_len.to_double()),
    "children": Json::array(children),
  }
}

///|
fn diagnostic_json(diagnostic : @api.PrimitiveDiagnostic) -> Json {
  {
    "severity": Json::string(diagnostic.severity),
    "code": Json::string(diagnostic.code),
    "message": Json::string(diagnostic.message),
    "expected_class": Json::string(diagnostic.expected_class),
    "start_byte": Json::number(diagnostic.start_byte.to_double()),
    "end_byte": Json::number(diagnostic.end_byte.to_double()),
    "statement_id": Json::number(diagnostic.statement_id.to_double()),
  }
}

///|
fn format_diagnostic_json(diagnostic : @api.FormatDiagnostic) -> Json {
  {
    "severity": Json::string(diagnostic.severity),
    "code": Json::string(diagnostic.code),
    "message": Json::string(diagnostic.message),
    "expected_class": Json::string(diagnostic.expected_class),
    "start_byte": Json::number(diagnostic.start_byte.to_double()),
    "end_byte": Json::number(diagnostic.end_byte.to_double()),
    "statement_id": Json::number(diagnostic.statement_id.to_double()),
  }
}

///|
fn diagnostics_json(diagnostics : Array[@api.PrimitiveDiagnostic]) -> Json {
  let values : Array[Json] = []
  for diagnostic in diagnostics {
    values.push(diagnostic_json(diagnostic))
  }
  Json::array(values)
}

///|
fn format_diagnostics_json(diagnostics : Array[@api.FormatDiagnostic]) -> Json {
  let values : Array[Json] = []
  for diagnostic in diagnostics {
    values.push(format_diagnostic_json(diagnostic))
  }
  Json::array(values)
}

///|
fn offsets_json(offsets : Array[Int]) -> Json {
  let values : Array[Json] = []
  for offset in offsets {
    values.push(Json::number(offset.to_double()))
  }
  Json::array(values)
}

///|
pub fn stringify(value : Json) -> String {
  value.stringify()
}

///|
/// Serialized lineage result envelope (LINE-01, D-07): the
/// fathom.lineage.v1 envelope carries the same dialect/profile/exact_release
/// selection metadata as the parse/format/lint envelopes (D-09 — consumers
/// must only compare lineage within the same selection), the source bytes,
/// and the resolved `edges` + honest `gaps` arrays (D-06 — strictly separate;
/// a gap is never a tagged edge). Edge/gap ordering is a public contract
/// (Pattern 6): document statement order -> SelectModel branch/CTE order ->
/// SelectItem order -> refs order; star expansion follows scope-entry order x
/// catalog column order (LinkedHashMap determinism). All spans are flattened
/// byte offsets serialized with `Json::number(to_double())` — safe below 2^53
/// (T-07-04-04).
pub fn lineage_result_json(
  source : Bytes,
  result : @api.LineageResult,
  dialect : String,
  profile : String,
  exact_release : String,
) -> String {
  let edges : Array[Json] = []
  for edge in result.edges {
    edges.push(
      Json::object({
        "source_name": Json::string(edge.source_name),
        "source_resolved_to": Json::string(edge.source_resolved_to),
        "source_start_byte": Json::number(edge.source_start_byte.to_double()),
        "source_end_byte": Json::number(edge.source_end_byte.to_double()),
        "target_name": Json::string(edge.target_name),
        "target_start_byte": Json::number(edge.target_start_byte.to_double()),
        "target_end_byte": Json::number(edge.target_end_byte.to_double()),
      }),
    )
  }
  let gaps : Array[Json] = []
  for gap in result.gaps {
    gaps.push(
      Json::object({
        "code": Json::string(gap.code),
        "message": Json::string(gap.message),
        "start_byte": Json::number(gap.start_byte.to_double()),
        "end_byte": Json::number(gap.end_byte.to_double()),
      }),
    )
  }
  stringify({
    "schema_version": Json::string(LINEAGE_SCHEMA_VERSION),
    "source_transport": Json::string(SOURCE_TRANSPORT),
    "dialect": Json::string(dialect),
    "profile": Json::string(profile),
    "exact_release": Json::string(exact_release),
    "source_bytes": byte_array_json(source),
    "source_byte_length": Json::number(source.length().to_double()),
    "edges": Json::array(edges),
    "gaps": Json::array(gaps),
  })
}
