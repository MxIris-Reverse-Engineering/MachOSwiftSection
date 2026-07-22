# Protocol Requirement（PWT Slot）投影与 Remangle 回退审计

> 状态：已定稿（spec 先于实现提交）。
> 关联：[ABIDiffDesignAndLimitations.md](ABIDiffDesignAndLimitations.md)、[PerConformanceAttribution.md](PerConformanceAttribution.md)、[ABIEvolutionDesign.md](ABIEvolutionDesign.md)

## 1. 动机 —— 两个遗留盲区

本批消化 SwiftDiffing 代码中挂账的两个 TODO(P2)，它们共享同一次快照格式升级：

### 盲区 A：stripped protocol requirement 不参与 diff

协议容器目前只投影**可解析**成员（符号能匹配回 requirement 的函数/属性/下标 +
associated type 名单）。符号被 strip 掉的 requirement——OS 框架的常态——在索引期落进
`ProtocolDefinition.strippedSymbolicRequirements` 后就再也没人看它。后果：

- 协议**增删一个 witness-table slot**（真 ABI 事件：PWT 形状变了）在 diff 里完全不可见；
- 两个版本 requirement 数量不同，报告却说"协议没变"，verdict 静默偏弱；
- `SwiftPrinting` 早已渲染这些 slot（`// PWT offset: N` + Kind/isAsync/isInstance），
  diff 侧反而比 interface dump 盲，能力不对称。

索引期信息其实全在：`StrippedSymbolicRequirement { requirement: ProtocolRequirement,
pwtOffset: Int }`，其中 flags（kind / isInstance / isAsync）与
`defaultImplementation.isValid` 都是纯值位运算，**不需要 Mach-O** 即可冻结。

### 盲区 B：remangle 回退键无法审计

`ABIKey.make(for:)` 在 `mangleAsString` 抛错时回退为 `.printed("<kind>:<print>")`。
已文档化的窄风险：两侧 demangle 树结构不同且恰好只有一侧 remangle 失败时，身份在
`.mangled`↔`.printed` 间翻转，声明表现为 removed+added。问题在于回退键**与刻意的
命名空间键（`field:`、`case:`…）无法区分**——线上到底有没有发生回退、发生了多少，
完全不可观测。诊断通道（key collision 那条线）已经证明"surfaced, not silent"的
价值，这里补上同类的观测面。

## 2. 方案 A —— stripped PWT slot 投影

### 2.1 模型层（SwiftDeclaration）：暴露 Mach-O-free 事实

SwiftDiffing 的模块契约是"只依赖 SwiftDeclaration + Demangling"。为不引入
`import MachOSwiftSection`，在 `StrippedSymbolicRequirement`（SwiftDeclaration）上
新增四个纯值访问器，作为 diff 侧消费的稳定门面：

```swift
extension StrippedSymbolicRequirement {
    public var kindToken: String              // 显式 switch，非 description —— 键格局的一部分
    public var isInstance: Bool               // flags.isInstance
    public var isAsync: Bool                  // flags.isAsync
    public var hasDefaultImplementation: Bool // layout.defaultImplementation.isValid
}
```

`kindToken` 用显式 switch 产出 `method` / `getter` / `baseProtocol` 等 camelCase
token（沿用 `extensionKindToken` / `accessorKindToken` 的"injective by code"惯例）。
这些 token 进入持久化键格局，改名即视为 key-scheme 变更（须 bump formatVersion）。

### 2.2 SwiftDiffing：新成员种类与键格局

- `MemberKind` 新增 `.protocolRequirement`（清掉 `ABIDiff.swift` 的 TODO 注释）。
- 新工厂（纯值参数，Mach-O-free 可单测）：

```swift
MemberRecord.makeProtocolRequirement(
    pwtOffset: Int, kindToken: String,
    isInstance: Bool, isAsync: Bool, hasDefaultImplementation: Bool
)
// identityKey: pwtslot:<pwtOffset>
// payloadKey:  pwtslot:<pwtOffset>|<kindToken>|instance:<0/1>|async:<0/1>|default:<0/1>
// signature:   stripped requirement at PWT offset N — Kind: method, isAsync: …, isInstance: …, hasDefaultImplementation: …
```

- `ABIDiffer.memberRecords(of: ProtocolDefinition)` 在 associated types 之后追加
  stripped slot 记录（冻结时机安全：`SwiftDiffableInterfaceBuilder.prepare()` 在
  `snapshot()` 之前已急切 `index(in:)` 所有协议）。

**身份取 `pwtOffset`**（slot 位置），payload 取 flags 指纹。语义：

- 同一 offset 两侧都在、flags 相同 → 无事件（最常见）；
- 末尾追加 slot → 单条 `.added`；
- 同一 offset 上 kind/instance/async/default 变了 → `.modified`；
- 表中段插入 requirement → 后续所有 stripped slot 的 offset 平移，级联
  removed+added。这是**如实的**：PWT 布局确实整体变了（见 §5 取舍）。

### 2.3 evolution 零改动

lineage 构建在快照层之上，`pwtslot:` 记录自动获得跨版本生命线。

## 3. 方案 B —— remangle 回退自识别 + 审计通道

### 3.1 回退键自识别

`ABIKey.fallbackString` 由 `"<kind>:<print>"` 改为 **`"unmangled:<kind>:<print>"`**，
并暴露 `ABIKey.isRemangleFallback`。前缀含冒号，Swift 标识符不可能撞车；由于本批
formatVersion 反正要 bump，键格局改动免费搭车。

### 3.2 审计扫描与诊断挂载

- 新纯值类型 `ABIRemangleFallback { key, containerName, signature }`（形状对齐
  `ABIKeyCollision`）。
- `ABISnapshot.remangleFallbacks()`：扫描全部键位面——容器键（含 `extbucket:` 组合键
  内嵌的成分 sortKey）、成员 identity/payload 键、全局桶——凡含 `unmangled:` 者记一条。
- `ABIDiffDiagnostics` 增 `oldSideRemangleFallbacks` / `newSideRemangleFallbacks`
  （init 带默认值，既有调用点不动；`isEmpty` 同步扩展）。
- `ABIEvolution` 增 `remangleFallbacksByVersion: [[ABIRemangleFallback]]?`（与
  `keyCollisionsByVersion` 同构、同 nil 语义）。
- 两个 reporter 的 Warnings 区各加一段：回退键身份是"remangle 失败侧打印文本"，
  提示读者跨工具链比较时该声明的 removed+added 可能是身份翻转假象。

## 4. formatVersion 3 → 4

新增 `pwtslot:` 成员命名空间 + `unmangled:` 回退前缀都是键格局变更：旧 baseline 里
协议容器没有 slot 记录，与新快照相比会把全部 stripped slot 误报为 added；回退键
两侧前缀不一致则直接身份错配。按既有契约 bump 到 4 并在 history 注释补一行，
旧 baseline 解码即得到带指引的类型化错误。

## 5. 语义后果与已知取舍

1. **中段插入的级联**：offset 身份使得表中段插入表现为后续 slot 的批量
   removed+added。在 fragile 访问模型下这本来就是逐 slot 的真破坏；在
   library-evolution 模型下（resilient witness 按 requirement descriptor 运行时
   匹配）顺序本身不破坏 ABI，但 slot 集合变化仍是真实信号。级联有界（只波及
   stripped slot），且方向诚实——宁可报多不静默。
2. **符号化状态不对称**（新收录的文档化局限）：stripped 与否取决于两侧二进制的
   符号表状态，不是 ABI 事实。同一协议一侧带符号、一侧被 strip 时，diff 会报
   "解析成员 removed + pwtslot added"的假差异。无廉价对策（无名可匹配）；
   报告读者须知比较双方应当处于相近的 strip 状态。诊断通道不为此报警
   （无法区分"真移除"与"失去符号"）。
3. **verdict 保持均匀启发式**：新增 slot 记 `.additive`，尽管无默认实现的
   requirement 追加对既有 conformer 是破坏性的。`hasDefaultImplementation` 已进
   payload，为后续"default-aware verdict"留好了数据（对**已解析** requirement 需
   经 `defaultImplementationExtensions` 的 offset 相关性补齐，本批不做，见 §7）。
4. **审计是观测不是修复**：`.mangled`↔`.printed` 身份翻转的行为不变（文档化局限
   照旧），本批只是让它从"不可观测"变为"Warnings 里点名"。

## 6. 测试计划（Tests/SwiftDiffingTests/）

- `makeProtocolRequirement` 键合成：identity 只含 offset；payload 含全部 flags；
  同 offset 不同 flags → diffMembers 报 `.modified`；增删 slot → added/removed。
- 快照级：手工构造协议 `ContainerSnapshot` 两侧对比，容器级 `.modified` 聚合正确。
- 回退前缀：构造 remangle 必失败的 Node，断言键带 `unmangled:` 前缀且
  `isRemangleFallback == true`；含回退键的快照 `remangleFallbacks()` 非空；
  经 `ABIDiffer().diff` 后 `diagnostics` 挂载、reporter Warnings 输出该条。
- evolution：`remangleFallbacksByVersion` 对齐 versions 轴；全空时为 nil。
- 文档层：现有 formatVersion 拒绝测试随常量自动跟进 4；无需新增用例。

## 7. 后续工作（本批不做）

- **default-aware compatibility**：把"requirement 追加是否带默认实现"折进 verdict
  （需解决已解析 requirement 的默认实现相关性、以及 `.modified`-即-breaking 的
  粒度问题——给默认实现的*出现*本身不该记 breaking）。
- **structure-driven reporter**（`ABIDiffReporter` 的 TODO(P2)）：经 `SwiftPrinting`
  重打印 before/after 声明的界面级 diff。
- 已解析 requirement 的 **PWT offset 进 payload**：能照出 requirement 重排，但在
  resilient 协议语义下是假阳性源，与 `Compatibility` 的 resilient 立场冲突，
  维持不折入。
