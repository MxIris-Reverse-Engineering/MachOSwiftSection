import Foundation

public enum EnumLayoutCalculator {
    // MARK: - ABI: Tag Count Calculation (swift/ABI/Enum.h: getEnumTagCounts)

    /// Mirrors `swift::EnumTagCounts` from swift/ABI/Enum.h.
    public struct EnumTagCounts: Sendable {
        public let numTags: Int
        public let numTagBytes: Int
    }

    /// Compute the number of tags and tag bytes needed for an enum layout.
    ///
    /// Mirrors `swift::getEnumTagCounts(size_t size, unsigned emptyCases, unsigned payloadCases)`
    /// from swift/ABI/Enum.h.
    ///
    /// - Parameters:
    ///   - payloadSize: The size of the payload area in bytes (the `size` parameter in the C++ version).
    ///   - emptyCases: The number of empty (no-payload) cases.
    ///   - payloadCases: The number of payload cases.
    /// - Returns: The number of tag values and tag bytes needed.
    public static func getEnumTagCounts(
        payloadSize: Int,
        emptyCases: Int,
        payloadCases: Int
    ) -> EnumTagCounts {
        // We can use the payload area with a tag bit set somewhere outside of the
        // payload area to represent cases. See how many bytes we need to cover
        // all the empty cases.
        var numTags = payloadCases
        if emptyCases > 0 {
            if payloadSize >= 4 {
                // Assume that one tag bit is enough if the precise calculation overflows
                // an int32.
                numTags += 1
            } else {
                let bits = payloadSize * 8
                let casesPerTagBitValue = 1 << bits
                numTags += (emptyCases + (casesPerTagBitValue - 1)) >> bits
            }
        }
        let numTagBytes: Int
        if numTags <= 1 { numTagBytes = 0 }
        else if numTags < 256 { numTagBytes = 1 }
        else if numTags < 65536 { numTagBytes = 2 }
        else { numTagBytes = 4 }
        return EnumTagCounts(numTags: numTags, numTagBytes: numTagBytes)
    }

    /// `ValueWitnessFlags::MaxNumExtraInhabitants` (MetadataValues.h): the cap
    /// every extra-inhabitant count saturates to.
    public static let maximumExtraInhabitantCount = 0x7FFF_FFFF

    // MARK: - Result Structures

    public struct SpareRegion: CustomStringConvertible, Sendable {
        public let range: Range<Int>
        public let bitCount: Int
        public let bytes: [UInt8]
        public var description: String { return "Offset \(range) (Used: \(bitCount) bits)" }
    }

    public struct EnumCaseProjection: CustomStringConvertible, Sendable {
        /// How ``memoryChanges`` should be read.
        public enum PatternResolution: Sendable, Equatable {
            /// ``memoryChanges`` is the case's authoritative fixed byte
            /// pattern. It may legitimately be empty: a single-payload
            /// enum's payload case writes no bytes of its own — any pattern
            /// no empty case claims selects it.
            case exactBytes
            /// The case is stored as the payload's extra-inhabitant pattern
            /// number `extraInhabitantIndex` — an invalid payload bit pattern
            /// whose concrete bytes depend on the payload type (e.g. a class
            /// reference's extra inhabitants are the small invalid addresses
            /// `0x0, 0x1, 0x2, …`) and were not resolved here. Resolving them
            /// requires the payload's extra-inhabitant semantics, which the
            /// runtime path supplies via `RuntimeEnumCaseProjector`.
            /// ``memoryChanges`` carries only what is known without them
            /// (the zeroed extra tag bytes, if the layout has any).
            case unresolvedExtraInhabitant(extraInhabitantIndex: Int)
        }

        /// The case's tag index: payload cases first, then empty cases — the
        /// numbering the enum's field records and the runtime's `getEnumTag`
        /// use.
        public let caseIndex: Int
        /// A structural label ("payload case", "empty case #1", …); prefer
        /// ``declaredName`` for display when present.
        public let caseName: String
        /// The source-level case name from the enum's field records, when the
        /// caller attached it (``LayoutResult/attachingDeclaredCaseNames(_:)``).
        public let declaredName: String?
        public let isPayloadCase: Bool
        public let tagValue: Int
        public let payloadValue: Int
        /// Fixed bytes identifying this case, keyed by byte offset. Interpret
        /// via ``patternResolution``.
        public let memoryChanges: [Int: UInt8]
        public let patternResolution: PatternResolution
        /// A human-readable sentence describing *how* this case is encoded
        /// (which mechanism, with the concrete tag / index values woven in).
        /// Composed by the strategy that built the projection, since only it
        /// knows the full context (spare bits vs extra tag bytes vs extra
        /// inhabitants, payload extent, …).
        public let encodingExplanation: String

        public init(
            caseIndex: Int,
            caseName: String,
            declaredName: String? = nil,
            isPayloadCase: Bool,
            tagValue: Int,
            payloadValue: Int,
            memoryChanges: [Int: UInt8],
            patternResolution: PatternResolution = .exactBytes,
            encodingExplanation: String = ""
        ) {
            self.caseIndex = caseIndex
            self.caseName = caseName
            self.declaredName = declaredName
            self.isPayloadCase = isPayloadCase
            self.tagValue = tagValue
            self.payloadValue = payloadValue
            self.memoryChanges = memoryChanges
            self.patternResolution = patternResolution
            self.encodingExplanation = encodingExplanation
        }

        public var description: String {
            description(indent: .zero)
        }

        /// The detailed default rendering — deliberately information-rich,
        /// since consumers with narrower needs can supply an
        /// `enumLayoutCaseTransformer` and pick the fields they want:
        ///
        /// ```
        /// Case 1 (0x01) `implicit` — empty case #0
        ///   encoding: stored as the payload's extra-inhabitant pattern #0 (an invalid payload bit pattern)
        ///   fixed bytes: bytes[0x8..<0x10] = 0x1
        ///     offset 0x08 = 0x01 (0b00000001)
        ///     offset 0x09 = 0x00 (0b00000000)
        ///     …
        /// ```
        public func description(indent: Int, prefix: String = "") -> String {
            let indentString = String(repeating: "    ", count: indent)
            var lines: [String] = []

            var header = "Case \(caseIndex) (\(String(format: "0x%02X", caseIndex)))"
            if let declaredName {
                header += " `\(declaredName)`"
            }
            header += " — \(caseName)"
            lines.append(header)

            if !encodingExplanation.isEmpty {
                lines.append("encoding: \(encodingExplanation)")
            }
            if case .unresolvedExtraInhabitant = patternResolution {
                lines.append("note: the exact bytes depend on the payload type's extra-inhabitant scheme and were not resolved offline (the in-process runtime path resolves them)")
            }

            if memoryChanges.isEmpty {
                if case .unresolvedExtraInhabitant = patternResolution {
                    lines.append("fixed bytes: not computed")
                } else if isPayloadCase {
                    lines.append("fixed bytes: none — any pattern no empty case claims selects this case")
                } else {
                    lines.append("fixed bytes: none recorded")
                }
            } else {
                lines.append("fixed bytes: \(formattedFixedBytes())")
                for offset in memoryChanges.keys.sorted() {
                    let byteValue = memoryChanges[offset]!
                    let binaryDigits = String(byteValue, radix: 2)
                    let paddedBinaryDigits = String(repeating: "0", count: 8 - binaryDigits.count) + binaryDigits
                    lines.append("    offset 0x\(String(format: "%02X", offset)) = 0x\(String(format: "%02X", byteValue)) (0b\(paddedBinaryDigits))")
                }
            }

            var output = ""
            for (lineIndex, line) in lines.enumerated() {
                let continuationIndent = lineIndex == 0 ? "" : "  "
                output += "\(indentString)\(prefix) \(continuationIndent)\(line)\n"
            }
            return output
        }

        /// The fixed bytes compressed into contiguous runs, little-endian:
        /// `bytes[0x8..<0x10] = 0x1` for a multi-byte run, and
        /// `byte[0x2] = 0x40 (0b01000000)` for a single byte (the binary form
        /// helps read sub-byte spare-bit tags).
        public func formattedFixedBytes() -> String {
            byteRuns().map { run in
                if run.bytes.count == 1 {
                    let byteValue = run.bytes[0]
                    let binaryDigits = String(byteValue, radix: 2)
                    let paddedBinaryDigits = String(repeating: "0", count: 8 - binaryDigits.count) + binaryDigits
                    return "byte[0x\(String(run.startOffset, radix: 16))] = 0x\(String(byteValue, radix: 16, uppercase: true)) (0b\(paddedBinaryDigits))"
                } else {
                    var runValue: UInt64 = 0
                    for byteValue in run.bytes.reversed() {
                        runValue = runValue << 8 | UInt64(byteValue)
                    }
                    let endOffset = run.startOffset + run.bytes.count
                    return "bytes[0x\(String(run.startOffset, radix: 16))..<0x\(String(endOffset, radix: 16))] = 0x\(String(runValue, radix: 16, uppercase: true))"
                }
            }
            .joined(separator: ", ")
        }

        /// Splits ``memoryChanges`` into runs of consecutive offsets, capped at
        /// 8 bytes per run so each renders as one little-endian value.
        private func byteRuns() -> [(startOffset: Int, bytes: [UInt8])] {
            var runs: [(startOffset: Int, bytes: [UInt8])] = []
            for offset in memoryChanges.keys.sorted() {
                let byteValue = memoryChanges[offset]!
                if var lastRun = runs.last,
                   lastRun.startOffset + lastRun.bytes.count == offset,
                   lastRun.bytes.count < 8 {
                    lastRun.bytes.append(byteValue)
                    runs[runs.count - 1] = lastRun
                } else {
                    runs.append((startOffset: offset, bytes: [byteValue]))
                }
            }
            return runs
        }

        /// Replaces this projection's byte pattern with an exactly-resolved one
        /// (from `RuntimeEnumCaseProjector`).
        public func withExactPattern(_ fixedBytes: [Int: UInt8]) -> EnumCaseProjection {
            EnumCaseProjection(
                caseIndex: caseIndex,
                caseName: caseName,
                declaredName: declaredName,
                isPayloadCase: isPayloadCase,
                tagValue: tagValue,
                payloadValue: payloadValue,
                memoryChanges: fixedBytes,
                patternResolution: .exactBytes,
                encodingExplanation: encodingExplanation
            )
        }

        /// Attaches the source-level case name.
        public func withDeclaredName(_ name: String) -> EnumCaseProjection {
            EnumCaseProjection(
                caseIndex: caseIndex,
                caseName: caseName,
                declaredName: name,
                isPayloadCase: isPayloadCase,
                tagValue: tagValue,
                payloadValue: payloadValue,
                memoryChanges: memoryChanges,
                patternResolution: patternResolution,
                encodingExplanation: encodingExplanation
            )
        }
    }

    public struct LayoutResult: CustomStringConvertible, Sendable {
        public let strategyDescription: String
        public let bitsNeededForTag: Int
        public let bitsAvailableForPayload: Int
        public let numTags: Int
        /// The enum's own extra inhabitants — tag values the layout can
        /// represent but no case uses, available to an outer enum. Exact per
        /// strategy: unused tag-bit values (spare-bits/hybrid, GenEnum.cpp
        /// `getFixedExtraInhabitantCount`), unused extra-tag-byte values
        /// (tagged, Enum.cpp `swift_initEnumMetadataMultiPayload`), or the
        /// payload's leftover inhabitants (single-payload). Capped at
        /// `maximumExtraInhabitantCount`.
        public let extraInhabitantCount: Int
        public let tagRegion: SpareRegion?
        public let payloadRegion: SpareRegion?
        public let cases: [EnumCaseProjection]

        /// A rich one-line summary for the default type-level comment:
        /// strategy, case counts, tag counts / bits, tag and occupied-bit
        /// regions when present, and the leftover extra inhabitants an outer
        /// enum could still use. Deliberately detailed — consumers wanting a
        /// terser line can supply an `enumLayoutTransformer` and pick fields
        /// (`strategyDescription`, `numTags`, `bitsNeededForTag`, …) directly.
        public var summaryDescription: String {
            let payloadCaseCount = cases.count { $0.isPayloadCase }
            let emptyCaseCount = cases.count - payloadCaseCount
            var parts: [String] = []
            parts.append("cases: \(cases.count) (\(payloadCaseCount) payload + \(emptyCaseCount) empty)")
            parts.append("tag values used: \(numTags)")
            if bitsNeededForTag > 0 {
                parts.append("tag bits: \(bitsNeededForTag)")
            }
            if let tagRegion {
                parts.append("tag region: offsets \(tagRegion.range) (\(tagRegion.bitCount) bits)")
            }
            if let payloadRegion {
                parts.append("occupied-bits region: offsets \(payloadRegion.range) (\(payloadRegion.bitCount) bits)")
            }
            parts.append("leftover extra inhabitants for an outer enum: \(extraInhabitantCount)")
            return "\(strategyDescription) — " + parts.joined(separator: "; ")
        }

        public var description: String {
            var output = "=== Enum Layout Result (\(strategyDescription)) ===\n"
            output += "Tag Bits: \(bitsNeededForTag), Payload Bits: \(bitsAvailableForPayload)\n"
            output += "Total Tags Used: \(numTags)\n"
            if let tagRegion { output += "Tag Region: \(tagRegion)\n" }
            if let payloadRegion { output += "Payload Value Region (Occupied Bits): \(payloadRegion)\n" }
            output += "--------------------------\n"
            cases.forEach { output += $0.description }
            output += "=========================="
            return output
        }

        /// Attaches the source-level case names read from the enum's field
        /// records. `declaredNames` is indexed by tag order — payload cases
        /// first, then empty cases — which is exactly the order field records
        /// store enum cases in.
        public func attachingDeclaredCaseNames(_ declaredNames: [String]) -> LayoutResult {
            replacingCases(cases.map { caseProjection in
                guard caseProjection.caseIndex >= 0, caseProjection.caseIndex < declaredNames.count else { return caseProjection }
                return caseProjection.withDeclaredName(declaredNames[caseProjection.caseIndex])
            })
        }

        /// Replaces formula-derived case patterns with exactly-resolved ones
        /// (from `RuntimeEnumCaseProjector`), keyed by tag-order case index.
        /// Cases without an entry keep their formula-derived pattern.
        public func applyingExactCasePatterns(_ fixedBytesByCaseIndex: [Int: [Int: UInt8]]) -> LayoutResult {
            replacingCases(cases.map { caseProjection in
                guard let fixedBytes = fixedBytesByCaseIndex[caseProjection.caseIndex] else { return caseProjection }
                return caseProjection.withExactPattern(fixedBytes)
            })
        }

        private func replacingCases(_ newCases: [EnumCaseProjection]) -> LayoutResult {
            LayoutResult(
                strategyDescription: strategyDescription,
                bitsNeededForTag: bitsNeededForTag,
                bitsAvailableForPayload: bitsAvailableForPayload,
                numTags: numTags,
                extraInhabitantCount: extraInhabitantCount,
                tagRegion: tagRegion,
                payloadRegion: payloadRegion,
                cases: newCases
            )
        }
    }

    // MARK: - Strategy 1: Multi-Payload (Spare Bits)
    //
    // Corresponds to `MultiPayloadEnumImplStrategy` in GenEnum.cpp.
    // Uses spare bits common to all payloads to encode the tag in the payload area.
    // If there aren't enough spare bits, extra tag bytes are appended.
    //
    // References:
    //   - GenEnum.cpp: MultiPayloadEnumImplStrategy::completeFixedLayout
    //   - GenEnum.cpp: MultiPayloadEnumImplStrategy::emitGetEnumTag
    //   - GenEnum.cpp: MultiPayloadEnumImplStrategy::getEmptyCasePayload
    //   - TypeLowering.cpp: MultiPayloadEnumTypeInfo::projectEnumValue
    //   - TypeLowering.cpp: MultiPayloadEnumTypeInfo::getMultiPayloadTagBitsMask

    public static func calculateMultiPayload(
        payloadSize: Int,
        spareBytes: [UInt8],
        spareBytesOffset: Int,
        numPayloadCases: Int,
        numEmptyCases: Int
    ) -> LayoutResult {
        // Build the CommonSpareBits mask from provided spare bytes.
        // GenEnum.cpp: completeFixedLayout accumulates CommonSpareBits from all payloads.
        var commonSpareBits = BitMask(sizeInBytes: payloadSize)
        commonSpareBits.makeZero()

        if spareBytesOffset < payloadSize {
            let copyLength = min(spareBytes.count, payloadSize - spareBytesOffset)
            for i in 0 ..< copyLength {
                commonSpareBits[byteAt: spareBytesOffset + i] = spareBytes[i]
            }
        }

        let commonSpareBitCount = commonSpareBits.countSetBits()
        // "Occupied bits" = non-spare bits = total bits - spare bits
        // GenEnum.cpp:7203: usedBitCount = CommonSpareBits.size() - commonSpareBitCount
        let usedBitCount = commonSpareBits.size * 8 - commonSpareBitCount

        // Determine how many tags we need for the empty cases.
        // GenEnum.cpp:7227-7238
        var numEmptyElementTags = 0
        if numEmptyCases > 0 {
            if usedBitCount >= 32 {
                // With >= 32 occupied bits, we can encode all empty cases in a single tag.
                numEmptyElementTags = 1
            } else {
                let emptyElementsPerTag = 1 << usedBitCount
                numEmptyElementTags = (numEmptyCases + emptyElementsPerTag - 1) / emptyElementsPerTag
            }
        }

        // GenEnum.cpp:7242: numTags = numPayloadTags + NumEmptyElementTags
        let numTags = numPayloadCases + numEmptyElementTags

        // GenEnum.cpp:7243: numTagBits = llvm::Log2_32(numTags-1) + 1
        let numTagBits = bitsRequired(toRepresent: numTags)

        // GenEnum.cpp:7247-7316: Determine PayloadTagBits and ExtraTagBitCount.
        // If there are enough spare bits, select from the most significant.
        // Otherwise, use ALL spare bits as tag bits plus extra tag bytes.
        var payloadTagBitsMask: BitMask
        let extraTagBitCount: Int

        if numTagBits <= commonSpareBitCount {
            // Enough spare bits: select from the most significant.
            // GenEnum.cpp:7292-7308
            payloadTagBitsMask = commonSpareBits
            payloadTagBitsMask.keepOnlyMostSignificantBits(numTagBits)
            extraTagBitCount = 0
        } else {
            // Not enough spare bits: use ALL spare bits + extra tag bytes.
            // GenEnum.cpp:7248-7260: PayloadTagBits = CommonSpareBits
            payloadTagBitsMask = commonSpareBits
            payloadTagBitsMask.keepOnlyLeastSignificantBytes(payloadSize)
            extraTagBitCount = numTagBits - commonSpareBitCount
        }

        let numPayloadTagBits = payloadTagBitsMask.countSetBits()
        let extraTagByteCount = (extraTagBitCount + 7) / 8

        // Occupied bits mask = complement of spare bits.
        // GenEnum.cpp:4084: scatterBits(~CommonSpareBits.asAPInt(), tagIndex)
        var payloadValueBitsMask = commonSpareBits
        payloadValueBitsMask.invert()
        let numPayloadValueBits = payloadValueBitsMask.countSetBits()

        // Build a display mask for meaningful payload bits (only for visualization).
        let bitsRequiredForEmptyCases = max(bitsRequired(toRepresent: numEmptyCases), 1)
        var meaningfulPayloadMask = BitMask(sizeInBytes: payloadSize)
        meaningfulPayloadMask.makeZero()

        var currentMeaningfulBits = 0
        for i in 0 ..< payloadSize {
            let byte = payloadValueBitsMask[byteAt: i]
            if byte == 0 { continue }
            var newByte: UInt8 = 0
            for b in 0 ..< 8 {
                if (byte & (1 << b)) != 0 {
                    if currentMeaningfulBits < bitsRequiredForEmptyCases {
                        newByte |= (1 << b)
                        currentMeaningfulBits += 1
                    }
                }
            }
            meaningfulPayloadMask[byteAt: i] = newByte
        }

        var cases: [EnumCaseProjection] = []

        // A. Payload Cases: tag = caseIndex
        // GenEnum.cpp: storePayloadTag scatters lower bits into PayloadTagBits,
        // upper bits go into extra tag bytes.
        for i in 0 ..< numPayloadCases {
            let tagValue = i
            let spareTagValue = (numPayloadTagBits >= 64) ? tagValue : tagValue & ((1 << numPayloadTagBits) - 1)
            let scatteredTagBytes = payloadTagBitsMask.scatterBits(value: spareTagValue)

            var memoryChanges = extractChanges(from: scatteredTagBytes, showMask: payloadTagBitsMask)

            // Write extra tag bytes (upper bits of tag after payload area)
            if extraTagByteCount > 0 {
                var extraTagValue = tagValue >> numPayloadTagBits
                for byteIndex in 0 ..< extraTagByteCount {
                    memoryChanges[payloadSize + byteIndex] = UInt8(extraTagValue & 0xFF)
                    extraTagValue >>= 8
                }
            }

            var payloadCaseExplanation = "tag \(tagValue) scattered into the payloads' common spare bits; the occupied (non-spare) bits hold this payload's value"
            if extraTagByteCount > 0 {
                payloadCaseExplanation += "; upper tag bits in the extra tag byte(s) after the payload area"
            }
            let `case` = EnumCaseProjection(
                caseIndex: i,
                caseName: "payload case #\(i)",
                isPayloadCase: true,
                tagValue: tagValue,
                payloadValue: 0,
                memoryChanges: memoryChanges,
                encodingExplanation: payloadCaseExplanation
            )
            cases.append(`case`)
        }

        // B. Empty Cases: tag scattered into PayloadTagBits, index into occupied bits.
        // GenEnum.cpp:4083-4084: getEmptyCasePayload
        //   v = scatterBits(PayloadTagBits.asAPInt(), tag);
        //   v |= scatterBits(~CommonSpareBits.asAPInt(), tagIndex);
        //
        // TypeLowering.cpp: MultiPayloadEnumTypeInfo::projectEnumValue (lines 1086-1100)
        //   occupiedBitCount >= 32: case = payloadValue + numPayloadCases
        //   else: case = ((tagValue - numPayloadCases) << occupiedBitCount | payloadValue) + numPayloadCases
        if numEmptyCases > 0 {
            for i in 0 ..< numEmptyCases {
                let globalIndex = numPayloadCases + i
                let emptyIndex = i

                // TypeLowering.cpp:1101-1104: When occupied bits >= 32, all empty
                // cases share a single tag value and the payload value alone
                // distinguishes them. This also avoids shift overflow when
                // numPayloadValueBits >= 63 (signed Int overflow or >= 64 trap).
                let payloadValue: Int
                let finalTag: Int
                if numPayloadValueBits >= 32 {
                    payloadValue = emptyIndex
                    finalTag = numPayloadCases
                } else {
                    let payloadValueMask = (1 << numPayloadValueBits) - 1
                    payloadValue = emptyIndex & payloadValueMask
                    let tagOffset = emptyIndex >> numPayloadValueBits
                    finalTag = numPayloadCases + tagOffset
                }

                // Scatter lower bits of tag into spare bits, tagIndex into occupied bits.
                let spareTagValue = (numPayloadTagBits >= 64) ? finalTag : finalTag & ((1 << numPayloadTagBits) - 1)
                let scatteredTagBytes = payloadTagBitsMask.scatterBits(value: spareTagValue)
                let scatteredPayloadBytes = payloadValueBitsMask.scatterBits(value: payloadValue)

                var combinedBytes = [UInt8](repeating: 0, count: payloadSize)
                for byteIndex in 0 ..< payloadSize {
                    combinedBytes[byteIndex] = scatteredTagBytes[byteIndex] | scatteredPayloadBytes[byteIndex]
                }

                var memoryChanges = extractChangesForEmptyCase(
                    data: combinedBytes,
                    tagMask: payloadTagBitsMask,
                    meaningfulPayloadMask: meaningfulPayloadMask
                )

                // Write extra tag bytes (upper bits of tag after payload area)
                if extraTagByteCount > 0 {
                    var extraTagValue = finalTag >> numPayloadTagBits
                    for byteIndex in 0 ..< extraTagByteCount {
                        memoryChanges[payloadSize + byteIndex] = UInt8(extraTagValue & 0xFF)
                        extraTagValue >>= 8
                    }
                }

                var emptyCaseExplanation = "tag \(finalTag) in the common spare bits + empty-case value \(payloadValue) in the occupied (non-spare) bits"
                if extraTagByteCount > 0 {
                    emptyCaseExplanation += "; upper tag bits in the extra tag byte(s) after the payload area"
                }
                let `case` = EnumCaseProjection(
                    caseIndex: globalIndex,
                    caseName: "empty case #\(i)",
                    isPayloadCase: false,
                    tagValue: finalTag,
                    payloadValue: payloadValue,
                    memoryChanges: memoryChanges,
                    encodingExplanation: emptyCaseExplanation
                )

                cases.append(`case`)
            }
        }

        let strategyDescription: String
        let tagRegion: SpareRegion?

        if extraTagByteCount > 0 {
            // Hybrid: spare bits in payload + extra tag bytes after payload.
            strategyDescription = "Multi-Payload (tag in payload spare bits: \(numPayloadTagBits) + extra tag bits: \(extraTagBitCount))"
            // Show the extra tag byte region (spare bits are visible in memoryChanges).
            tagRegion = SpareRegion(
                range: payloadSize ..< (payloadSize + extraTagByteCount),
                bitCount: extraTagBitCount,
                bytes: [UInt8](repeating: 0xFF, count: extraTagByteCount)
            )
        } else {
            strategyDescription = "Multi-Payload (tag in payload spare bits)"
            tagRegion = calculateRegion(from: payloadTagBitsMask, bitCount: numTagBits)
        }

        // The extra inhabitants are the unused tag values. The tag can address
        // every common spare bit plus the extra tag bits rounded up to whole
        // bytes — GenEnum.cpp: MultiPayloadEnumImplStrategy::
        // getFixedExtraInhabitantCount / getExtraTagBitCountForExtraInhabitants.
        let totalTagBits = commonSpareBitCount + extraTagByteCount * 8
        let extraInhabitantCount = totalTagBits >= 32
            ? maximumExtraInhabitantCount
            : min((1 << totalTagBits) - numTags, maximumExtraInhabitantCount)

        return LayoutResult(
            strategyDescription: strategyDescription,
            bitsNeededForTag: numTagBits,
            bitsAvailableForPayload: numPayloadValueBits,
            numTags: numTags,
            extraInhabitantCount: extraInhabitantCount,
            tagRegion: tagRegion,
            payloadRegion: calculateRegion(from: payloadValueBitsMask, bitCount: numPayloadValueBits),
            cases: cases
        )
    }

    // MARK: - Strategy 2: Tagged Multi-Payload
    //
    // Corresponds to `TaggedMultiPayloadEnumTypeInfo` in TypeLowering.cpp.
    // Used when there are no spare bits (or the enum has generic/resilient payloads).
    // An extra tag byte region is appended after the payload.
    //
    // References:
    //   - ABI/Enum.h: getEnumTagCounts
    //   - Enum.cpp: swift_storeEnumTagMultiPayload
    //   - Enum.cpp: swift_getEnumCaseMultiPayload
    //   - Enum.cpp: swift_initEnumMetadataMultiPayload
    //   - TypeLowering.cpp: TaggedMultiPayloadEnumTypeInfo::projectEnumValue

    public static func calculateTaggedMultiPayload(
        payloadSize: Int,
        numPayloadCases: Int,
        numEmptyCases: Int
    ) -> LayoutResult {
        // Use the shared getEnumTagCounts to compute tag layout.
        // ABI/Enum.h: getEnumTagCounts(size, emptyCases, payloadCases)
        let tagCounts = getEnumTagCounts(
            payloadSize: payloadSize,
            emptyCases: numEmptyCases,
            payloadCases: numPayloadCases
        )
        let numTags = tagCounts.numTags
        let numTagBytes = tagCounts.numTagBytes

        let bitsNeeded = numTagBytes * 8
        let tagOffset = payloadSize

        // Virtual mask for the extra tag region
        let region = SpareRegion(
            range: tagOffset ..< (tagOffset + numTagBytes),
            bitCount: bitsNeeded,
            bytes: [UInt8](repeating: 0xFF, count: numTagBytes)
        )

        // Build a display mask for meaningful payload bytes for empty cases.
        var meaningfulPayloadMask = BitMask(sizeInBytes: payloadSize)
        meaningfulPayloadMask.makeZero()

        if numEmptyCases > 0 {
            if payloadSize >= 4 {
                // Determine how many bits are actually needed for the max empty index
                let bitsForEmptyCases = max(bitsRequired(toRepresent: numEmptyCases), 1)

                var remainingBits = bitsForEmptyCases
                for i in 0 ..< payloadSize {
                    if remainingBits <= 0 { break }
                    let bitsInByte = min(remainingBits, 8)
                    meaningfulPayloadMask[byteAt: i] = UInt8((1 << bitsInByte) - 1)
                    remainingBits -= 8
                }
            } else {
                // Small payload: all bits are used/meaningful as it wraps around tags
                meaningfulPayloadMask.invert()
            }
        }

        var cases: [EnumCaseProjection] = []
        let totalCases = numPayloadCases + numEmptyCases

        for i in 0 ..< totalCases {
            let caseIndex = i
            var memoryChanges: [Int: UInt8] = [:]

            let tagValue: Int
            let payloadValue: Int

            if caseIndex < numPayloadCases {
                // --- Payload Case ---
                // Enum.cpp:682-684: storeMultiPayloadTag(value, layout, whichCase)
                tagValue = caseIndex
                payloadValue = 0
            } else {
                // --- Empty Case ---
                // Enum.cpp:688-699: swift_storeEnumTagMultiPayload for empty cases
                let emptyIndex = caseIndex - numPayloadCases

                if payloadSize >= 4 {
                    // Enum.cpp:690-692: whichTag = numPayloads, whichPayloadValue = whichEmptyCase
                    tagValue = numPayloadCases
                    payloadValue = emptyIndex
                } else {
                    // Enum.cpp:694-696: Spread empty cases across multiple tags
                    let numPayloadBits = payloadSize * 8
                    tagValue = numPayloadCases + (emptyIndex >> numPayloadBits)
                    payloadValue = emptyIndex & ((1 << numPayloadBits) - 1)
                }
            }

            // 1. Write tag bytes (after payload area)
            var remainingTagValue = tagValue
            for byteIndex in 0 ..< numTagBytes {
                memoryChanges[tagOffset + byteIndex] = UInt8(remainingTagValue & 0xFF)
                remainingTagValue >>= 8
            }

            // 2. Write payload bytes (only for empty cases)
            if caseIndex >= numPayloadCases {
                var remainingPayloadValue = payloadValue
                for byteIndex in 0 ..< payloadSize {
                    let byteValue = UInt8(remainingPayloadValue & 0xFF)
                    if meaningfulPayloadMask[byteAt: byteIndex] != 0 {
                        memoryChanges[byteIndex] = byteValue
                    }
                    remainingPayloadValue >>= 8
                }
            }

            let isPayloadCase = caseIndex < numPayloadCases
            let name = isPayloadCase ? "payload case #\(caseIndex)" : "empty case #\(caseIndex - numPayloadCases)"
            let payloadAreaEnd = String(payloadSize, radix: 16)
            let explanation = isPayloadCase
                ? "tag byte(s) after the payload area = \(tagValue); bytes[0x0..<0x\(payloadAreaEnd)] hold this payload's value"
                : "tag byte(s) after the payload area = \(tagValue); the payload area holds empty-case value \(payloadValue)"

            cases.append(EnumCaseProjection(
                caseIndex: caseIndex,
                caseName: name,
                isPayloadCase: isPayloadCase,
                tagValue: tagValue,
                payloadValue: isPayloadCase ? 0 : payloadValue,
                memoryChanges: memoryChanges,
                encodingExplanation: explanation
            ))
        }

        // The unused values of the extra tag byte(s) are the enum's extra
        // inhabitants — Enum.cpp: swift_initEnumMetadataMultiPayload computes
        // `(1 << (numTagBytes * 8)) - numTags` (saturated for a 4-byte tag).
        let extraInhabitantCount = numTagBytes >= 4
            ? maximumExtraInhabitantCount
            : min((1 << (numTagBytes * 8)) - numTags, maximumExtraInhabitantCount)

        return LayoutResult(
            strategyDescription: "Tagged Multi-Payload (tag bytes after the payload area)",
            bitsNeededForTag: bitsNeeded,
            bitsAvailableForPayload: 0,
            numTags: numTags,
            extraInhabitantCount: extraInhabitantCount,
            tagRegion: region,
            payloadRegion: nil,
            cases: cases
        )
    }

    // MARK: - Strategy 3: Single Payload
    //
    // Corresponds to `SinglePayloadEnumTypeInfo` in TypeLowering.cpp and
    // `swift_initEnumMetadataSinglePayload` in Enum.cpp.
    //
    // A single-payload enum encodes its empty cases with two mechanisms, in
    // order:
    //   1. Extra inhabitants: bit patterns the payload type can never hold
    //      (a class reference's small invalid addresses, `Bool`'s values 2-255,
    //      `String`'s reserved discriminator patterns, …). Empty case `i`
    //      becomes the payload's extra-inhabitant pattern `#i`.
    //   2. Overflow: once the payload's extra inhabitants run out, extra tag
    //      bytes are appended after the payload; the payload area is then
    //      reused to store the overflow case index.
    //
    // The *count* of extra inhabitants comes from the payload's value-witness
    // table, but their concrete *byte patterns* are a per-payload-type detail
    // this formula cannot know. Extra-inhabitant cases are therefore emitted
    // as `.unresolvedExtraInhabitant`; the runtime path replaces them with
    // exact bytes via `RuntimeEnumCaseProjector` +
    // `LayoutResult.applyingExactCasePatterns`.
    //
    // References:
    //   - Enum.cpp: swift_initEnumMetadataSinglePayload
    //   - EnumImpl.h: storeEnumTagSinglePayloadImpl
    //   - EnumImpl.h: getEnumTagSinglePayloadImpl
    //   - ABI/Enum.h: getEnumTagCounts
    //   - TypeLowering.cpp: SinglePayloadEnumTypeInfo::projectEnumValue

    /// - Parameters:
    ///   - size: Total size of the enum in bytes (payload + any extra tag bytes).
    ///   - payloadSize: Size of the payload area in bytes.
    ///   - numEmptyCases: Number of empty (no-payload) cases.
    ///   - numExtraInhabitants: The payload type's extra-inhabitant count, read
    ///     from its value-witness table (runtime path) or computed by the
    ///     static layout engine. `nil` means the count is unknown; the layout
    ///     then conservatively assumes every empty case overflows into extra
    ///     tag bytes.
    public static func calculateSinglePayload(
        size: Int,
        payloadSize: Int,
        numEmptyCases: Int,
        numExtraInhabitants: Int? = nil
    ) -> LayoutResult {
        let maxExtraInhabitants = numExtraInhabitants ?? 0

        // Empty cases fill the payload's extra inhabitants first, then
        // overflow into extra tag bytes.
        // Enum.cpp:139-146: swift_initEnumMetadataSinglePayload
        //   if (payloadNumExtraInhabitants >= emptyCases) {
        //     size = payloadSize; unusedExtraInhabitants = payloadNumExtraInhabitants - emptyCases;
        //   } else {
        //     size = payloadSize + getEnumTagCounts(...).numTagBytes;
        //   }
        let numExtraInhabitantCases = min(numEmptyCases, maxExtraInhabitants)
        let numOverflowCases = numEmptyCases - numExtraInhabitantCases

        // Extra tag bytes needed for the overflow cases.
        // ABI/Enum.h: getEnumTagCounts(payloadSize, numOverflowCases, 1 /*payload case*/)
        var extraTagBytes = 0
        if numOverflowCases > 0 {
            let tagCounts = getEnumTagCounts(
                payloadSize: payloadSize,
                emptyCases: numOverflowCases,
                payloadCases: 1
            )
            extraTagBytes = tagCounts.numTagBytes
        } else if size > payloadSize {
            // Physical padding exists even if no extra tag is logically needed.
            extraTagBytes = size - payloadSize
        }

        let numTags = 1 + numEmptyCases

        // The extra tag bytes are zero for the payload case and every
        // extra-inhabitant case — that zero is itself part of their patterns
        // (EnumImpl.h:156-160: "For payload or extra inhabitant cases,
        // zero-initialize the extra tag bits").
        var zeroedExtraTagBytes: [Int: UInt8] = [:]
        for byteIndex in 0 ..< extraTagBytes {
            zeroedExtraTagBytes[payloadSize + byteIndex] = 0
        }

        var cases: [EnumCaseProjection] = []
        let payloadAreaEnd = String(payloadSize, radix: 16)
        let zeroedExtraTagSuffix = extraTagBytes > 0
            ? "; the extra tag byte(s) after the payload area are zero"
            : ""

        // --- A. Payload case ---
        // EnumImpl.h: whichCase == 0 → payload case, extra tag bits zeroed.
        let payloadCaseExplanation = extraTagBytes > 0
            ? "holds a valid payload value in bytes[0x0..<0x\(payloadAreaEnd)]\(zeroedExtraTagSuffix)"
            : "holds a valid payload value in bytes[0x0..<0x\(payloadAreaEnd)]; selected when the payload bytes match no empty-case pattern"
        cases.append(EnumCaseProjection(
            caseIndex: 0,
            caseName: "payload case",
            isPayloadCase: true,
            tagValue: 0,
            payloadValue: 0,
            memoryChanges: zeroedExtraTagBytes,
            encodingExplanation: payloadCaseExplanation
        ))

        // --- B. Extra-inhabitant cases ---
        // EnumImpl.h:158-169: whichCase <= payloadNumExtraInhabitants
        //   → zero extra tag bits, store the payload's extra-inhabitant
        //   pattern #(whichCase - 1) via storeExtraInhabitantTag.
        for extraInhabitantIndex in 0 ..< numExtraInhabitantCases {
            cases.append(EnumCaseProjection(
                caseIndex: extraInhabitantIndex + 1,
                caseName: "empty case #\(extraInhabitantIndex)",
                isPayloadCase: false,
                tagValue: 0,
                payloadValue: 0,
                memoryChanges: zeroedExtraTagBytes,
                patternResolution: .unresolvedExtraInhabitant(extraInhabitantIndex: extraInhabitantIndex),
                encodingExplanation: "stored as the payload's extra-inhabitant pattern #\(extraInhabitantIndex) (an invalid payload bit pattern)\(zeroedExtraTagSuffix)"
            ))
        }

        // --- C. Overflow cases (extra tag + payload area) ---
        // EnumImpl.h:172-189: storeEnumTagSinglePayloadImpl
        //   noPayloadIndex = whichCase - 1;
        //   caseIndex = noPayloadIndex - payloadNumExtraInhabitants;
        //   if (payloadSize >= 4) { extraTagIndex = 1; payloadIndex = caseIndex; }
        //   else { extraTagIndex = 1 + (caseIndex >> payloadBits); payloadIndex = caseIndex & mask; }
        for overflowIndex in 0 ..< numOverflowCases {
            let globalEmptyIndex = numExtraInhabitantCases + overflowIndex

            let tagValue: Int
            let payloadValue: Int

            // EnumImpl.h:176-183: Factor the case index into payload and extra
            // tag parts. The threshold is payloadSize >= 4 (32 bits), NOT 8.
            if payloadSize >= 4 {
                // With >= 32 bits of payload, a single extra tag value (1)
                // suffices; the whole overflow index fits the payload area.
                tagValue = 1
                payloadValue = overflowIndex
            } else {
                // Small payload: spread overflow across multiple extra tag values.
                let payloadBits = payloadSize * 8
                payloadValue = overflowIndex & ((1 << payloadBits) - 1)
                tagValue = 1 + (overflowIndex >> payloadBits)
            }

            var memoryChanges: [Int: UInt8] = [:]

            // Extra tag bytes carry the (nonzero) overflow tag.
            if extraTagBytes > 0 {
                var remainingTagValue = tagValue
                for byteIndex in 0 ..< extraTagBytes {
                    memoryChanges[payloadSize + byteIndex] = UInt8(remainingTagValue & 0xFF)
                    remainingTagValue >>= 8
                }
            }

            // The payload area is reused for the overflow case index.
            if payloadSize > 0 {
                var remainingPayloadValue = payloadValue
                for byteIndex in 0 ..< payloadSize {
                    memoryChanges[byteIndex] = UInt8(remainingPayloadValue & 0xFF)
                    remainingPayloadValue >>= 8
                }
            }

            cases.append(EnumCaseProjection(
                caseIndex: globalEmptyIndex + 1,
                caseName: "empty case #\(globalEmptyIndex)",
                isPayloadCase: false,
                tagValue: tagValue,
                payloadValue: payloadValue,
                memoryChanges: memoryChanges,
                encodingExplanation: "overflow beyond the payload's extra inhabitants: extra tag byte(s) = \(tagValue), payload area reused for overflow index \(payloadValue)"
            ))
        }

        var tagRegion: SpareRegion? = nil
        if extraTagBytes > 0 {
            tagRegion = SpareRegion(
                range: payloadSize ..< (payloadSize + extraTagBytes),
                bitCount: extraTagBytes * 8,
                bytes: [UInt8](repeating: 0xFF, count: extraTagBytes)
            )
        }

        let strategyDescription: String
        if numOverflowCases == 0 {
            strategyDescription = "Single Payload (\(numExtraInhabitantCases) empty cases stored as payload extra inhabitants)"
        } else if numExtraInhabitantCases == 0 {
            strategyDescription = "Single Payload (\(numOverflowCases) empty cases stored via extra tag bytes)"
        } else {
            strategyDescription = "Single Payload (\(numExtraInhabitantCases) empty cases as payload extra inhabitants + \(numOverflowCases) via extra tag bytes)"
        }

        return LayoutResult(
            strategyDescription: strategyDescription,
            bitsNeededForTag: extraTagBytes * 8,
            bitsAvailableForPayload: 0,
            numTags: numTags,
            // The payload's inhabitants not spent on empty cases remain the
            // enum's own — GenEnum.cpp: SinglePayloadEnumImplStrategy::
            // getFixedExtraInhabitantCount (payload XI minus the tag values
            // represented as inhabitants).
            extraInhabitantCount: max(0, maxExtraInhabitants - numExtraInhabitantCases),
            tagRegion: tagRegion,
            payloadRegion: nil,
            cases: cases
        )
    }

    // MARK: - Helpers

    /// Number of bits needed to represent values in 0..<count.
    /// Returns 0 when count <= 1.
    ///
    /// Equivalent to `ceil(log2(count))`, but uses integer arithmetic
    /// to avoid floating-point precision loss for large values.
    private static func bitsRequired(toRepresent count: Int) -> Int {
        guard count > 1 else { return 0 }
        var bits = 0
        var value = count - 1
        while value > 0 {
            value >>= 1
            bits += 1
        }
        return bits
    }

    private static func calculateRegion(from mask: BitMask, bitCount: Int) -> SpareRegion? {
        if bitCount == 0 { return nil }
        var minByte = mask.size
        var maxByte = 0
        var hasBits = false

        for i in 0 ..< mask.size {
            if mask[byteAt: i] != 0 {
                if i < minByte { minByte = i }
                if i > maxByte { maxByte = i }
                hasBits = true
            }
        }

        guard hasBits else { return nil }
        let range = minByte ..< (maxByte + 1)
        let bytes = Array(mask.bytes[range])
        return SpareRegion(range: range, bitCount: bitCount, bytes: bytes)
    }

    private static func extractChanges(from data: [UInt8], showMask: BitMask) -> [Int: UInt8] {
        var changes: [Int: UInt8] = [:]
        for i in 0 ..< data.count {
            if showMask[byteAt: i] != 0 {
                changes[i] = data[i]
            }
        }
        return changes
    }

    private static func extractChangesForEmptyCase(
        data: [UInt8],
        tagMask: BitMask,
        meaningfulPayloadMask: BitMask
    ) -> [Int: UInt8] {
        var changes: [Int: UInt8] = [:]

        for i in 0 ..< data.count {
            if tagMask[byteAt: i] != 0 || meaningfulPayloadMask[byteAt: i] != 0 {
                changes[i] = data[i]
            }
        }

        return changes
    }
}
