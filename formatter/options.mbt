///|
/// Formatting policy knobs (D-25/D-26): exactly the six FMT-02 dimensions,
/// mirroring ParseMode (api.mbt:3-6) and the ParseOptions constructor/accessor
/// convention (api.mbt:19-118).
pub(all) enum KeywordCase {
  Upper
  Lower
} derive(Eq, @debug.Debug)

///|
pub(all) enum CommaStyle {
  Trailing
  Leading
} derive(Eq, @debug.Debug)

///|
pub(all) enum NewlineStyle {
  FollowInput
  Lf
  Crlf
} derive(Eq, @debug.Debug)

///|
/// Maximum accepted indent width (WR-02). A sane cap so a typo like
/// `--indent 5000000` fails construction (InvalidIndent) instead of
/// materializing `indent * break_indent` leading spaces per broken line —
/// multi-gigabyte output / OOM. Realistic indents (2-8) are far below it.
pub const MAX_INDENT : Int = 64

///|
/// Six locked fields (D-26). Construction validates (ASVS V5) mirroring
/// ParseError::InvalidLimit (api.mbt:57-58): negative or over-cap (above
/// MAX_INDENT) indent and non-positive line width fail construction and
/// never reach layout.
pub struct FormatOptions {
  keyword_case : KeywordCase
  indent : Int
  line_width : Int
  comma_style : CommaStyle
  newline_style : NewlineStyle
  trailing_newline : Bool
}

///|
/// Defaults per D-29..D-32: UPPERCASE, 2-space indent, 100 columns,
/// trailing comma style, FollowInput newlines, trailing newline on.
pub fn FormatOptions::default() -> FormatOptions {
  {
    keyword_case: KeywordCase::Upper,
    indent: 2,
    line_width: 100,
    comma_style: CommaStyle::Trailing,
    newline_style: NewlineStyle::FollowInput,
    trailing_newline: true,
  }
}

///|
pub fn FormatOptions::new(
  keyword_case : KeywordCase,
  indent : Int,
  line_width : Int,
  comma_style : CommaStyle,
  newline_style : NewlineStyle,
  trailing_newline : Bool,
) -> Result[FormatOptions, FormatError] {
  if indent < 0 || indent > MAX_INDENT {
    return Err(InvalidIndent(value=indent))
  }
  if line_width <= 0 {
    return Err(InvalidLineWidth(value=line_width))
  }
  Ok({
    keyword_case,
    indent,
    line_width,
    comma_style,
    newline_style,
    trailing_newline,
  })
}

///|
pub fn FormatOptions::keyword_case(self : FormatOptions) -> KeywordCase {
  self.keyword_case
}

///|
pub fn FormatOptions::indent(self : FormatOptions) -> Int {
  self.indent
}

///|
pub fn FormatOptions::line_width(self : FormatOptions) -> Int {
  self.line_width
}

///|
pub fn FormatOptions::comma_style(self : FormatOptions) -> CommaStyle {
  self.comma_style
}

///|
pub fn FormatOptions::newline_style(self : FormatOptions) -> NewlineStyle {
  self.newline_style
}

///|
pub fn FormatOptions::trailing_newline(self : FormatOptions) -> Bool {
  self.trailing_newline
}

///|
/// String-id mapping for the CLI flag surface (plan 03-04) and the
/// option-combination test driver (plan 03-03), mirroring
/// DorisProfile::from_id (token.mbt:241-248). Unknown ids return None.
pub fn KeywordCase::from_id(id : String) -> KeywordCase? {
  match id {
    "upper" => Some(KeywordCase::Upper)
    "lower" => Some(KeywordCase::Lower)
    _ => None
  }
}

///|
pub fn CommaStyle::from_id(id : String) -> CommaStyle? {
  match id {
    "trailing" => Some(CommaStyle::Trailing)
    "leading" => Some(CommaStyle::Leading)
    _ => None
  }
}

///|
pub fn NewlineStyle::from_id(id : String) -> NewlineStyle? {
  match id {
    "follow" => Some(NewlineStyle::FollowInput)
    "lf" => Some(NewlineStyle::Lf)
    "crlf" => Some(NewlineStyle::Crlf)
    _ => None
  }
}

///|
/// Validate a keyword case string id, returning a FormatError on unknown
/// values (FATHOM-FORMAT-002). Used by the CLI and binding layers.
pub fn KeywordCase::from_id_checked(
  id : String,
) -> Result[KeywordCase, FormatError] {
  match KeywordCase::from_id(id) {
    Some(value) => Ok(value)
    None => Err(UnknownKeywordCase(keyword_case_id=id))
  }
}

///|
/// Validate a comma style string id, returning a FormatError on unknown
/// values (FATHOM-FORMAT-003).
pub fn CommaStyle::from_id_checked(
  id : String,
) -> Result[CommaStyle, FormatError] {
  match CommaStyle::from_id(id) {
    Some(value) => Ok(value)
    None => Err(UnknownCommaStyle(comma_style_id=id))
  }
}

///|
/// Validate a newline style string id, returning a FormatError on unknown
/// values (FATHOM-FORMAT-004).
pub fn NewlineStyle::from_id_checked(
  id : String,
) -> Result[NewlineStyle, FormatError] {
  match NewlineStyle::from_id(id) {
    Some(value) => Ok(value)
    None => Err(UnknownNewlineStyle(newline_style_id=id))
  }
}
