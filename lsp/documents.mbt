/// Versioned full-document snapshots keyed by the client URI.

pub(all) struct Document {
  pub uri : String
  pub version : Int
  pub text : Bytes
}

pub(all) struct DocumentStore {
  docs : Map[String, Document]
}

pub fn DocumentStore::new() -> DocumentStore {
  { docs: Map([]) }
}

pub fn DocumentStore::open(self : DocumentStore, uri : String, version : Int, text : Bytes) -> Bool {
  if version < 0 { return false }
  self.docs[uri] = { uri: uri, version: version, text: text }
  true
}

pub fn DocumentStore::change(self : DocumentStore, uri : String, version : Int, text : Bytes) -> Bool {
  match self.docs.get(uri) {
    Some(document) if version > document.version => {
      self.docs[uri] = { uri: uri, version: version, text: text }
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
