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

            if memoryChanges.isEmpty {
                output += "\(indentString)\(prefix) (No bits set / Zero)\n"
            } else {
                for offset in memoryChanges.keys.sorted() {
                    let byteValue = memoryChanges[offset]!
                    let byteHex = String(format: "0x%02X", byteValue)
                    let binaryStr = String(byteValue, radix: 2)
                    let padding = String(repeating: "0", count: 8 - binaryStr.count)
                    output += "\(indentString)\(prefix) Memory Offset \(offset) (\(String(format: "0x%02X", offset))) = \(byteHex) (Bin: \(padding + binaryStr))\n"
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
        var commonSpareBits = BitMask(sizeInBytes: payloadSize)
        commonSpareBits.makeZero()

        if spareBytesOffset < payloadSize {
            let copyLength = min(spareBytes.count, payloadSize - spareBytesOffset)
            for i in 0 ..< copyLength {
                commonSpareBits[byteAt: spareBytesOffset + i] = spareBytes[i]
            }
        }

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

        var numTagBits = 0
        if numTags > 1 {
            var temp = numTags - 1
            while temp > 0 {
                temp >>= 1; numTagBits += 1
            }
        }

        var payloadTagBitsMask = commonSpareBits
        payloadTagBitsMask.keepOnlyMostSignificantBits(numTagBits)

        if payloadTagBitsMask.countSetBits() < numTagBits {
            throw LayoutError.notEnoughSpareBits(needed: numTagBits, available: payloadTagBitsMask.countSetBits())
        }

        var payloadValueBitsMask = commonSpareBits
        payloadValueBitsMask.invert()
        let numPayloadValueBits = payloadValueBitsMask.countSetBits()

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

        // A. Payload Cases
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

    public static func calculateTaggedMultiPayload(
        payloadSize: Int,
        numPayloadCases: Int,
        numEmptyCases: Int
    ) -> LayoutResult {
        // 1. Calculate correct Number of Tags based on Payload Capacity
        //
        var numTags = numPayloadCases
        if numEmptyCases > 0 {
            if payloadSize >= 4 {
                // If payload is large enough (>= 32 bits), we only need 1 extra tag
                // to cover all empty cases (up to 4 billion).
                numTags += 1
            } else {
                // If payload is small, we calculate how many tags are needed to cover empty cases.
                let bits = payloadSize * 8
                let capacityPerTag = 1 << bits
                let emptyTags = (numEmptyCases + capacityPerTag - 1) / capacityPerTag
                numTags += emptyTags
            }
        }

        // Enum.h: getEnumTagCounts
        let numTagBytes: Int
        if numTags <= 1 { numTagBytes = 0 }
        else if numTags < 256 { numTagBytes = 1 }
        else if numTags < 65536 { numTagBytes = 2 }
        else { numTagBytes = 4 }

        let bitsNeeded = numTagBytes * 8
        let tagOffset = payloadSize

        // Virtual mask for the extra tag region
        let region = SpareRegion(
            range: tagOffset ..< (tagOffset + numTagBytes),
            bitCount: bitsNeeded,
            bytes: [UInt8](repeating: 0xFF, count: numTagBytes)
        )

        // Calculate a mask to determine which payload bytes are meaningful for empty cases.
        // We don't want to show random 0s in high bytes if the index is small.
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
                // Logic: Tag = CaseIndex
                tagValue = caseIndex
                payloadValue = 0
            } else {
                // --- Empty Case ---
                // Logic:
                let emptyIndex = caseIndex - numPayloadCases

                if payloadSize >= 4 {
                    // Use a single separate tag, store index in payload
                    tagValue = numPayloadCases
                    payloadValue = emptyIndex
                } else {
                    // Spread empty cases across multiple tags
                    let bits = payloadSize * 8
                    tagValue = numPayloadCases + (emptyIndex >> bits)
                    payloadValue = emptyIndex & ((1 << bits) - 1)
                }
            }

            // 1. Write Tag Bytes
            var tempTag = tagValue
            for b in 0 ..< numTagBytes {
                memoryChanges[tagOffset + b] = UInt8(tempTag & 0xFF)
                tempTag >>= 8
            }

            // 2. Write Payload Bytes (Only for Empty Cases)
            // Payload cases have their own data, but here we are just projecting the enum structure.
            if caseIndex >= numPayloadCases {
                var tempPayload = payloadValue
                for b in 0 ..< payloadSize {
                    let byteVal = UInt8(tempPayload & 0xFF)
                    // Only show byte if it's within the meaningful range for the index
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
            bitsAvailableForPayload: 0, // Payload is used for Index, not free bits
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
        numEmptyCases: Int,
        spareBytes: [UInt8] = [],
        spareBytesOffset: Int = 0
    ) -> LayoutResult {
        // [Fix 1] 准备 Spare Bits Mask
        var spareBitMask = BitMask.zeroMask(sizeInBytes: payloadSize)
        if !spareBytes.isEmpty {
            let copyLen = min(spareBytes.count, payloadSize - spareBytesOffset)
            for i in 0 ..< copyLen {
                spareBitMask[byteAt: spareBytesOffset + i] = spareBytes[i]
            }
        }

        let totalSpareBits = spareBitMask.countSetBits()

        // [Fix 2] 计算 Extra Inhabitants (XI) 容量
        // Swift 运行时限制 XI 最多使用 32 位 spare bits
        let usableSpareBits = min(totalSpareBits, 32)
        let maxXI = (usableSpareBits >= 32) ? Int.max : (1 << usableSpareBits) - 1

        // [Fix 3] 混合策略：优先 XI，溢出用 Tag
        let numXICases = min(numEmptyCases, maxXI)
        let numOverflowCases = numEmptyCases - numXICases

        // [Fix 4] 计算 Extra Tag 需求
        var extraTagBytes = 0
        if numOverflowCases > 0 {
            let capacityPerTag: Int
            if payloadSize >= 8 {
                // 64位系统下，8字节能存下所有 Int 索引，容量视为无限
                capacityPerTag = Int.max
            } else {
                // 1 << 64 会导致崩溃，所以上面处理了 >= 8 的情况
                // 这里处理 0...7 字节的情况
                capacityPerTag = 1 << (payloadSize * 8)
            }

            // Tag 0 保留给 Payload/XI。溢出从 Tag 1 开始。
            // 这是一个安全的向上取整除法：ceil(numOverflowCases / capacityPerTag)
            let tagsNeededForOverflow = (numOverflowCases / capacityPerTag) + (numOverflowCases % capacityPerTag > 0 ? 1 : 0)

            let totalTagsIndices = 1 + tagsNeededForOverflow

            if totalTagsIndices <= 256 { extraTagBytes = 1 }
            else if totalTagsIndices <= 65536 { extraTagBytes = 2 }
            else { extraTagBytes = 4 }
        } else if size > payloadSize {
            // Padding (虽然不需要 Tag 区分，但物理空间存在)
            extraTagBytes = size - payloadSize
        }

        // 逻辑上的总 Tag 数（用于 LayoutResult 统计）
        let numTags = 1 + numEmptyCases

        var cases: [EnumCaseProjection] = []

        // --- A. Payload Case ---
        cases.append(EnumCaseProjection(
            caseIndex: 0,
            caseName: "Payload Case (Valid)",
            tagValue: 0,
            payloadValue: 0,
            memoryChanges: [:]
        ))

        // --- B. XI Cases ---
        if numXICases > 0 {
            // XI 掩码计算需要准确
            var xiMask = spareBitMask
            xiMask.keepOnlyLeastSignificantBytes(payloadSize)

            for i in 0 ..< numXICases {
                let xiIndex = i
                // Swift XI 逻辑: ~index 映射到 spare bits
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

        // --- C. Overflow Cases (Tag + Payload) ---
        if numOverflowCases > 0 {
            let startEmptyIndex = numXICases

            for i in 0 ..< numOverflowCases {
                let overflowIndex = i
                let globalEmptyIndex = startEmptyIndex + i

                let tagValue: Int
                let payloadVal: Int

                // [Fix 6] 核心修复：Payload 复用 & 安全计算
                if payloadSize >= 8 {
                    // Payload 足够大，直接存所有索引
                    tagValue = 1
                    payloadVal = overflowIndex
                } else {
                    let payloadBits = payloadSize * 8
                    let capacity = 1 << payloadBits

                    payloadVal = overflowIndex & (capacity - 1)
                    tagValue = 1 + (overflowIndex >> payloadBits)
                }

                var mem: [Int: UInt8] = [:]

                // 写 Tag
                if extraTagBytes > 0 {
                    var t = tagValue
                    for b in 0 ..< extraTagBytes {
                        mem[payloadSize + b] = UInt8(t & 0xFF)
                        t >>= 8
                    }
                }

                // 写 Payload (即使是 Spare Bits 也会被覆盖用于存索引)
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
            numTags: numTags, // 使用了之前定义的变量
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
