# Draft - SwiftEvolutionInterfaceBuilder：ABI 演进的并集注解接口渲染

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-25
- **最后更新**: 2026-08-25
- **所属愿景**: 无
- **关联提案**: 无（与 `0006` 之前落地的 SwiftDiffing 系列同域：`ABIDiffer` / `ABIEvolutionBuilder` / `SwiftDiffableInterfaceRenderer` 是其直接前作）
- **实现分支 / PR**: `feature/swift-evolution-interface-builder`
- **配套文档**: [ABIEvolutionDesign.md 第五批增量](../Internal/ABIEvolutionDesign.md)（与 evolution 模型的契约耦合点）、[TaskReports/2026-08-25-swift-evolution-interface-builder.md](../Internal/TaskReports/2026-08-25-swift-evolution-interface-builder.md)（过程复盘）

## 摘要

新增 `SwiftEvolutionInterfaceBuilder`：把一个模块跨 N ≥ 2 个版本的 ABI 演进渲染成**一份带生命周期注解的
Swift 接口**——所有版本声明的并集只出现一次，从未变化的声明照常渲染、不带注解，变过的声明在行尾以
`// [●●○] removed in 26.0` 形态标注存在位图与事件短语。它是 `SwiftDiffableInterfaceRenderer`
（两版本注解接口）向 N 版本的推广，取代眼下 `ABIEvolutionReporter` 那种「位图 + 事件行」的纯文本清单成为
演进结果的主要人读视图。公开 API 落在 `SwiftInterface` 模块，CLI 以 `swift-section evolution --interface`
薄封装暴露；N 个输入必须全部是二进制 / dyld 缓存（活模型全保真渲染），快照 JSON 输入在该模式下直接报错。

## 动机

`swift-section evolution` 目前唯一的人读输出是 `ABIEvolutionReporter`
（`Sources/SwiftDiffing/ABIEvolutionReporter.swift`）的 lineage 清单：

```
Types:
  [●●○] SwiftUI.Foo
      - removed in 26.0
      [●○○] func bar() -> ()
          - removed in 18.0
```

问题不在信息缺失，在形态：

- **它不是代码的形状。** 每条 lineage 是「位图 + 名字 + 缩进事件行」，成员脱离了其容器的语法上下文
  （没有 `struct` / `extension` 骨架、没有嵌套、没有未变成员做参照系），读者无法把变化放回接口全貌里理解。
- **只有变化，没有幸存者。** `ABIEvolution` 按设计只物化有事件的 lineage（changes-only 契约，
  `ABIEvolution.swift:46`），所以报告里看不到「这个类型还剩什么」——判断一次删减的严重性需要对照全量接口，
  报告给不了。
- **同一需求在两版本场景已经解决过。** `swift-section diff --interface` 走
  `SwiftDiffableInterfaceRenderer`，输出的是完整接口 + git-diff 标记，可读性是清单式报告不可比的；
  N 版本场景没有对应物，用户只能退回清单，或手动跑 N−1 次 diff 自行拼接。

## 前期调研

以下事实均已在当前 main（`164ff6ed`）代码中核实：

- **现有两版本注解接口的完整链路**：`SwiftDiffableInterfaceBuilder<MachO: FieldLayoutRenderable>`
  （`Sources/SwiftInterface/SwiftDiffableInterfaceBuilder.swift`）对单个二进制做索引并强制逐定义
  `index(in:)`；`SwiftDiffableInterfaceRenderer<OldMachO, NewMachO>`
  （`SwiftDiffableInterfaceRenderer.swift`）以 `ABIKey` 匹配两侧模型，逐成员构造
  `RenderableMember(identityKey:payloadKey:render:)` 单元，产出块分组的 `[[DiffLine]]`，
  由 `DiffFormat` 决定最终字符串。可直接复用的构件：per-member 渲染单元构造
  （`variableMember` / `functionMember` / `fieldMembers` / `deinitMembers` / `associatedTypeMembers`，
  renderer 320–395 行）、header 三态失败处理（`HeaderOutcome` / `resolveHeaders`，480–545 行）、
  extension 容器拆分（`extensionContainers(of:)`，与 `ABIDiffer.extensionContainerKey` 同源）、
  行拆分与缩进机制（`DiffMarking` / `DiffLine`）。
- **两侧匹配与排序规则**（`matchByKey`，renderer 551 行起）：以新侧顺序为脊柱，旧侧独有元素按旧侧顺序
  追加在后；成员级 `diffMembers`（423 行起）同规则，且有「payloadKey 不同但渲染串逐字节相同则折叠为
  unchanged」的降噪规则（437–444 行）。N 路推广有明确的既有先例可循。
- **lineage 模型**（`Sources/SwiftDiffing/ABIEvolution.swift`）：`ContainerLineage` / `MemberLineage`
  携带 `presence: [Bool]` 与 `events: [LineageEvent]`（`versionIndex ≥ 1`，含
  `oldSignature` / `newSignature` / `compatibilityOverride`）；容器 added/removed 期间不产生成员事件
  （容器事件即事件，`MemberLineage.events` 文档注释明确）；只有带事件的 lineage 会被物化。
  `ABIEvolutionBuilder` 的入口是 `evolution(of: [ABISnapshotDocument], labels:)` 与
  `evolution(of: [ABISnapshot], versions:)`（`ABIEvolutionBuilder.swift:16,31`），而
  `SwiftDiffableInterfaceBuilder.snapshot()` 可从活模型直接冻结快照——即「活模型渲染 + lineage 注解」
  两条输入线可以在库内无缝对接。
- **快照的渲染保真度上限**：`ContainerSnapshot` 只有 name / kind / conformedProtocolName /
  whereClauseText + `MemberRecord.signature` 单行字符串（`ABISnapshot.swift:61-71`、
  `MemberRecord.swift:16-21`），无嵌套结构、无完整 printer 输出——这是「interface 模式拒绝快照输入」
  决策的事实依据。`diff --interface` 已有同样的约束与报错文案（`DiffCommand.swift:65-72`）。
- **CLI 现状**：`EvolutionCommand` 已有输入装载（`ABISnapshotInputLoader`）、label 解析、
  `--summary-only` / `--json` / `--fail-on-breaking` 与互斥校验；`DiffCommand` 已有
  `--interface` 的 flag 形态、着色输出（`emit(_:)`）与 MachO 装载（`loadMachO(at:)`）可对照移植。
- **parameter pack 的可用性下限**：类型/值参数包（SE-0393）需要 Swift 5.9 运行时支持，公开 API 中使用
  须以 `@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)` 门控；本包部署下限为
  macOS 10.15 / iOS 13，因此 pack 形态只能作为门控的便利层，不能是唯一入口。
- **模型值不携带 reader 泛型**：`TypeDefinition` / `ProtocolDefinition` / `ExtensionDefinition` 等
  declaration 模型是普通值类型，泛型只出现在 `SwiftDeclarationIndexer<MachO>` /
  `SwiftDeclarationPrinter<MachO>` 上；而 renderer 消费 printer 只经由「异步渲染出 `SemanticString`」
  一种形状——即擦除层薄且无损，这是「非泛型公开类 + 泛型 initializer」设计可行的依据。
- **测试基座**：`Tests/SwiftDiffingTests/ABIEvolutionTests.swift`（lineage 构建单测，含 N==2 与
  `ABIDiffer` 全等的钉子）、`Tests/SwiftInterfaceTests/DiffRendererHeaderFailureTests.swift`
  （renderer 级）、`Tests/SwiftSectionCommandTests`（CLI 校验规则）、
  `Tests/IntegrationTests/SwiftInterface/SwiftDiffableInterfaceBuilderTests.swift`（维护者手检）。

## 提议方案

在 `SwiftInterface` 模块新增一条 N 版本注解接口渲染链路：

1. **公开面为双类型（2026-08-26 修订，见决策日志）**：运行时 N 的擦除类
   `AnySwiftEvolutionInterfaceBuilder`（全平台，CLI/RuntimeViewer 运行时选版本的唯一通路）+
   编译期定形的 pack 泛型 façade `SwiftEvolutionInterfaceBuilder<each MachO>`（macOS 14+ 门控，
   构造即擦除、行为与擦除类逐字节一致）。两者内部都为每个版本建一个
   `SwiftDiffableInterfaceBuilder` 并擦除，`prepare()` 后可产出：
   - `printAnnotatedInterface() -> SemanticString` —— 最终注解接口文本；
   - `annotatedBlocks() -> [[EvolutionLine]]`（`@_spi(Support)`）—— 结构化行流，供 RuntimeViewer
     等下游自定义渲染。
2. **注解事实的唯一来源是 `ABIEvolution`**：builder 在 `prepare()` 末尾把 N 个活模型冻结成快照、经
   `ABIEvolutionBuilder` 得到 lineage 矩阵；渲染期以 `ABIKey` 查 lineage——查得到就生成注解
   （presence 位图 + 事件短语），查不到即「全程存在未变」不注解。渲染器自己不重复推导事件，
   两条视图（清单报告 / 注解接口）永远不会各说各话。
3. **并集脊柱来自活模型的 N 路匹配**：`matchByKey` 推广为 N 侧——以最新版本的声明顺序为脊柱，
   不在最新版本中的声明按「最后一个拥有它的版本」的顺序追加；每个声明/成员由其最后存在版本的模型与
   printer 渲染文本（modified 成员即只渲染最新代际）。
4. **CLI**：`EvolutionCommand` 增加 `--interface` flag；该模式下所有输入必须是二进制 / dyld 缓存，
   快照输入报 `ValidationError`；与 `--json` / `--summary-only` 互斥；`--fail-on-breaking` 照常生效
   （evolution 已在手）；终端输出按事件类别着色（removed 红 / added 绿 / modified 黄），
   `--output` 落盘为纯文本。默认（无 `--interface`）输出保持逐字节不变。

### 输出形态示例

```swift
// Swift ABI evolution across 3 versions: 17.0 → 18.0 → 26.0
// Bitmap positions: [1] 17.0  [2] 18.0  [3] 26.0

public struct SwiftUI.Foo {
    public var title: Swift.String
    public var count: Swift.Int64                       // [●●●] modified in 26.0: Swift.Int32 → Swift.Int64
    public func bar() -> Swift.Int                      // [●●○] removed in 26.0
    public func bar(id: Swift.Int) -> Swift.Int         // [○●●] added in 18.0
}

public class SwiftUI.Legacy {                           // [●○○] removed in 18.0
    public func run() -> ()
}
```

### 非目标

- **不做快照输入的降级渲染**——interface 模式全二进制；「混用输入、快照走单行签名降级」留待将来独立提案。
- **不做 `--changes-only` 过滤**——首版永远渲染完整并集；折叠未变成员的过滤视图记入将来方向。
- **不做逐 transition 串联 diff 视图**——两版本对需求由既有 `diff --interface` 覆盖。
- **不动 `ABIEvolutionReporter`**——默认文本报告与 `--json` 输出保持现状，不改一字。
- **不做 `--format` 变体**（unified / markdown）——unified diff 语义与 N 路注解不对应；markdown fence
  如有需求另行加。
- **不渲染 `pwtslot:` 协议裸槽位记录**——沿用 `diff --interface` 先例（stripped requirement 不在
  declaration 模型里，接口视图不渲染）；其变更仍在清单报告与 JSON 中可见。

## 详细设计

### 公开 API（`Sources/SwiftInterface/SwiftEvolutionInterfaceBuilder.swift` 等）

```swift
/// 运行时 N 的擦除入口（2026-08-26 定名：好名字让给下面的 pack 泛型类）。
/// 每个版本在构造时被擦除为内部渲染单元，同质数组与异构 pack 两种构造收敛到同一类型。
public final class AnySwiftEvolutionInterfaceBuilder: Sendable {
    /// 同质构造：N 个版本同一 reader 类型（CLI 即 N 个 MachOFile）。全平台可用。
    public init<MachO: FieldLayoutRenderable>(
        configuration: SwiftDeclarationIndexConfiguration = .init(),
        eventHandlers: [SwiftIndexEvents.Handler] = [],
        versions: [MachO],
        labels: [String]
    ) throws   // versions.count < 2 或 labels 数不匹配即抛

    /// 异构构造：reader 类型逐版本独立。实测：pack 在**函数**位置不需要
    /// availability 门（编译器只强制「泛型参数表里用 pack 的类型」），全平台可用。
    public init<each Reader: FieldLayoutRenderable>(
        configuration: SwiftDeclarationIndexConfiguration = .init(),
        eventHandlers: [SwiftIndexEvents.Handler] = [],
        versions: repeat each Reader,
        labels: [String]
    ) throws

    /// 逐版本索引 + 强制成员索引（复用 SwiftDiffableInterfaceBuilder.prepare()），
    /// 随后冻结快照并构建 ABIEvolution 注解矩阵。
    public func prepare() async throws

    /// 完整注解接口。头部两行图例（版本轴 + 位图位置映射），随后按
    /// globals → types → protocols → 四类 extension 的既有渲染顺序输出。
    public func printAnnotatedInterface() async -> SemanticString

    /// 结构化行流：外层数组是顶层声明块，内层是该块的行。下游（RuntimeViewer）
    /// 可据此自定义着色/折叠而不解析文本。
    @_spi(Support)
    public func annotatedBlocks() async -> [[EvolutionLine]]

    /// prepare() 期间构建的演进事实，供调用方直接复用（CI 判定、警告展示）。
    public var evolution: ABIEvolution { get }
}

/// 编译期定形的 pack 泛型 façade（2026-08-26 用户裁定拿主名）：reader 类型进类型
/// 签名。pack 在类型泛型参数表 ⇒ 编译器强制 @available(macOS 14+)；arity 编译期
/// 固定 ⇒ 原理上无法承接运行时 N（same-element 约束当前工具链也不支持）。
/// 构造即擦除（erased 暴露给需要互操作的调用方），行为与擦除类逐字节一致。
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
public final class SwiftEvolutionInterfaceBuilder<each MachO: FieldLayoutRenderable>: Sendable {
    public let erased: AnySwiftEvolutionInterfaceBuilder

    public init(
        configuration: SwiftDeclarationIndexConfiguration = .init(),
        eventHandlers: [SwiftIndexEvents.Handler] = [],
        versions: repeat each MachO,
        labels: [String]
    ) throws
    // labels / evolution / prepare() / printAnnotatedInterface() / annotatedBlocks()
    // 全部转发 erased。
}

/// 注解接口的一行。annotation == nil 即「全程存在、从未变化」。
public struct EvolutionLine: Sendable {
    public let content: SemanticString      // 单行，无缩进、无注解文本
    public let indentLevel: Int
    public let annotation: EvolutionAnnotation?
}

/// 一条声明/成员的生命周期注解：presence 位图 + 事件序列（直接复用 SwiftDiffing 的
/// LineageEvent，短语渲染是格式层的事）。
public struct EvolutionAnnotation: Sendable {
    public let presence: [Bool]
    public let events: [LineageEvent]
}
```

内部结构：一个 `EvolutionVersionUnit`（internal struct）持有单版本的模型访问闭包与
`SwiftDeclarationPrinter` 的擦除渲染入口（printer 只以 `async -> SemanticString` 形状被消费，
擦除无损）；两个 public init 都把输入折叠成 `[EvolutionVersionUnit]`。渲染核心
`SwiftEvolutionInterfaceRenderer`（internal）消费该数组，公开面只有 builder 一个类型。

### 注解事实与渲染文本的分工

- **事实（presence / events）**：`prepare()` 末尾对每个版本调 `snapshot()`，经
  `ABIEvolutionBuilder().evolution(of:versions:)` 得到 lineage 矩阵，按 bucket 建
  `[ABIKey: ContainerLineage]` / 容器内 `[ABIKey: MemberLineage]` 查找表。渲染时每个单元用与
  `ABIDiffer` 同源的 key（容器沿用 `ABIKey.makeUnwrappingType` / `extensionContainerKey`，成员沿用
  `MemberRecord` 的 identityKey）查表；命中 → 注解，未命中 → 无注解。这保证注解接口与清单报告 / JSON
  永远同一套裁决（N==2 时与 `ABIDiffer.diff` 全等的既有钉子间接覆盖到本视图）。
- **文本**：每个声明由「最后一个存在版本」的模型 + printer 渲染。成员级即
  `RenderableMember` 推广：N 侧各自构造，按 identityKey 归并后取最新存在侧的 `render()`。
  modified 只渲染最新代际，旧形态进注解短语（`LineageEvent.oldSignature/newSignature`）。

### N 路并集排序

`matchByKey` 的 N 路推广，与两侧规则严格同构：

1. 脊柱 = 最新版本该 bucket / 该 category 的声明顺序；
2. 自新向旧逐版本扫描，把「尚未被收录」的 key 按该版本内顺序追加；
3. key 归并 first-wins（与 `ABIDiffer.keyed` 同规则），归并冲突已由 evolution 的
   `keyCollisionsByVersion` 记账，见「警告」。

容器体内逐 `MemberCategory`（沿用 `MemberCategory.allCases` 调度，保证类别永不静默丢失）做同样的
N 路归并；嵌套类型 / 嵌套协议递归同规则。

### 注解格式

- **图例**：文件头两行注释——版本轴（`17.0 → 18.0 → 26.0`）与位图位置映射
  （`[1] 17.0  [2] 18.0  [3] 26.0`）。
- **附着点**：注解附着在渲染单元的**首行**（成员的签名行 / 容器的 header 行）。同一容器块内的注解做
  列对齐：以块内最长的被注解代码行为准补空格（对齐列上限 72）；超限的行注解换到紧随其后的独立注释行，
  缩进与该行声明一致再进一层（首轮预览里 `bar(id:)` 的形态）。
- **事件短语**：`added in <label>` / `removed in <label>` /
  `modified in <label>: <oldSignature> → <newSignature>`；同一 lineage 多事件以 ` · ` 连接
  （`modified in 18.0: A → B · modified in 26.0: B → C`）。`oldSignature == newSignature` 时省去箭头段
  只写 `modified in <label>`（payload 变了但签名文本不可见，如 accessor 集 / 符号身份变化——对应两侧
  renderer 的「渲染串相同折叠」降噪先例）。
- **容器注解**：容器只有 added/removed 事件（lineage 模型如此）；全程存在但成员有事件的容器 header
  不注解（信号在成员行上）。removed 容器整体渲染自最后存在版本，header 带注解，体内成员不再逐个标注
  该次消失（容器事件即事件，与 `MemberLineage` 的事件抑制规则一致）。
- **警告尾注**：`keyCollisionsByVersion` / `remangleFallbacksByVersion` 非空时，在输出末尾以注释块
  逐条列出（措辞沿用 `ABIEvolutionReporter` 的两个 warnings section），维持「surfaced, not silent」纪律。

### header 失败处理

沿用两侧 renderer 的 `HeaderOutcome` 语义并推广到 N 侧：逐版本尝试 header，全部 failed/absent 才整体
丢弃该声明；任一版本 rendered 即以最新可渲染版本的 header 站位，失败经 `SwiftIndexEvents` 分发
（`definitionPrintFailed`），CLI 由 `ConsoleEventHandler` 落 stderr。

### CLI（`EvolutionCommand`）

```
swift-section evolution --interface v17/SwiftUI v18/SwiftUI v26/SwiftUI --labels 17.0,18.0,26.0
swift-section evolution --interface --dyld-shared-cache -n SwiftUICore cache17 cache18 cache26
```

- 新 flag `--interface`；`validate()` 增补：与 `--json` / `--summary-only` 互斥。
- interface 模式下逐输入 `ABISnapshotInputLoader.isSnapshotDocument` 预检，命中即
  `ValidationError("--interface needs binaries; snapshot JSON inputs only support the lineage report.")`
  ——与 `DiffCommand` 同款约束同款文案风格。
- MachO 装载复用 `MachOFile.load(...)`（对照 `DiffCommand.loadMachO`）；labels 解析沿用现有
  `parseLabels` + 文件名回退。
- 着色（无 `--output` 时）：按行注解的事件类别——removed 红、added 绿、modified 黄，图例/警告行青色；
  `--output` 落纯文本。着色作用在 CLI 层（对照 `DiffCommand.emit(_:)`），库输出不带颜色。
- `--fail-on-breaking`：直接用 builder 暴露的 `evolution.hasBreakingChange`，语义与现状一致。

## 替代方案考量

- **逐 transition 串联 N−1 段 diff 接口**：本质是既有两侧 renderer 跑 N−1 遍再拼接。被否：输出体量
  ~N−1 倍、同一声明在多段重复出现、且用户手拼 `diff --interface` 已能凑合——不构成新价值。
- **只渲染最新版接口 + since 注解，removed 入附录**：输出最短。被否：丢失中间版本的变化细节，
  removed 声明脱离语法上下文，与「并集」的核心诉求（一眼看全历史）冲突。
- **纯快照渲染（Mach-O-free，渲染器落 SwiftDiffing）**：所有输入类型天然支持。被否：快照只有单行
  签名字符串（见前期调研），无嵌套、无完整 printer 保真度；「接口视图」名不副实。
- **允许二进制/快照混用、快照版本走签名降级**：被否（首版）：同一成员在不同版本渲染形态不一致，
  且要终身维护两条渲染路径；用户本地有历年归档 dyld 缓存，二进制可得性不构成阻塞。留作将来提案。
- **注解用纯短语不带位图 / 伪 `@available` 属性形态**：纯短语在「中途消失又回来」（●○●）时冗长；
  伪 `@available` 看似 Swift 却语义不符，易误导，且 modified 事件塞不进该形状。被否，
  定为位图 + 短语。
- **每行都带 `[●●●]` 位图**：机械上更均匀。被否：系统框架几千行里绝大多数全程未变，同一位图刷屏，
  信号淹没——「没注解即未变」的约定信息密度最高。
- **modified 成员逐代际各渲一行**：历史更直观。被否：同名成员多行并列使接口主体不再像合法 Swift，
  违背「一份合法接口的形状」这一核心卖点。
- **同质泛型类 `SwiftEvolutionInterfaceBuilder<MachO>` 作为唯一公开形态**：实现最省。被否（收窄）：
  用户点名要求 pack 异构形态；且模型/printer 的消费形状使擦除无损，非泛型类 + 双 init 的代价只是
  一层内部擦除，换来单一公开类型名。
- **渲染器自行做 N 路事件推导、不经 ABIEvolution**：省一次快照冻结。被否：两套推导必然漂移，
  清单报告与注解接口对同一轴各说各话是最坏结局；快照冻结成本相对 N 次全量索引可忽略。
- **新子命令而非 `--interface` flag / 直接替换默认输出**：被否：前者破坏与 `diff --interface` 的
  对称心智模型；后者是破坏性 CLI 变更（CLI 的命令行接口即用户界面）。

## 影响

### 源码兼容性（source compatibility）

**纯新增**。新公开类型：`SwiftEvolutionInterfaceBuilder`、`EvolutionLine`、`EvolutionAnnotation`
（均在 `SwiftInterface`）；`SwiftDiffing` 的 `LineageEvent` 被新类型公开引用但自身不变。
不触碰任何现有公开 API；`swift-section evolution` 默认输出逐字节不变，新行为全部藏在新 flag 后。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

- 仓库内：`SwiftInterface`（新增渲染链路）、`swift-section`（`EvolutionCommand` 加 flag）、
  `Tests/SwiftInterfaceTests` / `Tests/SwiftSectionCommandTests`（新增覆盖）。`SwiftDiffing` 只读复用，
  不改动。
- 跨仓库：RuntimeViewer 将来做版本对比 UI 可经 `@_spi(Support)` 的 `annotatedBlocks()` 直接消费
  结构化行流（与其消费 `[[DiffLine]]` 的既有路径同构）；本提案不要求 RuntimeViewer 侧任何改动。

### 文档与示例

- `README.md`：`evolution` 命令一节补 `--interface` 用法与示例输出（英文）。
- `AGENTS.md` / `CLAUDE.md` 架构节：SwiftDiffing / SwiftInterface 条目补一句新链路。
- `Documentations/Internal/ABIEvolutionDesign.md`：追加注解接口视图一节，或独立实现说明
  （落地时按「三类文档的分工」判据裁决，结果记入决策日志）。

## API 演进与废弃策略

- 无被替代 API，无废弃标注：`ABIEvolutionReporter` 与注解接口长期并存（清单适合机器后处理与
  `--summary-only`，接口适合人读）。
- 纯新增公开 API，semver **minor** 跃迁（下一个 0.x 功能版本），无 major 需求。

## 落地步骤

1. **N 路归并核心**：`EvolutionVersionUnit` 擦除层 + N 路 `matchByKey` / 成员归并（internal），
   单测钉排序规则（脊柱 = 最新序、旧独有按最后存在版本序追加）。
2. **注解事实接线**：`prepare()` 冻结快照 → `ABIEvolutionBuilder` → key 查找表；
   单测钉「lineage 命中 ↔ 注解存在」「未命中 ↔ 无注解」，及 N==2 时注解裁决与 `ABIDiffer.diff` 一致。
3. **格式层**：位图/短语/图例/列对齐/超限换行/警告尾注；`EvolutionLine` 流 → `SemanticString` 的
   格式化单测（含 `oldSignature == newSignature` 省箭头、多事件 ` · ` 连接）。
4. **公开 builder**：同质 init + pack init（`@available` 门控）、`prepare()` /
   `printAnnotatedInterface()` / `annotatedBlocks()` / `evolution`；renderer 级测试用三个
   on-the-fly 编译的 fixture 二进制（沿用 `LegacyDyldInfoBindTests` 的即时编译手法）断言全输出。
5. **CLI**：`EvolutionCommand` 加 `--interface` 与互斥/快照预检校验、着色输出；
   `SwiftSectionCommandTests` 钉校验规则。
6. **文档同批次**：README / 架构节 / 实现说明或设计文档追加、`Documentations/README.md` 与
   Evolutions 状态表更新；`ProjectEvolutionLog.md` 追加工作弧小节。

每步独立可构建、可测试。**收尾时按模板要求裁决两件事并记入决策日志**：要不要配套专题文章
（预判：注解格式与 N 路归并规则属「API 签名看不出的契约」，倾向写实现说明）；有没有新术语
（预判：「并集接口」「生命周期注解」「注解事实/渲染文本分工」候选，落地时定夺）。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-25 | Created as Draft | 用户诉求：「写一个 SwiftEvolutionInterfaceBuilder，目前的 ABIEvolutionBuilder 输出太难看了」。经三轮澄清提问收空前沿并确认共识后落盘。 |
| 2026-08-25 | 提问结论（第一轮） | 输出形态定为并集接口 + 生命周期注解（否：逐 transition 串联、最新版 + since）；数据来源定为全二进制（否：混用降级、纯快照）；CLI 定为 `evolution --interface`（否：新子命令、替换默认输出）；API 定为 SwiftInterface 公开库 API（否：CLI 内部实现）。 |
| 2026-08-25 | Draft → Accepted → In Progress | 用户批准（「开工」），同日开始实现，分支 `feature/swift-evolution-interface-builder`。 |
| 2026-08-25 | In Progress → Implemented | 六步落地步骤完成：库侧五文件 + CLI flag + 四个测试 suite（30 tests 全绿）+ 三 target 回归 + 文档批次。与提案的差异（`evolution` 改可选、渲染入口加 throws、注解附着点定为末行）见任务报告「与方案的差异」。 |
| 2026-08-25 | 收尾裁决：配套文档 | 不另立实现说明——维护会踩的决策全部是与 evolution 模型的契约（changes-only 依赖、key join、容器事件语义），追加为 [ABIEvolutionDesign.md](../Internal/ABIEvolutionDesign.md) 的「第五批增量」一节，与历次增量同处一文。 |
| 2026-08-26 | API 形态修订：pack 上类型 | 用户指正第二轮第 4 题的本意是 pack 泛型**类**（`SwiftEvolutionInterfaceBuilder<each MachO: FieldLayoutRenderable>`），非「非泛型类 + pack init」。实测钉两个事实：pack 在类型泛型参数表必须 `@available(macOS 14+)`（编译器强制），函数位置则不需要；`repeat each MachO == Element` same-element 约束当前工具链不支持——故运行时 N 的 `[MachO]` init 无法落在 pack 类上，且 pack arity 编译期固定、原理上服务不了 CLI/RuntimeViewer 的运行时选版本场景。 |
| 2026-08-26 | 擦除类定名 AnySwiftEvolutionInterfaceBuilder | 用户拍板：pack 类拿主名（macOS 14+ 薄 façade，构造即擦除、行为逐字节一致，`packGenericFacadeMatchesTheErasedBuilder` 钉住），运行时 N 擦除类循 Swift 擦除惯例（AnyView/AnySequence）命名 `AnySwiftEvolutionInterfaceBuilder`，CLI 改用之。否：擦除类不公开（与第一轮「公开供 RuntimeViewer 复用」相抵触）。 |
| 2026-08-26 | 补集成测试 | `Tests/IntegrationTests/SwiftInterface/SwiftEvolutionInterfaceBuilderTests.swift`：沿用维护者手检 dump 形态（无断言、只编译不运行），AppKit 三缓存轴 + SwiftUICore 双模拟器轴（与 lineage 报告 dump 同输入便于并排目检），另含 pack façade 实机 dump。 |
| 2026-08-25 | 收尾裁决：术语表 | 新术语「union interface（并集接口）」「lifecycle annotation（生命周期注解）」已登记进项目术语表（同批次）。 |
| 2026-08-25 | 提问结论（第二轮） | 注解格式定为位图 + 事件短语 + 头部图例（否：纯短语、伪 @available）；未变声明渲染但不注解（否：每行位图；`--changes-only` 未采纳、记入将来方向）；modified 只渲染最新代际 + 变更注解（否：逐代际多行）；泛型形态定为 pack 异构 init（@available 门控）+ 同质数组 init 双轨（用户自定答案），实现收敛为非泛型公开类 + 内部擦除。 |
