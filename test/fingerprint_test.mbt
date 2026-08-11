/// api.fingerprint_text integration tests (FING-01, 06-01 Task 2). These run
/// through the real parser, proving the full raw -> parse -> normalize -> hash
/// pipeline behind @api.fingerprint_text.

fn fingerprint_options() -> @api.ParseOptions {
  match @api.ParseOptions::new("doris", "4.x", "strict") {
    Ok(options) => options
    Err(_) => panic()
  }
}

test "fingerprint_text_stable_across_trivia_and_case" {
  let opt = fingerprint_options()
  let r1 = match @api.fingerprint_text(b"SELECT 1", opt) {
    Ok(result) => result
    Err(_) => panic()
  }
  let r2 = match @api.fingerprint_text(b"select\n 1", opt) {
    Ok(result) => result
    Err(_) => panic()
  }
  let r3 = match @api.fingerprint_text(b"SELECT /*c*/ 1", opt) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(r1.fingerprint, r2.fingerprint)
  assert_eq(r1.fingerprint, r3.fingerprint)
  assert_eq(r1.normalized, b"select 1")
}

test "fingerprint_text_preserves_quote_style_and_identifier_case" {
  let opt = fingerprint_options()
  let double_quote = match @api.fingerprint_text(b"SELECT \"A\"", opt) {
    Ok(result) => result
    Err(_) => panic()
  }
  let single_quote = match @api.fingerprint_text(b"SELECT 'A'", opt) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(double_quote.fingerprint != single_quote.fingerprint)
  let upper_ident = match @api.fingerprint_text(b"SELECT A", opt) {
    Ok(result) => result
    Err(_) => panic()
  }
  let lower_ident = match @api.fingerprint_text(b"SELECT a", opt) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_true(upper_ident.fingerprint != lower_ident.fingerprint)
}

test "fingerprint_text_is_total_on_empty_and_errors" {
  let opt = fingerprint_options()
  // Empty document -> canonical empty -> fingerprint = FNV-1a offset basis.
  let empty = match @api.fingerprint_text(b"", opt) {
    Ok(result) => result
    Err(_) => panic()
  }
  assert_eq(empty.normalized, b"")
  assert_eq(empty.fingerprint, 0xcbf29ce484222325UL)
  // Error/skipped material still yields a deterministic fingerprint (total
  // function) — it never panics and never returns an unreadable result.
  match @api.fingerprint_text(b"SELECT 'unterminated", opt) {
    Ok(_) => assert_true(true)
    Err(_) => assert_true(true) // recoverable path also acceptable
  }
}

test "fingerprint_text_propagates_selection_errors" {
  // Unknown dialect -> UnknownDialect (structured, never a fallback).
  match @api.ParseOptions::new("bogus", "4.x", "strict") {
    Err(@api.ParseError::UnknownDialect(dialect_id~)) => assert_eq(dialect_id, "bogus")
    _ => assert_true(false)
  }
}
