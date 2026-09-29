@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
import SwiftDeclarationRendering
import Semantic
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// A marked print (`SwiftDeclarationPrintConfiguration.marksOptionalContent`),
/// projected to a configuration, reads byte for byte as printing with that
/// configuration — for every root type, root protocol and extension of the
/// SymbolTestsCore fixture, printed in process (the runtime layout path,
/// which RuntimeViewer takes) and from the file (the static layout path).
///
/// RuntimeViewer's Find searches one marked print per declaration under
/// whatever options the user displays with (evolution proposal
/// `visibility-regions`); this is the contract that stands on. A new output
/// point an option controls that is not marked shows up here: the
/// projection keeps it where the plain print drops it.
@Suite(.serialized)
final class VisibilityRegionProjectionTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Everything off, everything on, and each of `varied` alone and left
    /// out.
    private static func optionCombinations(varying varied: [SwiftVisibilityOption]) -> [Set<SwiftVisibilityOption>] {
        let allOptions = Set(SwiftVisibilityOption.allCases)
        var combinations: [Set<SwiftVisibilityOption>] = [[], allOptions]
        for option in varied {
            combinations.append([option])
            combinations.append(allOptions.subtracting([option]))
        }
        return combinations
    }

    /// The options whose output the file path works out differently from
    /// the in-process path: the layout comments. Everything else prints the
    /// same way from either, and the in-process test varies all of it.
    private static let layoutOptions: [SwiftVisibilityOption] = [.printFieldOffset, .printExpandedFieldOffsets, .printTypeLayout, .printEnumLayout]

    private static func configuration(enabling options: Set<SwiftVisibilityOption>) -> SwiftDeclarationPrintConfiguration {
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.printStrippedSymbolicItem = options.contains(.printStrippedSymbolicItem)
        configuration.printFieldOffset = options.contains(.printFieldOffset)
        configuration.printExpandedFieldOffsets = options.contains(.printExpandedFieldOffsets)
        configuration.printMemberAddress = options.contains(.printMemberAddress)
        configuration.printVTableOffset = options.contains(.printVTableOffset)
        configuration.printPWTOffset = options.contains(.printPWTOffset)
        configuration.printTypeLayout = options.contains(.printTypeLayout)
        configuration.printEnumLayout = options.contains(.printEnumLayout)
        configuration.infersObjCOverridesFromSelectorNames = options.contains(.infersObjCOverridesFromSelectorNames)
        return configuration
    }

    private static func makePrinter<MachO>(
        _ configuration: SwiftDeclarationPrintConfiguration,
        resolvesOpaqueTypes: Bool,
        in machO: MachO
    ) -> SwiftDeclarationPrinter<MachO> where MachO: MachOFieldLayoutRenderable & MachOSwiftSectionRepresentableWithCache & Sendable {
        let printer = SwiftDeclarationPrinter(configuration: configuration, in: machO)
        if resolvesOpaqueTypes {
            printer.addTypeNameResolver(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machO))
        }
        return printer
    }

    /// Prints every declaration marked and plainly under every combination,
    /// and describes the first few whose projection differs.
    private static func mismatches<MachO>(
        in machO: MachO,
        optionCombinations: [Set<SwiftVisibilityOption>]
    ) async throws -> (checkedDeclarationCount: Int, mismatches: [String]) where MachO: MachOFieldLayoutRenderable & MachOSwiftSectionRepresentableWithCache & Sendable {
        let indexer = SwiftDeclarationIndexer(in: machO)
        try await indexer.prepare()

        var markedConfiguration = SwiftDeclarationPrintConfiguration()
        markedConfiguration.marksOptionalContent = true
        let markedPrinter = makePrinter(markedConfiguration, resolvesOpaqueTypes: true, in: machO)
        let plainPrinters = optionCombinations.map { options in
            (options, configuration(enabling: options), makePrinter(configuration(enabling: options), resolvesOpaqueTypes: options.contains(.opaqueTypeResolution), in: machO))
        }

        typealias Printing = (SwiftDeclarationPrinter<MachO>) async throws -> SemanticString
        var printings: [(label: String, print: Printing)] = []
        // Definitions are classes the printers index in place; the printings
        // run one after another, as the fixture tests always do.
        for (name, definition) in indexer.rootTypeDefinitions {
            nonisolated(unsafe) let unsafeDefinition = definition
            printings.append(("type \(name)", { try await $0.printTypeDefinition(unsafeDefinition) }))
        }
        for (name, definition) in indexer.rootProtocolDefinitions {
            nonisolated(unsafe) let unsafeDefinition = definition
            printings.append(("protocol \(name)", { try await $0.printProtocolDefinition(unsafeDefinition) }))
        }
        let extensionGroups = [indexer.typeExtensionDefinitions, indexer.protocolExtensionDefinitions, indexer.typeAliasExtensionDefinitions, indexer.conformanceExtensionDefinitions]
        for extensionGroup in extensionGroups {
            for (name, definitions) in extensionGroup {
                for definition in definitions {
                    nonisolated(unsafe) let unsafeDefinition = definition
                    printings.append(("extension \(name)", { try await $0.printExtensionDefinition(unsafeDefinition) }))
                }
            }
        }

        var mismatches: [String] = []
        for printing in printings {
            let separated = try await printing.print(markedPrinter).frozen().separatingVisibilityRegions()
            for (options, configuration, printer) in plainPrinters {
                let expected = try await printing.print(printer).frozen()
                let projected = separated.regions.projection(of: separated.text) {
                    configuration.isVisibilityOptionEnabled($0, resolvesOpaqueTypes: options.contains(.opaqueTypeResolution))
                }.text
                if projected != expected {
                    let enabled = SwiftVisibilityOption.allCases.filter(options.contains).map(\.rawValue)
                    mismatches.append("\(printing.label) with \(enabled):\n\(projected.string)\n--- expected ---\n\(expected.string)")
                    break
                }
            }
            if mismatches.count >= 5 { break }
        }
        return (printings.count, mismatches)
    }

    @Test func inProcessPrintsProjectToEveryConfiguration() async throws {
        let result = try await Self.mismatches(in: machOImage, optionCombinations: Self.optionCombinations(varying: SwiftVisibilityOption.allCases))
        #expect(result.checkedDeclarationCount > 100)
        #expect(result.mismatches.isEmpty, "\(result.mismatches.joined(separator: "\n\n"))")
    }

    @Test func filePrintsProjectToEveryConfiguration() async throws {
        let result = try await Self.mismatches(in: machOFile, optionCombinations: Self.optionCombinations(varying: Self.layoutOptions))
        #expect(result.checkedDeclarationCount > 100)
        #expect(result.mismatches.isEmpty, "\(result.mismatches.joined(separator: "\n\n"))")
    }
}
