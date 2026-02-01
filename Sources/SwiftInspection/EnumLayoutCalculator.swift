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
            let indentString = (0 ..< indent).reduce("") { string, _ in string + "    " }

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
            let indentString = (0 ..< indent).reduce("") { string, _ in string + "    " }
            if memoryChanges.isEmpty {
                return "\(indentString)\(prefix) (No bits set / Zero)\n"
            } else {
                var output = ""
                for offset in memoryChanges.keys.sorted() {
                    let byteValue = memoryChanges[offset]!
                    let byteHex = String(format: "0x%02X", byteValue)
                    let binaryStr = String(byteValue, radix: 2)
                    let padding = String(repeating: "0", count: 8 - binaryStr.count)
                    output += "\(indentString)\(prefix) Memory Offset \(offset) (\(String(format: "0x%02X", offset))) = \(byteHex) (Bin: \(padding + binaryStr))\n"
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
            if let tr = tagRegion { output += "Tag Region: \(tr)\n" }
            if let pr = payloadRegion { output += "Payload Value Region (Occupied Bits): \(pr)\n" }
            output += "--------------------------\n"
            cases.forEach { output += $0.description }
            output += "=========================="
            return output
        }
    }

    public enum LayoutError: Error, CustomStringConvertible {
        case notEnoughSpareBits(needed: Int, available: Int)

        public var description: String {
            switch self {
            case .notEnoughSpareBits(let needed, let available):
                return "Not enough spare bits: needed \(needed), available \(available)"
            }
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
    ) throws -> LayoutResult {
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
        var numTagBits = 0
        if numTags > 1 {
            var temp = numTags - 1
            while temp > 0 {
                temp >>= 1; numTagBits += 1
            }
        }

        // Select tag bits from the most significant spare bits.
        // GenEnum.cpp:7292-7308: Takes bits starting from the most significant.
        var payloadTagBitsMask = commonSpareBits
        payloadTagBitsMask.keepOnlyMostSignificantBits(numTagBits)

        if payloadTagBitsMask.countSetBits() < numTagBits {
            throw LayoutError.notEnoughSpareBits(needed: numTagBits, available: payloadTagBitsMask.countSetBits())
        }

        // Occupied bits mask = complement of spare bits.
        // GenEnum.cpp:4084: scatterBits(~CommonSpareBits.asAPInt(), tagIndex)
        var payloadValueBitsMask = commonSpareBits
        payloadValueBitsMask.invert()
        let numPayloadValueBits = payloadValueBitsMask.countSetBits()

        // Build a display mask for meaningful payload bits (only for visualization).
        let bitsRequiredForEmptyCases = (numEmptyCases > 1) ? (Int(log2(Double(numEmptyCases - 1))) + 1) : 1
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

        // A. Payload Cases: tag = caseIndex, scattered into PayloadTagBits
        // GenEnum.cpp: storePayloadTag scatters tag into PayloadTagBits
        for i in 0 ..< numPayloadCases {
            let tagVal = i
            let memBytes = payloadTagBitsMask.scatterBits(value: tagVal)

            let `case` = EnumCaseProjection(
                caseIndex: i,
                caseName: "Payload Case \(i)",
                tagValue: tagVal,
                payloadValue: 0,
                memoryChanges: extractChanges(from: memBytes, showMask: payloadTagBitsMask)
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

                // Guard against shift overflow on 64-bit Swift Int
                let payloadValueMaskInt = (numPayloadValueBits >= 64) ? -1 : (1 << numPayloadValueBits) - 1
                let payloadVal = emptyIndex & payloadValueMaskInt

                let tagOffset = emptyIndex >> numPayloadValueBits
                let finalTag = numPayloadCases + tagOffset

                let tagBytes = payloadTagBitsMask.scatterBits(value: finalTag)
                let payloadBytes = payloadValueBitsMask.scatterBits(value: payloadVal)

                var combinedBytes = [UInt8](repeating: 0, count: payloadSize)
                for b in 0 ..< payloadSize {
                    combinedBytes[b] = tagBytes[b] | payloadBytes[b]
                }

                let `case` = EnumCaseProjection(
                    caseIndex: globalIndex,
                    caseName: "Empty Case \(i)",
                    tagValue: finalTag,
                    payloadValue: payloadVal,
                    memoryChanges: extractChangesForEmptyCase(
                        data: combinedBytes,
                        tagMask: payloadTagBitsMask,
                        meaningfulPayloadMask: meaningfulPayloadMask
                    )
                )

                cases.append(`case`)
            }
        }

        return LayoutResult(
            strategyDescription: "Multi-Payload (Spare Bits + Occupied Bits Overflow)",
            bitsNeededForTag: numTagBits,
            bitsAvailableForPayload: numPayloadValueBits,
            numTags: numTags,
            tagRegion: calculateRegion(from: payloadTagBitsMask, bitCount: numTagBits),
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
                let maxIndex = numEmptyCases - 1
                let bitsRequired = (maxIndex > 0) ? (Int(log2(Double(maxIndex))) + 1) : 1

                var remainingBits = bitsRequired
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
            var tempTag = tagValue
            for b in 0 ..< numTagBytes {
                memoryChanges[tagOffset + b] = UInt8(tempTag & 0xFF)
                tempTag >>= 8
            }

            // 2. Write payload bytes (only for empty cases)
            if caseIndex >= numPayloadCases {
                var tempPayload = payloadValue
                for b in 0 ..< payloadSize {
                    let byteVal = UInt8(tempPayload & 0xFF)
                    if meaningfulPayloadMask[byteAt: b] != 0 {
                        memoryChanges[b] = byteVal
                    }
                    tempPayload >>= 8
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
            let copyLen = min(spareBytes.count, payloadSize - spareBytesOffset)
            for i in 0 ..< copyLen {
                spareBitMask[byteAt: spareBytesOffset + i] = spareBytes[i]
            }
        }

        let totalSpareBits = spareBitMask.countSetBits()

        // Compute Extra Inhabitants (XI) capacity.
        // If numExtraInhabitants is provided (from payload type's VWT), use it directly.
        // Otherwise, derive from spare bits (capped at 32 usable bits).
        let maxXI: Int
        if let numExtraInhabitants {
            maxXI = numExtraInhabitants
        } else {
            let usableSpareBits = min(totalSpareBits, 32)
            maxXI = (usableSpareBits >= 32) ? Int.max : (1 << usableSpareBits) - 1
        }

        // Hybrid strategy: use XI first, overflow to extra tag bytes.
        // Enum.cpp:139-146: swift_initEnumMetadataSinglePayload
        //   if (payloadNumExtraInhabitants >= emptyCases) {
        //     size = payloadSize; unusedExtraInhabitants = payloadNumExtraInhabitants - emptyCases;
        //   } else {
        //     size = payloadSize + getEnumTagCounts(...).numTagBytes;
        //   }
        let numXICases = min(numEmptyCases, maxXI)
        let numOverflowCases = numEmptyCases - numXICases

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
        if numXICases > 0 {
            var xiMask = spareBitMask
            xiMask.keepOnlyLeastSignificantBytes(payloadSize)

            for i in 0 ..< numXICases {
                let xiIndex = i
                // XI encoding: ~index scattered into spare bits.
                // This approximates the runtime's storeExtraInhabitantTag behavior
                // for types where spare bits define the XI patterns.
                let invertedIndex = ~xiIndex
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
            let startEmptyIndex = numXICases

            for i in 0 ..< numOverflowCases {
                let overflowIndex = i
                let globalEmptyIndex = startEmptyIndex + i

                let tagValue: Int
                let payloadVal: Int

                // EnumImpl.h:176-183: Factor case index into payload and extra tag parts.
                // Threshold is payloadSize >= 4 (32 bits), NOT 8.
                if payloadSize >= 4 {
                    // With >= 32 bits of payload, a single extra tag value (1) suffices.
                    // The entire overflow index is stored in the payload area.
                    tagValue = 1
                    payloadVal = overflowIndex
                } else {
                    // Small payload: spread overflow across multiple extra tag values.
                    let payloadBits = payloadSize * 8
                    payloadVal = overflowIndex & ((1 << payloadBits) - 1)
                    tagValue = 1 + (overflowIndex >> payloadBits)
                }

                var mem: [Int: UInt8] = [:]

                // Write extra tag bytes
                if extraTagBytes > 0 {
                    var t = tagValue
                    for b in 0 ..< extraTagBytes {
                        mem[payloadSize + b] = UInt8(t & 0xFF)
                        t >>= 8
                    }
                }

                // Write payload bytes (entire payload area is reused for the index)
                if payloadSize > 0 {
                    var p = payloadVal
                    for b in 0 ..< payloadSize {
                        mem[b] = UInt8(p & 0xFF)
                        p >>= 8
                    }
                }

                cases.append(EnumCaseProjection(
                    caseIndex: globalEmptyIndex + 1,
                    caseName: "Empty Case \(globalEmptyIndex) (Overflow)",
                    tagValue: tagValue,
                    payloadValue: payloadVal,
                    memoryChanges: mem
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
            strategyDescription: "Single Payload (XI: \(numXICases) + Overflow: \(numOverflowCases))",
            bitsNeededForTag: extraTagBytes * 8,
            bitsAvailableForPayload: 0,
            numTags: numTags,
            tagRegion: tagRegion,
            payloadRegion: nil,
            cases: cases
        )
    }

    // MARK: - Helpers

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
