import Foundation

// MARK: - Swift Enum Layout Transformer Module

extension Transformer {
    /// Customizes Swift enum layout comment format using token templates.
    ///
    /// Three template levels mirror the comment structure:
    /// - ``template`` renders the type-level strategy line.
    /// - ``caseTemplate`` renders one block per case (may span multiple lines).
    /// - ``memoryOffsetTemplate`` renders one line per fixed byte, consumed by
    ///   the case template through `${memoryChangesDetail}` (each line indented
    ///   by four spaces relative to the case block).
    ///
    /// After substitution, case-template lines that end up empty or
    /// whitespace-only are dropped, so templates can list conditional
    /// line-tokens (`${encodingLine}`, `${patternNoteLine}`) unconditionally.
    ///
    /// When ``appendsOmittedDetails`` is set (the default, matching the
    /// historical RuntimeViewer behavior), a case template that references none
    /// of the byte-information tokens gets the unresolved-pattern note and the
    /// fixed-byte lines appended automatically after it — so a terse header
    /// template still shows the bytes. Presets that deliberately omit bytes
    /// (``compact``) turn the flag off.
    public struct SwiftEnumLayout: Module {
        public typealias Parameter = Token
        public typealias Output = String

        public static let displayName = "Enum Layout Comment"

        public var isEnabled: Bool

        /// Template for the type-level strategy comment line.
        public var template: String

        /// Template for each case's comment block.
        public var caseTemplate: String

        /// Template for each fixed-byte line.
        public var memoryOffsetTemplate: String

        /// Renders numeric tokens as hexadecimal (`0x…`) instead of decimal.
        public var useHexadecimal: Bool

        /// Appends the pattern note and fixed-byte lines after a case template
        /// that does not reference them itself (see the type documentation).
        public var appendsOmittedDetails: Bool

        public init(
            isEnabled: Bool = false,
            template: String = Templates.libraryDefault,
            caseTemplate: String = CaseTemplates.standard,
            memoryOffsetTemplate: String = MemoryOffsetTemplates.libraryDefault,
            useHexadecimal: Bool = false,
            appendsOmittedDetails: Bool = true
        ) {
            self.isEnabled = isEnabled
            self.template = template
            self.caseTemplate = caseTemplate
            self.memoryOffsetTemplate = memoryOffsetTemplate
            self.useHexadecimal = useHexadecimal
            self.appendsOmittedDetails = appendsOmittedDetails
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
            self.template = try container.decodeIfPresent(String.self, forKey: .template) ?? Templates.libraryDefault
            self.caseTemplate = try container.decodeIfPresent(String.self, forKey: .caseTemplate) ?? CaseTemplates.standard
            self.memoryOffsetTemplate = try container.decodeIfPresent(String.self, forKey: .memoryOffsetTemplate) ?? MemoryOffsetTemplates.libraryDefault
            self.useHexadecimal = try container.decodeIfPresent(Bool.self, forKey: .useHexadecimal) ?? false
            self.appendsOmittedDetails = try container.decodeIfPresent(Bool.self, forKey: .appendsOmittedDetails) ?? true
        }

        /// Checks if the strategy template contains a specific token.
        public func contains(_ token: Token) -> Bool {
            template.contains(token.placeholder)
        }

        /// Checks if the case template contains a specific case token.
        public func containsCase(_ token: CaseToken) -> Bool {
            caseTemplate.contains(token.placeholder)
        }

        /// Checks if the memory offset template contains a specific token.
        public func containsMemoryOffset(_ token: MemoryOffsetToken) -> Bool {
            memoryOffsetTemplate.contains(token.placeholder)
        }
    }
}

// MARK: - Presets

extension Transformer.SwiftEnumLayout {
    /// The built-in template bundles, in decreasing order of detail.
    public enum Preset: String, CaseIterable, Sendable, Codable {
        /// Everything, byte-mask form — identical to the library's built-in
        /// rendering (encoding sentence, fixed-byte summary, per-byte lines
        /// with `fixed bits 0b… = 0b…` masks for partially-fixed bytes).
        case detailed
        /// Everything, but partially-fixed bytes are spelled as bit ranges in
        /// plain words — `offset 0x07: bits 7-4 are always 0100; the other
        /// bits (3-0) hold payload data` — instead of binary masks.
        case explained
        /// Per-case header + encoding sentence + one-line fixed-byte summary;
        /// no per-byte detail lines.
        case standard
        /// One line per case, one short strategy line; no byte information.
        case compact

        /// The configured (enabled) module for this preset.
        public var module: Transformer.SwiftEnumLayout {
            switch self {
            case .detailed: .detailed
            case .explained: .explained
            case .standard: .standard
            case .compact: .compact
            }
        }
    }

    /// The library default, reproducing the built-in rendering exactly
    /// (guaranteed by unit test).
    public static let detailed = Transformer.SwiftEnumLayout(
        isEnabled: true,
        template: Templates.libraryDefault,
        caseTemplate: CaseTemplates.standard,
        memoryOffsetTemplate: MemoryOffsetTemplates.libraryDefault
    )

    /// Same information as ``detailed``, with partially-fixed bytes narrated
    /// as bit ranges instead of binary masks.
    public static let explained = Transformer.SwiftEnumLayout(
        isEnabled: true,
        template: Templates.libraryDefault,
        caseTemplate: CaseTemplates.standard,
        memoryOffsetTemplate: MemoryOffsetTemplates.explained
    )

    /// Header + encoding + one-line fixed-byte summary; no per-byte lines.
    public static let standard = Transformer.SwiftEnumLayout(
        isEnabled: true,
        template: Templates.caseBreakdown,
        caseTemplate: CaseTemplates.summaryOnly,
        memoryOffsetTemplate: MemoryOffsetTemplates.libraryDefault
    )

    /// One line per case, one short strategy line.
    public static let compact = Transformer.SwiftEnumLayout(
        isEnabled: true,
        template: Templates.strategyOnly,
        caseTemplate: CaseTemplates.compactLine,
        memoryOffsetTemplate: MemoryOffsetTemplates.libraryDefault,
        appendsOmittedDetails: false
    )
}

// MARK: - Input (Strategy Header)

extension Transformer.SwiftEnumLayout {
    /// Input for strategy header transformation.
    public struct Input: Sendable {
        public let strategy: String
        /// The library's rich one-line summary (`LayoutResult.summaryDescription`):
        /// strategy + case counts + tag values/bits + regions + leftover extra
        /// inhabitants.
        public let summary: String
        public let bitsNeededForTag: Int
        public let bitsAvailableForPayload: Int
        public let numTags: Int
        public let totalCases: Int
        public let payloadCaseCount: Int
        public let emptyCaseCount: Int
        /// Extra inhabitants the enum leaves for an outer enum
        /// (`LayoutResult.extraInhabitantCount`).
        public let leftoverExtraInhabitantCount: Int
        public let tagRegionRange: String
        public let tagRegionBitCount: Int
        public let tagRegionBytesHex: String
        public let payloadRegionRange: String
        public let payloadRegionBitCount: Int
        public let payloadRegionBytesHex: String

        public init(
            strategy: String,
            summary: String = "",
            bitsNeededForTag: Int,
            bitsAvailableForPayload: Int,
            numTags: Int,
            totalCases: Int = 0,
            payloadCaseCount: Int = 0,
            emptyCaseCount: Int = 0,
            leftoverExtraInhabitantCount: Int = 0,
            tagRegionRange: String = "N/A",
            tagRegionBitCount: Int = 0,
            tagRegionBytesHex: String = "N/A",
            payloadRegionRange: String = "N/A",
            payloadRegionBitCount: Int = 0,
            payloadRegionBytesHex: String = "N/A"
        ) {
            self.strategy = strategy
            self.summary = summary
            self.bitsNeededForTag = bitsNeededForTag
            self.bitsAvailableForPayload = bitsAvailableForPayload
            self.numTags = numTags
            self.totalCases = totalCases
            self.payloadCaseCount = payloadCaseCount
            self.emptyCaseCount = emptyCaseCount
            self.leftoverExtraInhabitantCount = leftoverExtraInhabitantCount
            self.tagRegionRange = tagRegionRange
            self.tagRegionBitCount = tagRegionBitCount
            self.tagRegionBytesHex = tagRegionBytesHex
            self.payloadRegionRange = payloadRegionRange
            self.payloadRegionBitCount = payloadRegionBitCount
            self.payloadRegionBytesHex = payloadRegionBytesHex
        }
    }
}

// MARK: - Case Input

extension Transformer.SwiftEnumLayout {
    /// Input for per-case transformation — the raw facts of one case's
    /// projection; every derived wording (`${caseHeader}`,
    /// `${fixedBytesLine}`, `${memoryChangesDetail}`, …) is computed by
    /// ``transformCase(_:)`` from these fields.
    public struct CaseInput: Sendable {
        /// The case's tag index (payload cases first, then empty cases).
        public let caseIndex: Int
        /// Structural label from the library ("payload case #1", "empty case #0", …).
        public let caseName: String
        /// Source-level case name from the enum's field records; `nil` when
        /// the records carry none (tokens fall back to ``caseName``).
        public let declaredName: String?
        public let isPayloadCase: Bool
        public let tagValue: Int
        public let payloadValue: Int
        /// How the case is encoded, composed by the layout strategy.
        public let encoding: String
        /// Whether only the extra-inhabitant *index* is known (offline path
        /// without runtime projection) rather than the exact bytes.
        public let isPatternUnresolved: Bool
        /// A human note explaining an unresolved pattern; empty for exact ones.
        public let patternNote: String
        /// Run-compressed fixed bytes (e.g. "bytes[0x8..<0x10] = 0x1"); empty
        /// when the case fixes none.
        public let fixedBytesSummary: String
        /// Fixed bytes identifying this case, keyed by byte offset.
        public let memoryChanges: [Int: UInt8]
        /// Per-byte masks of which bits are actually fixed; an absent offset
        /// means the whole byte (`0xFF`).
        public let fixedBitMasks: [Int: UInt8]

        public init(
            caseIndex: Int,
            caseName: String,
            declaredName: String? = nil,
            isPayloadCase: Bool,
            tagValue: Int,
            payloadValue: Int,
            encoding: String = "",
            isPatternUnresolved: Bool = false,
            patternNote: String = "",
            fixedBytesSummary: String = "",
            memoryChanges: [Int: UInt8] = [:],
            fixedBitMasks: [Int: UInt8] = [:]
        ) {
            self.caseIndex = caseIndex
            self.caseName = caseName
            self.declaredName = declaredName
            self.isPayloadCase = isPayloadCase
            self.tagValue = tagValue
            self.payloadValue = payloadValue
            self.encoding = encoding
            self.isPatternUnresolved = isPatternUnresolved
            self.patternNote = patternNote
            self.fixedBytesSummary = fixedBytesSummary
            self.memoryChanges = memoryChanges
            self.fixedBitMasks = fixedBitMasks
        }

        func fixedBitMask(atByteOffset offset: Int) -> UInt8 {
            fixedBitMasks[offset] ?? 0xFF
        }

        /// The built-in header line: ``Case 1 (0x01) `caseName` — empty case #0``.
        public var headerDescription: String {
            var header = "Case \(caseIndex) (\(String(format: "0x%02X", caseIndex)))"
            if let declaredName {
                header += " `\(declaredName)`"
            }
            header += " — \(caseName)"
            return header
        }

        /// The `fixed bytes: …` line — always meaningful, using the built-in
        /// "none …" wordings when the case fixes no bytes.
        public var fixedBytesLine: String {
            if memoryChanges.isEmpty {
                if isPatternUnresolved {
                    return "fixed bytes: not computed"
                }
                if isPayloadCase {
                    return "fixed bytes: none — any pattern no empty case claims selects this case"
                }
                return "fixed bytes: none recorded"
            }
            return "fixed bytes: \(fixedBytesSummary)"
        }
    }
}

// MARK: - Memory Offset Input

extension Transformer.SwiftEnumLayout {
    /// Input for per-memory-offset transformation.
    public struct MemoryOffsetInput: Sendable {
        public let offset: Int
        public let value: UInt8
        /// Which bits of `value` are actually fixed for the case. `0xFF`
        /// (every bit — the common case) unless the byte is shared between a
        /// spare-bits tag and live payload storage.
        public let fixedBitMask: UInt8

        public init(offset: Int, value: UInt8, fixedBitMask: UInt8 = 0xFF) {
            self.offset = offset
            self.value = value
            self.fixedBitMask = fixedBitMask
        }
    }
}

// MARK: - Rendering

extension Transformer.SwiftEnumLayout {
    /// Renders the strategy header template with actual enum layout values.
    public func transform(_ input: Input) -> String {
        var rendered = template
        rendered = rendered.replacingOccurrences(of: Token.strategy.placeholder, with: input.strategy)
        rendered = rendered.replacingOccurrences(of: Token.summary.placeholder, with: input.summary)
        rendered = rendered.replacingOccurrences(of: Token.bitsNeededForTag.placeholder, with: formatNumeric(input.bitsNeededForTag))
        rendered = rendered.replacingOccurrences(of: Token.bitsAvailableForPayload.placeholder, with: formatNumeric(input.bitsAvailableForPayload))
        rendered = rendered.replacingOccurrences(of: Token.numTags.placeholder, with: formatNumeric(input.numTags))
        rendered = rendered.replacingOccurrences(of: Token.totalCases.placeholder, with: formatNumeric(input.totalCases))
        rendered = rendered.replacingOccurrences(of: Token.payloadCaseCount.placeholder, with: formatNumeric(input.payloadCaseCount))
        rendered = rendered.replacingOccurrences(of: Token.emptyCaseCount.placeholder, with: formatNumeric(input.emptyCaseCount))
        rendered = rendered.replacingOccurrences(of: Token.leftoverExtraInhabitantCount.placeholder, with: formatNumeric(input.leftoverExtraInhabitantCount))
        rendered = rendered.replacingOccurrences(of: Token.tagRegionRange.placeholder, with: input.tagRegionRange)
        rendered = rendered.replacingOccurrences(of: Token.tagRegionBitCount.placeholder, with: formatNumeric(input.tagRegionBitCount))
        rendered = rendered.replacingOccurrences(of: Token.tagRegionBytesHex.placeholder, with: input.tagRegionBytesHex)
        rendered = rendered.replacingOccurrences(of: Token.payloadRegionRange.placeholder, with: input.payloadRegionRange)
        rendered = rendered.replacingOccurrences(of: Token.payloadRegionBitCount.placeholder, with: formatNumeric(input.payloadRegionBitCount))
        rendered = rendered.replacingOccurrences(of: Token.payloadRegionBytesHex.placeholder, with: input.payloadRegionBytesHex)
        return Self.droppingEmptyLines(of: rendered)
    }

    /// Renders one case's comment block (multi-line, unindented and without a
    /// comment prefix — the caller wraps it).
    public func transformCase(_ input: CaseInput) -> String {
        var rendered = caseTemplate
        rendered = rendered.replacingOccurrences(of: CaseToken.caseHeader.placeholder, with: input.headerDescription)
        rendered = rendered.replacingOccurrences(of: CaseToken.caseIndex.placeholder, with: formatNumeric(input.caseIndex))
        rendered = rendered.replacingOccurrences(of: CaseToken.caseHex.placeholder, with: String(format: "0x%02X", input.caseIndex))
        rendered = rendered.replacingOccurrences(of: CaseToken.caseName.placeholder, with: input.caseName)
        rendered = rendered.replacingOccurrences(of: CaseToken.declaredName.placeholder, with: input.declaredName ?? input.caseName)
        rendered = rendered.replacingOccurrences(of: CaseToken.caseType.placeholder, with: input.isPayloadCase ? "payload case" : "empty case")
        rendered = rendered.replacingOccurrences(of: CaseToken.tagValue.placeholder, with: formatNumeric(input.tagValue))
        rendered = rendered.replacingOccurrences(of: CaseToken.tagHex.placeholder, with: String(format: "0x%02X", input.tagValue))
        rendered = rendered.replacingOccurrences(of: CaseToken.tagValueBinary.placeholder, with: "0b\(String(input.tagValue, radix: 2))")
        rendered = rendered.replacingOccurrences(of: CaseToken.payloadValue.placeholder, with: formatNumeric(input.payloadValue))
        rendered = rendered.replacingOccurrences(of: CaseToken.payloadHex.placeholder, with: String(format: "0x%02X", input.payloadValue))
        rendered = rendered.replacingOccurrences(of: CaseToken.payloadValueBinary.placeholder, with: "0b\(String(input.payloadValue, radix: 2))")
        rendered = rendered.replacingOccurrences(of: CaseToken.encoding.placeholder, with: input.encoding)
        rendered = rendered.replacingOccurrences(
            of: CaseToken.encodingLine.placeholder,
            with: input.encoding.isEmpty ? "" : "encoding: \(input.encoding)"
        )
        rendered = rendered.replacingOccurrences(
            of: CaseToken.patternKind.placeholder,
            with: input.isPatternUnresolved ? "unresolvedExtraInhabitant" : "exact"
        )
        rendered = rendered.replacingOccurrences(of: CaseToken.patternNote.placeholder, with: input.patternNote)
        rendered = rendered.replacingOccurrences(
            of: CaseToken.patternNoteLine.placeholder,
            with: input.patternNote.isEmpty ? "" : "note: \(input.patternNote)"
        )
        rendered = rendered.replacingOccurrences(of: CaseToken.fixedBytesSummary.placeholder, with: input.fixedBytesSummary)
        rendered = rendered.replacingOccurrences(of: CaseToken.fixedBytesLine.placeholder, with: input.fixedBytesLine)
        rendered = rendered.replacingOccurrences(of: CaseToken.memoryChangeCount.placeholder, with: formatNumeric(input.memoryChanges.count))
        if rendered.contains(CaseToken.memoryChangesDetail.placeholder) {
            rendered = rendered.replacingOccurrences(
                of: CaseToken.memoryChangesDetail.placeholder,
                with: memoryChangesDetail(for: input)
            )
        }

        var lines = Self.droppingEmptyLines(of: rendered)

        // Historical RuntimeViewer behavior: a case template that opted into
        // none of the byte-information tokens still gets the note and the
        // fixed-byte lines appended, so terse header templates stay complete.
        if appendsOmittedDetails {
            if !input.patternNote.isEmpty,
               !containsCase(.patternNote), !containsCase(.patternNoteLine) {
                lines += "\nnote: \(input.patternNote)"
            }
            if !containsCase(.fixedBytesSummary), !containsCase(.fixedBytesLine), !containsCase(.memoryChangesDetail) {
                lines += "\n" + input.fixedBytesLine
                let detail = memoryChangesDetail(for: input)
                if !detail.isEmpty {
                    lines += "\n" + detail
                }
            }
        }
        return lines
    }

    /// Renders one fixed-byte line body through ``memoryOffsetTemplate``.
    ///
    /// A **partially-fixed** byte (a spare-bits tag sharing the byte with live
    /// payload storage) is only pushed through the template when the template
    /// is mask-aware (references `${fixedBitMask}`,
    /// `${fixedBitMaskBinaryPadded}`, `${fixedBitsPhrase}`, or
    /// `${offsetDescription}`); otherwise the built-in mask-scoped wording is
    /// used, because a whole-byte value would over-claim bits that are not
    /// fixed.
    public func transformMemoryOffset(_ input: MemoryOffsetInput) -> String {
        if input.fixedBitMask != 0xFF, !memoryOffsetTemplateIsMaskAware {
            return Self.builtInOffsetDescription(offset: input.offset, value: input.value, fixedBitMask: input.fixedBitMask)
        }
        var rendered = memoryOffsetTemplate
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.offset.placeholder, with: formatNumeric(input.offset))
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.offsetHex.placeholder, with: String(format: "0x%02X", input.offset))
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.value.placeholder, with: formatNumeric(Int(input.value)))
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.valueHex.placeholder, with: String(format: "0x%02X", input.value))
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.valueBinaryRaw.placeholder, with: String(input.value, radix: 2))
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.valueBinary.placeholder, with: "0b\(String(input.value, radix: 2))")
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.valueBinaryPaddedRaw.placeholder, with: Self.paddedBinary(input.value))
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.valueBinaryPadded.placeholder, with: "0b\(Self.paddedBinary(input.value))")
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.fixedBitMask.placeholder, with: String(format: "0x%02X", input.fixedBitMask))
        rendered = rendered.replacingOccurrences(of: MemoryOffsetToken.fixedBitMaskBinaryPadded.placeholder, with: "0b\(Self.paddedBinary(input.fixedBitMask))")
        rendered = rendered.replacingOccurrences(
            of: MemoryOffsetToken.offsetDescription.placeholder,
            with: Self.builtInOffsetDescription(offset: input.offset, value: input.value, fixedBitMask: input.fixedBitMask)
        )
        rendered = rendered.replacingOccurrences(
            of: MemoryOffsetToken.fixedBitsPhrase.placeholder,
            with: Self.fixedBitsPhrase(value: input.value, fixedBitMask: input.fixedBitMask)
        )
        return rendered
    }

    private var memoryOffsetTemplateIsMaskAware: Bool {
        containsMemoryOffset(.fixedBitMask)
            || containsMemoryOffset(.fixedBitMaskBinaryPadded)
            || containsMemoryOffset(.fixedBitsPhrase)
            || containsMemoryOffset(.offsetDescription)
    }

    /// The per-offset detail lines (four-space indented, newline-joined).
    private func memoryChangesDetail(for input: CaseInput) -> String {
        input.memoryChanges.keys.sorted().map { offset in
            "    " + transformMemoryOffset(
                MemoryOffsetInput(
                    offset: offset,
                    value: input.memoryChanges[offset]!,
                    fixedBitMask: input.fixedBitMask(atByteOffset: offset)
                )
            )
        }
        .joined(separator: "\n")
    }

    private func formatNumeric(_ value: Int) -> String {
        useHexadecimal ? "0x\(String(value, radix: 16, uppercase: true))" : String(value)
    }

    /// Drops lines that ended up empty after substitution, so conditional
    /// line-tokens can be listed unconditionally in a template.
    private static func droppingEmptyLines(of rendered: String) -> String {
        rendered
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    // MARK: Derived wordings

    /// The built-in per-byte line body (shared with the default rendering).
    public static func builtInOffsetDescription(offset: Int, value: UInt8, fixedBitMask: UInt8) -> String {
        if fixedBitMask == 0xFF {
            return "offset \(String(format: "0x%02X", offset)) = \(String(format: "0x%02X", value)) (0b\(paddedBinary(value)))"
        }
        return "offset \(String(format: "0x%02X", offset)): fixed bits 0b\(paddedBinary(fixedBitMask)) = 0b\(paddedBinary(value)) (the other bits hold payload storage)"
    }

    /// A plain-words description of what a fixed byte pins. For a
    /// partially-fixed byte the mask is decomposed into contiguous bit ranges:
    /// `bits 7-4 are always 0100; the other bits (3-0) hold payload data`.
    public static func fixedBitsPhrase(value: UInt8, fixedBitMask: UInt8) -> String {
        if fixedBitMask == 0xFF {
            return "\(String(format: "0x%02X", value)) (0b\(paddedBinary(value)))"
        }
        let fixedGroups = contiguousBitRanges(of: fixedBitMask)
        let payloadGroups = contiguousBitRanges(of: ~fixedBitMask)
        let fixedPhrases = fixedGroups.map { range in
            let bits = (range.lowerBound ... range.upperBound).reversed().map { bitIndex in
                (value >> bitIndex) & 1 == 1 ? "1" : "0"
            }.joined()
            if range.count == 1 {
                return "bit \(range.lowerBound) is always \(bits)"
            }
            return "bits \(range.upperBound)-\(range.lowerBound) are always \(bits)"
        }
        let payloadList = payloadGroups.map { range in
            range.count == 1 ? "\(range.lowerBound)" : "\(range.upperBound)-\(range.lowerBound)"
        }.joined(separator: ", ")
        return fixedPhrases.joined(separator: ", ") + "; the other bits (\(payloadList)) hold payload data"
    }

    /// Decomposes a bit mask into contiguous set-bit ranges, most-significant
    /// first (`0b11110001` → `[7...4, 0...0]`).
    private static func contiguousBitRanges(of mask: UInt8) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        var currentUpperBound: Int?
        for bitIndex in stride(from: 7, through: 0, by: -1) {
            let isSet = (mask >> bitIndex) & 1 == 1
            if isSet {
                if currentUpperBound == nil { currentUpperBound = bitIndex }
            } else if let upperBound = currentUpperBound {
                ranges.append((bitIndex + 1) ... upperBound)
                currentUpperBound = nil
            }
        }
        if let upperBound = currentUpperBound {
            ranges.append(0 ... upperBound)
        }
        return ranges
    }

    static func paddedBinary(_ byteValue: UInt8) -> String {
        let binaryDigits = String(byteValue, radix: 2)
        return String(repeating: "0", count: 8 - binaryDigits.count) + binaryDigits
    }
}

// MARK: - Token (Strategy Header)

extension Transformer.SwiftEnumLayout {
    /// Available tokens for strategy header templates.
    public enum Token: String, CaseIterable, Sendable {
        case strategy
        case summary
        case bitsNeededForTag
        case bitsAvailableForPayload
        case numTags
        case totalCases
        case payloadCaseCount
        case emptyCaseCount
        case leftoverExtraInhabitantCount
        case tagRegionRange
        case tagRegionBitCount
        case tagRegionBytesHex
        case payloadRegionRange
        case payloadRegionBitCount
        case payloadRegionBytesHex

        public var placeholder: String { "${\(rawValue)}" }
        public var displayName: String {
            switch self {
            case .strategy: "Strategy"
            case .summary: "Summary (Library Default)"
            case .bitsNeededForTag: "Bits Needed For Tag"
            case .bitsAvailableForPayload: "Bits Available For Payload"
            case .numTags: "Number of Tags"
            case .totalCases: "Total Cases"
            case .payloadCaseCount: "Payload Case Count"
            case .emptyCaseCount: "Empty Case Count"
            case .leftoverExtraInhabitantCount: "Leftover Extra Inhabitants"
            case .tagRegionRange: "Tag Region Range"
            case .tagRegionBitCount: "Tag Region Bit Count"
            case .tagRegionBytesHex: "Tag Region Bytes (Hex)"
            case .payloadRegionRange: "Payload Region Range"
            case .payloadRegionBitCount: "Payload Region Bit Count"
            case .payloadRegionBytesHex: "Payload Region Bytes (Hex)"
            }
        }
    }
}

// MARK: - Case Token

extension Transformer.SwiftEnumLayout {
    /// Available tokens for per-case templates.
    public enum CaseToken: String, CaseIterable, Sendable {
        /// The full built-in header:
        /// ``Case 1 (0x01) `caseName` — empty case #0`` (the backtick segment
        /// is omitted when no source-level case name is known).
        case caseHeader
        case caseIndex
        case caseHex
        case caseName
        case declaredName
        /// "payload case" or "empty case".
        case caseType
        case tagValue
        case tagHex
        case tagValueBinary
        case payloadValue
        case payloadHex
        case payloadValueBinary
        case encoding
        /// `encoding: …` when an encoding sentence exists, empty otherwise.
        case encodingLine
        /// "exact" or "unresolvedExtraInhabitant".
        case patternKind
        case patternNote
        /// `note: …` when a pattern note exists, empty otherwise.
        case patternNoteLine
        case fixedBytesSummary
        /// `fixed bytes: …` — always meaningful (falls back to the built-in
        /// "none …" wordings when the case fixes no bytes).
        case fixedBytesLine
        case memoryChangeCount
        /// One line per fixed byte, rendered through the memory-offset
        /// template and indented by four spaces; empty when none.
        case memoryChangesDetail

        public var placeholder: String { "${\(rawValue)}" }
        public var displayName: String {
            switch self {
            case .caseHeader: "Case Header (Library Default)"
            case .caseIndex: "Case Index"
            case .caseHex: "Case Hex"
            case .caseName: "Case Name (Structural)"
            case .declaredName: "Case Name (Declared)"
            case .caseType: "Case Type"
            case .tagValue: "Tag Value"
            case .tagHex: "Tag Hex"
            case .tagValueBinary: "Tag Value (Binary)"
            case .payloadValue: "Payload Value"
            case .payloadHex: "Payload Hex"
            case .payloadValueBinary: "Payload Value (Binary)"
            case .encoding: "Encoding Explanation"
            case .encodingLine: "Encoding Line (Conditional)"
            case .patternKind: "Pattern Kind"
            case .patternNote: "Pattern Note"
            case .patternNoteLine: "Pattern Note Line (Conditional)"
            case .fixedBytesSummary: "Fixed Bytes Summary"
            case .fixedBytesLine: "Fixed Bytes Line"
            case .memoryChangeCount: "Memory Change Count"
            case .memoryChangesDetail: "Memory Changes Detail"
            }
        }
    }
}

// MARK: - Memory Offset Token

extension Transformer.SwiftEnumLayout {
    /// Available tokens for per-memory-offset templates.
    public enum MemoryOffsetToken: String, CaseIterable, Sendable {
        case offset
        case offsetHex
        case value
        case valueHex
        case valueBinaryRaw
        case valueBinary
        case valueBinaryPaddedRaw
        case valueBinaryPadded
        case fixedBitMask
        case fixedBitMaskBinaryPadded
        /// The built-in per-byte line body: `offset 0x08 = 0x01 (0b00000001)`
        /// for a fully-fixed byte, `offset 0x00: fixed bits 0b… = 0b… (the
        /// other bits hold payload storage)` for a partially-fixed one.
        case offsetDescription
        /// A plain-words description of what the byte pins: `0x01
        /// (0b00000001)` for a fully-fixed byte; bit ranges for a
        /// partially-fixed one — `bits 7-4 are always 0100; the other bits
        /// (3-0) hold payload data`.
        case fixedBitsPhrase

        public var placeholder: String { "${\(rawValue)}" }
        public var displayName: String {
            switch self {
            case .offset: "Offset"
            case .offsetHex: "Offset (Hex)"
            case .value: "Value"
            case .valueHex: "Value (Hex)"
            case .valueBinaryRaw: "Value (Binary Raw)"
            case .valueBinary: "Value (Binary)"
            case .valueBinaryPaddedRaw: "Value (Binary Padded Raw)"
            case .valueBinaryPadded: "Value (Binary Padded)"
            case .fixedBitMask: "Fixed Bit Mask"
            case .fixedBitMaskBinaryPadded: "Fixed Bit Mask (Binary Padded)"
            case .offsetDescription: "Offset Description (Library Default)"
            case .fixedBitsPhrase: "Fixed Bits Phrase (Plain Words)"
            }
        }
    }
}

// MARK: - Templates (Strategy Header)

extension Transformer.SwiftEnumLayout {
    public enum Templates {
        /// The library's rich one-line summary (strategy + case counts +
        /// tag values/bits + regions + leftover extra inhabitants) — matches
        /// what the library renders by default.
        public static let libraryDefault = "${summary}"

        /// Standard style: "Multi-Payload (Spare Bits) (Tags: 3, Tag Bits: 2)"
        public static let standard = "${strategy} (Tags: ${numTags}, Tag Bits: ${bitsNeededForTag})"

        /// Verbose style: adds payload bits.
        public static let verbose = "${strategy} (Tags: ${numTags}, Tag Bits: ${bitsNeededForTag}, Payload Bits: ${bitsAvailableForPayload})"

        /// Strategy only: "Multi-Payload (Spare Bits)"
        public static let strategyOnly = "${strategy}"

        /// Compact style: "Tags: 3, Bits: 2"
        public static let compact = "Tags: ${numTags}, Bits: ${bitsNeededForTag}"

        /// Technical style with tag/payload/case counts.
        public static let technical = "${strategy}\nTags: ${numTags} (${bitsNeededForTag}-bit), Payload: ${bitsAvailableForPayload}-bit, Cases: ${totalCases}"

        /// Region detail style showing tag and payload memory regions.
        public static let regions = "${strategy}\nTag Region: ${tagRegionRange} (${tagRegionBitCount} bits)\nPayload Region: ${payloadRegionRange} (${payloadRegionBitCount} bits)"

        /// Summary style: strategy with case and tag counts.
        public static let summary = "${strategy} — ${totalCases} cases, ${numTags} tags"

        /// Bits-focused style showing bit allocation.
        public static let bits = "Tag: ${bitsNeededForTag} bits, Payload: ${bitsAvailableForPayload} bits (${numTags} tags)"

        /// Case breakdown style showing payload vs empty case counts.
        public static let caseBreakdown = "${strategy} — ${payloadCaseCount} payload + ${emptyCaseCount} empty = ${totalCases} cases"

        /// Full detail style with regions and byte patterns.
        public static let fullDetail = "${strategy}\nTags: ${numTags} (${bitsNeededForTag}-bit), Payload: ${bitsAvailableForPayload}-bit\nTag Region: ${tagRegionRange} (${tagRegionBitCount} bits) [${tagRegionBytesHex}]\nPayload Region: ${payloadRegionRange} (${payloadRegionBitCount} bits) [${payloadRegionBytesHex}]\nCases: ${payloadCaseCount} payload + ${emptyCaseCount} empty"

        public static let all: [(name: String, template: String)] = [
            ("Library Default", libraryDefault),
            ("Standard", standard),
            ("Verbose", verbose),
            ("Strategy Only", strategyOnly),
            ("Compact", compact),
            ("Technical", technical),
            ("Regions", regions),
            ("Summary", summary),
            ("Bits", bits),
            ("Case Breakdown", caseBreakdown),
            ("Full Detail", fullDetail),
        ]
    }
}

// MARK: - Case Templates

extension Transformer.SwiftEnumLayout {
    public enum CaseTemplates {
        /// The library default: header + conditional encoding/note lines +
        /// fixed-byte summary + per-byte detail lines. Reproduces the built-in
        /// rendering exactly.
        public static let standard = """
        ${caseHeader}
        ${encodingLine}
        ${patternNoteLine}
        ${fixedBytesLine}
        ${memoryChangesDetail}
        """

        /// Header + encoding + note + one-line summary; no per-byte detail.
        public static let summaryOnly = """
        ${caseHeader}
        ${encodingLine}
        ${patternNoteLine}
        ${fixedBytesLine}
        """

        /// One line per case: "[0x01] `caseName` — payload case, tag 1"
        public static let compactLine = "[${caseHex}] `${declaredName}` — ${caseType}, tag ${tagValue}"

        /// The pre-0.13 style: "Case 0 (0x00) - payload case:\nTag: 0"
        public static let classic = "Case ${caseIndex} (${caseHex}) - ${caseName}:\nTag: ${tagValue}"

        /// Verbose style includes payload value.
        public static let verbose = "Case ${caseIndex} (${caseHex}) - ${caseName}:\nTag: ${tagValue}, PayloadValue: ${payloadValue}"

        /// Index only: "Case 0: Tag 0"
        public static let indexOnly = "Case ${caseIndex}: Tag ${tagValue}"

        /// Hex-all style with tag and payload hex values.
        public static let hexAll = "Case ${caseHex}: ${caseName} [tag=${tagHex}, payload=${payloadHex}]"

        /// Named style with case type and tag.
        public static let named = "${caseName} (${caseType}, tag: ${tagValue})"

        /// Memory-focused style showing byte change count.
        public static let memory = "[${caseHex}] ${caseName} — ${memoryChangeCount} byte(s) changed"

        /// Binary style showing tag and payload in binary representation.
        public static let binary = "Case ${caseIndex}: ${caseName}\nTag: ${tagValueBinary} (${tagHex}), Payload: ${payloadValueBinary} (${payloadHex})"

        /// Encoding-focused style with the fixed-byte summary inline.
        public static let encodingDetail = "Case ${caseIndex} (${caseHex}) `${declaredName}` — ${caseName}\nencoding: ${encoding}\nfixed bytes: ${fixedBytesSummary}"

        public static let all: [(name: String, template: String)] = [
            ("Standard", standard),
            ("Summary Only", summaryOnly),
            ("Compact Line", compactLine),
            ("Classic", classic),
            ("Verbose", verbose),
            ("Index Only", indexOnly),
            ("Hex All", hexAll),
            ("Named", named),
            ("Memory", memory),
            ("Binary", binary),
            ("Encoding Detail", encodingDetail),
        ]
    }
}

// MARK: - Memory Offset Templates

extension Transformer.SwiftEnumLayout {
    public enum MemoryOffsetTemplates {
        /// The library default: `offset 0x08 = 0x01 (0b00000001)`, with the
        /// mask-scoped form for partially-fixed bytes.
        public static let libraryDefault = "${offsetDescription}"

        /// Plain-words style: `offset 0x07: bits 7-4 are always 0100; the
        /// other bits (3-0) hold payload data`.
        public static let explained = "offset ${offsetHex}: ${fixedBitsPhrase}"

        /// Standard style: "Memory Offset 0 (0x00) = 0x01 (Bin: 00000001)"
        public static let standard = "Memory Offset ${offset} (${offsetHex}) = ${valueHex} (Bin: ${valueBinaryPaddedRaw})"

        /// Compact style: "[0]=0x01"
        public static let compact = "[${offset}]=${valueHex}"

        /// Hex only style: "0x00: 0x01"
        public static let hexOnly = "${offsetHex}: ${valueHex}"

        /// Binary style: "Offset 0: 0b00000001"
        public static let binary = "Offset ${offset}: ${valueBinaryPadded}"

        /// Verbose style: "Offset 0 (0x00) = 1 (0x01, 0b00000001)"
        public static let verbose = "Offset ${offset} (${offsetHex}) = ${value} (${valueHex}, ${valueBinaryPadded})"

        /// Minimal style: "0: 0x01"
        public static let minimal = "${offset}: ${valueHex}"

        public static let all: [(name: String, template: String)] = [
            ("Library Default", libraryDefault),
            ("Explained", explained),
            ("Standard", standard),
            ("Compact", compact),
            ("Hex Only", hexOnly),
            ("Binary", binary),
            ("Verbose", verbose),
            ("Minimal", minimal),
        ]
    }
}
