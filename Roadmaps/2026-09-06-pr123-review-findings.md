# PR #123 review findings（vtable 槽归属改用 method descriptor 符号，2026-09-06）

`/code-review xhigh` 对 PR #123（`feature/vtable-slot-attribution` → `next`，2 个 commit，7 个源文件 + 10 份快照基线 + 1 个新测试文件 + 文档）的 15 条发现，已按四问（复现 / 基线对比 / 值不值得修 / 既往修复）逐条裁决：**真缺陷 4、建议同批修 3、低优先级 3、误报或早有裁决 3、流程 2**。

本表是原始清单与处置状态。「不修 / 误报 / 延后」的终审条目收录进 [ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md)（A34–A39）。

**当前状态：只落记录，代码未改。** 用户裁定先把审查结论记下来，修复批次另起。

对比基线：`git diff next...feature/vtable-slot-attribution`。

## 复核（2026-09-07）

本清单初版落地后交 `MachOSwiftSection-Fable` 复核，两条结论改判，均已就地改写：

1. **第 1 条改判**：初版判「墓碑注释的因果断言站不住」，实际**断言成立**（IRGen 只有一条写 null 的路径，注释原文就是 dead method elimination），站不住的是措辞；真实根因是**访问级别**（internal 成员在整模块优化下被删实现体），不是初版猜测的 async。已跑独立探针确证，数据写在该条里。SwiftUICore 那 33% 因此**可信**，Glossary 与 AGENTS.md 的对应表述改为死方法消除的措辞而非删除。
2. **第 5 条升级**：初版只当性能问题（遍历无去重），复核指出它同时是**正确性缺陷**——遍历无差别下降，把闭包 / 默认参数 / 变量初始化表达式的宿主报成声明上下文。白名单下降的修法同时解决两者。

复核同时确认 A34 / A35 / A36 三条误报裁决成立，并为 A38 补了一条可行的测试路径。

## 一、真缺陷（4 条，待修）

四条全部集中在本 PR 新增的两行注释上，建议一批改完。

### 1. 墓碑注释用词误导（初版判为「说假话」，2026-09-07 改判）

`Sources/SwiftDeclarationRendering/DeclarationRenderConfiguration.swift:211`

新注释 `// No implementation in this image (deleted method — slot retained for ABI)` 默认开启、无法关闭。

**改判说明**：本条初版判定「因果断言站不住」，依据是 fixture 里源码明确存在的 `init()` 也被打上了这个标签。经 `MachOSwiftSection-Fable` 复核并跑独立探针确证，**因果断言在编译器层面成立**，站不住的只是措辞。初版的错误在于把「声明存在」当成了「实现存在」——被删掉的是函数体，不是声明。

- **能复现吗 / 是不是误报**：注释出现的位置属实，但它描述的机制是**真的**，不是本库的推断。IRGen 写 method descriptor 实现指针的 `buildMethodDescriptorFields`（swiftlang/swift，`lib/IRGen/GenMeta.cpp` 约 340–364 行）只有两个分支：SIL vtable 有 entry 就写相对地址，没有就写 null，后者的原注释即 "The method is removed by dead method elimination. It should be never called."。**null 是唯一写入路径**。override descriptor 的 builder（约 2413–2431 行）同形；静态 class metadata 的 `addReifiedVTableEntry`（约 4770–4800 行）对同一情况填 `swift_deletedMethodError`（async / coroutine 各有变体）。
- **真实根因是访问级别，不是 async**：public 类型里不写修饰符的 `init()` 默认是 **internal**。在 whole-module optimization（整模块优化）的 Release 构建下，internal 成员不是 dead function elimination（死函数消除）的 anchor——`SILLinkage::Hidden` 经 `isPossiblyUsedExternally` 返回 `!wholeModule`（`include/swift/SIL/SILLinkage.h:274`），于是没人调用（或调用点内联后独立函数体死掉）的成员被 `removeDeadEntriesFromTables` 摘掉 vtable entry，IRGen 随即写 null。fixture 的 Xcode 配置正是 `SWIFT_COMPILATION_MODE = wholemodule` + `BUILD_LIBRARY_FOR_DISTRIBUTION = YES`。
  - **被标记的**全是 internal 或函数内局部类的成员：8 个类的隐式 `init()`、`ReferenceFieldTest.init(reference:)`（显式但无修饰符 ⇒ internal）、`ClassSubscriptTest` 的 `private var elements` 三个访问器（旁边 public subscript 的三个访问器都有名字）、`LocalClass` 的四个成员；`SubclassTest` / `FinalClassTest` 的 `override <unnamed vtable slot>` 是对那个 internal init 的 override。
  - **未标记的**全是显式 `public init`。初版观察到「唯一幸免的是 async 的 `AsyncInitializerActorTest`」——幸免的原因是它写了 `public init(identifier:) async`，**public 才是变量，async 是巧合**。
  - **独立探针**（2026-09-07 实测，`xcrun swiftc -O -wmo -enable-library-evolution -emit-library`）：`public final class A {}` 的隐式 init、`public class C { var x = 0 }` 的三个访问器**只有 `Tq` 符号、没有函数符号**；`public final class B { public init() {} }` 的 `__allocating_init` 函数符号在 `0x8a0` 且带 dispatch thunk。`dyld_info -fixups` 数出 **5** 处 `_swift_deletedMethodError` bind = A 的 init 1 + C 的 init / getter / setter / modify 4，与预期精确吻合。
- **与基线对比**：`next` 上这些槽输出 `Symbol not found`，用的是同一个 `implementation.isNull` 判定；本 PR 新增的是对该事实的解释，而该解释正确。**SwiftUICore 那 33% 因此可信**——OS 框架里多数 vtable 成员是 internal，整模块优化下 devirtualize + inline 之后独立函数体死掉。复核实测：SwiftUICore（iOS 18.5 arm64）有 341 处该 bind，Xcode 自带 SourceEditor.framework 有 11680 处（对应 4894 个 `Tq`）。
- **仍然要改的**：措辞。「deleted method」在编译器语境里指「优化器删掉了实现体」，读者会读成「声明 / API 被删除」，而声明还在（源码在、`Tq` 在、descriptor 在）。建议措辞 `// Implementation removed by dead-method elimination; vtable slot kept for layout (calling it traps)`。
- **文档必须补上的限定**：`swift_deletedMethodError` **只填进静态 metadata**。泛型类与 resilient 父类走运行时实例化路径时，`initClassVTable`（`stdlib/public/runtime/Metadata.cpp` 约 4157 行）把 `methodDescription.getImpl()` 原样拷入，null 保持 null，不会变成那个函数。
- **值不值得修**：值得，但严重程度从「输出在说假话」降为「用词误导」。
- **既往修复**：无。
- **明确不要做的**：不要在产品代码里验证 metadata 的 bind 来佐证墓碑判定。descriptor 的 null 已是唯一写入路径的权威标记，bind 只是它在静态 metadata 里的后果，泛型类根本不存在——验证会产生假阴性，还要为每个 null 槽多做一次 classlist 查找。离线可行性本身没问题（`SwiftLayout.ObjCClassIndex` 已有 `MachOFile` 版 `__objc_classlist` 读取，`MachOKitExtensions.resolveBind(fileOffset:)` 能解 bind），但只值得放进 `GraphHostVTableAttributionTests`：用 `$s7SwiftUI9GraphHostCN` 定位 metadata、验三个 word 等于 `_swift_deletedMethodError`，让那条测试的文档注释名副其实（复核已核对：GraphHost 的 `0xAAA0A0 / A8 / B0` 三个 word 确实 bind 到 `libswiftCore/_swift_deletedMethodError`）。
- **顺带核出的提案笔误**：提案表格里「`Tq` 符号给出的真值：getter / setter / modify」三行实际来自 descriptor flags——GraphHost 只有 7 个 `Tq`（从 `0x98ca14` 起），槽 20–22 并没有 `Tq`。

### 2. 歧义注释的判据用错了数，且在没有名字时照打

`Sources/SwiftDump/Dumper/ClassDumper.swift:250`

触发条件是 `implementationSymbols.count > 1`——折叠地址上的**原始符号总数**，不是「有几个候选真的属于本类」。

- **能复现吗**：能，两种形态。(a) 某地址折叠 3 个符号、其中仅 1 个是本类成员时，归属其实毫无歧义，却仍打印「3 symbols folded」。(b) `validNode` 返回 nil（无任何折叠符号的声明上下文匹配本类）时输出退化为 `sub_XXXX` 地址，注释却仍称「下面这个名字是最佳候选」——下面根本没有名字，与 `ambiguousAttributionComment` 自身的文档注释直接矛盾。SwiftUICore 上该行会打印「2878 symbols folded」，度量的是折叠桶大小而非候选集。
- **与基线对比**：新增代码，基线无。
- **值不值得修**：值得，改动小。
- **修法（复核给出）**：让 `validNode` 顺带返回「匹配本类且未被认领」的候选数，按它三分——**≥ 2** 才打歧义注释，措辞改成 `M of N symbols at this address are members of this type`（同时说明分子分母各是什么）；**= 1** 归属其实唯一，不打；**= 0** 输出 `sub_` 地址，此时更不该声称「下面这个名字是最佳候选」。`implementationSymbols` 与计数一起移进 `attributedMethodNode == nil` 分支，第 6 条随之一并解决。
- **注意（第二轮复核提出）**：本条要改的是歧义注释的**判据与措辞**，而代码此刻仍在输出字面的 `// Attribution: ambiguous — N symbols folded at this address`。`AGENTS.md` 与本条都保留这个字面文本作为「当前行为」的记录，修复批次落地时再一并替换为 `M of N …` 的新措辞——文档不得抢先描述尚未存在的输出。
- **既往修复**：无。

### 3. 同一个「实现为 null」在一个函数里有三种渲染

`Sources/SwiftDump/Dumper/ClassDumper.swift:248` / `323` / `354`

- method descriptor 循环：墓碑注释 + `<unnamed vtable slot>`
- override 循环的 `.element` 分支：**无**墓碑注释，只有 `override <unnamed vtable slot>`（见 `classesSnapshot.1.txt:87` 的 `SubclassTest`、`:111` 的 `FinalClassTest`）
- override / default-override 的 `else` 分支：仍是 method 循环刚淘汰的 `Error("Symbol not found")`

- **能复现吗**：能，提交的基线里直接可见。
- **与基线对比**：`next` 上三处一致（都是 `Symbol not found`），**不一致是本 PR 引入的**。
- **值不值得修**：值得。除输出不一致外有具体隐患：`GraphHostVTableAttributionTests.deletedMethodSlotsAreMarkedAsTombstones` 断言 `!output.contains("Symbol not found")`，目前能过仅因 GraphHost 恰好没有 null 实现的 override 槽。
- **修法（复核细化）**：一个 helper 算出「归属 + 注释」两件事，三个循环共用。null 实现的 override 槽建议渲染 `override <unnamed vtable slot>` 并附 `// overrides Parent.init()`——父类的 `Tq` 在 override 循环里本来就拿到了（`descriptor.methodDescriptor(in:)`），措辞是「覆盖了谁」而不是「是谁」，因此不会重蹈当初把 `override ResilientChild.init()` 印成 `override ResilientBase.init()` 的坑。两处残留的 `Error("Symbol not found")` 必须清掉，否则 `deletedMethodSlotsAreMarkedAsTombstones` 里的 `!contains("Symbol not found")` 只是碰巧绿。
- **既往修复**：无。

### 4. 两条新注释没有开关

`Sources/SwiftDeclarationRendering/DeclarationRenderConfiguration.swift:200`–`225`

`DeclarationRenderConfiguration` 里其他每种注释都有 `printXxx` 布尔开关（`printVTableOffset` / `printMemberAddress` / `printExportStatus` / `printFieldOffset`），新增两条一个都没有，无条件输出。RuntimeViewer、`swift-section dump` 与所有快照消费者被迫接收；在第 1 条的措辞问题解决前，宿主连「我不同意这个断言」都无法表达。

- **能复现吗**：属实。
- **与基线对比**：新增。
- **值不值得修**：**开关要加；transformer 模板槽不加**。[A14](../Documentations/Internal/ReviewAdjudications.md)（2026-08-23，`not exported` 注释）已裁决过「新注释不走 transformer 模板机制」——理由是模板机制的价值在**带变量 token 的注释**，零参数的固定陈述模板化只能改措辞，而措辞正是承重部分。该先例覆盖零 token 的 `deletedMethodSlotComment()`，**不覆盖**带一个变量的 `ambiguousAttributionComment(foldedSymbolCount:)`，也**不覆盖开关本身**——A14 明确写了「若需要开关，一个 Bool 就是全部所需表面」，而这两条连那个 Bool 都没有。详见 A37。
- **既往修复**：A14 是同形先例，见上。
- **默认值（2026-09-07 用户裁定）**：走折中——**歧义注释默认开**（猜出来的名字必须带 caveat，这是它存在的理由），**墓碑注释默认关**，跟随 CLI 的 `--emit-vtable-offsets` 一起打开（沿用 `Field offset: unknown (<reason>)` 挂 field-offset 家族、`protocol-extension default` 挂 member-address 家族的先例）。两者都不违反 A14。

## 二、建议同批修（3 条）

### 5. `declarationContextNode` 的遍历既无差别下降、又没有去重（2026-09-07 补入正确性缺陷）

`Sources/SwiftInspection/Extensions/Node+DeclarationContext.swift:47`

手写广度优先遍历，`queue.append(contentsOf: candidate.children)`，既不筛选下降路径，也**没有 visited 集合**。

- **正确性问题（复核补入，比性能问题更重）**：遍历会穿过**任何**非 entity 包装节点，于是 `closure #1 in Foo.bar()`、`default argument 0 of Foo.bar()`、`variable initialization expression of Foo.x` 都会走到里层的 `.function` / `.variable` 并把 `Foo` 报成声明上下文——这些符号因此被当作 `Foo` 的成员候选接受。对照组是符号索引自己的口径：`SymbolIndexStore.processMemberSymbol` **只接受** `.static` 与访问器包装。本 PR 的初衷正是堵住「把不属于本类的符号当本类成员」，这里等于开了一个新口子。
- **性能问题**：节点树是 hash-consed 的有向无环图（相同子树共享同一实例），无 visited 集合的遍历枚举的是路径数而非节点数。上游 swift-demangling 的 `DemanglingNode+Sequence.swift:245-251` 正是为此把 `first(of:)` 换成去重版，注释附实测：「on a shared DAG that one costs 2^N... Measured: 18.2s on a 22-level doubling DAG」，并指出**查不到东西的那次最贵**（无可短路）。这正是此处的常见情形：`validNode` 每个候选符号调一次，输入在 identical code folding（相同代码折叠）下是该地址上的全部符号——SwiftUICore 为 2878 个，其中多数是 metadata accessor、outlined function、witness table 这类根本没有 entity 节点的符号，每个都要走完整棵树才返回 nil。
- **与基线对比**：新增代码。基线用的是上游已去重的 `first(of: .class)`，两个问题都属**新引入**。
- **修法（一箭双雕）**：只沿白名单包装下降，并且**不进 type 子树**。闭包 / 默认参数 / 变量初始化表达式因此不再被误判，同时下降路径收敛成一条链，DAG 爆炸随之消失，**连 visited 集合都不需要**。初版建议的「改用上游 `first(of: 多个 kind)`」只解决性能、不解决误判，已废弃。
- **白名单（2026-09-07 第二轮复核修正后，已对 swift-demangling 源码逐条核过）**：
  - **可下降**：`global`（遍历全部子节点）、`static`、八个访问器 kind——`getter` / `setter` / `modifyAccessor` / `modify2Accessor` / `readAccessor` / `read2Accessor` / `unsafeAddressor` / `unsafeMutableAddressor`（`Node+Kind.swift`；**不是** `modify` / `read`，那两个 kind 名不存在）、`boundGenericFunction`（`[n, args]`，只降 `children[0]`）、`vTableThunk`（只降 `children[0]`）。
  - **必须含 `vTableThunk`**，否则 override 循环的回退会退化成 `override <unnamed vtable slot>`：`vtable thunk for Base.f() dispatching to Sub.f()` 是 override 槽合法的实现符号（`ResilientClasses` 快照里就有）。`Demangler.swift:1744` 建的是 `children: [derived, base]`，而 `printVTableThunk` 把 `children[1]`（base）印在 "vtable thunk for" 之后、`children[0]`（derived）印在 "dispatching to" 之后——**要的是 derived**。现行 BFS 没出问题纯粹因为 `children[0]` 先入队。
  - **跳过（是叶子标记，不是包装）**：`mergedFunction` / `asyncFunctionPointer` / `coroFunctionPointer` / `objCAttribute`。它们由 `NodeFactory` 造成**无子节点**的单例（`Node(kind: .mergedFunction)`），作为 `global` 的兄弟子节点出现，遍历 `global` 的全部子节点就已覆盖，不该列进「可下降」。
  - **`methodDescriptor` 不列入**：两个调用方（`ClassDumper.validNode`、`OverrideSymbolMatcher.demangledOverrideSymbol`）的输入都是**实现地址**上的符号，而 `Tq` 是数据符号、不会出现在代码地址；`attributedMemberNode` 自己用 `first(of: .methodDescriptor)` 解包；A38 的上下文断言也落在解包后的 `global(entity)` 上。去掉它使这个 API 的契约收窄为「实现符号树」。
  - 其余一律不下降。
- **横向排查**：全仓搜过，无第二处手写节点子树遍历，此为唯一一例。
- **既往修复**：上游 0.5.x 已就同一 DAG 形状做过修复，本仓库这次是重新引入；误判那一半是本 PR 独有。

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
| 8 | `TypeDefinition.swift:275`、`ClassDumper.swift:242` | `Tq` 分支跳过回退路径的两道闸（声明上下文匹配、`visitedNodes` 去重）。**基本是理论风险**：`attributedMemberNode` 只接受能 demangle 成 `.methodDescriptor` 的符号，而 descriptor 在一个镜像内地址唯一，同地址出现别类 `Tq` 的场景构造不出；dyld 共享缓存的偏移规范化理论上留了口子，未能构造实例 | 建议加一句与回退路径同样的上下文断言作便宜硬化，不急。见 A38。**复核补充**：「构造不出触发镜像」不等于「构造不出变红的测试」——`MethodDescriptorAttribution.memberNode(forMethodDescriptorSymbols:in:)` 收的是 `Symbols` 值，手造一个含别类 `Tq` 名字的 `Symbols` 即可在单元级变红，修复批次顺手加断言时测试是有的 |
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
