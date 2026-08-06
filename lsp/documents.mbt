/// Versioned full-document snapshots keyed by the client URI. Each document
/// carries its own resolved dialect/profile context (D-01/D-03): every
/// parse/format/completion call uses the document's context, never a global
/// ServerState selection.

pub(all) struct Document {
  pub uri : String
  pub version : Int
  pub text : Bytes
  pub dialect : String
  pub profile : String
  // Which D-01 priority source produced the resolved selection:
  // "document" (didOpen/didChange extension fields), "workspace"
  // (initializationOptions/serve_stdio default), or "language"
  // (user-configured languageId mapping). A workspace-default change only
  // re-resolves documents whose context did NOT come from document-level
  // explicit config.
  pub selection_source : String
}

pub(all) struct DocumentStore {
  docs : Map[String, Document]
}

pub fn DocumentStore::new() -> DocumentStore {
  { docs: Map([]) }
}

pub fn DocumentStore::open(self : DocumentStore, uri : String, version : Int, text : Bytes, dialect : String, profile : String, selection_source : String) -> Bool {
  if version < 0 { return false }
  match self.docs.get(uri) {
    Some(document) if version <= document.version => false
    _ => {
      self.docs[uri] = { uri: uri, version: version, text: text, dialect: dialect, profile: profile, selection_source: selection_source }
      true
    }
  }
}

pub fn DocumentStore::change(self : DocumentStore, uri : String, version : Int, text : Bytes, dialect : String, profile : String, selection_source : String) -> Bool {
  match self.docs.get(uri) {
    Some(document) if version > document.version => {
      self.docs[uri] = { uri: uri, version: version, text: text, dialect: dialect, profile: profile, selection_source: selection_source }
      true
    }
    _ => false
  }
}

pub fn DocumentStore::close(self : DocumentStore, uri : String) -> Bool {
  match self.docs.get(uri) {
    Some(_) => {
      self.docs.remove(uri)
      true
    }
    None => false
  }
}

pub fn DocumentStore::get(self : DocumentStore, uri : String) -> Document? {
  self.docs.get(uri)
}
