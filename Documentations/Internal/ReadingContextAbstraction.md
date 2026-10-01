# ReadingContext Abstraction

## Overview

This document describes the design and implementation of the `ReadingContext` protocol abstraction, which unifies memory reading operations across different data sources (MachO files and in-process memory).

## Problem Statement

The current codebase has two separate APIs for reading data:

1. **External Mode (MachO files)**:
   ```swift
   func resolve(from offset: Int, in machO: MachO) throws -> Self
   ```

2. **InProcess Mode (direct memory)**:
   ```swift
   func resolve(from ptr: UnsafeRawPointer) throws -> Self
   ```

This duplication leads to:
- Code duplication when writing generic functions
- Inability to write a single generic function that works with both modes
- Maintenance burden when adding new functionality

## Goals

1. **Unified API**: Provide a single generic API that works with both MachO files and in-process memory
2. **Backward Compatibility**: Keep existing APIs unchanged for existing code
3. **Type Safety**: Use associated types to ensure compile-time type checking
4. **Match Swift Runtime Design**: Follow similar patterns used in the official Swift runtime (see `MemoryReader` in swift/Remote/MemoryReader.h)

## Architecture Design

### Protocol Hierarchy

```
┌─────────────────────────────────────────────────────────────────────┐
│                         ReadingContext                               │
│  (Unified abstraction for MachO and UnsafeRawPointer reading)       │
├─────────────────────────────────────────────────────────────────────┤
│  associatedtype Runtime: RuntimeProtocol                             │
│  associatedtype Address                                              │
│                                                                      │
│  func readElement<T>(at: Address) throws -> T                        │
│  func readWrapperElement<T: LocatableLayoutWrapper>(at:) throws -> T │
│  func readString(at: Address) throws -> String                       │
│  func advanceAddress(_: Address, by: Int32) -> Address               │
└─────────────────────────────────────────────────────────────────────┘
                    │                              │
                    ▼                              ▼
┌───────────────────────────────┐    ┌─────────────────────────────────┐
│      MachOContext<MachO>      │    │       InProcessContext          │
├───────────────────────────────┤    ├─────────────────────────────────┤
│  Runtime = RuntimeTarget64    │    │  Runtime = InProcess            │
│  Address = Int (file offset)  │    │  Address = UnsafeRawPointer     │
│                               │    │                                 │
│  Reads via MachO.readElement  │    │  Direct memory load             │
│  Supports dyld shared cache   │    │  Zero-copy access               │
└───────────────────────────────┘    └─────────────────────────────────┘
```

### RuntimeProtocol Extension

The existing `RuntimeProtocol` is extended to support pointer type aliases:

```swift
public protocol RuntimeProtocol {
    associatedtype StoredPointer: FixedWidthInteger & UnsignedInteger
    associatedtype StoredSignedPointer: FixedWidthInteger
    associatedtype StoredSize: FixedWidthInteger & UnsignedInteger
    associatedtype StoredPointerDifference: FixedWidthInteger & SignedInteger

    static var pointerSize: Int { get }
}

// New: InProcess runtime for direct memory access
public enum InProcess: RuntimeProtocol {
    public typealias StoredPointer = UInt
    public typealias StoredSignedPointer = Int
    public typealias StoredSize = UInt
    public typealias StoredPointerDifference = Int

    public static var pointerSize: Int { MemoryLayout<UInt>.size }
}
```

### Key Components

#### 1. ReadingContext Protocol

The core abstraction that unifies different memory reading modes:

```swift
public protocol ReadingContext: Sendable {
    associatedtype Runtime: RuntimeProtocol
    associatedtype Address

    func readElement<T>(at address: Address) throws -> T
    func readWrapperElement<T: LocatableLayoutWrapper>(at address: Address) throws -> T
    func readString(at address: Address) throws -> String
    func advanceAddress(_ address: Address, by offset: Int32) -> Address
}
```

#### 2. MachOContext

Wraps a MachO file/image for external reading:

```swift
public struct MachOContext<MachO: MachORepresentableWithCache & Readable>: ReadingContext {
    public typealias Runtime = RuntimeTarget64
    public typealias Address = Int

    public let machO: MachO

    // Delegates to MachO.readElement, MachO.readString, etc.
}
```

#### 3. InProcessContext

Provides direct memory access for in-process reading:

```swift
public struct InProcessContext: ReadingContext {
    public typealias Runtime = InProcess
    public typealias Address = UnsafeRawPointer

    // Direct memory load via UnsafeRawPointer
}
```

### Integration with Existing APIs

#### Resolvable Protocol Extension

```swift
extension Resolvable {
    // New unified API
    public static func resolve<Context: ReadingContext>(
        at address: Context.Address,
        in context: Context
    ) throws -> Self
}
```

#### RelativePointerProtocol Extension

```swift
extension RelativeDirectPointerProtocol {
    // New unified API
    public func resolve<Context: ReadingContext>(
        from address: Context.Address,
        in context: Context
    ) throws -> Pointee
}
```

## Usage Examples

Since the single-implementation pass (below, 2026-09-30) the `ReadingContext` form is the only one to call. The Mach-O form (`in: machO`) and the pointer form (no reader argument) are deprecated forwarders until 0.23.0.

```swift
// A Mach-O file or image: pass its context.
let machO: MachOFile = ...
let name = try descriptor.name(in: machO.context)
let pointee = try descriptor.layout.name.resolve(
    at: descriptor.offset(of: \.name),
    in: machO.context
)

// Process memory: pass the in-process context.
let inProcessName = try pointerDescriptor.name(in: .inProcess)
```

### Generic Functions

The key benefit is writing generic functions that work with both modes:

```swift
func readProtocolDescriptor<Context: ReadingContext>(
    at address: Context.Address,
    in context: Context
) throws -> ProtocolDescriptor {
    try ProtocolDescriptor.resolve(at: address, in: context)
}

// Works with MachO files
let desc1 = try readProtocolDescriptor(at: offset, in: machO.context)

// Works with in-process memory
let desc2 = try readProtocolDescriptor(at: ptr, in: InProcessContext.shared)
```

## Comparison with Swift Runtime

This design is inspired by the Swift runtime's `MemoryReader` abstraction:

| Swift Runtime (C++) | This Project (Swift) |
|---------------------|----------------------|
| `MemoryReader` | `ReadingContext` |
| `InProcessMemoryReader` | `InProcessContext` |
| `CMemoryReader` | `MachOContext` |
| `RemoteAddress` | `Context.Address` |
| `RuntimeTarget<8>` / `InProcess` | `RuntimeTarget64` / `InProcess` |

### Swift Runtime Reference

From `swift/include/swift/ABI/TargetLayout.h`:

```cpp
// InProcess: Pointer<T> = T* (real pointer)
struct InProcess {
    template <typename T>
    using Pointer = T*;
};

// External: Pointer<T> = StoredPointer (just a number)
template <typename Runtime>
struct External {
    template <typename T>
    using Pointer = StoredPointer;
};
```

From `swift/include/swift/Remote/MemoryReader.h`:

```cpp
class MemoryReader {
public:
    virtual bool readBytes(RemoteAddress address, uint8_t *dest, uint64_t size) = 0;
    virtual bool readString(RemoteAddress address, std::string &dest) = 0;
    // ...
};
```

## File Structure

```
Sources/
├── MachOReading/
│   └── Reading/
│       ├── ReadingContext.swift          # Core protocol
│       ├── MachOContext.swift            # MachO implementation
│       └── InProcessContext.swift        # InProcess implementation
├── MachOResolving/
│   └── Resolvable+ReadingContext.swift   # Resolvable extension
├── MachOPointers/
│   └── Protocol/
│       └── RelativePointerProtocol+ReadingContext.swift  # Pointer extension
└── MachOSwiftSection/
    └── Protocols/
        └── RuntimeProtocol.swift         # Extended with InProcess
```

## Migration Strategy

| Phase | Changes | Impact |
|-------|---------|--------|
| **1. Add Infrastructure** | Add `ReadingContext`, `MachOContext`, `InProcessContext` | Non-breaking |
| **2. Add Extensions** | Add `resolve(at:in:)` to `Resolvable` and pointer protocols | Non-breaking |
| **3. Gradual Migration** | New code uses `ReadingContext` API | Progressive |
| **4. Deprecation** | The `ReadingContext` form becomes the only implementation; the Mach-O and pointer forms are deprecated forwarders (0.22.0) and removed (0.23.0) | Done 2026-09-30, see below |

## Benefits

1. **Single Generic Implementation**: Write one function that works with all data sources
2. **Type Safety**: `Address` associated type prevents mixing incompatible addresses
3. **Extensibility**: Easy to add new context types (e.g., remote process, network)
4. **Backward Compatible**: Existing code continues to work unchanged
5. **Consistent with Swift Runtime**: Follows established patterns from Apple's implementation

## Model Coverage Completion Pass (2026-05)

When the abstraction landed, only ~15 of the ~60 files under
`Sources/ABI/MachOSwiftSection/Models/` that expose a MachO-based API also exposed a
`ReadingContext` overload — any caller adopting the abstraction had to drop back
to the MachO/InProcess APIs for the rest. A dedicated completion pass (original
spec: `docs/superpowers/specs/2026-05-02-reading-context-api-design.md`, now in
git history only) added the missing overloads across all of `Models/`, purely
additive, batched per sub-directory with one passing build per batch. The
mechanical substitution rule: every `machO.read*(offset: o)` becomes
`context.read*(at: try context.addressFromOffset(o))`, every
`pointer.resolve(from: o, in: machO)` becomes
`pointer.resolve(at: try context.addressFromOffset(o), in: context)`; local
`Int` offset arithmetic stays unchanged — the translation to a context-specific
address happens at the read site.

One capability was added to support runtime-pointer-returning methods
(`metadataAccessorFunction` is the canonical case, which only makes sense when
the reader is mapped into the current process):

```swift
extension ReadingContext {
    /// nil unless the context is mapped into the current process.
    public func runtimePointer(at address: Address) throws -> UnsafeRawPointer? { nil }
}
// InProcessContext returns the address itself; MachOContext returns
// machO.ptr + address when its MachO is a MachOImage, else nil.
```

Two deliberate decisions worth keeping in mind:

- `runtimePointer(at:)` is an **extension method with a default, not a protocol
  requirement** — keeping it out of the requirement set makes the addition
  non-breaking for external conformers. A future conformer that needs it must
  override the extension, not implement a witness. **Superseded:** it became a
  requirement with a default shortly after (commit `35162f69`), so a call
  through `any ReadingContext` reaches the concrete context's implementation;
  the default still keeps new conformers non-breaking.
- The `machO as? MachOImage` runtime cast inside `MachOContext`'s override is
  unavoidable: the generic parameter is unconstrained at the conformance site,
  so a `where MachO == MachOImage` specialization would not produce a witness.
  For `MachOContext<MachOFile>` the method returns `nil`, matching the
  pre-existing MachO overload's behavior.

## 单一实现与废弃（2026-09-30，第 4 阶段）

提案：[0057-reading-context-migration](../Evolutions/0057-reading-context-migration.md)。

每个读取接口原先最多有三份手写实现：按偏移读 Mach-O 的、用裸指针读本进程的、经 `ReadingContext` 读的。现在只剩 `ReadingContext` 那一份；另外两份是一行转发（`machO.context` / `InProcessContext.shared`），标 `@available(*, deprecated)`，0.23.0 删除。下面是代码里看不出来、下次维护会踩的几点。

### 转发必须原地保留

旧声明留在原来的类型上、原来约束的扩展里，只换函数体。把它们统一挪到协议扩展里看起来更整洁，但会改变重载解析：`Pointer` 原来在具体类型上有 `resolve(from:in:) -> Self`，挪走之后协议扩展里的 `-> Self` 与 `-> Self?` 两个形式同级，`resolve(from:in:).descriptor()` 这种链式调用直接二义（迁移时实际撞上）。也不能用 `@_disfavoredOverload` 硬压：`ContextDescriptorWrapper` 等类型的 `-> Self?` 形式遇到非法 kind 返回 nil 而不是抛错，一律压成 `-> Self` 会悄悄改变旧调用方拿到的结果。

### 旧 requirement 的去留

旧形式大多从协议 requirement 里移除，只作为扩展上的废弃转发保留。转发调用的是 `ReadingContext` 那条 requirement，分派结果不变：`TypeContextDescriptorProtocol` 覆盖 `genericContext` 的那条链路照样走到 16 字节的 type generic context header。例外是 `PointerProtocol` 与 `RelativeIndirectType`：`Pointer` 同时遵循两者，两个互不相关的协议扩展各给一份转发，会让对 `Pointer` 的每次调用都二义，所以这两个协议把旧形式留作 requirement，requirement 与默认实现一起标废弃。Swift 6.3 实测：只废弃默认实现、不废弃 requirement，每个依赖该默认实现的遵循类型都报 “deprecated default implementation is used to satisfy …”；两者一起标，只在调用处报。

### 约束扩展里的空指针 guard

在 `where Pointee: OptionalProtocol` 这类约束扩展里，按名字调用一个同时是协议 requirement 的方法，绑定的是 requirement，也就是无约束的 witness，而不是旁边那个约束重载。所以转发如果写成 `try resolve(at: offset, in: machO.context)`，就会跳过空指针 guard，去读空指针自己所在位置的字节。guard 因此放在一个私有 helper 里，由 `ReadingContext` 入口和各个转发共同调用（`RelativeDirectPointerProtocol` 等四个协议，以及 `PointerProtocol`、`SymbolOrElementPointer`）。

### 收成一份时修掉的分歧

`ReadingContext` 那份实现以前有几处漏掉了传 `machO` 那份做的事，现在补齐。回归测试在 `Tests/MachOSwiftSectionTests/ReadingContextRelocationTests.swift`，三条在修复前都确认红过：

- `Pointer.resolve(at:in:)` 先查 rebase 表：文件里 rebase 槽存的是 chained fixup 编码，不是地址。
- `TypeMetadataRecord.contextDescriptor(in:)` 对槽位是 bind 的间接记录返回 nil（iOS 26.5 模拟器 `libswiftSynchronization` 里那条指向 `Swift.Optional` 的记录）。
- `SymbolOrElementPointer` 的可选元素先剥 tag 再判空。

另外两处没有专门的回归测试：`MangledName` 的所有偏移都以起始地址为基准，带 tag 的起点不再算错长度；metadata 地址为 0 时，本进程读取与原来的指针版一样抛错。bind / rebase 判定一律走 `context.bindRebaseResolver`，不再用 `as? MachOFile`，所以实现了 `MachOBindRebaseResolving` 的包装类型（MachOKitUI 的 `MachOFileSource`）也能拿到。旧指针版因此多了两处行为变化：遇到空指针或只带 tag 的指针会抛错而不是崩溃，遇到符号引用会返回 `.symbol` 而不是 `fatalError()`。

### 性能

`InProcessContext` 的 tag 掩码在进程里只算一次；`UnsafeRawPointer.stripPointerTags()` 每次调用都要找当前镜像、遍历一遍 load command。`advanceAddress` 也会剥 tag，与旧指针版的 `resolveDirectOffset(from:)` 一致。`MachOContext.addressFromVirtualAddress` 不再在 `resolveOffset(at:)` 之前多剥一次，因为 `MachOFile.fileOffset(of:)` 与 `MachOImage.resolveOffset(at:)` 自己会剥；它与 `addressFromOffset`、`offsetFromAddress` 一起声明成不抛错。

### 缓存范围：上层只读接口也收成一份

上层有一批接口只读数据，却因为要按镜像缓存而离不开 `machO`：`SymbolicDemangler` 的 `demangleType` / `demangleContext`、SwiftDeclaration 的 `typeName` / `protocolName`、`GenericContext+Dump` 等。`ReadingContext` 原先说不出自己读的是哪个镜像，所以 `SymbolicDemangler` 的 context 入口干脆不走缓存。现在 `ReadingContext` 多了一条带默认值的 requirement `cacheScope`：`MachOContext` 答 `.image(identifier:)`，`InProcessContext` 答 `.process`，其余一律 `.uncached`。反混淆 memo 与节点驻留池按它选层，这批接口因此也收成了只收 context 的一份。

- **同一个镜像只有一个键**：`.image` 带的就是 reader 的 `MachOTargetIdentifier`，两个缓存用现成的 `SharedCacheKey(identifier:)` 建键，与 `SharedCacheKey(machO)` 得到的是同一个键。经 reader 和经 context 存进去的条目是同一条，`SymbolicDemangler.removeCache(for:)` 与驱逐注册表照常认领、清理。
- **身份不装箱**：每次 memo 查找都要问一次 `cacheScope`。文件的 identifier 是路径加 UUID，放不进 existential 的 24 字节内联缓冲，包成 `AnyHashable` 每次都要堆分配，而 `SharedCacheKey` 当初就是为了去掉这次分配才写成现在的样子（见 [Modules/MachOCaches.md](Modules/MachOCaches.md)「键」一节）。所以 `.image` 的载荷是具体类型 `MachOTargetIdentifier`，不是 `AnyHashable`。代价是 identifier 不是这个类型的读者经 context 读时不缓存（`MachOContext` 答 `.uncached`），只慢不错；今天的读者（`MachOFile`、`MachOImage`、MachOKitUI 的包装类型）全都是这个类型。
- **默认不缓存是安全边界，不是省事**：全进程那层按偏移做键，只有地址是绝对地址时两个镜像才不会撞。一个以文件偏移为地址的第三方 context 如果落进去，会把 A 镜像的解析结果当成 B 镜像的返回。
- **只暴露缓存身份，不暴露 Mach-O**：`.image` 带的是 reader 的 `identifier`，不是 reader 本身，调用方拿它做不了符号查询或 `as? MachOFile`，延续提案 0018「`ReadingContext` 只管读」的定位。`SymbolicDemangler` 查符号仍走它私有的 `SymbolLookupContext` 转型。

### 这次没动的已知缺口

- `ValueMetadataProtocol.descriptor(in:)` 等经绝对指针读取的字段，对 dyld shared cache 里的镜像，偏移口径不对：`fileOffset(of:)` 给的是 cache 文件内的偏移，读取却按 `unslidVirtualAddress - sharedRegionStart` 来理解。三种形式本来就一样，这次既没修好也没弄坏。
- `EnumMetadataProtocol.payloadSize` 的返回类型是 `StoredSize?`，泛型读取按 9 字节的 `Optional<UInt64>` 去读，和 AGENTS.md 里的 Optional 读取陷阱同类。迁移之后已单独修复并验证，同时修了 `FunctionTypeMetadata.extendedFlags` 与 `SwiftClassObjectIndex` 读 class flags 的两处同类写法，见 [ProjectEvolutionLog.md](ProjectEvolutionLog.md)「Optional 读取多读一个 tag byte」一节。

## Future Considerations

1. **Async Support**: Add `AsyncReadingContext` for async reading operations
2. **Caching**: Add optional caching layer to `ReadingContext`
3. **Remote Reading**: Add `RemoteProcessContext` for reading from other processes
4. **32-bit Support**: `MachOContext` could dynamically select `RuntimeTarget32` based on MachO header

## References

- Swift Runtime: `swift/include/swift/ABI/TargetLayout.h`
- Memory Reader: `swift/include/swift/Remote/MemoryReader.h`
- Metadata Reader: `swift/include/swift/Remote/MetadataReader.h`
- Reflection Context: `swift/include/swift/RemoteInspection/ReflectionContext.h`
