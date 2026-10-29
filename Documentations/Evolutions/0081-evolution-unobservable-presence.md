# 0081 - evolution 与 diff 区分「不存在」和「看不见」

- **状态**: Implemented
- **创建日期**: 2026-10-24
- **最后更新**: 2026-10-29
- **所属愿景**: 无
- **关联提案**: [0013](0013-swift-evolution-interface-builder.md)（evolution 联合接口）、[0060](0060-evolution-interface-available-annotations.md)（`@available` 只在生命周期能完整表达时才发）、[0024](0024-exported-declaration-flag.md)（类型与协议的导出状态）
- **实现分支 / PR**: `feature/evolution-unobservable-presence`（worktree `.worktrees/MachOSwiftSection-EvolutionUnobservablePresence`，基于 `next`），2026-10-29 合入 `next`
- **配套文档**: [ABIEvolutionDesign.md](../Internal/ABIEvolutionDesign.md)、[ABIDiffDesignAndLimitations.md](../Internal/ABIDiffDesignAndLimitations.md) 第 6 节（符号化状态不对称）

## 摘要

evolution 和 diff 把每个声明在每个版本里只记成「在」或「不在」，分不出「不存在」和「这个版本看不见」。macOS 13.0–14.8 dyld shared cache 里的 SwiftUI 被剥掉了全部 local Swift 符号（11.x、12.x 与 15.0 以后都保留），非导出的函数、计算属性、初始化器在这些版本里一个都看不到，代码却都在（13.0 有 19.3 万个函数入口，只有 3.5 万个有名字）。结果 macOS 27.0 SwiftUI 跨 51 个版本的 evolution 里，有 5,189 条声明在 12.7 和 15.0 都在、中间却显示为缺席，多数印成 `removed in 13.0 · added in 15.0`；「removed in 13.0」之后再没出现的 13,033 条与只有一个 `added in 15.0` 事件的 12,329 条里，靠非导出符号才看得见的那部分，真实的变化可能发生在 13.0 到 15.0 之间的任何一版，却被钉在了端点上；对 12.7 和 13.0 做 diff，也会把这些声明报成删除并判为 breaking。本案让快照记下镜像有没有 local Swift 符号、每个成员是否导出，evolution 和 diff 据此把被剥的版本里本来就看不见的声明记为看不见而不是删除；一段看不见的版本两侧状态相同时按两侧推断、并在输出里标出，两侧不同时记成一个区间事件。

## 方案

**快照多记两件事**。`ABISnapshotDocument.currentFormatVersion` 从 8 升到 9（起草时是 7 升到 8，落地前 8 已被 0077 占用），旧快照照已有的 `unsupportedFormatVersion` 报错、要求重新生成。

- 镜像级：有没有 local Swift 符号。判据是符号表里一个非外部的 `_$s` 符号都没有（STABS 不算）。`SymbolIndexStore` 的建表扫描本来就只从符号表收 local Swift 符号，在那里顺手记下，和 `ExportFacts.hasExportInformation` 放在一起；`SwiftDiffableInterfaceBuilder.snapshot()` 冻结时写进 `ABISnapshot`。
- 成员级：`MemberRecord` 加一个可选的导出判定，用 `--emit-export-status` 注释那个 `isExportedIncludingDerivedSymbols`（`Tj`、`Tq` 这类派生入口导出也算导出）。和 `hasDefaultImplementation` 一样只是判定用的元数据，不进 key。判定在 SwiftInterface 一侧做、以闭包交给 `ABIDiffer.snapshot(of:)`，SwiftDiffing 仍然不碰 Mach-O。

**哪些声明在没有 local Swift 符号的版本里看不见**：

- 只靠符号才出现的成员：函数、计算属性和下标、初始化器、`deinit`、全局变量和全局函数，而且它在前后最近一次看得见的版本里不是导出的。只要有一侧不是导出的或判定不出，就算看不见。
- 成员全是上面这种的普通 extension（不是 conformance 的那种）本身也看不见，因为它只由成员撑起。
- 其余照旧看得见，缺席就是真的缺席：类型、协议、conformance、存储属性、enum case、关联类型和关联类型 witness、`pwtslot:` 记录，以及导出的成员。

**按两侧推断**。规则放在 SwiftDiffing，evolution 和 diff 共用：

- 一段连续看不见的版本，两侧观测到的状态相同，就推断中间也是这个状态，没有事件。两侧都在时记为「看不见、推断存在」；两侧都不在时推断为不在，仍记为看不见。依据：在都带符号的年份里，两端都在、中间某版真的缺席的声明只占 0.15%（11.0–12.7，16,184 条里 25 条）到 0.6%（15.0–27.0，24,553 条里 148 条）；一直都在的声明不带位图、没算进分母，所以这两个数是上限。
- 两侧状态不同，就记成一个区间事件：变化发生在两侧之间的某一版。`modified` 同样处理，比较两侧的记录。
- 挨着版本轴两端的一段不推断。
- 只比两个版本是这条规则的特例：一侧没有 local Swift 符号时，在那一侧看不见的成员既不算删除也不算新增，在 diff 的报告与 JSON 里单独列出，不参与 breaking 判定。「N == 2 时 evolution 与 diff 给出的变化一致」的保证继续成立。

**模型只增不改**，`evolution --json` 现有的字段原样保留：

- `MemberLineage` / `ContainerLineage` 保留 `presence: [Bool]`，含义改为「观测到或推断为存在」；另加一个逐版本的状态数组，区分观测到存在、观测到不存在、看不见但推断存在、看不见。
- 有看不见的版本的 lineage 即使没有事件也要收录，否则接口标不出推断；`EvolutionAnnotationIndex`「查不到就是全程都在、从未变化」的约定因此仍然成立。成员只在它自己看不见、而容器在那个版本观测在场，并且那段区段有话可说（推断存在，或让边界变得不确定）时才因此收录；只因容器看不见而看不见的成员由容器的 lineage 交代，与增删容器的成员一样，diff 里也只列容器。
- `LineageEvent` 加一个「最早可能发生在哪一版」，只有区间事件才有；`versionIndex` 仍是第一次观测到新状态的那一版，兼容性判定把区间事件算在这一步。

**显示**：

- evolution 联合接口和 lineage 报告的位图多两个符号：`◌` 看不见，`◍` 看不见、推断存在；图例说明这两个符号，并列出哪些版本没有 local Swift 符号。只有推断、没有事件的声明，注释写 `inferred present in 13.0–14.8`；区间事件写 `removed between 12.7 and 15.0`、`added between 12.7 and 15.0`。
- `@available`：涉及区间事件的不发，沿用 0060 的可表达性规则；推断存在的位置按存在算。看不见的区段挨着轴端时同样不发；两侧都不在的区段按不在算，边界照旧是观测到的，属性照发。两侧都不在的区段只画 `◌`，不写短语。
- diff 的文本报告和 `--json` 多一节，列出看不见的成员。`diff --interface` 的 `-` / `+` 这次不动，写进 `ABIDiffDesignAndLimitations.md` 第 6 节。
- 单版本的 `dump` / `interface` 不受影响。

**不在这次范围内**：

- 用汇编特征跨版本找回被剥的名字。测量办法是取两个都带符号的版本，把后一版的非导出名字藏起来，再从前一版借名字并与真名核对：小版本之间给出的声明名字约 99.5% 准，跨一个大版本约 91%，跨三年 63%–70%。进入 13.0 的那一步正好跨大版本，从 15.0 往回到 14.8 的那一步无法测量，只适合将来作为另一层推断。
- 用元数据直接观测被剥版本里的成员（witness table、vtable 槽位、协议描述符、ObjC 方法表），另开提案。
- 被剥前后身份变了的声明：协议要求在被剥的版本里变成 `pwtslot:` 记录、私有类型丢了 discriminator、同一个全局变量在两种状态下由不同的符号撑起。那 1,447 条 `added in 13.0 · removed in 15.0` 里有一部分属于这类。

**测试**：SwiftDiffingTests 用手工构造的快照覆盖两侧都在、两侧都不在、三种区间事件（added、removed、modified）、挨着轴端、导出成员与元数据记录的真缺席、普通 extension 整体看不见、只因容器看不见或只在两侧都不在时看不见的成员不收录、一侧被剥时 N == 2 的 diff 与 evolution 一致、轴上没有被剥版本时 JSON 不出现新字段、v9 编解码，以及两个文本报告。`UnobservablePresenceFixture` 现编三版 dylib、中间一版 `strip -x`，在快照这一层验证判据与导出判定，并端到端验证联合接口的每一种注解。`EvolutionMarkingTests` 覆盖新符号、新短语、短语顺序、图例与 `@available` 的边界规则，`InterfaceAnnotationStyleTests` 覆盖着色。实数据用 CLI 重跑 macOS 27.0 SwiftUI 的 51 版 evolution，与同一命令在 `next` 上的输出逐行对比。

**文档**：同批更新 `ABIEvolutionDesign.md`、`ABIDiffDesignAndLimitations.md` 第 6 节、`Modules/SwiftInterface.md`，在术语表登记 unobservable，并更新 `AgentPlugins/swift-section` 的 skill（evolution 输出多了两个符号和两种短语）。

**落地步骤**（每一步单独构建通过、相关测试通过后提交）：

1. （已完成）快照记下两件事，格式版本升到 9：`SymbolIndexStore` 的判据与查询，`MemberRecord` 的导出判定与 `ABISnapshot` 的镜像级标记，`SwiftDiffableInterfaceBuilder` 冻结时填好。测试判据（fixture 的被剥变体）、冻结结果与编解码。
2. （已完成）SwiftDiffing 里的看不见规则与按两侧推断：lineage 的状态数组、区间事件、收录规则；diff 的判定层（看不见的成员单列、不算 breaking）；两个文本报告与 JSON。测试方案里列出的手工快照用例。
3. （已完成）evolution 联合接口：`EvolutionAnnotation` 带上状态与区间，`EvolutionMarking` 的新符号、短语、图例和 `@available` 规则。测试 `EvolutionMarkingTests` 与 `SwiftEvolutionInterfaceBuilderTests`。
4. （已完成）文档与 skill 同步；用 CLI 重跑 macOS 27.0 SwiftUI 的 51 版 evolution 做实数据核对，结果写进本提案。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-24 | Created as Draft | macOS 27.0 SwiftUI 的 evolution 里大批「removed in 13.0 · added in 15.0」经核实是 13.0–14.8 剥掉了 local Swift 符号造成的：这些版本的 nlist 里没有一个 `_$s` 函数或变量符号，函数入口数却比 12.7 还多，`App.main()` 照样调用 12.7 里叫 `runApp` 的那个函数；同期 libswiftCore、Combine、AppKit 的符号计数平稳 |
| 2026-10-24 | 范围定为 evolution 加 diff 的判定层，`diff --interface` 的渲染不动 | 一轮提问定案。同一条规则放在 SwiftDiffing 共用层，保住「N == 2 时 evolution 与 diff 一致」；diffable 渲染器按两侧结构直接比对，改它另算 |
| 2026-10-24 | 推断默认开启，并在位图与注释里标出 | 一轮提问定案。有符号的年份里两端都在、中间真缺的比例上限只有 0.15%–0.6%，比任何匹配都准；标出来是为了不把推断当成观测 |
| 2026-10-24 | 不做汇编匹配找回名字 | 测量结果见方案：跨一个大版本约一成名字给错，而进入 13.0 的那一步正是跨大版本，从 15.0 往回的那一步无法验证 |
| 2026-10-24 | 自动识别被剥的版本，不加手动开关 | 未提问自定。实测 SwiftUI 各版本的剥离是全有或全无；有 Swift 代码却一个 local Swift 符号都没有的镜像，几乎只会是被剥过的 |
| 2026-10-24 | 区间事件不发 `@available` | 未提问自定。沿用 0060「事实不能完整表达就不发属性、由注释兜底」 |
| 2026-10-24 | 模型只增不改，`presence: [Bool]` 保留 | 未提问自定。它是 `evolution --json` 的现有输出，脚本可能依赖；本机的下游仓库（RuntimeViewer、MachOKitUI、swift-decompiler）都不读 lineage 模型 |
| 2026-10-24 | 落地拆成四步 | 精简提案原本没有落地步骤；按「快照事实 → 判定规则 → 接口呈现 → 文档与实数据」拆开，每一步都能单独构建和测试 |
| 2026-10-24 | 用户批准（Draft → Accepted），开始实现 | 方案与全部假设照单通过 |
| 2026-10-24 | 判据读符号表条目的 `N_EXT` 位（新增 `NlistProtocol.isLocal`），不沿用 `isExternal` | 实现中发现本库的 `isExternal` 只指未定义的导入，符号表那两条收集路径收的是全部已定义符号、导出的也在内；照字面用它，被剥的版本也会因为导出符号而被判成「有 local Swift 符号」，fixture 的测试当场抓到。`ExportFacts` 注释里「只收 local 符号」的旧说法顺带更正 |
| 2026-10-24 | 成员导出判定的组合规则收进 `SymbolIndexStore.isExportedIncludingDerivedSymbols(names:in:)` | 快照要的判定和 interface 的 `// not exported` 注释是同一条规则（任一入口导出即为导出、查不到就不下结论）；printer 原来自己写了一份，现在两边都调这一处，不会走样 |
| 2026-10-24 | 测试改用专门的三版本 fixture（`UnobservablePresenceFixture`，中间一版 `strip -x`），在快照这一层验证判据 | 方案原想用 `ObjCImplementationFixture` 的被剥变体单测 `SymbolIndexStore`；改在冻结结果上测能同时覆盖判据与导出判定，而且第 3 步的端到端测试要的正是这样三个版本，一个 fixture 两用 |
| 2026-10-24 | 第 1 步完成（In Progress） | 定向测试通过：`UnobservablePresenceTests` 3 个、`ABISnapshotDocumentTests` 与 `ABIDifferAlgorithmTests` 共 14 个、`ExportedSymbolFactsTests` 5 个，以及受 printer 改动影响的导出注释与 `--exported-only` 套件，原始退出码 0。真实数据核对：此前导出的 nlist 里，12.7 与 15.0 的 SwiftUI 各有 149,409 与 167,325 个 local `_$s` 符号，13.0 与 14.8 一个都没有 |
| 2026-10-24 | 规则集中在 `UnobservablePresence.swift`，evolution 与 diff 共用 | 「看不见」的判定（`MemberRecord` / `ContainerSnapshot.needsLocalSymbolsToBeSeen`）、逐版本观测与按两侧推断（`PresenceObservation`、`PresenceResolution`）只写一份，两版本时两条路径不可能给出不同结论 |
| 2026-10-24 | 模型另加两个可选字段 `ABIEvolution.versionIndicesWithoutLocalSwiftSymbols` 与 `MemberLineage.latestSignature`，以及报告共用的 `UnobservedSpan` 和版本区间的标签函数 | 方案没写到。图例与报告要知道哪些版本没有 local Swift 符号；只为看不见的版本才收录、没有事件的 lineage 没有地方带签名，报告只能印出 mangled key。新字段都是可选的，值为空时不编码，所以没有被剥版本的轴，`evolution --json` 输出逐字节不变（测试钉住） |
| 2026-10-24 | diff 把看不见的东西放进 `ABIDiff.unobservableDeclarations`；看不见的容器连同它的成员一起列出 | 两版本的 evolution 会给容器和每个成员各留一条「看不见」的 lineage，diff 列出同样的集合，一致性测试据此比对。列表为空时同样不编码 |
| 2026-10-24 | 报告的 Transitions 段把区间事件计入首次观测到它的那一步，下面另起一行注明其中几条发生在哪两个版本之间 | 与兼容性判定的归属一致，又不让人误以为变化就发生在那一步 |
| 2026-10-24 | 第 2 步完成 | SwiftDiffing 108 个测试全过（新增 19 个），原始退出码 0；变异检验：去掉「两侧都在则推断存在」、让导出成员也算看不见，新测试有 7 个变红（退出码 1），还原后转绿。SwiftSectionKitTests 65 个、SwiftSectionCommandTests 106 个、SwiftInterfaceTests 317 个全过 |
| 2026-10-24 | `@available` 遇到任何一个「看不见」的版本就不发，推断存在照常算存在 | 方案只写了区间事件；实现时发现挨着轴端的看不见版本同样会让边界不成立（`[●◌]` 会被读成 `obsoleted:`），按同一原则一并排除 |
| 2026-10-24 | 着色规则 `InterfaceAnnotationStyle.lineKinds` 认 `… between` 短语，只标看不见版本的注释算 plain | 方案没写到。原规则把不含 `removed in` / `modified in` 的注释一律当新增，`removed between` 会被染成新增 |
| 2026-10-24 | 第 3 步完成 | 定向测试 `UnobservablePresenceTests`（新增 5 个端到端用例）、`EvolutionMarkingTests`（新增 7 个）、`InterfaceAnnotationStyleTests`（新增 1 个）全过；SwiftInterfaceTests 329 个、SwiftSectionKitTests 66 个、SwiftSectionCommandTests 106 个、SwiftDiffingTests 108 个全过，原始退出码 0。变异检验：去掉 `@available` 的边界判断、把着色默认值改回新增，3 个测试变红，还原后转绿。CLI 冒烟：对现编的三版 dylib（第二版 `strip -x`）跑 `evolution --interface --emit-available`、文本报告与 `diff`，输出与设计一致 |
| 2026-10-25 | 实数据核对后收紧两处：只因容器看不见、或只在两侧都不在的区段看不见的成员，不再因此收录，diff 里看不见的容器也只列容器本身；两侧都不在的区段不写短语，也不拦 `@available` | 第一次重跑 51 版 SwiftUI 时，新输出多了 21,805 条 `not observable in …`、`@available` 少了约 2.2 万行，抽样发现两类：容器自己已有注解（类型在 13.0 出现、15.0 迁去 SwiftUICore，或 extension 整体看不见），它的成员却跟着各标一次，与增删容器的成员一贯不标注的规则不一致；以及 12.4 就删掉的成员在 13.0–14.8 两侧都不在，什么都说不出，却写了短语、丢了本来成立的 `obsoleted:`。收紧后另有 169 条只剩位图、没有短语的成员注解随之消失 |
| 2026-10-25 | 第 4 步完成，实数据结果 | 同一命令（release 版 CLI，`--dyld-shared-cache -p …/SwiftUI --interface --emit-available`，51 份归档 cache）在 `next` 与本分支上各跑一次。`next` 的输出与 0073 之前生成的那份只差 0073 修好的 20 行。本分支对 `next`：208,706 行代码逐行相同；42,517 条注解不变，30,229 条只有 13.0–14.8 那几位变了，没有一条观测到的位置被改，也没有注解丢失；新增 151 条注解，全部是此前被容器的假缺口挡住的跨段增删。两端都在、中间缺席的 5,189 条里 5,097 条（98.2%）整段变成推断存在；`removed in 13.0 · added in 15.0` 从 5,089 条降到 24 条（类型的真实删除、丢了 discriminator 的私有类型，以及几条公开 `static let` 在被剥前后由不同的访问器撑起，属方案列出的范围外情形）；`removed in 13.0` 从 18,293 降到 1,700、`added in 15.0` 从 19,596 降到 4,472，其余换成 2,084 / 2,065 / 17 条 `removed` / `added` / `modified between 12.7 and 15.0` 与 17,684 条 `not observable in …`（多是容器在 13.0 出现或 15.0 搬走、成员自己说不清何时增删的情形）。`@available` 行从 66,711 降到 48,214，去掉的都是边界不确定的。峰值内存占用（peak memory footprint）4.46 GB 对 `next` 的 4.41 GB，多 58 MB（约 1.3%，新增的导出判定与逐版本状态）；RSS 两边都是 12.8 GB，多是只读映射的 cache 页。这台 28 核机器上 release 版用时 216 秒 |
| 2026-10-25 | 实现完成，待合并 | 全量 `swift test --skip IntegrationTests`（收紧前的第 3 步代码）2,578 个测试全过，原始退出码 0；收紧后重跑受影响的 SwiftDiffingTests 110 个、SwiftInterfaceTests 330 个、SwiftSectionKitTests 66 个、SwiftSectionCommandTests 106 个，全过。每次收紧都做了变异检验（改回原规则，对应的新测试变红，还原后转绿）；最终提交上再跑一次全量，2,581 个测试全过，原始退出码 0。没有跑渲染 A/B：单版本的 `dump` / `interface` 只动了 printer 里导出判定的一处等价改写，相关的导出注释与 `--exported-only` 套件都过了。不另写使用指南或实现说明：规则与取舍写在 `ABIEvolutionDesign.md` 第六批与本提案；新术语 unobservable 已登记 |
| 2026-10-29 | 合入 `next`，取号 0081，状态改 Implemented | 用户决定先把本分支合进 `next`，再在合并后的 `next` 上做多 image 演进，两者改的是同一批文件。把 `next` 合进分支时解了四处冲突：快照格式版本（`next` 上 0077 已占用 8，本案改为 9）、两份文档索引、skill 里的格式说明（写明 8 和 9 都随 0.25.0 发布，8 只在开发分支上存在过）。`next` 后来加的 `AbbreviatedIdentifierScanTests` 抓到本案代码里的 `lhs` / `rhs`，改名为 `left` / `right`。合并结果在 JHs-Mac-Studio-Ultra 上验证（Xcode 26.6，远端依赖：MachOObjCSection 0.8.204、MachOKit 0.55.100、MachOKitExtensions 1.3.0、swift-demangling 0.7.2、swift-semantic-string 0.5.0；fixture 用 0.24.0 发版审计时编的那份，此后 fixture 源码只改过注释）：全量 `swift test --skip IntegrationTests` 2,700 个测试、514 个套件，只有这条扫描失败；改名后重跑扫描与 SwiftDiffingTests，112 个测试全过，原始退出码 0 |
| 2026-10-29 | 不另写使用指南或实现说明，不新增术语 | 规则与取舍已写在 `ABIEvolutionDesign.md` 第六批与本提案；unobservable 已在 10-25 登记进术语表 |
