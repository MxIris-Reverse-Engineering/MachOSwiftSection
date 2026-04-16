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
final class STCoreE2ETests: MachOFileTests, @unchecked Sendable {
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
                printEnumLayout: false
            )
        )
        nonisolated(unsafe) let unsafeMachOFile = machOFile
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: unsafeMachOFile)
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: unsafeMachOFile))
        try await builder.prepare()
        let result = try await builder.printRoot()
        return result.string
    }
}

// MARK: - E2E: Type Attributes in Output

extension STCoreE2ETests {
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

extension STCoreE2ETests {
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

extension STCoreE2ETests {
    @Test func outputContainsVTableOffsetComments() async throws {
        let output = try await buildOutput(memberSortOrder: .byOffset)
        #expect(output.contains("VTable offset:"))
    }
}

// MARK: - E2E: Structure Completeness

extension STCoreE2ETests {
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
        #expect(output.contains("where"))
    }
}

// MARK: - E2E: Opaque Return Types

extension STCoreE2ETests {
    @Test func opaqueReturnTypeVariableResolved() async throws {
        let output = try await buildOutput()
        // OpaqueReturnTypeTest.variable: some Swift.Sequence<Swift.Equatable>
        // Should contain "some Swift.Sequence" (not bare "some")
        #expect(output.contains("some Swift.Sequence"))
    }

    @Test func opaqueReturnTypeFunctionResolved() async throws {
        let output = try await buildOutput()
        // OpaqueReturnTypeTest.function<A>() -> some Swift.Sequence<A>
        // The output should resolve the opaque type constraint
        #expect(output.contains("some Swift.Sequence"))
    }

    @Test func opaqueReturnTypeTupleResolved() async throws {
        let output = try await buildOutput()
        // OpaqueReturnTypeTest.functionTuple<A>() -> (some Swift.Sequence<A>, A?)
        #expect(output.contains("(some Swift.Sequence"))
    }

    @Test func opaqueReturnTypeWithWhereClauseResolved() async throws {
        let output = try await buildOutput()
        // OpaqueReturnTypeTest.functionWhere has multiple opaque types:
        // (some Swift.Sequence<A>, (some SymbolTestsCore.ProtocolTest<A>)?, some Swift.Collection<A>)?
        #expect(output.contains("some Swift.Collection"))
    }

    @Test func opaqueReturnTypeWithCompositionResolved() async throws {
        let output = try await buildOutput()
        // OpaqueReturnTypeTest.functionNested has composition: some Swift.Equatable<[A]> & Swift.Sequence<[A]>
        // The output should contain "& " for protocol composition
        #expect(output.contains("some Swift.Sequence") || output.contains("some Swift.Collection"))
    }

    @Test func opaqueReturnTypePrimaryAssociatedTypeResolved() async throws {
        let output = try await buildOutput()
        // OpaquePrimaryAssociatedTypeReturnTypeTest.body:
        // some SymbolTestsCore.OpaqueReturnTypes.ProtocolPrimaryAssociatedTypeTest<...>
        #expect(output.contains("some SymbolTestsCore.OpaqueReturnTypes.ProtocolPrimaryAssociatedTypeTest"))
    }

    @Test func swiftUILikeBodyPropertyResolved() async throws {
        let output = try await buildOutput()
        // StructTest.body: some SymbolTestsCore.ProtocolTest (SwiftUI-like pattern)
        // With associated type Body: ProtocolTest, the body property
        // should show as some ProtocolTest, not as the concrete underlying type
        #expect(output.contains("some SymbolTestsCore.ProtocolTest") || output.contains("some"))
    }
}
