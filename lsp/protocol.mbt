/// Minimal JSON-RPC 2.0/LSP value adapter. JSON parsing and escaping are
/// delegated to moonbitlang/core/json; this package only validates the methods
/// and primitive shapes required by the Native tracer.

pub enum RpcId {
  Number(value~ : Int)
  String(value~ : String)
  Null
} derive(Eq, @debug.Debug)

pub(all) struct RpcMessage {
  pub id : RpcId?
  pub method : String
  pub params : Json?
}

fn field(value : Json, key : String) -> Json? {
  match value {
    Json::Object(object) => object.get(key)
    _ => None
  }
}

pub fn string_field(value : Json, key : String) -> String? {
  match field(value, key) {
    Some(Json::String(text)) => Some(text)
    _ => None
  }
}

pub fn int_field(value : Json, key : String) -> Int? {
  match field(value, key) {
    Json::Number(number, ..) if number.to_int().to_double() == number => Some(number.to_int())
    _ => None
  }
}

pub fn object_field(value : Json, key : String) -> Json? {
  match field(value, key) {
    Some(object) => if object is Json::Object(_) { Some(object) } else { None }
    _ => None
  }
}

pub fn array_field(value : Json, key : String) -> Array[Json]? {
  match field(value, key) {
    Some(Json::Array(values)) => Some(values)
    _ => None
  }
}

fn decode_id(value : Json) -> RpcId? {
  match value {
    Json::Number(number, ..) if number.to_int().to_double() == number => Some(Number(value=number.to_int()))
    Json::String(text) => Some(String(value=text))
    Json::Null => Some(Null)
    _ => None
  }
}

pub fn parse_message(body : Bytes) -> Result[RpcMessage, String] {
  let text = try {
    @utf8.decode(body)
  } catch {
    _ => return Err("invalid UTF-8 JSON-RPC body")
  }
  let value = try {
    @json.parse(text)
  } catch {
    _ => return Err("malformed JSON-RPC body")
  }
  let object = match value {
    Json::Object(object) => object
    _ => return Err("JSON-RPC message must be an object")
  }
  let version = match object.get("jsonrpc") {
    Some(Json::String(version)) => version
    _ => return Err("JSON-RPC message is missing jsonrpc=2.0")
  }
  if version != "2.0" { return Err("unsupported JSON-RPC version") }
  let method = match object.get("method") {
    Some(Json::String(method)) => method
    _ => return Err("JSON-RPC message is missing method")
  }
  let id = match object.get("id") {
    Some(value) => decode_id(value)
    None => None
  }
  if object.get("id").is_some() && id.is_none() { return Err("invalid JSON-RPC id") }
  let params = match object.get("params") {
    Some(Json::Null) | None => None
    Some(value) => Some(value)
  }
  Ok({ id: id, method: method, params: params })
}

fn id_json(id : RpcId) -> Json {
  match id {
    Number(value~) => Json::number(value.to_double())
    String(value~) => Json::string(value)
    Null => null
  }
}

pub fn response(id : RpcId, result : Json) -> Bytes {
  let value : Json = {
    "jsonrpc": Json::string("2.0"),
    "id": id_json(id),
    "result": result,
  }
  @utf8.encode(value.stringify())
}

pub fn error_response(id : RpcId, code : Int, message : String) -> Bytes {
  let value : Json = {
    "jsonrpc": Json::string("2.0"),
    "id": id_json(id),
    "error": {
      "code": Json::number(code.to_double()),
      "message": Json::string(message),
    },
  }
  @utf8.encode(value.stringify())
}

pub fn notification(method : String, params : Json) -> Bytes {
  let value : Json = {
    "jsonrpc": Json::string("2.0"),
    "method": Json::string(method),
    "params": params,
  }
  @utf8.encode(value.stringify())
}
