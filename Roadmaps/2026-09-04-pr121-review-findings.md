# PR #121 review findings（ABI 层自包含，2026-09-04）

并行 review 会话（machoswiftsection-71，xhigh code-review）对 PR #121（`feature/self-contained-abi-layer` → `next`，merge-base `f3782248`）的 12 条发现，全部复核为真、无误报。本表是原始清单与处置状态；「延后」的终审条目收录进 [ReviewAdjudications.md](../Documentations/Internal/ReviewAdjudications.md)（A23、A24）。

用户裁定：A–H 与 I、K、L 全修；J 只统一 `ProtocolConformanceDumper` 一个文件，全量迁移延后；async 提案草稿保留在本 PR 内。

## 合并前必修（5 条）

| # | 位置 | 问题 | 状态 |
|---|---|---|---|
| A | `Package.swift` products | `MachOSwiftSection` 不再再导出 `MachOFoundation`，但 manifest 没有 `MachOFoundation` / `MachOBase` / `MachOSymbols` 的 library product，changelog 让下游 `import MachOFoundation` 却无法在下游 manifest 里声明；explicit modules 下直接失败 | **已修**：新增 `.library(.MachOBase)`、`.library(.MachOFoundation)`；changelog 兼容性一节写明下游要加的 product |
| B | `ProtocolConformanceDumper.swift:105` | 空 witness 的地址注释被去掉（旧代码把空指针解析成字段自身位置当地址打印），方向正确但 changelog「输出逐字节一致」未限定 flag，A/B 三条腿都不带 `--emit-member-addresses` | **已修**：changelog 限定为默认 flag 并说明该变化；补跑一次带 `--emit-member-addresses` 的双侧对比（见任务报告） |
| C | `AGENTS.md:123`、`SelfContainedABILayer.md:14`、`String+.swift` 注释 | 声称 `ManglingPrefixTests` 钉住 `CImportedModuleNames`，实际测试只比前缀两个帮手 | **已修**：`ManglingPrefixTests.cImportedModuleNamesMatchTheDemangler` 断言两常量与 demangler 的 `objcModule` / `cModule` 相等 |
| D | `ProtocolRequirementTests.swift:65` | 两个新测试是 `nil == nil` 空转（选中的第一个 requirement 没有默认实现） | **已修**：新增 picker `protocol_BasicDefaultProtocol`，baseline 加 `firstDefaultedRequirement`（第一个 `defaultImplementation.isValid` 的 requirement），两个测试同时断言 nil 例与非 nil 字面量，并断言结果不等于指针字段自身位置；修复前用突变验证会红 |
| E | `Evolutions/README.md:28` | 提案仍 In Progress、未编号；捆绑 async 草稿 | **部分修**：落地 commit 编号 0018 并置 Implemented（与 0017 做法一致）；async 草稿按用户裁定保留 |

## 同批修（3 条）

| # | 位置 | 问题 | 状态 |
|---|---|---|---|
| F | `Package.swift` | `SwiftLayout` / `SwiftDeclarationRendering` / `SwiftInterface` 新增 `import MachOFoundation`、`MachOSwiftSectionTests` 新增 `import SwiftInspection`，target 依赖未声明 | **已修**：四个 target 补声明 |
| G | `MethodOverrideDescriptorBaselineGenerator.swift:54` | registered 含 `implementationOffset` 但 Entry 不发射，测试只能 `!= nil` | **已修**：Entry 加 `implementationOffset: Int?`，baseline 重生成，测试比字面量；过期头注释改掉 |
| H | `.github/workflows/macOS.yml:109` | CI filter 漏 `MethodDefaultOverrideDescriptorTests` | **已修** |

## 延后 / 单独处理（4 条）

| # | 位置 | 问题 | 状态 |
|---|---|---|---|
| I | `Package.swift:357` | `MachOSwiftSection` 丢了 `.target(.Utilities)`；`FoundationToolbox` / `SwiftStdlibToolbox` / `MachOReading` 在 next 上就未声明 | **Utilities 已补**；其余三个延后，见 A23 |
| J | `ClassDumper` / `TypeDefinition` / `ExtensionDefinition` / `ProtocolConformanceDumper` 约 14 处 | 旧写法未迁移到 `implementationOffset` | **ProtocolConformanceDumper 已统一**；其余延后，见 A24 |
| K | `MethodDescriptorTests.swift:89` | image 腿用 file 的 offset 查、无非空守卫，可能 `nil == nil` | **已修**：image 腿用自己的 offset，两侧都断言非空 |
| L | `String+.swift:55` | `strippingSwiftManglingPrefix` 扫两遍前缀 | **已修**：一次扫描 |
