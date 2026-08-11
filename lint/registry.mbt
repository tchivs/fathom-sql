/// SQLFluff-style rule registry (LINT-01, D-02/D-04): the default 8-rule table
/// plus per-rule enable/disable + severity overrides.
///
/// Rule codes freeze on release (D-02 costly) — 001..008 are the initial
/// public set. Rules 004-007 are analyzer-backed and only produce findings
/// when a caller injects an `AnalysisResult`; without a catalog they are
/// silently skipped (ANLY-01), so the wire/CLI surface runs only 001/002/003/
/// 008 (Pitfall 6).

/// One per-rule configuration override (D-04).
pub(all) struct RuleOverride {
  pub code : String
  pub setting : RuleSetting
} derive(Eq, @debug.Debug)

/// Lint configuration: the default registry plus per-rule overrides. There is
/// NO config file in this phase (D-04) — the API struct is the canonical
/// surface and the CLI `--rule <code>=<severity|off>` maps into it.
pub(all) struct LintOptions {
  overrides : Array[RuleOverride]
} derive(Eq, @debug.Debug)

/// Structured error for an unknown rule code (CLI exit-2 basis, D-04).
pub enum LintOptionsError {
  UnknownRule(code~ : String)
} derive(Eq, @debug.Debug)

/// The default 8-rule registry (D-02 focused set). `applies_to` is the
/// profile-applicability window ("2.1+" = all released Doris profiles).
pub fn default_registry() -> Array[LintRule] {
  [
    {
      code: "FATHOM-LINT-001",
      name: "unquoted-reserved-word",
      category: "style",
      default_severity: LintSeverity::Warning,
      fixable: true,
      applies_to: "2.1+",
      enabled: true,
    },
    {
      code: "FATHOM-LINT-002",
      name: "version-gated-syntax",
      category: "advisory",
      default_severity: LintSeverity::Info,
      fixable: false,
      applies_to: "2.1+",
      enabled: true,
    },
    {
      code: "FATHOM-LINT-003",
      name: "select-star-without-limit",
      category: "safety",
      default_severity: LintSeverity::Warning,
      fixable: false,
      applies_to: "2.1+",
      enabled: true,
    },
    {
      code: "FATHOM-LINT-004",
      name: "unknown-table",
      category: "correctness",
      default_severity: LintSeverity::Error,
      fixable: false,
      applies_to: "2.1+",
      enabled: true,
    },
    {
      code: "FATHOM-LINT-005",
      name: "unknown-column",
      category: "correctness",
      default_severity: LintSeverity::Error,
      fixable: false,
      applies_to: "2.1+",
      enabled: true,
    },
    {
      code: "FATHOM-LINT-006",
      name: "ambiguous-reference",
      category: "correctness",
      default_severity: LintSeverity::Warning,
      fixable: false,
      applies_to: "2.1+",
      enabled: true,
    },
    {
      code: "FATHOM-LINT-007",
      name: "function-arity",
      category: "correctness",
      default_severity: LintSeverity::Error,
      fixable: false,
      applies_to: "2.1+",
      enabled: true,
    },
    {
      code: "FATHOM-LINT-008",
      name: "deprecated-syntax",
      category: "deprecation",
      default_severity: LintSeverity::Info,
      fixable: false,
      applies_to: "2.1+",
      enabled: true,
    },
  ]
}

/// Resolve a rule's effective setting from the overrides, falling back to the
/// registry default. Returns None when the rule is disabled.
pub fn LintOptions::rule_setting(self : LintOptions, rule : LintRule) -> RuleSetting? {
  for rule_override in self.overrides {
    if rule_override.code == rule.code {
      return Some(rule_override.setting)
    }
  }
  if rule.enabled {
    Some(RuleSetting::Severity(rule.default_severity))
  } else {
    None
  }
}

/// Validate overrides against the registry: every code must be a known rule.
/// Unknown codes return a structured error (CLI maps it to exit 2, D-04).
pub fn LintOptions::new(overrides : Array[RuleOverride]) -> Result[LintOptions, LintOptionsError] {
  for rule_override in overrides {
    let code = rule_override.code
    if !registry_has_code(code) {
      return Err(UnknownRule(code~))
    }
  }
  Ok({ overrides: overrides })
}

/// Empty overrides -> default registry, all rules enabled at default severity.
pub fn LintOptions::default() -> LintOptions {
  { overrides: [] }
}

fn registry_has_code(code : String) -> Bool {
  let mut found = false
  for rule in default_registry() {
    if rule.code == code {
      found = true
      break
    }
  }
  found
}

test "default_registry_has_eight_stable_codes" {
  let registry = default_registry()
  assert_eq(registry.length(), 8)
  assert_eq(registry[0].code, "FATHOM-LINT-001")
  assert_eq(registry[1].code, "FATHOM-LINT-002")
  assert_eq(registry[2].code, "FATHOM-LINT-003")
  assert_eq(registry[3].code, "FATHOM-LINT-004")
  assert_eq(registry[4].code, "FATHOM-LINT-005")
  assert_eq(registry[5].code, "FATHOM-LINT-006")
  assert_eq(registry[6].code, "FATHOM-LINT-007")
  assert_eq(registry[7].code, "FATHOM-LINT-008")
  // 003 is the safety select-star rule; 001 is fixable; 004-007 are correctness
  assert_true(registry[2].category == "safety")
  assert_true(registry[0].fixable)
  assert_true(!registry[2].fixable)
}

test "lint_severity_from_id_roundtrip" {
  assert_eq(LintSeverity::from_id("error"), Some(LintSeverity::Error))
  assert_eq(LintSeverity::from_id("warning"), Some(LintSeverity::Warning))
  assert_eq(LintSeverity::from_id("info"), Some(LintSeverity::Info))
  assert_eq(LintSeverity::from_id("fatal"), None)
}

test "lint_options_validates_unknown_rule" {
  let valid = LintOptions::new([
    { code: "FATHOM-LINT-003", setting: RuleSetting::Disabled },
  ])
  assert_true(valid is Ok(_))
  match LintOptions::new([{ code: "FATHOM-LINT-999", setting: RuleSetting::Disabled }]) {
    Err(LintOptionsError::UnknownRule(code~)) => assert_eq(code, "FATHOM-LINT-999")
    _ => assert_true(false)
  }
}
