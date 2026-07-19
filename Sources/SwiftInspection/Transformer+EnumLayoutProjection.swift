import Foundation
import SemanticTransformer

/// Bridges `EnumLayoutCalculator`'s projection types into the
/// `Transformer.SwiftEnumLayout` token-template engine, so a template renders
/// directly from a `LayoutResult` / `EnumCaseProjection` without the caller
/// assembling inputs by hand.

// MARK: - Input Construction

extension Transformer.SwiftEnumLayout.Input {
    /// Builds the strategy-header input from a layout result.
    public init(_ layoutResult: EnumLayoutCalculator.LayoutResult) {
        let payloadCaseCount = layoutResult.cases.count { $0.isPayloadCase }
        self.init(
            strategy: layoutResult.strategyDescription,
            summary: layoutResult.summaryDescription,
            bitsNeededForTag: layoutResult.bitsNeededForTag,
            bitsAvailableForPayload: layoutResult.bitsAvailableForPayload,
            numTags: layoutResult.numTags,
            totalCases: layoutResult.cases.count,
            payloadCaseCount: payloadCaseCount,
            emptyCaseCount: layoutResult.cases.count - payloadCaseCount,
            leftoverExtraInhabitantCount: layoutResult.extraInhabitantCount,
            tagRegionRange: layoutResult.tagRegion.map { "\($0.range)" } ?? "none",
            tagRegionBitCount: layoutResult.tagRegion?.bitCount ?? 0,
            tagRegionBytesHex: layoutResult.tagRegion.map { $0.bytes.map { String(format: "%02X", $0) }.joined(separator: " ") } ?? "N/A",
            payloadRegionRange: layoutResult.payloadRegion.map { "\($0.range)" } ?? "none",
            payloadRegionBitCount: layoutResult.payloadRegion?.bitCount ?? 0,
            payloadRegionBytesHex: layoutResult.payloadRegion.map { $0.bytes.map { String(format: "%02X", $0) }.joined(separator: " ") } ?? "N/A"
        )
    }
}

extension Transformer.SwiftEnumLayout.CaseInput {
    /// Builds the per-case input from a case projection.
    public init(_ caseProjection: EnumLayoutCalculator.EnumCaseProjection) {
        let isPatternUnresolved: Bool
        let patternNote: String
        switch caseProjection.patternResolution {
        case .exactBytes:
            isPatternUnresolved = false
            patternNote = ""
        case .unresolvedExtraInhabitant:
            isPatternUnresolved = true
            patternNote = "the exact bytes depend on the payload type's extra-inhabitant scheme and were not resolved offline (the in-process runtime path resolves them)"
        }
        self.init(
            caseIndex: caseProjection.caseIndex,
            caseName: caseProjection.caseName,
            declaredName: caseProjection.declaredName,
            isPayloadCase: caseProjection.isPayloadCase,
            tagValue: caseProjection.tagValue,
            payloadValue: caseProjection.payloadValue,
            encoding: caseProjection.encodingExplanation,
            isPatternUnresolved: isPatternUnresolved,
            patternNote: patternNote,
            fixedBytesSummary: caseProjection.memoryChanges.isEmpty ? "" : caseProjection.formattedFixedBytes(),
            memoryChanges: caseProjection.memoryChanges,
            fixedBitMasks: caseProjection.fixedBitMasks
        )
    }
}

// MARK: - Rendering Conveniences

extension Transformer.SwiftEnumLayout {
    /// Renders the type-level strategy comment line for `layoutResult`.
    public func renderStrategyComment(for layoutResult: EnumLayoutCalculator.LayoutResult) -> String {
        transform(Input(layoutResult))
    }

    /// Renders one case's comment block (multi-line, unindented and without a
    /// comment prefix — see
    /// `EnumCaseProjection.description(indent:prefix:template:)` for the
    /// wrapped form).
    public func renderCaseComment(for caseProjection: EnumLayoutCalculator.EnumCaseProjection) -> String {
        transformCase(CaseInput(caseProjection))
    }
}

extension EnumLayoutCalculator.EnumCaseProjection {
    /// Renders this case's comment block through `template`, wrapped with the
    /// same indent/prefix layout as the built-in ``description(indent:prefix:)``.
    public func description(indent: Int, prefix: String = "", template: Transformer.SwiftEnumLayout) -> String {
        let indentString = String(repeating: "    ", count: indent)
        var output = ""
        for (lineIndex, line) in template.renderCaseComment(for: self).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let continuationIndent = lineIndex == 0 ? "" : "  "
            output += "\(indentString)\(prefix) \(continuationIndent)\(line)\n"
        }
        return output
    }
}
