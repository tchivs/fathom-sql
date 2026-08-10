# Phase 12: Cross-Dialect Corpus and Parity Gates - Pattern Map

**Mapped:** 2026-08-09
**Files analyzed:** 13（新增 7 项 + 修改 6 项，见 §9.1/§9.2 implementation surface）
**Analogs found:** 12 / 13（`scripts/compare_backends.py` 无同角色脚本模拟，取 CI job + 既有 gate 脚本复合模拟）

> 本阶段零 MoonBit 核心代码改动（D-01 边界：不新增 grammar/词法能力）。全部实现面 = Python stdlib gate 脚本 + parity 数据重组（manifest / `.sql` fixture / coverage.tsv）+ CI job + 注册表。因此本映射全部围绕「stdlib gate 脚本骨架」「manifest TSV 结构」「快照命名」「CI job 形态」四类既有模式展开。叙述用中文；代码/标识符/路径保留英文。

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `scripts/verify_corpus.py`（新） | utility（离线 manifest/hash 验证器） | file-I/O（只读 TSV/hash/快照树） | `scripts/extract_flink_lexical.py`（manifest sha512 复验 + 归档缺失跳过）+ `scripts/extract_flink_grammar.py`（problems+ok 出口门） | exact（角色+数据流一致） |
| `scripts/diff_parity.py`（新） | utility（冻结 vs 当前 diff harness） | file-I/O（快照树 diff + `moon test --update` 子进程） | `scripts/baseline_diff.py`（approved-vs-unexpected 引擎：parse_approve / walk_json / classify / --left/--right/--approve） | exact |
| `scripts/compare_backends.py`（新） | utility（三目标字节 parity 报告） | batch（subprocess 三 target + digest 比对） | `.github/workflows/ci.yml` `linear-wasm-parity` job（`moon test --target {t} --package parity`）+ `scripts/check_naming.py`（`scanned==0 → fail` 非空守卫） | partial（无既有 subprocess runner 脚本；取 CI job + guard 复合） |
| `parity/fixtures/flink/{profile}/{fixture_id}.sql`（新，~110 文件） | data（fixture raw 落盘） | file-I/O | `corpus/doris-{2.1,3.x,4.x}/*.sql`（31 文件）+ `parity/baseline-hashes.txt`（sha256 pin 先例）+ `parity/flink_grammar_test.mbt` `b"..."` 嵌入字节 | role-match |
| `parity/fixtures/flink/manifest.tsv`（新） | data（统一 manifest） | CRUD（TSV 行） | `parity/fixtures/flink-grammar/manifest.tsv`（11 列，97 fixture 行）+ `corpus/manifest.tsv`（15 列，示范 retrieval_date/heading/category/support_status 列） | exact |
| `corpus/flink-coverage.tsv`（新） | data（语义区分覆盖矩阵） | transform | `corpus/coverage.tsv`（7 列 header + 每类一行聚合） | exact |
| `corpus/CORPUS-REPORT.md` 增补（改） | doc（渲染输出） | transform | `corpus/CORPUS-REPORT.md`（由 `generate_corpus_report.py` 确定性生成） | exact |
| `scripts/baseline_diff.py`（改） | utility | file-I/O | 自身（加 `--frozen`/`--current` 别名；现接口已够，最小改） | exact |
| `scripts/extract_flink_grammar.py`（改） | utility | file-I/O | 自身（加 `b"..."` 嵌入字节 ↔ `.sql` 文件比对 + manifest 6 类枚举校验） | exact |
| `scripts/extract_flink_lexical.py`（改） | utility | file-I/O | 自身（加 13 行 fixture 的 6 类 + token 来源列校验） | exact |
| `corpus/tools/generate_corpus_report.py`（改） | utility | transform | 自身（读 `corpus/flink-coverage.tsv` 渲染双方言 + `--check` prerequisite 硬规则） | exact |
| `.github/workflows/ci.yml`（改） | config | event-driven（CI job） | 自身（既有 `parity-gate` / `linear-wasm-parity` / `corpus` job） | exact |
| `.planning/phases/12-…/approved-changes.md`（新） | config（D-08 注册表） | CRUD（机器可读行） | `.planning/phases/11-flink-grammar-and-recoverable-cst/approved-changes.md` | exact |
| `parity/flink_grammar_test.mbt` / `flink_lexical_test.mbt`（改） | test | event-driven（snapshot 断言） | 自身（仅注释/结构对齐；fixture raw 与测试内 4 类不动，A7） | exact |

---

## Pattern Assignments

### `scripts/verify_corpus.py`（新，utility，file-I/O）

**模拟 A（sha512 复验 + 归档缺失跳过）：** `scripts/extract_flink_lexical.py` `validate_manifest`（~408-470 行）。`verify_corpus.py` 的归档 sha512 校验与 fixture `.sql` sha256 校验都照此形态：**存在即复验、缺失即跳过（不是失败）**（D-06/Pitfall 3）。

```python
        archive_name = os.path.basename(row.get("source_archive_url", ""))
        archive_candidates = []
        if archive_name:
            archive_candidates = [
                os.path.join(archive_root, archive_name),
                os.path.join(RESEARCH_SRC, archive_name),
            ]
        present = [path for path in archive_candidates if os.path.isfile(path)]
        if not present:
            # Research-time fixture only — the archive is never shipped, so a
            # missing archive skips the hash check but keeps the metadata
            # assertions above.
            continue
        archive_path = present[0]
        with open(archive_path, "rb") as fh:
            digest = hashlib.sha512(fh.read()).hexdigest()
        expected_sha = row.get("sha512", "")
        if expected_sha != "N/A" and digest != expected_sha:
            problems.append(
                "flink-lexical manifest %s: sha512 of %s does not match the "
                "manifest column" % (fixture_id, archive_path)
            )
        else:
            verified += 1
```

**模拟 B（problems + `ok:` 出口门）：** `scripts/extract_flink_grammar.py` `main`（~320-337 行）——gate 脚本的标准出口：problems 非空 → 逐条 `error:` 到 stderr、`return 1`；否则 `ok: …` 计数行、`return 0`。

```python
    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1

    print(
        "ok: %d production line refs verified against pinned Parser-calcite "
        "files, %d Calcite-base reserved row sources verified "
        "(MATCH_RECOGNIZE/MATCH_NUMBER, Pitfall 9), %d flink-grammar manifest "
        "rows verified"
        % (production_verified, rows_verified, manifest_verified)
    )
    return 0
```

**模拟 C（header 精确匹配 + 字段数 + 枚举 + 非空守卫）：** `corpus/tools/check_keywords.py` `main`（76-103 行）+ `scripts/extract_flink_grammar.py` `parse_manifest`（~203-230 行）。

```python
    header = lines[0].split("\t")
    if header != HEADER:
        print("error: header mismatch: %r != %r" % (header, HEADER), file=sys.stderr)
        return 1
    problems = []
    ...
        if len(fields) != 4:
            problems.append(
                "line %d: expected 4 tab-delimited fields, got %d" % (lineno, len(fields))
            )
            continue
    ...
    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1
    print(
        "ok: %d keyword rows, %d production words covered"
        % (len(seen), len(PRODUCTION_WORDS))
    )
    return 0
```

**导入/骨架（从 RESEARCH Common Operation 1 落盘——直接给出）：**

```python
#!/usr/bin/env python3
"""Offline Flink corpus manifest/hash verifier (Phase 12, D-06; stdlib only)."""
import argparse, csv, hashlib, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "parity" / "fixtures" / "flink" / "manifest.tsv"
SNAPSHOT_DIR = ROOT / "parity" / "__snapshot__"
CATEGORIES = {
    "positive", "negative", "recovery", "known-limitation",
    "catalog-prerequisite", "planner-prerequisite",
}
# Mirrors dialect/flink.mbt FlinkProfileMetadata (verified in-repo).
PINS = {
    "flink-2.3.0":  ("1.36.0", "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"),
    "flink-2.1.3":  ("1.34.0", "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"),
    "flink-1.20.5": ("1.32.0", "Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT"),
}
```

**快照完整性命名（§8.1 第 6 条）——必须镜像测试内 snapshot filename 段：** flink 行 `{fixture_id}.{profile}.{mode}.json`（如 `flink-grammar.select-cte-join-agg.flink-2.3.0.strict.json`）；doris 行 `{fixture_id}.doris-{profile}.{mode}.json`（如 `flink-lexical.hash-comment.doris-4.x.strict.json`，profile 列 = `4.x`）。

```python
        seg = r["profile"] if r["dialect"] == "flink" else "doris-" + r["profile"]
        for mode in ("strict", "editor"):
            snap = SNAPSHOT_DIR / ("%s.%s.%s.json" % (r["fixture_id"], seg, mode))
            if not snap.is_file():
                problems.append("%s: missing snapshot %s" % (r["fixture_id"], snap.name))
```

**非空守卫（Pitfall 8）——仿 `scripts/check_naming.py:145-151`：** manifest 至少 1 行；快照文件数 == manifest 行数 × 2；`.sql` 文件数匹配。0 扫描必须 fail 而非 `ok: 0`。

```python
    if not rows:
        problems.append("manifest is empty")  # non-empty guard (Pitfall 8)
        return 1
```

**错误处理/退出码契约：** `--check` 模式 exit 非零（返回 1）；脚本入口统一 `if __name__ == "__main__": sys.exit(main(sys.argv))`（所有 gate 脚本一致）。

---

### `scripts/diff_parity.py`（新，utility，file-I/O）

**模拟（整文件）：** `scripts/baseline_diff.py`（270 行）。`diff_parity.py` 是 **wrapper**：frozen = committed 快照树 copy 到 temp；current = temp 里 `moon test --update --package parity` 生成（move/restore 不碰工作树，RESEARCH §6.2 工作流）；随后调用 baseline_diff 引擎 `--left temp/frozen --right temp/current --approve <register>`。approved/unexpected 归类与 exit 0/1 直接复用。

**注册表解析（复用 `scripts/baseline_diff.py:31-73` `parse_approve`）——三种机器可读行：**

```python
    """Parse the machine-readable section of the register.

    Line forms:
      key:<key>: <old> -> <new>   exact value replacement under a JSON key
      prefix: <old> -> <new>      prefix replacement of any JSON string value
      field: <name>               key may appear where it was absent
    Blank lines, comments (#), and code fences (```) are ignored.
    """
```

**diff 引擎（复用 `baseline_diff.py:100-149`）：** `is_approved_value` / `classify`（path 级 removed/added 配对，multi-document 快照多值配对 09-02 Rule 1）/ `diff_file`（非 JSON 字节比对 → unexpected）。

**CLI 形状（复用 `baseline_diff.py:150-178`）：**

```python
    parser.add_argument("--left", required=True, help="left snapshot directory")
    parser.add_argument("--right", required=True, help="right snapshot directory")
    parser.add_argument("--approve", required=True, help="approved-change register")
```

**出口门（复用 `baseline_diff.py:214-270`）：**

```python
    print(
        "ok: %d snapshots, %d approved diffs, %d unexpected"
        % (len(all_names), total_approved, total_unexpected)
    )
    return 1 if total_unexpected > 0 else 0
```

**新增 CLI 语义：** `--frozen-only`（CI 模式：跑 temp `--update` 再与 committed 树逐字节 + 逐 path 双通道比对，任何差异 exit 1）；`--approve <register>`（本地开发模式）。目录缺失 exit 2（沿用 baseline_diff 的 `return 2`）。

---

### `scripts/compare_backends.py`（新，utility，batch）

**无同角色脚本模拟**（仓库无 subprocess runner 脚本）——复合模拟：

**模拟 A（三目标运行形态）：** `.github/workflows/ci.yml` `linear-wasm-parity` job。`compare_backends.py` 对 `{native, js, wasm}` 依次跑同一条命令并捕获 rc + 失败快照名：

```yaml
      - name: Execute parity suite on linear-Wasm target
        run: moon test --target wasm --package parity
      # Byte-parity cross-check: run the identical suite on native so a wasm-only
      # regression cannot silently diverge from the reference target.
      - name: Execute parity suite on native target
        run: moon test --target native --package parity
```

**模拟 B（非空守卫 / 盲区防呆）：** `scripts/check_naming.py:145-151`——`scanned == 0 → fail` 是 gate 盲区守卫先例；`compare_backends.py` 需等价守卫（三 target 任一被跳过 = fail，快照树 digest 为空 = fail）。

```python
    if scanned == 0:
        print(
            "naming gate failed: 0 product files scanned — scan scope is empty "
            "(check ROOT, EXCLUDED_DIRS, and BUILD_OUTPUT_DIRS)",
            file=sys.stderr,
        )
        return 1
```

**核心逻辑（RESEARCH §7.2 + A8）：** wasm 无法 stdout dump（`parity/run_wasm.mbt` 注释「No println/env/host IO」）→ 比对物是 **`moon test --target {t}` 退出码 + 对 committed `parity/__snapshot__/` 算确定性 sha256 树 digest**。报告 per-target pass/fail + 失败 fixture 清单 + 三 target digest 一致性；任一 target 非 0 或 digest 不一致 → exit 1。

```python
# 骨架：对 native/js/wasm 依次运行 moon test --target {t} --package parity
# 捕获退出码与失败快照名；对 parity/__snapshot__/ 算三 target 一致的确定性 sha256
# 报告 per-target 状态 + 分歧 fixture 清单；任一 target 非 0 或 digest 不一致 → exit 1
```

**约束（RESEARCH §7.2.4）：** 序列化信封全为整数/字符串/字节数组（`fathom.parse.v1` 无 float；`source_bytes` 是整数数组；JS `Uint8Array` 由 binding 层归一为 int[]，`target-matrix.json` 注记）——digest 比对无需处理 float/字节序分歧。

---

### `parity/fixtures/flink/{profile}/{fixture_id}.sql`（新，~110 文件，data）

**模拟 A（`.sql` fixture 落盘先例）：** `corpus/doris-{2.1,3.x,4.x}/*.sql`（31 文件，`corpus/manifest.tsv` 44 行承载 provenance）。沿袭路径形态 `parity/fixtures/flink/{profile}/{fixture_id}.sql`，4 个 profile 目录：`flink-2.3.0` / `flink-2.1.3` / `flink-1.20.5` / `doris-4.x`（RESEARCH §9.1）。

**模拟 B（嵌入 raw 的源）：** `parity/flink_grammar_test.mbt` `FlinkGrammarFixture`（1-27 行）+ `parity/flink_lexical_test.mbt` `FlinkLexicalFixture`（30-34 行）——`.sql` 文件的字节源是测试内的 `b"..."` 字面量，**不替换嵌入字节**（Pitfall 6：只增新物）。

```moonbit
pub(all) struct FlinkGrammarFixture {
  pub fixture_id : String
  pub profile : String
  pub category : String
  pub raw : Bytes
}
...
  {
    fixture_id: "select-cte-join-agg",
    profile: "flink-2.3.0",
    category: "positive",
    raw: b"WITH o AS (SELECT user_id, amount FROM t1) SELECT u.name, SUM(o.amount) AS total FROM o JOIN users u ON o.user_id = u.id GROUP BY u.name",
  },
```

```moonbit
pub(all) struct FlinkLexicalFixture {
  pub fixture_id : String
  pub dialect : String
  pub profile : String
  pub raw : Bytes
}
```

**hash pin 先例：** `parity/baseline-hashes.txt`（44 corpus 文件 SHA-256，CI `sha256sum -c`）。flink 侧新增 `fixture_sha256` 列（manifest 第 14 列）pin 每个 `.sql` 文件，`verify_corpus.py` 用 `hashlib.sha256` 分块比对（RESEARCH Common Operation 1 `sha256_file`）。嵌入字节 ↔ `.sql` 一致性由 `extract_flink_grammar.py` 扩展（解析 `b"..."` 字面量）承担（D-08 embedded-raw provenance）。

---

### `parity/fixtures/flink/manifest.tsv`（新，data，CRUD）

**模拟 A（flink-grammar 11 列 header + 97 fixture 行）：** `parity/fixtures/flink-grammar/manifest.tsv:1` —— release-pinned provenance 现有形态：

```
fixture_id	profile	exact_release	calcite_version	parser_config	source_archive_url	sha512	git_tag	git_commit	grammar_path	line_range
flink-grammar.select-cte-join-agg	flink-2.3.0	flink-2.3.0	1.36.0	Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT	https://archive.apache.org/dist/flink/flink-2.3.0/flink-2.3.0-src.tgz	b189214e…	release-2.3.0	c0f8d1a…	Parser-calcite-1.36.0.jj:3395 (QueryOrExpr/WithList)	3395-3406
```

**模拟 B（Doris manifest 15 列 header——示范缺失的 5 列）：** `corpus/manifest.tsv:1`：

```
fixture_id	profile	exact_release	feature_introduction	official_url	retrieval_date	pinned_source_revision	page_heading	code_fence	category	support_status	parse_mode	classification	provenance_status
```

**模拟 C（flink-lexical release 级 4 行，需展开为 13 fixture 行）：** `parity/fixtures/flink-lexical/manifest.tsv:1-5`：

```
fixture_id	profile	exact_release	calcite_version	parser_config	source_archive_url	sha512	git_tag	git_commit
flink-2.3.0	flink-2.3.0	flink-2.3.0	1.36.0	Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT	https://archive.apache.org/dist/flink/flink-2.3.0/flink-2.3.0-src.tgz	b189214e…	release-2.3.0	c0f8d1a…
flink-1.20.5	flink-1.20.5	flink-1.20.5	1.32.0	Lex.JAVA,identifierMaxLength=256,conformance=FlinkSqlConformance.DEFAULT	…/flink-1.20.5-src.tgz	ce11ae5a…	release-1.20.5	09804850…
doris-4.x	doris-4.x	4.x	N/A (Doris official docs grammar — not Calcite-based)	Doris documented SQL grammar (official docs corpus, 4.x SELECT baseline)	https://doris.apache.org/docs/4.x/sql-manual/	N/A	N/A	N/A
```

**统一 schema（RESEARCH §5.1 推荐，planner 定稿）：** 合并两 manifest + 补 5 列 + 展开 lexical 13 行。`fixture_id` 前缀命名空间不相交（`flink-grammar.` / `flink-lexical.`）；`dialect` 列显式 `flink`/`doris`；新增 `source_url` / `heading` / `retrieval_date` / `category`（6 值枚举）/ `expected_status`（valid/error/recovered）/ `fixture_sha256` / `mode`（strict/editor）。**只增列不改既有 fixture_id/快照文件名**（Pitfall 6）。

**6 类枚举（D-01 语义权威，`verify_corpus.py` 枚举校验）：**

```
positive | negative | recovery | known-limitation | catalog-prerequisite | planner-prerequisite
```

判定优先级：`negative` > `recovery` > `known-limitation` > `planner-prerequisite` > `catalog-prerequisite` > `positive`（RESEARCH §5.3）。推荐单列 6 值 + 可选 `prerequisite_note` 列（Open Question 1）。

---

### `corpus/flink-coverage.tsv`（新，data，transform）

**模拟（header + 每类一行聚合）：** `corpus/coverage.tsv:1`：

```
profile	category	fixture_count	supported_count	expected_error_count	known_gap	coverage_note
2.1	industrial-select	1	1	0	pinned revision unavailable offline	SELECT hints, projection modifiers, table refs, joins, predicates, grouping, ordering, limit, UNION covered
```

**flink 侧 schema（RESEARCH §8.3）：** 复用 Doris 形态但把 supported/error 两列替换为语义区分列（**prerequisite 显式列为引擎支持=0**）：

```
profile	category	fixture_count	parser_accepted	parser_rejected	recovery	prerequisite	coverage_note
flink-2.3.0	planner-prerequisite	13	13	0	0	planner	**引擎支持=0**（显式列）
```

**硬规则（`--check` 强制）：** 任何 `catalog-prerequisite`/`planner-prerequisite`/`known-limitation` 行不得计入「engine supported」；报告输出两类合计（parser 接受 vs 引擎语义前置）；双方言同制（Doris 侧沿用 `supported`/`expected-error` 口径）。**禁止 `"100%"`/`"full compatibility"` 字样**（沿用 `generate_corpus_report.py` 的 CLAIM_PATTERN invariant）。

---

### `corpus/tools/generate_corpus_report.py`（改，utility，transform）

**模拟（自身——one-fixture-one-row invariant + CLAIM 扫描）：** `generate_corpus_report.py:200-260` `check_invariants`。扩展点：读 `corpus/flink-coverage.tsv`，渲染双方言报告；`--check` 加 prerequisite 硬规则（catalog/planner/known-limitation 不计入 engine supported）。

```python
    for path in [MANIFEST, COVERAGE, KEYWORDS, CORPUS / "differential.tsv", REPORT]:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for match in CLAIM_PATTERN.finditer(text):
            problems.append(f"full-compatibility claim pattern {match.group()!r} in {path.name}")
```

**`--check` 模式（staleness 判定）：** REPORT 与重新生成文本逐字节比较，stale → problem（`generate_corpus_report.py:245-255`）。

---

### `.github/workflows/ci.yml`（改，config，event-driven）

**模拟（自身——既有 job 形态）：** 三个被扩展的 job 现成先例：

- **`linear-wasm-parity`**（三目标运行时矩阵缺口）：现有只跑 `--target wasm` + `--target native`；① 增 `moon test --target js --package parity`（A10 推荐并入此 job）。
- **`parity-gate`**：现有三步 = `moon test --package parity`（无 `--update`）+ `baseline_diff.py --left __snapshot__ --right __snapshot__ --approve …/09/…`（自比对）+ `sha256sum -c parity/baseline-hashes.txt`；② 增 `python3 scripts/diff_parity.py --frozen-only`（把「冻结」从恒真自比对升级为可证重生成比对）。
- **`corpus`**：现有两步 = `generate_corpus_report.py --check` + `check_keywords.py`；③ 增 `python3 scripts/verify_corpus.py --check`；④ 新增 `compare_backends.py` 三 target 汇总 job（或并入 linear-wasm-parity）。

**安装 step 模板（新 job 直接复制）：**

```yaml
      - name: Set up Python
        uses: actions/setup-python@v6
        with:
          python-version: "3.11"
```

**约束：** `parity-gate` 注释明示 **NEVER add `--update` to CI**（Pitfall 1）；`verify_corpus.py` 不引入任何网络调用（Pitfall 5，stdlib 只读本地）；node 由 MoonBit js target 需要（本机 v25.2.0，RESEARCH §Environment）。

---

### `.planning/phases/12-…/approved-changes.md`（新，config，CRUD）

**模拟：** `.planning/phases/11-flink-grammar-and-recoverable-cst/approved-changes.md`（319 行）。沿用头部规则文本 + 分波快照表 + 机器可读注册行（`key:`/`prefix:`/`field:`）。Phase 12 预声明：统一 manifest 迁移若导致 flink 快照路径/文件名变化 → 注册；**Doris 213 零漂移为 HARD gate**（RESEARCH §9.2）。

```markdown
**Rule:** `moon test --update --package parity` is NEVER run without a
matching entry in this register already committed (single-use approval path —
research Pitfall 3/7). Any diff NOT in this register is a regression and must
be fixed, not absorbed. **Doris 213-snapshot zero-drift is a HARD gate:** ...
```

**机器可读行格式（`baseline_diff.py parse_approve` 消费）：**

```text
key:<key>: <old> -> <new>   # 精确 JSON key 值替换
prefix: <old> -> <new>      # JSON 字符串前缀替换
field: <name>               # key 允许出现在原本缺失处
```

---

## Shared Patterns

### Python stdlib gate 脚本骨架（应用：verify_corpus.py / diff_parity.py / compare_backends.py / 三个扩展脚本）
**Source:** `scripts/baseline_diff.py:1-30` + `scripts/extract_flink_grammar.py:1-25` + `corpus/tools/check_keywords.py:1-40`
**Apply to:** 全部新/改 gate 脚本
```python
#!/usr/bin/env python3
"""<D-XX> <purpose> (Python stdlib only). ..."""
import argparse, hashlib, os, pathlib, sys
# Repo layout: scripts/<name>.py -> repo root.
ROOT = pathlib.Path(__file__).resolve().parents[1]
...
def main(argv):
    problems = []
    ...
    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1
    print("ok: ..." % ...)
    return 0
if __name__ == "__main__":
    sys.exit(main(sys.argv))
```
（`verify_corpus.py` 用 `main(argv)`；`check_naming.py` 用 `main()` 无参——两个先例并存，新脚本推荐带参形态以便 `--check`。）

### problems + `ok:` 出口模式（应用：所有新 gate 的 `--check` 模式）
**Source:** `scripts/extract_flink_grammar.py:322-337`；`corpus/tools/check_keywords.py:96-103`
**Apply to:** verify_corpus.py / compare_backends.py / generate_corpus_report.py 扩展
```python
    if problems:
        for problem in problems:
            print("error: " + problem, file=sys.stderr)
        return 1
    print("ok: %d ..." % (n))
    return 0
```

### 非空守卫（应用：verify_corpus.py / compare_backends.py / generate_corpus_report.py 扩展）
**Source:** `scripts/check_naming.py:145-151`（`scanned == 0 → fail`）
**Apply to:** 所有「扫描/聚合」类 gate —— 0 行 manifest、0 快照、0 `.sql`、0 目标都必须 fail 而非 `ok: 0`（Pitfall 8）。

### approved-vs-unexpected 注册表引擎（应用：diff_parity.py；baseline_diff.py 扩展）
**Source:** `scripts/baseline_diff.py:31-73`（parse_approve）+ `:100-149`（classify/diff_file）+ `:150-178`（CLI）+ `:214-270`（出口门）
**Apply to:** `diff_parity.py --approve <register>`（冻结 vs 当前）与 CI `--frozen-only`；三种注册行 `key:`/`prefix:`/`field:`。

### 归档存在即验、缺失即跳过（应用：verify_corpus.py 归档 sha512）
**Source:** `scripts/extract_flink_lexical.py:438-465`（validate_manifest 内）
**Apply to:** `/tmp/flink-research/*.tgz` sha512 —— 缺失报 `archive-not-present (research fixture)` 状态，**不 fail 不伪造**（D-06 / Pitfall 3）。

### 快照命名段（应用：verify_corpus.py 快照完整性；manifest `mode` 列）
**Source:** `parity/__snapshot__/`（433 文件，RESEARCH §4.2）+ `parity/flink_grammar_test.mbt:7-10` + `parity/flink_lexical_test.mbt:13-16`
**Apply to:** `verify_corpus.py` 第 6 步（每 fixture 两个快照 strict+editor 必须存在）
```
flink-grammar.{fixture}.flink-2.3.0.{strict,editor}.json     # flink-grammar 194 = 97×2
flink-lexical.{fixture}.flink-{v}.{strict,editor}.json       # flink 侧（seg = profile）
flink-lexical.{fixture}.doris-4.x.{strict,editor}.json       # doris 侧（seg = "doris-"+profile）
```

### D-08 注册批准流（应用：diff_parity.py / CI parity-gate 增强 / 12-approved-changes.md）
**Source:** `.planning/phases/11-…/approved-changes.md:1-30` + `baseline_diff.py:31-73`
**Apply to:** 任何 `--update` 前必须先 commit 注册表条目；unexpected 一律走人工裁决（docs-vs-parser / release 事实 vs docs / 实现有意变更 三通道，RESEARCH §9）；**NEVER add `--update` to CI**。

### 确定性报告生成 + `--check` staleness（应用：generate_corpus_report.py 扩展）
**Source:** `corpus/tools/generate_corpus_report.py:245-255`（REPORT 与重新生成逐字节比较）
**Apply to:** 双方言 CORPUS-REPORT.md 增补——报告必须由脚本确定性生成，`--check` 判定 stale。

## No Analog Found

无完全同角色脚本先例的文件（planner 应以 RESEARCH 模式为主、以上述复合模拟为辅）：

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `scripts/compare_backends.py` | utility | batch | 仓库无 subprocess runner 脚本；取 CI `linear-wasm-parity` job（三 target `moon test` 形态）+ `check_naming.py`（非空守卫）+ RESEARCH §7.2 骨架复合。wasm 无法 stdout dump（A8）→ 用退出码 + 快照树 sha256 digest 比对 |
| `parity/fixtures/flink/{profile}/{fixture_id}.sql`（~110 文件） | data | file-I/O | `corpus/doris-*/` 是 31 文件规模的 Doris 侧先例；flink 侧 110 文件落盘是规模与来源（嵌入 `b"..."` 提取）上的新物——来源模式见 `flink_grammar_test.mbt:29-45` |

## Metadata

**Analog search scope:** `scripts/`（baseline_diff.py 270L / extract_flink_lexical.py 602L / extract_flink_grammar.py 337L / check_naming.py 189L）、`corpus/tools/`（check_keywords.py / generate_corpus_report.py）、`corpus/`（manifest.tsv 44 行 / coverage.tsv）、`parity/fixtures/`（flink-grammar manifest 97 行 / flink-lexical manifest 4 行 / corpus.json / target-matrix.json）、`parity/__snapshot__/`（433 快照，命名段核验）、`parity/`（moon.pkg / flink_grammar_test.mbt / flink_lexical_test.mbt）、`.github/workflows/ci.yml`（6 job）、`.planning/phases/11-…/approved-changes.md`（注册表格式）
**Files scanned:** 14（12 模拟源 + 2 数据 header 源）
**Pattern extraction date:** 2026-08-09

---

*Phase: 12-Cross-Dialect Corpus and Parity Gates*
*Patterns mapped: 2026-08-09*
