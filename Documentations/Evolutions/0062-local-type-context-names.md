# 0062 - 局部类型的名字：找回函数与闭包上下文

- **状态**: Implemented
- **创建日期**: 2026-10-10
- **最后更新**: 2026-10-11
- **所属愿景**: 无
- **关联提案**: [0050-symbolic-mangling-symbol-index](0050-symbolic-mangling-symbol-index.md)（对照测试发现并登记了这个问题，`_symbolic` 符号是这里的来源之一）
- **实现分支 / PR**: `feature/local-type-context-names`（worktree `.worktrees/MachOSwiftSection-LocalTypeContextNames`，基于 `next`），按本仓库惯例在本地合并进 `next`
- **配套文档**: 名字的三个来源与找不回函数的情况见 [SymbolicManglingSymbols.md](../Internal/SymbolicManglingSymbols.md)「边界」；CLI 用户在 dump / interface 里看到的写法见 `swift-section` agent skill 第 9 节（`AgentPlugins/swift-section/skills/swift-section-cli/SKILL.md`）；同类但不修的三处见 [ReviewAdjudications A60](../Internal/ReviewAdjudications.md)
- **起因**: RuntimeViewer 会话在 macOS 27.2 的 SwiftUI 上复现并查清根因后转交；早先的记录在 [Roadmaps/2026-09-24-local-type-context-names.md](../../Roadmaps/2026-09-24-local-type-context-names.md)

## 摘要

函数、闭包里声明的类型（local type）挂在一串 anonymous context 下面：类型本身、闭包、函数各一层（`lib/IRGen/GenDecl.cpp` 的 `getAddrOfContextDescriptorForParent`）。release 构建不给这些 anonymous context descriptor 写名字，所有系统框架和测试 fixture 都是 release 构建。`SymbolicDemangler` 于是只能二选一：

- 把整串丢掉。局部类型变成了外层类型的成员，同一类型里不同函数的同名局部类型撞成一个名字。SwiftUI 的 `TableDataSource` 有 7 个 `Visitor`，其中 6 个都解成 `SwiftUI.TableDataSource.Visitor`，索引器按名字存定义，只留下最后一个，嵌套遍历又把它追加了 6 次。结果 interface 里 5 个类型丢失、1 个重复 6 遍。
- 用 `first(of: .privateDeclName)` 从外围的 private 函数借来 private discriminator，把局部类型伪造成 private 类型，比如 `AccessibilityRotorInfo.(unknown context at _0306…).(IndexingWrappingGenerator in _0306…)`。

名字一错，用真名记录的成员符号就对不上，成员静默丢失。带扩展上下文的成员（`~Copyable` 泛型参数让成员落在一个 inverse 约束扩展里）会单独建一个 extension，RuntimeViewer 在顶层找不到同名类型，就把它列成一个孤立的 Ex。

debug 构建名字是有的（`-g -Onone` 时 driver 自动加 `-enable-anonymous-context-mangled-names`），但结果也会错。2025-05 的 `be2f186e` 把 anonymous context 从「保留成节点」改成了「直接丢掉」。`adoptAnonymousContextName` 后面那个判断要求父级是 anonymous context 节点才覆盖，此后只在外围函数恰好是 private、借到了 discriminator 时才成立。debug 版 swift-section 自己 dump 自己，`PendingRebuild #1 in getUnspecialized(_:)` 印成了 `PendingRebuild #1 in Demangling`，两个不同闭包里的 `VisitedPair` 撞成同一个名字。

本提案让 `SymbolicDemangler` 从三个来源找回局部类型的完整名字，三处都没有时按位置起一个不撞名的占位名；runtime 名字那条路同样处理；interface 打印器补上局部类型的写法。

## 方案

### 改动位置

- `Sources/Analysis/SwiftInspection/SymbolicDemangler.swift`
  - `adoptAnonymousContextName`（`:544`）与 `demangleAnonymousContextName`（`:573`）：anonymous context 的名字按三个来源依次取，见下一节。
  - `buildContextDescriptorMangling`（`:427`）：采用了名字、而 anonymous context 上面还是 anonymous context（即局部类型）时，名字里的上下文（闭包、函数）整体代替那串 anonymous context，不再逐层构建它们；覆盖条件按描述符判断，不再看节点的 kind。三处都没有名字的局部类型，名字写成 `PrivateDeclName("$<地址>", 名字)`。
  - `resolvedPrivateDiscriminatorIdentifier`（`:110`）与 `.anonymous` 分支（`:490`）：private discriminator 只取被包着的类型自己的 private 名字，不再从外围函数借。
  - `.opaqueType` 分支（`:508`）：同一个「看节点 kind」的判断改成按描述符判断，名字同样走三个来源。不改的话，debug 构建里 private 泛型函数的 opaque type 会因为上一条而丢名字。
- `Sources/Analysis/SwiftInspection/AnonymousContextPrivateDiscriminatorIndex.swift`：被引用者的名字是 `localDeclName` 时，把编译器写下的完整名字也记下来（`:131` 以前一律放弃）。类改名为 `AnonymousContextNameIndex`，它记的已经不只是 discriminator。
- `Sources/Output/SwiftDeclarationRendering/RuntimeTypeNameDemangling.swift`（`:59`–`:107`）：runtime 用 `$地址` 表示的 anonymous context 走同一套来源；局部类型的整串 anonymous context 由名字里的上下文代替；找不到名字的局部类型用同样的占位名。
- `Sources/Analysis/SwiftInspection/LocalTypeNaming.swift`（新增，公开）：`Node.localTypeNaming` / `NodeReference.localTypeNaming` 判断一个名字是不是局部类型、名字是编译器给的（`.compilerSpelled`）还是按位置起的（`.positionBased`）。打印器用它，RuntimeViewer 做 Local 标签、从 Private 标签里排除占位名也用它，不必自己按 `$` 猜。
- `Sources/Analysis/SwiftInspection/NodeTypeNaming.swift`（`qualifiedName(ofNominal:)`、`declaredName(of:)`）：静态布局引擎和 ObjC 那边按这个限定名给类型建索引、按名字查字段类型。局部类型的限定名以前只算得出光秃秃的 `Visitor`（函数上下文没有前缀），不同函数里的同名局部类型撞键；改成带上声明它的函数和 `#序号`，按位置命名的带上 `$` 地址。
- `Sources/Output/SwiftPrinting/NodePrintables/TypeNodePrintable.swift`（`printType`，`:156`）：类型位置上的局部类型印短名。现在函数、闭包这类上下文和 `localDeclName` 都印成空，debug 版 interface 里已经有 `__derived_struct_equals(_: , _: )`。
- `Sources/Output/SwiftDiffing/ABISnapshotDocument.swift`：`currentFormatVersion` 6 → 7，理由见决策日志。
- `Sources/Output/SwiftPrinting/SwiftDeclarationPrinter.swift`（`printIncludedTypeDefinition`）与 `SwiftDeclarationPrinter+Headers.swift`：局部类型的声明前加一行注释，写出它在哪个函数里；按位置命名的局部类型（以及嵌在它里面的类型）的 extension 头印带 `$` 的全名，否则会读成 `Holder.Visitor` 这种源码里没有的成员类型路径。diff / evolution 渲染器自己拼声明头，这批不加注释。
- 名字对上之后才暴露的五处整树搜索。成员节点的第一个子节点是上下文，witness 还把 conformance 排在 requirement 前面，前序搜索于是先碰到局部类型的外层声明。以前局部类型的名字对不上，这些符号从来匹配不到，问题一直藏着：
  - `Sources/Declaration/SwiftDeclaration/Extensions/DemanglingNode+MemberSubtree.swift`（新增）、`MemberSymbolBucketing.swift`（`addSymbol`）、`DefinitionBuilder.swift`：conformance 成员只按 witness 的 requirement 分类、去重。否则声明在 getter 里的类型，witness 全被当成以 getter 命名的属性丢掉；`static` 方法里的类型，witness 全进 `static` 桶；方法类 witness 都按外层函数去重，只剩一个（SwiftUI 的 `CodingKeys`、`HostKeys` 少了 `_rawHashValue`、`init?(intValue:)`、`_updateDefault` 等）。
  - `TypeDefinition+SynthesizedMembers.swift`（`labels(of:)`）：取成员自己声明节点上的标签。否则外层函数的标签顶替成员的，合成的 `hash(into:)`、`encode(to:)` 去不掉，在主体里重复出现。
  - `Sources/Declaration/SwiftAttributeInference/TypeAttributeInferrer.swift`（`hasDynamicMemberSubscript`）：取下标节点自己的标签，否则推断不出 `@dynamicMemberLookup`。
  - `Sources/Output/SwiftPrinting/NodePrintables/FunctionTypeNodePrintable.swift`（`printLabelList`）：参数全是匿名时，`_` 标签的个数按成员自己的参数元组定，不再按外层函数的。
  - `Sources/Declaration/SwiftDeclaration/Extensions/DemanglingNode+AccessorKind.swift`（`accessorKind`）：前序遍历里先碰到访问器还是先碰到成员自己的 `variable` / `subscript`，以先碰到的为准。否则声明在 getter 里的类型，它的 `static` 存储属性的存储符号被读成 getter，打印成 `{ get set }` 的计算属性。

### 明确不动

ABI 层（`MachOSwiftSection`）、符号索引（`MachOSymbols`）、索引器的嵌套遍历（`SwiftDeclarationIndexer.swift:525`，局部类型照旧挂在外层类型下，见决策日志）、RuntimeViewer 仓库。同类整树搜索里还有三处不改：`final` 恢复的 `Tq` 兜底、上游的 `DemanglingNode.identifier`、`DefinitionBuilder` 挑变量代表节点的那一步，理由见 [ReviewAdjudications A60](../Internal/ReviewAdjudications.md)。

### 名字从哪来

一个 anonymous context 的名字，就是编译器给它的 mangling（`IRGenMangler.h` 的 `mangleAnonymousDescriptorName`）。包着类型的那一层，名字就是类型自己的完整名字，比如 `Visitor #1 in TableDataSource.performDrop(to:)`。三个来源依次试：

1. **描述符自带的名字**：只有 `-enable-anonymous-context-mangled-names` 时才写，也就是 debug 构建。
2. **anonymous descriptor 上的符号**：`$s<上下文>MXX`（`mangleAnonymousDescriptor`），解出来是 `AnonymousDescriptor(<上下文>)`，剥掉这一层就和第 1 条相同。没剥本地符号的镜像都有：缓存里的 SwiftUI、SwiftUICore，测试 fixture。缓存里的 AppKit 一个都没有。
3. **`_symbolic` 符号**：有字段描述符的类型，编译器都会给它的类型名记一个 `_symbolic` 符号，里面是完整名字。剥了本地符号的系统框架照样留着它（AppKit 就靠它）。它按类型描述符记，所以只覆盖直接包着类型的那一层。

都没有时（主要是 strip 过的第三方 App），按 runtime 和 Remote Mirror 的做法用位置起名：`TableDataSource.(Visitor in $1a2b3c)`。数字是包着类型的那个 anonymous context 的地址，口径与 dump 的成员地址注释相同（`address(forOffset:)`：缓存镜像取未滑动的虚拟地址，独立文件取 vmaddr），所以 `MachOFile` 与进程内两条路径的名字一样。这个名字不撞名、不丢类型，只是看不出在哪个函数里。它借用 `privateDeclName` 的形状，是因为这个形状每个下游都已经会处理；`$` 开头的 discriminator 不是真的，RuntimeViewer 的 Private 标签要用 `localTypeNaming == .positionBased` 把它排除。

匿名上下文的名字以后只整体使用：采用名字时，类型自己的名字（`localDeclName` 或 `privateDeclName`）连同名字里的上下文一起用；private discriminator 只从「被包着的类型自己的 `privateDeclName`」取，函数、闭包的名字里有 `privateDeclName` 也不取。进程内按地址查名字要扫整张符号表，所以和 discriminator 一样按地址记忆。

### 输出

dump 的声明头打印完整名字，debug 构建今天就是这样：

```swift
struct Visitor #1 in SwiftUI.TableDataSource.performDrop(to: SwiftUI.DropCoordinator<Foundation.IndexPath>) -> () {
```

interface 里局部类型照旧嵌在外层类型里，声明前加一行注释写出所在函数，参数、字段这些类型位置印短名 `Visitor`，conformance 的 extension 头保留编译器全名。下面是 `TableDataSource` 的头两个 `Visitor`，字段从略：

```swift
struct TableDataSource {
    // Visitor #1 in TableDataSource.performDrop(to:)
    struct Visitor: ~Swift.Copyable {
        …
    }
    // Visitor #1 in TableDataSource.itemProvider(at:)
    struct Visitor: ~Swift.Copyable {
        …
    }
}
```

### 测试

- 仿照 `RenamedObjCClassFixture` 在测试里现场编一个局部类型 fixture（`LocalTypeFixture`）。五个变体各用自己的模块名，可以同时加载进测试进程；前三个各只留一个名字来源：
  - `debugNames`：`-Xfrontend -enable-anonymous-context-mangled-names` 编译后 `strip -x`，只有描述符自带的名字；
  - `anonymousDescriptorSymbols`：只保留导出符号、导入符号和 `MXX`；
  - `symbolicReferences`：只保留导出符号、导入符号和 `_symbolic`，AppKit 就是这个形状；
  - `unstripped`：一个符号都不剥，SwiftUI 在 cache 里就是这个形状，也是唯一留着成员符号的变体，用来验证成员能挂回类型；
  - `stripped`：`strip -x`，三处都没有。

  `strip -R` 只能删全局符号，删不掉 `MXX` 这种本地符号，所以只留一部分本地符号的两个变体用 `strip -s <保留清单>`；它只留得住原本是 private extern 的本地符号（`MXX`、`_symbolic` 是，成员实现符号不是）。strip 会让签名失效，每个变体都用 `codesign --force --sign -` 重签，才能 `dlopen`。形状覆盖 private 与非 private 的外围函数、闭包、同一类型里不同函数的同名局部类型、同一函数里的 `#1` 与 `#2`、局部类型里的嵌套类型、`~Copyable` 泛型参数让成员落在扩展上下文里、另一个模块的类型的 extension 里的局部类型、顶层函数里的局部类型、泛型函数的 opaque type。`MachOFile` 与进程内两条路径都跑，runtime 名字那条路也跑。
- 成员的测试拿局部类型和声明在任何函数体之外的「孪生」类型对照（`KeyTwin`、`PayloadTwin`、`LookupTwin`）：声明在 getter、`static` 方法、`throws` 方法、带标签的方法里的局部类型，每个 conformance 列出的成员、成员所在的数组（实例 / `static`、函数 / 属性 / 初始化器）、主体里的成员（含 `static` 存储属性）和 `@dynamicMemberLookup` 都要与孪生类型相同。期望值来自孪生类型，不来自被测代码对局部类型的输出。
- `SymbolicManglingIndexTests.descriptorBuiltNamesAgreeWithTheCompilersSpelling` 去掉 `withKnownIssue`：AppKit 里被直接引用的局部类型，从描述符还原的名字要与编译器写的一致。
- SymbolTestsCore 里本来就有一个局部类型（`outerWithLocalClass()` 里的 `LocalClass`），它的 dump 与 interface 快照重新生成。
- 系统框架 dump / interface 的 A/B 对比：差异只能是局部类型的名字、interface 里局部类型的写法，以及因此挂回来的成员。结果是 96 对里 30 对有差异，全在 SwiftUI / SwiftUICore，逐对核对都来自局部类型，没有一对少了成员；当前系统的 AppKit 只有 3 个局部类型变化。明细见 [ProjectEvolutionLog](../Internal/ProjectEvolutionLog.md) 本批一节。

### 已知限制

- 占位名看不出在哪个函数里。strip 过的 App 里，局部 class 的 ObjC 运行时名（`_TtCF…`，旧 mangling）其实带着函数上下文，可以作为第四个来源，本提案不做。
- 局部类型不会出现在泛型上下文里（编译器报 `type '…' cannot be nested in generic function`），所以离线特化不会遇到「局部类型外面的函数带实参」这种名字；局部类型里面可以有泛型类型（SwiftUI 的 `IndexWrappingVisitor<Base>`），它的参数是自己的，按普通嵌套类型处理。
- dump 的声明头先印名字、再接泛型参数，泛型局部类型于是读成 `IndexWrappingVisitor in WrappingGenerator #1 in M.Holder.wrapping() -> Swift.Bool<A>`，`<A>` 像是挂在 `Bool` 上。debug 构建早就是这样，属于 dump 拼声明头的既有写法，这批不改。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-10 | 创建为 Draft，用户批准后直接置为 In Progress | RuntimeViewer 会话转交的调查结果，用户要求接手修复。 |
| 2026-10-10 | 局部类型照旧挂在外层类型下，不提到顶层 | 用户选择。与 debug 构建今天的行为一致，索引器不用改；RuntimeViewer 侧边栏默认也挂在外层类型下，那边再加 Local 标签。 |
| 2026-10-10 | interface 里类型位置印短名，声明前加注释写出所在函数，extension 头保留编译器全名 | 用户选择。编译器全名太长，也不是合法 Swift；只印短名又分不清同名的几个，注释补上这一点。 |
| 2026-10-10 | 三个来源都没有时按位置起占位名，不维持现状 | 用户选择。现状会让同名局部类型互相覆盖，丢类型；占位名照 runtime 和 Remote Mirror 的做法，不撞名，代价是 RuntimeViewer 的 Private 标签要排除 `$` 开头的 discriminator。 |
| 2026-10-10 | `AnonymousContextPrivateDiscriminatorIndex` 改名为 `AnonymousContextNameIndex` | 它要记局部类型的完整名字，不只是 discriminator；`package` 级，不影响公开 API。 |
| 2026-10-10 | 删掉「泛型函数里的局部类型做离线特化」这条已知限制 | 试编 fixture 时编译器报 `type '…' cannot be nested in generic function`：局部类型根本不会出现在泛型上下文里。 |
| 2026-10-10 | fixture 加第五个变体 `unstripped` | `strip -s` 只留得住原本是 private extern 的本地符号（`MXX`、`_symbolic`），成员实现符号留不住，「只有 `MXX`」的变体里成员就没了；成员归属的测试改用不剥的变体。 |
| 2026-10-11 | 新增公开的 `LocalTypeNaming` | 打印器要分辨局部类型；RuntimeViewer 的 Local / Private 标签也要分辨，给一个受支持的接口，免得下游按 `$` 前缀猜。 |
| 2026-10-11 | `NodeTypeNaming` 的限定名一并改为带函数上下文 | 横向排查同类问题时发现：静态布局引擎按限定名建索引、按名字查字段类型，局部类型的限定名退化成光秃秃的 `Visitor`，同名的撞键。修复前同样撞（当时是 `M.Holder.Visitor`），属于同一类。 |
| 2026-10-11 | ABI snapshot `formatVersion` 6 → 7 | snapshot 记录全部类型，容器键是类型名的 mangling；局部类型改名后，旧基线对比新工具会把每个局部类型连同成员、conformance 报成删掉再加上，删掉类型算破坏性变更，`--fail-on-breaking` 的 CI 会误报失败。照 v6 的先例（记录方式变了、键格式没变也提升）提升，让旧基线以明确的错误被拒。 |
| 2026-10-11 | 成员分类、去重、三处标签读取和访问器种类改为只看成员自己的节点 | 系统框架 A/B 里 iOS 26.5 模拟器那条腿的 SwiftUICore 少了 conformance 成员（`_rawHashValue`、`_updateDefault`、`CodingKeys` 的初始化器）。基线里名字对不上，witness 符号匹配不到，退回按 requirement 打印，反而完整；名字对上以后拿到真正的 witness 符号，整树搜索就先碰到了外层声明。横向排查又找到四处同类，都用 fixture 复现、先红后绿。 |
| 2026-10-11 | `final` 恢复的 `Tq` 兜底、上游 `DemanglingNode.identifier`、变量的代表节点不修，登记 ReviewAdjudications A60 | 第一处被按节点的 descriptor 连接挡在前面，第三处因为符号表里 getter 总在最前，都造不出会变红的测试；第二处在上游包里，要局部类型声明在运算符函数里才触发。 |
| 2026-10-11 | 测试里 `__derived_struct_equals(Visitor, Visitor)` 的期望改为 `(_: Visitor, _: Visitor)` | 当时把无标签的输出当成打印器的既有写法；其实是 `printLabelList` 按外层函数 `countValues()` 的空参数元组算标签，与孪生类型对照后确认是错的。 |
| 2026-10-11 | In Progress → Implemented，编号 0062 | 用户确认合入。按共享分支编号（origin/next 与 origin/main 最大都是 0061），开工后 `next` 没有新提交，不用 rebase；本地合并进 `next`；演进账本第 87 节 |
| 2026-10-11 | 收尾判断：不另写专题文档；新术语已登记 | 名字的三个来源与找不回的情况写在 SymbolicManglingSymbols.md「边界」，CLI 用户看到的写法写在 agent skill 第 9 节，整树搜索的陷阱写进 AGENTS.md，不修的三处在 A60，都已登记在头部；其余实现决策都在本提案与演进账本里，没有再值得单列的。「position-based name」（按位置起的名字）是本提案新造的说法，已登记术语表；`LocalTypeNaming` 是标识符，不登记 |
