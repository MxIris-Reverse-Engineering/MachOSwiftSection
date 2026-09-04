# 0018 - ABI 层自包含：MachOSwiftSection 不再依赖符号索引

- **状态**: Implemented
- **作者**: JH
- **创建日期**: 2026-09-03
- **最后更新**: 2026-09-04
- **所属愿景**: 无
- **关联提案**: [draft-large-stack-executor-and-cross-version-parallelism](draft-large-stack-executor-and-cross-version-parallelism.md)（同一轮调研的另一产物，互不依赖，可独立落地）
- **实现分支 / PR**: `feature/self-contained-abi-layer`（worktree `.worktrees/MachOSwiftSection-SelfContainedABI`），[PR #121](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/pull/121)
- **配套文档**: [SelfContainedABILayer.md](../Internal/SelfContainedABILayer.md)（实现说明）、[TaskReports/2026-09-03-self-contained-abi-layer.md](../Internal/TaskReports/2026-09-03-self-contained-abi-layer.md)（过程复盘）

## 摘要

`MachOSwiftSection` 是这个库的 ABI 层：把 `__swift5_*` 段里的描述符按运行时布局读出来。它今天反向依赖着符号索引：五个描述符的 Layout 里声明了 `RelativeDirectPointer<Symbols?>` 字段，而 `Symbols` 的 `Resolvable` 实现会走 `SymbolIndexStore.shared`，第一次访问就触发整个镜像十几万个符号的扫描与 demangle；`SymbolOrElementPointer` 又把 `MachOSymbols.Symbol` 值类型带进了 ABI 层的每一种上下文指针。本提案把 ABI 层收成真正自包含的一层：描述符只暴露实现的**地址**，符号查询作为扩展上移到 `SwiftInspection`；`Symbol` / `Symbols` / `SymbolOrElement` 这几个纯值类型下沉到 `MachOResolving`，`MachOSymbolPointers` 并入 `MachOPointers`；`MachOSwiftSection` 的依赖收成 `MachOReading` / `MachOResolving` / `MachOPointers`（加 MachOKit 与 MachOKitExtensions），同时摘掉只为一处前缀判断而存在的 `Demangling` 依赖。顺带消除 `ReadingContext` 那条腿把机器码字节当 `Symbols` 结构体读出来的隐患。

## 动机

### 1. 一个 ABI 访问器背后跑着整镜像的符号扫描

`MethodDescriptor.Layout.implementation` 的类型是 `RelativeDirectPointer<Symbols?>`（`Sources/MachOSwiftSection/Models/Type/Class/Method/MethodDescriptor.swift:8`），访问器 `implementationSymbols(in:)`（`:22`）就是对这个指针调 `resolve(from:in:)`。`Symbols` 的 `resolve`（`Sources/MachOSymbols/Symbols.swift:21`）调 `machO.symbols(offset:)`（`Sources/MachOSymbols/MachO+Symbol.swift:5-7`），后者是 `SymbolIndexStore.shared.symbols(for:in:)`，查询前先 `storage(in:)`：没建表就当场建（`Sources/MachOCaches/SharedCache.swift` 的 `resolve(key:build:)`），建表就是 `buildStorageSweep` 对全部符号逐个 demangle（SwiftUI iOS 18.5 是 185,988 行）。同样的结构复制在 `MethodOverrideDescriptor`、`MethodDefaultOverrideDescriptor`、`ProtocolRequirement`、`ResilientWitness` 四个描述符上。

也就是说，「读一个 vtable 槽指向哪里」这种 ABI 层面的操作，会把符号索引、demangler、`SharedCache`、内存压力监听整套东西拉起来。下游已经为此付过代价：MachOKitUI 在渲染 Swift section 之前把进程全局开关 `MachOSymbols.Symbol.resolvesSymbolUsingIndexStore` 强行置 `false`（`MachOKitUI/Sources/MachOKitUICore/Builder/MachOSwiftSectionDetailBuilder.swift:18-20`），就是为了让一个 Mach-O 浏览器翻描述符时别把整张符号表建起来。一个只想读 ABI 的消费者不该需要知道这个开关。

### 2. 类型依赖把 ABI 层钉在符号索引模块下面

即使不谈行为，`MachOSwiftSection` 也在类型层面离不开 `MachOSymbols`：`SymbolOrElementPointer`（`Sources/MachOSymbolPointers/SymbolOrElementPointer.swift:14-17`）的 `.symbol` 载荷是 `MachOSymbols.Symbol`，而 `ContextPointer`（`Sources/MachOSwiftSection/Pointer/ContextPointer.swift:4`）、`RelativeContextPointer` / `RelativeMethodDescriptorPointer` / `RelativeProtocolRequirementPointer`（`Pointer/RelativePointers.swift:3-9`）、`ProtocolConformanceDescriptor.protocolDescriptor`（`Models/ProtocolConformance/ProtocolConformanceDescriptor.swift:7`）、`TypeReference.indirectObjCClass`（`Models/Type/TypeReference.swift:8`）、`RelativeProtocolDescriptorPointer`（`Pointer/RelativeProtocolDescriptorPointer.swift:5-6`）全部建立在它之上，`ContextDescriptorProtocol.parent(in:)` 返回 `SymbolOrElement<ContextDescriptorWrapper>`。这些 `Symbol` 值只是 bind 表解析出来的「偏移加名字」（`SymbolOrElementPointer.swift:77-86` 的 `resolveBind`），从不碰索引库，但它们的类型住在装着 `SymbolIndexStore`、缓存与 `Demangling` 依赖的模块里。`Package.swift:355-362` 因此让 `MachOSwiftSection` 依赖 `MachOFoundation` 伞模块，而伞模块 `@_exported` 了 `MachOSymbols` 与 `MachOSymbolPointers`（`Sources/MachOFoundation/Exported.swift`）。

### 3. `ReadingContext` 那条腿在读垃圾内存

`implementationSymbols(in context:)`（`MethodDescriptor.swift:30`，其余四个描述符同形）对 `RelativeDirectPointer<Symbols?>` 调 `resolve(at:in:)`。`Symbols` 没有为 `ReadingContext` 提供任何实现，于是落到 `Resolvable` 的默认实现 `context.readElement(at:)`（`Sources/MachOResolving/Resolvable.swift`），最终是 `assumingMemoryBound(to: Symbols.self).pointee`（`Sources/MachOReading/Readable/UnsafeRawPointer+Readable.swift:60-62`）：把函数入口处的机器码按「一个 `Int` 加一个数组引用」的结构体原样读出来。它没有崩溃只是因为读出的假数组指针恰好是非规范地址，运行时的 retain / release 会跳过它；三处 fixture 测试只断言 `!= nil`（`Tests/MachOSwiftSectionTests/Fixtures/Type/Class/Method/MethodDescriptorTests.swift:64`、`MethodOverrideDescriptorTests.swift:90`、`Fixtures/Protocol/ProtocolRequirementTests.swift:60`，`imageContext` 是 `MachOContext<MachOImage>`，见 `Sources/MachOTestingSupport/MachOSwiftSectionFixtureTests.swift:15`），非 Optional 路径永远不为 nil，所以永远绿。`Sources/` 里没有生产代码走这条腿。这是「符号查询伪装成内存读取」这个设计的必然结果：`MachO` 那条腿有索引库可查，`ReadingContext` 这条腿没有任何符号服务，只能读字节。

## 前期调研

- **两条依赖通道的完整清单**：行为通道是五个描述符的 `RelativeDirectPointer<Symbols?>` 字段与 `implementationSymbols` / `defaultImplementationSymbols` 访问器（`Models/Type/Class/Method/MethodDescriptor.swift:8,22,30`、`MethodOverrideDescriptor.swift:9,35,51`、`MethodDefaultOverrideDescriptor.swift:9,31,57`、`Models/Protocol/ProtocolRequirement.swift:7,21,43`、`Models/Protocol/ResilientWitness.swift:8,41,53`）；类型通道是 `SymbolOrElement` / `SymbolOrElementPointer`（上文动机 §2）。`MachOSwiftSection` 里显式 `import MachOSymbols` 的两个文件（`Models/Type/TypeContextWrapper.swift:3`、`Models/BuiltinType/BuiltinType.swift:2`）实际没有用到该模块的任何名字。
- **`Demangling` 依赖只剩一处**：`Sources/MachOSwiftSection/Extensions/String+.swift:18` 用了 `String.isSwiftSymbol`（上游 `Sources/Demangling/Utils/Extensions.swift:26`，一个 mangling 前缀判断）；`Models/OpaqueType/OpaqueType.swift` 与 `Models/ContextDescriptor/ContextDescriptorProtocol.swift:3` 的 `import Demangling` 没有实际引用。`MangledName` 是本模块自己的类型（`Models/Mangling/MangledName.swift:5`），不来自上游。
- **值类型的真实职责**：`Symbol`（`Sources/MachOSymbols/Symbol.swift:8-23`）是 `offset` / `name` / `isExternal` 三个字段的 struct；只有 `resolve(from:in:)`（`:25-35`）与 `@Mutex static var resolvesSymbolUsingIndexStore`（`:71-72`）牵扯索引库。`Symbols`（`Symbols.swift`）是 `[Symbol]` 的集合包装，其 `AsyncResolvable` 实现是全部耦合所在。`SymbolOrElement`（`Sources/MachOSymbols/SymbolOrElement.swift:6-8`）是 `symbol` / `element` 二选一的枚举。
- **`ResilientWitness` 已经有地址形态的访问器**：`implementationOffset`（`ResilientWitness.swift:30-32`，用 `resolveDirectOffset(from:)` 纯算术得出，不需要 reader）与 `implementationAddress(in:)`（`:37-39`）。本提案就是把这个形态推广到五个描述符。`MachOPointers` 已有 `RelativeDirectRawPointer`（`Sources/MachOPointers/RelativePointers.swift:9`）。
- **上层调用方**（都在本仓库内，`grep implementationSymbols|defaultImplementationSymbols|Symbols\.resolve|Symbol\.resolve`）：`SwiftDump` 的 `ClassDumper`（7 处）、`ProtocolConformanceDumper`（4）、`ProtocolDumper`（2）；`SwiftDeclaration` 的 `TypeDefinition`（3）、`ExtensionDefinition`（3）、`ProtocolDefinition`（2）；`SwiftInspection/MetadataReader.swift:162`（`MachOContext.lookupSymbol` 走 `Symbol.resolve`）；`SwiftDeclarationRendering/Extensions/OpaqueType+.swift:12`；`MachOFixtureSupport` 三个 baseline 生成器；`MachOSwiftSectionTests` 四个 fixture 套件。它们要的都是「这个偏移上有哪些符号」，多数已经直接写 `Symbols.resolve(from: x.offset, in: machO)`。
- **下游**：RuntimeViewer 两个文件 `import MachOSwiftSection`，没有经它间接使用 `MachOSymbols` / `MachODependencies` 的类型；MachOKitUI 有三个文件经再导出拿到了 `MachOSymbols` 的名字，其中 `MachOSwiftSectionDetailBuilder.swift:18-20` 用限定名 `MachOSymbols.Symbol` 且没有 `import MachOSymbols`；SymbolViewer 八个文件直接 `import MachOSymbols`，不经 `MachOSwiftSection`。
- **来历**：`RelativeDirectPointer<Symbols?>` 由 2025-06-29 的 commit `a9f019c1`「Handling the issue of multiple symbols with the same offset」引入——同地址多名字（identical code folding）需要一个集合类型，当时顺手让集合 `Resolvable`，字段就直接「解析成符号列表」了。集合本身仍是对的，错的是把查询做成读取。
- **覆盖不变量**：`MachOSwiftSectionCoverageInvariantTests` 要求 `Models/` 下每个公开方法都有登记测试；五个访问器登记在 `Tests/MachOSwiftSectionTests/Fixtures/__Baseline__/*Baseline.swift` 的 `registeredTestMethodNames`。方法移出 `Models/` 后登记随之迁移。

## 提议方案

1. **ABI 层只说地址。** 五个描述符 Layout 的 `RelativeDirectPointer<Symbols?>` 改为 `RelativeDirectRawPointer`；访问器统一为 `implementationOffset: Int?`（空指针为 nil）与 `implementationAddress(in context:)`；`ProtocolRequirement` 用 `defaultImplementationOffset` 命名。`implementationSymbols` 家族从 `MachOSwiftSection` 删除。
2. **符号查询作为扩展上移到 `SwiftInspection`。** 在 `SwiftInspection` 里给五个描述符补同名扩展 `implementationSymbols(in machO:)`，实现是拿偏移问 `machO.symbols(offset:)`。只保留 `MachO` 那条腿；`ReadingContext` 腿不再提供（没有符号服务可用，也没有生产调用方）。
3. **值与服务分家。** `Symbol` / `Symbols` / `SymbolOrElement` 移到 `MachOResolving`；`SymbolOrElementPointer` 连同 `MachOSymbolPointers` 整个并入 `MachOPointers`，删除该 target。`Symbols` 不再是 `Resolvable`；`Symbol` 走索引库的 `resolve(from:in:)` 与 `resolvesSymbolUsingIndexStore` 留在 `MachOSymbols` 作为扩展。
4. **依赖收窄。** `MachOSwiftSection` 的 target 依赖改为 MachOKit、MachOKitExtensions、`MachOReading`、`MachOResolving`、`MachOPointers`、`MachOSwiftSectionC`、`Utilities`；`Sources/MachOSwiftSection/Exported.swift` 改为再导出这几个底层模块而非伞模块；`isSwiftSymbol` 在本模块就地实现，摘掉 `Demangling` 依赖；删掉两处无用的 `import MachOSymbols`。`MachOFoundation` 伞模块继续服务上层，去掉 `MachOSymbolPointers` 一行。

### 非目标

- 不改 `SymbolIndexStore` 的任何行为与 API；不改 `MetadataReader` 的符号查找机制（它在 `SwiftInspection`，位置本来就对）。
- 不动 `resolvesSymbolUsingIndexStore` 开关的语义；它只影响 `MachOSymbols` 里留下的 `Symbol.resolve`。
- 不给 `ReadingContext` 增加符号服务抽象。
- 不处理 `Demangling` 以外的其它模块边界（`MachOSwiftSectionC`、`Utilities` 保持）。

## 详细设计

### ABI 层（`MachOSwiftSection`）

```swift
public struct MethodDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: MethodDescriptorFlags
        public let implementation: RelativeDirectRawPointer
    }
    public var layout: Layout
    public let offset: Int
}

extension MethodDescriptor {
    /// File offset of the implementation, or `nil` for a null pointer
    /// (a method with no implementation). Pure pointer arithmetic on the
    /// descriptor's own offset, so it needs no reader.
    public var implementationOffset: Int? {
        guard layout.implementation.isValid else { return nil }
        return layout.implementation.resolveDirectOffset(from: offset(of: \.implementation))
    }

    /// The same target as an address in `context`.
    public func implementationAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let implementationOffset else { return nil }
        return try context.addressFromOffset(implementationOffset)
    }
}
```

`MethodOverrideDescriptor`、`MethodDefaultOverrideDescriptor`、`ResilientWitness` 同形；`ProtocolRequirement` 的字段与访问器名为 `defaultImplementation` / `defaultImplementationOffset` / `defaultImplementationAddress(in:)`。`ResilientWitness` 现有的 `implementationOffset: Int` 改为 `Int?`（空指针语义原来靠调用方 `isValid` 自查，现在统一）。

### 符号查询扩展（`SwiftInspection`）

```swift
import MachOSwiftSection
import MachOSymbols

extension MethodDescriptor {
    public func implementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) -> Symbols? {
        guard let implementationOffset else { return nil }
        return machO.symbols(offset: implementationOffset)
    }
}
```

其余四个同形。返回类型从 `throws -> Symbols?` 变为 `-> Symbols?`（查询本身不抛）。

### 值类型下沉

```swift
// MachOResolving
public struct Symbol: Hashable, Sendable {
    public let offset: Int
    public let name: String
    public let isExternal: Bool
    public init(offset: Int, name: String, isExternal: Bool = false)
    public func addressString(format: AddressFormat, in machO: some MachORepresentableWithCache) -> String
}

public struct Symbols: RandomAccessCollection, MutableCollection { /* 现状，去掉 AsyncResolvable */ }

public enum SymbolOrElement<Element: Resolvable>: Resolvable {
    case symbol(Symbol)
    case element(Element)
}

// MachOPointers（吸收 MachOSymbolPointers 全部内容）
public enum SymbolOrElementPointer<Element: Resolvable>: RelativeIndirectType { /* 现状 */ }

// MachOSymbols 留下的部分
extension Symbol {
    @Mutex public static var resolvesSymbolUsingIndexStore: Bool
    public static func resolve<MachO: MachORepresentableWithCache & Readable>(from offset: Int, in machO: MachO) throws -> Self?
}
extension MachORepresentableWithCache {
    public func symbols(offset: Int) -> Symbols?
}
```

`MachOPointers` 需要新增对 `MachOKitExtensions` product 的依赖（`SymbolOrElementPointer` 用 `MachOBindRebaseResolving`）。`MachOFoundation/Exported.swift` 去掉 `MachOSymbolPointers`。

### 调用方迁移

| 现在 | 之后 |
|---|---|
| `try Symbols.resolve(from: x.offset, in: machO)` | `machO.symbols(offset: x.offset)` |
| `try Symbol.resolve(from: offset, in: machO)`（`MetadataReader.swift:162`） | `machO.symbols(offset: offset)?.first`（保留 `resolvesSymbolUsingIndexStore` 分支时仍调 `MachOSymbols` 留下的 `Symbol.resolve`） |
| `try descriptor.implementationSymbols(in: machO)` | `descriptor.implementationSymbols(in: machO)`（需 `import SwiftInspection`） |
| `descriptor.implementationSymbols(in: context)` | 删除；无生产调用方 |

### 测试

- **先钉住垃圾读**：对旧 API 写一条会红的测试——`implementationSymbols(in: imageContext)` 的结果应与 `implementationSymbols(in: machOImage)` 一致，今天不一致。它作为动机 §3 的证据进提案分支；旧 API 删除后由下一条永久替代。
- **永久回归**：四个 fixture 套件的 `implementationSymbols` 测试改为跨 reader 比对 `implementationOffset` 的真值并对照 baseline 字面量，`imageContext` 腿比对 `implementationAddress(in:)` 与偏移一致；`registeredTestMethodNames` 登记新成员名，`regen-baselines` 重生成。
- **分层本身由编译器守**：`Package.swift` 里 `MachOSwiftSection` 的依赖列表不含 `MachOSymbols` / `Demangling`，回归就是编译错误，不另加源码扫描。
- **渲染 A/B**：本提案触碰 reader 栈与索引路径，必须跑 `Scripts/run-rendering-ab-verification.py` 逐字节对比。

## 替代方案考量

- **只在代码里不调索引库，保留伞模块依赖（代码级别自包含）**：不必移动任何类型，下游零改动。否决：依赖仍在包图里，clean build 时 ABI 层仍要等 `Demangling` 编完，而「别再把索引库钩回 ABI 层」只能靠 review 守。2026-09-03 用户明确选包图级别。
- **在 `MachOReading` 定义符号查找协议，让 `ReadingContext` / `MachO` 类型 retroactive 遵循**：能保住 `ReadingContext` 腿。否决：为一个没有生产调用方的入口引入一层抽象，且 retroactive conformance 落在 `MachOSymbols` 就意味着谁 import 了它谁的 ABI 访问器行为就变，隐式耦合换了个地方。
- **给 `MachOSymbols` 留 `typealias Symbol = MachOResolving.Symbol` 保住限定名**：否决：`MachOFoundation` 同时再导出两个模块，同名 typealias 会让不限定的 `Symbol` 在所有 `import MachOFoundation` 的文件里产生歧义风险；限定名 `MachOSymbols.Symbol` 的已知调用方只有 MachOKitUI 一处，改一行即可。
- **把值类型全部并进 `MachOPointers`**：少一层，但 `MachOPointers` 的职责从「相对指针」变成「指针加符号值」。`Symbol` 是「地址解析」的结果，`MachOResolving` 更贴切，且 `Resolvable` 就在那里。
- **扩展放新建的小 target `MachOSwiftSectionSymbols`**：分层最纯，多一个模块要维护；`SwiftInspection` 已经是「ABI + 符号 + demangle」的交汇层。2026-09-03 用户选 `SwiftInspection`。

## 影响

### 源码兼容性（source compatibility）

**有破坏**，逐条：

| 调用点 | 改前 | 改后 |
|---|---|---|
| 描述符符号访问器 | `try d.implementationSymbols(in: machO)`（`MachOSwiftSection`） | `d.implementationSymbols(in: machO)`，需 `import SwiftInspection` |
| `ReadingContext` 腿 | `try d.implementationSymbols(in: context)` | 删除，无替代（读的是垃圾） |
| Layout 字段类型 | `RelativeDirectPointer<Symbols?>` | `RelativeDirectRawPointer` |
| `ResilientWitness.implementationOffset` | `Int` | `Int?` |
| `Symbols.resolve(from:in:)` / `Symbol.resolve(from:in:)` 作为 `Resolvable` 要求 | 存在 | `Symbols` 的删除；`Symbol` 的保留为 `MachOSymbols` 扩展方法 |
| 限定名 `MachOSymbols.Symbol` / `MachOSymbols.Symbols` / `MachOSymbols.SymbolOrElement` | 可用 | 改为 `MachOResolving.…` 或不限定 |
| `import MachOSymbolPointers` | 可用 | 模块并入 `MachOPointers` |
| 经 `import MachOSwiftSection` 间接得到 `MachOSymbols` / `MachODependencies` 的名字 | 可用 | 需显式 import |

`@available(*, deprecated, renamed:)` 能覆盖的只有 `symbols(offset:) async` 这种同模块内的改名；类型跨模块移动与字段类型变更无法平滑过渡，按 minor 版本一次性完成。

### ABI 兼容性

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

本仓库：`MachOSwiftSection`、`MachOSymbols`、`MachOResolving`、`MachOPointers`、`MachOSymbolPointers`（删除）、`MachOFoundation`、`SwiftInspection`、`SwiftDeclaration`、`SwiftDump`、`SwiftDeclarationRendering`、`MachOFixtureSupport`、`MachOSwiftSectionTests`。

跨仓库：MachOKitUI 三个文件补 `import MachOSymbols`（其中一处改限定名）；RuntimeViewer 无影响；SymbolViewer 无影响（直接 import `MachOSymbols`，用的是索引库）。

### 文档与示例

AGENTS.md 的模块依赖图与 `MachOSwiftSection` / `MachOSymbols` 条目；`Documentations/README.md`、`Documentations/Internal/Modules/` 的模块参考；`ProjectEvolutionLog.md` 新节；`Changelogs/` 随版本；Glossary 视是否引入新术语（预计不引入）。

## API 演进与废弃策略

- `symbols(offset:) async`（与同步版逐字相同）标 deprecated 一个版本后删除。
- 其余破坏项无法转发，随 minor 版本（0.18.0）一次性完成，Changelog 逐条列出改前 / 改后。
- 不需要 semver major：本库 0.x 阶段，且下游全部在本人控制之下。

## 落地步骤

1. 对旧 API 写红测试钉住 `ReadingContext` 腿的垃圾读（动机 §3），确认修前失败。
2. 值类型下沉：`Symbol` / `Symbols` / `SymbolOrElement` 移到 `MachOResolving`，`MachOSymbolPointers` 并入 `MachOPointers`，`Package.swift` 与 `MachOFoundation/Exported.swift` 同步；`MachOSymbols` 留下 `Symbol.resolve` 与开关。全仓库构建通过。
3. 描述符字段改 `RelativeDirectRawPointer`，补 `implementationOffset` / `implementationAddress(in:)`，删 `implementationSymbols` 家族。
4. `SwiftInspection` 补五个扩展；迁移 `SwiftDeclaration` / `SwiftDump` / `MetadataReader` / `OpaqueType+` / baseline 生成器的调用点。
5. `MachOSwiftSection` 依赖收窄：`Exported.swift`、就地实现 `isSwiftSymbol`、删无用 import、`Package.swift` 依赖列表。
6. fixture 测试改比对偏移真值，登记 `registeredTestMethodNames`，`regen-baselines`，覆盖不变量全绿；步骤 1 的红测试由新 API 上的等价断言永久替代。
7. 全量测试（`--skip IntegrationTests`）与渲染 A/B 逐字节验证。
8. 文档同批：AGENTS.md、README 索引、模块参考、演进账本、Changelog 与 `Version.swift`；MachOKitUI 侧补 import 的 PR。

**收尾时判断**：实现说明——写（「为什么 `ReadingContext` 腿没有符号服务」「为什么不留 typealias」是从签名看不出的决策）；术语——预计不引入。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-03 | Created as Draft | 用户提出「ABI 不能反向依赖 SymbolIndexStore，ABI 接口应该自包含」，本提案由当日调研直接产出 |
| 2026-09-03 | 自包含到包图级别 | 澄清提问第一轮：`MachOSwiftSection` 只依赖三个底层模块，不再再导出伞模块；代码级别方案否决（依赖仍在包图里，防回归靠 review） |
| 2026-09-03 | 扩展落点 `SwiftInspection` | 同轮：否决新建小 target 与「不提供扩展」 |
| 2026-09-03 | 值类型下沉 `MachOResolving`，`MachOSymbolPointers` 并入 `MachOPointers` | 第二、三轮：用户先反问「下沉有意义吗」，答复是不下沉则包图级别不成立；确认下沉 |
| 2026-09-03 | 未问自定 | deprecated 只覆盖可转发项，minor 版本一次完成；`ReadingContext` 腿先红测试后删除；顺手摘掉 `Demangling` 依赖 |
| 2026-09-03 | Accepted | 用户：「swift-demangling 那边的给它的 agent 就行了，你这边弄 ABI」——上游提案 0014 交由该仓库的 agent，本提案获准开工 |
| 2026-09-03 | In Progress | 在 worktree `MachOSwiftSection-SelfContainedABI`（分支 `feature/self-contained-abi-layer`，基于 `next` f3782248）实施；async 提案 draft 随分支携带，不在本批实现 |
| 2026-09-03 | 红测试证实垃圾读 | 对旧 API 比对两条腿的 `offset`：context 腿 -2999674702252736512，MachO 腿 5624（`MethodDescriptorTests`，修前失败）；修后由新 API 上的 `implementationAddress(in: context) == implementationOffset` 永久替代 |
| 2026-09-03 | 实现期决定：新增底层伞模块 `MachOBase` | 163 个文件的 `import MachOFoundation` 一行换成 `import MachOBase`，比每个文件写四五行显式 import 干净；`MachOFoundation` = `MachOBase` + `MachOSymbols` + `MachODependencies` |
| 2026-09-03 | 实现期决定：`symbols(offset:) async` 删除而非废弃 | 方案原想标 deprecated 留一版；实测 async 上下文优先绑定 async 重载并要求 `await`，`if let symbols = machO.symbols(offset:)` 四处直接报错，两个重载不能共存 |
| 2026-09-03 | 实现期决定：`Demangling` 依赖多摘出两处 | 除 `isSwiftSymbol` 外还有 `stripManglePrefix`（`MangledName.typeString`）与 `cModule` / `objcModule`（`ContextDescriptorProtocol`）；分别本地化为 `strippingSwiftManglingPrefix` 与 `CImportedModuleNames`，前两者由 `ManglingPrefixTests` 钉住与 demangler 一致 |
| 2026-09-03 | 实现期发现：16 个 target 靠传递依赖拿 `MachOFoundation` | `SwiftInspection`、`SwiftDump`、`SwiftDeclaration`、`SwiftIndexing`、`SwiftPrinting`、`swift-section` 与十个测试 target 从未声明 `.target(.MachOFoundation)`，全靠 `MachOSwiftSection` 的再导出；本批补齐声明，另有 12 个源码文件与若干测试文件补显式 import |
| 2026-09-03 | 验证通过 | `MachOSwiftSectionTests` 723 测试 / 161 套件全绿；全量 1617 测试 / 302 套件仅两个已知 flaky 的墙钟并行度断言假失败、单独重跑全绿；渲染 A/B 78 对输出逐字节一致（系统 dyld cache、四个模拟器运行时、进程内 MachOImage）。细节见任务报告 |
| 2026-09-04 | Review 修复批次（PR #121 review，12 条全真） | A–H 与 I（Utilities）、K、L 修复：补 `MachOBase` / `MachOFoundation` library product（下游能声明依赖）、changelog 限定「逐字节一致」为默认 flag 并说明 `--emit-member-addresses` 下空 witness 不再打假地址、`ManglingPrefixTests` 钉住 `CImportedModuleNames`、`ProtocolRequirementTests` 加有默认实现的第二个 picker、`MethodOverrideDescriptor` baseline 发射 `implementationOffset`、四个 target 补依赖、CI filter 补 `MethodDefaultOverrideDescriptorTests`、`ProtocolConformanceDumper` 统一到新 accessor、image 腿独立断言、前缀单次扫描。延后：A23（既有未声明 import）、A24（全量迁移）。清单见 `Roadmaps/2026-09-04-pr121-review-findings.md` |
| 2026-09-03 | 收尾判断 | 配套文档：写了实现说明 [SelfContainedABILayer.md](../Internal/SelfContainedABILayer.md)（登记在头部）；术语：不引入新术语（`MachOBase` 是模块名，不入术语表）。待合入 `next` 时按落地规则取编号并置 Implemented |
| 2026-09-04 | Implemented；落地编号 0018 | `origin/next` 的 `Evolutions/` 最大编号 0017，本线取 0018；改名、标题、状态表与同仓链接同批完成，代码与 fixture 注释按规则继续引用 slug |
