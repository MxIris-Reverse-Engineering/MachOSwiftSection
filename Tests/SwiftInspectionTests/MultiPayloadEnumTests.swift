import Foundation
import Testing
import MachOKit
@testable import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftInspection

#if canImport(SwiftUI)

import SwiftUI

final class MultiPayloadEnumTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUI }

    private var multiPayloadEnumDescriptorByMangledName: [String: MultiPayloadEnumDescriptor] = [:]

    private var demangleOptions: DemangleOptions = .default

    override init() async throws {
        try await super.init()

        let machO = machOImage
        let descriptors = try machO.swift.multiPayloadEnumDescriptors
        for descriptor in descriptors {
            let inProcessDescriptor = descriptor.asPointerWrapper(in: machO)
            try multiPayloadEnumDescriptorByMangledName[MetadataReader.demangleType(for: inProcessDescriptor.typeName()).print(using: demangleOptions)] = inProcessDescriptor
        }
    }

    private func printMultiPayloadEnum(_ descriptor: MultiPayloadEnumDescriptor) throws {
        guard descriptor.usesPayloadSpareBits else { return }
        let offset = try descriptor.payloadSpareBitMaskByteOffset()
        let count = try descriptor.payloadSpareBitMaskByteCount()
        let payloadSpareBits = try descriptor.payloadSpareBits()
        print("SpareBitMaskByteOffset:", offset)
        print("SpareBitMaskByteCount:", count)
        SpareBitAnalyzer.analyze(bytes: payloadSpareBits, startOffset: offset.cast())
    }

    @Test func main() async throws {
        let machO = machOImage
        let typeContextDescriptorWrappers = try machO.swift.typeContextDescriptors
        for typeContextDescriptorWrapper in typeContextDescriptorWrappers {
            let typeContextDescriptor = typeContextDescriptorWrapper.typeContextDescriptor.asPointerWrapper(in: machO)
            guard !typeContextDescriptor.layout.flags.isGeneric, typeContextDescriptorWrapper.isEnum else { continue }

            guard case .enum(let currentMetadata) = try typeContextDescriptor.metadataAccessor()?.perform(request: .init()).value.resolve() else { continue }

            let fieldDescriptor = try typeContextDescriptor.fieldDescriptor()
            let records = try fieldDescriptor.records()
            guard !records.isEmpty else { continue }

            let typeName = try MetadataReader.demangleContext(for: .type(.enum(typeContextDescriptor as! EnumDescriptor))).print(using: demangleOptions)
            guard let multiPayloadEnumDescriptor = multiPayloadEnumDescriptorByMangledName[typeName], multiPayloadEnumDescriptor.usesPayloadSpareBits else { continue }
            print(typeName)
            print("")
            var typeLayouts: [TypeLayout] = []
            var emptyCases: UInt32 = 0
            var payloadCases: UInt32 = 0
            var payloadSize: UInt64 = 0
            defer {
                do {
                    let enumTypeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    print(enumTypeLayout)
                    try printMultiPayloadEnum(multiPayloadEnumDescriptor)
                    try EnumLayoutCalculator.calculateMultiPayload( /* enumSize: enumTypeLayout.size.cast(), */ payloadSize: payloadSize.cast(), spareBytes: multiPayloadEnumDescriptor.payloadSpareBits(), spareBytesOffset: multiPayloadEnumDescriptor.payloadSpareBitMaskByteOffset().cast(), numPayloadCases: payloadCases.cast(), numEmptyCases: emptyCases.cast()).print()

                } catch {
                    print(error)
                }
                print("---------------------")
            }
            var hasIndirectCase = false
            for record in records {
                let mangledTypeName = try record.mangledTypeName()

                var indirectCaseString = ""
                if record.flags.contains(.isIndirectCase) {
                    indirectCaseString = "indirect "
                    hasIndirectCase = true
                }
                guard !mangledTypeName.isEmpty else {
                    try print("\(indirectCaseString)case", record.fieldName())
                    emptyCases += 1
                    continue
                }

                defer {
                    payloadCases += 1
                }

                let node = try MetadataReader.demangleType(for: mangledTypeName)
                var isTuplePayload = false
                if node.firstChild?.isKind(of: .tuple) ?? false {
                    isTuplePayload = true
                }

                func payloadString(_ payloadType: String) -> String {
                    if isTuplePayload {
                        return "\(payloadType)"
                    } else {
                        return "(\(payloadType))"
                    }
                }

                let mangledTypeNameString = try mangleAsString(node)
                if let metatype = try _getTypeByMangledNameInContext(mangledTypeName, genericContext: nil, genericArguments: nil) {
                    let currentMetadata = try Metadata.createInProcess(metatype)
                    try print("\(indirectCaseString)case \(record.fieldName())\(payloadString("\(node.print(using: .interfaceTypeBuilderOnly))"))")
                    let metadataWrapper = try currentMetadata.metadataWrapper()
                    let typeLayout = try currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                    let indentLevel = 1
                    let indent = "    " * indentLevel
                    if let tupleMetadata = metadataWrapper.tuple {
                        for (index, element) in try tupleMetadata.elements().enumerated() {
                            let tupleElementMetadata = try element.type.resolve()
                            if let descriptor = try tupleElementMetadata.typeContextDescriptorWrapper()?.asContextDescriptorWrapper {
                                print(indent + "Index: " + index.description)
                                try print(indent + "Type: " + MetadataReader.demangleContext(for: descriptor).print(using: demangleOptions))
                            }
                            let tupleElementTypeLayout = try tupleElementMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                            print(indent + "- " + tupleElementTypeLayout.description)
                        }
                        print(indent + "Total: ")
                    }
                    print(indent + "- " + typeLayout.description)
                    typeLayouts.append(typeLayout)

                } else {
                    try print("NotFound:", "case", record.fieldName(), mangledTypeNameString, node.print(using: .default))
                }
            }
            print("")
            guard !typeLayouts.isEmpty else {
                continue
            }
            payloadSize = hasIndirectCase ? 8 : typeLayouts.map(\.size).max() ?? 0
            print("PayloadSize:", payloadSize)
            print("TagCounts:", getEnumTagCounts(payloadSize: payloadSize, emptyCases: emptyCases, payloadCases: payloadCases))
        }
    }
}

extension String {
    static func * (lhs: Self, rhs: Int) -> Self {
        .init(repeating: lhs, count: rhs)
    }
}

// struct SpareBitRegion {
//    let range: Range<Int>
//    let numSpareBits: Int
//    let maxTagValue: UInt64
//    let hexBytes: [UInt8]
// }

// struct TagMemoryLocation {
//    let offset: Int
//    let value: UInt8
//    let mask: UInt8 // 标记哪些位被修改了
// }
//
// class EnumLayoutCalculator {
//    /// 计算枚举 Tag 在内存中的具体表示
//    /// - Parameters:
//    ///   - spareBytes: Spare Bits 原始字节数组 (Mask)
//    ///   - startOffset: Mask 相对于 Payload 的起始偏移量
//    ///   - numTags: 需要表示的 Tag 数量 (Payload Cases + Empty Cases)
//    static func calculate(spareBytes: [UInt8], startOffset: Int, numTags: Int) {
//        print("=== Enum Tag Memory Layout Calculator ===")
//        print("Input: Offset \(startOffset), NumTags \(numTags)")
//
//        // 1. 计算需要多少个 Bit 来存 Tag
//        // log2(4) = 2 bits
//        let bitsNeeded = Int(ceil(log2(Double(numTags))))
//        print("Bits Needed for Tag: \(bitsNeeded)")
//
//        // 2. 收集所有可用的 Spare Bit 坐标 (LSB -> MSB)
//        // 格式: (AbsoluteOffset, BitIndex 0-7)
//        var availableSlots: [(offset: Int, bit: Int)] = []
//
//        for (i, byte) in spareBytes.enumerated() {
//            let absOffset = startOffset + i
//            for b in 0 ..< 8 {
//                if (byte & (1 << b)) != 0 {
//                    availableSlots.append((offset: absOffset, bit: b))
//                }
//            }
//        }
//
//        print("Total Spare Bits Available: \(availableSlots.count)")
//
//        guard availableSlots.count >= bitsNeeded else {
//            print("Error: Not enough spare bits! Need \(bitsNeeded), have \(availableSlots.count)")
//            return
//        }
//
//        // 3. 关键步骤：Swift 使用 MSB (最高有效位)
//        // 所以我们取列表的最后 bitsNeeded 个元素
//        let targetSlots = Array(availableSlots.suffix(bitsNeeded))
//
//        print("Selected Tag Bits (MSB Strategy):")
//        for slot in targetSlots {
//            print("  - Offset \(slot.offset), Bit \(slot.bit)")
//        }
//        print("---------------------------------------------")
//
//        // 4. 计算每个 Tag 的内存表示
//        for tagValue in 0 ..< numTags {
//            printTagLayout(tagValue: tagValue, targetSlots: targetSlots)
//        }
//        print("=============================================\n")
//    }
//
//    private static func printTagLayout(tagValue: Int, targetSlots: [(offset: Int, bit: Int)]) {
//        // 这里的 tagValue 是逻辑上的 Tag (0, 1, 2, 3)
//        // 我们需要把它的每一位映射到 targetSlots 的物理位置上
//
//        // 存储结果：Offset -> ByteValue
//        var memoryChanges: [Int: UInt8] = [:]
//
//        for (i, slot) in targetSlots.enumerated() {
//            // i 是 Tag 值的第几位 (0 是低位)
//            // slot 是物理位置
//
//            // 检查 Tag Value 的第 i 位是否为 1
//            let bitValue = (tagValue >> i) & 1
//
//            if bitValue == 1 {
//                let currentByte = memoryChanges[slot.offset] ?? 0
//                memoryChanges[slot.offset] = currentByte | (1 << slot.bit)
//            } else {
//                // 如果是 0，我们需要确保该位置被显式标记（虽然默认是0，但为了展示完整性）
//                if memoryChanges[slot.offset] == nil {
//                    memoryChanges[slot.offset] = 0
//                }
//            }
//        }
//
//        // 格式化输出
//        let hexValue = String(format: "0x%02X", tagValue)
//        print("Tag \(tagValue) (\(hexValue)):")
//
//        let sortedOffsets = memoryChanges.keys.sorted()
//        for offset in sortedOffsets {
//            let byteVal = memoryChanges[offset]!
//            let byteHex = String(format: "0x%02X", byteVal)
//            let binary = String(byteVal, radix: 2).padding(toLength: 8, withPad: "0", startingAt: 0)
//            // 修正二进制显示为 MSB -> LSB
//            let displayBinary = String(repeating: "0", count: 8 - String(byteVal, radix: 2).count) + String(byteVal, radix: 2)
//
//            print("  -> Memory Offset \(offset) = \(byteHex) (Bin: \(displayBinary))")
//        }
//    }
// }

// enum EnumLayoutCalculator {
//    struct SpareRegion {
//        let range: Range<Int>
//        let bitCount: Int
//        let bytes: [UInt8]
//    }
//
//    /// 计算枚举 Tag 在内存中的具体表示
//    /// - Parameters:
//    ///   - spareBytes: Spare Bits 原始字节数组 (Mask)
//    ///   - startOffset: Mask 相对于 Payload 的起始偏移量
//    ///   - numTags: 需要表示的 Tag 数量 (Payload Cases + Empty Cases)
//    static func calculate(spareBytes: [UInt8], startOffset: Int, numTags: Int) {
//        print("=== Enum Tag Memory Layout Calculator ===")
//        print("Input: Offset \(startOffset), NumTags \(numTags)")
//
//        // 1. 计算需要多少个 Bit
//        let bitsNeeded = Int(ceil(log2(Double(numTags))))
//        print("Bits Needed for Tag: \(bitsNeeded)")
//
//        // 2. 识别所有连续的 Spare Regions
//        let regions = findSpareRegions(bytes: spareBytes, startOffset: startOffset)
//
//        // 3. 筛选并选择最佳 Region
//        // 策略：选择第一个容量足够 (>= bitsNeeded) 的 Region
//        guard let selectedRegion = regions.first(where: { $0.bitCount >= bitsNeeded }) else {
//            print("Error: No single region has enough bits! Need \(bitsNeeded)")
//            return
//        }
//
//        print("Selected Region: Offset \(selectedRegion.range) (Capacity: \(selectedRegion.bitCount) bits)")
//
//        // 4. 在选中的 Region 中确定 Tag 的物理位
//        // 策略：使用 Region 的最高有效位 (MSB)
//        // 我们需要把 Region 展开成位坐标列表，然后取最后 bitsNeeded 个
//        let targetSlots = getTargetSlots(region: selectedRegion, count: bitsNeeded)
//
//        print("Selected Tag Bits (MSB Strategy):")
//        for slot in targetSlots {
//            print("  - Offset \(slot.offset), Bit \(slot.bit)")
//        }
//        print("---------------------------------------------")
//
//        // 5. 计算每个 Tag 的内存表示
//        for tagValue in 0 ..< numTags {
//            printTagLayout(tagValue: tagValue, targetSlots: targetSlots)
//        }
//        print("=============================================\n")
//    }
//
//    // MARK: - Helper Methods
//
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
//        if let start = currentStart {
//            regions.append(SpareRegion(range: start ..< (startOffset + bytes.count), bitCount: currentBits, bytes: currentBytes))
//        }
//        return regions
//    }
//
//    private static func getTargetSlots(region: SpareRegion, count: Int) -> [(offset: Int, bit: Int)] {
//        var slots: [(offset: Int, bit: Int)] = []
//
//        // 遍历 Region 中的每个字节
//        for (i, byte) in region.bytes.enumerated() {
//            let absOffset = region.range.lowerBound + i
//            // 收集该字节中的所有 Spare Bits (从低到高)
//            for b in 0 ..< 8 {
//                if (byte & (1 << b)) != 0 {
//                    slots.append((offset: absOffset, bit: b))
//                }
//            }
//        }
//
//        // 取最后 count 个 (即 MSB)
//        return Array(slots.suffix(count))
//    }
//
//    private static func printTagLayout(tagValue: Int, targetSlots: [(offset: Int, bit: Int)]) {
//        var memoryChanges: [Int: UInt8] = [:]
//
//        for (i, slot) in targetSlots.enumerated() {
//            // i 是 Tag 值的第几位 (0 是低位)
//            let bitValue = (tagValue >> i) & 1
//
//            if bitValue == 1 {
//                let currentByte = memoryChanges[slot.offset] ?? 0
//                memoryChanges[slot.offset] = currentByte | (1 << slot.bit)
//            } else {
//                if memoryChanges[slot.offset] == nil {
//                    memoryChanges[slot.offset] = 0
//                }
//            }
//        }
//
//        let hexValue = String(format: "0x%02X", tagValue)
//        print("Tag \(tagValue) (\(hexValue)):")
//
//        let sortedOffsets = memoryChanges.keys.sorted()
//        for offset in sortedOffsets {
//            let byteVal = memoryChanges[offset]!
//            let byteHex = String(format: "0x%02X", byteVal)
//            // 显示二进制 (MSB -> LSB)
//            let binaryStr = String(byteVal, radix: 2)
//            let padding = String(repeating: "0", count: 8 - binaryStr.count)
//            let displayBinary = padding + binaryStr
//
//            print("  -> Memory Offset \(offset) = \(byteHex) (Bin: \(displayBinary))")
//        }
//    }
// }

#endif
