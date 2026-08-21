# lint

> [根级 CLAUDE.md](../CLAUDE.md) › lint

## 职责

Lint 规则引擎：CST 遍历 + 语句族分发 + 规则判断。支持规则覆盖和自动修复。

## 关键文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `engine.mbt` | 493 | 规则引擎核心、CST walk、语句族分发 |
| `rules.mbt` | ~200 | 规则定义、LintSeverity |
| `registry.mbt` | ~150 | 默认注册表、LintOptions |
| `fixes.mbt` | ~100 | 自动修复（apply_fixes） |

## 公开接口

```moonbit
pub fn run_rules(root, source, options : LintOptions, analysis : AnalysisResult?) -> LintResult
pub fn apply_fixes(root, source, findings : Array[LintFinding]) -> Bytes
pub fn LintOptions::new(overrides : Array[RuleOverride]) -> Result[LintOptions, LintOptionsError]
pub fn LintSeverity::from_id(id : String) -> LintSeverity?
pub fn default_registry() -> Array[LintRule]
```

## 依赖

- **上游**：`syntax` `dialect` `source` `formatter` `analyzer` `buffer` `debug`
- **下游**：`api` `test`

## 测试

`lint_test.mbt`（黑盒），由 `test/lint_test.mbt` 补充。

## 注意事项

- 关键字判断用 `@dialect.classification_of` / `@dialect.is_reserved_word`——**无第二张关键字表**（Pitfall 14 / naming gate）
- analyzer 支持的规则（004-007）仅在调用者注入 `AnalysisResult` 时触发；无 catalog 时静默跳过，语法校验通道不受影响（ANLY-01）
- LintOptions 支持规则覆盖（`RuleOverride { code, setting }`）
- 支持自动修复模式（`fix=true` 时调用 `apply_fixes`）
