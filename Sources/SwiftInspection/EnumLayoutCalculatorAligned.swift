import Foundation

public enum EnumLayoutCalculatorAligned {
    public typealias SpareRegion = EnumLayoutCalculator.SpareRegion
    public typealias EnumCaseProjection = EnumLayoutCalculator.EnumCaseProjection
    public typealias LayoutResult = EnumLayoutCalculator.LayoutResult
    public typealias LayoutError = EnumLayoutCalculator.LayoutError

    // MARK: - Strategy 1: Multi-Payload (Spare Bits + Extra Tag Bits)

    public static func calculateMultiPayload(
        payloadSize: Int,
        spareBytes: [UInt8],
        spareBytesOffset: Int,
        numPayloadCases: Int,
        numEmptyCases: Int
    ) throws -> LayoutResult {
        var commonSpareBits = BitMask.zeroMask(sizeInBytes: payloadSize)
        if spareBytesOffset < payloadSize {
            let copyLength = min(spareBytes.count, payloadSize - spareBytesOffset)
            for i in 0 ..< copyLength {
                commonSpareBits[byteAt: spareBytesOffset + i] = spareBytes[i]
            }
        }

        let commonSpareBitCount = commonSpareBits.countSetBits()
        let usedBitCount = commonSpareBits.size * 8 - commonSpareBitCount

        let numEmptyElementTags: Int
        if numEmptyCases == 0 {
            numEmptyElementTags = 0
        } else if usedBitCount >= 32 {
            numEmptyElementTags = 1
        } else {
            let emptyElementsPerTag = 1 << usedBitCount
            numEmptyElementTags = (numEmptyCases + emptyElementsPerTag - 1) / emptyElementsPerTag
        }

        let numTags = numPayloadCases + numEmptyElementTags
        let numTagBits = bitWidthForTagCount(numTags)

        let extraTagBitCount = max(0, numTagBits - commonSpareBitCount)
        let extraTagByteCount = byteCountForTagBits(extraTagBitCount)

        var payloadTagBitsMask = BitMask.zeroMask(sizeInBytes: payloadSize)
        if numTagBits > 0 {
            payloadTagBitsMask = commonSpareBits
            if numTagBits < commonSpareBitCount {
                payloadTagBitsMask.keepOnlyMostSignificantBits(numTagBits)
            }
        }

        var payloadValueBitsMask = commonSpareBits
        payloadValueBitsMask.invert()
        let numPayloadValueBits = payloadValueBitsMask.countSetBits()

        let numCaseBits = usedBitCount
        let casesPerTag = numCaseBits >= 32 ? 0x8000_0000 : (1 << numCaseBits)

        var bitsRequiredForPayloadIndex = 0
        if numEmptyCases > 0 {
            if numCaseBits >= 32 || casesPerTag >= numEmptyCases {
                bitsRequiredForPayloadIndex = bitWidthForTagCount(numEmptyCases)
                if bitsRequiredForPayloadIndex == 0 {
                    bitsRequiredForPayloadIndex = 1
                }
            } else {
                bitsRequiredForPayloadIndex = numCaseBits
            }
        }

        let meaningfulPayloadMask = buildMeaningfulPayloadMask(
            payloadValueBitsMask: payloadValueBitsMask,
            bitsRequired: bitsRequiredForPayloadIndex
        )

        var cases: [EnumCaseProjection] = []
        let numSpareBits = commonSpareBitCount

        // A. Payload Cases
        if numPayloadCases > 0 {
            for i in 0 ..< numPayloadCases {
                let tagVal = i
                let spareTagValue = tagVal & lowBitsMask(numSpareBits)
                let extraTagValue = extraTagBitCount > 0 ? safeShiftRight(tagVal, numSpareBits) : 0

                let tagBytes = payloadTagBitsMask.scatterBits(value: spareTagValue)
                var memoryChanges = extractChanges(from: tagBytes, showMask: payloadTagBitsMask)
                memoryChanges = addExtraTagBytes(
                    changes: memoryChanges,
                    extraTagBytes: encodeExtraTagBytes(extraTagValue, byteCount: extraTagByteCount),
                    offset: payloadSize
                )

                cases.append(EnumCaseProjection(
                    caseIndex: i,
                    caseName: "Payload Case \(i)",
                    tagValue: tagVal,
                    payloadValue: 0,
                    memoryChanges: memoryChanges
                ))
            }
        }

        // B. Empty Cases
        if numEmptyCases > 0 {
            for i in 0 ..< numEmptyCases {
                let globalIndex = numPayloadCases + i

                let tag: Int
                let tagIndex: Int
                if numCaseBits >= 32 || casesPerTag >= numEmptyCases {
                    tag = numPayloadCases
                    tagIndex = i
                } else {
                    tag = safeShiftRight(i, numCaseBits) + numPayloadCases
                    tagIndex = i & lowBitsMask(numCaseBits)
                }

                let payloadVal = numPayloadValueBits > 0
                    ? (tagIndex & lowBitsMask(numPayloadValueBits))
                    : 0

                let spareTagValue = tag & lowBitsMask(numSpareBits)
                let extraTagValue = extraTagBitCount > 0 ? safeShiftRight(tag, numSpareBits) : 0

                let tagBytes = payloadTagBitsMask.scatterBits(value: spareTagValue)
                let payloadBytes = payloadValueBitsMask.scatterBits(value: payloadVal)

                var combinedBytes = [UInt8](repeating: 0, count: payloadSize)
                for b in 0 ..< payloadSize {
                    combinedBytes[b] = tagBytes[b] | payloadBytes[b]
                }

                var memoryChanges = extractChangesForEmptyCase(
                    data: combinedBytes,
                    tagMask: payloadTagBitsMask,
                    meaningfulPayloadMask: meaningfulPayloadMask
                )

                memoryChanges = addExtraTagBytes(
                    changes: memoryChanges,
                    extraTagBytes: encodeExtraTagBytes(extraTagValue, byteCount: extraTagByteCount),
                    offset: payloadSize
                )

                cases.append(EnumCaseProjection(
                    caseIndex: globalIndex,
                    caseName: "Empty Case \(i)",
                    tagValue: tag,
                    payloadValue: payloadVal,
                    memoryChanges: memoryChanges
                ))
            }
        }

        return LayoutResult(
            strategyDescription: "Multi-Payload (payloadTagBits: \(payloadTagBitsMask.countSetBits()), extraTagBits: \(extraTagBitCount), extraTagBytes: \(extraTagByteCount))",
            bitsNeededForTag: numTagBits,
            bitsAvailableForPayload: numPayloadValueBits,
            numTags: numTags,
            tagRegion: calculateRegion(from: payloadTagBitsMask, bitCount: payloadTagBitsMask.countSetBits()),
            payloadRegion: calculateRegion(from: payloadValueBitsMask, bitCount: numPayloadValueBits),
            cases: cases
        )
    }

    // MARK: - Strategy 2: Tagged Multi-Payload (No Spare Bits)

    public static func calculateTaggedMultiPayload(
        payloadSize: Int,
        numPayloadCases: Int,
        numEmptyCases: Int
    ) -> LayoutResult {
        let usedBitCount = payloadSize * 8

        let numEmptyElementTags: Int
        if numEmptyCases == 0 {
            numEmptyElementTags = 0
        } else if usedBitCount >= 32 {
            numEmptyElementTags = 1
        } else {
            let emptyElementsPerTag = 1 << usedBitCount
            numEmptyElementTags = (numEmptyCases + emptyElementsPerTag - 1) / emptyElementsPerTag
        }

        let numTags = numPayloadCases + numEmptyElementTags
        let numTagBits = bitWidthForTagCount(numTags)
        let extraTagBitCount = numTagBits
        let extraTagByteCount = byteCountForTagBits(extraTagBitCount)
        let tagOffset = payloadSize

        let tagRegion = SpareRegion(
            range: tagOffset ..< (tagOffset + extraTagByteCount),
            bitCount: extraTagByteCount * 8,
            bytes: [UInt8](repeating: 0xFF, count: extraTagByteCount)
        )

        var meaningfulPayloadMask = BitMask(sizeInBytes: payloadSize)
        meaningfulPayloadMask.makeZero()

        if numEmptyCases > 0 {
            if payloadSize >= 4 {
                let maxIndex = numEmptyCases - 1
                var bitsRequired = bitWidthForTagCount(maxIndex + 1)
                if bitsRequired == 0 { bitsRequired = 1 }

                var remainingBits = bitsRequired
                for i in 0 ..< payloadSize {
                    if remainingBits <= 0 { break }
                    let bitsInByte = min(remainingBits, 8)
                    meaningfulPayloadMask[byteAt: i] = UInt8((1 << bitsInByte) - 1)
                    remainingBits -= 8
                }
            } else {
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
                tagValue = caseIndex
                payloadValue = 0
            } else {
                let emptyIndex = caseIndex - numPayloadCases
                if payloadSize >= 4 {
                    tagValue = numPayloadCases
                    payloadValue = emptyIndex
                } else {
                    let bits = payloadSize * 8
                    tagValue = numPayloadCases + safeShiftRight(emptyIndex, bits)
                    payloadValue = emptyIndex & lowBitsMask(bits)
                }
            }

            let extraTagBytes = encodeExtraTagBytes(tagValue, byteCount: extraTagByteCount)
            for b in 0 ..< extraTagByteCount {
                memoryChanges[tagOffset + b] = extraTagBytes[b]
            }

            if caseIndex >= numPayloadCases {
                var tempPayload = payloadValue
                for b in 0 ..< payloadSize {
                    let byteVal = UInt8(tempPayload & 0xFF)
                    if meaningfulPayloadMask[byteAt: b] != 0 {
                        memoryChanges[b] = byteVal
                    }
                    tempPayload = safeShiftRight(tempPayload, 8)
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
            strategyDescription: "Tagged Multi-Payload (extraTagBits: \(extraTagBitCount), extraTagBytes: \(extraTagByteCount))",
            bitsNeededForTag: extraTagByteCount * 8,
            bitsAvailableForPayload: 0,
            numTags: numTags,
            tagRegion: tagRegion,
            payloadRegion: nil,
            cases: cases
        )
    }

    // MARK: - Strategy 3: Single Payload (Extra Inhabitants + Extra Tag Bits)

    public static func calculateSinglePayload(
        size: Int,
        payloadSize: Int,
        numEmptyCases: Int,
        spareBytes: [UInt8] = [],
        spareBytesOffset: Int = 0
    ) -> LayoutResult {
        var spareBitMask = BitMask.zeroMask(sizeInBytes: payloadSize)
        if !spareBytes.isEmpty {
            let copyLen = min(spareBytes.count, max(0, payloadSize - spareBytesOffset))
            if copyLen > 0 {
                for i in 0 ..< copyLen {
                    spareBitMask[byteAt: spareBytesOffset + i] = spareBytes[i]
                }
            }
        }

        let fixedExtraInhabitantCount = 0
        let numTags = numEmptyCases
        let numExtraInhabitantTagValues = min(numTags, fixedExtraInhabitantCount)
        let tagsWithoutInhabitants = numTags - numExtraInhabitantTagValues

        let extraTagBitCount: Int
        let numExtraTagValues: Int
        if tagsWithoutInhabitants == 0 {
            extraTagBitCount = 0
            numExtraTagValues = 0
        } else if payloadSize >= 4 {
            extraTagBitCount = 1
            numExtraTagValues = 2
        } else {
            let payloadBits = payloadSize * 8
            let tagsPerTagBitValue = payloadBits >= 31 ? Int.max : (1 << payloadBits)
            let tagsNeeded = (tagsWithoutInhabitants + tagsPerTagBitValue - 1) / tagsPerTagBitValue
            numExtraTagValues = tagsNeeded + 1
            extraTagBitCount = bitWidthForTagCount(numExtraTagValues)
        }

        let extraTagByteCount = byteCountForTagBits(extraTagBitCount)

        var cases: [EnumCaseProjection] = []

        cases.append(EnumCaseProjection(
            caseIndex: 0,
            caseName: "Payload Case (Valid)",
            tagValue: 0,
            payloadValue: 0,
            memoryChanges: [:]
        ))

        if numEmptyCases > 0 {
            for i in 0 ..< numEmptyCases {
                let tagIndex = i - numExtraInhabitantTagValues

                let tagValue: Int
                let payloadVal: Int

                if payloadSize >= 4 {
                    tagValue = 1
                    payloadVal = max(tagIndex, 0)
                } else {
                    let payloadBits = payloadSize * 8
                    let payloadMask = lowBitsMask(payloadBits)
                    let safeIndex = max(tagIndex, 0)
                    payloadVal = safeIndex & payloadMask
                    tagValue = 1 + safeShiftRight(safeIndex, payloadBits)
                }

                var mem: [Int: UInt8] = [:]

                if extraTagByteCount > 0 {
                    let extraTagBytes = encodeExtraTagBytes(tagValue, byteCount: extraTagByteCount)
                    for b in 0 ..< extraTagByteCount {
                        mem[payloadSize + b] = extraTagBytes[b]
                    }
                }

                if payloadSize > 0 {
                    var p = payloadVal
                    for b in 0 ..< payloadSize {
                        mem[b] = UInt8(p & 0xFF)
                        p = safeShiftRight(p, 8)
                    }
                }

                cases.append(EnumCaseProjection(
                    caseIndex: i + 1,
                    caseName: "Empty Case \(i)",
                    tagValue: tagValue,
                    payloadValue: payloadVal,
                    memoryChanges: mem
                ))
            }
        }

        let tagRegion: SpareRegion?
        if extraTagByteCount > 0 {
            tagRegion = SpareRegion(
                range: payloadSize ..< (payloadSize + extraTagByteCount),
                bitCount: extraTagByteCount * 8,
                bytes: [UInt8](repeating: 0xFF, count: extraTagByteCount)
            )
        } else if fixedExtraInhabitantCount > 0 {
            let totalSpareBits = spareBitMask.countSetBits()
            tagRegion = calculateRegion(from: spareBitMask, bitCount: totalSpareBits)
        } else {
            tagRegion = nil
        }

        return LayoutResult(
            strategyDescription: "Single Payload (extraInhabitants: \(fixedExtraInhabitantCount), extraTagBits: \(extraTagBitCount), extraTagBytes: \(extraTagByteCount), size: \(size))",
            bitsNeededForTag: extraTagByteCount * 8,
            bitsAvailableForPayload: 0,
            numTags: numTags,
            tagRegion: tagRegion,
            payloadRegion: nil,
            cases: cases
        )
    }

    // MARK: - Helpers

    private static func bitWidthForTagCount(_ numTags: Int) -> Int {
        if numTags <= 1 { return 0 }
        var value = numTags - 1
        var bits = 0
        while value > 0 {
            value >>= 1
            bits += 1
        }
        return bits
    }

    private static func lowBitsMask(_ bits: Int) -> Int {
        if bits <= 0 { return 0 }
        if bits >= Int.bitWidth { return -1 }
        return (1 << bits) - 1
    }

    private static func safeShiftRight(_ value: Int, _ bits: Int) -> Int {
        if bits <= 0 { return value }
        if bits >= Int.bitWidth { return 0 }
        return value >> bits
    }

    private static func byteCountForTagBits(_ tagBits: Int) -> Int {
        if tagBits <= 0 { return 0 }
        if tagBits == 1 { return 1 }
        var tagBytes = (tagBits + 7) / 8
        if (tagBytes & (tagBytes - 1)) != 0 {
            tagBytes = nextPowerOfTwo(tagBytes)
        }
        return tagBytes
    }

    private static func nextPowerOfTwo(_ value: Int) -> Int {
        var v = max(1, value)
        v -= 1
        v |= v >> 1
        v |= v >> 2
        v |= v >> 4
        v |= v >> 8
        v |= v >> 16
        if Int.bitWidth > 32 {
            v |= v >> 32
        }
        return v + 1
    }

    private static func encodeExtraTagBytes(_ value: Int, byteCount: Int) -> [UInt8] {
        guard byteCount > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        var tempValue = value
        for i in 0 ..< byteCount {
            bytes[i] = UInt8(tempValue & 0xFF)
            tempValue = safeShiftRight(tempValue, 8)
        }
        return bytes
    }

    private static func buildMeaningfulPayloadMask(
        payloadValueBitsMask: BitMask,
        bitsRequired: Int
    ) -> BitMask {
        var meaningfulPayloadMask = BitMask(sizeInBytes: payloadValueBitsMask.size)
        meaningfulPayloadMask.makeZero()

        guard bitsRequired > 0 else { return meaningfulPayloadMask }

        var currentMeaningfulBits = 0
        for i in 0 ..< payloadValueBitsMask.size {
            let byte = payloadValueBitsMask[byteAt: i]
            if byte == 0 { continue }
            var newByte: UInt8 = 0
            for b in 0 ..< 8 {
                if (byte & (1 << b)) != 0 {
                    if currentMeaningfulBits < bitsRequired {
                        newByte |= (1 << b)
                        currentMeaningfulBits += 1
                    }
                }
            }
            meaningfulPayloadMask[byteAt: i] = newByte
            if currentMeaningfulBits >= bitsRequired {
                break
            }
        }

        return meaningfulPayloadMask
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

    private static func addExtraTagBytes(
        changes: [Int: UInt8],
        extraTagBytes: [UInt8],
        offset: Int
    ) -> [Int: UInt8] {
        guard !extraTagBytes.isEmpty else { return changes }
        var result = changes
        for i in 0 ..< extraTagBytes.count {
            result[offset + i] = extraTagBytes[i]
        }
        return result
    }
}
