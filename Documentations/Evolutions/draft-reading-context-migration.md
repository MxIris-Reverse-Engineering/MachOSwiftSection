# Draft - 读取接口统一到 ReadingContext：传 machO 与直接用指针的旧接口废弃

- **状态**: In Progress
- **作者**: JH
- **创建日期**: 2026-09-30
- **最后更新**: 2026-09-30
- **所属愿景**: 无
- **关联提案**: [0018-self-contained-abi-layer](0018-self-contained-abi-layer.md)（「`ReadingContext` 只管读、不带符号服务」的定位出自这里，本提案延续它）、[0025-key-path-component-and-property-descriptor](0025-key-path-component-and-property-descriptor.md)（记下了「新接口三套都写」的惯例，本提案推翻它）、[0053-shared-cache-composition-and-eviction-registry](0053-shared-cache-composition-and-eviction-registry.md)（按镜像缓存与驱逐的现行规则）
- **实现分支 / PR**: `refactor/reading-context-migration`（worktree `.worktrees/MachOSwiftSection-ReadingContextMigration`），[PR #129](https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/pull/129)
- **配套文档**: [ReadingContextAbstraction.md](../Internal/ReadingContextAbstraction.md)「单一实现与废弃」一节（实现说明：旧形式为何原地保留、两个协议保留已废弃的 requirement、约束扩展的 guard 陷阱、修掉的分歧、缓存范围、已知缺口）；术语表登记「cache scope」与「context / Mach-O / pointer form」

## 摘要

ABI 层几乎每个读取接口都有三份各自手写的实现：传 `machO` 的（按文件或镜像偏移读）、不传参直接用指针读本进程内存的、传 `some ReadingContext` 的。三份实现已经漂移：`ReadingContext` 版在 `MachOFile` 上漏了 rebase / bind 处理，指针版遇到空指针或带 tag 的指针直接崩。本提案把实现收成一份：`ReadingContext` 版补齐正确行为后成为唯一实现，传 `machO` 的旧接口改成一行转发到 `machO.context`，指针版改成一行转发到 `InProcessContext.shared`，两者在 0.22.0 标 `@available(*, deprecated)`、0.23.0 删除。范围是 ABI 层（`MachOSwiftSection`、`MachOPointers`、`MachOResolving` 的 `Resolvable`）的全部读取接口，外加上层模块里 61 个纯读取接口（`SymbolicDemangler`、`typeName` / `dumpName` 系列、`GenericContext+Dump` 等）；为了让后者按镜像缓存照常生效，`ReadingContext` 新增一个「缓存范围」声明。仓库内全部调用点与测试同批迁到 `ReadingContext` 版，下游（RuntimeViewer、MachOKitUI、swift-decompiler）在删除前各提 PR 迁移。

## 动机

### 1. 三份实现已经漂移，而且错在 `ReadingContext` 那一份

`ReadingContext` 在 2026-01 落地时（`Documentations/Internal/ReadingContextAbstraction.md`）是「新增一条腿」：旧接口不动，新接口另写一份。2026-05 的覆盖补全把 `Models/` 下缺的 `ReadingContext` 版全部机械地补上，同样是另写一份。结果是同一个接口的三份函数体各自维护，改一份忘两份：

- `Pointer.resolve`（`Sources/MachO/MachOPointers/Pointer.swift:15-29`）：传 `machO` 的版本先查 `MachOFile` 的 rebase 表（`:16`），`ReadingContext` 版直接把槽里的原始字节读出来（`:28`）。chained fixup 的文件里，这些字节是 fixup 编码而不是地址。所有「间接指针的中转类型是 `Pointer<…>`」的字段都继承这个差异：`ProtocolRecord.protocol`、`TypeMetadataRecord` 的间接描述符、`GenericRequirementContent.conformance`、`RelativeProtocolDescriptorPointer`、`ExistentialTypeMetadata.superclassConstraint`。
- `TypeMetadataRecord.contextDescriptor`（`Sources/ABI/MachOSwiftSection/Models/Type/TypeMetadataRecord.swift:40-71`）：传 `machO` 的版本跳过被 bind 的间接记录（`:48`），注释（`:32-39`）写明这是修过的真 bug——iOS 26.5 模拟器的 `libswiftSynchronization` 登记了一条指向 `libswiftCore` 里 `Swift.Optional` 的记录，读它会抛错并连带整张 `__swift5_types` 列表丢失。`ReadingContext` 版（`:58-71`）没有这个检查，这个 bug 在 `ReadingContext` 路径上还在。
- `SymbolOrElementPointer`（`Sources/MachO/MachOPointers/SymbolOrElementPointer.swift`）：可选元素的判空，指针版（`:110`）和 `machO` 版（`:121`）先 strip 再判 0，`ReadingContext` 版（`:132`）直接判 `address == 0`。指针版遇到 `.symbol` 直接 `fatalError()`（`:20-21`、`:108-109`），另外两版正常返回。
- 指针版的底层读取（`Sources/MachO/MachOReading/Readable/UnsafeRawPointer+Readable.swift:60-85`）既不 strip pointer tag 也不判空，`InProcessContext`（`Sources/MachO/MachOReading/ReadingContext/InProcessContext.swift:50-68`）两样都做。同一个本进程读取，走指针版遇到坏指针是崩溃，走 `ReadingContext` 版是抛错。
- 同名不同义：`ResilientWitness.implementationAddress(in: machO)` 返回格式化好的十六进制字符串（`Sources/ABI/MachOSwiftSection/Models/Protocol/ResilientWitness.swift:36-38`），`implementationAddress(in: context)` 返回地址值（`:50-53`）。

这些分歧没有被测试抓到，因为 fixture 套件主要测传 `machO` 的版本，`ReadingContext` 版多是附带一条断言，而且只在 `imageContext`（`MachOContext<MachOImage>`）上跑——镜像内存已经被 dyld 修正过，rebase / bind 的差异在那里不可见。

### 2. 惯例在让重复继续翻倍

[0025](0025-key-path-component-and-property-descriptor.md) 记下的惯例是「新接口三套都写」，每加一个读取接口就是三份函数体、三组测试。`ReadingContextAbstraction.md` 规划的第 4 阶段「给旧接口标 `@available(*, deprecated)`」一直写着 Future：2026-05 的补全 spec 把「重构旧接口」列为非目标，说上层迁移「留给后续分支」，这个后续分支从来没有发生。仓库内生产代码里，ABI 接口的调用约 229 处传 `machO`、约 104 处走指针、只有 28 处走 `ReadingContext`（其中 25 处在 `SymbolicDemangler.swift` 一个文件里）。

### 3. 上层模块把三份实现又复制了一遍

`SymbolicDemangler` 公开了传 `machO`、传 `ReadingContext`、什么都不传三套入口（`Sources/Analysis/SwiftInspection/SymbolicDemangler.swift:42-263`），`SwiftDeclaration` 的 `typeName(in: machO)` / `typeName()`、`SwiftDeclarationRendering` 的 `typeNode(in: machO)` / `typeNode()` 也是成对的。这些接口只读数据，本可以只收一个 `ReadingContext`；它们没有这么做，是因为 `SymbolicDemangler` 的缓存按镜像分（`SymbolicDemanglerCache`，`:834-964`），而 `ReadingContext` 说不出自己读的是哪个镜像——`SymbolicDemangler` 现有的 `ReadingContext` 入口（`:246-263`）因此完全不走缓存。

## 前期调研

- **三份实现的规模**（2026-09-30 在 `next` @ `32feff36` 上统计）：ABI 层传 `machO` 的声明 189 个、指针版 139 个、`ReadingContext` 版 143 个；`MachOPointers` / `MachOResolving` 另有一批协议 requirement 三套并列。已经转发的只有三处：`GenericContext.swift:144-150` 的两个 `init` 与 `TypeContextDescriptorProtocol.swift:110-113` 的 `typeImportInfo`。`Class` / `Enum` / `Struct` / `Protocol` / `ProtocolConformance` 的初始化在 `machO` 版与指针版之间共用一个 `initialize(… in reader: some Readable)`，`ReadingContext` 版另有一份。
- **指针版能否无损转发到 `InProcessContext`**：能。本进程读出来的 wrapper，其 `offset` 就是指针的 bit pattern（`UnsafeRawPointer+Readable.swift:64-67`），`asPointer`（MachOKitExtensions `LocatableLayoutWrapper.swift:24`）与 `InProcessContext.addressFromOffset`（`InProcessContext.swift:78-81`）得到同一个地址。行为差别只在更安全的一侧：多了 strip 与判空，崩溃变成抛错；错误类型从 `NullPointerError` 变成 `UnsafeRawPointer.Error.initFailed`。
- **`machO` 版能否无损转发到 `machO.context`**：能，前提是先把第 1 节的 rebase / bind / 判空差异补进 `ReadingContext` 版。每个 `machO` 参数都满足 `MachORepresentableWithCache & Readable`，`.context` 属性现成（`MachOContext.swift:97-112`）。bind / rebase 的判定统一走 `context.bindRebaseResolver`（`ReadingContext.swift:243-272`），它按协议而不是按 `MachOFile` 具体类型判定，所以 MachOKitUI 那种自己实现了 `MachOBindRebaseResolving` 的包装类型（`MachOKitUI/Sources/MachOKitUICore/Core/MachOFileSource+Traits.swift:131-139`）从此也能拿到正确的 rebase 处理，而它们今天在 `Pointer.resolve` 这类 `machO as? MachOFile` 的判定里是拿不到的。
- **缺 `ReadingContext` 版的接口**：`GenericMetadataPatternProtocol.extraDataPattern`、`GenericClassMetadataPattern.immediateMembersPattern`、`AccessibleFunctionRecord.genericEnvironment`、`RelativeProtocolDescriptorPointer.protocolDescriptorRef`、`MetadataWrapper.metadata`、`TargetGenericContext.uniqueCurrentRequirementsInProcess()`（有改了名的对应版本 `uniqueCurrentRequirements(in:)`）、`SymbolicDemangler.demangleType(for: Symbol, in:)`、`SymbolicDemangler.demangleTypeUncached(for:)`，以及只有传 `machO` 版的 `AsyncResolvable`（整个仓库没有调用方）。
- **天生离不开 Mach-O 或本进程的接口**：section 枚举入口（`MachOFile+Swift.swift` / `MachOImage+Swift.swift` 的 `machO.swift.*`，`SwiftSectionRepresentable`）、执行运行时代码的接口（`MetadataAccessorFunction.callAsFunction`、`RuntimeFunctions`、`MetadataProtocol.createInProcess` / `createInMachO` / `asMetatype`）、`MachOImage` 与指针之间的坐标换算（`asPointerWrapper(in:)`、`asMachOWrapper(in:)`）、地址格式化（`addressString`）、底层读原语（`Readable` 及其三个遵循、MachOKitExtensions 的 `asPointer` / `pointer(of:)`、`@Layout` 宏生成的 `pointer(from:of:)`）。它们不是「读取接口」而是入口、运行时调用或 `ReadingContext` 自身的实现基础。
- **上层模块的接口分类**：上层模块自己有 287 个传 `machO` 的 public / package 接口。226 个要用读取以外的能力——符号索引（`SymbolIndexStore`）、ObjC section（MachOObjCSection）、依赖闭包、section 枚举、thunk 反汇编、执行 `MachOImage` 里的运行时函数——`ReadingContext` 按 [0018](0018-self-contained-abi-layer.md) 的定位不提供这些。61 个只读数据：`SymbolicDemangler` 的 `demangleType` / `demangleContext` / `buildGenericSignature` / `extendedTypeContextDescriptor`，`SwiftDeclaration` 的 `typeName` / `protocolName` / `demangledTypeNode` / `materialized*` / `memberJoinKey`，`SwiftDump` 的 `dumpName` / `dumpTypeName` / `dumpProtocolName`，`SwiftDeclarationRendering` 的 `GenericContext+Dump`（20 个）、`ResilientSuperclass+Dump`、`ContextDescriptorWrapper+Dump`、`ProtocolConformance+` 的 `typeNode` / `protocolNode`、`ResolvedTypeReference.node`、`ParentClassVTableCache.slotIndex`。其中大部分是 `package`。
- **缓存怎么分层**：`SymbolicDemanglerCache` 与 `InternedNodeReferenceCache`（`Sources/MachO/MachOSymbols/InternedNodeReferenceCache.swift`）都分两层：按镜像的 `SharedCache` 条目（键是 `SharedCacheKey(machO)`，即 reader 的 `identifier`，随镜像驱逐），以及一份从不驱逐的全进程 `static` 存储，给本进程读取用。全进程那层按偏移做键（`nodeReferenceForContextOffset`），只对「偏移就是绝对地址」的 `InProcessContext` 安全；一个以文件偏移为地址的第三方 `ReadingContext` 如果落进这一层，两个镜像的偏移会撞在一起、互相串结果。`SharedCache` 已有按键取条目的 `resolve(key:build:)`（`Sources/MachO/MachOCaches/SharedCache.swift:179`）。
- **下游**（调用 ABI 旧接口的地方，全部是传 `machO` 版，没有一处用指针版或 `ReadingContext` 版）：RuntimeViewer `next` 3 处（`RuntimeSwiftSection.swift:713`、`RuntimeSwiftInterfaceIndexer.swift:208`，外加 `SymbolicDemangler.demangleType` 1 处；FindNavigator 分支另有 4 处）；MachOKitUI 24 处（`MachOSwiftSectionDetailBuilder.swift`），它还自己遵循了 `Readable`、`MachOSwiftSectionRepresentableWithCache`、`MachOBindRebaseResolving`；swift-decompiler 9 处 + 3 处 `dumpName(using:in:)`；REAgent 与 RuntimeViewer `main` 钉死在 0.15.2，不受影响。没有一个下游开了「警告当错误」，本仓库也没有（`Package.swift` 只给测试 target 加 `SILENT_TEST`）。
- **Swift 6.3 对废弃协议 requirement 的诊断**（`swiftc -typecheck` 探针实测）：只给默认实现标 `deprecated`、requirement 不标，每个依赖该默认实现的遵循类型都报「deprecated default implementation is used to satisfy …」；requirement 与默认实现一起标，遵循处不报、只在调用处报；遵循类型自己写的实现也不报。仓库里依赖默认实现的遵循类型成百上千（64 个直接遵循 `ResolvableLocatableLayoutWrapper`、25 个直接遵循 `Resolvable`），所以旧 requirement 不能只废弃默认实现。
- **分派是承重的**：`TypeContextDescriptorProtocol` 覆盖了 `genericContext`（`:17/38/52`），`any ContextDescriptorProtocol` 上的调用只有经过 requirement 才能落到这个覆盖；落不到时类型描述符会按 8 字节的 `GenericContextDescriptorHeader` 而不是 16 字节的 `TypeGenericContextDescriptorHeader` 解析（2026-04 的 `cc468e74` 就是为这个静态分派崩溃把 `ReadingContext` 版提成 requirement 的）。旧接口移出 requirement 列表之前，函数体必须已经转发到 `ReadingContext` requirement。
- **覆盖率不变式**：`MachOSwiftSectionCoverageInvariantTests` 的 `PublicMemberScanner` 只扫 `Sources/ABI/MachOSwiftSection/Models`，函数按「类型名 + 裸名字」建键、忽略标签与参数类型（`Sources/TestSupport/MachOFixtureSupport/Coverage/PublicMemberScanner.swift:127-145`），初始化器保留标签（`:147-156`），不看 `@available`。所以标废弃对它没有影响；0.23.0 删除时，只有指针版初始化器 `init(descriptor:)` / `init(contextDescriptor:)` 这 13 个键会从登记表里消失，要同步改 baseline 生成器的登记列表。另有一个陷阱：测试里用 `InProcessContext.shared` / `.inProcess` 而不是 fixture 的 `inProcessContext` 属性，会被 `SuiteBehaviorScanner` 判成 sentinel（它按大小写敏感的子串 `inProcessContext` 识别）。
- **仓库的废弃惯例**：[0018](0018-self-contained-abi-layer.md) 定过「能转发的废弃保留一个版本，否则在 minor 版本直接破坏」，0.x 阶段不升大版本，理由是下游都在本人控制之下；0.20.0 的两个废弃别名就是这么处理的。当前版本 0.21.0，本提案随 0.22.0 发布。
- **并行工作**：2026-09-30 另有会话在 `feature/offline-generic-specialization`（worktree `.worktrees/MachOSwiftSection-OfflineGenericSpecialization`）起草离线泛型特化，它会动 `SwiftSpecialization/GenericSpecializer.swift`，而那里有本提案要迁的约 50 处调用。两边谁后合，谁解冲突。

## 提议方案

**一份实现**：每个读取接口只保留 `ReadingContext` 版的函数体。传 `machO` 的旧接口写成 `try x(in: machO.context)`，指针版写成 `try x(in: InProcessContext.shared)`，两者标 `@available(*, deprecated)`，不再有自己的逻辑。

**废弃的**：

- ABI 层全部读取接口的传 `machO` 版与指针版：`Sources/ABI/MachOSwiftSection` 下的描述符、metadata、wrapper 初始化器与指针类型，`MachOPointers` 的相对 / 间接指针协议，`MachOResolving` 的 `Resolvable.resolve(from:in:)` / `resolve(from:)` 与 `AsyncResolvable`。
- 上层 61 个纯读取接口中的 `public` 者的传 `machO` 版与指针版（`SymbolicDemangler`、`SwiftDump` 的 `NamedDumpable.dumpName` / `ConformedDumpable.dumpTypeName` / `dumpProtocolName`、`SwiftDeclaration` 的 `materialized*`）。其中 `package` 级别的外部看不到，直接改签名，不走废弃。

**保留、不废弃的**：section 枚举入口、执行运行时代码的接口、`MachOImage` 与指针之间的坐标换算、地址格式化、底层读原语（清单见前期调研），以及上层那 226 个要用读取以外能力的接口。它们内部对 ABI 读取接口的调用照样改走 `ReadingContext`。

**`ReadingContext` 新增缓存范围**：一个带默认值的 requirement，回答「这个 context 读出来的东西，按镜像缓存、按进程缓存、还是不缓存」。`MachOContext` 回答按镜像（给出 reader 的 `identifier`），`InProcessContext` 回答按进程，其余一律不缓存。只暴露缓存身份，不暴露 Mach-O 本身。

**迁移**：仓库内全部调用点——`Sources/` 与测试、baseline 生成器——在废弃落地的同一个 PR 里改走 `ReadingContext` 版，每个 PR 合入时不新增任何废弃警告。下游在 0.22.0 发布后、0.23.0 之前各提 PR。

**惯例**：AGENTS.md 加一条——新读取接口只写 `ReadingContext` 版。

### 非目标

- 不改上层那 226 个要用符号索引、ObjC、依赖、section 枚举或运行时能力的接口，也不改 36 个按 `MachO` 泛型化的上层类型（`SwiftDeclarationIndexer<MachO>`、各 `Dumper`、`SwiftInterfaceBuilder` 等）。`ReadingContext` 不变成「镜像」抽象，不带符号服务。
- 不废弃、不收紧底层读原语（`Readable`、`UnsafeRawPointer: Readable`、`asPointer`、`pointer(of:)`、`pointer(from:of:)`）。MachOKitUI 自己实现了 `Readable`。
- 不动 MachOKitExtensions，不发它的新版本。
- 不改变任何 dump / interface 输出：三条读取路径的渲染 A/B 必须逐字节一致。
- 不支持 32 位 Mach-O（`MachOContext.Runtime` 仍是 `RuntimeTarget64`）。
- 不迁 REAgent、RuntimeViewer `main`（都钉死在 0.15.2）。

## 详细设计

### 1. 先修 `ReadingContext` 版，再切转发

每处修复先写一个修复前失败的测试（对 `MachOContext<MachOFile>` 断言与传 `machO` 版的结果一致，或直接断言正确值），修复后转绿，测试永久保留。

- **`Pointer.resolve(at:in:)`**：先问 `context.bindRebaseResolver?.resolveRebase(fileOffset:)`，有结果用它，否则再读字节。与 `SymbolOrElementPointer.resolve(at:in:)`（`:91-102`）现有的写法一致。
- **`TypeMetadataRecord.contextDescriptor(in:)`**：间接记录先问 `context.bindRebaseResolver?.resolveBind(fileOffset:)`，被 bind 的返回 `nil`。
- **`SymbolOrElementPointer` 可选元素**：判空改成 strip 之后判 0。
- **其它 `machO as? MachOFile` / `context as? MachOContext<MachOFile>` 的 bind 判定**（`SymbolOrElement.swift:37/45/57/65`）统一改走 `bindRebaseResolver`。

### 2. 转发与废弃的写法

```swift
extension NamedContextDescriptorProtocol {
    public func name(in context: some ReadingContext) throws -> String {
        let baseAddress = try context.addressFromOffset(offset + layout.offset(of: .name))
        return try layout.name.resolve(at: baseAddress, in: context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: machO.context for a Mach-O, .inProcess for process memory.")
    public func name(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> String {
        try name(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: .inProcess for process memory.")
    public func name() throws -> String {
        try name(in: InProcessContext.shared)
    }
}
```

- **协议 requirement**：`Resolvable`、`PointerProtocol`、`RelativePointerProtocol`、`RelativeIndirectType`、`RelativeIndirectPointerProtocol`、`RelativeIndirectablePointerProtocol`、`ContextDescriptorProtocol` 里的传 `machO` 版与指针版 requirement 移出协议声明，只作为废弃的扩展方法保留、转发到 `ReadingContext` requirement。具体遵循类型里手写的旧版本实现（`String` / `Optional` / `LocatableLayoutWrapper` 的 `resolve`、`Pointer.resolve`、`SymbolOrElementPointer.resolve` 等）一并删除，它们的 `ReadingContext` 版就是唯一实现。
- **不抛错的 `resolveOffset(in: machO) -> Int`**：转发到 `MachOContext` 自己的地址换算。`MachOContext.addressFromVirtualAddress` 的实现本来就不会抛错，把这个具体方法声明成不抛错（仍满足协议里的 `throws` requirement），转发处就不需要 `try!`。
- **`ResilientWitness.implementationAddress(in: machO) -> String?`** 属于地址格式化，保留，但改名为 `implementationAddressString(in:)`，旧名字标 `@available(*, deprecated, renamed:)`，免得和 `ReadingContext` 版同名、返回的却是另一种东西。
- **`AsyncResolvable`** 整个废弃，提示改用同步的 `resolve(at:in:)`。
- **补齐缺口**：前期调研列出的缺 `ReadingContext` 版的接口逐个补上，旧版本转发过去。`uniqueCurrentRequirementsInProcess()` 标 `deprecated`，提示 `uniqueCurrentRequirements(in: .inProcess)`。

### 3. `ReadingContext` 的缓存范围

```swift
/// Where the memo caches built on top of reading — demangling, node
/// interning — may file what they compute from a context.
public enum ReadingContextCacheScope: Sendable {
    /// Per image: entries are keyed on the reader's identifier and are
    /// evicted with the image.
    case image(identifier: AnyHashable)
    /// Process-wide: addresses are absolute, so two images never collide.
    case process
    /// The context gives no identity; nothing may be memoized.
    case uncached
}

public protocol ReadingContext<Runtime, Address>: Sendable {
    // Existing requirements unchanged.

    /// The scope a memo cache uses for what it computes from this context.
    var cacheScope: ReadingContextCacheScope { get }
}

extension ReadingContext {
    public var cacheScope: ReadingContextCacheScope { .uncached }
}
```

- `MachOContext` 返回 `.image(identifier: AnyHashable(machO.identifier))`，`InProcessContext` 返回 `.process`。默认值 `.uncached` 保证第三方 context 永远不会落进全进程那层。
- `MachOCaches` 的 `SharedCacheKey` 增加从 identifier 构造的入口，与 `SharedCacheKey(machO)` 共用同一段表示逻辑，保证同一个镜像经 `machO` 与经 context 得到同一个键，驱逐注册表（[0053](0053-shared-cache-composition-and-eviction-registry.md)）照常认领与驱逐。
- （实现时修订，见决策日志 2026-09-30「`.image` 的载荷改为 `MachOTargetIdentifier`」：`.image` 不带 `AnyHashable`，`SharedCacheKey` 也不加新入口，两个缓存用现成的 `SharedCacheKey(identifier:)`。）
- `SymbolicDemanglerCache` 与 `InternedNodeReferenceCache` 按 `cacheScope` 选层：`.image` 走按镜像的 `SharedCache` 条目，`.process` 走现有的全进程存储，`.uncached` 不查不存。`SymbolicDemangler.isCacheEnabled` 照旧是总开关。
- `SymbolicDemangler` 查符号用的私有 `SymbolLookupContext` 转型（`SymbolicDemangler.swift:184-231`）不变——那是符号服务，不是缓存身份。

### 4. 上层 61 个纯读取接口

- `public` 的：新增 `ReadingContext` 版作为唯一实现，旧版本废弃转发。`NamedDumpable` / `ConformedDumpable` 的 `dumpName` / `dumpTypeName` / `dumpProtocolName` 改成以 `some ReadingContext` 为参数的 requirement；取名逻辑从 `Dumper.name` 里抽成一个只读 context 的函数，`Dumper` 自己的 `name` 也调它（传 `machO.context`），保持一份实现。`ExtensionDefinition.init(extensionName:…:in:)` 的 `machO` 参数从未被使用，新增不带 reader 的初始化器，旧的废弃。
- `package` 的：直接改成 `some ReadingContext` 参数，调用方同批改。

### 5. 调用点迁移规则

- `x.f(…, in: machO)` → `x.f(…, in: machO.context)`；持有 `machO` 的上层类型在热点处可以存一份 `MachOContext`，其余就地写 `.context`。
- 指针版 `x.f()` → `x.f(in: .inProcess)`（生产代码）；测试里用 fixture 的 `inProcessContext` 属性。
- `T.resolve(from: offset, in: machO)` → `T.resolve(at: offset, in: machO.context)`；`pointer.resolve(from: ptr)` → `pointer.resolve(at: ptr, in: .inProcess)`。
- 以编译器的废弃警告为工作清单：先加废弃，再逐个清掉警告，直到构建零新增警告。

### 6. 测试

- fixture 套件与 baseline 生成器改调 `ReadingContext` 版，`acrossAllReaders` 改成 `acrossAllContexts`，按 `MachOContext<MachOFile>`、`MachOContext<MachOImage>`、本进程三种 context 各验一遍。baseline 的值不变（它们本来就由 `MachOFile` 上的传 `machO` 版生成，而那一版的正确行为已经补进 `ReadingContext` 版）。
- 新增一个转发套件：对每一类旧接口抽代表，断言旧接口与 `ReadingContext` 版结果相同。套件本身标 `@available(*, deprecated)` 以免报警，0.23.0 随旧接口一起删除。
- 第 1 节每处修复各带一个修复前失败的回归测试，永久保留。

### 7. 性能

`MachOFile`、`MachOImage`、本进程三条路径的 dump 与 interface 都和改动前对比耗时（同一份 `Package.resolved`、同一个 fixture 与系统镜像集），慢出测量噪声即视为回归，修到持平才合入。预期的风险点是原来走指针版的本进程路径（`RuntimeMetadataTypeBuilder`、`GenericSpecializer`、`RuntimeFieldLayoutBackend`）：每次读取多了 strip 与判空，调用从具体函数变成跨模块的泛型函数。手段按代价从低到高：在调用处持有具体的 `InProcessContext` 类型而不是存在类型、热点函数标 `@inlinable`、必要时对 `InProcessContext` 手动特化。

## 替代方案考量

- **只加废弃、三份实现不动**：改动最小，但漂移继续存在，第 1 节的 bug 也不会被修。用户明确要求「实现只有一份」。
- **旧接口直接删除**：一步到位，但会让 MachOKitUI、swift-decompiler、RuntimeViewer 在升级时直接编译失败。按 0018 定的惯例保留一个版本。
- **只迁 ABI 层**：不需要改 `ReadingContext` 协议，改动面约小一半；但 `SymbolicDemangler` 等上层只读接口会继续三套并存。用户选择把 61 个纯读取接口一起迁。
- **上层全部迁移，把 `ReadingContext` 扩成「镜像」抽象**：符号表、ObjC、依赖都经 context 走，226 个接口与 36 个泛型类型全部改写。工作量是本方案的数倍，而且推翻 0018「`ReadingContext` 不带符号服务」的决定。
- **`ReadingContext` 直接暴露底层 Mach-O**：一个可选的 `machO` 属性就能当缓存键，将来也方便更多上层接口改收 context。代价是调用方可以悄悄 `as? MachOFile`，把对 Mach-O 的依赖藏进 context 里，正是 0018 想避免的。
- **不改协议，缓存内部识别 `MachOContext` / `InProcessContext`**：公开面最小，但这个能力在协议上不可见，第三方 context 也无法选择加入。
- **运行时调用类接口也改收 `ReadingContext`**：这些接口只对本进程或 `MachOImage` 有意义，改成 context 形式只会得到一个传 `MachOContext<MachOFile>` 就报错的假泛型。
- **底层读原语一起收紧**：MachOKitUI 自己实现了 `Readable`，收紧会直接破坏它；而且 `ReadingContext` 本身就建在这些原语上。
- **测试保持调用旧接口**：靠转发间接覆盖唯一实现，测试构建会冒上千条废弃警告，0.23.0 删除时还得回头改一遍。

## 影响

### 源码兼容性（source compatibility）

0.22.0 对外是**纯新增 + 废弃警告**，另有三处行为变化与一处协议形状变化：

- 废弃：传 `machO` 版与指针版的调用照常编译，只多一条警告。改法：

  ```swift
  // Before
  let name = try descriptor.name(in: machO)
  let fields = try metadata.fieldOffsets()

  // After
  let name = try descriptor.name(in: machO.context)
  let fields = try metadata.fieldOffsets(in: .inProcess)
  ```

- 行为变化（写进 0.22.0 Changelog）：
  - 原来走指针版的调用，遇到空指针或带 tag 的指针改为抛错，不再崩溃；错误类型从 `NullPointerError` 变成 `UnsafeRawPointer.Error.initFailed`。
  - 指针版遇到符号引用时返回 `.symbol`，不再 `fatalError()`。
  - 自己实现了 `MachOBindRebaseResolving` 的包装类型（MachOKitUI 的 `MachOFileSource`）在间接指针上开始走 rebase 表，读出的是正确的目标，而不是 fixup 编码。
- 协议形状：旧 requirement 移出协议声明。外部类型如果遵循了这些协议并**只**实现了旧 requirement（仓库外没有已知实例），它的实现不再参与分派；`ReadingContext` 新增的 `cacheScope` requirement 带默认值，外部 context 不需要改。
- `NamedDumpable` / `ConformedDumpable` 的 requirement 换成 `ReadingContext` 参数：外部遵循者需要改（仓库外没有已知实例）；外部调用者走废弃转发，不受影响。
- `ResilientWitness.implementationAddress(in: machO)` 改名，旧名字带 `renamed:`，Xcode 可以一键修复。

0.23.0 删除旧接口，属于破坏性变更，届时下游应已迁完。

### ABI 兼容性（条件项）

不适用 —— 本库以 SPM 源码分发，使用方每次重新编译。

### 下游影响

本仓库内：几乎所有 target。生产代码约 333 处 ABI 调用、上层 61 个接口的调用方，测试约 1000 处调用、baseline 生成器约 190 处。

下游仓库：

- **RuntimeViewer**（`next` 分支跟随 MachOSwiftSection `next`）：3 处 ABI 调用 + `SymbolicDemangler` 1 处；FindNavigator 分支另 4 处。0.22.0 进入 `next` 之后即可迁。
- **MachOKitUI**（`from: "0.19.0"`）：24 处，需要 0.22.0 发布后迁。它遵循的 `Readable` / `MachOSwiftSectionRepresentableWithCache` / `MachOBindRebaseResolving` 不受影响。
- **swift-decompiler**（跟随 `main`）：9 处 + 3 处 `dumpName(using:in:)`，0.22.0 发布后迁。
- REAgent、RuntimeViewer `main`：钉死在 0.15.2，不受影响，也不在本次范围。

### 文档与示例

- `Documentations/Internal/ReadingContextAbstraction.md`：第 4 阶段落地；缓存范围一节；更正「`runtimePointer(at:)` 不是 requirement」的过时说法；用法示例改成 `ReadingContext`。
- `AGENTS.md`：新读取接口只写 `ReadingContext` 版；模块描述里提到的接口形态同步。
- `Documentations/Internal/Modules/` 下涉及的模块页、`Documentations/README.md` 索引、`Documentations/Glossary.md`（登记「缓存范围 / cache scope」）、`Documentations/Internal/ProjectEvolutionLog.md`、`Changelogs/0.22.0.md`。
- `AgentPlugins/swift-section/`：CLI 不变，不需要改。

## API 演进与废弃策略

- 被替代的旧 API 标 `@available(*, deprecated, message:)` 保留，函数体只转发，不再有自己的逻辑。改名的一处用 `renamed:`。
- 废弃期一个版本：0.22.0 标废弃，0.23.0 删除。删除前在各下游仓库提 PR 迁移调用点。
- 不需要 semver major 跃迁：0.x 阶段按惯例在 minor 版本做破坏性变更。

## 落地步骤

**PR 1：ABI 层**（进 `next`）

1. 第 1 节的四处修复，各带一个修复前失败的回归测试。
2. 补齐缺 `ReadingContext` 版的接口。
3. 旧接口改成转发并标废弃；旧 requirement 移出协议声明；删除具体类型里手写的旧实现。
4. 以废弃警告为清单，迁移 `Sources/` 里全部 ABI 调用点，直到零新增警告。
5. 迁移测试与 baseline 生成器，新增转发套件。
6. 验证：`swift test --skip IntegrationTests` 原始退出码为 0；`regen-baselines` 之后 `__Baseline__/` 零 diff；渲染 A/B 三条路径逐字节一致；三条路径耗时不劣于基线。

**PR 2：缓存范围与上层 61 个接口**（进 `next`）

7. `ReadingContextCacheScope`、`MachOContext` / `InProcessContext` 的实现、`SharedCacheKey` 的 identifier 入口；两个缓存按 scope 选层，带测试（同一镜像经 `machO` 与经 context 命中同一条目、驱逐一致、第三方 context 不缓存）。
8. 上层 61 个接口：`public` 的加 `ReadingContext` 版并废弃旧版，`package` 的直接改签名；迁移调用点。
9. 同第 6 步的验证。

**文档**：随各自 PR 同批更新第「文档与示例」节列出的文件，本提案原地更新。

**发布与下游**

10. 0.22.0 发布（Changelog 写明废弃清单与三处行为变化）。
11. RuntimeViewer、MachOKitUI、swift-decompiler 各提迁移 PR。
12. 0.23.0：删除全部废弃转发与转发套件，更新覆盖率登记表（13 个指针版初始化器键），本提案决策日志补一行。

**收尾判断**（落地时写进决策日志）：是否需要配套实现说明（预期更新 `ReadingContextAbstraction.md` 即可，不另写）；新术语「缓存范围」登记进术语表。

## 当前进度（2026-09-30）

**一句话**：实现、正确性验收与性能验收都已完成（落地步骤 1–9），分支 `refactor/reading-context-migration` 已推送，基于 `next` @ `f7c189b8`，以一个 PR 合入 `next`。

| commit | 内容 |
|---|---|
| `b00fda81` | 本提案 |
| `a23d52b6` | ABI 层：`ReadingContext` 形式成为唯一实现，传 `machO` 与指针的形式改为废弃转发；五处分歧修复及回归测试 |
| `9c75c40f` | `Sources/` 与测试、baseline 生成器的全部调用点改走 context 形式 |
| `9827e1d0` | 删掉迁移后变成「自己比自己」的 fixture 断言 |
| `17d101e6` | `ReadingContext.cacheScope`；上层 61 个只读接口迁移；AGENTS.md、实现说明、术语表 |
| `3d84ee05` | 缓存范围的镜像身份不装箱（`SharedCacheKey` 恢复原样） |
| `1cf72537` 及之后 | 验证数据与本节 |

这些 commit 是在 JHs-Mac-Studio-Ultra 上按会话记录重建的：原分支（`bd670206` 到 `b7c99dbf`）只存在于公司那台机器上，没有推送。重建时按时间顺序重放记录里的每次编辑，并逐一核对记录中「编辑前的完整文件」；重建后各 commit 的文件清单与行数统计和原 commit 一致（例如 ABI 那次 86 个源文件 +1959 / −2800、测试去重那次 24 个文件 +75 / −206）。

**正确性验收**：
- 全量测试：公司机器（Xcode 26 工具链）2157 个 / 410 个套件，只有那台机器既有的两条 `MultiPayloadEnumDescriptorCacheTests` 失败；Ultra（Swift 6.4，fixture 用 Xcode 26.6 编）同样 2157 个 / 410 个，全部通过，原始退出码 0。零新增警告。
- 渲染 A/B：公司机器 90 对、Ultra 84 对（CLI 两条腿 60 对，MachOImage 腿 24 对）逐字节一致；Ultra 上计时所用的 26.6 cache 与 iOS 26.5 模拟器 SwiftUI 输出两侧也一致。

**性能验收**（Ultra，release，每组按「基线、候选、候选、基线」运行，SwiftUI）：三条路径都没有变慢。

| 路径 | 基线 | 候选 | 结论 |
|---|---|---|---|
| dyld cache 里的 `MachOFile`（26.6）`dump` | 580.42G 条指令，user 31.82 秒 | 577.63G，31.62 秒 | 指令 −0.48% |
| 同上 `interface` | 740.22G，40.81 秒 | 738.64G，40.85 秒 | 指令 −0.21% |
| 磁盘上的 `MachOFile`（iOS 26.5 模拟器）`dump` | user 30.51 秒 | 30.57 秒 | +0.2% |
| 同上 `interface`（各 4 次） | user 38.75 秒（38.57–38.93） | 38.97 秒（38.62–39.45） | +0.57%，区间重叠 |
| MachOImage 与本进程（`RenderingVerificationTests`） | user 504.2 秒 | 498.2 秒 | −1.2% |

指标以 `/usr/bin/time -l` 的退休指令数为主（同一侧两次相差 0.03%–0.3%），模拟器路径的内核时间占一半、指令数跟着抖，改看 user 时间；MachOImage 腿的指令数只统计了 `swift test` 驱动进程本身，也只看 user 时间。公司那台机器上测出的 MachOImage 腿「多 2.5%」是噪声（那台机器上基线两次之间就差 3%）。

**换机器时的注意事项**：
- Xcode 27 的机器上，SymbolTestsCore fixture 要用 Xcode 26.6 编（`DEVELOPER_DIR=…/Xcode-26.6.0.app/Contents/Developer`，ad-hoc 签名），否则 `MachOSwiftSectionTests` 会有约 195 个 offset / layout 与 baseline 不符，那是编译器版本带来的漂移，不是回归。
- 渲染 A/B 脚本的归档 cache 目录写死为 `26.6.2` 与 `15.5`，缺哪个就静默少一条腿（Ultra 上只有 `15.5`）。脚本自己会跑 `swift build -c release` 与 `swift test -c release`，不经 `queued-build`；在限流的 10 核 Mac Studio 上，`queued-build` 给预构建加的 `--jobs 8` 会变成编译器参数 `-num-threads 8`，脚本的那次构建于是两侧并行、绕过队列地全量重编。

**不在本 PR、另开分支处理**（用户已决定）：

1. 本批发现的既有问题：`FunctionTypeMetadata.extendedFlags(in:)` 与 `EnumMetadataProtocol.payloadSize(descriptor:in:)` 从泛型 `readElement` 直接返回 Optional，按 Optional 的内存形状多读一个字节，`FunctionTypeMetadataTests` 时好时坏就是它；`ContextDescriptorWrapper.resolve(at:in:) -> Self?` 出错时用 `print` 写 stdout，违反日志规则，也会弄脏 CLI 的输出。
2. 渲染 A/B 脚本加 `--skip-build`：直接使用预先经 `queued-build` 构建好的产物，脚本自己不再构建。

**合入之后**：落地时分配编号（`draft-` → `NNNN-`，同步两个索引与进度账本的节号），状态改为 Implemented；0.22.0 的 Changelog 写明废弃清单与三处行为变化；给 RuntimeViewer（`next`）、MachOKitUI、swift-decompiler 提迁移 PR；0.23.0 删除全部废弃转发、`DeprecatedReadingFormsTests`，以及覆盖率登记表里 13 个指针版初始化器的键。

## 决策日志

| 日期 | 变更 | 说明 |
|------|------|------|
| 2026-09-30 | Created as Draft | 用户原话：「把传递machO和直接用指针解析的接口全部迁移至ReadingContext，旧接口全部弃用」 |
| 2026-09-30 | 旧接口废弃后转发到 `ReadingContext` 版，实现只留一份 | 用户：「弃用旧接口后旧接口的实现直接调用ReadingContext接口，确保实现只有1份」 |
| 2026-09-30 | 范围：ABI 层 + 上层 61 个纯读取接口 | 用户选定；否决「只迁 ABI 层」与「上层全部迁移」（后者要推翻 0018 的定位） |
| 2026-09-30 | 0.22.0 标废弃，0.23.0 删除，删除前迁下游 | 用户选定，与 0018 的废弃惯例一致；否决「只废弃不定删除时间」「下游迁完再删」 |
| 2026-09-30 | 测试与 baseline 生成器全部改走 `ReadingContext`，另留转发套件 | 用户选定；否决「测试保持不动」 |
| 2026-09-30 | 天生离不开 Mach-O / 本进程的接口保留不废弃 | 用户选定；否决「运行时调用类也改 context 版」「连底层原语一起废弃」 |
| 2026-09-30 | `ReadingContext` 新增缓存范围声明，只暴露缓存身份 | 用户选定；否决「直接暴露底层 Mach-O」「不改协议、内部转型」 |
| 2026-09-30 | 性能：三条路径都不许变慢，修到持平才合入 | 用户选定；否决「本进程路径允许 10% 开销」「只验正确性」 |
| 2026-09-30 | 自定：先修 `ReadingContext` 版再切转发；旧 requirement 移出协议；`package` 接口直接改签名；`implementationAddress(in: machO)` 改名；`AsyncResolvable` 废弃；分两个 PR；AGENTS.md 改惯例 | 列在收尾确认清单里，用户确认 |
| 2026-09-30 | Accepted | 用户确认决策清单：「可以，然后开一个worktree开工」 |
| 2026-09-30 | In Progress | worktree `.worktrees/MachOSwiftSection-ReadingContextMigration`，分支 `refactor/reading-context-migration` |
| 2026-09-30 | 旧形式原地保留成转发，不集中到协议扩展 | 集中之后 `Pointer.resolve(from:in:).descriptor()` 这类链式调用在 `-> Self` 与 `-> Self?` 之间二义（实际撞上）；原地保留使重载解析与原来一致 |
| 2026-09-30 | 不用 `@_disfavoredOverload` 压 `-> Self?` 形式 | `ContextDescriptorWrapper` 等类型的 `-> Self?` 遇非法 kind 返回 nil，一律压成 `-> Self` 会改变旧调用方的结果 |
| 2026-09-30 | `PointerProtocol` 与 `RelativeIndirectType` 保留已废弃的旧 requirement，其余协议移除 | `Pointer` 同时遵循两者，两个协议扩展各给一份转发会让对 `Pointer` 的调用二义；requirement 与默认实现一起废弃只在调用处报警（Swift 6.3 探针实测） |
| 2026-09-30 | 约束扩展里的空指针 guard 放进私有 helper | 约束扩展内按名字调用同名 requirement 绑定到无约束 witness（探针实测），直接写成一行转发会跳过 guard |
| 2026-09-30 | 分歧修复：`Pointer` 查 rebase、`TypeMetadataRecord` 跳过 bind、`SymbolOrElementPointer` 剥 tag 后判空、`MangledName` 偏移统一基准、metadata 地址为 0 时抛错 | 以传 `machO` 版为准补进 `ReadingContext` 版；前三处各带修复前确认红过的回归测试 |
| 2026-09-30 | `InProcessContext` 的 tag 掩码只算一次、`advanceAddress` 剥 tag；`MachOContext` 去掉多余的预剥并改为不抛错 | 性能：避免每次读取都查当前镜像、遍历 load command；与旧的传 `machO` 版做完全相同的事 |
| 2026-09-30 | `NamedDumpable` / `ConformedDumpable` 的 requirement 换成收 `ReadingContext` 的形式，取名逻辑从各 Dumper 抽成被 dump 类型上的一份实现 | 取名只读数据；Dumper 自己的 `name` 与 `dumpName` 共用同一份，保持单一实现 |
| 2026-09-30 | `ProtocolConformance.typeName` 遇只剩 `typeAlias` 的符号时按 struct 处理（原指针版返回 nil） | 以传 `machO` 版（`Node.typeKind`）为准 |
| 2026-09-30 | 测试去重：改写后与已有 context 断言等价的重复断言删除，保留更强的一条 | 旧形式只是转发，改写后两边走同一路径，对比永远成立 |
| 2026-09-30 | `.image` 的载荷改为 `MachOTargetIdentifier`（原设计为 `AnyHashable`），`SharedCacheKey` 不加新入口；identifier 不是这个类型的读者经 context 读时不缓存 | 按原设计实现后，`SharedCacheKey(machO)` 被改成先装箱再拆箱，退回了 0053 专门去掉的每次查找一次堆分配（文件的 identifier 放不进 existential 内联缓冲），context 路径每次 memo 查找也要装箱一次。今天所有读者（含 MachOKitUI 的包装类型）都用 `MachOTargetIdentifier`，不缓存只影响假想中的读者，且只慢不错 |
| 2026-09-30 | 性能验收暂缓，换性能更好的机器再测 | 用户：「差不多先停下来，基准测试在这台电脑上可能不准，得换另一台性能更好的设备才看的出来，这台电脑内存不足和cpu占用过高了」。已有结果：cache 路径按退休指令数与 user 时间持平；模拟器文件路径 user 时间持平；MachOImage 腿 CPU 时间候选平均多 2.5%，而基线两次之间就差 3%，未定论。正确性验收（全量测试、90 对渲染 A/B）已完成，数据见 ProjectEvolutionLog。接手步骤见「当前进度」一节 |
| 2026-09-30 | 分支在 JHs-Mac-Studio-Ultra 上按会话记录重建并推送 | 原分支没有推送，公司那台机器随后关机。用户：「你在我这台设备重新写吧，自己对着对话记录抄」。重建后各 commit 的文件清单与行数统计与原 commit 一致，全量测试与渲染 A/B 在 Ultra 上重跑通过 |
| 2026-09-30 | 性能验收完成：三条路径都没有变慢 | 在 Ultra（28 核，负载低）上测：dyld cache 路径退休指令数 −0.48% / −0.21%，模拟器文件路径 user 时间 +0.2% / +0.57%（两侧区间重叠），MachOImage 与本进程路径 user 时间 −1.2%。公司机器上「多 2.5%」的读数判为噪声 |
| 2026-09-30 | 改为一个 PR 合入（原计划拆成 ABI 层与缓存范围加上层接口两个） | 用户选定。ABI 层的文档改动是和第二部分一起提交的，拆开要重排 commit；现有 commit 已按逻辑分开，评审时可逐个看 |
| 2026-09-30 | 既有的 Optional 读取陷阱与 `print` 写 stdout 另开分支修，A/B 脚本加 `--skip-build` 也另开分支 | 用户选定；本 PR 只做迁移，保持聚焦 |
