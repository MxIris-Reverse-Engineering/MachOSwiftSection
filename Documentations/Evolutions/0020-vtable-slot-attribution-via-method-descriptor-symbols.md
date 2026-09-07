# 0020 - vtable 槽归属改用 method descriptor 符号：ICF 折叠下的错名修正与墓碑槽还原

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-06
- **最后更新**: 2026-09-07
- **所属愿景**: 无
- **关联提案**: [0006-final-keyword-and-lazy-accessor-type-recovery](0006-final-keyword-and-lazy-accessor-type-recovery.md)（首次把 `Tq` 符号当作 ICF 免疫证据用于 `final` 判定，但只用作否定证据，没有用于正向归属——本提案补上那一步）
- **实现分支 / PR**: `feature/vtable-slot-attribution`（worktree `.worktrees/MachOSwiftSection-VTableSlotAttribution`），[PR #123](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/pull/123)
- **配套文档**: [TaskReports/2026-09-06-vtable-slot-attribution.md](../Internal/TaskReports/2026-09-06-vtable-slot-attribution.md)（过程复盘）

## 摘要

class vtable 每个槽打印成哪个成员，今天是靠「实现地址反查符号」决定的：从 `MethodDescriptor` 的 implementation 相对指针算出偏移，再问符号索引这个偏移上有哪些符号。这个映射在 linker 做过 identical code folding（ICF，把字节相同的函数体合并到同一地址）之后就是一对多的，反查不回去。SwiftUICore（iOS 18.5 arm64）里 `SwiftUI.GraphHost` 的四个空实现方法全部折叠在 `0x9330`，那个地址上有 2878 个符号，于是 dump 把 vtable 槽 26–29 印成了 `isHiddenForReuseDidChange()` 加三个属于嵌套 struct `GraphHost.Data` 的协程 resume 函数，而真正的 `instantiateOutputs()` / `uninstantiateOutputs()` / `timeDidChange()` 一个都没出现在 vtable 列表里。

每个 method descriptor 自己带一个 `Tq` 符号（method descriptor symbol），它是 `S` 类型的全局数据符号，一个成员一个唯一地址，ICF 完全影响不到。本提案把 vtable 槽的归属**主源**从「实现地址反查」换成「descriptor 自身地址查 `Tq`」，实现地址反查降级为回退；顺带修掉筛选条件 `node.first(of: .class)` 把嵌套类型成员误判成本类成员的问题，并让 `Tq` 还原出那些实现已被删除、槽位为 ABI 保留的墓碑槽的名字。

## 方案

### 现状与真值（`SwiftUI.GraphHost` 实测）

类描述符 `0x98c9c8`，`vTableOffset = 20`、`vTableSize = 10`，十条 method descriptor 连续排在 `0x98c9fc`–`0x98ca44`：

| slot | descriptor | `Tq` 符号给出的真值 | 当前 dump 输出 |
|---|---|---|---|
| 20 | `0x98c9fc` | getter，metadata 里绑到 `swift_deletedMethodError` | `Symbol not found` |
| 21 | `0x98ca04` | setter，同上 | `Symbol not found` |
| 22 | `0x98ca0c` | modify，同上 | `Symbol not found` |
| 23 | `0x98ca14` | `init(data:)` | 一致 |
| 24 | `0x98ca1c` | `graphDelegate.getter` | 一致 |
| 25 | `0x98ca24` | `parentHost.getter` | 一致 |
| 26 | `0x98ca2c` | `instantiateOutputs()` | `isHiddenForReuseDidChange()` |
| 27 | `0x98ca34` | `uninstantiateOutputs()` | `Data.graph.modify … .resume.0` |
| 28 | `0x98ca3c` | `timeDidChange()` | `Data.globalSubgraph.modify … .resume.0` |
| 29 | `0x98ca44` | `isHiddenForReuseDidChange()` | `Data.rootSubgraph.modify … .resume.0` |

前三槽在 class metadata（`0xaaa000`）里是 chained-fixup bind 槽，import ordinal `0xc1c` 解出来是 `_swift_deletedMethodError`：某个 overridable 属性被删除了，槽位作为 ABI 墓碑保留，调用即 trap。descriptor 侧 implementation 为 null，正是这个原因。

### 两条根因

**一、归属主源选错。** `Sources/SwiftDump/Dumper/ClassDumper.swift:239` 用 `descriptor.implementationSymbols(in: machO)` 取名字。ICF 之下一个地址对应多个成员，这个方向的映射不存在逆。

**二、候选筛选过松。** `Sources/SwiftDump/Dumper/ClassDumper.swift:618` 用 `node.first(of: .class)` 深度优先找第一个 class 节点来判断「这个符号属不属于本类」。`GraphHost.Data.graph.modify` 的 context 链是 `class GraphHost → struct Data`，`first(of: .class)` 命中 `GraphHost`，于是嵌套类型的成员被认作本类的 vtable 方法。这一条独立于 ICF 也是错的。

### 影响面（SwiftUICore iOS 18.5 arm64，171 个非泛型带 vtable 的类 / 512 个槽）

| 情况 | 槽数 | 占比 | 本提案后 |
|---|---|---|---|
| implementation 符号唯一 + 有 `Tq` | 224 | 43.8% | 已正确，`Tq` 只是加固 |
| implementation 为 null（墓碑）+ 有 `Tq` | 79 | 15.4% | **从 `Symbol not found` 变成有名字** |
| implementation 多符号（ICF）+ 有 `Tq` | 64 | 12.5% | **从错名变正确名**（GraphHost 属于此类） |
| implementation 符号唯一 + 无 `Tq` | 27 | 5.3% | 已正确，走回退 |
| implementation 多符号（ICF）+ 无 `Tq` | 19 | 3.7% | 仍不可归属，标注为不可靠 |
| implementation 为 null（墓碑）+ 无 `Tq` | 91 | 17.8% | 仍无名，标注为无实现 |
| implementation 无符号 | 8 | 1.6% | 仍无名 |

泛型类的 vtable 不在这份统计里（统计脚本跳过了 trailing object 布局较复杂的泛型描述符），但归属机制与非泛型类完全相同，修复同样覆盖。

### 改动

1. **`Sources/SwiftInspection/Extensions/Descriptor+MethodDescriptorSymbols.swift`**（新文件）——`MethodDescriptor.methodDescriptorSymbols(in:)` 拿 descriptor **自身的偏移**查符号索引，`attributedMemberNode(in:)` 把 `global(methodDescriptor(<entity>))` 还原成 printer 期望的 `global(<entity>)` 形状。放在 `SwiftInspection` 而不是 ABI 层，与提案 0018 定下的分工一致：`MachOSwiftSection` 只暴露地址，符号归属属于上一层。

   **只给 `MethodDescriptor`，不给两个 override descriptor**（最初写了，实测后撤回，见决策日志）：override descriptor 自己没有 `Tq`，它指向的是**父类**的 descriptor，用那个身份回答的是另一个问题——dump 要打印的是本类的实现符号，`TypeDefinition.index` 要 join 的是本类的成员符号。override 槽的槽号本来就来自 `ParentClassVTableCache`，从不依赖符号归属。

2. **`Sources/SwiftDump/Dumper/ClassDumper.swift` 的 vtable 主循环**——归属改为三级：先 `Tq`，取不到再走实现地址反查，都取不到才落到地址或墓碑文案。两个 override 循环保持原样。

3. **`Sources/SwiftDump/Dumper/ClassDumper.swift` 的 `validNode`**——把「节点里含有本类的 class 节点」换成「成员的直接 context 就是本类」（`NodeReference.declarationContextNode`，新文件 `Node+DeclarationContext.swift`），堵住嵌套类型串味。`SwiftDeclaration` 的 `demangledOverrideSymbol` 同样处理。`ProtocolDumper` 的同名 helper 试改后回退（见决策日志）。

4. **`Sources/SwiftDeclaration/Components/Definitions/TypeDefinition.swift`**——interface 路径的 `methodDescriptors` 循环同样优先走 descriptor 符号（两个 override 循环同上，保持原样）。这条路径修复前的症状比 dump 轻但同样不对：GraphHost 的 slot 26 一样错标到 `isHiddenForReuseDidChange`，而 `instantiateOutputs` / `uninstantiateOutputs` / `timeDidChange` 三个真 vtable 方法完全没有 vtable 注释。

5. **两种渲染档**（本轮已定，见决策日志），落在 `DeclarationRenderConfiguration` 的 `ambiguousAttributionComment` / `deletedMethodSlotComment`：
   - 不可归属槽（无 `Tq` 且实现地址被折叠）仍打印猜测名，但加注释说明该地址折叠了多少个符号、归属不可确定。
   - 墓碑槽（implementation 为 null）打印 `Tq` 还原出的声明，并注释说明该槽在本镜像内无实现、调用会 trap；拿不到 `Tq` 的墓碑槽渲染为 `<unnamed vtable slot>`。

### 明确不做

- **protocol witness / resilient witness 的归属不动。** `ResilientWitness` 与 `ProtocolRequirement` 的默认实现没有对应的独立 descriptor 数据符号，`Tq` 这条路子在那边不存在，只能继续靠实现地址反查。它们同样受 ICF 影响，但那是另一个问题，需要另外的证据源，不在本提案范围。
- **`SwiftDiffing` 的 snapshot 格式不动。** 已确认 `MemberRecord` 的 identityKey / payloadKey 都不含 vtable offset（`Sources/SwiftDiffing/` 全目录无 vtable 引用），`formatVersion` 不需要 bump，历史 baseline 不失效。
- **不改 vtable 槽号的计算方式。** `vTableOffset + index` 经 GraphHost 实测与 class metadata 的 immediate members 布局吻合（`numImmediateMembers = 20` = field offset vector 10 + vtable 10，`fieldOffsetVectorOffset = 10`，故 vtable 起于 word 20），这部分本来就是对的。

### 验证（已执行，数据为 SwiftUICore iOS 18.5 arm64 实测）

- **单元回归**（`Tests/SwiftDumpTests/VTableSlotAttributionTests.swift`）：on-the-fly 编译的 fixture，`open class Host` 三个空方法加一个嵌套 `class Nested` 的空方法，全部用 `-Xlinker -deduplicate` 强制折叠到同一地址。修复前 dump 出 `beta` / `alpha` / `gamma`（符号表顺序），修复后 `alpha` / `beta` / `gamma`（`Tq` 地址顺序）。fixture 带 class 满足 `__DATA` 段要求。
  - 嵌套串味在这个规模的 fixture 上**复现不出来**：是否串味取决于 linker 把嵌套成员排在符号表的哪个位置，这里外层类的三个成员排在前面、槽位先被取完。相关的两条测试因此是防御性的（修复前也绿），已在测试注释里写明，实证复现在下面的 GraphHost 套件。
- **真实二进制回归**（`GraphHostVTableAttributionTests`）：钉住 GraphHost 的四个折叠槽（26–29 对应 `instantiateOutputs` / `uninstantiateOutputs` / `timeDidChange` / `isHiddenForReuseDidChange`）、`!output.contains("resume")`、以及 20–22 的墓碑注释。simruntime 路径按目录扫描发现，缺失即跳过。
- **红/绿证明**：源码改动整体回退后，5 条测试红 3 条（9 个 issue）；改动恢复后 5 条全绿。
- **全库 A/B**：828 条声明行变化。7 处 `.resume.` 串味全部消失、零新增；`Symbol not found` 358 → 0（其中 195 条拿到真名，163 条转为带墓碑注释的 `<unnamed vtable slot>`）；**零**行从有名字退化成 `sub_` 地址。
- **机械比对**：把 1199 个 `Tq` 符号按地址排序作为真值，与 dump 输出的槽序列逐类比对——55 个类同时具备 `Tq` 真值与 vtable 输出，其中 54 个相对顺序与 `Tq` 地址顺序完全一致，**0 个顺序错配**（余下 1 个是比对脚本的类名前缀归属误判，把嵌套类 `ResolvedStyledText.TextLayoutManager` 的成员算给了外层类）。
- **渲染 A/B 脚本**：`Scripts/run-rendering-ab-verification.py` 的逐字节判据不适用于本提案（改变输出正是目的），故以上述定量比对替代，结论同样写入任务报告。

### 已知遗留

- `ClassDumper.vtableAccessorFieldNames`（`final` 关键字还原的证据源之一）仍按实现地址收集访问器字段名，ICF 下会把折叠地址上所有符号的字段名一并收进来。后果是**少标** `final`（保守方向，不会错标），且它还有 `Tq` method descriptor 符号作为第二证据源。改用 `Tq` 主源会改变 `final` 输出，属于提案 0006 的领域，未纳入本批次。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-09-06 | Created as Draft | 用户报告 Hopper 看到的 `SwiftUI.GraphHost` vtable 布局与 dump 输出不符；调研确认 dump 错，根因是 ICF 下实现地址反查符号不可逆 |
| 2026-09-06 | 归属主源改用 method descriptor 自身的 `Tq` 符号，实现地址反查降级为回退 | `Tq` 是 `S` 类型全局数据符号，每个成员一个唯一地址，ICF 免疫；提案 0006 落地时（commit 83a4308c）已确认过这条性质，但只把它用作 `final` 判定的否定证据，没有用于正向归属 |
| 2026-09-06 | 不可归属槽（无 `Tq` 且实现地址折叠，实测 3.7%）仍打印猜测名，但加注释标明折叠符号数与归属不可确定 | 保留线索的同时不误导读者；完全不给名字会让这批槽失去全部可读性 |
| 2026-09-06 | 墓碑槽打印 `Tq` 还原的声明并注明「本镜像内无实现」 | descriptor 的实现被删除但符号仍在，能还原出被删的是哪个方法（实测 79 槽 / 15.4%），比现状的 `Symbol not found` 信息量高；同时必须讲清它没有实现，否则读者会以为是普通成员 |
| 2026-09-06 | 走轻量档：不套完整模板，不做完整拷问 | 归属机制的局部修正，不涉及架构变更或破坏性 API；新增的 `descriptorSymbols(in:)` 是纯增量 API |
| 2026-09-06 | 用户批准，直接进入 In Progress | 轻量档提案，用户看过方案后指示开工；`In Review` 阶段跳过 |
| 2026-09-06 | ProtocolDumper 的同类修改试做后回退 | 协议侧符号不只是成员：`base conformance descriptor for P: Q` 等要求描述符没有 entity 节点，按声明上下文匹配会整批丢弃（实测 SwiftUICore 协议输出 1033 行退化为 `[Stripped Symbol]`）。协议侧需要自己的证据模型，不在本提案范围 |
| 2026-09-06 | `validNode` 的上下文修复保留，尽管在本二进制上零影响 | `Tq` 主源已覆盖所有会出问题的槽，隔离 A/B 显示该修复单独作用时输出逐字节不变；保留是因为它在 `Tq` 缺失的回退路径上仍是正确性前提 |
| 2026-09-06 | `vtableAccessorFieldNames` 不改 | 同一 ICF 根因，但后果是保守的少标 `final`，且改动会牵动提案 0006 的输出，混入本批次会让 A/B 审查失去焦点 |
| 2026-09-06 | `Tq` 主源**只用于类自己的 `MethodDescriptor`**，两个 override descriptor 撤回 | 先按「override 也能经父类 descriptor 拿 `Tq`」实现，结果 `override` 关键字从输出里整个消失——`TypeDefinition.index` 的 joinKey 要跟本类成员符号对上，父类形状的节点匹配不到任何东西（`SymbolTestsCoreE2ETests.outputContainsOverrideKeyword` 抓住）。撤回后另有一处残留在 `dumpMethodDeclaration`，被 override 循环的 `.element` 腿调用时把 `override ResilientChild.init()` 打成 `override ResilientBase.init()`，并丢掉实现符号带的 `vtable thunk … dispatching to …` 细节（快照 diff 审查抓住）。教训：`Tq` 回答的是「这个 descriptor 声明了谁」，override 槽问的是「本类的实现是谁」，不是同一个问题 |
| 2026-09-06 | 更新 10 份快照基线（9 份 dump + 1 份 interface） | 逐条审查确认全部为修正：16 条墓碑注释新增、10 条 `[Init] Symbol not found` 拿到真名、6 条降级为 `<unnamed vtable slot>`、4 条去掉 `async function pointer to` 前缀（vtable 槽显示成员本身而非 `Tu` 常量）、`FinalMembersTest` 三条 kind 与名字的系统性错位修正（`[Setter]` 配 `plainMethod()` 这类）、interface 的 `static func classMethod()` → `class func classMethod()`（fixture 源码写的就是 `public class func`，此前因归属错位没 join 上 descriptor 而误印 `static`） |
| 2026-09-07 | `/code-review xhigh` 跑完 PR #123，15 条发现全部按四问裁决：真缺陷 4、建议同批修 3、低优先级 3、误报或已有裁决 3、流程 2 | 清单与逐条论证见 [`Roadmaps/2026-09-06-pr123-review-findings.md`](../../Roadmaps/2026-09-06-pr123-review-findings.md)；「不修 / 误报 / 延后」的终审登记为 A34–A39。本轮**只落记录，代码未改**，修复批次另起 |
| 2026-09-07 | 上面 2026-09-06「墓碑槽」那条决定**成立**，只有措辞要改（本行取代同日一条判它「因果前提被推翻」的记录，那条判断经复核有误，已撤回） | 初判依据是「fixture 里 `TestsObjects` 的 `init()` 明明存在却被标成 deleted」，错在把「声明存在」当成「实现存在」。IRGen 的 `buildMethodDescriptorFields`（`lib/IRGen/GenMeta.cpp` 约 340–364 行）只有两个分支，写 null 那支的原注释即 "The method is removed by dead method elimination."——null 是编译器唯一的写入路径，不是本库的推断。真实根因是**访问级别**：public 类型里不写修饰符的 `init()` 默认 internal，整模块优化下不是死函数消除的 anchor，没人调就被删实现体；fixture 里被标记的全是 internal 或函数内局部类成员，未标记的全是显式 `public init`（`AsyncInitializerActorTest` 幸免是因为 public，与 async 无关）。独立探针确证：`-O -wmo -enable-library-evolution` 下 internal init / 访问器只剩 `Tq` 无函数符号，`dyld_info` 数出的 `_swift_deletedMethodError` bind 数与预期精确吻合。故 SwiftUICore 33% 的比例可信。待修：注释措辞改为 `Implementation removed by dead-method elimination; vtable slot kept for layout (calling it traps)`，并在文档补上「`swift_deletedMethodError` 只填静态 metadata，运行时实例化路径 null 保持 null」这一限定 |
