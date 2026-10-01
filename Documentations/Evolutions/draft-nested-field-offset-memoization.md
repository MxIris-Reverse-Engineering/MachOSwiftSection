# Draft - 进程内嵌套字段偏移展开的记忆化与匿名上下文判别符缓存

- **状态**: Accepted
- **创建日期**: 2026-09-30
- **最后更新**: 2026-10-01
- **所属愿景**: 无
- **关联提案**: [0056-visibility-regions](0056-visibility-regions.md)（RuntimeViewer 的语料按标记模式打印，所以每个类型都要付
  `printExpandedFieldOffsets` 的全价）、[0053-shared-cache-composition-and-eviction-registry](0053-shared-cache-composition-and-eviction-registry.md)（进程作用域存储的形态）
- **实现分支 / PR**: `feature/runtime-viewer/find-navigator`
- **配套文档**: [Internal/NestedFieldOffsetCycleGuard.md](../Internal/NestedFieldOffsetCycleGuard.md)、
  [Internal/TaskReports/2026-08-06-nested-field-offset-cycle-guard.md](../Internal/TaskReports/2026-08-06-nested-field-offset-cycle-guard.md)、
  [Internal/MachOCaches.md](../Internal/MachOCaches.md)（进程作用域 memo 的清单随本提案更新）

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
- 文档同批：`Internal/MachOCaches.md` 的进程作用域 memo 清单加上这两个（其中一个有 `removeAll()`）；
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
