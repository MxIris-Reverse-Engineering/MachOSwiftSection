# MetadataReaderCache 清退：class Node 树缓存换持 NodeReference

> **状态：Implemented（2026-08-08 批准并同日落地）**——落地记录见文末。

## 一句话

`MetadataReaderCache` 是 NodeStore 体系之前的旧式缓存——三张字典直接持有整棵 class `Node` 树，是五镜像实测中约 18.4 万个残留 `Node`（占存活总量 207,489 的 ~89%）的持有主体；把它的载荷换成 `NodeReference`（汇入既有的 `InternedNodeReferenceCache` 作用域 store），公开 API 与全部 103 处调用点零改动，class `Node` 常驻清零，并补上它缺失的按镜像清理出口。

## 背景与账目

RuntimeViewer 索引五个系统镜像（Foundation + libswiftCore + AppKit + SwiftUI + SwiftUICore）后的 memory graph：`SharedNodeStore` 迁移把 `NodeStore` 实例从 14,451 降到 15，但存活 class `Node` 几乎未动（208,809 → 207,489）。归因（本仓库 `DeclarationModelMemoryFootprint.md` 第五节第 3 条与对面会话的独立全量持有点扫描相互印证）：

- **主体是 `MetadataReaderCache.Storage`**（`Sources/SwiftInspection/MetadataReader.swift:649-660`）的三张字典，value 都是整棵 class `Node` 树：`nodeForMangledNameBox`（mangled name → 树）、`nodeForContextOffset`（descriptor offset → 树）、`nodeForSymbolName`（symbol 名 → 树或 `nil` 拒绝裁决）。
- **只进不出**：该类是 `private` 单例，`SharedCache.remove(for:)` 明明存在（`Sources/MachOCaches/SharedCache.swift:121`），但没有任何公开 seam 能调到它——`SwiftDeclarationIndexer.deinit` 按镜像清了 symbol store 和 `InternedNodeReferenceCache`（`SwiftDeclarationIndexer.swift:156-160`）却清不到这里，唯一出口是内存压力触发的全局 `removeAll`。
- **零跨树共享**：Stage 5c 把构造改成了 transient（阻止全局 `NodeCache` 增长），但没改**持有**形态——每棵被缓存的树都自带私有的 `.module("Swift")` / `.identifier("Int")` 叶子副本，hash-consing 去重率为零。
- 用户裁决（2026-08-08，经 swift-demangling 会话转达）：这套旧式简单缓存机制去掉，方案与审批按本仓库规矩走。

## 改动位置（先看这里）

| 位置 | 改什么 |
|---|---|
| `Sources/SwiftInspection/MetadataReader.swift:649-660`（`MetadataReaderCache.Storage`） | 三张字典的 value 从 `Node` / `Node?` 换成 `NodeReference` / `NodeReference?`。键不动（`MangledNameBox` / `Int` offset / `String` symbol 名——键是对「demangle 这件工作」的去重，store 是对「树」的去重，两层各管各的，与 `lateDemangledNode` 落地的模式完全同构）。 |
| 同文件六个缓存方法（`demangleType` ×2、`demangleContext` ×2、`buildContextManglingForSymbol` ×2） | miss 路径：现有 `_demangle…`（transient 构造，不变）→ `InternedNodeReferenceCache.shared.reference(interning:in:)`（镜像作用域）/ `reference(interning:)`（进程作用域）→ 字典存引用 → 把刚 demangle 出的树直接返回。hit 路径：`reference.materialize()` 重建一棵独立树返回；`nil` 拒绝裁决直接返回 `nil`。`@_spi(Internals) import MachOSymbols` 已在（`MetadataReader.swift:8`），无新依赖。 |
| `Sources/SwiftInspection/MetadataReader.swift`（新增） | 补清理 seam：`MetadataReader.removeCache(for:)`（`@_spi(Internals) public`），实现即 `MetadataReaderCache.shared.remove(for: machO)`。 |
| `Sources/SwiftIndexing/SwiftDeclarationIndexer.swift:156-160`（`deinit`） | 在既有两个按镜像 remove 旁边追加 `MetadataReader.removeCache(for: machO)`，让这份缓存与 symbol store / interned-name 桶同一节奏回收。 |
| `AGENTS.md`「Symbol indexing」段 | 同步措辞：`MetadataReader` 的 demangle memo 载荷已是 `NodeReference`（汇入 `InternedNodeReferenceCache` 作用域 store），且随 indexer 的按镜像清理一起释放。 |

## 明确不动的部分

- **公开 API 与 103 处调用点**：`MetadataReader.demangleType` / `demangleContext` 仍返回 `Node`，Sources 内 36 个文件共 103 处调用点（对面报 112，含测试口径差）一行不改。
- **`MultiPayloadEnumDescriptorCache` 的 `[Node: MultiPayloadEnumDescriptor]` 键**（`Sources/SwiftDeclarationRendering/MultiPayloadEnumDescriptorCache.swift:32`）：对面判断「主缓存动了它必须同批改键」，核实后**不成立**——class `Node` 的 `==` / `hash` 是**结构语义**（上游 `Node+Hashable.swift`：全子树结构摘要 + DAG 记忆化，实例身份仅是快路径），换后端后 build 键与查询键即使是不同实例也照常命中。该缓存人口极小（每镜像的 multi-payload enum 数量级是百，树是短名字树），保留原样；它残留的少量 class `Node` 在预期残余 ≲2.3 万之内。
- **`isCacheEnabled` 开关与 `demangleTypeUncached`**：语义不变。后者的免重入理由（`SharedCache` build 闭包内再进 `storage()` 会 trap）在新形态下依旧成立。
- **`GenericArgumentEnvironment.swift:250` 往 `NodeCache.shared` 叶子表灌节点**：对面留档的次要项，属剩余 ~11% 的一部分，不在本次范围。

## 关键设计取舍

- **换后端，而非彻底删除**：三张字典 memo 的是昂贵的 demangle 工作——`nodeForContextOffset` 尤其省掉了逐类型重建父 context 链的重复 Mach-O 读取与递归构建。彻底删除会让 103 处调用点每次全量重做，CPU 回归几乎必然，内存上却不比换后端多赚（常驻已清零）。
- **汇入 `InternedNodeReferenceCache` 的既有作用域 store，而非自持新 store**：AGENTS.md 记载的模型本来就是「metadata 派生的名字树走 `InternedNodeReferenceCache`」——喂进声明模型的 `TypeName` / `ProtocolName` 等树与本缓存的树**大量就是同一批**，汇入同一 store 后字典 value 只是 16 字节引用，树体与声明模型去重共享，边际内存≈字典本身。生命周期也同构：两者都是 `SharedCache`（同受内存压力清理），且 `deinit` 里新增的 remove 让两者同一节奏按镜像释放。上一轮 `lateDemangledNode` 自持 side store 的理由（`SymbolIndexStore.Storage` 不是 `SharedCache`，生命周期错配）在这里不存在。
- **hit 路径每次 `materialize()` 一棵新树**：这是本方案唯一的性能代价——今天 hit 返回共享实例零分配，之后每次 hit 付 O(节点数) 的重建。重建远比它 memo 掉的 demangle + Mach-O 解析便宜（一至两个数量级），且 `materializeNode` 按 index 记忆化、**保 DAG 共享**（back-reference 子树在同一棵物化树内仍是 `===` 复用）。验收里做整镜像 interface 生成的 wall-clock 对比兜底。
- **返回实例的跨调用身份不再稳定**：这是唯一可能隐性破坏的行为面，已横向排查 Sources 全部按身份键控的用法——`SwiftPrinting` 的 `printCache`（`ObjectIdentifier(node)` 键）只活在单次 `printRoot` 内，靠的是**同一棵树内**的 DAG 共享，物化保共享所以不受影响；`RuntimeFieldLayoutBackend:223` 的 `ObjectIdentifier(metatype)` 是 runtime metadata 包装、与 `Node` 无关；其余所有 `[Node: …]` 容器靠结构语义 `Hashable` 不受实例更替影响。副作用是正向的：调用方拿到的从「可被下游意外污染的共享缓存实例」变成私有树，缓存不再可能被调用方的树改写毒化。
- **改 API 返回 `NodeReference`（被否）**：内存收益与本方案完全相同（关键在常驻形态，不在瞬时分配），却要动 103 处调用点及其下游消费链。若日后 profiling 证明 hit 物化是热点，再作为独立演进推进。

## 验收计划

1. 全量 `swift test --skip IntegrationTests` 全绿；fixture interface 快照逐字节一致（输出零变化是硬约束）。
2. `Scripts/run-rendering-ab-verification.py`（AGENTS.md 对触及 demangling 层的重构的强制项）：baseline = 本分支当前 tip，candidate = 落地后，三条 reader 路径逐字节对拍。
3. 性能兜底：SwiftUI 量级二进制的 `swift-section interface` 整镜像生成 wall-clock A/B，确认 hit 物化未造成可感知回归。
4. RuntimeViewer 侧同一批五镜像复测 memory graph（对面会话协调）：预期存活 class `Node` 207,489 → ≲23,000。

## 上游依赖

无新增。`NodeReference.materialize()`（cache-free、保 DAG）与 `InternedNodeReferenceCache` 的两个作用域接口都已在现分支可用；不引入新的 swift-demangling 改动，也不改变「上游 `feature/node-store` 未 push 前本分支在无 sibling 环境不可构建」的既有状态。

## 落地记录（2026-08-08）

按改动位置表原样实施：`Storage` 三张字典换 `NodeReference` / `NodeReference?` 载荷（symbol 名的 `nil` 拒绝裁决用 `updateValue` 显式写入，避免 subscript 赋 `nil` 删键）；六个缓存方法 miss 时 intern 进 `InternedNodeReferenceCache` 对应作用域、hit 时 `materialize()`；新增 `MetadataReader.removeCache(for:)` 接进 `SwiftDeclarationIndexer.deinit` 的按镜像清理三连。类文档注释改写为「字典去重工作、作用域 store 去重存储、返回实例跨调用不共享」的新契约。AGENTS.md「Symbol indexing」段同步。

**验证（三轴全绿）**：

1. 全量 `swift test --skip IntegrationTests` **1337 tests 全绿、0 失败**，与改动前完全同数（含 interface 快照逐字节断言）。
2. `Scripts/run-rendering-ab-verification.py`（baseline = `ed2f4d1`，candidate = 本改动）：**96 对输出全部逐字节一致、零跳过**，覆盖当前系统 dyld cache、七个模拟器 runtime（iOS 15.5–27.0）、in-process MachOImage 三条 reader 路径的 dump + interface。
3. 性能：A/B 脚本 72 对场景总耗时 baseline 1150s vs candidate 1148s（±0.2%，持平）；iOS 18.5 模拟器 SwiftUI 的 `interface` 三轮交错受控测量中位 71.3s vs 70.9s——hit 路径物化的代价不可感知，与设计预判一致。
4. RuntimeViewer 五镜像 memory graph 复测（2026-08-08 闭环，RV 用户亲自抓取；环境逐项核对：本仓库 @ `dda9d72` + swift-demangling @ `9464265`，均经 sibling 符号链接本地编译、显式 `USING_LOCAL_DEPENDENCIES=1`、checkouts 确认无远端回退）：存活 class `Node` **207,489 → 44（−99.98%）**；`NodeStore` 15（与上轮持平，符合「汇入既有作用域 store、不新增 store 身份」的预测）。

**为什么 44 远低于方案预期的 ≲23,000**：那个预期是测量学假象，不是本次超额达成——≲23k 来自「207,489（RV 复测图）− 183,994（`DeclarationModelMemoryFootprint.md` 的归属数）」，两个数字出自不同测量上下文，差值不对应真实人口。实际上 `MetadataReaderCache` 在 RV 的 eager 索引负载里持有的就是全部 20.7 万的几乎百分之百：预期中的两个残留来源在该负载下根本不运行（`GenericArgumentEnvironment` 的 `NodeCache` 叶子表喂入点在静态布局解析路径上；`MultiPayloadEnumDescriptorCache` 按渲染惰性填充，索引 sweep 不触发）。残余 44 个的量级对应 `NodeFactory` 在 `NodeCache.shared` 初始化时预注册的无参 singleton 池加快照瞬间的少量 churn，判定为终态。

**附带发现**：A/B 首跑时基线全新 scratch 把 swift-demangling 解析回了远端 0.5.1（`NodeStoreBuilder has no member reserveCapacity`）——本地 sibling 依赖生效需要「兄弟目录存在 + `USING_LOCAL_DEPENDENCIES=1`」双条件，而旧 scratch 的 manifest 求值缓存会掩盖环境变量未置位。已补进 AGENTS.md 环境漂移检查第 2 条（诊断：`workspace-state.json` 的 `packageRef.kind`）。与方案本身无差异，方案按原样落地。
