import Foundation
import Testing
import MachOKit
@_spi(Internals) @testable import Demangling
@_spi(Internals) @testable import MachOSymbols
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import SwiftInterface
@testable import MachOTestingSupport

/// The export verdict of declarations in extensions of another module's
/// types, in images that keep no symbol at a non-exported descriptor
/// (evolution proposal `export-verdict-without-local-symbols`), on the
/// on-the-fly `ExtensionContextExportFixture` — see its documentation for
/// the declarations and the three variants.
///
/// The bug this pins: AppKit in the macOS 27.2 dyld shared cache keeps no
/// local symbol but the `_symbolic` ones, so its non-exported types reached
/// the remangling leg, which refused every name with an extension context.
/// Every Swift type nested in an Objective-C class has one, so about 45
/// AppKit types — 33 of them private — got no verdict, and RuntimeViewer
/// kept listing them after the user excluded what the image does not export.
@Suite(.serialized, ExclusiveImageAccess(ExtensionContextExportFixture.exclusiveAccessName))
struct ExtensionContextExportStatusTests {
    typealias Variant = ExtensionContextExportFixture.Variant

    /// The declarations the fixture keeps out of its export trie, and how
    /// each one's name places it.
    private static let declarationsInUnconstrainedExtensions = [
        "InternalNestedInExtension",
        "PrivateNestedInExtension",
        "NestedInPrivateType",
        "InternalProtocolNestedInExtension",
        "LocalTypeInExtension",
        "InternalNestedInObjCClassExtension",
        "PrivateNestedInObjCClassExtension",
    ]

    private static let exportedDeclarations = [
        "PublicNestedInExtension",
        "PublicNestedInObjCClassExtension",
        "GenericBox",
        "PublicNestedInConstrainedExtension",
    ]

    private static func preparedIndexer(_ variant: Variant) async throws -> SwiftDeclarationIndexer<MachOFile> {
        let indexer = SwiftDeclarationIndexer(
            configuration: .init(showCImportedTypes: false),
            eventHandlers: [],
            in: try ExtensionContextExportFixture.machOFile(variant)
        )
        try await indexer.prepare()
        return indexer
    }

    /// Every type and protocol the fixture defines, by declared name.
    private static func exportStatuses(in indexer: SwiftDeclarationIndexer<MachOFile>) -> [String: ExportStatus] {
        var statuses: [String: ExportStatus] = [:]
        for typeDefinition in indexer.allTypeDefinitions.values {
            statuses[typeDefinition.typeName.declaredNameForTesting] = typeDefinition.exportStatus
        }
        for protocolDefinition in indexer.allProtocolDefinitions.values {
            statuses[protocolDefinition.protocolName.declaredNameForTesting] = protocolDefinition.exportStatus
        }
        return statuses
    }

    /// How many unconstrained and constrained extension contexts a name runs
    /// through.
    private static func extensionContexts(of node: NodeReference) -> (unconstrained: Int, constrained: Int) {
        var unconstrainedCount = 0
        var constrainedCount = 0
        for descendant in node.materialize() where descendant.kind == .extension {
            if descendant.children.contains(where: { $0.kind == .dependentGenericSignature }) {
                constrainedCount += 1
            } else {
                unconstrainedCount += 1
            }
        }
        return (unconstrainedCount, constrainedCount)
    }

    /// The premise: the unstripped variant carries a symbol at every
    /// descriptor and rules by it, so it is the reference; the other two
    /// carry none at a non-exported descriptor and must reach the later legs.
    @Test(arguments: Variant.allCases)
    func localDescriptorSymbolsAreWhereTheVariantSaysTheyAre(variant: Variant) async throws {
        let indexer = try await Self.preparedIndexer(variant)
        let machOFile = indexer.machO
        for typeDefinition in indexer.allTypeDefinitions.values {
            let name = typeDefinition.typeName.declaredNameForTesting
            guard Self.declarationsInUnconstrainedExtensions.contains(name) else { continue }
            let descriptorOffset = typeDefinition.typeContextDescriptorWrapper.typeContextDescriptor.offset
            let descriptorSymbol = SymbolIndexStore.shared.symbols(for: descriptorOffset, in: machOFile)?.first { $0.name.isSwiftSymbol && $0.name.hasSuffix("Mn") }
            #expect((descriptorSymbol != nil) == (variant == .unstripped), "\(name) in \(variant)")
        }
        #expect(SymbolIndexStore.shared.hasExportInformation(in: machOFile))
    }

    @Test(arguments: Variant.allCases)
    func publicDeclarationsAreExported(variant: Variant) async throws {
        let statuses = Self.exportStatuses(in: try await Self.preparedIndexer(variant))
        for name in Self.exportedDeclarations {
            #expect(statuses[name] == .exported, "\(name) in \(variant)")
        }
    }

    /// The regression: without a symbol at the descriptor, an internal,
    /// private or local declaration in an unconstrained extension used to
    /// read `descriptorSymbolNameUnresolvable`.
    @Test(arguments: Variant.allCases)
    func declarationsInUnconstrainedExtensionsAreNotExported(variant: Variant) async throws {
        let statuses = Self.exportStatuses(in: try await Self.preparedIndexer(variant))
        for name in Self.declarationsInUnconstrainedExtensions {
            #expect(statuses[name] == .notExported, "\(name) in \(variant)")
        }
    }

    /// What makes it safe to remangle an unconstrained extension context:
    /// where the compiler's own spelling sits at the descriptor, the
    /// remangled name is exactly it, so an exported type reaching the
    /// remangling leg would be found in the trie rather than dropped.
    @Test func remanglingAnUnconstrainedExtensionContextSpellsTheCompilersName() async throws {
        let indexer = try await Self.preparedIndexer(.unstripped)
        let machOFile = indexer.machO
        var comparedNames: [String] = []
        for typeDefinition in indexer.allTypeDefinitions.values {
            let contexts = Self.extensionContexts(of: typeDefinition.typeName.node)
            guard contexts.unconstrained > 0, contexts.constrained == 0 else { continue }
            let descriptorOffset = typeDefinition.typeContextDescriptorWrapper.typeContextDescriptor.offset
            let descriptorSymbolName = try #require(
                SymbolIndexStore.shared.symbols(for: descriptorOffset, in: machOFile)?.first { $0.name.isSwiftSymbol && $0.name.hasSuffix("Mn") }?.name,
                "\(typeDefinition.typeName.name) has no descriptor symbol"
            )
            #expect(ExportStatus.descriptorSymbolName(for: typeDefinition.typeName.node, descriptorKind: .nominalTypeDescriptor) == descriptorSymbolName, "\(typeDefinition.typeName.name)")
            comparedNames.append(typeDefinition.typeName.declaredNameForTesting)
        }
        for protocolDefinition in indexer.allProtocolDefinitions.values {
            let contexts = Self.extensionContexts(of: protocolDefinition.protocolName.node)
            guard contexts.unconstrained > 0, contexts.constrained == 0 else { continue }
            let descriptorSymbolName = try #require(
                SymbolIndexStore.shared.symbols(for: protocolDefinition.protocolDescriptor.offset, in: machOFile)?.first { $0.name.isSwiftSymbol && $0.name.hasSuffix("Mp") }?.name,
                "\(protocolDefinition.protocolName.name) has no descriptor symbol"
            )
            #expect(ExportStatus.descriptorSymbolName(for: protocolDefinition.protocolName.node, descriptorKind: .protocolDescriptor) == descriptorSymbolName, "\(protocolDefinition.protocolName.name)")
            comparedNames.append(protocolDefinition.protocolName.declaredNameForTesting)
        }
        // Every shape the fixture declares in an unconstrained extension was compared.
        #expect(Set(comparedNames).isSuperset(of: Self.declarationsInUnconstrainedExtensions + ["PublicNestedInExtension", "PublicNestedInObjCClassExtension"]), "\(comparedNames)")
    }

    /// A constrained extension stays refused by the remangling leg, so an
    /// internal type there keeps no verdict — but a private one is ruled on
    /// by the third leg: by its name where the binary keeps its private
    /// discriminator, by the anonymous context enclosing its descriptor where
    /// it does not (the fully stripped variant names no anonymous context).
    @Test(arguments: Variant.withoutLocalDescriptorSymbols)
    func aConstrainedExtensionLeavesOnlyItsNonPrivateTypesUnjudged(variant: Variant) async throws {
        let statuses = Self.exportStatuses(in: try await Self.preparedIndexer(variant))
        #expect(statuses["InternalNestedInConstrainedExtension"] == .descriptorSymbolNameUnresolvable)
        #expect(statuses["PrivateNestedInConstrainedExtension"] == .notExported)
    }

    /// The `@objc` protocols have no descriptor, so only the private one's
    /// name rules, in every variant.
    @Test(arguments: Variant.allCases)
    func onlyThePrivateObjCProtocolIsRuledOn(variant: Variant) async throws {
        let indexer = try await Self.preparedIndexer(variant)
        var statuses: [String: ExportStatus] = [:]
        for objcProtocolDefinition in indexer.objcProtocolDefinitions.values {
            statuses[objcProtocolDefinition.protocolName.declaredNameForTesting] = objcProtocolDefinition.exportStatus
        }
        #expect(statuses["PrivateObjCProtocol"] == .notExported, "\(statuses)")
        #expect(statuses["PublicObjCProtocol"] == .declarationHasNoSymbol, "\(statuses)")
    }

    private static func interface(of variant: Variant, exportedOnly: Bool) async throws -> String {
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.printConfiguration.printExportedDeclarationsOnly = exportedOnly
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: try ExtensionContextExportFixture.machOFile(variant))
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// A category adopting only a private `@objc` protocol goes with the
    /// protocol under the exported-only filter, as a conformance to a
    /// non-exported Swift protocol does; one adopting a public protocol as
    /// well stays whole.
    @Test(arguments: Variant.allCases)
    func exportedOnlyInterfaceDropsACategoryAdoptingOnlyAPrivateObjCProtocol(variant: Variant) async throws {
        let unfiltered = try await Self.interface(of: variant, exportedOnly: false)
        #expect(unfiltered.contains("extension __C.NSNumberFormatter:"), "\(unfiltered)")
        #expect(unfiltered.contains("extension __C.NSByteCountFormatter:"), "\(unfiltered)")

        let filtered = try await Self.interface(of: variant, exportedOnly: true)
        #expect(!filtered.contains("extension __C.NSNumberFormatter:"), "\(filtered)")
        #expect(filtered.contains("extension __C.NSByteCountFormatter:"), "\(filtered)")
        #expect(!filtered.contains("protocol PrivateObjCProtocol"), "\(filtered)")
        #expect(filtered.contains("protocol PublicObjCProtocol"), "\(filtered)")
    }

    /// End to end: the exported-only interface keeps the public types nested
    /// in the extensions and drops every other one.
    @Test(arguments: Variant.withoutLocalDescriptorSymbols)
    func exportedOnlyInterfaceDropsTheNonExportedTypesInExtensions(variant: Variant) async throws {
        let unfiltered = try await Self.interface(of: variant, exportedOnly: false)
        let filtered = try await Self.interface(of: variant, exportedOnly: true)
        for name in Self.declarationsInUnconstrainedExtensions where name != "LocalTypeInExtension" {
            #expect(unfiltered.contains(name), "\(name) missing unfiltered in \(variant):\n\(unfiltered)")
            #expect(!filtered.contains(name), "\(name) kept in \(variant):\n\(filtered)")
        }
        #expect(!filtered.contains("PrivateNestedInConstrainedExtension"), "\(filtered)")
        for name in ["PublicNestedInExtension", "PublicNestedInObjCClassExtension", "PublicNestedInConstrainedExtension"] {
            #expect(filtered.contains(name), "\(name) dropped in \(variant):\n\(filtered)")
        }
    }
}
