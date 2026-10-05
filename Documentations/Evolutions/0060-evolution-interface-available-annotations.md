# 0060 - evolution 联合接口的 @available 生命周期标注

- **状态**: Implemented
- **创建日期**: 2026-08-31
- **最后更新**: 2026-10-05
- **关联提案**: [0013](0013-swift-evolution-interface-builder.md)（evolution 联合接口本身，以及它否决过的伪 `@available` 形态）、[0058](0058-swift-section-kit.md)（命令行逻辑所在的 SwiftSectionKit）
- **实现分支 / PR**: `feature/evolution-interface-available-annotations`（worktree `.worktrees/MachOSwiftSection-EvolutionAvailableAnnotations`，基于 `next`），按本仓库惯例在本地合并进 `next`
- **配套文档**: 模块文档 [Modules/SwiftInterface.md](../Internal/Modules/SwiftInterface.md)「子系统 5」与「消费入口速查」、[Modules/SwiftSectionKit.md](../Internal/Modules/SwiftSectionKit.md)；使用指南 [SwiftSectionKit.md](../SwiftSectionKit.md) / [SwiftSectionKit_zh.md](../SwiftSectionKit_zh.md) 的「Errors / 错误」；任务报告 [TaskReports/2026-08-31-evolution-interface-available-annotations.md](../Internal/TaskReports/2026-08-31-evolution-interface-available-annotations.md)

## 摘要

`swift-section evolution --interface` 的联合接口目前用位图注释（`// [○●●] added in 18.0`）承载每条声明的生命周期。本案在此之上增加**真实、语法合法的 `@available` 属性行**：当一条声明的生命周期能被一条 `@available` 完整表达时，在声明上方渲染 `@available(iOS, introduced: 18.0, obsoleted: 26.0)`；位图注释原样保留，继续承载属性表达不了的事实（modified 事件、多区间形状等）。flag 门控、默认关，默认输出逐字节不变。

## 方案

**事实层零改动**：属性只从 `EvolutionAnnotation`（presence 位图 + `LineageEvent`）派生，与位图注释同一事实源（`EvolutionAnnotationIndex`），两种呈现永不打架。

**可表达性判据**（不满足任一条即整条声明不发属性，注释兜底）：

- presence 位图必须是单一在场区间 `○ᵃ●ᵇ○ᶜ`（a、c ≥ 0，b ≥ 1）；`●○●` 这类多区间不发。
- `introduced:` 事实仅在 a ≥ 1 时存在（首版就在场 = 早于轴起点，没有 introduced 事实，不发）；`obsoleted:` 事实仅在 c ≥ 1 时存在（removal 映射为 `obsoleted:`）。两个事实都不存在（全程在场，只有 modified）→ 不发。
- 涉及的版本标签必须能解析为 1–3 段数字版本号（`26.0` / `18.5.1`）；文件名回退标签解析不了 → 不发。
- modified 事件永不进属性（`@available` 无此语义），始终留在注释短语里。

**平台名从哪来**：由 SwiftSectionKit 的 `ABIEvolutionRequest.AvailabilityAttributes` 决定，它是 `Report.annotatedInterface(availabilityAttributes:)` 的关联值，所以「只有 annotated interface 才有属性」在类型上写不出反例。三种取值：`.none`（不发属性，即原来的输出）；`.inferredPlatform`（读每个输入的 `LC_BUILD_VERSION`，模拟器算作对应的设备平台，映射成 `@available` 的拼写 macOS / iOS / tvOS / watchOS / visionOS / macCatalyst）；`.platform(String)`（调用方直接给拼写）。推断在加载之后、索引之前做，失败就抛 `AvailabilityPlatformInferenceError`：某个输入没有 `LC_BUILD_VERSION`、或者它的平台在 `@available` 里没有名字（DriverKit、bridgeOS），抛 `.noPlatform(path:)`；输入之间平台不一致，抛 `.conflictingPlatforms(_:)`。响亮失败，不悄悄地退回不发属性。`LC_BUILD_VERSION` 用 MachOKitExtensions 公开的 `buildVersionCommand` 读，TypeIndexing 按同一条 load command 选 SDK（`Sources/Declaration/TypeIndexing/SwiftInterfaceBuilderTypeNameProvider.swift`）。

**命令行**：`evolution --emit-available` 打开属性，只能和 `--interface` 一起用；`--platform <拼写>` 覆盖推断，只能和 `--emit-available` 一起用，两条组合规则在 `validate()` 里拒绝。`makeRequest()` 把这两个 flag 映射成上面三种取值。库的两种推断错误由 `CommandLineErrorTranslation` 译成指向 `--platform` 的 `ValidationError`（退出码 64）。

**渲染位置**：属性是独立的一行 `EvolutionLine`（自身不带 annotation），成员单元插在声明行上方、容器单元插在 header 首行上方（header 的属性行本就先于声明行，锚点规则不变）；位图注释与逐块列对齐逻辑不动。生成属性文本的是格式层纯函数（`EvolutionMarking` 新增，遵循既有可单测形态）；`SwiftEvolutionInterfaceRenderer` 持配置（平台名，optional，`nil` = 关闭），经 `AnySwiftEvolutionInterfaceBuilder` / pack façade 透传。启用时 `@_spi(Support) annotatedBlocks()` 结构流同样包含属性行；未配置时全链路行为逐字节不变。启用时图例区加一行说明语义分辨率：introduced/obsoleted 指「该轴点首次/末次观测到」，不保证是精确的引入/移除 OS 版本。着色规则 `InterfaceAnnotationStyle.lineKinds(of:)` 不用改：图例第三行以 `//` 开头，算 header；属性行不带 `// [`，算 plain，着色的仍是它下面那行声明。

**范围**：仅 evolution 联合接口。`diff --interface` 的 `-`/`+` 标记已表达增删，不做。

**测试**：`EvolutionMarkingTests` 可表达性矩阵单测（introduced-only / obsoleted-only / 双端 / `●○●` 跳过 / 非版本标签跳过 / 全程在场不发 / modified-only 不发）；`SwiftEvolutionInterfaceBuilderTests` 渲染器级属性落位测试（成员与容器两种锚点、注释保留）。`SwiftSectionKitTests` 的 `ABIRequestTests` 端到端跑请求：三种取值下图例第三行有没有、写的是哪个平台；平台冲突（模拟器按设备算）与平台没有拼写两种推断错误，并确认它们在索引之前抛出——不同平台的输入是测试里现场改写了 `LC_BUILD_VERSION` 的 fixture 副本。`InterfaceAnnotationStyleTests` 钉住属性行与图例第三行的着色。`SwiftSectionCommandTests` 钉 flag 组合校验、flag 到请求的映射与错误译文。默认输出逐字节不变由现有快照测试兜底。

## 决策日志

| 日期 | 决定 | 理由 |
|------|------|------|
| 2026-08-31 | Created as Draft | 用户提出：基于既有 ABI 演进功能实现 @available 标注 |
| 2026-08-31 | 形态定为「真属性 + 保留位图注释」 | 一轮提问定案。前案 [0013（SwiftEvolutionInterfaceBuilder）](0013-swift-evolution-interface-builder.md) 否决过「伪 @available 属性形态」，理由是①似 Swift 而语义不符、②modified 塞不进该形状；本案只发语法合法的真属性、只在事实完整可表达时发、注释继续承载全部真相，两条否决理由均不复现，不构成翻案 |
| 2026-08-31 | 不可表达时不发属性、注释兜底 | 同轮定案；与项目一贯的「算不出就诚实标注、宁缺勿假」渲染原则一致 |
| 2026-08-31 | 范围仅 evolution --interface | 同轮定案；diff 双侧渲染的 -/+ 标记已表达增删，属性放入语义重复 |
| 2026-08-31 | 平台名自动推断 + `--platform` 覆盖，解析失败响亮报错 | 未提问自定：`LC_BUILD_VERSION` 仓内已有读取先例，推断可靠；静默不发属性会让用户以为没有生命周期事实，报错才诚实 |
| 2026-08-31 | 用户批准（Accepted → In Progress） | 方案与全部假设照单通过，随即开始实现 |
| 2026-08-31 | 实现完成，实施偏差：无 | 定向套件 47 tests 绿、`SwiftInterfaceTests` + `SwiftSectionCommandTests` 全量 168 tests 绿（`--skip IntegrationTests`）、CLI 冒烟通过（推断 macOS、`--platform iOS` 覆盖、默认输出零属性）。落地文件：`EvolutionMarking`（属性纯函数 + 图例第三行）、`SwiftEvolutionInterfaceRenderer`（前插属性行）、两个 builder（`availabilityAnnotationPlatform` 配置）、`EvolutionCommand`（`--emit-available` / `--platform` + `LC_BUILD_VERSION` 推断）。过程复盘见 [TaskReports/2026-08-31-evolution-interface-available-annotations.md](../Internal/TaskReports/2026-08-31-evolution-interface-available-annotations.md) |
| 2026-10-01 | rebase 到 `next`（`514bb4bd`） | 分支写成时落后 `next` 271 个提交。`printAnnotatedInterface` 的冲突把 `next` 的 `LargeStackTaskExecution.run` 包裹与本分支的平台参数合在一起；原本写进 `AGENTS.md` 模块条目的三处说明，因为 `next` 已把模块细节移出 `AGENTS.md`，改写进 `Modules/SwiftInterface.md` |
| 2026-10-05 | 命令行逻辑搬进 SwiftSectionKit（实施偏差） | 落地前 `next` 已把每个子命令的逻辑移进 SwiftSectionKit（[0058](0058-swift-section-kit.md)），CLI 只剩包装层，原 `EvolutionCommand` 里的平台推断与报错没法照原样合入。用户在「搬进 SwiftSectionKit 再合」与「这次只合另一个分支」之间选了前者。按 0058 的约定重做：只对 annotated interface 有意义的选项并进已有 enum，`Report.annotatedInterface` 带上 `availabilityAttributes`，与 `ABIDiffRequest.Report.annotatedInterface(format:includesBreakingChangeVerdict:)` 同形；库的错误不提 flag 名，CLI 再译回原分支的报错文案。`.annotatedInterface` 改成带关联值对调用方是源码不兼容的改动，但 SwiftSectionKit 还没发过版本，受影响的只有本仓库里的调用处 |
| 2026-10-05 | 验证 | rebase 后只含 SwiftInterface 部分的那个提交单独编译通过（含测试）。定向套件全部通过，原始退出码 0：`SwiftSectionKitTests` 64 个（新增 4 个）、`SwiftSectionCommandTests` 103 个（新增 4 个）、`EvolutionMarkingTests` / `SwiftEvolutionInterfaceBuilderTests` / `EvolutionAnnotationIndexTests` / `PrintFailureEventTests` 49 个。变异检验：同时注入「模拟器不算 iOS」「DriverKit 有拼写」「`.platform` 被忽略」三处，`ABIRequestTests` 正好对应的 3 个用例变红（原始退出码 1），其余照旧通过，还原后转绿。全量 `swift test --skip IntegrationTests`（JHs-Mac-Studio-Ultra，Swift 6.4，远端依赖）2268 个测试 / 422 个套件全部通过，原始退出码 0，只有早已登记的 `SymbolicManglingIndexTests` known issue。CLI 冒烟（现编的三版 dylib，`Added` 在 2.0 加入、`Removed` 在 3.0 删除）：推断出 macOS，两者分别带 `introduced: 2.0` / `obsoleted: 3.0`，`--platform iOS` 覆盖生效，不加 `--emit-available` 时输出里没有 `@available`；用 `vtool` 改成 iOS 模拟器 / DriverKit 平台的副本分别报冲突（`iOS, macOS`）与推不出，退出码都是 64；两条 flag 组合规则也是 64。插件 skill 提到的每个 flag 都在新 CLI 的 `--help` 里，`claude plugin validate` 两项通过。没有跑渲染 A/B：改动全在开关后面，默认输出由现有快照测试兜底 |
| 2026-10-05 | In Progress → Implemented，编号 0060 | 按共享分支编号（`next` 最大为 0059），合入 `next`；演进账本第 79 节 |
| 2026-10-05 | 收尾判断：不另写专题文档；无新术语 | 规则与边界已写进 `Modules/SwiftInterface.md` 子系统 5 与本提案；`AvailabilityAttributes` 等是标识符，不是自造词。术语表「lifecycle annotation」条目补一句指向本提案 |
