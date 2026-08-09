# Review 已裁决清单

判定为「不修」或「误报」的 code-review 发现，连同结论、理由与复审条件，集中登记在这里。

**使用规则**：每轮 code review 开始前先对照此表；已裁决且理由仍成立的发现直接跳过，不再重走「复现 / 基线对比 / 值不值得修 / 既往修复」四问。若新证据（profiling 数据、上游变更、新的触发路径）推翻了当初的理由，更新对应条目并重新裁决。

各轮 review 的原始发现清单在 [`Roadmaps/*-review-findings.md`](../../Roadmaps/)；本表只收录其中作出「不修 / 误报」终审的条目。

---

## A1 — 上游 `mangleAsString(some DemanglingNode)` 经 materialize 桥接（`ABIKey.make` 路径）

- **裁决**：不修（2026-08-03）。
- **发现**：store-backed 节点（`NodeReference`）remangle 时，上游泛型重载的实现是 `mangleAsString(node.materializedNode)`（swift-demangling `RemangleInterface.swift:49`，0.5.0 与 `feature/node-store` tip `5cc30c9` 均如此；**0.5.1 复核仍然保持，且上游维护者确认按设计不改**——文档注释明言 Remangler 不是只读消费者、桥接成本瞬态且不影响 store 驻留内存目标）——每次调用把子树 materialize 成一棵瞬态 `Node` 类树后再走具体 `Node` 版 Remangler。`ABIKey.make(for: some DemanglingNode)` 是本仓库的主要受影响调用点。
- **复现 / 是否误报**：属实，非误报。已直接核对上游两个版本的源码。
- **与 main 基线对比**：非本仓库引入。main（0.4.x `Node` 线）传具体 `Node`，重载解析命中具体版本，零 materialize；仅 node-store migration 线的 store-backed 路径受影响。上游侧这是记录在案的设计取舍——Remangler 遍历中要构造临时辅助节点（unspecialized nominals、SIL box 布局包装），不是只读消费者，故运行在 class 表示上（上游 `RemangleInterface.swift` 文档注释原文）。
- **为什么不修**：
  1. 成本是每 key **恰好一次**的瞬态 O(subtree) 类树构造，用完即弃，不进常驻内存；remangle 输出本来就是新 `String`，store 的驻留内存目标不受影响。本仓库侧无重复 materialize 可省。
  2. 根治在上游：把约 6200 行的 Remangler 泛型化到 `DemanglingNode`（需引入 overlay 节点表示"新脊柱挂旧子树"的两簇合成点，并把替换表的身份 hash / 深比较异构化）。上游已把它列为既定方向——`materializedNode` 的文档注释原话是 *"remangling until the `Remangler` is genericized"*——且所需基础设施（跨表示 `structurallyEquals` / 一致的 `structuralHash`、`printCacheIdentity` 身份抽象、printer 泛型化先例）在 `feature/node-store` 分支均已就绪。
  3. 下游任何 workaround（如自写泛型 remangler、绕过 `ABIKey` 的 remangle 身份）都比等上游代价大。
- **既往修复**：无。上游有意设计，非回归。
- **代码锚点**：`Sources/SwiftDiffing/ABIKey.swift` `make(for:)` 调用点注释（"Adjudicated — not worth fixing"）。
- **复审条件**：① 上游发布泛型化的 Remangler 后，删调用点注释即可直接受益，本条目关闭；② profiling 显示批量建 key 时 materialize 占总耗时比例可观（当前仅为推断成本，无测量数据）——届时正确动作是推动上游泛型化，而非下游绕路。
- **关联上游事项**（非本表裁决，仅备查）：`structuralHash` 分配一条见 A2。~~同轮核对的 `NodeReference` 缺 async `print(using:)` 一条属上游补齐范畴~~——**已闭环（2026-08-03）**：上游 `f913742` 把 print 便利方法整体迁到 `DemanglingNode` 协议扩展并补 async 变体，发布为 **0.5.1**，对 `NodeReference` 直接可用；本仓库依赖已升 `from: "0.5.1"`，`indexExtensions` 的 `await` 已恢复。

---

## A2 — 上游 `NodeReference.structuralHash` 每文本节点分配一个瞬态 `String`

- **裁决**：下游不修、不 workaround（2026-08-03）。~~上游按 enhancement 提 issue~~——**追记（2026-08-03）**：上游维护者已说明按设计不改（单一编码源 `nodeContents` 共享 `Node.Contents`，一致性由构造保证，是两轮事故换来的设计；`0.5.1` 保持现状），不再提 issue。仅当下条复审条件 ① 的 profiling 证据出现时重议。
- **发现**：`NodeReference.structuralHash` → `structuralDigest()` 对每个文本节点经 `nodeContents` 构造一个瞬态 `String`（`store.text(offset:length:)` → `String(decoding:)`，upstream `NodeReference.swift:169` / `NodeStore.swift:97`）。且 digest 的 memo（`digestByIndex`）是每次调用局部的——字典每次插入 / 查找 / 扩容重哈希都会重走子树。
- **复现 / 是否误报**：属实，非误报。0.5.0 与 `feature/node-store` tip（`5cc30c9`）均已核对源码。
- **与 main 基线对比**：非本仓库引入，是上游 store 表示的实现特性。本仓库 main（`Node` 线）不受影响——`Node.text` 本就驻留，hash 现有 `String` 零分配。
- **既往修复（这是不是刻意设计）**：修过两轮，现状是刻意设计的**一部分**——
  1. 出生（upstream `26db7a4`，Stage 5）：手写 discriminator 编码，且 `String` 分配从出生就在；手写编码与 `Node.hash(into:)` 不一致 → 跨表示字典查找永远落空的 bug。
  2. 编码统一修复：引入 `nodeContents` 共享 `Node.Contents` 编码源，一致性由构造保证（上游 `nodeContents` 注释记录了该事故）。
  3. 性能修复（upstream `69fdbd3`）：路径放大 615,165× → memoized digest，刻意保留共享编码，跨表示一致由测试钉住。
  结论：「单一编码源」是设计且理由仍成立；「每文本节点分配 String」只是该设计当前实现的副作用，二者可分离。
- **为什么下游不动作**：暴露面真实——`structuralHash` 支撑 `TypeName` / `ProtocolName` / `ExtensionName` 的 `Hashable` 与 `MachOSymbols.StructuralNodeReferenceKey`，都在索引字典路径上；但这些子树是名字链（几个到二十来个节点），每次操作只是少量小 `String` 的瞬态垃圾，且无 profiling 证据表明是热点。
- **上游修法（issue 内容）**：两侧已汇合到唯一漏斗 `seededDigestHasher(kind:contents:childCount:)`；把漏斗改成字节级——`Node` 侧以驻留 `String` 的 `utf8` view 进 hasher（零分配），`NodeReference` 侧以 store 字节表切片直接进 hasher（零分配），discriminator 单处定义，跨表示一致性由既有测试继续钉住。哈希值会变，但 `Hasher` 本就 per-process 播种，无持久化契约。
- **代码锚点**：无单一调用点，不加代码注释，以本条目为准。
- **复审条件**：① profiling 显示索引热路径上该 `String` 构造占比可观 → 升级为催上游或直接贡献 PR；② 上游修复发布并重新 pin 后，本条目关闭。

---

## A3 — 接口打印器每成员 materialize 一棵树（`SwiftDeclarationPrinter` 7 处）

- **裁决**：暂不修（2026-08-03，数据裁决）。
- **发现**：`SwiftDeclarationPrinter.swift:454/464/474/277` 与 `+Members.swift:42/65/108` 在打印每个成员 / 字段 / 扩展 where 子句时把 `NodeReference` materialize 成 `Node` 类树再交给 `TypeNodePrinter` / `FunctionNodePrinter` 等（2026-07-31 审查四.6，估算 SwiftUI 规模 ~10⁵ 次瞬态建树）。
- **复现 / 是否误报**：机制属实，但**量级测出来不值得**：fixture（SymbolTestsCore）全量 interface 导出，打印墙钟 2768.8 ms，materialize 合计 32.6 ms / 1313 次（单次 ~25 μs），占 **1.18%**。测量方式：7 处临时包计时器（临时代码与临时测试已删，数据落档于此与任务报告）。
- **与 main 基线对比**：main 的成员节点本就是类树（`NodeCache` 常驻），零 materialize 但常驻内存只涨不落——正是迁移要治的病。本条是迁移代价的一部分，且是瞬态代价。
- **为什么不修**：根治需把 `NodePrintable` 五协议栈（`NodePrintables/` + `NodePrinter/`，约 1700 行）泛型化到 `DemanglingNode`，其中 3 处**构造**节点的逻辑（`Variable/Function/SubscriptNodePrinter` 的 `.static` 包装、`SubscriptNodePrinter` 与 `FunctionTypeNodePrintable` 的 labelList 合成）纯引用无法表达，需局部重设计；print cache 的 `ObjectIdentifier` 键也要按表示异构化。~1% 的收益撑不起这个投入与回归风险。
- **既往修复**：无既往修复；`TypedDumper`（dump 路径）保留独立实现是记录在案的设计（AGENTS.md）。
- **代码锚点**：不加代码注释（7 处太散），以本条目为准。
- **复审条件**：① 大镜像（SwiftUI 级）剖析显示 materialize 占比显著高于 fixture 的 1.18%；② 上游 Remangler / 打印基础设施泛型化（A1 复审条件 ①）落地后，节点合成问题若有上游方案可顺路重开。

---

## A4 — `MachOImage` 符号名裸指针在镜像卸载后悬垂（PR #103 review M2）

- **裁决**：不修（2026-08-09，实验裁决——触发面在 Darwin 上结构性不可达）。
- **发现**：`SymbolTable.withNameBytes(atRow:)` 对 mapped 行直接读 `mappedStringTableBase`（镜像 LINKEDIT 字符串表的裸指针），而 `SharedCache` 以镜像基址为键——推理链是 `dlopen → prepare → dlclose → 同址再 dlopen 另一 dylib` 后旧 `Storage` 被继续命中，材料化读到重映射内存（乱名或 SIGSEGV）。review 自记「mechanism confirmed by reading; end-to-end trigger not reproduced」。
- **复现 / 是否误报**：机制读码属实，但**端到端触发被实验推翻**（2026-08-09，macOS 26 / Darwin 25.6.0 实测）：
  1. 含 Swift 内容的镜像（无论有没有 class，连仅含 `public func` + `struct` 的 dylib 都算）被 dyld 标记 never-unload——`dlclose` 后镜像仍在 `_dyld_image_count` 枚举中，永不 unmap。被本库索引的镜像必有 Swift 元数据（否则无从索引），全部落在这一类。
  2. 唯一实测能真正 unmap 的形状是纯 C dylib（无 ObjC/Swift 内容）——但 mapped 行只为通过 `nameBytesHaveSwiftManglingPrefix` 的名字铸造，纯 C 镜像一个都不会有；export-trie 名走私有缓冲（拷贝）。能悬垂的没有行，有行的不会悬垂。
- **与 main 基线对比**：main 每行驻留拷贝的 `String`，无此暴露面；裸指针层随 evolution 0001 引入。
- **为什么不修**：两半暴露面都被结构性关死（上）。残余是内存安全的陈旧性问题：纯 C 镜像卸载后同址加载别的库，旧 `Storage`（仅有私有缓冲行，读安全）可能对新镜像被错误命中——答案错但不崩，且要求调用方索引纯 C dylib 再卸载再同址加载，窄到不值得为它上 `_dyld_register_func_for_remove_image` 驱逐钩子（对被 pin 的镜像该回调永不触发，等于常驻死代码）。review 建议的另一半「公开查询面改 vend 拷贝」同样拒绝：查询路径每次 vend 数十万个值，拷贝直接推翻 32 字节值 + 共享表的性能设计，为一个不可达场景付常驻代价。
- **既往修复**：无；生命周期约束在 proposal 0001 落地时已记录为接受项（「镜像需保持加载」——现在知道这在 Darwin 上是 dyld 免费保证的）。
- **代码锚点**：`SymbolTable` 类型注释（生命周期约束段，指回本条目）。
- **复审条件**：① Apple 改变 never-unload 语义（dyld 开始真正卸载含 Swift/ObjC 内容的镜像）；② 本库新增对非 Darwin 平台的 `MachOImage` 支持；③ 出现「索引纯 C 镜像」的真实消费者——届时优先考虑 remove-image 驱逐钩子而非 vend 拷贝。

---

## A5 — `detachedFromSharedTable()` 不随符号表一并拷出 node store（PR #103 review M5 的建议修法）

- **裁决**：拒绝按建议修（2026-08-09）；实际落地为文档收紧 + 回归测试钉住共享契约。
- **发现**：`detachedFromSharedTable()` 只重建符号表层，`demangledNode` 原样传递、仍引用 per-image node store（全镜像符号的 nodes + edges + 文本 arena）——review 判「回收是部分的，而 doc comment 读起来像完全 detach」，建议把 node 层也拷出并扩展 `SymbolTableRetentionTests`。
- **复现 / 是否误报**：现象属实（node store 确实不随 detach 释放），但**修法被读码推翻**：存储该 symbol 的定义自身的 `node` 字段就是**同一个** `NodeReference`（`DefinitionBuilder.makeFunctionDefinition` 等：`node = demangledSymbol.demangledNode`，不 detach，是 AGENTS.md 记录在案的「intended per-image recycling model」——活着的 definition 本来就该把它的 store 留活，打印名字要用）。只要 model 活着，兄弟字段就 pin 着同一个 store；在 detach 里拷贝 node 树回收为零，只多付每存储符号一次的分配。
- **与 main 基线对比**：main 无 `NodeReference` 层（0001 之前），无此问题域。
- **为什么这样裁决**：detach 的真实目的是让存储值不 pin 那张（definition 不需要的）符号表；node store 的生命周期被设计绑定在 model 上，二者分层清晰。缺陷只在 doc comment 的表述——已补上「detach 的是符号表层、node 层有意共享」的明文（`DemangledSymbol.detachedFromSharedTable()` doc），并新增 `storedDeclarationSymbolsShareTheDefinitionsNodeStore` 钉住共享（谁要改成拷贝必须先推翻这条测试、拿出测量）。
- **既往修复**：`a7caf944` 设计单层 detach（当时只有符号表层）；`6b0dad20` 加 arena 层未回访 doc——回访结论是设计成立、文档失准。
- **代码锚点**：`DemangledSymbol.detachedFromSharedTable()` doc comment；`SymbolTableRetentionTests.storedDeclarationSymbolsShareTheDefinitionsNodeStore`。
- **复审条件**：出现「declaration model 已释放、仅存储的 `DemangledSymbol` 长期存活」的真实消费形态（届时 node 层拷贝才有回收对象），或 profiling 显示 per-image node store 是驻留头部且 model 生命周期无法缩短。

---

## A6 — `machOFile(by:)` 对 plain-dylib 名字全量扫描、无 rank-0 以外的早退（PR #103 review L3）

- **裁决**：优化不做（2026-08-09，机制分析 + 测量双重裁决）；强制配套的 plain-`.dylib` 端到端用例已落地。
- **发现**：rank 公式下只有原生 canonical framework 能到 `bestMatchRank`（0），plain dylib 名（`libswiftCore` → rank 2）永远触发全部 cache 文件的完整扫描；review 建议「track the best rank still achievable and stop when the current match ties it」。
- **复现 / 是否误报**：扫描行为属实；但**建议的早退机制不成立**：持有 rank 2（dylib 命中）时，尚未扫描的 subcache 里仍可能存在 rank 0 的 framework 本体——「当前 rank 已是可达最优」这个判断在扫描中途无法安全做出，提前停恰是 `17ad4358` 要修的 SwiftUI→axbundle 顺序依赖误解析的复发形状（同名镜像跨 subcache 分布正是当年的触发条件）。rank 0 是唯一可靠的早退点，现状已实现。
- **与 main 基线对比**：main 是 first-match-wins（快但错）；ranking 线是记录在案的 correctness-for-speed 取舍。
- **为什么优化不做**：代价测出来是噪声级——当前系统 dyld cache（macOS 26，含全部 subcache）上 `machOFile(by: .name("libswiftCore"))` 全量扫描 **43 ms**（review 估计的「thousands of MachOFile constructions」实际单次构造微秒级），每次 CLI 调用至多一次。备选的「路径先行、只构造赢家」方案需在 MachOExtensions 里复刻 MachOKit `_machOFiles` 的枚举细节（main-cache imageInfos 回退、fileOffset 过滤），漂移风险大于 43 ms 的收益。
- **既往修复**：`17ad4358`（引入 ranking）→ `6647359e`（跨 cache 文件生效）→ 本轮第三次审视。三轮都没落的 plain-`.dylib` 用例这次落了：`DyldCacheEndToEndLookupTests`（当前系统 cache 上 `libswiftCore` 解析到 `/usr/lib/swift/libswiftCore.dylib`、`SwiftUI` 解析到原生 framework 本体且非 iOSSupport）。
- **代码锚点**：`DyldCacheEndToEndLookupTests` 的套件注释。
- **复审条件**：① 出现高频调用 `machOFile(by:)` 的新消费形态（当前每 CLI 调用一次）；② MachOKit 上游暴露 `(imagePath, fileOffset)` 级枚举后，「只构造赢家」无需复刻内部细节——届时可顺手做。
