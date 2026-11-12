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
@testable import MachOTestingSupport

/// The interface opens a property's accessor block with its SE-0400 `init`
/// (evolution proposal `init-accessor-recovery`): `@storageRestrictions(initializes: _x) init`
/// when the field it initializes is inferred, and the bare `init` under a
/// comment saying the binary does not record them otherwise.
@Suite(.serialized)
struct InitAccessorInterfaceTests {
    private static let notRecordedComment = "// init accessor: the binary does not record which stored properties it initializes"

    private struct Indexed<MachO: MachOFieldLayoutRenderable & MachOSwiftSectionRepresentableWithCache & Sendable> {
        let machO: MachO
        let indexer: SwiftDeclarationIndexer<MachO>

        func printedType(_ typeName: String, _ configure: (inout SwiftDeclarationPrintConfiguration) -> Void = { _ in }) async throws -> SemanticString {
            var configuration = SwiftDeclarationPrintConfiguration()
            configure(&configuration)
            let printer = SwiftDeclarationPrinter(configuration: configuration, in: machO)
            printer.installExportFilterScope(types: indexer.allTypeDefinitions.values, protocols: indexer.allProtocolDefinitions.values)
            let definition = try #require(indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == typeName }, "no type named \(typeName)")
            return try await printer.printTypeDefinition(definition)
        }
    }

    private func indexed(_ variant: InitAccessorFixture.Variant) async throws -> Indexed<MachOFile> {
        let machOFile = try await InitAccessorFixture.machOFile(variant)
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        return Indexed(machO: machOFile, indexer: indexer)
    }

    /// `print`'s lines, each with its indentation trimmed.
    private func lines(of print: String) -> [String] {
        print.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The index of the line declaring `declaration` with an accessor block.
    private func declarationIndex(of declaration: String, in lines: [String], sourceLocation: SourceLocation = #_sourceLocation) throws -> Int {
        try #require(lines.firstIndex { $0.hasSuffix(declaration + " {") }, "no block declares \(declaration) in:\n\(lines.joined(separator: "\n"))", sourceLocation: sourceLocation)
    }

    /// The lines inside the accessor block of `declaration`.
    private func accessorBlock(of declaration: String, in print: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String] {
        let lines = lines(of: print)
        let start = try declarationIndex(of: declaration, in: lines, sourceLocation: sourceLocation)
        let end = try #require(lines[start...].firstIndex(of: "}"), "the block of \(declaration) does not close", sourceLocation: sourceLocation)
        return Array(lines[(start + 1) ..< end])
    }

    // MARK: - Images that keep their init accessors

    @Test(arguments: [InitAccessorFixture.Variant.debug, .release])
    func anInferredFieldPrintsTheStorageRestrictions(variant: InitAccessorFixture.Variant) async throws {
        let indexed = try await indexed(variant)
        let frozenBox = try await indexed.printedType("FrozenBox").string
        #expect(try accessorBlock(of: "var value: A", in: frozenBox) == ["@storageRestrictions(initializes: _value) init", "get", "set"])
        let model = try await indexed.printedType("Model").string
        #expect(try accessorBlock(of: "var name: Swift.String", in: model) == ["@storageRestrictions(initializes: _name) init", "get", "set"])
        // The field type is `weak Swift.AnyObject?`.
        #expect(try accessorBlock(of: "var delegate: Swift.AnyObject?", in: model) == ["@storageRestrictions(initializes: _delegate) init", "get", "set"])
        // `accesses: b` is not recovered.
        let mixed = try await indexed.printedType("Mixed").string
        #expect(try accessorBlock(of: "var a: Swift.String", in: mixed) == ["@storageRestrictions(initializes: _a) init", "get", "set"])
        // The declaration prints from the getter, whose older mangling lacks
        // `@Sendable`; the init accessor names the field's type.
        let sendableUpgrade = try await indexed.printedType("SendableUpgrade").string
        #expect(try accessorBlock(of: "var value: (_: Swift.Int) -> Swift.Int", in: sendableUpgrade) == ["@storageRestrictions(initializes: _value) init", "get", "set"])
        // The field is `() -> sending A`; the declaration's mangling, the init
        // accessor's included, leaves `sending` out.
        let sendingResult = try await indexed.printedType("SendingResult").string
        #expect(try accessorBlock(of: "var make: () -> A", in: sendingResult) == ["@storageRestrictions(initializes: _make) init", "get", "set"])
        for print in [frozenBox, model, mixed, sendableUpgrade, sendingResult] {
            #expect(!print.contains(Self.notRecordedComment), "\(print)")
        }
    }

    @Test(arguments: [InitAccessorFixture.Variant.debug, .release])
    func anUnnamedFieldPrintsTheBareInitUnderAComment(variant: InitAccessorFixture.Variant) async throws {
        let indexed = try await indexed(variant)
        for (typeName, declaration) in [
            ("Angle", "var radians: Swift.Double"),
            ("Titled", "var title: Swift.String"),
            ("Pair", "var point: (x: Swift.Int, y: Swift.Int)"),
            ("PersistedLookalike", "var name: Swift.String"),
        ] {
            let print = try await indexed.printedType(typeName).string
            #expect(try accessorBlock(of: declaration, in: print) == ["init", "get", "set"], "\(typeName)")
            let lines = lines(of: print)
            let index = try declarationIndex(of: declaration, in: lines)
            #expect(lines[index - 1] == Self.notRecordedComment, "\(typeName):\n\(print)")
        }
    }

    @Test func theInitAccessorsAddressIsOneOfThePropertys() async throws {
        let print = try await indexed(.debug).printedType("Angle") { $0.printMemberAddress = true }.string
        #expect(print.contains("// Address (init): 0x"), "\(print)")
    }

    @Test func theCommentIsMarkedAsTheInitAccessorsComment() async throws {
        let printed = try await indexed(.release).printedType("Angle") { $0.marksCommentStructure = true }
        let separated = printed.frozen().separatingAnnotationRegions()
        let utf8 = Array(separated.text.string.utf8)
        let texts = separated.annotations.regions.filter { $0.kind == .initAccessorFields }.map { region in
            let start = Int(region.utf8Offset)
            return String(decoding: utf8[start ..< start + Int(region.utf8Length)], as: UTF8.self)
        }
        #expect(texts == [Self.notRecordedComment])
    }

    // MARK: - Stripped images

    /// An image keeps only the exported init accessor: every other property
    /// prints the block it printed before.
    @Test(arguments: [InitAccessorFixture.Variant.releaseDeadStripped, .releaseStripped])
    func aStrippedImagePrintsOnlyTheInitAccessorItKeeps(variant: InitAccessorFixture.Variant) async throws {
        let indexed = try await indexed(variant)
        let frozenBox = try await indexed.printedType("FrozenBox").string
        #expect(try accessorBlock(of: "var value: A", in: frozenBox) == ["@storageRestrictions(initializes: _value) init", "get", "set"])
        let angle = try await indexed.printedType("Angle").string
        #expect(try accessorBlock(of: "var radians: Swift.Double", in: angle) == ["get", "set"])
        #expect(!angle.contains(Self.notRecordedComment), "\(angle)")
    }

    // MARK: - A stored property with an init accessor's symbol

    /// SwiftUICore's `_GeometryActionModifier.value`: the function under the
    /// init accessor's name changes nothing in the stored property's print.
    @Test(arguments: InitAccessorFixture.Variant.allCases)
    func aStoredPropertyWithTheSymbolPrintsAsBefore(variant: InitAccessorFixture.Variant) async throws {
        let print = try await indexed(variant).printedType("ShimmedBox").string
        let lines = lines(of: print)
        #expect(lines.contains { $0.hasSuffix("var value: Swift.Int") }, "\(print)")
        #expect(!lines.contains { $0.hasSuffix("var value: Swift.Int {") }, "\(print)")
        #expect(!lines.contains("init"), "\(print)")
        #expect(!print.contains(Self.notRecordedComment), "\(print)")
    }
}
