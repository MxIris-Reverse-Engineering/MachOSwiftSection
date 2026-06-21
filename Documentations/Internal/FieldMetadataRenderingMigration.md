# Field-Metadata Rendering Extraction — Migration Notes

供 review：把「字段的 metadata 富化注释」渲染逻辑抽到 `SwiftDeclarationRendering`，
让 `SwiftDump` 的 dumper 与 `SwiftPrinting` 的 `SwiftDeclarationPrinter` **共用同一份**
（单一真源）。

## 背景：为什么要做

`feature/swift-diffing` 把原本单体的 `SwiftInterface` 拆成
`SwiftDeclaration` / `SwiftIndexing` / `SwiftPrinting` 等层。拆分前，
`SwiftInterface.SwiftInterfacePrinter.printTypeDefinition` 渲染类型体时是
**委托给 SwiftDump 的 dumper** 的：

```swift
// 重构前 main: Sources/SwiftInterface/SwiftInterfacePrinter.swift
let dumper = typeDefinition.type.dumper(using: .init(... printFieldOffset: ..., printTypeLayout: ...),
                                        metadata: typeDefinition.metadata, in: machO)
...
try await dumper.fields   // ← 这里产出 // Field offset / // Type Layout / Enum Layout 等注释
```

拆分后，新的 `SwiftPrinting.SwiftDeclarationPrinter` 改成**直接按模型渲染**
（`renderModelFields` → `printField` / `printEnumCase`），但**没有**再产出那些依赖
运行期 metadata 的注释。后果（MachOImage 接口，老 vs 新逐行对比 SwiftUICore）：

| 指标 | 重构前(main) | 回归后(拆分版) |
|---|---:|---:|
| `// Field offset:` | 5082 | 251（退化到与 MachOFile 静态可解析的相同部分） |
| `// Type Layout:` | 5396 | **0** |

即 `printTypeLayout` 在打印路径变成**悬空配置**、运行期 field offset 丢失。
受影响：`swift-section interface` 与 **RuntimeViewer**（其核心 field-offset / type-layout
功能依赖 `SwiftDeclarationPrinter<MachOImage>`）。

## 方案

新增共享渲染器 `FieldLayoutRenderer`（在 `SwiftDeclarationRendering`），把
struct/class 的 field offset / type layout / expanded-offset，以及 enum 的
layout / spare-bit / per-case type layout 全部集中到这里。`SwiftDump` 的三个 dumper
与 `SwiftPrinting` 的打印器都调用它。

依赖方向（无环）：`SwiftDump → SwiftDeclarationRendering`、
`SwiftPrinting → SwiftDeclarationRendering`；`SwiftDeclarationRendering` 只依赖
`MachOSwiftSection` / `SwiftInspection` 等底层。

## 重构前的内容被挪到哪里了（review 用对照表）

| 重构前 位置/符号 | 现在 位置 |
|---|---|
| `SwiftDump/Dumper/StructDumper.swift` 的 `fieldOffsets` 属性 + `fields` 里内联的 `fieldOffsetComment` / end-offset / `expandedFieldOffsets` / `dumpTypeLayout` 编排 | `SwiftDeclarationRendering/FieldLayoutRenderer.swift`：`fieldOffsets`、`storedFieldComments(forFieldAtIndex:mangledTypeName:fieldOffsets:)`。`StructDumper.fields` 现改为调用它（声明本身仍由 dumper 渲染） |
| `SwiftDump/Dumper/ClassDumper.swift` 的同名 `fieldOffsets` + `fields` 内联编排 | 同上，`ClassDumper.fields` 改为调用 `FieldLayoutRenderer` |
| `SwiftDump/Protocols/TypedDumper.swift` 的 `expandedFieldOffsets(for:...)`、`walkNestedExpandedFieldOffsets`、`walkNestedStructFieldOffsets`、`walkNestedEnumPayloadFieldOffsets`、`resolveNestedMetatype`、`nestedTypeName`，以及全部静态泛型替换 helper（`substitutedNestedTypeNode`/`staticallyBoundMetatype`/`substitutingGenericParameters`/`boundGenericArgumentType`/`topLevelGenericKeyArgumentFlags`/`depthZeroFlatIndex`/`genericParameterDepthAndIndex`/`innerTypeNode`/`nodeContainsDependentReference`） | `SwiftDeclarationRendering/FieldLayoutRenderer.swift`（行为逐字保留；仅把 `Metadata.createInProcess` 改成固定的 `StructMetadata.createInProcess`——`asMetadataWrapper()` 按实际 kind 重分派，与原行为一致；顶层 hop 的替换走本类型注入的 `resolveFieldMetatype`） |
| `SwiftDump/Dumper/EnumDumper.swift` 的 `enumLayout` 计算、`fields` 里的 enum-layout/spare-bit 前缀与 per-case type-layout/enum-layout-case 编排、底部的 `MultiPayloadEnumDescriptorCache`、`EnumDescriptor.payloadSize/payloadExtraInhabitantCount` 扩展 | `SwiftDeclarationRendering/FieldLayoutRenderer+Enum.swift`：`enumLayout`、`enumPrefixComments(enumLayout:)`、`enumCaseComments(forCaseAtIndex:mangledTypeName:enumLayout:)` + 私有 helper。`EnumDumper.fields` 改为调用它。**注意**：原来用 `SharedCache` 缓存 multi-payload descriptor，这里改为**内联线性查找**（仅在 `printEnumLayout`/`printSpareBitAnalysis` 开启时触发），以免 `SwiftDeclarationRendering` 依赖 `MachOCaches` |
| 重构前接口路径的 metadata 注释来源：`SwiftInterface/SwiftInterfacePrinter.printTypeDefinition` 内 `dumper.fields` | `SwiftPrinting/SwiftDeclarationPrinter+Headers.swift` 的 `renderModelFields`：构造 `FieldLayoutRenderer` 并逐字段/逐 case 前置注释（回归修复点） |

### 没有移动、仍留在 `SwiftDump/Protocols/TypedDumper.swift`（声明渲染要用）
`resolveFieldMetatype`（含 `ValueMetadataProtocol` / `ClassMetadataObjCInterop` 约束实现）、
`fieldDemangledTypeNode` / `substitutedFieldNode`、`fieldDeclarationKeywords` /
`fieldMutabilityKeyword`、`boundDumpedMetatype` / `boundDumpedTypeNode` /
`demangledNode(forMetatype:)`、`resolveBoundDumpedTypeName` + `BoundDumpedTypeNameRenderer`、
`typeLayout`。这些参与的是「字段/类型**声明**」的渲染（类型名替换、weak/lazy 关键字等），
不属于 metadata 注释，故保留。

## 新 API 速览

`FieldLayoutRenderer<MachO>`（`@SemanticStringBuilder` 风格）
- `init(type:metadata:machO:configuration:autoResolveAccessorMetadata:)`
  - `autoResolveAccessorMetadata`（默认 `true`）：无显式 metadata 时，对**非泛型**类型
    经其 metadata accessor 解析运行期 metadata（只在进程内/MachOImage 成功）。
    **打印器**用默认 `true`（对应重构前工厂的「nil + 非泛型 → 走 accessor」）；
    **struct/class dumper** 传 `false`，保持「无 metadataContext ⇒ 不打印 offset」的旧契约；
    **enum dumper** 用默认 `true`（enum 布局本就经 accessor 解析、不依赖 metadataContext）。
- `var fieldOffsets: [Int]?`、`func storedFieldComments(...)`（struct/class）
- `var enumLayout`、`func enumPrefixComments(...)`、`func enumCaseComments(...)`（enum）
- `func resolveFieldMetatype(...)` / `func expandedFieldOffsets(...)`

## 行为保证 / 验证

- **回归对比**：`/tmp/macho-refactor-verify/old`（main 重构前）vs 修复后重跑，SwiftUI / SwiftUICore
  经 MachOImage 接口、**全部 options 打开**（fieldOffset / expandedFieldOffsets / typeLayout /
  enumLayout / memberAddress / vtableOffset / pwtOffset）。目标：各类注释逐行恢复，计数与重构前一致。
  仅 fieldOffset+typeLayout 时已验证 `// Field offset` 与 `// Type Layout` 计数与 main 逐一相等
  （SwiftUICore 5082/5396、SwiftUI 6483/6917），行数完全相等；剩余差异仅为既有的 subscript 重排。
  复现 harness：`Tests/IntegrationTests/SwiftInterface/RenderingVerificationTests.swift`（维护者验证工具，
  框架 / options / 输出目录由 `$RV_FRAMEWORKS` / `$RV_OPTS` / `$RV_OUT` 控制，默认全开）——在两个
  checkout 各跑一次、`diff` 两个输出目录即可对比。
- **dump 路径未变**：`SymbolTestsCoreDumpSnapshotTests`（MachOFile，`.test` 配置，59 个用例）继续通过，
  证明 dumper 去重未改变声明渲染。
- **全矩阵 old(main) vs new 对比（SwiftUI/SwiftUICore × MachOFile/MachOImage × 全 options，dump 经 factory 带 metadata）**：
  - **Dump 输出：5/5 逐字节完全一致**（含 dump-SwiftUICore-image 469830 行）。dumper 去重对输出零影响。
  - **Interface 输出：metadata 内容完全一致**——Field offset / Type Layout / Enum Layout / VTable / Address / PWT 计数 old=new 全相等；
    唯一差异是既有的 **subscript 成员重排**（平衡 +N/-N、无增删，连同其 Address 注释整体移位），
    由 model 驱动打印器的 `.byCategory` 成员排序（`printMembersByCategory`，本次未改动）相对旧 dumper 顺序产生，
    是 `SwiftInterface` 拆分带来的、早于本次 metadata 修复的差异，与 metadata 正交。
- **移植中修正的一个段错误（已对齐 OLD）**：开 `printEnumLayout` 时崩溃（SIGSEGV）。根因：我移植时
  `enumTypeLayout` 误用了无参 `metadata.valueWitnessTable()`——enum metadata 来自 `…resolve(in: machO)`，
  其 VWT 必须经同一 reader 读回，无参版本会错误解析 offset 并段错误。已改为 `valueWitnessTable(in: machO)`，
  **与重构前 `EnumDumper.typeLayout` 一致**。这是修正我自己移植引入的偏差，不是行为变更。

## 已知残留差异（与本次抽取无关，供 review 区分）

- **subscript 成员顺序**：模型驱动打印器（`memberSortOrder = .byCategory`）与旧 dumper 的
  成员顺序对个别 subscript 重载存在**平衡的重排**（`+N/-N`，无内容增减）。这是
  `SwiftInterface` 拆分本身带来的、早于本次修复就存在的差异，不是 metadata 回归。
- **`nestedFieldOffsetExpansionDepthLimit` 常量**：现同时存在于 `SwiftDeclarationRendering`
  （走查实际使用）与 `SwiftDump/Protocols/TypedDumper.swift`（仅作
  `NestedFieldOffsetExpansionDepthLimitTests` 的 pin 锚点）。两者均为 16；若要彻底单点，
  可让该测试改读 `SwiftDeclarationRendering` 的常量并删除 `SwiftDump` 里的副本。

## 附带修复：model 接口成员顺序的非确定性（SwiftDeclaration）

现象：model 驱动的接口（`SwiftDeclarationPrinter`）里，**重载下标与（合并的）`@objc func` 成员顺序每次运行都变**（同一批成员、同样 metadata，仅顺序不同）。dump 路径不受影响（它直接按 `symbolIndexStore.memberSymbols` 的有序结果渲染）。

根因：`Sources/SwiftDeclaration/Components/Definitions/DefinitionBuilder.swift` 有 **3 处普通 `Dictionary` 迭代**，Swift 字典迭代顺序随进程哈希随机化：
- `subscripts(...)`：`accessorsByNode: [Node: [Accessor]]`（重载下标都叫 "subscript"，无法像 `variables` 那样按名排序）；
- `functions(...)` / `allocators(...)`：`pendingMergedBy*Node: [Node: ...]`（合并 thunk 尾部追加）。

修复：上述三处改为 `OrderedDictionary`（保插入=符号顺序）。验证：同一 fixture 连跑两次接口输出**逐字节一致**（此前 +N/-N 漂移）。这是 `SwiftInterface` 拆分引入的既有 bug，与本次 metadata 抽取正交。

注：修复后 model 接口的成员顺序虽已**确定**，但与重构前 dumper 的顺序仍有稳定差异（dumper 把合并成员按符号顺序就地渲染，model 则把合并 thunk 归到尾部）——这是两种渲染路径的结构差异，非 metadata 差异；若需与旧逐字节一致需进一步对齐成员排序。

## 既有问题（与本次抽取无关，OLD 同样存在，未在本次改动）

- **~~`printExpandedFieldOffsets` 在深泛型框架上的栈溢出（SIGSEGV）~~（已不复现）**：曾记录对
  SwiftUI（经 MachOImage、同时开 `printFieldOffset + printExpandedFieldOffsets`）会崩溃，并猜测根因是
  `substitutingGenericParameters` 沿 demangled node 树无界递归致栈溢出。**复核后确认这其实就是下文那个
  value-generic `EXC_BAD_ACCESS @ 0x1`**（崩溃栈里 ~30 帧 `substitutingGenericParameters` 看似深递归，
  实为叶子处把整数当指针解引用，并非真正的栈耗尽）。修复后，`RenderingVerificationTests` 对 **SwiftUI ×
  MachOImage × 全 options（含 expandedFieldOffsets）** 跑通 dump+interface（1074s，exit 0，无崩溃），该
  问题不再复现。`substitutingGenericParameters` 的 node 递归理论上仍无界，但在实测框架上未观察到溢出；
  若未来遇到真正的病态深度，再在该处加深度上限即可（单点惠及 dumper 与 printer）。

- **值/包泛型参数导致的 `EXC_BAD_ACCESS @ 0x1`（本次已修，OLD 同样存在）**：对 SwiftUI（经
  MachOImage，开 `printExpandedFieldOffsets`/`printTypeLayout`）从 `SwiftUI.FileExportOperation`
  起的嵌套字段走查会硬崩。根因:`FieldLayoutRenderer.boundGenericArgumentType` 把父 specialized
  metadata 泛型实参向量里的**每个 key argument 都当作 type-metadata 指针裸读再 `unsafeBitCast` 成
  `Any.Type`**，完全忽略 `GenericParamKind`。SE-0452 **值泛型参数（`.value`）的槽位存的是整数值本身**
  （这里是 `1`），`.typePack` 存带低位 tag 的 pack 指针——把整数 `1` 当指针交给
  `_mangledTypeName` → `swift_getMangledTypeName` → `_swift_buildDemanglingForMetadata` 解引用
  `0x1` → `EXC_BAD_ACCESS address=0x1`（地址正好等于那个值 `1`）。该手工静态替换由 `0107c8a`
  引入（为绕开 runtime `getTypeByMangledNameInContext(specializedFrom:)` 的 PAC-fault），自带此缺陷；
  之前只因 model 打印器在 MachOImage 上**根本不发射 expanded offsets**（即上文 metadata 回归）而从未触发，
  修复回归后即暴露。
  **首版修复（止崩）**：`substitutingGenericParameters` / `staticallyBoundMetatype` 仅对 `kind == .type` 的
  depth-0 参数做替换，`.value`/`.typePack` 留未绑定占位符（纯文字降级；offset 来自 `metadata.fieldOffsets`，
  不受影响）。flat-index 仍按**全部** key argument 计数（每种参数恰好占一个槽），故后续 `.type` 参数槽位
  定位不变。`boundGenericArgumentType` 另加 null + 指针对齐兜底。配套把
  `GenericParamDescriptor.kind` 的强解包改为 `?? .max`——门控新增的 `map(\.kind)` 急切求值会在
  reserved kind 字节（`3...0x3E`）上 trap，此改动同时盖掉 `GenericSpecializer` 既有的同类暴露。
  全仓扫描确认 `boundGenericArgumentType` 是唯一"裸读单槽再 bit-cast"处，无第二例。
  **随后**把占位符降级升级为真正的 value/pack 渲染，见下文「值泛型 / 泛型包参数渲染支持」。

## 值泛型 / 泛型包参数渲染支持

> 这套“替换”是什么、当初为什么引入（绕开运行期 PAC-fault / `fatalError` trap）、依赖的实参向量 ABI、
> 以及埋过的 `EXC_BAD_ACCESS @ 0x1` 坑，独立成篇：见
> [`GenericArgumentSubstitution.md`](GenericArgumentSubstitution.md)。本节只记本次的增量。

把 `substitutingGenericParameters` 对非 `.type` 参数的占位符降级，升级为**真正的 value / pack 渲染**——
嵌套字段类型里引用父类型的 depth-0 `.value`（SE-0452 值泛型）/ `.typePack`（variadic 泛型包）参数时，
注释里的类型名显示具体实参而非占位符 `A`。

### 实参向量 ABI（以权威 Swift 源码为准，非猜测）

按 `swift/include/swift/ABI/GenericContext.h` 与运行期真正的读取器
`SubstGenericParametersFromMetadata::getMetadata`（`swift/stdlib/public/runtime/MetadataLookup.cpp`），
specialized metadata 头之后的内联实参向量布局为：

```
[ numShapeClasses 个 pack 长度字 ][ 每个 hasKeyArgument 参数一字，按声明序、
  type/value/typePack 三种 kind 交错：metadata 指针 / 整数值 / metadata-pack 指针 ][ 见证表 ]
```

故任一 kind 的 depth-0 参数槽位 = `numShapeClasses + (其前 hasKeyArgument 参数计数，不分 kind)`
（与 `getMetadata` 完全一致；头注释里"value 排在末尾"描述的是另一种布局，**实测读取器以交错为准**）。

- **`.value`**：读该槽整数 → 建 `.integer` / `.negativeInteger` 字面量节点（local swift-demangling 的
  NodePrinter 把 `negativeInteger` 打成 `-<magnitude>`，故存绝对值）。
- **`.typePack`**：第 k 个 `.metadata`-kind `GenericPackShapeDescriptor` 对应第 k 个 `.typePack` key 参数；
  pack 指针槽 = `descriptor.index`（绝对，IRGen 已含 shape class 偏移），count = `genericArgs[descriptor.shapeClass]`
  （前导 shape-class 槽存 pack 长度，比 `getNumElements()` 读 `elements[-1]` 更安全——后者对 on-stack pack 会
  `fatalError`）。pack 指针低位是 on-heap 标记（`& ~1` 清除），逐元素 `_mangledTypeName` → 建 `.pack` 节点
  （打成 `Pack{…}`）。
- 顺带修正：给 `.type` 槽位也加上 `numShapeClasses` 偏移——首版（及 `0107c8a`）对**变长类型**会算错槽位
  （非变长 numShapeClasses=0，逐字节不变）。
- 全程 bounds（`< numKeyArguments`）/ 8 字节对齐 / count 上限（256）兜底；任何读取失败回退占位符，**绝不崩**。
- 递归侧 `staticallyBoundMetatype` 仍仅 `.type`（value/pack 无可静态走查的嵌套字段布局）。

### 验证（before/after，权威源码对照 + 真机实测）

- **对抗式复核**：4-agent 逐条对照 `MetadataLookup.cpp` / `GenericContext.h` / `Metadata.h`（`TargetPackPointer`），
  确认槽位数学、pack 映射、count 来源、tag 清除、元素布局、崩溃安全全部正确，无 must-fix。
- **真机 before/after**：`RenderingVerificationTests`（SwiftUI × MachOImage × 全 options）两版 diff——
  `*-file.txt`（MachOFile）逐字节一致；`*-image.txt` 仅 16 行变化，**全部**是
  `repeat …Variable<A>` → `repeat …Variable<Pack{Foundation.URL}>` 一类占位符→具体包，其余完全一致、无回归、
  无崩溃（dump+interface，1074s，exit 0）。dump 输出 0 个渲染 `Error:`。
