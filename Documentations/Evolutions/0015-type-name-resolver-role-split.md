# 0015 - TypeNameResolvable 角色化拆分：printer 查询解析器按能力分协议

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-01
- **最后更新**: 2026-09-01
- **所属愿景**: 无
- **关联提案**: [0009-type-indexing-revival](0009-type-indexing-revival.md)（`swiftName(forCName:category:)` 在该案加入本协议，是协议持续增宽的实例之一）、[0011-opaque-primary-associated-type-attribution](0011-opaque-primary-associated-type-attribution.md)（`opaqueType(forNode:index:)` 的消费语义）
- **实现分支 / PR**: `next` 直落
- **配套文档**: [Internal/Modules/SwiftInterface.md](../Internal/Modules/SwiftInterface.md)（`SwiftInterfaceBuilderExtraDataProvider` 条目同批改写）；不另立实现说明，裁决见决策日志

## 摘要

`SwiftPrinting.TypeNameResolvable` 是 printer 外挂查询解析器的注册协议，三个方法
（`moduleName(forTypeName:)` / `swiftName(forCName:category:)` / `opaqueType(forNode:index:)`）
全部带默认 `nil` 实现。本提案把它拆成一个空标记协议 `TypeNameResolving` + 三个单方法角色协议
（`ModuleNameResolving` / `CImportedNameResolving` / `OpaqueTypeResolving`，**无默认实现**），
provider 只声明自己真正服务的角色；`SwiftDeclarationPrinter` 在注册时按角色分箱
（`as?` 只发生在 `addTypeNameResolver` 里，打印热路径零转型），每个 delegate 查询只走
能回答它的那一箱。`SwiftInterfaceBuilderExtraDataProvider` 同步与 resolver 概念解耦：
退化为纯生命周期钩子（`Sendable` + `setup()`），`addExtraDataProvider` 改为按能力转发。
输出逐字节不变。

## 动机

用户指出该协议同时违反接口隔离原则（ISP）与开闭原则（OCP），核实成立：

- **ISP：没有任何一个真实 provider 实现全部三个方法。** `SwiftInterfaceBuilderOpaqueTypeProvider`
  只实现 `opaqueType`，`TypeIndexing.SwiftInterfaceBuilderTypeNameProvider` 只实现两个名字方法，
  其余全靠默认 `nil` 实现凑数；唯一「全实现」的 `SwiftDeclarationPrinter` 是多路复用器，不算数。
- **OCP：每加一个查询能力都要修改公共契约。** git 历史证实协议从 opaque-type 起步，
  先后增宽 `moduleName`（TypeIndexing 一期）与 `swiftName` + `category` 参数（提案 0009），
  每次都要同时动协议定义、默认扩展、printer 的三处转发，且波及继承它的
  `SwiftInterfaceBuilderExtraDataProvider` 整条线。
- **默认实现是静默失效的温床。** 用 protocol extension 默认返回 `nil` 模拟「可选 delegate 方法」，
  意味着 conformer 签名漂移（如 `swiftName` 加 `category:` 那次）不会编译报错，只是永远不被调用。
- **热路径无效 fan-out。** delegate 方法按「每个打印出来的标识符」调用，每次 `moduleName`
  查询都异步跳一遍全部 resolver，包括只会返回 `nil` 的 opaque provider。

## 前期调研

- 全部消费面已枚举：`NodePrintable.printModule`（`moduleName`，带 `Ref` 后缀剥除回退）、
  `TypeNodePrintable`（`swiftName` / `opaqueType`）、`SwiftDeclarationPrinter` 的三处
  `asyncFirstNonNil` fan-out、`SwiftInterfaceBuilder.addExtraDataProvider` 的注册转发。
  `Sources` 内对旧协议名的引用仅此数处；`Tests` 无直接引用（全部经 `addExtraDataProvider`）。
- 消费端聚合接口（内部协议 `NodePrintableDelegate`，node printer 持有的 weak delegate）
  **不是病灶**：printer 是唯一 conformer 且真要回答全部查询，胖在消费端是职责面本身。
- `SwiftDeclarationPrinter` 为 `@_spi(Support)`，其 `typeNameResolvers` 公开属性无外部读取方，
  可安全改为私有分箱存储。

## 提议方案

1. **角色协议**（`SwiftPrinting/NodePrintables/TypeNameResolving.swift`，`CImportedTypeNameCategory`
   随迁）：空标记协议 `TypeNameResolving: Sendable` 作注册入口；三个单方法角色协议
   `ModuleNameResolving` / `CImportedNameResolving` / `OpaqueTypeResolving` 各自 refine 标记协议，
   **不带默认实现**——签名漂移在 conformer 处编译期报错，而非静默脱钩。
2. **注册分箱**：`SwiftDeclarationPrinter.addTypeNameResolver(_ resolver: any TypeNameResolving)`
   注册时逐角色 `as?` 分箱进私有 `TypeNameResolverRegistry`（三个角色数组）；命中零角色触发
   debug `assert`（注册了却永远不被咨询几乎必是忘了声明角色 conformance）。三个 delegate
   查询各走自己那一箱，打印热路径零转型、零无效跳转。
3. **`SwiftInterfaceBuilderExtraDataProvider` 解耦**：不再继承 resolver 协议，只余
   `Sendable` + 默认为空的 `setup()`（生命周期钩子）；`addExtraDataProvider` 改为
   `as? any TypeNameResolving` 命中才转发给 printer。纯 setup 型 provider（如只预热缓存）
   从此是合法形态；builder 将来长出别的能力面走同一分发路数，provider 协议不再被动。
4. **`TypeNameResolvable` 删名不留 typealias**：留一个指向标记协议的别名会让旧 conformer
   静默编译通过但永远不被调用（恰是要消灭的失效形态）；删名让下游在编译期撞见、有意识迁移。
5. 现有两个 provider 只改 conformance 声明，方法体零改动。

### 非目标

- 不合并 `moduleName` 与 `swiftName` 两角色。二者虽同源（都由 `TypeDatabase` 回答、同属 C
  导入名归属），但打印侧是两个独立调用点，分开更彻底、合并收益只是少一个协议名。
- 不做完全开放的查询注册表（泛型 `Query → Answer` 的 type-erased registry）。对三个方法的
  表面积而言，type erasure + async + `Sendable` 的机械成本远超收益，且「系统支持哪些查询」
  会从协议定义可见退化为翻注册代码才知道。新查询能力在 printer 里的提问点无论如何省不掉，
  角色协议已消掉了其余全部修改面（协议、旧 conformer、分发基础设施）。

## 替代方案考量

- **保持现状（Cocoa optional-delegate 惯用法）**：默认实现确实让「加方法」对既有 conformer
  源码兼容，但代价是把编译期检查换成静默失效，且 ISP 违反持续累积。否。
- **enum 查询 + 单方法**（`resolve(_ query: TypeNameQuery) async -> ...`）：加 case 对
  exhaustive switch 的 conformer 同样是修改，还丢掉每查询的专属签名。否。
- **`SwiftInterfaceBuilderExtraDataProvider` 继承标记协议**（初版草图）：转发可无条件、
  忘声明角色会撞注册 assert；但强迫「所有 extra-data provider 必是 resolver」，与原病灶同构。
  用户点破后改为按能力转发，接受「setup-only 合法化后忘声明角色退回静默」的已知代价
  （写 provider 必跑一次即暴露）。

## 影响

### 源码兼容性（source compatibility）

**破坏性**：`TypeNameResolvable` 删除；`SwiftDeclarationPrinter.typeNameResolvers` 公开属性
（`@_spi(Support)`）移除；`SwiftInterfaceBuilderExtraDataProvider` 不再自带三个查询方法。
下游自定义 provider 需把 conformance 从旧协议改为所服务的角色协议——编译期报错，机械迁移。
`addTypeNameResolver` / `addExtraDataProvider` / `removeAll*` 签名语义不变。

### ABI 兼容性（条件项）

不适用——源码分发，无 ABI 承诺。

### 下游影响

RuntimeViewer 等下游若有自定义 provider，重编译时收到编译错误，按角色声明即可；
仅用库内两个 provider 的调用方零改动。

### 文档与示例

`Internal/Modules/SwiftInterface.md` 的 `SwiftInterfaceBuilderExtraDataProvider` 条目同批改写；
AGENTS.md 架构节未提及旧协议名（provider 挂接 API 不变），判定无需同步。

## API 演进与废弃策略

删名即迁移信号，不设废弃期（源码分发、下游可数）。将来新增查询能力的既定路径：
新角色协议 refine `TypeNameResolving` + registry 加一箱 + printer 加一个转发方法 + 提问点，
旧协议与旧 conformer 零触碰。

## 验收

- `swift build` 绿（原始退出码 0）。
- `SwiftInterfaceTests` 131/131 全绿，含字节级 interface 快照
  （`SymbolTestsCoreInterfaceSnapshotTests`）与 opaque provider / TypeName provider 的 e2e——
  新分发路径下输出逐字节不变的直接证据。
- `SwiftDumpTests` + `SwiftSectionCommandTests` 97/97 全绿。
- 不跑 rendering A/B 全量：改动为小规模机械重构（7 文件、零行为变化），字节级快照钉子已覆盖
  经新分发路径的打印主路（与 0014 同判据）。
- 过程记录：首轮测试 25 处失败经 AGENTS.md 环境漂移程序甄别为 fixture 二进制过期
  （`FinalMembersTest` 在源码而不在 8 月 6 日的共享二进制里，`strings` 计数 0），按既定
  xcodebuild 程序重建后与本改动无关的失败全部消失。

## 落地步骤

一批完成：角色协议新文件 → printer 分箱 → builder 解耦转发 → 两 provider 改 conformance →
测试验证 → 文档批次（本提案 + Evolutions/README + 模块文档 + ProjectEvolutionLog）→ 提交推送。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-01 | Created | 用户指出 `public protocol TypeNameResolvable: Sendable` 违反 SOLID（ISP + OCP）。对话中三轮定稿：角色拆分方向 → 完整改法草图（含删默认实现、注册分箱、删名不留别名）→ 用户点破 `SwiftInterfaceBuilderExtraDataProvider` 应与 resolver 概念完全解耦。 |
| 2026-09-01 | Accepted（对话批准，流程降档） | 用户「可以，改吧，改完直接提交推送就好」——按全局规则降档直做，完整澄清提问以对话讨论代偿；提案与代码同批落地，直取 Implemented。 |
| 2026-09-01 | 关键裁决：删默认实现 | 角色协议单方法、conformer 只认领所服务的角色后，默认实现失去存在理由；删掉换回编译期检查。 |
| 2026-09-01 | 关键裁决：ExtraDataProvider 不继承标记协议 | 初版草图令其继承；用户指出这与原病灶同构（强迫所有 provider 是 resolver）。改为 `addExtraDataProvider` 按能力 `as?` 转发，setup-only provider 合法化；接受「忘声明角色退回静默」的已知代价。 |
| 2026-09-01 | In Progress → Implemented | 实现 + 验证完成（构建绿、131 + 97 tests 全绿、字节级快照不变）；落地取号 0015（全局最大 0014 + 1）。 |
| 2026-09-01 | 收尾裁决：配套文档与术语表 | 不另立实现说明——设计取舍完整落在本提案与角色协议/registry 的代码文档注释里，单独成篇只会复述；模块文档 `SwiftInterface.md` 条目同批改写。无新造术语（标记协议/角色协议为通用概念），术语表不登记。 |
