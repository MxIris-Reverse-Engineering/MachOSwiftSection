# TypeIndexing：`__C` 模块归属索引管线实现说明

> 本文是 evolution 提案 [0008](../Evolutions/0008-type-indexing-revival.md)（TypeIndexing 重启）的配套实现说明，面向维护者：记录实际落地的管线、与提案的差异、缓存布局与已知降级。

## 这个模块做什么

打印管线遇到 `__C` / `__ObjC` module 节点时（`NodePrintable.printModule`），会拿 sibling identifier 问 delegate 的 `moduleName(forTypeName:)`（带 `Ref` 后缀剥除回退）。`TypeIndexing` 提供唯一的 provider 实现 `SwiftInterfaceBuilderTypeNameProvider`：挂上它之后，`__C.NSString` 打印为 `Foundation.NSString`。CLI 入口是 `swift-section interface --resolve-c-module-names`；库入口是 `builder.addExtraDataProvider(SwiftInterfaceBuilderTypeNameProvider(machO:dependencies:))`。

## 查询数据流（三源合并，优先级从高到低）

```
moduleName(forTypeName: "NSString")
    1. moduleNamesByTypeName   ← Swift interface 类型名（低）+ APINotes C 名（高，后写覆盖）
    2. objcModuleNamesByTypeName ← ObjC 元数据懒索引（最低，只补缺）

swiftName(forCName: "CFStringRef", category:)   ← identifier 重写（见下节）
    1. APINotes 改名表（按声明类别隔离）
    2. CF `Ref` 剥除规则（剥后名必须存在于归属表；protocol 类别不适用）
```

## Identifier 重写：C 拼写 → Swift 拼写（用户指正驱动）

module 名替换之外，`__C` 类型的 **identifier 本身**也可能是 Swift 里不存在的 C 拼写——首轮端到端输出的 `CoreFoundation.CFStringRef` 被用户指正：`CFStringRef` 是 C 侧 typedef 名，ClangImporter 剥 `Ref` 后缀桥接为原生 class `CFString`。落地为打印侧对 `swiftName(forCName:category:)` 的消费（该协议方法此前零消费者）：

- **只在 module 解析成功时重写**（`printModule` 返回是否命中），未解析的 `__C.CFStringRef` 绝不渲染成半吊子 `__C.CFString`。
- **查询必须带声明类别**（`CImportedTypeNameCategory`，由 mangling 的 `Node.Kind` 映射：class / protocol / 值类型 / other）。这是第一版合并改名表当场踩出的回归：ObjC 的 class `NSObject` 与 protocol `NSObject` 同名，APINotes 只把 **protocol** 改名为 `NSObjectProtocol`——类别盲查让所有 class 继承行都被错写成 `NSObjectProtocol`（而 protocol 继承行反而是被修对的）。`APINotesIndex` 的改名表按 Classes / Protocols / 值类型（Tags + Enumerators + Typedefs）三张隔离，`.other`（typealias 等 mangling 不定类别的引用）查值类型表再查 class 表、**永不查 protocol 表**。
- **CF `Ref` 剥除**是 APINotes miss 后的兜底规则：`Ref` 结尾且剥后名真实存在于归属表才重写（碰巧以 `Ref` 结尾的 ObjC 类不受影响），protocol 类别不适用（无 CF protocol 惯例）。
- 归属表（`moduleNamesByCName`）不拆类别——同名实体同模块，归属无歧义。

- **Swift interface 类型名**：对二进制依赖命中的每个 SDK 模块，经 sourcekitd `editor.open.interface`（带 `key.enablesubstructure`）生成含 ObjC 导入声明的 Swift 视角 interface，`InterfaceTypeNameExtractor` 从结构树提取 fully-qualified 类型名。**不用 SwiftSyntax**（体积裁定，见提案 A′ 节）；`.swiftinterface` 文件也不可用——它只含 Swift 声明，而本功能主要目标恰是 ObjC 导入类型。
- **APINotes**：`.apinotes` 是编译器视角的权威归属记录，`APINotesIndex` 把**每个列出的实体**（含无 `SwiftName` 改名、含 `SwiftPrivate`）的 C 名注册到声明模块，后写覆盖 interface 名。双向改名表（`swiftName(forCName:)` / `cName(forSwiftName:)`）只收非 `SwiftPrivate` 的改名实体。
- **ObjC 懒索引**：前两层 miss 才按依赖顺序逐 image 构造 MachOObjCSection `ObjCIndexing` 的 `ObjCInterfaceIndexer`、`prepare()`、并入 class / protocol / C struct / union 名 → image 模块名，命中即止。已索引 image 的结果缓存在 actor 内；索引失败的 image 记日志后丢弃不重试。依赖耗尽后 miss 只花一次字典探查。

## 管线分层（每层一个类型，一文件）

| 类型 | 职责 | 关键点 |
|---|---|---|
| `SDKPlatform` / `SDKSettings` | 平台 → SDK 路径、target triple、SDK 版本标识 | `SDKSettings.plist` 的 `Version` + `ProductBuildVersion` 组成缓存目录段 |
| `Subprocess` | `xcrun` / `xcode-select -p` 同步调用 | 非零退出码抛错，不再静默返回空串 |
| `SourceKitManager` | actor：sourcekitd 请求 + 响应转值类型 | dylib 路径从 active developer dir 派生（不再硬编码 `/Applications/Xcode.app`）；substructure 在 actor 内转成 `InterfaceDeclarationNode` 值树；`importedModuleNames` 是行级 import 扫描 |
| `InterfaceDeclarationNode` | substructure 的值类型投影 | `other` 节点的子树在转换时即丢弃 |
| `InterfaceTypeNameExtractor` | 值树 → fully-qualified 类型名（纯函数） | extension 节点用被扩展类型名（可带点）作限定前缀、自身不入清单——旧 SwiftSyntax 解析器的 extension 嵌套键错误在此结构性消失 |
| `SDKIndexer` | SDK 文件发现（秒级，零 sourcekitd） | `.swiftmodule` 目录 `skipDescendants`；同名模块先到先得（search path 优先级） |
| `APINotesFile` / `APINotesIndex` | `.apinotes` 解析与三张名表 | 修复历史 bug：C 名 → Swift 名映射的 `moduleName` 字段曾被写成 swiftName |
| `ModuleIndexCacheEntry` / `ModuleIndexCache` | per-module JSON 缓存 | 见下节 |
| `ModuleInterfaceIndexer` | 单模块管线：缓存 → 生成 → 提取 → 回写 | 单模块失败记日志返回 `nil`，不作废整轮索引；submodule interface 并入主模块条目（归属永远写顶层模块名） |
| `TypeDatabase` | actor：三源合并 + 懒索引 + 查询 | `register(moduleEntries:)` / `register(apiNotesIndex:)` / `register(dependencies:)` 三步公开为 package API，合并优先级因此可脱离 sourcekitd 单测 |
| `SwiftInterfaceBuilderTypeNameProvider` | 对接 `SwiftInterfaceBuilder` 的 provider | 模块过滤 = 依赖 image 名集合（`TypeDatabase.moduleName(forImagePath:)`：剥全部扩展名 + `libswift` 前缀） |

## 缓存布局

```
~/Library/Application Support/MachOSwiftSection/SDKIndexer/<platform>/<Version>-<ProductBuildVersion>/<module>.json
```

- 条目是**提取产物**（类型名清单 + submodule 名单），不存 interface 全文。
- 按 SDK 精确构建分目录：Xcode 升级换目录，陈旧条目自然失效（历史实现只按 platform 分目录且要求全 SDK 索引完成的标记文件，升级后继续吃旧数据）。
- `generatorVersion` 不匹配的条目按 miss 处理——提取行为变更时把 `ModuleIndexCacheEntry.currentGeneratorVersion` 加一。
- 全部缓存 I/O 是 best-effort：读写失败记日志、走重新生成，不向上抛错。

## 性能形态

- SDK 扫描只做文件发现，秒级；sourcekitd 生成只对**依赖过滤命中的模块**进行（历史实现对全 SDK 数百模块逐个生成、过滤在其后，首次索引小时级——这是该 target 当年被禁用的直接原因）。
- 首个未命中缓存的模块仍要付一次真实生成成本（大模块数秒到数十秒）；同 SDK 下第二次起走缓存。
- ObjC 懒索引把依赖 image 的解析成本压到「前两层查不到」的路径上；`ObjCInterfaceIndexer.prepare()` 解析全部成员 info，对单个大 framework 不算轻——若实测过重，未来方向是在 MachOObjCSection 加 name-only 快速路径。

## 降级行为（0005 事件化纪律的落点）

TypeIndexing 内部拿不到 `SwiftIndexEvents` 的 dispatcher（provider 协议面只有 `setup()`），所以降级全部走 `@Loggable` + `#log` 地板（subsystem `com.machoswiftsection.typeindexing`）：单模块 interface 生成失败、submodule 失败、`.apinotes` 解析失败、缓存读写失败、依赖 image ObjC 索引失败——都是「跳过该项 + 记日志」，绝不让一个模块的失败作废整个数据库。`setup()` 整体抛错（如 SDK 设置读不到）由 `SwiftInterfaceBuilder.prepare()` 的既有 `.renderingDegraded(source: .extraDataProvider)` 事件兜住。

## `@Loggable` 的形态约束（本模块特有的坑）

TypeIndexing 的类型都标 `@available(macOS 13.0, *)`（包部署下限是 macOS 10.15）。`@Loggable` 的**直接类型形态**会展开自带 availability 标注的 static stored `logger`，在显式 `@available` 的类型里被 emit-module 拒绝（"cannot be more available than enclosing scope"，单 target 编译只是 warning，整包 emit-module 是 error）。因此本模块一律用 **protocol 形态**：不标 availability 的 `fileprivate protocol XxxLogging {}` + 标 `@available(macOS 13.0, *)` 的 conformance extension。泛型 `TypeDatabase` 本来就只能用 protocol 形态，非泛型类型在这里也被迫用它。

## 与提案的差异

- **swift-dependencies 未引入**：提案 E 节的依赖清单含 `Dependencies`（历史实现用 `@Dependency` 注入 `SourceKitManager`）。落地改为把 `TypeDatabase` 的三个 `register` 步骤公开为 package API，测试直接驱动合并逻辑，不需要依赖注入框架——少一个 target 依赖。
- **兜底行级解析器未编写**：提案 A′ 允许 substructure 验证失败时退手写解析；scratchpad 探针实测 substructure 完整可用（ObjectiveC / CoreGraphics 两模块，节点带 kind + name + 嵌套 + extension），按提案「二选一定夺」条款只落主路。
- **`MachOObjCSection` 下限抬到 0.8.105**：泛型（`ObjCMetadataSource`，支持 `MachOFile`）的 `ObjCInterfaceIndexer` 在 0.8.105 才有，0.8.104 的只接受 `MachOImage`。
- **APINotes 归属注册比历史实现更宽**：历史实现只注册有 `SwiftName` 的实体；现在每个列出的实体（含 `SwiftPrivate`）都注册归属——`__C.X` 的 X 是 C 名，归属正确性与 Swift 侧可见性无关。改名表仍跳过 `SwiftPrivate`。

## 已知限制

- 整个 target 是 macOS-only（`#if os(macOS)` 全文件 + 依赖的 `.when(platforms: [.macOS])` 条件），且运行时要求 macOS 13+ 与本机 Xcode（sourcekitd）。
- Identifier 重写只覆盖类型引用（`printType` 的 nominal 路径）；成员级 SwiftName 改名（selector → Swift 方法名等）不在本案，另立提案。
- 依赖 image 的模块名取自 image 文件名（`libobjc.A.dylib` → `libobjc`），与 Swift module 名在少数 dylib 上不一致；影响仅限私有类型归属的显示名。
- CLI 的 provider 依赖集用 `.usesSystemDyldSharedCache`（被检查二进制的依赖按本机 dyld cache 解析）；跨版本 / 跨平台二进制的依赖解析不在 CLI 默认路径覆盖内。
