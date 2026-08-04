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

fn diagnostics_json(diagnostics : Array[@api.PrimitiveDiagnostic]) -> Json {
  let values : Array[Json] = []
  for diagnostic in diagnostics {
    values.push(diagnostic_json(diagnostic))
  }
  Json::array(values)
}

fn format_diagnostics_json(diagnostics : Array[@api.FormatDiagnostic]) -> Json {
  let values : Array[Json] = []
  for diagnostic in diagnostics {
    values.push(format_diagnostic_json(diagnostic))
  }
  Json::array(values)
}

fn offsets_json(offsets : Array[Int]) -> Json {
  let values : Array[Json] = []
  for offset in offsets {
    values.push(Json::number(offset.to_double()))
  }
  Json::array(values)
}

pub fn stringify(value : Json) -> String {
  value.stringify()
}
