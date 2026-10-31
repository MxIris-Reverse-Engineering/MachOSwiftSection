@_spi(Internals) import SwiftInspection

// The comments the dump and the interface print, each spelled out once
// (evolution proposal `comment-structure`). A doc comment shows the text a
// factory prints; the segments it is made of follow the proposal's table.

// MARK: - Addresses and Offsets

extension StructuredComment {
    /// `// Address: 0x135DC`, or `// Address (getter): 0x135DC` with the
    /// accessor — or `destructor` — it is the address of.
    package static func memberAddress(addressString: String, qualifier: String? = nil) -> Self {
        labeledValue("Address", qualifier: qualifier, value: "0x" + addressString)
    }

    /// `// VTable offset: 12`, or `// VTable offset (setter): 13` with the
    /// accessor owning the slot.
    package static func vtableOffset(_ slotOffset: Int, qualifier: String? = nil) -> Self {
        labeledValue("VTable offset", qualifier: qualifier, value: String(slotOffset))
    }

    /// `// Field offset: 0x8`.
    package static func fieldOffset(_ offset: Int) -> Self {
        Self.offset(labeled: "Field offset", offset)
    }

    /// `// PWT offset: 0x18`.
    package static func pwtOffset(_ offset: Int) -> Self {
        Self.offset(labeled: "PWT offset", offset)
    }

    /// `// <label>: 0x18`: an offset, in hexadecimal, under `label`.
    package static func offset(labeled label: String, _ offset: Int) -> Self {
        labeledValue(label, value: hexadecimal(offset))
    }

    /// `// Field offset: unknown (generic parameter not substituted)`: the
    /// offset could not be computed, and why.
    package static func unknownFieldOffset(reasonDescription: String) -> Self {
        line([
            .label("Field offset"), .separator(": "), .value("unknown"),
            .separator(" ("), .text(reasonDescription), .separator(")"),
        ])
    }

    /// `// │   ├── _countAndFlagsBits (Swift.UInt64): 0x8`: one row of the
    /// expanded field-offset tree. An empty `typeName` prints none:
    /// `// └── _value: 0x8`.
    package static func fieldLayoutNode(treePrefix: String, fieldName: String, typeName: String, offset: Int) -> Self {
        if typeName.isEmpty {
            return line([.treePrefix(treePrefix), .name(fieldName), .separator(": "), .value(hexadecimal(offset))])
        }
        return line([
            .treePrefix(treePrefix), .name(fieldName), .separator(" ("), .type(typeName), .separator("): "),
            .value(hexadecimal(offset)),
        ])
    }

    private static func labeledValue(_ label: String, qualifier: String? = nil, value: String) -> Self {
        if let qualifier {
            return line([.label(label), .separator(" ("), .qualifier(qualifier), .separator("): "), .value(value)])
        }
        return line([.label(label), .separator(": "), .value(value)])
    }

    private static func hexadecimal(_ value: Int) -> String {
        "0x" + String(value, radix: 16)
    }
}

// MARK: - Type Layouts

extension StructuredComment {
    /// `// Type Layout: (size: 16, stride: 16, alignment: 8, extraInhabitantCount: 2147483647)`.
    /// `label` is `Layout` for the lines of a tuple's layout block.
    package static func typeLayout(
        labeled label: String = "Type Layout",
        size: some BinaryInteger,
        stride: some BinaryInteger,
        alignment: some BinaryInteger,
        extraInhabitantCount: some BinaryInteger
    ) -> Self {
        line([
            .label(label), .separator(": ("),
            .key("size"), .separator(": "), .value(String(size)), .separator(", "),
            .key("stride"), .separator(": "), .value(String(stride)), .separator(", "),
            .key("alignment"), .separator(": "), .value(String(alignment)), .separator(", "),
            .key("extraInhabitantCount"), .separator(": "), .value(String(extraInhabitantCount)),
            .separator(")"),
        ])
    }

    /// `/* Type Layout */`, heading the layout block of a tuple.
    package static let tupleTypeLayoutHeading = inline([.label("Type Layout")])

    /// `// Type: Swift.Int`: the element of a tuple whose layout follows.
    package static func tupleElementType(_ typeName: String) -> Self {
        line([.label("Type"), .separator(": "), .type(typeName)])
    }

    /// `// Total: `, ahead of the tuple's own layout.
    package static let tupleTypeLayoutTotal = line([.label("Total"), .separator(": ")])
}

// MARK: - Enum Layouts

extension StructuredComment {
    /// `/* Tagged Multi-Payload (tag bytes after the payload area) — cases: 3
    /// (2 payload + 1 empty); …; leftover extra inhabitants for an outer enum:
    /// 253 */`: the strategy and the facts of `summaryDescription`.
    package static func enumLayoutSummary(_ layoutResult: EnumLayoutCalculator.LayoutResult) -> Self {
        var body: [Segment] = [.label(layoutResult.strategyDescription), .separator(" — ")]
        for (factIndex, fact) in layoutResult.summaryFacts.enumerated() {
            if factIndex > 0 {
                body.append(.separator("; "))
            }
            body += [.key(fact.key), .separator(": "), .value(fact.value)]
        }
        return inline(body)
    }

    /// `/* Enum Layout */`, heading the layout block of one case.
    package static let enumLayoutCaseHeading = inline([.label("Enum Layout")])

    /// The layout block of one case, as one comment: lines in their prefix
    /// and indentation, each ending in a line break.
    package static func enumLayoutCaseBlock(_ block: String) -> Self {
        Self(segments: [.plain(block)])
    }

    /// `/* Spare Bits: 12 total */`.
    package static func spareBits(totalSpareBits: Int) -> Self {
        inline([.label("Spare Bits"), .separator(": "), .value(String(totalSpareBits)), .separator(" "), .text("total")])
    }
}

// MARK: - Member Facts

extension StructuredComment {
    /// `// not exported`: none of the member's symbols is in the export trie.
    package static let exportStatus = line([.label("not exported")])

    /// `// protocol-extension default`: the witness resolved to a
    /// protocol-extension default.
    package static let protocolExtensionDefault = line([.label("protocol-extension default")])

    /// `// No implementation in this image (deleted method — slot retained for ABI)`.
    package static let deletedMethodSlot = note("No implementation in this image (deleted method — slot retained for ABI)")

    /// `// Attribution: ambiguous — 3 symbols folded at this address`.
    package static func ambiguousAttribution(foldedSymbolCount: Int) -> Self {
        line([
            .label("Attribution"), .separator(": "), .value("ambiguous"), .separator(" — "),
            .text("\(foldedSymbolCount) symbols folded at this address"),
        ])
    }

    /// `// Kind: Method, isAsync: false, isInstance: true`: what a protocol
    /// requirement whose symbol was stripped still records.
    package static func strippedSymbolicRequirement(kindDescription: String, isAsync: Bool, isInstance: Bool) -> Self {
        line([
            .key("Kind"), .separator(": "), .value(kindDescription), .separator(", "),
            .key("isAsync"), .separator(": "), .value(String(isAsync)), .separator(", "),
            .key("isInstance"), .separator(": "), .value(String(isInstance)),
        ])
    }
}
