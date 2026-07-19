import Foundation
import Testing
import SemanticTransformer
@testable @_spi(Internals) import SwiftInspection

/// Unit tests for the enum-layout comment token templates
/// (`Transformer.SwiftEnumLayout`) and their presets.
///
/// The projections under test are hand-built (no Mach-O required): one
/// spare-bits payload case with a partially-fixed byte, one empty case with a
/// contiguous byte run, and one unresolved-extra-inhabitant case — together
/// they exercise every conditional wording the templates cover.
@Suite
struct EnumLayoutCommentTemplateTests {

    // MARK: - Fixtures

    /// A spare-bits payload case: tag scattered into byte 7's high nibble and
    /// byte 0's low three bits (both bytes shared with live payload storage).
    private static let sparBitsPayloadCase = EnumLayoutCalculator.EnumCaseProjection(
        caseIndex: 1,
        caseName: "payload case #1",
        declaredName: "foregroundKeyColor",
        isPayloadCase: true,
        tagValue: 1,
        payloadValue: 0,
        memoryChanges: [0: 0b0000_0000, 7: 0b0100_0000],
        fixedBitMasks: [0: 0b0000_0111, 7: 0b1111_0000],
        encodingExplanation: "tag 1 scattered into the payloads' common spare bits; the occupied (non-spare) bits hold this payload's value"
    )

    /// An empty case fixing a whole contiguous byte run.
    private static let emptyCase = EnumLayoutCalculator.EnumCaseProjection(
        caseIndex: 2,
        caseName: "empty case #0",
        declaredName: "none",
        isPayloadCase: false,
        tagValue: 2,
        payloadValue: 0,
        memoryChanges: [8: 0x01, 9: 0x00],
        encodingExplanation: "stored via extra tag bytes"
    )

    /// An unresolved extra-inhabitant empty case (offline path).
    private static let unresolvedCase = EnumLayoutCalculator.EnumCaseProjection(
        caseIndex: 3,
        caseName: "empty case #1",
        declaredName: "sentinel",
        isPayloadCase: false,
        tagValue: 3,
        payloadValue: 0,
        memoryChanges: [:],
        patternResolution: .unresolvedExtraInhabitant(extraInhabitantIndex: 1),
        encodingExplanation: "stored as the payload's extra-inhabitant pattern #1 (an invalid payload bit pattern)"
    )

    private static let layoutResult = EnumLayoutCalculator.LayoutResult(
        strategyDescription: "Multi-Payload (Spare Bits)",
        bitsNeededForTag: 2,
        bitsAvailableForPayload: 62,
        numTags: 3,
        extraInhabitantCount: 5,
        tagRegion: EnumLayoutCalculator.SpareRegion(range: 7 ..< 8, bitCount: 2, bytes: [0b1100_0000]),
        payloadRegion: EnumLayoutCalculator.SpareRegion(range: 0 ..< 8, bitCount: 62, bytes: []),
        cases: [sparBitsPayloadCase, emptyCase, unresolvedCase]
    )

    // MARK: - The .detailed preset is the built-in rendering

    @Test func detailedPresetReproducesBuiltInRenderingExactly() {
        for caseProjection in Self.layoutResult.cases {
            #expect(
                caseProjection.description(indent: 1, prefix: "//", template: .detailed)
                    == caseProjection.description(indent: 1, prefix: "//")
            )
        }
        #expect(
            Transformer.SwiftEnumLayout.detailed.renderStrategyComment(for: Self.layoutResult)
                == Self.layoutResult.summaryDescription
        )
    }

    @Test func detailedPartialMaskLineUsesBitMaskForm() {
        let rendered = Transformer.SwiftEnumLayout.detailed.renderCaseComment(for: Self.sparBitsPayloadCase)
        #expect(rendered.contains("offset 0x00: fixed bits 0b00000111 = 0b00000000 (the other bits hold payload storage)"))
        #expect(rendered.contains("offset 0x07: fixed bits 0b11110000 = 0b01000000 (the other bits hold payload storage)"))
    }

    // MARK: - The .explained preset narrates bit ranges

    @Test func explainedPresetNarratesPartialMaskAsBitRanges() {
        let rendered = Transformer.SwiftEnumLayout.explained.renderCaseComment(for: Self.sparBitsPayloadCase)
        #expect(rendered.contains("offset 0x00: bits 2-0 are always 000; the other bits (7-3) hold payload data"))
        #expect(rendered.contains("offset 0x07: bits 7-4 are always 0100; the other bits (3-0) hold payload data"))
        // Fully-fixed bytes keep the plain value form.
        let emptyRendered = Transformer.SwiftEnumLayout.explained.renderCaseComment(for: Self.emptyCase)
        #expect(emptyRendered.contains("offset 0x08: 0x01 (0b00000001)"))
    }

    @Test func fixedBitsPhraseHandlesNonContiguousAndSingleBitMasks() {
        // 0b11110001: two fixed groups (bits 7-4 and bit 0).
        #expect(
            Transformer.SwiftEnumLayout.fixedBitsPhrase(value: 0b1010_0001, fixedBitMask: 0b1111_0001)
                == "bits 7-4 are always 1010, bit 0 is always 1; the other bits (3-1) hold payload data"
        )
        #expect(
            Transformer.SwiftEnumLayout.fixedBitsPhrase(value: 0x2A, fixedBitMask: 0xFF)
                == "0x2A (0b00101010)"
        )
    }

    // MARK: - Terser presets

    @Test func standardPresetOmitsPerByteDetail() {
        let rendered = Transformer.SwiftEnumLayout.standard.renderCaseComment(for: Self.emptyCase)
        #expect(rendered.contains("Case 2 (0x02) `none` — empty case #0"))
        #expect(rendered.contains("encoding: stored via extra tag bytes"))
        #expect(rendered.contains("fixed bytes: bytes[0x8..<0xa] = 0x1"))
        #expect(!rendered.contains("offset 0x08"))
    }

    @Test func compactPresetRendersOneLinePerCase() {
        let rendered = Transformer.SwiftEnumLayout.compact.renderCaseComment(for: Self.sparBitsPayloadCase)
        #expect(rendered == "[0x01] `foregroundKeyColor` — payload case, tag 1")
        #expect(
            Transformer.SwiftEnumLayout.compact.renderStrategyComment(for: Self.layoutResult)
                == "Multi-Payload (Spare Bits)"
        )
    }

    // MARK: - Conditional line-tokens

    @Test func emptyConditionalLinesAreDropped() {
        // The unresolved case has no fixed bytes: no per-byte lines, and the
        // note line appears; the payload case has no note line.
        let unresolvedRendered = Transformer.SwiftEnumLayout.detailed.renderCaseComment(for: Self.unresolvedCase)
        #expect(unresolvedRendered.contains("note: the exact bytes depend on the payload type's extra-inhabitant scheme"))
        #expect(unresolvedRendered.contains("fixed bytes: not computed"))
        #expect(!unresolvedRendered.contains("\n\n"))
        let payloadRendered = Transformer.SwiftEnumLayout.detailed.renderCaseComment(for: Self.sparBitsPayloadCase)
        #expect(!payloadRendered.contains("note:"))
    }

    @Test func payloadCaseWithoutFixedBytesExplainsSelectionRule() {
        let bareCase = EnumLayoutCalculator.EnumCaseProjection(
            caseIndex: 0,
            caseName: "payload case",
            isPayloadCase: true,
            tagValue: 0,
            payloadValue: 0,
            memoryChanges: [:]
        )
        let rendered = Transformer.SwiftEnumLayout.detailed.renderCaseComment(for: bareCase)
        #expect(rendered.contains("fixed bytes: none — any pattern no empty case claims selects this case"))
        // No declared name: the header omits the backtick segment.
        #expect(rendered.contains("Case 0 (0x00) — payload case"))
    }

    // MARK: - Historical auto-append compatibility

    /// A case template referencing none of the byte-information tokens (like
    /// the pre-migration RuntimeViewer catalogs) still shows the note and the
    /// fixed-byte lines — the historical auto-append behavior.
    @Test func templateWithoutByteTokensGetsDetailsAppended() {
        var classicModule = Transformer.SwiftEnumLayout.detailed
        classicModule.caseTemplate = Transformer.SwiftEnumLayout.CaseTemplates.classic
        let rendered = classicModule.renderCaseComment(for: Self.emptyCase)
        #expect(rendered.hasPrefix("Case 2 (0x02) - empty case #0:\nTag: 2"))
        #expect(rendered.contains("fixed bytes: bytes[0x8..<0xa] = 0x1"))
        #expect(rendered.contains("offset 0x08 = 0x01"))

        let unresolvedRendered = classicModule.renderCaseComment(for: Self.unresolvedCase)
        #expect(unresolvedRendered.contains("note: the exact bytes depend on the payload type's extra-inhabitant scheme"))
        #expect(unresolvedRendered.contains("fixed bytes: not computed"))
    }

    /// A mask-unaware memory-offset template must not over-claim a
    /// partially-fixed byte: the engine falls back to the mask-scoped built-in
    /// wording for that byte.
    @Test func maskUnawareMemoryOffsetTemplateFallsBackOnPartialBytes() {
        var compactBytesModule = Transformer.SwiftEnumLayout.detailed
        compactBytesModule.memoryOffsetTemplate = Transformer.SwiftEnumLayout.MemoryOffsetTemplates.compact
        let rendered = compactBytesModule.renderCaseComment(for: Self.sparBitsPayloadCase)
        #expect(rendered.contains("offset 0x00: fixed bits 0b00000111 = 0b00000000"))
        #expect(!rendered.contains("[0]=0x00"))
        // Fully-fixed bytes do go through the custom template.
        let emptyRendered = compactBytesModule.renderCaseComment(for: Self.emptyCase)
        #expect(emptyRendered.contains("[8]=0x01"))
    }

    // MARK: - Custom templates

    @Test func customTemplateSubstitutesRawTokens() {
        let customModule = Transformer.SwiftEnumLayout(
            template: "${strategy} | tags=${numTags} leftoverXI=${leftoverExtraInhabitantCount}",
            caseTemplate: "${caseIndex}:${declaredName}:${caseType}:${tagHex}:${memoryChangeCount}",
            memoryOffsetTemplate: "${offsetHex}=${valueHex}&${fixedBitMask}",
            appendsOmittedDetails: false
        )
        #expect(
            customModule.renderStrategyComment(for: Self.layoutResult)
                == "Multi-Payload (Spare Bits) | tags=3 leftoverXI=5"
        )
        #expect(
            customModule.renderCaseComment(for: Self.emptyCase)
                == "2:none:empty case:0x02:2"
        )
        #expect(
            customModule.transformMemoryOffset(.init(offset: 7, value: 0b0100_0000, fixedBitMask: 0b1111_0000))
                == "0x07=0x40&0xF0"
        )
    }

    @Test func hexadecimalModeFormatsNumericTokens() {
        var hexModule = Transformer.SwiftEnumLayout.compact
        hexModule.useHexadecimal = true
        hexModule.caseTemplate = "tag ${tagValue} index ${caseIndex}"
        let twelvePayloadCase = EnumLayoutCalculator.EnumCaseProjection(
            caseIndex: 12,
            caseName: "empty case #9",
            isPayloadCase: false,
            tagValue: 12,
            payloadValue: 0,
            memoryChanges: [:]
        )
        #expect(hexModule.renderCaseComment(for: twelvePayloadCase) == "tag 0xC index 0xC")
    }

    @Test func declaredNameFallsBackToStructuralName() {
        let anonymousCase = EnumLayoutCalculator.EnumCaseProjection(
            caseIndex: 0,
            caseName: "empty case #0",
            isPayloadCase: false,
            tagValue: 0,
            payloadValue: 0,
            memoryChanges: [:]
        )
        let rendered = Transformer.SwiftEnumLayout.compact.renderCaseComment(for: anonymousCase)
        #expect(rendered == "[0x00] `empty case #0` — empty case, tag 0")
    }
}
