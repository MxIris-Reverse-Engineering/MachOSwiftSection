# Draft - 定义对象的并发打印安全：索引前置，打印期不再写定义

- **状态**: In Progress
- **创建日期**: 2026-09-30
- **最后更新**: 2026-10-01
- **所属愿景**: 无
- **关联提案**: [0019-large-stack-executor-and-cross-version-parallelism](0019-large-stack-executor-and-cross-version-parallelism.md)（跨版本并行；
  同版本内并行当时明确不做）、[0002-declaration-model-descriptor-slimming](0002-declaration-model-descriptor-slimming.md)（定义对象的惰性索引形态与物化纪律）
- **实现分支 / PR**: `feature/runtime-viewer/find-navigator`
- **配套文档**: [Internal/Modules/SwiftDeclaration.md](../Internal/Modules/SwiftDeclaration.md)（`isIndexed` 的说明随本提案更新）

## 摘要

`SwiftDeclarationPrinter` 本身是 `Sendable`（可变状态全在 `@Mutex` 后面），但它打印的 `TypeDefinition` /
`ProtocolDefinition` / `ExtensionDefinition` 不是：三者在打印时才惰性 `index(in:)`，守卫是无锁的 check-then-set；
`printIncludedTypeDefinition` 与 diff 渲染的 `printTypeHeader` 每次打印都写 `typeDefinition.attributes`；父类型打印会顺带
打印嵌套子类型、协议打印默认实现扩展、扩展打印其中的类型与协议。AGENTS.md 因此写明「intra-version parallelism is not safe」。

**这个竞争今天已经在发生，不只是并行打印的前提。** RuntimeViewer 的 `RuntimeSwiftSection` 是 actor，显示路径
`interface(for:)` 与语料路径 `corpusEntry` 都经 `printInterface` `await` 到 printer 的 nonisolated 入口；本库没有启用
`NonisolatedNonsendingByDefault`，所以打印期间 actor 被释放，两条打印在不同线程上真并行，且共享同一批定义。语料在后台一建
就是几分钟，期间用户点开同一镜像的类型（或父类型在语料里内联打印嵌套子类型时用户正好点开它），两边同时对同一个定义
`index(in:)`、同时写数组与 `attributes`——数据竞争，可到堆损坏级别。`next` 上 MCP、导出、多文档共用 `.local` 引擎走的是
同一条路径，只是时间窗小。本提案把它修掉，并以此解除 `MachOImage`（进程内）读者下同版本内并发打印的限制；
`MachOFile` 共用一个 `FileHandle` 的问题不在本提案。

## 方案

- **索引一次、并发等待，同步阻塞形态**：三个 `index(in:)` 的函数体今天一个 `await` 都没有，改成**同步函数**（去掉 `async`），
  让「索引体内没有挂起点」由编译器保证；`isIndexed` 改为受锁保护的三态（未索引 / 索引中 / 已索引）加一个带错误通道的
  promise（形态照 `SharedCacheBuildPromise`，含同线程重入的 `precondition`）。锁是**进程级一把**加一张按 `ObjectIdentifier(定义)`
  的 in-flight 表，临界区只翻状态与取 promise，不给每个定义各挂一个 `Mutex`（0002 刚给定义瘦过身，每个定义一次堆分配不值）。
  首个调用者认领后在自己的线程里跑索引体（它已带大栈执行器偏好），后来者在 promise 上阻塞等待。不死锁的不变量：
  认领 → 索引体 → fulfill 之间没有挂起点（编译器保证），索引体不索引别的定义（今天成立：体内只经 `SharedCache` 取 catalog
  或符号表；用 precondition 守住）。抛错时状态回到未索引、错误广播给全部等待者，下次调用重试（`ExtensionDefinition+Indexing`
  今天就依赖这条重试语义）。不选异步等待（continuation）：它不占线程，但要多一套能携带错误的 promise，而同步形态的前提今天全部成立。
- **打印期不写定义**：`attributes` 按 AGENTS.md 的物化纪律改为**局部变量**——两个打印点各算一次
  `let attributes = TypeAttributeInferrer().infer(for: typeDefinition)` 往下传，删掉存储属性。不做计算属性：纪律明写
  「Never a per-access computed property」，且 `TypeAttributeInferrer` 在 `SwiftAttributeInference`，该模块依赖 `SwiftDeclaration`，
  `TypeDefinition` 自己调不到它。输出不变（今天也是每次打印、在索引之后重算；它读的 `conformingProtocolNames` 由
  `SwiftDeclarationIndexer.prepare()` 填，不受影响）。两处写入点一起改：`SwiftDeclarationPrinter.printIncludedTypeDefinition`
  与 `SwiftDeclarationPrinter+DiffRendering.printTypeHeader`。源码兼容：`public package(set) var attributes` 的读面消失，
  仓库内无其它使用者；下游要的话在 `SwiftAttributeInference` 里留一个转发扩展。`TypeAttributeInferrer` 读
  `typeDefinition.extensions` 的三处是死读（该属性从未被赋值），删掉；顺带记下被它掩盖的缺口：声明在扩展里的
  `buildBlock` 今天识别不到 `@resultBuilder`。
- **Sendable**：三个定义类标 `@unchecked Sendable`，理由写在类型上：「除索引状态外只在索引期间写、且索引受锁」。本库是
  Swift 6 模式，不标的话调用方在任务组里传不进去。
- **打印路径的其余共享可变状态**：`Sources/Output` 全量核对，打印路径写定义的只有上述两处；`ParentClassVTableCache` 是
  每次索引各一份的局部值类型；`SharedCache` 一族本来就线程安全；`SymbolicDemangler.isCacheEnabled` 只读无写入点，**不加锁**
  （它在最热的入口上，加 `@Mutex` 等于给 8 路并行加一把全局锁），改 `static let`。打印路径之外的非原子写
  `specialize(...)` 追加 `_specializedChildren`，RuntimeViewer 里写与读都在 section actor 上；「同一 printer 可并发」的承诺不覆盖它，
  文档里写明。
- **约定更新**：AGENTS.md 的那条改成「`MachOImage` 读者下，同一 printer 实例可被多个任务并发调用，包括同时打印同一个定义、
  父类型与其嵌套子类型；`MachOFile` 读者仍不可」；`Internal/Modules/SwiftDeclaration.md` 关于 `isIndexed` 的说明同步。
  不改 `SwiftDeclarationPrinter` 的公开 API，也不提供并行的入口——并行由调用方（RuntimeViewer 的语料 store）用任务组自己组织。
- **验证**：压力测试用 SymbolTests fixture，覆盖三种情况——全部定义分给 N 个任务、**多个任务同时打印同一个定义**、
  **父类型与它的嵌套子类型同时打印**；**先在改动前跑出 TSan 红**，修后绿，输出与串行逐字节相等；套件按 AGENTS.md 声明
  `ExclusiveImageAccess`，TSan 结论记入决策日志；现有套件全过；渲染 A/B 按 AGENTS.md 必跑。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-30 | Created as Draft | 用户在 RuntimeViewer 的 Find 语料构建性能提问轮里选定「跳过嵌套重复 + 并行打印」；并行的前提是本库的定义对象能被并发打印。 |
| 2026-09-30 | 只解除 `MachOImage` 读者的限制 | `MachOFile` 的不安全来自共享 `FileHandle` 的 seek + read，是另一类问题；语料只在进程内构建。 |
| 2026-09-30 | 第一轮审查：「等待同一个 Task」改为首个调用者原地索引 + promise 等待，补抛错回退；补上 diff 渲染那处写入 | 非结构化 `Task {}` 不继承大栈执行器偏好、索引体本来没有 `await`；`SwiftDeclarationPrinter+DiffRendering.swift` 同样写 `attributes`。 |
| 2026-09-30 | 第二轮审查：`attributes` 改局部变量而非计算属性；等待形态定为同步阻塞并把 `index(in:)` 改成同步函数；锁改进程级一把 + in-flight 表；撤掉 `isCacheEnabled` 加锁；动机补上「竞争今天已在发生」、测试先红后绿；定义类标 `@unchecked Sendable` | 计算属性违反 AGENTS.md 物化纪律且依赖方向不通（inferrer 所在模块依赖 `SwiftDeclaration`）；`SharedCacheBuildPromise` 是同步阻塞且无错误通道，两种等待形态要二选一并写出不变量；每定义一把 `Mutex` 是每定义一次堆分配；`isCacheEnabled` 无写入点，加锁只添争用；RuntimeViewer 的显示路径与语料路径今天已在 actor 外并行打印同一批定义。 |
| 2026-10-01 | Accepted | 用户在 RuntimeViewer 的 Find navigator 会话里说「开始实现提案，MachOSwiftSection的更改可以和 MachOSwiftSection-FindNavigator 这个agent说」，并在本仓库的会话里直接确认「两份都开工」。 |
| 2026-10-01 | In Progress；开工前定下的实现细节 | 两份里先做本提案：RuntimeViewer 的显示路径与语料路径今天已在并发打印同一批定义。带错误通道的 promise 直接复用 `SharedCacheBuildPromise`（载荷是 `Result`），不另写一个同形的类；`isIndexed` 保持公开只读；`attributes` 直接删除、不留转发扩展——RuntimeViewer、REAgent、swift-decompiler 三个下游都不读它（2026-10-01 逐仓 grep），删除记入 changelog。 |
| 2026-10-01 | 实现：`DefinitionIndexing`（`Components/Definitions/DefinitionIndexing.swift`）；认领时检查「当前线程是否正在跑某个索引体」 | 一把 `@Mutex` 守着 in-flight 表与各定义的 `hasCompletedIndexing`；三个定义的旧函数体原样挪进私有的 `runIndexingPass(in:)`，`ExtensionDefinition` 的两处提前返回不再自己置标志。同线程重入与「索引体去索引别的定义」用同一条 `precondition` 拦下：认领或等待时，in-flight 表里只要有一个 promise 的构建线程是当前线程就 trap，不需要另设 task-local。所有 `SharedCache` 都在 `SwiftDeclaration` 下层的模块里，构建闭包按依赖方向够不到定义，「索引体不索引定义」由结构保证。 |
| 2026-10-01 | 压力测试 `ConcurrentDefinitionPrintingTests`（`SwiftPrintingTests`）不声明 `ExclusiveImageAccess` | 它只比较同一进程里两个 indexer 的串行与并发输出，不对进程级状态下断言，不属于 AGENTS.md 要求声明的那类套件；单边声明也排除不了别人。套件加进 CI 的主过滤列表，并因为有意阻塞等待而加进单线程协作池那一步。 |
| 2026-10-01 | TSan 用 release 配置跑 | debug 下 `--sanitize=thread` 在加载 fixture 时就 trap：MachOKit `FileHandle+.swift:194` 用 `load(as:)` 读 `Data` 的内联字节，TSan 改了栈布局，地址落到奇数，标准库的 `_debugPrecondition` 对齐检查触发。这是 MachOKit 的既有问题（应改用 `loadUnaligned`），不在本仓库；release 下该检查被编译掉，TSan 照样检测竞争。 |
| 2026-10-01 | 验证：先红后绿 | 改动前：不开 TSan 跑压力测试，进程直接崩在 `SwiftDeclarationPrinter.swift:237`（`for attribute in typeDefinition.attributes`，另一个任务刚给 `attributes` 重新赋值，旧数组被释放后又被读）；release + TSan 报出 28 条数据竞争，全部落在 `TypeDefinition.index` 内部（成员构建、thunk 属性、wrapped property）、打印器写 `attributes` 那段，以及读写成员数组（含 `detachedFromSharedTable()` 新建的 `SymbolTable` 被另一个任务无同步地读），`swift test` 退出码 1。改动后：debug 三个用例全过（约 9 秒）；release + TSan 三个用例全过、0 条报告、退出码 0；`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` 下通过（7.5 秒），再关掉大栈执行器（`MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR=0`）也通过（18 秒），说明阻塞等待不需要额外的池线程。 |
| 2026-10-01 | 全量测试与渲染 A/B | 全量 `swift test --skip IntegrationTests`（JHs-Mac-Studio-Ultra，Swift 6.4）：改动前 2160 个、改动后 2163 个测试全部通过，原始退出码都是 0，唯一的 known issue（`SymbolicManglingIndexTests`）两边相同。渲染 A/B：基线是改动前的 `4fd4049b`，两侧共用一份 `Package.resolved`，35 个依赖完全一致（其中 5 个是本地兄弟依赖），**92 对逐字节一致**——归档 cache 26.6 与 15.5 各 12 对、iOS 15.5–26.5 模拟器 44 对、MachOImage 腿 24 对。脚本写死的 `26.6.2` 归档目录在这台机器上叫 `26.6`，本轮用只改了这个常量的脚本副本跑。iOS 15.5 模拟器的 SwiftUI / WidgetKit 4 对两侧同样以 SIGTRAP 失败，记为 SKIPPED：本地兄弟依赖 MachOKit `next` 合入上游 0.53.0 后（上游 `7adae68` 开始校验 LINKEDIT 范围），导出信息为空（offset 0、size 0）的镜像让 `ExportTrie.init` 的强制解包崩溃，由 `ObjCAncestorResolver` 沿依赖闭包查导出表触发；仓库远程 pin 的 `0.52.103 ..< 0.53.0` 不含这个改动，与本提案无关。 |
| 2026-10-01 | 计时：串行下没有额外开销；宽度 14 的并行反而更慢，原因在 swift-demangling | 宽度 1（RuntimeViewer 会话的 `CorpusBuildTimingProbe` corpus 模式，Release，每次新进程，三档交替各两轮，负载 5–9；A = `next` 514bb4bd，B = `9f5ffa92`，C = `937172ef`，RuntimeViewer Core 同为 `8bbb46cf`、打印宽度 1，其余依赖逐项一致；原始数据在 `/Volumes/DerivedData/Agents.noindex/claude/ProbeRuns/20261001-163445-concurrent-printing/`）：libswiftCore A 1.02/1.03 s、B 1.03/1.02 s；Foundation A 4.15/4.27 s、B 4.19/4.15 s；SwiftUI A 39.93/40.31 s、B 38.75/45.59 s（第二次只用了 0.93 核，按噪声计）——索引加锁在串行下看不出成本。宽度 14（同一来源，改前 = A + 宽度 1，改后 = B + 宽度 14）：SwiftUI 串行 42–50 s，并行 61 s / 约 400 s CPU，机器越空越慢（负载约 6 时 204 s / 2599 s CPU）。采样里热点是 `ExtensionDefinition` 索引体里按 conformance 找符号的 `first(of:)`：`NodeReference` 每复制一次都 retain 共享的 `NodeStore`，14 个线程同时给同一个对象加减引用计数。修在 swift-demangling（用户选「上游改遍历」，提案 `draft-unretained-kind-queries`），RuntimeViewer 在修好之前保持宽度 1。 |
| 2026-10-01 | swift-demangling 修好遍历（它的提案 0016，已快进合入它的 `next`，未推送、未发版）；剩下的争用以后再说 | 用临时基准在沙盒里量（本分支的快照，只把 swift-demangling 换成修复分支）：进程内打印 SwiftUI 的 17920 个定义，标记模式、一个共享 printer、`.utility` 有界任务组，每个宽度一个新进程，release，JHs-Mac-Studio-Ultra。改前：宽度 1 墙钟 37.74 s / CPU 37.77 s；宽度 14 墙钟 329.50 s / CPU 4446 s。改后：宽度 1 18.02 s / 18.08 s；宽度 4 8.87 s / 26.26 s；宽度 14 15.06–18.87 s / 约 165 s。串行本身也快了一倍：按 conformance 找符号的查询在单线程下同样是热点，省掉的是逐节点的引用计数和以 `NodeReference` 为元素的去重集合。改后在宽度 14 下再采样，剩下的争用在本库：`SymbolIndexStore.demangledNodeReference(for:in:)` 每查一个符号都经 `SharedCache.resolve` 取一次存储（同一把锁，`__ulock_wait2` 约 2750 个样本），以及 `ExtensionDefinition` 索引体里按 conformance 找符号时逐个造 `NodeReference`、retain 同一个 store。用户选择先做 `draft-nested-definition-regions`，这部分以后再说。全量 `swift test --skip IntegrationTests` 用修好的 swift-demangling 跑，2168 个全过（原始退出码 0）。RuntimeViewer 要拿到修复，构建需要解析到 swift-demangling 的 `next`。 |
| 2026-10-01 | RuntimeViewer 用修好的 swift-demangling 复测：宽度 4 在三个镜像上都快约 2.5 倍，宽度 14 在 SwiftUI 上反而比宽度 4 慢 | RuntimeViewer 会话的 `CorpusBuildTimingProbe`（corpus 模式，Release，每次新进程，四档交替各两轮，负载 5–7；本库为 `937172ef` 的 git archive，swift-demangling 为 `e17ae7f`，对照组为 `35d550a`；RuntimeViewer Core 为 `c0ed5fe4`，只改 `defaultPrintingWidth`；原始数据在 `/Volumes/DerivedData/Agents.noindex/claude/ProbeRuns/20261001-163445-concurrent-printing/fix-*`）。libswiftCore（660 个对象）：修复前宽度 1 为 0.94 / 0.95 s；修复后宽度 1 为 0.84 / 0.86 s，宽度 4 为 0.34 / 0.34 s（CPU 1.1 s），宽度 14 为 0.36 / 0.35 s（CPU 3.6–3.8 s）。Foundation（2559 个）：3.69 / 3.56 s → 3.34 / 3.36 s → 宽度 4 为 1.28 / 1.28 s（CPU 3.5 s）→ 宽度 14 为 0.84 / 0.84 s（CPU 4.6 s）。SwiftUI（7378 个）：34.76 / 33.85 s → 17.44 / 16.30 s → 宽度 4 为 6.68 / 6.81 s（CPU 21.9–22.3 s）→ 宽度 14 为 11.95 / 11.58 s（CPU 144–149 s）。与沙盒基准一致：串行减半，宽度 4 收益最好，宽度 14 被本库符号索引里剩下的争用拖住。RuntimeViewer 准备在它的提案里建议宽度取 min(4, 核数 / 2)（下限 1），等它能解析到含 `9f5ffa92` 的本库和含 `d7693c2` 的 swift-demangling 之后再改代码，以免在没有索引锁的版本上并发打印。 |
