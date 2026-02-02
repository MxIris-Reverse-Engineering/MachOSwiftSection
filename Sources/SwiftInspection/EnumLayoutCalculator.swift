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

    // MARK: - Result Structures

    public struct SpareRegion: CustomStringConvertible, Sendable {
        public let range: Range<Int>
        public let bitCount: Int
        public let bytes: [UInt8]
        public var description: String { return "Offset \(range) (Used: \(bitCount) bits)" }
    }

    public struct EnumCaseProjection: CustomStringConvertible, Sendable {
        public let caseIndex: Int
        public let caseName: String
        public let tagValue: Int
        public let payloadValue: Int
        public let memoryChanges: [Int: UInt8]

        public var description: String {
            description(indent: .zero)
        }

        public func description(indent: Int, prefix: String = "") -> String {
            let indentString = String(repeating: "    ", count: indent)

            let hexIndex = String(format: "0x%02X", caseIndex)
            var output = "\(indentString)\(prefix) Case \(caseIndex) (\(hexIndex)) - \(caseName):\n"
            output += "\(indentString)\(prefix) Tag: \(tagValue)"
            if payloadValue > 0 {
                output += ", PayloadValue: \(payloadValue)"
            }
            output += "\n"

            output += formattedMemoryChanges(indent: indent, prefix: prefix)
            return output
        }

        /// Returns only the memory changes portion of the case description.
        public func formattedMemoryChanges(indent: Int, prefix: String = "") -> String {
            let indentString = String(repeating: "    ", count: indent)
            if memoryChanges.isEmpty {
                return "\(indentString)\(prefix) (No bits set / Zero)\n"
            } else {
                var output = ""
                for offset in memoryChanges.keys.sorted() {
                    let byteValue = memoryChanges[offset]!
                    let byteHex = String(format: "0x%02X", byteValue)
                    let binaryString = String(byteValue, radix: 2)
                    let padding = String(repeating: "0", count: 8 - binaryString.count)
                    output += "\(indentString)\(prefix) Memory Offset \(offset) (\(String(format: "0x%02X", offset))) = \(byteHex) (Bin: \(padding + binaryString))\n"
                }
                return output
            }
        }
    }

    public struct LayoutResult: CustomStringConvertible, Sendable {
        public let strategyDescription: String
        public let bitsNeededForTag: Int
        public let bitsAvailableForPayload: Int
        public let numTags: Int
        public let tagRegion: SpareRegion?
        public let payloadRegion: SpareRegion?
        public let cases: [EnumCaseProjection]

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

            let `case` = EnumCaseProjection(
                caseIndex: i,
                caseName: "Payload Case \(i)",
                tagValue: tagValue,
                payloadValue: 0,
                memoryChanges: memoryChanges
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

                let `case` = EnumCaseProjection(
                    caseIndex: globalIndex,
                    caseName: "Empty Case \(i)",
                    tagValue: finalTag,
                    payloadValue: payloadValue,
                    memoryChanges: memoryChanges
                )

                cases.append(`case`)
            }
        }

        let strategyDescription: String
        let tagRegion: SpareRegion?

        if extraTagByteCount > 0 {
            // Hybrid: spare bits in payload + extra tag bytes after payload.
            strategyDescription = "Multi-Payload (Spare Bits: \(numPayloadTagBits) + Extra Tag: \(extraTagBitCount) bits)"
            // Show the extra tag byte region (spare bits are visible in memoryChanges).
            tagRegion = SpareRegion(
                range: payloadSize ..< (payloadSize + extraTagByteCount),
                bitCount: extraTagBitCount,
                bytes: [UInt8](repeating: 0xFF, count: extraTagByteCount)
            )
        } else {
            strategyDescription = "Multi-Payload (Spare Bits)"
            tagRegion = calculateRegion(from: payloadTagBitsMask, bitCount: numTagBits)
        }

        return LayoutResult(
            strategyDescription: strategyDescription,
            bitsNeededForTag: numTagBits,
            bitsAvailableForPayload: numPayloadValueBits,
            numTags: numTags,
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

            let name = (caseIndex < numPayloadCases) ? "Payload Case \(caseIndex)" : "Empty Case \(caseIndex - numPayloadCases)"

            cases.append(EnumCaseProjection(
                caseIndex: caseIndex,
                caseName: name,
                tagValue: tagValue,
                payloadValue: (caseIndex >= numPayloadCases) ? payloadValue : 0,
                memoryChanges: memoryChanges
            ))
        }

        return LayoutResult(
            strategyDescription: "Tagged Multi-Payload (Extra Tag)",
            bitsNeededForTag: bitsNeeded,
            bitsAvailableForPayload: 0,
            numTags: numTags,
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
    // A single-payload enum uses two mechanisms to encode empty cases:
    //   1. Extra Inhabitants (XI): Invalid bit patterns in the payload area
    //      (determined by the payload type's spare bits).
    //   2. Overflow: Extra tag bytes appended after the payload, with the payload
    //      area reused to store the overflow case index.
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
    ///   - numExtraInhabitants: Number of extra inhabitants from the payload type's VWT.
    ///     When provided, this overrides the spare-bits-derived XI count.
    ///     This is the primary way EnumDumper passes XI info for single-payload enums.
    ///   - spareBytes: Raw spare bit mask bytes (optional, for detailed XI encoding display).
    ///   - spareBytesOffset: Offset of spare bytes within the payload area.
    public static func calculateSinglePayload(
        size: Int,
        payloadSize: Int,
        numEmptyCases: Int,
        numExtraInhabitants: Int? = nil,
        spareBytes: [UInt8] = [],
        spareBytesOffset: Int = 0
    ) -> LayoutResult {
        // Build spare bits mask from provided spare bytes.
        var spareBitMask = BitMask.zeroMask(sizeInBytes: payloadSize)
        if !spareBytes.isEmpty {
            let copyLength = min(spareBytes.count, payloadSize - spareBytesOffset)
            for i in 0 ..< copyLength {
                spareBitMask[byteAt: spareBytesOffset + i] = spareBytes[i]
            }
        }

        let totalSpareBits = spareBitMask.countSetBits()

        // Compute Extra Inhabitants (XI) capacity.
        // If numExtraInhabitants is provided (from payload type's VWT), use it directly.
        // Otherwise, derive from spare bits (capped at 32 usable bits).
        let maxExtraInhabitants: Int
        if let numExtraInhabitants {
            maxExtraInhabitants = numExtraInhabitants
        } else {
            let usableSpareBits = min(totalSpareBits, 32)
            // Cap at ValueWitnessFlags::MaxNumExtraInhabitants (0x7FFFFFFF).
            maxExtraInhabitants = (usableSpareBits >= 32) ? 0x7FFF_FFFF : (1 << usableSpareBits) - 1
        }

        // Hybrid strategy: use XI first, overflow to extra tag bytes.
        // Enum.cpp:139-146: swift_initEnumMetadataSinglePayload
        //   if (payloadNumExtraInhabitants >= emptyCases) {
        //     size = payloadSize; unusedExtraInhabitants = payloadNumExtraInhabitants - emptyCases;
        //   } else {
        //     size = payloadSize + getEnumTagCounts(...).numTagBytes;
        //   }
        let numExtraInhabitantCases = min(numEmptyCases, maxExtraInhabitants)
        let numOverflowCases = numEmptyCases - numExtraInhabitantCases

        // Compute extra tag bytes needed for overflow cases.
        // Uses getEnumTagCounts(payloadSize, numOverflowCases, 1 /*payload case*/).
        // ABI/Enum.h: getEnumTagCounts
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

        var cases: [EnumCaseProjection] = []

        // --- A. Payload Case ---
        // EnumImpl.h: whichCase == 0 → payload case, extra tag bits zeroed.
        cases.append(EnumCaseProjection(
            caseIndex: 0,
            caseName: "Payload Case (Valid)",
            tagValue: 0,
            payloadValue: 0,
            memoryChanges: [:]
        ))

        // --- B. XI Cases ---
        // EnumImpl.h:158-169: whichCase <= payloadNumExtraInhabitants
        //   → zero extra tag bits, store extra inhabitant via storeExtraInhabitantTag.
        if numExtraInhabitantCases > 0 {
            var extraInhabitantMask = spareBitMask
            extraInhabitantMask.keepOnlyLeastSignificantBytes(payloadSize)

            for i in 0 ..< numExtraInhabitantCases {
                let extraInhabitantIndex = i
                // XI encoding: ~index scattered into spare bits.
                // This approximates the runtime's storeExtraInhabitantTag behavior
                // for types where spare bits define the XI patterns.
                let invertedIndex = ~extraInhabitantIndex
                let scatterValue = Int(bitPattern: UInt(truncatingIfNeeded: invertedIndex))

                let memBytes = spareBitMask.scatterBits(value: scatterValue)

                cases.append(EnumCaseProjection(
                    caseIndex: i + 1,
                    caseName: "Empty Case \(i) (XI #\(i))",
                    tagValue: 0,
                    payloadValue: 0,
                    memoryChanges: extractChanges(from: memBytes, showMask: spareBitMask)
                ))
            }
        }

        // --- C. Overflow Cases (Extra Tag + Payload) ---
        // EnumImpl.h:172-189: storeEnumTagSinglePayloadImpl
        //   noPayloadIndex = whichCase - 1;
        //   caseIndex = noPayloadIndex - payloadNumExtraInhabitants;
        //   if (payloadSize >= 4) { extraTagIndex = 1; payloadIndex = caseIndex; }
        //   else { extraTagIndex = 1 + (caseIndex >> payloadBits); payloadIndex = caseIndex & mask; }
        if numOverflowCases > 0 {
            let startEmptyIndex = numExtraInhabitantCases

            for i in 0 ..< numOverflowCases {
                let overflowIndex = i
                let globalEmptyIndex = startEmptyIndex + i

                let tagValue: Int
                let payloadValue: Int

                // EnumImpl.h:176-183: Factor case index into payload and extra tag parts.
                // Threshold is payloadSize >= 4 (32 bits), NOT 8.
                if payloadSize >= 4 {
                    // With >= 32 bits of payload, a single extra tag value (1) suffices.
                    // The entire overflow index is stored in the payload area.
                    tagValue = 1
                    payloadValue = overflowIndex
                } else {
                    // Small payload: spread overflow across multiple extra tag values.
                    let payloadBits = payloadSize * 8
                    payloadValue = overflowIndex & ((1 << payloadBits) - 1)
                    tagValue = 1 + (overflowIndex >> payloadBits)
                }

                var memoryChanges: [Int: UInt8] = [:]

                // Write extra tag bytes
                if extraTagBytes > 0 {
                    var remainingTagValue = tagValue
                    for byteIndex in 0 ..< extraTagBytes {
                        memoryChanges[payloadSize + byteIndex] = UInt8(remainingTagValue & 0xFF)
                        remainingTagValue >>= 8
                    }
                }

                // Write payload bytes (entire payload area is reused for the index)
                if payloadSize > 0 {
                    var remainingPayloadValue = payloadValue
                    for byteIndex in 0 ..< payloadSize {
                        memoryChanges[byteIndex] = UInt8(remainingPayloadValue & 0xFF)
                        remainingPayloadValue >>= 8
                    }
                }

                cases.append(EnumCaseProjection(
                    caseIndex: globalEmptyIndex + 1,
                    caseName: "Empty Case \(globalEmptyIndex) (Overflow)",
                    tagValue: tagValue,
                    payloadValue: payloadValue,
                    memoryChanges: memoryChanges
                ))
            }
        }

        var tagRegion: SpareRegion? = nil
        if extraTagBytes > 0 {
            tagRegion = SpareRegion(
                range: payloadSize ..< (payloadSize + extraTagBytes),
                bitCount: extraTagBytes * 8,
                bytes: [UInt8](repeating: 0xFF, count: extraTagBytes)
            )
        } else {
            tagRegion = calculateRegion(from: spareBitMask, bitCount: totalSpareBits)
        }

        return LayoutResult(
            strategyDescription: "Single Payload (XI: \(numExtraInhabitantCases) + Overflow: \(numOverflowCases))",
            bitsNeededForTag: extraTagBytes * 8,
            bitsAvailableForPayload: 0,
            numTags: numTags,
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
