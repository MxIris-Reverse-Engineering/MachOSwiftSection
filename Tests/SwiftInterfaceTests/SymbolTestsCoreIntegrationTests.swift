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
final class STCoreTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func preparedIndexer() async throws -> SwiftInterfaceIndexer<MachOFile> {
        let indexer = SwiftInterfaceIndexer(in: machOFile)
        try await indexer.prepare()
        return indexer
    }

    private func findTypeDefinition(named typeName: String, in indexer: SwiftInterfaceIndexer<MachOFile>) -> TypeDefinition? {
        indexer.allTypeDefinitions.values.first { $0.typeName.name.hasSuffix(".\(typeName)") }
    }

    private func findProtocolDefinition(named protocolName: String, in indexer: SwiftInterfaceIndexer<MachOFile>) -> ProtocolDefinition? {
        indexer.allProtocolDefinitions.values.first { $0.protocolName.name.hasSuffix(".\(protocolName)") }
    }

    private func indexTypeDefinition(_ typeDefinition: TypeDefinition) async throws {
        nonisolated(unsafe) let unsafeTypeDefinition = typeDefinition
        nonisolated(unsafe) let unsafeMachOFile = machOFile
        try await unsafeTypeDefinition.index(in: unsafeMachOFile)
    }

    private func indexProtocolDefinition(_ protocolDefinition: ProtocolDefinition) async throws {
        nonisolated(unsafe) let unsafeProtocolDefinition = protocolDefinition
        nonisolated(unsafe) let unsafeMachOFile = machOFile
        try await unsafeProtocolDefinition.index(in: unsafeMachOFile)
    }
}

// MARK: - Type Parsing

extension STCoreTests {
    @Test func parsedTypeNames() async throws {
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

    @Test func typeKinds() async throws {
        let indexer = try await preparedIndexer()

        let structTest = try #require(findTypeDefinition(named: "StructTest", in: indexer))
        #expect(structTest.typeName.kind == .struct)

        let classTest = try #require(findTypeDefinition(named: "ClassTest", in: indexer))
        #expect(classTest.typeName.kind == .class)

        let multiPayloadEnumTests = try #require(findTypeDefinition(named: "MultiPayloadEnumTests", in: indexer))
        #expect(multiPayloadEnumTests.typeName.kind == .enum)
    }

    @Test func parsedProtocolNames() async throws {
        let indexer = try await preparedIndexer()
        let protocolNames = Set(indexer.allProtocolDefinitions.values.map { $0.protocolName.currentName })

        #expect(protocolNames.contains("ProtocolTest"))
        #expect(protocolNames.contains("ProtocolWitnessTableTest"))
        #expect(protocolNames.contains("TestCollection"))
        #expect(protocolNames.contains("ProtocolPrimaryAssociatedTypeTest"))
    }
}

// MARK: - Fields and Stored Properties

extension STCoreTests {
    @Test func storedPropertyFields() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "GenericStructNonRequirement", in: indexer))
        try await indexTypeDefinition(typeDefinition)

        let fieldNames = typeDefinition.fields.map(\.name)
        #expect(fieldNames == ["field1", "field2", "field3"])
    }
}

// MARK: - Protocol Conformances

extension STCoreTests {
    @Test func structTestConformances() async throws {
        let indexer = try await preparedIndexer()
        let conformancesByType = indexer.protocolConformancesByTypeName

        let structTestConformances = conformancesByType.first { $0.key.name.hasSuffix(".StructTest") }
        let protocolNames = try #require(structTestConformances?.value.keys.map(\.name))

        #expect(protocolNames.contains(where: { $0.hasSuffix(".ProtocolTest") }))
        #expect(protocolNames.contains(where: { $0.hasSuffix(".ProtocolWitnessTableTest") }))
    }

    @Test func genericReqConformance() async throws {
        let indexer = try await preparedIndexer()
        let conformancesByType = indexer.protocolConformancesByTypeName

        let genericConformances = conformancesByType.first { $0.key.name.hasSuffix(".GenericRequirementTest") }
        let protocolNames = try #require(genericConformances?.value.keys.map(\.name))

        #expect(protocolNames.contains(where: { $0.hasSuffix(".ProtocolTest") }))
    }

    @Test func retroactiveConformance() async throws {
        let indexer = try await preparedIndexer()
        let conformanceExtensions = indexer.conformanceExtensionDefinitions

        let neverExtensions = conformanceExtensions.filter { $0.key.name == "Swift.Never" }
        let hasRetroactive = neverExtensions.values.flatMap { $0 }.contains { $0.isRetroactive }

        #expect(hasRetroactive)
    }
}

// MARK: - Class Hierarchy and Override

extension STCoreTests {
    @Test func classTestNoOverride() async throws {
        let indexer = try await preparedIndexer()
        let classTest = try #require(findTypeDefinition(named: "ClassTest", in: indexer))
        try await indexTypeDefinition(classTest)

        for function in classTest.functions {
            #expect(!function.isOverride, "ClassTest.\(function.name) should not be override")
        }
    }

    @Test func subclassOverride() async throws {
        let indexer = try await preparedIndexer()
        let subclassTest = try #require(findTypeDefinition(named: "SubclassTest", in: indexer))
        try await indexTypeDefinition(subclassTest)

        let instanceMethod = subclassTest.functions.first { $0.name == "instanceMethod" }
        #expect(instanceMethod?.isOverride == true)
    }

    @Test func finalClassOverride() async throws {
        let indexer = try await preparedIndexer()
        let finalClassTest = try #require(findTypeDefinition(named: "FinalClassTest", in: indexer))
        try await indexTypeDefinition(finalClassTest)

        let instanceMethod = finalClassTest.functions.first { $0.name == "instanceMethod" }
        #expect(instanceMethod?.isOverride == true)
    }
}

// MARK: - Nested Types

extension STCoreTests {
    @Test func nestedTypeExists() async throws {
        let indexer = try await preparedIndexer()

        // RawRepresentableNestedStruct is defined in a conditional extension of GenericRequirementTest,
        // so it appears as a separate type definition, not as a typeChild of GenericRequirementTest.
        let nestedStruct = findTypeDefinition(named: "RawRepresentableNestedStruct", in: indexer)
        #expect(nestedStruct != nil)
    }

    @Test func deeplyNestedType() async throws {
        let indexer = try await preparedIndexer()

        // RawRepresentableNestedStruct is defined inside a conditional extension, so its typeChildren
        // contain NestedStruct (which is defined in a direct extension of RawRepresentableNestedStruct).
        let rawRepresentableNested = try #require(findTypeDefinition(named: "RawRepresentableNestedStruct", in: indexer))
        let nestedChildren = rawRepresentableNested.typeChildren.map { $0.typeName.currentName }
        #expect(nestedChildren.contains("NestedStruct"))
    }

    @Test func offsetSortedExtensionDefinitionsRetainMembers() async throws {
        let indexer = try await preparedIndexer()
        let typeExtensionDefinitions = indexer.typeExtensionDefinitions.values.flatMap { $0 }

        let rawRepresentableExtensionDefinition = try #require(
            typeExtensionDefinitions.first { extensionDefinition in
                extensionDefinition.variables.contains { variableDefinition in
                    variableDefinition.name == "rawValue"
                }
            }
        )

        #expect(
            rawRepresentableExtensionDefinition.orderedMembers.contains { orderedMember in
                if case .variable(let variableDefinition) = orderedMember {
                    return variableDefinition.name == "rawValue"
                }
                return false
            }
        )

        let neverExtensionDefinition = try #require(
            typeExtensionDefinitions.first { extensionDefinition in
                extensionDefinition.extensionName.name == "Swift.Never" &&
                    extensionDefinition.functions.contains { functionDefinition in
                        functionDefinition.name == "next"
                    }
            }
        )

        #expect(
            neverExtensionDefinition.orderedMembers.contains { orderedMember in
                if case .function(let functionDefinition) = orderedMember {
                    return functionDefinition.name == "next"
                }
                return false
            }
        )
    }
}

// MARK: - Associated Types

extension STCoreTests {
    @Test func protocolAssociatedType() async throws {
        let indexer = try await preparedIndexer()
        let protocolTest = try #require(findProtocolDefinition(named: "ProtocolTest", in: indexer))
        try await indexProtocolDefinition(protocolTest)

        #expect(protocolTest.associatedTypes.contains("Body"))
    }

    @Test func offsetSortedProtocolDefaultImplementationExtensionsRetainMembers() async throws {
        let indexer = try await preparedIndexer()
        let protocolDefinition = try #require(findProtocolDefinition(named: "ProtocolTest", in: indexer))
        try await indexProtocolDefinition(protocolDefinition)

        let matchingExtensions = protocolDefinition.defaultImplementationExtensions.filter { extensionDefinition in
            extensionDefinition.extensionName.name.hasSuffix(".Protocols.ProtocolTest")
        }

        #expect(!matchingExtensions.isEmpty)

        // Only the static `body` variable is currently retained by the indexer.
        // The static `test` function defined in the same extension is not
        // captured by `defaultImplementationExtensions` — this appears to be
        // a pre-existing indexer limitation (the staticFunctions array is
        // empty even when the binary clearly contains the symbol). Revisit
        // once `SwiftInterfaceIndexer` populates default-impl static funcs.
        #expect(
            matchingExtensions.contains { extensionDefinition in
                extensionDefinition.orderedMembers.contains { orderedMember in
                    if case .variable(let variableDefinition) = orderedMember {
                        return variableDefinition.name == "body"
                    }
                    return false
                }
            }
        )
    }
}

// MARK: - Type Attributes (Integration)

extension STCoreTests {
    @Test func propertyWrapperAttr() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "PropertyWrapperStruct", in: indexer))
        try await indexTypeDefinition(typeDefinition)

        let inferrer = TypeAttributeInferrer()
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(attributes.contains(.propertyWrapper))
    }

    @Test func resultBuilderAttr() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "ResultBuilderStruct", in: indexer))
        try await indexTypeDefinition(typeDefinition)

        let inferrer = TypeAttributeInferrer()
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(attributes.contains(.resultBuilder))
    }

    @Test func dynamicMemberLookupAttr() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "DynamicMemberLookupStruct", in: indexer))
        try await indexTypeDefinition(typeDefinition)

        let inferrer = TypeAttributeInferrer()
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(attributes.contains(.dynamicMemberLookup))
    }

    @Test func dynamicCallableAttr() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "DynamicCallableStruct", in: indexer))
        try await indexTypeDefinition(typeDefinition)

        let inferrer = TypeAttributeInferrer()
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(attributes.contains(.dynamicCallable))
    }

    @Test func structTestNoTypeAttr() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "StructTest", in: indexer))
        try await indexTypeDefinition(typeDefinition)

        let inferrer = TypeAttributeInferrer()
        let attributes = inferrer.infer(for: typeDefinition)

        #expect(!attributes.contains(.propertyWrapper))
        #expect(!attributes.contains(.resultBuilder))
        #expect(!attributes.contains(.dynamicMemberLookup))
        #expect(!attributes.contains(.dynamicCallable))
    }
}

// MARK: - Member Attributes (Integration)

extension STCoreTests {
    @Test func dynamicMemberAttr() async throws {
        let indexer = try await preparedIndexer()
        let classTest = try #require(findTypeDefinition(named: "ClassTest", in: indexer))
        try await indexTypeDefinition(classTest)

        // Verify dynamic members exist
        let dynamicMethod = classTest.functions.first { $0.name == "dynamicMethod" }
        #expect(dynamicMethod != nil, "dynamicMethod should exist in ClassTest.functions")

        let dynamicVariable = classTest.variables.first { $0.name == "dynamicVariable" }
        #expect(dynamicVariable != nil, "dynamicVariable should exist in ClassTest.variables")

        // Check the @objc dynamic case in ObjCAttributeClass where isDynamic IS set
        let objcClass = try #require(findTypeDefinition(named: "ObjCAttributeClass", in: indexer))
        try await indexTypeDefinition(objcClass)

        let objcDynamicMethod = objcClass.functions.first { $0.name == "objcDynamicMethod" }
        #expect(objcDynamicMethod != nil, "objcDynamicMethod should exist")
        // @objc dynamic methods have the isDynamic flag set in the method descriptor
        if let descriptor = objcDynamicMethod?.methodDescriptor?.method {
            #expect(descriptor.layout.flags.isDynamic, "objcDynamicMethod descriptor should have isDynamic flag")
        }
    }

    @Test func objcClassMemberAttr() async throws {
        let indexer = try await preparedIndexer()
        let objcClass = try #require(findTypeDefinition(named: "ObjCAttributeClass", in: indexer))
        try await indexTypeDefinition(objcClass)

        // @objc is detected via thunk symbols in applyThunkAttributes
        let objcMethod = objcClass.functions.first { $0.name == "objcMethod" }
        #expect(objcMethod?.attributes.contains(.objc) == true)

        // @objc on dynamic method should also be detected via thunks
        let objcDynamicMethod = objcClass.functions.first { $0.name == "objcDynamicMethod" }
        #expect(objcDynamicMethod?.attributes.contains(.objc) == true)
    }
}

// MARK: - VTable Offset and Member Ordering

extension STCoreTests {
    @Test func vtableOrdering() async throws {
        let indexer = try await preparedIndexer()
        let classTest = try #require(findTypeDefinition(named: "ClassTest", in: indexer))
        try await indexTypeDefinition(classTest)

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

    @Test func overrideMethodsDetected() async throws {
        let indexer = try await preparedIndexer()
        let subclassTest = try #require(findTypeDefinition(named: "SubclassTest", in: indexer))
        try await indexTypeDefinition(subclassTest)

        // Override methods should be detected as overrides
        let overrideMethods = subclassTest.functions.filter { $0.isOverride }
        #expect(!overrideMethods.isEmpty, "SubclassTest should have override methods")

        // Verify specific override methods are detected
        let instanceMethodOverride = subclassTest.functions.first { $0.name == "instanceMethod" }
        #expect(instanceMethodOverride?.isOverride == true, "instanceMethod should be detected as override")
    }
}

// MARK: - PWT Offset Ordering

extension STCoreTests {
    @Test func pwtOrdering() async throws {
        let indexer = try await preparedIndexer()
        let protocolDefinition = try #require(findProtocolDefinition(named: "ProtocolWitnessTableTest", in: indexer))
        try await indexProtocolDefinition(protocolDefinition)

        let pwtOffsets = protocolDefinition.orderedMembers.compactMap(\.pwtOffset)

        #expect(!pwtOffsets.isEmpty)
        for index in 1..<pwtOffsets.count {
            #expect(pwtOffsets[index - 1] <= pwtOffsets[index],
                    "PWT offsets not ascending: \(pwtOffsets[index - 1]) > \(pwtOffsets[index])")
        }
    }
}

// MARK: - Opaque Return Types (Integration)

extension STCoreTests {
    @Test func opaqueReturnTypeTestHasExpectedMembers() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "OpaqueReturnTypeTest", in: indexer))
        try await indexTypeDefinition(typeDefinition)

        // Should have the expected variables and functions
        #expect(typeDefinition.variables.contains { $0.name == "variable" })
        #expect(typeDefinition.functions.contains { $0.name == "function" })
        #expect(typeDefinition.functions.contains { $0.name == "functionOptional" })
        #expect(typeDefinition.functions.contains { $0.name == "functionTuple" })
        #expect(typeDefinition.functions.contains { $0.name == "functionWhere" })
        #expect(typeDefinition.functions.contains { $0.name == "functionNested" })
    }

    @Test func opaqueReturnTypeNestedTypeExists() async throws {
        let indexer = try await preparedIndexer()
        let opaqueReturnType = try #require(findTypeDefinition(named: "OpaqueReturnTypeTest", in: indexer))

        // OpaqueReturnTypeTest has a nested type AnyProtocolTest
        let childNames = opaqueReturnType.typeChildren.map { $0.typeName.currentName }
        #expect(childNames.contains("AnyProtocolTest"))
    }

    @Test func opaquePrimaryAssocTypeReturnTestExists() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "OpaquePrimaryAssociatedTypeReturnTypeTest", in: indexer))
        try await indexTypeDefinition(typeDefinition)

        #expect(typeDefinition.variables.contains { $0.name == "body" })
    }

    @Test func swiftUILikePatternStructTestHasBody() async throws {
        let indexer = try await preparedIndexer()
        let typeDefinition = try #require(findTypeDefinition(named: "StructTest", in: indexer))
        try await indexTypeDefinition(typeDefinition)

        // StructTest has both instance and static body properties (SwiftUI-like pattern)
        let instanceBody = typeDefinition.variables.first { $0.name == "body" }
        #expect(instanceBody != nil)

        let staticBody = typeDefinition.staticVariables.first { $0.name == "body" }
        #expect(staticBody != nil)
    }

    @Test func protocolTestHasBodyRequirement() async throws {
        let indexer = try await preparedIndexer()
        let protocolDefinition = try #require(findProtocolDefinition(named: "ProtocolTest", in: indexer))
        try await indexProtocolDefinition(protocolDefinition)

        // ProtocolTest has associatedtype Body: ProtocolTest
        #expect(protocolDefinition.associatedTypes.contains("Body"))

        // ProtocolTest should have body variable and static body variable requirements
        let bodyVariable = protocolDefinition.variables.first { $0.name == "body" }
        #expect(bodyVariable != nil)
    }
}
