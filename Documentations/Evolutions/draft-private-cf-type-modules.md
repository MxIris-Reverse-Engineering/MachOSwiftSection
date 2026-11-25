# Draft - 私有 CF 类型按导出 `GetTypeID` 的镜像解析所属模块

- **状态**: In Progress
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

`swift-section interface --resolve-c-module-names` 能把公开的 C 导入类型写到真实模块下（`__C.CGColorRef` → `CoreGraphics.CGColor`），私有的 CF 类型却查不到模块：SDK 里没有它们的头文件，依赖镜像的 Objective-C 元数据也不列 CF 类型，于是按 0106 的规则只印描述符给的裸名（`CGSVGDocument`）。本提案在 `SwiftTypeNameResolution` 里新增 `CFDeclaredTypeNames`，它是 swift-type-indexing 的 `DeclaredTypeNameSource` 的又一个实现：从镜像的导出表里找出每个 `…GetTypeID` 函数，列出它定义的 CF 类型（`_CGSVGDocumentGetTypeID` → `CGSVGDocumentRef`）。`SwiftInterfaceBuilderTypeNameProvider` 为根镜像登记它；每个直接依赖改登记新的 `ImageDeclaredTypeNames`，把这个镜像的 Objective-C 名字和 CF 类型合成一个来源，因为 `TypeDatabase` 每个镜像路径只收一个来源。`GetTypeID` 只负责定位：一个名字是不是 CF 类型，由根镜像自己的 foreign class 描述符决定，CF 来源只给出被它证实的名字。之后 `CGSVGDocumentRef` 归到 CoreSVG，引用印成 `CoreSVG.CGSVGDocument`。打印器、swift-type-indexing 和 CLI 参数都不改。

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
5. **swift-type-indexing 已有开放的注册表。** 0.2.0 的 `DeclaredTypeNameSource`（`Sources/TypeIndexing/DeclaredTypeNameSource.swift`）：一个依赖镜像报出它声明的类型名，`TypeDatabase.moduleName(forTypeName:)` 只在模块接口和 API notes 都没有这个名字时，才按登记顺序一个个读这些来源，第一个声明了它的镜像胜出，模块名取自 `TypeDatabase.moduleName(forImagePath:)`（镜像文件名去掉扩展名与 `libswift` 前缀）。文档写明这个包自己不读 Mach-O。MachOObjCSection 0.8.209 的 `ObjCDeclaredTypeNames`（`Sources/ObjCTypeIndexing/ObjCDeclaredTypeNames.swift`）是现在唯一的实现，报出类、协议、struct 和 union 名，不含 CF 类型。`TypeDatabase.register(dependencies:)` 按镜像路径去重（`Sources/TypeIndexing/TypeDatabase.swift:237-243`）：同一路径的第二个来源直接丢掉，所以一个镜像的几种名字必须放进同一个来源。这一条是实现时由端到端测试发现的，见决策日志。
6. **TypeDatabase 的 CF 去 `Ref` 规则只认 SDK 里有的名字。** `TypeDatabase.swiftName(forCName:category:)` 在 API notes 没有改名时，只有去掉 `Ref` 的名字出现在模块接口或 API notes 的归属表里才返回它，运行时登记的名字不算。私有 CF 类型因此拿不到解析器给的 Swift 名，走第 4 条里描述符那一档，`AGGraphRef` 正确地印成 `Graph` 而不是 `AGGraph`。
7. **现在谁被登记。** `SwiftInterfaceBuilderTypeNameProvider.setup()`（`Sources/Output/SwiftTypeNameResolution/SwiftInterfaceBuilderTypeNameProvider.swift:81-98`）只给每个**直接**依赖登记一个 `ObjCDeclaredTypeNames`，根镜像自己不登记。只取直接依赖是有意的（`Sources/Output/SwiftInterface/SwiftInterfaceBuilderDependencies.swift:9-19`：每个依赖模块都要生成一份 SourceKit 接口，传递闭包有几百个镜像）。CLI 里只有 `interface --resolve-c-module-names` 会接上它（`Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift:273-320`），依赖按本机 dyld cache 解析。RuntimeViewer 不经这个 provider，它在 `RuntimeViewerCore/Sources/RuntimeViewerCore/Sections/Swift/RuntimeSwiftSection.swift:2013` 给自己打开的每个镜像登记一个 `ObjCDeclaredTypeNames`。
8. **按这个设计能覆盖多少。** 对「动机」表里的 20 个查使用方的直接依赖（`dyld_info -dependents`）：CoreSVG、CoreGraphics、AttributeGraph、CoreRealityIO 都是使用方的直接依赖，覆盖 14 个；`CAXUIElementRef` 由使用方自己定义，登记根镜像后覆盖，共 15 个。剩下 5 个：`LSASNRef` 的导出在 LaunchServices，使用方只直接链接重新导出它的 CoreServices；`CFPhoneNumberRef` 的 CorePhoneNumbers 不是 IDSFoundation 的直接依赖；另外 3 个没有对应的导出。
9. **带 `Ref` 的名字在 Swift 里不能用。** ClangImporter 只在 Swift 3 及以后的名字里去掉 `Ref`（`swift/lib/ClangImporter/ImportName.cpp:2269-2277` 的 `swift3OrLaterName`），带 `Ref` 的拼写只剩一个改名用的兼容别名。所以一个私有 CF 类型如果在本镜像里没有描述符（只出现在符号签名里），即使模块解析出来，也只能印成 `CoreSVG.CGSVGDocumentRef`，能读懂，但不是能编译的写法；加了 foreign 描述符闸门以后（提议方案第 3 条），这种引用不再认领模块，保持 `__C.CGSVGDocumentRef`。去掉 `Ref` 时还要避开重名：`IOSurfaceRef` 的描述符名字就是 `IOSurfaceRef`，因为 IOSurface 里已有同名的 Objective-C 类 `IOSurface`（`hasNamingConflict`）。
10. **顺带怀疑过、复现后没有出现**：曾推测第 6 条的去 `Ref` 规则不看重名，会把 `__C.IOSurfaceRef` 印成 `IOSurface.IOSurface`。在 Ultra 上对直接链接 IOSurface、用到 `IOSurfaceRef` 的 TextRecognition 跑 `interface --resolve-c-module-names`，改动前后都印成 `CoreGraphics.IOSurfaceRef`（9 处），名字没被改。模块落在 CoreGraphics，是因为 CoreGraphics 的头文件里也有一份 `IOSurfaceRef` 的 typedef；swiftc 6.4.2 探针确认 `CoreGraphics.IOSurfaceRef` 能编过。同一探针还确认 `IOSurface.IOSurfaceRef` 与 `IOSurface.IOSurface` 都编不过（模块名 `IOSurface` 被同名的 Objective-C 类遮住，报 `'IOSurfaceRef' is not a member type of class 'IOSurface.IOSurface'`），要写成模块选择器 `IOSurface::IOSurfaceRef`、`IOSurface::IOSurface`；`--module-selectors` 下 TextRecognition 印成 `CoreGraphics::IOSurfaceRef`。后者是打印器在「模块名与它里面的类型同名」时的通用问题，不属于本提案。

## 提议方案

1. **新增 `CFDeclaredTypeNames`**（`Sources/Output/SwiftTypeNameResolution/`），实现 `DeclaredTypeNameSource`，与 `ObjCDeclaredTypeNames` 同形：`init(machO:imagePath:)`，`declaredTypeNames()` 读 `machO.exportedSymbols`，每个名为 `_<名字>GetTypeID` 的导出给出 `<名字>Ref`；`<名字>` 以下划线开头的私有函数（`__LSASNGetTypeID`）同时给出去掉前导下划线的拼写（`LSASNRef`）。
2. **新增 `ImageDeclaredTypeNames`**（同一目录），也实现 `DeclaredTypeNameSource`：一个镜像的 `ObjCDeclaredTypeNames` 名字在前、`CFDeclaredTypeNames` 名字在后，合成一个来源。`TypeDatabase` 每个镜像路径只收第一个来源（调研第 5 条），把两种来源分开登记，后登记的那个永远读不到。
3. **provider 登记它们**：`setup()` 交给 `TypeDatabase.index(dependencies:moduleFilter:)` 的来源变成「根镜像的 `CFDeclaredTypeNames`，然后每个直接依赖一个 `ImageDeclaredTypeNames`」，取代原来每个依赖一个 `ObjCDeclaredTypeNames`。根镜像排第一，因为它自己定义的类型由它自己说了算；根镜像不进 `moduleFilter`，不触发 SourceKit 接口生成，它的 Objective-C 名字照旧不登记。来源的排列抽成一个内部静态函数。**`GetTypeID` 只负责定位，「是不是 CF 类型」由 foreign 描述符决定**：provider 先从根镜像收集 C 导入、从 C typedef 升格来的 class 描述符（ClangImporter 给 CF 类型生成的 foreign class）的 typedef 名，所有 CF 来源只给出这个集合里的名字。这样 `CFGetTypeID` 给出的 `CFRef` 这类非类型名字，以及恰好与某个导出同名的 `swift_wrapper` typedef，都不会被认领。
4. **打印器、swift-type-indexing、CLI 参数都不改**。效果全部经现有路径体现：`moduleName(forTypeName:)` 多答出一些名字，打印器按调研第 4 条的规则写成 `模块.描述符名`。`--resolve-c-module-names` 的帮助文字和 swift-section skill 的说明补一句来源。

### 非目标

- **跟着重新导出找子框架**（`LSASNRef` → CoreServices）：`ObjCDeclaredTypeNames` 同样不跟重新导出，两种来源应该一起做；MachOKitExtensions 3.3.0 的 `DependencyTraversal` 也只有 `direct` / `transitive`（`DependencyClosure.swift:6-11`）。另开提案。
- **间接依赖**（`CFPhoneNumberRef`）：放宽到传递闭包会让 SourceKit 接口生成回到几百个模块（调研第 7 条）。要做也应该只给运行时来源放宽、不动 `moduleFilter`，另开提案。
- **没有 `GetTypeID` 导出的类型**（`CFXGPUDeviceRef` 等 3 个），以及非 CF 的私有 C 类型（struct、enum、`swift_wrapper` typedef，如 `AGTreeElement`）：二进制里没有可靠的模块证据。
- **本镜像没有描述符的引用**：foreign 描述符闸门把它挡在外面，仍印 `__C.XRef`（调研第 9 条）。要在没有描述符时也给出模块和 Swift 名，就得让 TypeDatabase 的去 `Ref` 规则认运行时名表，会碰上重名与 `swift_name` 改名（见「替代方案」第 5 条）。
- **自己定义、却没导出 `GetTypeID` 的 CF 桥接类型**：foreign 描述符能证实它是 CF 类，但没有任何二进制证据说明它属于哪个模块（桥接到哪个类不进二进制），印描述符给的裸名。端到端测试里的 `ProbeLonelyRef` 钉住了这一点。
- **根镜像自己的 Objective-C 类**：现在也没登记，是另一个问题，本提案不顺手改，免得 ObjC 输出跟着变。
- **`dump`**：`dump` 不做 `__C` 模块解析，本提案不引入。
- **RuntimeViewer 接入**：本库发版后，把 `RuntimeSwiftSection.swift:2013` 的 `metadataSources` 里的 `ObjCDeclaredTypeNames` 换成 `ImageDeclaredTypeNames`，属于 RuntimeViewer 的改动。不能另加一个 `CFDeclaredTypeNames`：同一路径的第二个来源会被丢掉。
- **调研第 10 条的 `IOSurfaceRef` 疑似问题**：先复现，另行修复。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| `Sources/Output/SwiftTypeNameResolution/CFDeclaredTypeNames.swift` · `CFDeclaredTypeNames` | 新增 | `DeclaredTypeNameSource` 的实现：读导出表，`…GetTypeID` → typedef 名；内部静态函数 `typedefNames(forExportedSymbolName:)` 承载命名规则 | 私有 CF 类型的模块证据 | 1 |
| `Tests/SwiftTypeNameResolutionTests/CFDeclaredTypeNamesTests.swift` | 新增 | 现场编译的 C 动态库经 `MachOFile` 与 `MachOImage` 两种读法读出的名字（覆盖命名规则的各种写法）；本机 cache 的 CoreSVG | 规则与两种读法 | 1 |
| `Sources/Output/SwiftTypeNameResolution/ImageDeclaredTypeNames.swift` · `ImageDeclaredTypeNames` | 新增 | 一个镜像的 ObjC 名字与 CF 类型合成一个 `DeclaredTypeNameSource` | `TypeDatabase` 每个镜像路径只收一个来源 | 2 |
| `Tests/SwiftTypeNameResolutionTests/ImageDeclaredTypeNamesTests.swift` | 新增 | IOSurface 一个镜像里同时列出 ObjC 类 `IOSurface` 与 CF 类型 `IOSurfaceRef` | 合成来源两种名字都在 | 2 |
| `Sources/Output/SwiftTypeNameResolution/SwiftInterfaceBuilderTypeNameProvider.swift:81-113` · `setup()` | 修改 | 来源改为「根的 `CFDeclaredTypeNames`，然后每个依赖一个 `ImageDeclaredTypeNames`」；排列抽成 `static func declaredTypeNameSources(root:dependencies:)`（internal） | 登记新来源 | 2 |
| `Tests/SwiftTypeNameResolutionTests/PrivateCFTypeModuleTests.swift` | 新增 | 用现场编译的 C 库与 Swift 库验证接口里的拼写：依赖定义的、根镜像定义的、不挂 provider 时的 | 端到端证明 | 2 |
| `Sources/Executables/swift-section/Commands/InterfaceCommand.swift:33` · `resolveCModuleNames` 的 `help` | 修改 | 来源列表补上「依赖导出的 `…GetTypeID`（CF 类型）」 | `--help` 就是文档 | 3 |
| `AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md` 第 8 节 | 修改 | 「没有 sourcekitd 时由 API notes 与 Objective-C 元数据归属」补上导出的 `GetTypeID`；加一句私有 CF 类型的效果与第 9 条的 `XRef` 退路 | CLI 行为变了，skill 同批更新 | 3 |
| `CLAUDE.md` · SwiftTypeNameResolution 一条 | 修改 | 列出 `CFDeclaredTypeNames` 与 `ImageDeclaredTypeNames` | 模块清单与代码同步 | 3 |
| `Documentations/Evolutions/README.md`、`Documentations/README.md` | 修改 | 登记本提案；落地时改编号与状态 | 文档索引 | 0、3 |
| `Documentations/Internal/ProjectEvolutionLog.md` | 修改 | 落地时追加一节 | 演进账本 | 3 |

## 架构图

改了什么：

```text
SwiftTypeNameResolution/
+ CFDeclaredTypeNames<MachO: MachORepresentable & Sendable>      DeclaredTypeNameSource
+     declaredTypeNames()   machO.exportedSymbols: _<Name>GetTypeID -> "<Name>Ref"
+ ImageDeclaredTypeNames<MachO: ObjCMetadataSource>              DeclaredTypeNameSource, one per image
+     declaredTypeNames()   ObjCDeclaredTypeNames names + CFDeclaredTypeNames names
~ SwiftInterfaceBuilderTypeNameProvider.setup()
+     cfTypedefNames(referencedBy: root)   root's foreign class descriptors -> the CF typedef names it uses
+                                          every CF source below gives only these names
~     TypeDatabase.index(dependencies:
+         [CFDeclaredTypeNames(root),
-          ObjCDeclaredTypeNames(dependency1),
+          ImageDeclaredTypeNames(dependency1),
-          ObjCDeclaredTypeNames(dependency2),
+          ImageDeclaredTypeNames(dependency2), ...],
          moduleFilter: dependency module names)                  unchanged: root never generates an interface

swift-type-indexing 0.2.0 (unchanged)
  TypeDatabase.register(dependencies:)    keeps the first source per image path
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
│           ├─ ImageDeclaredTypeNames(AttributeGraph)               miss    (~ was ObjC only)
│           ├─ ...
│           └─ ImageDeclaredTypeNames(CoreSVG): "CGSVGDocumentRef"  -> "CoreSVG"   (~)
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
/// `__C` — while the framework defining it exports the type's `GetTypeID` function. This
/// attributes a private CF type such as `CGSVGDocumentRef` to the image exporting
/// `CGSVGDocumentGetTypeID` (`CoreSVG`). `TypeDatabase` consults it only for names neither the
/// SDK's module interfaces nor its API notes attribute, and reads the image's exports only on
/// such a miss.
///
/// `TypeDatabase` keeps one source per image path, so an image whose Objective-C names are
/// registered too goes in as one `ImageDeclaredTypeNames`, which reads both; this alone is for
/// an image read for its CF types only.
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

/// Every type an image declares, as one swift-type-indexing source: the classes, protocols,
/// structs and unions its Objective-C metadata names (`ObjCDeclaredTypeNames`), then the CF
/// types it exports a `GetTypeID` function for (`CFDeclaredTypeNames`).
public struct ImageDeclaredTypeNames<MachO: ObjCMetadataSource>: DeclaredTypeNameSource {
    public let imagePath: String

    public init(machO: MachO, imagePath: String)

    /// The Objective-C names, then the CF typedef names. Throws when the Objective-C metadata
    /// cannot be read, as `ObjCDeclaredTypeNames` does on its own: `TypeDatabase` then logs
    /// the image and skips it whole.
    public func declaredTypeNames() async throws -> [String]
}

#endif
```

`ImageDeclaredTypeNames` 只要 `ObjCMetadataSource` 一个约束：它经 `MachORepresentableWithCache` 继承 `MachORepresentable` 与 `Sendable`，正好满足两种来源。Objective-C 元数据读不出来时整个来源抛错，与只登记 `ObjCDeclaredTypeNames` 时一样，由 `TypeDatabase` 记日志并跳过这个镜像；不为保住 CF 名字而吞掉这个错误。

形状照 `ObjCDeclaredTypeNames<MachO: ObjCMetadataSource & Sendable>` 抄：同样的 `init(machO:imagePath:)`、同样的 `imagePath` 属性、同样放在 `#if os(macOS)` 里，名字按「来源 + `DeclaredTypeNames`」对称。泛型约束只要 `MachORepresentable & Sendable`：`exportedSymbols` 是 MachOKit `MachORepresentable` 的要求（`Sources/MachOKit/Protocol/MachORepresentable.swift:124-129`），`MachOFile`、`MachOImage` 和包装类型都有，不需要判断读取器种类。provider 的 `MachO` 约束经 `MachOSwiftSectionRepresentableWithCache: MachORepresentableWithCache: MachORepresentable, Sendable` 满足它。协议要求是 `async throws`，实现不会失败，所以写成不抛错的 `async`。

### 命名规则

1. 导出名必须以一个 `_` 开头（C 符号的 Mach-O 前缀），去掉它得到 C 函数名；Swift 符号（`_$s…`）和 Objective-C 符号（`_OBJC_…`）因为不以 `GetTypeID` 结尾自然落选。
2. C 函数名以 `GetTypeID` 结尾，去掉后缀的部分非空、由字母数字和下划线组成、不以数字开头，记为 `base`。
3. 给出 `base + "Ref"`；`base` 以下划线开头时，再给出去掉全部前导下划线后的 `+ "Ref"`（非空才给）。
4. 规则本身会产生一些不是类型的名字，例如 `CFGetTypeID` 给出 `CFRef`。provider 登记的来源都带 foreign 描述符闸门（下一节），只给出根镜像证实是 CF 类的名字；公开的 `init(machO:imagePath:)` 不带闸门，给需要全部名字的调用方（RuntimeViewer 那种为整个进程登记镜像、没有单一根镜像的场合）。

### 来源的排列

```swift
extension SwiftInterfaceBuilderTypeNameProvider {
    /// The declared-type-name sources `setup()` registers, in the order `TypeDatabase` folds
    /// them: the root's CF types first — a type the root defines is its own — then each direct
    /// dependency's Objective-C names and CF types, one `ImageDeclaredTypeNames` per image, in
    /// dependency order.
    static func declaredTypeNameSources(root: MachO, dependencies: [MachO]) -> [any DeclaredTypeNameSource]

    /// The typedef names of the CF types `image`'s Swift metadata refers to: its C-imported
    /// class descriptors promoted from a C typedef — the foreign class ClangImporter makes of a
    /// CF type. Named by the ABI name, or by the descriptor's own name when ClangImporter kept
    /// the C spelling (`IOSurfaceRef`).
    static func cfTypedefNames(referencedBy image: MachO) -> Set<String>
}

extension CFDeclaredTypeNames {
    /// A source giving only the names in `admittedTypedefNames`.
    init(machO: MachO, imagePath: String, restrictedTo admittedTypedefNames: Set<String>?)
}

extension ImageDeclaredTypeNames {
    /// A source whose CF part gives only the names in `admittedTypedefNames`.
    init(machO: MachO, imagePath: String, restrictingCFTypesTo admittedTypedefNames: Set<String>?)
}
```

`setup()` 只把 `dependencies:` 参数换成这个函数的结果，`moduleFilter` 不变。带闸门的两个构造器是 internal：闸门的集合取决于一个根镜像，只有 provider 这种「为一个根镜像登记依赖」的调用方有它；公开接口因此不变。判定只看描述符：种类是 class、`isCImportedContextDescriptor` 为真、import info 的 `isCTypedef` 为真且不是相关实体。只有 CF 类型会被升格成 class 而又来自 C typedef（`swift_wrapper` 给的是 struct / enum，C++ 的 foreign reference type 来自 tag namespace），所以这四条合起来就是「ClangImporter 给 CF 类型生成的 foreign class」。

### 性能

`TypeDatabase` 只在一个名字查不到时才按顺序读下一个来源，读过的来源不再读。根镜像排第一，所以第一次未命中就会读一遍根镜像的导出表：SwiftUICore 这样的大镜像有数十万个导出，`exportedSymbols` 要建一个同样大的数组。第 3 步在 Ultra 上量了 `interface --resolve-c-module-names` 的耗时：SwiftUICore 热缓存下 17.22 → 17.28 秒，测不出差别，所以不改成直接遍历导出 trie。

## 替代方案考量

1. **在打印器上新注册一个 `ModuleNameResolving` 解析器**（讨论时最先选的方向，仍在本仓库）：否。swift-type-indexing 已经有 `DeclaredTypeNameSource` 这个注册表，「SDK 优先、按依赖顺序折叠、第一个声明者胜出、镜像路径换模块名」都在那里。另写一个解析器要么把这些规则抄一遍，要么和 `TypeDatabase` 对同一个名字给出不同答案，谁胜出取决于注册顺序。RuntimeViewer 也是经 `DeclaredTypeNameSource` 接入的，走同一个接口它只需加一行。
2. **让 swift-type-indexing 自己读导出表**：否。那个包按设计不读 Mach-O（`DeclaredTypeNameSource.swift` 的文档），读二进制的部分都由实现方提供。
3. **从 CF 运行时类注册取类型名**（`_CFRuntimeRegisterClass` 的 `CFRuntimeClass.className`）：否。要反汇编调用点才能找到参数，得到的仍然只是「哪个镜像定义了它」，和导出表等价；而且 `className` 是 `"CGSVGDocument"` 这样的显示名，不是 mangling 用的 typedef 名。
4. **用一致性符号里的模块**（`_$sSo10AGGraphRefaSQ14AttributeGraphMc`）：否。那是声明这条一致性的模块，不是类型的模块；合成的一致性在 `__C_Synthesized`；cache 里的这类本地符号大多被剥掉了。
5. **让 TypeDatabase 的去 `Ref` 规则也认运行时名表**，好在没有描述符时也给出 Swift 名：否。它不知道重名，会把 `IOSurfaceRef` 改成 `IOSurface`（调研第 9 条）；而打印器先问解析器、后用描述符，它还会把 `swift_name` 改过的 `AGGraphRef` 从 `Graph` 改坏成 `AGGraph`。
6. **跟着 `LC_REEXPORT_DYLIB` 把子框架的导出算进伞框架**：推迟，见「非目标」第一条。
7. **让 swift-type-indexing 允许一个镜像路径登记多个来源**（不合成 `ImageDeclaredTypeNames`）：否。「一个来源代表一个镜像」是那个包按镜像路径去重时的模型，改它要动 swift-type-indexing 并发版，而本提案定下不改那个包；在本仓库合成一个来源就够了。

## 影响

### 源码兼容性（source compatibility）

纯新增：多两个公开类型 `CFDeclaredTypeNames` 与 `ImageDeclaredTypeNames`，`SwiftInterfaceBuilderTypeNameProvider` 的公开接口不变。行为上，`--resolve-c-module-names` 下原本没有模块的私有 CF 类型会带上模块。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：`SwiftSectionKit` 的 `InterfaceRequest` 经 provider 自动受益，不用改代码。没有基线或快照测试开着 `__C` 模块解析（它要 SDK），渲染 A/B 校验不受影响。
- RuntimeViewer：它不经 provider，自己在 `RuntimeSwiftSection.swift:2013` 登记来源，本提案落地不改变它的输出。要受益，等本库发版后把那里的 `ObjCDeclaredTypeNames` 换成 `ImageDeclaredTypeNames`（见「非目标」）。
- MachOKitUI、SymbolViewer：不用 `SwiftTypeNameResolution`，不受影响。

### 文档与示例

`swift-section interface --help` 里 `--resolve-c-module-names` 的说明、swift-section skill 第 8 节、`CLAUDE.md` 的模块清单，都在第 3 步同批更新。

## API 演进与废弃策略

- 没有被替代的旧 API，不需要废弃期。
- 纯新增，按 minor 版本发布。

## 落地步骤

0. **提案落盘、登记索引**（本次）—— 改动地图最后两行中的索引部分
1. ✅ **`CFDeclaredTypeNames` 与它的测试** —— 改动地图第 1、2 行（`Tests/SwiftTypeNameResolutionTests/CFDeclaredTypeNamesTests.swift`；Ultra，Xcode 26.6，3 个测试通过）
   - 行为：`fileNamesTheTypedefOfEveryExportedTypeIDFunction`（`FixtureCompiler` 现场编译的 C 库导出 `ProbeWidgetGetTypeID`、`_ProbeSecretGetTypeID`、`ProbeWidgetCreate`、`GetTypeID`、`__GetTypeID`，经 `MachOFile` 读出的名字恰好是 `ProbeWidgetRef`、`_ProbeSecretRef`、`ProbeSecretRef`）
   - 行为：`loadedImageNamesTheSameTypedefs`（同一个库 `dlopen` 后经 `MachOImage` 读出同样的名字）
   - 行为：`coreSVGDeclaresItsPrivateDocumentType`（本机 cache 里的 CoreSVG，文件与进程内两种读法都给出 `CGSVGDocumentRef`）
2. ✅ **合成来源、provider 登记新来源，端到端验证** —— 改动地图第 3–6 行（`ImageDeclaredTypeNamesTests.swift`、`PrivateCFTypeModuleTests.swift`；Ultra，Xcode 26.6，`SwiftTypeNameResolutionTests` 13 个测试通过。`aPrivateCFTypePrintsUnderTheImageExportingItsTypeID` 在合成来源之前是红的，见决策日志）
   - 行为：`listsTheObjectiveCClassAndTheCFTypeOfOneImage`（本机 cache 的 IOSurface 一个来源里同时有 ObjC 类 `IOSurface` 与 CF 类型 `IOSurfaceRef`）
   - 夹具：C 库 `ProbeCF` 导出 `ProbeWidgetGetTypeID`；Swift 库 `ProbeKit` 用桥接头声明两个 `CF_BRIDGED_TYPE(id)` 的 typedef，链接 `ProbeCF`，并用 `@_cdecl` 自己导出 `ProbeGadgetGetTypeID`。`FixtureCompiler` 把 install name 固定成 `@rpath/lib<名字>.dylib`，所以模块名是 `libProbeCF`、`libProbeKit`
   - 行为：`aPrivateCFTypePrintsUnderTheImageExportingItsTypeID`（字段类型印成 `libProbeCF.ProbeWidget`）
   - 行为：`aCFTypeTheRootDefinesPrintsUnderTheRootsModule`（根镜像自己定义的印成 `libProbeKit.ProbeGadget`）
   - 行为：`aBridgedTypeWithoutATypeIDFunctionKeepsItsBareSwiftName`（`ProbeLonelyRef` 只有 `CF_BRIDGED_TYPE(id)`、没有任何镜像导出它的 `GetTypeID`，印裸名 `ProbeLonely`）
   - 行为：`aGetTypeIDExportDoesNotClaimATypedefThatIsNoCFClass`（`ProbeCF` 导出 `ProbeDecoyGetTypeID`，`ProbeKit` 的 `ProbeDecoyRef` 却是 `swift_wrapper` 结构体，不被印成 `libProbeCF.ProbeDecoyRef`；加 foreign 描述符闸门之前它是红的）
   - 行为：`withoutTheProviderAPrivateCFTypeKeepsItsBareSwiftName`（不挂 provider 时仍是 0106 的 `ProbeWidget`）
3. ✅ **文档与系统镜像验证** —— 改动地图第 7–11 行
   - 在 Ultra（macOS 27.2 26B131，Xcode 26.6 release 构建）上，对本机 cache 的四个镜像各跑一遍 `interface --resolve-c-module-names`，改动前用第 1 步那个提交（provider 还没改）编出的 `swift-section`，改动后用最终提交编出的：

     | 镜像 | 改动前后不同的行 | 新增的模块限定（出现次数） | 改动后耗时 |
     |---|---|---|---|
     | SwiftUICore | 300 | `AttributeGraph.Subgraph` 134、`AttributeGraph.Graph` 13、`CoreSVG.CGSVGDocument` 7 | 17.28 秒（改动前热缓存 17.22 秒） |
     | AppKit | 16 | `CoreGraphics.CGColorTransform` 4、`CoreGraphics.CGContextDelegate` 3、`CoreGraphics.CGDisplayList` 1 | 8.17 秒 |
     | RealityIO | 976 | `CoreRealityIO.RIOPxrUsdObject`、`RIOPxrVtValue`、`RIOBuilder…` 等二十多种 | 2.24 秒 |
     | TextRecognition | 0 | 无（只用公开的 CF 类型） | 2.62 秒 |

   - 所有变化都是原本没有模块的私有 CF 类型带上了定义它的模块，没有归错的；实际覆盖比「动机」里按一致性表估计的多（AppKit 的 `CGDisplayList`、RealityIO 的 `RIOBuilder…` 一批不在那张表里，它们有描述符但没有一致性记录）。加 foreign 描述符闸门前后，这四个镜像的输出逐字节相同。耗时看 SwiftUICore 的热缓存对比，没有可测出的变化，所以「性能」一节说的「改成遍历导出 trie」不做
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
| 2026-11-25 | 测试都放在公开 seam 上 | 命名规则不单独测内部静态函数，改由现场编译的 C 库的导出覆盖各种写法；来源顺序不单独测内部函数，改由端到端测试证明根镜像与依赖各自归属。`declaredTypeNameSources(root:dependencies:)` 仍按设计抽成内部静态函数。 |
| 2026-11-25 | 新增 `ImageDeclaredTypeNames`，一个依赖只登记一个来源 | 偏离原方案。端到端测试发现依赖定义的私有 CF 类型仍印裸名：`TypeDatabase.register(dependencies:)` 按镜像路径去重，同一依赖先登记的 `ObjCDeclaredTypeNames` 占了位置，随后的 `CFDeclaredTypeNames` 被丢掉；根镜像只有一个来源，所以那条通过了。改为每个依赖登记一个合成两种名字的 `ImageDeclaredTypeNames`，方案方向不变，多一个纯新增的公开类型；RuntimeViewer 的后续接入也要用它。 |
| 2026-11-25 | 加 foreign 描述符闸门 | 用户指出判断「是不是 CF 类型」要靠 foreign metadata 才可靠。改为：`GetTypeID` 只负责定位，provider 先从根镜像的 foreign class 描述符（C 导入、从 C typedef 升格来的 class）收集 CF typedef 名，CF 来源只给出这些名字。诱饵测试 `aGetTypeIDExportDoesNotClaimATypedefThatIsNoCFClass` 加闸前红、加闸后绿。代价是本镜像没有描述符的引用不再认领模块，保持 `__C.XRef`（原来会印成不能编译的 `模块.XRef`）。带闸门的构造器是 internal，公开接口不变。 |
| 2026-11-25 | 自己定义、不导出 `GetTypeID` 的 CF 桥接类型印裸名 | 应用户要求实测：`ProbeLonelyRef` 只有 `CF_BRIDGED_TYPE(id)`，foreign 描述符证实它是 CF 类，但没有模块证据，印 `ProbeLonely`。写成测试钉住，列入非目标。 |
| 2026-11-25 | `IOSurfaceRef` 疑似问题未复现 | TextRecognition 改动前后都印 `CoreGraphics.IOSurfaceRef`，能编过；没有被改成 `IOSurface`。复现中确认的另一件事——`IOSurface.IOSurfaceRef` / `IOSurface.IOSurface` 因模块名被同名类遮住而编不过、要用 `IOSurface::…`——是打印器的通用拼写问题，记为后续项。 |
| 2026-11-25 | 不改成遍历导出 trie | 第 3 步实测 SwiftUICore 热缓存下耗时 17.22 → 17.28 秒，`exportedSymbols` 的开销测不出来。 |
