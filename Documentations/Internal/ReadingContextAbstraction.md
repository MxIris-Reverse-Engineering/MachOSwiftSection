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

### Existing API (Unchanged)

```swift
// MachO file reading - continues to work
let machO: MachOFile = ...
let name = try descriptor.layout.name.resolve(
    from: descriptor.offset(of: \.name),
    in: machO
)

// Direct pointer reading - continues to work
let ptr: UnsafeRawPointer = ...
let name = try descriptor.layout.name.resolve(from: ptr)
```

### New Unified API

```swift
// Using MachO context
let machO: MachOFile = ...
let context = machO.context  // MachOContext<MachOFile>
let name = try descriptor.layout.name.resolve(
    from: descriptor.offset(of: \.name),
    in: context
)

// Using InProcess context
let ptr: UnsafeRawPointer = ...
let context = InProcessContext.shared
let name = try descriptor.layout.name.resolve(from: ptr, in: context)
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
| **4. Deprecation** | Mark old APIs as `@available(*, deprecated)` | Future |

## Benefits

1. **Single Generic Implementation**: Write one function that works with all data sources
2. **Type Safety**: `Address` associated type prevents mixing incompatible addresses
3. **Extensibility**: Easy to add new context types (e.g., remote process, network)
4. **Backward Compatible**: Existing code continues to work unchanged
5. **Consistent with Swift Runtime**: Follows established patterns from Apple's implementation

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
