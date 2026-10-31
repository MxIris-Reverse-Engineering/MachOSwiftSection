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

/// The shapes RuntimeViewer draws its comment tags and folds from (evolution
/// proposal `comment-structure`), read from the table a marked print of the
/// SymbolTestsCore fixture separates to: a field offset and the tree under
/// it, an enum's layout summary and one case's block, a tuple's type layout,
/// and the segments of the one-line comments.
@Suite(.serialized)
final class CommentStructureShapeTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// A marked print, separated.
    private struct SeparatedPrint {
        let utf8: [UInt8]
        let annotations: AnnotationRegionTable

        init(_ printed: SemanticString) {
            let separated = printed.frozen().separatingAnnotationRegions()
            utf8 = Array(separated.text.string.utf8)
            annotations = separated.annotations
        }

        func text(ofRegionAt regionIndex: Int) -> String {
            let region = annotations.regions[regionIndex]
            return text(utf8Offset: region.utf8Offset, utf8Length: region.utf8Length)
        }

        /// The role and text of the segments directly in the region — not in
        /// a region nested in it.
        func segments(ofRegionAt regionIndex: Int) -> [(role: String, text: String)] {
            annotations.segments(inRegionAt: regionIndex).map { ($0.role.rawValue, text(utf8Offset: $0.utf8Offset, utf8Length: $0.utf8Length)) }
        }

        func childRegionIndices(of regionIndex: Int) -> [Int] {
            annotations.regions.indices.filter { annotations.regions[$0].enclosingRegionIndex == regionIndex }
        }

        func regionIndices(ofKind kind: AnnotationRegion.Kind) -> [Int] {
            annotations.regions.indices.filter { annotations.regions[$0].kind == kind }
        }

        /// The text of the region's first segment of `role`.
        func firstSegmentText(ofRegionAt regionIndex: Int, role: AnnotationSegment.Role) -> String? {
            segments(ofRegionAt: regionIndex).first { $0.role == role.rawValue }?.text
        }

        private func text(utf8Offset: UInt32, utf8Length: UInt32) -> String {
            let start = Int(utf8Offset)
            return String(decoding: utf8[start ..< start + Int(utf8Length)], as: UTF8.self)
        }
    }

    private static func markedPrint<MachO>(ofTypeNamed name: String, in machO: MachO) async throws -> SeparatedPrint where MachO: MachOFieldLayoutRenderable & MachOSwiftSectionRepresentableWithCache & Sendable {
        let indexer = SwiftDeclarationIndexer(in: machO)
        try await indexer.prepare()
        let typeDefinition = try #require(indexer.allTypeDefinitions.first { $0.key.name == name }?.value, "no type \(name)")
        var configuration = CommentStructureContractTests.everyCommentConfiguration
        configuration.marksCommentStructure = true
        let printer = SwiftDeclarationPrinter(configuration: configuration, in: machO)
        return SeparatedPrint(try await printer.printTypeDefinition(typeDefinition))
    }

    /// The tree of `characterField: Character` — `_str` holds `_guts`,
    /// which holds `_object`, which holds the two words of a string — is the
    /// nesting of its regions, every node's region ending at its last row.
    @Test(arguments: [false, true])
    func aFieldOffsetHoldsItsTreeAsNestedRegions(inProcess: Bool) async throws {
        let printed = inProcess
            ? try await Self.markedPrint(ofTypeNamed: "SymbolTestsCore.BuiltinTypeFields.PrimitiveTypesTest", in: machOImage)
            : try await Self.markedPrint(ofTypeNamed: "SymbolTestsCore.BuiltinTypeFields.PrimitiveTypesTest", in: machOFile)
        let rootIndex = try #require(printed.regionIndices(ofKind: .fieldOffset).first { printed.text(ofRegionAt: $0).hasPrefix("// Field offset: 0x8\n") })
        #expect(printed.segments(ofRegionAt: rootIndex).map(\.role) == ["marker", "label", "separator", "value"])

        func nodeName(_ regionIndex: Int) -> String? {
            printed.firstSegmentText(ofRegionAt: regionIndex, role: .name)
        }
        func childNames(_ regionIndex: Int) -> [String?] {
            printed.childRegionIndices(of: regionIndex).map(nodeName)
        }
        let stringIndex = try #require(printed.childRegionIndices(of: rootIndex).first)
        #expect(childNames(rootIndex) == ["_str"])
        let gutsIndex = try #require(printed.childRegionIndices(of: stringIndex).first)
        #expect(childNames(stringIndex) == ["_guts"])
        let objectIndex = try #require(printed.childRegionIndices(of: gutsIndex).first)
        #expect(childNames(gutsIndex) == ["_object"])
        #expect(childNames(objectIndex) == ["_countAndFlagsBits", "_object"])
        let countAndFlagsIndex = try #require(printed.childRegionIndices(of: objectIndex).first)
        #expect(childNames(countAndFlagsIndex) == ["_value"])
        #expect(printed.annotations.regions[countAndFlagsIndex].depth == printed.annotations.regions[rootIndex].depth + 4)

        #expect(printed.childRegionIndices(of: rootIndex).allSatisfy { printed.annotations.regions[$0].kind == .fieldLayoutNode })
        #expect(printed.segments(ofRegionAt: countAndFlagsIndex).map(\.role) == ["marker", "treePrefix", "name", "separator", "type", "separator", "value"])
        #expect(printed.firstSegmentText(ofRegionAt: countAndFlagsIndex, role: .type) == "Swift.UInt64")
        // A region ends at its last row, not at the line break after it.
        #expect(printed.text(ofRegionAt: rootIndex).hasSuffix("_object (Builtin.BridgeObject): 0x10"))
        #expect(printed.text(ofRegionAt: objectIndex).hasSuffix("_object (Builtin.BridgeObject): 0x10"))
    }

    /// `empty`, `withValue(Int)` and `withPair(left:right:)`: tag bytes after
    /// the payload area, a summary of five facts, and for each case a block
    /// of one region per line.
    @Test func anEnumLayoutIsASummaryAndOneBlockPerCase() async throws {
        let printed = try await Self.markedPrint(ofTypeNamed: "SymbolTestsCore.CodableTests.CodableEnumTest", in: machOFile)
        let summaryIndex = try #require(printed.regionIndices(ofKind: .enumLayoutSummary).first)
        #expect(printed.firstSegmentText(ofRegionAt: summaryIndex, role: .label) == "Tagged Multi-Payload (tag bytes after the payload area)")
        #expect(printed.segments(ofRegionAt: summaryIndex).filter { $0.role == "key" }.map(\.text) == [
            "cases", "tag values used", "tag bits", "tag region", "leftover extra inhabitants for an outer enum",
        ])

        let caseIndices = printed.regionIndices(ofKind: .enumLayoutCase)
        try #require(caseIndices.count == 3)
        #expect(caseIndices.allSatisfy { printed.text(ofRegionAt: $0).hasPrefix("/* Enum Layout */\n") })

        let withPairIndex = caseIndices[1]
        let lineIndices = printed.childRegionIndices(of: withPairIndex)
        #expect(lineIndices.map { printed.annotations.regions[$0].kind } == [.enumLayoutCaseHeader, .enumLayoutCaseEncoding, .enumLayoutCaseFixedBytes, .enumLayoutCaseByte])
        let headerSegments = printed.segments(ofRegionAt: lineIndices[0])
        #expect(headerSegments.map(\.role) == ["marker", "label", "separator", "value", "separator", "value", "separator", "name", "separator", "key", "separator", "value"])
        #expect(headerSegments.map(\.text) == ["// ", "Case", " ", "1", " (", "0x01", ") `", "withPair", "` — ", "payload case", " #", "1"])
        let byteSegments = printed.segments(ofRegionAt: lineIndices[3])
        #expect(byteSegments.map(\.text) == ["//       ", "offset", " ", "0x18", " = ", "0x01", " (", "0b00000001", ")"])
        #expect(byteSegments.map(\.role) == ["marker", "label", "separator", "key", "separator", "value", "separator", "value", "separator"])
        // The block ends at the last byte line, not at the line break after it.
        #expect(printed.text(ofRegionAt: withPairIndex).hasSuffix("offset 0x18 = 0x01 (0b00000001)"))

        let emptyIndex = caseIndices[2]
        #expect(printed.childRegionIndices(of: emptyIndex).count > 4, "the empty case fixes every byte of the payload area")
    }

    /// In process, a tuple field's layout is a block: one region over all of
    /// it, a region for each element.
    @Test func aTupleTypeLayoutIsOneRegionWithARegionPerElement() async throws {
        let printed = try await Self.markedPrint(ofTypeNamed: "SymbolTestsCore.BuiltinTypeFields.TupleBuiltinTest", in: machOImage)
        let blockIndex = try #require(printed.regionIndices(ofKind: .typeLayout).first { printed.text(ofRegionAt: $0).hasPrefix("/* Type Layout */\n") })
        let elementIndices = printed.childRegionIndices(of: blockIndex)
        #expect(elementIndices.count == 2)
        #expect(elementIndices.allSatisfy { printed.annotations.regions[$0].kind == .typeLayoutElement })
        #expect(printed.firstSegmentText(ofRegionAt: elementIndices[0], role: .type) == "Swift.Int")
        #expect(printed.text(ofRegionAt: blockIndex).hasSuffix("extraInhabitantCount: 0)"))
    }

    @Test func anOffsetThatCouldNotBeComputedSaysWhy() async throws {
        let printed = try await Self.markedPrint(ofTypeNamed: "SymbolTestsCore.AccessorFunctionReferences.NoncopyableGenericBoxTest", in: machOFile)
        let unknownIndex = try #require(printed.regionIndices(ofKind: .fieldOffsetUnknown).first)
        #expect(printed.segments(ofRegionAt: unknownIndex).map(\.text) == ["// ", "Field offset", ": ", "unknown", " (", "generic parameter not substituted", ")"])
        #expect(printed.segments(ofRegionAt: unknownIndex).map(\.role) == ["marker", "label", "separator", "value", "separator", "text", "separator"])
    }

    /// An accessor's address and vtable slot name the accessor as a
    /// qualifier.
    @Test func anAccessorsAddressAndSlotNameTheAccessor() async throws {
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        var configuration = CommentStructureContractTests.everyCommentConfiguration
        configuration.marksCommentStructure = true
        let printer = SwiftDeclarationPrinter(configuration: configuration, in: machOFile)
        var addressSegments: [(role: String, text: String)]?
        var slotSegments: [(role: String, text: String)]?
        for typeDefinition in indexer.rootTypeDefinitions.values where addressSegments == nil || slotSegments == nil {
            let printed = SeparatedPrint(try await printer.printTypeDefinition(typeDefinition))
            addressSegments = addressSegments ?? printed.regionIndices(ofKind: .memberAddress).lazy.map { printed.segments(ofRegionAt: $0) }.first { $0.contains { $0.role == "qualifier" && $0.text == "getter" } }
            slotSegments = slotSegments ?? printed.regionIndices(ofKind: .vtableOffset).lazy.map { printed.segments(ofRegionAt: $0) }.first { $0.contains { $0.role == "qualifier" && $0.text == "setter" } }
        }
        let address = try #require(addressSegments)
        #expect(address.map(\.role) == ["marker", "label", "separator", "qualifier", "separator", "value"])
        #expect(address.map(\.text).prefix(5) == ["// ", "Address", " (", "getter", "): "])
        let slot = try #require(slotSegments)
        #expect(slot.map(\.role) == ["marker", "label", "separator", "qualifier", "separator", "value"])
        #expect(slot.map(\.text).prefix(5) == ["// ", "VTable offset", " (", "setter", "): "])
    }
}
