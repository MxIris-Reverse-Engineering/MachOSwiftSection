# ReadingContext API Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `ReadingContext`-based overloads to every method in `Sources/MachOSwiftSection/Models/` that currently exposes only the MachO/InProcess API pair, plus the small `runtimePointer(at:)` extension needed to express runtime-pointer-returning methods.

**Architecture:** Mechanical mirroring per the substitution table in the design doc. New overloads sit in `// MARK: - ReadingContext Support` sections. Existing MachO/InProcess code is left untouched. One small protocol extension (`runtimePointer(at:)`) is added to `MachOReading` to support `metadataAccessorFunction`.

**Tech Stack:** Swift 6.2+ / Xcode 26.0+, Swift Package Manager. Build via `swift build`, test via `swift test`. Reference doc: `docs/superpowers/specs/2026-05-02-reading-context-api-design.md`.

---

## Working agreements (apply to every task)

These are rules the implementer follows for every batch — the per-task steps below assume these:

- **Reuse the per-method pattern** documented in the design doc, section "Pattern for the common case". The substitution table is the contract; do not invent a new style.
- **Place new overloads in a dedicated `// MARK: - ReadingContext Support` extension** at the bottom of the file. If the file already has one, append to it.
- **Do not modify existing MachO or InProcess code** in any task except Task 1.
- **Mirror the MachO overload exactly:** same return type, same nullability, same `throws`, same parent helpers (e.g. `try someMethod(in: context)` instead of `try someMethod(in: machO)`).
- **Local offset arithmetic on `Int`** (`currentOffset.offset(of:)`, `currentOffset.align(to:)`, `currentOffset += ...`) stays untouched. Only the *read site* uses `try context.addressFromOffset(currentOffset)`.
- **For partial files** (already have some `<Context: ReadingContext>` methods), add only the methods that are *missing* relative to the file's MachO API surface. Do not duplicate existing ReadingContext methods.
- **Build after every batch:** `swift package update && swift build 2>&1 | xcsift`. Must succeed before commit.
- **Commit message convention:** `feat(MachOSwiftSection): add ReadingContext API for <area>` for content batches; `feat(MachOReading): add runtimePointer extension` for Task 1.
- **One commit per batch.** Do not stack multiple batches in one commit.

---

## Task 1: Add `runtimePointer(at:)` extension to `MachOReading`

**Files:**
- Modify: `Sources/MachOReading/ReadingContext/ReadingContext.swift` (append extension at bottom)
- Modify: `Sources/MachOReading/ReadingContext/MachOContext.swift` (append extension)
- Modify: `Sources/MachOReading/ReadingContext/InProcessContext.swift` (append extension)

- [x] **Step 1: Read the three target files end-to-end**

Read all three files completely so the extension placement matches existing style (imports, doc comment style, ordering).

```bash
# verify imports — MachOContext already imports MachOKit, so MachOImage is in scope
grep -n "import" Sources/MachOReading/ReadingContext/MachOContext.swift
```

- [x] **Step 2: Append default extension to `ReadingContext.swift`**

After the existing `extension ReadingContext { ... bindRebaseResolver default ... }` block, add:

```swift
extension ReadingContext {
    /// Converts a context-specific address to a runtime `UnsafeRawPointer`,
    /// when this context is mapped into the current process.
    ///
    /// - `InProcessContext`: returns the address itself (already a pointer).
    /// - `MachOContext<MachOImage>`: returns `machO.ptr + address`.
    /// - `MachOContext<MachOFile>` / other readers: returns `nil`.
    ///
    /// This is an extension method (not a protocol requirement) so adding
    /// new `ReadingContext` conformers does not become a breaking change.
    /// Concrete contexts that *can* vend a runtime pointer override this in
    /// their own files.
    public func runtimePointer(at address: Address) throws -> UnsafeRawPointer? {
        nil
    }
}
```

- [x] **Step 3: Append override to `MachOContext.swift`**

At the bottom of the file (after the `Convenience Extensions` MARK):

```swift
// MARK: - Runtime Pointer Support

extension MachOContext {
    /// Returns the runtime pointer for the given file offset when the
    /// underlying reader is a `MachOImage` mapped into the current process.
    /// Returns `nil` for `MachOFile` and other non-resident readers.
    public func runtimePointer(at address: Int) throws -> UnsafeRawPointer? {
        if let machOImage = machO as? MachOImage {
            return machOImage.ptr + UnsafeRawPointer.Stride(address)
        }
        return nil
    }
}
```

- [x] **Step 4: Append override to `InProcessContext.swift`**

At the bottom of the file:

```swift
// MARK: - Runtime Pointer Support

extension InProcessContext {
    /// In-process addresses are already runtime pointers, so this returns
    /// the address unchanged.
    public func runtimePointer(at address: UnsafeRawPointer) throws -> UnsafeRawPointer? {
        address
    }
}
```

- [x] **Step 5: Build**

```bash
swift package update && swift build 2>&1 | xcsift
```

Expected: build succeeds.

- [x] **Step 6: Commit**

```bash
git add Sources/MachOReading/ReadingContext/ReadingContext.swift \
        Sources/MachOReading/ReadingContext/MachOContext.swift \
        Sources/MachOReading/ReadingContext/InProcessContext.swift
git commit -m "feat(MachOReading): add runtimePointer extension for ReadingContext

Default returns nil. MachOContext returns machO.ptr + address when the
underlying reader is a MachOImage; InProcessContext returns the address
itself. Enables runtime-pointer-returning methods (e.g.
metadataAccessorFunction) to be expressed under the unified ReadingContext
abstraction without per-call type dispatch."
```

---

## Task 2: `Anonymous/`, `Module/`, `Extension/` (top-level Context wrappers)

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/Anonymous/AnonymousContext.swift`
- Modify: `Sources/MachOSwiftSection/Models/Module/ModuleContext.swift`
- Modify: `Sources/MachOSwiftSection/Models/Extension/ExtensionContext.swift`

These three files each have a MachO `init(descriptor:in:)` and an InProcess `init(descriptor:)`. Add a third `init(descriptor:in:Context)` mirroring the MachO version.

- [x] **Step 1: Add `init(descriptor:in:Context)` to `AnonymousContext.swift`**

Append at bottom:

```swift
extension AnonymousContext {
    public init<Context: ReadingContext>(descriptor: AnonymousContextDescriptor, in context: Context) throws {
        self.descriptor = descriptor
        var currentOffset = descriptor.offset + descriptor.layoutSize

        let genericContext = try descriptor.genericContext(in: context)
        if let genericContext {
            currentOffset += genericContext.size
        }
        self.genericContext = genericContext

        if descriptor.hasMangledName {
            let mangledNamePointerAddress = try context.addressFromOffset(currentOffset)
            let mangledNamePointer: RelativeDirectPointer<MangledName> = try context.readElement(at: mangledNamePointerAddress)
            self.mangledName = try mangledNamePointer.resolve(at: mangledNamePointerAddress, in: context)
            currentOffset += MemoryLayout<RelativeDirectPointer<MangledName>>.size
        } else {
            self.mangledName = nil
        }
    }
}
```

- [x] **Step 2: Add `init(descriptor:in:Context)` to `ModuleContext.swift`**

Append at bottom:

```swift
extension ModuleContext {
    public init<Context: ReadingContext>(descriptor: ModuleContextDescriptor, in context: Context) throws {
        self.descriptor = descriptor
        self.name = try descriptor.name(in: context)
    }
}
```

(`name(in: Context)` already exists on `NamedContextDescriptorProtocol`.)

- [x] **Step 3: Add `init(descriptor:in:Context)` to `ExtensionContext.swift`**

Append at bottom:

```swift
extension ExtensionContext {
    public init<Context: ReadingContext>(descriptor: ExtensionContextDescriptor, in context: Context) throws {
        self.descriptor = descriptor
        self.extendedContextMangledName = try descriptor.extendedContext(in: context)
        self.genericContext = try descriptor.genericContext(in: context)
    }
}
```

If `extendedContext(in: Context)` does not yet exist on `ExtensionContextDescriptor`, add it first inside `Sources/MachOSwiftSection/Models/Extension/ExtensionContextDescriptor.swift` mirroring the MachO version, then complete this step.

- [x] **Step 4: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 5: Commit**

```bash
git add Sources/MachOSwiftSection/Models/Anonymous/AnonymousContext.swift \
        Sources/MachOSwiftSection/Models/Module/ModuleContext.swift \
        Sources/MachOSwiftSection/Models/Extension/ExtensionContext.swift \
        Sources/MachOSwiftSection/Models/Extension/ExtensionContextDescriptor.swift
git commit -m "feat(MachOSwiftSection): add ReadingContext API for top-level contexts

Mirror the MachO init(descriptor:in:) overloads on AnonymousContext,
ModuleContext, and ExtensionContext under the ReadingContext abstraction."
```

---

## Task 3: `ContextDescriptor/` (`ContextProtocol.swift`, `ContextWrapper.swift`)

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/ContextDescriptor/ContextProtocol.swift`
- Modify: `Sources/MachOSwiftSection/Models/ContextDescriptor/ContextWrapper.swift`

`ContextProtocol` exposes `parent(in: machO)`. `ContextWrapper` exposes `parent(in: machO)` and `forContextDescriptorWrapper(_:in:)`. Mirror both.

- [x] **Step 1: Add ReadingContext extension to `ContextProtocol.swift`**

Append at bottom:

```swift
// MARK: - ReadingContext Support

extension ContextProtocol {
    public func parent<Context: ReadingContext>(in context: Context) throws -> SymbolOrElement<ContextWrapper>? {
        try descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
    }
}
```

- [x] **Step 2: Add ReadingContext methods to `ContextWrapper.swift`**

Append at bottom (after the existing `parent()` method):

```swift
// MARK: - ReadingContext Support

extension ContextWrapper {
    public static func forContextDescriptorWrapper<Context: ReadingContext>(_ contextDescriptorWrapper: ContextDescriptorWrapper, in context: Context) throws -> Self {
        switch contextDescriptorWrapper {
        case .type(let typeContextDescriptorWrapper):
            switch typeContextDescriptorWrapper {
            case .enum(let enumDescriptor):
                return try .type(.enum(.init(descriptor: enumDescriptor, in: context)))
            case .struct(let structDescriptor):
                return try .type(.struct(.init(descriptor: structDescriptor, in: context)))
            case .class(let classDescriptor):
                return try .type(.class(.init(descriptor: classDescriptor, in: context)))
            }
        case .protocol(let protocolDescriptor):
            return try .protocol(.init(descriptor: protocolDescriptor, in: context))
        case .anonymous(let anonymousContextDescriptor):
            return try .anonymous(.init(descriptor: anonymousContextDescriptor, in: context))
        case .extension(let extensionContextDescriptor):
            return try .extension(.init(descriptor: extensionContextDescriptor, in: context))
        case .module(let moduleContextDescriptor):
            return try .module(.init(descriptor: moduleContextDescriptor, in: context))
        case .opaqueType(let opaqueTypeDescriptor):
            return try .opaqueType(.init(descriptor: opaqueTypeDescriptor, in: context))
        }
    }

    public func parent<Context: ReadingContext>(in context: Context) throws -> SymbolOrElement<ContextWrapper>? {
        switch self {
        case .type(let typeWrapper):
            switch typeWrapper {
            case .enum(let `enum`):
                return try `enum`.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
            case .struct(let `struct`):
                return try `struct`.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
            case .class(let `class`):
                return try `class`.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
            }
        case .protocol(let `protocol`):
            return try `protocol`.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        case .anonymous(let anonymousContext):
            return try anonymousContext.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        case .extension(let extensionContext):
            return try extensionContext.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        case .module(let moduleContext):
            return try moduleContext.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        case .opaqueType(let opaqueType):
            return try opaqueType.descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
        }
    }
}
```

`ContextWrapper.forContextDescriptorWrapper(_:in:Context)` depends on every concrete Context type having a `init(descriptor:in:Context)` overload. Tasks 2, 4, 5, 6, 7 add those; this task can compile only after they all land — **so move this task's commit to be the last commit in the series** (after Task 7), or split into two: stub today, fill in once the dependents land.

**Recommended:** Land *only* the `parent(in:context:)` portion now (which depends on `descriptor.parent(in:context:)` already provided by `ContextDescriptorProtocol`), and defer `forContextDescriptorWrapper(_:in:context:)` to a later task (Task 11) once all `init(descriptor:in:context:)` overloads exist.

- [x] **Step 3: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 4: Commit**

```bash
git add Sources/MachOSwiftSection/Models/ContextDescriptor/ContextProtocol.swift \
        Sources/MachOSwiftSection/Models/ContextDescriptor/ContextWrapper.swift
git commit -m "feat(MachOSwiftSection): add ReadingContext API for ContextProtocol/ContextWrapper

Adds parent(in:context:) on both. forContextDescriptorWrapper(_:in:context:)
is deferred until concrete Context types have their ReadingContext init
overloads (Task 11)."
```

Combined with Task 11 below into a single commit `d5d1d74` since the dependency only resolves once all concrete `init(descriptor:in:Context)` overloads exist.

---

## Task 4: `Type/Class/` (descriptor + class type + class metadata protocols + method descriptors)

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/Type/Class/Class.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Class/ClassDescriptor.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Class/Metadata/AnyClassMetadata/AnyClassMetadataProtocol.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Class/Metadata/AnyClassMetadataObjCInterop/AnyClassMetadataObjCInteropProtocol.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Class/Metadata/FinalClassMetadataProtocol.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Class/Method/MethodDescriptor.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Class/Method/MethodOverrideDescriptor.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Class/Method/MethodDefaultOverrideDescriptor.swift`

- [x] **Step 1: Read each file end-to-end**

For each of the 8 files, list every method with a `<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO)` signature. Those are the methods that need a sibling `<Context: ReadingContext>(in context: Context)` overload.

- [x] **Step 2: Add ReadingContext overloads to each file**

Apply the substitution table from the design doc to each MachO method. Place new overloads in a `// MARK: - ReadingContext Support` extension at the bottom of each file.

For `Class.swift` (the highest-level wrapper): mirror the `init(descriptor:in:)` and any other MachO-parameterized methods, calling `.someMethod(in: context)` for nested calls instead of `.someMethod(in: machO)`.

For `ClassDescriptor.swift`: mirror every descriptor method one-by-one.

For metadata protocols: mirror every method that reads through `machO`.

- [x] **Step 3: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 4: Commit**

```bash
git add Sources/MachOSwiftSection/Models/Type/Class/
git commit -m "feat(MachOSwiftSection): add ReadingContext API for class types

Mirror the MachO overloads on Class, ClassDescriptor, the AnyClassMetadata
and FinalClassMetadata protocols, and the Method*Descriptor types. Call
sites pass the context through to nested methods so the unified path is
end-to-end."
```

---

## Task 5: `Type/Enum/`, `Type/Struct/`

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/Type/Enum/Enum.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Enum/Metadata/EnumMetadataProtocol.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Enum/MultiPayloadEnumDescriptor.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Struct/Struct.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/Struct/StructMetadataProtocol.swift`

- [x] **Step 1: Add ReadingContext overloads to each file**

For each file, list every method whose signature uses `<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO)` and add a sibling `<Context: ReadingContext>(in context: Context)` overload using the substitution table from the design doc. Place new overloads in a `// MARK: - ReadingContext Support` extension at the bottom of each file.

Specifics for this batch:
- `Enum.swift` and `Struct.swift`: mirror `init(descriptor:in:)` so the value-type wrappers can be built from a `ReadingContext`. Pass `in: context` to all nested `descriptor.someMethod(in: ...)` calls.
- `EnumMetadataProtocol` and `StructMetadataProtocol`: mirror metadata-reading methods (e.g. `payloadCases`, `typeDescriptor`).
- `MultiPayloadEnumDescriptor`: mirror payload-tag and case helpers.

- [x] **Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 3: Commit**

```bash
git add Sources/MachOSwiftSection/Models/Type/Enum/ \
        Sources/MachOSwiftSection/Models/Type/Struct/
git commit -m "feat(MachOSwiftSection): add ReadingContext API for enum/struct types

Mirror init(descriptor:in:) and metadata helpers on Enum, Struct,
EnumMetadataProtocol, StructMetadataProtocol, and
MultiPayloadEnumDescriptor."
```

---

## Task 6: `Type/` root files (descriptor, references, value metadata)

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/Type/TypeContextDescriptor.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/TypeContextWrapper.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/TypeReference.swift`
- Modify: `Sources/MachOSwiftSection/Models/Type/ValueMetadataProtocol.swift`
- Modify (partial top-up): `Sources/MachOSwiftSection/Models/Type/TypeContextDescriptorProtocol.swift`

- [x] **Step 1: Add ReadingContext overloads to the four uncovered files**

Same procedure as prior batches.

- [x] **Step 2: Top up `TypeContextDescriptorProtocol.swift`**

The file already has `genericContext(in:Context)` and `typeGenericContext(in:Context)`. Add the missing `fieldDescriptor(in:Context)` and `metadataAccessorFunction(in:Context)`:

```swift
extension TypeContextDescriptorProtocol {
    public func fieldDescriptor<Context: ReadingContext>(in context: Context) throws -> FieldDescriptor {
        let address = try context.addressFromOffset(offset + layout.offset(of: .fieldDescriptor))
        return try layout.fieldDescriptor.resolve(at: address, in: context)
    }

    public func metadataAccessorFunction<Context: ReadingContext>(in context: Context) throws -> MetadataAccessorFunction? {
        let fieldAddress = try context.addressFromOffset(offset + layout.offset(of: .accessFunctionPtr))
        let relativeOffset: Int32 = try context.readElement(at: fieldAddress)
        let targetAddress = context.advanceAddress(fieldAddress, by: Int(relativeOffset))
        return try context.runtimePointer(at: targetAddress).map { MetadataAccessorFunction(ptr: $0) }
    }
}
```

The `metadataAccessorFunction(in:Context)` returns `nil` for `MachOContext<MachOFile>` (matching the existing MachO overload), and returns the function pointer for `InProcessContext` and `MachOContext<MachOImage>`.

- [x] **Step 3: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 4: Commit**

```bash
git add Sources/MachOSwiftSection/Models/Type/TypeContextDescriptor.swift \
        Sources/MachOSwiftSection/Models/Type/TypeContextWrapper.swift \
        Sources/MachOSwiftSection/Models/Type/TypeReference.swift \
        Sources/MachOSwiftSection/Models/Type/ValueMetadataProtocol.swift \
        Sources/MachOSwiftSection/Models/Type/TypeContextDescriptorProtocol.swift
git commit -m "feat(MachOSwiftSection): add ReadingContext API for Type root descriptors

Mirror MachO overloads on TypeContextDescriptor, TypeContextWrapper,
TypeReference, and ValueMetadataProtocol. Add the missing
fieldDescriptor(in:context:) and metadataAccessorFunction(in:context:)
overloads on TypeContextDescriptorProtocol — the latter uses the new
runtimePointer(at:) extension to return the function pointer for
InProcess and MachOImage contexts and nil for MachOFile.

Also retarget EnumMetadataProtocol.enumDescriptor and
StructMetadataProtocol.structDescriptor to call descriptor(in:context:)
now that the helper exists."
```

---

## Task 7: `Protocol/`, `ProtocolConformance/`

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/Protocol/Protocol.swift`
- Modify: `Sources/MachOSwiftSection/Models/Protocol/ProtocolDescriptor.swift`
- Modify: `Sources/MachOSwiftSection/Models/Protocol/ProtocolDescriptorRef.swift`
- Modify: `Sources/MachOSwiftSection/Models/Protocol/ProtocolRecord.swift`
- Modify: `Sources/MachOSwiftSection/Models/Protocol/ProtocolRequirement.swift`
- Modify: `Sources/MachOSwiftSection/Models/Protocol/ResilientWitness.swift`
- Modify: `Sources/MachOSwiftSection/Models/ProtocolConformance/GlobalActorReference.swift`
- Modify: `Sources/MachOSwiftSection/Models/ProtocolConformance/ProtocolConformance.swift`
- Modify: `Sources/MachOSwiftSection/Models/ProtocolConformance/ProtocolConformanceDescriptor.swift`

- [x] **Step 1: Add ReadingContext overloads to each file**

For each file, list every method whose signature uses `<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO)` and add a sibling `<Context: ReadingContext>(in context: Context)` overload using the substitution table from the design doc. Place new overloads in a `// MARK: - ReadingContext Support` extension at the bottom of each file.

Note: `Protocol.swift` and `ProtocolConformance.swift` are the highest-level wrappers — their `init(descriptor:in:Context)` overloads are required by Task 11 (`ContextWrapper.forContextDescriptorWrapper(_:in:context:)`), so do not skip them.

- [x] **Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 3: Commit**

```bash
git add Sources/MachOSwiftSection/Models/Protocol/ \
        Sources/MachOSwiftSection/Models/ProtocolConformance/
git commit -m "feat(MachOSwiftSection): add ReadingContext API for protocol/conformance types

Mirror MachO overloads on Protocol, ProtocolDescriptor, ProtocolDescriptorRef,
ProtocolRecord, ProtocolRequirement, ResilientWitness, GlobalActorReference,
ProtocolConformance, and ProtocolConformanceDescriptor."
```

The implementation also added two prerequisite mirrors needed by `Protocol.swift` and `ProtocolDescriptorRef.swift`:
- `GenericRequirement.init<Context>` (would otherwise be in Task 8).
- `ObjCProtocolPrefix.name<Context>` (a partial file from the Task 12 audit list).

---

## Task 8: `Generic/`, `FieldDescriptor/`, `FieldRecord/`, `AssociatedType/`

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/Generic/GenericRequirement.swift`
- Modify: `Sources/MachOSwiftSection/Models/FieldDescriptor/FieldDescriptor.swift`
- Modify: `Sources/MachOSwiftSection/Models/FieldRecord/FieldRecord.swift`
- Modify: `Sources/MachOSwiftSection/Models/AssociatedType/AssociatedType.swift`
- Modify: `Sources/MachOSwiftSection/Models/AssociatedType/AssociatedTypeDescriptor.swift`
- Modify: `Sources/MachOSwiftSection/Models/AssociatedType/AssociatedTypeRecord.swift`

- [x] **Step 1: Add ReadingContext overloads to each file**

For each file, list every method whose signature uses `<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO)` and add a sibling `<Context: ReadingContext>(in context: Context)` overload using the substitution table from the design doc. Place new overloads in a `// MARK: - ReadingContext Support` extension at the bottom of each file.

Note: `GenericRequirement.swift` only needs an `init(descriptor:in:Context)` mirror — `paramMangledName(in:Context)` and `resolvedContent(in:Context)` already exist on `GenericRequirementDescriptor` (one of the partial files). Already added in Task 7 as a prerequisite, so this batch covers only the field/associated-type files.

- [x] **Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 3: Commit**

```bash
git add Sources/MachOSwiftSection/Models/FieldDescriptor/ \
        Sources/MachOSwiftSection/Models/FieldRecord/ \
        Sources/MachOSwiftSection/Models/AssociatedType/
git commit -m "feat(MachOSwiftSection): add ReadingContext API for generic/field/associated-type

Mirror MachO overloads on FieldDescriptor, FieldRecord, and the
AssociatedType family.

GenericRequirement.init<Context> was added as a prerequisite in the
preceding protocol/conformance batch."
```

---

## Task 9: `Metadata/` (protocols and wrappers)

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/Metadata/MetadataProtocol.swift`
- Modify: `Sources/MachOSwiftSection/Models/Metadata/MetadataWrapper.swift`

- [x] **Step 1: Add ReadingContext overloads to each file**

For each file, list every method whose signature uses `<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO)` and add a sibling `<Context: ReadingContext>(in context: Context)` overload using the substitution table from the design doc. Place new overloads in a `// MARK: - ReadingContext Support` extension at the bottom of each file.

Specifics for this batch:
- `MetadataProtocol`: mirror metadata-reading methods (e.g. `valueWitnessTable`, `typeContextDescriptor`, kind-specific accessors).
- `MetadataWrapper`: mirror the static `forMetadata(_:in:)` factory (the switch over metadata kinds) and any wrapper-level methods that take `in: machO`.

- [x] **Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 3: Commit**

```bash
git add Sources/MachOSwiftSection/Models/Metadata/MetadataProtocol.swift \
        Sources/MachOSwiftSection/Models/Metadata/MetadataWrapper.swift
git commit -m "feat(MachOSwiftSection): add ReadingContext API for Metadata protocol/wrapper"
```

---

## Task 10: `ExistentialType/`, `ForeignType/`, `TupleType/`, `OpaqueType/`, `BuiltinType/`

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/ExistentialType/ExistentialTypeMetadata.swift`
- Modify: `Sources/MachOSwiftSection/Models/ForeignType/ForeignClassMetadata.swift`
- Modify: `Sources/MachOSwiftSection/Models/ForeignType/ForeignReferenceTypeMetadata.swift`
- Modify: `Sources/MachOSwiftSection/Models/TupleType/TupleTypeMetadata.swift`
- Modify: `Sources/MachOSwiftSection/Models/OpaqueType/OpaqueType.swift`
- Modify: `Sources/MachOSwiftSection/Models/BuiltinType/BuiltinType.swift`
- Modify: `Sources/MachOSwiftSection/Models/BuiltinType/BuiltinTypeDescriptor.swift`

- [ ] **Step 1: Add ReadingContext overloads to each file**

For each file, list every method whose signature uses `<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO)` and add a sibling `<Context: ReadingContext>(in context: Context)` overload using the substitution table from the design doc. Place new overloads in a `// MARK: - ReadingContext Support` extension at the bottom of each file.

These are the remaining metadata wrappers — most have one to three methods each. Read each file end-to-end before mirroring.

- [x] **Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 3: Commit**

```bash
git add Sources/MachOSwiftSection/Models/ExistentialType/ \
        Sources/MachOSwiftSection/Models/TupleType/ \
        Sources/MachOSwiftSection/Models/OpaqueType/ \
        Sources/MachOSwiftSection/Models/BuiltinType/
git commit -m "feat(MachOSwiftSection): add ReadingContext API for remaining metadata types

Mirror MachO overloads on ExistentialTypeMetadata, TupleTypeMetadata,
OpaqueType, BuiltinType, and BuiltinTypeDescriptor.

ForeignClassMetadata.classDescriptor and
ForeignReferenceTypeMetadata.classDescriptor were added as prerequisites
in the preceding Metadata batch."
```

---

## Task 11: `ContextWrapper.forContextDescriptorWrapper(_:in:context:)`

**Files:**
- Modify: `Sources/MachOSwiftSection/Models/ContextDescriptor/ContextWrapper.swift`

This was deferred from Task 3 because it depends on every concrete Context type having a `init(descriptor:in:Context)` overload, which Tasks 2/4/5/6/7 add.

- [x] **Step 1: Add `forContextDescriptorWrapper(_:in:Context)` to `ContextWrapper.swift`**

Inside the existing `// MARK: - ReadingContext Support` extension (added in Task 3), add:

```swift
public static func forContextDescriptorWrapper<Context: ReadingContext>(_ contextDescriptorWrapper: ContextDescriptorWrapper, in context: Context) throws -> Self {
    switch contextDescriptorWrapper {
    case .type(let typeContextDescriptorWrapper):
        switch typeContextDescriptorWrapper {
        case .enum(let enumDescriptor):
            return try .type(.enum(.init(descriptor: enumDescriptor, in: context)))
        case .struct(let structDescriptor):
            return try .type(.struct(.init(descriptor: structDescriptor, in: context)))
        case .class(let classDescriptor):
            return try .type(.class(.init(descriptor: classDescriptor, in: context)))
        }
    case .protocol(let protocolDescriptor):
        return try .protocol(.init(descriptor: protocolDescriptor, in: context))
    case .anonymous(let anonymousContextDescriptor):
        return try .anonymous(.init(descriptor: anonymousContextDescriptor, in: context))
    case .extension(let extensionContextDescriptor):
        return try .extension(.init(descriptor: extensionContextDescriptor, in: context))
    case .module(let moduleContextDescriptor):
        return try .module(.init(descriptor: moduleContextDescriptor, in: context))
    case .opaqueType(let opaqueTypeDescriptor):
        return try .opaqueType(.init(descriptor: opaqueTypeDescriptor, in: context))
    }
}
```

Also retrofit the `parent(in:context:)` method added in Task 3 to call this new helper instead of inlining it (search for the eight `forContextDescriptorWrapper($0, in: context)` call sites — they should already be calling this name; this step just adds the actual implementation).

- [x] **Step 2: Build**

```bash
swift build 2>&1 | xcsift
```

- [x] **Step 3: Commit**

Combined with Task 3 above into a single commit `d5d1d74` with body:

```
feat(MachOSwiftSection): wire ContextProtocol/ContextWrapper for ReadingContext

Add parent(in:context:) on ContextProtocol and ContextWrapper, and the
forContextDescriptorWrapper(_:in:context:) static factory on ContextWrapper.

These three methods were deferred from earlier batches because
forContextDescriptorWrapper(_:in:context:) depends on every concrete
Context type having an init(descriptor:in:context:) overload — and those
landed across Tasks 2, 4, 5, 6, and 7. Now that all dependencies exist,
this commit closes the dependency and completes the parent traversal API
under the unified ReadingContext abstraction.
```

---

## Task 12: Audit partial files, sweep for missed methods, full test pass

**Files:**
- Audit (no expected modifications): all 15 files that already had partial ReadingContext support, listed below.

The 15 partially-implemented files were:

```
Models/Anonymous/AnonymousContextDescriptorProtocol.swift
Models/ContextDescriptor/ContextDescriptorProtocol.swift
Models/ContextDescriptor/ContextDescriptorWrapper.swift
Models/ContextDescriptor/NamedContextDescriptorProtocol.swift
Models/ExistentialType/ExtendedExistentialTypeShape.swift
Models/ExistentialType/NonUniqueExtendedExistentialTypeShape.swift
Models/Extension/ExtensionContextDescriptor.swift
Models/Generic/GenericContext.swift
Models/Generic/GenericRequirementDescriptor.swift
Models/Mangling/MangledName.swift
Models/Protocol/ObjC/ObjCProtocolPrefix.swift
Models/Protocol/ObjC/RelativeObjCProtocolPrefix.swift
Models/Type/TypeContextDescriptorProtocol.swift   (already topped up in Task 6)
Models/Type/TypeContextDescriptorWrapper.swift
Models/Type/TypeMetadataRecord.swift
```

- [x] **Step 1: Per-file audit**

For each of the 15 files, list its `<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO)` methods and its `<Context: ReadingContext>(in context: Context)` methods. Any MachO method without a sibling ReadingContext method is a gap — add it using the same substitution table. Skip files with no gap.

Run this command to surface gaps quickly:

```bash
for f in $(grep -l "Context: ReadingContext" Sources/MachOSwiftSection/Models/ -r); do
  echo "=== $f ==="
  grep -E "func .*<(MachO|Context):" "$f" | sed -E 's/.*func ([a-zA-Z]+)<(MachO|Context).*/\1 \2/'
done
```

Look for method names that appear with `MachO` but not with `Context`.

- [x] **Step 2: Add missing ReadingContext overloads found in Step 1**

Apply the substitution table. If no gaps were found, this step is a no-op.

- [x] **Step 3: Full test pass**

```bash
swift package update && swift test 2>&1 | xcsift
```

Expected: existing tests pass (`MachOSwiftSectionTests`, `DemanglingTests`, `SwiftDumpTests`, `SwiftInterfaceTests`). No new tests are introduced by this work.

If a test fails: read the failure carefully. The most likely cause is a typo in a substitution (e.g. forgot `try`, wrong type cast). Fix in place and re-run.

- [x] **Step 4: Final coverage check**

Run the gap query from the design doc one more time:

```bash
grep -lL "ReadingContext" $(grep -l "MachOSwiftSectionRepresentableWithCache" \
  Sources/MachOSwiftSection/Models/ -r)
```

Expected: empty output (every model file with a MachO API now has a ReadingContext API).

- [x] **Step 5: Commit (only if Step 2 produced changes; otherwise skip)**

```bash
git add Sources/MachOSwiftSection/Models/
git commit -m "feat(MachOSwiftSection): close ReadingContext gaps in partial files

Audit pass over the 15 files that previously had partial ReadingContext
coverage. Adds the few overloads that were missing relative to each
file's MachO API surface."
```

---

## Done

After Task 12, the entire `Sources/MachOSwiftSection/Models/` tree exposes a complete `ReadingContext` API mirror, the `runtimePointer(at:)` extension is in place, and `swift test` passes.
