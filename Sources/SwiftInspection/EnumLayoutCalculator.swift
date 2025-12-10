import Foundation

// MARK: - Public API

public enum EnumLayoutCalculator {
    /// 计算枚举 Tag 在内存中的布局
    /// - Parameters:
    ///   - spareBytes: Spare Bits 原始字节数组 (Mask)
    ///   - startOffset: Mask 相对于 Payload 的起始偏移量
    ///   - numTags: 需要表示的 Tag 数量 (Payload Cases + Empty Cases)
    /// - Returns: 计算结果，包含选中的 Region 和每个 Tag 的内存表示
    public static func calculate(spareBytes: [UInt8], startOffset: Int, numTags: Int) throws -> EnumLayoutResult {
        // 1. 计算所需位数
        let bitsNeeded = Int(ceil(log2(Double(numTags))))

        // 2. 识别所有连续的 Spare Regions
        let regions = findSpareRegions(bytes: spareBytes, startOffset: startOffset)

        // 3. 筛选并选择最佳 Region
        // 策略：选择第一个容量足够 (>= bitsNeeded) 的 Region
        guard let selectedRegion = regions.first(where: { $0.bitCount >= bitsNeeded }) else {
            throw LayoutError.insufficientSpareBits(needed: bitsNeeded, availableRegions: regions)
        }

        // 4. 在选中的 Region 中确定 Tag 的物理位 (MSB 策略)
        let targetSlots = getTargetSlots(region: selectedRegion, count: bitsNeeded)

        // 5. 计算每个 Tag 的内存表示
        var tagLayouts: [TagMemoryRepresentation] = []
        for tagValue in 0 ..< numTags {
            let layout = computeTagMemory(tagValue: tagValue, targetSlots: targetSlots)
            tagLayouts.append(layout)
        }

        return EnumLayoutResult(
            bitsNeeded: bitsNeeded,
            selectedRegion: selectedRegion,
            tagLayouts: tagLayouts
        )
    }

    // MARK: - Errors

    public enum LayoutError: Error, CustomStringConvertible {
        case insufficientSpareBits(needed: Int, availableRegions: [SpareRegion])

        public var description: String {
            switch self {
            case .insufficientSpareBits(let needed, let regions):
                return "Insufficient spare bits! Need \(needed), but available regions are: \(regions.map { "\($0.bitCount) bits at \($0.range)" })"
            }
        }
    }
}

// MARK: - Data Structures

public struct SpareRegion: CustomStringConvertible, Sendable {
    public let range: Range<Int>
    public let bitCount: Int
    public let bytes: [UInt8]

    public var description: String {
        return "Offset \(range) (Capacity: \(bitCount) bits)"
    }
}

public struct TagMemoryRepresentation: CustomStringConvertible {
    public let tagIndex: Int
    /// 键是内存偏移量 (Offset)，值是该字节的内容 (Byte)
    public let memoryChanges: [Int: UInt8]

    public var description: String {
        let hexValue = String(format: "0x%02X", tagIndex)
        var output = "Tag \(tagIndex) (\(hexValue)):\n"

        let sortedOffsets = memoryChanges.keys.sorted()
        for offset in sortedOffsets {
            let byteVal = memoryChanges[offset]!
            let byteHex = String(format: "0x%02X", byteVal)
            let binaryStr = String(byteVal, radix: 2)
            let padding = String(repeating: "0", count: 8 - binaryStr.count)
            let displayBinary = padding + binaryStr

            output += "  -> Memory Offset \(offset) = \(byteHex) (Bin: \(displayBinary))\n"
        }
        return output
    }
}

public struct EnumLayoutResult: CustomStringConvertible {
    public let bitsNeeded: Int
    public let selectedRegion: SpareRegion
    public let tagLayouts: [TagMemoryRepresentation]

    public var description: String {
        var output = "=== Enum Layout Result ===\n"
        output += "Bits Needed: \(bitsNeeded)\n"
        output += "Selected Region: \(selectedRegion)\n"
        output += "--------------------------\n"
        for layout in tagLayouts {
            output += layout.description
        }
        output += "=========================="
        return output
    }
}

// MARK: - Private Helpers

extension EnumLayoutCalculator {
    private static func findSpareRegions(bytes: [UInt8], startOffset: Int) -> [SpareRegion] {
        var regions: [SpareRegion] = []
        var currentStart: Int?
        var currentBits = 0
        var currentBytes: [UInt8] = []

        for (i, byte) in bytes.enumerated() {
            let offset = startOffset + i
            if byte != 0 {
                if currentStart == nil { currentStart = offset }
                currentBits += byte.nonzeroBitCount
                currentBytes.append(byte)
            } else {
                if let start = currentStart {
                    regions.append(SpareRegion(range: start ..< offset, bitCount: currentBits, bytes: currentBytes))
                    currentStart = nil
                    currentBits = 0
                    currentBytes = []
                }
            }
        }
        if let start = currentStart {
            regions.append(SpareRegion(range: start ..< (startOffset + bytes.count), bitCount: currentBits, bytes: currentBytes))
        }
        return regions
    }

    private static func getTargetSlots(region: SpareRegion, count: Int) -> [(offset: Int, bit: Int)] {
        var slots: [(offset: Int, bit: Int)] = []

        for (i, byte) in region.bytes.enumerated() {
            let absOffset = region.range.lowerBound + i
            for b in 0 ..< 8 {
                if (byte & (1 << b)) != 0 {
                    slots.append((offset: absOffset, bit: b))
                }
            }
        }

        return Array(slots.suffix(count))
    }

    private static func computeTagMemory(tagValue: Int, targetSlots: [(offset: Int, bit: Int)]) -> TagMemoryRepresentation {
        var memoryChanges: [Int: UInt8] = [:]

        for (i, slot) in targetSlots.enumerated() {
            let bitValue = (tagValue >> i) & 1

            if bitValue == 1 {
                let currentByte = memoryChanges[slot.offset] ?? 0
                memoryChanges[slot.offset] = currentByte | (1 << slot.bit)
            } else {
                if memoryChanges[slot.offset] == nil {
                    memoryChanges[slot.offset] = 0
                }
            }
        }

        return TagMemoryRepresentation(tagIndex: tagValue, memoryChanges: memoryChanges)
    }
}
