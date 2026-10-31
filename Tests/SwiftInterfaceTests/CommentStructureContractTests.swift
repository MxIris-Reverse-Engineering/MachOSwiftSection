@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@_spi(Support) import SwiftPrivateDiscriminators
import SwiftDeclarationRendering
import OutputTransformer
import SwiftOutputTransformer
import Semantic
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// With `SwiftDeclarationPrintConfiguration.marksCommentStructure`, every
/// definition of the SymbolTestsCore fixture separates to exactly its print
/// without the marks — text, spans, identifiers — and every comment in it
/// lies in an annotation region (evolution proposal `comment-structure`).
/// Checked in process and from the file: with every comment option on, with
/// the `Transformer` templates installed, marking optional content as well,
/// and with the source files of private declarations.
///
/// A comment built without `StructuredComment`, or printed without asking
/// whether to mark it, shows up here as a comment in no region; a marked
/// rendering that spells a comment differently from the plain one shows up
/// as a separated print that differs.
@Suite(.serialized)
final class CommentStructureContractTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    enum Variant: CaseIterable, Sendable, CustomStringConvertible {
        case everyComment
        case everyCommentWithTransformers
        case markedOptionalContent
        case privateDeclarationSourceFiles

        var description: String {
            switch self {
            case .everyComment: "every comment"
            case .everyCommentWithTransformers: "every comment with transformers"
            case .markedOptionalContent: "marked optional content"
            case .privateDeclarationSourceFiles: "private declaration source files"
            }
        }

        func configuration(marksCommentStructure: Bool) -> SwiftDeclarationPrintConfiguration {
            var configuration = CommentStructureContractTests.everyCommentConfiguration
            configuration.marksCommentStructure = marksCommentStructure
            switch self {
            case .everyComment, .privateDeclarationSourceFiles:
                break
            case .everyCommentWithTransformers:
                var transformers = Transformer.SwiftConfiguration()
                transformers.swiftFieldOffset.isEnabled = true
                transformers.swiftVTableOffset.isEnabled = true
                transformers.swiftMemberAddress.isEnabled = true
                transformers.swiftTypeLayout.isEnabled = true
                transformers.swiftEnumLayout.isEnabled = true
                configuration.applyTransformers(transformers)
            case .markedOptionalContent:
                configuration.marksOptionalContent = true
            }
            return configuration
        }
    }

    /// Every option that prints a comment.
    nonisolated static var everyCommentConfiguration: SwiftDeclarationPrintConfiguration {
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.printFieldOffset = true
        configuration.printExpandedFieldOffsets = true
        configuration.printMemberAddress = true
        configuration.printVTableOffset = true
        configuration.printPWTOffset = true
        configuration.printTypeLayout = true
        configuration.printEnumLayout = true
        configuration.printExportStatus = true
        return configuration
    }

    private static func privateDeclarationSourceFileIndex<MachO>(of indexer: SwiftDeclarationIndexer<MachO>) -> PrivateDiscriminatorSourceFileIndex? {
        if let fileIndexer = indexer as? SwiftDeclarationIndexer<MachOFile> {
            PrivateDiscriminatorSourceFileIndex(indexer: fileIndexer)
        } else if let imageIndexer = indexer as? SwiftDeclarationIndexer<MachOImage> {
            PrivateDiscriminatorSourceFileIndex(indexer: imageIndexer)
        } else {
            nil
        }
    }

    /// A printer for `variant`, set up as a host printing one declaration at
    /// a time sets one up.
    private static func printer<MachO>(
        for variant: Variant,
        marksCommentStructure: Bool,
        indexer: SwiftDeclarationIndexer<MachO>,
        sourceFileIndex: PrivateDiscriminatorSourceFileIndex?,
        in machO: MachO
    ) -> SwiftDeclarationPrinter<MachO> where MachO: MachOFieldLayoutRenderable & MachOSwiftSectionRepresentableWithCache & Sendable {
        let printer = SwiftDeclarationPrinter(configuration: variant.configuration(marksCommentStructure: marksCommentStructure), in: machO)
        printer.addTypeNameResolver(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machO))
        if let sourceFileIndex {
            printer.setPrivateDeclarationSourceFileProvider(sourceFileIndex)
        }
        if variant == .markedOptionalContent {
            printer.installExportFilterScope(types: indexer.allTypeDefinitions.values, protocols: indexer.allProtocolDefinitions.values)
        }
        return printer
    }

    /// Prints every root type, every protocol and every extension of the
    /// image marked and plain, and describes the first few that break the
    /// contract.
    private static func violations<MachO>(
        in machO: MachO,
        variant: Variant
    ) async throws -> (regionCount: Int, violations: [String]) where MachO: MachOFieldLayoutRenderable & MachOSwiftSectionRepresentableWithCache & Sendable {
        let indexer = SwiftDeclarationIndexer(in: machO)
        try await indexer.prepare()
        var sourceFileIndex: PrivateDiscriminatorSourceFileIndex?
        if variant == .privateDeclarationSourceFiles {
            let index = try #require(Self.privateDeclarationSourceFileIndex(of: indexer))
            index.recoverSourceFiles(ofEveryDeclarationIn: indexer)
            sourceFileIndex = index
        }
        let markedPrinter = Self.printer(for: variant, marksCommentStructure: true, indexer: indexer, sourceFileIndex: sourceFileIndex, in: machO)
        let plainPrinter = Self.printer(for: variant, marksCommentStructure: false, indexer: indexer, sourceFileIndex: sourceFileIndex, in: machO)

        typealias Printing = (SwiftDeclarationPrinter<MachO>) async throws -> SemanticString
        var printings: [(label: String, print: Printing)] = []
        for (name, typeDefinition) in indexer.rootTypeDefinitions {
            printings.append(("type \(name.name)", { try await $0.printTypeDefinition(typeDefinition) }))
        }
        for (name, protocolDefinition) in indexer.allProtocolDefinitions {
            printings.append(("protocol \(name.name)", { try await $0.printProtocolDefinition(protocolDefinition) }))
        }
        let extensionGroups = [indexer.typeExtensionDefinitions, indexer.protocolExtensionDefinitions, indexer.typeAliasExtensionDefinitions, indexer.conformanceExtensionDefinitions]
        for extensionGroup in extensionGroups {
            for (name, extensionDefinitions) in extensionGroup {
                for extensionDefinition in extensionDefinitions {
                    printings.append(("extension \(name.name)", { try await $0.printExtensionDefinition(extensionDefinition) }))
                }
            }
        }

        var regionCount = 0
        var violations: [String] = []
        for printing in printings {
            let marked = try await printing.print(markedPrinter).frozen()
            let plain = try await printing.print(plainPrinter).frozen()
            if let violation = CommentStructureContract.violation(marked: marked, unmarked: plain) {
                violations.append("\(printing.label): \(violation)")
                if violations.count >= 5 { break }
            }
            regionCount += marked.separatingAnnotationRegions().annotations.regions.count
        }
        return (regionCount, violations)
    }

    @Test(arguments: Variant.allCases)
    func inProcessPrintsSeparateToTheirPlainPrints(variant: Variant) async throws {
        let result = try await Self.violations(in: machOImage, variant: variant)
        #expect(result.regionCount > 1000)
        #expect(result.violations.isEmpty, "\(result.violations.joined(separator: "\n\n"))")
    }

    @Test(arguments: Variant.allCases)
    func filePrintsSeparateToTheirPlainPrints(variant: Variant) async throws {
        let result = try await Self.violations(in: machOFile, variant: variant)
        #expect(result.regionCount > 1000)
        #expect(result.violations.isEmpty, "\(result.violations.joined(separator: "\n\n"))")
    }

    /// The whole interface: the header, the globals, every block.
    @Test func theWholeInterfaceSeparatesToItsPlainPrint() async throws {
        func interface(marksCommentStructure: Bool) async throws -> FrozenSemanticString {
            var printConfiguration = Self.everyCommentConfiguration
            printConfiguration.marksCommentStructure = marksCommentStructure
            let builder = try SwiftInterfaceBuilder(
                configuration: SwiftInterfaceBuilderConfiguration(
                    indexConfiguration: .init(showCImportedTypes: false),
                    printConfiguration: printConfiguration,
                    interfaceHeaderInfo: InterfaceHeaderInfo(
                        generatorName: "swift-section",
                        generatorVersion: "test",
                        imagePath: "/SymbolTestsCore",
                        cpuDescription: "arm64",
                        fileTypeDescription: "dylib",
                        dispatchThunkCount: 3
                    )
                ),
                eventHandlers: [],
                in: machOFile
            )
            try await builder.prepare()
            return try await builder.printRoot().frozen()
        }
        let marked = try await interface(marksCommentStructure: true)
        let plain = try await interface(marksCommentStructure: false)
        #expect(marked.separatingAnnotationRegions().annotations.regions(ofKind: .note).count >= 5, "the header's lines are notes")
        let violation = CommentStructureContract.violation(marked: marked, unmarked: plain)
        #expect(violation == nil, "\(violation ?? "")")
    }

    /// Marking optional content as well, a projection separates to the
    /// regions of printing with the projected configuration: the regions
    /// follow what the projection keeps — a field offset whose tree is
    /// projected away is a region of its one line.
    @Test func projectionsSeparateToThePrintsOfTheirConfigurations() async throws {
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        var markedConfiguration = SwiftDeclarationPrintConfiguration()
        markedConfiguration.marksOptionalContent = true
        markedConfiguration.marksCommentStructure = true
        markedConfiguration.printExportStatus = true
        let markedPrinter = SwiftDeclarationPrinter(configuration: markedConfiguration, in: machOFile)
        markedPrinter.addTypeNameResolver(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machOFile))
        markedPrinter.installExportFilterScope(types: indexer.allTypeDefinitions.values, protocols: indexer.allProtocolDefinitions.values)

        func projectedConfiguration(_ configure: (inout SwiftDeclarationPrintConfiguration) -> Void) -> SwiftDeclarationPrintConfiguration {
            var configuration = SwiftDeclarationPrintConfiguration()
            configure(&configuration)
            configuration.marksCommentStructure = true
            configuration.printExportStatus = true
            return configuration
        }
        let projectedConfigurations = [
            projectedConfiguration { $0 = Self.everyCommentConfiguration },
            // A field offset whose tree the projection leaves out.
            projectedConfiguration { $0.printFieldOffset = true; $0.printTypeLayout = true },
            projectedConfiguration { $0.printEnumLayout = true },
            projectedConfiguration { _ in },
        ]
        let projectedPrinters = projectedConfigurations.map { configuration in
            let printer = SwiftDeclarationPrinter(configuration: configuration, in: machOFile)
            printer.addTypeNameResolver(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machOFile))
            return printer
        }

        var checkedCount = 0
        var mismatches: [String] = []
        for (name, typeDefinition) in indexer.rootTypeDefinitions {
            let separatedVisibility = try await markedPrinter.printTypeDefinition(typeDefinition).frozen().separatingVisibilityRegions()
            for (configuration, printer) in zip(projectedConfigurations, projectedPrinters) {
                let projected = separatedVisibility.regions.projection(of: separatedVisibility.text) {
                    configuration.isVisibilityOptionEnabled($0, resolvesOpaqueTypes: true)
                }.text.separatingAnnotationRegions()
                let ownPrint = try await printer.printTypeDefinition(typeDefinition).frozen().separatingAnnotationRegions()
                checkedCount += 1
                if projected.text != ownPrint.text {
                    mismatches.append("type \(name.name): \(CommentStructureContract.firstDifference(between: projected.text, and: ownPrint.text))")
                } else if projected.annotations != ownPrint.annotations {
                    mismatches.append("type \(name.name): the annotation regions differ")
                }
            }
            if mismatches.count >= 5 { break }
        }
        #expect(checkedCount > 100)
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n\n"))")
    }

    @Test func plainPrintsCarryNoAnnotations() async throws {
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        let printer = SwiftDeclarationPrinter(configuration: Self.everyCommentConfiguration, in: machOFile)
        var checkedCount = 0
        for typeDefinition in indexer.rootTypeDefinitions.values {
            let plain = try await printer.printTypeDefinition(typeDefinition).frozen()
            #expect(plain.separatingAnnotationRegions().annotations.isEmpty)
            checkedCount += 1
        }
        #expect(checkedCount > 50)
    }
}
