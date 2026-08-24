# Opaque 返回类型的 primary associated type 归属实现说明

> 对应提案：[0006 - opaque 返回类型的 primary associated type 归属](../Evolutions/0006-opaque-primary-associated-type-attribution.md)。
> 提案是决策记录；本文写最终实现、为什么这么实现、以及与提案的差异。
> 领域原理（opaque 的二进制编码、anchor / 塌缩机制、调试方法）见专题
> [OpaqueReturnTypeResolution.md](OpaqueReturnTypeResolution.md)，本文不重复。

## 问题一句话

`SwiftInterfaceBuilderOpaqueTypeProvider` 曾把 opaque 参数上的 same-type 约束（primary associated type 的尖括号参数）无差别分发给该参数组合里的每一个协议，产出 `some Swift.Equatable<[A]>` 这类非法 Swift。修复后按 anchor 协议逐条裁决归属。

## 实现结构（`Sources/SwiftInterface/`）

| 文件 | 职责 |
|---|---|
| `OpaqueSameTypeConstraint.swift` | 约束记录（关联类型名、anchor 协议名、参数来源）+ `OpaqueDependentMemberProjection.parse`：从 `dependentMemberType` 节点提取单级 dependent member（嵌套路径 `τ.Name.Sub` 不可能来自 primary sugar，直接拒绝） |
| `ProtocolFactsResolver.swift` | `ProtocolFacts`（自声明关联类型名单、直接 refine 名单、可选 primary 名单）+ 解析（descriptor 优先、内置表增补/兜底）+ refine 闭包查找（BFS、环保护、incomplete 三态） |
| `BuiltinStandardLibraryProtocolFacts.swift` | stdlib 协议冻结表，key 为 demangle 后限定名；对照 `swift-6.3.2-RELEASE` stdlib 源码核对 |
| `SwiftInterfaceBuilderOpaqueTypeProvider.swift` | 收集（保留 anchor）+ 四步归属裁决 + 渲染 |

## 关键决策（代码看不出来的）

### anchor 信息一直都在，丢它的是打印端

same-type 约束 subject 的 mangling 带着声明协议：`7ElementSTQyd__` = `τ_1_0.[Swift.Sequence]Element`（`ST` 标准替换；本模块协议用 symbolic reference）。demangler 把它保留在 `dependentAssociatedTypeRef` 的第二个 child 里（`[identifier, protocol]`）。修复前的 provider 在收集时只取参数名和右侧类型，anchor 整个扔掉——这就是「无差别分发」的直接来源。`SwiftDeclarationRendering` 的 `OpaqueType+.swift` 过滤器甚至专门**删除**这个 child 再与函数符号签名比对（那里需要的是「等价性」而非「归属」），可见它的存在早被感知。

### 三层解析链在实现里塌成了两问

提案的三层（本模块 descriptor → 内置表 → 进程内跨镜像）在实现中由既有机制自然合并：`GenericRequirementDescriptor.resolvedContent(in:)` 对可达的 descriptor（同镜像 symbolic ref，或进程内任意镜像的间接指针）统一给出 `.element(.swift(ProtocolDescriptor))`，对离线 bind 给出 `.symbol`（只有身份）。所以实现只问两件事：**有 descriptor 吗**（有 → 读 requirement signature + `associatedTypeNames`，并用内置表的 primary 名单增补）；**没有** → 内置表按限定名兜底。跨镜像在 `MachOImage` 下不需要任何额外代码——`SymbolOrElement.resolve` 只在 `MachOFile` 分支查 bind，进程内永远解析到元素，`Protocol(descriptor:in:)` 的 offset 读取跨镜像照常工作（offset 相对 machO 基址的算术在进程内自洽）。

### 「看起来更简单的那条路」为什么走不通

- **只按名字匹配**（不看 anchor）：`Equatable` 没有关联类型时确实能排除，但两个协议声明同名关联类型即歧义，且无法利用 refine 链。anchor 是二进制里现成的强信号，放着不用没有道理。
- **要求 primary 标记**：运行时元数据根本没有（SE-0346 不留痕迹，连 libswiftCore 也没有）。opaque 的 same-type 约束只可能来自 primary sugar，这个前提使 anchor + 名字推断在此场景可靠；内置表补的是 stdlib 协议的 primary **顺序**（多 primary 时 requirement 顺序不保证等于声明顺序）。
- **名字兜底不设 anchor-在组合外的限定**：会捏造 sugar。descriptor 层面「P 的同名关联类型被塌缩合并」与「P 的同名关联类型根本没被 pin」**逐字节相同**（等价类最小化只留 canonical anchor 一条约束）。anchor 协议自身在组合里时（sugar 确定写在它头上），其他同名成员写没写 sugar 无从知道——`some TestCollection<[A]> & UnpinnedElementProtocol & Equatable` 里给 UEP 挂 `<[A]>` 就是编造。anchor 在组合外（`functionNested` 的 Sequence，只能经 Collection 的 refine 链进来）时兜底照常，`TestCollection<[A]>` 的恢复不受影响。这条判据是实施期发现补进提案的（见提案决策日志）。

### 已知限制（下次维护会撞上的）

- **组合顺序不可还原**：descriptor 的协议 requirement 是 canonical 排序（`Equatable & Sequence`，源码是 `Sequence & Equatable`）。不是 bug，别试图修。
- **离线的非 stdlib 外部协议**：anchor 直接命中照常（身份比对走 bind 符号名）；但 refine 闭包、名字兜底需要协议内容，`MachOFile` 拿不到 → 参数诚实降级为不挂。`functionCrossImageRefineClosure` fixture 两侧各锁一种行为（离线不挂 / 进程内挂 `<Swift.Int>`）。两种 reader 输出深度不一致是**接受的**（提案裁决），进程内严格增量。后续「离线依赖闭包」提案落地后收敛。
- **双 sugar 同值且 anchor 在组合内的真塌缩**不再恢复第二个 sugar（兜底收紧的代价）——信息丢失的诚实呈现。
- **内置表缺项无害但有感**：miss 只意味着走 descriptor 或降级不挂，绝不误挂。新 stdlib 协议获得 primary associated types 时补表即可。

## 与提案的差异

| 提案 | 实现 | 原因 |
|---|---|---|
| `ProtocolFactsResolving` 协议 + 三个实现 | 单个 `ProtocolFactsResolver` struct + 内置表 | `resolvedContent(in:)` 已把层 1/3 统一为「descriptor 可达性」，协议抽象没有第二个实现者，徒增间接 |
| 规则 3 无 anchor 位置限定 | 加「候选 anchor 不在组合成员内」判据 | 实施期发现塌缩与未 pin 同形（见上文），纯保守收紧，已回写提案 |
| `OpaqueSameTypeConstraint` 带 `parameterName` 字段 | 参数名只作分组 key，不进记录 | 分组后字段无消费者 |

## 验证

- E2E（`Tests/SwiftInterfaceTests/SymbolTestsCoreE2ETests.swift`，MachOFile）：`functionNested` 三个 opaque 的精确串、名字兜底防捏造、模块内 refine 闭包、跨镜像离线降级、多 primary 顺序。
- MachOImage 侧（`OpaqueAttributionImageE2ETests.swift`）：跨镜像 refine 闭包挂 `<Swift.Int>`；无需跨镜像事实的场景与离线输出逐字一致。
- fixture 场景与 witness 见 `Tests/Projects/SymbolTests/SymbolTestsCore/OpaqueReturnTypes.swift`（`functionNameFallbackGuard` / `functionModuleRefineClosure` / `functionCrossImageRefineClosure`）与 `SymbolTestsHelper`（`HelperBaseProtocol` / `HelperRefinedProtocol`）。
