# Phase 14: Release Hygiene & Toolchain Pinning - Pattern Map

**Mapped:** 2026-08-13
**Files analyzed:** 8 likely new/modified files
**Analogs found:** 5 / 8

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `.github/moonbit-toolchain.json` (new, recommended name) | config / supply-chain lock | file-I/O, transform | release manifest generated in `.github/workflows/fathom-native-release.yml:152-181` | partial: stable JSON manifest only; no toolchain lock exists |
| `.github/scripts/install-moonbit.sh` or equivalent shared Unix helper (new) | utility / installer | file-I/O, request-response | `.github/workflows/fathom-native-release.yml:42-62` and `.github/workflows/ci.yml:26-31` | role-match, but current acquisition is intentionally unsafe |
| `.github/scripts/install-moonbit.ps1` or equivalent Windows helper (new) | utility / installer | file-I/O, request-response | `.github/workflows/fathom-native-release.yml:64-85` | role-match, but current acquisition omits integrity checks |
| `.github/workflows/ci.yml` | config / CI workflow | batch, event-driven | its own `linear-wasm-parity`, `parity-gate`, `corpus`, and `naming-gate` jobs | exact |
| `.github/workflows/fathom-native-release.yml` | config / release workflow | batch, event-driven, manifest aggregation | its own build matrix and `release` aggregation job; gate commands from `.github/workflows/ci.yml` | exact composite |
| `.github/workflows/jetbrains-plugin.yml` | config / CI workflow | batch, event-driven | existing workflow itself | exact; commit current action-only delta as-is |
| `.gitignore` | config | file-I/O | existing repository-wide output rules in `.gitignore:1-12` | exact syntax, missing required entries |
| `scripts/validate_toolchain_evidence.py` or equivalent focused aggregation helper (new only if logic is not kept inline) | utility / validator | file-I/O, transform | inline release manifest validator/generator in `.github/workflows/fathom-native-release.yml:152-181`; fail-closed validators in `scripts/check_naming.py:142-183` | role-match |

The helper names above are discretionary. The invariant is one committed lock source plus platform-specific consumers with identical fail-closed semantics. Research explicitly omits a separate validation-test architecture because `workflow.nyquist_validation` is false (`14-RESEARCH.md:296-301`); no new test file is mandated.

## Pattern Assignments

### `.github/moonbit-toolchain.json` (config, file-I/O/transform)

**Analog:** `.github/workflows/fathom-native-release.yml:152-181` (inline stable JSON manifest generation)

**Stable JSON pattern** (lines 161-181):

```python
tag = os.environ["RELEASE_TAG"]
dist = Path("dist")
platforms = {
    "linux-x86_64": "fathom-lsp-linux-x86_64",
    "macos-x86_64": "fathom-lsp-macos-x86_64",
    "macos-aarch64": "fathom-lsp-macos-aarch64",
    "windows-x86_64": "fathom-lsp-windows-x86_64.exe",
}
assets = {}
for key, name in platforms.items():
    path = dist / name
    if not path.is_file():
        raise SystemExit(f"missing Native asset: {path}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assets[key] = {"name": name, "sha256": digest}
manifest = {"schemaVersion": 1, "tag": tag, "assets": assets}
(dist / "fathom-lsp-manifest.json").write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
```

**Copy:** schema versioning, deterministic sorted/indented UTF-8 JSON, terminal newline, explicit platform map, and fatal missing-file behavior.

**Do not copy:** the manifest's current runtime-derived hashes as vendor trust. The new lock must contain the freeze-preflight-proven static channel key, complete expected raw `moon version`, six exact archive URLs, six checksum URLs, and six vendor SHA-256 values (`14-RESEARCH.md:129-145`). There is no in-repo analog for an immutable MoonBit acquisition lock.

**Landmine:** neither historical `0.1.20260724` nor observed moving `0.1.20260807` is a valid static key. Freeze must GET all four platform binaries, both core formats, and all sidecars; unavailable Darwin x86_64 or official core checksums blocks implementation rather than selecting a fallback (`14-RESEARCH.md:129-147`).

---

### Shared Unix installer or equivalent (utility, request-response/file-I/O)

**Analogs:** `.github/workflows/ci.yml:26-31`; `.github/workflows/fathom-native-release.yml:42-62`

**Current call-site shape** (`ci.yml`, lines 26-31):

```yaml
- name: Install MoonBit
  shell: bash
  run: |
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
    echo "$HOME/.moon/bin" >> "$GITHUB_PATH"
    "$HOME/.moon/bin/moon" version
```

**Platform-specific behavior to preserve** (`fathom-native-release.yml`, lines 42-62):

```yaml
- name: Install MoonBit on Unix
  if: runner.os != 'Windows'
  shell: bash
  run: |
    curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
    echo "$HOME/.moon/bin" >> "$GITHUB_PATH"
    "$HOME/.moon/bin/moon" version
    if [[ "${{ matrix.platform }}" == "macos-x86_64" ]]; then
      # ... create x86_64 clang wrapper ...
      echo "MOON_CC=$RUNNER_TEMP/x86_64-apple-clang" >> "$GITHUB_ENV"
    fi
```

**Copy:** `bash` shell, `$GITHUB_PATH` publication, explicit matrix-platform branching, and the existing x86_64 linker architecture assertion path. Replace the piped moving installer with lock-driven download → official sidecar verification → archive path/layout validation → extraction/core bundling → exact full-output comparison.

**Cross-platform contract:** Unix and PowerShell may use native extraction/hash syntax, but both must consume the same lock, have no default/fallback, verify binary **and core** before executing, and assert complete raw `moon version` equality. Unix official mappings are Darwin arm64, Linux x86_64, and Linux aarch64; there is no official installer mapping for Darwin x86_64 (`14-RESEARCH.md:109-115`). Do not relabel an arm64 compiler as x86_64.

**Per-platform evidence:** after validation and before build, emit `moon-toolchain.json` beside the binary with `schemaVersion`, `requestedVersion`, complete `reportedVersion`, `runnerOS`, observed `runnerArch`, `targetPlatform`, binary digest, and core digest (`14-RESEARCH.md:203-220`).

---

### Shared PowerShell installer or equivalent (utility, request-response/file-I/O)

**Analog:** `.github/workflows/fathom-native-release.yml:64-85`

**Windows acquisition/extraction shape** (lines 68-85):

```powershell
$moonHome = Join-Path $env:USERPROFILE ".moon"
$moonBin = Join-Path $moonHome "bin"
New-Item -ItemType Directory -Force -Path $moonBin | Out-Null
$archive = Join-Path $env:RUNNER_TEMP "moonbit.zip"
$uri = "https://cli.moonbitlang.com/binaries/$env:MOONBIT_INSTALL_VERSION/moonbit-windows-x86_64.zip"
Invoke-WebRequest -Uri $uri -OutFile $archive
Expand-Archive -Path $archive -DestinationPath $moonHome -Force
$moon = Get-ChildItem -Path $moonHome -Filter "moon.exe" -Recurse | Select-Object -First 1
if ($null -eq $moon) { throw "moon.exe was not found after extraction" }
$moon.Directory.FullName | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
# ... core extraction ...
& $moon.FullName -C (Join-Path $moonHome "lib/core") bundle --warn-list -a --all
& $moon.FullName -C (Join-Path $moonHome "lib/core") bundle --warn-list -a --target wasm-gc --quiet
& $moon.FullName version
```

**Copy:** `Join-Path`, runner-temp archives, fatal `throw` on missing executable, appending the actual executable directory to `$GITHUB_PATH`, and both core bundle invocations.

**Correct:** consume Windows ZIP binary and ZIP core identities from the shared lock; use official checksum sidecars/locked vendor values; validate archive entries and expected roots before extraction; capture stdout without normalizing away the complete raw version; throw on any mismatch.

**Do not copy:** current guessed URI construction, unverified downloads, or `.tar.gz` core assumption. Research verifies official Windows installer semantics use `moonbit-windows-x86_64.zip` and `core-$Version.zip` (`14-RESEARCH.md:111-115`).

---

### `.github/workflows/ci.yml` (workflow config, batch/event-driven)

**Analog:** existing file; it is the authoritative command inventory.

**Exact three-target parity pattern** (lines 100-123):

```yaml
- name: Execute parity suite on linear-Wasm target
  run: moon test --target wasm --package parity
- name: Execute parity suite on native target
  run: moon test --target native --package parity
- name: Execute parity suite on JavaScript target
  run: moon test --target js --package parity
- name: Cross-backend byte-parity aggregate (compare_backends)
  run: python3 scripts/compare_backends.py
```

**Frozen baseline pattern** (lines 164-172):

```yaml
- name: Frozen-vs-current regeneration proof (diff_parity)
  run: python3 scripts/diff_parity.py --frozen-only
```

**Offline corpus and naming patterns** (lines 194-223):

```yaml
- name: Offline Flink corpus verifier
  run: python3 scripts/verify_corpus.py --check
- name: Corpus report --check
  run: python3 corpus/tools/generate_corpus_report.py --check
- name: Keyword classification check
  run: python3 corpus/tools/check_keywords.py corpus/keywords.tsv
- name: Neutral naming inventory
  run: python3 scripts/check_naming.py
```

**Assignment:** replace every duplicated moving install block with the shared exact-pin entry point. Ordinary CI and release CI must resolve the same committed identity. Preserve existing package-specific native test workaround (`ci.yml:58-68`) and all gate commands; do not invent another parity/corpus implementation.

**Negative-gate comment pitfall:** `scripts/check_naming.py` scans product workflow/config text line-by-line (`check_naming.py:84-108,142-162`). Comments containing forbidden legacy product terms can fail the naming gate even when executable YAML is clean. Conversely, over-broad exclusions can create a false green; the script deliberately fails on zero scanned files (`check_naming.py:163-183`). Keep workflow comments neutral and do not weaken the scanner/allowlist to accommodate a comment.

---

### `.github/workflows/fathom-native-release.yml` (workflow config, batch/event-driven/aggregation)

**Analogs:** its current matrix/aggregator plus exact gate commands above.

**Four-platform matrix** (lines 22-36):

```yaml
build:
  name: Build ${{ matrix.platform }}
  runs-on: ${{ matrix.runner }}
  strategy:
    fail-fast: false
    matrix:
      include:
        - platform: linux-x86_64
          runner: ubuntu-latest
        - platform: macos-x86_64
          runner: macos-14
        - platform: macos-aarch64
          runner: macos-14
        - platform: windows-x86_64
          runner: windows-latest
```

**Artifact co-location pattern** (lines 87-109):

```yaml
- name: Build Native LSP
  shell: bash
  run: |
    moon check --target native fathom-lsp
    moon build --target native --release fathom-lsp
    mkdir -p dist
    # copy platform binary into dist
- name: Upload Native asset
  uses: actions/upload-artifact@v7
  with:
    name: fathom-lsp-${{ matrix.platform }}
    path: dist/*
    if-no-files-found: error
```

Create each platform evidence record in `dist/` before this upload. Preserve `if-no-files-found: error`.

**Current publish barrier to replace** (lines 136-149):

```yaml
release:
  name: Publish GitHub Release
  needs: [build, linear-wasm-parity]
  # ...
  - name: Download Native assets
    uses: actions/download-artifact@v8
    with:
      pattern: fathom-lsp-*
      path: dist
      merge-multiple: true
```

**Required DAG:** introduce one Ubuntu `release-gates` job and set exactly `release.needs: [build, release-gates]`. Both tag and `workflow_dispatch` naturally enter the same jobs; add no skip input. Do not use `always()`, `continue-on-error`, or another workflow's historical status. All nine qualification commands run once in `release-gates`, not per platform (`14-RESEARCH.md:187-201`).

**Manifest aggregation:** extend the existing explicit-platform manifest loop (`fathom-native-release.yml:161-181`) rather than trusting artifact glob success. Accept exactly `linux-x86_64`, `macos-x86_64`, `macos-aarch64`, `windows-x86_64`; reject missing, duplicate, or unknown records; validate schema/non-empty fields; require one requested/reported identity across all records and equality with the lock; retain the four records plus lock identity in an aggregate release asset. Only then generate the existing binary SHA-256 manifest and invoke `gh release upload` (`fathom-native-release.yml:184-197`).

**Evidence landmine:** logs are diagnostic only. The record must be in each platform artifact and the aggregate must be a final release asset. `runnerArch` must be observed, not copied from the matrix label.

---

### `.github/workflows/jetbrains-plugin.yml` (workflow config, batch/event-driven)

**Analog:** current file itself.

**Exact scoped action pattern** (lines 25-46):

```yaml
- name: Check out source
  uses: actions/checkout@v7
- name: Set up JDK 21
  uses: actions/setup-java@v5
  with:
    distribution: temurin
    java-version: "21"
    cache: gradle
    cache-dependency-path: jetbrains/gradle/wrapper/gradle-wrapper.properties
# ...
- name: Upload plugin distribution
  uses: actions/upload-artifact@v7
  with:
    name: fathom-sql-intellij
    path: jetbrains/build/distributions/*.zip
    if-no-files-found: error
```

Commit this action-only state as-is. Do not modify Gradle, Kotlin, IDE compatibility, plugin publication logic, job triggers, or artifact naming.

---

### `.gitignore` (config, file-I/O)

**Analog:** current repository-root patterns (`.gitignore:1-12`).

```gitignore
.ace-tool/
_build/
__pycache__/
*.pyc

web/node_modules/
vscode/node_modules/
# ...
jetbrains/build/
```

Add repository-level `pkg.generated.mbti`, not `fathom-sql/pkg.generated.mbti`, so every MoonBit package's generated interface is covered while hand-written `.mbti` files remain trackable. Add only `.planning/research/.cache/` for the regenerable research cache; never broadly ignore `.planning/` or `.planning/.omp-*`.

If a generated interface is already tracked, untrack that exact path explicitly. Delete only the classified cache and the two untracked duplicate quick `PLAN.md` files; retain both tracked `SUMMARY.md` files and the five-file `v1.0-research` archive.

**Path-explicit hygiene commit pattern:** there is no source-code helper to copy. Planning must use an explicit allowlist of intended paths and fail on unexpected scoped status. Stage/commit named paths only; never `git add -A`, `git clean`, reset, stash, or a broad deletion. Exclude `.planning/.omp-next-action.json`, `.planning/.omp-task-results.json`, and `.planning/.omp-checkpoint.json` without reverting user/runtime state (`14-RESEARCH.md:222-249`).

---

### `scripts/validate_toolchain_evidence.py` or inline equivalent (utility, file-I/O/transform)

**Analogs:** release inline manifest (`fathom-native-release.yml:152-181`) and fail-closed naming validator (`scripts/check_naming.py:142-183`).

**Fail-closed validation shape** (`check_naming.py`, lines 142-183):

```python
problems = []
scanned = 0
# deterministically inspect inputs and append concrete problems
if scanned == 0:
    print("naming gate failed: 0 product files scanned ...", file=sys.stderr)
    return 1
if problems:
    for problem in problems:
        print("error: " + problem, file=sys.stderr)
    return 1
return 0
```

Use deterministic sorted traversal, accumulate actionable errors, require a non-empty/exact input set, return nonzero for every structural or identity mismatch, and write the aggregate only after all validation passes. The manifest analog supplies `Path.is_file()`, explicit platform mapping, SHA-256, stable `json.dumps(..., sort_keys=True)`, and terminal-newline conventions.

If kept inline in the workflow, do not create this file. If created for maintainability, it should own both validation and aggregate output so workflow YAML does not duplicate schema logic. Research does not mandate a focused test file; do not invent source-text/YAML tests.

## Shared Patterns

### One Exact Pin Source

**Source:** new `.github/moonbit-toolchain.json`, shaped by `fathom-native-release.yml:161-181` and mandatory freeze contract `14-RESEARCH.md:129-145`.

**Apply to:** both installer helpers, every MoonBit install in `ci.yml`, all release matrix builds, and `release-gates`.

There must be no workflow-level `latest`, inferred URL, duplicated version constant, environment fallback, or compiler-output-to-channel guess. Verify official binary and core checksums before execution; compare complete raw `moon version` after installation.

### Cross-Platform Installation

**Source:** Unix call sites `ci.yml:26-31`, release Unix architecture handling `fathom-native-release.yml:42-62`, Windows extraction/bundling `fathom-native-release.yml:64-85`.

**Apply to:** shared Unix and PowerShell entry points.

Preserve shell-native path/extraction behavior while enforcing the same lock/schema/failure semantics. Platform-specific code is allowed; platform-specific identity policy is not.

### Per-Platform Evidence

**Source:** release matrix/artifact layout `fathom-native-release.yml:22-36,87-109`; research contract `14-RESEARCH.md:203-220`.

**Apply to:** every matrix row before upload.

Evidence is generated from observed validated installation state, placed beside the platform binary, and uploaded through the existing `dist/*` artifact. Validate executable architecture for macOS x86_64 in addition to the existing output-binary `lipo` assertion.

### Release Gate DAG

**Source:** current explicit `needs` barrier `fathom-native-release.yml:136-149`; gate bodies `ci.yml:100-123,164-172,194-223`.

**Apply to:** release workflow.

`release-gates` is independent of the build matrix and runs once. `release` explicitly needs both `build` and `release-gates`; its write permission stays scoped to the publish job. No bypass, `always()`, `continue-on-error`, update mode, or external workflow status.

### Manifest Aggregation

**Source:** `fathom-native-release.yml:152-181`.

**Apply to:** publish job or focused validator.

Enumerate the exact platform set rather than trusting glob counts. Missing/duplicate/unknown records or requested/reported/lock disagreement are fatal. Generate stable JSON only after validation, then include it in `dist/*` with the existing product checksum manifest.

### Negative Gates Must Fail Visibly

**Sources:** `compare_backends.py:16-27,161-191`; `diff_parity.py:18-38,211-235`; `check_naming.py:142-183`; `verify_corpus.py:1-43`.

**Apply to:** `release-gates` and new evidence validation.

Existing conventions reject skipped targets, missing/empty trees, mutated snapshots, any frozen difference, zero scanned product files, malformed/non-empty corpus violations, and missing evidence. Do not turn absence into success. Be careful that comments are scanner inputs: a comment can itself trigger a negative naming match, while an over-broad exclusion can hide all inputs.

### Path-Explicit Hygiene

**Source:** locked classification `14-RESEARCH.md:222-249` (no executable analog).

**Apply to:** Phase 14 hygiene commits.

Use exact path allowlists, retain canonical history, delete only named regenerable/duplicate artifacts, and leave OMP runtime state untouched. Never broad-stage or broad-clean.

## No Analog Found

| File | Role | Data Flow | Reason / Verified Research Pattern |
|---|---|---|---|
| `.github/moonbit-toolchain.json` | config | file-I/O, transform | No immutable toolchain lock exists. Follow mandatory freeze fields and stop conditions in `14-RESEARCH.md:129-147`; JSON serialization style comes from release manifest lines 161-181 only. |
| Shared Unix installer helper | utility | request-response, file-I/O | Existing snippets pipe a moving installer and do not verify archives. Follow official semantics summarized at `14-RESEARCH.md:107-115` plus verify-before-execute at lines 167-174. |
| Shared PowerShell installer helper | utility | request-response, file-I/O | Current Windows block is the extraction analog but lacks sidecar verification and uses the wrong core archive form. Follow `14-RESEARCH.md:111-115,167-174`. |

A standalone evidence validator also has no exact analog, but the existing inline release manifest and fail-closed Python gates provide sufficient role-level patterns. No focused validation test is mandated (`14-RESEARCH.md:296-301`).

## Planner Landmines Checklist

1. Freeze official exact acquisition before editing workflows; no proven static four-platform set means Phase 14 implementation stops.
2. Never treat `moon version` as the static channel key or accept `latest`/nightly/redirected moving aliases.
3. Verify binary **and core** with official sidecars before extraction/execution; local hashes are not vendor authority.
4. Prove macOS x86_64 compiler and runner architecture; the current `macos-14` label alone is insufficient.
5. Generate evidence on each runner and publish both per-platform records and aggregate asset; logs do not satisfy TC-01.
6. Run Native, JS, and linear-Wasm parity plus all frozen/naming/corpus commands once in `release-gates`.
7. Make publication depend explicitly on both build and gates; never use `always()` or bypass inputs.
8. Keep all negative gates free of `--update`, `continue-on-error`, empty-result tolerance, or warning-only mismatch handling.
9. Treat YAML/comments as naming-scan input; do not mention forbidden legacy product identifiers in scanned comments and do not weaken exclusions to silence them.
10. Commit hygiene changes by explicit path allowlist; retain summaries/archive, remove only named cache/duplicate plans, and exclude rather than revert `.omp-*` runtime state.

## Metadata

**Analog search scope:** `.github/workflows/`, `.gitignore`, `scripts/`, `corpus/tools/`, Phase 14 context/research
**Strong analogs read:** 7 files (`ci.yml`, `fathom-native-release.yml`, `jetbrains-plugin.yml`, `.gitignore`, `compare_backends.py`, `diff_parity.py`, `check_naming.py`, plus the `verify_corpus.py` gate contract)
**Pattern extraction date:** 2026-08-13
