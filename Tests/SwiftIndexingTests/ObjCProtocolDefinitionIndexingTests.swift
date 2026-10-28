import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Internals) import Demangling
import MachOSwiftSection
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@testable import MachOTestingSupport

/// The declaration model of the `@objc` protocols a Swift module declares
/// (evolution proposal `swift-declared-objc-protocols`): one
/// `ObjCProtocolDefinition` each, their requirements read on `index(in:)` —
/// spelled from a Swift class of the image that implements them where there
/// is one, from the selector otherwise — and the image's extensions of them
/// attached as their default implementations.
///
/// Holds `ExclusiveImageAccess` because the indexer registers an ancestor
/// resolver per image and the requirements read per-image ObjC indexes.
@Suite(.serialized, ExclusiveImageAccess(SwiftDeclaredObjCProtocolsFixture.moduleName))
struct ObjCProtocolDefinitionIndexingTests {
    private static let moduleName = SwiftDeclaredObjCProtocolsFixture.moduleName

    private static func indexer<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws -> SwiftDeclarationIndexer<MachO> {
        var configuration = SwiftDeclarationIndexConfiguration()
        configuration.dependencySearchPaths = try SwiftDeclaredObjCProtocolsFixture.dependencySearchPaths()
        let indexer = SwiftDeclarationIndexer(configuration: configuration, in: machO)
        try await indexer.prepare()
        return indexer
    }

    private static func definitionsByName(_ definitions: some Sequence<ObjCProtocolDefinition>) -> [String: ObjCProtocolDefinition] {
        Dictionary(definitions.map { ($0.protocolName.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The qualified name of the class a requirement was taken from, `nil`
    /// for one spelled from its selector.
    private static func conformerName(of requirement: ObjCProtocolRequirementDefinition) -> String? {
        guard case .conformer(let className) = requirement.source else { return nil }
        return className.name
    }

    /// `keepsLocalSymbols` is false for the stripped file: an internal
    /// class's members lose every symbol there, and its requirement falls
    /// back to the selector.
    private static func expectModel(in machO: some MachOSwiftSectionRepresentableWithCache, keepsLocalSymbols: Bool = true) async throws {
        let indexer = try await indexer(for: machO)
        let definitions = definitionsByName(indexer.objcProtocolDefinitions.values)
        #expect(Set(definitions.keys) == Set(["DerivedSelectors", "SameNameRenamed", "DifferentlyNamed", "RefinedProtocol", "InternalProtocol", "Outer.NestedProtocol"].map { "\(moduleName).\($0)" }))
        // None is a `ProtocolDefinition`: no protocol descriptor lists them.
        #expect(indexer.allProtocolDefinitions.keys.allSatisfy { !definitions.keys.contains($0.name) })
        for definition in definitions.values {
            #expect(definition.exportStatus == .declarationHasNoSymbol)
            try definition.index(in: machO)
        }

        let derivedSelectors = try #require(definitions["\(moduleName).DerivedSelectors"])
        #expect(derivedSelectors.objcRuntimeName == "_TtP\(moduleName.count)\(moduleName)16DerivedSelectors_")
        #expect(!derivedSelectors.hasExplicitObjCName)
        #expect(derivedSelectors.inheritedProtocolNames.map(\.name) == ["__C.NSObject"])
        #expect(derivedSelectors.requirements.count == 15)
        // No class of the image adopts it: every requirement is spelled from
        // its selector, and pinned.
        #expect(derivedSelectors.requirements.allSatisfy { $0.source == .selector && $0.hasExplicitSelector })
        // Its extension is its default implementation, out of the top-level
        // extensions.
        let defaultImplementation = try #require(derivedSelectors.defaultImplementationExtensions.first)
        #expect(defaultImplementation.isAttachedToProtocolDefinition)
        #expect(defaultImplementation.functions.map(\.name) == ["describe"])

        // Implemented by `Conformer` (in its declaration) and by
        // `ExtensionConformer` (through `RefinedProtocol`, in an extension):
        // the first class in the class list gives the signature.
        let sameNameRenamed = try #require(definitions["\(moduleName).SameNameRenamed"])
        #expect(sameNameRenamed.objcRuntimeName == "SameNameRenamed")
        #expect(sameNameRenamed.hasExplicitObjCName)
        let ping = try #require(sameNameRenamed.requirements.first)
        #expect(sameNameRenamed.requirements.map(\.selector) == ["ping"])
        let pingClassName = try #require(conformerName(of: ping), "ping was not taken from a conformer")
        #expect(["\(moduleName).Conformer", "\(moduleName).ExtensionConformer"].contains(pingClassName))
        // `ping()` derives `ping`: nothing to spell out.
        #expect(!ping.hasExplicitSelector)
        let printedPing = await ping.node.materialize().print(using: .interface)
        #expect(printedPing.contains("ping() -> ()"), "\(printedPing)")

        let refined = try #require(definitions["\(moduleName).RefinedProtocol"])
        #expect(refined.inheritedProtocolNames.map(\.name) == ["\(moduleName).SameNameRenamed"])
        #expect(refined.requirements.map(conformerName(of:)) == ["\(moduleName).ExtensionConformer"])

        let internalProtocol = try #require(definitions["\(moduleName).InternalProtocol"])
        if keepsLocalSymbols {
            #expect(internalProtocol.requirements.map(conformerName(of:)) == ["\(moduleName).InternalConformer"])
        } else {
            #expect(internalProtocol.requirements.map(\.source) == [.selector])
            #expect(internalProtocol.requirements.map(\.hasExplicitSelector) == [true])
        }

        // Declared in a type: its name and runtime name carry the parent.
        let nestedProtocol = try #require(definitions["\(moduleName).Outer.NestedProtocol"])
        #expect(nestedProtocol.objcRuntimeName == "_TtPC\(moduleName.count)\(moduleName)5Outer14NestedProtocol_")
        #expect(nestedProtocol.requirements.map(conformerName(of:)) == ["\(moduleName).NestedConformer"])

        // Renamed to another name: no record pairs with it, so nothing lists
        // its requirements.
        let differentlyNamed = try #require(definitions["\(moduleName).DifferentlyNamed"])
        #expect(differentlyNamed.objcRuntimeName == nil)
        #expect(differentlyNamed.hasExplicitObjCName)
        #expect(differentlyNamed.requirements.isEmpty)
    }

    @Test func modelFromTheFile() async throws {
        try await Self.expectModel(in: SwiftDeclaredObjCProtocolsFixture.machOFile(.full))
    }

    @Test func modelFromTheLoadedImage() async throws {
        try await Self.expectModel(in: SwiftDeclaredObjCProtocolsFixture.loadedImage())
    }

    /// Stripped of local symbols, a public class's member is still tied to
    /// its Objective-C method through the thunk's code, which calls the
    /// exported implementation.
    @Test func modelFromTheStrippedFile() async throws {
        try await Self.expectModel(in: SwiftDeclaredObjCProtocolsFixture.machOFile(.strippedLocals), keepsLocalSymbols: false)
    }

    /// Without reflection metadata only the protocols whose runtime names
    /// spell the module are found; the renamed ones are not.
    @Test func modelWithoutReflectionMetadata() async throws {
        let indexer = try await Self.indexer(for: try SwiftDeclaredObjCProtocolsFixture.machOFile(.withoutReflectionMetadata))
        let names = Set(indexer.objcProtocolDefinitions.values.map(\.protocolName.name))
        #expect(names == Set(["DerivedSelectors", "RefinedProtocol", "InternalProtocol", "Outer.NestedProtocol"].map { "\(Self.moduleName).\($0)" }))
    }
}
