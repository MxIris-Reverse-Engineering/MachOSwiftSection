@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
import SwiftDeclarationRendering
import OutputTransformer
import SwiftOutputTransformer
import Semantic
import Demangling
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// With `SwiftDeclarationPrintConfiguration.marksNestedDefinitions`, every
/// nested type and protocol taken out of its parent's print —
/// `content(ofDefinitionRegion:)`, then
/// `removingIndentation(levels: depth + 1)` — is exactly the definition
/// printed on its own: text, spans, identifiers, and the tables its
/// visibility and definition separations produce. Checked for every root
/// type and every extension of the SymbolTestsCore fixture that has nested
/// definitions — nearly every type there sits in a namespace enum — in
/// process and from the file, plainly, marked (`marksOptionalContent`), and
/// with every option on and the `Transformer` templates installed.
///
/// RuntimeViewer builds its Find corpus on this (evolution proposal
/// `nested-definition-regions`): it prints a parent once and takes the nested
/// definitions out of that print instead of printing each again. A nested
/// print that depends on its level other than through indentation — a
/// hard-coded level, a line its renderer does not indent — shows up here as a
/// mismatch, or as a region whose indentation cannot be removed; a lost mark
/// shows up as a parent with fewer regions than nested definitions.
@Suite(.serialized)
final class NestedDefinitionRegionContractTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    enum Variant: CaseIterable, Sendable, CustomStringConvertible {
        case plain
        case markedOptionalContent
        case everyOptionWithTransformers

        var description: String {
            switch self {
            case .plain: "plain"
            case .markedOptionalContent: "marked optional content"
            case .everyOptionWithTransformers: "every option with transformers"
            }
        }

        var configuration: SwiftDeclarationPrintConfiguration {
            var configuration = SwiftDeclarationPrintConfiguration()
            configuration.marksNestedDefinitions = true
            switch self {
            case .plain:
                break
            case .markedOptionalContent:
                configuration.marksOptionalContent = true
            case .everyOptionWithTransformers:
                configuration.printFieldOffset = true
                configuration.printExpandedFieldOffsets = true
                configuration.printMemberAddress = true
                configuration.printVTableOffset = true
                configuration.printPWTOffset = true
                configuration.printTypeLayout = true
                configuration.printEnumLayout = true
                configuration.printExportStatus = true
                var transformers = Transformer.SwiftConfiguration()
                transformers.swiftFieldOffset.isEnabled = true
                transformers.swiftVTableOffset.isEnabled = true
                transformers.swiftMemberAddress.isEnabled = true
                transformers.swiftTypeLayout.isEnabled = true
                transformers.swiftEnumLayout.isEnabled = true
                configuration.applyTransformers(transformers)
            }
            return configuration
        }

        var resolvesOpaqueTypes: Bool {
            self != .plain
        }
    }

    private static func nestedDefinitionCount(of typeDefinition: TypeDefinition) -> Int {
        typeDefinition.protocolChildren.count
            + typeDefinition.typeChildren.reduce(0) { $0 + 1 + nestedDefinitionCount(of: $1) }
    }

    private static func nestedDefinitionCount(of extensionDefinition: ExtensionDefinition) -> Int {
        extensionDefinition.protocols.count
            + extensionDefinition.types.reduce(0) { $0 + 1 + nestedDefinitionCount(of: $1) }
    }

    /// Where two prints first differ, for a readable failure.
    private static func firstDifference(between takenOut: FrozenSemanticString, and ownPrint: FrozenSemanticString) -> String {
        if takenOut.string != ownPrint.string {
            let takenOutLines = takenOut.string.split(separator: "\n", omittingEmptySubsequences: false)
            let ownPrintLines = ownPrint.string.split(separator: "\n", omittingEmptySubsequences: false)
            let lineIndex = (0 ..< max(takenOutLines.count, ownPrintLines.count)).first { index in
                index >= takenOutLines.count || index >= ownPrintLines.count || takenOutLines[index] != ownPrintLines[index]
            } ?? 0
            let takenOutLine = lineIndex < takenOutLines.count ? String(takenOutLines[lineIndex]) : "<none>"
            let ownPrintLine = lineIndex < ownPrintLines.count ? String(ownPrintLines[lineIndex]) : "<none>"
            return "text differs at line \(lineIndex + 1):\n  taken out: \(takenOutLine)\n  own print: \(ownPrintLine)"
        }
        let takenOutComponents = takenOut.components
        let ownPrintComponents = ownPrint.components
        let componentIndex = (0 ..< max(takenOutComponents.count, ownPrintComponents.count)).first { index in
            index >= takenOutComponents.count || index >= ownPrintComponents.count || takenOutComponents[index] != ownPrintComponents[index]
        } ?? 0
        let takenOutComponent = componentIndex < takenOutComponents.count ? "\(takenOutComponents[componentIndex])" : "<none>"
        let ownPrintComponent = componentIndex < ownPrintComponents.count ? "\(ownPrintComponents[componentIndex])" : "<none>"
        return "same text, span \(componentIndex) differs:\n  taken out: \(takenOutComponent)\n  own print: \(ownPrintComponent)"
    }

    /// Prints every parent with nested definitions, takes each region out,
    /// and describes the first few that differ from the definition's own
    /// print.
    private static func mismatches<MachO>(
        in machO: MachO,
        variant: Variant
    ) async throws -> (checkedRegionCount: Int, mismatches: [String]) where MachO: MachOFieldLayoutRenderable & MachOSwiftSectionRepresentableWithCache & Sendable {
        let indexer = SwiftDeclarationIndexer(in: machO)
        try await indexer.prepare()
        let printer = SwiftDeclarationPrinter(configuration: variant.configuration, in: machO)
        if variant.resolvesOpaqueTypes {
            printer.addTypeNameResolver(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machO))
        }

        typealias Printing = (SwiftDeclarationPrinter<MachO>) async throws -> SemanticString
        // Every definition a region can name, by the identity the printer
        // gives it.
        var ownPrintingByIdentity: [String: Printing] = [:]
        for typeDefinition in indexer.allTypeDefinitions.values {
            ownPrintingByIdentity[try await mangleAsString(typeDefinition.typeName.node)] = { try await $0.printTypeDefinition(typeDefinition) }
        }
        for protocolDefinition in indexer.allProtocolDefinitions.values {
            ownPrintingByIdentity[try await mangleAsString(protocolDefinition.protocolName.node)] = { try await $0.printProtocolDefinition(protocolDefinition) }
        }

        var parents: [(label: String, nestedDefinitionCount: Int, print: Printing)] = []
        for (name, typeDefinition) in indexer.rootTypeDefinitions {
            let nestedDefinitionCount = nestedDefinitionCount(of: typeDefinition)
            guard nestedDefinitionCount > 0 else { continue }
            parents.append(("type \(name.name)", nestedDefinitionCount, { try await $0.printTypeDefinition(typeDefinition) }))
        }
        let extensionGroups = [indexer.typeExtensionDefinitions, indexer.protocolExtensionDefinitions, indexer.typeAliasExtensionDefinitions, indexer.conformanceExtensionDefinitions]
        for extensionGroup in extensionGroups {
            for (name, extensionDefinitions) in extensionGroup {
                for extensionDefinition in extensionDefinitions {
                    let nestedDefinitionCount = nestedDefinitionCount(of: extensionDefinition)
                    guard nestedDefinitionCount > 0 else { continue }
                    parents.append(("extension \(name.name)", nestedDefinitionCount, { try await $0.printExtensionDefinition(extensionDefinition) }))
                }
            }
        }

        var checkedRegionCount = 0
        var mismatches: [String] = []
        for parent in parents {
            let printed = try await parent.print(printer).frozen()
            let regions = printed.separatingDefinitionRegions().definitions.regions
            if regions.count != parent.nestedDefinitionCount {
                mismatches.append("\(parent.label): \(regions.count) regions for \(parent.nestedDefinitionCount) nested definitions")
            }
            for region in regions {
                checkedRegionCount += 1
                let label = "\(parent.label) → \(region.identity) (depth \(region.depth))"
                guard let ownPrinting = ownPrintingByIdentity[region.identity] else {
                    mismatches.append("\(label): no definition has this identity")
                    continue
                }
                let ownPrint = try await ownPrinting(printer).frozen()
                let regionContent = printed.content(ofDefinitionRegion: region)
                guard let takenOut = regionContent.removingIndentation(levels: region.depth + 1) else {
                    mismatches.append("\(label): the indentation could not be removed\n\(regionContent.string)")
                    continue
                }
                if takenOut != ownPrint {
                    mismatches.append("\(label): \(firstDifference(between: takenOut, and: ownPrint))")
                } else if takenOut.separatingVisibilityRegions().regions != ownPrint.separatingVisibilityRegions().regions {
                    mismatches.append("\(label): the visibility regions differ")
                } else if takenOut.separatingDefinitionRegions().definitions != ownPrint.separatingDefinitionRegions().definitions {
                    mismatches.append("\(label): the nested definition regions differ")
                }
            }
            if mismatches.count >= 5 { break }
        }
        return (checkedRegionCount, mismatches)
    }

    @Test(arguments: Variant.allCases)
    func inProcessNestedDefinitionsTakeOutAsTheirOwnPrints(variant: Variant) async throws {
        let result = try await Self.mismatches(in: machOImage, variant: variant)
        #expect(result.checkedRegionCount > 100)
        #expect(result.mismatches.isEmpty, "\(result.mismatches.joined(separator: "\n\n"))")
    }

    @Test(arguments: Variant.allCases)
    func fileNestedDefinitionsTakeOutAsTheirOwnPrints(variant: Variant) async throws {
        let result = try await Self.mismatches(in: machOFile, variant: variant)
        #expect(result.checkedRegionCount > 100)
        #expect(result.mismatches.isEmpty, "\(result.mismatches.joined(separator: "\n\n"))")
    }

    @Test func unmarkedPrintsAreUnchanged() async throws {
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        var markedConfiguration = SwiftDeclarationPrintConfiguration()
        markedConfiguration.marksNestedDefinitions = true
        let markedPrinter = SwiftDeclarationPrinter(configuration: markedConfiguration, in: machOFile)
        let plainPrinter = SwiftDeclarationPrinter(configuration: .init(), in: machOFile)
        var checkedCount = 0
        for typeDefinition in indexer.rootTypeDefinitions.values {
            let marked = try await markedPrinter.printTypeDefinition(typeDefinition).frozen()
            let plain = try await plainPrinter.printTypeDefinition(typeDefinition).frozen()
            #expect(marked.separatingDefinitionRegions().text == plain)
            #expect(plain.separatingDefinitionRegions().definitions.isEmpty)
            checkedCount += 1
        }
        #expect(checkedCount > 50)
    }
}
