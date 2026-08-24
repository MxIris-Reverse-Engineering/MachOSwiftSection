# 0006 - opaque 返回类型的 primary associated type 归属：anchor 协议裁决 + 协议事实解析链

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-08-24
- **最后更新**: 2026-08-24
- **所属愿景**: 无
- **关联提案**: 无（与 0004 正交）。第四层「离线依赖闭包」明确出参本案范围，另立后续提案（见非目标）
- **实现分支 / PR**: `feature/opaque-primary-associated-type-attribution`（`/tmp/claude/Workspace` worktree 实施、并回 main）
- **配套文档**: [OpaquePrimaryAssociatedTypeAttribution.md](../Internal/OpaquePrimaryAssociatedTypeAttribution.md)（实现说明：最终结构、与提案的差异、已知限制）；[OpaqueReturnTypeResolution.md](../Internal/OpaqueReturnTypeResolution.md)（领域专题：opaque 的二进制编码、协议/关联类型/约束关系、本 bug 成因复盘、字节级调试方法）

## 摘要

`SwiftInterfaceBuilder` 展开 `some` 返回类型的协议组合时，把 opaque 参数上的 same-type 约束（primary associated type 的尖括号参数）**无差别分发给该参数的每一个协议**，产出 `some Swift.Equatable<[A]> & Swift.Sequence<[A]>` 这类非法 Swift（`Equatable` 没有任何 associated type）。本案把归属规则改为 **anchor 协议裁决**：约束的 subject 在二进制里本就带着「声明该 associated type 的协议」（anchor），demangler 也完整保留了它，只是 provider 丢弃了；按「anchor 即协议自身或在其 refine 闭包内」归属，配合仅在等价类塌缩时启用的名字兜底。协议的 refine 链与 associated type 名单经三层解析链获取：本模块 protocol descriptor → 内置 stdlib 协议表 → 进程内跨镜像读取；信息拿不到时宁缺毋滥（不挂参数），绝不退回无差别分发。

## 动机

### 症状

fixture `Tests/Projects/SymbolTests/SymbolTestsCore/OpaqueReturnTypes.swift:17` 的源码：

```swift
public func functionNested<A: Protocols.ProtocolTest & Equatable, B: Protocols.ProtocolTest & Equatable>(_: A, _: B)
    -> (some Sequence<[A]> & Equatable,
        (some Protocols.ProtocolTest<A>)?,
        some Collection<[A]> & Protocols.TestCollection<[A]> & Equatable)?
    where A.Body == Generics.GenericRequirementTest<B>, A.Body.Body.Body == B
```

带 opaque provider 的 SwiftInterface 输出：

```swift
func functionNested<A, B>(_: A, _: B)
    -> (some Swift.Equatable<[A]> & Swift.Sequence<[A]>,
        (some SymbolTestsCore.Protocols.ProtocolTest<A>)?,
        some Swift.Collection<[A]> & Swift.Equatable<[A]> & SymbolTestsCore.Protocols.TestCollection<[A]>)? …
```

逐项判定：

| opaque | 输出 | 判定 |
|---|---|---|
| 1 | `Equatable<[A]> & Sequence<[A]>` | `Sequence<[A]>` 对；`Equatable<[A]>` **错**（Equatable 无 associated type，非法 Swift） |
| 2 | `ProtocolTest<A>` | 对（单协议，无从错起） |
| 3 | `Collection<[A]> & Equatable<[A]> & TestCollection<[A]>` | `Collection` / `TestCollection` **碰巧对**（同为无差别分发的产物）；`Equatable<[A]>` **错** |

### 直接原因

`Sources/SwiftInterface/SwiftInterfaceBuilderOpaqueTypeProvider.swift:42-85`：same-type 约束只按**泛型参数**分组（`associatedTypeByParamType` / `witnessTypeByParamType` 均以参数名为 key），随后对该参数的每一条协议 requirement 追加同一份尖括号参数列表。约束 subject 里的 associated type 引用（含 anchor 协议）在 `:53-54` 被整个丢弃，只留下参数名与右侧类型。

## 前期调研

以下事实均已实测查证（本节的二进制取证对象为 fixture `SymbolTestsCore`，直接解析 `functionNested` 的 opaque type descriptor，符号 `…lFQOMQ`，文件偏移 `0x42fa8`，5 个泛型参数 / 13 条 generic requirements）：

- **anchor 协议在二进制里有。** same-type 约束的 subject 是带协议限定的 dependent member mangling：`7ElementSTQyd__` 即 `τ_1_0.[Swift.Sequence]Element == [A]`（`ST` 为 Sequence 的标准替换）；本模块协议用 symbolic reference（如 `4Body\x02<ref>` → `ProtocolTest` 的 descriptor）。「信息不够、必须追 libswiftCore」的旧印象**部分失实**——anchor 身份本身不缺。
- **demangler 完整保留 anchor。** 限定形式的 `dependentAssociatedTypeRef` 有 `[identifier, protocol]` 两个 child（sibling 仓库 `swift-demangling`，`Demangler.swift:710`）。项目里 `Sources/SwiftDeclarationRendering/Extensions/OpaqueType+.swift:22-24` 甚至专门把这个 protocol child **删掉**再与函数符号签名比对——protocol child 的存在早已被感知，只是打印端从未使用。
- **等价类塌缩是真实的信息丢失。** 源码第三个 opaque 有两处 sugar（`Collection<[A]>` 与 `TestCollection<[A]>`；`TestCollection` 是独立协议、自声明 `Element`，与 Sequence 无 refine 关系），但 descriptor 里 τ_1_2 只有**一条** same-type 约束，anchor 在 Sequence（`7ElementSTQyd_1_`）——两个 associated type pin 到同一具体类型后，编译器最小化签名时把等价类塌缩为 canonical anchor 一条。`TestCollection` 的 pin 无法从 anchor 恢复，只能按名字推断。
- **anchor 会越过组合成员落在 refine 链上层。** `Collection<[A]>` 的约束 anchor 是 **Sequence**（`Collection: Sequence`，canonicalization 把 `Element` 锚到继承链最上层声明者），而 Sequence 不在组合里——归属 `Collection` 需要知道它 refines Sequence，这条事实在 libswiftCore 的 Collection protocol descriptor（requirement signature）里。这才是旧印象的真实出处。
- **「primary」标记在运行时元数据里根本不存在**（SE-0346 不留运行时痕迹，libswiftCore 里也没有）。可获取的只有 requirement signature（refine 关系）与 `AssociatedTypeNames`（全部 associated type 名，声明顺序）。但 opaque 类型无法在源码写 where 子句，其参数上的 same-type 约束**只可能来自 primary sugar**，故按 anchor + 名字推断在 opaque 场景是可靠的。
- **两种 reader 的信息面不同。** MachOImage：requirement content 的间接指针直接解引用到目标镜像的活 descriptor，跨镜像读取几乎免费。MachOFile：该槽是 bind，只能拿到符号名（如 `$sSTMp`）——**身份**可知（足以判定「anchor 即协议自身」的直接命中），**内容**（refine 链、associated type 名单）读不到。
- **反向 pin 同样带 anchor。** `some ProtocolTest<A>` 在 descriptor 里是 `x == τ_1_1.Body`（外层参数在左、dependent member 在右的反向形态，provider 的 `substitutionMap` 分支处理），其 `Body` 引用同样带 symbolic reference anchor。
- **模型层能力已齐备。** `ProtocolDescriptor` 已暴露 `associatedTypes(in:)`（`Sources/MachOSwiftSection/Models/Protocol/ProtocolDescriptor.swift:34`）与 requirement signature（`Protocol.swift:44-47`），无需新增底层解析。
- **测试面现状。** opaque 展开只被 `Tests/SwiftInterfaceTests/SymbolTestsCoreE2ETests.swift` 覆盖（显式 `addExtraDataProvider`，MachOFile reader）；`interfaceSnapshot` 不挂 provider（打裸 `some`），不受影响。`:159` 的注释把错误输出当预期描述（断言本身是弱 `contains`，不锁错误形态）。CLI `swift-section interface` 也挂 provider，输出会随之改善，但无 snapshot pin。
- **跨镜像 fixture 素材现成。** `SymbolTestsCore` 已链接 `SymbolTestsHelper`（`otool -L` 证实），在 Helper 声明协议、Core 使用，即可构造跨镜像归属与 reader 降级差异的回归场景。
- **组合顺序不可恢复。** descriptor 的协议 requirement 顺序是 canonical 排序（输出 `Equatable & Sequence`，源码为 `Sequence & Equatable`），源码顺序无处可查——属实然约束，不是 bug（见非目标）。

## 提议方案

### 归属规则

对参数 τ 的每个协议 requirement P、每条 same-type 约束 c（记 c 的 associated type 名为 N、anchor 协议为 A、右侧类型为 X），按序裁决：

1. **anchor 直接命中**：A 即 P → c 归属 P。只需身份比对，离线 bind 符号亦可判定。
2. **anchor 经 refine 闭包命中**：A ∈ P 的 refine 传递闭包 → c 归属 P。闭包沿解析链逐环求取；任一环节读不到即视为「P 信息不完整」。
3. **名字兜底**（恢复等价类塌缩，如 `TestCollection<[A]>`）：P 无任何 anchor 命中、P **自身声明**了名为 N 的 associated type、τ 上名为 N 的候选约束**恰好一条**、且该候选的 **anchor 协议不在本组合成员之内** → 归属 P。两条以上歧义 → 放弃，不猜。一条约束可以同时归属多个协议（塌缩前本就是多处 sugar）。
   - anchor-在组合外的限定是实施期精化：descriptor 层面「P 的同名 assoc 被塌缩合并」与「P 的同名 assoc 根本没被 pin」**不可区分**（两者都只留 canonical anchor 一条约束，逐字节相同）。当 anchor 协议自身就在组合里（sugar 确定写在它头上），其余声明同名 assoc 的成员写没写 sugar 无从知道，兜底会给「未 pin」的成员捏造参数（如 `some TestCollection<[A]> & UnpinnedElementProtocol & Equatable` 中 UEP 误挂 `<[A]>`）——按宁缺毋滥收紧为不挂。anchor 在组合外（`functionNested` 的 Sequence，只能经某成员 refine 链进来）时兜底照常，`TestCollection<[A]>` 的恢复不受影响。代价：双 sugar 同值且 anchor 落在组合内成员上的真塌缩（`some TestCollection<[A]> & OtherElementProtocol<[A]>`）不再恢复第二个 sugar——信息丢失的诚实呈现，不是错误输出。
4. **宁缺毋滥**：P 的必要信息拿不到 → 不挂参数。绝不退回无差别分发——错挂正是本 bug，漏挂只是信息丢失的诚实呈现。

多 primary 的尖括号顺序按 requirement 顺序；stdlib 协议以内置表的 primary 声明顺序校准。反向 pin（`x == τ_1_1.Body`）分支走完全相同的裁决。

### 协议事实解析链（三层，按序尝试）

获取协议 P 的事实（refine 的协议名单、自声明 associated type 名单、可选的 primary 名单及顺序）：

1. **本模块 descriptor**：P 的 descriptor 在当前二进制（symbolic reference 直接可解）→ 读 requirement signature + `associatedTypeNames`。两种 reader 都可用。
2. **内置 stdlib 协议表**：以 demangle 后的限定名（`Swift.Sequence`）为 key 的静态表，放 SwiftInterface 模块内。stdlib 协议 ABI 稳定、集合有限，此层还额外提供运行时元数据没有的 **primary 名单与顺序**。两种 reader 都可用。
3. **进程内跨镜像读取**（仅 MachOImage）：间接指针解引用到目标镜像的活 descriptor，读法同第 1 层。

三层都失手 → 该协议信息不完整，按规则 4 降级。第四层「离线依赖闭包」（MachOFile 追 libswiftCore / dyld shared cache）不在本案（见非目标）。

两种 reader 的输出深度差异是**接受的**：同一二进制里非 stdlib 外部协议的 refine 闭包/名字兜底，MachOImage 能判、MachOFile 判不了会降级——与项目 reader-specialized 的既有方向一致（`FieldLayoutRenderer` 同理），后续闭包提案落地后差异自然收敛。

### 非目标

- **离线依赖闭包（第四层）**：为 SwiftInterface 建仿 SwiftLayout `ImageUniverse` 的依赖闭包（或提取共享），使 MachOFile 也能追 libswiftCore——工作量与风险另立提案，本案只在设计上保证解析链可扩展。
- **组合顺序还原**：canonical 排序即最终输出，源码顺序不可恢复。
- **dump 路径**：`swift-section dump` 打裸 `some`，不展开组合，不涉及。
- **两 reader 输出强一致**：已裁决接受差异，不为一致性主动丢弃 MachOImage 的免费信息。
- **协议组合之外的 opaque 场景重构**：provider 的整体结构（按参数分组、`substitutionMap` 反向 pin 机制）保持，只改归属裁决。

## 详细设计

### 数据结构（SwiftInterface 模块内，internal）

```swift
/// One same-type constraint mined from the opaque descriptor's requirements,
/// with the anchor information the current code discards.
struct OpaqueSameTypeConstraint {
    enum Origin {
        case directPin      // τ_1_0.[P]Name == X
        case reversedPin    // outerParam == τ_1_1.[P]Name (substitutionMap branch)
    }

    let origin: Origin
    let parameterName: String        // grouping key, matches dumpParameterName output
    let associatedTypeName: String   // e.g. "Element"
    let anchorProtocolNode: Node?    // second child of dependentAssociatedTypeRef; nil when unqualified
    let argumentNode: Node           // the node rendered inside the angle brackets
}

/// What the resolution chain knows about one protocol.
struct ProtocolFacts {
    let qualifiedName: String                    // "Swift.Sequence"
    let declaredAssociatedTypeNames: [String]    // own declarations only, no inheritance
    let refinedProtocolQualifiedNames: [String]  // direct refinements (requirement-signature protocol entries)
    let primaryAssociatedTypeNames: [String]?    // builtin table only; nil from descriptors
}

protocol ProtocolFactsResolving {
    /// Returns nil when this layer cannot see the protocol; the chain moves on.
    func protocolFacts(forQualifiedName qualifiedName: String) -> ProtocolFacts?
}
```

三个实现：`LocalDescriptorProtocolFactsResolver`（第 1 层，索引当前 machO 的 `__swift5_protos`，key 为限定名）、`BuiltinStdlibProtocolFactsTable`（第 2 层，静态字典）、`InProcessCrossImageProtocolFactsResolver`（第 3 层，仅 `MachOImage` 构造时加入链）。链在 provider 初始化时按 reader 组装。

### refine 闭包求取

从 P 出发沿 `refinedProtocolQualifiedNames` 经**同一条解析链**逐环展开（BFS，环保护，已访问集去重）。任一环节解析不到 facts → 闭包标记 `incomplete`；`incomplete` 的闭包仍可用于已展开部分的 anchor 命中（命中是充分的），但**不**据以断言「anchor 不在链上」——规则 2 未命中且闭包不完整时，该协议不进入名字兜底以外的任何推断，最终按规则 4 处理。

### 归属算法落点

`SwiftInterfaceBuilderOpaqueTypeProvider.opaqueType(forNode:index:)` 现有循环改造：

1. 收集阶段（现 `:45-56`）：从 same-type requirement node 提取 `OpaqueSameTypeConstraint`——`dependentMemberType` 的 `dependentAssociatedTypeRef` 保留两个 child（名字 + anchor），反向 pin 经 `substitutionMap.rootOriginal` 还原 `argumentNode` 后同样记录 anchor。
2. 裁决阶段（替换现 `:64-82` 的无差别追加）：对每个协议 requirement 按「归属规则」四步裁决，产出该协议的有序参数列表。
3. anchor 身份比对用限定名字符串（anchor node 与协议 requirement 的 `dumpContent` 同经 `.opaqueTypeBuilderOnly` 解析后比对），避免 node 结构性比较对 symbolic reference / 标准替换两种形态的敏感。

### 内置 stdlib 表初版清单（实施时以 Swift 6.x stdlib 源码逐条核对，此处为待审范围）

- **带 primary**（SE-0358 / SE-0421 采纳集为准）：`Sequence<Element>`、`Collection<Element>: Sequence`、`BidirectionalCollection<Element>: Collection`、`RandomAccessCollection<Element>: BidirectionalCollection`、`MutableCollection<Element>: Collection`、`RangeReplaceableCollection<Element>: Collection`、`RawRepresentable<RawValue>`、`Identifiable<ID>`、`AsyncSequence<Element, Failure>`、`AsyncIteratorProtocol<Element, Failure>`、`Clock<Duration>`。
- **无 associated type（表的价值 = 永不挂 + refine 事实）**：`Equatable`、`Hashable: Equatable`、`Comparable: Equatable`、`Error`、`Sendable`、`CustomStringConvertible`、`CustomDebugStringConvertible`、`Encodable`、`Decodable`。
- **有 associated type、无 primary**：`IteratorProtocol`（`Element`）、`ExpressibleByArrayLiteral`（`ArrayLiteralElement`）等——收录以「出现在真实 opaque 组合的概率」为度，不求穷尽；表缺项的后果只是走后续层或降级，不是错误输出。

### 测试设计

fixture 扩充（`SymbolTestsCore/OpaqueReturnTypes.swift` + `Protocols.swift`；跨镜像素材放 `SymbolTestsHelper`）：

| 场景 | fixture 形态 | 锁什么 |
|---|---|---|
| 名字兜底不误挂 | `some Collection<[A]> & Protocols.TestCollection<String> & Protocols.UnpinnedElementProtocol`（新协议 `UnpinnedElementProtocol { associatedtype Element }`，不 pin） | 前两者各按 anchor 命中（`<[A]>` / `<String>`），第三者候选有两条 → 放弃不挂；修复前三者全挂 |
| 多 primary 顺序 | 新协议 `MultiPrimary<First, Second>` + `some MultiPrimary<Int, String>` | 尖括号参数顺序 |
| 本模块 refine 闭包 | 新协议 `ModuleBase<Item>` / `ModuleRefined<Item>: ModuleBase` + `some ModuleRefined<Int> & Equatable` | anchor 在 ModuleBase、经第 1 层闭包归属 ModuleRefined |
| 跨镜像 + reader 差异 | Helper 声明 `HelperBase<Item>` / `HelperRefined<Item>: HelperBase`，Core 用 `some HelperRefined<Int> & Equatable` | MachOFile：HelperRefined 的 refine 事实读不到 → 不挂（降级路径）；MachOImage：第 3 层命中 → 挂（差异是预期，两侧各自断言） |

既有断言收紧：`SymbolTestsCoreE2ETests` 对 `functionNested` 三个 opaque pin 修复后的精确串（`some Swift.Equatable & Swift.Sequence<[A]>` 等），并更正 `:159` 把错误输出当预期的注释。MachOImage 侧经既有 image 加载基建（dlopen fixture）补 provider 级或 resolver 级断言。重建 fixture 二进制（`xcodebuild … -derivedDataPath Tests/Projects/SymbolTests/DerivedData/SymbolTests`）并重生成受影响 snapshot / baseline（interfaceSnapshot 预期不变——它不挂 provider；变了即另有回归，需查明）。

## 替代方案考量

- **维持无差别分发**：即本 bug，被否。
- **只 anchor 不做名字兜底**：规则最干净，但 `TestCollection<[A]>` 这类被编译器塌缩的 pin 永久丢失，第三个 opaque 比现状（碰巧对）更退步。被否——兜底限定「自身声明 + 候选唯一」后误挂面已足够窄。
- **歧义时全挂**：不丢信息，但会产出源码中不存在的形态（`P<[A], String>`），与「绝不产出看似合法实则错误的输出」的裁决相悖。被否。
- **信息缺失时退回无差别分发**：见规则 4，被否——错挂比漏挂更有害。
- **内置表放 SwiftInspection 或 swift-demangling sibling**：前者把纯渲染知识放进元数据层，后者牵涉跨仓库改动与发版联动；当前唯一消费者在 SwiftInterface，就地安放，将来出现第二消费者再下沉。被否（暂缓形态）。
- **四层一次做完（含离线依赖闭包）**：SwiftInterface 无现成闭包设施，体量与风险不成比例；前三层已覆盖本 fixture 全部场景。被否——闭包另立提案。
- **为 reader 强一致而限制 MachOImage 到最小公共信息集**：主动丢弃免费信息、架空第 3 层设计意图。被否。

## 影响

### 源码兼容性（source compatibility）

**纯新增 / 无破坏。** 公开 API 签名零变化（`SwiftInterfaceBuilderOpaqueTypeProvider` 的 public 接口不动，改动全在内部裁决逻辑与新增 internal 类型）。输出**文本行为**变化：错误的尖括号参数消失、信息不足时参数省略——属 bug 修复方向的行为改善。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译（项目类型声明见 [`Documentations/README.md`](../README.md)）。

### 下游影响

- 本仓库：`SwiftInterface`（主改动）；`swift-section` CLI 的 `interface` 子命令输出随之改善（无 flag 变化）；测试侧 `SwiftInterfaceTests` + fixture 工程 `SymbolTests`。
- 下游仓库：RuntimeViewer 等展示的 interface 中 opaque 组合不再出现非法尖括号参数；零源码迁移，重编即得。

### 文档与示例

- AGENTS.md 的 SwiftInterface 段补一句 opaque 归属规则与解析链的指引。
- 落地时按模板判据决定配套实现说明（预判：解析链分层与「塌缩兜底为什么存在」属「代码看不出来的决策」，值得一篇）。

## API 演进与废弃策略

无公开 API 变化，无废弃需求；随下一次常规版本发布，changelog 记录 interface 输出修复。无 semver major 需要。

## 落地步骤

1. ✅ `OpaqueSameTypeConstraint` 提取重构：收集阶段保留 anchor 与名字（`OpaqueDependentMemberProjection.parse`，嵌套路径拒绝），反向 pin 同步。与计划的偏差：提取与裁决一并落地（拆两步的中间态无独立验证价值），`ProtocolFactsResolving` 协议 + 三实现简化为单 `ProtocolFactsResolver` struct（`resolvedContent` 已把层 1/3 统一为 descriptor 可达性，见实现说明「与提案的差异」）。
2. ✅ `ProtocolFactsResolver` + refine 闭包求取（BFS、环保护、incomplete 三态）+ `BuiltinStandardLibraryProtocolFacts`（primary 清单对照本机 `swift-6.3.2-RELEASE` 源码树核对；Concurrency 协议 demangle 在 `Swift` 模块名下，`$sSciMp` → `Swift.AsyncSequence`）。
3. ✅ 归属裁决替换无差别分发（规则 1–4 + 顺序规则 + 实施期精化的「anchor 在组合外」兜底判据）。`functionNested` 输出修复为 `some Swift.Equatable & Swift.Sequence<[A]>` / `some Swift.Collection<[A]> & Swift.Equatable & …TestCollection<[A]>`。
4. ✅ fixture 扩充四场景（`functionNameFallbackGuard` / `functionModuleRefineClosure` / `functionCrossImageRefineClosure` + 既有多 primary fixture 复用）+ Helper 跨镜像协议对；E2E 断言收紧至精确串（含 `!contains("Swift.Equatable<")` 反断言）并更正把错误输出当预期的注释；新增 MachOImage 侧 `OpaqueAttributionImageE2ETests`（跨镜像挂 `<Swift.Int>` 实测通过——第三层零额外代码即工作，`SymbolOrElement.resolve` 只在 MachOFile 分支查 bind）；interfaceSnapshot / 两个 dump snapshot 重录（diff 均为纯新增 fixture 符号，既有行零改动）、59 个 `__Baseline__` 经 `regen-baselines` 重生成（drift 纯偏移移位，已逐类审查）。
5. ✅ 全量 `swift test --skip IntegrationTests`：1360 tests / 254 suites，唯一 issue 是 `SharedCache.resolve` 的已知墙钟 flaky（`concurrentCallsForDifferentKeysRunInParallel` 单测试隔离跑 0.208s 必过；与本案无关，SwiftInterface 之外零改动面）。
6. ✅ 文档同批：AGENTS.md SwiftInterface 段、`Documentations/README.md` 索引与头注、ProjectEvolutionLog 第 28 节、任务报告 `TaskReports/2026-08-24-opaque-primary-associated-type-attribution.md`；配套两篇（实现说明 + 领域专题，见头部「配套文档」）。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-08-24 | Created as In Review | 用户复查 fixture 指出 `functionNested` 的 `Equatable<[A]>` 错误。会话完成二进制级取证（opaque descriptor `0x42fa8` 逐字节解析：anchor 协议存在、等价类塌缩证实、reader 信息差界定），两轮澄清提问定下 7 项决策（归属规则四步、三层解析链、内置表落点 SwiftInterface、接受 reader 差异、fixture 扩充边界、闭包出参范围、降级宁缺毋滥），用户确认共识清单（「写」）后立项成文。被否方向见「替代方案考量」。 |
| 2026-08-24 | In Review → Accepted | 用户审核通过（「开工」）。实施分支 `feature/opaque-primary-associated-type-attribution`（`/tmp/claude/Workspace` worktree），按落地步骤推进。 |
| 2026-08-24 | 实施期精化：名字兜底加「anchor 在组合外」判据 | 构造兜底测试场景时发现：塌缩恢复与「同名 assoc 未被 pin」在 descriptor 里逐字节同形（canonical anchor 归并后只剩一条），原规则会给未 pin 的同名成员捏造参数。收紧为仅当候选约束的 anchor 不在组合成员内时兜底（纯保守方向，`functionNested` 的 `TestCollection<[A]>` 恢复不受影响）；细节见「提议方案」规则 3。 |
| 2026-08-24 | Accepted → Implemented | 六步全部落地（见落地步骤勾选）：离线四场景 + 进程内跨镜像实测符合预期，全量 1360 tests 除已知 `SharedCache` 墙钟 flaky 外全绿。**配套文档判断**：写两篇——实现说明 `OpaquePrimaryAssociatedTypeAttribution.md`（解析链塌并、兜底不可区分性、与提案的三处差异均属「代码看不出来的决策」）+ 用户点名的领域专题 `OpaqueReturnTypeResolution.md`（descriptor 编码 / anchor 与塌缩机制 / 成因复盘 / 字节级调试方法），已登记头部与索引。**术语表判断**：「anchor 协议」「等价类塌缩」「名字兜底」在提案、实现说明、专题三篇间跨文档复用，登记进项目 `Documentations/Glossary.md`（该表由 0.16.0 线建立，本案 rebase 整合时按「同批次登记」规矩补录）。测试歧义场景（同名不同值双 pin）未做成 fixture：同一类型对同名 associated type 只能给一个 witness，合法 Swift 几乎构造不出，`candidates.count == 1` 判定保留为纵深防御（记入任务报告偏差 3）。 |
| 2026-08-24 | 编号 0005 → 0006（rebase 整合） | push 时发现远端 main 已合并 release/0.16.0 线，编号 0005 被该线的《降级上报统一走事件》占用；本案 rebase 到新 main 之上并整体改号 0006（文件名、代码注释、fixture 注释、全部文档互链）。同批补录：项目 `Glossary.md`（0.16.0 线建立）登记本案三术语，ProjectEvolutionLog 节号让位为 42。 |
