# 同名私有类型的成员归属：name key 不是单射（issue #115 修复说明）

> 修复 [issue #115](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/issues/115)：`swift-section dump` 把同名但私有判别符（private discriminator）不同的类型的成员混进彼此的声明。本文记录不变量本身、当时踩坑的全部位置，以及后续新增消费者必须遵守的规则。面向维护者。

## 不变量：成员索引的字符串 key 会把同名私有类型折叠成一个桶

`SymbolIndexStore` 的成员类索引统一是三层结构：

```
memberSymbolRowsByKind[MemberKind][打印后的类型名 String][interned 上下文节点 NodeIndex] → SymbolRowBucket
```

其中「打印后的类型名」用 `DemangleOptions.interfaceTypeBuilderOnly` 生成，而 `.interface` 系列选项**刻意移除了 `.showPrivateDiscriminators`**（这是渲染层的正确决定——interface 输出不该带 `_6FA990C1…` 这类噪声）。代价是这个 key **不是单射**：

- `(ArchivableDisplayList in _6FA…)` 和 `(ArchivableDisplayList in _AEFE…)` 打印成同一个字符串，落进同一个 name 桶；
- 只有第三层的 interned 上下文节点（保留了 `privateDeclName` 子树）还能区分它们。

因此规则是：

> **凡是「解析某一个类型自己的成员/信息/属性」的查询，必须走带 `node:` 参数的重载**（结构匹配挑出正确的子桶）；name-only 重载的语义是「把打印成这个名字的所有类型聚合在一起」，只用于确实需要聚合的场景，且其文档已注明这一点。

带 `node:` 的重载：`memberSymbols(of:for:node:in:)`、`methodDescriptorMemberSymbols(of:for:node:in:)`、`typeInfo(for:node:in:)`、`thunkAttributeMembers(of:for:node:in:)`。查询节点既可以是 `MetadataReader.demangleContext` 产出的树（descriptor 侧），也可以是符号侧 demangle 的树——两侧对私有类型都会生成结构相等的 `privateDeclName` 上下文，这正是 interface 路径（`TypeDefinition.index`）一直归属正确的原因。

## 当时踩坑的全部位置（2026-08-26 修复批次）

| 位置 | 症状 | 修复 |
|---|---|---|
| `StructDumper` / `EnumDumper` / `ClassDumper` 的 `body`（含 `ClassDumper` 的 methodDescriptor 段） | **issue #115 本体**：dump 输出把两个同名私有类型的 init/方法互相混入 | demangle 出 descriptor 的上下文节点，改走 `node:` 重载；上下文 demangle 失败时回退 name-only（宁可合并也不丢成员，且此时连类型名都打不出来，属退化场景） |
| `TypeDefinition.index` 的 `deallocatorSymbol` / `destructorSymbol` | name-only `.first` 可能拿到同名兄弟的 deinit 地址 | 改走 `node:` 重载 |
| `applyThunkAttributes`（`@objc` / `@nonobjc` / `@distributed` 交叉标注） | thunk 桶只按名字，成员再按**成员名字符串**匹配——同名兄弟的同名成员会被错误盖章 | thunk 索引补上第三层节点 key，查询走 `node:` 重载 |
| `typeInfoByName`（`indexExtensions` 判定扩展目标的 kind） | 原为 `[String: TypeInfo]` last-wins，同名不同 kind 时后写者覆盖 | 改为 name → node → `TypeInfo` 两层；`indexExtensions` 传 node |

dump 路径从未做过区分（0.14.0 即有此病，非回归）；interface 路径的主查询一直带 node，只有上表后三处漏网。

### 追记（2026-08-27）：上表并不完备 —— PR #118 review 又扫出 5 处

本节标题原写作「当时踩坑的**全部**位置」，PR #118 的 code review 证否了这个"全部"。同一批次里 `final` 恢复（提案 0006）的 5 处符号查找仍是 name-only，而它们是 08-22 的代码、写在 08-26 的 node 化清扫**之前**，恰好被清扫的 diff 绕过：

| 位置 | 门控 | 修复 |
|---|---|---|
| `ClassDumper.vtableAccessorFieldNames`（`methodDescriptorMemberSymbols`） | 负面证据：有 `Tq` 即非 `final` | 新增 `contextNode` 参数，走 `node:` 重载 |
| `ClassDumper.storedAccessorFieldNames`（`memberSymbols` + `thunkAttributeMembers`） | 正面证据门 + `@objc` 排除 | 同上 |
| `TypeDefinition.index` 的 `@objc` 门控（`thunkAttributeMembers`） | 排除 `@objc` 成员 | 传已在作用域内的 `node` |
| `TypeDefinition.index` 的 `Tq` 门控（`methodDescriptorMemberSymbols`） | 负面证据 | 传已在作用域内的 `node` |

修复同时补齐两个缺失的镜像重载（`thunkAttributeMembers` 缺收 `Node` 的、`methodDescriptorMemberSymbols` 缺收 `NodeReference` 的）。

**但这 5 处构造不出触发场景**（`private` class 既不发 `Tq` 也不发存储属性访问器符号；Swift 拒绝同名的 `internal`/`private` 配对），所以修复带的是防回归钉子而非红→绿复现。完整论证与复审条件见 [`ReviewAdjudications.md`](ReviewAdjudications.md) 的 A22。

**教训**：一次 node 化清扫要按「所有 name-only 重载的调用点」grep 一遍，而不是按当次 diff 涉及的函数走。判定完备性的命令是 `git grep -n 'memberSymbols(of:.*for:.*in: machO)'` 一族，不是"我改过的地方都看了"。

### 追记（2026-08-27）：同一族的第 6 处 —— 协议扩展归并

`SwiftDeclarationIndexer.unifyExtensionContainers`（提案 0007，08-22 代码，同样早于清扫）用一个临时的 `[String: ProtocolDefinition]` 把协议按打印名归并，last-wins；而附着是**赋值**不是 append，于是碰撞时输者的整桶成员先被标记移出顶层 extensions 块、再被赢者覆盖出 `defaultImplementationExtensions`——**从输出里彻底消失**。这一处**复现成立**（fixture `PrivateDoppelgangerProtocol` 对，修前只渲染出一块扩展且只含 `beta*`，修后各归各）。修法是把 key 换成结构化的 `ExtensionName`（`ProtocolName.extensionName` 现成可用），详见 [`ExtensionContainerUnification.md`](ExtensionContainerUnification.md)。

## 修复时刻意不做的事

- **不给 name key 恢复判别符**。改 key 格式会波及 `typeInfoByName`、`memberSymbols(of:excluding:)` 的排除集合、RuntimeViewer 侧的既有调用等一整片消费者，而收益与「查询侧带 node」完全等价。
- **name-only 重载保留不删**。它们是公开 API（RuntimeViewer 可能在用），语义改为文档化的「聚合/first-wins」。

## 复现与回归防线

- fixture：`SymbolTestsCore` 的 `PrivateDoppelgangers.swift` + `PrivateDoppelgangersSecondFile.swift`——两个文件各声明一个顶层 `private struct PrivateDoppelganger`，成员集合刻意不相交（`alpha*` vs `beta*`）。注意其中的防优化手段：`@_optimize(none)` 保住未特化的成员符号（否则 Release 只剩 `Tf4nd_n` 特化 thunk，成员索引不识别），anchor 把实例装箱成 `Any` 保住 descriptor 与 field descriptor（否则整个类型被优化掉——首版 fixture 实测如此）。
- 断言测试：`SwiftDumpTests.PrivateTypeMemberAttributionTests`（修复前双向混入、修复后各归各，红→绿验证过）。
- 协议对（2026-08-27 追加）：`SwiftInterfaceTests.ExtensionContainerUnificationTests.sameNamedPrivateProtocolsKeepTheirOwnDefaultImplementations` / `…ResolveToDistinctDefinitions`，红→绿验证过。
- 类对（2026-08-27 追加）：`SwiftInterfaceTests.FinalMemberRecoveryTests.sameNamedPrivateClassesGetIndependentFinalVerdicts` —— **防回归钉子，不是复现**，理由见 A22。
- 快照：`SymbolTestsCoreDumpSnapshotTests.privateDoppelgangersSnapshot` 把两个声明并排钉死；全模块 interface 快照同时钉住 interface 路径的正确归属。
- 索引层：`SymbolIndexStoreFixtureTests.typeInfoLookupMatchesIndexedNames` 同时校验 name-only（first-wins）与 node 匹配两条路径。
