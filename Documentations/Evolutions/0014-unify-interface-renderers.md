# 0014 - 统一 diff / evolution 接口渲染器的结构遍历核心

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-26
- **最后更新**: 2026-08-31
- **所属愿景**: 无
- **关联提案**: [0013-swift-evolution-interface-builder](0013-swift-evolution-interface-builder.md)（被统一的两条渲染路之一即其产物；其决策日志 2026-08-26「属性打印修正」条目记录的 diff 路径同源缺陷，本提案顺带修复）
- **实现分支 / PR**: `feature/swift-evolution-interface-builder`（PR #114 同分支追加）
- **配套文档**: [TaskReports/2026-08-26-unify-interface-renderers.md](../Internal/TaskReports/2026-08-26-unify-interface-renderers.md)（过程复盘）；不另立实现说明，裁决见决策日志

## 摘要

`SwiftDiffableInterfaceRenderer`（两版本 diff 接口，602 行）与 `SwiftEvolutionInterfaceRenderer`
（N 版本注解接口，525 行）是同一个结构遍历写了两遍：顶层组合顺序、容器体组合顺序、
`MemberCategory.allCases` 调度、extension 容器拆分、八个成员构造器、按 `ABIKey` 的归并排序规则
全部平行，其中两段逐字节相同、两路匹配算法互为 N=2 特例。本提案抽出一个共享的**结构遍历核心**
（internal），两个渲染器各自只保留**发射策略**（+/- 标记 vs 生命周期注解）；成员发射统一到
printer level 0 + 格式层逐行缩进，顺带修掉 diff 路径遗留的 accessor 块双重缩进缺陷。
公开 API 零变更：`SwiftDiffableInterfaceRenderer<OldMachO, NewMachO>` 保留为外壳内部委托。

## 动机

两条渲染路的重复不是零星的，是成建制的（行号基于分支 `67d459e7`）：

- **逐字节相同的两段**：`extensionContainers(of:)`（ExtensionName 桶按 conformance / where 拆容器，
  diff 261–278 行 vs evolution 237–254 行）与 extension header 构造
  （`extension X: P where …`，diff 293–307 行 vs evolution 265–278 行）。
- **互为特例的匹配算法**：diff 的两路 `matchByKey`（551 行起）与 evolution 的 N 路
  `matchAcrossVersions`（451 行起）连输出顺序语义都一致——新（最新）序为脊柱、旧独有 key 按旧序
  追加、每侧 first-wins——是一份算法两副本。
- **机械平行的八个成员构造器**：variable / function / subscript / field+enumCase / deinit /
  associatedType / 单定义分类 / extension 合并，差异只有三点：diff 直接吃具体
  `SwiftDeclarationPrinter<MachO>` 而 evolution 走擦除接缝；diff 的 `RenderableMember` 多带
  `payloadKey`；diff 按真实 level 渲染而 evolution 按 level 0。
- **同一份组合顺序**：顶层 globals → types → protocols → 四类 extension，容器体
  嵌套类型 → 嵌套协议 → 字段/枚举 case → 分类成员 → deinit，两边注释都写着「mirroring」对方。
- **70 行纯转发**：`EvolutionVersionUnit` 存在只因 diff 不走擦除接缝——一旦共用，它就是两条路的
  「每版本单元」而非 evolution 专属转发层。

代价不只是行数：**同一条修复要打两遍**。evolution 路刚修过的成员多行渲染缺陷（accessor 块双重
缩进，`67d459e7`）在 diff 路上原样存在——根因正是「diff 成员按真实 level 渲染」这条无谓的差异
（成员 printer 按 `level` 烘焙**绝对**块内缩进，`DiffMarking` 又逐行加层级缩进）。不统一，
每个成员级修复与新特性都要在两处各写一份并各配一套测试。

## 前期调研

以下事实均已在分支 `67d459e7` 代码中核实：

- **匹配顺序语义等价**：`matchByKey(old, new)` 的输出序（新侧序 + 旧独有按旧序追加）与
  `matchAcrossVersions([old, new])` 的输出序（最新脊柱 + 自新向旧追加未见 key）逐 case 一致，
  含成员级 `diffMembers` 的「removed 追加在 category 末尾」规则。N 路核心可无损承接两路。
- **成员 printer 的缩进契约**：`VariableNodePrinter` / `SubscriptNodePrinter` 按 `level` 烘焙绝对
  块内缩进（accessor `(level+1)*4`、收尾 `}` `level*4`），首行不缩进；function / field 忽略该参数。
  evolution 路已统一 level 0 渲染 + 格式层逐行缩进（`67d459e7` 修复），输出正确；diff 路仍按真实
  level 渲染 + `DiffMarking.inlineLineComponents` 逐行缩进 ⇒ 多行成员双重缩进（已知遗留缺陷）。
- **header 语义真不同，不能统一**：diff 需要两侧独立结果（`HeaderOutcome` / `resolveHeaders`：
  变更时 `-`/`+` 成对、单侧 failed 由对侧站位、双侧 failed/absent 才整体丢弃）；evolution 只要
  最新可渲染版本（`latestRenderableHeader`）。二者留在各自策略里。
- **容器装配与格式层真不同，不合**：`DiffContainerAssembler`（marker 三态 + header 变更成对）vs
  `EvolutionContainerAssembler`（注解锚点 firstLine/lastLine）；`DiffMarking` / `EvolutionMarking`
  已共享 `splitIntoLines`，其余语义各异。
- **公开面**：`SwiftDiffableInterfaceRenderer` 是 public class（双泛型参数 + `printAnnotatedInterface(format:)`），
  `annotatedDiffBlocks()` 为 `@_spi(Support)`；`DiffLine` / `DiffFormat` / `EvolutionLine` public。
  擦除接缝 `EvolutionVersionRendering` / `EvolutionVersionUnit` 均 internal，改名零外部代价。
- **测试面**：diff 路字节钉子在 `DiffRendererHeaderFailureTests`（e2e 走 `printAnnotatedInterface`）
  与 `DiffFormatTests` / `DiffMarkingTests` / `DiffContainerAssemblerTests`（合成行）；evolution 路在
  `SwiftEvolutionInterfaceBuilderTests`（三 fixture 二进制 e2e）与 `EvolutionMarkingTests`。
  `diff --interface` 无 CLI 快照测试；IntegrationTests 维护者手检、无断言。

## 提议方案

1. **共享结构遍历核心**（internal，新文件 `InterfaceUnionWalker.swift`）：N 路匹配
  （`matchAcrossVersions` 迁入）、extension 容器拆分与 header 构造、八个成员构造器（统一为携带
  `identityKey` + `payloadKey` 的 `UnionRenderableMember`，evolution 侧忽略 payloadKey）、
  容器体与顶层组合顺序、`MemberCategory.allCases` 调度。核心以策略协议
  `InterfaceUnionEmitting`（`associatedtype Line`）参数化：策略决定 header 解析
  （返回 nil 即整体丢弃）、单个成员归并结果如何发射为 `[[Line]]`、容器如何装配。
2. **两个渲染器退化为策略**：diff 策略持有 `HeaderOutcome` / `resolveHeaders`、payloadKey 比对与
  「渲染串相同折叠 unchanged」降噪、`DiffContainerAssembler` 装配；evolution 策略持有
  `latestRenderableHeader`、`EvolutionAnnotationIndex` 查表与 `EvolutionContainerAssembler` 装配。
3. **成员发射统一 level 0**：两路都以 printer level 0 渲染成员、行级 `indentLevel` 交给格式层。
  diff 路的 accessor 块双重缩进随之消失——多行成员的输出字节**变正确**，其余输出逐字节不变。
4. **擦除接缝升格共用并改中性名**：`EvolutionVersionRendering` → `InterfaceVersionRendering`、
  `EvolutionVersionUnit` → `InterfaceVersionUnit`（git mv），后者增加一个接收已建
  `SwiftDiffableInterfaceBuilder` 的构造口（保持 printer 共享 indexer dispatcher 的既有契约），
  供 diff 外壳把两侧包成单元。
5. **公开 API 零变更**：`SwiftDiffableInterfaceRenderer<OldMachO, NewMachO>` 保留公开签名，
  类体变薄——构造时两侧擦除为 `InterfaceVersionUnit` 交给核心 + diff 策略；双泛型参数只剩
  类型检查意义。`AnySwiftEvolutionInterfaceBuilder` 两个渲染入口的 renderer 构造收敛为一个
  私有工厂（顺手小去重）。

### 非目标

- **不合并格式层**：`DiffMarking` / `EvolutionMarking` / 两个 ContainerAssembler 语义真不同，保持分立。
- **不接 opaque 展开**：两路裸 `some` 打印（printer 未接 `addExtraDataProvider` 线）是功能缺口
  不是重复代码，另立提案。
- **不动 SwiftDiffing / SwiftPrinting / 主接口路径**：`ABIDiffer`、`SwiftDeclarationPrinter`、
  `SwiftInterfaceBuilder.printRoot()` 零改动。
- **不做 API 废弃**：无新公开类型，无 deprecation。

## 替代方案考量

- **小步去重（只抽逐字节相同段 + 匹配算法 + 成员构造器，保留两套遍历骨架）**：约 −250~300 行、
  风险最低。被否：遍历骨架（组合顺序、递归结构、category 调度）本身就是重复的主体，留两份意味着
  每个结构级修复仍要打两遍，双重缩进缺陷也修不掉。
- **统一核心但 diff 保持真实 level 渲染（字节零变）**：被否：等于给遍历器加一个只为兼容已知缺陷
  存在的参数，缺陷本身永久化；diff 多行成员的字节变化是修正而非漂移，基线更新成本一次性。
- **反向统一——把 evolution 视为 diff 的推广、废弃两路渲染器改用 N 路公开类**：被否：破坏公开 API
  （`SwiftDiffableInterfaceRenderer` 有下游），收益只是少一对泛型参数。
- **格式层也统一（Line 类型合一、marker 与 annotation 做成枚举 payload）**：被否：`DiffLine` /
  `EvolutionLine` 都是公开类型，合一即破坏性变更；且 +/- 标记逐行有效而注解按锚点附着，
  强行抽象比两份小文件更难读。

## 影响

### 源码兼容性（source compatibility）

**公开签名零变更**。行为变化仅一处且为修正：`diff --interface` 多行成员（带 accessor 块的
variable / subscript）的块内缩进从双重变为正确；单行成员、header、结构、标记逐字节不变。
`@_spi(Support)` 的 `annotatedDiffBlocks()` 行流中，多行成员的内部行 `content` 改为携带相对缩进
（`indentLevel` 全单元统一）——SPI 面，可接受，与 evolution 路 `annotatedBlocks()` 现状对齐。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发。

### 下游影响

- 仓库内：`SwiftInterface` 单模块重构；`Tests/SwiftInterfaceTests` 更新钉住双重缩进的既有字节 +
  新增修前必红回归测试。
- 跨仓库：RuntimeViewer 若经 `@_spi` 行流自渲染 diff，多行成员显示缩进随之变正确，无代码改动。

### 文档与示例

- `AGENTS.md` 架构节：SwiftInterface 条目改写为「共享遍历核心 + 双策略」形态，diff 缩进缺陷条目移除。
- 配套文章归属落地时裁决（见头部「配套文档」）；`ProjectEvolutionLog.md` 追加小节；
  术语表按需登记（候选：「发射策略」）。

## API 演进与废弃策略

无新公开 API、无废弃。semver **patch** 级（内部重构 + 缺陷修正）；随 PR #114 所在的 minor 一并发布。

## 验收

- `Tests/SwiftInterfaceTests` 全绿（原始退出码为准）；evolution 路输出逐字节不变（既有 e2e 钉住）；
  diff 路除缩进修正外逐字节不变（`DiffRendererHeaderFailureTests` 等既有钉子即 N=2 等价性的证明）。
- 新增回归测试：diff e2e fixture 含计算属性，钉「声明行 / `get` / `}` 的相对缩进 + 全文无双重缩进
  残留」，实现前必须红。
- **不跑 rendering A/B 全量验证**：`SwiftPrinting` 与主 dump / interface 路径零 diff
  （`git diff --stat` 佐证），A/B 覆盖的正是那条不动的路——判断依据即此。

## 落地步骤

1. **核心迁移，evolution 先行**：新建 `InterfaceUnionWalker` + `InterfaceUnionEmitting` +
  `UnionRenderableMember`，接缝改名（git mv）+ 增建 builder 构造口；evolution 渲染器改为策略，
  其 e2e 字节钉子必须原样通过（核心正确性的第一道验收）。
2. **diff 策略 + 缩进修正**：先写修前必红的回归测试；`SwiftDiffableInterfaceRenderer` 类体改委托，
  `HeaderOutcome` / 降噪折叠迁入策略，成员发射 level 0；更新钉住旧缩进的既有字节。
3. **文档同批次**：AGENTS.md / 配套文章裁决 / ProjectEvolutionLog / Evolutions 状态表 / 术语表。

每步独立可构建、可测试。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-26 | Created as Draft | 用户诉求：「看一下怎么优化一下 3 个 Builder 的代码，现在太多重复代码了」。调研结论：Builder 层重复很小（pack façade 转发是既定设计的固有代价），大头在两个渲染器（~1100 行六成平行）+ 70 行擦除转发层。经两轮澄清提问收空前沿并确认共识后落盘。 |
| 2026-08-26 | 提问结论（范围轮） | 定为统一遍历核心 + 顺带修 diff 双重缩进（否：小步去重——骨架重复仍在；否：diff 字节零变——缺陷永久化；否：暂不重构）。格式层不合并。 |
| 2026-08-26 | 提问结论（第二轮） | 公开类保留为外壳内部委托（否：废弃换新——破坏 API 换微小收益）；擦除接缝改中性名（否：保留 Evolution* 名——归属误导）；opaque 展开不入本批另立提案（否：并入——范围与风险失控）；验收不跑 A/B 全量（否：跑——覆盖的主路径零改动），依据写入「验收」节。 |
| 2026-08-26 | Draft → Accepted → In Progress | 用户批准（「开始」），同日实现。 |
| 2026-08-26 | 匹配 first-wins 全面对齐 | 实现中确认旧 diff 的发射循环对**新侧**同 key 重复项会重复发射（其查表字典与注释都声明 first-wins，与 `ABIDiffer.keyed` 一致——发射循环是漏网）；统一后连发射也 first-wins。受影响的唯一钉子 `unrenderableHeaderIsReportedAsAnEvent` 原以 append 同名损坏定义触发 header 失败、恰好依赖该漏网，改用其姊妹测试已验证的 replace 注入，测试意图不变。 |
| 2026-08-26 | 测试基建发现：fixture 必须带 class | 纯 struct 的即时编译 fixture dylib 无 `__DATA` 段，pinned MachOKit 解析该布局的 chained-fixup 页越界崩溃（`prepare()` 内 SIGSEGV，崩溃地址恰为 mmap 按页取整末尾）。规避：fixture 加跨版本不变的 `Anchor` class；规矩记入 AGENTS.md Test Environment。MachOKit 根因属另一仓库，另行处理。 |
| 2026-08-26 | 顺手修正：协议 header 失败事件的 kind | diff 路原硬编码 `.type`（协议 header 失败也报 `.type`）；策略化后如实传 `.protocol`，与 evolution 路一致。无测试钉旧值。 |
| 2026-08-26 | In Progress → Implemented | 落地三步完成：核心迁移（evolution e2e 字节钉子原样通过）→ diff 策略 + 缩进修正（修前必红的 `DiffMemberIndentationTests` 转绿）→ 文档批次。SwiftInterface + SwiftDiffing + SwiftSectionCommand 三 target 209 tests / 34 suites 全绿（原始退出码 0）。 |
| 2026-08-26 | 收尾裁决：配套文档与术语表 | 不另立实现说明——发射策略接缝的取舍已完整落在遍历器/策略的代码文档注释与 AGENTS.md `InterfaceUnionWalker` 条目里，单独成篇只会复述（反向判据命中）；过程复盘在任务报告。术语表登记「emission strategy（发射策略）」。 |
| 2026-08-31 | 补取编号 draft → 0014 | 与 0013 同因：本案 2026-08-26 已置 `Implemented`，落地 commit 漏了 README 规定的取号一步。按落地先后排在 0013（其被统一的渲染路之一即 0013 的产物）之后。同批完成互链改名：AGENTS.md、Glossary、ProjectEvolutionLog 第 49 节、ReviewAdjudications A20、任务报告 |
