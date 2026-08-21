/// Analyzer-internal SELECT model (D-01). The analyzer re-parses the flat
/// token-leaf CST into its own clause structure instead of depending on CST
/// sub-nodes (syntax/SyntaxKind only has coarse statement families). This file
/// fixes the full model shape: every SELECT clause, CTE definitions, set-op
/// branches, select items (with AS aliases and star markers) and FROM items
/// (tables, aliases, JOIN chains, subqueries, paren-depth markers). No
/// SyntaxKind is added and syntax/syntax.mbt is untouched (D-01, Phase 12
/// frozen parser hard gate).

///|
/// Top-level SELECT clause kinds recognized by the re-parser (D-01).
pub(all) enum ClauseKind {
  SelectList
  From
  Where
  GroupBy
  Having
  Qualify
  OrderBy
  Limit
  Window
  SetOpUnion
} derive(Eq, @debug.Debug)

///|
/// A token slice: token bytes plus a flattened byte span (D-01/D-06).
pub(all) struct TokenSlice {
  bytes : Bytes
  start_byte : Int
  end_byte : Int
}

///|
/// One dotted name reference inside an expression (D-01): the maximal
/// dot-separated identifier run, e.g. `a`, `t.a`, `db.t.col`, `t.*`, `*`.
/// `parts` holds one slice per identifier segment in source order; `star` is
/// set when the final segment is `*` (then `parts` excludes the star);
/// `is_call` is set when the reference is immediately followed by `(` (a
/// function call), and `call_args` then holds the token slices between that
/// `(` and its matching `)` (parens excluded) for arity counting (D-04).
/// Source spelling and byte spans are preserved (D-03).
pub(all) struct NameRef {
  parts : Array[TokenSlice]
  star : Bool
  is_call : Bool
  call_args : Array[TokenSlice]
  start_byte : Int
  end_byte : Int
}

///|
/// One SELECT-list item: the expression token slices, the optional AS/bare
/// alias_name, and whether the item is a star projection (`*`, `t.*`, `db.t.*`).
/// `star_qualifier` holds the dotted name before `.*` (None for a bare `*`);
/// `except_cols` holds the `EXCEPT (cols)` exclusion list token slices (empty
/// when the item has no EXCEPT modifier — D-03: unquoted ASCII case-fold,
/// quoted byte-exact, matching find_column_in).
pub(all) struct SelectItem {
  tokens : Array[TokenSlice]
  alias_name : String?
  alias_slice : TokenSlice?
  star : Bool
  star_qualifier : NameRef?
  refs : Array[NameRef]
  except_cols : Array[TokenSlice]
}

///|
/// One FROM item: a table reference with its alias_name and optional subquery
/// body. `name` is None for a bare subquery; `is_subquery` distinguishes it.
/// `join` records how the item attaches to the previous one ("INNER"/"LEFT"/
/// ... or None for a base/comma-separated ref). `depth` marks the paren depth
/// at which the item was parsed (0 at the top level; subqueries recurse).
pub(all) struct FromItem {
  name : NameRef?
  alias_name : String?
  alias_slice : TokenSlice?
  is_subquery : Bool
  subquery : SelectModel?
  join : String?
  depth : Int
}

///|
/// A CTE definition: name, optional column-name alias_name list text (`WITH c(x)
/// AS ...`), and the parsed body core (D-02 scope, Pitfall 4).
pub(all) struct CteDef {
  name : String
  alias_name : String?
  body : SelectCore
}

///|
/// One SELECT core: per-clause material produced by the re-parser. Expression
/// clauses carry pre-extracted `NameRef`s; `limit`/`window` keep raw token
/// slices (not name-resolved). `set_op` records the set operation that
/// follows this core in a UNION chain (None for the final branch).
pub(all) struct SelectCore {
  select_list : Array[SelectItem]
  from : Array[FromItem]
  joins : Array[FromItem]
  where_refs : Array[NameRef]
  group_by : Array[NameRef]
  having : Array[NameRef]
  qualify : Array[NameRef]
  order_by : Array[NameRef]
  limit : Array[TokenSlice]
  window : Array[TokenSlice]
  set_op : String?
}

///|
/// The model of a full SELECT statement: CTEs plus set-op branches. The first
/// branch's output columns are the statement's output columns (UNION column
/// names come from the first SELECT).
pub(all) struct SelectModel {
  ctes : Array[CteDef]
  branches : Array[SelectCore]
}
