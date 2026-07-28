# NodeStore 迁移遗留问题清单

本文记录 `feature/node-store-migration` 分支上**已确认但尚未修复**的问题，供后续按优先级处理。每条注明成因、影响面、以及"该在哪里修"（有几条的正确修复位置在上游 `swift-demangling`，不在本仓库）。

产生方式：2026-07-28 对该分支做了两轮代码审查 + 一轮结论复核。第一轮的复核记录见 [TaskReports/2026-07-28-review-verification-and-fixes.md](TaskReports/2026-07-28-review-verification-and-fixes.md)，其中三条已在本分支修掉（`printSemantic` 换用引擎预算入口、`registerRow` 按桶去重、dyld 缓存镜像选择的 Catalyst 平局与子缓存遍历）。本文只列**仍然打开**的。

---

## 一、上一轮修复自身的缺口

这两条是 2026-07-28 那批修复引入或未覆盖的，优先级最高——它们让已经宣称修好的问题只修了一部分。

### 1. Catalyst 降级只覆盖了 framework 形态，plain dylib 仍然平局

`DyldCache+.swift` 的 `matchRank` 把 `/System/iOSSupport` 的判断写在了 `<name>.framework` 分支**内部**。一个既不在 `<name>.framework` 下、叶名又以 `.dylib` 结尾的镜像走不到那个判断，于是原生与 Catalyst 两份同名 dylib 双双落在 2 级，胜负重新取决于缓存文件的枚举顺序——正是这次排序机制要根除的那类不确定性。

本机实测存在的碰撞：

```
/System/Library/Frameworks/OpenGL.framework/Versions/A/Libraries/libGLVMPlugin.dylib
/System/iOSSupport/System/Library/Frameworks/OpenGLES.framework/Versions/A/Libraries/libGLVMPlugin.dylib
```

`-n libGLVMPlugin` 对两者都返回 2 级。另有 `/System/iOSSupport/usr/lib/swift/libswift{QuickLook,HomeKit,PencilKit}.dylib` 一组，目前**没有**原生同名物，属于"将来会踩"而非当下已坏。

**正确修法**：把支持根的判断提成一次性的**惩罚项**，在形态分类**之前**施加，而不是塞进某个分支里。例如先算形态基准分（framework 0 / dylib 1 / 其他 2），再对 `/System/iOSSupport` 下的结果统一加一档。这样任何形态的 Catalyst 变体都稳定劣于同形态的原生物。

**修复位置**：本仓库 `Sources/MachOExtensions/DyldCache+.swift`。

### 2. `appendRowIfAbsent` 是线性扫描，桶变大就退化成 O(n²)

`registerRow` 的去重改成了 `symbolRowsByOffset[offset]?.contains(row)`，对桶做线性扫描。注释里断言"桶实际上只有一两行"，但没有任何东西保证这一点——不同符号名合法地共享同一地址（桶之所以是数组就是因为这个），而退化偏移（0，或 stripped / dyld 缓存镜像里被大量别名的地址）可以攒到上千行。那样每次登记都是 O(桶大小)，整趟采集变成 O(n²)。

**正确修法**：重复只来自两个已枚举的成因，不需要通用去重。可以只记住每个偏移最近一次追加的行，或者仅在 `canonicalOffset == rawOffset` 时配合一个按名字的已见集合来挡。

**修复位置**：本仓库 `Sources/MachOSymbols/SymbolIndexStore.swift`。

---

## 二、公开 API 语义问题

### 3. 两个公开查询 API 的字典键从结构相等翻成了身份相等

`memberSymbols(of:excluding:in:)` 与 `allOpaqueTypeDescriptorSymbols(in:)` 原本返回 `OrderedDictionary<Node, …>`。`Node` 的 `==` 是结构相等，所以外部调用方拿任意来源的节点做下标查询都能命中。现在键是 `NodeReference`，其 `==` 为 `store === store && index == index`。调用方用自己 demangle 出来的节点查询会**恒定返回 nil，且没有任何编译错误**。

仓库内部这两个 API 只被遍历、从不下标查询，所以测试全绿也发现不了。`StructuralNodeReferenceKey` 这套处理施加到了所有内部集合上，唯独漏了这两个**逃逸到外部**的面。

现状缓解：扫过 RuntimeViewer 的 `main` 与 `feature/node-store-adoption`，两条分支都没有调用这两个 API，所以目前没有现实触发者。

**正确修法**：要么改成 vend `StructuralNodeReferenceKey`（或干脆 `Node`）作键，要么不暴露裸字典、改提供一个查询方法。

**修复位置**：本仓库 `Sources/MachOSymbols/SymbolIndexStore.swift`。

---

## 三、性能问题

### 4. `structuralHash` 每个文本节点分配一个 `String`

`StructuralNodeReferenceKey.hash` 委托给上游 `NodeReference.structuralHash`，后者对文本节点执行 `hasher.combine(text)`，而 `NodeReference.text` 会走 `NodeStore.text(offset:length:)` → `String(decoding:as:)`——每个标识符/模块节点每次哈希都堆分配一次。迁移前的 `Node` 键组合的是节点里**已经存在**的 `String`。

影响面不小：`TypeName` / `ProtocolName` / `ExtensionName` 是 `SwiftDeclarationIndexer` 里几乎每个索引的键，`DefinitionBuilder` 还会对**整棵符号根节点**每个成员构造两次 `StructuralNodeReferenceKey`。

**正确修法**：改哈希 `textUTF8`（`NodeReference` 上已有，返回 `ArraySlice<UInt8>`，零拷贝）而非 `text`。

**修复位置**：**上游 `swift-demangling`** 的 `Sources/Demangling/Store/NodeReference.swift`，不是本仓库。本仓库这一侧无法绕开。

### 5. `memberSymbols(of:for:node:)` 从 O(1) 退化成线性扫描 + 逐候选全树比对

迁移前是 `memberSymbolsByKind[$0]?[name]?[node]`，一次哈希查找。现在两个重载都走 `rowsByTypeNodeIndex.elements.first(where: { …structurallyEquals(node) })`——对桶里每个键做一次结构化树遍历直到命中。

`TypeDefinition.index` 会为 allocator、变量、静态变量、函数、静态函数、下标各调一次，所以每个被索引的类型付 6 × 桶大小次结构遍历。

**正确修法**：在 `Storage.init` 里一次性建一份 `[StructuralNodeReferenceKey: NodeStore.NodeIndex]` 旁路索引恢复 O(1)——这正是 `opaqueTypeDescriptorEntriesByMemberIdentifier` 已经用过的手法。

**修复位置**：本仓库 `Sources/MachOSymbols/SymbolIndexStore.swift`。

### 6. build sweep 由并行改为串行，且每个符号都无条件跨线程往返

原来是 `symbolArray.concurrentMap { try? demangleAsNode($0.name) }`，N 路并行。现在是单趟顺序循环，且每次 `demangleAsNodeTransient` 走的是 `StackSafeExecutor.execute`（不是打印/重编码路径用的 `executeWithinStackBudget`）。`buildStorage` 跑在 512 KB 栈的线程上，于是一个框架里几十万个符号，**每一个**都付一次线程池提交 + 信号量等待，而且没有并行来摊薄。

**正确修法**：`demangleAsNodeTransient` 应当像打印器那样改用带预算的入口。

**修复位置**：**上游 `swift-demangling`** 的 `DemangleInterface.swift`。本仓库改不动。

### 7. `ABIKey.make` 泛型化后每个 key 都要 materialize 整棵树

`ABIKey.make(for:)` / `makeUnwrappingType(for:)` 泛型化到 `DemanglingNode` 之后，走的是 `mangleAsString` 的 `DemanglingNode` 重载，其实现是 `mangleAsString(node.materializedNode)`。而 `TypeName.node` / `ProtocolName.node` / `FieldDefinition.typeNode` / `FunctionDefinition.node` 现在全是 `NodeReference`，于是构建 `ABISnapshot` 时每个类型、协议、扩展容器、成员、字段的 key 都会重建一整棵类树再丢掉。

**正确修法**：`mangleAsString` 增加一条 store 原生路径（上游），或 `ABIKey` 改成每个声明 materialize 一次而非每个 key 一次（本仓库）。

**修复位置**：上游或本仓库 `Sources/SwiftDiffing/ABIKey.swift`，取决于选哪条路。

---

## 四、代码卫生

### 8. `Symbol.isExternal` 在符号表里恒为 `false`

采集局部符号的循环已经用 `where … && !symbol.nlist.isExternal` 过滤掉了外部符号，导出符号循环走默认参数 `isExternal: false`。所以 `symbolTable` 里没有任何一行能是 `true`，`if !symbol.isExternal` 的守卫永远成立、是死代码。而 `Symbol.swift` 的注释声称这个标志是被提取出来供后续查询的，与实际不符。该字段只有在非索引存储的 `Symbol.resolve` 路径（`asCurrentSymbol`）上才可能非 `false`。

过滤和守卫二者必有其一冗余，需要挑一个删掉并修正注释。

### 9. `lateDemangledNode(forName:)` 在持锁期间 demangle

`demangleAsNodeTransient` 会走 `StackSafeExecutor.execute`，在 512 KB 栈线程上无条件提交线程池并 `semaphore.wait()`。于是一次 miss 会**在持有 per-image 互斥锁的情况下**跨线程等待不定时长，该镜像上所有查询晚绑定名字的线程都排在它后面；线程池饱和时持锁时间无上界。

注意这是**刻意的权衡**：代码注释写明查找与插入必须同处一个临界区，否则两个并发 miss 会各自冻结一份 mini store，把同一名字的引用分裂到不同 store 里。所以修的时候要保住这个保证。

**正确修法**：在锁外 demangle，锁内用 insert-if-absent（后写者放弃、返回胜出者），单 store 保证不变而临界区里不再阻塞。

### 10. `ProtocolConformanceDumper` 里一个分支还在 materialize

同一个 `switch requirement` 块里，`case .element` 和 `Self.demangledSymbol(...)` 都已改走 `MetadataReader.demangleSymbolReference` 留在 store 上，唯独 `case .symbol` 仍调 `MetadataReader.demangleSymbol` 把整棵树 materialize 出来，只为交给 `demangleResolver.resolve(for:)`——而后者现在有 `some DemanglingNode` 重载，可以直接吃引用。既多余，又会让下一个维护者误以为这个不一致是有意的。

### 11. 两处 `throws` 是迁移残留

`ExtensionDefinition._symbol(for:typeName:visitedNodes:)` 与 `ProtocolDefinition` 里对应的那个，唯一的抛出调用已被换成不抛出的 `demangleSymbolReference`，函数体里不再有任何 `try`，但签名仍是 `throws`，调用点仍写 `try`。删掉 `throws` 之后，周围 `if let` 链里真正会抛的调用（`resilientWitness.implementationSymbols(in:)`、`Symbols.resolve`）才看得出来。

---

## 五、分支状态

### 12. 落后 `main` 五个提交，`AGENTS.md` 两侧都改过

`main` 已发布 `0.14.0`，并新增了注释模板的命令行接口（`--enum-layout-template` / `--enum-layout-case-template` / `--enum-layout-byte-template`）及其 `AGENTS.md` 章节。本分支的 `AGENTS.md` 还是 0.14.0 之前的正文，另外加了自己的 NodeStore 段落。直接合并会冲突，而**保留分支侧的粗暴解法会静默回退掉 `main` 的那份文档**。

同理，`ProjectEvolutionLog.md` 里本分支新增的 `## 19.` 把原「引用存储」小节顶成了 `## 20.`，与 `main` 的 `## 20.` 正面撞号；两条新小节都写"将入 0.14.0"，而 0.14.0 已经发布。另有一条指向 `TaskReports/2026-07-25-dyld-cache-image-selection-...` 的链接是死的（实际文件名无 `dyld-` 前缀）。

此外，`main` 的 `TransformerOptionGroup` 与本分支的 `DemangleResolver` / `printSemantic` / `FieldDefinition.typeNode` 改动之间的交互从未被跑过。

**处理顺序**：先 rebase 到 `main`，重编演进日志小节号、修死链、对齐 `AGENTS.md`，再谈合并。演进日志的小节应在 rebase 之后补，现在写只会加深冲突。
