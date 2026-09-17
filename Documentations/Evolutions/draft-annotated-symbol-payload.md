# Draft - `AnnotatedSymbol<Payload>`：构建期符号包装泛型化，两个 offset 不再同名

- **状态**: In Progress
- **创建日期**: 2026-09-17
- **最后更新**: 2026-09-17
- **所属愿景**: 无
- **关联提案**: [draft-swift-declaration-file-layout](draft-swift-declaration-file-layout.md)（那批把这个类型从 `ProtocolDefinition.swift` 抽成独立文件，当时名为 `DemangledSymbolWithOffset.swift`；本提案改它的建模与文件名。该提案正文保留当时的名字不动——它记录的是自己那批做了什么，改写会让它的决策日志指向一个当时并不存在的名字）
- **实现分支 / PR**: `next`
- **配套文档**: [Modules/SwiftDeclaration.md](../Internal/Modules/SwiftDeclaration.md)（构建期机器一行）；[DefaultImplementationAwareCompatibility.md](../Internal/DefaultImplementationAwareCompatibility.md)（索引期数据通路一段）

## 摘要

`DemangledSymbolWithOffset` 是构建期把一个 `DemangledSymbol` 和它在协议见证表（protocol witness table，PWT）里的槽位偏移配对的包装：只有 `ProtocolDefinition.index(in:)` 有偏移可填，其余产地一律 `nil`。

问题出在名字上。它的存储属性叫 `offset`，而它通过 `@dynamicMemberLookup` 转发的 `DemangledSymbol.offset` 是**符号在镜像里的字节偏移** —— 同名、不同类型（`Int?` 对 `Int`）、语义毫不相干，存储属性静默遮蔽转发的动态成员，编译器不给任何提示。`DefinitionBuilder` 里四处不得不写 `memberSymbol.base.offset` 才能拿到真正的符号偏移，而 `memberSymbol.offset` 悄悄给的是 PWT 槽位——这正是 `LayoutWrapper` 那条「同名不同类型的属性遮蔽动态成员」戒律的同款，只是发生在声明模型这一侧。

类型名本身也是把字段名塞进类型名（`…WithOffset`），是同一个毛病的表层。

## 方案

**通用容器**：`AnnotatedSymbol<Payload>` —— `base: DemangledSymbol` 加一个 `payload: Payload`，`@dynamicMemberLookup` 转发到 `base`，条件 `Sendable`。需要什么语义就特化一个 `Payload` 并扩展一个具名计算属性，`payload` 与具名属性两条路都能读，文档注释规定优先读具名的那条。

**类型标签**：`ProtocolWitnessTableOffset: RawRepresentable, Sendable`，`RawValue == Int`。它不带行为，存在的唯一理由是让特化约束写成 `where Payload == ProtocolWitnessTableOffset?` 而不是 `where Payload == Int?` —— 后者任何别的 `Int?` payload 都会白白命中。

**特化扩展**提供 `protocolWitnessTableOffset` 和对称的语义 init，两侧都说 `RawValue?`：

```swift
extension AnnotatedSymbol where Payload == ProtocolWitnessTableOffset? {
    package var protocolWitnessTableOffset: ProtocolWitnessTableOffset.RawValue? { payload?.rawValue }

    package init(base: DemangledSymbol, protocolWitnessTableOffset: ProtocolWitnessTableOffset.RawValue?) {
        self.init(base: base, payload: protocolWitnessTableOffset.map(ProtocolWitnessTableOffset.init(_:)))
    }
}

package typealias MemberSymbol = AnnotatedSymbol<ProtocolWitnessTableOffset?>
```

标签因此不泄漏到调用点：`ProtocolDefinition+Indexing` 照旧传 `offsetOfPWT` 这个 `Int`，`DefinitionBuilder` 照旧把 `Int?` 塞进 `Accessor.offset`。

**调用点的净收益**：`base.` 只在真正需要 `DemangledSymbol` 本体的地方出现（`detachedFromSharedTable()`），符号偏移回到 `memberSymbol.offset`，PWT 槽位是 `memberSymbol.protocolWitnessTableOffset`，肉眼可分。顺带统一了两种做同一件事的写法——`TypeDefinition+MemberIndexing` 那 7 处手写的 `.map { .init(base: $0, offset: nil) }` 与 `SwiftDeclarationIndexer` 用的 `mapToDemangledSymbolWithOffset()`，现在都是 `mapToAnnotatedSymbols()`。

**遮蔽由测试守住，不靠注释**：`AnnotatedSymbolTests` 断言带 payload 的值其 `offset` 仍等于 `base.offset`，两个偏移取不同的字面量，所以遮蔽回归不可能靠巧合通过。临时加一个 `package var offset: Int { payload?.rawValue ?? 0 }` 验证过它确实变红。

模型侧的 `FunctionDefinition.offset` / `Accessor.offset` / `VariableDefinition.offset` / `OrderedMember.pwtOffset` 一律不动——它们是 `public`，改名是破坏性 API 变更，另案。

## 决策日志

- **2026-09-17 为什么不把 PWT 偏移并进 `DemangledSymbol`**：语义上它属于 `SwiftDeclaration` 这一层，而 `DemangledSymbol` 在 `MachOSymbols`，隔两层；而且 `SymbolIndexStoreFixtureTests.compactValueLayouts` 把它的 stride 钉在 ≤ 32 字节（一个镜像要 vend 几十万个值），多一个 `Int?` 就超。
- **2026-09-17 为什么 payload 是 `Optional` 而不是「有值」「无值」两个特化**：协议路径和其余路径必须喂进同一个 `DefinitionBuilder` 入口，所以必须是同一个特化，「没有」只能由 `Optional` 表达。要做成 `AnnotatedSymbol<Void>` 加 `AnnotatedSymbol<ProtocolWitnessTableOffset>` 两支，就得把 payload 抽成协议再让 `Void` 也遵循，比现在复杂得多。
- **2026-09-17 为什么不用具名元组**：`(symbol:protocolWitnessTableOffset:)` 零类型零宏、结构上不可能遮蔽，但丢掉 `@dynamicMemberLookup`（十几处 `memberSymbol.demangledNode` 要变成 `entry.symbol.demangledNode`），而且元组扩展不了、挂不上语义计算属性——正是这次要的那个能力。
- **2026-09-17 typealias 为什么叫 `MemberSymbol`**：周围术语全是这个词（`memberSymbolsByKind`、`MemberSymbolBucketing`、`SymbolIndexStore.MemberKind`、`SymbolIndexStore.memberSymbols(of:for:node:in:)`），builder 收的正是最后那个查询的产物。它对 `SwiftDeclarationIndexer` 里建全局变量 / 全局函数的两行偏窄，但那 6 个 builder 方法本来就带 `isGlobalOrStatic`、明摆着同时服务两者，且 typealias 只出现在声明处，那两处调用点靠类型推断根本看不见这个名字。要绝对准确得叫 `MemberOrGlobalSymbol`，为两行代码扛一个带 `Or` 的类型名不划算。
- **2026-09-17 为什么不下沉到 `Utilities`**：`base` 写死了 `DemangledSymbol`，最低只能到 `MachOSymbols`；真要进 `Utilities` 得连 base 一起泛型化成 `Annotated<Base, Payload>`，写起来 `Annotated<DemangledSymbol, Int?>` 反而更长，而且那一层现在没有第二个用例。等真出现第二个消费者再搬。
- **2026-09-17 `package struct` 的 `Sendable` 推断**：typecheck 探针证实 `package` 类型会被推断为 `Sendable`，但本提案仍在 `ProtocolWitnessTableOffset` 上显式写出——探针只覆盖单模块，而真实用法是 `SwiftDeclaration` 定义、`SwiftIndexing` 消费，不赌推断规则。
- **2026-09-17 `.map(ProtocolWitnessTableOffset.init)` 编译不过**：`init(rawValue:)` 与 `init(_:)` 都只收一个 `Int`，裸 `.init` 报 `ambiguous use of 'init'`，必须写全 `.init(_:)`。两个 init 都保留——`init(_:)` 让内部构造短，`init(rawValue:)` 是 `RawRepresentable` 的要求。
