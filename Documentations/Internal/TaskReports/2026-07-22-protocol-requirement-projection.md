# 2026-07-22 - stripped PWT slot 投影 + remangle 回退审计批次

## 1. 问题 / 任务

用户指令「继续完善 SwiftDiffing」。选题为代码里挂账的两个 TODO(P2)：

1. **stripped protocol requirement 盲区**：协议容器只投影可解析成员；符号被
   strip 的 requirement（OS 框架常态）落进 `strippedSymbolicRequirements` 后
   不参与 diff——协议增删 witness-table slot 不可见，verdict 静默偏弱，且
   `SwiftPrinting` 早已渲染这些 slot，diff 侧能力反而落后于 interface dump。
2. **remangle 回退不可观测**：`ABIKey` 回退键（`mangleAsString` 抛错时的
   printed 形式）与刻意命名空间键无法区分，跨 toolchain 的
   `.mangled`↔`.printed` 身份翻转风险只在注释里存在，线上无从审计。

## 2. 探索与调研

- `StrippedSymbolicRequirement { requirement: ProtocolRequirement, pwtOffset }`
  的 flags（kind/isInstance/isAsync）与 `defaultImplementation.isValid` 都是
  纯值位运算——冻结**不需要** Mach-O；SwiftDiffing 无需 import MachOSwiftSection，
  在 SwiftDeclaration 上加事实门面即可维持模块契约。
- 冻结时机安全：`SwiftDiffableInterfaceBuilder.prepare()` 在 `snapshot()` 之前
  已急切 `index(in:)` 所有协议（`strippedSymbolicRequirements` 是懒索引填充的）。
- 已解析成员的 PWT offset 也留在 definition 上（`FunctionDefinition.offset` 等），
  技术上可照出 requirement 重排——但 resilient 协议运行时按 requirement
  descriptor 匹配 witness，重排非破坏，折入 payload 即假阳性源，**决定不做**
  （与 `Compatibility` 的 resilient 立场一致）。
- 回退键审计的钥匙：本批 formatVersion 反正要 bump，把回退键改成自识别前缀
  `unmangled:`（含冒号，Swift 标识符不可能撞车）即可让扫描零启发式。
- 测试可构造性：`@testable import MachOSwiftSection` 拿到
  `ProtocolRequirement.Layout` 的 internal memberwise init；
  `Node.create(kind: .genericSpecializationParam)` 是 remangler 必然拒绝的节点
  （`mangleGenericSpecializationParam` 直接 `throw .unsupportedNodeKind`）。

## 3. 最终方案

见 [ProtocolRequirementProjection.md](../ProtocolRequirementProjection.md)
（spec 先于实现提交）。核心：

- slot 身份 `pwtslot:<offset>`（printer 既有词汇），payload 折入 flags 指纹
  `|<kindToken>|instance:|async:|default:`；中段插入如实级联 removed+added。
- 回退键 `unmangled:` 前缀 + `ABISnapshot.remangleFallbacks()` 全键位面扫描
  （容器键、组合 `extbucket:` 键内嵌成分、成员 identity/payload 键），经
  `ABIDiffDiagnostics` 新增的两个逐侧字段与
  `ABIEvolution.remangleFallbacksByVersion` 上浮，双 reporter 各渲染一段 Warnings。
- 两项键格局变更共用 formatVersion 3 → 4。

## 4. 实际执行与改动

- SwiftDeclaration：`StrippedSymbolicRequirement` 事实门面（kindToken 显式
  switch / isInstance / isAsync / hasDefaultImplementation）。
- SwiftDiffing：`MemberKind.protocolRequirement`、
  `MemberRecord.makeProtocolRequirement`、differ 协议成员追加、`ABIKey`
  回退前缀 + `isRemangleFallback`、`ABIRemangleFallback` +
  `remangleFallbacks()` 扫描、`ABIDiffDiagnostics`/`ABIEvolution`/builder/
  双 reporter 扩展、formatVersion 4。
- 测试：`ABIProtocolRequirementTests.swift` 两个 Suite 共 11 用例（模型门面、
  键合成、flag 翻转 `.modified`、追加/移除、级联、回退前缀、快照扫描三形态、
  diff/evolution 诊断、双 reporter 输出锁定）。
- 顺带：`differentKeysParallelViaAsyncLet` 计时预算 0.5× → 0.75× serial
  ceiling（上批 0.8s 预算在满载全量跑下 0.845s 再次翻车；隔离 0.405s 完美并行，
  纯 detached task 起跑延迟；0.75× 仍与串行下限 1.6s 保持 0.4s 判别余量）。

## 5. 验证

- SwiftDiffingTests 80 用例全过；全量 `swift test --skip IntegrationTests`
  **1246 个测试全绿**（以原始输出 `Test run with …` 行为准；首轮唯一 issue 即
  上述计时测试，加固后复跑全绿）。
- CLI 冒烟（scratchpad）：
  - 新造 `PWTSmoke` fixture 对（internal 协议 + `strip -x` 模拟 OS strip 状态，
    v2 追加一个 requirement）：`diff` 报 `~ PWTSmoke.Shape` +
    `+ stripped requirement at PWT offset 24 — Kind: method, …`；`evolution`
    生命线 `[○●] … + added in v2`、verdict additive。
  - 旧 baseline（v2 格式 g1.json）被类型化拒绝：「Unsupported ABI snapshot
    format version 2 (this tool supports 4)」。
  - Geometry v4/v5 per-conformance 输出无回归。

## 6. 与原方案的差异

无实质偏差。测试侧比 spec 预估多锁定了 reporter 的完整输出串（沿用
ABIDiagnosticsTests 的锁串风格）。
