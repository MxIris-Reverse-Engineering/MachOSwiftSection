# 0065 - 并行打印下的惰性索引提速：同一地址的符号按归属查表、属性包装器目录锁外查找

- **状态**: Implemented
- **创建日期**: 2026-10-13
- **最后更新**: 2026-10-13
- **关联提案**: [0066-concurrent-definition-printing](0066-concurrent-definition-printing.md)（同版本内并行打印的前提）、[0053-shared-cache-composition-and-eviction-registry](0053-shared-cache-composition-and-eviction-registry.md)（`SharedCache` 的现行形态）
- **实现分支**: `feature/faster-lazy-definition-indexing`

## 摘要

RuntimeViewer 的 Find 语料要把一个镜像的全部定义打印一遍（进程内 `MachOImage`，每镜像 4 路并行），打印触发的惰性索引才是大头，真正渲染文本只占约两成。2026-10-13 在 M1 Max 上用 RuntimeViewer 的计时探针测 AppKit、SwiftUI、SwiftUICore、libswiftCore、Foundation 五个镜像：语料合计 Release 约 20 s、Debug 约 104 s。整轮采样（占语料时间）：

- `ExtensionDefinition.runIndexingPass` 给 resilient witness 找实现符号的 `_symbol(for:typeName:visitedNodes:)` 占 **50–53%**（Release、Debug 一致）；
- Release 下 `SharedCache.resolve` 的 `os_unfair_lock` 慢路径占 **25%**，其中约四分之三来自上一条里逐个候选的 `demangledNodeReference`；
- `TypeDefinition` 索引 13–20%，其中 `PropertyWrapperTypeCatalog.evidence` 拿着 `NSLock` 搜依赖镜像的导出表，锁等待约 **8%**。

修完：Release 约 20 s → 8.4 s，Debug 约 104 s → 53 s。输出逐字节不变。

## 方案

**1. 同一地址的符号按归属查表（主因）。** 临时计数（SwiftUI，Debug）：`_symbol` 调用 15,047 次，平均每次 451 个候选、平均第 242 个才命中；共检查 365 万次，涉及的不重复符号只有 17,852 个，每个平均被检查 204 次。原因是 identical code folding：许多类型内容相同的 witness 实现（`_destroySelf`、`Owup` 一类）被合并到同一地址，一个地址挂着成百上千个别名，每个 conformance 都要从头把这串别名逐个 demangle、`first(of: .protocolConformance)` 全树搜索、打印类型名再比较——对别名组大小是平方级。

`SymbolIndexStore.symbols(for:ownedBy:ownerKind:printedWith:in:)` 回答「这个地址上、归属打印为 T 的符号，按 `symbols(for:in:)` 的顺序」。归属两种（`SymbolOwnerKind`）：`.conformingType` 是符号树里第一个 `protocolConformance` 的第一个子节点，`.protocol` 是第一个 `protocol` 节点；打印预设由调用方给。每个「地址 + 规则 + 预设」第一次被问到时把该地址的全部行分组一次（锁外计算，锁内插入，先到者胜），之后每次查询是两次字典查找。分组表挂在该镜像的 `Storage` 上，随它一起淘汰。同一写法的四处都改用它，各自只剩已认领节点（`visitedNodes`）的过滤：

| 调用点 | 规则 | 预设 |
|---|---|---|
| `ExtensionDefinition` 索引 | `.conformingType` | `.interfaceTypeBuilderOnly` |
| `ProtocolDefinition` 索引 | `.protocol` | `.interfaceTypeBuilderOnly` |
| `ProtocolConformanceDumper.demangledSymbol` | `.conformingType` | `.interfaceType` |
| `ProtocolDumper.validNode` | `.protocol` | `.interfaceType` |

规则与原实现逐条相同：同一个打印预设、同一个「树里第一个节点」、同一个候选顺序、返回值同样是带查询偏移的独立 `DemangledSymbol`、demangler 拒绝的行同样跳过。

**2. 属性包装器目录锁外查找。** `PropertyWrapperTypeCatalog.evidence(forWrapperCandidate:)` 锁内只读写按前缀的结论缓存；导出表搜索与其中的 demangle 放到锁外，并发的首次查询各算各的、先写入者胜（结论是导出表的纯函数，谁写都一样）；依赖闭包的查找表用另一把锁只建一次。

锁去掉之后剩下的开销是建依赖闭包本身：`InProcessDependencyLocator` 每找一个依赖都调 `MachOImage(name:)`，后者把进程里全部已映射镜像的路径逐个拆一遍，一个几百个依赖的闭包、上千个映射镜像就是几十万次拆分，其余打印线程都在等它。定位器改为构造时遍历一遍已映射镜像建「bare name → 镜像」表，同名取第一个，与 `MachOImage(name:)` 的选择逐个一致；代价是构造之后才映射的镜像它看不到（`DependencyClosure(root: MachOImage)` 每次新建定位器）。MachOKit 的 `MachOImage(name:)` 按 fork 政策不动。

**3. `SharedCache` 读路径：不改。** 第 1 条修完重测，锁的慢路径只剩语料时间的 0.7%–1.7%，`SharedCache.resolve` 在语料打印内部只占 2%（其余是加载阶段建符号索引）。见决策日志。

**验证。**

- `SymbolOwnerGroupingSwiftUITests`（MachOSymbolsTests）：进程内 SwiftUI 的每个多名字地址，两种规则 × 两种预设，新查询与旧的逐个符号规则（测试里的参照实现：按名字 demangle、取归属、打印、比较）给出同样的名字、偏移与节点；另在一份不进缓存的新建索引上让 8 个任务同时首次查询同一地址，答案全部一致。
- `PropertyWrapperTypeCatalogLockTests`（SwiftDeclarationRenderingTests）：一个前缀的搜索被卡住时，另一个已有结论的前缀必须立刻返回；旧写法下 10 秒超时失败，新写法通过。没有结论的前缀也被记住、不再搜索。
- `InProcessDependencyLocatorTests`（MachODependenciesTests）：进程里每个已映射镜像的路径（加几个不存在的拼写），定位器与 `MachOImage(name:)` 指向同一个镜像。
- 现有测试套件；AGENTS.md 规定的渲染 A/B（三种 reader 路径，逐字节一致）；RuntimeViewer 探针前后对照。

**未询问即采用的假设**：分组表只按需建、不在符号索引构建时预算（多数镜像的大多数地址永远不会被问到）；不改变 `first(of:)` 在符号树上的语义（AGENTS.md 指出它对成员树往往不对，但改它会改输出，不在本提案内）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-13 | 创建并置为 Accepted：三处都做，Debug 构建下未优化泛型的固有开销（约 28%）先不处理 | 用户在 RuntimeViewer 会话中报「Find 构建语料还是太慢」，看过上面的测量与采样后选定「三处都做」「Debug 专项先不管」。 |
| 2026-10-13 | 查表做成两种归属规则 × 任意打印预设，同一写法的四处一起改；`ClassDumper.validNode` 与 `OverrideSymbolMatcher` 不改 | 横向排查找到 `ProtocolDefinition` 索引与两个 dumper 用的是同一种「在别名里逐个比较」的写法（采样里 `ProtocolDefinition` 约占语料时间 1%，dumper 不在 RuntimeViewer 的路径上，但 `dump` 同样平方级）。后两处按声明上下文**结构相等**认领，规则不同，实测各占 0.4%–0.5%。 |
| 2026-10-13 | 第 2 条扩大到依赖定位：`InProcessDependencyLocator` 改为构造时建表 | 目录的锁去掉后重采样（负载约 40）：`TypeDefinition` 索引占 39%，其中目录 25%，几乎全是 `resolvedDependencyLookups()`——一个线程建闭包，其余线程等它；建闭包的时间又几乎都在 `MachOImage.init(name:)`。改后 libswiftCore 的语料 1.2 s → 0.4 s。 |
| 2026-10-13 | 第 3 条不改 `SharedCache` | 第 1 条修完后，低负载采样里全部锁慢路径占语料时间 1.7%（`SharedCache.resolve` 自己 0.7% 以下）；`SharedCache.resolve` 的包含时间在语料打印内部只占 2%，其余 28% 是加载阶段在后台队列上建符号索引，不在语料构建里。 |
| 2026-10-13 | ReviewAdjudications A61 第四处（`PropertyWrapperTypeCatalog`）改判为修 | A61 只考虑了「小栈调用方持锁切线程」，没考虑长临界区本身：并行打印的调用方都在大栈上、不切线程，照样排在别人的导出表搜索后面。 |
| 2026-10-13 | 验证通过 | 全量 `swift test --skip IntegrationTests`（JHs-Mac-Studio，`USING_LOCAL_DEPENDENCIES=1`）：2442 个测试 / 468 个套件，原始退出码 1，失败的只有两条 `MultiPayloadEnumDescriptorCacheTests`，在基线 next `5dca3331` 的 release 测试包上同样两条、同样失败点。渲染 A/B（基线为钉在 `5dca3331` 的 detached worktree，两侧共用本地兄弟依赖与同一份 `Package.resolved`，经构建队列各预构建一次 release 后带 `--skip-build`）：**90 对全部逐字节一致**——归档 cache 15.5 与 26.6.2 各 12 对，iOS 15.5 / 18.5 / 18.6 / 26.5 模拟器 42 对，MachOImage 腿 24 对；iOS 15.5 缺的三个框架与 iOS 27.0 / 27.1 模拟器（框架在 cache 里）按设计跳过。 |
| 2026-10-13 | 实测（RuntimeViewer 探针，进程内，每镜像 4 路，M1 Max，基线与候选交替两轮，负载 6–13）：Release 合计 20.3 s → 8.4 s（SwiftUI 8.8 → 2.7，SwiftUICore 6.0 → 1.9，AppKit 2.9 → 2.4，Foundation 1.4 → 1.0，libswiftCore 1.2 → 0.4），CPU 64.5 s → 30 s；Debug 合计 103.7 s → 52.6 s（SwiftUI 47.0 → 18.1，SwiftUICore 32.2 → 12.3） | 同一份 RuntimeViewerCore（next `4fc214ad`）与锁文件，只把 MachOSwiftSection 用 SwiftPM edit 模式换成本分支。修后采样：`ExtensionDefinition` 索引从 53% 降到 7%，锁慢路径合计 1.7%；剩下的大头是 ObjC 打印（约四分之一）、`TypeDefinition` 索引（约五分之一）和字段布局（约 8%）。 |
| 2026-10-13 | 落地为 0065，Implemented：合入 next | 配套文档不另写：实现说明落在 [Modules/MachOSymbols.md](../Internal/Modules/MachOSymbols.md)「同一地址上的符号按归属分组」与 [Modules/MachODependencies.md](../Internal/Modules/MachODependencies.md)「定位器」，规则进了 AGENTS.md；术语表无新增（`SymbolOwnerKind` 是 API 名，不是新概念）。演进账本第 91 节。 |
