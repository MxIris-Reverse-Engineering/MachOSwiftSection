# SwiftInterface Attribute Inference Design

## Summary

Recover Swift declaration attributes (`@propertyWrapper`, `@resultBuilder`, `@objc`, `@frozen`, etc.) from Mach-O binary metadata and emit them in SwiftInterface output. Attributes fall into three categories by detection strategy: type-level inference from characteristic members, member-level detection from Node tree / descriptor flags, and conformance-level detection from conformance flags.

## Motivation

SwiftInterface currently outputs zero `@`-prefix attributes, resulting in incomplete interface files. Many attributes are recoverable from binary metadata or can be inferred from the presence of compiler-required members, significantly improving the fidelity of the generated interface.

## Scope

### In Scope

| Attribute | Level | Detection Source | Resilience-gated |
|---|---|---|---|
| `@propertyWrapper` | Type | `wrappedValue` member exists | No |
| `@resultBuilder` | Type | `static buildBlock` method exists | No |
| `@dynamicMemberLookup` | Type | `subscript(dynamicMember:)` exists | No |
| `@dynamicCallable` | Type | `dynamicallyCall` method exists | No |
| `@frozen` | Type | `TypeContextDescriptorFlags.noMetadataInitialization` (struct/enum only) | Yes |
| `@usableFromInline` | Type | `TypeContextDescriptorFlags.hasImportInfo` + trailing field | Yes |
| `@objc("Name")` | Type | `ClassFlags.hasCustomObjCName` (class only) | No |
| `@objc` | Member | Node tree `.objCAttribute` Kind | No |
| `@nonobjc` | Member | Node tree `.nonObjCAttribute` Kind | No |
| `dynamic` | Member | `MethodDescriptorFlags.isDynamic` | No |
| `@inlinable` | Member | Node tree `.isSerialized` child node | Yes |
| `@retroactive` | Conformance | `ProtocolConformanceFlags.isRetroactive` | No |

### Out of Scope (Not Recoverable)

| Attribute | Reason |
|---|---|
| `@available` | Not stored in binary metadata; compile-time only |
| `@objcMembers` | Expands to per-member @objc thunks; no type-level flag |
| `@Sendable` | Type system constraint; no metadata encoding |

## Architecture

### Design: Unified AttributeInferrer Components

Two inferrer structs handle the two layers:

- `TypeAttributeInferrer` (SwiftInterface layer) — infers type-level attributes after `TypeDefinition.index()` completes, when all members are available
- `MemberAttributeInferrer` (SwiftInterface layer, consumed by DefinitionBuilder) — infers member-level attributes from Node tree and MethodDescriptorFlags during member construction

Both accept a `resilienceAwareAttributes: Bool` configuration flag.

### Why This Approach

- Detection logic is centralized — adding a new attribute means adding one rule
- Rules are pure functions, independently testable
- Type-level and member-level inference have different timing and data sources; the split reflects this naturally
- The `resilienceAwareAttributes` config threads through cleanly as an initializer parameter

## Data Model

### `SwiftAttribute` Enum

Location: `Sources/SwiftDump/` (both SwiftDump and SwiftInterface need access)

```swift
public enum SwiftAttribute: Comparable {
    // Type-level (inferred from members)
    case propertyWrapper       // @propertyWrapper
    case resultBuilder         // @resultBuilder
    case dynamicMemberLookup   // @dynamicMemberLookup
    case dynamicCallable       // @dynamicCallable

    // Type-level (from metadata flags)
    case frozen                // @frozen
    case usableFromInline      // @usableFromInline
    case objcType              // @objc on type (from ClassFlags.hasCustomObjCName)

    // Member-level (from Node tree / descriptor flags)
    case objc                  // @objc
    case nonobjc               // @nonobjc
    case inlinable             // @inlinable

    // Member-level (from descriptor flags)
    case dynamic               // dynamic

    // Conformance-level
    case retroactive           // @retroactive
}
```

The enum conforms to `Comparable` to ensure deterministic output ordering (declaration order = print order).

### Definition Extensions

Add to `TypeDefinition`, `FunctionDefinition`, `VariableDefinition`, `SubscriptDefinition`:

```swift
public internal(set) var attributes: [SwiftAttribute] = []
```

Add to `ExtensionDefinition`:

```swift
public internal(set) var isRetroactive: Bool = false
```

### Configuration

Add to `SwiftInterfaceBuilderConfiguration`:

```swift
public var resilienceAwareAttributes: Bool = false
```

### `Keyword.Swift` Extension

Add new cases for all `@`-prefix attributes:

```swift
case atObjc              // "@objc"
case atNonobjc           // "@nonobjc"
case atFrozen            // "@frozen"
case atInlinable         // "@inlinable"
case atUsableFromInline  // "@usableFromInline"
case atPropertyWrapper   // "@propertyWrapper"
case atResultBuilder     // "@resultBuilder"
case atDynamicMemberLookup  // "@dynamicMemberLookup"
case atDynamicCallable   // "@dynamicCallable"
case atRetroactive       // "@retroactive"
```

All use `.keyword` semantic type.

## Type-Level Inference

### `TypeAttributeInferrer`

Location: `Sources/SwiftInterface/AttributeInference/TypeAttributeInferrer.swift`

```swift
public struct TypeAttributeInferrer {
    let resilienceAwareAttributes: Bool

    func infer(for typeDefinition: TypeDefinition) -> [SwiftAttribute]
}
```

### Detection Rules

**`@propertyWrapper`** — struct/class/enum only (never protocol):
```swift
typeDefinition.fields.contains { $0.name == "wrappedValue" }
    || typeDefinition.variables.contains { $0.name == "wrappedValue" }
```

**`@resultBuilder`** — detect `static buildBlock`:
```swift
typeDefinition.staticFunctions.contains { $0.name == "buildBlock" }
```
Also check extension definitions for this type via the indexer, since `buildBlock` may be defined in an extension.

**`@dynamicMemberLookup`** — detect `subscript(dynamicMember:)`:
```swift
typeDefinition.subscripts.contains { sub in
    sub.node.children.first { $0.kind == .labelList }?
        .children.first?.text == "dynamicMember"
}
// Also check staticSubscripts
```

**`@dynamicCallable`** — detect `dynamicallyCall`:
```swift
typeDefinition.functions.contains { $0.name == "dynamicallyCall" }
    || typeDefinition.staticFunctions.contains { $0.name == "dynamicallyCall" }
```

**`@frozen`** (resilience-gated, struct/enum only):
```swift
typeDefinition.type.descriptor.typeContextDescriptorFlags.noMetadataInitialization
```

**`@usableFromInline`** (resilience-gated):

When `hasImportInfo` is set, a `TypeImportInfo` trailing field follows the type context descriptor. It is a null-terminated UTF-8 string with a prefix byte encoding visibility: `0x00` = public, `0x02` = `@usableFromInline`. This trailing field is not yet parsed in the codebase — a new parser must be added to read and decode it.

```swift
// 1. Check the flag
typeDefinition.type.descriptor.typeContextDescriptorFlags.hasImportInfo
// 2. Parse the TypeImportInfo trailing field
// 3. Check if the prefix byte == 0x02 (@usableFromInline)
```

**`@objc("CustomName")`** (class only):
```swift
classDescriptor.classFlags.contains(.hasCustomObjCName)
```

### Injection Point

In `SwiftInterfacePrinter.printTypeDefinition`, after `typeDefinition.index(in:)` completes and before `dumper.declaration`:

```swift
if !typeDefinition.isIndexed {
    try typeDefinition.index(in: machO)
}
typeDefinition.attributes = typeAttributeInferrer.infer(for: typeDefinition)
```

### Output Format

Each type-level attribute on its own line, before the type declaration:

```swift
@frozen
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
```

## Member-Level Inference

### `MemberAttributeInferrer`

Location: `Sources/SwiftInterface/AttributeInference/MemberAttributeInferrer.swift`

```swift
public struct MemberAttributeInferrer {
    let resilienceAwareAttributes: Bool

    func infer(for node: Node, flags: MethodDescriptorFlags?) -> [SwiftAttribute]
    func infer(for variableNode: Node) -> [SwiftAttribute]
}
```

### Detection Rules

**`@objc`** — Node tree `.objCAttribute` Kind:

`@objc` thunk symbols have the Node tree structure `global(objCAttribute, function(...))`. Currently, `SymbolIndexStore` collects these in `symbolsByKind[.objCAttribute]` but does NOT store them in `memberSymbolsByKind` because `.objCAttribute` is not in the `isMember` list. The implementation must:

1. Query `symbolsByKind[.objCAttribute]` from `SymbolIndexStore`
2. For each thunk symbol, extract the inner function/variable node from `rootNode.children` (the child after the `.objCAttribute` marker)
3. Match by member name against already-built `FunctionDefinition`/`VariableDefinition`/`SubscriptDefinition` nodes
4. Set `attributes.append(.objc)` on the matched definition

**`@nonobjc`** — Node tree `.nonObjCAttribute` Kind. Same cross-reference pattern using `symbolsByKind[.nonObjCAttribute]`.

**`dynamic`** — `MethodDescriptorFlags.isDynamic`. Currently handled only in `ClassDumper.dumpMethodKeyword`; extract to `MemberAttributeInferrer` for unified management.

**`@inlinable`** (resilience-gated) — `.isSerialized` child in specialization nodes:
```swift
node.recursiveFirstChild(of: .isSerialized) != nil
```
Known limitation: false negatives for `@inlinable` functions without specialization records.

### Injection Point

In `DefinitionBuilder` during member construction. When building `FunctionDefinition`, `VariableDefinition`, or `SubscriptDefinition`, call `MemberAttributeInferrer.infer()` and populate the definition's `attributes` field.

### Output Format

Member-level attributes inline before the declaration:

```swift
    @objc dynamic public func viewDidLoad()
    @objc public var title: String?
    @inlinable public func map<T>(_ transform: (Element) -> T) -> [T]
```

## Conformance-Level: `@retroactive`

### Detection

`ProtocolConformanceFlags.isRetroactive` flag.

### Injection Point

In `SwiftInterfaceIndexer.indexConformances()`, read the flag and set `ExtensionDefinition.isRetroactive = true`.

### Output Format

In `SwiftInterfacePrinter.printExtensionDefinition`, output `@retroactive` before the protocol name:

```swift
extension Array: @retroactive Equatable where Element: Equatable { }
```

## Edge Cases

### Multiple Attributes on One Type

A type may satisfy multiple inference rules (e.g., SwiftUI `Binding` is both `@propertyWrapper` and `@dynamicMemberLookup`). Output all matching attributes in `SwiftAttribute` enum declaration order, each on its own line.

### Inherited Characteristic Members

`TypeDefinition` only contains directly declared members, not inherited ones. Only the type that directly declares the characteristic member gets the attribute annotation. This matches Swift compiler behavior — `@dynamicMemberLookup` must be explicitly annotated even if the parent class qualifies.

### Protocol Characteristic Members

A protocol requiring `wrappedValue` does not make it a `@propertyWrapper`. Type-level inference (for `@propertyWrapper`, `@resultBuilder`, `@dynamicMemberLookup`, `@dynamicCallable`) runs only on struct/class/enum, never on protocols.

### Extension-Defined Characteristic Members

`buildBlock` may be defined in an extension rather than the type body. The inferrer must check both `TypeDefinition.staticFunctions` and the type's `ExtensionDefinition`s (queried from `SwiftInterfaceIndexer`) for characteristic members.

### `@frozen` False Positives

In non-library-evolution binaries, all structs/enums have `noMetadataInitialization = true`. The `resilienceAwareAttributes` config (default `false`) prevents false positives. Documentation notes this limitation.

### `@inlinable` False Negatives

`@inlinable` functions without specialization records are undetectable. This is a known limitation documented in the design.

## File Structure

### New Files

```
Sources/SwiftInterface/AttributeInference/
├── TypeAttributeInferrer.swift        # Type-level inference rules
└── MemberAttributeInferrer.swift      # Member-level inference rules
```

### Modified Files

| File | Change |
|---|---|
| `Sources/SwiftDump/SwiftAttribute.swift` (new) | `SwiftAttribute` enum definition |
| `Sources/SwiftDump/Extensions/Keyword+Swift.swift` | Add `@`-prefix keyword cases |
| `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift` | Add `attributes` field |
| `Sources/SwiftInterface/Components/Definitions/FunctionDefinition.swift` | Add `attributes` field |
| `Sources/SwiftInterface/Components/Definitions/VariableDefinition.swift` | Add `attributes` field |
| `Sources/SwiftInterface/Components/Definitions/SubscriptDefinition.swift` | Add `attributes` field |
| `Sources/SwiftInterface/Components/Definitions/ExtensionDefinition.swift` | Add `isRetroactive` field |
| `Sources/SwiftInterface/Components/Definitions/DefinitionBuilder.swift` | Integrate `MemberAttributeInferrer` |
| `Sources/SwiftInterface/SwiftInterfacePrinter.swift` | Emit type-level attributes before declaration; emit member attributes inline |
| `Sources/SwiftInterface/SwiftInterfaceIndexer.swift` | Read `isRetroactive` in `indexConformances()` |
| `Sources/SwiftInterface/SwiftInterfaceBuilder.swift` | Pass config to inferrers |
| `Sources/SwiftInterface/SwiftInterfaceBuilderConfiguration.swift` | Add `resilienceAwareAttributes` |

### Unmodified

- Demangling module — no changes
- `SemanticType` — reuse `.keyword`
- `SemanticComponents.swift` — no new components needed

## Testing Strategy

### Unit Tests

**`TypeAttributeInferrerTests`** — verify each type-level rule against Apple SDK types:

| Test Case | Target Type (Apple SDK) | Expected Attribute |
|---|---|---|
| `@propertyWrapper` | SwiftUI `State`, `Binding`, `Environment` | Has `wrappedValue` |
| `@resultBuilder` | SwiftUI `ViewBuilder`, `SceneBuilder` | Has `static buildBlock` |
| `@dynamicMemberLookup` | SwiftUI `Binding` | Has `subscript(dynamicMember:)` |
| `@dynamicCallable` | Construct mock or find in third-party library | Has `dynamicallyCall` |
| `@frozen` | Standard library `Array`, `Optional` | `noMetadataInitialization` |

**`MemberAttributeInferrerTests`** — verify each member-level rule:

| Test Case | Signal Source | Expected Attribute |
|---|---|---|
| `@objc` method | UIKit UIViewController methods with `.objCAttribute` Node | `@objc` |
| `dynamic` method | `MethodDescriptorFlags.isDynamic == true` | `dynamic` |
| `@retroactive` | Conformance flags `isRetroactive` bit | `@retroactive` |

### Integration Tests

`AttributeInferenceIntegrationTests` — run the full `SwiftInterfaceBuilder` pipeline on Apple SDK frameworks (e.g., SwiftUI.framework) and verify the output interface text contains expected attribute annotations.

### Configuration Tests

- `resilienceAwareAttributes = false` (default) → no `@frozen`, `@usableFromInline`, `@inlinable` output
- `resilienceAwareAttributes = true` → correct output for library-evolution binaries
- Non-library-evolution binary with `resilienceAwareAttributes = true` → all structs/enums show `@frozen` (documented behavior)
