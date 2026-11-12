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
        let machOFile = try await ObservableMacroFixture.machOFile(variant)
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
        let machOFile = try await ObservableMacroFixture.machOFile(.release)
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

    // MARK: - The expansion in parts

    @Test func theExpansionPrintsInPartsPlacedLikeXcodes() async throws {
        let indexed = try await indexed(.release)
        let parts = try await indexed.printer().printMacroExpansionParts(of: .observable, attachedTo: indexed.typeDefinition(named: "InternalModel"))
        #expect(parts.map(\.placement) == [
            .trackedProperty(named: "value"),
            .trackedProperty(named: "optionalText"),
            .trackedProperty(named: "delegate"),
            .members,
            .conformance,
        ])
        for part in parts {
            let content = part.content.string
            #expect(!content.hasPrefix("\n") && !content.hasSuffix("\n") && !content.hasPrefix(" "), "\(part.placement): \(content)")
        }
        // The computed property's accessor block, then its storage.
        let value = parts[0].content.string
        #expect(value.hasPrefix("{\n") && value.contains("\n    get\n    set\n}\n"), "\(value)")
        #expect(value.hasSuffix("var _value: Swift.Int"), "\(value)")
        let members = parts[3].content.string
        for declaration in ["let _$observationRegistrar: Observation.ObservationRegistrar", "func access<A>(keyPath:", "func withMutation<A, B>(keyPath:", "func shouldNotifyObservers<A>("] {
            #expect(members.contains(declaration), "\(declaration) not in:\n\(members)")
        }
        // A tracked property's computed property is in its own piece.
        #expect(!members.contains("var value"), "\(members)")
        #expect(parts[4].content.string == "extension ObservableMacroFixture.InternalModel: Observation.Observable {}")
        #expect(parts[0].anchorKind == .attachedMacroTrackedProperty(.observable, named: "value"))
        #expect(parts[3].anchorKind == nil)
    }

    /// A tracked property's piece opens with the accessor block the expanded
    /// form prints for the property, line for line: a host showing the
    /// pieces shows what the expanded interface shows, whatever lines the
    /// block gains.
    @Test(arguments: [("FinalModel", "name"), ("FinalModel", "count"), ("InternalModel", "value")])
    func aTrackedPropertysAccessorBlockIsTheExpandedFormsBlock(typeName: String, propertyName: String) async throws {
        let indexed = try await indexed(.release)
        let typeDefinition = try indexed.typeDefinition(named: typeName)
        let expandedLines = try await indexed.printer { $0.expandsMacros = true }.printTypeDefinition(typeDefinition).string.components(separatedBy: "\n")
        let declarationLineIndex = try #require(expandedLines.firstIndex { $0.contains("var \(propertyName): ") && $0.hasSuffix(" {") })
        let indentation = expandedLines[declarationLineIndex].prefix { $0 == " " }.count
        let closingLine = String(repeating: " ", count: indentation) + "}"
        let closingLineIndex = try #require(expandedLines[(declarationLineIndex + 1)...].firstIndex(of: closingLine))
        let expandedBlock = ["{"] + expandedLines[(declarationLineIndex + 1) ..< closingLineIndex].map { String($0.dropFirst(indentation)) } + ["}"]

        let parts = try await indexed.printer().printMacroExpansionParts(of: .observable, attachedTo: typeDefinition)
        let part = try #require(parts.first { $0.placement == .trackedProperty(named: propertyName) })
        let partLines = part.content.string.components(separatedBy: "\n")
        let partBlock = Array(partLines[...(try #require(partLines.firstIndex(of: "}")))])
        #expect(partBlock == expandedBlock)
    }

    @Test func aPropertyWhoseAccessorsAreStrippedHasItsStorageAlone() async throws {
        let indexed = try await indexed(.releaseStripped)
        let parts = try await indexed.printer().printMacroExpansionParts(of: .observable, attachedTo: indexed.typeDefinition(named: "InternalModel"))
        let value = try #require(parts.first { $0.placement == .trackedProperty(named: "value") })
        #expect(value.content.string.hasSuffix("var _value: Swift.Int") && !value.content.string.contains("{"), "\(value.content.string)")
    }

    @Test func aTypeWithoutTheMacroHasNoParts() async throws {
        let indexed = try await indexed(.release)
        #expect(try await indexed.printer().printMacroExpansionParts(of: .observable, attachedTo: indexed.typeDefinition(named: "ManualObservable")).isEmpty)
    }

    /// Each tracked property's folded declaration is the anchor its piece
    /// is placed below, told by kind.
    @Test func eachTrackedPropertyIsAnchoredByItsName() async throws {
        let indexed = try await indexed(.release)
        let marked = try await indexed.printer { $0.marksAttachedMacros = true }.printTypeDefinition(indexed.typeDefinition(named: "FinalModel")).frozen()
        let separated = marked.separatingAnnotationRegions()
        let printedBytes = Array(separated.text.string.utf8)
        for name in ["name", "count", "uninitialized"] {
            let regions = separated.annotations.regions(ofKind: .attachedMacroTrackedProperty(.observable, named: name))
            #expect(regions.count == 1, "\(name)")
            let region = try #require(regions.first)
            let regionStart = Int(region.utf8Offset)
            let regionText = String(decoding: printedBytes[regionStart ..< regionStart + Int(region.utf8Length)], as: UTF8.self)
            #expect(regionText.contains("var \(name): ") && !regionText.contains("\n"), "\(regionText)")
        }
        // A stored property the macro left alone is no anchor.
        #expect(separated.annotations.regions(ofKind: .attachedMacroTrackedProperty(.observable, named: "ignored")).isEmpty)
        #expect(AnnotationRegion.Kind.attachedMacroTrackedProperty(.observable, named: "count").rawValue == "attachedMacro.Observation.Observable.trackedProperty.count")
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
