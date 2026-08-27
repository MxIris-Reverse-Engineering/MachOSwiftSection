# 0009 - TypeIndexing 重启：`__C` 类型模块归属解析的索引管线修复与重构

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-21
- **最后更新**: 2026-08-22
- **所属愿景**: 无
- **关联提案**: 无（与 0005 的事件化上报正交，但本案的降级上报遵循 0005 确立的规则：库代码不写进程流，走 `SwiftIndexEvents` / `#log` 地板）
- **实现分支 / PR**: `feature/type-indexing-revival`（基于 `next`）
- **配套文档**: [TypeIndexingPipeline.md](../Internal/TypeIndexingPipeline.md)（实现说明，含与提案的差异）、[TaskReports/2026-08-22-type-indexing-revival.md](../Internal/TaskReports/2026-08-22-type-indexing-revival.md)；AGENTS.md 架构节与 `Documentations/README.md` 索引已同步

## 摘要

`Sources/TypeIndexing` 是把打印输出里的 `__C.NSString` 恢复成 `Foundation.NSString` 的模块归属索引库：用 SourceKit 生成 SDK 模块的 Swift interface 并从中提取「类型名 → 模块」映射（覆盖公开 API，含 APINotes 改名的 C 类型），再以 ObjC 运行时元数据补私有类的归属。它的 target 早在 Swift 6 迁移期就被整体注释出 `Package.swift`，一直未恢复。本案恢复该 target 并修复使它当年不可用的结构性问题：SDK 全量 SourceKit interface 生成导致的小时级首次索引（过滤形同虚设）、APINotes 双向表的模块名写错等正确性 bug、被 MachOObjCSection 新 `ObjCIndexing` library 取代的本地 ObjC 索引器（用户已裁定删除）、以及日志规范欠账（`os.Logger` 直用，`PrintFailureEventTests` 留有「revive 前必须先转换」的显式豁免）。同时按用户裁定**去掉 SwiftSyntax 运行时依赖**：类型名提取改从 sourcekitd 的结构化响应（document structure）直接读取，手写行级解析兜底——swift-syntax 目前在包里只喂 `MachOMacros` 宏插件（编译期产物，不进库），TypeIndexing 若把 `SwiftSyntax` + `SwiftParser` 作为普通依赖链接，会给每个消费方带来数十 MB 量级的体积增量。

## 动机

打印管线的挂接点一直是活的：`NodePrintable.printModule`（`Sources/SwiftPrinting/NodePrintables/NodePrintable.swift:113-122`）在 module 节点为 `__C` / `__ObjC` 且带 sibling identifier 时，会问 delegate 的 `moduleName(forTypeName:)`（带 `Ref` 后缀剥除回退，覆盖 `CFStringRef` → `CFString`）；`TypeNameResolvable` → `SwiftInterfaceBuilderExtraDataProvider` → `SwiftInterfaceBuilder.addExtraDataProvider` 的协议链完整。但唯一的 provider 实现 `SwiftInterfaceBuilderTypeNameProvider` 躺在不参与编译的 TypeIndexing 里，所以现在所有 `__C` 类型都原样打印，dump / interface 输出里的 ObjC 导入类型全部丢失真实模块归属。

索引必须双来源，缺一不可：

1. **公开 API**：`__C.NSString` 里的 `NSString` 是 ObjC 头文件导入的类型，SDK 的 `.swiftinterface` 文件只含 Swift 声明、不含 ObjC 导入声明，所以唯一能拿到「Swift 视角下含全部 ObjC 导入声明的模块 interface」的现成途径是 sourcekitd 的 `editor.open.interface`（即 Xcode 生成 interface 用的那条路）。APINotes 补两类信息：被 `SwiftName` 改名的 C 类型的归属，以及 C 名 ↔ Swift 名的双向映射。
2. **ObjC 元数据**：私有类（`_UINavigationBarVisualProvider` 之类）不出现在任何公开 interface 里，只能从二进制依赖的 `__objc_classlist` / `__objc_protolist` 反查它声明在哪个 image。

## 前期调研（现状问题清单）

以下基于 `next` 分支 `Sources/TypeIndexing` 十个文件的逐行阅读。

### 1. 性能结构性缺陷 —— 当年「暂时关闭」的最可能直接原因

`SDKIndexer.index()` 扫描 SDK 目录时，对每个发现的 `.swiftmodule` 立即构造 `SwiftModule(moduleName:path:platform:)`，而这个 init 当场调 `SourceKitManager.interface(for:in:)` 生成整个模块的 interface（每个请求 60 秒超时，还递归生成 submodule 的）。也就是说**全 SDK 数百个模块每个都要过一遍 sourcekitd**，而 `TypeDatabase.index(dependencies:filter:)` 的 filter 在这之后才应用——过滤从不省任何时间。首次索引是小时级的，且磁盘缓存以整个 SDK 索引完成为前提（`indexComplete` 标记文件）。

### 2. 正确性 bug

| # | 位置 | 问题 |
|---|------|------|
| 2a | `APINotesManager.swift:60` | `cNameToSwiftName[cName] = .init(moduleName: swiftName, name: swiftName)` —— `moduleName` 字段填的是 swiftName，`swiftName(forCName:)` 拿到的模块名是错的 |
| 2b | `SwiftModule.swift:43` | `write(toDirectory:)` 把主 interface 内容写到 `directoryURL`（目录路径本身）而不是算好却从未使用的 `moduleDirectoryURL` |
| 2c | `SwiftInterfaceParser.swift:195-227` | `fullyQualifiedName` 只识别 struct / class / enum / protocol 父节点，不处理 `ExtensionDeclSyntax` —— 生成的 interface 里大量 `extension Foo { public struct Bar }` 形态的嵌套类型会以裸名 `Bar` 入库，键错误 |
| 2d | `SDKIndexer.swift:120-124` | 磁盘缓存只按 platform rawValue 分目录，不含 SDK 版本 —— Xcode 升级后继续返回陈旧索引，无任何失效机制 |
| 2e | `SourceKitManager.swift:19` | sourcekitd 的 dylib 路径硬编码 `/Applications/Xcode.app/...XcodeDefault.xctoolchain/...` —— Xcode-beta、多版本共存、重命名安装一律 init 失败 |
| 2f | `TypeDatabase.swift:49-51` | APINotes 注册循环消费的 `Name.moduleName` 依赖 2a 的错误赋值，须与 2a 一起修并补测试 |
| 2g | `SDKIndexer.swift:198` | `apinodesFile` 拼写错误（应为 `apiNotesFile`） |

### 3. 被取代组件

`Sources/TypeIndexing/ObjCInterfaceIndexer.swift` 是基于 `ObjCDump` 全量 `info(in:)` 解析的自建索引器，且 `TypeDatabase.index` 里对它的调用整段被注释、结果只 `print` 占位——从未真正接线。MachOObjCSection（本仓库依赖下限已是 0.8.104）现在提供独立的 **`ObjCIndexing`** library product：同名 `ObjCInterfaceIndexer`，per-image `prepare()` 一次、之后按名字查询 classes / protocols / categories，file / image 双模式与 arm64e PAC 处理都已做对。**用户已裁定删除本仓库副本，改用 MachOObjCSection 的索引 API。**

### 4. 工程规范欠账

- 日志直用 `os.Logger`（`SDKIndexer.swift` 6 处），违反项目「`@Loggable` + `#log`，永不 `os.Logger`」硬规则；`PrintFailureEventTests.libraryModulesLogThroughTheLoggableMacro` 留有显式豁免注释："If that target is ever revived, convert it first."
- `Package.swift` 注释块里声明的依赖有两个实际零 import：`swift-clang`（`Clang`）与 `SwiftSyntaxBuilder`——恢复时不再引入。
- `BinaryCodable` 仅用于索引缓存序列化，缓存主体是文本，换 Foundation 的 `JSONEncoder` / `JSONDecoder` 可减一个第三方依赖，编码效率差异无关紧要。
- `SwiftInterfaceParser` 的 `IndexerVisitor` 标 `@unchecked Sendable` 并给单线程 walk 的两个数组套 `@Mutex`——属于当年 Swift 6 迁移的应付式写法，顺手改成普通类内状态。

### 5. 测试缺失

`TypeIndexingTests` 从未存在——`Package.swift` 注释块引用的 `Tests/TypeIndexingTests` 目录不在仓库里。

### 6. SwiftSyntax 是不必要的体积负担

swift-syntax 目前在本包里只被 `MachOMacros` 宏 target 消费——宏是编译期插件，产物不进库和下游 app。TypeIndexing 把 `SwiftSyntax` + `SwiftParser` 作为普通运行时依赖链接，才是体积暴增的引入点（release 静态链接数十 MB 量级，RuntimeViewer 一旦引 TypeIndexing product 全部吃进）。而 `TypeDatabase` 对解析结果的**全部消费只有 fully-qualified 类型名清单**——`TypeInfo` 的 members、genericParams 从头到尾无人读取，整套语法树解析是杀鸡用牛刀。用户裁定：去掉 SwiftSyntax，换 sourcekitd 结构化响应（方案 A′）。

## 提议方案

### A. 索引管线重构：发现与生成分离，过滤前移

- `SDKIndexer` 的扫描只做**文件发现**：枚举 `.swiftmodule` 得到 `[SwiftModuleDescriptor]`（moduleName + path），解析 `.apinotes` 文件——全程不触 SourceKit，秒级。
- SourceKit interface 生成与类型名提取下沉到 `TypeDatabase.index` 的 **filter 之后**：只对二进制依赖命中的模块（典型：一个 app 二进制十几到几十个）生成 interface。`SwiftModule` 不再在 init 里做重活，改为从 descriptor 显式驱动。
- 磁盘缓存改为 **per-module、按 SDK 版本分层**：`Application Support/MachOSwiftSection/SDKIndexer/<platform>/<SDK ProductBuildVersion>/<module>.json`，内容是解析产物（类型名清单 + submodule 名单），不再缓存 interface 全文；去掉全量 `indexComplete` 门槛，命中一个模块用一个模块。序列化用 `JSONEncoder`，`BinaryCodable` 依赖移除。

### A′. 类型名提取去 SwiftSyntax：sourcekitd 结构化响应为主，行级解析兜底

- 删除基于 `SwiftSyntax` / `SwiftParser` 的 `SwiftInterfaceParser`；`SwiftSyntax`、`SwiftParser`、`OrderedCollections` 三个依赖不再引入（swift-syntax 的 package 声明仍在，继续只服务 `MachOMacros` 宏插件）。
- **主路**：`editor.open.interface` 请求带 `key.enablesubstructure`，从响应的 `key.substructure`（Xcode 大纲视图的数据源）直接读声明树——每个节点带 kind（`source.lang.swift.decl.class` / `.struct` / `.enum` / `.protocol` / `.extension`）与 `key.name`，沿父链拼 fully-qualified 名（extension 节点取被扩展类型名作限定前缀，天然覆盖原 2c 的 extension 嵌套问题）。提取器写成「substructure 字典 → `[TypeName]`」的纯函数，测试用罐装响应驱动、不触 sourcekitd。
- **兜底**：若落地验证发现 `editor.open.interface` 不返回 substructure（或树不含所需信息），退到手写行级解析器：生成的 interface 是机器产出的规整文本，声明形态有限，缩进栈 + 声明关键字匹配即可提取类型名与嵌套关系，零依赖、字符串驱动可测。主路兜底二选一在落地步骤 1 的验证后定夺，接口对 `TypeDatabase` 同形。
- submodule 名单（原 `importInfos` 的用途）从 sourcetext 做行级 `import <Module>.<Sub>` 扫描获得，不需要语法解析。

### B. ObjC 私有类归属：删自建索引器，接 MachOObjCSection `ObjCIndexing`

- 删除 `Sources/TypeIndexing/ObjCInterfaceIndexer.swift`。
- `TypeDatabase` 持有依赖 image 列表；`moduleName(forTypeName:)` 查询顺序为 **公开 API + APINotes 合并表 → ObjC 懒索引**：只有前者 miss 时，才按依赖顺序对下一个尚未索引的 image 构造 `ObjCIndexing.ObjCInterfaceIndexer` 并 `prepare()`，把它的 class / protocol 名并入「ObjC 名 → image 模块名」表，命中即止、结果缓存。私有类查询是少数路径，懒索引把几百个依赖 image 的解析成本摊到真正 miss 的时刻。
- 模块名取 image 路径最后一段（去扩展名，`libswift` 前缀剥除逻辑保留）。

### C. 正确性修复

前期调研 2a–2g 逐条落实：2a/2f（APINotes 模块名）原地修复并带针对性单测（修复前失败、修复后通过，永久保留）；2b（`SwiftModule.write` 写错路径）与 2c（extension 嵌套键错误）随重构消亡——前者所在的 interface 全文持有/导出逻辑在新缓存设计下整体删除，后者由 A′ 的新提取器承接为显式需求并带单测；2d（缓存无 SDK 版本）由 A 节的缓存分层解决；2g 拼写修正。2e 的 sourcekitd 路径改为从 `xcode-select -p`（active developer dir）拼 `Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd`，失败时抛带指引的错误而不是硬编码路径。

### D. 规范整改

- 全模块日志转 `@Loggable` + `#log`（泛型类型 `TypeDatabase<MachO>` 走 protocol 形态）；移除 `PrintFailureEventTests` 里 `SDKIndexer.swift` 的 `excludedFromBuild` 豁免。
- 降级行为（某模块 interface 生成失败、某 apinotes 解析失败、某依赖 image 索引失败）不吞：能到达事件层的走 `SwiftIndexEvents`，否则 `#log` 地板，与 0005 一致。
- 拼写与命名修正（`apinodesFile` 等）。

### E. `Package.swift` 恢复、CLI 接线与测试

- 恢复 `TypeIndexing` target / library product / `TypeIndexingTests`。依赖裁剪后为：`SwiftInterface`、`Dependencies`（既有 swift-dependencies）、`FoundationToolbox`（既有 FrameworkToolbox）、`ObjCIndexing`（既有 MachOObjCSection range）、**新增** `SourceKitD`（Mx-Iris/SourceKitD）与 `APINotes`（MxIris-DeveloperTool/swift-apinotes），后两者 `.when(platforms: [.macOS])`。不再引入 swift-syntax 全家（`SwiftSyntax` / `SwiftParser` / `SwiftSyntaxBuilder`，见 A′）、swift-clang、`OrderedCollections`、BinaryCodable、ObjCDump。
- `swift-section interface` 新增 `--resolve-c-module-names` 开关：开启时构造 `SwiftInterfaceBuilderDependencies`（MachOFile 默认 `.usesSystemDyldSharedCache`）并挂 `SwiftInterfaceBuilderTypeNameProvider`。默认关闭，默认输出字节不变。
- 测试分层：类型名提取器（substructure 罐装响应驱动，含 extension 嵌套、fully-qualified 键；兜底行级解析器则字符串驱动）与 `APINotesManager` 双向表（临时文件驱动）为纯单测；`TypeDatabase` 合并优先级用注入 fake 的单测；真触 SDK + sourcekitd 的端到端放 `Tests/IntegrationTests/`（维护者手动，agent 不跑）。

### 非目标

- `swiftName(forCName:)` 的**打印侧消费**：`NodePrintable` 目前从不调它（协议里有、渲染里无消费点）。本案只保证 provider 侧数据正确（修 2a），C 名 → Swift 名的渲染替换另立提案。
- RuntimeViewer 侧接入（RuntimeViewer 当前零引用，接入是它自己的变更）。
- 非 macOS 平台支持（整个 target 保持 `#if os(macOS)`）。
- MachOObjCSection 侧的 name-only 快速索引路径（见「替代方案考量」，若懒索引实测过重再去上游提）。

## 详细设计

### 查询数据流

```
NodePrintable.printModule("__C", sibling: "NSString")
    → SwiftDeclarationPrinter.moduleName(forTypeName: "NSString")   // typeNameResolvers 逐个问
    → SwiftInterfaceBuilderTypeNameProvider
    → TypeDatabase.moduleName(forTypeName:)
        1. types["NSString"]          // Swift interface 类型名 + APINotes C 名，setup 时合并完成
        2. objcNameToModule 懒索引     // miss 才逐依赖 image prepare，命中即止
    → "Foundation"
```

`types` 合并写入顺序：先 Swift interface 类型名（typeName → 其所属模块），后 APINotes 的 C 名条目（cName → apinotes 文件所属模块）——APINotes 覆盖同名冲突，因为它是编译器视角的权威改名记录。ObjC 懒索引不写入 `types`，单独成表，且从不覆盖前两层（公开归属永远优先于「它的元数据在哪个 image」——同一个类可能被多个 image 引用，声明处才是归属）。

### `SDKIndexer` 拆分后的形态

```swift
struct SwiftModuleDescriptor: Sendable, Codable {
    let moduleName: String
    let path: String
}

final class SDKIndexer: Sendable {
    func discover() throws -> (modules: [SwiftModuleDescriptor], apiNotesFiles: [APINotesFile])
}
```

`TypeDatabase.index(dependencies:filter:)`：`discover()` → filter descriptors → 对命中者并发（沿用 `withThrowingTaskGroup`，sourcekitd 请求由 `SourceKitManager` actor 天然串行）走「缓存命中读 JSON / miss 生成 interface → 解析 → 写缓存」→ 合并 `types` → 记录依赖 image 列表供懒索引。单模块失败降级为跳过该模块并上报，不再让整次索引 throw 中断（现状是 task group 里一个模块 throw 全部作废）。

### 缓存条目

```swift
struct ModuleIndexCacheEntry: Codable {
    let moduleName: String
    let typeNames: [String]        // fully-qualified，含 submodule 的
    let subModuleNames: [String]
    let generatorVersion: Int      // 解析器行为变更时递增，整目录失效
}
```

SDK 版本取 `SDKSettings.plist` 的 `Version` + `ProductBuildVersion`（后者区分同版本号的 beta 序列）。

### 类型名提取器（`InterfaceTypeNameExtractor`）

`editor.open.interface` 响应经 SourceKitD 的字典封装后进提取器：深度优先走 `key.substructure`，声明类节点（class / struct / enum / protocol）按父链累积限定名入清单，extension 节点自身不入清单、只以 `key.name`（被扩展类型名，可能已带点分限定）作为其子节点的限定前缀——`extension Foo.Bar { public struct Baz }` 产出 `Foo.Bar.Baz`，原 2c 的键错误在新提取器里是显式测试用例。提取器输入建模为值类型的节点树（从 SourceKitD 响应转换），单测用罐装树驱动，不触 sourcekitd 进程。

### 风险与接受的约束

- **SourceKitD / swift-apinotes 两个外部包的健康度**是本案最大的落地风险：都是低频维护的个人仓库，恢复后第一步就是在当前 Swift 6.2 工具链下解析与编译验证；编不过则修 fork（两个都在用户自己的 org 下，可控）。
- sourcekitd 是进程内 XPC 客户端，行为随 Xcode 版本漂移；`editor.open.interface` 是 Xcode 自身依赖的稳定请求，风险可接受。**`key.enablesubstructure` 在该请求上的支持情况需落地实测**（`editor.open` 明确支持，interface 变体文档缺失）——验证失败即启用 A′ 的行级解析兜底，对 `TypeDatabase` 接口同形，不影响其余设计。
- 首个未命中缓存的模块仍要付一次 interface 生成的真实成本（大模块数秒到数十秒）——这是功能本质成本，管线重构消掉的是「为不相关模块付费」。
- `ObjCIndexing.ObjCInterfaceIndexer.prepare()` 解析全部成员 info，对单个大 framework 不算轻。懒索引 + 命中即止把它压到 miss 路径上；若实测仍重，未来方向是在 MachOObjCSection 加 name-only 路径，本案不做。

## 替代方案考量

- **保留自建 ObjCDump 索引器**：与 MachOObjCSection `ObjCIndexing` 功能重复且没做 PAC / file 模式细节，用户已裁定删除。不采。
- **绕过 `ObjCIndexing`、直接枚举 `machO.objc.classes64` 取名**：更轻，但要在本仓库重做 file / image 双模式与防御性读取的细节，恰是 `ObjCIndexing` 已经做对的部分。不采（作为上游 name-only 优化的未来方向保留）。
- **直读 SDK `.swiftinterface` 文件代替 sourcekitd**：省掉 SourceKitD 依赖，但 `.swiftinterface` 只含 Swift 声明，而本功能的主要目标恰是 ObjC 导入类型——缺主料。不采。
- **一张静态打表（常见 ObjC 类 → 模块）**：零依赖零成本，但覆盖永远追不上 SDK 演进，且私有类完全无解。不采。
- **保留 SwiftSyntax 做 interface 文本解析**（原方案）：`SwiftSyntax` + `SwiftParser` 作为运行时依赖静态链接进每个 TypeIndexing 消费方，体积增量数十 MB 量级，而消费面只是类型名清单。用户裁定不采，换 sourcekitd 结构化响应（A′）。
- **索引器做成独立 executable、SwiftSyntax 只进工具**：体积问题可解，但引入进程间协作与工具分发的复杂度；在 A′ 可行（且兜底同样零依赖）的前提下没有必要。不采。

## 影响

### 源码兼容性（source compatibility）

TypeIndexing 是重新恢复的 product，无既有下游消费者（RuntimeViewer 及其余下游 grep 证实零引用）；`SwiftInterface` / `SwiftPrinting` 侧协议与既有 public API 不动。`swift-section interface` 新增 flag 为纯增量，默认输出字节不变。

### ABI 兼容性（条件项）

不适用（SPM 源码分发，见 `Evolutions/README.md` 头部声明）。

### API 演进与废弃策略

public 面收口到 `SwiftInterfaceBuilderTypeNameProvider` 一个类型；`TypeDatabase`、`SDKIndexer`、`SourceKitManager` 等保持 `package` / internal 访问级，后续可自由重构。

### 下游影响

RuntimeViewer 将来接入只需构造 provider 并 `addExtraDataProvider`，无其它面。新增两个 macOS-only 外部依赖（SourceKitD、swift-apinotes）只被 TypeIndexing target 引用，不影响其余 product 的依赖闭包。

### 文档与示例

落地时新增 `Documentations/Internal/TypeIndexingPipeline.md`（管线、缓存布局、降级行为、已知坑），AGENTS.md 架构节补 TypeIndexing 条目，`Documentations/README.md` 索引登记，本提案状态原地推进。

## 落地步骤

1. `Package.swift`：恢复 target / product / test target，按 E 节裁剪依赖；验证 SourceKitD 与 swift-apinotes 在当前工具链可解析可编译，并实测 `editor.open.interface` + `key.enablesubstructure` 的可用性（本步是 go / no-go 闸门：包编不过先修 fork；substructure 不可用则 A′ 落兜底行级解析）。
2. 删除 `ObjCInterfaceIndexer.swift` 与 SwiftSyntax 版 `SwiftInterfaceParser`；`SDKIndexer` 拆分（A 节）；类型名提取器落地（A′ 节）；`TypeDatabase` 重构（查询数据流 + 懒索引 + 缓存）。
3. 正确性批（C 节，2a–2g，带复现测试）。
4. 规范批（D 节：`@Loggable` 转换、豁免移除、事件化降级）。
5. CLI 接线 + `TypeIndexingTests` 全套 + IntegrationTests 端到端。
6. 文档批（配套文档、AGENTS.md、README 索引、提案状态 → Implemented），与代码同批提交。

验证口径：单测按「修复前失败」纪律逐条挂钩；端到端以真实 framework（AppKit / Foundation 依赖面）跑 `swift-section interface --resolve-c-module-names`，人工核对 `__C.` 前缀替换正确性与 miss 时的懒索引行为；默认路径（不开 flag）与 main 输出字节比对确认零扰动。

## 决策日志

- 2026-08-21：用户裁定删除 TypeIndexing 内的旧 `ObjCInterfaceIndexer`，私有类归属改用 MachOObjCSection 已有的 `ObjCIndexing` 索引 API；提案立项（In Review）。
- 2026-08-21：用户指出 SwiftSyntax 集成会使库体积暴增；结合「`TypeDatabase` 只消费类型名清单」的调研发现，裁定类型名提取改走 sourcekitd 结构化响应（`key.substructure`）、手写行级解析兜底，SwiftSyntax / SwiftParser / OrderedCollections 不再进 TypeIndexing 依赖（A′ 节）。
- 2026-08-22：用户批准提案（Accepted），并裁定在独立 worktree 实施；开工，状态置 In Progress，实现分支 `feature/type-indexing-revival`（基于 `next`）。
- 2026-08-22：落地步骤 1 的 go / no-go 闸门通过（scratchpad 探针包实测，Xcode 26 / macOS 26.5 SDK）：SourceKitD 0.1.0 与 swift-apinotes 在 Swift 6.2 下编译通过；`editor.open.interface` + `key.enablesubstructure` 返回完整 substructure（节点带 kind + name，嵌套类型与 extension 节点齐全，ObjectiveC / CoreGraphics 两模块验证）；APINotes 解析真实 `Foundation.apinotes` 正常（100 class + 113 tag 改名，含点分限定 SwiftName）。**A′ 主路成立，兜底行级解析器不再编写**。
- 2026-08-22：编号从 0006 避让至 0008——`main` 上的并行会话同日登记了 0005–0007 三个 Draft（其 0006 为「Extension 容器索引期去重」），避免合并时撞文件名。注意 `main` 新登记的 0005 与 `next` 已有的 0005（事件化降级上报，Implemented）也已互撞，该冲突非本案引入，留待两线合并时裁决。
- 2026-08-22：用户指正首轮端到端输出——`CoreFoundation.CFStringRef` 是 Swift 里不存在的拼写：`CFStringRef` 是 C 侧 typedef 名，ClangImporter 剥 `Ref` 后缀桥接为原生 class `CFString`。据此把「非目标」里的 C 名 → Swift 名渲染替换**局部收进本案**：打印侧在 `__C` module 解析成功时对 identifier 消费 `swiftName(forCName:)`（此前该协议方法零消费者），数据侧在 APINotes miss 后补 CF `Ref` 剥除规则（剥后名必须真实存在于归属表）。完整的改名渲染（含成员级）仍另立提案。
- 2026-08-23：两线合并的编号终审——`main` 线的 0006/0007/0008（其 0008 为「interface header 与导出状态标注」）先并入 `next`，按「后合并者重排」原则本案由 0008 重排为 **0009**，续作提案（补充映射）由 0009 重排为 0010。本文历史叙述中自称的「0008」均指本案。
