# Attribute Inference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recover Swift declaration attributes (`@propertyWrapper`, `@resultBuilder`, `@objc`, `@frozen`, etc.) from Mach-O binary metadata and emit them in SwiftInterface output.

**Architecture:** Two inferrer structs — `TypeAttributeInferrer` for type-level attributes inferred from characteristic members and metadata flags, `MemberAttributeInferrer` for member-level attributes from Node tree and descriptor flags. A `SwiftAttribute` enum in SwiftDump defines all recoverable attributes. Configuration controls resilience-gated attributes.

**Tech Stack:** Swift 6.2+, MachOKit, Demangling, SemanticString

**Spec:** `docs/superpowers/specs/2026-04-02-attribute-inference-design.md`

---

### Task 1: Add `SwiftAttribute` Enum and `Keyword.Swift` Extensions

**Files:**
- Create: `Sources/SwiftDump/SwiftAttribute.swift`
- Modify: `Sources/SwiftDump/Extensions/Keyword+Swift.swift`

- [ ] **Step 1: Create `SwiftAttribute` enum**

Create `Sources/SwiftDump/SwiftAttribute.swift`:

```swift
import Semantic

public enum SwiftAttribute: Int, Comparable, Sendable, CaseIterable {
    // Type-level (inferred from members)
    case propertyWrapper
    case resultBuilder
    case dynamicMemberLookup
    case dynamicCallable

    // Type-level (from metadata flags)
    case frozen
    case usableFromInline
    case objcType

    // Member-level (from Node tree / descriptor flags)
    case objc
    case nonobjc
    case inlinable
    case dynamic

    // Conformance-level
    case retroactive

    public static func < (lhs: SwiftAttribute, rhs: SwiftAttribute) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var annotationString: String {
        switch self {
        case .propertyWrapper: return "@propertyWrapper"
        case .resultBuilder: return "@resultBuilder"
        case .dynamicMemberLookup: return "@dynamicMemberLookup"
        case .dynamicCallable: return "@dynamicCallable"
        case .frozen: return "@frozen"
        case .usableFromInline: return "@usableFromInline"
        case .objcType: return "@objc"
        case .objc: return "@objc"
        case .nonobjc: return "@nonobjc"
        case .inlinable: return "@inlinable"
        case .dynamic: return "dynamic"
        case .retroactive: return "@retroactive"
        }
    }

    public var keyword: Keyword.Swift {
        switch self {
        case .propertyWrapper: return .atPropertyWrapper
        case .resultBuilder: return .atResultBuilder
        case .dynamicMemberLookup: return .atDynamicMemberLookup
        case .dynamicCallable: return .atDynamicCallable
        case .frozen: return .atFrozen
        case .usableFromInline: return .atUsableFromInline
        case .objcType: return .atObjc
        case .objc: return .atObjc
        case .nonobjc: return .atNonobjc
        case .inlinable: return .atInlinable
        case .dynamic: return .dynamic
        case .retroactive: return .atRetroactive
        }
    }
}
```

- [ ] **Step 2: Add `Keyword.Swift` cases**

In `Sources/SwiftDump/Extensions/Keyword+Swift.swift`, add the new attribute keyword cases after the existing `case repeat` (line 26):

```swift
    case atObjc
    case atNonobjc
    case atFrozen
    case atInlinable
    case atUsableFromInline
    case atPropertyWrapper
    case atResultBuilder
    case atDynamicMemberLookup
    case atDynamicCallable
    case atRetroactive
```

Each case's `description` (used by `Keyword` for output) must return the `@`-prefixed string. The `Keyword.Swift` enum conforms to `RawRepresentable` with `String` raw value — check how existing cases map to strings. If the raw value is the case name itself, you need to set explicit raw values:

```swift
    case atObjc = "@objc"
    case atNonobjc = "@nonobjc"
    case atFrozen = "@frozen"
    case atInlinable = "@inlinable"
    case atUsableFromInline = "@usableFromInline"
    case atPropertyWrapper = "@propertyWrapper"
    case atResultBuilder = "@resultBuilder"
    case atDynamicMemberLookup = "@dynamicMemberLookup"
    case atDynamicCallable = "@dynamicCallable"
    case atRetroactive = "@retroactive"
```

Check `Keyword.Swift`'s `RawRepresentable` conformance and `Keyword`'s `buildComponents()` to confirm how the string value is used. Existing cases like `case `class`` map to `"class"` via the Swift case name. The new `@`-prefixed cases need explicit raw values since Swift identifiers can't start with `@`.

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED (or no errors in SwiftDump module)

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftDump/SwiftAttribute.swift Sources/SwiftDump/Extensions/Keyword+Swift.swift
git commit -m "feat: add SwiftAttribute enum and Keyword.Swift extensions for attribute inference"
```

---

### Task 2: Add `attributes` Field to Definition Types

**Files:**
- Modify: `Sources/SwiftInterface/Components/Definitions/FunctionDefinition.swift:6-17`
- Modify: `Sources/SwiftInterface/Components/Definitions/VariableDefinition.swift:6-13`
- Modify: `Sources/SwiftInterface/Components/Definitions/SubscriptDefinition.swift:4-11`
- Modify: `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift:56-58`

- [ ] **Step 1: Add `attributes` to `FunctionDefinition`**

`FunctionDefinition` uses `@MemberwiseInit(.public)`. Adding a property with a default value means the generated memberwise init will include it as an optional parameter. Add after line 15 (`vtableOffset`):

```swift
    public var attributes: [SwiftAttribute] = []
```

- [ ] **Step 2: Add `attributes` to `VariableDefinition`**

Add after line 11 (`isGlobalOrStatic`), before the computed properties:

```swift
    public var attributes: [SwiftAttribute] = []
```

- [ ] **Step 3: Add `attributes` to `SubscriptDefinition`**

Add after line 9 (`isStatic`), before the computed properties:

```swift
    public var attributes: [SwiftAttribute] = []
```

- [ ] **Step 4: Add `attributes` to `TypeDefinition`**

`TypeDefinition` is a class, not `@MemberwiseInit`. Add a new property after line 56 (`orderedMembers`):

```swift
    public internal(set) var attributes: [SwiftAttribute] = []
```

- [ ] **Step 5: Build to verify compilation**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftInterface/Components/Definitions/FunctionDefinition.swift \
      Sources/SwiftInterface/Components/Definitions/VariableDefinition.swift \
      Sources/SwiftInterface/Components/Definitions/SubscriptDefinition.swift \
      Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift
git commit -m "feat: add attributes field to Definition types"
```

---

### Task 3: Add `resilienceAwareAttributes` Configuration

**Files:**
- Modify: `Sources/SwiftInterface/SwiftInterfaceBuilderConfiguration.swift:24-40`

- [ ] **Step 1: Add configuration property**

In `SwiftInterfacePrintConfiguration`, add after line 40 (`enumLayoutCaseTransformer`):

```swift
    public var resilienceAwareAttributes: Bool = false
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftInterface/SwiftInterfaceBuilderConfiguration.swift
git commit -m "feat: add resilienceAwareAttributes configuration option"
```

---

### Task 4: Implement `TypeAttributeInferrer`

**Files:**
- Create: `Sources/SwiftInterface/AttributeInference/TypeAttributeInferrer.swift`
- Test: `Tests/SwiftInterfaceTests/TypeAttributeInferrerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiftInterfaceTests/TypeAttributeInferrerTests.swift`. The tests should verify each inference rule using mock `TypeDefinition` objects or real Apple SDK types. Since `TypeDefinition` requires a `MachO` object and real descriptors, we'll test the inferrer's logic by testing against real SDK frameworks.

However, `TypeAttributeInferrer` is a pure function on `TypeDefinition` — we can unit test the inference rules directly. The challenge is that `TypeDefinition` is a class that requires `MachO` for construction. A practical approach: test the inferrer's core detection logic as standalone functions first, then add integration tests in Task 9.

Write the core detection predicates as static methods for testability:

```swift
import Testing
import SwiftDump
import Demangling
@testable import SwiftInterface

@Suite("TypeAttributeInferrer Tests")
struct TypeAttributeInferrerTests {
    @Test("detectPropertyWrapper returns true when wrappedValue field exists")
    func detectPropertyWrapperFromField() {
        let fields = [
            FieldDefinition(name: "wrappedValue", typeNode: Node(kind: .type), flags: .isVariable)
        ]
        #expect(TypeAttributeInferrer.hasWrappedValueMember(fields: fields, variables: []))
    }

    @Test("detectPropertyWrapper returns false when no wrappedValue exists")
    func detectPropertyWrapperAbsent() {
        let fields = [
            FieldDefinition(name: "value", typeNode: Node(kind: .type), flags: .isVariable)
        ]
        #expect(!TypeAttributeInferrer.hasWrappedValueMember(fields: fields, variables: []))
    }

    @Test("detectResultBuilder returns true when static buildBlock exists")
    func detectResultBuilder() {
        let functions = [
            makeMockFunctionDefinition(name: "buildBlock")
        ]
        #expect(TypeAttributeInferrer.hasBuildBlockMethod(staticFunctions: functions))
    }

    @Test("detectResultBuilder returns false when no buildBlock exists")
    func detectResultBuilderAbsent() {
        let functions = [
            makeMockFunctionDefinition(name: "someOtherMethod")
        ]
        #expect(!TypeAttributeInferrer.hasBuildBlockMethod(staticFunctions: functions))
    }

    @Test("detectDynamicMemberLookup returns true when subscript(dynamicMember:) exists")
    func detectDynamicMemberLookup() {
        let subscriptNode = makeDynamicMemberSubscriptNode()
        let subscripts = [
            SubscriptDefinition(node: subscriptNode, accessors: [], isStatic: false)
        ]
        #expect(TypeAttributeInferrer.hasDynamicMemberSubscript(subscripts: subscripts, staticSubscripts: []))
    }

    @Test("detectDynamicCallable returns true when dynamicallyCall method exists")
    func detectDynamicCallable() {
        let functions = [
            makeMockFunctionDefinition(name: "dynamicallyCall")
        ]
        #expect(TypeAttributeInferrer.hasDynamicallyCallMethod(functions: functions, staticFunctions: []))
    }
}
```

Note: You will need helper functions `makeMockFunctionDefinition(name:)` and `makeDynamicMemberSubscriptNode()`. The `FunctionDefinition` requires a `Node`, `String`, `FunctionKind`, `DemangledSymbol`, etc. — create minimal mocks:

```swift
// MARK: - Test Helpers

private func makeMockFunctionDefinition(name: String) -> FunctionDefinition {
    let functionNode = Node(kind: .function, children: [
        Node(kind: .structure),
        Node(kind: .identifier, text: name),
        Node(kind: .type)
    ])
    return FunctionDefinition(
        node: functionNode,
        name: name,
        kind: .function,
        symbol: DemangledSymbol(demangledNode: functionNode, offset: 0),
        isGlobalOrStatic: true,
        methodDescriptor: nil,
        offset: nil,
        vtableOffset: nil
    )
}

private func makeDynamicMemberSubscriptNode() -> Node {
    return Node(kind: .subscript, children: [
        Node(kind: .structure),
        Node(kind: .labelList, children: [
            Node(kind: .identifier, text: "dynamicMember")
        ]),
        Node(kind: .type)
    ])
}
```

Check that `Node` has these initializer forms. `Node(kind:children:)` and `Node(kind:text:)` may use `Node.create(kind:children:)` or `NodeFactory`. Verify the Node API in the Demangling module before writing tests. If `Node` uses a factory pattern, adjust accordingly.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TypeAttributeInferrerTests 2>&1 | head -30`
Expected: Compilation error — `TypeAttributeInferrer` does not exist yet

- [ ] **Step 3: Implement `TypeAttributeInferrer`**

Create `Sources/SwiftInterface/AttributeInference/TypeAttributeInferrer.swift`:

```swift
import SwiftDump
import MachOSwiftSection
import Demangling

public struct TypeAttributeInferrer: Sendable {
    public let resilienceAwareAttributes: Bool

    public init(resilienceAwareAttributes: Bool) {
        self.resilienceAwareAttributes = resilienceAwareAttributes
    }

    public func infer(for typeDefinition: TypeDefinition) -> [SwiftAttribute] {
        var attributes: [SwiftAttribute] = []

        // Only infer member-based attributes for struct/class/enum, never for protocols
        inferPropertyWrapper(typeDefinition: typeDefinition, into: &attributes)
        inferResultBuilder(typeDefinition: typeDefinition, into: &attributes)
        inferDynamicMemberLookup(typeDefinition: typeDefinition, into: &attributes)
        inferDynamicCallable(typeDefinition: typeDefinition, into: &attributes)

        if resilienceAwareAttributes {
            inferFrozen(typeDefinition: typeDefinition, into: &attributes)
            inferUsableFromInline(typeDefinition: typeDefinition, into: &attributes)
        }

        inferObjCType(typeDefinition: typeDefinition, into: &attributes)

        return attributes.sorted()
    }

    // MARK: - Detection Predicates (static for testability)

    static func hasWrappedValueMember(fields: [FieldDefinition], variables: [VariableDefinition]) -> Bool {
        fields.contains { $0.name == "wrappedValue" }
            || variables.contains { $0.name == "wrappedValue" }
    }

    static func hasBuildBlockMethod(staticFunctions: [FunctionDefinition]) -> Bool {
        staticFunctions.contains { $0.name == "buildBlock" }
    }

    static func hasDynamicMemberSubscript(subscripts: [SubscriptDefinition], staticSubscripts: [SubscriptDefinition]) -> Bool {
        let allSubscripts = subscripts + staticSubscripts
        return allSubscripts.contains { subscriptDefinition in
            subscriptDefinition.node.children
                .first { $0.kind == .labelList }?
                .children.first?.text == "dynamicMember"
        }
    }

    static func hasDynamicallyCallMethod(functions: [FunctionDefinition], staticFunctions: [FunctionDefinition]) -> Bool {
        let allFunctions = functions + staticFunctions
        return allFunctions.contains { $0.name == "dynamicallyCall" }
    }

    // MARK: - Private Inference Methods

    private func inferPropertyWrapper(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasWrappedValueMember(fields: typeDefinition.fields, variables: typeDefinition.variables) {
            attributes.append(.propertyWrapper)
        }
    }

    private func inferResultBuilder(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasBuildBlockMethod(staticFunctions: typeDefinition.staticFunctions) {
            attributes.append(.resultBuilder)
        }
        // Also check extensions for this type
        for extensionDefinition in typeDefinition.extensions {
            if Self.hasBuildBlockMethod(staticFunctions: extensionDefinition.staticFunctions) {
                attributes.append(.resultBuilder)
                return
            }
        }
    }

    private func inferDynamicMemberLookup(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasDynamicMemberSubscript(subscripts: typeDefinition.subscripts, staticSubscripts: typeDefinition.staticSubscripts) {
            attributes.append(.dynamicMemberLookup)
        }
    }

    private func inferDynamicCallable(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        if Self.hasDynamicallyCallMethod(functions: typeDefinition.functions, staticFunctions: typeDefinition.staticFunctions) {
            attributes.append(.dynamicCallable)
        }
    }

    private func inferFrozen(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        let descriptor = typeDefinition.type.descriptor
        // @frozen only applies to struct and enum
        guard descriptor.kind == .struct || descriptor.kind == .enum else { return }
        if descriptor.typeContextDescriptorFlags.noMetadataInitialization {
            attributes.append(.frozen)
        }
    }

    private func inferUsableFromInline(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        // hasImportInfo indicates the type has import info trailing field
        // The trailing field prefix byte 0x02 = @usableFromInline
        // TODO: Parse the actual trailing import info field value
        // For now, hasImportInfo is a necessary but not sufficient condition
        // This will be refined when TypeImportInfo parsing is added
        if typeDefinition.type.descriptor.typeContextDescriptorFlags.hasImportInfo {
            attributes.append(.usableFromInline)
        }
    }

    private func inferObjCType(typeDefinition: TypeDefinition, into attributes: inout [SwiftAttribute]) {
        // @objc("CustomName") on class — from ClassFlags.hasCustomObjCName
        guard let classDescriptor = typeDefinition.type.descriptor as? ClassDescriptor else { return }
        if classDescriptor.classFlags.contains(.hasCustomObjCName) {
            attributes.append(.objcType)
        }
    }
}
```

Note: Verify the exact API for accessing `descriptor.kind`, `descriptor.typeContextDescriptorFlags`, and `ClassDescriptor.classFlags` by reading the actual types. The descriptor is accessed via `typeDefinition.type.descriptor` — check `TypeContextWrapper` to see what type this returns and how to downcast to `ClassDescriptor`.

Look at:
- `Sources/MachOSwiftSection/Models/Type/TypeContextWrapper.swift` for the `descriptor` property type
- `Sources/MachOSwiftSection/Models/Type/TypeContextDescriptorProtocol.swift` for `typeContextDescriptorFlags`
- `Sources/MachOSwiftSection/Models/Type/Class/ClassDescriptor.swift` (or similar) for `classFlags`

Adjust the code to match the actual APIs found.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TypeAttributeInferrerTests 2>&1 | head -50`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftInterface/AttributeInference/TypeAttributeInferrer.swift \
      Tests/SwiftInterfaceTests/TypeAttributeInferrerTests.swift
git commit -m "feat: implement TypeAttributeInferrer for type-level attribute inference"
```

---

### Task 5: Implement `MemberAttributeInferrer`

**Files:**
- Create: `Sources/SwiftInterface/AttributeInference/MemberAttributeInferrer.swift`
- Test: `Tests/SwiftInterfaceTests/MemberAttributeInferrerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiftInterfaceTests/MemberAttributeInferrerTests.swift`:

```swift
import Testing
import SwiftDump
import Demangling
import MachOSwiftSection
@testable import SwiftInterface

@Suite("MemberAttributeInferrer Tests")
struct MemberAttributeInferrerTests {
    let inferrer = MemberAttributeInferrer(resilienceAwareAttributes: false)
    let resilientInferrer = MemberAttributeInferrer(resilienceAwareAttributes: true)

    @Test("detects @objc from objCAttribute node kind")
    func detectObjC() {
        // An @objc thunk symbol has .objCAttribute as the first child of .global
        let objcNode = Node(kind: .global, children: [
            Node(kind: .objCAttribute),
            Node(kind: .function, children: [
                Node(kind: .class),
                Node(kind: .identifier, text: "viewDidLoad"),
                Node(kind: .type)
            ])
        ])
        let attributes = MemberAttributeInferrer.detectFromThunkNode(objcNode)
        #expect(attributes.contains(.objc))
    }

    @Test("detects @nonobjc from nonObjCAttribute node kind")
    func detectNonobjc() {
        let nonobjcNode = Node(kind: .global, children: [
            Node(kind: .nonObjCAttribute),
            Node(kind: .function, children: [
                Node(kind: .class),
                Node(kind: .identifier, text: "someMethod"),
                Node(kind: .type)
            ])
        ])
        let attributes = MemberAttributeInferrer.detectFromThunkNode(nonobjcNode)
        #expect(attributes.contains(.nonobjc))
    }

    @Test("detects dynamic from MethodDescriptorFlags")
    func detectDynamic() {
        // isDynamic is bit 5 (0x20)
        let flags = MethodDescriptorFlags(rawValue: 0x20)
        let attributes = MemberAttributeInferrer.detectFromMethodFlags(flags)
        #expect(attributes.contains(.dynamic))
    }

    @Test("does not detect dynamic when flag is not set")
    func detectDynamicAbsent() {
        let flags = MethodDescriptorFlags(rawValue: 0x00)
        let attributes = MemberAttributeInferrer.detectFromMethodFlags(flags)
        #expect(!attributes.contains(.dynamic))
    }
}
```

Adjust the `Node` construction to match the actual Demangling API (factory methods vs direct init).

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MemberAttributeInferrerTests 2>&1 | head -30`
Expected: Compilation error — `MemberAttributeInferrer` does not exist yet

- [ ] **Step 3: Implement `MemberAttributeInferrer`**

Create `Sources/SwiftInterface/AttributeInference/MemberAttributeInferrer.swift`:

```swift
import SwiftDump
import MachOSwiftSection
import Demangling

public struct MemberAttributeInferrer: Sendable {
    public let resilienceAwareAttributes: Bool

    public init(resilienceAwareAttributes: Bool) {
        self.resilienceAwareAttributes = resilienceAwareAttributes
    }

    /// Detect attributes from a thunk symbol node (e.g., @objc thunk).
    /// The node structure is: global(objCAttribute, function(...))
    public static func detectFromThunkNode(_ rootNode: Node) -> [SwiftAttribute] {
        var attributes: [SwiftAttribute] = []
        for child in rootNode.children {
            switch child.kind {
            case .objCAttribute:
                attributes.append(.objc)
            case .nonObjCAttribute:
                attributes.append(.nonobjc)
            default:
                break
            }
        }
        return attributes
    }

    /// Detect attributes from MethodDescriptorFlags.
    public static func detectFromMethodFlags(_ flags: MethodDescriptorFlags) -> [SwiftAttribute] {
        var attributes: [SwiftAttribute] = []
        if flags.isDynamic {
            attributes.append(.dynamic)
        }
        return attributes
    }

    /// Detect @inlinable from isSerialized child in specialization nodes.
    /// Only used when resilienceAwareAttributes is true.
    public static func detectFromSpecializationNode(_ node: Node) -> [SwiftAttribute] {
        var attributes: [SwiftAttribute] = []
        if hasSerializedChild(node) {
            attributes.append(.inlinable)
        }
        return attributes
    }

    static func hasSerializedChild(_ node: Node) -> Bool {
        if node.kind == .isSerialized {
            return true
        }
        for child in node.children {
            if hasSerializedChild(child) {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MemberAttributeInferrerTests 2>&1 | head -50`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftInterface/AttributeInference/MemberAttributeInferrer.swift \
      Tests/SwiftInterfaceTests/MemberAttributeInferrerTests.swift
git commit -m "feat: implement MemberAttributeInferrer for member-level attribute detection"
```

---

### Task 6: Integrate Member Attribute Detection into `DefinitionBuilder`

**Files:**
- Modify: `Sources/SwiftInterface/Components/Definitions/DefinitionBuilder.swift`
- Modify: `Sources/MachOSymbols/SymbolIndexStore.swift` (read-only reference — understand `symbolsByKind`)

The goal is to detect `@objc`/`@nonobjc` thunk symbols and mark the corresponding `FunctionDefinition`/`VariableDefinition`/`SubscriptDefinition` with the appropriate attribute. Also detect `dynamic` from `MethodDescriptorFlags`.

- [ ] **Step 1: Add `dynamic` detection to `DefinitionBuilder.functions()`**

In `Sources/SwiftInterface/Components/Definitions/DefinitionBuilder.swift`, inside the `functions()` method (line 83-101), after constructing the `FunctionDefinition` at line 98, check if the method descriptor has `isDynamic`:

Find the line where `FunctionDefinition(...)` is created (around line 93-100). After the definition is created, add attribute detection:

```swift
var functionDefinition = FunctionDefinition(
    node: functionNode,
    name: functionNode.identifier ?? "",
    kind: .function,
    symbol: demangledSymbol,
    isGlobalOrStatic: isGlobalOrStatic,
    methodDescriptor: descriptor,
    offset: offset,
    vtableOffset: vtableOffset
)

// Detect dynamic attribute from method descriptor flags
if let descriptor = descriptor, descriptor.flags.isDynamic {
    functionDefinition.attributes.append(.dynamic)
}
```

Note: `FunctionDefinition` uses `@MemberwiseInit` and is a struct. After adding the `attributes` field in Task 2, the struct should be mutable (use `var` not `let`). Check the existing code to see if definitions are created with `let` or `var` — if `let`, change to `var`.

- [ ] **Step 2: Add `dynamic` detection to `DefinitionBuilder.allocators()`**

Same pattern in the `allocators()` method (line 65-81). After constructing the `FunctionDefinition`, check for `isDynamic`:

```swift
if let descriptor = descriptor, descriptor.flags.isDynamic {
    functionDefinition.attributes.append(.dynamic)
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftInterface/Components/Definitions/DefinitionBuilder.swift
git commit -m "feat: detect dynamic attribute from MethodDescriptorFlags in DefinitionBuilder"
```

---

### Task 7: Integrate @objc/@nonobjc Thunk Detection

**Files:**
- Modify: `Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift` (the `index(in:)` method)
- Read: `Sources/MachOSymbols/SymbolIndexStore.swift` (understand thunk symbol access)

The `@objc` thunk symbols are stored in `SymbolIndexStore.symbolsByKind[.objCAttribute]` but never reach `DefinitionBuilder`. After `DefinitionBuilder` builds all member definitions, cross-reference thunk symbols with built definitions by member name.

- [ ] **Step 1: Understand thunk symbol access**

Read `Sources/MachOSymbols/SymbolIndexStore.swift` to understand:
1. How `symbolsByKind` is accessed — it's on the `Storage` object
2. How to query symbols of kind `.objCAttribute` and `.nonObjCAttribute`
3. How to extract the inner function/variable name from a thunk node

The thunk node structure is: `global(objCAttribute, function(context, identifier(name), ...))`. The member name is in `rootNode.children[1]` (the function/variable node after the attribute marker), then navigate to `identifier` child for the name.

Check how `SymbolIndexStore` exposes its storage and whether `TypeDefinition.index()` has access to the symbol index store. Look at `TypeDefinition.index(in:)` — it receives `machO` and accesses `machO.symbolIndexStore` or similar.

- [ ] **Step 2: Add @objc/@nonobjc cross-referencing in `TypeDefinition.index()`**

After all `DefinitionBuilder` calls complete (around line 240 in `TypeDefinition.index()`), add a pass that:
1. Queries the symbol index store for `.objCAttribute` and `.nonObjCAttribute` symbols belonging to this type
2. For each thunk symbol, extracts the member name
3. Finds the matching definition by name
4. Appends `.objc` or `.nonobjc` to the definition's `attributes`

```swift
// After all DefinitionBuilder calls, cross-reference @objc thunks
private func applyObjCAttributes(symbolIndexStore: SymbolIndexStore, typeName: String) {
    let objcThunks = symbolIndexStore.symbols(ofKind: .objCAttribute, forType: typeName)
    for thunk in objcThunks {
        guard let memberNode = thunk.demangledNode.children.first(where: { $0.kind != .objCAttribute }),
              let memberName = memberNode.identifier else { continue }

        // Find matching function/variable/subscript and mark as @objc
        if let index = functions.firstIndex(where: { $0.name == memberName }) {
            functions[index].attributes.append(.objc)
        } else if let index = staticFunctions.firstIndex(where: { $0.name == memberName }) {
            staticFunctions[index].attributes.append(.objc)
        } else if let index = variables.firstIndex(where: { $0.name == memberName }) {
            variables[index].attributes.append(.objc)
        } else if let index = staticVariables.firstIndex(where: { $0.name == memberName }) {
            staticVariables[index].attributes.append(.objc)
        }
    }

    // Same for @nonobjc
    let nonobjcThunks = symbolIndexStore.symbols(ofKind: .nonObjCAttribute, forType: typeName)
    for thunk in nonobjcThunks {
        guard let memberNode = thunk.demangledNode.children.first(where: { $0.kind != .nonObjCAttribute }),
              let memberName = memberNode.identifier else { continue }

        if let index = functions.firstIndex(where: { $0.name == memberName }) {
            functions[index].attributes.append(.nonobjc)
        } else if let index = staticFunctions.firstIndex(where: { $0.name == memberName }) {
            staticFunctions[index].attributes.append(.nonobjc)
        }
        // variables/subscripts can also be @nonobjc
    }
}
```

**Important:** This is pseudocode. The actual API for querying symbols by kind and type from `SymbolIndexStore` needs to be verified. The `SymbolIndexStore` may not have a direct `symbols(ofKind:forType:)` method — you may need to access the internal storage or add a new query method. Look at:
- How `TypeDefinition.index()` already queries the symbol index store (lines 169-238 of TypeDefinition.swift)
- The `SymbolIndexStore.memberSymbols(of:for:in:)` API
- Whether `symbolsByKind` storage is accessible

If the symbol index store doesn't expose a suitable API, add one.

- [ ] **Step 3: Add @inlinable detection (resilience-gated)**

When `resilienceAwareAttributes` is enabled, also scan for specialization symbols that contain `.isSerialized` nodes. These indicate the original function is `@inlinable`. The approach:

1. Query the symbol index store for specialization symbols (`.functionSignatureSpecialization`, `.genericSpecialization`, etc.) that have a `.isSerialized` child
2. Extract the original function name from the specialization node
3. Match against built `FunctionDefinition`s by name
4. Append `.inlinable` to matched definitions

This is similar to the @objc cross-referencing but uses different node kinds. The `MemberAttributeInferrer.detectFromSpecializationNode()` method (from Task 5) handles the node inspection; this step handles the cross-referencing.

```swift
if resilienceAwareAttributes {
    // Query specialization symbols and detect @inlinable
    let specializationKinds: [Node.Kind] = [.functionSignatureSpecialization, .genericSpecialization]
    for kind in specializationKinds {
        let symbols = symbolIndexStore.symbols(ofKind: kind)
        for symbol in symbols {
            if MemberAttributeInferrer.hasSerializedChild(symbol.demangledNode) {
                // Extract original function name and match
                guard let functionNode = symbol.demangledNode.first(of: .function),
                      let functionName = functionNode.identifier else { continue }
                if let index = functions.firstIndex(where: { $0.name == functionName }) {
                    if !functions[index].attributes.contains(.inlinable) {
                        functions[index].attributes.append(.inlinable)
                    }
                }
            }
        }
    }
}
```

Adjust the API for querying specialization symbols based on actual `SymbolIndexStore` methods available.

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftInterface/Components/Definitions/TypeDefinition.swift
git commit -m "feat: cross-reference @objc/@nonobjc thunks and @inlinable specializations with member definitions"
```

---

### Task 8: Emit Type-Level Attributes in `SwiftInterfacePrinter`

**Files:**
- Modify: `Sources/SwiftInterface/SwiftInterfacePrinter.swift:53-103` (printTypeDefinition)
- Modify: `Sources/SwiftInterface/SwiftInterfaceBuilder.swift` (pass config to inferrer)

- [ ] **Step 1: Add `TypeAttributeInferrer` to `SwiftInterfacePrinter`**

In `Sources/SwiftInterface/SwiftInterfacePrinter.swift`, add a property to the printer (check where existing properties are declared):

```swift
let typeAttributeInferrer: TypeAttributeInferrer
```

Initialize it from the configuration. Check how `SwiftInterfacePrinter` is currently initialized — look at its `init` method and add `typeAttributeInferrer` as a parameter, or derive it from `configuration`:

```swift
let typeAttributeInferrer = TypeAttributeInferrer(
    resilienceAwareAttributes: configuration.resilienceAwareAttributes
)
```

- [ ] **Step 2: Integrate inference in `printTypeDefinition`**

In `printTypeDefinition` (line 53-103), after `typeDefinition.index(in:)` (line 59) and before the dumper creation (line 62), add:

```swift
typeDefinition.attributes = typeAttributeInferrer.infer(for: typeDefinition)
```

- [ ] **Step 3: Emit attributes before `DeclarationBlock`**

The `DeclarationBlock` automatically adds `Indent(level-1)` before the header. Type-level attributes should appear as separate lines before the declaration. Insert them before the `DeclarationBlock`:

```swift
// Emit type-level attributes
for attribute in typeDefinition.attributes {
    Indent(level: level - 1)
    Keyword(attribute.keyword)
    BreakLine()
}

try await DeclarationBlock(level: level) {
    try await dumper.declaration
} body: {
    // ... existing body ...
}
```

**Note:** `DeclarationBlock` is inside a `@SemanticStringBuilder`. The attributes for-loop must produce `SemanticString` components. Verify that `Indent`, `Keyword`, and `BreakLine` work inside a `@SemanticStringBuilder` context with a `for` loop. The `@SemanticStringBuilder` result builder likely supports `for-in` loops via `buildArray`.

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftInterface/SwiftInterfacePrinter.swift \
      Sources/SwiftInterface/SwiftInterfaceBuilder.swift
git commit -m "feat: emit type-level attributes before type declarations"
```

---

### Task 9: Emit Member-Level Attributes in Printer

**Files:**
- Modify: `Sources/SwiftInterface/SwiftInterfacePrinter.swift:351-404` (printVariable, printFunction, printSubscript, and their throwing variants)

Member-level attributes (`@objc`, `dynamic`, `@nonobjc`, `@inlinable`) need to be emitted before each member declaration. The attributes are stored in the definition's `attributes` field (populated by Tasks 6 and 7).

- [ ] **Step 1: Add attribute output to `printThrowingFunction`**

In `printThrowingFunction` (lines 394-398), before calling `printer.printRoot(function.node)`, emit attributes:

```swift
@SemanticStringBuilder
public func printThrowingFunction(_ function: FunctionDefinition, level: Int) async throws -> SemanticString {
    for attribute in function.attributes {
        Keyword(attribute.keyword)
        Space()
    }
    var printer = FunctionNodePrinter(isOverride: function.isOverride, delegate: self)
    try await printer.printRoot(function.node)
}
```

- [ ] **Step 2: Add attribute output to `printThrowingVariable`**

In `printThrowingVariable` (lines 388-392):

```swift
@SemanticStringBuilder
public func printThrowingVariable(_ variable: VariableDefinition, level: Int) async throws -> SemanticString {
    for attribute in variable.attributes {
        Keyword(attribute.keyword)
        Space()
    }
    var printer = VariableNodePrinter(isStored: variable.isStored, isOverride: variable.isOverride, hasSetter: variable.hasSetter, indentation: level, delegate: self)
    try await printer.printRoot(variable.node)
}
```

- [ ] **Step 3: Add attribute output to `printThrowingSubscript`**

In `printThrowingSubscript` (lines 400-403):

```swift
@SemanticStringBuilder
public func printThrowingSubscript(_ `subscript`: SubscriptDefinition, level: Int) async throws -> SemanticString {
    for attribute in `subscript`.attributes {
        Keyword(attribute.keyword)
        Space()
    }
    var printer = SubscriptNodePrinter(isOverride: `subscript`.isOverride, hasSetter: `subscript`.hasSetter, indentation: level, delegate: self)
    try await printer.printRoot(`subscript`.node)
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftInterface/SwiftInterfacePrinter.swift
git commit -m "feat: emit member-level attributes before member declarations"
```

---

### Task 10: Implement `@retroactive` for Conformance Extensions

**Files:**
- Modify: `Sources/SwiftInterface/Components/Definitions/ExtensionDefinition.swift`
- Modify: `Sources/SwiftInterface/SwiftInterfaceIndexer.swift` (indexConformances)
- Modify: `Sources/SwiftInterface/SwiftInterfacePrinter.swift` (printExtensionDefinition)

- [ ] **Step 1: Add `isRetroactive` to `ExtensionDefinition`**

In `Sources/SwiftInterface/Components/Definitions/ExtensionDefinition.swift`, add after line 19 (`associatedType`):

```swift
    public internal(set) var isRetroactive: Bool = false
```

- [ ] **Step 2: Set `isRetroactive` in `indexConformances()`**

In `Sources/SwiftInterface/SwiftInterfaceIndexer.swift`, inside `indexConformances()`, after creating the `ExtensionDefinition` (around line 476), set the flag:

```swift
let extensionDefinition = ExtensionDefinition(
    extensionName: typeName.extensionName,
    genericSignature: protocolConformance.conditionalRequirements.isEmpty ? nil : genericSignatureNode,
    protocolConformance: protocolConformance,
    associatedType: associatedType,
    in: machO
)
extensionDefinition.isRetroactive = protocolConformance.flags.isRetroactive
```

- [ ] **Step 3: Emit `@retroactive` in `printExtensionDefinition`**

In `Sources/SwiftInterface/SwiftInterfacePrinter.swift`, inside `printExtensionDefinition` (lines 155-214), at the point where the protocol name is printed (lines 168-173), add `@retroactive` before the protocol name:

Change from:
```swift
if let protocolConformance = extensionDefinition.protocolConformance,
   let protocolName = try? await protocolConformance.dumpProtocolName(using: .demangleOptions(.interfaceTypeBuilderOnly), in: machO) {
    Standard(":")
    Space()
    protocolName
}
```

To:
```swift
if let protocolConformance = extensionDefinition.protocolConformance,
   let protocolName = try? await protocolConformance.dumpProtocolName(using: .demangleOptions(.interfaceTypeBuilderOnly), in: machO) {
    Standard(":")
    Space()
    if extensionDefinition.isRetroactive {
        Keyword(.atRetroactive)
        Space()
    }
    protocolName
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | head -30`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftInterface/Components/Definitions/ExtensionDefinition.swift \
      Sources/SwiftInterface/SwiftInterfaceIndexer.swift \
      Sources/SwiftInterface/SwiftInterfacePrinter.swift
git commit -m "feat: emit @retroactive for retroactive protocol conformances"
```

---

### Task 11: Integration Tests with Real Binaries

**Files:**
- Create: `Tests/SwiftInterfaceTests/AttributeInferenceIntegrationTests.swift`

- [ ] **Step 1: Write integration tests using Apple SDK frameworks**

Create `Tests/SwiftInterfaceTests/AttributeInferenceIntegrationTests.swift`:

```swift
import Testing
import MachOKit
import MachOSwiftSection
import SwiftDump
@testable import SwiftInterface

@Suite("Attribute Inference Integration Tests")
struct AttributeInferenceIntegrationTests {
    // Test @propertyWrapper detection on a known type (e.g., SwiftUI.State if available,
    // or a type from the test binary that has wrappedValue)
    @Test("SwiftUI.Binding should be detected as @propertyWrapper and @dynamicMemberLookup")
    func swiftUIBindingAttributes() async throws {
        // Load SwiftUI framework from dyld shared cache or framework path
        // Build a SwiftInterfaceBuilder, prepare(), then check TypeDefinition.attributes
        // for the Binding type

        // The exact setup depends on how tests currently load frameworks.
        // Look at existing tests in SwiftInterfaceTests/ for the pattern.
        // Specifically: SwiftInterfaceBuilderTests.swift and the Snapshot tests.
    }

    // Test @frozen detection with resilienceAwareAttributes = true
    @Test("Standard library Array should be @frozen with resilience-aware enabled")
    func stdlibArrayFrozen() async throws {
        // Load Swift standard library
        // Enable resilienceAwareAttributes
        // Check that Array's TypeDefinition.attributes contains .frozen
    }

    // Test @resultBuilder detection
    @Test("SwiftUI.ViewBuilder should be detected as @resultBuilder")
    func swiftUIViewBuilderResultBuilder() async throws {
        // Load SwiftUI framework
        // Check ViewBuilder type's attributes contains .resultBuilder
    }

    // Test that resilienceAwareAttributes = false (default) does not emit @frozen
    @Test("Standard library Array should NOT be @frozen with default config")
    func stdlibArrayNotFrozenByDefault() async throws {
        // Load Swift standard library with default config
        // Check that Array's TypeDefinition.attributes does NOT contain .frozen
    }
}
```

**Important:** Look at existing test files (`SwiftInterfaceBuilderTests.swift`, snapshot tests) to understand the exact pattern for loading frameworks, creating builders, and accessing types. Copy the setup pattern from there.

- [ ] **Step 2: Run tests**

Run: `swift test --filter AttributeInferenceIntegrationTests 2>&1 | head -50`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftInterfaceTests/AttributeInferenceIntegrationTests.swift
git commit -m "test: add attribute inference integration tests with Apple SDK frameworks"
```

---

### Task 12: Full Test Suite Verification

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All existing tests still pass. No regressions.

- [ ] **Step 2: Run the CLI tool to verify output**

Run the CLI tool against a known framework to visually verify attribute output:

```bash
swift run swift-section interface /System/Library/Frameworks/SwiftUI.framework/SwiftUI 2>&1 | head -100
```

Look for:
- `@propertyWrapper` before types like `State`, `Binding`, `Environment`
- `@resultBuilder` before `ViewBuilder`
- `@dynamicMemberLookup` before `Binding`
- `@objc` before ObjC-exposed methods

- [ ] **Step 3: Run with resilience-aware attributes**

Check if the CLI has a flag for this, or modify a test to enable it:

```bash
swift run swift-section interface --resilience-aware /System/Library/Frameworks/SwiftUI.framework/SwiftUI 2>&1 | head -100
```

Look for `@frozen` on value types.

If no CLI flag exists, this step verifies through the integration tests from Task 11 instead.

- [ ] **Step 4: Commit any fixes**

If any issues were found and fixed during verification:

```bash
git add -A
git commit -m "fix: address issues found during attribute inference verification"
```
