# Draft - 定义对象的并发打印安全：索引前置，打印期不再写定义

- **状态**: Draft
- **创建日期**: 2026-09-30
- **最后更新**: 2026-09-30
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
