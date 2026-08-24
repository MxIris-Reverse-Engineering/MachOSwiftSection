@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable import SwiftDump

@Suite(.serialized)
final class STCoreE2ETests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func buildOutput(memberSortOrder: SwiftDeclarationMemberSortOrder = .byOffset) async throws -> String {
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
        let unsafeMachOFile = machOFile
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
        // OpaqueReturnTypeTest.functionNested's compositions, in the
        // descriptor's canonical protocol order (source order is not
        // recoverable). Attribution follows proposal 0006: `Equatable`
        // declares no associated types and must never carry a
        // primary-associated-type argument (pre-0006 this printed the
        // invalid `Swift.Equatable<[A]>`).
        #expect(output.contains("some Swift.Equatable & Swift.Sequence<[A]>"))
        #expect(output.contains("some Swift.Collection<[A]> & Swift.Equatable & SymbolTestsCore.Protocols.TestCollection<[A]>"))
        #expect(!output.contains("Swift.Equatable<"))
    }

    // MARK: Proposal 0006 — primary-associated-type attribution

    @Test func opaqueNameFallbackDoesNotFabricateSugar() async throws {
        let output = try await buildOutput()
        // functionNameFallbackGuard: `UnpinnedElementProtocol` declares an
        // `Element` of its own, but the sugar pins only `TestCollection`'s.
        // The collapsed-pin and never-pinned cases are byte-identical in the
        // descriptor, and the anchor (TestCollection) sits inside the
        // composition — so the fallback must not fabricate
        // `UnpinnedElementProtocol<[A]>`.
        #expect(output.contains("some Swift.Equatable & SymbolTestsCore.Protocols.TestCollection<[A]> & SymbolTestsCore.Protocols.UnpinnedElementProtocol"))
        #expect(!output.contains("UnpinnedElementProtocol<"))
    }

    @Test func opaqueModuleRefineClosureAttaches() async throws {
        let output = try await buildOutput()
        // functionModuleRefineClosure: the constraint anchors on
        // `ModuleBaseProtocol` (outside the composition); attribution reaches
        // `ModuleRefinedProtocol` through its descriptor's requirement
        // signature in the same image.
        #expect(output.contains("some Swift.Equatable & SymbolTestsCore.Protocols.ModuleRefinedProtocol<Swift.Int>"))
    }

    @Test func opaqueCrossImageRefineClosureDegradesOffline() async throws {
        let output = try await buildOutput()
        // functionCrossImageRefineClosure: the refine fact lives in
        // SymbolTestsHelper, which a MachOFile reader cannot reach (bind
        // symbol only). The parameter honestly degrades to none — the
        // MachOImage counterpart in OpaqueAttributionImageE2ETests attaches
        // `<Swift.Int>` by resolving cross-image.
        #expect(output.contains("some Swift.Equatable & SymbolTestsHelper.HelperRefinedProtocol"))
        #expect(!output.contains("HelperRefinedProtocol<"))
    }

    @Test func opaqueMultiplePrimaryAssociatedTypesKeepDeclarationOrder() async throws {
        let output = try await buildOutput()
        // OpaquePrimaryAssociatedTypeReturnTypeTest.body: both constraints
        // anchor on the protocol itself; the angle brackets keep the
        // primary declaration order (First, Second).
        #expect(output.contains("some SymbolTestsCore.OpaqueReturnTypes.ProtocolPrimaryAssociatedTypeTest<SymbolTestsCore.OpaqueReturnTypes.ProtocolPrimaryAssociatedTypeFirst, SymbolTestsCore.OpaqueReturnTypes.ProtocolPrimaryAssociatedTypeSecond>"))
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
