# MachOSymbols 模块

> 模块参考文档（module reference），随代码维护。读者：维护者。
> 细节文档见文末[「相关文档」](#相关文档)；本文负责全貌与分工，不复述细节。

## 模块定位

MachOSymbols 是**符号索引**层：把一个镜像的符号表和 export trie 扫成可查询的索引，并把每个 Swift 符号 demangle 成节点树存起来，供上层按偏移、按名字、按类型成员反查。

它坐在 ABI 模型**上面一层**。`MachOSwiftSection` 够不到它（演进提案 `self-contained-abi-layer` 的边界）：描述符只暴露实现偏移，把偏移归属到符号名是 `SwiftInspection` 的事。符号的**值类型**（`Symbol` / `Symbols` / `SymbolOrElement`）住在 `MachOResolving`，不在这里——「这个偏移上有哪些符号」是一次针对索引的**查询**，不是一次读取，所以 `Symbols` 故意不是 `Resolvable`。

模块另外托管一个跟符号无关的东西：`LargeStackTaskExecution`，库入口用来把整个调用链搬到大栈执行器上的开关。它放这儿是因为 demangler 是它唯一的服务对象。

## 文件 → 子系统对照

| 子系统 | 文件 |
|---|---|
| 1. 索引本体 | `SymbolIndexStore`、`SymbolTable`、`SymbolRowBucket` |
| 2. 符号值与查询出口 | `Symbol`、`DemangledSymbol`、`MachO+Symbol` |
| 3. 节点引用的共享与跨 store 对账 | `InternedNodeReferenceCache`、`StructuralNodeReferenceKey` |
| 4. 大栈执行器接入 | `LargeStackTaskExecution` |
| 5. `_symbolic` 符号表 | `SymbolicManglingSymbols` |

## 子系统 1：索引本体

`SymbolIndexStore.Storage` 里**不驻留 `Node` 类树，也不驻留符号名 `String`**。建索引时每个符号 demangle 到一棵临时树上，分类完就 intern 进这个镜像的 `NodeStoreBuilder`；全局 `NodeCache` 全程不参与，`Storage` 一放，整个镜像的内存占用就跟着走。

存储形态是每个唯一符号名一行 16 字节的 `SymbolRow`（规范化偏移 + 名字字节的打包引用）。名字有两个来源：`MachOImage` 的行直接指进镜像 mmap 的 LINKEDIT 字符串表（零拷贝、干净页，代价是这张表要求镜像保持加载）；`MachOFile` 的行和 export trie 解出来的名字进表内部的私有连续缓冲区。名字反查是在 `rowsSortedByName` 排列上做字节级二分。

**成员 / typeInfo / thunk 属性这几个索引的 key 不是单射的**：第一层是打印出来的类型名，用 `.interfaceTypeBuilderOnly` 打印，会剥掉 private discriminator，于是不同文件里同名的 private 类型共用一个名字桶（issue #115：dump 路径按名字查，把两个类型的成员混进了同一个声明）。所以——

> 解析**某一个**类型的成员 / 信息 / 属性，必须用带 node 的重载（`memberSymbols(of:for:node:in:)`、`methodDescriptorMemberSymbols(of:for:node:in:)`、`typeInfo(for:node:in:)`、`thunkAttributeMembers(of:for:node:in:)`）。只带名字的那几个重载会故意把所有子桶摊平，只用于「所有打印成这个名字的类型」这种聚合查询。

`Storage` 同时带着镜像的**导出事实**：两条 symtab 采集腿都过滤掉 external 符号，导出符号的行只可能来自 export trie 那条腿，而那条腿的行是有条件产出的，所以 trie 归属在同一趟里单独记（逐行位图加一个给无偏移 re-export 用的名字集合），撑起三态的 `isExported(name:in:)`（`nil` = 这个镜像没有导出信息，**此时绝不标注**）。

## 子系统 2：查询出口与 detach

查询在出口处构造 `DemangledSymbol` / `NodeReference` 值。这些值共享镜像那张 `SymbolTable`——对于一次查询吐出又丢弃的几十万个值，这是对的交换。

> **但凡要存进声明模型的 `DemangledSymbol`，必须先 `detachedFromSharedTable()`。** 一个存活的值就钉住整张表（镜像表还会把它对 mapped string table 的读连在加载状态上），`removeSubIndexer(_:)` 想回收的按镜像内存就白回收了。查询路径上**不要** detach。

实测（SwiftUI，iOS 18.5）：9872 个被存下来的值只引用 5.1% 的行，detach 是拿约 0.6 MB 的小分配换掉整张表的驻留。存的地方一共六处，`SymbolTableRetentionTests` 会在有人新增第七处却忘了 detach 时立刻变红。

## 子系统 3：跨 store 对账

节点引用的 `Hashable` 是 **store 身份**语义。一个镜像内部同时存在好几个 store——冻结的主符号 store、迟到名字的旁路 store、缓存的各作用域 store，内存压力驱逐还会把某个作用域重建到新 store 上而旧引用仍然钉着旧的——所以跨 store 是常态，不是例外。

> **任何 key 与查询可能来自不同 store 的 `Dictionary` / `Set`，必须以 `StructuralNodeReferenceKey` 为 key，不能用裸 `NodeReference`。**

用裸 key 会静默失败，而且各处的失败形态还不一样：override / vtable 查找会丢掉 `override` 关键字和 vtable 偏移注释；下标的 getter 和 setter 分进两个桶，只有 setter 的那个被丢弃；合并的 thunk 会把 `func` / `init` 印两遍；witness 会被认领两次。只有在**一批** `memberSymbols` 内部做分组或去重（单一 hash-consed store，结构相等与索引相等重合）时，裸 key 才是安全的。

`InternedNodeReferenceCache` 管的是 `SharedNodeStore` 里**没有**的那部分职责：按 Mach-O 作用域分区和驱逐。metadata 派生的名字树走它。

> 批量路径上不要裸调 `NodeReference(interning:)`，走缓存。

## 子系统 4：大栈执行器

`LargeStackTaskExecution.run(_:)` 在库入口外面把 swift-demangling 的 16 MB `LargeStackTaskExecutor` 设为 task executor preference。demangler 每次调用会拿**调用线程**的剩余栈跟 2 MB 下限比一下决定要不要跳到自己的 8 MB 池；协作线程和 libdispatch 线程只有 512 KB，于是异步打印循环每打印一个符号就要付一次线程往返加信号量等待（实测 8–21 µs，1.14–2.28 倍）。在执行器线程上这个探测每次都过，整条流水线（含同步被调用方）就地跑完。

几条容易踩的：嵌套调用是 no-op；**非结构化的 `Task {}` 不继承这个偏好**（SE-0417），所以绝不要在被包裹的入口里起一个；main actor 保留自己的执行器；macOS 15 / iOS 18 以下或非 Darwin 平台原样执行 body。进程级关闭开关 `isEnabled`，由环境变量 `MACHO_SWIFT_SECTION_LARGE_STACK_EXECUTOR` 播种。

## 子系统 5：`_symbolic` 符号表

编译器给每条带 symbolic reference 的 mangled name 生成一个链接器去重用的符号（`_symbolic ` / `_default assoc type ` 开头），
名字里按引用顺序写出每个被引用者的完整 mangling。构建扫描的两条 symtab 采集腿各多一个前缀分支，把它们收进
`Storage.symbolicManglingSymbolTable`——同一个 `SymbolTable` 结构、同样的名字来源与偏移换算，但**不进任何索引**：
`symbols(for:in:)`、`containsSymbol(named:)`、导出事实都看不到它们，这些名字也从不 demangle。唯一的出口是
`symbolicManglingSymbols(in:)`，解码在 SwiftInspection 的 `SymbolicManglingIndex`（它要读 mangled name 的字节，本模块够不到
ABI 模型）。

> 被引用者不能单独 demangle：同一个 mangler 依次写出它们，后面的会用 substitution 借用前面的。一律经
> `SymbolicManglingIndex.referentNode(of:in:)` 拿节点。

细节与实测：[SymbolicManglingSymbols.md](../SymbolicManglingSymbols.md)。

## 关键契约

- **不要重新引入带缓存的 demangle**。全模块（以及上层）用 `demangleAsNodeTransient` + `Node.createTransient`；一棵用完即弃的树必须是 transient 的，否则全局 `NodeCache` 会随浏览一路涨。
- **不要在缓存锁里做可能阻塞的大栈跳转**。迟到名字的 demangle 跑在锁外面，竞争的 misser 各自 intern 进同一个 store，靠结构化去重拿到同一个引用。
- **改本模块的结构布局要先 `swift package clean`**。SwiftPM 增量构建被观察到链接了陈旧的下游目标文件，症状是运行时在 `outlined destroy` 里 SIGSEGV。公开类型跨模块搬家或翻转依赖边同样会触发（2026-09-12 有一次实例）——先 clean，再诊断。

## 相关文档

- [NodeStoreMigrationPlan.md](../NodeStoreMigrationPlan.md)——存储形态迁移的完整分阶段计划。
- [NodeStoreMigrationOpenIssues.md](../NodeStoreMigrationOpenIssues.md)——迁移遗留问题。
- [SharedNodeStoreMigration.md](../SharedNodeStoreMigration.md)——声明模型持有 `NodeReference` 的那一步。
- [SymbolIndexStoreMemoryOptimization.md](../SymbolIndexStoreMemoryOptimization.md)——内存优化。
- [PrivateTypeMemberAttribution.md](../PrivateTypeMemberAttribution.md)——同名 private 类型的成员归属（issue #115）。
- [LargeStackTaskExecutorAdoption.md](../LargeStackTaskExecutorAdoption.md)——执行器接入与实测数据。
- [MetadataReaderCacheRetirement.md](../MetadataReaderCacheRetirement.md)——`SymbolicDemangler` 的 demangle memo。
- [SymbolicManglingSymbols.md](../SymbolicManglingSymbols.md)——`_symbolic` 符号的格式、收集与解码。
- 演进提案：[0001](../../Evolutions/0001-symbol-name-offsetization.md) 符号名 offset 化 · [0003](../../Evolutions/0003-symbol-row-bucket-flattening.md) 行号桶扁平化 · [0018](../../Evolutions/0018-self-contained-abi-layer.md) ABI 层自包含 · [0019](../../Evolutions/0019-large-stack-executor-and-cross-version-parallelism.md) 大栈执行器。
