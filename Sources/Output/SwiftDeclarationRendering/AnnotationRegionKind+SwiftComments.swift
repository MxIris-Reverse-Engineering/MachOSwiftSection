import Semantic

// The kinds of the comments the interface prints (evolution proposal
// `comment-structure`): the region a print with
// `SwiftDeclarationPrintConfiguration.marksCommentStructure` puts each comment
// in. Every other explanatory comment is a `note`, which swift-semantic-string
// defines itself. A host that meets a kind it does not know draws it as a
// note: kinds are added as the printers add comments.

extension AnnotationRegion.Kind {
    /// `// Address: 0x135DC`, `// Address (getter): 0x135DC`: where a member's
    /// implementation — or one accessor's, or a class's destructor — lives.
    public static let memberAddress = Self("memberAddress")

    /// `// VTable offset: 12`, `// VTable offset (setter): 13`.
    public static let vtableOffset = Self("vtableOffset")

    /// `// PWT offset: 0x18`: a protocol requirement's offset in the witness
    /// table.
    public static let pwtOffset = Self("pwtOffset")

    /// `// Field offset: 0x8`, and below it, when the expanded offsets print,
    /// the tree of the field's own fields: one `fieldLayoutNode` for each row.
    public static let fieldOffset = Self("fieldOffset")

    /// `// Field offset: unknown (generic parameter not substituted)`.
    public static let fieldOffsetUnknown = Self("fieldOffsetUnknown")

    /// `// │   ├── _countAndFlagsBits (Swift.UInt64): 0x8`: one row of the
    /// expanded field-offset tree and the rows nested under it, each a
    /// `fieldLayoutNode` of its own.
    public static let fieldLayoutNode = Self("fieldLayoutNode")

    /// `// Type Layout: (size: 16, stride: 16, alignment: 8, extraInhabitantCount: 0)`;
    /// for a tuple read in process, the whole block of its elements' layouts
    /// and its own.
    public static let typeLayout = Self("typeLayout")

    /// One element of a tuple's type layout block: its `// Type: Swift.Int`
    /// and `// Layout: (…)` lines.
    public static let typeLayoutElement = Self("typeLayoutElement")

    /// `/* Tagged Multi-Payload (tag bytes after the payload area) — cases: 3
    /// (2 payload + 1 empty); … */`: an enum's layout strategy and its facts.
    public static let enumLayoutSummary = Self("enumLayoutSummary")

    /// `/* Enum Layout */` and the block of lines below it that describes one
    /// case, each line a region of one of the five kinds that follow.
    public static let enumLayoutCase = Self("enumLayoutCase")

    /// ``// Case 1 (0x01) `withPair` — payload case #1``.
    public static let enumLayoutCaseHeader = Self("enumLayoutCaseHeader")

    /// `//   encoding: tag byte(s) after the payload area = 1; …`.
    public static let enumLayoutCaseEncoding = Self("enumLayoutCaseEncoding")

    /// `//   note: the exact bytes depend on …`.
    public static let enumLayoutCaseNote = Self("enumLayoutCaseNote")

    /// `//   fixed bytes: byte[0x18] = 0x1 (0b00000001)`.
    public static let enumLayoutCaseFixedBytes = Self("enumLayoutCaseFixedBytes")

    /// `//       offset 0x18 = 0x01 (0b00000001)`: one fixed byte.
    public static let enumLayoutCaseByte = Self("enumLayoutCaseByte")

    /// `// not exported`.
    public static let exportStatus = Self("exportStatus")

    /// `// protocol-extension default`.
    public static let protocolExtensionDefault = Self("protocolExtensionDefault")

    /// `// EnabledKey is declared in Enabled.swift of module SwiftUICore`.
    public static let privateDeclarationSource = Self("privateDeclarationSource")

    /// `// Body is picked at run time by an availability check (SE-0360):`
    /// and the lines below it, each a `conditionalWitnessBranch`.
    public static let conditionalWitness = Self("conditionalWitness")

    /// `//   macOS 26.0 or later: some SwiftUI.View`.
    public static let conditionalWitnessBranch = Self("conditionalWitnessBranch")

    /// `// Kind: Method, isAsync: false, isInstance: true`: what a protocol
    /// requirement whose symbol was stripped still records.
    public static let strippedSymbolicRequirement = Self("strippedSymbolicRequirement")

    // Comments only the dump prints, and the dump marks none.

    package static let deletedMethodSlot = Self("deletedMethodSlot")
    package static let ambiguousAttribution = Self("ambiguousAttribution")
    package static let spareBits = Self("spareBits")
}
