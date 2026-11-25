# Draft - C 导入类型的拼写补齐：同名类型去掉 `__C`，布局注释跟着打印器的拼写

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-11-25
- **最后更新**: 2026-11-25
- **所属愿景**: 无
- **关联提案**: [0106-c-imported-type-name-spelling](0106-c-imported-type-name-spelling.md)（本提案补齐它留下的两处：没改名的 C 类型、字段布局注释）；[0067-nested-field-offset-memoization](0067-nested-field-offset-memoization.md)（进程内每层展开的缓存，本提案往缓存的行里多存一个类型节点）；[0064-module-selectors](0064-module-selectors.md)、[0092-existential-any](0092-existential-any.md)（布局注释由此也带上模块选择器与 `any`）
- **实现分支 / PR**: `feature/consistent-c-imported-type-spelling`（worktree `.worktrees/MachOSwiftSection-ConsistentCImportedTypeSpelling`）
- **配套文档**: 待定 —— 落地时判断
- **网页版**: 同目录同名的 `.html`

## 摘要

0106 让改了名的 C 导入类型在声明、成员类型和扩展头里一律写 Swift 名，但还剩两处混用。第一处：镜像里有 descriptor、Swift 名与 C 名相同的类型，声明行写裸名 `struct AGDescriptionOption`，引用和扩展头却写 `__C::AGDescriptionOption`。第二处：字段布局注释（展开的嵌套字段偏移树）用固定的 `.default` 选项印类型名，`var base: AnyWeakAttribute` 下面的注释写着 `identifier (__C.AGAttribute)`，也不带模块选择器和 `any`。本提案让名字表把「没有 ABI 名」的 descriptor 也收进来——编译器只在两个名字不同时才写 ABI 名，所以这样的 descriptor 证明了 Swift 名就是 C 名——引用处因此写裸名；再让 interface 路径的布局注释经打印器自己的类型拼写印类型名，离线（`MachOFile`）与进程内（`MachOImage`）两条后端一起改，dump 不变。镜像里没有 descriptor 的类型照旧写 `__C::`，跨镜像查找另开提案。

## 动机

用户用 `SwiftInterfaceBuilderTestSuite.DyldCacheTests.buildFile` 打 macOS 27.2 的 AttributeGraph（开 `showCImportedTypes`、注册 `SwiftInterfaceBuilderTypeNameProvider`、模块选择器、展开字段偏移），输出 `macOS-27.2.0-AttributeGraph-FileDump.swiftinterface` 里同一个类型出现两种写法：

```swift
struct AGDescriptionOption {                                   // 声明：裸名
...
extension __C::AGDescriptionOption: @retroactive Swift::RawRepresentable {   // 扩展头：__C::
```

```swift
struct WeakAttribute<A> {
    // Field offset: 0x0
    // └── _details (__C.AGWeakAttribute.__Unnamed_struct__details): 0x0
    //     ├── identifier (__C.AGAttribute): 0x0
    //     │   └── rawValue (Swift.UInt32): 0x0
    var base: AnyWeakAttribute
```

第一段是同一个类型的声明与扩展头拼写不一致，读起来像是给另一个类型加的遵循。第二段的注释用 C 名 `__C.AGAttribute`，紧挨着的声明却写 `AnyWeakAttribute`；而且整份输出开着模块选择器（`Swift::UInt32`），注释里仍是 `Swift.UInt32`，违反项目「模块限定名必须经类型打印器或调用方的 `DemangleResolver` 印出」的规则（CLAUDE.md 声明模型一节）。RuntimeViewer 用同一个打印器，它的 Imported Type Names 开关切到 Swift 名时，这两处照样混用。

用户确认只做「二进制能证明的」部分：镜像里没有 descriptor 的类型（`AGValueOptions`、`AGSubgraphRef` 等）二进制里查不到 Swift 名，保留 `__C::`；从依赖它的其它镜像的 descriptor 找名字（`AGSubgraphRef` 在 SwiftUICore 里记作 `Subgraph`）另开提案。

## 前期调研

1. **名字表只收改了名的条目**。`CImportedTypeSwiftNameTable.init(typeContextDescriptors:in:)`（`Sources/Output/SwiftPrinting/CImportedTypeSwiftNameTable.swift:34`）要求 `descriptor.hasImportInfo`，再经 `trustsUserFacingName(_:importInfo:)`（同文件 `:74`）要求有 ABI 名、与 descriptor 的名字不同、不是相关实体、ABI 名不以 descriptor 的名字结尾。`TypeNodePrintable.printType`（`Sources/Output/SwiftPrinting/NodePrintables/TypeNodePrintable.swift:170-280`）只在模块没解析出来、名字表又有答案时省掉模块写裸名（`:202`），表里没有就写 `__C::` 加标识符。

2. **声明行用 descriptor 的名字**。`declaredTypeName(of:)`（`Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+Headers.swift:153`）对没有 ABI 名的 C 导入 descriptor 直接返回 descriptor 的名字、不带标注（`cImportedTypeNames: nil`），所以同名类型的声明本来就是裸名。扩展头经 `renderExtendedTypeName`（同文件 `:832`）走 `typeDemangleResolver`，即 `printType`。

3. **编译器什么时候写 ABI 名**。IRGen `computeIdentity`（`/Volumes/SwiftProjects/swift-project/swift/lib/IRGen/GenMeta.cpp:1567-1609`）：`UserFacingName = Type->getName()`（Swift 声明的基名），ABI 名取 Clang 声明的限定名，**只有两者不同才写进 import info**；typedef 提升的类型另写符号命名空间 `St`。所以一个没有 ABI 名的 C 导入 descriptor，它的名字既是 Swift 名也是 C 名。不带任何 import info 的 descriptor（普通 C struct、`NS_ENUM`）同理。唯一的例外形态：一个 C 名不带前缀的类型被 `swift_name` 导入成另一个类型的成员（C 名 `Foo`、Swift 名 `Owner.Foo`），基名与 C 名相同、不写 ABI 名，但 Swift 拼写是 `Owner.Foo`。Apple SDK 的 C 名都带前缀，没有见过这种类型，作为假设记在方案里。

4. **AttributeGraph 里哪些是同名的**（macOS 27.2 系统 cache，`ipsw dyld str` / `ipsw dyld dump` 读 `__TEXT.__const`）：
   - `AGDescriptionOption`：AG 与 SwiftUICore 的 descriptor 的名字都是 `AGDescriptionOption`，后面只有 `St`，没有 ABI 名——同名，本提案让它的引用写裸名。
   - `AGTreeValue` → `TreeValue`、`AGTypeSignature` → `Signature`：有 ABI 名、但 ABI 名以 descriptor 的名字结尾，0106 的规则不采信（可能是导入成成员），照旧写 `__C::`，不在本提案范围。
   - `AGValueOptions`、`AGComparisonMode` 等 16 个只出现在签名里的类型：AG 里没有它们的 descriptor（C 导入类型的 metadata 由用到它的镜像各自按需生成，`lib/IRGen/GenDecl.cpp:1609` 的 `canBeLazy`），保留 `__C::`。

5. **布局注释的类型名从哪来**。
   - 离线：`StaticLayoutCalculator.nestedFieldOffsetTree`（`Sources/Analysis/SwiftLayout/NestedFieldOffsetTree.swift:49`、`:73`）与 `makeNode`（`:247`）用 `node.print(using: .default)` 印成字符串，存进公开的 `NestedFieldOffset.typeName`，同一个字符串还当防环的键（`enclosingTypeNames`）。`StaticFieldLayoutBackend.renderNestedFieldOffsetTree`（`Sources/Output/SwiftDeclarationRendering/StaticFieldLayoutBackend.swift:194`）原样交给 `expandedFieldOffsetComment`。
   - 进程内：`RuntimeFieldLayoutBackend.nestedTypeName(for:parentMetadata:)`（`Sources/Output/SwiftDeclarationRendering/RuntimeFieldLayoutBackend.swift:395`）同样 `.default`，结果存进 0067 的全进程缓存 `NestedFieldOffsetLevel`（`NestedFieldOffsetLevel.swift:27-49`），按 metatype 一份，所有打印器共用。
   - 两边最后都进 `DeclarationRenderConfiguration.expandedFieldOffsetComment(fieldName:typeName:…)`（`DeclarationRenderConfiguration.swift:305`），`typeName` 是字符串，也交给 `ExpandedFieldOffsetTransformer` 模板（RuntimeViewer 的设置界面）。
   - `.default` 不带 `useModuleSelectors`、`useExistentialAny`（CLAUDE.md：固定预设两者都不带），也不认识名字表，所以 C 名、点号限定、裸存在类型都由此而来。

6. **interface 路径手里有打印器的拼写**。`modelFieldBlock`（`SwiftDeclarationPrinter+Headers.swift:521`）构造渲染配置时把 `typeDemangleResolver` 传成 `demangleResolver`；它是 `.builder`，每次新建一个 `SemanticTypeNodePrinter` 印节点（`SwiftDeclarationPrinter.swift:199`）。这是渲染配置唯一的构造点。打印器按节点身份记忆片段的缓存是每个 `printRoot` 一份（`InterfaceNodePrintable.swift:18-28`），节点只要活过那一次调用就安全。

7. **两条后端必须一起改**。`OfflineSpecializationParityTests`（`Tests/SwiftSpecializationTests/OfflineSpecializationParityTests.swift`）要求进程内与离线两条路径在开着展开字段偏移时逐字节相同；只改一边，开了 `any` 或模块选择器的场景就会对不上。

8. **进程内缓存为什么存节点而不是渲染时重算**。0067 做这个缓存，是因为 RuntimeViewer 建搜索语料时 61% 的时间耗在逐层重读 metadata，且每个 struct 字段节点要 demangle 约三次（`demangleTypeUncached`）。渲染时重新 demangle 会把这部分成本带回来；而节点在建层时本来就算出来了（`nestedTypeName` 先得节点再印），存下它不增加 CPU，只增加每个唯一 metatype 一份的内存。

9. **dump 不受影响的理由**。dump 的渲染配置是 `.options(...)`（测试里是 `.options(.test)`，`Sources/TestSupport/SwiftSectionFixtureSupport/DumpableTests.swift:32`），声明按 mangled 身份打印（0106 前期调研 1），它没有 C 名 / Swift 名开关。本提案不改 dump 的任何输出。

## 提议方案

### 1. 名字表收「没有 ABI 名」的条目

`CImportedTypeSwiftNameTable` 对每个 C 导入（父模块是 `__C` / `__C_Synthesized`）的 descriptor 求「已知的 Swift 名」：

- 不是相关实体、没有 ABI 名（含完全没有 import info）、且直接位于 `__C` / `__C_Synthesized` 模块下 → descriptor 的名字就是 Swift 名，收进表；
- 有 ABI 名 → 照旧，`trustsUserFacingName` 采信才收；
- 相关实体 → 不收；
- 有 import info 却读不出来 → 不收（读失败不当作没有）。

`printType` 不用改：表里有答案、模块没解析出来就写裸名，解析器找到模块照旧写 `模块::名字`。声明行不变（本来就是裸名），标注（`marksCImportedTypeNames`）不变（两种拼写相同的不标）。嵌在 C 类型里的类型（`__Unnamed_struct__details`）不收：它的引用由父类型那一段决定写法，表里不需要它。

### 2. 布局注释经打印器的拼写印类型名

- `NestedFieldOffset` 多存一个公开的 `typeNode: Node?`（字段类型的节点，替换过泛型参数），`typeName` 保持 `.default` 字符串——它仍是防环键和 dump 的拼写。
- 进程内缓存的行（`NestedFieldOffsetLevel.StructField` / `EnumPayload`）同样多存 `typeNode`。
- `DeclarationRenderConfiguration` 加一个包级开关 `spellsFieldLayoutTypeNamesThroughResolver`（默认关，`@Init(.ignore)`，照 `marksCommentStructure` 用修饰方法设置）和一个异步方法 `fieldLayoutTypeName(printedName:typeNode:)`：开关开着、有节点时经 `demangleResolver` 印节点取纯文本，否则返回 `printedName`。
- 两条后端渲染树时改成异步：每一行先 `await` 取类型名，再递归渲染子行，最后套进 `commentRegion`（已有 async 版本）。树的形状、`isLast`、防环与深度判断、`#log` 告警都不动。
- interface 打印器构造渲染配置时打开这个开关。dump 不开，输出逐字节不变。

于是 interface 里注释的类型名与声明写法一致：`.swiftName` 下是 `AnyAttribute`，`.cName` 下是 `__C.AGAttribute`；开了模块选择器写 `Swift::UInt32`；存在类型带 `any`；`Optional`、`Array`、`Dictionary` 写成语法糖（`Swift.Int?`）；私有类型不带判别符（`M.Foo`，`.default` 写 `M.(Foo in _ABC…)`），局部类型只写自己的名字——都和声明一样。`ExpandedFieldOffsetTransformer` 模板收到的也是这个拼写。注释行因此和声明一样分不清同名的私有类型；要分清，看声明上方 `--emit-private-source-files` 印的源文件注释。

### 没有询问就采用的假设

- **范围取字面最小的理解**：只补 0106 留下的两处；`AGTreeValue` 这类「改了名但不可信」的类型不碰，照旧 `__C::`。
- **「没有 ABI 名 = Swift 名就是 C 名」**：依据 IRGen 的 `computeIdentity`。唯一会错的形态是 C 名不带前缀、又被导入成成员的类型（前期调研 3），没有见过实例，接受这个风险。
- **dump 不跟着改**：dump 没有拼写开关、按 mangled 身份打印，注释维持 `.default`。要不要让 dump 的注释也走它自己的 `demangleResolver`，记为后续项。
- **进程内缓存存节点**：用内存换掉渲染时的重复 demangle（前期调研 8）。
- **开关放在渲染配置而不是按 `DemangleResolver` 的 case 判断**：`.builder` 不等于「interface 打印器」，显式的开关不把语义绑在枚举 case 上。

### 非目标

- 镜像里没有 descriptor 的 C 类型（`AGValueOptions`、`AGSubgraphRef`）：保留 `__C::`；从依赖它的镜像（SwiftUICore 记着 `Subgraph`）查名字另开提案。
- 「改了名但不可信」的条目（`TreeValue`、`Signature`、`ValueFlags`）：0106 的成员导入保护不放松。
- `@retroactive`：它按 mangling 里的 `__C` 判定，模块解析出来后也照印，与本提案无关，记为后续项。
- dump 的任何输出；diff / snapshot / evolution 的键（仍按 mangled 身份比较）。
- 其它注释里的类型名（枚举布局等）：本提案只管展开的字段偏移树；同类排查结果写进后续项。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Sources/Output/SwiftPrinting/CImportedTypeSwiftNameTable.swift` · `CImportedTypeSwiftNameTable` | 修改 | `init` 改为对每个 C 导入 descriptor 求已知 Swift 名；新增 `knownSwiftName(ofDescriptorNamed:importInfo:isDirectlyInImportedModule:)`；`trustsUserFacingName` 语义不变 | 同名类型进表，引用写裸名 | 1 |
| `Sources/Output/SwiftPrinting/CImportedTypeNameSpelling.swift` · `CImportedTypeNameSpelling.swiftName` | 修改 | 文档：「本镜像 descriptor 给出名字的类型（改名与否）写裸名」 | 文档跟上行为 | 1 |
| `Sources/Output/SwiftPrinting/NodePrintables/TypeNodePrintable.swift` · `swiftNameFromDescriptor(ofCImportedType:)` | 修改 | 只改注释 | 同上 | 1 |
| `Sources/Executables/swift-section/Commands/InterfaceCommand.swift` · `cImportedTypeNameSpelling` | 修改 | `--c-imported-type-name-spelling` 的帮助文字补上同名类型与布局注释 | CLI 帮助即文档 | 1、3 |
| `AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md` | 修改 | 「Swift names come first」一段补上同名类型、没有 descriptor 的保留 `__C.`、布局注释同拼写 | CLI 输出变了，skill 同批更新 | 1、3 |
| `Tests/SwiftInterfaceTests/CImportedTypeNameSpellingTests.swift` | 修改 | fixture 加两个同名 C 类型（普通 struct `ProbePlainValue`、`swift_wrapper` 的 `ProbeOption`），加第 1、2、3 步的行为测试 | 回归 | 1、2、3 |
| `Tests/SwiftInterfaceTests/CImportedTypeConformanceInterfaceTests.swift` | 修改 | 定位扩展块用的类型名从 `__C.ProbeMode` 改成 `ProbeMode` | 同名类型的扩展头不再带 `__C.` | 1 |
| `Tests/SwiftInterfaceTests/Snapshots/__Snapshots__/SymbolTestsCoreInterfaceSnapshotTests/interfaceSnapshot.1.txt` | 重录 | `__C.CMTime` → `CMTime` | fixture 镜像里有 `CMTime` 的 descriptor | 1 |
| `Sources/Analysis/SwiftLayout/NestedFieldOffsetTree.swift` · `NestedFieldOffset` | 修改 | 新增 `public let typeNode: Node?`，`init` 加 `typeNode: Node? = nil`；`makeNode` 填上 | 渲染层要拿节点按打印器拼写 | 2 |
| `Sources/Output/SwiftDeclarationRendering/DeclarationRenderConfiguration.swift` · `DeclarationRenderConfiguration` | 修改 | 新增 `spellsFieldLayoutTypeNamesThroughResolver`、`spellingFieldLayoutTypeNamesThroughResolver(_:)`、`fieldLayoutTypeName(printedName:typeNode:)` | 两条后端共用的拼写入口 | 2 |
| `Sources/Output/SwiftDeclarationRendering/StaticFieldLayoutBackend.swift` · `StaticFieldLayoutBackend` | 修改 | `expandedFieldOffsets(for:baseOffset:)`、`renderNestedFieldOffsetTree(_:ancestors:)` 改成 async，每行经 `fieldLayoutTypeName` 取名字 | 离线路径的注释跟拼写 | 2 |
| `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter+Headers.swift` · `modelFieldBlock` | 修改 | 渲染配置加 `.spellingFieldLayoutTypeNamesThroughResolver(true)` | interface 打开开关 | 2 |
| `Sources/Output/SwiftDeclarationRendering/NestedFieldOffsetLevel.swift` · `StructField` / `EnumPayload` | 修改 | 新增 `typeNode: Node?` | 进程内缓存带节点 | 3 |
| `Sources/Output/SwiftDeclarationRendering/RuntimeFieldLayoutBackend.swift` · `RuntimeFieldLayoutBackend` | 修改 | `nestedTypeName` 拆出 `nestedTypeNode`；建层时存节点；`expandedFieldOffsets(of:…)` 与 `walkNestedExpandedFieldOffsets` 改成 async，每行经 `fieldLayoutTypeName` 取名字 | 进程内路径的注释跟拼写，与离线逐字节一致 | 3 |
| `Tests/SwiftDeclarationRenderingTests/…` | 视情况修改 | 调用点随 async 化补 `await` | 编译 | 2、3 |
| `Documentations/Glossary.md` · C-imported type name spelling | 修改 | 补同名类型、布局注释 | 术语表跟上行为 | 4 |
| `Documentations/Internal/Modules/SwiftLayout.md` | 修改 | `NestedFieldOffset` 多了 `typeNode` | 模块参考 | 4 |
| `Documentations/Internal/Modules/SwiftDeclarationRendering.md`（若有相关段落）、`Documentations/Internal/Modules/SwiftPrinting.md` | 视情况修改 | 布局注释的拼写来源、名字表的收录规则 | 模块参考 | 4 |
| `Documentations/Internal/ProjectEvolutionLog.md` | 修改 | 新增一节（节号落地时取） | 演进账本 | 4 |
| `Documentations/Evolutions/README.md` | 修改 | 登记本提案（编号 `draft`）；`Documentations/README.md` 照项目惯例在落地取号时登记（进行中的 draft 都不在那里） | 索引 | 0 |

## 架构图

改了什么：

```text
SwiftPrinting
  CImportedTypeSwiftNameTable
~   init: entry when the descriptor's name is a known Swift name
+     knownSwiftName(ofDescriptorNamed:importInfo:isDirectlyInImportedModule:)
+       no ABI name, directly in __C        -> descriptor name (Swift name == C name)
        ABI name, trustsUserFacingName       -> descriptor name (unchanged)
        related entity / unreadable          -> nil
  SwiftDeclarationPrinter.modelFieldBlock
~   DeclarationRenderConfiguration(...).spellingFieldLayoutTypeNamesThroughResolver(true)

SwiftLayout
  NestedFieldOffset
      typeName: String            (.default spelling; cycle key, dump spelling)
+     typeNode: Node?

SwiftDeclarationRendering
  DeclarationRenderConfiguration
+   spellsFieldLayoutTypeNamesThroughResolver: Bool   (package, default false)
+   fieldLayoutTypeName(printedName:typeNode:) async -> String
  StaticFieldLayoutBackend
~   expandedFieldOffsets / renderNestedFieldOffsetTree   sync -> async
  NestedFieldOffsetLevel.StructField / EnumPayload
+   typeNode: Node?
  RuntimeFieldLayoutBackend
+   nestedTypeNode(for:parentMetadata:)
~   nestedTypeName -> prints nestedTypeNode with .default
~   expandedFieldOffsets / walkNestedExpandedFieldOffsets   sync -> async
```

一行布局注释的类型名怎么来：

```text
interface print (SwiftDeclarationPrinter)
  modelFieldBlock
    renderConfiguration.demangleResolver = typeDemangleResolver   (.builder: SemanticTypeNodePrinter)
    renderConfiguration.spellsFieldLayoutTypeNamesThroughResolver = true
    FieldLayoutRenderer.storedFieldComments
      MachOFile  -> StaticFieldLayoutBackend
                      provider.nestedFieldOffsetTree  -> [NestedFieldOffset(typeName, typeNode)]
                      for row: await configuration.fieldLayoutTypeName(printedName: row.typeName, typeNode: row.typeNode)
      MachOImage -> RuntimeFieldLayoutBackend
                      NestedFieldOffsetLevelMemo.level(for: metatype)  -> rows(typeName, typeNode)
                      for row: await configuration.fieldLayoutTypeName(printedName: row.typeName, typeNode: row.typeNode)
    fieldLayoutTypeName
      flag on, node present  -> (try? await demangleResolver.resolve(for: node))?.string   e.g. AnyAttribute, Swift::UInt32
      otherwise              -> printedName                                               e.g. __C.AGAttribute (dump)
    expandedFieldOffsetComment(fieldName:typeName:offset:...)
```

## 详细设计

### 名字表

```swift
struct CImportedTypeSwiftNameTable: Sendable {
    init(typeContextDescriptors: [TypeContextDescriptorWrapper], in context: some ReadingContext) {
        var swiftNamesByIdentity: [Node: String] = [:]
        for descriptorWrapper in typeContextDescriptors {
            let descriptor = descriptorWrapper.typeContextDescriptor
            guard (try? descriptor.isCImportedContextDescriptor(in: context)) == true,
                  let userFacingName = try? descriptorWrapper.namedContextDescriptor.name(in: context),
                  let identity = try? SymbolicDemangler.demangleContext(for: descriptorWrapper.asContextDescriptorWrapper, in: context)
            else { continue }
            let importInfo: TypeImportInfo?
            if descriptor.hasImportInfo {
                // An import info that cannot be read is not an absent one.
                guard let readImportInfo = try? descriptor.typeImportInfo(in: context) else { continue }
                importInfo = readImportInfo
            } else {
                importInfo = nil
            }
            let key = Self.key(for: identity)
            guard let swiftName = Self.knownSwiftName(ofDescriptorNamed: userFacingName, importInfo: importInfo, isDirectlyInImportedModule: key.children.first?.kind == .module) else { continue }
            swiftNamesByIdentity[key] = swiftName
        }
        self.swiftNamesByIdentity = swiftNamesByIdentity
    }

    /// The Swift name a C-imported descriptor's name is known to be, or nil.
    static func knownSwiftName(ofDescriptorNamed userFacingName: String, importInfo: TypeImportInfo?, isDirectlyInImportedModule: Bool) -> String? {
        if let importInfo, importInfo.isRelatedEntity { return nil }
        guard let abiName = importInfo?.abiName, abiName != userFacingName else {
            return isDirectlyInImportedModule ? userFacingName : nil
        }
        return trustsUserFacingName(userFacingName, importInfo: importInfo!) ? userFacingName : nil
    }
}
```

（实现时去掉强制解包，写法以代码为准。）`trustsUserFacingName` 不改：`declaredTypeName(of:)` 仍用它决定改名，`refusesNameWithoutABIName` 测试的语义（「没有 ABI 名不算可信的改名」）保持。

### 渲染配置

```swift
extension DeclarationRenderConfiguration {
    /// Set by a printer that spells its declarations' types through
    /// `demangleResolver`: a field layout tree row then spells its type the
    /// same way. The dump never sets it.
    @Init(.ignore)
    package var spellsFieldLayoutTypeNamesThroughResolver: Bool = false   // stored property in the struct

    package func spellingFieldLayoutTypeNamesThroughResolver(_ spellsThroughResolver: Bool) -> Self

    /// The type name a field layout tree row prints: `typeNode` spelled
    /// through `demangleResolver` when the printer asks for it, else
    /// `printedName`, the `.default` spelling the tree was built with.
    package func fieldLayoutTypeName(printedName: String, typeNode: Node?) async -> String
}
```

解析失败或得到空串时退回 `printedName`，一行注释不会因此消失。

### 两条后端

离线：

```swift
@SemanticStringBuilder
private func expandedFieldOffsets(for mangledTypeName: MangledName, baseOffset: Int) async -> SemanticString

@SemanticStringBuilder
private func renderNestedFieldOffsetTree(_ nodes: [NestedFieldOffset], ancestors: [Bool]) async -> SemanticString {
    for (index, node) in nodes.enumerated() {
        let isLast = index == nodes.count - 1
        let typeName = await configuration.fieldLayoutTypeName(printedName: node.typeName, typeNode: node.typeNode)
        await configuration.commentRegion(.fieldLayoutNode) {
            configuration.expandedFieldOffsetComment(fieldName: node.fieldName, typeName: typeName, offset: node.offset, baseIndentation: configuration.indentation, ancestors: ancestors, isLast: isLast)
            await renderNestedFieldOffsetTree(node.children, ancestors: ancestors + [isLast])
        }
    }
}
```

`storedFieldComments` 里 `configuration.optionalContent(.printFieldOffset) { configuration.commentRegion(.fieldOffset) { … } }` 换成 async 版本。

进程内：`walkNestedExpandedFieldOffsets` 同样改成 async，环与深度判断、两个 `#log` 告警原样；`nestedStructFields` / `nestedEnumPayloads` 建行时调 `nestedTypeNode(for:parentMetadata:)` 一次，存节点，`typeName` 由同一个节点 `.default` 印出（与改前相同的派生）。

## 替代方案考量

- **按 `DemangleResolver` 的 case 决定**（`.builder` 就经它印）：dump 不会受影响，但「是 `.builder`」不等于「是 interface 打印器」，宿主自己传 `.builder` 时行为会悄悄变。否。
- **dump 的注释也经它自己的 `demangleResolver`**：dump 测试用 `.options(.test)`，会改 dump 快照；dump 按 mangled 身份打印，没有拼写开关。超出范围，记为后续项。
- **`NestedFieldOffset.typeName` 直接改成打印器拼写**：SwiftLayout 在 SwiftPrinting 之下，拿不到打印器；而且 `typeName` 还是防环键，必须是与打印无关的稳定拼写。否。
- **进程内渲染时重新 demangle 取节点**：不占缓存内存，但把 0067 去掉的 demangle 成本带回来（前期调研 8）。否。
- **同名类型也写 `__C::`，只把声明行改成 `__C::`**：声明行不能带模块；而且同名类型的 Swift 名二进制已经证明了，与改了名的类型一样写裸名才一致。否。

## 影响

### 源码兼容性（source compatibility）

纯新增。`NestedFieldOffset` 多一个公开属性，`init` 多一个带默认值的参数，原有调用点不变。渲染配置的新成员是 `package`。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：`SwiftPrinting`、`SwiftDeclarationRendering`、`SwiftLayout`；interface 输出变化：同名 C 类型的引用与扩展头少了 `__C.`；开了展开字段偏移时注释的类型名与声明写法一致（C 类型 Swift 名、模块选择器、`any`、语法糖、私有类型不带判别符、局部类型只写名字）。每一行多一次经打印器的异步打印，开销在交付前实测。dump、diff 键、snapshot 不变。
- RuntimeViewer：用同一个打印器，内容区的接口文本跟着变；Imported Type Names 切到 C 名时注释也写 C 名。它的 `ExpandedFieldOffsetTransformer` 模板收到的 `typeName` 变成打印器拼写。不需要改 RuntimeViewer 代码。

### 文档与示例

`swift-section interface --help`（`--c-imported-type-name-spelling`）、agent 插件 skill、术语表、模块参考、演进账本。

## API 演进与废弃策略

无废弃。新增的 `NestedFieldOffset.typeNode` 是可选值，没有它的旧构造点照旧印 `typeName`。

## 落地步骤

1. **名字表收同名条目**（已完成：行为测试先红后绿；两个审查 agent 各一轮，修了文档说法；SymbolTestsCore 的 interface 快照重录，只变了 `__C.CMTime` → `CMTime` 两行；`CImportedTypeConformanceInterfaceTests` 按新拼写改了定位用的类型名） —— 改动地图第 1–6 行
   - 行为：同名 C 类型的引用写裸名（`var plain: ProbePlainValue`）
   - 行为：同名 C 类型的扩展头写裸名（`extension ProbePlainValue: Swift.Equatable`）
   - 行为：解析器找到模块时同名类型写成 `模块.名字`
   - 行为：C 名模式下同名类型的引用照旧写 `__C.ProbePlainValue`
   - 行为：不可信的改名（`ProbeOwnerKey`）照旧写 `__C.ProbeOwnerKey`
   - 行为：名字表收同名类型、不收嵌在 C 类型里的匿名结构
   - 行为：同名类型的声明名不带 C 名标注
2. **离线路径的布局注释经打印器拼写**（已完成：行为测试先红后绿；两个审查 agent 各一轮，修了两条测试——dump 守护测试原先用 `.default` 解析器、证明不了开关，C 名测试原先在旧代码上也会过；受波及的六个测试目标 1082 个测试全过，离线与进程内的对照测试在这一步仍是绿的，因为它的嵌套行只有标准库类型与 builtin） —— 改动地图第 7–10、12 行
   - 行为：离线路径的布局注释里，改了名的 C 类型写声明用的 Swift 名（`identifier (AnyFooIdentifier)`）
   - 行为：离线路径的布局注释里，同名 C 类型写裸名
   - 行为：C 名模式下布局注释写 mangled 的 C 名（`__C.AGFooIdentifier`）
   - 行为：开了模块选择器时布局注释写 `Swift::UInt32`
   - 行为：dump 的布局注释仍是 `.default` 拼写
3. **进程内路径的布局注释经打印器拼写**（已完成：行为测试先红后绿；两个审查 agent 各一轮，补了三条测试——打印器提前释放会让对照测试两边都退回 `.default` 而假绿，现在保住它的生命周期并要求行里出现 `::`；对照从子集改成逐行相同；缓存测试补上开关打开的一轮；受波及的六个测试目标 1086 个测试全过） —— 改动地图第 11、13、14 行
   - 行为：进程内路径的布局注释同样写 Swift 名与模块选择器
   - 行为：进程内与离线两条路径对非泛型字段的布局注释逐行相同（且进程内的行里必须出现只有打印器才写的 `::`，防止两边都退回 `.default` 时空过）
   - 行为：带缓存与不带缓存的进程内展开逐字相同，开关关着（既有测试）与开着、用另一种拼写（新增）都一样
4. **文档** —— 改动地图第 15–19 行，以及第 4、5 行在第 3 步之后的补全

**收尾时必须判断两件事**：要不要配套专题文章；有没有引入新术语。结论写进决策日志。

## 后续项

- 跨镜像查找 C 类型的 Swift 名：dyld cache 里扫依赖目标镜像的镜像，取它们 descriptor 的名字（`AGSubgraphRef` → `Subgraph`）。另开提案。
- dump 的布局注释是否也走 dump 自己的 `demangleResolver`。
- `@retroactive` 按 mangling 的 `__C` 判定，模块解析出来后（`extension AttributeGraph::Graph: @retroactive …`）仍印。
- 同类排查：渲染层里另一处用 `.default` 印类型名进 interface 文本的是 `OpaqueReferenceSpelling`（`Sources/Output/SwiftDeclarationRendering/OpaqueReferenceSpelling.swift:142`、`:145`，没展开的 opaque 引用的泛型实参与所属声明的注释），同样不带模块选择器、`any` 与名字表。它走的是另一套拼写（`textualInterface`），单独处理。
- 0106 的疑似遗留（第 1 步审查按编译器源码推断，未实测；若属实，`next` 上就有）：`NS_ERROR_ENUM` 生成的 `Code` 枚举 descriptor 的名字是 `Code`、ABI 名是错误类型自己的 C 名（如 `MTLLibraryError`），不以 `Code` 结尾，于是被当成可信的顶层改名，引用印成裸的 `Code`，而 Swift 的拼写是 `MTLLibraryError.Code`。要另修 `trustsUserFacingName`。
- 嵌套字段是 opaque 类型的行：经打印器后写成没展开的 `textualInterface` 拼写，而那个类型自己的声明是 `OpaqueTypeRewriter` 展开过的，两者仍不一致（改前的 `.default` 也不一致）。打印器给注释行印类型时没有 `targetNode`，展开不了。
- 两条路径的对照还没覆盖的嵌套行形状：variadic 泛型的 pack 实参、整数泛型参数（`InlineArray<3, UInt8>`）、按层里自己的 metadata 绑定的关联类型成员（进程内可能印 `[Int].Element`，离线投影成 `Int`）；位置命名的局部类型（`(Visitor in $<地址>)`）进程内与离线的地址不同。都是改前就有的差别，本提案没有让它变好或变坏。
- **符号索引的建索引死锁**（第 3 步写测试时撞上，`next` 上就有；栈里没有本分支改过的代码）：`SwiftSymbolIndexStore.Storage.demangledIndex(reportingProgressTo:)`（`Sources/Symbols/SwiftSymbols/SwiftSymbolIndexStore.swift:265`）先切到大栈线程、再取这个镜像的建索引锁；持锁的那个线程在 `DemanglingWave.waitUntilDemangled()`（`:1771`）等一批 demangle，而每一批也要先切到大栈线程（`:1760`）。同一 QoS 的大栈池只有 16 个线程，当 15 个以上的调用方同时为同一个镜像建索引、都切到大栈后在锁上排队时，池子被占满，持锁者的那批 demangle 永远分不到线程。观测到的触发方式：同一个测试进程里两个测试各自对 dlopen 进来的 fixture 做进程内的 `SwiftInterfaceBuilder.prepare()`（`prepareWithProgress` 从 `DispatchQueue.global(qos: .userInitiated)` 并发进入，共 20 个线程），同时还有别的套件在跑。修法方向：等锁不占大栈线程（先取锁、或把等待者挡在切大栈之前），或者让 wave 的批次不走同一个池子。当时的线程采样只留在 agent 的日志目录，没进仓库；要修时先照上面的触发方式造一条能卡住的测试（带看门狗）。本分支的进程内测试因此改在渲染器接缝上测，不建索引。
- C++ 类模板特化（顶层、无命名空间）的 descriptor 的名字带尖括号（`Box<CInt>`），按 IRGen 的规则不写 ABI 名，本提案后它的引用从 `__C.Box<CInt>` 变成 `Box<CInt>`。两种写法都不是可声明的 Swift 拼写，没有变坏；要不要单独处理留给 C++ interop 的提案。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-25 | Created as Draft | AttributeGraph 的 interface 里，同名 C 类型的声明写裸名、扩展头写 `__C::`，布局注释用 C 名且不带模块选择器；补齐 0106 留下的这两处 |
| 2026-11-25 | 范围 | 用户选定只做二进制能证明的部分：同名类型写裸名、布局注释跟开关；镜像里没有 descriptor 的类型保留 `__C::`，跨镜像查找另开提案 |
| 2026-11-25 | 批准 | 用户调用 `implement-feature` 即批准，提案由 agent 起草、用户事前未审阅 |
| 2026-11-25 | 开始实现 | 功能分支 `feature/consistent-c-imported-type-spelling`，从 `next` 切出 |
| 2026-11-25 | 调研更正 | 对话里曾把 `AGTreeValue`、`AGTypeSignature` 归为「有 descriptor、没改名」；读 cache 字节后确认它们改了名（`TreeValue`、`Signature`）但不可信，照旧写 `__C::`，不在本提案范围 |
| 2026-11-25 | 两条后端一起改 | `OfflineSpecializationParityTests` 要求两条路径逐字节一致 |
| 2026-11-25 | 进程内缓存存节点 | 渲染时重算会带回 0067 去掉的 demangle 成本 |
| 2026-11-25 | 第 1 步审查（两个审查 agent） | 文档里「只有没有 descriptor 的保留 `__C.`」说错了：改名不可信的（`ProbeOwnerKey`、`AGTreeValue`）也保留，CLI 帮助、插件 skill 与 `CImportedTypeNameSpelling` 的注释已改。名字表在锁内 demangle：A61 第一处已裁决「打印器的一次性建表不改锁」，理由（入口已切到大栈）对 0106 的名字表同样成立，不改，第 5 步登记。`Code` 枚举与 C++ 模板特化记为后续项。`Documentations/README.md` 缺登记是误报：项目惯例是 draft 落地时才登记 |
| 2026-11-25 | 进程内测试改在渲染器接缝上 | 最初用进程内 `SwiftInterfaceBuilder` 打 dlopen 进来的 fixture，撞上符号索引的建索引死锁（后续项有详情，是 `next` 上的旧问题）。改为用打印器自己的 `typeDemangleResolver` 直接驱动 `FieldLayoutRenderer`，与打印器构造渲染配置的方式相同、但不建索引；离线与进程内的逐行对照照样做，以进程内的行是离线行的子集为准（进程内从活的 metadata 读偏移，可能更早停下） |
| 2026-11-25 | 第 3 步审查（两个审查 agent） | 测试有三处证明力不够，已补（见落地步骤 3）。`SpecializedRuntimeTypeNameTests` 改了期望：注释行和字段声明一样写 `SwiftSpecializationTests.RuntimeNamedPrivateArgument`，测试要证明的「保留模块」不变；运行时名字里判别符的恢复另有 `RuntimeTypeNamePrivateDiscriminatorTests` 守着，不另加 dump 侧的孪生测试。pack、整数泛型参数、关联类型成员这几种嵌套行的两条路径对照、位置命名的局部类型在两条路径地址不同，都是改前就没覆盖的，记为后续项。进程内缓存多存节点的内存成本，交付前实测 |
| 2026-11-25 | 第 2 步审查（两个审查 agent） | 两条测试证明不了它声称的：dump 守护测试改成用一个把所有类型都印成固定字样的解析器，开关关着不生效、开着才生效；C 名测试加开模块选择器。注释行跟着声明不带私有判别符、带语法糖，是这次有意的一致，写进「提议方案」与「影响」；opaque 行记为后续项。每行一次异步打印的开销，交付前在大框架上实测 |
