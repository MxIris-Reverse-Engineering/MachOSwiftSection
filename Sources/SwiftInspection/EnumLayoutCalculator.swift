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

// import Foundation
//
//// MARK: - Public API
//
// public enum EnumLayoutCalculator {
//    /// Calculates the memory layout of enum tags based on spare bits.
//    ///
//    /// This method implements the Swift Runtime's **Global MSB Strategy** (from `BitMask.h`):
//    /// 1. Treats the entire spare bit area as a large Little-Endian integer.
//    /// 2. Selects the Most Significant Bits (High Address, High Bit) to store the Tag.
//    /// 3. Maps the Tag Value's bits to these locations (Tag LSB -> Lowest Address/Bit of the selected slots).
//    ///
//    /// - Parameters:
//    ///   - spareBytes: The raw byte array of Spare Bits (Mask).
//    ///   - startOffset: The starting offset of the mask relative to the Payload.
//    ///   - numTags: The number of tags required (Payload Cases + Empty Cases).
//    /// - Returns: The calculation result.
//    /// - Throws: `LayoutError` if there are insufficient spare bits.
//    public static func calculateMultiPayload(spareBytes: [UInt8], startOffset: Int, numTags: Int) throws -> EnumLayoutResult {
//        // 1. Calculate required bits
//        let bitsNeeded = Int(ceil(log2(Double(numTags))))
//
//        // 2. Create a BitMask and apply the Global MSB selection logic
//        var mask = BitMask(bytes: spareBytes)
//
//        // This is the core logic from C++ `BitMask::keepOnlyMostSignificantBits`
//        // It modifies the mask to keep ONLY the bits that will be used for the tag.
//        mask.keepOnlyMostSignificantBits(bitsNeeded)
//
//        // 3. Verify we have enough bits
//        if mask.numSetBits < bitsNeeded {
//            throw LayoutError.insufficientSpareBits(needed: bitsNeeded, found: mask.numSetBits)
//        }
//
//        // 4. Extract the physical slots (Offset + Bit Index)
//        // IMPORTANT: We extract them in Low->High order (Little Endian packing).
//        // The first slot found (lowest address/bit) corresponds to Tag Bit 0.
//        let targetSlots = mask.getSortedSetBits(startOffset: startOffset)
//
//        // 5. Calculate memory representation for each Tag
//        var tagLayouts: [TagMemoryRepresentation] = []
//        for tagValue in 0 ..< numTags {
//            let layout = computeTagMemory(tagValue: tagValue, targetSlots: targetSlots)
//            tagLayouts.append(layout)
//        }
//
//        // 6. Construct result (Identify the "Selected Region" just for display purposes)
//        // We find the region that encompasses the selected bits.
//        let selectedRegion = deriveRegionFromSlots(slots: targetSlots, fullBytes: spareBytes, startOffset: startOffset)
//
//        return EnumLayoutResult(
//            bitsNeeded: bitsNeeded,
//            selectedRegion: selectedRegion,
//            tagLayouts: tagLayouts,
//            strategyDescription: "Multi-Payload (Global MSB)"
//        )
//    }
//
//    // MARK: - Single Payload & Tagged MPE (Unchanged)
//
//    public static func calculateSinglePayload(
//        payloadSize: Int,
//        payloadExtraInhabitants: Int,
//        emptyCases: Int
//    ) -> EnumLayoutResult {
//        if payloadExtraInhabitants >= emptyCases {
//            // Case A: Internal XI
//            let region = SpareRegion(range: 0 ..< payloadSize, bitCount: 0, bytes: [])
//            var layouts: [TagMemoryRepresentation] = []
//            layouts.append(TagMemoryRepresentation(tagIndex: 0, memoryChanges: [:]))
//            for i in 1 ... emptyCases {
//                layouts.append(TagMemoryRepresentation(tagIndex: i, memoryChanges: [0: 0xFF])) // Placeholder
//            }
//            return EnumLayoutResult(bitsNeeded: 0, selectedRegion: region, tagLayouts: layouts, strategyDescription: "Single Payload (Internal XI)")
//        }
//
//        // Case B: Extra Tag
//        let extraCases = emptyCases - payloadExtraInhabitants
//        let tagBytes = getEnumTagCounts(payloadSize: payloadSize, emptyCases: extraCases, payloadCases: 1)
//        let tagOffset = payloadSize
//        let region = SpareRegion(range: tagOffset ..< (tagOffset + tagBytes), bitCount: tagBytes * 8, bytes: Array(repeating: 0, count: tagBytes))
//
//        var layouts: [TagMemoryRepresentation] = []
//        layouts.append(TagMemoryRepresentation(tagIndex: 0, memoryChanges: [tagOffset: 0x00]))
//        for i in 1 ... emptyCases {
//            let tagValue = i
//            var changes: [Int: UInt8] = [:]
//            for b in 0 ..< tagBytes {
//                changes[tagOffset + b] = UInt8((tagValue >> (b * 8)) & 0xFF)
//            }
//            layouts.append(TagMemoryRepresentation(tagIndex: i, memoryChanges: changes))
//        }
//
//        return EnumLayoutResult(bitsNeeded: tagBytes * 8, selectedRegion: region, tagLayouts: layouts, strategyDescription: "Single Payload (Extra Tag)")
//    }
//
//    public static func calculateTaggedMultiPayload(payloadSize: Int, numTags: Int) -> EnumLayoutResult {
//        let tagBytes = getEnumTagCounts(payloadSize: payloadSize, emptyCases: numTags, payloadCases: 0)
//        let tagOffset = payloadSize
//        let region = SpareRegion(range: tagOffset ..< (tagOffset + tagBytes), bitCount: tagBytes * 8, bytes: Array(repeating: 0, count: tagBytes))
//
//        var layouts: [TagMemoryRepresentation] = []
//        for i in 0 ..< numTags {
//            var changes: [Int: UInt8] = [:]
//            for b in 0 ..< tagBytes {
//                changes[tagOffset + b] = UInt8((i >> (b * 8)) & 0xFF)
//            }
//            layouts.append(TagMemoryRepresentation(tagIndex: i, memoryChanges: changes))
//        }
//        return EnumLayoutResult(bitsNeeded: tagBytes * 8, selectedRegion: region, tagLayouts: layouts, strategyDescription: "Multi-Payload (Tagged)")
//    }
//
//    // MARK: - Errors & Helpers
//
//    public enum LayoutError: Error {
//        case insufficientSpareBits(needed: Int, found: Int)
//    }
//
//    private static func getEnumTagCounts(payloadSize: Int, emptyCases: Int, payloadCases: Int) -> Int {
//        let total = UInt64(emptyCases) + UInt64(payloadCases)
//        if total <= 1 { return 0 }
//        if total <= 256 { return 1 }
//        if total <= 65536 { return 2 }
//        return 4
//    }
//
//    private static func computeTagMemory(tagValue: Int, targetSlots: [(offset: Int, bit: Int)]) -> TagMemoryRepresentation {
//        var memoryChanges: [Int: UInt8] = [:]
//
//        // Swift Runtime `storeEnumTagMultiPayload`:
//        // Maps the Tag Value's bits to the Spare Bits.
//        // The mapping order corresponds to `readMaskedInteger`:
//        // Tag Bit 0 -> Lowest Address/Bit in Mask
//        // Tag Bit N -> Highest Address/Bit in Mask
//
//        for (i, slot) in targetSlots.enumerated() {
//            let bitValue = (tagValue >> i) & 1
//
//            if bitValue == 1 {
//                let currentByte = memoryChanges[slot.offset] ?? 0
//                memoryChanges[slot.offset] = currentByte | (1 << slot.bit)
//            } else {
//                if memoryChanges[slot.offset] == nil { memoryChanges[slot.offset] = 0 }
//            }
//        }
//        return TagMemoryRepresentation(tagIndex: tagValue, memoryChanges: memoryChanges)
//    }
//
//    private static func deriveRegionFromSlots(slots: [(offset: Int, bit: Int)], fullBytes: [UInt8], startOffset: Int) -> SpareRegion {
//        guard let first = slots.first, let last = slots.last else {
//            return SpareRegion(range: 0 ..< 0, bitCount: 0, bytes: [])
//        }
//        // Create a visual region covering the range of used bits
//        let range = first.offset ..< (last.offset + 1)
//        let relativeStart = first.offset - startOffset
//        let relativeEnd = last.offset - startOffset
//        let bytes = Array(fullBytes[relativeStart ... relativeEnd])
//        return SpareRegion(range: range, bitCount: slots.count, bytes: bytes)
//    }
// }
//
//// MARK: - Data Structures
//
// public struct SpareRegion: CustomStringConvertible, Sendable {
//    public let range: Range<Int>
//    public let bitCount: Int
//    public let bytes: [UInt8]
//    public var description: String { return "Offset \(range) (Used: \(bitCount) bits)" }
// }
//
// public struct TagMemoryRepresentation: CustomStringConvertible, Sendable {
//    public let tagIndex: Int
//    public let memoryChanges: [Int: UInt8]
//
//    public var description: String {
//        let hexValue = String(format: "0x%02X", tagIndex)
//        var output = "Tag \(tagIndex) (\(hexValue)):\n"
//        for offset in memoryChanges.keys.sorted() {
//            let byteVal = memoryChanges[offset]!
//            let byteHex = String(format: "0x%02X", byteVal)
//            let binaryStr = String(byteVal, radix: 2)
//            let padding = String(repeating: "0", count: 8 - binaryStr.count)
//            output += "  -> Memory Offset \(offset) = \(byteHex) (Bin: \(padding + binaryStr))\n"
//        }
//        return output
//    }
// }
//
// public struct EnumLayoutResult: CustomStringConvertible, Sendable {
//    public let bitsNeeded: Int
//    public let selectedRegion: SpareRegion
//    public let tagLayouts: [TagMemoryRepresentation]
//    public let strategyDescription: String
//
//    public var description: String {
//        var output = "=== Enum Layout Result (\(strategyDescription)) ===\n"
//        output += "Bits Needed: \(bitsNeeded)\n"
//        output += "Selected Region: \(selectedRegion)\n"
//        output += "--------------------------\n"
//        tagLayouts.forEach { output += $0.description }
//        output += "=========================="
//        return output
//    }
// }
//
// extension BitMask {
//    /// Returns the indices of set bits in Low -> High order.
//    /// This matches the packing order of `readMaskedInteger`.
//    func getSortedSetBits(startOffset: Int) -> [(offset: Int, bit: Int)] {
//        var slots: [(offset: Int, bit: Int)] = []
//        for (i, byte) in bytes.enumerated() {
//            if byte == 0 { continue }
//            let absOffset = startOffset + i
//            for b in 0 ..< 8 {
//                if (byte & (1 << b)) != 0 {
//                    slots.append((offset: absOffset, bit: b))
//                }
//            }
//        }
//        return slots
//    }
// }
//
// import Foundation
//
//// MARK: - Public API
//
// public enum EnumLayoutCalculator {
//    public struct SpareRegion: CustomStringConvertible, Sendable {
//        public let range: Range<Int>
//        public let bitCount: Int
//        /// 原始的 spare bytes
//        public let bytes: [UInt8]
//        public var description: String { return "Offset \(range) (Total Spare Bits: \(bitCount))" }
//    }
//
//    public struct TagMemoryRepresentation: CustomStringConvertible, Sendable {
//        public let caseName: String // "Payload Case X" or "Empty Case Y"
//        public let tagValue: Int
//        /// 内存偏移 -> 字节值
//        public let memoryChanges: [Int: UInt8]
//
//        public var description: String {
//            let hexValue = String(format: "0x%X", tagValue)
//            var output = "\(caseName) (Internal Tag: \(tagValue) / \(hexValue)):\n"
//            if memoryChanges.isEmpty {
//                output += "  -> No memory bits set (All Zero)\n"
//            }
//            for offset in memoryChanges.keys.sorted() {
//                let byteVal = memoryChanges[offset]!
//                let byteHex = String(format: "0x%02X", byteVal)
//                let binaryStr = String(byteVal, radix: 2)
//                let padding = String(repeating: "0", count: 8 - binaryStr.count)
//                output += "  -> Offset \(offset): \(byteHex) (Bin: \(padding + binaryStr))\n"
//            }
//            return output
//        }
//    }
//
//    public struct LayoutResult: CustomStringConvertible, Sendable {
//        public let bitsNeeded: Int
//        public let selectedRegion: SpareRegion
//        public let tagLayouts: [TagMemoryRepresentation]
//        public let strategyDescription: String
//
//        public var description: String {
//            var output = "=== Enum Layout Result ===\n"
//            output += "Strategy: \(strategyDescription)\n"
//            output += "Tag Bits Needed: \(bitsNeeded)\n"
//            output += "Spare Region: \(selectedRegion)\n"
//            output += "--------------------------\n"
//            tagLayouts.forEach { output += $0.description }
//            output += "=========================="
//            return output
//        }
//    }
//
//    /// 计算多负载枚举的内存布局
//    /// - Parameters:
//    ///   - enumSize: 枚举总大小（包含可能的 Extra Tag）
//    ///   - payloadSize: 关联值（Payload）的大小
//    ///   - spareBytes: 关联值中的空闲字节（通常由编译器提供或通过逆向分析得出）
//    ///   - spareBytesOffsetInEnum: 空闲字节在枚举内存中的起始偏移
//    ///   - numPayloadCases: 带关联值的成员数量
//    ///   - numEmptyCases: 不带关联值的成员数量
//    public static func calculateMultiPayload(
//        enumSize: Int,
//        payloadSize: Int,
//        spareBytes: [UInt8],
//        spareBytesOffsetInEnum: Int,
//        numPayloadCases: Int,
//        numEmptyCases: Int
//    ) throws -> LayoutResult {
//
//        // 1. 构建 BitMask 对象 (对应 C++ BitMask)
//        // 注意：spareBytes 通常只覆盖 payloadSize 的范围
//        let spareMask = BitMask(bytes: spareBytes)
//
//        // 2. 计算需要多少个 Tag 值 (对应 getMultiPayloadTagBitsMask 中的逻辑)
//        // C++: auto payloadTagValues = NumEffectivePayloadCases - 1;
//        var payloadTagValues = numPayloadCases > 0 ? numPayloadCases - 1 : 0
//
//        let totalCases = numPayloadCases + numEmptyCases
//
//        // 如果有 Empty Cases，我们需要检查是否需要额外的 Tag 值来区分它们
//        if totalCases > numPayloadCases {
//            // C++: payloadBits.complement(); // Non-spare bits are payload bits
//            // 计算 Payload 区域中“非空闲”的位数（即数据位）。
//            // 逻辑是：对于 Empty Case，我们可以利用整个 Payload 区域（包括数据位和空闲位）来编码。
//            // 但前提是 Tag 必须先告诉我们“这是个 Empty Case”。
//            let totalPayloadBits = payloadSize * 8
//            let spareBitsCount = spareMask.countSetBits()
//            let dataBitsCount = totalPayloadBits - spareBitsCount
//
//            if dataBitsCount >= 32 {
//                // 如果有超过 32 位的数据位，空间巨大，只需要 1 个额外的 Tag 值就足够容纳所有 Empty Cases
//                payloadTagValues += 1
//            } else {
//                // 否则，计算一个 Tag 能容纳多少个 Empty Case
//                let numNonPayloadCasesPerTag = 1 << dataBitsCount
//                let numNonPayloadCases = totalCases - numPayloadCases
//                // 向上取整除法
//                let tagsForEmpty = (numNonPayloadCases + numNonPayloadCasesPerTag - 1) / numNonPayloadCasesPerTag
//                payloadTagValues += tagsForEmpty
//            }
//        }
//
//        // 3. 计算需要的 Tag 位数
//        // C++: while (payloadTagValues > 0) ...
//        var requiredTagBits = 0
//        var tempValues = payloadTagValues
//        while tempValues > 0 {
//            tempValues >>= 1
//            requiredTagBits += 1
//        }
//
//        // 4. 确定 Tag 使用哪些空闲位
//        // C++: payloadTagBitsMask.keepOnlyMostSignificantBits(payloadTagBits);
//        // 这里的逻辑是：优先使用最高有效的空闲位作为 Tag
//        var tagMask = spareMask
//        tagMask.keepOnlyMostSignificantBits(count: requiredTagBits)
//
//        // 5. 确定剩余的空闲位（用于辅助编码 Empty Cases）
//        // C++: occupiedBits.complement() logic in projectEnumValue
//        // 实际上就是 spareMask 中剔除了 tagMask 的部分
//        var secondarySpareMask = spareMask
//        secondarySpareMask.removeBits(presentIn: tagMask)
//        let secondarySpareBitCount = secondarySpareMask.countSetBits()
//
//        // 6. 生成布局报告
//        var layouts: [TagMemoryRepresentation] = []
//
//        // 6a. 生成 Payload Cases 的布局
//        for i in 0..<numPayloadCases {
//            let tagValue = i
//            let memory = encode(
//                tagValue: tagValue,
//                payloadValue: 0, // Payload Case 的数据部分由用户数据填充，这里只展示 Tag
//                tagMask: tagMask,
//                secondaryMask: secondarySpareMask,
//                enumSize: enumSize,
//                payloadSize: payloadSize,
//                offset: spareBytesOffsetInEnum
//            )
//
//            layouts.append(TagMemoryRepresentation(
//                caseName: "Payload Case \(i)",
//                tagValue: tagValue,
//                memoryChanges: memory
//            ))
//        }
//
//        // 6b. 生成 Empty Cases 的布局
//        // C++ projectEnumValue 逆逻辑:
//        // ComputedCase = (((tagValue - NumEffectivePayloadCases) << occupiedBitCount) | payloadValue) + NumEffectivePayloadCases;
//        // 所以:
//        // TargetIndex = EmptyCaseIndex + numPayloadCases
//        // Delta = TargetIndex - numPayloadCases = EmptyCaseIndex
//        // PayloadValue (in secondary bits) = Delta & ((1 << occupiedBitCount) - 1)
//        // TagValue = (Delta >> occupiedBitCount) + numPayloadCases
//
//        for i in 0..<numEmptyCases {
//            let emptyCaseIndex = i
//            // 分解 Empty Case Index 到 Tag 和 Secondary Bits
//            let payloadValueForEmpty = emptyCaseIndex & ((1 << secondarySpareBitCount) - 1)
//            let tagValueForEmpty = (emptyCaseIndex >> secondarySpareBitCount) + numPayloadCases
//
//            let memory = encode(
//                tagValue: tagValueForEmpty,
//                payloadValue: payloadValueForEmpty,
//                tagMask: tagMask,
//                secondaryMask: secondarySpareMask,
//                enumSize: enumSize,
//                payloadSize: payloadSize,
//                offset: spareBytesOffsetInEnum
//            )
//
//            layouts.append(TagMemoryRepresentation(
//                caseName: "Empty Case \(i)",
//                tagValue: tagValueForEmpty,
//                memoryChanges: memory
//            ))
//        }
//
//        let region = SpareRegion(
//            range: spareBytesOffsetInEnum..<(spareBytesOffsetInEnum + spareBytes.count),
//            bitCount: spareMask.countSetBits(),
//            bytes: spareBytes
//        )
//
//        return LayoutResult(
//            bitsNeeded: requiredTagBits,
//            selectedRegion: region,
//            tagLayouts: layouts,
//            strategyDescription: "Multi-Payload (Tag in Spare Bits)"
//        )
//    }
//
//    // MARK: - Private Helpers
//
//    /// 将 Tag 值和 Payload 值编码进内存
//    private static func encode(
//        tagValue: Int,
//        payloadValue: Int,
//        tagMask: BitMask,
//        secondaryMask: BitMask,
//        enumSize: Int,
//        payloadSize: Int,
//        offset: Int
//    ) -> [Int: UInt8] {
//        var memory: [Int: UInt8] = [:]
//
//        // 1. 处理 Extra Tag (如果 Tag 值太大，超出了 TagMask 能容纳的范围)
//        // C++: if (numPayloadTagBits >= 32) ... else tagValue = (extraTag << numPayloadTagBits) | payloadTag;
//        let numTagBits = tagMask.countSetBits()
//        let maxTagInSpare = (1 << numTagBits) - 1
//
//        let tagPartInSpare = tagValue & maxTagInSpare
//        let tagPartExtra = tagValue >> numTagBits
//
//        // 2. 将 Tag 的低位写入 Spare Bits
//        let tagBytes = tagMask.deposit(value: tagPartInSpare)
//        merge(bytes: tagBytes, into: &memory, at: offset)
//
//        // 3. 将 Empty Case 的数据部分写入剩余的 Spare Bits
//        if payloadValue > 0 {
//            let payloadBytes = secondaryMask.deposit(value: payloadValue)
//            merge(bytes: payloadBytes, into: &memory, at: offset)
//        }
//
//        // 4. 写入 Extra Tag (如果有)
//        // Extra Tag 位于 Payload 之后
//        if tagPartExtra > 0 {
//            let extraTagSize = enumSize - payloadSize
//            if extraTagSize > 0 {
//                // 简单的将整数写入字节
//                for b in 0..<extraTagSize {
//                    let byteVal = UInt8((tagPartExtra >> (b * 8)) & 0xFF)
//                    if byteVal != 0 {
//                        memory[payloadSize + b] = byteVal
//                    }
//                }
//            }
//        }
//
//        return memory
//    }
//
//    private static func merge(bytes: [UInt8], into memory: inout [Int: UInt8], at offset: Int) {
//        for (i, byte) in bytes.enumerated() {
//            if byte != 0 {
//                let addr = offset + i
//                let existing = memory[addr] ?? 0
//                memory[addr] = existing | byte
//            }
//        }
//    }
// }
//
//// MARK: - Internal BitMask Implementation
//
///// 模拟 C++ BitMask 类的核心功能
// internal struct BitMask {
//    var bytes: [UInt8]
//
//    init(bytes: [UInt8]) {
//        self.bytes = bytes
//    }
//
//    func countSetBits() -> Int {
//        return bytes.reduce(0) { $0 + $1.nonzeroBitCount }
//    }
//
//    /// 对应 C++: keepOnlyMostSignificantBits
//    /// 保留最高的 N 个置位，其余清零
//    mutating func keepOnlyMostSignificantBits(count: Int) {
//        if bytes.isEmpty { return }
//
//        var bitsToKeep = count
//        // C++ 逻辑是从高地址向低地址遍历 (i = size; i > 0; i--)
//        // 在 Little Endian 的内存模型中，高地址代表高位。
//        for i in (0..<bytes.count).reversed() {
//            if bitsToKeep <= 0 {
//                bytes[i] = 0
//                continue
//            }
//
//            let byte = bytes[i]
//            var newByte: UInt8 = 0
//            // 从字节的高位 (0x80) 到低位 (0x01) 扫描
//            var mask: UInt8 = 0x80
//            while mask > 0 {
//                if (byte & mask) != 0 {
//                    if bitsToKeep > 0 {
//                        newByte |= mask
//                        bitsToKeep -= 1
//                    }
//                }
//                mask >>= 1
//            }
//            bytes[i] = newByte
//        }
//    }
//
//    /// 移除在另一个掩码中存在的位 (相当于 self &= ~other)
//    mutating func removeBits(presentIn other: BitMask) {
//        for i in 0..<min(bytes.count, other.bytes.count) {
//            bytes[i] &= ~other.bytes[i]
//        }
//    }
//
//    /// 核心功能：Scatter / Deposit
//    /// 将 value 的二进制位，依次填入 mask 中为 1 的位置
//    func deposit(value: Int) -> [UInt8] {
//        var result = [UInt8](repeating: 0, count: bytes.count)
//        var remainingValue = value
//
//        // 遍历掩码的每一位，如果是 1，则从 value 取一位填入
//        // 顺序：从低地址的低位开始 (Little Endian)
//        for i in 0..<bytes.count {
//            let maskByte = bytes[i]
//            var resultByte: UInt8 = 0
//            var bitPos: UInt8 = 1 // 0x01, 0x02, 0x04 ...
//
//            while bitPos > 0 { // 8次循环
//                if (maskByte & bitPos) != 0 {
//                    // 掩码该位有效，填入 value 的最低位
//                    if (remainingValue & 1) != 0 {
//                        resultByte |= bitPos
//                    }
//                    remainingValue >>= 1
//                }
//                // 检查是否溢出 (UInt8 循环移位在 Swift 会 crash，所以用 > 0 判断)
//                if bitPos == 0x80 { break }
//                bitPos <<= 1
//            }
//            result[i] = resultByte
//        }
//        return result
//    }
// }
//
// import Foundation
//
// public enum EnumLayoutCalculator {
//
//    // MARK: - Types
//
//    public struct SpareRegion: CustomStringConvertible, Sendable {
//        public let range: Range<Int>
//        public let bitCount: Int
//        public let bytes: [UInt8]
//        public var description: String { return "Offset \(range) (Used: \(bitCount) bits)" }
//    }
//
//    public struct TagMemoryRepresentation: CustomStringConvertible, Sendable {
//        public let tagIndex: Int
//        public let caseName: String
//        public let memoryChanges: [Int: UInt8]
//
//        public var description: String {
//            let hexValue = String(format: "0x%02X", tagIndex)
//            var output = "Tag \(tagIndex) (\(hexValue)) - \(caseName):\n"
//            if memoryChanges.isEmpty {
//                output += "  -> (No bits set / Zero)\n"
//            } else {
//                for offset in memoryChanges.keys.sorted() {
//                    let byteVal = memoryChanges[offset]!
//                    let byteHex = String(format: "0x%02X", byteVal)
//                    let binaryStr = String(byteVal, radix: 2)
//                    let padding = String(repeating: "0", count: 8 - binaryStr.count)
//                    output += "  -> Memory Offset \(offset) = \(byteHex) (Bin: \(padding + binaryStr))\n"
//                }
//            }
//            return output
//        }
//    }
//
//    public struct LayoutResult: CustomStringConvertible, Sendable {
//        public let strategyDescription: String
//        public let bitsNeeded: Int
//        public let numTags: Int
//        public let selectedRegion: SpareRegion?
//        public let tagLayouts: [TagMemoryRepresentation]
//
//        public var description: String {
//            var output = "=== Enum Layout Result (\(strategyDescription)) ===\n"
//            output += "Bits Needed: \(bitsNeeded)\n"
//            output += "Total Tags: \(numTags)\n"
//            if let region = selectedRegion {
//                output += "Selected Region: \(region)\n"
//            }
//            output += "--------------------------\n"
//            tagLayouts.forEach { output += $0.description }
//            output += "=========================="
//            return output
//        }
//    }
//
//    public enum LayoutError: Error, CustomStringConvertible {
//        case notEnoughSpareBits(needed: Int, available: Int)
//
//        public var description: String {
//            switch self {
//            case .notEnoughSpareBits(let needed, let available):
//                return "Not enough spare bits: needed \(needed), available \(available)"
//            }
//        }
//    }
//
//    // MARK: - Strategy 1: Multi-Payload (Spare Bits)
//
//    /// 对应 GenEnum.cpp: MultiPayloadEnumImplStrategy::completeFixedLayout
//    public static func calculateMultiPayload(
//        payloadSize: Int,
//        spareBytes: [UInt8],
//        spareBytesOffset: Int,
//        numPayloadCases: Int,
//        numEmptyCases: Int
//    ) throws -> LayoutResult {
//
//        // 1. 构建 CommonSpareBits (Intersection of all payload spare bits)
//        var commonSpareBits = BitMask(sizeInBytes: payloadSize)
//        commonSpareBits.makeZero() // 默认全 0 (Used)
//
//        // 填充用户提供的 spareBytes
//        if spareBytesOffset < payloadSize {
//            let copyLength = min(spareBytes.count, payloadSize - spareBytesOffset)
//            for i in 0..<copyLength {
//                commonSpareBits[byteAt: spareBytesOffset + i] = spareBytes[i]
//            }
//        }
//
//        // 2. 计算 Tag 数量 (GenEnum.cpp logic)
//        let commonSpareBitCount = commonSpareBits.countSetBits()
//        let usedBitCount = commonSpareBits.size * 8 - commonSpareBitCount
//
//        var numEmptyElementTags = 0
//        if numEmptyCases > 0 {
//            if usedBitCount >= 32 {
//                numEmptyElementTags = 1
//            } else {
//                let emptyElementsPerTag = 1 << usedBitCount
//                numEmptyElementTags = (numEmptyCases + emptyElementsPerTag - 1) / emptyElementsPerTag
//            }
//        }
//
//        let numTags = numPayloadCases + numEmptyElementTags
//
//        // 3. 计算需要的位数
//        var numTagBits = 0
//        if numTags > 1 {
//            var temp = numTags - 1
//            while temp > 0 {
//                temp >>= 1
//                numTagBits += 1
//            }
//        }
//
//        // 4. 选择 PayloadTagBits (MSB 优先)
//        var payloadTagBitsMask = commonSpareBits
//        payloadTagBitsMask.keepOnlyMostSignificantBits(numTagBits)
//
//        let availableBits = payloadTagBitsMask.countSetBits()
//        if availableBits < numTagBits {
//            throw LayoutError.notEnoughSpareBits(needed: numTagBits, available: availableBits)
//        }
//
//        // 5. 生成结果
//        let region = calculateRegion(from: payloadTagBitsMask, payloadSize: payloadSize, bitCount: numTagBits)
//
//        var tagLayouts: [TagMemoryRepresentation] = []
//
//        // Payload Cases (Tag 0 ..< numPayloadCases)
//        for tagVal in 0..<numPayloadCases {
//            let mem = generateMemoryChanges(mask: payloadTagBitsMask, tagValue: tagVal)
//            tagLayouts.append(TagMemoryRepresentation(tagIndex: tagVal, caseName: "Payload Case \(tagVal)", memoryChanges: mem))
//        }
//
//        // Empty Cases (Tag numPayloadCases ..< numTags)
//        // 注意：Empty Case 的实际 Payload 值不仅仅是 Tag，还包含 Payload 区域的填充。
//        // 这里我们只展示 Tag 部分的位变化。
//        if numEmptyCases > 0 {
//            for tagVal in numPayloadCases..<numTags {
//                let mem = generateMemoryChanges(mask: payloadTagBitsMask, tagValue: tagVal)
//                tagLayouts.append(TagMemoryRepresentation(tagIndex: tagVal, caseName: "Empty Case Group", memoryChanges: mem))
//            }
//        }
//
//        return LayoutResult(
//            strategyDescription: "Multi-Payload (Spare Bits)",
//            bitsNeeded: numTagBits,
//            numTags: numTags,
//            selectedRegion: region,
//            tagLayouts: tagLayouts
//        )
//    }
//
//    // MARK: - Strategy 2: Tagged Multi-Payload (Extra Tag)
//
//    /// 对应 GenEnum.cpp: MultiPayloadEnumImplStrategy (ExtraTagBitCount > 0)
//    public static func calculateTaggedMultiPayload(
//        payloadSize: Int,
//        numPayloadCases: Int,
//        numEmptyCases: Int
//    ) -> LayoutResult {
//
//        let numTags = numPayloadCases + numEmptyCases
//
//        // Enum.h: getEnumTagCounts
//        let numTagBytes: Int
//        if numTags <= 1 { numTagBytes = 0 }
//        else if numTags < 256 { numTagBytes = 1 }
//        else if numTags < 65536 { numTagBytes = 2 }
//        else { numTagBytes = 4 }
//
//        let bitsNeeded = numTagBytes * 8
//        let tagOffset = payloadSize
//
//        // 构造一个虚拟的 Mask 来表示 Tag 区域
//        let region = SpareRegion(
//            range: tagOffset..<(tagOffset + numTagBytes),
//            bitCount: bitsNeeded,
//            bytes: [UInt8](repeating: 0xFF, count: numTagBytes)
//        )
//
//        var tagLayouts: [TagMemoryRepresentation] = []
//
//        for tagVal in 0..<numTags {
//            var memoryChanges: [Int: UInt8] = [:]
//            var tempTag = tagVal
//            for i in 0..<numTagBytes {
//                memoryChanges[tagOffset + i] = UInt8(tempTag & 0xFF)
//                tempTag >>= 8
//            }
//
//            let name = tagVal < numPayloadCases ? "Payload Case \(tagVal)" : "Empty Case \(tagVal - numPayloadCases)"
//            tagLayouts.append(TagMemoryRepresentation(tagIndex: tagVal, caseName: name, memoryChanges: memoryChanges))
//        }
//
//        return LayoutResult(
//            strategyDescription: "Tagged Multi-Payload (Extra Tag)",
//            bitsNeeded: bitsNeeded,
//            numTags: numTags,
//            selectedRegion: region,
//            tagLayouts: tagLayouts
//        )
//    }
//
//    // MARK: - Strategy 3: Single Payload
//
//    /// 对应 GenEnum.cpp: SinglePayloadEnumImplStrategy
//    public static func calculateSinglePayload(
//        size: Int,
//        payloadSize: Int,
//        numEmptyCases: Int
//    ) -> LayoutResult {
//
//        let numTags = numEmptyCases + 1 // 1 for Payload Case
//
//        if size > payloadSize {
//            // Case A: Extra Tag (Payload 满了，或者没有 XI)
//            let extraTagBytes = size - payloadSize
//            let bitsNeeded = extraTagBytes * 8
//
//            let region = SpareRegion(
//                range: payloadSize..<size,
//                bitCount: bitsNeeded,
//                bytes: [UInt8](repeating: 0xFF, count: extraTagBytes)
//            )
//
//            var tagLayouts: [TagMemoryRepresentation] = []
//
//            // Payload Case: Tag = 0 (Extra Tag Area is 0)
//            var payloadMem: [Int: UInt8] = [:]
//            for i in 0..<extraTagBytes { payloadMem[payloadSize + i] = 0 }
//            tagLayouts.append(TagMemoryRepresentation(tagIndex: 0, caseName: "Payload Case", memoryChanges: payloadMem))
//
//            // Empty Cases: Tag = 1..N
//            // 展示前几个 Empty Case
//            let casesToShow = min(numEmptyCases, 5)
//            for i in 1...casesToShow {
//                var mem: [Int: UInt8] = [:]
//                var tempTag = i
//                for b in 0..<extraTagBytes {
//                    mem[payloadSize + b] = UInt8(tempTag & 0xFF)
//                    tempTag >>= 8
//                }
//                tagLayouts.append(TagMemoryRepresentation(tagIndex: i, caseName: "Empty Case \(i-1)", memoryChanges: mem))
//            }
//
//            return LayoutResult(
//                strategyDescription: "Single Payload (Extra Tag)",
//                bitsNeeded: bitsNeeded,
//                numTags: numTags,
//                selectedRegion: region,
//                tagLayouts: tagLayouts
//            )
//
//        } else {
//            // Case B: Extra Inhabitants (XI)
//            // Tag 实际上是 Payload 类型的 XI 索引。
//            // Payload Case = Valid Value (Tag 0 in logic, but -1 index)
//            // Empty Case 0 = XI #0
//            // Empty Case 1 = XI #1
//
//            return LayoutResult(
//                strategyDescription: "Single Payload (Extra Inhabitants)",
//                bitsNeeded: 0, // 依赖于 Payload 内部结构
//                numTags: numTags,
//                selectedRegion: nil,
//                tagLayouts: [
//                    TagMemoryRepresentation(tagIndex: 0, caseName: "Payload Case (Valid Value)", memoryChanges: [:]),
//                    TagMemoryRepresentation(tagIndex: 1, caseName: "Empty Case 0 (Uses XI #0)", memoryChanges: [:]),
//                    TagMemoryRepresentation(tagIndex: 2, caseName: "Empty Case 1 (Uses XI #1)", memoryChanges: [:])
//                ]
//            )
//        }
//    }
//
//    // MARK: - Helpers
//
//    private static func calculateRegion(from mask: BitMask, payloadSize: Int, bitCount: Int) -> SpareRegion {
//        var minByte = payloadSize
//        var maxByte = 0
//        var hasBits = false
//
//        for i in 0..<payloadSize {
//            if mask[byteAt: i] != 0 {
//                if i < minByte { minByte = i }
//                if i > maxByte { maxByte = i }
//                hasBits = true
//            }
//        }
//
//        let regionRange = hasBits ? minByte..<(maxByte + 1) : 0..<0
//        let regionBytes = hasBits ? (minByte...maxByte).map { mask[byteAt: $0] } : []
//
//        return SpareRegion(range: regionRange, bitCount: bitCount, bytes: regionBytes)
//    }
//
//    private static func generateMemoryChanges(mask: BitMask, tagValue: Int) -> [Int: UInt8] {
//        let scatteredBytes = mask.scatterBits(value: tagValue)
//        var memoryChanges: [Int: UInt8] = [:]
//
//        for i in 0..<mask.size {
//            if mask[byteAt: i] != 0 {
//                memoryChanges[i] = scatteredBytes[i]
//            }
//        }
//        return memoryChanges
//    }
//
//
//    // MARK: - Helpers
//
//    private static func calculateRegion(from mask: BitMask, bitCount: Int) -> SpareRegion? {
//        if bitCount == 0 { return nil }
//        var minByte = mask.size
//        var maxByte = 0
//        var hasBits = false
//
//        for i in 0..<mask.size {
//            if mask[byteAt: i] != 0 {
//                if i < minByte { minByte = i }
//                if i > maxByte { maxByte = i }
//                hasBits = true
//            }
//        }
//
//        guard hasBits else { return nil }
//        let range = minByte..<(maxByte + 1)
//        let bytes = Array(mask.bytes[range])
//        return SpareRegion(range: range, bitCount: bitCount, bytes: bytes)
//    }
//
//    private static func extractChanges(from data: [UInt8], mask: BitMask) -> [Int: UInt8] {
//        return extractChanges(from: data, maskBytes: mask.bytes)
//    }
//
//    private static func extractChanges(from data: [UInt8], maskBytes: [UInt8]) -> [Int: UInt8] {
//        var changes: [Int: UInt8] = [:]
//        for i in 0..<data.count {
//            if maskBytes[i] != 0 {
//                changes[i] = data[i]
//            }
//        }
//        return changes
//    }
// }
import Foundation

public enum EnumLayoutCalculator {
    
    // MARK: - Result Structures
    
    public struct SpareRegion: CustomStringConvertible, Sendable {
        public let range: Range<Int>
        public let bitCount: Int
        public let bytes: [UInt8]
        public var description: String { return "Offset \(range) (Used: \(bitCount) bits)" }
    }

    /// Represents the calculated memory layout for a specific enum case.
    public struct EnumCaseProjection: CustomStringConvertible, Sendable {
        public let caseIndex: Int
        public let caseName: String
        
        // Debug info: How the index was split
        public let tagValue: Int
        public let payloadValue: Int // The part spilled into remaining spare bits
        
        // The actual byte changes required to represent this case
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
    
    /// Calculates layout for Multi-Payload Enums using Spare Bits.
    /// Handles the logic where empty case indices spill from Tag bits into remaining Payload bits.
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
        if spareBytesOffset < payloadSize {
            let copyLength = min(spareBytes.count, payloadSize - spareBytesOffset)
            for i in 0..<copyLength {
                commonSpareBits[byteAt: spareBytesOffset + i] = spareBytes[i]
            }
        }
        
        // 2. Calculate Tag Counts (GenEnum.cpp logic)
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
            while temp > 0 { temp >>= 1; numTagBits += 1 }
        }
        
        // 4. Separate Tag Bits and Payload Value Bits
        // Tag Bits: MSB Priority
        var payloadTagBitsMask = commonSpareBits
        payloadTagBitsMask.keepOnlyMostSignificantBits(numTagBits)
        
        if payloadTagBitsMask.countSetBits() < numTagBits {
            throw LayoutError.notEnoughSpareBits(needed: numTagBits, available: payloadTagBitsMask.countSetBits())
        }
        
        // Payload Value Bits: Remaining spare bits (CommonSpareBits - TagBits)
        // Actually, for Empty Cases, we use Occupied Bits (~CommonSpareBits)
        var payloadValueBitsMask = commonSpareBits
        payloadValueBitsMask.invert() // Occupied Bits
        let numPayloadValueBits = payloadValueBitsMask.countSetBits()
        
        // 5. Generate Projections (Inverse ProjectEnumValue)
        var cases: [EnumCaseProjection] = []
        
        // --- A. Payload Cases ---
        // Logic: Tag = CaseIndex, PayloadValue = 0
        for i in 0..<numPayloadCases {
            let tagVal = i
            let memBytes = payloadTagBitsMask.scatterBits(value: tagVal)
            
            cases.append(EnumCaseProjection(
                caseIndex: i,
                caseName: "Payload Case \(i)",
                tagValue: tagVal,
                payloadValue: 0,
                memoryChanges: extractChanges(from: memBytes, showMask: payloadTagBitsMask)
            ))
        }
        
        // --- B. Empty Cases ---
        // Logic:
        // emptyIndex = CaseIndex - numPayloadCases
        // PayloadValue = emptyIndex's low bits (fitting in numPayloadValueBits)
        // TagOffset = emptyIndex's high bits
        // FinalTag = numPayloadCases + TagOffset
        
        if numEmptyCases > 0 {
            for i in 0..<numEmptyCases {
                let globalIndex = numPayloadCases + i
                let emptyIndex = i
                
                // Split emptyIndex
                // 1. Calculate Payload Value (Low bits)
                let payloadValueMask = (numPayloadValueBits >= 64) ? -1 : (1 << numPayloadValueBits) - 1
                let payloadVal = emptyIndex & payloadValueMask
                
                // 2. Calculate Tag Offset (High bits)
                let tagOffset = emptyIndex >> numPayloadValueBits
                let finalTag = numPayloadCases + tagOffset
                
                // 3. Generate Memory
                let tagBytes = payloadTagBitsMask.scatterBits(value: finalTag)
                let payloadBytes = payloadValueBitsMask.scatterBits(value: payloadVal)
                
                // Combine Memory (OR operation)
                var combinedBytes = [UInt8](repeating: 0, count: payloadSize)
                for b in 0..<payloadSize {
                    combinedBytes[b] = tagBytes[b] | payloadBytes[b]
                }
                
                cases.append(EnumCaseProjection(
                    caseIndex: globalIndex,
                    caseName: "Empty Case \(i)",
                    tagValue: finalTag,
                    payloadValue: payloadVal,
                    memoryChanges: extractChangesForEmptyCase(
                        data: combinedBytes,
                        tagMask: payloadTagBitsMask,
                        payloadValueMask: payloadValueBitsMask,
                        payloadValue: payloadVal
                    )
                ))
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
    
    // MARK: - Strategy 2: Tagged Multi-Payload (Extra Tag)
    
    public static func calculateTaggedMultiPayload(
        payloadSize: Int,
        numPayloadCases: Int,
        numEmptyCases: Int
    ) -> LayoutResult {
        
        let numTags = numPayloadCases + numEmptyCases
        
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
            range: tagOffset..<(tagOffset + numTagBytes),
            bitCount: bitsNeeded,
            bytes: [UInt8](repeating: 0xFF, count: numTagBytes)
        )
        
        var cases: [EnumCaseProjection] = []
        
        for tagVal in 0..<numTags {
            var memoryChanges: [Int: UInt8] = [:]
            var tempTag = tagVal
            for i in 0..<numTagBytes {
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
        
        let numTags = numEmptyCases + 1 // 1 for Payload Case
        
        if size > payloadSize {
            // Case A: Extra Tag (Payload full, or no XIs)
            let extraTagBytes = size - payloadSize
            let bitsNeeded = extraTagBytes * 8
            
            let region = SpareRegion(
                range: payloadSize..<size,
                bitCount: bitsNeeded,
                bytes: [UInt8](repeating: 0xFF, count: extraTagBytes)
            )
            
            var cases: [EnumCaseProjection] = []
            
            // Payload Case: Tag = 0 (Extra Tag Area is 0)
            var payloadMem: [Int: UInt8] = [:]
            for i in 0..<extraTagBytes { payloadMem[payloadSize + i] = 0 }
            cases.append(EnumCaseProjection(
                caseIndex: 0,
                caseName: "Payload Case",
                tagValue: 0,
                payloadValue: 0,
                memoryChanges: payloadMem
            ))
            
            // Empty Cases: Tag = 1..N
            // Show first few empty cases
            let casesToShow = min(numEmptyCases, 5)
            for i in 1...casesToShow {
                var mem: [Int: UInt8] = [:]
                var tempTag = i
                for b in 0..<extraTagBytes {
                    mem[payloadSize + b] = UInt8(tempTag & 0xFF)
                    tempTag >>= 8
                }
                cases.append(EnumCaseProjection(
                    caseIndex: i,
                    caseName: "Empty Case \(i-1)",
                    tagValue: i,
                    payloadValue: 0,
                    memoryChanges: mem
                ))
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
            // Case B: Extra Inhabitants (XI)
            // Tag is effectively the XI index of the payload type.
            
            return LayoutResult(
                strategyDescription: "Single Payload (Extra Inhabitants)",
                bitsNeededForTag: 0,
                bitsAvailableForPayload: 0,
                numTags: numTags,
                tagRegion: nil,
                payloadRegion: nil,
                cases: [
                    EnumCaseProjection(caseIndex: 0, caseName: "Payload Case (Valid Value)", tagValue: -1, payloadValue: 0, memoryChanges: [:]),
                    EnumCaseProjection(caseIndex: 1, caseName: "Empty Case 0 (Uses XI #0)", tagValue: 0, payloadValue: 0, memoryChanges: [:])
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
        
        for i in 0..<mask.size {
            if mask[byteAt: i] != 0 {
                if i < minByte { minByte = i }
                if i > maxByte { maxByte = i }
                hasBits = true
            }
        }
        
        guard hasBits else { return nil }
        let range = minByte..<(maxByte + 1)
        let bytes = Array(mask.bytes[range])
        return SpareRegion(range: range, bitCount: bitCount, bytes: bytes)
    }
    
    /// Extract changes for Payload Cases: Only show Tag bits.
    private static func extractChanges(from data: [UInt8], showMask: BitMask) -> [Int: UInt8] {
        var changes: [Int: UInt8] = [:]
        for i in 0..<data.count {
            if showMask[byteAt: i] != 0 {
                changes[i] = data[i]
            }
        }
        return changes
    }
    
    /// Extract changes for Empty Cases: Show Tag bits AND Payload Value bits.
    /// If Payload Value is 0, show the LSB of the Payload Mask to indicate "0".
    private static func extractChangesForEmptyCase(
        data: [UInt8],
        tagMask: BitMask,
        payloadValueMask: BitMask,
        payloadValue: Int
    ) -> [Int: UInt8] {
        var changes: [Int: UInt8] = [:]
        
        // 1. Tag Part: Always show
        for i in 0..<data.count {
            if tagMask[byteAt: i] != 0 {
                changes[i] = data[i]
            }
        }
        
        // 2. Payload Value Part
        if payloadValue == 0 {
            // If Value is 0, find the LSB of the Payload Mask to display 0x00.
            for i in 0..<data.count {
                if payloadValueMask[byteAt: i] != 0 {
                    changes[i] = 0
                    break // Only show one byte to indicate 0
                }
            }
        } else {
            // If Value > 0, show all non-zero bytes in the payload area.
            for i in 0..<data.count {
                if changes[i] == nil { // Don't overwrite Tag bytes
                    if payloadValueMask[byteAt: i] != 0 && data[i] != 0 {
                        changes[i] = data[i]
                    }
                }
            }
        }
        
        return changes
    }
}
