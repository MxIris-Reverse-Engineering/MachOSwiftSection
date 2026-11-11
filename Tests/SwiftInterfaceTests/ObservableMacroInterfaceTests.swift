import Foundation
import Testing
import MachOKit
@_spi(Internals) import Demangling
import Semantic
import SwiftDeclarationRendering
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@testable import MachOTestingSupport

/// The interface folds what `@Observable` generated (evolution proposal
/// `observable-macro-folding`): by default a class the macro expanded reads
/// the way its source does, and `expandsMacros` prints the expansion as the
/// binary has it. `printMacroExpansion(of:attachedTo:level:)` prints the
/// expansion on its own, and `marksAttachedMacros` marks the attribute a host
/// anchors it to.
@Suite(.serialized)
struct ObservableMacroInterfaceTests {
    private struct Indexed<MachO: MachOFieldLayoutRenderable & MachOSwiftSectionRepresentableWithCache & Sendable> {
        let machO: MachO
        let indexer: SwiftDeclarationIndexer<MachO>

        func typeDefinition(named typeName: String) throws -> TypeDefinition {
            try #require(indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == typeName }, "no type named \(typeName)")
        }

        func printer(_ configure: (inout SwiftDeclarationPrintConfiguration) -> Void = { _ in }) -> SwiftDeclarationPrinter<MachO> {
            var configuration = SwiftDeclarationPrintConfiguration()
            configure(&configuration)
            let printer = SwiftDeclarationPrinter(configuration: configuration, in: machO)
            printer.installExportFilterScope(types: indexer.allTypeDefinitions.values, protocols: indexer.allProtocolDefinitions.values)
            return printer
        }

        func printedType(_ typeName: String, _ configure: (inout SwiftDeclarationPrintConfiguration) -> Void = { _ in }) async throws -> String {
            try await printer(configure).printTypeDefinition(typeDefinition(named: typeName)).string
        }
    }

    private func indexed(_ variant: ObservableMacroFixture.Variant) async throws -> Indexed<MachOFile> {
        let machOFile = try ObservableMacroFixture.machOFile(variant)
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        return Indexed(machO: machOFile, indexer: indexer)
    }

    /// The line of `print` declaring `declaration` — the first that contains
    /// it — with its indentation trimmed.
    private func line(declaring declaration: String, in print: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
        let line = try #require(print.split(separator: "\n").first { $0.contains(declaration) }, "no line declares \(declaration) in:\n\(print)", sourceLocation: sourceLocation)
        return line.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - The folded form

    @Test(arguments: [ObservableMacroFixture.Variant.debug, .release])
    func theFoldedFormReadsLikeTheSource(variant: ObservableMacroFixture.Variant) async throws {
        let print = try await indexed(variant).printedType("FinalModel")
        #expect(print.hasPrefix("@Observation.Observable\nclass FinalModel {"), "\(print)")
        // Tracked properties, as stored `var`s under their own names.
        for declaration in ["var name: Swift.String", "var count: Swift.Int", "var uninitialized: Swift.Double"] {
            let declaringLine = try line(declaring: declaration, in: print)
            #expect(!declaringLine.contains("@Observation"), "\(declaringLine)")
            #expect(!declaringLine.contains("{"), "a tracked property prints as stored: \(declaringLine)")
        }
        // Stored `var`s the macro left alone say so; a `let` needs not.
        for declaration in ["var ignored: Swift.Double", "var _cache: [Swift.Int]", "var lazyValue: Swift.Int"] {
            #expect(try line(declaring: declaration, in: print).hasPrefix("@Observation.ObservationIgnored "))
        }
        #expect(try line(declaring: "let constant: Swift.Int", in: print).hasPrefix("let "))
        // What the macro generated is left out.
        for generated in ["_$observationRegistrar", "_name", "_count", "_uninitialized", "func access", "func withMutation", "shouldNotifyObservers"] {
            #expect(!print.contains(generated), "\(generated) in:\n\(print)")
        }
    }

    @Test(arguments: [ObservableMacroFixture.Variant.debug, .release])
    func expandingMacrosPrintsTheExpansionWithoutTheAttribute(variant: ObservableMacroFixture.Variant) async throws {
        let print = try await indexed(variant).printedType("FinalModel") { $0.expandsMacros = true }
        #expect(!print.contains("@Observation"), "\(print)")
        for generated in ["let _$observationRegistrar: Observation.ObservationRegistrar", "var _name: Swift.String", "var name: Swift.String {", "func access<A>(keyPath:", "func withMutation<A, B>(keyPath:"] {
            #expect(print.contains(generated), "\(generated) not in:\n\(print)")
        }
    }

    @Test func aWrappedPropertyTheSourceIgnoredSaysSo() async throws {
        let indexed = try await indexed(.release)
        let folded = try await indexed.printedType("WrapperModel")
        #expect(try line(declaring: "var clamped: Swift.Int", in: folded).hasPrefix("@Observation.ObservationIgnored @ObservableMacroFixture.Clamped "))
        #expect(!(try line(declaring: "var tracked: Swift.Int", in: folded)).contains("@"))
        let expanded = try await indexed.printedType("WrapperModel") { $0.expandsMacros = true }
        #expect(try line(declaring: "var clamped: Swift.Int", in: expanded).hasPrefix("@ObservableMacroFixture.Clamped "))
    }

    @Test func aStrippedClassSaysWhichPropertiesAreSynthesized() async throws {
        let print = try await indexed(.releaseStripped).printedType("InternalModel")
        #expect(print.hasPrefix("@Observation.Observable\nclass InternalModel {"), "\(print)")
        let lines = print.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        for (storage, declaration) in [("_value", "var value: Swift.Int"), ("_optionalText", "var optionalText: Swift.String?"), ("_delegate", "weak var delegate: Swift.AnyObject?"), ("_underscored", "var underscored: Swift.Int")] {
            let declarationIndex = try #require(lines.firstIndex { $0.hasSuffix(declaration) }, "\(declaration) not in:\n\(print)")
            #expect(lines[declarationIndex - 1] == "// " + FieldRecordRendering.synthesizedTrackedPropertyComment(backingFieldName: storage))
        }
        #expect(!print.contains("_$observationRegistrar"))
    }

    @Test func moduleSelectorsReachTheAttributes() async throws {
        let print = try await indexed(.release).printedType("FinalModel") { $0.usesModuleSelectors = true }
        #expect(print.hasPrefix("@Observation::Observable\n"), "\(print)")
        #expect(try line(declaring: "var ignored: Swift::Double", in: print).hasPrefix("@Observation::ObservationIgnored "))
    }

    @Test func theExportedOnlyFilterRulesOnTheComputedProperty() async throws {
        let print = try await indexed(.release).printedType("FinalModel") { $0.printExportedDeclarationsOnly = true }
        // `name` is public: its computed property is exported.
        #expect(print.contains("var name: Swift.String"), "\(print)")
        // `count` is internal.
        #expect(!print.contains("var count: Swift.Int"), "\(print)")
    }

    // MARK: - The whole interface

    @Test func theGeneratedConformanceIsPartOfTheExpansion() async throws {
        let machOFile = try ObservableMacroFixture.machOFile(.release)
        func interface(expandsMacros: Bool) async throws -> String {
            var printConfiguration = SwiftDeclarationPrintConfiguration()
            printConfiguration.expandsMacros = expandsMacros
            let builder = try SwiftInterfaceBuilder(configuration: .init(printConfiguration: printConfiguration), eventHandlers: [], in: machOFile)
            try await builder.prepare()
            return try await builder.printRoot().string
        }
        let folded = try await interface(expandsMacros: false)
        #expect(!folded.contains("extension ObservableMacroFixture.FinalModel: Observation.Observable"), "\(folded)")
        // A conformance written by hand is no macro's.
        #expect(folded.contains("extension ObservableMacroFixture.ManualObservable: Observation.Observable {}"), "\(folded)")
        let expanded = try await interface(expandsMacros: true)
        #expect(expanded.contains("extension ObservableMacroFixture.FinalModel: Observation.Observable {}"), "\(expanded)")
        #expect(expanded.contains("extension ObservableMacroFixture.ManualObservable: Observation.Observable {}"), "\(expanded)")
    }

    // MARK: - The expansion on its own

    @Test func theExpansionPrintsAsOneBlock() async throws {
        let indexed = try await indexed(.release)
        let expansion = try await indexed.printer().printMacroExpansion(of: .observable, attachedTo: indexed.typeDefinition(named: "InternalModel")).string
        #expect(!expansion.hasPrefix("\n") && !expansion.hasSuffix("\n"), "\(expansion)")
        let lines = expansion.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(!lines.contains(""), "no blank line in:\n\(expansion)")
        // The storage of the first tracked property opens it, at the members'
        // indentation, as the expanded type body prints it.
        let firstLine = try #require(lines.first)
        #expect(firstLine.hasPrefix("    ") && firstLine.hasSuffix("var _value: Swift.Int"), "\(expansion)")
        #expect(lines.last == "extension ObservableMacroFixture.InternalModel: Observation.Observable {}", "\(expansion)")
        for declaration in ["let _$observationRegistrar: Observation.ObservationRegistrar", "var value: Swift.Int {", "func access<A>(keyPath: Swift.KeyPath<ObservableMacroFixture.InternalModel, A>)", "func withMutation<A, B>(keyPath:", "func shouldNotifyObservers<A>("] {
            #expect(expansion.contains(declaration), "\(declaration) not in:\n\(expansion)")
        }
        // A stored property the macro left alone is not part of it.
        #expect(!expansion.contains("_underscored"), "\(expansion)")
        #expect(!expansion.contains("@Observation"), "\(expansion)")
    }

    @Test func theExpansionCarriesTheCommentsTheConfigurationAsksFor() async throws {
        let indexed = try await indexed(.release)
        let expansion = try await indexed.printer { $0.printMemberAddress = true }.printMacroExpansion(of: .observable, attachedTo: indexed.typeDefinition(named: "InternalModel")).string
        #expect(expansion.contains("// Address (getter): 0x"), "\(expansion)")
    }

    @Test func aTypeWithoutTheMacroHasNoExpansion() async throws {
        let indexed = try await indexed(.release)
        let expansion = try await indexed.printer().printMacroExpansion(of: .observable, attachedTo: indexed.typeDefinition(named: "ManualObservable"))
        #expect(expansion.string.isEmpty)
    }

    // MARK: - Anchoring the expansion

    @Test func theAttributeIsMarkedOnlyWhenAsked() async throws {
        let indexed = try await indexed(.release)
        let unmarked = try await indexed.printer().printTypeDefinition(indexed.typeDefinition(named: "FinalModel")).frozen()
        let marked = try await indexed.printer { $0.marksAttachedMacros = true }.printTypeDefinition(indexed.typeDefinition(named: "FinalModel")).frozen()
        let separated = marked.separatingAnnotationRegions()
        #expect(separated.text == unmarked)
        #expect(unmarked.separatingAnnotationRegions().annotations.isEmpty)
        let regions = separated.annotations.regions(ofKind: .attachedMacro(.observable))
        #expect(regions.count == 1)
        let region = try #require(regions.first)
        let printedBytes = Array(separated.text.string.utf8)
        let regionStart = Int(region.utf8Offset)
        let regionEnd = regionStart + Int(region.utf8Length)
        let attributeText = String(decoding: printedBytes[regionStart ..< regionEnd], as: UTF8.self)
        #expect(attributeText == "@Observation.Observable")
        #expect(AnnotationRegion.Kind.attachedMacro(.observable).rawValue == "attachedMacro.Observation.Observable")
    }

    /// One print holds the attribute of a type and of the type nested in it;
    /// the definition regions tell them apart, the innermost around an
    /// attribute naming its type.
    @Test func theNestedDefinitionRegionAroundAnAttributeNamesItsType() async throws {
        let indexed = try await indexed(.release)
        let container = try indexed.typeDefinition(named: "ContainerModel")
        let nested = try indexed.typeDefinition(named: "NestedModel")
        let marked = try await indexed.printer {
            $0.marksAttachedMacros = true
            $0.marksNestedDefinitions = true
        }.printTypeDefinition(container).frozen()
        let (afterAnnotations, annotations) = marked.separatingAnnotationRegions()
        let (_, definitions) = afterAnnotations.separatingDefinitionRegions()
        let attributeRegions = annotations.regions(ofKind: .attachedMacro(.observable))
        #expect(attributeRegions.count == 2)

        func enclosingIdentities(of attributeRegion: AnnotationRegionTable.Region) -> [String] {
            definitions.regions.filter { definition in
                definition.utf8Offset <= attributeRegion.utf8Offset
                    && attributeRegion.utf8Offset + attributeRegion.utf8Length <= definition.utf8Offset + definition.utf8Length
            }.map { definition in definition.identity }
        }
        let nestedIdentity = try await mangleAsString(nested.typeName.node)
        #expect(attributeRegions.map(enclosingIdentities) == [[], [nestedIdentity]])
    }
}
