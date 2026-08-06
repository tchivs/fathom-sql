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
  // The languageId the client declared at didOpen (LSP standard field), used
  // to re-resolve through the user-configured language mapping when settings
  // change (D-01 level 3, D-03).
  pub language_id : String?
}

pub(all) struct DocumentStore {
  docs : Map[String, Document]
}

pub fn DocumentStore::new() -> DocumentStore {
  { docs: Map([]) }
}

pub fn DocumentStore::open(self : DocumentStore, uri : String, version : Int, text : Bytes, dialect : String, profile : String, selection_source : String, language_id : String?) -> Bool {
  if version < 0 { return false }
  match self.docs.get(uri) {
    Some(document) if version <= document.version => false
    _ => {
      self.docs[uri] = { uri: uri, version: version, text: text, dialect: dialect, profile: profile, selection_source: selection_source, language_id: language_id }
      true
    }
  }
}

pub fn DocumentStore::change(self : DocumentStore, uri : String, version : Int, text : Bytes, dialect : String, profile : String, selection_source : String, language_id : String?) -> Bool {
  match self.docs.get(uri) {
    Some(document) if version > document.version => {
      self.docs[uri] = { uri: uri, version: version, text: text, dialect: dialect, profile: profile, selection_source: selection_source, language_id: language_id }
      true
    }
    _ => false
  }
}

/// D-03 re-resolution: rewrite a document's selection context in place,
/// keeping its uri/version/text/language_id unchanged.
pub fn DocumentStore::update_selection(self : DocumentStore, uri : String, dialect : String, profile : String, selection_source : String) -> Bool {
  match self.docs.get(uri) {
    Some(document) => {
      self.docs[uri] = {
        uri: uri,
        version: document.version,
        text: document.text,
        dialect: dialect,
        profile: profile,
        selection_source: selection_source,
        language_id: document.language_id,
      }
      true
    }
    None => false
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

/// Snapshot of every open document (re-resolution iteration, D-03).
pub fn DocumentStore::documents(self : DocumentStore) -> Array[Document] {
  let out : Array[Document] = []
  let keys = self.docs.keys()
  for key in keys {
    match self.docs.get(key) {
      Some(document) => out.push(document)
      None => ()
    }
  }
  out
}
