/// Versioned primitive serialization helpers for the Native/JS/Wasm boundary.
///
/// The schema deliberately carries source bytes once at the envelope root. CST
/// nodes contain only primitive fields and half-open UTF-8 byte spans; clients
/// must not infer editor coordinates from statement_offsets.

fn byte_array_json(bytes : Bytes) -> @json.Json {
  let values : Array[@json.Json] = []
  for byte in bytes {
    values.push(@json.Json::number(byte.to_int().to_double()))
  }
  @json.Json::array(values)
}

fn node_json(node : @api.PrimitiveNode) -> @json.Json {
  let children : Array[@json.Json] = []
  for child in node.children {
    children.push(node_json(child))
  }
  {
    "kind": @json.Json::string(node.kind),
    "start_byte": @json.Json::number(node.start_byte.to_double()),
    "end_byte": @json.Json::number(node.end_byte.to_double()),
    "text_len": @json.Json::number(node.text_len.to_double()),
    "children": @json.Json::array(children),
  }
}

fn diagnostic_json(diagnostic : @api.PrimitiveDiagnostic) -> @json.Json {
  {
    "severity": @json.Json::string(diagnostic.severity),
    "code": @json.Json::string(diagnostic.code),
    "message": @json.Json::string(diagnostic.message),
    "expected_class": @json.Json::string(diagnostic.expected_class),
    "start_byte": @json.Json::number(diagnostic.start_byte.to_double()),
    "end_byte": @json.Json::number(diagnostic.end_byte.to_double()),
    "statement_id": @json.Json::number(diagnostic.statement_id.to_double()),
  }
}

fn format_diagnostic_json(diagnostic : @api.FormatDiagnostic) -> @json.Json {
  {
    "severity": @json.Json::string(diagnostic.severity),
    "code": @json.Json::string(diagnostic.code),
    "message": @json.Json::string(diagnostic.message),
    "expected_class": @json.Json::string(diagnostic.expected_class),
    "start_byte": @json.Json::number(diagnostic.start_byte.to_double()),
    "end_byte": @json.Json::number(diagnostic.end_byte.to_double()),
    "statement_id": @json.Json::number(diagnostic.statement_id.to_double()),
  }
}

fn diagnostics_json(diagnostics : Array[@api.PrimitiveDiagnostic]) -> @json.Json {
  let values : Array[@json.Json] = []
  for diagnostic in diagnostics {
    values.push(diagnostic_json(diagnostic))
  }
  @json.Json::array(values)
}

fn format_diagnostics_json(diagnostics : Array[@api.FormatDiagnostic]) -> @json.Json {
  let values : Array[@json.Json] = []
  for diagnostic in diagnostics {
    values.push(format_diagnostic_json(diagnostic))
  }
  @json.Json::array(values)
}

fn offsets_json(offsets : Array[Int]) -> @json.Json {
  let values : Array[@json.Json] = []
  for offset in offsets {
    values.push(@json.Json::number(offset.to_double()))
  }
  @json.Json::array(values)
}

pub fn stringify(value : @json.Json) -> String {
  value.stringify()
}
