# 0082 - 一个版本由一组 image 组成的演进

- **状态**: Implemented
- **创建日期**: 2026-10-29
- **最后更新**: 2026-10-29
- **所属愿景**: 无
- **关联提案**: [0013](0013-swift-evolution-interface-builder.md)（evolution 联合接口）、[0081](0081-evolution-unobservable-presence.md)（看不见的版本）、MachOObjCSection 的 `0016-objc-evolution-image-groups`（ObjC 侧，随 MachOObjCSection 0.8.205 发布）
- **实现分支 / PR**: `feature/image-group-evolution`（worktree `.worktrees/MachOSwiftSection-ImageGroupEvolution`，基于 `next` e1221a02），2026-10-29 合入 `next`
- **配套文档**: [ABIEvolutionDesign.md](../Internal/ABIEvolutionDesign.md) 第七批、[Modules/SwiftInterface.md](../Internal/Modules/SwiftInterface.md)（`InterfaceVersionGroupUnit`）

## 摘要

evolution 一个版本只读一个 image。Apple 拆框架时声明会在 image 之间搬家：AppKit 的东西挪进 UIFoundation、CollectionViewCore、CoreAutoLayout，macOS 15 起 SwiftUI 的大批类型挪进 SwiftUICore（带 `@_originallyDefinedIn(module: "SwiftUI")`，mangled name 不变）。单 image 的演进把搬走的报成 removed、搬来的报成 added，其实它们没有消失。本案让一个版本由一组 image（image group）组成：组里的声明合成一个 API 面来比较，组内搬家不再报成增删，而是单独记成 moved（`> moved in 15.0: SwiftUI → SwiftUICore`）；lineage 报告、JSON 与联合接口都支持。顺带修掉一个单 image 就有的缺口：SwiftUI 二进制里给 SwiftUICore 类型加的成员，mangling 里没有 extension 上下文，索引器只在类型自己的 image 里收这类成员，结果 SwiftUI 的 dump、interface 与快照里它们整个消失（macOS 26.7 的 SwiftUI interface 里就没有 `Text.accessibilityTextContentType(_:)`）。ObjC 侧的同一功能由 MachOObjCSection 的会话实现，两边约定同一套模型与文案。

## 方案

**第一步：索引漏收的成员**（已完成，单独提交）。`SwiftDeclarationIndexer.indexExtensions()` 另外收「类型不在本 image、mangling 里也没有 extension 上下文」的成员（allocator、函数、计算属性、下标、静态存储属性；实例存储属性除外），当作该类型的 extension 成员，进 `extension <类型>`。三条判据同时成立才收：上下文是「模块 → struct、class、enum 一路下来」；那个模块是本 image 自己的类型或协议所在的 Swift 模块（`__C` 除外）；类型与协议的名字不在本 image 的定义里（用的是定义收成员时用的同一个名字）。单 image 的 interface 从此能看到这些成员（dump 不经这条路径，不变）；ABI 快照的格式版本从 9 升到 10，旧基线会把它们全报成新增。

这样收到的不只是拆分出去的类型的成员：同一模块里没有类型描述符的类型（编译器把只当命名空间用的内部 enum 的描述符删掉了）的成员、定义按名字收不到的成员，原先同样被丢掉，现在也一并出现在 `extension <类型>` 里。它们都是本模块真实的成员，只是先前看不见。渲染 A/B 在 Ultra 上跑，差异逐类核对后写进本提案。

**第二步：SwiftDiffing 的 image 组**（已完成）。

- 输入：每个版本一个有序的单 image 快照列表，主 image 在前：`ABIImageSnapshot(imageName:snapshot:)`；入口 `ABIEvolutionBuilder().evolution(ofImageGroups: [[ABIImageSnapshot]], versions: [ABIVersionDescriptor])`。单 image 快照与它的文档格式不变，image 名由调用方给出。组为空就当这个版本什么都没有。
- 合并：types、protocols、globals 直接拼接，同 key 的只比较组里第一个 image 的，其余走现有的 key collision 报出；四个 extension 桶里同 key 的容器合成一个，成员按组顺序拼接。组里定义了的类型，它的普通 extension 容器（没有协议、没有 `where`、不是 retroactive）并回类型本体：单 image 时这些成员本来就算在类型本体里，跨 image 才分出去，不并回就会在搬家那一版报成「类型里删掉、extension 里新增」。
- 看不见的版本：组里任一 image 没有 local Swift 符号，这个版本就按没有 local Swift 符号处理，宁可多标看不见，不误报删除。
- 搬家：一个声明在跳变两侧都观测到在场、两侧所在的 image 集合不同，就记一条 `ImageMove(versionIndex:oldImageNames:newImageNames:earliestVersionIndex:)`；中间隔着看不见的版本时比较两侧最近的观测，`earliestVersionIndex` 标出起点。成员只在旧集合 ≠ 新集合、并且 (旧, 新) 与所属容器的不同时才记，整个类型搬走时不给每个成员都记一遍。只有搬家的 lineage 也要收录；没有事件的成员 lineage 用 0081 加的 `latestSignature` 带签名。搬家不进兼容性判定：旧 image 有没有 re-export 新 image，快照里没有这个事实，只报不判。
- 模型只增不改：`ABIVersionDescriptor.imageNames`、`ContainerLineage.imageMoves`、`MemberLineage.imageMoves`、`ABIKeyCollision.droppedImageNames`，值为空时不编码，单 image 的 `evolution --json` 逐字节不变。
- 报告：头部那行下面紧跟 `Image group:` 与每个 image 的在场位图（按在轴上首次出现的顺序），`--summary-only` 也带；跳变摘要多一项 `N moved`；事件行与搬家行按版本合并排序，同一版本里事件在前：`> moved in 15.0: SwiftUI → SwiftUICore`、`> moved between 12.7 and 15.0: …`，集合用 ` + ` 连接；collision 警告写成 `dropped: <签名> (SwiftUICore)`。

**第三步：联合接口的 image 组**（已完成）。`SwiftEvolutionInterfaceImage(imageName:machO:)` 与 `AnySwiftEvolutionInterfaceBuilder(…, imageGroups:labels:…)`。内部一个版本由几个单 image 的渲染单元组成，每个声明交给索引它的那个 image 的打印器：容器按定义的身份找，成员跟着所属容器走，全局声明按 image 逐个列。并回类型本体的 extension 成员在类型体里渲染，与 evolution 的口径一致。注解多一种短语 `moved in 15.0: SwiftUI → SwiftUICore`，与其他短语按版本顺序用 ` · ` 连接；图例在位图位置那行之后加 `// Image group:` 与每个 image 的位图，放在 `@available` 说明之前。单 image 的构造与输出不变。

**第四步：集成测试与文档**（已完成）。`MachOImageName` 加 UIFoundation、CollectionViewCore、CoreAutoLayout；`ABIEvolutionTestSuite.MultiVersionDyldCacheImageTests` 加 `cacheImageNames`（默认只有主 image）和逐版本的 image 组，主 image 在场才上轴，其余在场才加入；Swift 侧新增 SwiftUI + SwiftUICore 的报告与联合接口套件（默认三版本轴与 51 版归档轴）；ObjC 的报告与联合接口套件（`ObjCAPIEvolutionTestSuite`、`ObjCEvolutionInterfaceTestSuite`）各加 AppKit + UIFoundation + CollectionViewCore + CoreAutoLayout 与 SwiftUI + SwiftUICore 两组，同样分默认三版本轴与归档轴，MachOObjCSection 的依赖下限随之抬到 0.8.205。产物文件名用组里的 image 名以 `+` 连接。文档同批更新 `ABIEvolutionDesign.md`、`Modules/SwiftInterface.md`、术语表（image group）与演进账本，agent 插件的 skill 只改快照格式那一段。

**没问就定下的假设**：

- 命令行这次不接，`evolution` 不加选项。
- 两版本的 `ABIDiffer.diff` 不加 image 组入口。
- 组里定义了的类型，它的普通 extension 容器不论 mangling 带不带 extension 上下文都并回类型本体；这只影响成员列在哪个容器下，不影响身份。

**测试**：第一步用现编的两 image fixture（`ProbeCore` 定义带 `@_originallyDefinedIn(module: "Probe")` 的类型，`Probe` 给它加成员），验证单 image 索引收到这些成员、带 extension 上下文的跨模块成员照旧；第二步用手工快照覆盖合并规则、并回、搬家（容器、成员、只跟着容器走的不记、隔着看不见的版本）、collision 的 image 名、单 image JSON 不变与两个文本报告；第三步用同一 fixture 的多个版本做联合接口端到端，并在 `EvolutionMarkingTests` 覆盖新短语与图例。测试一律在 JHs-Mac-Studio-Ultra 上跑。

**后续项**：

- 命令行入口：`evolution` 接收一组 image（这次按假设不接，有需要再提）。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-10-29 | Created as Draft，用户批准开工（Accepted） | 用户要 ObjC 演进的集成套件支持多个 image：AppKit 的东西搬进 UIFoundation、CollectionViewCore，SwiftUI 的搬进 SwiftUICore，只看一个 image 发现不了；库里的快照与演进模型都只认一个版本一个 image，用户决定直接实现 |
| 2026-10-29 | ObjC 侧交给 MachOObjCSection 的会话，本库做 Swift 侧与集成测试 | 用户的分工。两边约定同一套输入形状、搬家记录与文案；ObjC 侧另有 protocol 副本去重、同名 category 合并两条规则 |
| 2026-10-29 | 先把 `feature/evolution-unobservable-presence` 合进 `next` 再切本分支 | 一轮提问定案。两者改的是同一批文件（演进模型、builder、报告、接口注解），那个分支 10-25 起就是「实现完成，待合并」；已作为 0081 落地 |
| 2026-10-29 | 报告、JSON 与联合接口都做，命令行不接 | 一轮提问定案 |
| 2026-10-29 | 单 image 漏收成员这次一起修，作为第一步单独提交 | 核实时发现 SwiftUI 给 SwiftUICore 类型加的、没有 extension 上下文的成员在单 image 索引里整个消失（宿主 26.7 的 SwiftUI interface 里没有 `Text.accessibilityTextContentType(_:)`），不修的话 image 组里它们照样在 15.0 报成 removed；用户选择这次一起修 |
| 2026-10-29 | 成员搬家的签名放在 lineage 的 `latestSignature` 上，`ImageMove` 只记版本与两侧的 image；Swift 侧多一个 `earliestVersionIndex` | 0081 已经给没有事件的成员 lineage 加了 `latestSignature`；隔着看不见的版本时，搬家只能落在两次观测之间。ObjC 侧照同样的分工改了 |
| 2026-10-29 | 第一步的判据收紧：只认上下文是「模块 → struct、class、enum 一路下来」的成员，并排除本 image 定义的协议名 | 第一版只按类型名排除。全量测试里 SymbolTestsCore 的 interface 快照抓到误收：协议 `BasicDefaultProtocol` 的两个默认实现被列了两遍，带约束 extension 里三个嵌套类型的存储属性访问器成了 extension 成员。这些符号的上下文与本 image 的定义对不上名字，但它们都不属于别的 image |
| 2026-10-29 | 第一到第三步完成（Draft → Accepted → In Progress） | 在 JHs-Mac-Studio-Ultra 上验证（Xcode 26.6，远端依赖：MachOObjCSection 0.8.204、MachOKit 0.55.100、MachOKitExtensions 1.3.0、swift-demangling 0.7.2、swift-semantic-string 0.5.0）：复现测试在修复前 3 处失败、修复后通过；全量 `swift test --skip IntegrationTests` 2,729 个测试、518 个套件全部通过，原始退出码 0；IntegrationTests 编译通过，按项目规定不运行 |
| 2026-10-29 | ObjC 的两个集成套件等 MachOObjCSection 发版后再接 | ObjC 侧的 API 只在 MachOObjCSection 本地 `next`（118e8db）上，那边的提案还在等用户审。IntegrationTests 随全量一起编译，Ultra 与 CI 都按远端版本解析依赖，提前接会让 `next` 编不过 |
| 2026-10-29 | 第一步再加一条判据：成员所在类型的模块必须是本 image 自己的类型或协议所在的 Swift 模块（`__C` 除外） | 第一次渲染 A/B（基线 `next` e1221a02，候选 f97ba3b2；归档 cache 15.5 与 26.6、iOS 15.5 / 16.4 / 17.5 / 18.5 / 26.5 模拟器、进程内）所有 dump 一致，interface 在 SwiftUI、SwiftUICore、Combine 有差异。其中一部分是别的模块的成员：标准库内联进来的代码（`Swift.Array._endMutation()`、`Swift.String._copying(_:)`）、ClangImporter 给导入的 C 枚举合成的 `init?(rawValue:)`（`__C.UIButtonType`）、SwiftUI 里带进来的 `Foundation` 与 `Combine` 成员。它们不是本模块的 API，判据把它们排除；回归测试在 fixture 里调用 `ComparisonResult(rawValue:)`，修复前变红 |
| 2026-10-29 | 本模块里定义收不到的成员照样收进 `extension <类型>` | 同一次 A/B 里另一部分是本模块的成员：没有类型描述符的内部命名空间（`SwiftUI.Accessibility`、`Combine.CombineFeatures` 的静态成员）与定义按名字收不到的成员（如 iOS 15.5 SwiftUI 里 `ConicGradient` 的一个内部初始化器）。它们在单 image 里与拆分出去的类型的成员分不开，原先同样被丢掉；收进来是更完整的接口，不是误报 |
| 2026-10-29 | 第二次渲染 A/B 通过核对 | 基线 `next` e1221a02，候选 a0a7dc27，JHs-Mac-Studio-Ultra，Xcode 26.6，两侧共用一份 `Package.resolved`。96 对里 77 对逐字节一致，所有 dump 一致；差异只在 SwiftUI、SwiftUICore 与 Combine 的 interface，全部只增不减（每对删除 0 行），新出现的 extension 全在本 image 自己的模块上，别的模块的 extension 块两侧逐字节一致。规模：macOS 26.6 cache 的 SwiftUI +1,222 行、52 个新 extension（`Text.accessibilityTextContentType(_:)` 等，基线里没有），SwiftUICore +102 行、23 个；iOS 26.5 模拟器的 SwiftUI +1,336 行、69 个；iOS 15.5 模拟器（拆分之前）的 SwiftUI +191 行、35 个，都是没有类型描述符的内部命名空间之类本模块原先丢掉的成员；Combine 各场景 +3 行，即 `Combine.CombineFeatures` 的一个静态成员 |
| 2026-10-29 | 搬家按集合比较；被丢记录的文案收成 `ABIKeyCollision.droppedRecordDescriptions` 一处 | MachOObjCSection 的会话对照两边实现核对出两处不一致：联合接口末尾的 collision 警告没写 image 名，而报告写了；搬家按数组比较，调用方在两个版本里把同一组 image 换个顺序列，同时在两个 image 里的声明会被报成搬家。两条回归测试在修复前变红；两版本 diff 的报告也改用同一处文案。随后又按 ObjC 侧的做法补了一处：image 名与签名数量对不上时（只有手工构造或改过的 JSON 才会这样）只列签名，不再被 `zip` 悄悄截掉多出来的签名 |
| 2026-10-29 | 合入 `next`，取号 0082，状态改 Implemented | 先在本地合进常驻检出给用户看（3c4356cf；跨端核对的修复之后又合一次，1ed65d32），用户看过后正式收尾。最终代码 fa33331a（之后只改文档）在 JHs-Mac-Studio-Ultra 上全量 `swift test --skip IntegrationTests`：2,734 个测试、518 个套件全过，原始退出码 0（Xcode 26.6；远端依赖 MachOObjCSection 0.8.204、MachOKit 0.55.100、MachOKitExtensions 1.3.0、swift-demangling 0.7.2、swift-semantic-string 0.5.0）。渲染 A/B 沿用 a0a7dc27 上的第二次结果：此后的三处修复只改 evolution 的搬家判定与 collision 文案，单版本的 `dump` / `interface` 不经过它们。ObjC 的两个集成套件与命令行入口记为后续项 |
| 2026-10-29 | 不另写使用指南；术语已登记 | 实现说明在 `ABIEvolutionDesign.md` 第七批与 `Modules/SwiftInterface.md`。没有面向调用方的公开文档讲 evolution 的库 API（`SwiftSectionKit.md` 只讲命令对应的请求，这次没接命令行），所以不另写使用指南。image group 与 move 已登记进术语表 |
| 2026-10-29 | 接上 ObjC 的两个集成套件，MachOObjCSection 的下限抬到 0.8.205 | MachOObjCSection 0.8.205（它的提案 0016）发布了 image 组的 API。`ObjCAPIEvolutionTestSuite` 与 `ObjCEvolutionInterfaceTestSuite` 各加 AppKit + UIFoundation + CollectionViewCore + CoreAutoLayout、SwiftUI + SwiftUICore 两组，默认三版本轴与归档轴各一套；按 `objc` 子命令的方式建 indexer 的几行收成一个共用函数，单 image 的套件也改用它。在 JHs-Mac-Studio-Ultra 上只把 MachOObjCSection 解析到 0.8.205、其余依赖不变，全量 2,734 个测试、518 个套件全过，原始退出码 0；IntegrationTests 编译通过（按项目规定不运行）。后续项只剩命令行入口 |
