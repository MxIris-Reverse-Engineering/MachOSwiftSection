import Foundation

public enum EnumLayoutCalculator {
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
            let hexIndex = String(format: "0x%02X", caseIndex)
            var output = "Case \(caseIndex) (\(hexIndex)) - \(caseName):\n"
            output += "  [Logic] Tag: \(tagValue)"
            if payloadValue > 0 {
                output += ", PayloadVal: \(payloadValue)"
            }
            output += "\n"

            if memoryChanges.isEmpty {
                output += "  -> (No bits set / Zero)\n"
            } else {
                for offset in memoryChanges.keys.sorted() {
                    let byteVal = memoryChanges[offset]!
                    let byteHex = String(format: "0x%02X", byteVal)
                    let binaryStr = String(byteVal, radix: 2)
                    let padding = String(repeating: "0", count: 8 - binaryStr.count)
                    output += "  -> Memory Offset \(offset) = \(byteHex) (Bin: \(padding + binaryStr))\n"
                }
            }
            return output
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

    public static func calculateMultiPayload(
        payloadSize: Int,
        spareBytes: [UInt8],
        spareBytesOffset: Int,
        numPayloadCases: Int,
        numEmptyCases: Int
    ) throws -> LayoutResult {
        // 1. Construct CommonSpareBits
        var commonSpareBits = BitMask(sizeInBytes: payloadSize)
        commonSpareBits.makeZero()
        // Note: makeZero implies 'occupied' for regions not covered by spareBytes input
        if spareBytesOffset < payloadSize {
            let copyLength = min(spareBytes.count, payloadSize - spareBytesOffset)
            for i in 0 ..< copyLength {
                commonSpareBits[byteAt: spareBytesOffset + i] = spareBytes[i]
            }
        }

        // 2. Calculate Tag Counts
        let commonSpareBitCount = commonSpareBits.countSetBits()
        let usedBitCount = commonSpareBits.size * 8 - commonSpareBitCount

        var numEmptyElementTags = 0
        if numEmptyCases > 0 {
            if usedBitCount >= 32 {
                numEmptyElementTags = 1
            } else {
                let emptyElementsPerTag = 1 << usedBitCount
                numEmptyElementTags = (numEmptyCases + emptyElementsPerTag - 1) / emptyElementsPerTag
            }
        }

        let numTags = numPayloadCases + numEmptyElementTags

        // 3. Calculate Bits Needed for Tag
        var numTagBits = 0
        if numTags > 1 {
            var temp = numTags - 1
            while temp > 0 {
                temp >>= 1; numTagBits += 1
            }
        }

        // 4. Separate Tag Bits and Payload Value Bits
        var payloadTagBitsMask = commonSpareBits
        payloadTagBitsMask.keepOnlyMostSignificantBits(numTagBits)

        if payloadTagBitsMask.countSetBits() < numTagBits {
            throw LayoutError.notEnoughSpareBits(needed: numTagBits, available: payloadTagBitsMask.countSetBits())
        }

        var payloadValueBitsMask = commonSpareBits
        payloadValueBitsMask.invert() // All Occupied Bits
        let numPayloadValueBits = payloadValueBitsMask.countSetBits()

        // --- Fix for "Meaningful Bytes" ---
        // We only want to display bytes that are actually reachable by the max empty index.
        // e.g., if we need 4 bits for indices, we only care about the first 4 occupied bits in the mask.
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
        // ----------------------------------

        var cases: [EnumCaseProjection] = []

        // A. Payload Cases
        for i in 0 ..< numPayloadCases {
            let tagVal = i
            let memBytes = payloadTagBitsMask.scatterBits(value: tagVal)

            cases.append(
                EnumCaseProjection(
                    caseIndex: i,
                    caseName: "Payload Case \(i)",
                    tagValue: tagVal,
                    payloadValue: 0,
                    memoryChanges: extractChanges(from: memBytes, showMask: payloadTagBitsMask)
                )
            )
        }

        // B. Empty Cases
        if numEmptyCases > 0 {
            for i in 0 ..< numEmptyCases {
                let globalIndex = numPayloadCases + i
                let emptyIndex = i

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

                cases.append(
                    EnumCaseProjection(
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
                )
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

    public static func calculateTaggedMultiPayload(
        payloadSize: Int,
        numPayloadCases: Int,
        numEmptyCases: Int
    ) -> LayoutResult {
        let numTags = numPayloadCases + numEmptyCases
        let numTagBytes: Int
        if numTags <= 1 { numTagBytes = 0 }
        else if numTags < 256 { numTagBytes = 1 }
        else if numTags < 65536 { numTagBytes = 2 }
        else { numTagBytes = 4 }

        let bitsNeeded = numTagBytes * 8
        let tagOffset = payloadSize

        let region = SpareRegion(
            range: tagOffset ..< (tagOffset + numTagBytes),
            bitCount: bitsNeeded,
            bytes: [UInt8](repeating: 0xFF, count: numTagBytes)
        )

        var cases: [EnumCaseProjection] = []

        for tagVal in 0 ..< numTags {
            var memoryChanges: [Int: UInt8] = [:]
            var tempTag = tagVal
            for i in 0 ..< numTagBytes {
                memoryChanges[tagOffset + i] = UInt8(tempTag & 0xFF)
                tempTag >>= 8
            }

            let isPayload = tagVal < numPayloadCases
            let name = isPayload ? "Payload Case \(tagVal)" : "Empty Case \(tagVal - numPayloadCases)"

            cases.append(EnumCaseProjection(
                caseIndex: tagVal,
                caseName: name,
                tagValue: tagVal,
                payloadValue: 0,
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

    public static func calculateSinglePayload(
        size: Int,
        payloadSize: Int,
        numEmptyCases: Int
    ) -> LayoutResult {
        let numTags = numEmptyCases + 1

        if size > payloadSize {
            let extraTagBytes = size - payloadSize
            let bitsNeeded = extraTagBytes * 8

            let region = SpareRegion(
                range: payloadSize ..< size,
                bitCount: bitsNeeded,
                bytes: [UInt8](repeating: 0xFF, count: extraTagBytes)
            )

            var cases: [EnumCaseProjection] = []

            var payloadMem: [Int: UInt8] = [:]
            for i in 0 ..< extraTagBytes {
                payloadMem[payloadSize + i] = 0
            }
            cases.append(
                EnumCaseProjection(
                    caseIndex: 0,
                    caseName: "Payload Case",
                    tagValue: 0,
                    payloadValue: 0,
                    memoryChanges: payloadMem
                )
            )

            let casesToShow = min(numEmptyCases, 5)
            for i in 1 ... casesToShow {
                var mem: [Int: UInt8] = [:]
                var tempTag = i
                for b in 0 ..< extraTagBytes {
                    mem[payloadSize + b] = UInt8(tempTag & 0xFF)
                    tempTag >>= 8
                }
                cases.append(
                    EnumCaseProjection(
                        caseIndex: i,
                        caseName: "Empty Case \(i - 1)",
                        tagValue: i,
                        payloadValue: 0,
                        memoryChanges: mem
                    )
                )
            }

            return LayoutResult(
                strategyDescription: "Single Payload (Extra Tag)",
                bitsNeededForTag: bitsNeeded,
                bitsAvailableForPayload: 0,
                numTags: numTags,
                tagRegion: region,
                payloadRegion: nil,
                cases: cases
            )

        } else {
            return LayoutResult(
                strategyDescription: "Single Payload (Extra Inhabitants)",
                bitsNeededForTag: 0,
                bitsAvailableForPayload: 0,
                numTags: numTags,
                tagRegion: nil,
                payloadRegion: nil,
                cases: [
                    EnumCaseProjection(caseIndex: 0, caseName: "Payload Case (Valid Value)", tagValue: -1, payloadValue: 0, memoryChanges: [:]),
                    EnumCaseProjection(caseIndex: 1, caseName: "Empty Case 0 (Uses XI #0)", tagValue: 0, payloadValue: 0, memoryChanges: [:]),
                ]
            )
        }
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

    /// Extract changes filtering for meaningful bytes only.
    /// A byte is meaningful if it is part of the Tag OR if it falls within the `meaningfulPayloadMask`
    /// (which represents the occupied bits actually needed to store the max empty index).
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
