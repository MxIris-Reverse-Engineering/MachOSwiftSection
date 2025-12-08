import Foundation
import Testing
@testable import Demangling
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport
@testable import SwiftInspection
import MachOKit

#if canImport(SwiftUI)

import SwiftUI
@testable @_spi(Support) import SwiftInterface

struct SpareBitRegion {
    let range: Range<Int>
    let numSpareBits: Int
    let maxTagValue: UInt64
    let hexBytes: [UInt8]
}

enum SpareBitAnalyzer {
    static func analyze(bytes: [UInt8], startOffset: Int) {
        print("=== Spare Bits Analysis (Little Endian Memory) ===")
        print("Input Offset: \(startOffset)")
        print("Input Bytes (Hex): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("-------------------------------------------------------------")
        print("Offset | Hex  | Binary (MSB->LSB) | Spare Bits (1=Spare)")
        print("-------|------|-------------------|--------------------------")

        var currentStartOffset: Int? = nil
        var currentBitsCount = 0
        var currentBytes: [UInt8] = []

        for (index, byte) in bytes.enumerated() {
            let absoluteOffset = startOffset + index
            let hex = String(format: "%02X", byte)
            let binary = toBinaryString(byte)

            var interpretation = ""
            if byte == 0 {
                interpretation = "None (Used)"
            } else if byte == 0xFF {
                interpretation = "All 8 bits"
            } else {
                // 简单的位描述
                var parts: [String] = []
                if (byte & 0xF0) == 0xF0 { parts.append("High 4") }
                if (byte & 0x0F) == 0x0F { parts.append("Low 4") }
                if parts.isEmpty {
                    var bits: [Int] = []
                    for i in 0 ..< 8 {
                        if (byte & (1 << i)) != 0 { bits.append(i) }
                    }
                    interpretation = "Bits: " + bits.map(String.init).joined(separator: ",")
                } else {
                    interpretation = parts.joined(separator: ", ")
                }
            }

            print(String(format: "  +%02d  | 0x%@ |     %@      | %@", absoluteOffset, hex, binary, interpretation))

            // 统计区域逻辑
            if byte != 0 {
                if currentStartOffset == nil {
                    currentStartOffset = absoluteOffset
                }
                currentBitsCount += byte.nonzeroBitCount
                currentBytes.append(byte)
            } else {
                if let start = currentStartOffset {
                    let end = absoluteOffset
                    printRegionSummary(range: start ..< end, bits: currentBitsCount, bytes: currentBytes)
                    currentStartOffset = nil
                    currentBitsCount = 0
                    currentBytes = []
                }
            }
        }

        if let start = currentStartOffset {
            let end = startOffset + bytes.count
            printRegionSummary(range: start ..< end, bits: currentBitsCount, bytes: currentBytes)
        }
        print("=============================================================")
    }

    private static func toBinaryString(_ byte: UInt8) -> String {
        let binary = String(byte, radix: 2)
        let padding = String(repeating: "0", count: 8 - binary.count)
        return padding + binary
    }

    private static func printRegionSummary(range: Range<Int>, bits: Int, bytes: [UInt8]) {
        let maxTag: String
        if bits >= 64 {
            maxTag = "UInt64.max"
        } else {
            let val = (UInt64(1) << bits) - 1
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            maxTag = numberFormatter.string(from: NSNumber(value: val)) ?? "\(val)"
        }

        print("------------------------------------------------------")
        print(">>> Found Spare Region: Offset \(range)")
        print(">>> Capacity: \(bits) bits (Max Tag: \(maxTag))")
        print("------------------------------------------------------")
    }
}

final class MultiPayloadEnumTests: MachOImageTests, @unchecked Sendable {
    override class var imageName: MachOImageName { .SwiftUICore }

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
            
            print(typeName)
            print("")
            defer {
                try? print(currentMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout)
                if let multiPayloadEnumDescriptor = multiPayloadEnumDescriptorByMangledName[typeName], multiPayloadEnumDescriptor.usesPayloadSpareBits {
                    try? printMultiPayloadEnum(multiPayloadEnumDescriptor)
                }
                print("---------------------")
            }

            var typeLayouts: [TypeLayout] = []
            var emptyCases: UInt32 = 0
            for record in records {
                let mangledTypeName = try record.mangledTypeName()

                var indirectCaseString = ""
                var isIndirectCase = false
                if record.flags.contains(.isIndirectCase) {
                    indirectCaseString = "indirect "
                    isIndirectCase = true
                }
                guard !mangledTypeName.isEmpty else {
                    try print("\(indirectCaseString)case", record.fieldName())
                    emptyCases += 1
                    continue
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
                                try print(indent  + "Type: " + MetadataReader.demangleContext(for: descriptor).print(using: demangleOptions))
                            }
                            let tupleElementTypeLayout = try tupleElementMetadata.asFullMetadata().valueWitnesses.resolve().typeLayout
                            print(indent + "- " + tupleElementTypeLayout.description)
                        }
                        print(indent + "Total: ")
                    }
                    print(indent + "- " + typeLayout.description)
                    if !isIndirectCase {
                        typeLayouts.append(typeLayout)
                    }
                } else {
                    try print("NotFound:", "case", record.fieldName(), mangledTypeNameString, node.print(using: .default))
                }
            }
            print("")
            guard !typeLayouts.isEmpty else {
                continue
            }
            let payloadSize = typeLayouts.map(\.size).max() ?? 0
            print("PayloadSize:", payloadSize)
            print("TagCounts:", getEnumTagCounts(payloadSize: payloadSize, emptyCases: emptyCases, payloadCases: typeLayouts.count.uint32))
            
        }
    }
}

extension String {
    static func * (lhs: Self, rhs: Int) -> Self {
        .init(repeating: lhs, count: rhs)
    }
}

#endif
