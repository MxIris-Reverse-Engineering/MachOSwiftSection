# 0045 - 展不开的 opaque 引用改用 `@_opaqueReturnTypeOf` 拼法，`(some P).Element` 化简为 type witness，`numUnderlyingTypeArguments` 改名

- **状态**: Implemented
- **创建日期**: 2026-09-18
- **最后更新**: 2026-09-26
- **所属愿景**: 无
- **关联提案**: [0033](0033-by-name-opaque-reference-expansion.md)（按名字引用的 opaque 类型展开）、[0028](0028-offline-opaque-accessor-thunk-resolution.md)（可用性分支的 witness 注释机制，本提案的 dump 注释沿用它）
- **实现分支 / PR**: `next`
- **配套文档**: [OpaqueReturnTypeResolution.md](../Internal/OpaqueReturnTypeResolution.md)、[References/SwiftGenericsOpaqueResultTypes.md](../Internal/References/SwiftGenericsOpaqueResultTypes.md)

## 摘要

对照官方《Compiling Swift Generics》的 Opaque Result Types 一章，opaque 解析还差三件事。**①** 展不开的 opaque 引用（描述符所在镜像没找到、accessor thunk 读不出）今天打成 demangler 的 `<<opaque return type of …>>.0`，不是合法 Swift，而 textual interface 有一套专门引用已有 opaque archetype 的语法 `@_opaqueReturnTypeOf("mangling", index) __<args>`；改用它兜底，interface 就能被编译器接受，diff 的 payload key 也不再随描述符地址漂移。**②** 跨模块的 `(some P).Element` 形态（owner declaration 在开了 library evolution 的另一个模块里，witness 是 opaque archetype 的 dependent member）展开后留成 `IndexingIterator<[Int]>.Element` 不化简，而官方文档「Map type parameter into opaque generic environment」算法会投影出 `Int`；按 conformance 的 associated type witness 记录做这一步投影。**③** `OpaqueTypeDescriptorProtocol.numUnderlyingTypeArugments` 拼错了，改名并保留一个版本的 deprecated 转发（MachOKitUI 还在用旧名）。① 和 ② 各带一个 interface / dump 开关：interface 只输出能编译的形态，dump 展示更多信息、不考虑能否编译。

## 方案

**① 展不开引用的拼写**。在 `SwiftDeclarationRendering` 新增 `OpaqueReferenceSpelling` 枚举，两个档位：`.textualInterface` 把残留的 `opaqueType` 节点改写成叶子 `@_opaqueReturnTypeOf("$s…", n) __<A, B>`（mangled name 是 owner declaration 的完整符号 mangling，由 `opaqueReturnTypeOf` 名字节点重新 mangle 得到，指针形式的引用先读描述符建出名字节点；n 是节点自带的序号；实参按 depth 顺序拍平）；`.annotated` 在同一拼法后附 `/* owner declaration 的 demangle 文本 */`。改写发生在 `resolveOpaqueType*` 出口处，对所有打印器统一（indexer 冻结 witness 文本用的是上游打印器，dump 用宿主的 resolver，都只能在节点层统一）。indexer / interface 用 `.textualInterface`，`AssociatedTypeDumper` 用 `.annotated`。签名里按名字引用别的声明的 opaque 类型（符号 demangle 出来的 `opaqueType`，永远是名字形式）在 `SwiftPrinting` 的 `printOpaqueType` 里同样拼成 `.textualInterface` 形态。

**② dependent member 投影**。`OpaqueTypeRewriter` 自底向上重写，展开 `opaqueType` 之后再访问它的父节点；父节点是 `dependentMemberType` 且 base 已是具体 nominal 时，去查该 nominal 对 anchor protocol 的 conformance 的 associated type witness 记录（`__swift5_assocty`），用 base 的泛型实参代入 witness，再在声明该 conformance 的镜像里递归展开（witness 自己可能又是 opaque 或另一个 dependent member）。查找复用 `SwiftLayout` 已有的跨镜像索引 `ImageUniverse.resolveAssociatedTypeWitness`（`DependentMemberTypeBridge` 用它算布局），新增一个返回节点而非布局的 public 入口；universe 按根镜像懒建、缓存，搜索路径与按名字展开走同一来源（task 级 resolver 的 searchPaths，否则按文件位置推断）。anchor protocol 缺失（mangling 没带限定）时不投影，留原样。投影结果记入 `OpaqueTypeResolution.projectedMembers`；dump 在 `typealias` 上方打一行注释说明「从哪个 base 的哪个 witness 投影而来」，interface 不打。

**③ 改名**。`numUnderlyingTypeArugments` → `numUnderlyingTypeArguments`，旧名以 `@available(*, deprecated, renamed:)` 转发保留一个版本；覆盖率基线、allowlist、fixture 生成器同批改。

**默认假设**（没问的）：interface 侧 ② 直接给化简后的类型，不像编译器的 `.swiftinterface` 那样写 `(@_opaqueReturnTypeOf(…) __).Element`——本库的 interface 本来就揭示 underlying type；`.annotated` 的注释内联在叶子里而不是另起一行，因为引用可能嵌在任意深的类型里；投影只处理 base 为具体 nominal 的情形，base 仍是泛型参数的 `A.Element` 不动；投影递归上限沿用 opaque 展开的嵌套上限。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-18 | Created as Draft；用户当场批准三项一起做，① 与 ③ 加 interface / dump 开关，"interface 就写 `@_opaqueReturnTypeOf`，dump 要展示更多的信息，不考虑是否能编译" | 用户原话；对照官方文档后列出的三项可选改进 |
| 2026-09-18 | 状态置为 Accepted | 用户批准 |
| 2026-09-18 | 开关落在节点层（`OpaqueReferenceSpelling`）而不是各打印器 | indexer 冻结 witness 文本走上游 `NodePrinter`、dump 走宿主 resolver、interface 走 `SwiftPrinting`，三条路只有节点层是公共的 |
| 2026-09-18 | ② 复用 `SwiftLayout.ImageUniverse` 的 witness 索引 | 同一份 `__swift5_assocty` 读取与跨镜像懒索引已经存在，再写一套等于两份真相 |
| 2026-09-18 | 断言不再逐字比编译器的 `.swiftinterface`，改用显式期望串（`CrossImageOpaqueReferenceTests`），只在 client 自己没有 opaque 的投影 fixture 上与编译器逐字比 | `Outer.body: some Equatable { helper() }` 的 witness 编译器写 `body` 自己的 opaque，二进制记录已被 IRGen 代入一层指向 `helper()`——拼法同、层级差一 |
| 2026-09-18 | 状态置为 Implemented。配套文档：[OpaqueReturnTypeResolution.md](../Internal/OpaqueReturnTypeResolution.md) §1.5、§2.6 记实现与边界，不另写实现说明；术语表不登记新词——`@_opaqueReturnTypeOf`、type witness、projection 都是编译器与官方文档的既有术语，`.annotated` 只是一个枚举 case | 实现说明的判据（下一位维护者会踩、代码里看不出的决定）在专题文档里已经有落点 |
| 2026-09-26 | 落地编号 0045 | 已于 2026-09-18 随 `72b5c5f6` 合入 `next` 并标为 Implemented，但当时没有取号；0.20.0 发版收尾时按合入顺序补取 |
