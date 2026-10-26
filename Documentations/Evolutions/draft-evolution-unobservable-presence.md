# Draft - evolution 与 diff 区分「不存在」和「看不见」

- **状态**: Accepted
- **创建日期**: 2026-10-24
- **最后更新**: 2026-10-24
- **所属愿景**: 无
- **关联提案**: [0013](0013-swift-evolution-interface-builder.md)（evolution 联合接口）、[0060](0060-evolution-interface-available-annotations.md)（`@available` 只在生命周期能完整表达时才发）、[0024](0024-exported-declaration-flag.md)（类型与协议的导出状态）
- **实现分支 / PR**: `feature/evolution-unobservable-presence`（worktree `.worktrees/MachOSwiftSection-EvolutionUnobservablePresence`，基于 `next`）
- **配套文档**: [ABIEvolutionDesign.md](../Internal/ABIEvolutionDesign.md)、[ABIDiffDesignAndLimitations.md](../Internal/ABIDiffDesignAndLimitations.md) 第 6 节（符号化状态不对称）

## 摘要

evolution 和 diff 把每个声明在每个版本里只记成「在」或「不在」，分不出「不存在」和「这个版本看不见」。macOS 13.0–14.8 dyld shared cache 里的 SwiftUI 被剥掉了全部 local Swift 符号（11.x、12.x 与 15.0 以后都保留），非导出的函数、计算属性、初始化器在这些版本里一个都看不到，代码却都在（13.0 有 19.3 万个函数入口，只有 3.5 万个有名字）。结果 macOS 27.0 SwiftUI 跨 51 个版本的 evolution 里，有 5,189 条声明在 12.7 和 15.0 都在、中间却显示为缺席，多数印成 `removed in 13.0 · added in 15.0`；「removed in 13.0」之后再没出现的 13,033 条与只有一个 `added in 15.0` 事件的 12,329 条里，靠非导出符号才看得见的那部分，真实的变化可能发生在 13.0 到 15.0 之间的任何一版，却被钉在了端点上；对 12.7 和 13.0 做 diff，也会把这些声明报成删除并判为 breaking。本案让快照记下镜像有没有 local Swift 符号、每个成员是否导出，evolution 和 diff 据此把被剥的版本里本来就看不见的声明记为看不见而不是删除；一段看不见的版本两侧状态相同时按两侧推断、并在输出里标出，两侧不同时记成一个区间事件。

## 方案

**快照多记两件事**。`ABISnapshotDocument.currentFormatVersion` 从 7 升到 8，旧快照照已有的 `unsupportedFormatVersion` 报错、要求重新生成。

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
- 有看不见的版本的 lineage 即使没有事件也要收录，否则接口标不出推断；`EvolutionAnnotationIndex`「查不到就是全程都在、从未变化」的约定因此仍然成立。
- `LineageEvent` 加一个「最早可能发生在哪一版」，只有区间事件才有；`versionIndex` 仍是第一次观测到新状态的那一版，兼容性判定把区间事件算在这一步。

**显示**：

- evolution 联合接口和 lineage 报告的位图多两个符号：`◌` 看不见，`◍` 看不见、推断存在；图例说明这两个符号，并列出哪些版本没有 local Swift 符号。只有推断、没有事件的声明，注释写 `inferred present in 13.0–14.8`；区间事件写 `removed between 12.7 and 15.0`、`added between 12.7 and 15.0`。
- `@available`：涉及区间事件的不发，沿用 0060 的可表达性规则；推断存在的位置按存在算。
- diff 的文本报告和 `--json` 多一节，列出看不见的成员。`diff --interface` 的 `-` / `+` 这次不动，写进 `ABIDiffDesignAndLimitations.md` 第 6 节。
- 单版本的 `dump` / `interface` 不受影响。

**不在这次范围内**：

- 用汇编特征跨版本找回被剥的名字。测量办法是取两个都带符号的版本，把后一版的非导出名字藏起来，再从前一版借名字并与真名核对：小版本之间给出的声明名字约 99.5% 准，跨一个大版本约 91%，跨三年 63%–70%。进入 13.0 的那一步正好跨大版本，从 15.0 往回到 14.8 的那一步无法测量，只适合将来作为另一层推断。
- 用元数据直接观测被剥版本里的成员（witness table、vtable 槽位、协议描述符、ObjC 方法表），另开提案。
- 被剥前后身份变了的声明：协议要求在被剥的版本里变成 `pwtslot:` 记录、私有类型丢了 discriminator、同一个全局变量在两种状态下由不同的符号撑起。那 1,447 条 `added in 13.0 · removed in 15.0` 里有一部分属于这类。

**测试**：SwiftDiffingTests 用手工构造的快照覆盖两侧都在、两侧都不在、三种区间事件（added、removed、modified）、挨着轴端、导出成员与元数据记录的真缺席、普通 extension 整体看不见、一侧被剥时 N == 2 的 diff 与 evolution 一致、v8 编解码；`SymbolIndexStore` 的判据用 `ObjCImplementationFixture` 的 `.strippedLocals` 变体和普通变体各测一次；`EvolutionMarkingTests` 覆盖新符号、新短语、图例和区间事件不发 `@available`。实数据用 CLI 重跑 macOS 27.0 SwiftUI 的 51 版 evolution，核对那 5,189 条都变成推断存在，并统计区间事件的数量。

**文档**：同批更新 `ABIEvolutionDesign.md`、`ABIDiffDesignAndLimitations.md` 第 6 节、`Modules/SwiftInterface.md`，在术语表登记 unobservable，并更新 `AgentPlugins/swift-section` 的 skill（evolution 输出多了两个符号和两种短语）。

**落地步骤**（每一步单独构建通过、相关测试通过后提交）：

1. 快照记下两件事，格式版本升到 8：`SymbolIndexStore` 的判据与查询，`MemberRecord` 的导出判定与 `ABISnapshot` 的镜像级标记，`SwiftDiffableInterfaceBuilder` 冻结时填好。测试判据（fixture 的被剥变体）、冻结结果与编解码。
2. SwiftDiffing 里的看不见规则与按两侧推断：lineage 的状态数组、区间事件、收录规则；diff 的判定层（看不见的成员单列、不算 breaking）；两个文本报告与 JSON。测试方案里列出的手工快照用例。
3. evolution 联合接口：`EvolutionAnnotation` 带上状态与区间，`EvolutionMarking` 的新符号、短语、图例和 `@available` 规则。测试 `EvolutionMarkingTests` 与 `SwiftEvolutionInterfaceBuilderTests`。
4. 文档与 skill 同步；用 CLI 重跑 macOS 27.0 SwiftUI 的 51 版 evolution 做实数据核对，结果写进本提案。

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
