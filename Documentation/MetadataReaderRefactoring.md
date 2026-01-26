# MetadataReader Refactoring Plan

## Problem

`MetadataReader.swift` (888 lines) contains two nearly identical implementations:

1. **MachO version** (lines 12-394): Uses `in machO: MachO` parameter
2. **InProcess version** (lines 396-777): Uses `from ptr: UnsafeRawPointer`

This duplication leads to:
- ~400 lines of duplicated logic
- Maintenance burden (changes must be made twice)
- Risk of implementations diverging

## Solution

Use the `ReadingContext` abstraction to unify both implementations into a single generic version.

## Key Differences to Unify

### 1. Address Types

```swift
// MachO version
let offset = requirement.offset(of: \.content)
let mangledName = try relativeDirectPointer.resolve(from: offset, in: machO)

// InProcess version
let ptr = try requirement.pointer(of: \.content)
let mangledName = try relativeDirectPointer.resolve(from: ptr)
```

**Unified with ReadingContext:**
```swift
func resolve<Context: ReadingContext>(
    from address: Context.Address,
    in context: Context
) throws -> MangledName
```

### 2. Context Passing

```swift
// MachO version
private static func demangle<MachO: MachOSwiftSectionRepresentableWithCache>(
    for mangledName: MangledName,
    kind: MangledNameKind,
    in machO: MachO
) throws -> Node

// InProcess version
private static func demangle(
    for mangledName: MangledName,
    kind: MangledNameKind
) throws -> Node
```

**Unified with ReadingContext:**
```swift
private static func demangle<Context: ReadingContext>(
    for mangledName: MangledName,
    kind: MangledNameKind,
    in context: Context
) throws -> Node
```

### 3. Symbolic Reference Resolution

The `symbolicReferenceResolver` closure differs in how it resolves addresses:

```swift
// MachO version
let offset = lookup.offset
let context = try RelativeDirectPointer<...>(relativeOffset: relativeOffset)
    .resolve(from: offset, in: machO)

// InProcess version
let ptr = try UnsafeRawPointer(bitPattern: offset)
let context = try RelativeDirectPointer<...>(relativeOffset: relativeOffset)
    .resolve(from: ptr)
```

**Unified with ReadingContext:**
```swift
let address = context.addressFromOffset(lookup.offset)  // New helper method
let resolved = try RelativeDirectPointer<...>(relativeOffset: relativeOffset)
    .resolve(from: address, in: context)
```

## Required Changes

### 1. Extend ReadingContext Protocol

Add a method to convert offset to address:

```swift
public protocol ReadingContext: Sendable {
    // ... existing methods ...

    /// Converts an integer offset to this context's address type.
    /// - For MachOContext: returns the offset as-is (Int)
    /// - For InProcessContext: converts to UnsafeRawPointer
    func addressFromOffset(_ offset: Int) -> Address
}

extension MachOContext {
    public func addressFromOffset(_ offset: Int) -> Int {
        return offset
    }
}

extension InProcessContext {
    public func addressFromOffset(_ offset: Int) -> UnsafeRawPointer {
        return UnsafeRawPointer(bitPattern: offset)!
    }
}
```

### 2. Create Generic MetadataReader

```swift
extension MetadataReader {
    // Single generic implementation
    package static func demangleType<Context: ReadingContext>(
        for mangledName: MangledName,
        in context: Context
    ) throws -> Node {
        try MetadataReaderCache.shared.demangleType(for: mangledName, in: context)
    }

    private static func demangle<Context: ReadingContext>(
        for mangledName: MangledName,
        kind: MangledNameKind,
        in context: Context
    ) throws -> Node {
        let symbolicReferenceResolver: DemangleSymbolicReferenceResolver = { kind, directness, index -> Node? in
            let lookup = mangledName.lookupElements[index]
            let address = context.addressFromOffset(lookup.offset)
            // ... unified logic using context ...
        }
        // ...
    }
}
```

### 3. Convenience Wrappers (Backward Compatibility)

Keep the existing API signatures as thin wrappers:

```swift
extension MetadataReader {
    // MachO convenience (calls generic version)
    package static func demangleType<MachO: MachOSwiftSectionRepresentableWithCache>(
        for mangledName: MangledName,
        in machO: MachO
    ) throws -> Node {
        try demangleType(for: mangledName, in: machO.context)
    }

    // InProcess convenience (calls generic version)
    package static func demangleType(for mangledName: MangledName) throws -> Node {
        try demangleType(for: mangledName, in: InProcessContext.shared)
    }
}
```

## Estimated Impact

| Metric | Before | After |
|--------|--------|-------|
| Total lines | ~888 | ~500 |
| Duplicated logic | ~400 lines | 0 lines |
| API compatibility | N/A | 100% backward compatible |

## Migration Steps

1. **Phase 1**: Add `addressFromOffset` to `ReadingContext` protocol
2. **Phase 2**: Create generic versions of core methods (`demangle`, `buildContextMangling`, etc.)
3. **Phase 3**: Convert existing methods to call generic versions
4. **Phase 4**: Mark old internal methods as deprecated
5. **Phase 5**: Remove deprecated code in future release

## Special Considerations

### MangledName with Lookup Elements

The `MangledName` type stores offsets that need to be converted to addresses:

```swift
struct MangledName {
    var lookupElements: [LookupElement]
}

struct LookupElement {
    var offset: Int  // This is always an Int (pointer bit pattern)
}
```

For InProcess context, this offset is a pointer bit pattern that can be directly converted.
For MachO context, this offset is a file offset within the MachO.

The `addressFromOffset` method handles this conversion appropriately.

### Cache Handling

The `MetadataReaderCache` will need to support both context types:

```swift
func demangleType<Context: ReadingContext>(
    for mangledName: MangledName,
    in context: Context
) throws -> Node
```

The cache key can use the mangledName's elements, which are context-independent.

## Files to Modify

1. `Sources/MachOReading/Reading/ReadingContext.swift` - Add `addressFromOffset`
2. `Sources/MachOReading/Reading/MachOContext.swift` - Implement `addressFromOffset`
3. `Sources/MachOReading/Reading/InProcessContext.swift` - Implement `addressFromOffset`
4. `Sources/SwiftInspection/MetadataReader.swift` - Refactor to use generic context
