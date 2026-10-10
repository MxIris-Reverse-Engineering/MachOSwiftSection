# Draft - 进程内嵌套字段偏移展开的记忆化与匿名上下文判别符缓存

- **状态**: In Progress
- **创建日期**: 2026-09-30
- **最后更新**: 2026-10-01
- **所属愿景**: 无
- **关联提案**: [0056-visibility-regions](0056-visibility-regions.md)（RuntimeViewer 的语料按标记模式打印，所以每个类型都要付
  `printExpandedFieldOffsets` 的全价）、[0053-shared-cache-composition-and-eviction-registry](0053-shared-cache-composition-and-eviction-registry.md)（进程作用域存储的形态）
- **实现分支 / PR**: `feature/runtime-viewer/find-navigator`
- **配套文档**: [Internal/NestedFieldOffsetCycleGuard.md](../Internal/NestedFieldOffsetCycleGuard.md)、
  [Internal/TaskReports/2026-08-06-nested-field-offset-cycle-guard.md](../Internal/TaskReports/2026-08-06-nested-field-offset-cycle-guard.md)、
  [Internal/Modules/MachOCaches.md](../Internal/Modules/MachOCaches.md)（进程作用域 memo 的清单随本提案更新）

## 摘要

RuntimeViewer 给一个镜像的全部类型建搜索语料时，对正在打印的进程采样：单个 Swift 类型的打印里 61% 落在
`RuntimeFieldLayoutBackend.storedFieldComments → expandedFieldOffsets → walkNested*FieldOffsets`，其中 9% 落在
`SymbolicDemangler.buildContextDescriptorMangling → InProcessContext.lookupSymbol(at:)`。前者对每个存储字段从运行时元数据
重新递归展开嵌套 struct / enum 的布局（深到 16 层），同一个字段类型（`String`、`UInt64`、`Builtin.BridgeObject`……）在每个
出现处都重算一遍，且故意绕开 demangle memo（`demangleTypeUncached`，每个 struct 字段节点通常 3 次 demangle）；后者在共享缓存
镜像上每查一个匿名上下文地址就逐个重建 dyld 镜像再线性扫镜像自己的 `LC_SYMTAB`（本地符号早已剥离，基本必落空），然后才
回落到 `AnonymousContextPrivateDiscriminatorIndex`。两处都没有任何缓存。本提案按 metatype 记忆化「一层展开」的结果、
遍历本身原样不动，给匿名上下文的判别符查询补一层按地址的记忆化。

## 方案

**1. 按 metatype 缓存单层展开记录，遍历不变。**

- 不缓存整棵树、不做渲染期剪枝（第二轮审查否掉的形态：节点漏记 `isLast` 会改 `├──` / `└──`，子树是否跨根共享又决定
  剪枝怎么写，两条路各有陷阱）。缓存的是 `walkNestedStructFieldOffsets` / `walkNestedEnumPayloadFieldOffsets` 对**一个
  metatype** 做的一层工作：
  - 类别（struct / enum 或 optional / 其它）；
  - struct：每条字段 `(fieldName, typeName, relativeOffset, childMetatype?, isLast)`——`isLast` 照今天按 `fieldEntries.count`
    算（名字读失败的字段不出记录但照样计数），`childMetatype` 是 `resolveNestedMetatype` 的结果，nil 表示不下钻；
  - enum：每条 payload `(fieldName, typeName, childMetatype, isLast, descends)`——只记解析成功的 payload（今天只给它们打行），
    `isLast` 照今天按 `payloadRecords.count` 算，`descends = !isIndirectCase`。
  遍历的结构、环判断（`enclosingMetatypes`）、深度判断、`#log` 告警全部原封不动，只是把每层的 descriptor / offsets /
  records / `nestedTypeName` / `resolveNestedMetatype` 换成查表。字节一致是构造出来的，连告警条数都不变；建一条记录不递归，
  没有 in-flight 问题；内存按唯一 metatype 各一份。
- 缓存形态照 0053 采纳的方案（不是它否掉的「`SharedCache` 常量键」）：`private static let processScopedStorage = Storage()`，
  `Storage` 内是 `@Mutex` 字典，键 `ObjectIdentifier(metatype)`——与 `SymbolicDemanglerCache` 的进程作用域 memo 同形。前提是
  进程不卸载镜像（RuntimeViewer 没有任何 `dlclose`）；进程内 metatype 全局唯一，泛型特化的元数据由运行时分配且不回收。
  它不受按镜像的驱逐管理，大小由进程碰到的唯一 metatype 数决定。记录在锁外建，一次 `withLock` 里 check-and-insert，
  先存者赢（内容确定，浪费上限是并行宽度乘一次构建）。
- **nil 的固化**：记录里 `childMetatype == nil`（struct 字段解析失败、enum payload 解析失败）会被缓存。定义那个类型的镜像
  在首次展开之后才加载的话，今天的遍历会开始下钻 / 打出 payload 行，缓存版不会。提供 `removeAll()`，宿主在加载镜像后调一次
  （RuntimeViewer 在 `loadImage` 之后调；宿主自己 `dlopen` 的镜像覆盖不到，但被引用类型所在的镜像通常早已随链接加载，
  近乎理论，写明即可）。`removeAll()` 带代数计数：跨越它的构建只在代数没变时写回，避免把旧结果写回去。
- `storedFieldComments` 里 `resolveFieldMetatype` 最多被调 3 次（末字段、type layout、展开入口），合并成一个局部变量；
  展开入口的 `?? getTypeByMangledNameInContext(mangledTypeName, in: machO)` 回退保留在入口——另两处没有这个回退，特化失败
  但裸名能解出的字段不能因合并丢掉展开。这一跳每个顶层字段仍付一次，不在缓存里。
- `expandedFieldOffsetTransformer` 不受影响：渲染仍逐行经它。RuntimeViewer 从不设置它。

**2. 匿名上下文判别符按地址记忆化。**

- `InProcessContext.privateDiscriminatorIdentifier(forAnonymousContextAt:)` 的结果对已加载镜像是稳定的（来自持有该地址
  的镜像自己的符号表或 `_symbolic` 索引）：加一层进程级 `@Mutex` 字典（同一个 `processScopedStorage`），键是描述符地址，
  值是判别符文本或「无」；命中直接构造 `.identifier` 节点，不再进 `MachOImage.symbol(for:)` 与 `MachOImage.image(for:)`。
  今天第一条路返回的是 `privateDeclName.children.first`，测试断言它总是 identifier。
- 只覆盖 `InProcessContext` 这条路；`MachOContext` 走 `Symbol.resolve(from:in:)`，前面已有按镜像的 `demangleContext` memo。
  进程级的 `nodeReferenceForContextOffset` 只覆盖 `demangleContext(for:)`，不覆盖 `demangleTypeUncached` 经 symbolic
  reference 走到的 `buildContextDescriptorMangling`，所以这一刀是必要的。
- 第 1 条落地后这一条仍有价值：`RuntimeTypeNameDemangling.node(forMetatype:)` 在遍历之外（bound generic 的名字渲染、
  `TypedDumper`）也走这条查找。
- 不动 MachOKit：fork 政策把性能缓存全放在 MachOKitExtensions（其提案 0001 明确推迟了 `MachOImage` 的 cached view
  与 `closestSymbol` 拷贝），而这里的查找在共享缓存镜像上本来就查不到东西，排序索引救不了它。

**3. 验证与文档。**

- 现有：`RecursiveNestedFieldOffsetExpansionTests`、`NestedFieldOffsetExpansionDepthLimitTests`、`SpecializedDumperFieldTypeTests`
  的运行时用例、`VisibilityRegionProjectionTests.inProcessPrintsProjectToEveryConfiguration`。
- 新增 fixture 与断言：记忆化路径与「关掉缓存」的路径渲染结果逐字节相等，覆盖**末 payload 解析失败**（特化泛型 enum 里
  `case b([T])` 就能触发）、**末字段名读失败**、间接 payload、环；判别符缓存前后节点相等且为 identifier；`removeAll()` 后重建。
- 渲染 A/B（`Scripts/run-rendering-ab-verification.py`）按 AGENTS.md 必跑。
- 文档同批：`Internal/Modules/MachOCaches.md` 的进程作用域 memo 清单加上这两个（其中一个有 `removeAll()`）；
  `Internal/NestedFieldOffsetCycleGuard.md` 补一句「每层从记录里读」。
- 计时：RuntimeViewer 分支上的 `CorpusBuildTimingProbe`（Release）对 Foundation / SwiftUI / libswiftCore 各跑
  `mcp` 与 `mcp-no-expanded-field-offset` 两个预设，前后对比与 `ru_maxrss` 记入决策日志。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-30 | Created as Draft | 用户在 RuntimeViewer 的 Find 语料构建性能提问轮里选定「记忆化 + 符号索引」；用户：「把要改的仓库建一个分支(feature/runtime-viewer/find-navigator)，然后开工」。 |
| 2026-09-30 | 符号查找不做排序索引，改为记忆化判别符结果 | 进程内查找先逐个重建 dyld 镜像再线性扫 `LC_SYMTAB`，共享缓存镜像的本地符号已剥离，必落空；MachOKit 上游文件按 fork 政策不改。 |
| 2026-09-30 | 第一轮审查：剪枝改为「保留行、剪子树」；缓存形态改按 0053；写明 enum payload 的 nil 不对称；修 TaskReports 链接 | 原稿把「剪掉节点」写成了字面意思，且引用 0053 的缓存形态与 0053 的决定相反。 |
| 2026-09-30 | 第二轮审查：放弃「结构树 + 渲染期剪枝」，改为按 metatype 缓存单层展开记录、遍历原样不动；缓存形态改成 0053 采纳的 `private static let` + `@Mutex` 字典（第一轮改正时仍写成了 0053 否掉的常量键 `SharedCache`）；记录记 `isLast`；展开入口保留 `?? getTypeByMangledNameInContext` 回退；`removeAll()` 带代数；补文档同步清单 | 审查指出树方案漏记 `isLast` 会在「末 payload 解析失败」时改掉 `├──` / `└──` 与祖先列，且子树是否跨根共享没定、两条路各有陷阱；单层记录方案把字节一致变成构造性的，也没有 in-flight 与剪枝问题。 |
| 2026-10-01 | Accepted | 与 [draft-concurrent-definition-printing](draft-concurrent-definition-printing.md) 同一次批准：用户在 RuntimeViewer 会话里批准开工，并在本仓库的会话里直接确认「两份都开工」。实现排在并发打印之后。 |
| 2026-10-01 | In Progress；修正配套文档链接 | 并发打印那份已提交（`9f5ffa92`），本提案接着做。配套文档写成了不存在的 `Internal/MachOCaches.md`，实际在 `Internal/Modules/MachOCaches.md`。 |
| 2026-10-01 | 记下 Release 下的「改前」计时：展开字段偏移约占打印时间一成，不是 Debug 采样的 61% | RuntimeViewer 会话用 `CorpusBuildTimingProbe` 在 JHs-Mac-Studio-Ultra 上量（RuntimeViewer `72913c3d`，Release，MachOSwiftSection `next` 514bb4bd，每个预设一个进程；机器上同时有其他会话，负载 16–55，绝对值偏噪）：Foundation（2559 个对象）`mcp` 3.72 s、`mcp-no-expanded-field-offset` 3.33 s，差 0.39 s，约 10.5%；SwiftUI（7378 个）51.95 s 对 47.0 s（两组负载不同，约 10%）；libswiftCore（660 个）各预设都在 0.82–0.86 s，差别在噪声内。收益因此比提案动机写的小，但仍按批准的范围实现；「改后」数字等提交后由 RuntimeViewer 会话用同样的预设再量。 |
| 2026-10-01 | 实现：`NestedFieldOffsetLevel` 与 `NestedFieldOffsetLevelMemo`（`SwiftDeclarationRendering/NestedFieldOffsetLevel.swift`）；宿主入口是 `RuntimeFieldLayoutMemo.removeAll()` | 记录分 `structFields` / `enumPayloads` / `notExpanded` 三种，构建逻辑从原来的两个遍历函数原样搬出；遍历里只剩基址、祖先列、深度、路径环守卫和日志。memo 是一把 `@Mutex` 守着字典与代数计数，记录在锁外建、先存者赢。宿主入口做成 `public`（不加 SPI）：`SwiftDeclarationRendering` 里给宿主的接口都是纯 `public`，RuntimeViewer 已经 import 这个模块。 |
| 2026-10-01 | `storedFieldComments` 只在三个消费方里至少一个要用时才解析字段的 metatype，且只解析一次 | 三个条件（最后一个字段要算结束偏移、要展开、要打 type layout）取并集。直接提到函数开头无条件解析，会让原来一次都不解析的配置（比如只开字段偏移的非末字段）多出一次解析。展开入口的 `?? getTypeByMangledNameInContext` 回退留在展开那段里。运行时展开入口原来的 `machO == nil` 分支没有调用方，随之删掉。 |
| 2026-10-01 | 判别符记忆化：把 `privateDiscriminatorIdentifier` 改成私有协议 `SymbolLookupContext` 的 requirement，只有 `InProcessContext` 换成查表 | 原来它是协议扩展里的方法，经 `as? SymbolLookupContext` 调用时静态派发，`InProcessContext` 覆盖不了。只记 `identifier` 的文本，命中时重建同样的节点，「没有判别符」也记；表放在 `SymbolicDemanglerCache` 的进程级存储里。不提供清除入口：查的是已经在内存里的匿名上下文，答案不会变。 |
| 2026-10-01 | 测试不新建 fixture；加一个只给测试用的 `NestedFieldOffsetLevelMemo.isBypassed`（`package` 级 `@TaskLocal`） | SymbolTestsCore 的 `ValueSpec<String>` 已经同时有：最后一个 payload `pair` 解析不出（前一行 `reference` 因此画 `├──`）、`indirect` payload、`ReferenceSpec` ↔ `ValueSpec` 的环；改 SymbolTestsCore 会牵动全部基线。「末字段名读失败」编译器产不出来，靠构造保证：记录里的 `isLast` 与原来按同一个表达式、对全部字段记录计数。绕过开关是提案「关掉缓存的路径」所需，`@TaskLocal` 只影响当前任务树，不碰并行的其它套件。判别符缓存的测试以 AppKit 私有类的 Objective-C 运行时名字为独立真值，冷热两次都比。 |
| 2026-10-01 | 验证 | 新测试与相关既有套件（嵌套展开、深度上限、特化字段类型、可见性区域投影、两个判别符套件、并发打印）全过。全量 `swift test --skip IntegrationTests` 2168 个测试全过，原始退出码 0，known issue 仍是 `SymbolicManglingIndexTests` 那一条。release + TSan 跑 `ConcurrentDefinitionPrintingTests`（标记模式打印含展开字段偏移，多线程同时查 memo）与 `NestedFieldOffsetMemoizationTests`：0 条报告，退出码 0。渲染 A/B 对 `9f5ffa92`（并发打印那份）：92 对逐字节一致，SKIPPED 的仍是 iOS 15.5 模拟器 SwiftUI / WidgetKit 那 4 对（本地 MachOKit `next` 的既有问题）。A/B 的 MachOImage 腿默认不开展开字段偏移，所以另用 `RenderingVerificationTests` 打开全部选项（含 `expandedFieldOffsets`）对 Combine、SwiftData、WidgetKit、ActivityKit 两侧各跑一遍：16 对逐字节一致，进程内那几份带 17 到约 7800 行展开行。SwiftUI / SwiftUICore 没放进这一轮：该工具记着它们在开展开字段偏移时有既有的栈溢出。`NestedFieldOffsetMemoizationTests` 加进 CI 的主过滤列表。 |
| 2026-10-01 | 「改后」计时：省 4–10% | 宽度 1（RuntimeViewer 会话的 `CorpusBuildTimingProbe` corpus 模式，Release，每次新进程，三档交替各两轮，负载 5–9；A = `next` 514bb4bd，B = `9f5ffa92`，C = `937172ef`，RuntimeViewer Core 同为 `8bbb46cf`、打印宽度 1，其余依赖逐项一致；原始数据在 `/Volumes/DerivedData/Agents.noindex/claude/ProbeRuns/20261001-163445-concurrent-printing/`；用 `nm` 确认只有 C 带 `RuntimeFieldLayoutMemo`）：libswiftCore B 1.03/1.02 s → C 0.98/0.99 s（−4%）；Foundation B 4.19/4.15 s → C 3.80/3.98 s（CPU 3.80/3.81，约 −9%）；SwiftUI B 38.75/45.59 s → C 36.71/37.94 s（CPU 35.85/37.86，约 −7% 到 −10%）。与「展开字段偏移约占打印时间一成」的分项一致。 |
| 2026-10-08 | PR #131 review 第 12 条（缓存会记住「这个字段类型解析不出」）本库不修，登记为 [ReviewAdjudications.md](../Internal/ReviewAdjudications.md) A54；转 RuntimeViewer | 这是方案里写明的取舍，清除入口 `RuntimeFieldLayoutMemo.removeAll()` 交给宿主在加载镜像后调用。review 查到 RuntimeViewer 的 find-navigator 分支只在它自己 `dlopen` 之后调用，被检查的进程自己加载的镜像不会触发；`DyldUtilities.observeDyldRegisterEvents()` 写好了 dyld 加载镜像的回调但从没被调用，那边要注册它并在回调里调用 `removeAll()`。 |
