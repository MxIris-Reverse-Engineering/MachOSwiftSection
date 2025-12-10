// import Foundation
//
// extension EnumLayoutCalculator {
//    // MARK: - Data Structures
//
//    public struct SpareRegion: CustomStringConvertible, Sendable {
//        public let range: Range<Int>
//        public let bitCount: Int
//        public let bytes: [UInt8]
//
//        public var description: String {
//            return "Offset \(range) (Capacity: \(bitCount) bits)"
//        }
//    }
//
//    public struct TagMemoryRepresentation: CustomStringConvertible, Sendable {
//        public let tagIndex: Int
//        /// Key is the memory offset, Value is the byte content
//        public let memoryChanges: [Int: UInt8]
//
//        public var description: String {
//            let hexValue = String(format: "0x%02X", tagIndex)
//            var output = "Tag \(tagIndex) (\(hexValue)):\n"
//
//            let sortedOffsets = memoryChanges.keys.sorted()
//            for offset in sortedOffsets {
//                let byteVal = memoryChanges[offset]!
//                let byteHex = String(format: "0x%02X", byteVal)
//                let binaryStr = String(byteVal, radix: 2)
//                let padding = String(repeating: "0", count: 8 - binaryStr.count)
//                let displayBinary = padding + binaryStr
//
//                output += "  -> Memory Offset \(offset) = \(byteHex) (Bin: \(displayBinary))\n"
//            }
//            return output
//        }
//    }
//
//    public struct EnumLayoutResult: CustomStringConvertible, Sendable {
//        public let bitsNeeded: Int
//        public let selectedRegion: SpareRegion
//        public let tagLayouts: [TagMemoryRepresentation]
//        public let strategyDescription: String // Added to distinguish strategies
//
//        public init(bitsNeeded: Int, selectedRegion: SpareRegion, tagLayouts: [TagMemoryRepresentation], strategyDescription: String = "Spare Bits") {
//            self.bitsNeeded = bitsNeeded
//            self.selectedRegion = selectedRegion
//            self.tagLayouts = tagLayouts
//            self.strategyDescription = strategyDescription
//        }
//
//        public var description: String {
//            var output = "=== Enum Layout Result (\(strategyDescription)) ===\n"
//            output += "Bits Needed: \(bitsNeeded)\n"
//            output += "Selected Region: \(selectedRegion)\n"
//            output += "--------------------------\n"
//            for layout in tagLayouts {
//                output += layout.description
//            }
//            output += "=========================="
//            return output
//        }
//    }
// }
//
//// MARK: - Public API
//
// public enum EnumLayoutCalculator {
//    /// Calculates the memory layout of enum tags based on spare bits.
//    ///
//    /// This method implements the Swift Runtime's strategy for allocating tags in Multi-Payload Enums:
//    /// 1. Identifies contiguous regions of spare bits.
//    /// 2. Selects the "best" region (Largest Capacity > Lowest Offset).
//    /// 3. Allocates tags using the Most Significant Bits (MSB) of that region.
//    ///
//    /// - Parameters:
//    ///   - spareBytes: The raw byte array of Spare Bits (Mask).
//    ///   - startOffset: The starting offset of the mask relative to the Payload.
//    ///   - numTags: The number of tags required (Payload Cases + Empty Cases).
//    /// - Returns: The calculation result containing the selected region and memory representation for each tag.
//    /// - Throws: `LayoutError` if there are insufficient spare bits.
//    public static func calculateMultiPayload(spareBytes: [UInt8], startOffset: Int, numTags: Int) throws -> EnumLayoutResult {
//        // 1. Calculate required bits
//        let bitsNeeded = Int(ceil(log2(Double(numTags))))
//
//        // 2. Identify all contiguous Spare Regions
//        let regions = findSpareRegions(bytes: spareBytes, startOffset: startOffset)
//
//        // 3. Filter and select the best Region
//        // Strategy:
//        //  a. Filter regions that have enough capacity.
//        //  b. Sort by Capacity (Descending) - Swift prefers the largest available space.
//        //  c. Sort by Offset (Ascending) - If capacities are equal, prefer the earlier offset.
//        let validRegions = regions.filter { $0.bitCount >= bitsNeeded }
//
//        let sortedRegions = validRegions.sorted { lhs, rhs in
//            if lhs.bitCount != rhs.bitCount {
//                return lhs.bitCount > rhs.bitCount // Larger capacity is better
//            }
//            return lhs.range.lowerBound < rhs.range.lowerBound // Lower offset is better
//        }
//
//        guard let selectedRegion = sortedRegions.first else {
//            throw LayoutError.insufficientSpareBits(needed: bitsNeeded, availableRegions: regions)
//        }
//
//        // 4. Determine the physical bits for the Tag within the selected Region (MSB Strategy)
//        // We take the last 'bitsNeeded' slots from the region (which corresponds to the highest available bits).
//        let targetSlots = getTargetSlots(region: selectedRegion, count: bitsNeeded)
//
//        // 5. Calculate memory representation for each Tag
//        var tagLayouts: [TagMemoryRepresentation] = []
//        for tagValue in 0 ..< numTags {
//            let layout = computeTagMemory(tagValue: tagValue, targetSlots: targetSlots)
//            tagLayouts.append(layout)
//        }
//
//        return EnumLayoutResult(
//            bitsNeeded: bitsNeeded,
//            selectedRegion: selectedRegion,
//            tagLayouts: tagLayouts
//        )
//    }
//
//    // MARK: - Errors
//
//    public enum LayoutError: Error, CustomStringConvertible {
//        case insufficientSpareBits(needed: Int, availableRegions: [SpareRegion])
//
//        public var description: String {
//            switch self {
//            case .insufficientSpareBits(let needed, let regions):
//                return "Insufficient spare bits! Need \(needed), but available regions are: \(regions.map { "\($0.bitCount) bits at \($0.range)" })"
//            }
//        }
//    }
// }
//
// extension EnumLayoutCalculator {
//    /// Calculates the layout for a **Single Payload Enum** (e.g., `Optional<T>`).
//    ///
//    /// Logic based on `swift_initEnumMetadataSinglePayload` in `Enum.cpp`.
//    ///
//    /// - Parameters:
//    ///   - payloadSize: The size of the payload in bytes.
//    ///   - payloadExtraInhabitants: The number of "extra inhabitants" (invalid values) the payload type has (e.g., Bool has 254, Pointers have many).
//    ///   - emptyCases: The number of empty cases (e.g., `nil` is 1 empty case).
//    /// - Returns: The layout result.
//    public static func calculateSinglePayload(
//        payloadSize: Int,
//        payloadExtraInhabitants: Int,
//        emptyCases: Int
//    ) -> EnumLayoutResult {
//        // 1. Check if we can fit the empty cases into the payload's extra inhabitants.
//        // Logic from Enum.cpp: if (payloadNumExtraInhabitants >= emptyCases)
//        if payloadExtraInhabitants >= emptyCases {
//            // Case A: No extra memory needed. The tag is encoded inside the payload's invalid values.
//            // Since we cannot simulate the exact bit patterns of the payload's XIs without knowing the specific type (Pointer vs Bool),
//            // we return a result indicating the payload itself is the container.
//
//            let region = SpareRegion(range: 0 ..< payloadSize, bitCount: 0, bytes: [])
//
//            // We generate a placeholder representation
//            var layouts: [TagMemoryRepresentation] = []
//
//            // Payload Case (Index 0)
//            layouts.append(TagMemoryRepresentation(tagIndex: 0, memoryChanges: [:])) // Valid Payload
//
//            // Empty Cases (Index 1...N)
//            // We mark them as "Internal XI" for visualization purposes
//            for i in 1 ... emptyCases {
//                layouts.append(TagMemoryRepresentation(tagIndex: i, memoryChanges: [0: 0xFF])) // Placeholder
//            }
//
//            return EnumLayoutResult(
//                bitsNeeded: 0,
//                selectedRegion: region,
//                tagLayouts: layouts,
//                strategyDescription: "Single Payload (Internal Extra Inhabitants)"
//            )
//        }
//
//        // Case B: Extra inhabitants are insufficient. We must append an extra tag.
//        // Logic from Enum.cpp: size = payloadSize + getEnumTagCounts(...).numTagBytes
//        let extraCasesToEncode = emptyCases - payloadExtraInhabitants
//        let tagBytesNeeded = getEnumTagCounts(payloadSize: payloadSize, emptyCases: extraCasesToEncode, payloadCases: 1)
//
//        let tagOffset = payloadSize
//        let region = SpareRegion(
//            range: tagOffset ..< (tagOffset + tagBytesNeeded),
//            bitCount: tagBytesNeeded * 8,
//            bytes: Array(repeating: 0x00, count: tagBytesNeeded)
//        )
//
//        var layouts: [TagMemoryRepresentation] = []
//
//        // 0 is the Payload Case
//        layouts.append(TagMemoryRepresentation(tagIndex: 0, memoryChanges: [tagOffset: 0x00]))
//
//        // 1...N are Empty Cases
//        // Logic from EnumImpl.h: storeEnumTagSinglePayloadImpl
//        // The tag value starts counting from 1 for the first empty case that couldn't fit in XIs.
//        for i in 1 ... emptyCases {
//            // If this empty case could fit in XI, it wouldn't use the extra tag (it would be 0).
//            // But for visualization here, we assume we are visualizing the cases that *require* the tag.
//            // The tag value is roughly (index - XIs).
//
//            // Simplified visualization:
//            // Payload = 0x00
//            // Empty Case 1 = 0x01
//            // ...
//            let tagValue = i
//            var changes: [Int: UInt8] = [:]
//
//            // Write tag value into the appended bytes
//            for byteIdx in 0 ..< tagBytesNeeded {
//                let val = UInt8((tagValue >> (byteIdx * 8)) & 0xFF)
//                changes[tagOffset + byteIdx] = val
//            }
//            layouts.append(TagMemoryRepresentation(tagIndex: i, memoryChanges: changes))
//        }
//
//        return EnumLayoutResult(
//            bitsNeeded: tagBytesNeeded * 8,
//            selectedRegion: region,
//            tagLayouts: layouts,
//            strategyDescription: "Single Payload (Extra Tag)"
//        )
//    }
//
//    /// Calculates the layout for a **Tagged Multi-Payload Enum** (No Spare Bits).
//    ///
//    /// This is used when payloads don't have common spare bits, or the compiler decides to use a separate tag.
//    /// Logic based on `swift_initEnumMetadataMultiPayload` (fallback path) and `TaggedMultiPayloadEnumTypeInfo`.
//    ///
//    /// - Parameters:
//    ///   - payloadSize: The size of the largest payload.
//    ///   - numTags: Total number of cases (Payload Cases + Empty Cases).
//    /// - Returns: The layout result.
//    public static func calculateTaggedMultiPayload(
//        payloadSize: Int,
//        numTags: Int
//    ) -> EnumLayoutResult {
//        // 1. Calculate required tag bytes
//        // Logic from Enum.cpp: getEnumTagCounts
//        // For MPE, we treat all cases as needing a tag value.
//        let tagBytesNeeded = getEnumTagCounts(payloadSize: payloadSize, emptyCases: numTags, payloadCases: 0)
//
//        // 2. The tag is appended AFTER the payload
//        let tagOffset = payloadSize
//
//        let region = SpareRegion(
//            range: tagOffset ..< (tagOffset + tagBytesNeeded),
//            bitCount: tagBytesNeeded * 8,
//            bytes: Array(repeating: 0x00, count: tagBytesNeeded)
//        )
//
//        var layouts: [TagMemoryRepresentation] = []
//
//        // 3. Calculate values
//        // In a Tagged MPE, the tag simply enumerates the cases: 0, 1, 2...
//        for tagValue in 0 ..< numTags {
//            var changes: [Int: UInt8] = [:]
//
//            // Write tag value into the appended bytes (Little Endian)
//            for byteIdx in 0 ..< tagBytesNeeded {
//                let val = UInt8((tagValue >> (byteIdx * 8)) & 0xFF)
//                changes[tagOffset + byteIdx] = val
//            }
//
//            layouts.append(TagMemoryRepresentation(tagIndex: tagValue, memoryChanges: changes))
//        }
//
//        return EnumLayoutResult(
//            bitsNeeded: tagBytesNeeded * 8,
//            selectedRegion: region,
//            tagLayouts: layouts,
//            strategyDescription: "Multi-Payload (Tagged / No Spare Bits)"
//        )
//    }
//
//    // MARK: - Internal Helper for Tag Counts
//
//    /// Replicates `getEnumTagCounts` from `Enum.cpp`.
//    /// Determines how many bytes are needed for the tag based on payload size and number of cases.
//    private static func getEnumTagCounts(payloadSize: Int, emptyCases: Int, payloadCases: Int) -> Int {
//        // Logic simplified from Swift Runtime:
//        // If payloadSize >= 4, we can usually fit a huge number of empty cases in 1 byte + payload area reuse.
//        // But strictly for the *Extra Tag* size:
//
//        let totalCases = UInt64(emptyCases) + UInt64(payloadCases)
//
//        if totalCases <= 1 { return 0 } // Should not happen in this context
//        if totalCases <= 256 { return 1 }
//        if totalCases <= 65536 { return 2 }
//        if totalCases <= 4294967296 { return 4 }
//        return 8
//    }
// }
//
//// MARK: - Private Helpers
//
// extension EnumLayoutCalculator {
//    /// Scans the byte array to find contiguous regions of non-zero spare bits.
//    private static func findSpareRegions(bytes: [UInt8], startOffset: Int) -> [SpareRegion] {
//        var regions: [SpareRegion] = []
//        var currentStart: Int?
//        var currentBits = 0
//        var currentBytes: [UInt8] = []
//
//        for (i, byte) in bytes.enumerated() {
//            let offset = startOffset + i
//            if byte != 0 {
//                if currentStart == nil { currentStart = offset }
//                currentBits += byte.nonzeroBitCount
//                currentBytes.append(byte)
//            } else {
//                if let start = currentStart {
//                    regions.append(SpareRegion(range: start ..< offset, bitCount: currentBits, bytes: currentBytes))
//                    currentStart = nil
//                    currentBits = 0
//                    currentBytes = []
//                }
//            }
//        }
//        // Handle the case where the region extends to the end of the array
//        if let start = currentStart {
//            regions.append(SpareRegion(range: start ..< (startOffset + bytes.count), bitCount: currentBits, bytes: currentBytes))
//        }
//        return regions
//    }
//
//    /// Extracts the specific physical bits (Offset + BitIndex) to be used for the Tag.
//    /// Returns the *last* `count` bits available in the region (MSB strategy).
//    private static func getTargetSlots(region: SpareRegion, count: Int) -> [(offset: Int, bit: Int)] {
//        var slots: [(offset: Int, bit: Int)] = []
//
//        // Iterate bytes from low address to high address
//        for (i, byte) in region.bytes.enumerated() {
//            let absOffset = region.range.lowerBound + i
//            // Iterate bits from LSB (0) to MSB (7)
//            for b in 0 ..< 8 {
//                if (byte & (1 << b)) != 0 {
//                    slots.append((offset: absOffset, bit: b))
//                }
//            }
//        }
//
//        // Taking the suffix ensures we grab the "Most Significant" available bits
//        // because 'slots' is ordered from LSB to MSB.
//        return Array(slots.suffix(count))
//    }
//
//    /// Maps a logical Tag Value (0, 1, 2...) to the physical memory bytes.
//    private static func computeTagMemory(tagValue: Int, targetSlots: [(offset: Int, bit: Int)]) -> TagMemoryRepresentation {
//        var memoryChanges: [Int: UInt8] = [:]
//
//        for (i, slot) in targetSlots.enumerated() {
//            // Map the i-th bit of the tag value to the i-th target slot.
//            // Since targetSlots contains the MSBs (sorted LSB->MSB within that subset),
//            // Tag Bit 0 maps to the lowest bit of the high-order spare bits.
//            let bitValue = (tagValue >> i) & 1
//
//            if bitValue == 1 {
//                let currentByte = memoryChanges[slot.offset] ?? 0
//                memoryChanges[slot.offset] = currentByte | (1 << slot.bit)
//            } else {
//                // Ensure the byte exists in the map even if the bit is 0 (for completeness)
//                if memoryChanges[slot.offset] == nil {
//                    memoryChanges[slot.offset] = 0
//                }
//            }
//        }
//
//        return TagMemoryRepresentation(tagIndex: tagValue, memoryChanges: memoryChanges)
//    }
// }

import Foundation

// MARK: - Public API

public enum EnumLayoutCalculator {
    /// Calculates the memory layout of enum tags based on spare bits.
    ///
    /// This method implements the Swift Runtime's **Global MSB Strategy** (from `BitMask.h`):
    /// 1. Treats the entire spare bit area as a large Little-Endian integer.
    /// 2. Selects the Most Significant Bits (High Address, High Bit) to store the Tag.
    /// 3. Maps the Tag Value's bits to these locations (Tag LSB -> Lowest Address/Bit of the selected slots).
    ///
    /// - Parameters:
    ///   - spareBytes: The raw byte array of Spare Bits (Mask).
    ///   - startOffset: The starting offset of the mask relative to the Payload.
    ///   - numTags: The number of tags required (Payload Cases + Empty Cases).
    /// - Returns: The calculation result.
    /// - Throws: `LayoutError` if there are insufficient spare bits.
    public static func calculateMultiPayload(spareBytes: [UInt8], startOffset: Int, numTags: Int) throws -> EnumLayoutResult {
        // 1. Calculate required bits
        let bitsNeeded = Int(ceil(log2(Double(numTags))))

        // 2. Create a BitMask and apply the Global MSB selection logic
        var mask = BitMask(bytes: spareBytes)

        // This is the core logic from C++ `BitMask::keepOnlyMostSignificantBits`
        // It modifies the mask to keep ONLY the bits that will be used for the tag.
        mask.keepOnlyMostSignificantBits(bitsNeeded)

        // 3. Verify we have enough bits
        if mask.countSetBits < bitsNeeded {
            throw LayoutError.insufficientSpareBits(needed: bitsNeeded, found: mask.countSetBits)
        }

        // 4. Extract the physical slots (Offset + Bit Index)
        // IMPORTANT: We extract them in Low->High order (Little Endian packing).
        // The first slot found (lowest address/bit) corresponds to Tag Bit 0.
        let targetSlots = mask.getSortedSetBits(startOffset: startOffset)

        // 5. Calculate memory representation for each Tag
        var tagLayouts: [TagMemoryRepresentation] = []
        for tagValue in 0 ..< numTags {
            let layout = computeTagMemory(tagValue: tagValue, targetSlots: targetSlots)
            tagLayouts.append(layout)
        }

        // 6. Construct result (Identify the "Selected Region" just for display purposes)
        // We find the region that encompasses the selected bits.
        let selectedRegion = deriveRegionFromSlots(slots: targetSlots, fullBytes: spareBytes, startOffset: startOffset)

        return EnumLayoutResult(
            bitsNeeded: bitsNeeded,
            selectedRegion: selectedRegion,
            tagLayouts: tagLayouts,
            strategyDescription: "Multi-Payload (Global MSB)"
        )
    }

    // MARK: - Single Payload & Tagged MPE (Unchanged)

    public static func calculateSinglePayload(
        payloadSize: Int,
        payloadExtraInhabitants: Int,
        emptyCases: Int
    ) -> EnumLayoutResult {
        if payloadExtraInhabitants >= emptyCases {
            // Case A: Internal XI
            let region = SpareRegion(range: 0 ..< payloadSize, bitCount: 0, bytes: [])
            var layouts: [TagMemoryRepresentation] = []
            layouts.append(TagMemoryRepresentation(tagIndex: 0, memoryChanges: [:]))
            for i in 1 ... emptyCases {
                layouts.append(TagMemoryRepresentation(tagIndex: i, memoryChanges: [0: 0xFF])) // Placeholder
            }
            return EnumLayoutResult(bitsNeeded: 0, selectedRegion: region, tagLayouts: layouts, strategyDescription: "Single Payload (Internal XI)")
        }

        // Case B: Extra Tag
        let extraCases = emptyCases - payloadExtraInhabitants
        let tagBytes = getEnumTagCounts(payloadSize: payloadSize, emptyCases: extraCases, payloadCases: 1)
        let tagOffset = payloadSize
        let region = SpareRegion(range: tagOffset ..< (tagOffset + tagBytes), bitCount: tagBytes * 8, bytes: Array(repeating: 0, count: tagBytes))

        var layouts: [TagMemoryRepresentation] = []
        layouts.append(TagMemoryRepresentation(tagIndex: 0, memoryChanges: [tagOffset: 0x00]))
        for i in 1 ... emptyCases {
            let tagValue = i
            var changes: [Int: UInt8] = [:]
            for b in 0 ..< tagBytes {
                changes[tagOffset + b] = UInt8((tagValue >> (b * 8)) & 0xFF)
            }
            layouts.append(TagMemoryRepresentation(tagIndex: i, memoryChanges: changes))
        }

        return EnumLayoutResult(bitsNeeded: tagBytes * 8, selectedRegion: region, tagLayouts: layouts, strategyDescription: "Single Payload (Extra Tag)")
    }

    public static func calculateTaggedMultiPayload(payloadSize: Int, numTags: Int) -> EnumLayoutResult {
        let tagBytes = getEnumTagCounts(payloadSize: payloadSize, emptyCases: numTags, payloadCases: 0)
        let tagOffset = payloadSize
        let region = SpareRegion(range: tagOffset ..< (tagOffset + tagBytes), bitCount: tagBytes * 8, bytes: Array(repeating: 0, count: tagBytes))

        var layouts: [TagMemoryRepresentation] = []
        for i in 0 ..< numTags {
            var changes: [Int: UInt8] = [:]
            for b in 0 ..< tagBytes {
                changes[tagOffset + b] = UInt8((i >> (b * 8)) & 0xFF)
            }
            layouts.append(TagMemoryRepresentation(tagIndex: i, memoryChanges: changes))
        }
        return EnumLayoutResult(bitsNeeded: tagBytes * 8, selectedRegion: region, tagLayouts: layouts, strategyDescription: "Multi-Payload (Tagged)")
    }

    // MARK: - Errors & Helpers

    public enum LayoutError: Error {
        case insufficientSpareBits(needed: Int, found: Int)
    }

    private static func getEnumTagCounts(payloadSize: Int, emptyCases: Int, payloadCases: Int) -> Int {
        let total = UInt64(emptyCases) + UInt64(payloadCases)
        if total <= 1 { return 0 }
        if total <= 256 { return 1 }
        if total <= 65536 { return 2 }
        return 4
    }

    private static func computeTagMemory(tagValue: Int, targetSlots: [(offset: Int, bit: Int)]) -> TagMemoryRepresentation {
        var memoryChanges: [Int: UInt8] = [:]

        // Swift Runtime `storeEnumTagMultiPayload`:
        // Maps the Tag Value's bits to the Spare Bits.
        // The mapping order corresponds to `readMaskedInteger`:
        // Tag Bit 0 -> Lowest Address/Bit in Mask
        // Tag Bit N -> Highest Address/Bit in Mask

        for (i, slot) in targetSlots.enumerated() {
            let bitValue = (tagValue >> i) & 1

            if bitValue == 1 {
                let currentByte = memoryChanges[slot.offset] ?? 0
                memoryChanges[slot.offset] = currentByte | (1 << slot.bit)
            } else {
                if memoryChanges[slot.offset] == nil { memoryChanges[slot.offset] = 0 }
            }
        }
        return TagMemoryRepresentation(tagIndex: tagValue, memoryChanges: memoryChanges)
    }

    private static func deriveRegionFromSlots(slots: [(offset: Int, bit: Int)], fullBytes: [UInt8], startOffset: Int) -> SpareRegion {
        guard let first = slots.first, let last = slots.last else {
            return SpareRegion(range: 0 ..< 0, bitCount: 0, bytes: [])
        }
        // Create a visual region covering the range of used bits
        let range = first.offset ..< (last.offset + 1)
        let relativeStart = first.offset - startOffset
        let relativeEnd = last.offset - startOffset
        let bytes = Array(fullBytes[relativeStart ... relativeEnd])
        return SpareRegion(range: range, bitCount: slots.count, bytes: bytes)
    }
}

// MARK: - Data Structures

public struct SpareRegion: CustomStringConvertible, Sendable {
    public let range: Range<Int>
    public let bitCount: Int
    public let bytes: [UInt8]
    public var description: String { return "Offset \(range) (Used: \(bitCount) bits)" }
}

public struct TagMemoryRepresentation: CustomStringConvertible, Sendable {
    public let tagIndex: Int
    public let memoryChanges: [Int: UInt8]

    public var description: String {
        let hexValue = String(format: "0x%02X", tagIndex)
        var output = "Tag \(tagIndex) (\(hexValue)):\n"
        for offset in memoryChanges.keys.sorted() {
            let byteVal = memoryChanges[offset]!
            let byteHex = String(format: "0x%02X", byteVal)
            let binaryStr = String(byteVal, radix: 2)
            let padding = String(repeating: "0", count: 8 - binaryStr.count)
            output += "  -> Memory Offset \(offset) = \(byteHex) (Bin: \(padding + binaryStr))\n"
        }
        return output
    }
}

public struct EnumLayoutResult: CustomStringConvertible, Sendable {
    public let bitsNeeded: Int
    public let selectedRegion: SpareRegion
    public let tagLayouts: [TagMemoryRepresentation]
    public let strategyDescription: String

    public var description: String {
        var output = "=== Enum Layout Result (\(strategyDescription)) ===\n"
        output += "Bits Needed: \(bitsNeeded)\n"
        output += "Selected Region: \(selectedRegion)\n"
        output += "--------------------------\n"
        tagLayouts.forEach { output += $0.description }
        output += "=========================="
        return output
    }
}

extension BitMask {
    /// Returns the indices of set bits in Low -> High order.
    /// This matches the packing order of `readMaskedInteger`.
    func getSortedSetBits(startOffset: Int) -> [(offset: Int, bit: Int)] {
        var slots: [(offset: Int, bit: Int)] = []
        for (i, byte) in bytes.enumerated() {
            if byte == 0 { continue }
            let absOffset = startOffset + i
            for b in 0 ..< 8 {
                if (byte & (1 << b)) != 0 {
                    slots.append((offset: absOffset, bit: b))
                }
            }
        }
        return slots
    }
}
