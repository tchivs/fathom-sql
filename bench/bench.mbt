/// Minimal `@bench` availability probe on the pinned toolchain (Pitfall 1).
///
/// Task 1 of 08-01: verify that `@bench` + `moon bench --target native
/// --output-json` work on `moon 0.1.20260724` before building the full
/// editor-scale benchmark suite. The probe conclusion (three states) is
/// recorded in the Task 1 commit and in 08-BENCHMARK.md.

fn bench_options() -> @api.ParseOptions {
  match @api.ParseOptions::new("doris", "4.x", "editor") {
    Ok(options) => options
    Err(_) => panic()
  }
}

test "bench probe_parse_small" (it : @bench.T) {
  let raw = b"SELECT 1;"
  let options = bench_options()
  it.bench(name="probe_parse_small", fn() { it.keep(@api.parse(raw, options)) })
}
