# Default-Implementation-Aware Compatibility Verdict

> 状态：已定稿（spec 先于实现提交）。
> 关联：[ProtocolRequirementProjection.md](ProtocolRequirementProjection.md)（§7 预留项）、
> [ABIDiffDesignAndLimitations.md](ABIDiffDesignAndLimitations.md)

## 1. 动机

`Compatibility` 的均匀启发式——「新增即 additive」——在协议 requirement 上与
Swift library evolution 的官方规则相悖：**给协议追加一个没有默认实现的
requirement 是破坏性变更**（既有 conformance 缺 witness，resilient 实例化后
调用即 trap；带默认实现的追加才是 additive）。当前 diff 对协议新增
requirement 一律报 `backward-compatible: true`，`--fail-on-breaking` CI 门
在这类真破坏上静默放行——这是核心结论最后一处「自信地出错」。

上一批已把 stripped slot 的 `hasDefaultImplementation` 备进 payload；本批把
「是否有默认实现」升为结构化事实并折进 verdict，对**已解析** requirement 同样
生效。

## 2. 数据通路

### 2.1 索引期（SwiftDeclaration）

`ProtocolDefinition` 新增 `defaultedRequirementPWTOffsets: Set<Int>`
（package(set)）：`index(in:)` 的 requirement 循环里，对**每个** requirement
（无论符号是否可解析）读 `layout.defaultImplementation.isValid`（纯相对指针
位运算，不需要符号表），命中则记入当前 `offsetOfPWT`。已解析成员经
`DemangledSymbolWithOffset` 把同一 offset 存进 `FunctionDefinition.offset` /
`Accessor.offset`，两边天然可关联。

### 2.2 冻结期（SwiftDiffing）

- `MemberRecord` 新增 `hasDefaultImplementation: Bool?`（默认 nil = 非协议
  requirement / 不可知；**不参与 identity/payload key**，仅 verdict 元数据）。
- `makeProtocolRequirement` 直接带上精确位（payload 中的 `default:` 位保留，
  flip 仍产生 `.modified` 事件）。
- `memberRecords(of: ProtocolDefinition)` 改为逐集合投影并附标志：
  函数/allocator/constructor 关联 `[definition.offset]`；variable/subscript
  关联全部 `accessors.map(\.offset)`——**所有** slot 都有默认实现才算 `true`
  （`var { get set }` 只有 getter 默认 ⇒ `false`）；任一 offset 缺失 ⇒ `nil`
  （诚实降级回 status 规则）。纯函数
  `requirementDefaultImplementationFlag(slotOffsets:defaultedOffsets:)` 可单测。

## 3. verdict 规则

`MemberChange` / `LineageEvent` 各新增 `compatibilityOverride: Compatibility?`
（init 默认 nil，Codable 增量字段），计算属性
`compatibility = compatibilityOverride ?? status.compatibility`。override 由
diff / evolution 构建时用同一条纯规则计算（`MemberRecord` 上的静态函数，两路
共享，N=2 一致性自动保持）：

| 情形 | override |
|---|---|
| `.added` 且 `new.hasDefaultImplementation == false` | `.breaking`（defaultless requirement 追加） |
| `.added` 且 flag 为 `true` / `nil` | 无（status 规则：additive） |
| `.modified` 且两侧均为 `.protocolRequirement`、仅 `default:` 位 `0→1`（payload 去掉 default 位后相等） | `.additive`（获得默认实现本身不破坏） |
| 其余 `.modified` / `.removed` | 无（status 规则：breaking） |

要点：

- **已解析 requirement 的 default flip 不产生事件**（flag 不入 payload key）——
  这不丢信息：默认实现函数本身就是 protocol-extension 容器里的成员增删，
  已在该轴如实呈现。
- stripped slot 的 `default:1→0`（默认实现被移除）经 status 规则报 breaking，
  正确：依赖默认实现的既有 conformance 将 trap。
- `associatedType:` 名单记录保持 verdict 中立（无 flag）；其 slot 化身
  （`pwtslot:` 的 `associatedTypeAccessFunction`，默认 witness 即
  `associatedtype A = X`）承担判定。

## 4. formatVersion 4 → 5

`MemberRecord` 增加可选字段属快照 schema 变更。按契约 bump（宁可让用户重生成
baseline，也不引入「同版本号两种 schema」的模糊态）；history 注明 v5 仅增
verdict 元数据、键格局与 v4 相同。

## 5. 已知边界（含落地实测修正）

1. **flag 的语义是「resilient default witness 存在」，不是「源码有默认实现」**
   （落地实测确认，比 spec 初稿更精确）：编译器只为 **resilient 协议**
   （public + library-evolution 模块）生成 default witness table——internal
   协议或未开 evolution 的模块，即使源码在 protocol extension 里写了默认实现，
   描述符位也恒为 0（SIL 层无 `sil_default_witness_table`）。而这恰是**正确的**
   verdict 输入：非 resilient 协议的既有 conformance witness table 编译期定长，
   追加 requirement 无论有无源码默认都必然破坏；resilient default witness 正是
   让追加二进制兼容的那个机制本身。故位读数即 ABI 真值，无需(也不能)修正。
2. **flag 的符号依赖只剩一半**：默认位来自描述符（精确），但已解析成员的
   关联靠 PWT offset——协议成员一定携带 offset（索引路径注入），nil 仅出现在
   防御性路径上，降级为旧行为而非错报。
3. **`var` 升 `{ get set }`**：报 `.modified`（accessor 集变化）→ status 规则
   breaking。新 setter slot 即便有默认实现也维持 breaking——保守但方向安全，
   且该情形极罕见。
4. 符号化状态不对称（上一批局限）在 verdict 维度同样适用：stripped 侧用
   slot 记录判定、符号侧用成员记录判定，规则一致故结论一致。

## 6. 测试计划

- 纯规则表驱动：四行规则 + resolved 形态（kind `.function` 带 flag）逐一断言。
- `requirementDefaultImplementationFlag`：全默认 → true；部分 → false；
  含 nil offset → nil。
- 容器级整合：协议容器仅含 defaultless 追加 → `ContainerChange.compatibility
  == .breaking` 且 `hasBreakingChange`；defaulted 追加 → additive。
- evolution：同轴上 `transitionCompatibilities` 与双侧 diff verdict 一致
  （N=2）；default 0→1 的 `.modified` 事件不把 transition 判 breaking。
- CLI 冒烟（实测结果）：public + library-evolution 的 PWTSmoke 对——追加
  defaultless `erase()` → **ABI-breaking: true**（上一批为 false）；追加带
  protocol-extension 默认实现的版本 → **additive**（已解析路径，flag 经
  offset 关联命中）。internal 协议对照组两种写法都报 breaking——见 §5.1，
  这是正确行为而非缺陷。

## 7. 后续（本批不做）

- structure-driven reporter（`ABIDiffReporter` 的 TODO(P2)）。
- full-matrix evolution 视图。
