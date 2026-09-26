# 0042 - SwiftDeclaration 模块的文件归位与 TypeDefinition 拆分

- **状态**: Implemented
- **创建日期**: 2026-09-17
- **最后更新**: 2026-09-26
- **所属愿景**: 无
- **关联提案**: 无
- **实现分支 / PR**: `feature/swift-declaration-file-layout`（从 `next` 的 01fe2f82 起）
- **配套文档**: [Modules/SwiftDeclaration.md](../Internal/Modules/SwiftDeclaration.md)（「文件 → 子系统对照」表随本批改写）

## 摘要

`Sources/SwiftDeclaration/Components/Definitions/` 这个目录名说的是「声明本体」，实际装着三类东西：真正的 `*Definition`、成员构件（`Accessor` / `OrderedMember` / `MemberCategory`）、以及构建期的机器（`DefinitionBuilder`、`Definition+.swift` 里的符号分桶、`OverrideSymbolMatcher` 这两个自由函数），外加两个与声明本体平级的独立概念（`ExportStatus`、`AssociatedTypeWitnessProjection`）。另有两个 package 级工具类型（`DemangledSymbolWithOffset`、`StrippedSymbolicRequirement`）藏在 `ProtocolDefinition.swift` 文件中段，按文件名根本搜不到。

同时 `TypeDefinition.swift` 有 756 行，其中 `index(in:)` 一个方法占 370 行，串起互不相干的六件事：字段记录构建、类的 vtable / override 查找表构建、六类成员构建、`final` 关键字恢复、thunk attribute 交叉引用、合成成员去重。`ExtensionDefinition` 与 `ProtocolDefinition` 的 `index(in:)` 也各自压在类本体文件末尾。

本批是**纯组织性改动：不新增能力、不改变任何输出、不动任何 public/package API 的签名语义**，唯一的签名变化是把 `DefinitionBuilder` 五个方法上重复出现的四个查找表参数打包成一个结构体（模块外的三个调用点全都走默认值，不受影响）。

## 方案

### 一、目录归位

```
Sources/SwiftDeclaration/
  Components/
    Definitions/        ← 只剩声明本体
    Members/            ← 成员构件
    Building/           ← 构建期机器
    Names/  Kinds/      ← 不动
    ExportStatus.swift
    AssociatedTypeWitnessProjection.swift
    SwiftAttribute.swift
  Extensions/           ← 原根目录 Extensions.swift 按被扩展类型拆开
  Events/               ← 不动
```

**`Components/Members/`**（新建）：`Accessor.swift`、`OrderedMember.swift`、`MemberCategory.swift` 原样搬入；新增 `StrippedSymbolicRequirement.swift`——类型从 `ProtocolDefinition.swift` 抽出，连同 `Extensions.swift` 里那个只服务于它的 `strippedSymbolicInfo()`。

**`Components/Building/`**（新建）：`DefinitionBuilder.swift`、`OverrideSymbolMatcher.swift` 原样搬入；`Definition+.swift` 改名 `MemberSymbolBucketing.swift`（它装的是 `addSymbol` 与 `setDefinitions` 两个符号分桶方法，`+` 这个文件名不说明任何事）；新增 `DemangledSymbolWithOffset.swift`（从 `ProtocolDefinition.swift` 抽出，连同 `Sequence.mapToDemangledSymbolWithOffset()`）与 `ClassDispatchLookups.swift`（见下）。

**`Components/` 顶层**：`ExportStatus.swift`、`AssociatedTypeWitnessProjection.swift`（含 `ConditionalWitnessCandidate`）从 `Definitions/` 上移；`SwiftAttribute.swift` 从模块根下移——它和 `ExportStatus` 同类，都是挂在声明上的独立概念，不是声明本体。

**`Extensions/`**（新建，对齐 `SwiftDeclarationRendering/Extensions/` 的惯例）：根目录那个 257 行的 `Extensions.swift` 按被扩展的类型拆成 `DemanglingNode+AccessorKind.swift`、`Node+TypeKind.swift`、`ProtocolConformance+Names.swift`、`AssociatedType+Names.swift`、`Protocol+Names.swift`（`Protocol` 与 `ProtocolDescriptor` 两个扩展）、`TypeContext+Names.swift`（`TypeContextWrapper` 与 `TypeContextDescriptorWrapper`，含 `kind`）、`FieldRecord+DemangledType.swift`、`Sequence+NonNil.swift`。

### 二、三个 Definition 的文件拆分

统一用 `<类型>+<功能>.swift` 命名，与 `SwiftPrinting/SwiftDeclarationPrinter+*.swift` 一致。

| 文件 | 内容 |
|---|---|
| `TypeDefinition.swift` | 存储属性、两个 `init`、`hasMembers`、`materializedTypeContext(in:)` |
| `TypeDefinition+Indexing.swift` | `index(in:)` 主干（52 行，依次调用下列步骤）、字段记录 → `FieldDefinition` 的构建、存储属性 accessor 组的回折 |
| `TypeDefinition+ClassDispatch.swift` | 类分支的 vtable / override / defaultOverride 查找表构建 |
| `TypeDefinition+MemberIndexing.swift` | 六类成员 + deallocator / destructor 符号 |
| `TypeDefinition+FinalRecovery.swift` | 提案 0006 的 `final` 恢复与它的四道门 |
| `TypeDefinition+ThunkAttributes.swift` | `applyThunkAttributes` 与三个 `applyAttributeTo*` |
| `TypeDefinition+SynthesizedMembers.swift` | `deduplicateSynthesizedProtocolMembers` |
| `TypeDefinition+WrappedProperties.swift` | 已存在，只留 `extension TypeDefinition`；其中的 `WrappedPropertyRecovery` 命名空间移到 `Building/WrappedPropertyRecovery.swift` |
| `ProtocolDefinition.swift` / `+Indexing.swift` | 类本体与 `index(in:)` 分开 |
| `ExtensionDefinition.swift` / `+Indexing.swift` | 类本体（含 `absorbAssociatedTypes` / `absorbMembers`）与 `index(in:)` + `markProtocolExtensionDefaults` 分开 |

### 三、`ClassDispatchLookups`

`index(in:)` 里那四张查找表（`methodDescriptorLookup`、`vtableOffsetLookup`、`implOffsetDescriptorLookup`、`implOffsetVTableSlotLookup`）加上 `classCanRecoverFinalMembers` 这个证据门，现在是五个平行局部变量，逐个传给 `DefinitionBuilder` 的七次调用。拆成独立方法后它们必须跨方法传递，因此打包：

```swift
package struct ClassDispatchLookups {
    package var methodDescriptorLookup: [StructuralNodeReferenceKey: MethodDescriptorWrapper] = [:]
    package var vtableOffsetLookup: [StructuralNodeReferenceKey: Int] = [:]
    package var implementationOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:]
    package var implementationOffsetVTableSlotLookup: [Int: Int] = [:]
    /// 提案 0006 的证据门：只有 vtable 头在、且不是 actor 的类能作证「没有方法描述符」等于 `final`。
    package var canRecoverFinalMembers: Bool = false
}
```

`DefinitionBuilder` 的 `variables` / `variablesProduct` / `subscripts` / `allocators` / `functions` 把那四个参数换成一个 `dispatchLookups: ClassDispatchLookups = .init()`。模块外只有 `SwiftIndexing` 的三处调用，全都不传这组参数，走默认值，不受影响。顺带把 `impl` 这个缩写展开成 `implementation`（项目命名规则不允许缩写）。

### 四、等价性与验证

拆出来的每个步骤方法逐句照搬原文，**执行顺序一字不改**，只有一处顺序移动：存储属性 accessor 组回折到 `fields` 的那一段，从「`variables` 构建之后、`staticVariables` 构建之前」移到「六类成员全部构建完之后」。这是等价的——回折只读 `variablesProduct` 并只写局部的 `indexedFields`，而后面四类成员的构建既不读 `indexedFields` 也不写它。

验证三层，全部已执行：

1. **全量测试**（本地全量，不认 CI 子集）：1929 tests / 367 suites，3 个 issue 全部来自 `SharedCacheTests` 的三条墙钟并行度断言（`differentKeysParallelViaTaskGroup` 实测 7.67 s 超 0.8 s 预算等）。单独复跑该套件 9 tests / 2 suites 全过，耗时 0.6 s——全量下机器被其它套件占满导致的既有 flaky，与本批无关（它在 `MachOCaches`，本批一行未碰）。
2. **ABI 基线零漂移**：基线套件逐字节比对 dump / interface 输出，随全量一起绿。
3. **渲染 A/B 验证**（`Scripts/run-rendering-ab-verification.py`，baseline = 分支点 `01fe2f82` 的独立 worktree，candidate = 本批，两侧共用同一份 `Package.resolved`）：**90 对全部逐字节一致，零 skip**——归档 cache macOS 26.6.2 / 15.5 各 12 对，模拟器 runtime iOS 15.5 / 18.5 / 18.6 / 26.5 共 42 对，in-process MachOImage 24 对。比文档记录的 2026-08-03 基线运行多 12 对（本机多装了一个 iOS 18.6 runtime）。

**跑 A/B 时顺带修掉一个会让它静默失效的问题**：`ARCHIVED_CACHE_DIRECTORIES` 写死的两条归档路径（`26.5.2_25F84` / `15.5_24F74`）已与归档卷的实际命名脱节——卷改用纯版本号，且 `26.5.2` 目录下不再放 cache。路径对不上时脚本不报错，只打印一行 fallback 就降级成只跑当前系统 cache，跨版本语料整段消失而最终报告照样是「全部一致」。常量改为 `26.6.2` / `15.5`，harness 自测 9 tests 全过，这个坑记进了 [SystemFrameworkRenderingVerification.md](../Internal/SystemFrameworkRenderingVerification.md)。

## 决策日志

- **为什么不是把非 Definition 的东西统统塞进一个 `Supporting/`**：那只是把杂物袋换个名字。`Members/` 与 `Building/` 的分界是有判据的——前者是模型的一部分（会出现在 public API 的返回值里），后者只在索引期活着（全是 `package`），未来若要把构建期机器整体挪到 `SwiftIndexing`，边界已经画好了。
- **为什么 `index(in:)` 要拆方法体，而不只是搬文件**：搬文件只把 370 行从一个文件挪到另一个文件，最臃肿的东西没变。拆开后每一步有名字、有独立的 doc comment，`final` 恢复那四道门的注释终于能挂在一个叫 `recoverFinalMembers` 的东西上，而不是淹在主干中段。代价是这成了真改代码，因此验证里加了 A/B 一层。
- **为什么 `ExportStatus` 上移到 `Components/` 而不是自成目录**：它是单文件概念，`Components/Export/ExportStatus.swift` 这种一个文件的目录是噪音。`AssociatedTypeWitnessProjection` 与 `SwiftAttribute` 同理。
- **为什么 `DemangledSymbolWithOffset` 进 `Building/` 而不是 `Members/`**：它是 `DemangledSymbol` 加一个 PWT 偏移的构建期包装，只在分桶与构建路径上出现，索引结束后不留在模型里。
- **历史文档不追改**：`Internal/TaskReports/`、`Internal/Reviews/`、`SwiftModularizationMigration.md` 里的旧路径是当时的事实快照，保留原样；只更新现行参考文档（`Modules/SwiftDeclaration.md` 的对照表、`ExportedOnlyInterfaceFiltering.md`、`FinalKeywordAndLazyAccessorTypeRecovery.md`、`ExtensionContainerUnification.md` 中指向现行路径的行）。
- **2026-09-26 In Progress → Implemented，落地编号 0042**：代码已于 2026-09-17 随 `c8aae551` 合入 `next`，当时状态停在 In Progress、没有取号；0.20.0 发版收尾时按合入顺序补取。配套文档见头部，已随代码更新；没有新的项目术语。
