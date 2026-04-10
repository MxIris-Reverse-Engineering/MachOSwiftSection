# SymbolTestsCore Integration Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend SymbolTestsCore with attribute-focused types and add comprehensive integration tests covering both new and existing functionality with structured assertions.

**Architecture:** Add new Swift types to the existing SymbolTestsCore Xcode framework project, rebuild it, then write two test files — one middle-layer test using `SwiftInterfaceIndexer`/`TypeDefinition` APIs directly, and one end-to-end test using `SwiftInterfaceBuilder` output strings. Tests load the compiled `SymbolTestsCore.framework` binary via the existing `MachOFileTests` base class.

**Tech Stack:** Swift Testing framework (`@Test`, `#expect`, `#require`), `SwiftInterfaceIndexer`, `TypeAttributeInferrer`, `MemberAttributeInferrer`, `OrderedMember`, `SwiftInterfaceBuilder`.

---

### Task 1: Add New Types to SymbolTestsCore

**Files:**
- Modify: `Tests/Projects/SymbolTests/SymbolTestsCore/SymbolTestsCore.swift`

- [ ] **Step 1: Add PropertyWrapperStruct**

Append to end of `SymbolTestsCore.swift`:

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

- [ ] **Step 2: Add ResultBuilderStruct**

Append:

```swift
@resultBuilder
public struct ResultBuilderStruct<Element> {
    public static func buildBlock(_ components: Element...) -> [Element] { components }
    public static func buildOptional(_ component: [Element]?) -> [Element] { component ?? [] }
}
```

- [ ] **Step 3: Add DynamicMemberLookupStruct**

Append:

```swift
@dynamicMemberLookup
public struct DynamicMemberLookupStruct {
    public subscript(dynamicMember member: String) -> Int { 0 }
}
```

- [ ] **Step 4: Add DynamicCallableStruct**

Append:

```swift
@dynamicCallable
public struct DynamicCallableStruct {
    public func dynamicallyCall(withArguments arguments: [Int]) -> Int {
        arguments.reduce(0, +)
    }

    public func dynamicallyCall(withKeywordArguments arguments: KeyValuePairs<String, Int>) -> Int { 0 }
}
```

- [ ] **Step 5: Add ObjCAttributeClass**

Append:

```swift
public class ObjCAttributeClass: NSObject {
    @objc public func objcMethod() {}
    @nonobjc public func nonobjcMethod() {}
    @objc public dynamic func objcDynamicMethod() {}
}
```

- [ ] **Step 6: Commit**

```bash
git add Tests/Projects/SymbolTests/SymbolTestsCore/SymbolTestsCore.swift
git commit -m "feat: add attribute-focused types to SymbolTestsCore"
```

---

### Task 2: Rebuild SymbolTests Xcode Project

**Files:**
- Output: `Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore`

- [ ] **Step 1: Build SymbolTests in Release configuration**

```bash
xcodebuild -project Tests/Projects/SymbolTests/SymbolTests.xcodeproj \
  -scheme SymbolTests \
  -configuration Release \
  -derivedDataPath Tests/Projects/SymbolTests/DerivedData \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Verify built binary contains new types**

```bash
nm Tests/Projects/SymbolTests/DerivedData/SymbolTests/Build/Products/Release/SymbolTestsCore.framework/Versions/A/SymbolTestsCore | grep -c "PropertyWrapperStruct\|ResultBuilderStruct\|DynamicMemberLookupStruct\|DynamicCallableStruct\|ObjCAttributeClass"
```

Expected: Non-zero count (new symbols present in binary).

- [ ] **Step 3: Commit built binary**

```bash
git add Tests/Projects/SymbolTests/DerivedData/
git commit -m "build: rebuild SymbolTests with new attribute-focused types"
```

---

### Task 3: Write Middle-Layer Integration Tests — Type Parsing and Fields

**Files:**
- Create: `Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift`

- [ ] **Step 1: Create test file with shared setup**

Create `Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift`:

```swift
import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftDump

// MARK: - Shared Setup

@Suite(.serialized)
final class SymbolTestsCoreIntegrationTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func preparedIndexer() async throws -> SwiftInterfaceIndexer<MachOFile> {
        let indexer = SwiftInterfaceIndexer(in: machOFile)
        try await indexer.prepare()
        return indexer
    }

    private func findTypeDefinition(named typeName: String, in indexer: SwiftInterfaceIndexer<MachOFile>) -> TypeDefinition? {
        indexer.allTypeDefinitions.values.first { $0.typeName.name.hasSuffix(typeName) }
    }

    private func findProtocolDefinition(named protocolName: String, in indexer: SwiftInterfaceIndexer<MachOFile>) -> ProtocolDefinition? {
        indexer.allProtocolDefinitions.values.first { $0.protocolName.name.hasSuffix(protocolName) }
    }
}

// MARK: - Type Parsing

extension SymbolTestsCoreIntegrationTests {
    @Test func parsedTypeNamesContainExpectedTypes() async throws {
        let indexer = try await preparedIndexer()
        let typeNames = Set(indexer.allTypeDefinitions.values.map { $0.typeName.currentName })

        #expect(typeNames.contains("StructTest"))
        #expect(typeNames.contains("ClassTest"))
        #expect(typeNames.contains("SubclassTest"))
        #expect(typeNames.contains("FinalClassTest"))
        #expect(typeNames.contains("MultiPayloadEnumTests"))
        #expect(typeNames.contains("GenericRequirementTest"))
        #expect(typeNames.contains("GenericPackTest"))
        #expect(typeNames.contains("GenericValueTest"))
        #expect(typeNames.contains("OpaqueReturnTypeTest"))
        #expect(typeNames.contains("PropertyWrapperStruct"))
        #expect(typeNames.contains("ResultBuilderStruct"))
        #expect(typeNames.contains("DynamicMemberLookupStruct"))
        #expect(typeNames.contains("DynamicCallableStruct"))
        #expect(typeNames.contains("ObjCAttributeClass"))
    }

    @Test func typeKindsAreCorrect() async throws {
        let indexer = try await preparedIndexer()

        let structTest = try #require(findTypeDefinition(named: "StructTest", in: indexer))
        #expect(structTest.typeName.kind == .struct)

        let classTest = try #require(findTypeDefinition(named: "ClassTest", in: indexer))
        #expect(classTest.typeName.kind == .class)

        let multiPayloadEnumTests = try #require(findTypeDefinition(named: "MultiPayloadEnumTests", in: indexer))
        #expect(multiPayloadEnumTests.typeName.kind == .enum)
    }

    @Test func parsedProtocolNamesContainExpectedProtocols() async throws {
        let indexer = try await preparedIndexer()
        let protocolNames = Set(indexer.allProtocolDefinitions.values.map { $0.protocolName.currentName })

        #expect(protocolNames.contains("ProtocolTest"))
        #expect(protocolNames.contains("ProtocolWitnessTableTest"))
        #expect(protocolNames.contains("TestCollection"))
        #expect(protocolNames.contains("ProtocolPrimaryAssociatedTypeTest"))
    }
}

// MARK: - Fields and Stored Properties

extension SymbolTestsCoreIntegrationTests {
    @Test func storedPropertyFieldsAreCorrect() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "GenericStructNonRequirement", in: indexer))
        try await typeDefinition.index(in: machOFile)

        let fieldNames = typeDefinition.fields.map(\.name)
        #expect(fieldNames == ["field1", "field2", "field3"])
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
swift test --filter SymbolTestsCoreIntegrationTests 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift
git commit -m "test: add type parsing and fields integration tests"
```

---

### Task 4: Add Protocol Conformance and Retroactive Tests

**Files:**
- Modify: `Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift`

- [ ] **Step 1: Add protocol conformance tests**

Append to `SymbolTestsCoreIntegrationTests.swift`:

```swift
// MARK: - Protocol Conformances

extension SymbolTestsCoreIntegrationTests {
    @Test func structTestConformsToExpectedProtocols() async throws {
        let indexer = try await preparedIndexer()
        let conformancesByType = indexer.protocolConformancesByTypeName

        let structTestConformances = conformancesByType.first { $0.key.name.hasSuffix("StructTest") }
        let protocolNames = try #require(structTestConformances?.value.keys.map(\.name))

        #expect(protocolNames.contains(where: { $0.hasSuffix("ProtocolTest") }))
        #expect(protocolNames.contains(where: { $0.hasSuffix("ProtocolWitnessTableTest") }))
    }

    @Test func genericRequirementTestConformsToProtocolTest() async throws {
        let indexer = try await preparedIndexer()
        let conformancesByType = indexer.protocolConformancesByTypeName

        let genericConformances = conformancesByType.first { $0.key.name.hasSuffix("GenericRequirementTest") }
        let protocolNames = try #require(genericConformances?.value.keys.map(\.name))

        #expect(protocolNames.contains(where: { $0.hasSuffix("ProtocolTest") }))
    }

    @Test func retroactiveConformanceIsDetected() async throws {
        let indexer = try await preparedIndexer()
        let conformanceExtensions = indexer.conformanceExtensionDefinitions

        let neverExtensions = conformanceExtensions.filter { $0.key.name == "Swift.Never" }
        let hasRetroactive = neverExtensions.values.flatMap { $0 }.contains { $0.isRetroactive }

        #expect(hasRetroactive)
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter SymbolTestsCoreIntegrationTests 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift
git commit -m "test: add protocol conformance and retroactive integration tests"
```

---

### Task 5: Add Class Hierarchy, Nested Types, and Associated Types Tests

**Files:**
- Modify: `Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift`

- [ ] **Step 1: Add class hierarchy and override tests**

Append to `SymbolTestsCoreIntegrationTests.swift`:

```swift
// MARK: - Class Hierarchy and Override

extension SymbolTestsCoreIntegrationTests {
    @Test func classTestOwnMethodsAreNotOverride() async throws {
        let indexer = try await preparedIndexer()
        let classTest = try #require(findTypeDefinition(named: "ClassTest", in: indexer))
        try await classTest.index(in: machOFile)

        for function in classTest.functions {
            #expect(!function.isOverride, "ClassTest.\(function.name) should not be override")
        }
    }

    @Test func subclassTestHasOverrideMethods() async throws {
        let indexer = try await preparedIndexer()
        let subclassTest = try #require(findTypeDefinition(named: "SubclassTest", in: indexer))
        try await subclassTest.index(in: machOFile)

        let instanceMethod = subclassTest.functions.first { $0.name == "instanceMethod" }
        #expect(instanceMethod?.isOverride == true)
    }

    @Test func finalClassTestHasOverrideMethods() async throws {
        let indexer = try await preparedIndexer()
        let finalClassTest = try #require(findTypeDefinition(named: "FinalClassTest", in: indexer))
        try await finalClassTest.index(in: machOFile)

        let instanceMethod = finalClassTest.functions.first { $0.name == "instanceMethod" }
        #expect(instanceMethod?.isOverride == true)
    }
}

// MARK: - Nested Types

extension SymbolTestsCoreIntegrationTests {
    @Test func genericRequirementTestHasNestedType() async throws {
        let indexer = try await preparedIndexer()
        let genericRequirementTest = try #require(findTypeDefinition(named: "GenericRequirementTest", in: indexer))

        let childNames = genericRequirementTest.typeChildren.map { $0.typeName.currentName }
        #expect(childNames.contains("RawRepresentableNestedStruct"))
    }

    @Test func rawRepresentableNestedStructHasNestedType() async throws {
        let indexer = try await preparedIndexer()
        let genericRequirementTest = try #require(findTypeDefinition(named: "GenericRequirementTest", in: indexer))

        let rawRepresentableNested = genericRequirementTest.typeChildren.first { $0.typeName.currentName == "RawRepresentableNestedStruct" }
        let nestedChildren = try #require(rawRepresentableNested?.typeChildren.map { $0.typeName.currentName })
        #expect(nestedChildren.contains("NestedStruct"))
    }
}

// MARK: - Associated Types

extension SymbolTestsCoreIntegrationTests {
    @Test func protocolTestHasAssociatedTypeBody() async throws {
        let indexer = try await preparedIndexer()
        let protocolTest = try #require(findProtocolDefinition(named: "ProtocolTest", in: indexer))
        try await protocolTest.index(in: machOFile)

        #expect(protocolTest.associatedTypes.contains("Body"))
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter SymbolTestsCoreIntegrationTests 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift
git commit -m "test: add class hierarchy, nested types, associated types integration tests"
```

---

### Task 6: Add Type Attribute Inference Integration Tests

**Files:**
- Modify: `Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift`

- [ ] **Step 1: Add type attribute inference tests**

Append to `SymbolTestsCoreIntegrationTests.swift`:

```swift
// MARK: - Type Attributes (Integration)

extension SymbolTestsCoreIntegrationTests {
    @Test func propertyWrapperStructInfersPropertyWrapperAttribute() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "PropertyWrapperStruct", in: indexer))
        try await typeDefinition.index(in: machOFile)

        let inferrer = TypeAttributeInferrer(resilienceAwareAttributes: false)
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(attributes.contains(.propertyWrapper))
    }

    @Test func resultBuilderStructInfersResultBuilderAttribute() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "ResultBuilderStruct", in: indexer))
        try await typeDefinition.index(in: machOFile)

        let inferrer = TypeAttributeInferrer(resilienceAwareAttributes: false)
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(attributes.contains(.resultBuilder))
    }

    @Test func dynamicMemberLookupStructInfersDynamicMemberLookupAttribute() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "DynamicMemberLookupStruct", in: indexer))
        try await typeDefinition.index(in: machOFile)

        let inferrer = TypeAttributeInferrer(resilienceAwareAttributes: false)
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(attributes.contains(.dynamicMemberLookup))
    }

    @Test func dynamicCallableStructInfersDynamicCallableAttribute() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "DynamicCallableStruct", in: indexer))
        try await typeDefinition.index(in: machOFile)

        let inferrer = TypeAttributeInferrer(resilienceAwareAttributes: false)
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(attributes.contains(.dynamicCallable))
    }

    @Test func structTestDoesNotInferAnyTypeAttribute() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "StructTest", in: indexer))
        try await typeDefinition.index(in: machOFile)

        let inferrer = TypeAttributeInferrer(resilienceAwareAttributes: false)
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(!attributes.contains(.propertyWrapper))
        #expect(!attributes.contains(.resultBuilder))
        #expect(!attributes.contains(.dynamicMemberLookup))
        #expect(!attributes.contains(.dynamicCallable))
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter SymbolTestsCoreIntegrationTests 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift
git commit -m "test: add type attribute inference integration tests"
```

---

### Task 7: Add Member Attribute Integration Tests

**Files:**
- Modify: `Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift`

- [ ] **Step 1: Add member attribute tests**

Append to `SymbolTestsCoreIntegrationTests.swift`:

```swift
// MARK: - Member Attributes (Integration)

extension SymbolTestsCoreIntegrationTests {
    @Test func classTestDynamicMembersHaveDynamicAttribute() async throws {
        let indexer = try await preparedIndexer()
        let classTest = try #require(findTypeDefinition(named: "ClassTest", in: indexer))
        try await classTest.index(in: machOFile)

        let dynamicVariable = classTest.variables.first { $0.name == "dynamicVariable" }
        #expect(dynamicVariable?.attributes.contains(.dynamic) == true)

        let dynamicMethod = classTest.functions.first { $0.name == "dynamicMethod" }
        #expect(dynamicMethod?.attributes.contains(.dynamic) == true)
    }

    @Test func objcAttributeClassMemberAttributes() async throws {
        let indexer = try await preparedIndexer()
        let objcClass = try #require(findTypeDefinition(named: "ObjCAttributeClass", in: indexer))
        try await objcClass.index(in: machOFile)

        let objcMethod = objcClass.functions.first { $0.name == "objcMethod" }
        #expect(objcMethod?.attributes.contains(.objc) == true)

        let nonobjcMethod = objcClass.functions.first { $0.name == "nonobjcMethod" }
        #expect(nonobjcMethod?.attributes.contains(.nonobjc) == true)

        let objcDynamicMethod = objcClass.functions.first { $0.name == "objcDynamicMethod" }
        #expect(objcDynamicMethod?.attributes.contains(.objc) == true)
        #expect(objcDynamicMethod?.attributes.contains(.dynamic) == true)
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter SymbolTestsCoreIntegrationTests 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift
git commit -m "test: add member attribute integration tests"
```

---

### Task 8: Add VTable Offset and Member Ordering Tests

**Files:**
- Modify: `Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift`

- [ ] **Step 1: Add vtable offset and PWT ordering tests**

Append to `SymbolTestsCoreIntegrationTests.swift`:

```swift
// MARK: - VTable Offset and Member Ordering

extension SymbolTestsCoreIntegrationTests {
    @Test func classTestVTableMembersAreSortedByVTableOffset() async throws {
        let indexer = try await preparedIndexer()
        let classTest = try #require(findTypeDefinition(named: "ClassTest", in: indexer))
        try await classTest.index(in: machOFile)

        let orderedMembers = OrderedMember.classOrdered(OrderedMember.allMembers(from: classTest))
        let vtableOffsets = orderedMembers.compactMap(\.minVTableOffset)

        // vtable offsets should be in ascending order
        #expect(!vtableOffsets.isEmpty)
        for index in 1..<vtableOffsets.count {
            #expect(vtableOffsets[index - 1] <= vtableOffsets[index],
                    "vtable offsets not ascending: \(vtableOffsets[index - 1]) > \(vtableOffsets[index])")
        }

        // All vtable members should come before non-vtable members
        let hasVTable = orderedMembers.map { $0.minVTableOffset != nil }
        let lastVTableIndex = hasVTable.lastIndex(of: true) ?? -1
        let firstNonVTableIndex = hasVTable.firstIndex(of: false) ?? orderedMembers.count
        #expect(lastVTableIndex < firstNonVTableIndex)
    }

    @Test func subclassTestOverrideMembersHaveVTableOffset() async throws {
        let indexer = try await preparedIndexer()
        let subclassTest = try #require(findTypeDefinition(named: "SubclassTest", in: indexer))
        try await subclassTest.index(in: machOFile)

        let overrideMethods = subclassTest.functions.filter { $0.isOverride }
        #expect(!overrideMethods.isEmpty)

        for method in overrideMethods {
            #expect(method.vtableOffset != nil, "Override method \(method.name) should have vtable offset")
        }
    }
}

// MARK: - PWT Offset Ordering

extension SymbolTestsCoreIntegrationTests {
    @Test func protocolWitnessTableTestMembersAreSortedByPWTOffset() async throws {
        let indexer = try await preparedIndexer()
        let protocolDefinition = try #require(findProtocolDefinition(named: "ProtocolWitnessTableTest", in: indexer))
        try await protocolDefinition.index(in: machOFile)

        let pwtOffsets = protocolDefinition.orderedMembers.compactMap(\.pwtOffset)

        #expect(!pwtOffsets.isEmpty)
        for index in 1..<pwtOffsets.count {
            #expect(pwtOffsets[index - 1] <= pwtOffsets[index],
                    "PWT offsets not ascending: \(pwtOffsets[index - 1]) > \(pwtOffsets[index])")
        }
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter SymbolTestsCoreIntegrationTests 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftInterfaceTests/SymbolTestsCoreIntegrationTests.swift
git commit -m "test: add vtable offset and PWT ordering integration tests"
```

---

### Task 9: Write End-to-End Tests

**Files:**
- Create: `Tests/SwiftInterfaceTests/SymbolTestsCoreE2ETests.swift`

- [ ] **Step 1: Create E2E test file**

Create `Tests/SwiftInterfaceTests/SymbolTestsCoreE2ETests.swift`:

```swift
import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftDump

@Suite(.serialized)
final class SymbolTestsCoreE2ETests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func buildOutput(memberSortOrder: SwiftInterfaceMemberSortOrder = .byOffset) async throws -> String {
        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(showCImportedTypes: false),
            printConfiguration: .init(
                printStrippedSymbolicItem: true,
                printFieldOffset: true,
                printMemberAddress: false,
                printVTableOffset: true,
                printPWTOffset: true,
                memberSortOrder: memberSortOrder,
                printTypeLayout: false,
                printEnumLayout: false,
                resilienceAwareAttributes: false
            )
        )
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machOFile)
        try await builder.prepare()
        let result = try await builder.printRoot()
        return result.string
    }
}

// MARK: - E2E: Type Attributes in Output

extension SymbolTestsCoreE2ETests {
    @Test func outputContainsPropertyWrapperAttribute() async throws {
        let output = try await buildOutput()
        #expect(output.contains("@propertyWrapper"))
    }

    @Test func outputContainsResultBuilderAttribute() async throws {
        let output = try await buildOutput()
        #expect(output.contains("@resultBuilder"))
    }

    @Test func outputContainsDynamicMemberLookupAttribute() async throws {
        let output = try await buildOutput()
        #expect(output.contains("@dynamicMemberLookup"))
    }

    @Test func outputContainsDynamicCallableAttribute() async throws {
        let output = try await buildOutput()
        #expect(output.contains("@dynamicCallable"))
    }
}

// MARK: - E2E: Member Attributes in Output

extension SymbolTestsCoreE2ETests {
    @Test func outputContainsObjcAttribute() async throws {
        let output = try await buildOutput()
        #expect(output.contains("@objc"))
    }

    @Test func outputContainsDynamicKeyword() async throws {
        let output = try await buildOutput()
        #expect(output.contains("dynamic"))
    }
}

// MARK: - E2E: VTable Offset in Output

extension SymbolTestsCoreE2ETests {
    @Test func outputContainsVTableOffsetComments() async throws {
        let output = try await buildOutput(memberSortOrder: .byOffset)
        #expect(output.contains("vtable offset"))
    }
}

// MARK: - E2E: Structure Completeness

extension SymbolTestsCoreE2ETests {
    @Test func outputContainsAllExpectedTypeDeclarations() async throws {
        let output = try await buildOutput()

        #expect(output.contains("struct StructTest"))
        #expect(output.contains("class ClassTest"))
        #expect(output.contains("class SubclassTest"))
        #expect(output.contains("class FinalClassTest"))
        #expect(output.contains("enum MultiPayloadEnumTests"))
        #expect(output.contains("protocol ProtocolTest"))
        #expect(output.contains("protocol ProtocolWitnessTableTest"))
        #expect(output.contains("struct GenericRequirementTest"))
        #expect(output.contains("struct PropertyWrapperStruct"))
        #expect(output.contains("struct ResultBuilderStruct"))
        #expect(output.contains("struct DynamicMemberLookupStruct"))
        #expect(output.contains("struct DynamicCallableStruct"))
        #expect(output.contains("class ObjCAttributeClass"))
    }

    @Test func outputContainsOverrideKeyword() async throws {
        let output = try await buildOutput()
        #expect(output.contains("override"))
    }

    @Test func outputContainsRetroactiveAnnotation() async throws {
        let output = try await buildOutput()
        #expect(output.contains("@retroactive"))
    }

    @Test func outputContainsConditionalConformanceWhereClause() async throws {
        let output = try await buildOutput()
        // GenericRequirementTest: Equatable where T: Equatable
        #expect(output.contains("where"))
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter SymbolTestsCoreE2ETests 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/SwiftInterfaceTests/SymbolTestsCoreE2ETests.swift
git commit -m "test: add end-to-end integration tests for SwiftInterfaceBuilder output"
```

---

### Task 10: Final Verification

- [ ] **Step 1: Run all SwiftInterfaceTests**

```bash
swift test --filter SwiftInterfaceTests 2>&1 | tail -30
```

Expected: All tests pass, including existing tests that were not modified.

- [ ] **Step 2: Run full test suite to check for regressions**

```bash
swift test 2>&1 | tail -30
```

Expected: No regressions in any test target.

- [ ] **Step 3: Commit plan doc**

```bash
git add docs/superpowers/plans/2026-04-10-symboltestscore-integration-tests.md
git commit -m "docs: add SymbolTestsCore integration tests implementation plan"
```
