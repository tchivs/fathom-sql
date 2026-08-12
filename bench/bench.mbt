/// Whole-document reparse latency benchmarks — EDIT-01 benchmark gate (D-01).
///
/// Primary measured surface: `@api.parse` (api.mbt:431) — the full editor
/// path including envelope serialization (the cost an editor caller actually
/// pays). Auxiliary measured surface: `@parser.parse_with_limits_context`
/// (parser.mbt:4275) — the pure core CST parse (Pattern 2 dual measurement:
/// separates core parse cost from serialization cost). `it.keep(...)`
/// (moonbitlang/core/bench) prevents dead-code elimination of the parse
/// result (STACK.md:231).

fn bench_options() -> @api.ParseOptions {
  match @api.ParseOptions::new("doris", "4.x", "editor") {
    Ok(options) => options
    Err(_) => panic()
  }
}

fn bench_core_context() -> @dialect.DialectContext {
  {
    dialect: @dialect.Dialect::Doris,
    profile_id: "4.x",
    exact_release: "4.x",
    feature_introduction: "",
  }
}

// --- Editor-scale gradient, full @api.parse path (25/50/100/200 KB) ---

test "bench parse_full_editor_scale_25k" (it : @bench.T) {
  let raw = build_editor_scale(25 * 1024)
  let options = bench_options()
  it.bench(name="parse_full_editor_scale_25k", fn() { it.keep(@api.parse(raw, options)) })
}

test "bench parse_full_editor_scale_50k" (it : @bench.T) {
  let raw = build_editor_scale(50 * 1024)
  let options = bench_options()
  it.bench(name="parse_full_editor_scale_50k", fn() { it.keep(@api.parse(raw, options)) })
}

test "bench parse_full_editor_scale_100k" (it : @bench.T) {
  let raw = build_editor_scale(100 * 1024)
  let options = bench_options()
  it.bench(name="parse_full_editor_scale_100k", fn() { it.keep(@api.parse(raw, options)) })
}

test "bench parse_full_editor_scale_200k" (it : @bench.T) {
  let raw = build_editor_scale(200 * 1024)
  let options = bench_options()
  it.bench(name="parse_full_editor_scale_200k", fn() { it.keep(@api.parse(raw, options)) })
}

// --- Corpus baselines, full @api.parse path on the real small fixtures ---

test "bench parse_full_select_industrial" (it : @bench.T) {
  let raw = corpus_select_industrial_4x
  let options = bench_options()
  it.bench(name="parse_full_select_industrial", fn() { it.keep(@api.parse(raw, options)) })
}

test "bench parse_full_script_multi_statement" (it : @bench.T) {
  let raw = corpus_script_multi_statement_4x
  let options = bench_options()
  it.bench(name="parse_full_script_multi_statement", fn() { it.keep(@api.parse(raw, options)) })
}

test "bench parse_full_ddl_create_table" (it : @bench.T) {
  let raw = corpus_ddl_create_table_4x
  let options = bench_options()
  it.bench(name="parse_full_ddl_create_table", fn() { it.keep(@api.parse(raw, options)) })
}

// --- Pure-core auxiliary surface (Pattern 2 dual measurement) ---
// Isolates the CST parse cost from the api envelope serialization cost.

test "bench parse_core_editor_scale_100k" (it : @bench.T) {
  let source = match @source.SourceText::new(build_editor_scale(100 * 1024)) {
    Ok(source) => source
    Err(_) => panic()
  }
  let context = bench_core_context()
  let limits = @parser.ParserLimits::default()
  it.bench(name="parse_core_editor_scale_100k", fn() {
    it.keep(@parser.parse_with_limits_context(source, context, @parser.ParseMode::Editor, limits))
  })
}

test "bench parse_core_editor_scale_200k" (it : @bench.T) {
  let source = match @source.SourceText::new(build_editor_scale(200 * 1024)) {
    Ok(source) => source
    Err(_) => panic()
  }
  let context = bench_core_context()
  let limits = @parser.ParserLimits::default()
  it.bench(name="parse_core_editor_scale_200k", fn() {
    it.keep(@parser.parse_with_limits_context(source, context, @parser.ParseMode::Editor, limits))
  })
}
