# Draft - evolution 联合接口的 @available 生命周期标注

- **状态**: In Progress
- **创建日期**: 2026-08-31
- **最后更新**: 2026-08-31

## 摘要

`swift-section evolution --interface` 的联合接口目前用位图注释（`// [○●●] added in 18.0`）承载每条声明的生命周期。本案在此之上增加**真实、语法合法的 `@available` 属性行**：当一条声明的生命周期能被一条 `@available` 完整表达时，在声明上方渲染 `@available(iOS, introduced: 18.0, obsoleted: 26.0)`；位图注释原样保留，继续承载属性表达不了的事实（modified 事件、多区间形状等）。flag 门控、默认关，默认输出逐字节不变。

## 方案

**事实层零改动**：属性只从 `EvolutionAnnotation`（presence 位图 + `LineageEvent`）派生，与位图注释同一事实源（`EvolutionAnnotationIndex`），两种呈现永不打架。

**可表达性判据**（不满足任一条即整条声明不发属性，注释兜底）：

- presence 位图必须是单一在场区间 `○ᵃ●ᵇ○ᶜ`（a、c ≥ 0，b ≥ 1）；`●○●` 这类多区间不发。
- `introduced:` 事实仅在 a ≥ 1 时存在（首版就在场 = 早于轴起点，没有 introduced 事实，不发）；`obsoleted:` 事实仅在 c ≥ 1 时存在（removal 映射为 `obsoleted:`）。两个事实都不存在（全程在场，只有 modified）→ 不发。
- 涉及的版本标签必须能解析为 1–3 段数字版本号（`26.0` / `18.5.1`）；文件名回退标签解析不了 → 不发。
- modified 事件永不进属性（`@available` 无此语义），始终留在注释短语里。

**平台名解析**：每个输入二进制读 `LC_BUILD_VERSION` 推断平台（仓内已有先例 `SwiftInterfaceBuilderTypeNameProvider.swift:30`），映射为 Swift availability 平台拼写（macOS / iOS / macCatalyst / …）；新增 `--platform` 选项覆盖推断。各输入平台不一致、或推断不出且未给 `--platform` → `ValidationError`，响亮失败不静默降级。

**渲染位置**：属性是独立的一行 `EvolutionLine`（自身不带 annotation），成员单元插在声明行上方、容器单元插在 header 首行上方（header 的属性行本就先于声明行，锚点规则不变）；位图注释与逐块列对齐逻辑不动。生成属性文本的是格式层纯函数（`EvolutionMarking` 新增，遵循既有可单测形态）；`SwiftEvolutionInterfaceRenderer` 持配置（平台名，optional，`nil` = 关闭），经 `AnySwiftEvolutionInterfaceBuilder` / pack façade 透传。启用时 `@_spi(Support) annotatedBlocks()` 结构流同样包含属性行；未配置时全链路行为逐字节不变。启用时图例区加一行说明语义分辨率：introduced/obsoleted 指「该轴点首次/末次观测到」，不保证是精确的引入/移除 OS 版本。

**范围**：仅 evolution 联合接口（CLI `--emit-available`，仅与 `--interface` 组合合法，validate 拒绝其余组合）。`diff --interface` 的 `-`/`+` 标记已表达增删，不做。

**测试**：`EvolutionMarking` 可表达性矩阵单测（introduced-only / obsoleted-only / 双端 / `●○●` 跳过 / 非版本标签跳过 / 全程在场不发 / modified-only 不发）；渲染器级属性落位测试（成员与容器两种锚点、注释保留）；`SwiftSectionCommandTests` 钉 flag 校验与平台解析/覆盖/冲突；默认输出逐字节不变由现有快照测试兜底。

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
