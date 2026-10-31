import Testing
import Semantic
@testable import SwiftDeclarationRendering
@testable @_spi(Internals) import SwiftInspection

/// Every comment the printers emit is spelled out once, by a
/// `StructuredComment` factory, as segments that each play a role (evolution
/// proposal `comment-structure`). The text must stay what the printers have
/// always printed — the literals here are taken from their output — and the
/// segments are the split RuntimeViewer draws its comment tags from.
@Suite
struct StructuredCommentTests {
    struct Expectation: Sendable, CustomTestStringConvertible {
        let comment: StructuredComment
        let text: String
        let segments: [StructuredComment.Segment]

        var testDescription: String { text }
    }

    static let expectations: [Expectation] = [
        Expectation(
            comment: .memberAddress(addressString: "135DC"),
            text: "// Address: 0x135DC",
            segments: [.marker("// "), .label("Address"), .separator(": "), .value("0x135DC")]
        ),
        Expectation(
            comment: .memberAddress(addressString: "135DC", qualifier: "getter"),
            text: "// Address (getter): 0x135DC",
            segments: [.marker("// "), .label("Address"), .separator(" ("), .qualifier("getter"), .separator("): "), .value("0x135DC")]
        ),
        Expectation(
            comment: .vtableOffset(12),
            text: "// VTable offset: 12",
            segments: [.marker("// "), .label("VTable offset"), .separator(": "), .value("12")]
        ),
        Expectation(
            comment: .vtableOffset(13, qualifier: "setter"),
            text: "// VTable offset (setter): 13",
            segments: [.marker("// "), .label("VTable offset"), .separator(" ("), .qualifier("setter"), .separator("): "), .value("13")]
        ),
        Expectation(
            comment: .fieldOffset(0x8),
            text: "// Field offset: 0x8",
            segments: [.marker("// "), .label("Field offset"), .separator(": "), .value("0x8")]
        ),
        Expectation(
            comment: .pwtOffset(0x18),
            text: "// PWT offset: 0x18",
            segments: [.marker("// "), .label("PWT offset"), .separator(": "), .value("0x18")]
        ),
        Expectation(
            comment: .unknownFieldOffset(reasonDescription: "generic parameter not substituted"),
            text: "// Field offset: unknown (generic parameter not substituted)",
            segments: [
                .marker("// "), .label("Field offset"), .separator(": "), .value("unknown"),
                .separator(" ("), .text("generic parameter not substituted"), .separator(")"),
            ]
        ),
        Expectation(
            comment: .fieldLayoutNode(treePrefix: "│   ├── ", fieldName: "_countAndFlagsBits", typeName: "Swift.UInt64", offset: 0x8),
            text: "// │   ├── _countAndFlagsBits (Swift.UInt64): 0x8",
            segments: [
                .marker("// "), .treePrefix("│   ├── "), .name("_countAndFlagsBits"),
                .separator(" ("), .type("Swift.UInt64"), .separator("): "), .value("0x8"),
            ]
        ),
        Expectation(
            comment: .fieldLayoutNode(treePrefix: "    └── ", fieldName: "_value", typeName: "", offset: 0x10),
            text: "//     └── _value: 0x10",
            segments: [.marker("// "), .treePrefix("    └── "), .name("_value"), .separator(": "), .value("0x10")]
        ),
        Expectation(
            comment: .typeLayout(size: 16, stride: 16, alignment: 8, extraInhabitantCount: 2147483647),
            text: "// Type Layout: (size: 16, stride: 16, alignment: 8, extraInhabitantCount: 2147483647)",
            segments: [
                .marker("// "), .label("Type Layout"), .separator(": ("),
                .key("size"), .separator(": "), .value("16"), .separator(", "),
                .key("stride"), .separator(": "), .value("16"), .separator(", "),
                .key("alignment"), .separator(": "), .value("8"), .separator(", "),
                .key("extraInhabitantCount"), .separator(": "), .value("2147483647"),
                .separator(")"),
            ]
        ),
        Expectation(
            comment: .typeLayout(labeled: "Layout", size: 8, stride: 8, alignment: 8, extraInhabitantCount: 0),
            text: "// Layout: (size: 8, stride: 8, alignment: 8, extraInhabitantCount: 0)",
            segments: [
                .marker("// "), .label("Layout"), .separator(": ("),
                .key("size"), .separator(": "), .value("8"), .separator(", "),
                .key("stride"), .separator(": "), .value("8"), .separator(", "),
                .key("alignment"), .separator(": "), .value("8"), .separator(", "),
                .key("extraInhabitantCount"), .separator(": "), .value("0"),
                .separator(")"),
            ]
        ),
        Expectation(
            comment: .tupleTypeLayoutHeading,
            text: "/* Type Layout */",
            segments: [.marker("/* "), .label("Type Layout"), .marker(" */")]
        ),
        Expectation(
            comment: .tupleElementType("Swift.Int"),
            text: "// Type: Swift.Int",
            segments: [.marker("// "), .label("Type"), .separator(": "), .type("Swift.Int")]
        ),
        Expectation(
            comment: .tupleTypeLayoutTotal,
            text: "// Total: ",
            segments: [.marker("// "), .label("Total"), .separator(": ")]
        ),
        Expectation(
            comment: .enumLayoutCaseHeading,
            text: "/* Enum Layout */",
            segments: [.marker("/* "), .label("Enum Layout"), .marker(" */")]
        ),
        Expectation(
            comment: .enumLayoutCaseBlock("    // Case 2 (0x02) `empty` — empty case #0\n"),
            text: "    // Case 2 (0x02) `empty` — empty case #0\n",
            segments: [.plain("    // Case 2 (0x02) `empty` — empty case #0\n")]
        ),
        Expectation(
            comment: .spareBits(totalSpareBits: 12),
            text: "/* Spare Bits: 12 total */",
            segments: [.marker("/* "), .label("Spare Bits"), .separator(": "), .value("12"), .separator(" "), .text("total"), .marker(" */")]
        ),
        Expectation(
            comment: .exportStatus,
            text: "// not exported",
            segments: [.marker("// "), .label("not exported")]
        ),
        Expectation(
            comment: .protocolExtensionDefault,
            text: "// protocol-extension default",
            segments: [.marker("// "), .label("protocol-extension default")]
        ),
        Expectation(
            comment: .deletedMethodSlot,
            text: "// No implementation in this image (deleted method — slot retained for ABI)",
            segments: [.marker("// "), .text("No implementation in this image (deleted method — slot retained for ABI)")]
        ),
        Expectation(
            comment: .ambiguousAttribution(foldedSymbolCount: 3),
            text: "// Attribution: ambiguous — 3 symbols folded at this address",
            segments: [
                .marker("// "), .label("Attribution"), .separator(": "), .value("ambiguous"),
                .separator(" — "), .text("3 symbols folded at this address"),
            ]
        ),
        Expectation(
            comment: .strippedSymbolicRequirement(kindDescription: "Method", isAsync: false, isInstance: true),
            text: "// Kind: Method, isAsync: false, isInstance: true",
            segments: [
                .marker("// "), .key("Kind"), .separator(": "), .value("Method"), .separator(", "),
                .key("isAsync"), .separator(": "), .value("false"), .separator(", "),
                .key("isInstance"), .separator(": "), .value("true"),
            ]
        ),
        Expectation(
            comment: .note("Visitor #1 in Holder.countValues()"),
            text: "// Visitor #1 in Holder.countValues()",
            segments: [.marker("// "), .text("Visitor #1 in Holder.countValues()")]
        ),
        Expectation(
            comment: .note("  `T!` prints as `T?` (ABI-identical) · parameter internal names · @available ·"),
            text: "//   `T!` prints as `T?` (ABI-identical) · parameter internal names · @available ·",
            segments: [.marker("// "), .marker("  "), .text("`T!` prints as `T?` (ABI-identical) · parameter internal names · @available ·")]
        ),
        Expectation(
            comment: .inlineNote("type not recoverable"),
            text: "/* type not recoverable */",
            segments: [.marker("/* "), .text("type not recoverable"), .marker(" */")]
        ),
    ]

    @Test("a comment prints what the printers have always printed", arguments: expectations)
    func printedText(of expectation: Expectation) {
        #expect(expectation.comment.string == expectation.text)
    }

    @Test("a comment is made of the segments agreed with RuntimeViewer", arguments: expectations)
    func segments(of expectation: Expectation) {
        #expect(expectation.comment.segments == expectation.segments)
    }

    /// The comment is the atom `Comment` / `InlineComment` made: one
    /// `.comment` atom, so a print's spans and elements do not change.
    @Test("a comment prints as the one atom Comment and InlineComment made")
    func printsAsOneAtom() {
        let lineComment = SemanticString { StructuredComment.memberAddress(addressString: "135DC", qualifier: "getter") }
        #expect(lineComment.components == SemanticString { Comment("Address (getter): 0x135DC") }.components)

        let inlineComment = SemanticString { StructuredComment.spareBits(totalSpareBits: 12) }
        #expect(inlineComment.components == SemanticString { InlineComment("Spare Bits: 12 total") }.components)
    }

    // MARK: - Comments built from other values

    /// The output of a tagged multi-payload enum in SymbolTestsCore.
    @Test("an enum layout summary is its strategy and the facts of summaryDescription")
    func enumLayoutSummary() {
        let layoutResult = EnumLayoutCalculator.LayoutResult(
            strategyDescription: "Tagged Multi-Payload (tag bytes after the payload area)",
            bitsNeededForTag: 8,
            bitsAvailableForPayload: 192,
            numTags: 3,
            extraInhabitantCount: 253,
            tagRegion: EnumLayoutCalculator.SpareRegion(range: 24 ..< 25, bitCount: 8, bytes: [0xFF]),
            payloadRegion: nil,
            cases: [
                .init(caseIndex: 0, caseName: "payload case #0", isPayloadCase: true, tagValue: 0, payloadValue: 0, memoryChanges: [0x18: 0x00]),
                .init(caseIndex: 1, caseName: "payload case #1", isPayloadCase: true, tagValue: 1, payloadValue: 0, memoryChanges: [0x18: 0x01]),
                .init(caseIndex: 2, caseName: "empty case #0", isPayloadCase: false, tagValue: 2, payloadValue: 0, memoryChanges: [0x18: 0x02]),
            ]
        )
        let comment = StructuredComment.enumLayoutSummary(layoutResult)
        #expect(comment.string == "/* Tagged Multi-Payload (tag bytes after the payload area) — cases: 3 (2 payload + 1 empty); tag values used: 3; tag bits: 8; tag region: offsets 24..<25 (8 bits); leftover extra inhabitants for an outer enum: 253 */")
        #expect(comment.segments == [
            .marker("/* "), .label("Tagged Multi-Payload (tag bytes after the payload area)"), .separator(" — "),
            .key("cases"), .separator(": "), .value("3 (2 payload + 1 empty)"), .separator("; "),
            .key("tag values used"), .separator(": "), .value("3"), .separator("; "),
            .key("tag bits"), .separator(": "), .value("8"), .separator("; "),
            .key("tag region"), .separator(": "), .value("offsets 24..<25 (8 bits)"), .separator("; "),
            .key("leftover extra inhabitants for an outer enum"), .separator(": "), .value("253"),
            .marker(" */"),
        ])
    }

    @Test("a source-file line names the declaration, the file and the module")
    func privateDeclarationSourceSegments() {
        let body = PrivateDeclarationSourceFileComments.lineBody(
            for: PrivateDeclaration(name: "EnabledKey", discriminator: "_09CE35833F3876FE3A3A46977D61FC64"),
            sourceFile: .init(fileName: "Enabled.swift", moduleName: "SwiftUICore", isSynthesized: false),
            printedModuleName: "SwiftUI"
        )
        #expect(body == [
            .name("EnabledKey"), .separator(" "), .text("is declared in"), .separator(" "), .value("Enabled.swift"),
            .separator(" "), .text("of module"), .separator(" "), .name("SwiftUICore"),
        ])
    }

    @Test("an unrecovered source file is said so, with its discriminator as a value")
    func unrecoveredPrivateDeclarationSourceSegments() {
        let body = PrivateDeclarationSourceFileComments.lineBody(
            for: PrivateDeclaration(name: nil, discriminator: "_1282F137F8790A6AF4B7E2738A640142"),
            sourceFile: nil,
            printedModuleName: "SymbolTestsCore"
        )
        #expect(body == [
            .text("Declared in a source file whose name could not be recovered"), .separator(" ("),
            .key("private discriminator"), .separator(" "), .value("_1282F137F8790A6AF4B7E2738A640142"), .separator(")"),
        ])
    }

    /// The padding that lines the types up belongs to the separator after the
    /// condition, never to the condition itself.
    @Test("a conditional witness names the associated type, then each branch's condition and type")
    func conditionalWitnessSegments() {
        let macOS: UInt32 = 1
        let lineBodies = ConditionalWitnessComment.lineBodies(
            associatedTypeName: "Body",
            branches: [
                ConditionalWitnessComment.Branch(
                    availability: PlatformAvailabilityCondition(platform: macOS, major: 26, minor: 0, patch: 0, isSatisfiedBranch: true),
                    typeText: "M.Box<M.Static>"
                ),
                ConditionalWitnessComment.Branch(
                    availability: PlatformAvailabilityCondition(platform: macOS, major: 26, minor: 0, patch: 0, isSatisfiedBranch: false),
                    typeText: "M.Box<M.Dynamic>"
                ),
            ]
        )
        #expect(lineBodies == [
            [.name("Body"), .separator(" "), .text("is picked at run time by an availability check (SE-0360)"), .separator(":")],
            [.marker("  "), .qualifier("macOS 26.0 or later"), .separator(": "), .type("M.Box<M.Static>")],
            [.marker("  "), .qualifier("before macOS 26.0"), .separator(":   "), .type("M.Box<M.Dynamic>")],
        ])
    }
}
