# 2026-08-27 PR #118 code review 修复批次

- **分支 / PR**: `fix/pr118-review-findings`（基于 `origin/next` @ `6c811948`，目标 [PR #118](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/pull/118)）
- **裁决登记**: [ReviewAdjudications.md](../ReviewAdjudications.md) A20 / A21 / A22

## 问题

用户诉求：对 PR #118（`next` → `main`，215 files，+11738/-1836）跑 `/code-review`，把发现"发给本项目另一个 agent 审核"，然后"改"。

review（effort: xhigh）产出 15 条 finding，经同项目另一会话按 CLAUDE.md 的「发现必答四问」逐条复核后收敛为：6 条确认需修、7 条部分成立、2 条误报。本批次处理其中定性最重的三族，并把两条误报与一条"真实但不可达"落进已裁决清单。

## 调研

三处代码全部在 `origin/next` 上只读核对（`git show`，不动工作区），每一处都做了红→绿验证。

### 一、协议扩展按裸名归并（review 发现 2）

`SwiftDeclarationIndexer.unifyExtensionContainers`（提案 0007，08-22 代码）用临时的 `[String: ProtocolDefinition]` 建查找表，key 取 `ProtocolName.name`。该名字以 `interfaceTypeBuilderOnly` 打印，**明确移除 private discriminator**，两个同名 `private protocol` 于是塌进一个 key，last-wins。

比 review 原文更重的一层：附着是**赋值**而非 append，所以碰撞时的序列是「先处理的桶被逐个标记 `isAttachedToProtocolDefinition`（顶层 extensions 块从此过滤掉它们）→ 随即被后一个桶的赋值覆盖出 `defaultImplementationExtensions`」，**该桶成员从输出中彻底消失**，且哪桶倒霉取决于字典迭代序。

关键发现是同文件里其它地方本就做对了：`allProtocolDefinitions` 以结构化的 `ProtocolName` 为键（两个同名协议本就分开存），紧邻的 `mergingSameIdentityContainers` 用 `StructuralNodeReferenceKey`，180 行外的 `typeInfo(for:node:)` 还专门写了 issue #115 的注释。只有这张临时表把它们压平。

### 二、`final` 恢复的 5 处 name-only 查找（review 发现 4/5）

`ClassDumper.vtableAccessorFieldNames` / `storedAccessorFieldNames`（3 处）与 `TypeDefinition.index` 的两处 `final` 门控走合并名字桶，而同一 PR 在三行外的成员循环里已改成传 node。属提案 0006（08-22）的代码被 issue #115 的 node 化清扫（`a77db414`，08-26）绕过——清扫按当次 diff 涉及的函数走，没有按「所有 name-only 重载的调用点」grep。

**但复现构造不出**，三条独立理由，均经实测（详见「与方案的差异」）。

### 三、全局导出注释多一个空行（review 发现 6）

`globalExportStatusComment` 自带尾部 `BreakLine()`，而调用方 `BlockList.buildComponents()`（sibling 包 `swift-semantic-string` 的 `Block.swift:271`）对每个非空条目已先发一个换行。`--emit-export-status` 下全局注释因此浮在被标注声明上方一个空行处，读起来像在标注上一条。成员路径的 `Rows` 设计正确，所以此前无人察觉。

### 复核推翻的两条

| 发现 | review 定性 | 复核终审 |
|---|---|---|
| walker 的 key 去重丢弃同 key 重复声明 | 渲染静默丢成员 | **误报**——本账本第 49 节记录在案的 deliberate 改动，旧行为被项目定性为 bug（A20） |
| `symbolCount` 把「无 storage」折叠成 0 | header 无证据也断言 | **误报**——`buildStorageSweep` 唯一出口是 `return Storage(...)`，nil 分支是死代码（A21） |

## 最终方案

| 修复 | 改法 | 规模 |
|---|---|---|
| 协议归并 | 查找表 key 换成结构化的 `ExtensionName`（`ProtocolName.extensionName` 现成可用，桶本就以 `ExtensionName` 为键，1:1 对应，赋值不再有覆盖风险） | 5 行 |
| `final` 5 处 | 全部改走 node 匹配，`contextNode` 拿不到时退回名字查找（沿用 `ClassDumper.members` 已确立的写法）；补齐两个缺失的镜像重载 | ~40 行 |
| 空行 | 删掉 `SwiftDeclarationPrinter.swift` 的一行 `BreakLine()` | 1 行 |

补齐的重载：`thunkAttributeMembers(of:for:node: Node,in:)`（原只有 `NodeReference` 版）与 `methodDescriptorMemberSymbols(of:for:node: NodeReference,in:)`（原只有 `Node` 版）。

**为什么协议归并这个修法安全**：协议定义侧的名字节点来自类型描述符，扩展桶侧来自符号扫描，出自不同 node store。若结构对不上，附着会整体失效——退回 main 的行为（扩展渲染在顶层，不丢数据），而既有的 `protocolExtensionBlockTrailsItsProtocol` 断言 `!attachedDefinitions.isEmpty` 会立刻变红。失败模式是「安全降级 + 测试立即告警」，不是静默错误。

## 实际执行

### 改动清单

| 文件 | 操作 | 说明 |
|---|---|---|
| `Sources/SwiftIndexing/SwiftDeclarationIndexer.swift` | 修改 | 附着查找表改结构化键控 |
| `Sources/SwiftDump/Dumper/ClassDumper.swift` | 修改 | 3 处 `final` 查找改 node 匹配，`contextNode` 引入 `fields` |
| `Sources/SwiftDeclaration/Components/Definitions/TypeDefinition.swift` | 修改 | 2 处 `final` 门控传已在作用域内的 `node` |
| `Sources/MachOSymbols/SymbolIndexStore.swift` | 修改 | 补两个缺失的镜像重载 |
| `Sources/SwiftPrinting/SwiftDeclarationPrinter.swift` | 修改 | 删多余 `BreakLine()` |
| `Tests/Projects/SymbolTests/SymbolTestsCore/PrivateDoppelgangers*.swift` | 修改 | 各加一对同名 `private protocol`（`alpha*` / `beta*` 默认实现）与同名 `private class`（`sharedNameMethod()` 一边非 final、一边 `final`） |
| `Tests/SwiftInterfaceTests/ExtensionContainerUnificationTests.swift` | 修改 | 2 个新测试；顺带修 `memberCarryingContainerIdentitiesAreUnique` 的身份键 |
| `Tests/SwiftInterfaceTests/ExportStatusAnnotationTests.swift` | 修改 | 全局注释相邻性测试（带非空洞守卫） |
| `Tests/SwiftInterfaceTests/FinalMemberRecoveryTests.swift` | 修改 | 防回归钉子 |
| `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/*.swift`（59 个） | 修改 | `regen-baselines` 重录 |
| 2 个快照 `.txt` | 修改 | `privateDoppelgangersSecondFileSnapshot`、`interfaceSnapshot` |
| `Documentations/Internal/{ReviewAdjudications,PrivateTypeMemberAttribution,ExtensionContainerUnification,ProjectEvolutionLog}.md` | 修改 | 见下 |

新增测试：

| 测试 | 类型 |
|---|---|
| `sameNamedPrivateProtocolsKeepTheirOwnDefaultImplementations` | 红→绿复现 |
| `sameNamedPrivateProtocolsResolveToDistinctDefinitions` | 模型层对应 |
| `exportStatusCommentIsAdjacentToItsDeclaration` | 红→绿复现 |
| `sameNamedPrivateClassesGetIndependentFinalVerdicts` | **防回归钉子，非复现** |

### 关键命令

```bash
git worktree add -b fix/pr118-review-findings /tmp/claude/Workspace/MachOSwiftSection origin/next
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj -scheme SymbolTestsCore \
  -configuration Release -derivedDataPath Tests/Projects/SymbolTests/DerivedData/SymbolTests build
swift package --scratch-path /tmp/claude/SwiftPM/MachOSwiftSection-Workspace \
  --allow-writing-to-package-directory regen-baselines
swift test --scratch-path /tmp/claude/SwiftPM/MachOSwiftSection-Workspace --skip IntegrationTests
```

红→绿验证的手法是 `git stash push -- Sources/`（夹具留在原地）后重建再跑，验完 `git stash pop`。

### 文档

- `ReviewAdjudications.md`：新增 A20（walker 去重，误报）、A21（`symbolCount` 折叠 0，误报）、A22（`final` 5 处，已修但复现构造不出，含三条不可达论证与复审条件）。
- `PrivateTypeMemberAttribution.md`：两条追记，**证否了原文「当时踩坑的全部位置」的完备性声明**，登记本批次的第 5、第 6 处漏网，并写下教训——node 化清扫要按「所有 name-only 重载的调用点」grep，判定完备性的命令是 `git grep -n 'memberSymbols(of:.*for:.*in: machO)'` 一族，不是"我改过的地方都看了"。
- `ExtensionContainerUnification.md`：新增「附着映射必须结构化键控」一节。
- `ProjectEvolutionLog.md`：新增第 50 节。

## 验证

- `swift build` 通过。
- 红→绿实证（协议）：

  ```
  修前：protocol …{} / protocol …{} / extension …{ betaDefaultProperty, betaDefaultMethod }   ← alpha 整块消失
  修后：protocol …{} / extension …{ alpha* } / protocol …{} / extension …{ beta* }
  ```

- 红→绿实证（空行）：临时把 `BreakLine()` 加回 → EXIT=1；删掉 → EXIT=0。
- `swift test --skip IntegrationTests`：重录基线前 1463 通过 / 23 个测试失败（**全部**为夹具偏移基线与快照失配）；重录后全量重跑 **1557 tests / 293 suites 全绿，退出码 0**（357 秒）。**判定一律以原始退出码为准**，不看 xcsift 摘要。
- ABI 基线重录：59 文件、96 增 96 删，逐行核对**全部是偏移族字段**，无语义漂移。
- 快照重录 2 个。其中 `interfaceSnapshot` 的 diff 是 **+62 行、0 删除**——纯新增，现有输出一字节未变，本身即是「修复不波及既有渲染」的证据。`privateDoppelgangersSnapshot` 未受影响（命名空间按类型名精确匹配，新类型不落入）。
- 已知 flaky：`SharedCacheTests.differentKeysParallelViaTaskGroup` / `…ViaAsyncLet` 用墙钟断言并行度，全量跑会假失败，单独跑必过——两次全量跑中出现在第一次、第二次未出现（最终全绿的那次它们也通过了），与本批改动无关。
- **未跑** rendering A/B 验证：本批未触及 demangling / printing / indexing / reader stack 的通用路径，改动全部收敛在「同名碰撞时选哪个桶」这一条件分支上，无碰撞时逐字节不变（interface 快照 0 删除即实证）。

## 与方案的差异

**夹具迭代了三轮，两次否定假设**，最终导致 `final` 那一族的定性与复核方不同。

- **差异点**：`final` 的 5 处从「确认需修的真 bug，配红→绿复现测试」降级为「真实但不可达，配防回归钉子」。
- **原因**：三条独立理由，均经实测——
  1. 第一版夹具用**存储属性**做复现：失败。私有类的存储属性访问器在 Release 下被内联，`accessors.isEmpty` 让证据门直接落空，两个类的 `final` 都印不出来。
  2. 第二版改用**方法 + `@objc`**（NSObject 子类）：失败。`objcThunkMemberNames` 门控只作用于存储字段，functions/variables/subscripts 三个循环读的是 per-member 的 `attributes.contains(.objc)`，而那个属性来自已经 node 匹配过的 `applyThunkAttributes`。
  3. 第三版试 **internal + private 同名**：被 Swift 编译器直接拒绝（`error: invalid redeclaration of 'PrivateDoppelgangerClass'`），这条路根本不存在。

  另经 `nm` 实证：`private` class **不发** `Tq` 方法描述符符号（`SymbolTestsCore` 全库 770 个 `Tq`，doppelganger 一个没有），所以负面证据门从任一兄弟都读不到东西。
- **影响**：代码仍然改（严格更安全的收紧、与 PR 自身在相邻代码声明的不变量一致、无碰撞时零行为差异），但复现结论落进 A22 并写明复审条件，避免下一轮 review 重复找复现。真实性成立、可达性不成立。

**另一处计划外收获**：修复暴露出既有测试 `memberCarryingContainerIdentitiesAreUnique` 犯了和生产代码同样的错——用去 discriminator 的字符串拼身份键，于是把两个**合法不同**的同名私有协议容器报成重复容器。身份键同样换成以 `ExtensionName` 值为分量的结构化 key，同批修掉。

**其余方案外事项**：无。三处修法与调研阶段定下的完全一致。

## 后续

尚未处理的 follow-up（复核已给出定性，均不阻塞合并）：`#13` refinement 静默丢弃、`#15` 无上限 task group（另需更新提案 0009 中被 actor 重入证伪的「actor 天然串行」依据）、`#1` opaque 越界 trap（存量债，非本 PR 引入）、`#8` CLI 进度写 stdout（存量债，5 处）、`#10` 的 subscript/extension 半边、`#14` 按修正方案、`#11`/`#12` 顺手项。

下一次接手可用的 skill：`code-review`（对照 `ReviewAdjudications.md` 跳过已裁决项）、`diagnose-bug`（follow-up 里 `#1`/`#15` 需要先造出能变红的复现回路）。
