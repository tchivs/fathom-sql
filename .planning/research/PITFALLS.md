# Domain Pitfalls

**Domain:** Apache Doris SQL 解析器 SDK（MoonBit、无损 CST、Native/Wasm/JS、CLI/LSP）  
**Researched:** 2026-08-03  
**Evidence confidence:** LOW（研究抓取工具对 `websearch`/`webfetch` 的自动分级为 LOW；下文优先采用已直接读取的 Apache Doris、MoonBit、LSP、Tree-sitter 与 Prettier 官方文档，并把从其事实推出的工程结论标为推论）

## 风险排序

最可能造成重写或破坏用户信任的风险是：版本/语法权威失配、关键字分类错误、无损 CST 破坏 round-trip、错误恢复产生级联误诊、跨后端 ABI 不一致，以及 LSP 坐标/同步错误。它们都会让用户看到“数据库能执行而 SDK 拒绝”或“编辑器/格式化器悄悄改坏源码”，而不是普通的未覆盖语法报错。

## Critical Pitfalls

### Pitfall 1：把 `current` 文档或单一 Doris 语法当作永久规范（方言与版本漂移）

**What goes wrong:**

解析器在 Doris 2.1、3.x、4.x 或未发布开发版之间混用语法、关键字和示例；旧集群的合法 SQL 被报错，新版本语法被错误接受，或者同一 SQL 在不同配置下得到不同 CST。用户无法判断诊断是 Doris 真实错误还是 SDK 的版本错误，覆盖率数字也失去意义。

**Why it happens:**

Apache Doris 文档仓库明确同时维护 current（开发中）与 4.x、3.x、2.1 版本树，且 current 页面提示其为 unreleased 文档。Doris 的 MySQL 协议兼容层也不等于 MySQL 语法完全等价。把文档网页的“最新”地址、FE 当前源码、MySQL 关键字表拼成一个无版本表，会把独立演进的来源错误地合并。

**How to avoid:**

- 在 lexer/parser API 中强制 `DialectVersion`/feature profile（至少 2.1、3.x、4.x、dev），禁止隐式使用 current。
- 每个关键词、语法产生式和 corpus fixture 带版本标签，并区分 `introduced`、`deprecated`、`removed`、`accepted-but-not-reserved`。
- 将已发布 Doris 文档版本作为兼容目标；current 只作为候选变更输入，未经确认不得提升稳定规范。
- 记录“SDK 接受”与“FE 执行”两种状态，避免把未连接 FE 的纯语法结果宣传为执行兼容。

**Warning signs:**

- 同一个 fixture 在 CI 中随抓取日期改变结果。
- 文档 URL 没有版本目录、测试只引用 `master`/`current`，或 coverage 报表没有版本维度。
- 新增语法只改一个关键字表，没有对应版本记录和反例。
- issue 中出现“在 2.1 可执行但在 SDK 报错”或“格式化后旧集群拒绝”。

**Phase to address:**

**Phase 1（内核/版本化词法）**建立版本 profile、版本化 token/fixture 和拒绝混用的 API；**Phase 2（完整性）**对每个版本跑官方 corpus diff；**Phase 4（生态）**在 CLI/LSP 中暴露并持久化版本选择。

**Evidence confidence:** LOW（直接核验的 Apache Doris Website README；该 README 说明 `docs/`、`versioned_docs/version-4.x`、`version-3.x`、`version-2.1` 并存，且当前页面说明 current 为 unreleased）。

---

### Pitfall 2：把 MySQL 兼容性误当作关键字分类规则

**What goes wrong:**

未加引号的列名、表名、别名或属性名被误认为关键字；或者真正需要在特定语境下识别的 Doris 关键字被当成普通标识符。结果可能是合法 SQL 无法解析、Pratt 表达式在别名处走错分支、格式化器改变标识符大小写，甚至把用户的数据对象名打印成保留字。

**Why it happens:**

“兼容 MySQL 协议”和“ANSI SQL syntax”只描述接口定位，不是完整 Doris grammar/keyword contract。SQL 关键字往往有 reserved、non-reserved、contextual、功能/类型名等不同类别；关键字可否作为 identifier 还受引号形式和产生式上下文影响。把 `SELECT` 等词硬编码为唯一全局 enum，或者直接复用 MySQL 关键字表，会丢掉 Doris 的上下文和版本差异。

**How to avoid:**

- 维护版本化、可审计的 keyword matrix：拼写、大小写策略、类别、可用上下文、引用方式、引入版本、来源 URL。
- lexer 只产生稳定的词素/原文和候选 token；parser 在期待 identifier 的上下文用显式策略决定是否接受 contextual keyword。
- 保留 quoted/unquoted identifier 的原始文本、引号类型和 escape，不要在 CST 构造阶段规范化。
- 用成对反例测试：同一词作为关键字、未引用名称、反引号名称、字符串、函数名和别名；每个版本都验证。

**Warning signs:**

- keyword set 由 MySQL 或 SQL 标准库自动生成且没有 Doris 版本审阅。
- 失败只出现在 `SELECT keyword FROM ...`、别名、DDL 属性或反引号名称中。
- lexer 测试只断言 token 名，不断言原文、类别和上下文。
- 为了“让更多语句通过”把所有未知词降级成 identifier，之后诊断质量突然下降。

**Phase to address:**

**Phase 1（lexer/CST）**先定义 token/trivia/identifier 契约；**Phase 2（SELECT 与 DDL 完整性）**完成 keyword matrix 与上下文测试；**Phase 3（formatter）**确保保留字和标识符打印不变形。

**Evidence confidence:** LOW（直接核验的 Doris Overview 对 MySQL protocol-compatible/ANSI SQL 的表述；关键字分类的细化是基于 SQL parser 工程推论，需在实现阶段用版本文档与 FE 行为交叉核验）。

---

### Pitfall 3：官方文档语料抽取把展示内容当成可执行 SQL

**What goes wrong:**

corpus 把 Markdown 中的伪代码、命令提示符、输出、变量占位符、截断片段、不同语言 tab、注释说明或需要预先建表/设置 session 的 SQL 当成独立可执行样例。通过率虚高或误报大量 parser bug；更糟的是抓取器在文档改版时悄悄换样例，导致 golden 基线不可追溯。

**Why it happens:**

Doris 文档有版本目录、英文/中文镜像、侧边栏和代码块约定；页面可能包含多语种示例、SQL 与 shell 混合、输出块和语义前置条件。文档规范要求代码围栏语言标记，但不能证明每个 `sql` 围栏可以脱离上下文执行。文件移动、sidebar 变化和译文不同步也会制造重复或漏采。

**How to avoid:**

- 抽取器保存来源 URL、git commit、版本、文件路径、heading、代码围栏语言、行号和上下文，而不是只保存 SQL 字符串。
- 对 fixture 分类：`parse-only`、`requires-session`、`requires-catalog`、`executable`、`expected-error`、`not-sql`；不能自动判定的进入人工 review 队列。
- 对 SQL 做最小清洗并保留原始块；变量/省略号/输出不能被静默替换。双语文档按同一 case ID 对齐，不能按文本 hash 猜等价。
- corpus 更新必须产生新增/删除/变更报告，固定版本 release 时冻结输入；coverage 报告按文档版本和 fixture 类别统计。

**Warning signs:**

- 所有代码块都被标作 `parse-only` 或所有示例都被直接送进执行器。
- fixture 没有来源 commit/版本/heading；重跑抓取后 diff 很大但没有文档变更记录。
- 通过率上升但新增的 SQL 来自 shell、输出或占位变量。
- 中文与英文样例数量不一致，却没有 triage 清单。

**Phase to address:**

**Phase 2（官方 corpus/完整性）**实现可复现 manifest、分类和人工审阅；**Phase 4（CI/生态）**执行版本锁定、变更审计和可见的 coverage dashboard。

**Evidence confidence:** LOW（直接核验 Doris Website README 的版本目录与文档规范：代码围栏需标语言、文档维护有 current/4.x/3.x/2.1 分层；“代码块不必然可独立执行”属于由文档结构推出的工程结论）。

---

### Pitfall 4：无损 CST 名义上保留 trivia，实际 round-trip 仍丢字节或错位

**What goes wrong:**

注释、空白、换行、BOM、CRLF、字符串 escape 或未知 token 在 parse/print 后消失或移动；Span 在 Unicode、多字节 UTF-8、换行转换后与原文不一致。格式化、诊断和 LSP range 因此互相矛盾，用户最重视的“不会改坏源码”承诺失效。

**Why it happens:**

仅保存 AST 节点和“前后一个 comment 字符串”无法表达 trivia 所属边界、重复空行、尾随注释和错误 token。以字符索引代替 byte offset，或在 lexer 中先 normalize newline/Unicode，再把 normalized offset 当原始 span，会造成跨后端/跨编辑器偏移错误。无损与格式化是两种不同操作，若 printer 默认重建 token 而非使用原始叶节点，也会在未请求格式化时丢失信息。

**How to avoid:**

- CST 以 source buffer 为真相，叶节点保存原始 span；trivia 采用稳定的 leading/trailing/inner 关联规则，未知与错误 token 也进入树。
- 明确 byte offset、Unicode scalar、UTF-16 三套坐标的转换 API；永远不要在调用方自行换算。
- 定义强不变量：`print_lossless(parse(x)) == x`（字节级）；格式化另走 `format` API，并声明其可改变空白但不得改变 token/语义。
- 用 CRLF、混合换行、非 ASCII 标识符、emoji 注释、BOM、嵌套注释边界、EOF 注释和非法 byte 序列做 property/golden 测试。

**Warning signs:**

- round-trip 只用 `trim` 后字符串比较，或只测 ASCII/LF。
- CST 没有未知 token/错误 token，解析失败就丢弃剩余源文。
- 诊断位置在 Native 与 JS、VS Code 与 Monaco 之间相差一列或一行。
- printer 读取 AST 字段而不读取 token/trivia span。

**Phase to address:**

**Phase 1（内核）**在任何语法扩展前锁定 source/trivia/span 不变量；**Phase 3（格式化）**分离 lossless printer 与 pretty printer 并加入字节级回归。

**Evidence confidence:** LOW（由项目核心约束与 Tree-sitter 官方增量编辑 API 的 byte/point 双坐标要求交叉推导；需在 MoonBit 实现阶段进一步验证 UTF-8/UTF-16 细节）。

---

### Pitfall 5：手写递归下降的错误恢复把一次错误扩散成全文件假错误

**What goes wrong:**

缺少右括号、半成品 CTE、编辑中的字符串或错误 DDL 会触发无限循环、跳过下一条语句、产生数十个互相矛盾诊断，或者为了恢复而生成看似合法但语义完全错误的 CST。LSP 用户在输入过程中看到抖动的 diagnostics，无法定位真正错误。

**Why it happens:**

panic-mode 只按一个分号恢复会在分号缺失时吞掉后续 SQL；子句同步集合过宽会把错误 token 丢失，过窄则无法前进。Pratt parser 的 precedence、前缀/后缀运算符和错误节点若没有统一进度不变量，某些 token 序列会反复尝试同一产生式。把“恢复树”当“有效 AST”传给 analyzer/formatter，会把错误状态传播到下层。

**How to avoid:**

- 每个 parse routine 规定进度不变量（成功、显式 error node 或至少消费一个 token）；设置最大恢复步数和递归深度。
- 分层同步点：语句级 `;`/EOF，子句级 `SELECT/FROM/WHERE/GROUP...`，括号级 delimiter；恢复时保留 skipped tokens 和错误 span。
- 诊断对象区分 primary error、recovery note、suppressed cascade，并提供稳定 code/category；未闭合 delimiter 使用虚拟 token 但标记 synthetic。
- fuzz 半成品输入和删除/插入单字符场景，验证 parser 终止、错误数量有界、后续独立语句仍可解析。

**Warning signs:**

- 任意输入 parser 超时/栈溢出，或错误数随文件长度线性爆炸。
- 修改一处字符会让整个文档所有诊断位置大幅移动。
- error node 没有原始 span/token，formatter 只能猜缺失内容。
- analyzer 对 `recovered` 节点和 valid 节点没有区分。

**Phase to address:**

**Phase 1（SELECT/Pratt 与诊断内核）**建立 progress/recovery 契约和 fuzz harness；**Phase 2（DML/DDL）**为每类语句定义同步集合；**Phase 4（LSP）**验证编辑中诊断稳定性。

**Evidence confidence:** LOW（手写解析器行为属于工程推论；与项目规定的 statement panic-mode、clause best-effort recovery 直接相关，需用实现和 focused fuzz 进一步确认）。

---

### Pitfall 6：增量解析只重用树，却没有同步编辑后的 range、缓存和父节点

**What goes wrong:**

一次文本编辑后，节点 Span、token 索引、诊断或 symbol cache 仍指向旧位置；局部 parse 看似成功，但后续 edit 会越来越偏移。共享旧树时出现竞态，或把旧节点句柄交给新树后导致随机错误。最终编辑器中高亮、补全和诊断漂移，重启后问题“消失”而难以复现。

**Why it happens:**

增量解析不是只把旧 tree 作为参数传入。Tree-sitter 官方文档要求先用 `TSInputEdit` 更新旧树范围，再重解析；编辑前取得的节点若继续使用，还要分别更新节点位置；单个树实例也不是线程安全的。自研 CST 常见地只更新根 span，忘记 trivia、token cache、父链或外部分析索引。

**How to avoid:**

- 定义不可变 `TextEdit`，一次性携带旧/新 byte offset 与 line/column（含 UTF-16）；所有 span、trivia cache、diagnostic cache、索引从同一 edit 更新。
- 维护 revision ID；任何诊断、LSP response、CST handle 绑定 revision，过期对象拒绝使用。
- 增量路径必须有全量 parse 作为 oracle：随机编辑后比较 CST、diagnostics、lossless print 和关键节点范围。
- 跨线程只传不可变 snapshot 或显式 clone；不要共享可变 parser/tree。

**Warning signs:**

- 只测单次插入，不测连续编辑、删除、跨行替换和 undo/redo。
- 只有根节点 span 改变，叶 token 的 start/end 不做不变量检查。
- LSP 返回没有 document version，或 response 可晚于当前 revision 应用。
- 增量结果和全量结果不同却以“增量更快”为理由跳过比较。

**Phase to address:**

**Phase 1（CST/span 基础）**先完成 edit/span 模型；**Phase 4（LSP/生态）**再启用增量解析并用全量 oracle 做 CI；在此之前宁可使用可证明正确的全量 parse。

**Evidence confidence:** LOW（Tree-sitter 官方 Advanced Parsing 明确给出 `ts_tree_edit`、`ts_node_edit`、byte/point range 和线程安全限制；将这些限制映射到自研 CST 是工程推论）。

---

### Pitfall 7：golden/snapshot 测试锁住了错误实现或被“批量更新”驯化

**What goes wrong:**

快照只比较 AST 的序列化，漏测 trivia、span、diagnostics、版本或语义 token；或者一次格式化/grammar 重构后批量接受所有 snapshot，实际回归被掩盖。固定 fixture 很快变旧，测试全绿却没有随机错误输入、跨后端差异和真实文档覆盖。

**Why it happens:**

golden 测试易读、便宜，但它是结果记录而非正确性证明。解析器输出包含很多“可变表示”（节点 ID、内部顺序、错误恢复细节），若没有规范化会产生噪声；反过来过度规范化又可能抹掉真实的 span/trivia 回归。单一 golden 也无法说明格式化是否幂等、parse-print 是否无损或版本边界是否正确。

**How to avoid:**

- 分层 oracle：字节级 lossless round-trip、token/trivia/span、结构化 CST、diagnostics、formatter idempotence、版本 acceptance/rejection、跨后端一致性。
- snapshot 中固定 schema/version/source hash/fixture provenance；禁止无审阅的 `--update-snapshots`，要求变更说明和 diff 分类。
- 文档 corpus、手写边界样例、property-based/fuzz、Doris FE（可用时）分别统计；报告 mutation score 或至少包含故意破坏实现的负例。
- 对输出做稳定规范化只隐藏内部 ID，不隐藏源码位置、原始 token 和错误信息。

**Warning signs:**

- 测试主要是 `assert snapshot == file`，没有 round-trip/property/invariant。
- PR 中 snapshot 文件大面积变化却没有语法设计说明。
- coverage 只有“解析成功率”，没有误接受率和诊断稳定性。
- Native 通过而 Wasm/JS snapshot 未运行，或 fixture 没有版本标签。

**Phase to address:**

**Phase 1**建立最小 golden + property oracle；**Phase 2**将官方 corpus 和版本差分纳入 CI；**Phase 3**加入 formatter stability；**Phase 4**加入跨后端与 LSP E2E。

**Evidence confidence:** LOW（来自 parser/formatter 测试工程推论；需在项目建立首批 fixtures 后用故意注入 bug 的 focused checks 校验测试灵敏度）。

---

### Pitfall 8：MoonBit Native/Wasm/JS 的 ABI 和宿主假设泄漏进核心模型

**What goes wrong:**

Native CLI 能用的 parser API 在 JS 中因 String/Bytes/Array 表示、导出符号、异常/Result、内存生命周期或 host import 不同而失效；Wasm 模块在浏览器加载但在另一个 runtime 缺少 `env`/`moonbit:ffi`；Native 与 Wasm 输出不同的 span、整数溢出或诊断文本。团队被迫维护两套实现，违背“一套核心代码”。

**Why it happens:**

MoonBit 官方 FFI 文档列出五类 backend，并明确 Wasm 外部交互依赖 host；不同 backend 对 `Int`、`String`、`Bytes`、external type、callback 有不同 ABI。文档还说明未列出的类型表示不稳定、FFI signature 必须精确、`Unit` 对应 void；`#export_name` 有当前限制，native foreign-library 不能作为 library artifact。直接把 MoonBit 内部 struct/Array/exception 或 host-specific package 作为公开 SDK ABI，是把实现细节当协议。

**How to avoid:**

- 核心只暴露纯数据、固定整数/字符串/Bytes 边界和显式 Result；C/JS/Wasm wrapper 各自做转换，禁止外部依赖未承诺表示。
- 设计 versioned C ABI/JS API/Wasm export 清单：UTF-8 输入、owned/borrowed 生命周期、错误编码、最大输入限制、释放责任。
- 每次发布对 Native、Wasm、Wasm GC（若支持）、JS 分别跑同一 corpus、round-trip、diagnostic/span 和 API smoke test。
- 将 host imports、module name、export symbol 和 package kind 写入构建产物 manifest；不要依赖默认 `main`/运行时导出。

**Warning signs:**

- 公开函数参数包含 MoonBit 内部 ADT、泛型、callback 或 backend-dependent external type。
- 只在 Native 编译/测试；Wasm/JS 直到发布前才尝试链接。
- JS API 依赖对象 identity，Wasm API 却返回线性内存指针，或两者错误模型不一致。
- 改动 `#export_name`、`moon.pkg` 或 runtime 版本就出现链接/宿主导入错误。

**Phase to address:**

**Phase 1**定义纯核心与稳定数据边界；**Phase 4（生态输出）**定义并测试 backend-specific wrappers、ABI manifest 和兼容策略，不能把 ABI 作为最后的打包工作。

**Evidence confidence:** LOW（直接核验 MoonBit v0.10.5 FFI/package 文档的 backend、ABI stability、host import、export 与 native 限制；版本随 MoonBit 发布变化，执行阶段必须重新核对）。

---

### Pitfall 9：LSP 文本同步和坐标协商错误，使“正确诊断”显示在错误位置

**What goes wrong:**

服务器采用 UTF-8 byte offset，客户端按 UTF-16 code unit；`didChange` 的 range 用旧版本，服务器却按新文本应用；增量/全量同步能力协商错误；server 在初始化前发通知或没有响应 cancellation。结果是编辑丢失、诊断跳列、补全插入破坏字符串，且只在非 ASCII SQL 或特定编辑器中出现。

**Why it happens:**

LSP 不是仅输出 JSON diagnostics：Base Protocol 规定 JSON-RPC framing/lifecycle，Document Synchronization 规定同步模式、版本与变更序列，位置编码需要 capability negotiation。SQL 解析器内部的 byte/span 与 LSP 的 UTF-16/UTF-8/UTF-32 坐标不是同一坐标系；若没有中央转换层，各 handler 会各自猜测。

**How to avoid:**

- 初始化时协商 `positionEncoding`，默认行为按协议版本处理；内部统一保存 byte span，边界层集中转换并测试 surrogate pair、emoji 注释、CJK、CRLF。
- 明确文档 revision：拒绝/记录过期 change，按 `TextDocumentSyncKind` 正确处理 full/incremental；响应和 diagnostics 带相应 version 语义。
- 严格实现 initialize/shutdown/exit、publishDiagnostics、cancellation 和 capability gating；先做协议录制/回放，再接复杂功能。
- 用 VS Code/Monaco 等真实客户端做 E2E，并把原文、edit、期望 byte span 和 LSP range 全部记录。

**Warning signs:**

- 只用 ASCII、单行 SQL 测 LSP；没有 CJK/emoji/CRLF fixture。
- 客户端重连或快速连续输入后出现旧诊断覆盖新诊断。
- server 不保存 document version，或把 LSP range 直接当 CST byte span。
- `didChange` 能工作但 initialize capability 没有根据客户端声明调整。

**Phase to address:**

**Phase 4（CLI/LSP）**先实现协议边界、同步/revision/坐标转换，再实现 completion/formatting/hover；**Phase 1**必须提供可靠 span API 供边界层转换。

**Evidence confidence:** LOW（LSP 3.17 官方规范是协议主来源；此处具体故障模式是将规范的同步、坐标和生命周期要求映射到解析器集成的工程推论）。

---

### Pitfall 10：pretty printer 不幂等，或格式化器把“无损”误实现为“重建”

**What goes wrong:**

`format(format(sql))` 每次继续改变换行、括号、注释位置或尾随逗号；同一 AST 因原始 trivia 不同得到不同且不可逆结果。更严重时，关键字/字符串/注释边界被改写导致 Doris 语义变化。用户只想格式化一处却得到全文件 diff，随后停止信任工具。

**Why it happens:**

格式化是规范化，lossless print 是原文重放，两者目标不同。Prettier 官方 rationale 将输出正确性和可逆性作为重要原则，同时承认某些基于原始换行的 heuristic 会造成“非可逆”格式；SQL 还有注释附着、窗口/CTE、字符串、hint、方言特有 DDL 和语义敏感换行等额外边界。若 printer 同时承担修复错误树、补 synthetic token 和格式化有效树，结果更不稳定。

**How to avoid:**

- 提供两个明确 API：`print_lossless(cst)` 必须字节级回放；`format(cst, options)` 只接受有效/可证明恢复的树，并声明无法安全格式化时返回诊断而不是猜。
- 采用确定性的 doc/layout 算法；规定 comment ownership、blank-line policy、keyword case、line ending 和 trailing newline；同一配置下必须幂等。
- 每个 formatter 输出先重新 parse，再验证 token 序列/关键结构与原输入等价；对 Doris hint、字符串、反引号、动态分区、物化视图 DDL 做 golden + differential tests。
- 原始 trivia 作为布局输入但不让随机 token/节点 ID影响输出；选项变更纳入格式版本（format schema version）。

**Warning signs:**

- `format` 只能对比视觉输出，没测第二次输出是否相同。
- formatter fixture 的 token 序列变化没有人工批准，或注释只按最近节点重新挂载。
- 无法解析的输入被静默部分格式化并丢弃尾部。
- 用户报告每次保存都产生 diff、注释跨节点移动、SQL 执行结果变化。

**Phase to address:**

**Phase 3（格式化）**在 lossless printer 已稳定后实现；**Phase 4**通过 CLI/LSP 的 on-type/save formatting 做真实客户端验证，禁止在 Phase 1/2 以 formatter 掩盖 parser 缺陷。

**Evidence confidence:** LOW（直接核验 Prettier 官方 rationale 对 correctness、empty lines 和 non-reversible formatting 的说明；Doris 规则的具体集合仍需语料驱动）。

## Moderate Pitfalls

### Pitfall 11：未限制输入规模、嵌套深度和 token 数，嵌入式 SDK 被资源耗尽

**What goes wrong:**

极深括号/CTE、超长字符串、海量注释、重复运算符或无终止恢复路径导致栈溢出、超时和内存峰值；Wasm 页面卡死，LSP 阻塞所有请求，CLI 在 CI 中被 OOM kill。

**Why it happens:**

手写递归下降和 Pratt 天然依赖递归/循环；无损 CST 还保存原文/trivia/span，错误恢复可能制造大量 error nodes。解析器常在“正常 SQL”上做性能基准，却忽略不可信输入和半成品编辑文本。

**How to avoid / detection:**

设置字节、token、节点、递归深度、诊断数量和 wall-clock budget；超过预算返回带准确 span 的 resource-limit error，并保留可安全的前缀。做嵌套/长 token/随机 Unicode/注释 fuzz、峰值内存和 cancellation 测试；Native/Wasm 分别测。warning signs 是 latency 随嵌套深度非线性增长、单次输入占满 LSP event loop、Wasm UI 长任务警告。

**Phase to address:**

**Phase 1**加入 parser progress/limits；**Phase 4**在 CLI/LSP/Wasm API 让预算可配置且默认安全。

**Evidence confidence:** LOW（资源风险是基于递归 parser、无损树和嵌入场景的工程推论，需 focused fuzz/benchmark 量化阈值）。

---

### Pitfall 12：Parser、Analyzer、Formatter 的边界互相污染

**What goes wrong:**

为提高“解析成功率”，parser 调用 catalog 或猜列类型；formatter 依赖 analyzer 的解析结果；无 catalog 的 IDE 输入无法工作，缺少表元数据被误报为语法错误，后续语义扩展反过来破坏纯语法 API。

**Why it happens:**

Doris 语句同时有语法、session 属性、catalog 和 FE 执行语义；把这些层合并看似减少数据结构，实际让错误来源不可区分。项目明确要求 parser/analyzer 分离，但恢复节点、未解析名称和可选 catalog 若无稳定接口，后续开发仍会越界。

**How to avoid / detection:**

Parser 只消费文本和 dialect profile，输出 CST/diagnostics；Analyzer 接受 CST、可选 catalog、session profile 并产生独立 semantic diagnostics。测试必须覆盖无 catalog 纯语法、catalog 缺失、语义冲突三种状态；诊断 code 明确 `syntax`/`semantic`/`configuration`。warning signs 是 parser 构造函数需要数据库连接、语法测试必须准备 schema、formatter 在 analyzer 失败时停止。

**Phase to address:**

**Phase 1**冻结层接口；**Phase 2**扩展 DDL/DML 时用显式 session/profile；**M5+**再实现 analyzer/lint，不把它塞回首个解析器。

**Evidence confidence:** LOW（直接来自 PROJECT.md 的用户约束，架构后果为工程推论）。

---

### Pitfall 13：只跟踪 accepted SQL，不跟踪拒绝集合和“误接受”

**What goes wrong:**

coverage 只报告官方示例通过率，parser 为了高通过率过度宽松，接受 Doris FE 会拒绝的拼写、错误 clause 顺序或错误类型；用户把 SDK 的绿色诊断当作可执行保证，直到生产才失败。

**Why it happens:**

“能生成 CST”比“准确拒绝”容易量化。文档 corpus 多为 happy path，非法 SQL 样本稀少；恢复 parser 又天然倾向于继续构树。没有 negative corpus、FE differential 或 version-specific rejection policy，误接受不会暴露。

**How to avoid / detection:**

维护 `valid`、`invalid`、`version-invalid`、`requires-semantic` 四类 fixture；对每个新增宽松规则添加反例。可用 Doris FE 时做 parse/execute/dry-run differential；不可用时至少维护官方错误示例、grammar boundary 和 mutation-generated negatives。发布指标必须同时有 false accept rate、false reject rate、diagnostic locality。

**Phase to address:**

**Phase 2（完整性）**建立 negative corpus 与版本 rejection policy；**Phase 4**将 CLI/LSP 的诊断承诺文档化。

**Evidence confidence:** LOW（测试策略工程推论；与项目验收信号“非法 SQL 的诊断质量”直接对应）。

---

### Pitfall 14：通过复制 grammar/keyword 表绕过单一来源，后续升级出现漂移

**What goes wrong:**

lexer、parser、formatter、syntax highlight、LSP completion 各有一份关键字/产生式知识；修复只更新其中一份，CLI 接受而格式化器不识别，LSP 高亮与 parser 不一致，下一次 Doris 版本升级需要手工追查大量隐性分叉。

**Why it happens:**

不同消费者需要不同投影，直接复制最省事；Doris FE 自身也有 grammar/lexer 源码，SDK 若从其片段手抄而不保存来源和版本，容易形成“看起来相同”的独立实现。

**How to avoid / detection:**

建立单一 versioned language metadata（token spelling、precedence、keyword category、feature flags），生成或校验 highlight/completion/formatter projection；parser 手写逻辑仍可保留，但每个特殊 token 必须指向 metadata/source ID。CI 检测重复表、未映射 token 和版本 diff；新增关键字 PR 必须同时带正反例与来源。

**Phase to address:**

**Phase 1**定义 metadata/schema；**Phase 2**以 corpus 驱动维护；**Phase 4**为 LSP/highlighting 使用同一投影。

**Evidence confidence:** LOW（Doris repository 官方页面显示 FE 的 ANTLR4 grammar tree；“复制会漂移”是工程推论，不能把 FE grammar 当独立 SDK 规范）。

## Minor Pitfalls

### Pitfall 15：诊断文本、token 名和内部节点 ID 被当作稳定 API

**What goes wrong:**

客户端按错误消息字符串匹配，或把节点枚举顺序序列化后持久化；一次 parser 重构导致插件、snapshot 和 LSP UI 破坏。用户得到不兼容升级，却无法从 error code 判断迁移。

**Prevention / detection:**

公开稳定 error code、severity、span、expected token class；message 可本地化/改进。节点 schema 和 ABI 版本化，内部 ID 不出现在公开 JSON。对升级运行 fixture contract test。

**Phase to address:**

**Phase 1**诊断/CST schema；**Phase 4**SDK/LSP API versioning。

---

### Pitfall 16：行尾、编码和生成物处理不一致

**What goes wrong:**

Windows CRLF 被归一化后无法 lossless round-trip，Wasm 包含错误 source map，CLI 输出与 JS 输出的 newline 不同，golden 在不同平台反复变化。

**Prevention / detection:**

保留原始 source buffer 和 line-ending policy；测试 BOM、CRLF/LF、非 ASCII、空文件、无尾随换行；artifact 中固定编码并在跨平台 CI 校验 hash。

**Phase to address:**

**Phase 1**source/span；**Phase 4**distribution smoke tests。

---

### Pitfall 17：把 `#export_name`、默认入口或 runtime import 当作永久 ABI

**What goes wrong:**

MoonBit 工具链更新后导出名、package kind 或 host import 改变，消费者无法加载；依赖包里的 export 没有出现在下游 artifact，导致“本地能调用、发布包找不到符号”。

**Prevention / detection:**

用 wrapper package 明确导出，发布 exports manifest 和 ABI smoke test；不依赖未承诺的类型表示，记录 MoonBit toolchain 版本。逐 backend 检查真实 artifact 的 exports/imports，而不是只看源码注解。

**Phase to address:**

**Phase 4**生态打包和发布。

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|---|---|---|---|
| 只抓 current 文档 | 初期 corpus 很快 | 版本回归不可复现、旧集群不可信 | 永远不能作为稳定 fixture；仅可作候选 nightly 输入 |
| 先丢弃 trivia/span，后面再补 | AST 开发快 | 无法恢复注释关联和原始 offsets，通常需要重写 lexer/CST | 永远不适用于核心 parser；可在独立实验 AST 中使用 |
| 用一个全局 MySQL keyword set | lexer 简单 | Doris contextual/version keywords 全部错误 | 仅可作为候选词典，不能直接决定 parser 接受性 |
| snapshot 全量自动更新 | PR 容易变绿 | 真实回归随批量更新被吞掉 | 仅允许人工审阅、带 fixture/version diff 的更新 |
| 首先实现 LSP 增量路径 | Demo 延迟好看 | stale spans/revision bugs 难定位 | Phase 1/2 应先用全量 oracle；稳定后再启用 |
| 公开 MoonBit 内部 ADT/Array | 无 wrapper | Native/Wasm/JS ABI 绑定且不可升级 | 永远不作为跨语言公共 ABI |
| formatter 对错误恢复树“尽量输出” | 编辑器看起来不空白 | 悄悄改写未完成 SQL/注释 | 默认拒绝或仅 lossless print；安全修复需显式选项 |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|---|---|---|
| Doris 官方文档 | 抓 current 页面并把 URL 当版本 | 使用 versioned corpus manifest，记录 commit、heading、代码块类别和版本 |
| Doris FE（可选 differential） | 把 FE execute 结果当 parser contract，或忽略 session/catalog | 分离 syntax acceptance、semantic/execution result，并记录 FE 版本与 session |
| MoonBit Wasm/JS host | 假设所有 host 都提供相同 imports/ABI | 固定 host adapter、exports/imports manifest 和各 backend smoke tests |
| LSP client | 直接把 byte span 当 UTF-16 range，忽略 capability/version | 中央坐标转换、positionEncoding 协商、revision-aware sync 和真实客户端 E2E |
| Monaco/Web worker | 在主线程解析、跨 worker 传递内部对象 | 传输版本化文本/序列化结果，限制输入并取消过期请求 |
| Formatter/CLI | 将 lossless print 与 pretty format 混为一项 | 两个显式 API；formatter 输出重新 parse 且验证幂等/结构不变 |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|---|---|---|---|
| 深度递归 + 无深度预算 | 栈溢出、LSP 卡死 | 迭代化可行路径、深度/token/时间预算、fuzz | 恶意或半成品嵌套达到几千层即可；不要等生产 |
| 每个 CST 节点复制 trivia/source slice | 大 SQL 内存峰值、Wasm GC 压力 | source buffer + span/view，必要时 arena/immutable sharing | 百 MB 文本或高频 LSP 编辑时明显 |
| 每次编辑全量重建所有索引 | 输入延迟随文件长度增长 | 先正确的全量 baseline，再按 revision 分层增量 | 数万行 SQL 或连续输入时明显 |
| 每个诊断同步做 analyzer/catalog 查询 | keystroke 阻塞、旧结果覆盖新结果 | syntax first、异步可取消 analyzer、revision gate | 多文件 workspace/远端 catalog 时明显 |

## Security Mistakes

| Mistake | Risk | Prevention |
|---|---|---|
| 无界解析不可信文本 | CPU/内存 DoS，浏览器/语言服务器失去响应 | 限制输入、节点、递归、诊断和 wall time；支持 cancellation |
| 把 SQL 字符串直接拼入日志/JSON/HTML | 注释、控制字符或超大 literal 造成日志注入/前端 DoS | 结构化编码、长度上限、转义；诊断引用原文时截断并保留 span |
| FFI 接收裸指针/不明生命周期 | Native 崩溃、Wasm 越界或 use-after-free | 仅使用稳定 ABI 类型，明确 ownership，边界校验并做 sanitizer/host tests |
| 将 parser “接受”宣传为可执行安全保证 | 绕过 catalog/权限/FE 语义检查，给用户错误安全感 | 文档明确 parser-only；分析和执行校验分层，禁止执行副作用 |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---|---|---|
| 未选择 Doris 版本仍静默猜测 | 同一 SQL 在用户环境中行为不一致 | CLI/LSP/Web 明示 profile，并在诊断/结果中返回版本 |
| 保存时每次 formatter 都产生 diff | 用户关闭自动格式化，失去信任 | 幂等 printer、最小变更策略、保留注释和 line ending |
| 半成品 SQL 报成几十个错误 | 用户不知道改哪一处 | primary + recovery diagnostics、稳定范围、错误数量上限 |
| LSP 仅在 ASCII 样例中看似正常 | CJK/emoji 用户编辑被错位 | UTF-16/UTF-8 fixture、真实客户端回放、中央坐标转换 |
| 诊断把语法/语义/版本混在一起 | 用户误以为需要修改 SQL | 分层 severity/code/source，显示“需要 catalog/版本”的原因 |

## “Looks Done But Isn't” Checklist

- [ ] **版本覆盖：** 每个 fixture 有 Doris 版本、来源 commit、语法类别，并且 current 与稳定版本分开。
- [ ] **关键字：** 已测试 reserved/non-reserved/contextual、大小写、反引号、别名和同词不同上下文。
- [ ] **无损 CST：** `print_lossless(parse(x)) == x` 是字节级，不是 trim 后比较；包含 CRLF、BOM、CJK、emoji、EOF 注释和非法 token。
- [ ] **错误恢复：** parser 对所有错误输入都会前进并终止；后续语句仍可解析；诊断数量和范围有界。
- [ ] **增量：** 随机编辑的增量结果与全量结果比较过，含连续 edit、undo/redo、过期 revision 和跨行替换。
- [ ] **golden：** snapshot 更新有人工审阅；同时有 negative corpus、property tests、formatter idempotence 和误接受率。
- [ ] **跨后端：** Native/Wasm/JS 使用同一 corpus 验证 token/CST/span/diagnostic，真实 artifact exports/imports 已检查。
- [ ] **LSP：** initialize capability、position encoding、full/incremental sync、document version、cancellation 和 shutdown 均有回放测试。
- [ ] **formatter：** lossless 与 pretty API 分离；二次 format 无变化；输出重新 parse 且 token/结构/注释策略通过检查。

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---|---|---|
| 版本 corpus 混用 | HIGH | 冻结受影响 release；按 commit 重建 manifest；迁移 fixture 到版本 profile；发布兼容性说明和反例 |
| trivia/span 已丢失 | HIGH | 停止 formatter 扩展；回到 source buffer/lexer 契约；重建 CST 叶节点与 span；以字节级 round-trip 作为门禁 |
| 错误恢复级联 | MEDIUM/HIGH | 保留原始 token 流；加入 progress/recovery trace；缩窄同步集合；对旧诊断 golden 做迁移而非静默更新 |
| 增量 stale range | HIGH | 临时关闭增量、回退全量 parse；用 edit sequence 找首个 divergence；修 revision/cache 更新后再开启 feature flag |
| ABI 不一致 | HIGH | 保持旧 wrapper；按 artifact 检查 exports/imports；新增版本化 ABI adapter；跨后端 corpus 通过后再发布 |
| LSP 坐标/同步错误 | MEDIUM | 记录原始 JSON-RPC 和文档 revision；统一坐标转换；加入非 ASCII/快速输入回放；过期响应丢弃 |
| formatter 不幂等 | MEDIUM | 暂停自动保存格式化；固定 formatter options/schema；最小化 printer 规则；parse/format/format property 通过后恢复 |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---|---|---|
| 版本/方言漂移 | Phase 1–2 | 2.1/3.x/4.x 版本矩阵、来源锁定和 accepted/rejected diff |
| MySQL/Doris 关键字误分类 | Phase 1–2 | 上下文/引用/版本反例与 token metadata 一致性检查 |
| 文档 corpus 污染 | Phase 2 | 可重放 extractor、fixture 分类、来源 manifest、变更审阅报告 |
| 无损 CST 破坏 | Phase 1 | 字节级 lossless property、UTF-8/CRLF/trivia/span invariants |
| 错误恢复级联 | Phase 1–2 | malformed/partial fuzz、进度/终止/诊断 locality 检查 |
| 增量 stale state | Phase 1（模型）/4（启用） | 全量 oracle 对比、连续 edit、revision 和线程隔离测试 |
| golden 假绿 | Phase 1–3 | negative/property/differential tests；snapshot 更新审阅门禁 |
| Native/Wasm/JS ABI 漂移 | Phase 1（边界）/4（发布） | 三后端 artifact smoke、exports/imports manifest、同 corpus 结果一致 |
| LSP 坐标/同步错误 | Phase 4 | 3.17 协议回放、position encoding、非 ASCII 和真实客户端 E2E |
| formatter 不稳定/语义改变 | Phase 3 | format idempotence、reparse/token equivalence、注释/DDL/hint golden |
| 无界输入资源耗尽 | Phase 1/4 | fuzz、预算/cancellation、峰值内存和 Wasm 长任务基准 |
| Parser/Analyzer 越界 | Phase 1–2 | 无 catalog 语法测试与独立 semantic diagnostics contract |

## Sources

以下链接均为截至 2026-08-03 直接读取或核验的主来源；自动抓取 provider 的置信等级为 LOW，因此版本/实现细节在执行阶段仍需重新核对：

- Apache Doris Website README（版本树、current unreleased、英文/中文文档组织）：<https://raw.githubusercontent.com/apache/doris-website/master/README.md>
- Apache Doris 官方 Overview（MySQL protocol-compatible layer、ANSI SQL、FE 负责解析请求）：<https://doris.apache.org/docs/dev/getting-started/what-is-apache-doris/>
- Apache Doris 文档格式规范（SQL 代码围栏、版本文档修改、文档结构）：<https://raw.githubusercontent.com/apache/doris-website/master/community/how-to-contribute/docs-format-specification.md>
- Apache Doris FE ANTLR4 语法目录（官方仓库当前 grammar 组织）：<https://github.com/apache/doris/tree/master/fe/fe-core/src/main/antlr4/org/apache/doris/nereids>
- MoonBit Foreign Function Interface v0.10.5（backend、ABI、host imports、callbacks、exports、稳定表示限制）：<https://docs.moonbitlang.com/en/latest/language/ffi.html>
- MoonBit Package Configuration v0.10.5（`foreign_library`、`#export_name`、exports scope、native 限制）：<https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html>
- Language Server Protocol 3.17 Specification（JSON-RPC、生命周期、文本同步、位置与诊断协议）：<https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/>
- Tree-sitter Advanced Parsing（编辑树/节点的 byte-point ranges、增量重解析、线程安全）：<https://tree-sitter.github.io/tree-sitter/using-parsers/3-advanced-parsing.html>
- Prettier Rationale（correctness、空行策略、可逆/非可逆格式化）：<https://prettier.io/docs/rationale>

---
*Pitfalls research for: Doris SQL Parser SDK*  
*Researched: 2026-08-03*
