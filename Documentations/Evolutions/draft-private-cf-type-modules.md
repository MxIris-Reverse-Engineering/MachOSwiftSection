# Draft - 私有 CF 类型按导出 `GetTypeID` 的镜像解析所属模块

- **状态**: Accepted
- **作者**: JH
- **创建日期**: 2026-11-25
- **最后更新**: 2026-11-25
- **所属愿景**: 无
- **关联提案**: [0105 swift-type-indexing-package](0105-swift-type-indexing-package.md)（`__C` 类型按 SDK 解析模块，`DeclaredTypeNameSource` 就是它定下的接口）；[0106 c-imported-type-name-spelling](0106-c-imported-type-name-spelling.md)（引用处改用描述符给的 Swift 名，本提案补上它缺的模块）
- **实现分支 / PR**: `feature/private-cf-type-modules`（worktree `.worktrees/MachOSwiftSection-PrivateCFTypeModules`），叠在本地 `next` 上：那里有 `feature/moved-swift-type-modules` 的本地合并、尚未推到 `origin/next`，它同样改了 `SwiftInterfaceBuilderTypeNameProvider.swift`
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接
- **网页版**: 同目录同名的 `.html`
- **涉及仓库**: 只有 MachOSwiftSection。RuntimeViewer 自己登记类型名来源，要它也受益需要一行后续改动（见「非目标」）

## 摘要

`swift-section interface --resolve-c-module-names` 能把公开的 C 导入类型写到真实模块下（`__C.CGColorRef` → `CoreGraphics.CGColor`），私有的 CF 类型却查不到模块：SDK 里没有它们的头文件，依赖镜像的 Objective-C 元数据也不列 CF 类型，于是按 0106 的规则只印描述符给的裸名（`CGSVGDocument`）。本提案在 `SwiftTypeNameResolution` 里新增 `CFDeclaredTypeNames`，它是 swift-type-indexing 的 `DeclaredTypeNameSource` 的又一个实现：从镜像的导出表里找出每个 `…GetTypeID` 函数，列出它定义的 CF 类型（`_CGSVGDocumentGetTypeID` → `CGSVGDocumentRef`）。`SwiftInterfaceBuilderTypeNameProvider` 为根镜像和每个直接依赖各登记一个。之后 `CGSVGDocumentRef` 归到 CoreSVG，引用印成 `CoreSVG.CGSVGDocument`。打印器、swift-type-indexing 和 CLI 参数都不改。

## 动机

**现象**（按代码推断，没有实跑 CLI）：macOS 27.2 的 SwiftUICore 用到私有的 `CGSVGDocumentRef`。0106 之后，`interface --resolve-c-module-names` 把它的引用印成 `CGSVGDocument`，没有模块；公开的 `CGImageRef` 则印成 `CoreGraphics.CGImage`。同一份接口里，读者分不出 `CGSVGDocument` 来自哪个框架，也无从知道它和另一个镜像里同名的类型是不是同一个。

**规模**：macOS 27.2 的 dyld shared cache 里，被 Swift 代码用到的 CF 类一共 66 个，其中 20 个不在公开 SDK 的头文件里（测法见「前期调研」第 1 条）：

| 私有 CF 类型（typedef 名） | 描述符里的 Swift 名 | 导出 `GetTypeID` 的镜像 | 用到它的 Swift 镜像 |
|---|---|---|---|
| `CGSVGDocumentRef` | `CGSVGDocument` | CoreSVG | SwiftUICore |
| `CGColorTransformRef`、`CGContextDelegateRef` | 去掉 `Ref` | CoreGraphics | AppKit |
| `AGGraphRef`、`AGSubgraphRef` | `Graph`、`Subgraph` | AttributeGraph | SwiftUICore、AttributeGraph |
| `RIOPxrSdfLayerRef` 等 9 个 `RIO…Ref` | 去掉 `Ref` | CoreRealityIO | RealityIO |
| `CAXUIElementRef` | `CAXUIElement` | CoreAccessibility | CoreAccessibility（自己） |
| `CFPhoneNumberRef` | `CFPhoneNumber` | CorePhoneNumbers | IDSFoundation |
| `LSASNRef` | `LSASN` | LaunchServices（导出名 `__LSASNGetTypeID`） | GamePolicyFoundation |
| `CFXGPUDeviceRef`、`LXEntryRef`、`RTIImportOperation_t` | `CFXGPUDevice`、`LXEntry`、`ImportOperation` | 找不到 | VFX、ImageGenerationServices、_USDKit_RealityKit |

这些类型的 Swift 名 0106 已经能从描述符里读出来，缺的只有模块。模块不在二进制里（第 2 条），但定义 CF 类型的框架几乎都会导出一个 `<名字>GetTypeID` 函数，用公开类型验证，这个对应关系 46 个全对（第 3 条）。

## 前期调研

1. **哪些是 CF 类，怎么枚举。** ClangImporter 把指向带 `objc_bridge` / `objc_bridge_mutable` / `objc_bridge_related` 的 struct 的指针 typedef 当作 CF 类型（`swift/lib/ClangImporter/CFTypeInfo.cpp:75-78`），导入成 `ForeignKind::CFType` 的类，并合成一条 `_CFObject` 一致性（`swift/lib/ClangImporter/ImportDecl.cpp` 的 `importCFClassType`，`addSynthesizedProtocolAttrs(theClass, {KnownProtocolKind::CFObject})`）。它的类型描述符种类是 class，名字后的 import info 写着 `N<typedef 名>` 和 `St`（来自 C typedef，`swift/include/swift/ABI/TypeIdentity.h:41-55`、`swift/lib/IRGen/GenMeta.cpp:1585-1608`）。dyld 在 cache 里预存了所有 `__C` 类型一致性的表，`ipsw dyld swift --foreign <cache>` 能导出，键是「typedef 名 + `St`」；按协议 `_$s14CoreFoundation9_CFObjectMp` 筛出的就是被 Swift 用过的全部 CF 类。macOS 27.2：66 个，20 个私有（「动机」那张表），46 个公开。
2. **模块不在二进制里。** CF 类的描述符挂在 `__C` 模块下，`_CFObject` 等合成的一致性在 `__C_Synthesized`（mangling 里的 `SC`），都不带真实模块。Swift 给一个 Clang 声明定模块时取的是**顶层** Clang 模块（`swift/lib/ClangImporter/ClangImporter.cpp:3143-3154`，注释写明 submodule 没有自己的 `ClangModuleUnit`），所以 LaunchServices 里的类型在 Swift 里属于 CoreServices（SDK 的 `CoreServices.framework/Modules/module.modulemap:43` 把 LaunchServices 声明成 CoreServices 的 submodule）。
3. **`GetTypeID` 的镜像就是模块。** 对 46 个公开 CF 类逐个查 `_<去掉 Ref 的名字>GetTypeID` 由 cache 里哪个镜像导出（`ipsw dyld symaddr`），再和 SDK 里声明它的框架比，46 个全部一致；其中 `IOSurfaceRef` 在 CoreGraphics 的头文件里有一份前向声明，真正的声明在 IOSurface，导出镜像也是 IOSurface。私有的 20 个里有 17 个能这样找到镜像，`CFXGPUDeviceRef`、`LXEntryRef`、`RTIImportOperation_t` 找不到对应的导出。Core* 框架一共导出约 190 个公开 SDK 里没有的 `…GetTypeID`（CoreMedia 75、CoreRealityIO 41、CoreGraphics 23、CoreSVG 16、CoreFoundation 12），并不是每个都对应 Swift 用到的类型。
4. **打印器在模块解析出来以后已经会用描述符的名字。** 引用处 `TypeNodePrintable.printType`（`Sources/Output/SwiftPrinting/NodePrintables/TypeNodePrintable.swift:186-268`）：模块经 `resolvedModuleName(of:siblingIdentifier:)`（`NodePrintable.swift:186-196`，先按 C 名查，再按去掉 `Ref` 的名字查）解析；标识符依次取解析器的 `swiftName(forCName:category:)`、0106 名字表里描述符给的名字、C 名。声明行 `declaredTypeName(of:)`（`SwiftDeclarationPrinter+Headers.swift:153-183`）同样在解析器给不出 Swift 名时退回描述符的名字。所以只要模块查得到，私有 CF 类型就会印成 `CoreSVG.CGSVGDocument`，打印器不用改。
5. **swift-type-indexing 已有开放的注册表。** 0.2.0 的 `DeclaredTypeNameSource`（`Sources/TypeIndexing/DeclaredTypeNameSource.swift`）：一个依赖镜像报出它声明的类型名，`TypeDatabase.moduleName(forTypeName:)` 只在模块接口和 API notes 都没有这个名字时，才按登记顺序一个个读这些来源，第一个声明了它的镜像胜出，模块名取自 `TypeDatabase.moduleName(forImagePath:)`（镜像文件名去掉扩展名与 `libswift` 前缀）。文档写明这个包自己不读 Mach-O。MachOObjCSection 0.8.209 的 `ObjCDeclaredTypeNames`（`Sources/ObjCTypeIndexing/ObjCDeclaredTypeNames.swift`）是现在唯一的实现，报出类、协议、struct 和 union 名，不含 CF 类型。
6. **TypeDatabase 的 CF 去 `Ref` 规则只认 SDK 里有的名字。** `TypeDatabase.swiftName(forCName:category:)` 在 API notes 没有改名时，只有去掉 `Ref` 的名字出现在模块接口或 API notes 的归属表里才返回它，运行时登记的名字不算。私有 CF 类型因此拿不到解析器给的 Swift 名，走第 4 条里描述符那一档，`AGGraphRef` 正确地印成 `Graph` 而不是 `AGGraph`。
7. **现在谁被登记。** `SwiftInterfaceBuilderTypeNameProvider.setup()`（`Sources/Output/SwiftTypeNameResolution/SwiftInterfaceBuilderTypeNameProvider.swift:81-98`）只给每个**直接**依赖登记一个 `ObjCDeclaredTypeNames`，根镜像自己不登记。只取直接依赖是有意的（`Sources/Output/SwiftInterface/SwiftInterfaceBuilderDependencies.swift:9-19`：每个依赖模块都要生成一份 SourceKit 接口，传递闭包有几百个镜像）。CLI 里只有 `interface --resolve-c-module-names` 会接上它（`Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift:273-320`），依赖按本机 dyld cache 解析。RuntimeViewer 不经这个 provider，它在 `RuntimeViewerCore/Sources/RuntimeViewerCore/Sections/Swift/RuntimeSwiftSection.swift:2013` 给自己打开的每个镜像登记一个 `ObjCDeclaredTypeNames`。
8. **按这个设计能覆盖多少。** 对「动机」表里的 20 个查使用方的直接依赖（`dyld_info -dependents`）：CoreSVG、CoreGraphics、AttributeGraph、CoreRealityIO 都是使用方的直接依赖，覆盖 14 个；`CAXUIElementRef` 由使用方自己定义，登记根镜像后覆盖，共 15 个。剩下 5 个：`LSASNRef` 的导出在 LaunchServices，使用方只直接链接重新导出它的 CoreServices；`CFPhoneNumberRef` 的 CorePhoneNumbers 不是 IDSFoundation 的直接依赖；另外 3 个没有对应的导出。
9. **带 `Ref` 的名字在 Swift 里不能用。** ClangImporter 只在 Swift 3 及以后的名字里去掉 `Ref`（`swift/lib/ClangImporter/ImportName.cpp:2269-2277` 的 `swift3OrLaterName`），带 `Ref` 的拼写只剩一个改名用的兼容别名。所以一个私有 CF 类型如果在本镜像里没有描述符（只出现在符号签名里），模块解析出来以后会印成 `CoreSVG.CGSVGDocumentRef`，能读懂，但不是能编译的写法。去掉 `Ref` 时还要避开重名：`IOSurfaceRef` 的描述符名字就是 `IOSurfaceRef`，因为 IOSurface 里已有同名的 Objective-C 类 `IOSurface`（`hasNamingConflict`）。
10. **顺带发现、未验证（推测）**：第 6 条的去 `Ref` 规则不看重名，而打印器先问解析器、后用描述符。若一个二进制链接了 IOSurface，`__C.IOSurfaceRef` 在 `--resolve-c-module-names` 下可能被印成 `IOSurface.IOSurface`，正确写法是 `IOSurface.IOSurfaceRef`。这与本提案无关，要在 Ultra 上复现后另行处理。

## 提议方案

1. **新增 `CFDeclaredTypeNames`**（`Sources/Output/SwiftTypeNameResolution/`），实现 `DeclaredTypeNameSource`，与 `ObjCDeclaredTypeNames` 同形：`init(machO:imagePath:)`，`declaredTypeNames()` 读 `machO.exportedSymbols`，每个名为 `_<名字>GetTypeID` 的导出给出 `<名字>Ref`；`<名字>` 以下划线开头的私有函数（`__LSASNGetTypeID`）同时给出去掉前导下划线的拼写（`LSASNRef`）。
2. **provider 登记它**：`setup()` 交给 `TypeDatabase.index(dependencies:moduleFilter:)` 的来源变成「根镜像的 `CFDeclaredTypeNames`，然后每个直接依赖依次是 `ObjCDeclaredTypeNames`、`CFDeclaredTypeNames`」。根镜像排第一，因为它自己定义的类型由它自己说了算；根镜像不进 `moduleFilter`，不触发 SourceKit 接口生成。来源的排列抽成一个可测的静态函数。
3. **打印器、swift-type-indexing、CLI 参数都不改**。效果全部经现有路径体现：`moduleName(forTypeName:)` 多答出一些名字，打印器按调研第 4 条的规则写成 `模块.描述符名`。`--resolve-c-module-names` 的帮助文字和 swift-section skill 的说明补一句来源。

### 非目标

- **跟着重新导出找子框架**（`LSASNRef` → CoreServices）：`ObjCDeclaredTypeNames` 同样不跟重新导出，两种来源应该一起做；MachOKitExtensions 3.3.0 的 `DependencyTraversal` 也只有 `direct` / `transitive`（`DependencyClosure.swift:6-11`）。另开提案。
- **间接依赖**（`CFPhoneNumberRef`）：放宽到传递闭包会让 SourceKit 接口生成回到几百个模块（调研第 7 条）。要做也应该只给运行时来源放宽、不动 `moduleFilter`，另开提案。
- **没有 `GetTypeID` 导出的类型**（`CFXGPUDeviceRef` 等 3 个），以及非 CF 的私有 C 类型（struct、enum、`swift_wrapper` typedef，如 `AGTreeElement`）：二进制里没有可靠的模块证据。
- **没有描述符时给出 Swift 名**：仍印 `模块.XRef`（调研第 9 条）。要改得让 TypeDatabase 的去 `Ref` 规则认运行时名表，会碰上重名与 `swift_name` 改名（见「替代方案」第 5 条）。
- **根镜像自己的 Objective-C 类**：现在也没登记，是另一个问题，本提案不顺手改，免得 ObjC 输出跟着变。
- **`dump`**：`dump` 不做 `__C` 模块解析，本提案不引入。
- **RuntimeViewer 接入**：本库发版后，在 `RuntimeSwiftSection.swift:2013` 的 `metadataSources` 里加一个 `CFDeclaredTypeNames`，属于 RuntimeViewer 的改动。
- **调研第 10 条的 `IOSurfaceRef` 疑似问题**：先复现，另行修复。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Sources/Output/SwiftTypeNameResolution/CFDeclaredTypeNames.swift` · `CFDeclaredTypeNames` | 新增 | `DeclaredTypeNameSource` 的实现：读导出表，`…GetTypeID` → typedef 名；内部静态函数 `typedefNames(forExportedSymbolName:)` 承载命名规则 | 私有 CF 类型的模块证据 | 1 |
| `Tests/SwiftTypeNameResolutionTests/CFDeclaredTypeNamesTests.swift` | 新增 | 命名规则的表驱动测试；现场编译的 C 动态库经 `MachOFile` 与 `MachOImage` 两种读法读出的名字 | 规则与两种读法 | 1 |
| `Sources/Output/SwiftTypeNameResolution/SwiftInterfaceBuilderTypeNameProvider.swift:81-98` · `setup()` | 修改 | 来源改为「根的 CF，然后每个依赖的 ObjC、CF」；排列抽成 `static func declaredTypeNameSources(root:dependencies:)`（internal） | 登记新来源，顺序可测 | 2 |
| `Tests/SwiftTypeNameResolutionTests/PrivateCFTypeModuleTests.swift` | 新增 | 来源顺序；`TypeDatabase` 按新来源归属模块；用现场编译的 Swift 库验证接口里的拼写 | 端到端证明 | 2 |
| `Sources/Executables/swift-section/Commands/InterfaceCommand.swift:33` · `resolveCModuleNames` 的 `help` | 修改 | 来源列表补上「依赖导出的 `…GetTypeID`（CF 类型）」 | `--help` 就是文档 | 3 |
| `AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md` 第 8 节 | 修改 | 「没有 sourcekitd 时由 API notes 与 Objective-C 元数据归属」补上导出的 `GetTypeID`；加一句私有 CF 类型的效果与第 9 条的 `XRef` 退路 | CLI 行为变了，skill 同批更新 | 3 |
| `CLAUDE.md` · SwiftTypeNameResolution 一条 | 修改 | 列出 `CFDeclaredTypeNames` | 模块清单与代码同步 | 3 |
| `Documentations/Evolutions/README.md`、`Documentations/README.md` | 修改 | 登记本提案；落地时改编号与状态 | 文档索引 | 0、3 |
| `Documentations/Internal/ProjectEvolutionLog.md` | 修改 | 落地时追加一节 | 演进账本 | 3 |

## 架构图

改了什么：

```text
SwiftTypeNameResolution/
+ CFDeclaredTypeNames<MachO: MachORepresentable & Sendable>      DeclaredTypeNameSource
+     declaredTypeNames()   machO.exportedSymbols: _<Name>GetTypeID -> "<Name>Ref"
~ SwiftInterfaceBuilderTypeNameProvider.setup()
~     TypeDatabase.index(dependencies:
+         [CFDeclaredTypeNames(root),
               ObjCDeclaredTypeNames(dependency1),
+              CFDeclaredTypeNames(dependency1),
               ObjCDeclaredTypeNames(dependency2),
+              CFDeclaredTypeNames(dependency2), ...],
          moduleFilter: dependency module names)                  unchanged: root never generates an interface

swift-type-indexing 0.2.0 (unchanged)
  TypeDatabase.moduleName(forTypeName:)
      1. module interfaces, API notes
      2. runtime declared names, folded source by source in registration order

SwiftPrinting (unchanged)
  TypeNodePrintable.printType
      module      <- moduleName(forTypeName: C name, then Ref-stripped)
      identifier  <- swiftName(forCName:) ?? descriptor name (0106) ?? C name
```

一个引用怎么印出来（SwiftUICore 里的 `__C.CGSVGDocumentRef`）：

```text
printType(__C.CGSVGDocumentRef)
├─ swiftNameFromDescriptor            -> "CGSVGDocument"           (0106 name table)
├─ resolvedModuleName(__C, "CGSVGDocumentRef")
│   └─ SwiftInterfaceBuilderTypeNameProvider.moduleName
│       └─ TypeDatabase.moduleName
│           ├─ SDK tables                                           miss
│           ├─ CFDeclaredTypeNames(SwiftUICore)                     miss    (+)
│           ├─ ObjCDeclaredTypeNames(AttributeGraph)                miss
│           ├─ CFDeclaredTypeNames(AttributeGraph)                  miss    (+)
│           ├─ ...
│           └─ CFDeclaredTypeNames(CoreSVG): "CGSVGDocumentRef"     -> "CoreSVG"   (+)
├─ swiftName(forCName: "CGSVGDocumentRef")                          -> nil (no API notes, not SDK-indexed)
└─ writes  CoreSVG . CGSVGDocument
```

## 详细设计

### API

```swift
#if os(macOS)

import MachOKit
import TypeIndexing

/// The Core Foundation types an image defines, as swift-type-indexing's `TypeDatabase` reads
/// them: one for every `…GetTypeID` function the image exports.
///
/// A CF type's Swift metadata names the type but never its module — the descriptor sits in
/// `__C` — while the framework defining it exports the type's `GetTypeID` function. Registered
/// beside `ObjCDeclaredTypeNames`, this attributes a private CF type such as `CGSVGDocumentRef`
/// to the image exporting `CGSVGDocumentGetTypeID` (`CoreSVG`). `TypeDatabase` consults it only
/// for names neither the SDK's module interfaces nor its API notes attribute, and reads the
/// image's exports only on such a miss.
///
/// ```swift
/// let sources: [any DeclaredTypeNameSource] = dependencyImages.flatMap { image in
///     [
///         ObjCDeclaredTypeNames(machO: image, imagePath: image.imagePath),
///         CFDeclaredTypeNames(machO: image, imagePath: image.imagePath),
///     ]
/// }
/// ```
public struct CFDeclaredTypeNames<MachO: MachORepresentable & Sendable>: DeclaredTypeNameSource {
    public let imagePath: String

    private let machO: MachO

    /// - Parameters:
    ///   - machO: The image, in this process or in a file.
    ///   - imagePath: Its install path, which names the module its types are attributed to
    ///     (`…/CoreSVG.framework/Versions/A/CoreSVG` → `CoreSVG`).
    public init(machO: MachO, imagePath: String) {
        self.machO = machO
        self.imagePath = imagePath
    }

    /// The typedef name of every CF type the image exports a `GetTypeID` function for.
    public func declaredTypeNames() async -> [String] {
        machO.exportedSymbols.flatMap { exportedSymbol in
            Self.typedefNames(forExportedSymbolName: exportedSymbol.name)
        }
    }

    /// The typedef names an exported symbol implies: `_CGSVGDocumentGetTypeID` →
    /// `["CGSVGDocumentRef"]`, the private `__LSASNGetTypeID` → `["_LSASNRef", "LSASNRef"]`,
    /// any other symbol → `[]`.
    static func typedefNames(forExportedSymbolName symbolName: String) -> [String]
}

#endif
```

形状照 `ObjCDeclaredTypeNames<MachO: ObjCMetadataSource & Sendable>` 抄：同样的 `init(machO:imagePath:)`、同样的 `imagePath` 属性、同样放在 `#if os(macOS)` 里，名字按「来源 + `DeclaredTypeNames`」对称。泛型约束只要 `MachORepresentable & Sendable`：`exportedSymbols` 是 MachOKit `MachORepresentable` 的要求（`Sources/MachOKit/Protocol/MachORepresentable.swift:124-129`），`MachOFile`、`MachOImage` 和包装类型都有，不需要判断读取器种类。provider 的 `MachO` 约束经 `MachOSwiftSectionRepresentableWithCache: MachORepresentableWithCache: MachORepresentable, Sendable` 满足它。协议要求是 `async throws`，实现不会失败，所以写成不抛错的 `async`。

### 命名规则

1. 导出名必须以一个 `_` 开头（C 符号的 Mach-O 前缀），去掉它得到 C 函数名；Swift 符号（`_$s…`）和 Objective-C 符号（`_OBJC_…`）因为不以 `GetTypeID` 结尾自然落选。
2. C 函数名以 `GetTypeID` 结尾，去掉后缀的部分非空、由字母数字和下划线组成、不以数字开头，记为 `base`。
3. 给出 `base + "Ref"`；`base` 以下划线开头时，再给出去掉全部前导下划线后的 `+ "Ref"`（非空才给）。
4. 会产生一些不是类型的名字，例如 `CFGetTypeID` 给出 `CFRef`。它们只在某个查询恰好问到这个名字时才会命中，而那时 SDK 的归属已经先问过了，所以无害，不做过滤。

### 来源的排列

```swift
extension SwiftInterfaceBuilderTypeNameProvider {
    /// The declared-type-name sources `setup()` registers, in the order `TypeDatabase` folds
    /// them: the root's CF types first — a type the root defines is its own — then each direct
    /// dependency's Objective-C names and CF types, in dependency order.
    static func declaredTypeNameSources(root: MachO, dependencies: [MachO]) -> [any DeclaredTypeNameSource]
}
```

`setup()` 只把 `dependencies:` 参数换成这个函数的结果，`moduleFilter` 不变。

### 性能

`TypeDatabase` 只在一个名字查不到时才按顺序读下一个来源，读过的来源不再读。根镜像排第一，所以第一次未命中就会读一遍根镜像的导出表：SwiftUICore 这样的大镜像有数十万个导出，`exportedSymbols` 要建一个同样大的数组。第 3 步在 Ultra 上量一次 `interface --resolve-c-module-names` 的耗时变化；如果明显，改成直接遍历导出 trie、只取以 `GetTypeID` 结尾的名字。

## 替代方案考量

1. **在打印器上新注册一个 `ModuleNameResolving` 解析器**（讨论时最先选的方向，仍在本仓库）：否。swift-type-indexing 已经有 `DeclaredTypeNameSource` 这个注册表，「SDK 优先、按依赖顺序折叠、第一个声明者胜出、镜像路径换模块名」都在那里。另写一个解析器要么把这些规则抄一遍，要么和 `TypeDatabase` 对同一个名字给出不同答案，谁胜出取决于注册顺序。RuntimeViewer 也是经 `DeclaredTypeNameSource` 接入的，走同一个接口它只需加一行。
2. **让 swift-type-indexing 自己读导出表**：否。那个包按设计不读 Mach-O（`DeclaredTypeNameSource.swift` 的文档），读二进制的部分都由实现方提供。
3. **从 CF 运行时类注册取类型名**（`_CFRuntimeRegisterClass` 的 `CFRuntimeClass.className`）：否。要反汇编调用点才能找到参数，得到的仍然只是「哪个镜像定义了它」，和导出表等价；而且 `className` 是 `"CGSVGDocument"` 这样的显示名，不是 mangling 用的 typedef 名。
4. **用一致性符号里的模块**（`_$sSo10AGGraphRefaSQ14AttributeGraphMc`）：否。那是声明这条一致性的模块，不是类型的模块；合成的一致性在 `__C_Synthesized`；cache 里的这类本地符号大多被剥掉了。
5. **让 TypeDatabase 的去 `Ref` 规则也认运行时名表**，好在没有描述符时也给出 Swift 名：否。它不知道重名，会把 `IOSurfaceRef` 改成 `IOSurface`（调研第 9 条）；而打印器先问解析器、后用描述符，它还会把 `swift_name` 改过的 `AGGraphRef` 从 `Graph` 改坏成 `AGGraph`。
6. **跟着 `LC_REEXPORT_DYLIB` 把子框架的导出算进伞框架**：推迟，见「非目标」第一条。

## 影响

### 源码兼容性（source compatibility）

纯新增：多一个公开类型 `CFDeclaredTypeNames`，`SwiftInterfaceBuilderTypeNameProvider` 的公开接口不变。行为上，`--resolve-c-module-names` 下原本没有模块的私有 CF 类型会带上模块。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：`SwiftSectionKit` 的 `InterfaceRequest` 经 provider 自动受益，不用改代码。没有基线或快照测试开着 `__C` 模块解析（它要 SDK），渲染 A/B 校验不受影响。
- RuntimeViewer：它不经 provider，自己在 `RuntimeSwiftSection.swift:2013` 登记来源，本提案落地不改变它的输出。要受益，等本库发版后在那里加一个 `CFDeclaredTypeNames`（见「非目标」）。
- MachOKitUI、SymbolViewer：不用 `SwiftTypeNameResolution`，不受影响。

### 文档与示例

`swift-section interface --help` 里 `--resolve-c-module-names` 的说明、swift-section skill 第 8 节、`CLAUDE.md` 的模块清单，都在第 3 步同批更新。

## API 演进与废弃策略

- 没有被替代的旧 API，不需要废弃期。
- 纯新增，按 minor 版本发布。

## 落地步骤

0. **提案落盘、登记索引**（本次）—— 改动地图最后两行中的索引部分
1. **`CFDeclaredTypeNames` 与它的测试** —— 改动地图第 1、2 行
   - 行为：`exportedTypeIDFunctionNamesItsTypedef`（`_CGSVGDocumentGetTypeID` → `CGSVGDocumentRef`）
   - 行为：`underscoredTypeIDFunctionNamesBothSpellings`（`__LSASNGetTypeID` → `_LSASNRef`、`LSASNRef`）
   - 行为：`otherExportsNameNothing`（`_CGSVGDocumentCreate`、`_GetTypeID`、`_$s…`、`_OBJC_CLASS_$_…` → 空）
   - 行为：`readsACompiledLibrarysExportsThroughBothReaders`（用 `FixtureCompiler` 现场编译一个导出 `ProbeWidgetGetTypeID`、`_ProbeSecretGetTypeID`、`ProbeWidgetCreate` 的 C 动态库，`MachOFile` 与 `dlopen` 后的 `MachOImage` 读出同样的名字）
2. **provider 登记新来源，端到端验证** —— 改动地图第 3、4 行
   - 行为：`sourcesListTheRootFirstThenEachDependencyObjCBeforeCF`
   - 行为：`typeDatabaseAttributesAnExportedCFTypeToItsImage`（`TypeDatabase` 只登记第 1 步的 C 库、`moduleFilter` 不选任何模块，`moduleName(forTypeName: "ProbeWidgetRef") == "ProbeCF"`）
   - 行为：`interfacePrintsAPrivateCFTypeUnderItsDeclaringModule`（一个用桥接头引入 `CF_BRIDGED_TYPE(id)` 的 `ProbeWidgetRef`、在公开 struct 里存它的 Swift 库，接口里的字段类型印成 `ProbeCF.ProbeWidget`；先断言这个库确实带着 `ProbeWidgetRef` 的描述符）
   - 行为：`interfaceKeepsTheBareSwiftNameWithoutTheSource`（同一个库、不登记来源时仍是 0106 的 `ProbeWidget`）
   - 现场编译用 `FixtureCompiler`；它给不出桥接头的路径时，照 `Tests/SwiftInterfaceTests/CImportedTypeNameSpellingTests.swift` 的写法，并把这个能力缺口记进 shared-macho-testing-support 提案
3. **文档与系统镜像验证** —— 改动地图第 5–9 行
   - 在 Ultra 上对本机 cache 的 SwiftUICore、AppKit、RealityIO 跑 `interface --resolve-c-module-names`，确认 `CoreSVG.CGSVGDocument`、`AttributeGraph.Graph`、`CoreGraphics.CGColorTransform`、`CoreRealityIO.RIOPxrSdfLayer`，并量耗时变化（详细设计「性能」），结果记进本提案
   - 测试一律在 Ultra 上跑（公司那台不跑本库的测试），`--filter` 同时带 `--skip IntegrationTests`

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预计不需要：调用方契约都在 `CFDeclaredTypeNames` 的文档注释里，维护要知道的「为什么只取直接依赖、为什么不认运行时名表去 `Ref`」在本提案里。
- **有没有引入新术语** —— 预计没有。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-25 | Created as Draft | 起因是想知道 Swift 用到的私有 CF 类能否还原原名（`__C.CGSVGDocumentRef` → `CoreSVG.CGSVGDocument`）。调研发现 Swift 名 0106 已经从描述符取得，缺的是模块；定义 CF 类型的框架都导出 `GetTypeID`，46 个公开类型验证全对。 |
| 2026-11-25 | 实现放在本仓库，形式是 `DeclaredTypeNameSource` | 用户选定放在本仓库、不改 swift-type-indexing。调研发现用户设想的「类型索引开放注册表、各库注册自己的内容」已经以 `DeclaredTypeNameSource` 存在，ObjC 侧就是这样接入的，因此不再另写打印器解析器（替代方案第 1 条）。用户确认这个形式。 |
| 2026-11-25 | `IOSurfaceRef` 疑似问题先复现 | 用户定：先在 Ultra 上复现调研第 10 条，确认是真的再按 bug 修复另走一批，不并入本提案。 |
| 2026-11-25 | 用户批准，开始实现 | 轻量档，用户看过简报后批准。功能分支从本地 `next` 切，因为 moved-swift-type-modules 的本地合并也改了 provider 的 `setup()`，从 `origin/next` 切会在合回时冲突。 |
