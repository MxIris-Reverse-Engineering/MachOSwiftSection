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

## 修复时刻意不做的事

- **不给 name key 恢复判别符**。改 key 格式会波及 `typeInfoByName`、`memberSymbols(of:excluding:)` 的排除集合、RuntimeViewer 侧的既有调用等一整片消费者，而收益与「查询侧带 node」完全等价。
- **name-only 重载保留不删**。它们是公开 API（RuntimeViewer 可能在用），语义改为文档化的「聚合/first-wins」。

## 复现与回归防线

- fixture：`SymbolTestsCore` 的 `PrivateDoppelgangers.swift` + `PrivateDoppelgangersSecondFile.swift`——两个文件各声明一个顶层 `private struct PrivateDoppelganger`，成员集合刻意不相交（`alpha*` vs `beta*`）。注意其中的防优化手段：`@_optimize(none)` 保住未特化的成员符号（否则 Release 只剩 `Tf4nd_n` 特化 thunk，成员索引不识别），anchor 把实例装箱成 `Any` 保住 descriptor 与 field descriptor（否则整个类型被优化掉——首版 fixture 实测如此）。
- 断言测试：`SwiftDumpTests.PrivateTypeMemberAttributionTests`（修复前双向混入、修复后各归各，红→绿验证过）。
- 快照：`SymbolTestsCoreDumpSnapshotTests.privateDoppelgangersSnapshot` 把两个声明并排钉死；全模块 interface 快照同时钉住 interface 路径的正确归属。
- 索引层：`SymbolIndexStoreFixtureTests.typeInfoLookupMatchesIndexedNames` 同时校验 name-only（first-wins）与 node 匹配两条路径。
