# Draft - 被 SDK 搬过家的 Swift 类型，按现在声明它的模块打印

- **状态**: Accepted
- **作者**: JH
- **创建日期**: 2026-11-25
- **最后更新**: 2026-11-25
- **所属愿景**: 无
- **关联提案**: [0105 swift-type-indexing-package](0105-swift-type-indexing-package.md)（`TypeDatabase` 搬进独立包，本提案给它加一类数据）；[0106 c-imported-type-name-spelling](0106-c-imported-type-name-spelling.md)（`__C` 类型按 SDK 拼写，本提案把同样的思路推到原生 Swift 类型）；[0082 image-group-evolution](0082-image-group-evolution.md)（evolution 把 SwiftUI 与 SwiftUICore 当一组比较，同样源于 `@_originallyDefinedIn`）；[0064 module-selectors](0064-module-selectors.md)（`Module::Name` 写法）
- **实现分支 / PR**: 两个仓库都是 `feature/moved-swift-type-modules`（worktree `.worktrees/MachOSwiftSection-MovedSwiftTypeModules`、swift-type-indexing 的 `.worktrees/swift-type-indexing-MovedSwiftTypeModules`）
- **配套文档**: 待定 —— 落地时登记实现说明 / 使用指南的链接
- **网页版**: 同目录同名的 `.html`
- **涉及仓库**: swift-type-indexing（从 SDK 读出搬家记录、提供查询）、MachOSwiftSection（本仓库：打印器、`SwiftTypeNameResolution` 适配层、`SwiftSectionKit` 请求、`swift-section interface` 开关）。这是跨仓库的唯一提案，swift-type-indexing 的提案索引在实现时登记为 cross-repository draft

## 摘要

Apple 把一些 Swift 类型从一个模块搬进另一个模块时，会给声明加上 `@_originallyDefinedIn(module: "旧模块", 平台 版本)`。这个属性让 mangled name 和运行时元数据继续使用旧模块名，老二进制不用重编，所以二进制里只能读到旧名字：`CGFloat` 现在由 CoreFoundation 声明，mangling 却还是 `$s12CoreGraphics7CGFloatV`；macOS 15 起 SwiftUI 的约 370 个类型搬进了 SwiftUICore，mangling 还是 `7SwiftUI`。`swift-section interface` 因此印出 `CoreGraphics.CGFloat`、`SwiftUI.View`，而 SDK 的 `.swiftinterface` 写的是 `CoreFoundation::CGFloat`（CoreGraphics 的接口）、`SwiftUICore.View`（SwiftUI 的接口，2182 处）。

本提案做两件事：

- **swift-type-indexing** 在 `TypeDatabase` 第一次 `index` 时顺带扫描 SDK 里所有模块的文本 `.swiftinterface`，把每个顶层类型声明上的 `@_originallyDefinedIn` 记成「旧模块 + 类型名 → 现在声明它的模块，以及各平台的搬家版本」。新增一个查询 `declaringModuleName(ofMovedTypeNamed:originallyDefinedIn:builtAgainst:)`。扫描只读文本，不用 sourcekitd。
- **MachOSwiftSection** 的打印器多一个解析器角色 `MovedTypeModuleResolving`。注册了它，原生 Swift 类型的模块名就先问它（`CoreGraphics.CGFloat` → `CoreFoundation.CGFloat`，嵌套类型跟随最外层类型）。`swift-section interface` 新增开关 `--resolve-moved-type-modules`，默认关闭。

是否改写按二进制自己的 SDK 版本判断（`LC_BUILD_VERSION` 的 `sdk`）：用 macOS 14 SDK 编出的 SwiftUI 镜像，`View` 那时还在 SwiftUI 里，照旧印 `SwiftUI.View`。

## 动机

**现象**（本机 macOS 27.2，Xcode 27.2 的 MacOSX27.2 SDK）：

- SDK 的 `usr/lib/swift/CoreFoundation.swiftmodule/arm64e-apple-macos.swiftinterface` 第 10–16 行：

  ```swift
  @available(macOS 10.0, macCatalyst 13.0, iOS 2.0, watchOS 1.0, tvOS 9.0, *)
  @_originallyDefinedIn(module: "CoreGraphics", macOS 10.0)
  @_originallyDefinedIn(module: "CoreGraphics", macCatalyst 13.0)
  @_originallyDefinedIn(module: "CoreGraphics", iOS 2.0)
  @_originallyDefinedIn(module: "CoreGraphics", watchOS 1.0)
  @_originallyDefinedIn(module: "CoreGraphics", tvOS 9.0)
  @frozen public struct CGFloat : Swift::Sendable {
  ```

  CoreGraphics 自己的接口里引用它时写的是 `CoreFoundation::CGFloat`（例如 `public func CGContextMoveToPoint(_ c: CoreGraphics::CGContext?, _ x: CoreFoundation::CGFloat, _ y: CoreFoundation::CGFloat)`）。
- 二进制里：运行时 `libswiftCoreFoundation.dylib` 导出 `_$s12CoreGraphics7CGFloatVMn`（类型描述符）与 `_$s12CoreGraphics7CGFloatVN`（类型元数据），模块名仍是 CoreGraphics。
- 因此任何引用 `CGFloat` 的二进制，`swift-section interface` 都印 `CoreGraphics.CGFloat`；SwiftUI 相关的二进制满屏是 `SwiftUI.View`、`SwiftUI.Text`，而 SDK 和 Xcode 的生成接口写的是 SwiftUICore。

用户在对照 SDK 阅读输出时会困惑「这个类型到底声明在哪」。现在的输出能编译过（见前期调研 6），所以问题出在跟 SDK 不一致：它照实反映了 ABI，却和源码对不上。已有的 `--resolve-c-module-names` 只处理 `__C` 类型（前期调研 3），管不到这类原生 Swift 类型。

**范围不只 CGFloat**（前期调研 5）：macOS 27.2 SDK 里带 `@_originallyDefinedIn` 的模块有 SwiftUICore（旧模块 SwiftUI，约 370 个类型）、RealityFoundation（RealityKit）、CoreFoundation（CoreGraphics）、AVFAudio（AVFoundation）、RelevanceKit（AppIntents）、DeveloperToolsSupport 与 CoreTransferable（SwiftUI）、Foundation（`_System_Foundation`）等。一张表就能把它们全部修好。

## 前期调研

1. **编译器怎么用这个属性**（`/Volumes/SwiftProjects/swift-project/swift`）：
   - `include/swift/AST/Attr.h:2486` 的 `OriginallyDefinedInAttr` 存两个模块名：`ManglingModuleName`（mangling 用）与 `LinkerModuleName`（链接指令用）。源码里写成 `"Swift;CompatibilitySpan"` 时，分号前是 mangling 用的模块，分号后是链接用的库。
   - `lib/AST/Decl.cpp:1155` 的 `Decl::getAlternateModuleName()`：声明自己带有在当前平台生效的属性就用它的 `ManglingModuleName`，否则沿 `DeclContext` 往上找，所以**嵌套类型跟随外层类型的旧模块名**。`lib/AST/ASTMangler.cpp:205/970/2642/4484` 都经它取模块名。
   - 生效与否只看平台、**不看版本**：`lib/AST/Attr.cpp:2561` 的 `isActivePlatform` 只调 `isPlatformActive`。所以同一平台上，任何部署目标编出的 mangling 都用旧模块名；版本只影响链接指令（`$ld$previous`）。
   - 平台继承（`lib/AST/PlatformKindUtils.cpp:131`）：`iOS` 条目在 Mac Catalyst（`ios-macabi` 三元组也是 iOS）和 visionOS（编译期）上同样生效；`macCatalyst` 条目只对 Catalyst 生效。
2. **SDK 里的搬家记录**：
   - `$ld$previous` 记录了运行时位置的变化：`libswiftCoreFoundation.tbd` 有 `$ld$previous$/usr/lib/swift/libswiftCoreGraphics.dylib$$1$10.15$13.0$_$s12CoreGraphics7CGFloatVMn$`，即部署目标在 macOS 10.15–13.0 之间时，这个符号链接到 `libswiftCoreGraphics.dylib`；Catalyst 是 13.0–16.0。现在的 `libswiftCoreGraphics.tbd` 只重新导出 CoreGraphics.framework。**属性写的是 macOS 10.0，运行时真正搬家是 macOS 13**：属性的版本不一定等于源码搬家的时间，见「已知偏差」。
   - SwiftUICore 的版本分布（`grep -o '^@_originallyDefinedIn(module: "SwiftUI", …)'`）：macOS 15.0 共 1442 行，另有 15.2、26.0、27.0 等批次。**同一模块里不同声明的搬家版本不同**，表里必须逐个声明存版本。
   - `@_originallyDefinedIn` 只出现在顶层声明上，并且总是单独占一行、从第 0 列开始。SwiftUICore 里跟在它后面的声明：266 个 struct、23 个 class、33 个 enum、40 个 protocol、5 个 typealias，另有 994 个 extension、17 个 func、185 个 var、16 个 let。
3. **现状代码怎么走**：
   - 打印器只在模块名是 `__C` / `__ObjC` 时才去问解析器：`Sources/Output/SwiftPrinting/NodePrintables/NodePrintable.swift:186` 的 `resolvedModuleName(of:siblingIdentifier:)`。它是全部模块名输出的唯一出口，有三个调用点：`NodePrintable.swift:176`（`printModule`）、`TypeNodePrintable.swift:197`（顶层类型的限定名，`siblingIdentifier` 是该顶层类型的标识符）、`TypeNodePrintable.swift:310`（`printModuleSelector(ofNestedType:)`，嵌套类型自己的模块选择器，`siblingIdentifier` 是嵌套类型自己的标识符）。
   - 嵌套类型的模块选择器取自 `TypeNodePrintable.swift:635` 的 `declaringModuleForModuleSelector`：沿上下文链找到根上的 `module` 节点，或最近一层 `extension` 的模块。
   - 解析器角色协议在 `Sources/Output/SwiftPrinting/NodePrintables/TypeNameResolving.swift`（`ModuleNameResolving`、`CImportedNameResolving`、`OpaqueTypeResolving`，刻意不给默认实现）；注册在 `SwiftDeclarationPrinter.swift:240` 的 `addTypeNameResolver(_:)`，按角色分发在 `SwiftDeclarationPrinter.swift:1296` 起的 `NodePrintableDelegate` 实现里。
   - 适配层：`Sources/Output/SwiftTypeNameResolution/TypeDatabaseTypeNameResolver.swift`（无状态，包一个 `TypeDatabase`）与 `SwiftInterfaceBuilderTypeNameProvider.swift`（extra-data provider，`init?` 从 `machO.loadCommands.buildVersionCommand` 取平台，`setup()` 按依赖过滤索引）。
   - `SwiftSectionKit` 的 `InterfaceRequest`（`Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift:224`）只在 `cModuleNameResolution == .enabled` 时挂上 provider；`dump`、`diff`、`snapshot`、`evolution` 都不挂任何类型名解析器。
   - interface 头部的 `import` 行来自符号里出现的 mangling 模块名（`SwiftInterfaceBuilder.swift:357` 的 `collectModules()`），本提案不改它。
4. **swift-type-indexing 的现状**（`../swift-type-indexing`，0.1.1）：`TypeDatabase` 只回答 `__C` 类型的归属（`moduleName(forTypeName:)`）与 C 名 → Swift 名（`swiftName(forCName:category:)`）。模块接口一层经 sourcekitd `editor.open.interface` 生成，`InterfaceDeclarationNode` 只留种类、名字与嵌套，不留属性；`Documentations/Internal/TypeIndexingPipeline.md` 明确说不读文本 `.swiftinterface`，因为它只含 Swift 声明，而那一层要的是 ObjC 导入类型。本提案要的恰好是 Swift 声明。`SDKIndexer.discover` 已经列出每个 `.swiftmodule` 目录（`SwiftModuleDescriptor.path`）。第一次 `index` 在 `discoverSDK()` 里登记 API notes；只要 ObjC 标注的调用方用一个不选任何模块的 `moduleFilter` 调一次 `index`，这个用法已有先例。
5. **成本**：macOS 27.2 SDK 有 368 个 `.swiftmodule`，`arm64e-apple-macos.swiftinterface` 共 266 份（另有 `arm64e.x1-apple-macos` 12 份、`x86_64` 与 `ios-macabi` 各一套）。`grep -A12 '^@_originallyDefinedIn'` 扫完全部 macOS 份用时 0.38 秒。Swift 逐行解析会慢一些，落地时实测并记入本节。
6. **现在的输出能编过**：SE-0491（模块选择器）第 421 行规定 `Module::Name` 的候选包括「声明在该模块或被该模块重新导出的」声明；点号限定的写法同样会查到重新导出的声明。CoreGraphics 的接口头部有 `@_exported public import CoreFoundation`，SwiftUI 的接口第 19 行有 `@_exported import SwiftUICore`，所以 `CoreGraphics.CGFloat`、`SwiftUI.View` 都合法。本提案改的只是写法与 SDK 是否一致，不是正确性。
7. **使用方**：RuntimeViewer 按平台共用一个 `TypeDatabase`，经 `TypeDatabaseTypeNameResolver(typeDatabase:)` 注册（`RuntimeViewerCore/Sources/RuntimeViewerCore/TypeNames/RuntimeTypeIndex.swift:145`）。本提案不改这个类型的行为，RuntimeViewer 的输出不会因为升级而悄悄改变。

## 提议方案

### swift-type-indexing

1. 新增内部类型 `MovedTypeIndex`：输入一份 `.swiftinterface` 的文本和它所属的模块名，逐行扫描第 0 列的属性组。遇到 `@_originallyDefinedIn(module: "<名>", <平台> <版本>)` 就收集；属性组之后的第一行声明是 `struct` / `class` / `enum` / `protocol` / `actor` / `typealias`（前面可以有 `public`、`final`、`@frozen` 之类的修饰）时，记一条 `MovedTypeDeclaration`（类型名、mangling 旧模块、按平台的搬家版本）。是 extension、func、var 之类的就丢掉这组属性。模块名有分号时取分号前的部分；取出来等于本模块（例如 `Swift;CompatibilitySpan` 在 Swift 模块里）就不记。
2. `TypeDatabase.discoverSDK()` 在登记 API notes 之后，对发现的每个模块挑一份与平台匹配的文本接口（选法见详细设计）交给 `MovedTypeIndex`，结果并进一张 `[MovedTypeKey: MovedTypeDeclaration]` 表，键是「旧模块 + 类型名」。同一个键在两个模块里都出现时，按发现顺序先到先得，并记一条日志。
3. 新增公开查询：

   ```swift
   public func declaringModuleName(ofMovedTypeNamed typeName: String, originallyDefinedIn originalModuleName: String, builtAgainst sdkVersion: OperatingSystemVersion) -> String?
   ```

   当 SDK 把 `originalModuleName.typeName` 搬进了另一个模块、并且搬家版本不晚于 `sdkVersion`（数据库自身平台的版本）时，返回现在声明它的模块，否则返回 `nil`。

### MachOSwiftSection

4. `SwiftPrinting` 新增角色协议 `MovedTypeModuleResolving`。`resolvedModuleName(of:siblingIdentifier:)` 在模块不是 `__C` / `__ObjC`、标识符不为空时问它；问到就印新模块，`isResolvedCImportedModule` 仍是 `false`，不触发 C 名改写。
5. 嵌套类型的模块选择器（`printModuleSelector(ofNestedType:)`）改为按「它所在的顶层声明」查：模块节点来自上下文链的根时，键用最外层类型的标识符，`SwiftUI::Text.SwiftUI::Storage` 就整体变成 `SwiftUICore::Text.SwiftUICore::Storage`；来自某个 `extension` 时不查（非目标）。
6. `SwiftTypeNameResolution` 新增 `TypeDatabaseMovedTypeModuleResolver`（`typeDatabase` + `sdkVersion`）。`SwiftInterfaceBuilderTypeNameProvider` 增加一个 `resolutions` 参数（选项集合：`.cImportedModules`、`.movedTypeModules`，默认只有前者，与现在一致）；它从 `LC_BUILD_VERSION` 取 `sdk` 版本，开了 `.movedTypeModules` 就同时遵循新角色。只开 `.movedTypeModules` 时，`setup()` 用不选任何模块的 `moduleFilter` 调一次 `index`：不生成任何模块接口，不需要 sourcekitd。
7. `InterfaceRequest` 新增 `resolvesMovedTypeModules: Bool = false`；`swift-section interface` 新增 `--resolve-moved-type-modules`。两个开关可以同时开，共用一个 provider 和一个数据库。

### 非目标

- **`dump`**：`dump` 按 mangled 身份打印，从不读 SDK，`__C` 类型在 dump 里也不解析（0106 前期调研 1）。搬家记录来自 SDK 而不是二进制，同样不进 dump。
- **`diff`、`snapshot`、`evolution` 与一切查找键**：它们按 mangled 名比较，必须保持旧模块名。0082 已经用 image 分组处理了 SwiftUI → SwiftUICore 的搬家。
- **interface 头部的 `import` 行**：旧模块总会重新导出新模块（例如 CoreGraphics 重新导出 CoreFoundation），`import CoreGraphics` 足以让 `CoreFoundation.CGFloat` 编过，不补 `import CoreFoundation`。
- **声明在搬过家的 extension 里的嵌套类型**：SwiftUICore 有 994 个带 `@_originallyDefinedIn` 的 extension，声明在其中的嵌套类型，它自己的模块选择器仍印旧模块。这种情况很少，而且照样能编过。
- **函数、全局变量与 extension 成员的搬家**：interface 引用它们时不带模块名。
- **默认开启**：输出会随宿主机的 SDK 变化，同一份二进制在两台机器上印得不一样，渲染 A/B 与快照测试也会跟着漂移。
- **RuntimeViewer 接入**：留给 RuntimeViewer 自己的后续改动，它要为每个镜像传入正确的 SDK 版本。

## 改动地图

| 文件 / 类型 | 动作 | 改什么 | 为什么 | 步骤 |
|---|---|---|---|---|
| swift-type-indexing `Sources/TypeIndexing/MovedTypeIndex.swift` · `MovedTypeIndex`、`MovedTypeDeclaration`、`MovedTypeKey` | 新增 | 文本扫描器（纯函数）与表的键值类型 | 搬家记录只在文本接口里 | 1 |
| swift-type-indexing `Sources/TypeIndexing/SDKPlatform.swift` · `SDKPlatform` | 修改 | 新增内部属性：本平台文本接口的文件名后缀（`-apple-macos`、`-apple-ios-macabi`、`-apple-ios-simulator`…），以及取哪个平台的搬家版本（含 Catalyst / visionOS 回退到 iOS） | 挑文件、选版本都要按平台来 | 1 |
| swift-type-indexing `Sources/TypeIndexing/TypeDatabase.swift` · `TypeDatabase` | 修改 | `discoverSDK()` 扫描并登记搬家表；新增 `declaringModuleName(ofMovedTypeNamed:originallyDefinedIn:builtAgainst:)`；内部的 `register(movedTypeDeclarations:)` 供测试直接驱动 | 对外的唯一入口 | 2 |
| swift-type-indexing `Tests/TypeIndexingTests/MovedTypeIndexTests.swift` | 新增 | 扫描器的单元测试（手写的接口文本） | 解析规则可脱离 SDK 验证 | 1 |
| swift-type-indexing `Tests/TypeIndexingTests/TypeDatabaseMovedTypeTests.swift` | 新增 | 版本判断与平台回退 | 查询语义 | 2 |
| swift-type-indexing `Tests/TypeIndexingTests/SDKIntegrationTests.swift` | 修改 | 加 `CGFloat` 与 `SwiftUI.View` 两条，照旧默认关闭 | 对真实 SDK 的核对 | 2 |
| swift-type-indexing `Documentations/Internal/TypeIndexingPipeline.md`、`README.md`、`Documentations/Evolutions/README.md` | 修改 | 新增「搬家记录」一节；README 写查询用法；提案索引登记 cross-repository 一行 | 文档同批 | 2 |
| `Sources/Output/SwiftPrinting/NodePrintables/TypeNameResolving.swift` · `MovedTypeModuleResolving` | 新增 | 角色协议 | 打印器侧的入口 | 3 |
| `Sources/Output/SwiftPrinting/NodePrintables/NodePrintableDelegate.swift` · `NodePrintableDelegate` | 修改 | 加 `declaringModuleName(ofMovedTypeNamed:originallyDefinedIn:)` | 节点打印器经委托提问 | 3 |
| `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift` · `TypeNameResolverRegistry`、`addTypeNameResolver(_:)`、委托实现 | 修改 | 新角色的注册与分发 | 与其他角色同一套机制 | 3 |
| `Sources/Output/SwiftPrinting/NodePrintables/NodePrintable.swift` · `resolvedModuleName(of:siblingIdentifier:)` | 修改 | 非 `__C` 模块问新角色 | 唯一出口 | 3 |
| `Sources/Output/SwiftPrinting/NodePrintables/TypeNodePrintable.swift` · `printModuleSelector(ofNestedType:)`、`declaringModuleForModuleSelector` | 修改 | 模块节点来自根时，带回最外层类型的标识符作键 | 嵌套类型跟随外层（编译器同样如此） | 3 |
| `Tests/SwiftInterfaceTests/MovedTypeModuleTests.swift` | 新增 | 用 `FixtureCompiler` 现编一个引用 `CGFloat` 的小库，配记录型替身解析器 | 打印器行为不依赖 SDK | 3 |
| `Sources/Output/SwiftTypeNameResolution/TypeDatabaseMovedTypeModuleResolver.swift` · `TypeDatabaseMovedTypeModuleResolver` | 新增 | 包 `TypeDatabase` + SDK 版本的适配器 | 版本按镜像固定，打印器协议不带版本 | 4 |
| `Sources/Output/SwiftTypeNameResolution/SwiftInterfaceBuilderTypeNameProvider.swift` · `SwiftInterfaceBuilderTypeNameProvider` | 修改 | 加 `Resolutions` 选项集合与 `resolutions:` 参数；遵循新角色；只开搬家时不生成模块接口 | 两个开关共用一个数据库 | 4 |
| `Tests/SwiftTypeNameResolutionTests/TypeDatabaseMovedTypeModuleResolverTests.swift` | 新增 | 适配器的版本判断，经 `@testable` 驱动 `register` | 适配层契约 | 4 |
| `Sources/Commands/SwiftSectionKit/Swift/InterfaceRequest.swift` · `InterfaceRequest` | 修改 | `resolvesMovedTypeModules` 字段与 provider 接线、非 macOS 与无 build version 的警告 | 子命令逻辑在请求里 | 5 |
| `Sources/Executables/swift-section/Commands/InterfaceCommand.swift` · `InterfaceCommand` | 修改 | `--resolve-moved-type-modules` 及 `makeRequest()` 一行 | CLI 只是外壳 | 5 |
| `Tests/SwiftSectionKitTests/…`、`Tests/SwiftSectionCommandTests/CommandRequestMappingTests.swift` | 修改 | 请求两侧各一条 | 新开关两侧各一测（CLAUDE.md） | 5 |
| `Package.swift`、`Tuist/Package.swift` | 修改 | swift-type-indexing 升到新版本 | 用上新 API | 4 |
| `AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md` | 修改 | 第 8 节旁加新开关的说明与陷阱（版本判断、默认关闭） | CLI 改动同批改 skill | 5 |
| `Documentations/Internal/Modules/SwiftInterface.md`、`Documentations/Internal/Modules/SwiftSectionKit.md`、`Documentations/Glossary.md`、`Documentations/Internal/ProjectEvolutionLog.md`、`CLAUDE.md` 的 SwiftTypeNameResolution 条 | 修改 | 新角色、新开关、术语「moved type」、账本一节 | 文档同批 | 6 |

## 架构图

改了什么：

```text
swift-type-indexing
  TypeDatabase (actor)
    discoverSDK()
      APINotesIndex(files:)                         (kept)
    + MovedTypeIndex.scan(interfaceText:moduleName:) for every SDK module
    + movedTypeDeclarationsByKey: [MovedTypeKey: MovedTypeDeclaration]
    moduleName(forTypeName:)                         (kept, __C only)
    swiftName(forCName:category:)                    (kept, __C only)
  + declaringModuleName(ofMovedTypeNamed:originallyDefinedIn:builtAgainst:)

MachOSwiftSection
  SwiftPrinting
    TypeNameResolving
      ModuleNameResolving / CImportedNameResolving / OpaqueTypeResolving   (kept)
    + MovedTypeModuleResolving
    SwiftDeclarationPrinter.typeNameResolverRegistry
    + movedTypeModuleResolvers
    NodePrintable.resolvedModuleName(of:siblingIdentifier:)
      __C / __ObjC  -> ModuleNameResolving           (kept)
    + other module  -> MovedTypeModuleResolving
    TypeNodePrintable.printModuleSelector(ofNestedType:)
    ~ key: outermost type's identifier when the module is the context root
  SwiftTypeNameResolution
    TypeDatabaseTypeNameResolver                     (kept, unchanged)
  + TypeDatabaseMovedTypeModuleResolver(typeDatabase:sdkVersion:)
    SwiftInterfaceBuilderTypeNameProvider
    ~ resolutions: [.cImportedModules, .movedTypeModules]
  SwiftSectionKit.InterfaceRequest
  + resolvesMovedTypeModules
  swift-section interface
  + --resolve-moved-type-modules
```

一次查询的数据流：

```text
interface print of `x: CoreGraphics.CGFloat`
  TypeNodePrintable (context node = module "CoreGraphics", identifier "CGFloat")
    resolvedModuleName(of: module, siblingIdentifier: "CGFloat")
      not __C / __ObjC
      delegate.declaringModuleName(ofMovedTypeNamed: "CGFloat", originallyDefinedIn: "CoreGraphics")
        SwiftDeclarationPrinter -> first non-nil of movedTypeModuleResolvers
          SwiftInterfaceBuilderTypeNameProvider
            TypeDatabaseMovedTypeModuleResolver(sdkVersion: LC_BUILD_VERSION.sdk)
              TypeDatabase.declaringModuleName(ofMovedTypeNamed:originallyDefinedIn:builtAgainst:)
                movedTypeDeclarationsByKey[CoreGraphics, CGFloat]
                  -> declaringModule "CoreFoundation", moved macOS 10.0
                  sdkVersion >= 10.0 -> "CoreFoundation"
    writes "CoreFoundation" + "." (or "::")
```

## 详细设计

### 扫描器

```swift
struct MovedTypeKey: Hashable, Sendable {
    let originalModuleName: String
    let typeName: String
}

struct MovedTypeDeclaration: Hashable, Sendable {
    let typeName: String
    /// The module the mangling names: the part of the attribute's module
    /// argument before a `;`.
    let originalModuleName: String
    /// The module whose interface declares the type now.
    let declaringModuleName: String
    /// The version the attribute names per platform keyword (`macOS`,
    /// `macCatalyst`, `iOS`, `tvOS`, `watchOS`, `visionOS`, `driverKit`).
    let movedVersionsByPlatformName: [String: OperatingSystemVersion]
}

enum MovedTypeIndex {
    /// The type declarations `interfaceText` (a textual `.swiftinterface`
    /// of `moduleName`) marks `@_originallyDefinedIn` another module.
    static func movedTypeDeclarations(inInterfaceText interfaceText: String, moduleName: String) -> [MovedTypeDeclaration]
}
```

规则：

- 只看从第 0 列开始的行。一个属性组是连续的以 `@` 开头的行；组里收集所有 `@_originallyDefinedIn(module: "M", P V)`，同一个属性写多个平台（`macOS 15.0, iOS 18.0`）时逐个拆开。
- 属性组结束后的那一行是声明。去掉行首的属性（`@frozen`、`@MainActor`、`@preconcurrency` 等，含括号参数）和修饰词（`public`、`open`、`final`、`indirect`、`nonisolated`），第一个关键字是 `struct` / `class` / `enum` / `protocol` / `actor` / `typealias` 时取紧跟的标识符为类型名（遇到 `<`、`:`、空格、`=`、`{` 截止；反引号去掉）。其他关键字一律丢弃。
- 平台关键字的拼写取 Swift 源码的写法：`macOS`、`macCatalyst`、`iOS`、`tvOS`、`watchOS`、`visionOS`、`driverKit`；`OSX` 视同 `macOS`，`*ApplicationExtension` 视同其基础平台。
- `module:` 的值有 `;` 时取前半段。前半段等于 `moduleName` 时整条丢弃。

### 挑哪份接口文件

`SwiftModuleDescriptor.path` 是 `.swiftmodule` 目录。在它下面找文件名形如 `<架构>-apple-<平台后缀>.swiftinterface` 的文件，排除 `.private.swiftinterface` 与 `.package.swiftinterface`；平台后缀取自 `SDKPlatform`（`macos`、`ios-macabi`、`ios`、`ios-simulator`、`tvos`、`tvos-simulator`、`watchos`、`watchos-simulator`、`xros`、`xros-simulator`、`driverkit`）。同一模块有几种架构时按文件名排序取第一个（`arm64-` < `arm64e-` < `arm64e.x1-` < `x86_64-`，结果确定）。属性对每个平台都写全，所以选哪个架构不影响结果。目录里没有文本接口的模块（只有二进制 `.swiftmodule`）直接跳过。读文件失败记日志后跳过，不影响别的模块。

### 版本判断

```swift
extension TypeDatabase {
    /// The module that declares the Swift type the mangling names
    /// `originalModuleName.typeName`, when the SDK moved it there
    /// (`@_originallyDefinedIn`) no later than `sdkVersion` of the database's
    /// platform; nil when it never moved, or moved after that version.
    public func declaringModuleName(ofMovedTypeNamed typeName: String, originallyDefinedIn originalModuleName: String, builtAgainst sdkVersion: OperatingSystemVersion) -> String?
}
```

- 用哪个平台的条目：`macOS` → `macOS`；`macCatalyst` → `macCatalyst`，没有就用 `iOS`（Catalyst 的版本号与 iOS 一致）；`iOS` / `iOSSimulator` → `iOS`；`tvOS*` → `tvOS`；`watchOS*` → `watchOS`；`visionOS*` → `visionOS`，没有就用 `iOS` 并换算（iOS 17.x → visionOS 1.x，18.x → 2.x，26 起版本号相同，17 以前视为 visionOS 出现之前就已搬家）；`driverKit` → `driverKit`。
- 找不到适用条目：属性在该平台不生效，mangling 本来就是新模块，返回 `nil`。
- `sdkVersion` 大于或等于搬家版本时返回 `declaringModuleName`。
- 调用前没有 `index` 过：返回 `nil`（与 `moduleName(forTypeName:)` 一致）。

为什么用 `LC_BUILD_VERSION` 的 `sdk` 而不是 `minos`：mangling 与部署目标无关（前期调研 1），interface 想还原的是作者写代码时 SDK 里的样子，这由编译所用的 SDK 决定。系统镜像的 `sdk` 就是它所属的系统版本，所以 macOS 14 cache 里的 SwiftUI 不会被改写成 SwiftUICore。

**已知偏差**：属性写的版本不一定是源码真正搬家的时间。`CGFloat` 写的是 macOS 10.0，运行时却是 macOS 13 才搬进 `libswiftCoreFoundation`（前期调研 2）。用 macOS 12 SDK 编的二进制也会印成 `CoreFoundation.CGFloat`：它在当前 SDK 下成立，但不一定是当年 SDK 的写法。这里信属性，不另做修正表。

### 打印器

```swift
/// Resolves the module that declares a Swift type today when its mangling
/// names the module the type was originally defined in
/// (`@_originallyDefinedIn`): `CoreGraphics.CGFloat` → `CoreFoundation`.
public protocol MovedTypeModuleResolving: TypeNameResolving {
    func declaringModuleName(ofMovedTypeNamed typeName: String, originallyDefinedIn originalModuleName: String) async -> String?
}
```

`resolvedModuleName(of:siblingIdentifier:)` 的新分支：

```swift
if moduleName != objcModule, moduleName != cModule,
   let identifier = siblingIdentifier, !identifier.isEmpty,
   let delegate,
   let declaringModuleName = await delegate.declaringModuleName(ofMovedTypeNamed: identifier, originallyDefinedIn: moduleName) {
    return (declaringModuleName, false)
}
```

它与 `cImportedTypeNameSpelling` 无关：`.cName` 只管 C 导入类型。`printModuleSelector(ofNestedType:)` 改为让 `declaringModuleForModuleSelector` 同时带回「模块节点的来源」：来自根时，带回最外层类型节点的标识符（根模块节点的兄弟）作为查询键；来自 `extension` 时不带，不查询。

### 适配层与请求

```swift
@available(macOS 13.0, *)
public struct TypeDatabaseMovedTypeModuleResolver: MovedTypeModuleResolving {
    public let typeDatabase: TypeDatabase
    /// The SDK version of the image being printed (`LC_BUILD_VERSION`'s `sdk`).
    public let sdkVersion: OperatingSystemVersion
    public init(typeDatabase: TypeDatabase, sdkVersion: OperatingSystemVersion)
}

extension SwiftInterfaceBuilderTypeNameProvider {
    public struct Resolutions: OptionSet, Sendable {
        public static let cImportedModules: Resolutions
        public static let movedTypeModules: Resolutions
    }
}

public init?(machO: MachO, dependencies: SwiftInterfaceBuilderDependencies<MachO>, resolutions: Resolutions = .cImportedModules, supplementaryAPINotesURLs: [URL] = [])
```

- `MachOKit.Version` → `OperatingSystemVersion` 的转换放在适配层（swift-type-indexing 不依赖 MachOKit）。
- provider 未开 `.cImportedModules` 时，`moduleName(forTypeName:)` 与 `swiftName(forCName:category:)` 返回 `nil`，`setup()` 用 `moduleFilter: { _ in false }` 调一次 `index`，不传依赖；未开 `.movedTypeModules` 时，新角色的方法返回 `nil`。
- `InterfaceRequest`：任一开关打开就构造 provider，`resolutions` 按两个开关组合。只开搬家时，现有警告的措辞里把 `--resolve-c-module-names` 换成实际打开的开关名。

### CLI

```text
--resolve-moved-type-modules
    Print a Swift type the SDK moved to another module (@_originallyDefinedIn)
    under the module that declares it now (CoreGraphics.CGFloat ->
    CoreFoundation.CGFloat, SwiftUI.View -> SwiftUICore.View), when the binary
    was built against an SDK that had already moved it. Reads the SDK's
    .swiftinterface files; needs Xcode or the Command Line Tools, not
    sourcekitd. macOS only.
```

## 替代方案考量

- **并进 `--resolve-c-module-names`**：用户只需要记一个「按 SDK 解析」的开关，但那个开关第一次运行要经 sourcekitd 生成模块接口（UIKit 冷生成 126 秒），只想要搬家改写的人不该为它付这笔钱；它的名字和帮助文字也说的是 `__C`。否：用独立开关，两个都开时共用数据库。
- **从 `$ld$previous` 推导**：tbd 里有符号的旧安装路径与版本区间，但给的是库路径而不是模块名，还要逐个符号去重归并成类型；属性才是编译器自己的依据。否。
- **经 sourcekitd 生成的接口读属性**：那一层只有依赖过滤命中的模块才生成，而且 `InterfaceDeclarationNode` 不留属性。搬家后的模块常常不是二进制的直接依赖（引用 `SwiftUI.View` 的二进制未必直接链接 SwiftUICore）。否。
- **不做版本判断、一律按宿主 SDK 改写**：macOS 14 的 SwiftUI 镜像会印出当时还不存在的 SwiftUICore，而 `View` 恰好就声明在被打印的这个镜像里。否。
- **按「类型定义是否在被打印的镜像里」判断**：SwiftUICore 镜像（macOS 15 起）里的定义正应改写成 SwiftUICore，这条规则会反着判。否。
- **打印器协议带版本参数**：版本是被打印镜像的固定属性，放进适配器构造时一次给定，打印器不必知道 Mach-O。否。
- **给 `TypeDatabaseTypeNameResolver` 直接加新角色**：RuntimeViewer 升级后输出会悄悄改变，而且它拿不到每个镜像的 SDK 版本。否：另起一个适配器。
- **默认开启**：见非目标。

## 影响

### 源码兼容性（source compatibility）

纯新增：

- swift-type-indexing：`TypeDatabase` 多一个公开方法。
- MachOSwiftSection：`SwiftPrinting` 多一个公开协议；`SwiftTypeNameResolution` 多一个公开类型；`SwiftInterfaceBuilderTypeNameProvider.init` 多一个带默认值的参数（默认值保持现有行为）；`InterfaceRequest` 多一个带默认值的字段；CLI 多一个开关。`NodePrintableDelegate` 是内部协议，加要求不影响外部。

### ABI 兼容性（条件项）

不适用 —— 两个库都以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 本仓库：`SwiftPrinting`、`SwiftTypeNameResolution`、`SwiftSectionKit`、`swift-section`。
- swift-type-indexing 要先发新版本（0.2.0，新增公开 API），本库才能用上。
- RuntimeViewer：不受影响（`TypeDatabaseTypeNameResolver` 不变）；以后想要这项改写，要为每个镜像构造 `TypeDatabaseMovedTypeModuleResolver` 并传入 SDK 版本。MachOObjCSection 的 `ObjCTypeIndexing` 不受影响。

### 文档与示例

- swift-type-indexing：`TypeIndexingPipeline.md` 新增一节，README 写查询用法。
- 本仓库：`Documentations/Internal/Modules/SwiftInterface.md`、`Documentations/Internal/Modules/SwiftSectionKit.md`、`CLAUDE.md` 的 SwiftTypeNameResolution 一条、agent 插件 skill（`AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md`）、`Documentations/Glossary.md`（术语 moved type）、`ProjectEvolutionLog.md`。

## API 演进与废弃策略

- 不替代任何旧 API。
- `Resolutions` 用 `OptionSet`：以后再加别的 SDK 解析能力时只是加一个成员。
- swift-type-indexing 0.1.x → 0.2.0；MachOSwiftSection 跟随下一个版本发布，不需要大版本跃迁。

## 落地步骤

1. **扫描器** —— 改动地图 swift-type-indexing 的 `MovedTypeIndex.swift`、`SDKPlatform.swift`、`MovedTypeIndexTests.swift`
   - 行为：`structMovedFromAnotherModuleIsRecorded`
   - 行为：`protocolClassEnumActorAndTypealiasAreRecorded`
   - 行为：`extensionsFunctionsAndVariablesAreNotRecorded`
   - 行为：`declarationModifiersAndAttributesBeforeTheKeywordAreSkipped`
   - 行为：`severalPlatformsInOneAttributeAreSplit`
   - 行为：`manglingModuleIsThePartBeforeTheSemicolon`
   - 行为：`moveWithinTheSameModuleIsNotRecorded`
   - 行为：`indentedAttributesAreIgnored`
   - 行为：`interfaceFileMatchingThePlatformIsChosen`
2. **数据库与查询** —— 改动地图 swift-type-indexing 的 `TypeDatabase.swift`、`TypeDatabaseMovedTypeTests.swift`、`SDKIntegrationTests.swift` 与文档三行；完成后发 swift-type-indexing 0.2.0
   - 行为：`answersTheDeclaringModuleWhenTheSDKIsNotOlderThanTheMove`
   - 行为：`answersNothingForAnSDKOlderThanTheMove`
   - 行为：`answersNothingForATypeThatNeverMoved`
   - 行为：`answersNothingBeforeIndexing`
   - 行为：`macCatalystFallsBackToTheIOSVersion`
   - 行为：`visionOSMapsTheIOSVersion`
   - 行为：`firstDiscoveredModuleWinsATiedKey`
   - 行为（SDK 集成，默认关闭）：`cgFloatMovedFromCoreGraphicsToCoreFoundation`、`swiftUIViewMovedToSwiftUICoreInMacOS15`
   - 落地时把扫描全部 SDK 模块的实测耗时写进前期调研 5。
3. **打印器** —— 改动地图 `TypeNameResolving.swift`、`NodePrintableDelegate.swift`、`SwiftDeclarationPrinter.swift`、`NodePrintable.swift`、`TypeNodePrintable.swift`、`MovedTypeModuleTests.swift`
   - 行为：`movedTopLevelTypePrintsUnderItsDeclaringModule`
   - 行为：`nestedTypeFollowsItsOutermostType`
   - 行为：`moduleSelectorsSpellTheDeclaringModuleOnNestedTypes`
   - 行为：`extensionHeaderOfAMovedProtocolUsesTheDeclaringModule`
   - 行为：`cImportedModulesAreNeverAskedAboutMoves`
   - 行为：`withoutAResolverTheManglingModuleIsKept`
   - 行为：`importLinesKeepTheManglingModules`
4. **适配层** —— 改动地图 `TypeDatabaseMovedTypeModuleResolver.swift`、`SwiftInterfaceBuilderTypeNameProvider.swift`、`TypeDatabaseMovedTypeModuleResolverTests.swift`、`Package.swift`、`Tuist/Package.swift`
   - 行为：`resolverAnswersForTheImagesSDKVersion`
   - 行为：`providerWithOnlyMovedTypesGeneratesNoModuleInterface`
   - 行为：`providerWithBothResolutionsSharesOneDatabase`
   - 行为：`providerDefaultKeepsTodaysResolutions`
5. **请求与 CLI** —— 改动地图 `InterfaceRequest.swift`、`InterfaceCommand.swift`、两侧测试、agent 插件 skill
   - 行为：`interfaceRequestResolvesMovedTypeModulesOnlyWhenAsked`
   - 行为：`resolveMovedTypeModulesFlagMapsOntoTheRequest`
   - 行为：`bothResolutionFlagsCombine`
   - 核对 skill 里点到的每个开关都还存在（CLAUDE.md 的 `grep -ohE` 命令）。
6. **文档与收尾** —— 改动地图最后一行
   - 用 `swift-section interface --resolve-moved-type-modules` 打一次 macOS 27 的 SwiftUI 与 15.5 归档 cache 里的 SwiftUI，确认前者印 SwiftUICore、后者照旧印 SwiftUI，结果写进决策日志。
   - 新开关默认关闭，不开时输出逐字节不变；按 CLAUDE.md，这一改动不属于需要渲染 A/B 的大重构，以 `withoutAResolverTheManglingModuleIsKept` 与现有快照测试为准。

**收尾时必须判断两件事**（判断结果写进决策日志，不允许沉默跳过）：

- **要不要配套专题文章** —— 预计不单独写：调用方契约在 swift-type-indexing 的 README 与 `TypeIndexingPipeline.md` 里，打印器一侧在 `Modules/SwiftInterface.md`。
- **有没有引入新术语** —— 有：「moved type」（被 `@_originallyDefinedIn` 搬过家的类型），登记进 `Documentations/Glossary.md`。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-11-25 | Created as Draft | 用户发现 `CGFloat` 在 SDK 里由 CoreFoundation 声明、二进制里却叫 CoreGraphics，问 swift-type-indexing 能否让输出与 SDK 一致；调研确认能做，用户要求写提案。 |
| 2026-11-25 | 方案取舍 | 独立开关、默认关闭；按二进制的 SDK 版本判断是否改写；`dump` 与 diff 类命令不改；RuntimeViewer 不随升级改变行为。用户确认开关做成独立的 `--resolve-moved-type-modules`。 |
| 2026-11-25 | Accepted | 用户批准，开始实现。 |
