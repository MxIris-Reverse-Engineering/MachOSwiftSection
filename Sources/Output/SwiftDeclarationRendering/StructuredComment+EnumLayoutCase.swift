import Foundation
import Semantic
import OutputTransformer
import SwiftOutputTransformer
@_spi(Internals) import SwiftInspection

// One enum case's layout block, marked line by line (evolution proposal
// `comment-structure`). Unmarked, the block prints through
// `EnumCaseProjection.description(indent:prefix:)` — the `.detailed` template
// the dump and the template engine share — so this spells the same lines a
// second time, one segment at a time. `StructuredCommentTests` holds the two
// to the same text for every wording, and the contract tests for every enum
// of the fixture.

extension StructuredComment {
    /// The layout block of one case as `description(indent: indentation,
    /// prefix: "//")` prints it — one annotated atom, each line a region:
    /// the header, the encoding, the note, the fixed bytes, then one region
    /// for each fixed byte. A line's code indentation and its line break lie
    /// outside its region.
    package static func annotatedEnumLayoutCaseBlock(_ caseProjection: EnumLayoutCalculator.EnumCaseProjection, indentation: Int) -> AnnotatedAtom {
        let caseInput = Transformer.SwiftEnumLayout.CaseInput(caseProjection)
        var lines: [(kind: AnnotationRegion.Kind, body: [Segment])] = [(.enumLayoutCaseHeader, enumLayoutCaseHeaderBody(caseInput))]
        if !caseInput.encoding.isEmpty {
            lines.append((.enumLayoutCaseEncoding, [.label("encoding"), .separator(": "), .text(caseInput.encoding)]))
        }
        if !caseInput.patternNote.isEmpty {
            lines.append((.enumLayoutCaseNote, [.label("note"), .separator(": "), .text(caseInput.patternNote)]))
        }
        lines.append((.enumLayoutCaseFixedBytes, enumLayoutCaseFixedBytesBody(caseProjection, caseInput: caseInput)))
        for (offset, value) in caseProjection.memoryChanges.sorted(by: { $0.key < $1.key }) {
            // The detail lines sit four spaces further in than the others.
            let body = enumLayoutCaseByteBody(offset: offset, value: value, fixedBitMask: caseProjection.fixedBitMask(atByteOffset: offset))
            lines.append((.enumLayoutCaseByte, [.marker("    ")] + body))
        }

        let codeIndentation = String(repeating: "    ", count: indentation)
        var blockPieces = SemanticString()
        for (lineIndex, line) in lines.enumerated() {
            // Every line after the first is a continuation, two spaces in.
            let marker: [Segment] = lineIndex == 0 ? [.marker("// ")] : [.marker("// "), .marker("  ")]
            blockPieces.append(Standard(codeIndentation))
            blockPieces.append(AnnotationRegion(line.kind, content: Self.pieces(of: marker + line.body)))
            blockPieces.append(Standard("\n"))
        }
        return AnnotatedAtom(type: .comment, content: blockPieces)
    }

    /// ``Case 1 (0x01) `withPair` — payload case #1``: the case's index, in
    /// decimal and in hexadecimal, its declared name when the records keep
    /// one, and its structural label.
    private static func enumLayoutCaseHeaderBody(_ caseInput: Transformer.SwiftEnumLayout.CaseInput) -> [Segment] {
        var body: [Segment] = [
            .label("Case"), .separator(" "), .value(String(caseInput.caseIndex)),
            .separator(" ("), .value(String(format: "0x%02X", caseInput.caseIndex)),
        ]
        if let declaredName = caseInput.declaredName {
            body += [.separator(") `"), .name(declaredName), .separator("` — ")]
        } else {
            body.append(.separator(") — "))
        }
        return body + structuralCaseNameBody(caseInput.caseName)
    }

    /// `payload case #1` as the kind of case and its number among the cases
    /// of that kind; a label of any other shape, whole.
    private static func structuralCaseNameBody(_ caseName: String) -> [Segment] {
        guard let numberSeparator = caseName.range(of: " #", options: .backwards) else {
            return [.key(caseName)]
        }
        let number = caseName[numberSeparator.upperBound...]
        guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return [.key(caseName)]
        }
        return [.key(String(caseName[..<numberSeparator.lowerBound])), .separator(" #"), .value(String(number))]
    }

    /// `fixed bytes: byte[0x18] = 0x1 (0b00000001)`, a value for each run of
    /// bytes. When the case fixes none, the template's own wording of why.
    private static func enumLayoutCaseFixedBytesBody(_ caseProjection: EnumLayoutCalculator.EnumCaseProjection, caseInput: Transformer.SwiftEnumLayout.CaseInput) -> [Segment] {
        let labelText = "fixed bytes: "
        guard !caseProjection.memoryChanges.isEmpty else {
            let line = caseInput.fixedBytesLine
            guard line.hasPrefix(labelText) else {
                return [.text(line)]
            }
            return [.label("fixed bytes"), .separator(": "), .text(String(line.dropFirst(labelText.count)))]
        }
        var body: [Segment] = [.label("fixed bytes"), .separator(": ")]
        for (runIndex, run) in caseProjection.formattedFixedByteRuns().enumerated() {
            if runIndex > 0 {
                body.append(.separator(", "))
            }
            body.append(.value(run))
        }
        return body
    }

    /// `offset 0x18 = 0x01 (0b00000001)`, or for a byte only some of whose
    /// bits are fixed, `offset 0x00: fixed bits 0b11000000 = 0b10000000 (the
    /// other bits hold payload storage)` — `builtInOffsetDescription`'s
    /// wordings.
    private static func enumLayoutCaseByteBody(offset: Int, value: UInt8, fixedBitMask: UInt8) -> [Segment] {
        let offsetText = String(format: "0x%02X", offset)
        if fixedBitMask == 0xFF {
            return [
                .label("offset"), .separator(" "), .key(offsetText), .separator(" = "),
                .value(String(format: "0x%02X", value)), .separator(" ("), .value("0b" + paddedBinary(value)), .separator(")"),
            ]
        }
        return [
            .label("offset"), .separator(" "), .key(offsetText), .separator(": "),
            .label("fixed bits"), .separator(" "), .value("0b" + paddedBinary(fixedBitMask)), .separator(" = "),
            .value("0b" + paddedBinary(value)), .separator(" ("), .text("the other bits hold payload storage"), .separator(")"),
        ]
    }

    private static func paddedBinary(_ byteValue: UInt8) -> String {
        let binaryDigits = String(byteValue, radix: 2)
        return String(repeating: "0", count: 8 - binaryDigits.count) + binaryDigits
    }
}
