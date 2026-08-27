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

---

## A7 — 索引器与 dump 路径的 conformance witness 匹配用不同 print options（PR #103 第二轮 review）

- **裁决**：本轮不修，记录待查（2026-08-13）。
- **发现**：`ExtensionDefinition.index(in:)` 的 witness 匹配（`ExtensionDefinition.swift:150`）用 `.interfaceTypeBuilderOnly` 打印符号侧类型名，而 dump 路径的同款循环（`ProtocolConformanceDumper.swift:185`）用 `.interfaceType`。两者只差一个 `.displayObjCModule` 标志，所以一个 ObjC 导入类型在前者打印成 `__C.NSObject`、在后者是 `NSObject`。两条路径的 fallback 子句都查 `PrimitiveTypeMappingCache.shared.storage(in:)?.primitiveType(for: typeName)`，而 `PrimitiveTypeMapping` 的键是**裸** descriptor 名（`PrimitiveTypeMapping.swift:26`，`descriptor.name(in: machO)`，从不带模块限定）。推论是：对某个只能经 primitive mapping 匹配上的 conformance，`swift-section dump` 绑定到具体 witness 符号，而 `swift-section interface` 落到 requirement 分支。
- **复现 / 是否误报**：**未能构造出触发场景，因此不作为已确认缺陷**。print options 的分歧与 mapping 键的裸名形态都已逐行核对属实，但触发还需要一个"带 ObjC 导入 typedef 原始类型、且携带 resilient witness"的真实框架；仓库内无 fixture 覆盖（`grep -rn 'extension __C\.' Tests/` 为空）。另需注意：`typeName` 参数是外部传入的 `extensionName.name`，不是用同一 option 现算的，所以 `symbolTypeName == typeName` 那一半是否受影响也取决于 `ExtensionName` 的构造选项——初版分析曾误断为"不可观测"，实际未定。
- **与 main 基线对比**：**main 上完全相同**（aa38ff5 的两处有一模一样的 option 分歧与裸名键）。非本 PR 引入；本 PR 只是重写了这几行所在的区域。
- **为什么本轮不修**：无法复现的旧问题，改任一侧的 print option 都会影响 witness 绑定这一敏感路径，而没有测试能证明改动方向正确。盲改的风险大于收益。
- **既往修复**：无。两处自各自模块拆分以来就是这样。
- **复审条件**：① 出现 `extension __C.<Type>` 的真实用户报告或 fixture；② 为 ObjC 导入类型的 resilient conformance 补 fixture 后重测两条路径的输出差异。届时正确修法是让两条路径共享同一个匹配 helper（含同一套 print options），而不是各自调 option。

---

## A8 — `updateConfiguration` 的 re-prepare 因 `isPrepared` 早退而是 no-op（PR #103 第二轮 review）

- **裁决**：不修（2026-08-13）。
- **发现**：`SwiftDeclarationIndexer.updateConfiguration(_:)` 在 `showCImportedTypes` 变化时调 `try await prepare()` 重建索引，但 `prepare()` 第一行是 `if isPrepared { return }`，而 `isPrepared` 在首次 prepare 结束时就置 true——所以配置变了索引并不会重建，这个分支实际是空操作。
- **复现 / 是否误报**：机制属实。但**当前无消费者能触发**：仓库内 `updateConfiguration` 零调用点；已知的下游消费者 RuntimeViewer 把 `showCImportedTypes` 硬编码为 false，那个分支永不进入。
- **与 main 基线对比**：main 字节相同。非本 PR 引入。
- **为什么不修**：正确修法（重置 `isPrepared` 与全部 storage 后重建）等于给一个无人调用的路径加一次全量重索引，且需要想清楚重建期间已 vend 出去的 definition 引用怎么办（它们持有 per-image store）。在没有真实消费者定义期望语义之前，改动只会引入未经验证的行为。
- **既往修复**：无。
- **复审条件**：任一消费者真正开始在运行时切换 `showCImportedTypes`——届时先定义"重建期间旧 definition 引用的语义"，再动实现。

---

## A9 — 两个公开批量查询的字典键从结构相等翻成身份相等（**推翻 2026-08-03 的「不修」**）

- **裁决**：**已修**（2026-08-14）。本条推翻 [`NodeStoreMigrationOpenIssues.md`](NodeStoreMigrationOpenIssues.md) 第 3 条 2026-08-03 的「不修」结论，该条目已标记为被本条取代。
- **发现**：`allOpaqueTypeDescriptorSymbols(in:)` 与 `memberSymbols(of:excluding:in:)` 原本返回 `OrderedDictionary<Node, …>`（`Node` 的 `==` 是结构相等），迁移后键成了 `NodeReference`（`==` 是 `store === store && index == index`）。调用方拿自己 demangle 的树下标查询会**恒定返回 nil，且没有编译错误**。
- **当初为什么裁「不修」**：`SymbolIndexStore` 在类型层面就是 SPI（`@_spi(ForSymbolViewer)` / `@_spi(Internals)`），包内唯一调用点只遍历不下标，RuntimeViewer 两条分支零调用——契约只对包内与已知 SPI 消费方成立，保证包内正确即可。这些事实至今仍然属实（2026-08-14 复核：仓库内与 RuntimeViewer 源码依旧零调用点）。
- **为什么推翻**：① **同一类错误已经真实咬过一次**——Stage 5a 的回归里，身份相等的键让 `override` 关键字与 vtable offset 注释成批消失，单条版 `opaqueTypeDescriptorSymbol(for:)` 正是为此改成结构化键的；这两个批量版是那次修复漏下的，属于同一类而非同一处。② **修复成本是每处一行**（键类型换成 `StructuralNodeReferenceKey`），而 08-03 条目自己就写好了修法。③ **本 PR 本就在 break 这块 API**，同批改动的迁移成本最低。④ 「目前没有外部调用方」是会变的，而这个失败模式无声无息、无编译错误。
- **落地**：两处键类型改为 `StructuralNodeReferenceKey`；该类型从 `package` 提升为 `@_spi(Internals) public`（连同 `init(_:)` / `init(querying:)`），否则 SPI 消费方能拿到字典却没法构造查询键——那等于把陷阱换了个形状。包内 `DefinitionBuilder.swift` 的 `import MachOSymbols` 相应补上 `@_spi(Internals)`。测试 `bulkOpaqueQueryIsProbableWithACallerDemangledTree` 用 `materialize()` 出的「无 store 的树」逐条探测，正是外部调用方的处境。
- **既往修复**：Stage 5a 的单条版修复（见上）。本条是同一 bug 类的第二处实例。

---

## A10 — `OrderedMember.minSymbolOffset` 「每次比较分配一个 String」（**误报**）

- **裁决**：误报，不修（2026-08-14，PR #103 第三轮 review）。
- **发现（原报告）**：`DemangledSymbol.symbol` 由存储属性变成了会构造完整 `Symbol`（含 `String(decoding:)` 物化 mangled name）的计算属性，而 `minSymbolOffset` 仍读 `.symbol.offset`，且它被 `sorted { }` 的比较器调用，所以成员排序变成每次比较一次 String 堆分配。
- **为什么是误报**：`f.symbol` 的静态类型就是 `DemangledSymbol`（`FunctionDefinition.symbol` / `Accessor.symbol` 都是存储属性），`.offset` 命中的是 `DemangledSymbol` 自己声明的**具体属性**（`canonicalOffset(atRow:)`，纯数组读），不是经 `@dynamicMemberLookup` 转到 `Symbol.offset`——SE-0195 规定 dynamic member subscript 只在常规成员查找失败时参与。main 上同一表达式经 dynamic member 转发到存储的 `Symbol`，同样是字段读，**无回归**。原报告据以区分对错的两处（`SwiftDeclarationPrinter.swift:456/463/471` 与 `OrderedMember.swift:25/27/29`）是**完全相同的表达式形状**，那个区分不成立。
- **排他性普查（交叉复核补充）**：全 `Sources/` 的 `.symbol.` 共 13 处——打印器 4 处 deallocator/destructor（真的两跳，已在本批修为 `.offset`）、打印器 3 处 + `OrderedMember` 3 处（快路径）、`DefinitionBuilder` 2 处读 `\.symbol.demangledNode`（`DemangledSymbol` 的存储属性，快）。且 `Symbol` 只有 `offset` / `name` / `isExternal` 三个存储成员，`DemangledSymbol` 对三者都有具体快路径，`demangledNode` 又被自身存储属性遮蔽——不存在 grep 看不见的隐式慢读。「慢的只有那 4 处」是穷尽结论，不是抽样。
- **复审条件**：`DemangledSymbol` 若移除任一具体快路径属性（`offset` / `name` / `isExternal`），本条结论作废，需重新普查。

---

## A11 — `SwiftDiffableInterfaceBuilder.prepare()` 无 per-definition catch

- **裁决**：本轮不修（2026-08-14，PR #103 第三轮 review）。
- **发现**：`prepare()` 用裸 `try await` 循环驱动每个 type / protocol / extension 的 `index(in:)`，一个坏 descriptor 会中止整个 `swift-section snapshot` / `diff` / `evolution` 构建，而 interface 路径对同样的抛错是 per-definition catch + 事件。
- **与 main 基线对比**：**文件与 merge-base 字面零 diff**，且 `index(in:)` 在 main 上本来就会抛、`prepare()` 本来就整体中止。非本 PR 回归。
- **本 PR 带来的变化（caveat，必须记住）**：三个 `index(in:)` 内新增了 materialize 抛错点（`TypeDefinition.swift:223` / `ProtocolDefinition.swift:149` / `ExtensionDefinition.swift:140`；main 读存储属性不可能抛），所以**失败面变宽了**——同样的结构，触发概率上升。
- **为什么本轮不修**：它不是本 PR 的回归，改法（per-definition catch + 诊断）与批次 2 的可观测性工作同源但属于独立范围；混进来会让本已很大的 PR 更难审。
- **复审条件**：① 出现真实的 snapshot/diff 构建被单个坏 descriptor 中止的报告；② 或下一次触碰 `SwiftDiffableInterfaceBuilder` 时顺带补上——修法很便宜（照 `SwiftInterfaceBuilder.printRoot` 的 per-definition catch 抄）。

---

## A12 — 每次操作重复 materialize 一次包装器（协议 / 扩展 / 类各 2 次）

- **裁决**：本轮不修，先测量（2026-08-14，PR #103 第三轮 review）。照 [A3](#a3--接口打印器每成员-materialize-一棵树swiftdeclarationprinter-7-处) 的先例——同类成本用实测数据裁决，不靠推理。
- **发现**：proposal 0002 的「每次操作至多一次 materialize」规则实际是 2 次。协议：`printProtocolDefinition` 一次 + `ProtocolDefinition.index:149` 一次；扩展：`index(in:)` 一次 + `printExtensionHeader` 一次（代码注释自己写着 both run this same materialization）；类：`TypeDefinition.index:223` 建 `Class` + `printTypeDefinition:132` 建 `TypeContextWrapper`（对类同样落到 `Class`）。main 读存储属性是 0 次。
- **与 main 基线对比**：本 PR 引入，是 proposal 0002 用 CPU 换内存的既定代价——只是超出了它自己写下的规则。
- **为什么先不修**：规则只写在 doc comment 里，`DeclarationModelInstanceSizeTests` 钉的是保留字节数而非 materialize 次数，所以没有任何测试会因此变红；而 A3 的先例表明这类成本的直觉常常错（那次实测占比 1.18%，远低于估算）。**测量范围必须包含 diff 路径**（builder 的 `prepare()` + DiffRendering 的 header 对 class/protocol 同样是 2×，extension 是 1×）**与 specialize 路径**（`TypeDefinition+Specialization.swift:206` 与 `ConformanceProvider` 各一次）。
- **修法（测出来值得再动）**：把那一次 materialize 提到 `index(in:)` 之前传进去——`printTypeDefinition` 已经是这个写法（它把 `materializedTypeContext` 线程给 `renderTypeDeclarationHeader`）。
- **复审条件**：SwiftUI 级镜像的剖析显示 materialize 占打印墙钟的比例显著高于 A3 实测的 1.18%。

---

## A13 — 导出状态标注在 stripped 二进制上因 `To` thunk 缺失而豁免失效（PR #111 review A4）

- **裁决**：误报（2026-08-23）。
- **发现**（review 原话大意）：interface 路径的 `@objc` 豁免依赖 `SwiftAttribute.objc`，而它由 `MemberAttributeInferrer` 从符号表里的 `To` thunk 推断——dyld cache 镜像或剥了 local 符号的二进制没有该符号，豁免失效，每个 `@objc dynamic` 成员都会被标 `// not exported`。
- **复现 / 是否误报**：**误报——触发条件自相矛盾**（同侪复核后一致确认，成因表述从「To 与实现符号同生共死」修正为更严密的模型构造论证）。成员定义是**符号驱动**的：`FunctionDefinition.symbol` 非可选，`DefinitionBuilder` 的全部构造点都从 `DemangledSymbol` 建。要触发假阳性须同时满足：成员在模型里（实现符号在）、该成员全形态 trie-miss（确实不导出）、且是 `@objc dynamic`。逐端封死：① 剥离场景——不导出的 `@objc dynamic` 成员的实现符号必然是 local symtab 符号，剥掉后成员根本不进模型，无行可标；② 未剥离场景——实现符号与 `To` thunk 同在，属性推断得出，豁免生效；③ 导出的 `@objc dynamic` 成员——派生查询直接命中 `true`，压根不发标注。
- **与 main 基线对比**：标注是 PR #111 新增，无基线可比。
- **既往修复**：无。
- **复审条件**：出现「实现符号保留而 `To` thunk 被选择性剥除」的真实输入（自定义 strip 脚本 / 非常规链接产物）。届时 dump 侧已有的 `containsSymbol(named: name + "To")` 口径可以直接搬到 interface 侧作第二道豁免。

---

## A14 — `not exported` 注释不走 OutputTransformer token-template 机制（PR #111 review B2）

- **裁决**：不修（2026-08-23）。
- **发现**：`DeclarationRenderConfiguration` 里其他注释种类（member address / field offset / vtable offset / type layout / enum layout）都有 `…Transformer` 闭包槽并经 `applyTransformers(_:)` 物化为 token 模板；`not exported` 硬编码，没有 `Transformer.SwiftExportStatus` 模块、没有 `--…-template` CLI 选项，RuntimeViewer 设置界面与 `--transformer-config` 都控制不了它。
- **复现 / 是否误报**：属实，非误报——机制差异客观存在。
- **与 main 基线对比**：PR #111 新增，无基线。
- **为什么不修**：transformer 机制的价值在**有变量 token 的注释**（offset、address、size/stride、case 字节模式——模板决定这些值如何呈现）。`not exported` 是零参数的固定事实陈述，模板化只能改文案措辞，而措辞恰恰是这个标注的语义承重部分（「符号表事实、非访问级别猜测」的措辞边界是提案审议的产物，开放自定义反而请人破坏它）。RuntimeViewer 若需要开关，`printExportStatus` 这一个 Bool 就是全部所需表面。
- **既往修复**：无。
- **复审条件**：出现真实的自定义需求（如本地化、或工具链要求不同 marker 文本）；届时补一个单 token（`${status}`）模块即可，机制上无障碍。

---

## A15 — CF `Ref` 剥除规则不加「原名已在索引」守卫（PR #110 review 发现 8）

- **裁决**：不修守卫（2026-08-23）。
- **发现**：review 建议在剥除前查 `moduleNamesByTypeName[cName] == nil`，避免「`XxxRef` 本身是索引里真实存在的类型时被误剥」。
- **复现 / 是否误报**：机制上可构造，但无真实实例——SDK 全部 80 个 apinotes 的 6145 个条目中**零个**以 `Ref` 结尾（review 会话实证），swift-api-digester dump 的 CoreFoundation 同样没有。
- **这是不是刻意设计**：是。commit `97d9f39a` 记录了 CG/CV/CM 实测：同一类型两种 mangling 形态并存（签名 `__C.CGContextRef`、字段元数据 `__C.CGContext`），「剥后名存在于索引」正是有意选的判据。反向风险真实：interface 提取会收进 obsoleted 的 typealias stub（`CFStringRef` 在 Swift 里是编译器认识的重命名 stub），加守卫可能把 CF 剥除整体关掉。
- **复审条件**：出现「以 `Ref` 结尾、且剥后名恰好是另一个真实类型」的实例。

---

## A16 — interface 输出的 import 列表不含被解析出的真模块（PR #110 review 发现 11）

- **裁决**：不修（2026-08-23）。
- **发现**：`--resolve-c-module-names` 后 body 里出现 `CoreFoundation.CFString`，import 列表却没有 `import CoreFoundation`。
- **与基线对比**：基线上同位置是 `__C.CFStringRef`，`__C` 同样不在 import 列表（`filterModules` 排除）——不自洽的形式早已存在，本 PR 只是把它换成了可读的真模块名。恢复出的 interface 本不以可编译为目标。
- **复审条件**：interface 输出立「可编译」目标时一并处理（import 列表需要整体重derive）。

---

## A17 — `TypeDatabase` 懒索引循环的 actor 重入窗口（PR #110 review 发现 12）

- **裁决**：暂不修（2026-08-23）。
- **发现**：`moduleName(forTypeName:)` 的 `while` 循环在 `removeFirst()` 之后 `await indexObjCMetadata(of:)`，actor 重入可让两个并发查询交错弹出依赖，索引结果仍正确但一个 image 可能被并发索引两次（浪费，不腐化状态）。
- **与基线对比**：本 PR 引入（基线无此代码）。库内不可达：打印是顺序 await（`SwiftDeclarationPrinter` 无并发驱动），无并发调用方。
- **复审条件**：TypeDatabase 出现并发消费方（如 GUI 宿主并行打印多镜像）时加 in-flight 去重。

---

## A18 — 补充 APINotes 条目可覆盖任意同名 SDK 条目（PR #110 review 发现 13）

- **裁决**：不修（2026-08-23）。
- **发现**：用户提供的补充文件对同名 C 名后写覆盖，不限于它自己声明的模块——理论上可劫持无关 SDK 类型的归属。
- **这是不是刻意设计**：是。提案 0010 明确把「覆盖 SDK 条目」列为修正官方数据错误的通道（「碰到直接替换」是用户原话）；补充文件是用户自己提供的，信任边界在用户手里。实测 SDK apinotes 与 AttributeGraph 样例无名字冲突。
- **复审条件**：出现真实的意外覆盖报告——届时可加「补充条目限制在其声明模块的 C 名前缀」的可选严格模式。

---

## A19 — `printModule` 对 `__C` identifier 的双查询（PR #110 review 发现 14）

- **裁决**：不修（2026-08-23，微优化）。
- **发现**：review 原文称「绝大多数引用都要查两次」；核实后 `or` 的第二参数是 `@autoclosure`（`Utilities/OrFunctions.swift`），仅在第一查询 miss 时才发生第二次。
- **为什么不修**：仅 miss 路径多一次字典探查，无测量证据表明可感知；加 `hasSuffix("Ref")` 前置判断属纯微优化。
- **复审条件**：profiling 显示该路径可感知。

---

## A20 — 统一 walker 的 key 去重丢弃同 key 重复声明（PR #118 review 发现 3，**误报**）

- **裁决**：误报 / 有意行为，不修（2026-08-27）。
- **发现**：`InterfaceUnionWalker.matchAcrossVersions` 用 `seen.insert(elementKey).inserted` 门控 emission，而它替换掉的 `SwiftDiffableInterfaceRenderer.diffMembers`（main `:428`）与 `matchByKey`（main `:556`）遍历新侧全部元素——identity key 碰撞时旧路径两个都渲染，新路径只渲染第一个。review 据此判定 `swift-section diff --interface` 会静默少渲染成员。
- **复现 / 是否误报**：行为差异属实，但**定性错误**。walker 的文档注释明写 "Keys are first-wins within each version (emission included…) mirroring `ABIDiffer.keyed`"，`draft-unify-interface-renderers.md` 的决策日志（2026-08-26）专条记载：实现中确认旧 diff 发射循环对同 key 重复项重复发射，与其**自身查表字典**和注释声明的 first-wins 相矛盾，判定为漏网，统一后连发射也 first-wins；恰好依赖旧行为的测试 `unrenderableHeaderIsReportedAsAnEvent` 同批改成 replace 注入。旧行为也并非「更正确」——第二个重复项是与 first-wins 的旧侧条目**错配比较**后发射的。
- **与 main 基线对比**：行为变化确由本 PR 引入，但项目已把旧行为定性为 bug，故不是回归。
- **既往修复**：无。这是首次把发射对齐 first-wins 的 deliberate 改动。
- **残余关切（不构成缺陷）**：`--interface` 模式直接从 live model 渲染、不经 `ABIDiff`，所以 `keyCollisions()` 诊断在该视图无处输出。**main 同样如此**，属可选增强而非本 PR 缺陷。
- **代码锚点**：`Sources/SwiftInterface/InterfaceUnionWalker.swift` `matchAcrossVersions` 的 first-wins 注释。
- **复审条件**：把碰撞诊断带进 interface 视图（事件或注释形式）被单独提案时，本条目关闭。

---

## A21 — `symbolCount(of:in:)` 把「无 symbol store」折叠成 `0`（PR #118 review 发现 9，**误报**）

- **裁决**：误报，不修（2026-08-27）。
- **发现**：`SymbolIndexStore.symbolCount` 的 `guard let storage = storage(in: machO) else { return 0 }` 会把构建失败折叠成零计数，于是 `InterfaceHeaderBlock` 在 resilient 二进制上打印断言式的 `Library evolution: not detected (0 dispatch thunks)`，而属性文档承诺 `nil` 时省略该行。
- **复现 / 是否误报**：**声称的触发机制是死代码**。`buildStorageSweep` 唯一出口是 `return Storage(...)`——任何输入（含无符号表镜像）都产出一个可能为空的 `Storage`，`storage(in:)` 的 `nil` 分支实践不可达。把 guard 改成返回 `nil` 也改变不了任何输出。
- **与 main 基线对比**：不适用（不可达）。
- **为什么不修**：`0 → not detected` 是 test-pin 的设计行为（`zeroThunkCountRendersNotDetected`），属性文档自陈零计数合法，提案 0008 明确。
- **可选增强（低价值）**：若要更诚实地区分「判定」与「无证据」，可另做 `hasExportInformation` 之类的证据信号；与本条裁决无关。
- **复审条件**：`storage(in:)` 出现真实可达的 `nil` 路径（例如惰性构建改成可失败）。

---

## A22 — `final` 恢复的名字查找可被同名私有兄弟污染（PR #118 review 发现 4/5，**已修但无法构造触发场景**）

- **裁决**：代码**已修**（2026-08-27），但复现**构造不出**；本条登记的是「不要再为它找复现」的结论。
- **发现**：`ClassDumper.vtableAccessorFieldNames` / `storedAccessorFieldNames`（3 处）与 `TypeDefinition.index` 的两处 `final` 门控（`thunkAttributeMembers` / `methodDescriptorMemberSymbols`）走的是**只按名字**的合并桶，而同一 PR 在三行外的成员循环里已改成传 node 并留了 issue #115 的注释。
- **修了什么**：5 处全部改成 node 匹配（`contextNode` 拿不到时退回名字查找，沿用 `ClassDumper.members` 已确立的写法），并补齐两个缺失的镜像重载：`thunkAttributeMembers(of:for:node: Node,in:)` 与 `methodDescriptorMemberSymbols(of:for:node: NodeReference,in:)`。碰撞不存在时行为逐字节不变。
- **复现 / 是否误报**：**构造不出触发场景**，三条独立理由，均经实测：
  1. 同名只能靠 `private`/`fileprivate` 分文件取得——Swift 拒绝同名的 `internal`/`private` 配对（`error: invalid redeclaration of 'PrivateDoppelgangerClass'`，实测）。
  2. `private` class **不发 `Tq` 方法描述符符号**（`SymbolTestsCore` 全库 770 个 `Tq`，doppelganger 一个没有），所以 `methodDescriptorMemberSymbols` 门控从任一兄弟都读不到负面证据。
  3. `private` class 的**存储属性访问器符号在 Release 下不存在**（`final var` 也印不出 `final`，因为证据门 `accessors.isEmpty` 直接落空），而 `objcThunkMemberNames` 那条门控**只作用于存储字段**（functions/variables/subscripts 三个循环读的是 per-member 的 `attributes.contains(.objc)`，那个属性来自已经 node 匹配的 `applyThunkAttributes`）。
- **为什么仍然修**：改动是严格更安全的收紧，与本 PR 自己在相邻代码里声明的不变量一致，且无碰撞时零行为差异；留着一个「已知按名字查、只是恰好没人能触发」的查询是下一次回归的种子。
- **测试**：`FinalMemberRecoveryTests.sameNamedPrivateClassesGetIndependentFinalVerdicts` 是**防回归钉子而非复现**（夹具 `PrivateDoppelgangerClass` 对，一边非 final、一边 `final`），测试注释与本条目互引。
- **复审条件**：① 在真实框架二进制上观察到同名私有类型且其中一方贡献了 `Tq` 或存储属性访问器符号；② 上游工具链改变私有类型的符号发射策略（例如为 `private` class 也发 `Tq`）——届时本条的三条理由需重测。
