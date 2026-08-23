# TypeIndexing：`__C` 模块归属索引管线实现说明

> 本文是 evolution 提案 [0009](../Evolutions/0009-type-indexing-revival.md)（TypeIndexing 重启）与 [0010](../Evolutions/0010-community-type-mapping-bundles.md)（补充映射包）的配套实现说明，面向维护者：记录实际落地的管线、与提案的差异、缓存布局与已知降级。

## 这个模块做什么

打印管线遇到 `__C` / `__ObjC` module 节点时（`NodePrintable.printModule`），会拿 sibling identifier 问 delegate 的 `moduleName(forTypeName:)`（带 `Ref` 后缀剥除回退）。`TypeIndexing` 提供唯一的 provider 实现 `SwiftInterfaceBuilderTypeNameProvider`：挂上它之后，`__C.NSString` 打印为 `Foundation.NSString`。CLI 入口是 `swift-section interface --resolve-c-module-names`（用户自备补充映射经 `--supplementary-apinotes` 追加）；库入口是 `builder.addExtraDataProvider(SwiftInterfaceBuilderTypeNameProvider(machO:dependencies:supplementaryAPINotesURLs:))`（末参数带默认值）。

## 查询数据流（三源合并，优先级从高到低）

```
moduleName(forTypeName: "NSString")
    1. moduleNamesByTypeName   ← Swift interface 类型名（低）+ APINotes C 名与 SwiftName 拼写
                                  （高，后写覆盖；SDK APINotes → 用户补充文件按传入序）
    2. objcModuleNamesByTypeName ← ObjC 元数据懒索引（最低，只补缺）

swiftName(forCName: "CFStringRef", category:)   ← identifier 重写（见下节）
    1. APINotes 改名表（按声明类别隔离；补充包条目同表、后写覆盖）
    2. CF `Ref` 剥除规则（剥后名必须存在于归属表；protocol 类别不适用）
```

## Identifier 重写：C 拼写 → Swift 拼写（用户指正驱动）

module 名替换之外，`__C` 类型的 **identifier 本身**也可能是 Swift 里不存在的 C 拼写——首轮端到端输出的 `CoreFoundation.CFStringRef` 被用户指正：`CFStringRef` 是 C 侧 typedef 名，ClangImporter 剥 `Ref` 后缀桥接为原生 class `CFString`。落地为打印侧对 `swiftName(forCName:category:)` 的消费（该协议方法此前零消费者）：

- **只在 module 解析成功时重写**（`printModule` 返回是否命中），未解析的 `__C.CFStringRef` 绝不渲染成半吊子 `__C.CFString`。
- **查询必须带声明类别**（`CImportedTypeNameCategory`，由 mangling 的 `Node.Kind` 映射：class / protocol / 值类型 / other）。这是第一版合并改名表当场踩出的回归：ObjC 的 class `NSObject` 与 protocol `NSObject` 同名，APINotes 只把 **protocol** 改名为 `NSObjectProtocol`——类别盲查让所有 class 继承行都被错写成 `NSObjectProtocol`（而 protocol 继承行反而是被修对的）。`APINotesIndex` 的改名表按 Classes / Protocols / 值类型（Tags + Enumerators + Typedefs）三张隔离，`.other`（typealias 等 mangling 不定类别的引用）查值类型表再查 class 表、**永不查 protocol 表**。
- **CF `Ref` 剥除**是 APINotes miss 后的兜底规则：`Ref` 结尾且剥后名真实存在于归属表才重写（碰巧以 `Ref` 结尾的 ObjC 类不受影响），protocol 类别不适用（无 CF protocol 惯例）。
- 归属表（`moduleNamesByCName`）不拆类别——同名实体同模块，归属无歧义。
- **`Ref` 规则对整个 `objc_bridge`（`CF_BRIDGED_TYPE` / `CV_BRIDGED_TYPE` 等各框架宏别名）家族通用**，不是 CoreFoundation 专属——判据只是「剥后名存在于索引」。CG / CV / CM 探针实测（链 CoreGraphics + CoreVideo + libswiftCoreMedia 的 dylib）：同一类型**两种 mangling 形态并存**——符号签名用 C typedef 名（`__C.CGContextRef`），字段元数据用剥后名（`__C.CGContext`）——分别由剥除规则与归属表直查覆盖，全部解析为 `CoreGraphics.CGContext` / `CoreVideo.CVBuffer` / `CoreMedia.CMFormatDescription`（`CVPixelBuffer` 在 mangling 层已归一为 `CVBuffer`，输出如实反映 ABI）。CoreMedia 仅以 `libswiftCoreMedia` overlay 形式出现在依赖里，`libswift` 前缀剥除使过滤命中其 SDK 模块——overlay-only 依赖场景成立。

- **Swift interface 类型名**：对二进制依赖命中的每个 SDK 模块，经 sourcekitd `editor.open.interface`（带 `key.enablesubstructure`）生成含 ObjC 导入声明的 Swift 视角 interface，`InterfaceTypeNameExtractor` 从结构树提取 fully-qualified 类型名。**不用 SwiftSyntax**（体积裁定，见提案 A′ 节）；`.swiftinterface` 文件也不可用——它只含 Swift 声明，而本功能主要目标恰是 ObjC 导入类型。
- **APINotes**：`.apinotes` 是编译器视角的权威归属记录，`APINotesIndex` 把**每个列出的实体**（含无 `SwiftName` 改名、含 `SwiftPrivate`）的 C 名注册到声明模块，后写覆盖 interface 名。双向改名表（`swiftName(forCName:)` / `cName(forSwiftName:)`）只收非 `SwiftPrivate` 的改名实体。
- **ObjC 懒索引**：前两层 miss 才按依赖顺序逐 image 构造 MachOObjCSection `ObjCIndexing` 的 `ObjCInterfaceIndexer`、`prepare()`、并入 class / protocol / C struct / union 名 → image 模块名，命中即止。已索引 image 的结果缓存在 actor 内；索引失败的 image 记日志后丢弃不重试。依赖耗尽后 miss 只花一次字典探查。

## 补充映射：私有框架的外部知识入口（提案 0010）

AttributeGraph 这类私有框架在 SDK 里没有任何模块（无头文件、无 swiftmodule、无 apinotes），三源全 miss；而 `AG_SWIFT_NAME(Graph)` 的改名只活在头文件 attribute 里、二进制零残留，原理上不可恢复。[提案 0010](../Evolutions/0010-community-type-mapping-bundles.md) 的补充映射就是这份外部知识的入口：映射用**标准 `.apinotes` 格式**表达（零新格式，直接进 `APINotesIndex` 既有管线，类别隔离天然携带），**全部由用户自备**——宿主经 provider 的 `supplementaryAPINotesURLs:`、CLI 经 `--supplementary-apinotes`（可重复，文件或目录）传入；库自身不内置任何映射（首版曾内置 SPM resource bundle，review 后按用户裁定移除：`Bundle.module` accessor 在 bundle 缺失时 fatalError，而 `build-executable-product.sh` 只分发裸二进制，分发出去一用就崩——纯用户自备把整个 resource 分发问题结构性消掉）。覆盖顺序：SDK APINotes → 用户文件按传入序，`APINotesIndex.register(files:)` 的后写覆盖即优先级实现。面向用户的公开指引见 [SupplementaryTypeMappings.md](../SupplementaryTypeMappings.md)。

**同一个 CF-bridged 类型有三种 mangling 形态**（AG probe 实测：手造 clang module 复刻 `objc_bridge` + `swift_name` 声明，5 处引用全解析为 `AttributeGraph.Graph` / `.Subgraph`），各自的覆盖机制不同：

1. **typedef 名**（`__C.AGGraphRef`，符号签名，typealias node → `.other` 类别）：`Typedefs` 条目的改名表命中。
2. **storage / tag 名**（`__C.AGGraphStorage`，字段元数据的 foreign **class** descriptor，`.objcClass` 类别）：条目按 C 语义归 `Tags`（值类型表），所以 `.objcClass` 查询在 class 表 miss 后**回退值类型表**。安全性论证：C 的 tag namespace 与 ObjC class namespace 理论上可同名共存，但 class 表先查先赢，「改名只在 tag 侧、同名 ObjC class 又真被引用」无已知真实实例；protocol 表仍绝不回退（`NSObject` 隔离不动）。系统 dyld cache 的 SwiftUI 里实测存在孤立的 `AGGraphStorage` descriptor 名，即此形态。
3. **导入名直出**（`__C.Graph`，probe 实测：消费方二进制 emit 的 foreign descriptor 记录的是 **swift_name 之后**的拼写）：identifier 已是最终拼写、无需也无从改名，缺的只是归属——因此 `TypeDatabase` 的归属同步（`registerAttribution(fromAPINotesIndex:)`）把改名反查表（`cNamesBySwiftName`）的 **SwiftName 拼写也登进归属表**（带点的嵌套改名如 `ProcessInfo.ActivityOptions` 不会以单 identifier 出现，跳过）。此登记对 SDK APINotes 同样生效（`NSDecimal → Decimal` 的 `__C.Decimal` 引用同理受益）。

映射内容立场：**宁缺毋滥**——条目错了输出跟着错，公开指引要求每条改名都有头文件级一手证据（重建头文件声明或 OpenGraph 这类文档化项目）。

## 管线分层（每层一个类型，一文件）

| 类型 | 职责 | 关键点 |
|---|---|---|
| `SDKPlatform` / `SDKSettings` | 平台 → SDK 路径、target triple、SDK 版本标识 | `SDKSettings.plist` 的 `Version` + `ProductBuildVersion` 组成缓存目录段 |
| `Subprocess` | `xcrun` / `xcode-select -p` 同步调用 | 非零退出码抛错，不再静默返回空串 |
| `SourceKitManager` | actor：sourcekitd 请求 + 响应转值类型 | dylib 路径从 active developer dir 派生（不再硬编码 `/Applications/Xcode.app`）；substructure 在 actor 内转成 `InterfaceDeclarationNode` 值树；`importedModuleNames` 是行级 import 扫描 |
| `InterfaceDeclarationNode` | substructure 的值类型投影 | `other` 节点的子树在转换时即丢弃 |
| `InterfaceTypeNameExtractor` | 值树 → fully-qualified 类型名（纯函数） | extension 节点用被扩展类型名（可带点）作限定前缀、自身不入清单——旧 SwiftSyntax 解析器的 extension 嵌套键错误在此结构性消失 |
| `SDKIndexer` | SDK 文件发现（秒级，零 sourcekitd） | `.swiftmodule` 目录 `skipDescendants`；同名模块先到先得（search path 优先级） |
| `APINotesFile` / `APINotesIndex` | `.apinotes` 解析与三张名表 | 修复历史 bug：C 名 → Swift 名映射的 `moduleName` 字段曾被写成 swiftName；`register(files:)` 可追加（后写覆盖，补充包优先级的实现点） |
| `SupplementaryAPINotesLoader` | 用户自备补充映射的枚举与解析（提案 0010） | 路径可为文件或目录（目录取浅层 `.apinotes` 按文件名排序）；解析失败逐文件记日志跳过；CLI 侧另有 stderr 预检警告 |
| `ModuleIndexCacheEntry` / `ModuleIndexCache` | per-module JSON 缓存 | 见下节 |
| `ModuleInterfaceIndexer` | 单模块管线：缓存 → 生成 → 提取 → 回写 | 单模块失败记日志返回 `nil`，不作废整轮索引；submodule interface 并入主模块条目（归属永远写顶层模块名）；**任一 submodule 失败则本轮照常返回但不写缓存**（缓存无完整性标记，写了就把缺口固化到 SDK/generator 版本变化为止——review 发现 4）；sourcekitd 调用经 `InterfaceGenerator` 闭包注入缝，缓存纪律可脱离 sourcekitd 单测 |
| `TypeDatabase` | actor：三源合并 + 懒索引 + 查询 | `register(moduleEntries:)` / `register(apiNotesIndex:)` / `register(supplementaryAPINotesFiles:)` / `register(dependencies:)` 四步公开为 package API，合并优先级因此可脱离 sourcekitd 单测；task group 结果按**完成序**到达，注册前经 `entriesInDiscoveryOrder` 重排回 SDK 发现序（后写覆盖 + 完成序 = 同名归属跨两次运行不确定——review 发现 7）；`moduleName(forImagePath:)` 的扩展名剥除循环带不动点守卫（前导点名字如 `.hidden` 是剥除不动点，曾死循环——review 发现 5） |
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
- **声明模块完全不在依赖列表里时三层全 miss**：类型只出现在签名 / 元数据、二进制没有对该框架的任何符号引用时，链接器不会记 `LC_LOAD_DYLIB`（探针实测：只声明 `CGContext` 字段而不调 CG 函数，CoreGraphics 就不在依赖里），依赖过滤自然不会索引该模块，`__C.` 原样保留。真实二进制里用一个类型几乎必调它的函数（或至少链 overlay），所以实际影响很小；若将来遇到，可选增强是把过滤集合扩到依赖闭包（传递依赖）。用户自备的补充映射（提案 0010）不受此限：它不参与依赖过滤，条目覆盖到就能解析——SDK 里根本没有模块的私有框架（AttributeGraph）正是靠它。
