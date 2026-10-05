# 2026-08-31 · evolution 联合接口的 @available 生命周期标注

## 问题

用户诉求：「目前已经有了 ABI 演进的功能了，能从这个开始实现 @available 标注吗」。`swift-section evolution --interface` 的联合接口用位图注释（`// [○●●] added in 18.0`）承载生命周期，但不产出真正的 `@available` 属性——想要接口里直接出现 `@available(iOS, introduced: 18.0)` 这种编译器语法的标注。

## 调研结论

- 事实层零缺口：`ABIEvolution` 的 lineage 已带逐版本 presence 位图 + added/removed 事件，`introduced:`/`obsoleted:` 需要的事实全部现成；格式层（`EvolutionMarking`）与事实层分离，属性渲染是纯格式层扩展。
- 历史决策核对：前案 [0013（SwiftEvolutionInterfaceBuilder）](../../Evolutions/0013-swift-evolution-interface-builder.md) 否决过「伪 `@available` 属性形态」（似 Swift 而语义不符、modified 塞不进）。本案只发语法合法真属性、只在事实完整可表达时发、注释继续承载全部真相——两条否决理由均不复现，不构成翻案。
- 平台名可从二进制 `LC_BUILD_VERSION` 推断，仓内已有先例（TypeIndexing 按它选 SDK，`Sources/Declaration/TypeIndexing/SwiftInterfaceBuilderTypeNameProvider.swift`）。

## 定案（一轮澄清提问，轻量档）

1. 形态：真属性 + 保留位图注释（否：替换注释、只改注释措辞）。
2. 不可表达时（`●○●`、非版本号标签、首版已存在无 introduced 事实、modified-only）：不发属性，注释兜底（否：尽力发部分事实）。
3. 范围：仅 `evolution --interface`（否：同时扩展 `diff --interface`——其 `-`/`+` 标记已表达增删）。
4. 未提问自定：平台自动推断 + `--platform` 覆盖、推断失败响亮报错；长形态 `@available(iOS, introduced: 18.0, obsoleted: 26.0)`；removal 映射 `obsoleted:`。

提案：[0060-evolution-interface-available-annotations](../../Evolutions/0060-evolution-interface-available-annotations.md)（写成时是 draft，落地时取号）。

## 实际执行

- `EvolutionMarking`（格式层纯函数）：`availabilityAttributeText(for:versions:platform:)`（单区间判据 `○ᵃ●ᵇ○ᶜ`、只解析涉事标签、任何一步不满足即整体 `nil`）、`availabilityVersion(fromLabel:)`（1–3 段 ASCII 数字）、`prependingAvailabilityAttribute(_:to:indentLevel:)`（空单元不发、属性行自身不带注解）；`legendLines`/`renderInterface` 加可选平台参数，启用时图例第三行声明轴分辨率语义。
- `SwiftEvolutionInterfaceRenderer`：持 `versionDescriptors` + `availabilityAnnotationPlatform`，成员单元在声明行上方、容器单元在 header 首行上方（缩进 `level - 1`，与 assembler 的 header 层级一致）前插属性行。
- `AnySwiftEvolutionInterfaceBuilder` / pack façade：新增 `availabilityAnnotationPlatform: String? = nil` init 参数（默认关，输出逐字节不变），façade 透传并转发只读属性。
- `EvolutionCommand`：`--emit-available` flag（要求 `--interface`）+ `--platform` 覆盖（要求 `--emit-available`）；`resolveAvailabilityAnnotationPlatform` 逐输入读 `LC_BUILD_VERSION` 映射 `@available` 拼写（模拟器归并到设备平台；driverKit/bridgeOS 等无拼写平台返回 `nil`），缺失或跨输入冲突时 `ValidationError` 指路 `--platform`，绝不静默降级。这一条落地时搬进了 SwiftSectionKit，见文末「落地（2026-10-05）」。

## 验证

- 新增单测：`EvolutionMarkingTests` 可表达性矩阵 9 个（introduced-only / obsoleted-only / 双端 / 全程在场 / `●○●` / 涉事标签解析 / 位图错位防御 / 版本字面量规则 / 前插规则）+ 图例条件行；`SwiftEvolutionInterfaceBuilderTests.availabilityAttributesRenderWhenConfigured` 端到端（属性落位与缩进、注释保留、modified-only 与未变声明裸行、默认配置零属性）；`EvolutionCommandValidationTests` 4 个（两条 flag 依赖规则、并行解析、平台拼写映射）。
- 定向套件 47 tests 绿；`SwiftInterfaceTests` + `SwiftSectionCommandTests` 全量 168 tests / 25 suites 绿（`--skip IntegrationTests`）。
- CLI 冒烟：即时编译双版本 dylib，验证平台推断（`macOS`）、属性 + 位图注释共存、默认输出零 `@available`、`--platform iOS` 覆盖生效。

## 偏差与备忘

- 实施与提案零偏差。
- 环境备忘一：`--filter SwiftEvolutionInterfaceBuilderTests` 会同时命中 `Tests/IntegrationTests/` 里的同名 suite（维护者手工目标，读本机不存在的框架路径而红）——按 AGENTS.md 规矩带上 `--skip IntegrationTests` 即可，非本次改动引入。
- 环境备忘二：本地兄弟仓 `../MachOObjCSection` 停在 detached 旧 commit（缺 `ObjCIndexing` product），`USING_LOCAL_DEPENDENCIES=1` 构建必败；本次未动用户检出，改用远端解析 scratch（`/tmp/claude/SwiftPM/MachOSwiftSection-remote`）构建与测试。

## 落地（2026-10-05）

分支写成后一个多月没合，期间 `next` 把每个子命令的逻辑抽进了 SwiftSectionKit（提案 0058），CLI 只剩包装层。用户说「合并一下」时，`EvolutionCommand.swift` 上的冲突已经没法照原样解，于是问了用户一句：搬进 SwiftSectionKit 再合，还是这次只合另一个分支。用户选前者。

- **rebase**：原提交只保留 SwiftInterface 部分（builder、`EvolutionMarking`、渲染器与它们的测试），`EvolutionCommand.swift` 取 `next` 的版本，CLI 测试的新增也先拿掉；这个提交单独编译通过。
- **搬进 SwiftSectionKit**（第二个提交）：`ABIEvolutionRequest.Report.annotatedInterface` 带上关联值 `availabilityAttributes`（`.none` / `.inferredPlatform` / `.platform(_:)`），照 diff 的 `annotatedInterface(format:includesBreakingChangeVerdict:)` 的样子；平台推断在加载之后、索引之前，失败抛 `AvailabilityPlatformInferenceError`（`.noPlatform(path:)` / `.conflictingPlatforms(_:)`），错误文案不提 flag。`LC_BUILD_VERSION` 改用 MachOKitExtensions 公开的 `buildVersionCommand`，原分支自己写的那个私有扩展不要了。CLI 只剩两个 flag、两条组合校验、`makeRequest()` 的映射，以及 `CommandLineErrorTranslation` 里把两种推断错误译回原分支的报错文案（`ValidationError`，退出码 64）。
- **测试**：推断失败要一个平台不同的输入，测试里现场把 fixture 副本的 `LC_BUILD_VERSION` 平台字段改掉（`FixtureFiles.makeCopy(of:buildPlatform:in:)`，照 `makeSingleSliceFatFile` 手工拼字节的先例）。副本 UUID 不变，各个按镜像的缓存会把它当成原件，所以只用在索引之前就结束的用例里，并断言没有出现「Indexing」进度行。模拟器归设备平台这条规则不单测纯函数，而是让 iOS 模拟器副本与 macOS 的 fixture 冲突，看错误里列出的是 `iOS`。
- **验证**：定向套件、变异检验、全量与 CLI 冒烟的结果见提案决策日志「2026-10-05 验证」一行与账本第 79 节。
