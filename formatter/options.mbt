/// Formatting policy knobs (D-25/D-26): exactly the six FMT-02 dimensions,
/// mirroring ParseMode (api.mbt:3-6) and the ParseOptions constructor/accessor
/// convention (api.mbt:19-118).

pub(all) enum KeywordCase {
  Upper
  Lower
} derive(Eq, @debug.Debug)

pub(all) enum CommaStyle {
  Trailing
  Leading
} derive(Eq, @debug.Debug)

pub(all) enum NewlineStyle {
  FollowInput
  Lf
  Crlf
} derive(Eq, @debug.Debug)

/// Six locked fields (D-26). Construction validates (ASVS V5) mirroring
/// ParseError::InvalidLimit (api.mbt:57-58): negative indent and non-positive
/// line width fail construction and never reach layout.
pub struct FormatOptions {
  keyword_case : KeywordCase
  indent : Int
  line_width : Int
  comma_style : CommaStyle
  newline_style : NewlineStyle
  trailing_newline : Bool
}

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

pub fn FormatOptions::new(
  keyword_case : KeywordCase,
  indent : Int,
  line_width : Int,
  comma_style : CommaStyle,
  newline_style : NewlineStyle,
  trailing_newline : Bool,
) -> Result[FormatOptions, FormatError] {
  if indent < 0 {
    return Err(InvalidIndent(value=indent))
  }
  if line_width <= 0 {
    return Err(InvalidLineWidth(value=line_width))
  }
  Ok({
    keyword_case: keyword_case,
    indent: indent,
    line_width: line_width,
    comma_style: comma_style,
    newline_style: newline_style,
    trailing_newline: trailing_newline,
  })
}

pub fn FormatOptions::keyword_case(self : FormatOptions) -> KeywordCase {
  self.keyword_case
}

pub fn FormatOptions::indent(self : FormatOptions) -> Int {
  self.indent
}

pub fn FormatOptions::line_width(self : FormatOptions) -> Int {
  self.line_width
}

pub fn FormatOptions::comma_style(self : FormatOptions) -> CommaStyle {
  self.comma_style
}

pub fn FormatOptions::newline_style(self : FormatOptions) -> NewlineStyle {
  self.newline_style
}

pub fn FormatOptions::trailing_newline(self : FormatOptions) -> Bool {
  self.trailing_newline
}
