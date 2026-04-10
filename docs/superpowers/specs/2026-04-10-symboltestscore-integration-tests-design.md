# SymbolTestsCore Integration Tests Design

**Date:** 2026-04-10
**Branch:** feature/vtable-offset-and-member-ordering
**Scope:** Extend SymbolTestsCore with attribute-focused types; add two-layer integration tests covering both new and existing functionality.

## Goal

The existing test suite for SymbolTestsCore relies heavily on "dump and print" tests without structured assertions. This design adds:

1. New Swift types in SymbolTestsCore that exercise attribute inference features
2. Middle-layer integration tests that load the compiled binary and assert on parsed `TypeDefinition` data
3. End-to-end tests that verify `SwiftInterfaceBuilder` output strings

## SymbolTestsCore: New Types

Added to `Tests/Projects/SymbolTests/SymbolTestsCore/SymbolTestsCore.swift`:

### PropertyWrapperStruct

```swift
@propertyWrapper
public struct PropertyWrapperStruct<Value: Comparable> {
    public var wrappedValue: Value
    public var projectedValue: ClosedRange<Value>

    public init(wrappedValue: Value, range: ClosedRange<Value>) {
        self.projectedValue = range
        self.wrappedValue = min(max(wrappedValue, range.lowerBound), range.upperBound)
    }
}
```

Exercises: `TypeAttributeInferrer` detecting `@propertyWrapper` via `wrappedValue` field.

### ResultBuilderStruct

```swift
@resultBuilder
public struct ResultBuilderStruct<Element> {
    public static func buildBlock(_ components: Element...) -> [Element] { components }
    public static func buildOptional(_ component: [Element]?) -> [Element] { component ?? [] }
}
```

Exercises: `TypeAttributeInferrer` detecting `@resultBuilder` via `static buildBlock`.

### DynamicMemberLookupStruct

```swift
@dynamicMemberLookup
public struct DynamicMemberLookupStruct {
    public subscript(dynamicMember member: String) -> Int { 0 }
}
```

Exercises: `TypeAttributeInferrer` detecting `@dynamicMemberLookup` via `subscript(dynamicMember:)`.

### DynamicCallableStruct

```swift
@dynamicCallable
public struct DynamicCallableStruct {
    public func dynamicallyCall(withArguments arguments: [Int]) -> Int {
        arguments.reduce(0, +)
    }
    public func dynamicallyCall(withKeywordArguments arguments: KeyValuePairs<String, Int>) -> Int { 0 }
}
```

Exercises: `TypeAttributeInferrer` detecting `@dynamicCallable` via `dynamicallyCall`.

### ObjCAttributeClass

```swift
public class ObjCAttributeClass: NSObject {
    @objc public func objcMethod() {}
    @nonobjc public func nonobjcMethod() {}
    @objc public dynamic func objcDynamicMethod() {}
}
```

Exercises: `MemberAttributeInferrer` detecting `@objc`, `@nonobjc`, and `dynamic` from real binary symbols.

## Test File 1: SymbolTestsCoreIntegrationTests.swift

**Location:** `Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift`

Loads `SymbolTestsCore` binary via `MachOFileTests` base class. Uses `SwiftInterfaceIndexer` and `TypeDefinition` APIs for assertions.

### Type Parsing

- Parsed type names include `StructTest`, `ClassTest`, `MultiPayloadEnumTests`, `ProtocolTest`, etc.
- Each type's kind (struct/class/enum) is correct.

### Fields and Stored Properties

- `GenericStructNonRequirement` fields: `field1` (Double), `field2` (A), `field3` (Int) in order.

### Protocol Conformances

- `StructTest` conforms to `ProtocolTest` and `ProtocolWitnessTableTest`.
- `GenericRequirementTest` conforms to `ProtocolTest`.
- `Never: @retroactive IteratorProtocol` has `isRetroactive == true`.

### Class Hierarchy and Override

- `SubclassTest.instanceMethod` has `isOverride == true`.
- `FinalClassTest.dynamicMethod` has `isOverride == true`.
- `ClassTest` own methods have `isOverride == false`.

### Nested Types

- `GenericRequirementTest` has child type `RawRepresentableNestedStruct`.
- `RawRepresentableNestedStruct` has child type `NestedStruct`.

### Associated Types

- `ProtocolTest` has `associatedtype Body`.

### Type Attributes (Integration)

- `PropertyWrapperStruct` → inferred `.propertyWrapper`
- `ResultBuilderStruct` → inferred `.resultBuilder`
- `DynamicMemberLookupStruct` → inferred `.dynamicMemberLookup`
- `DynamicCallableStruct` → inferred `.dynamicCallable`
- `StructTest` → no attribute inferred (negative test)

### Member Attributes (Integration)

- `ObjCAttributeClass.objcMethod` → `.objc`
- `ObjCAttributeClass.nonobjcMethod` → `.nonobjc`
- `ObjCAttributeClass.objcDynamicMethod` → `.objc`, `.dynamic`
- `ClassTest.dynamicVariable` → `.dynamic`
- `ClassTest.dynamicMethod` → `.dynamic`

### VTable Offset and Member Ordering

- `ClassTest` ordered members: vtable-offset members first, sorted by vtable offset ascending.
- `SubclassTest` override members retain vtable offsets.

### PWT Offset Ordering

- `StructTest: ProtocolWitnessTableTest` extension ordered members sorted by PWT offset.

## Test File 2: SymbolTestsCoreE2ETests.swift

**Location:** `Tests/SwiftInterfaceTests/SymbolTestsCoreE2ETests.swift`

Uses `SwiftInterfaceBuilder` to generate full output string, then asserts on content.

**Configuration:** `printVTableOffset: true`, `memberSortOrder: .byOffset`, `resilienceAwareAttributes: false`.

### Type Attributes in Output

- Output contains `@propertyWrapper` before `PropertyWrapperStruct` declaration.
- Output contains `@resultBuilder` before `ResultBuilderStruct` declaration.
- Output contains `@dynamicMemberLookup` before `DynamicMemberLookupStruct`.
- Output contains `@dynamicCallable` before `DynamicCallableStruct`.

### Member Attributes in Output

- `ObjCAttributeClass` block contains `@objc`.
- `ClassTest` block contains `dynamic`.

### VTable Offset in Output

- `ClassTest` members have `vtable offset` comments.
- VTable offset values are in ascending order.

### Structure Completeness

- Output contains all expected type declarations.
- Conditional conformances include `where` clauses.
- `@retroactive` annotation present for retroactive conformances.
- `override` keyword present for override members.

## Build Prerequisite

The SymbolTests Xcode project must be rebuilt in Release configuration after adding new types:

```bash
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTests \
  -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
  build
```
