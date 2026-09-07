# PR #123 review findings（vtable 槽归属改用 method descriptor 符号，2026-09-06）

`/code-review xhigh` 对 PR #123（`feature/vtable-slot-attribution` → `next`，2 个 commit，7 个源文件 + 10 份快照基线 + 1 个新测试文件 + 文档）的 15 条发现，已按四问（复现 / 基线对比 / 值不值得修 / 既往修复）逐条裁决：**真缺陷 4、建议同批修 3、低优先级 3、误报或早有裁决 3、流程 2**。

本表是原始清单与处置状态。「不修 / 误报 / 延后」的终审条目收录进 [ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md)（A34–A39）。

**当前状态：只落记录，代码未改。** 用户裁定先把审查结论记下来，修复批次另起。

对比基线：`git diff next...feature/vtable-slot-attribution`。

## 一、真缺陷（4 条，待修）

四条全部集中在本 PR 新增的两行注释上，建议一批改完。

### 1. 墓碑注释在说假话 —— 最高优先级

`Sources/SwiftDeclarationRendering/DeclarationRenderConfiguration.swift:211`

新注释 `// No implementation in this image (deleted method — slot retained for ABI)` 默认开启、无法关闭，对**每一个** implementation 指针为 null 的 vtable 槽断言「这个成员被删了、槽位为 ABI 兼容保留」。

- **能复现吗**：能，且是系统性的。`Tests/Projects/SymbolTests/SymbolTestsCore/BasicTypes.swift:8` 是 `public final class TestsObjects {}`，隐式 `init()` 明确存在；新基线 `basicTypesSnapshot.1.txt:5-6` 却给它打上了墓碑注释，而同一文件三行后就列着 `method descriptor for ...__allocating_init()`。本次快照更新共新增 17 行该注释，覆盖 `ActorTest` / `CustomGlobalActor` / `GlobalActorAnnotatedClass` / `MainActorAnnotatedTest` / `TestsObjects` / `ClassTest` / `ReferenceFieldTest` / `ClosureParameterTest` / `ClassSubscriptTest` 的 `__allocating_init`，外加 `ClassSubscriptTest` 的 getter / setter / modify。**fixture 里所有非 async 的 `__allocating_init` 全部中招**，唯一幸免的是 async 的 `AsyncInitializerActorTest`。
- **与基线对比**：`next` 上这些槽输出 `Symbol not found`，用的是**同一个** `implementation.isNull` 判定。也就是说「实现指针为 null」是本库长期观察到的老事实，本 PR 新增的是**对该事实的因果解释**，而这个解释站不住：SwiftUICore 上 33% 的 vtable 槽都是「被删除的方法」，比例本身即不可信。
- **值不值得修**：值得，优先级最高。这条断言已被当作项目事实写进 `AGENTS.md:128` 与 [Glossary.md](../Documentations/Glossary.md)（「实测 SwiftUICore 的非泛型类里约 33% 的槽是墓碑」），后续工作会拿它当前提。
- **既往修复**：无。全仓搜 `swift_deletedMethodError` 零命中，首次出现。
- **修法**：注释只陈述可观察事实（本镜像内无实现指针），因果解释留给文档。若确实要断言墓碑，那个断言是**可验证的**——读 class metadata 对应的 word，看是否真的 bind 到 `swift_deletedMethodError`。`GraphHostVTableAttributionTests` 的文档注释已如此声称，但代码并未验证。
- **复现测试**：拿 fixture 里源码明确存在的 `init()` 断言输出中不出现「deleted method」字样。

### 2. 歧义注释的判据用错了数，且在没有名字时照打

`Sources/SwiftDump/Dumper/ClassDumper.swift:250`

触发条件是 `implementationSymbols.count > 1`——折叠地址上的**原始符号总数**，不是「有几个候选真的属于本类」。

- **能复现吗**：能，两种形态。(a) 某地址折叠 3 个符号、其中仅 1 个是本类成员时，归属其实毫无歧义，却仍打印「3 symbols folded」。(b) `validNode` 返回 nil（无任何折叠符号的声明上下文匹配本类）时输出退化为 `sub_XXXX` 地址，注释却仍称「下面这个名字是最佳候选」——下面根本没有名字，与 `ambiguousAttributionComment` 自身的文档注释直接矛盾。SwiftUICore 上该行会打印「2878 symbols folded」，度量的是折叠桶大小而非候选集。
- **与基线对比**：新增代码，基线无。
- **值不值得修**：值得，改动小。计数应取 `validNode` 实际考察过的、匹配本类的候选数；`resolvedMethodNode == nil` 时换措辞或不打。
- **既往修复**：无。

### 3. 同一个「实现为 null」在一个函数里有三种渲染

`Sources/SwiftDump/Dumper/ClassDumper.swift:248` / `323` / `354`

- method descriptor 循环：墓碑注释 + `<unnamed vtable slot>`
- override 循环的 `.element` 分支：**无**墓碑注释，只有 `override <unnamed vtable slot>`（见 `classesSnapshot.1.txt:87` 的 `SubclassTest`、`:111` 的 `FinalClassTest`）
- override / default-override 的 `else` 分支：仍是 method 循环刚淘汰的 `Error("Symbol not found")`

- **能复现吗**：能，提交的基线里直接可见。
- **与基线对比**：`next` 上三处一致（都是 `Symbol not found`），**不一致是本 PR 引入的**。
- **值不值得修**：值得。除输出不一致外有具体隐患：`GraphHostVTableAttributionTests.deletedMethodSlotsAreMarkedAsTombstones` 断言 `!output.contains("Symbol not found")`，目前能过仅因 GraphHost 恰好没有 null 实现的 override 槽。
- **修法**：把「null 实现」的渲染收进一个共享 helper，三个循环都走它。
- **既往修复**：无。

### 4. 两条新注释没有开关

`Sources/SwiftDeclarationRendering/DeclarationRenderConfiguration.swift:200`–`225`

`DeclarationRenderConfiguration` 里其他每种注释都有 `printXxx` 布尔开关（`printVTableOffset` / `printMemberAddress` / `printExportStatus` / `printFieldOffset`），新增两条一个都没有，无条件输出。RuntimeViewer、`swift-section dump` 与所有快照消费者被迫接收；在第 1 条的措辞问题解决前，宿主连「我不同意这个断言」都无法表达。

- **能复现吗**：属实。
- **与基线对比**：新增。
- **值不值得修**：**开关要加；transformer 模板槽不加**。[A14](../Documentations/Internal/ReviewAdjudications.md)（2026-08-23，`not exported` 注释）已裁决过「新注释不走 transformer 模板机制」——理由是模板机制的价值在**带变量 token 的注释**，零参数的固定陈述模板化只能改措辞，而措辞正是承重部分。该先例覆盖零 token 的 `deletedMethodSlotComment()`，**不覆盖**带一个变量的 `ambiguousAttributionComment(foldedSymbolCount:)`，也**不覆盖开关本身**——A14 明确写了「若需要开关，一个 Bool 就是全部所需表面」，而这两条连那个 Bool 都没有。详见 A37。
- **既往修复**：A14 是同形先例，见上。

## 二、建议同批修（3 条）

### 5. 新的 `outermostEntityNode` 没有去重，撞在上游明确警告过的形状上

`Sources/SwiftInspection/Extensions/Node+DeclarationContext.swift:47`

手写广度优先遍历，`queue.append(contentsOf: candidate.children)`，**没有 visited 集合**。节点树是 hash-consed 的有向无环图（相同子树共享同一实例），枚举逻辑树等于枚举路径数而非节点数。

- **能复现吗**：机制属实。上游 swift-demangling 的 `DemanglingNode+Sequence.swift:245-251` 正是为此把 `first(of:)` 换成去重版，注释附实测：「on a shared DAG that one costs 2^N... Measured: 18.2s on a 22-level doubling DAG」，并指出**查不到东西的那次最贵**（无可短路）。这正是此处的常见情形：`validNode` 每个候选符号调一次，输入在 identical code folding（相同代码折叠）下是该地址上的全部符号——SwiftUICore 为 2878 个，其中多数是 metadata accessor、outlined function、witness table 这类**根本没有 entity 节点**的符号，每个都要走完整棵树才返回 nil。
- **与基线对比**：新增代码。基线用的是上游已去重的 `first(of: .class)`，故属**新引入**的风险。
- **值不值得修**：值得，修法便宜——改用上游公开的 `first(of: .function, .variable, .subscript, .constructor, .allocator, .destructor, .deallocator)`，内部即去重前序遍历。语义差异（前序深度优先 vs 广度优先）在实际符号树上不产生不同结果，因为 `global` 的第一个子节点就是 entity。
- **横向排查**：全仓搜过，无第二处手写节点子树遍历，此为唯一一例。
- **既往修复**：上游 0.5.x 已就同一形状做过修复，本仓库这次是重新引入。

### 6. 快路径上白算一次 `implementationSymbols`

`Sources/SwiftDump/Dumper/ClassDumper.swift:241`

无条件调用 `descriptor.implementationSymbols(in: machO)`，但它只在 `Tq` 查不到时的回退分支用得上。`Symbols` 是实打实的 `[Symbol]` 数组（`Sources/MachOResolving/Symbols.swift:12`，每个 `Symbol` 为 32 字节 eager value）。按 PR 自身测量 71.7% 的槽有 `Tq` 符号，这些槽白建一次数组；在 PR 描述的折叠地址上是 2878 × 32 ≈ 92 KB 建了就扔。

- **与基线对比**：基线也调一次，但基线**需要**它；本 PR 使其变成可避免的开销。
- **值不值得修**：值得。把调用挪进 `if resolvedMethodNode == nil` 分支即可，歧义计数一并挪入（与第 2 条的修法合并）。

### 7. 模型 / interface 路只抄了归属顺序，没抄诚实标注

`Sources/SwiftDeclaration/Components/Definitions/TypeDefinition.swift:275`

采用了同样的「先 `Tq` 后实现地址」证据顺序，但回退命中折叠地址时**不发任何事件、不渲染任何标记**。那 3.7%「折叠且无 `Tq`」的槽位，在 interface 输出里照样带 vtable offset 注释与 `override` / `class` 关键字，而 dump 路径对同一槽会标注归属不确定。

- **能复现吗**：属实，diff 直接可见——`SwiftIndexEvents` 无新事件，`SwiftPrinting` 无新标记。
- **值不值得修**：中等。该路径喂给 interface、diff、evolution 三个输出，影响面比 dump 大；但属于「诚实性没做全」而非「输出变错」，可作独立小批次。

## 三、低优先级 / 硬化（3 条）

| # | 位置 | 结论 | 处置 |
|---|---|---|---|
| 8 | `TypeDefinition.swift:275`、`ClassDumper.swift:242` | `Tq` 分支跳过回退路径的两道闸（声明上下文匹配、`visitedNodes` 去重）。**基本是理论风险**：`attributedMemberNode` 只接受能 demangle 成 `.methodDescriptor` 的符号，而 descriptor 在一个镜像内地址唯一，同地址出现别类 `Tq` 的场景构造不出；dyld 共享缓存的偏移规范化理论上留了口子，未能构造实例 | 建议加一句与回退路径同样的上下文断言作便宜硬化，不急。见 A38 |
| 9 | `Tests/SwiftDumpTests/VTableSlotAttributionTests.swift` | 新增 5 个测试全部驱动 `ClassDumper`；`TypeDefinition.index` / `OverrideSymbolMatcher` 那一半的全部证据是 `interfaceSnapshot.1.txt:3157` 改了一行。PR 说明自记：本改动的早期版本曾让 `override` 从 interface 输出中**整个消失**，那种失败模式现有测试抓不住 | 待补：至少钉住 `OverrideSymbolMatcher` 从 `first(of: .class)` 换成 `declarationContextNode` |
| 10 | `Sources/SwiftInspection/Extensions/Descriptor+MethodDescriptorSymbols.swift:61` | `MethodDescriptorAttribution` 是包一个静态函数的公开命名空间，其解包 `SymbolIndexStore.swift:695` 已做过一遍（结果形状不同：`global(entity)` vs 裸 `entity`），今后靠人手同步；`methodDescriptorSymbols(in:)` 是一行 `machO.symbols(offset:)`，按理应与既有四个 `implementationSymbols(in:)` 重载同文件 | 纯结构问题，不影响行为，随修复批次顺手整理 |

## 四、误报或早有裁决（3 条，不动）

| # | 位置 | 结论 | 状态 |
|---|---|---|---|
| 11 | `vTableEntryVariantsSnapshot.1.txt:142` 的 `class func static X.classMethod()` | **已裁决**：[ClassMemberKeywordRecovery.md:73-81](../Documentations/Internal/ClassMemberKeywordRecovery.md) 明确记过这个决定，原文即写着「现为 `class func static Foo...`」。本 PR 只是让该槽第一次正确解析到 `classMethod`（基线上错解析成 subscript setter），既有形态首次出现在此 fixture | 不动，见 A34 |
| 12 | `Node+DeclarationContext.swift:25` 的 `entityNodeKinds` 缺 `.boundGenericFunction` | **误报**：`Demangler.swift:1288` 构造它时是 `children: [n, args]`，第一个子节点是 `.function` / `.constructor` 节点本身而**非声明上下文**（`NodePrinter.swift:1954` 同样如此解包）。把它排除、让遍历**穿过**它落到里面的 `.function`，拿到的才是正确上下文 | 不动，见 A35 |
| 13 | `VTableSlotAttributionTests.swift:107` 的前提硬失败 | **误报（前半）+ 有意设计（后半）**：`swiftc` 不带 `-target` 默认产出宿主架构 thin 文件，走 `.machO` 分支，`.fat` 分支不会走到；「linker 不折叠即红」是测试自己写明的设计（文件头注释：a REQUIRED premise rather than a soft check） | 不动，见 A36 |

## 五、流程（2 条）

### 14. 提案状态三处不一致，且从未到过 `Accepted`

- `Documentations/Evolutions/draft-vtable-slot-attribution-via-method-descriptor-symbols.md:3`：`In Progress`
- `Documentations/Evolutions/README.md:30`：`Draft`
- `Documentations/README.md:106`：`Draft`

三个来源两种答案，无一为 `Accepted`，而实现代码已在同一 commit 落地。文件名仍带 `draft-` 前缀（约定是落地时才分配 `NNNN-` 编号）。**待办：修复批次落地前把状态改为 `Accepted` 并分配编号，三处对齐。**

### 15. `vtableAccessorFieldNames` 的折叠地址扫描 —— 基线既有，非本 PR 引入

`Sources/SwiftDump/Dumper/ClassDumper.swift:561-571` 仍按实现地址收集访问器名字，内层循环无本类过滤、无早退，把每个 `.variable` 的名字都塞进集合。折叠地址上是每个访问器 descriptor ~2878 次 demangle 查询（有 memo 缓存兜底），且会把嵌套类型的同名字段一并收进，从而抑制本类同名字段的 `final` 标记——正是本 PR 在别处修掉的那种跨类型串味。

- **与基线对比**：`next` 上一模一样，本 PR 未触及。
- **既往修复**：来自提案 0006（commit `da9b8be2` / `83a4308c`）。PR 记为后续项，理由是错误方向保守（少标 `final` 而非错标）。
- **处置**：同意作独立批次，见 A39。
