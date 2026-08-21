///|
/// Caller-owned catalog JSON → StaticCatalog (D-05, T-02-42, LINE-01).
///
/// The catalog document is an untrusted host input. Parsing mirrors
/// `parse_overrides` (exports.mbt): empty bytes or `"{}"` mean no catalog
/// (`Ok(None)` — the D-05 default under which every `*`/external view reports
/// an honest `requires-catalog` gap, SC2); malformed UTF-8/JSON or any
/// shape/field error is a structured `Err(String)` — NEVER a silent fallback
/// to the no-catalog behavior (T-06-03-01, ASVS V5). The wire export maps
/// `Err` to FATHOM-SCHEMA-004.
///
/// JSON shape (RESEARCH A5):
/// ```
/// {
///   "tables":    [{ "name": "t", "columns": [{ "name": "a", "data_type": "INT" }] }],
///   "db_tables": [{ "db": "db1", "name": "t", "table": { "name": "t", "columns": [...] } }],
///   "functions": [{ "name": "f", "param_types": ["INT"], "return_type": "INT", "min_arity": 1 }]
/// }
/// ```
/// Column order is the JSON array order — `StaticCatalog` is backed by
/// `Map` = LinkedHashMap, so star-expansion order follows the caller's JSON
/// order (the parity byte-consistency contract, Pattern 6). Keys are
/// case-sensitive (Phase 5 discipline).
pub fn parse_catalog_json(bytes : Bytes) -> Result[@api.StaticCatalog?, String] {
  if bytes.length() == 0 {
    return Ok(None)
  }
  let text = @utf8.decode(bytes) catch {
    _ => return Err("invalid UTF-8 in catalog JSON")
  }
  let value = @json.parse(text) catch {
    _ => return Err("malformed JSON in catalog JSON")
  }
  match value {
    Json::Object(obj) => {
      // "{}" is the no-catalog default (D-05); any non-empty object is parsed.
      if obj.is_empty() {
        return Ok(None)
      }
      // tables
      let tables : Array[@analyzer.TableInfo] = []
      match obj.get("tables") {
        Some(Json::Array(items)) =>
          for item in items {
            match parse_table_info(item) {
              Ok(table) => tables.push(table)
              Err(message) => return Err(message)
            }
          }
        Some(_) => return Err("catalog JSON 'tables' must be an array")
        None => ()
      }
      let mut catalog = @analyzer.StaticCatalog::new(tables)
      // db_tables
      match obj.get("db_tables") {
        Some(Json::Array(items)) =>
          for item in items {
            match parse_db_table(item) {
              Ok((db, name, table)) =>
                catalog = catalog.with_db(db, name, table)
              Err(message) => return Err(message)
            }
          }
        Some(_) => return Err("catalog JSON 'db_tables' must be an array")
        None => ()
      }
      // functions
      match obj.get("functions") {
        Some(Json::Array(items)) =>
          for item in items {
            match parse_function(item) {
              Ok(function) =>
                catalog = catalog.with_function(function.name, function)
              Err(message) => return Err(message)
            }
          }
        Some(_) => return Err("catalog JSON 'functions' must be an array")
        None => ()
      }
      Ok(Some(catalog))
    }
    _ => Err("catalog JSON must be an object")
  }
}

///|
fn parse_table_info(item : Json) -> Result[@analyzer.TableInfo, String] {
  match item {
    Json::Object(obj) => {
      let name = match obj.get("name") {
        Some(Json::String(s)) => s
        _ => return Err("catalog table missing string name")
      }
      let columns : Array[@analyzer.ColumnInfo] = []
      match obj.get("columns") {
        Some(Json::Array(items)) =>
          for column in items {
            match parse_column_info(column) {
              Ok(column_info) => columns.push(column_info)
              Err(message) => return Err(message)
            }
          }
        Some(_) => return Err("catalog table 'columns' must be an array")
        None => return Err("catalog table missing columns array")
      }
      Ok({ name, columns })
    }
    _ => Err("catalog table must be an object")
  }
}

///|
fn parse_column_info(item : Json) -> Result[@analyzer.ColumnInfo, String] {
  match item {
    Json::Object(obj) => {
      let name = match obj.get("name") {
        Some(Json::String(s)) => s
        _ => return Err("catalog column missing string name")
      }
      let data_type = match obj.get("data_type") {
        Some(Json::String(s)) => s
        _ => return Err("catalog column missing string data_type")
      }
      Ok({ name, data_type })
    }
    _ => Err("catalog column must be an object")
  }
}

///|
fn parse_db_table(
  item : Json,
) -> Result[(String, String, @analyzer.TableInfo), String] {
  match item {
    Json::Object(obj) => {
      let db = match obj.get("db") {
        Some(Json::String(s)) => s
        _ => return Err("catalog db_table missing string db")
      }
      let name = match obj.get("name") {
        Some(Json::String(s)) => s
        _ => return Err("catalog db_table missing string name")
      }
      let table = match obj.get("table") {
        Some(value) =>
          match parse_table_info(value) {
            Ok(table) => table
            Err(message) => return Err(message)
          }
        None => return Err("catalog db_table missing table object")
      }
      Ok((db, name, table))
    }
    _ => Err("catalog db_table must be an object")
  }
}

///|
fn parse_function(item : Json) -> Result[@analyzer.FunctionInfo, String] {
  match item {
    Json::Object(obj) => {
      let name = match obj.get("name") {
        Some(Json::String(s)) => s
        _ => return Err("catalog function missing string name")
      }
      let param_types : Array[String] = []
      match obj.get("param_types") {
        Some(Json::Array(items)) =>
          for param in items {
            match param {
              Json::String(s) => param_types.push(s)
              _ => return Err("catalog function param_types must be strings")
            }
          }
        Some(_) => return Err("catalog function 'param_types' must be an array")
        None => return Err("catalog function missing param_types array")
      }
      let return_type = match obj.get("return_type") {
        Some(Json::String(s)) => s
        _ => return Err("catalog function missing string return_type")
      }
      let min_arity = match obj.get("min_arity") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => return Err("catalog function missing number min_arity")
      }
      Ok({ name, param_types, return_type, min_arity })
    }
    _ => Err("catalog function must be an object")
  }
}
